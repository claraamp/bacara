#include <avr/io.h>
#include "defs.h"


 /*  VARIAVEIS GLOBAIS NA SRAM  */
    .section .bss

    .global game_state
game_state:     .skip 1      /* ST_IDLE .. ST_RESULT             */

    .global bet_type
bet_type:       .skip 1      /* BET_NONE .. BET_TIE              */

    .global player_score
player_score:   .skip 1      /* 0..9                             */

    .global banker_score
banker_score:   .skip 1      /* 0..9                             */

    .global player_cards
player_cards:   .skip 3      /* ranks 1..13 (3a carta = 0 se nao usada) */

    .global banker_cards
banker_cards:   .skip 3

    .global player_count
player_count:   .skip 1      /* 2 ou 3                           */

    .global banker_count
banker_count:   .skip 1

    .global rng_state
rng_state:      .skip 2      /* LFSR de 8 bits (2o byte reserva) */

    .global result
result:         .skip 1      /* RES_BANKER / RES_PLAYER / RES_TIE */

    .global disp_left
disp_left:      .skip 1      /* indice de fonte display ESQUERDO (Jogador) */

    .global disp_right
disp_right:     .skip 1      /* indice de fonte display DIREITO  (Banca)   */

    .global flags
flags:          .skip 1      /* bits: FLG_NEW_BET, FLG_GAME_END  */

/* RESET main  */
    .text
    .global main
main:
    /* pilha no topo da SRAM */
    ldi  r24, lo8(RAMEND)
    out  _SFR_IO_ADDR(SPL), r24
    ldi  r24, hi8(RAMEND)
    out  _SFR_IO_ADDR(SPH), r24

    /* estado inicial */
    ldi  r24, ST_IDLE
    sts  game_state, r24
    ldi  r24, BET_NONE
    sts  bet_type, r24
    clr  r24
    sts  flags, r24

    /* displays apagados */
    ldi  r24, DISP_DASH
    sts  disp_left,  r24
    sts  disp_right, r24

    /* inicializa modulos */
    rcall display_init
    rcall buttons_init
    sei                          /* habilita ISRs antes do lcd_init: display funciona mesmo se I2C travar */
    rcall lcd_init

    /* mensagem inicial */
    ldi  r24, MSG_PLACE_BET
    rcall lcd_message


 /*  LACO PRINCIPAL */
main_loop:
    lds  r24, game_state
    cpi  r24, ST_IDLE
    brne 1f
    rjmp state_idle
1:  cpi  r24, ST_BET
    brne 1f
    rjmp state_bet
1:  cpi  r24, ST_DEAL
    brne 1f
    rjmp state_deal
1:  cpi  r24, ST_THIRD
    brne 1f
    rjmp state_third
1:  cpi  r24, ST_RESULT
    brne 1f
    rjmp state_result
1:  rjmp main_loop

/*  ST_IDLE  -  aguarda botao de aposta  */
state_idle:
    lds  r24, flags
    sbrs r24, FLG_NEW_BET
    rjmp main_loop
    /* aposta registrada */
    ldi  r24, ST_BET
    sts  game_state, r24
    rjmp main_loop

/*  ST_BET  -  confirma a aposta e exibe mensagem  */
state_bet:
    /* consome o flag */
    lds  r24, flags
    andi r24, ~(1<<FLG_NEW_BET)
    sts  flags, r24

    /* semeia LFSR na 1a aposta (TCNT2 ja correu varios segundos) */
    lds  r24, rng_state
    tst  r24
    brne sb_seeded
    lds  r24, TCNT2
    tst  r24
    brne sb_seed_ok
    ldi  r24, 0xA5          /* fallback se TCNT2 ainda for 0 */
sb_seed_ok:
    sts  rng_state, r24
sb_seeded:

    /* escolhe a mensagem conforme aposta */
    lds  r24, bet_type
    cpi  r24, BET_PLAYER
    breq bet_is_player
    cpi  r24, BET_BANKER
    breq bet_is_banker
    /*  Esse trecho só roda quando a apposta é feita no empate  */
    ldi  r24, MSG_BET_TIE
    rjmp bet_display
bet_is_player:
    ldi  r24, MSG_BET_PLAYER
    rjmp bet_display
bet_is_banker:
    ldi  r24, MSG_BET_BANKER
bet_display:
    rcall lcd_message
    rcall pause_2s               /* usuario le a aposta antes de distribuir */

    ldi  r24, ST_DEAL
    sts  game_state, r24
    rjmp main_loop

/*  ST_DEAL  -  distribui 2 cartas para cada lado  */
state_deal:
    ldi  r24, MSG_DEALING
    rcall lcd_message
    rcall pause_2s               /* usuario ve "Distribuindo..." durante a distribuicao */

    /* --- cartas do jogador --- */
    rcall sorteia_carta
    sts  player_cards,   r24
    rcall sorteia_carta
    sts  player_cards+1, r24
    clr  r24
    sts  player_cards+2, r24         /* 3a carta: sem carta */
    ldi  r24, 2
    sts  player_count, r24

    /* --- cartas da banca --- */
    rcall sorteia_carta
    sts  banker_cards,   r24
    rcall sorteia_carta
    sts  banker_cards+1, r24
    clr  r24
    sts  banker_cards+2, r24
    ldi  r24, 2
    sts  banker_count, r24

    /* --- pontuacoes iniciais (3a carta = 0 = nao contribui) --- */
    lds  r24, player_cards
    lds  r22, player_cards+1
    ldi  r20, 0
    rcall calcula_pontuacao
    sts  player_score, r24

    lds  r24, banker_cards
    lds  r22, banker_cards+1
    ldi  r20, 0
    rcall calcula_pontuacao
    sts  banker_score, r24

    /* atualiza displays de 7 segmentos antes de mostrar cartas */
    lds  r24, player_score
    sts  disp_left,  r24
    lds  r24, banker_score
    sts  disp_right, r24

    /* limpa o LCD e mostra as cartas (sem rastro de "Distribuindo...") */
    rcall lcd_clear
    ldi  r24, 0
    rcall lcd_cards
    ldi  r24, 1
    rcall lcd_cards

    /* tempo para o usuario ler as cartas iniciais */
    rcall pause_2s               

    /* verifica natural (8 ou 9) */
    lds  r24, player_score
    lds  r22, banker_score
    rcall checa_natural
    tst  r24
    brne deal_natural

    ldi  r24, ST_THIRD
    sts  game_state, r24
    rjmp main_loop

deal_natural:
    rcall finalize_round
    rjmp main_loop

/*  ST_THIRD  -  avalia e distribui a 3a carta (regras oficiais do Bacara)  */
state_third:
    /*  regra do Jogador  */
    lds  r24, player_score
    rcall decide_simples         /* r24 = 1 se compra, 0 se fica */
    tst  r24
    breq third_no_player_draw

    /* Jogador compra */
    rcall sorteia_carta
    sts  player_cards+2, r24
    ldi  r24, 3
    sts  player_count, r24

    lds  r24, player_cards
    lds  r22, player_cards+1
    lds  r20, player_cards+2
    rcall calcula_pontuacao
    sts  player_score, r24
    sts  disp_left, r24

    ldi  r24, 0
    rcall lcd_cards

    /* Banca decide com base na 3a carta do Jogador */
    lds  r24, player_cards+2     /* rank da 3a carta do jogador */
    rcall valor_carta            /* converte rank -> valor (0..9) */
    mov  r22, r24                /* r22 = p3 (valor para decide_banca_p3) */
    lds  r24, banker_score
    rcall decide_banca_p3
    tst  r24
    brne third_banker_draw
    rjmp third_done

third_no_player_draw:
    /* Jogador nao comprou: Banca usa regra simples */
    lds  r24, banker_score
    rcall decide_simples
    tst  r24
    breq third_done

third_banker_draw:
    /* Banca compra */
    rcall sorteia_carta
    sts  banker_cards+2, r24
    ldi  r24, 3
    sts  banker_count, r24

    lds  r24, banker_cards
    lds  r22, banker_cards+1
    lds  r20, banker_cards+2
    rcall calcula_pontuacao
    sts  banker_score, r24
    sts  disp_right, r24

    ldi  r24, 1
    rcall lcd_cards

third_done:
    rcall pause_2s               /* usuario le o estado final antes do resultado */
    rcall finalize_round
    rjmp main_loop

/* --------------------------------------------------------------------------
 *  ST_RESULT  -  aguarda qualquer botao para nova rodada
 * --------------------------------------------------------------------------*/
state_result:
    lds  r24, flags
    sbrs r24, FLG_NEW_BET
    rjmp main_loop

    /* consome flag e reinicia */
    lds  r24, flags
    andi r24, ~(1<<FLG_NEW_BET)
    sts  flags, r24

    ldi  r24, BET_NONE
    sts  bet_type, r24
    ldi  r24, ST_IDLE
    sts  game_state, r24

    ldi  r24, DISP_DASH
    sts  disp_left,  r24
    sts  disp_right, r24

    ldi  r24, MSG_PLACE_BET
    rcall lcd_message

    rjmp main_loop

/*  finalize_round  -  calcula vencedor e exibe resultado
 *
 *  Sequencia:
 *    1) define_vencedor -> salva em result
 *    2) lcd_scores: mostra pontuacoes em ambas as linhas
 *    3) breve pausa (busy-wait ~0.5s a 16 MHz)
 *    4) lcd_message: quem ganhou a rodada
 *    5) lcd_message: apostador ganhou ou perdeu
 *    6) game_state = ST_RESULT  */

finalize_round:
    push r18
    push r19

    /* define vencedor */
    lds  r24, player_score
    lds  r22, banker_score
    rcall define_vencedor
    sts  result, r24

    /* exibe pontuacoes finais */
    lds  r24, player_score
    lds  r22, banker_score
    rcall lcd_scores

    rcall pause_2s               /* usuario le as pontuacoes finais */

    /* mensagem: quem ganhou a rodada */
    lds  r24, result
    cpi  r24, RES_PLAYER
    breq fr_player_wins
    cpi  r24, RES_BANKER
    breq fr_banker_wins
    ldi  r24, MSG_TIE
    rjmp fr_show_round
fr_player_wins:
    ldi  r24, MSG_PLAYER_WINS
    rjmp fr_show_round
fr_banker_wins:
    ldi  r24, MSG_BANKER_WINS
fr_show_round:
    rcall lcd_message
    rcall pause_2s               /* usuario le quem ganhou a rodada */

    /* mensagem: apostador ganhou ou perdeu
     * r18 = bet_type, r19 = result (preservados pela pausa e chamadas) */
    lds  r18, bet_type
    lds  r19, result

    cpi  r18, BET_PLAYER
    brne fr_chk_ban
    cpi  r19, RES_PLAYER
    breq fr_you_win
    rjmp fr_you_lose
fr_chk_ban:
    cpi  r18, BET_BANKER
    brne fr_chk_tie
    cpi  r19, RES_BANKER
    breq fr_you_win
    rjmp fr_you_lose
fr_chk_tie:
    cpi  r19, RES_TIE
    breq fr_you_win
    rjmp fr_you_lose

fr_you_win:
    ldi  r24, 8                  /* "8 8" nos displays = vitoria */
    sts  disp_left,  r24
    sts  disp_right, r24
    ldi  r24, MSG_YOU_WIN
    rjmp fr_show_outcome
fr_you_lose:
    ldi  r24, 0                  /* "0 0" nos displays = derrota */
    sts  disp_left,  r24
    sts  disp_right, r24
    ldi  r24, MSG_YOU_LOSE
fr_show_outcome:
    rcall lcd_message            /* "Voce ganhou!" ou "Voce perdeu" */

    ldi  r24, ST_RESULT
    sts  game_state, r24

    pop  r19
    pop  r18
    ret

/*  pausa de 2 segundos  */
    .global pause_2s
pause_2s:
    ldi  r20, 0xA4               /* outer: ~164 iteracoes */
ps_outer:
    ldi  r19, 0xFF
ps_mid:
    ldi  r18, 0xFF
ps_inner:
    dec  r18
    brne ps_inner
    dec  r19
    brne ps_mid
    dec  r20
    brne ps_outer
    ret
