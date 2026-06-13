/* ==========================================================================
 *  interrupts.S  -  ISRs dos botoes + configuracao das interrupcoes
 *  Projeto Bacara (ATmega328P)  -  Pessoa 3 (Mux + interrupcoes)
 *
 *  EXPOE (chamado pelo main):
 *     buttons_init   configura PD2/PD3/PB5 como entrada com pull-up e
 *                    habilita INT0, INT1 e PCINT5
 *
 *  ISRs (ligadas automaticamente nos vetores):
 *     __vector_1  (INT0)    botao Jogador (PD2)  ->  bet_type = BET_PLAYER
 *     __vector_2  (INT1)    botao Banca   (PD3)  ->  bet_type = BET_BANKER
 *     __vector_3  (PCINT0)  botao Empate  (PB5)  ->  bet_type = BET_TIE
 *
 *  Regra de arquitetura (do planejamento): a ISR e curta, salva/restaura o
 *  que mexe e SO grava bet_type + levanta FLG_NEW_BET. Quem age e o main.
 *  Nunca chamar o LCD daqui.
 *
 *  Botoes sem resistor externo: usam pull-up interno -> pressionado = LOW.
 *  INT0/INT1 disparam na borda de descida. PCINT dispara em qualquer borda,
 *  entao a ISR do Empate confere se o pino esta LOW antes de agir.
 * ==========================================================================*/
#include <avr/io.h>
#include "defs.h"

    .text

/* ==========================================================================
 *  buttons_init  -  chamada UMA vez pelo main, antes do sei
 * ==========================================================================*/
    .global buttons_init
buttons_init:
    ; PD2, PD3 como entrada
    in   r24, _SFR_IO_ADDR(DDRD)
    andi r24, 0xF3                  ; limpa bits 2 e 3
    out  _SFR_IO_ADDR(DDRD), r24
    ; pull-up interno em PD2, PD3
    in   r24, _SFR_IO_ADDR(PORTD)
    ori  r24, (1<<PD2)|(1<<PD3)
    out  _SFR_IO_ADDR(PORTD), r24

    ; PB5 como entrada
    in   r24, _SFR_IO_ADDR(DDRB)
    andi r24, 0xDF                  ; limpa bit 5
    out  _SFR_IO_ADDR(DDRB), r24
    ; pull-up interno em PB5
    in   r24, _SFR_IO_ADDR(PORTB)
    ori  r24, (1<<PB5)
    out  _SFR_IO_ADDR(PORTB), r24

    ; INT0 e INT1 na borda de descida
    ;   ISC01=1,ISC00=0 -> INT0 falling ; ISC11=1,ISC10=0 -> INT1 falling
    ldi  r24, (1<<ISC01)|(1<<ISC11)
    sts  EICRA, r24
    ; habilita INT0 e INT1
    in   r24, _SFR_IO_ADDR(EIMSK)
    ori  r24, (1<<INT0)|(1<<INT1)
    out  _SFR_IO_ADDR(EIMSK), r24

    ; pin change para PB5 (PCINT5, pertence ao grupo PCINT0)
    ldi  r24, (1<<PCINT5)
    sts  PCMSK0, r24
    lds  r24, PCICR
    ori  r24, (1<<PCIE0)            ; habilita grupo de pin change 0
    sts  PCICR, r24
    ret

/* ==========================================================================
 *  __vector_1  -  INT0  (botao Jogador, PD2)
 * ==========================================================================*/
    .global __vector_1
__vector_1:
    push r24
    in   r24, _SFR_IO_ADDR(SREG)
    push r24
    sbic _SFR_IO_ADDR(PIND), PD2    ; se PD2=0 (pressionado), pula o rjmp
    rjmp int0_fim                    ; PD2=1 (bounce: ja soltou): ignora
    ldi  r24, BET_PLAYER
    sts  bet_type, r24
    lds  r24, flags
    ori  r24, (1<<FLG_NEW_BET)
    sts  flags, r24
int0_fim:
    pop  r24
    out  _SFR_IO_ADDR(SREG), r24
    pop  r24
    reti

/* ==========================================================================
 *  __vector_2  -  INT1  (botao Banca, PD3)
 * ==========================================================================*/
    .global __vector_2
__vector_2:
    push r24
    in   r24, _SFR_IO_ADDR(SREG)
    push r24
    sbic _SFR_IO_ADDR(PIND), PD3    ; se PD3=0 (pressionado), pula o rjmp
    rjmp int1_fim                    ; PD3=1 (bounce: ja soltou): ignora
    ldi  r24, BET_BANKER
    sts  bet_type, r24
    lds  r24, flags
    ori  r24, (1<<FLG_NEW_BET)
    sts  flags, r24
int1_fim:
    pop  r24
    out  _SFR_IO_ADDR(SREG), r24
    pop  r24
    reti

/* ==========================================================================
 *  __vector_3  -  PCINT0  (botao Empate, PB5 = PCINT5)
 *  PCINT dispara em qualquer borda; so age se PB5 estiver LOW (pressionado).
 * ==========================================================================*/
    .global __vector_3
__vector_3:
    push r24
    in   r24, _SFR_IO_ADDR(SREG)
    push r24
    sbic _SFR_IO_ADDR(PINB), PB5    ; se PB5 = 0 (pressionado), pula o rjmp
    rjmp pcint0_fim                  ; PB5 = 1 (solto): ignora
    ldi  r24, BET_TIE
    sts  bet_type, r24
    lds  r24, flags
    ori  r24, (1<<FLG_NEW_BET)
    sts  flags, r24
pcint0_fim:
    pop  r24
    out  _SFR_IO_ADDR(SREG), r24
    pop  r24
    reti
