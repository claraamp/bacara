#include "defs.h"
; =========================================================================
;  game.S  -  Logica do jogo Bacara (ATmega328P)
;
;  CORRECOES aplicadas (vs versao original):
;   (1) sorteia_carta agora retorna RANK 1..13 (nao mais valor 0..9)
;   (2) valor_carta: nova funcao pura rank(1..13)->valor(0..9)
;   (3) calcula_pontuacao converte cada carta via valor_carta antes de somar
;   (4) regra_terceira_carta removida; trocada por duas funcoes puras:
;         decide_simples(score)        -> 0/1
;         decide_banca_p3(score, p3)   -> 0/1
;       o main.S orquestra a ordem do jogo.
;   (LFSR) a semeadura de rng_state NAO e feita aqui; ver interrupts.S.
;
;  ABI avr-gcc: argumentos/retorno em r24 (1o), r22 (2o), r20 (3o).
;  Funcoes folha so usam regs de scratch (r18-r27,r30,r31); as que chamam
;  outra (rcall) salvam o que precisam preservar.
; =========================================================================

; =========================================================================
;  sorteia_carta  -  gira o LFSR e devolve uma carta como RANK (1..13)
;  Saida: r24 = rank (1 = As, ... 10, 11=J, 12=Q, 13=K)
;  Obs:  a conversao rank->valor so acontece na pontuacao (valor_carta).
;        rng_state precisa estar semeado com valor != 0 (ver interrupts.S);
;        com semente 0 o LFSR fica travado em 0.
; =========================================================================
    .global sorteia_carta
sorteia_carta:
    ; --- PARTE 1: GIRA A ROLETA (LFSR de 8 bits, taps 0xB8) ---
    LDS  r24, rng_state
    LSR  r24                 ; desloca pra direita
    BRCC fim_lfsr            ; se saiu 0, pula o XOR
    LDI  r25, 0xB8
    EOR  r24, r25            ; mistura (XOR com os taps)
fim_lfsr:
    STS  rng_state, r24      ; salva nova posicao do LFSR

    ; --- PARTE 2: MAPEIA PRA CARTA (modulo 13 -> 0..12) ---
filtra_modulo:
    CPI  r24, 13
    BRLO converte_rank       ; 0..12 -> achou
    SUBI r24, 13
    RJMP filtra_modulo

converte_rank:
    INC  r24                 ; 0..12 -> rank 1..13
    RET                      ; <-- PARA AQUI. Retorna o RANK (nao o valor!)

; =========================================================================
;  valor_carta  -  converte RANK (1..13) no valor de bacara (0..9)
;  Entrada: r24 = rank (1..13)   |   tambem aceita 0 (sentinela "sem carta")
;  Saida:   r24 = valor (0..9)   ; 10,J,Q,K valem 0; As..9 valem o proprio
;  Funcao folha (so usa r24).
; =========================================================================
    .global valor_carta
valor_carta:
    CPI  r24, 10
    BRLO vc_fim              ; 0..9 ja sao o proprio valor
    LDI  r24, 0              ; 10,11(J),12(Q),13(K) -> 0
vc_fim:
    RET

; =========================================================================
;  calcula_pontuacao  -  soma ate 3 cartas (em RANK) com modulo 10
;  Entradas: r24 = carta1, r22 = carta2, r20 = carta3 (rank; 0 = sem carta)
;  Saida:    r24 = pontuacao final (0..9)
;  Converte cada carta via valor_carta ANTES de somar (senao um "10" somaria
;  10 em vez de 0). Acumula em r23 pra nao perder o valor entre chamadas.
; =========================================================================
    .global calcula_pontuacao
calcula_pontuacao:
    push r23
    push r22
    push r20

    rcall valor_carta        ; r24 = valor(carta1)
    mov  r23, r24            ; acumulador = valor1

    mov  r24, r22
    rcall valor_carta        ; r24 = valor(carta2)
    add  r23, r24

    mov  r24, r20
    rcall valor_carta        ; r24 = valor(carta3) (0 -> 0)
    add  r23, r24

    mov  r24, r23
filtra_dezena:
    CPI  r24, 10
    BRLO fim_pontuacao
    SUBI r24, 10
    RJMP filtra_dezena
fim_pontuacao:
    pop  r20
    pop  r22
    pop  r23
    RET

; =========================================================================
;  checa_natural  -  Jogador ou Banca fizeram 8 ou 9 na mao inicial?
;  Entradas: r24 = placar jogador, r22 = placar banca (ja em VALOR 0..9)
;  Saida:    r24 = 1 (natural, fim de jogo) | 0 (continua)
; =========================================================================
    .global checa_natural
checa_natural:
    CPI  r24, 8
    BREQ deu_natural
    CPI  r24, 9
    BREQ deu_natural
    CPI  r22, 8
    BREQ deu_natural
    CPI  r22, 9
    BREQ deu_natural
    LDI  r24, 0
    RET
deu_natural:
    LDI  r24, 1
    RET

; =========================================================================
;  decide_simples  -  regra de "saque simples" (0..5 compra, 6..7 fica)
;  Usada para: (a) o Jogador sempre; (b) a Banca QUANDO o jogador NAO comprou.
;  Entrada: r24 = score (0..9)
;  Saida:   r24 = 1 (compra a 3a carta) | 0 (fica)
; =========================================================================
    .global decide_simples
decide_simples:
    CPI  r24, 6
    BRLO ds_compra           ; 0..5 -> compra
    LDI  r24, 0              ; 6,7 (e mais) -> fica
    RET
ds_compra:
    LDI  r24, 1
    RET

; =========================================================================
;  decide_banca_p3  -  tabela de saque da Banca QUANDO o jogador comprou
;  Entradas: r24 = banker_score (0..9), r22 = p3 (valor 0..9 da 3a carta
;            do JOGADOR)
;  Saida:    r24 = 1 (banca compra) | 0 (banca fica)
;
;  Tabela oficial do Bacara:
;    score 0,1,2          -> sempre compra
;    score 3              -> compra, exceto se p3 == 8
;    score 4              -> compra se p3 in [2..7]
;    score 5              -> compra se p3 in [4..7]
;    score 6              -> compra se p3 in [6,7]
;    score 7 (e maior)    -> nunca compra
; =========================================================================
    .global decide_banca_p3
decide_banca_p3:
    CPI  r24, 3
    BRLO db_compra           ; 0,1,2 -> sempre compra
    BREQ db_3                ; ==3
    CPI  r24, 4
    BREQ db_4
    CPI  r24, 5
    BREQ db_5
    CPI  r24, 6
    BREQ db_6
    RJMP db_fica             ; 7 (e qualquer >6 que nao bateu) -> fica

db_3:
    CPI  r22, 8
    BREQ db_fica             ; p3 == 8 -> fica
    RJMP db_compra           ; p3 != 8 -> compra

db_4:
    CPI  r22, 2
    BRLO db_fica             ; p3 < 2 -> fica
    CPI  r22, 8
    BRSH db_fica             ; p3 >= 8 -> fica
    RJMP db_compra           ; p3 in [2..7] -> compra

db_5:
    CPI  r22, 4
    BRLO db_fica             ; p3 < 4 -> fica
    CPI  r22, 8
    BRSH db_fica             ; p3 >= 8 -> fica
    RJMP db_compra           ; p3 in [4..7] -> compra

db_6:
    CPI  r22, 6
    BREQ db_compra
    CPI  r22, 7
    BREQ db_compra
    RJMP db_fica             ; p3 != 6 e != 7 -> fica

db_compra:
    LDI  r24, 1
    RET
db_fica:
    LDI  r24, 0
    RET

; =========================================================================
;  define_vencedor  -  compara os placares finais
;  Entradas: r24 = placar final jogador, r22 = placar final banca (0..9)
;  Saida:    r24 = RES_PLAYER (1) | RES_BANKER (2) | RES_TIE (3)
; =========================================================================
    .global define_vencedor
define_vencedor:
    CP   r24, r22
    BREQ deu_empate
    BRLO banca_ganhou        ; jogador < banca (unsigned lower)
jogador_ganhou:
    LDI  r24, RES_PLAYER
    RET
banca_ganhou:
    LDI  r24, RES_BANKER
    RET
deu_empate:
    LDI  r24, RES_TIE
    RET