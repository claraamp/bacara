/* ==========================================================================
 *  display.S  -  Multiplexacao dos 2 displays + tabela de fonte + timer
 *  Projeto Bacara (ATmega328P)  -  Pessoa 3 (Mux + interrupcoes)
 *
 *  EXPOE (chamado pelo main):
 *     display_init   configura pinos de segmento/selecao e o Timer2
 *
 *  ISR (ligada automaticamente no vetor):
 *     __vector_9  (TIMER2_OVF)  varre os 2 displays alternadamente
 *
 *  LE da SRAM (contrato defs.h, alocadas no state.S da Pessoa 1):
 *     disp_left    digito do display ESQUERDO (Jogador, selecao em PB4)
 *     disp_right   digito do display DIREITO  (Banca,   selecao em PB3)
 *
 *  HARDWARE: catodo comum com chave NPN no lado baixo  ->  tudo ativo em
 *  nivel ALTO (segmento acende com HIGH; display ligado com PB3/PB4 em HIGH).
 *  Segmentos divididos em duas portas:
 *     a b c d  ->  PD4 PD5 PD6 PD7
 *     e f g    ->  PB0 PB1 PB2
 * ==========================================================================*/
#include <avr/io.h>
#include "defs.h"

/* -------- variavel privada do modulo (nao faz parte do contrato) -------- */
    .section .bss
scan_side:                  /* 0 = mostra Jogador (esq);  1 = mostra Banca */
    .skip 1

    .text

/* ==========================================================================
 *  display_init  -  chamada UMA vez pelo main, antes do sei
 * ==========================================================================*/
    .global display_init
display_init:
    ; segmentos a-d como saida (PD4..PD7)
    in   r24, _SFR_IO_ADDR(DDRD)
    ori  r24, 0xF0                  ; bits 4-7 = saida
    out  _SFR_IO_ADDR(DDRD), r24

    ; segmentos e-g + selecao como saida (PB0..PB4)
    in   r24, _SFR_IO_ADDR(DDRB)
    ori  r24, 0x1F                  ; bits 0-4 = saida
    out  _SFR_IO_ADDR(DDRB), r24

    ; desliga os dois displays (PB3 = PB4 = 0)
    in   r24, _SFR_IO_ADDR(PORTB)
    andi r24, 0xE7                  ; limpa bits 3 e 4
    out  _SFR_IO_ADDR(PORTB), r24

    ; comeca a varredura pelo Jogador
    clr  r24
    sts  scan_side, r24

    ; Timer2 em modo normal (overflow), prescaler 64
    ;   overflow ~= 16MHz / 64 / 256 = 976 Hz
    ;   cada display e atualizado ~488 vezes/s -> sem flicker
    clr  r24
    sts  TCCR2A, r24                ; modo normal
    ldi  r24, (1<<CS22)             ; prescaler 64
    sts  TCCR2B, r24
    ldi  r24, (1<<TOIE2)            ; habilita interrupcao de overflow
    sts  TIMSK2, r24
    ret

/* ==========================================================================
 *  ISR do Timer2 (overflow)  -  __vector_9
 *  A cada disparo mostra UM display (alterna). Sequencia sem ghosting:
 *     1 apaga os dois  ->  2 escreve os segmentos  ->  3 liga um display
 * ==========================================================================*/
    .global __vector_9
__vector_9:
    push r24
    in   r24, _SFR_IO_ADDR(SREG)
    push r24
    push r18
    push r25
    push r30
    push r31
    push r1
    clr  r1                         ; garante r1 = 0 (usado no adc)

    ; 1 apaga ambos os displays (limpa PB3 e PB4)
    in   r24, _SFR_IO_ADDR(PORTB)
    andi r24, 0xE7
    out  _SFR_IO_ADDR(PORTB), r24

    ; qual lado mostrar nesta varredura?
    lds  r25, scan_side
    tst  r25
    brne mux_banca

mux_jogador:
    lds  r25, disp_left             ; digito do jogador
    rcall mux_segmentos             ; 2 escreve segmentos (preserva o resto)
    in   r24, _SFR_IO_ADDR(PORTB)
    ori  r24, (1<<PB4)              ; 3 liga display esquerdo
    out  _SFR_IO_ADDR(PORTB), r24
    ldi  r25, 1                     ; proxima varredura: Banca
    sts  scan_side, r25
    rjmp mux_fim

mux_banca:
    lds  r25, disp_right            ; digito da banca
    rcall mux_segmentos
    in   r24, _SFR_IO_ADDR(PORTB)
    ori  r24, (1<<PB3)              ; liga display direito
    out  _SFR_IO_ADDR(PORTB), r24
    clr  r25                        ; proxima varredura: Jogador
    sts  scan_side, r25

mux_fim:
    pop  r1
    pop  r31
    pop  r30
    pop  r25
    pop  r18
    pop  r24
    out  _SFR_IO_ADDR(SREG), r24
    pop  r24
    reti

/* ==========================================================================
 *  mux_segmentos  -  escreve o digito (r25 = 0..11) nos pinos de segmento
 *  Preserva PD0-PD3 (botoes/UART) e PB3-PB7 (selecao, botao Emp, XTAL).
 *  Usa r18, r24, Z e r1 (=0). So e chamada pela ISR acima.
 * ==========================================================================*/
mux_segmentos:
    ; --- parte alta: segmentos a-d em PD4..PD7 ---
    ldi  ZL, lo8(font_pd)
    ldi  ZH, hi8(font_pd)
    add  ZL, r25
    adc  ZH, r1                     ; trata carry (r1 = 0)
    lpm  r24, Z                     ; padrao com bits 4-7
    in   r18, _SFR_IO_ADDR(PORTD)
    andi r18, 0x0F                  ; preserva PD0-PD3
    or   r18, r24
    out  _SFR_IO_ADDR(PORTD), r18

    ; --- parte baixa: segmentos e-g em PB0..PB2 ---
    ldi  ZL, lo8(font_pb)
    ldi  ZH, hi8(font_pb)
    add  ZL, r25
    adc  ZH, r1
    lpm  r24, Z                     ; padrao com bits 0-2
    in   r18, _SFR_IO_ADDR(PORTB)
    andi r18, 0xF8                  ; preserva PB3-PB7
    or   r18, r24
    out  _SFR_IO_ADDR(PORTB), r18
    ret

/* ==========================================================================
 *  TABELAS DE FONTE (catodo comum, ativo em HIGH)
 *
 *  Indices 0-9 = digitos.  10 = apagado.  11 = traco "-".
 *
 *  font_pd: bits 4-7 = a,b,c,d        font_pb: bits 0-2 = e,f,g
 *
 *  Dig  segmentos acesos       PD(abcd) PB(efg)
 *   0   a b c d e f            0xF0      0x03
 *   1   b c                    0x60      0x00
 *   2   a b d e g              0xB0      0x05
 *   3   a b c d g              0xF0      0x04
 *   4   b c f g                0x60      0x06
 *   5   a c d f g              0xD0      0x06
 *   6   a c d e f g            0xD0      0x07
 *   7   a b c                  0x70      0x00
 *   8   a b c d e f g          0xF0      0x07
 *   9   a b c d f g            0xF0      0x06
 *  10   (nada)                 0x00      0x00
 *  11   g (traco)              0x00      0x04
 * ==========================================================================*/
    .section .progmem.data,"a",@progbits
font_pd:
    .byte 0xF0,0x60,0xB0,0xF0,0x60,0xD0,0xD0,0x70,0xF0,0xF0,0x00,0x00
font_pb:
    .byte 0x03,0x00,0x05,0x04,0x06,0x06,0x07,0x00,0x07,0x06,0x00,0x04
