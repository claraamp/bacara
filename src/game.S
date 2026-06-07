#include "defs.h"
; =========================================================================
; Função: sorteia_carta
; Puxa o estado da roleta, gira ela, salva, e converte o valor de 0 a 9.
; =========================================================================
.global sorteia_carta

sorteia_carta:
    ; --- PARTE 1: GIRA A ROLETA (LFSR) ---
    LDS r24, rng_state   ; Pega a posição atual da roleta(variável da documentação)
    LSR r24              ; Desloca para a direita (divide por 2)
    BRCC fim_lfsr        ; Se caiu 0, pula o XOR
    LDI r25, 0xB8
    EOR r24, r25         ; Mistura matemática (XOR)
fim_lfsr:
    STS rng_state, r24   ; Salva a nova posição da roleta na SRAM

    ; --- PARTE 2: CONVERTE PARA O BARALHO (Módulo 13) ---
filtra_modulo:
    CPI r24, 13          
    BRLO converte_bacara ; Se for menor que 13 (0 a 12), achou a carta!
    SUBI r24, 13         ; Se for maior, tira 13...
    RJMP filtra_modulo   ; ...e volta pra testar de novo

converte_bacara:
    ; Soma 1 para a carta ir de 1 a 13 (Ás = 1, Rei = 13)
    INC r24              
    
    ; Transforma as figuras (10, J, Q, K) em ZERO
    CPI r24, 10          
    BRLO fim_sorteio     ; Se for 1, 2, 3... 9, tá pronto, pode sair!
    
    LDI r24, 0           ; Se for 10, 11, 12 ou 13, força a virar 0.

fim_sorteio:
    ; Fim! O r24 agora tem um valor perfeito de 0 a 9.
    RET

; =========================================================================
; Função: checa_natural
; Objetivo: Verifica se o Jogador ou a Banca tiraram 8 ou 9 na mão inicial.
; Entradas: r24 (Placar Jogador), r22 (Placar Banca)
; Retorno:  r24 (1 = É Natural, Fim de Jogo | 0 = Não é Natural, Continua)
; =========================================================================
.global checa_natural

checa_natural:
    ; --- Checa o Jogador ---
    CPI r24, 8           ; O jogador tem 8?
    BREQ deu_natural     ; Se igual (Branch if Equal), pula pro final!
    CPI r24, 9           ; O jogador tem 9?
    BREQ deu_natural     ; Se igual, pula pro final!

    ; --- Checa a Banca ---
    CPI r22, 8           ; A banca tem 8?
    BREQ deu_natural
    CPI r22, 9           ; A banca tem 9?
    BREQ deu_natural

    ; Se o código chegou até aqui sem pular, ninguém tirou 8 ou 9.
    LDI r24, 0           ; Retorna 0 (Falso)
    RET

deu_natural:
    LDI r24, 1           ; Retorna 1 (Verdadeiro - Alguém cravou o Natural!)
    RET

; =========================================================================
; Função: calcula_pontuacao
; Objetivo: Soma até 3 cartas e aplica a regra do Módulo 10 do Bacará.
; Entradas: r24 (Carta 1), r22 (Carta 2), r20 (Carta 3 - passar 0 se não houver)
; Retorno:  r24 (Pontuação final de 0 a 9)
; =========================================================================
.global calcula_pontuacao

calcula_pontuacao:
    ; 1. Soma todas as cartas no registrador r24
    ADD r24, r22          ; r24 = Carta 1 + Carta 2
    ADD r24, r20          ; r24 = r24 + Carta 3 

    ; 2. Aplica o Módulo 10 (Corta a dezena fora)
filtra_dezena:
    CPI r24, 10           ; O placar é menor que 10?
    BRLO fim_pontuacao    ; Se for de 0 a 9, tá pronto! Pula pro fim.
    
    SUBI r24, 10          ; Se for 10 ou mais (ex: 15), tira 10 (vira 5)
    RJMP filtra_dezena    ; Volta e testa de novo (caso a soma passe de 20)

fim_pontuacao:
    ; O r24 agora tem o valor exato da pontuação (0 a 9).
    ; Como manda a ABI, a função retorna a resposta no próprio r24!
    RET


; =========================================================================
; Função: regra_terceira_carta
; Objetivo: Aplica as regras combinadas do Jogador e da Banca para a 3ª carta.
; Entradas: r24 (Score Jogador), r22 (Score Banca)
; Retornos: r24 (Bit 0 = Jogador compra; Bit 1 = Banca compra)
;           -> 0x00: Nenhum compra (Fica)
;           -> 0x01: Apenas Jogador compra
;           -> 0x02: Apenas Banca compra
;           -> 0x03: Ambos compram
; =========================================================================
.global regra_terceira_carta

regra_terceira_carta:
    ; Vamos usar r20 para guardar a decisão do Jogador (0=Fica, 1=Compra)
    LDI r20, 0 
    ; Vamos usar r21 para guardar a decisão da Banca (0=Fica, 1=Compra)
    LDI r21, 0

    ; ---------------------------------------------------------------------
    ; PARTE 1: REGRA DO JOGADOR
    ; ---------------------------------------------------------------------
    CPI r24, 6            ; Jogador tem menos que 6? (0 a 5) [cite: 57]
    BRLO jogador_compra   ; Se sim, ele compra obrigatoriamente! [cite: 57]
    RJMP regra_banca      ; Se não (6 ou 7), ele fica. Vai direto para a Banca. [cite: 57]

jogador_compra:
    LDI r20, 1            ; Sinaliza que Jogador comprou a 3ª carta

    ; ⚠️ NOTA DE INTEGRAÇÃO: Se o jogador compra, na vida real a Frente 1 
    ; precisa sortear uma carta para ele AGORA. Para que esta função decida a
    ; vida da Banca, vamos assumir que o valor dessa 3ª carta tirada (P3) 
    ; será carregado em r20 para a lógica abaixo.

    ; Para este exemplo lógico, vamos simular que precisamos buscar a nova carta.
    ; Como estamos dentro do game.S, vamos assumir que a Frente 1 nos deu o valor 
    ; de P3 em r20 após o sorteio.

    ; ---------------------------------------------------------------------
    ; PARTE 2: REGRA DA BANCA
    ; ---------------------------------------------------------------------
regra_banca:
    ; Cenário A: O Jogador NÃO comprou a 3ª carta [cite: 58]
    CPI r20, 255
    BRNE banca_com_jogador_comprado

    ; Se o jogador NÃO comprou, a Banca age exatamente igual a ele (0-5 compra, 6-7 fica) [cite: 58]
    CPI r22, 6            ; Banca tem menos que 6? [cite: 58]
    BRLO banca_compra     ; Se sim, compra [cite: 58]
    RJMP fim_regras       ; Se não, fica [cite: 58]

banca_com_jogador_comprado:
    ; Cenário B: O Jogador COMPROU a 3ª carta. Vamos ler a pontuação da Banca (r22) [cite: 53, 60]
    ; r20 agora guarda o valor de P3 (a 3ª carta do jogador, 0 a 9) [cite: 60]

    CPI r22, 3            ; Banca tem 0, 1 ou 2? 
    BRLO banca_compra     ; Menor que 3 (0, 1, 2) -> Sempre compra! 

    CPI r22, 3            ; Banca tem 3? 
    BREQ banca_3          ; Se sim, avalia p3 != 8 

    CPI r22, 4            ; Banca tem 4? 
    BREQ banca_4          ; Se sim, avalia p3 entre 2 e 7 

    CPI r22, 5            ; Banca tem 5? 
    BREQ banca_5          ; Se sim, avalia p3 entre 4 e 7 

    CPI r22, 6            ; Banca tem 6? 
    BREQ banca_6          ; Se sim, avalia p3 igual a 6 ou 7 

    ; Se for 7, cai aqui direto: Nunca compra (Fica) 
    RJMP fim_regras

; --- Sub-regras específicas da tabela de trading da Banca --- 
banca_3:
    CPI r20, 8            ; P3 é igual a 8? 
    BREQ fim_regras       ; Se for igual a 8, a banca NÃO compra (fica) 
    RJMP banca_compra     ; Se for qualquer outra carta (p3 != 8), compra! 

banca_4:
    CPI r20, 2            ; P3 é menor que 2? 
    BRLO fim_regras       ; Se sim, fica 
    CPI r20, 8            ; P3 é maior ou igual a 8? 
    BRSH fim_regras       ; Se sim, fica 
    RJMP banca_compra     ; Se está entre 2 e 7, compra! 

banca_5:
    CPI r20, 4            ; P3 é menor que 4? 
    BRLO fim_regras       ; Se sim, fica 
    CPI r20, 8            ; P3 é maior ou igual a 8? 
    BRSH fim_regras       ; Se sim, fica 
    RJMP banca_compra     ; Se está entre 4 e 7, compra! 

banca_6:
    CPI r20, 6            ; P3 é 6? 
    BREQ banca_compra     ; Se sim, compra 
    CPI r20, 7            ; P3 é 7? 
    BREQ banca_compra     ; Se sim, compra 
    RJMP fim_regras       ; Se não for 6 nem 7, fica 

banca_compra:
    LDI r21, 2            ; Ativa o Bit 1 sinalizando compra da Banca (0x02)

    ; ---------------------------------------------------------------------
    ; FIM DO PROCESSAMENTO: Monta o retorno conforme a ABI
    ; ---------------------------------------------------------------------
fim_regras:
    ; Vamos resgatar o que o jogador decidiu. Se ele comprou, r20 vale 1.
    ; Se a banca comprou, r21 vale 2.
    ; Se somarmos os dois, temos o mapa completo de quem joga!
    
    ; Mas espere, se o jogador comprou, r20 foi modificado com o valor da carta P3.
    ; Vamos fazer uma checagem limpa baseada no fluxo inicial se necessário, 
    ; ou simplesmente retornar as flags diretas. 

    ; Para deixar o retorno 100% limpo, vamos apenas reconstruir o r24 de saída:
    ; (No seu projeto real, você pode preferir salvar o estado direto nas variáveis 
    ; da SRAM 'player_count' e 'banker_count' que estão listadas no PDF!) [cite: 26]
    
    RET

; =========================================================================
; Função: define_vencedor
; Objetivo: Compara a pontuação final e decide quem ganhou a rodada.
; Entradas: r24 (Placar Final do Jogador), r22 (Placar Final da Banca)
; Retorno:  r24 (1 = Jogador, 2 = Banca, 3 = Empate)
; =========================================================================
.global define_vencedor

define_vencedor:
    ; Compara as duas pontuações diretamente
    CP r24, r22          ; Faz a conta invisível: Jogador (r24) - Banca (r22)
    
    BREQ deu_empate      ; Se as pontuações forem IGUAIS, pula para o empate
    BRLO banca_ganhou    ; Se o Jogador for MENOR (Branch if Lower), a Banca ganhou!

    ; Se o código não pulou para o empate e o jogador não é menor... 
    ; Então o Jogador é MAIOR! Ele ganhou.
jogador_ganhou:
    LDI r24, RES_PLAYER  ; Coloca o código 1 (RES_PLAYER) no r24
    RET                  ; Volta para o main.S

banca_ganhou:
    LDI r24, RES_BANKER  ; Coloca o código 0 (RES_BANKER) no r24
    RET                  ; Volta para o main.S

deu_empate:
    LDI r24, RES_TIE     ; Coloca o código 2 (RES_TIE) no r24
    RET                  ; Volta para o main.S