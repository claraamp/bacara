/* ==========================================================================
 *  defs.h  —  Contrato compartilhado do projeto Bacará (ATmega328P @ 16 MHz)
 *
 *  Incluído por TODOS os módulos:
 *    - arquivos .S (Assembly):  #include "defs.h"   (use extensão .S maiúscula,
 *                               assim o pré-processador roda antes do montador)
 *    - arquivos .c (C):         #include "defs.h"
 *
 * ==========================================================================*/
#ifndef DEFS_H
#define DEFS_H

#ifndef F_CPU
#define F_CPU 16000000UL          /* Arduino Nano = 16 MHz */
#endif
#include <avr/io.h>               /* nomes de pinos/registradores (C e ASM) */

/* --------------------------------------------------------------------------
 *  1) ESTADOS DA MÁQUINA DE ESTADOS   (variável: game_state)
 *  Dono: main.S decide transições; game.S calcula; display.S/ISRs só leem.
 * --------------------------------------------------------------------------*/
#define ST_IDLE     0   /* aguardando o jogador escolher a aposta            */
#define ST_BET      1   /* aposta registrada -> vai distribuir as cartas     */
#define ST_DEAL     2   /* distribuindo as 2 cartas iniciais de cada lado    */
#define ST_THIRD    3   /* avaliando a regra da 3a carta                     */
#define ST_RESULT   4   /* resultado calculado, mostrando no display/LCD     */

/* --------------------------------------------------------------------------
 *  2) TIPOS DE APOSTA   (variável: bet_type)  — setado pelas ISRs dos botões
 * ------------------------------------------------------------------------*/
#define BET_NONE    0
#define BET_PLAYER  1   /* botão Jog  -> D2  / PD2 / INT0   */
#define BET_BANKER  2   /* botão Ban  -> D3  / PD3 / INT1   */
#define BET_TIE     3   /* botão Emp  -> D13 / PB5 / PCINT5 */

/* --------------------------------------------------------------------------
 *  3) RESULTADO   (variável: result)
 * ------------------------------------------------------------------------*/
#define RES_BANKER  0
#define RES_PLAYER  1
#define RES_TIE     2

/* --------------------------------------------------------------------------
 *  4) BITS DA FLAG GLOBAL   (variável: flags)  — comunicação ISR -> main loop
 * ------------------------------------------------------------------------*/
#define FLG_NEW_BET  0   /* uma ISR de botão registrou nova aposta           */
#define FLG_GAME_END 1   /* rodada terminou, main pode mostrar resultado     */

/* --------------------------------------------------------------------------
 *  5) CARTAS  —  guardadas como RANK CRU (1..13) em player_cards[]/banker_cards[]
 *     A=1, 2..10 = valor, J=11, Q=12, K=13.  (suíte não importa no baccará)
 *     O sorteio (RNG, em game.S) gera ranks 1..13.
 *
 *     Conversão rank -> valor de baccará (game.S):
 *         valor = (rank >= 10) ? 0 : rank; (10,J,Q,K valem 0; Ás vale 1)
 *     A pontuação da mão é o último dígito da soma dos valores (soma % 10).
 * ------------------------------------------------------------------------*/
#define CARD_ACE    1
#define CARD_JACK   11
#define CARD_QUEEN  12
#define CARD_KING   13

/* --------------------------------------------------------------------------
 *  6) MENSAGENS PARA O LCD   (argumento de lcd_message)
 *     O Assembly passa SÓ o ID. A tabela de strings vive no lcd_interface.c
 *     (Pessoa 4 escreve os textos; os IDs abaixo estão travados).
 * ------------------------------------------------------------------------*/
#define MSG_PLACE_BET    0   /* "Faca sua aposta"   */
#define MSG_BET_PLAYER   1   /* "Aposta: Jogador"   */
#define MSG_BET_BANKER   2   /* "Aposta: Banca"     */
#define MSG_BET_TIE      3   /* "Aposta: Empate"    */
#define MSG_DEALING      4   /* "Distribuindo..."   */
#define MSG_PLAYER_WINS  5   /* "Jogador vence"     */
#define MSG_BANKER_WINS  6   /* "Banca vence"       */
#define MSG_TIE          7   /* "Empate"            */
#define MSG_YOU_WIN      8   /* "Voce ganhou!"      */
#define MSG_YOU_LOSE     9   /* "Voce perdeu"       */

/* --------------------------------------------------------------------------
 *  7) PINOS E MÁSCARAS  (confere com o SimulIDE)
 *     Tudo ATIVO-ALTO: segmento acende com HIGH; display selecionado com HIGH.
 *     Botões ativo-baixo (pull-up interno), interrupção na borda de descida.
 * ------------------------------------------------------------------------*/
/* Segmentos: a-d em PD4..PD7 ; e-g em PB0..PB2 */
#define SEG_PORTD_MASK  0xF0          /* PD4..PD7 (segmentos a,b,c,d) */
#define SEG_PORTB_MASK  0x07          /* PB0..PB2 (segmentos e,f,g)   */
/* Seleção de display */
#define SEL_LEFT_BIT    PB4           /* D12 - Jogador (display esquerdo) */
#define SEL_RIGHT_BIT   PB3           /* D11 - Banca   (display direito)  */
#define SEL_MASK        ((1<<SEL_LEFT_BIT)|(1<<SEL_RIGHT_BIT))
/* Botões */
#define BTN_PLAYER_BIT  PD2           /* INT0  */
#define BTN_BANKER_BIT  PD3           /* INT1  */
#define BTN_TIE_BIT     PB5           /* PCINT5 (banco PCINT[7:0]) */

/* --------------------------------------------------------------------------
 *  8) TABELA DE FONTE  (display.S)
 *     Formato do byte do dígito:  b0=a, b1=b, b2=c, b3=d, b4=e, b5=f, b6=g, b7=livre
 *     Saída fixa derivada desse formato:
 *         PORTD = (PORTD & ~SEG_PORTD_MASK) | ((fonte << 4) & SEG_PORTD_MASK);
 *         PORTB = (PORTB & ~SEG_PORTB_MASK) | ((fonte >> 4) & SEG_PORTB_MASK);
 *     (não tocar em SEL_*_BIT nem em BTN_TIE_BIT ao escrever no PORTB!)
 *
 *     disp_left / disp_right guardam um ÍNDICE na tabela de fonte:
 * ------------------------------------------------------------------------*/
#define DISP_BLANK  10    /* índice = display apagado */
#define DISP_DASH   11    /* índice = traço "-"       */

/* --------------------------------------------------------------------------
 *  9) LCD I2C
 * ------------------------------------------------------------------------*/
#define LCD_I2C_ADDR  0x28   /* 7-bit; write byte = 0x28<<1 = 0x50 (Control_Code do SimulIDE) */

/* ==========================================================================
 *  MAPA DE RECURSOS  (quem usa o quê — evita dois módulos brigando)
 *
 *    Timer2 (Normal/OVF) .. multiplexação dos displays. ISR TIMER2_OVF_vect.
 *                           Config na init do display.S; lógica em display.S.
 *                           Alvo: refresh >= 100 Hz por display (sem flicker).
 *    INT0 (PD2) ........... botão Jogador. ISR INT0_vect.   (interrupts.S)
 *    INT1 (PD3) ........... botão Banca.   ISR INT1_vect.   (interrupts.S)
 *    PCINT5 (PB5) ......... botão Empate. Habilita PCIE0 (PCICR) + bit PCINT5
 *                           em PCMSK0. ISR é PCINT0_vect (vetor por BANCO,
 *                           não por pino!).                 (interrupts.S)
 *    sei() ................ só DEPOIS de toda a config, no main.S.
 * ==========================================================================*/

/* ==========================================================================
 *  MAPA DA MEMÓRIA (SRAM)  —  DOCUMENTAÇÃO do contrato.
 *  A alocação real fica em UM arquivo .S (ex.: state.S, na .bss):
 *
 *      .section .bss
 *      game_state:    .skip 1
 *      bet_type:      .skip 1
 *      player_score:  .skip 1     ; 0..9
 *      banker_score:  .skip 1     ; 0..9
 *      player_cards:  .skip 3     ; ranks 1..13
 *      banker_cards:  .skip 3     ; ranks 1..13
 *      player_count:  .skip 1     ; 2 ou 3
 *      banker_count:  .skip 1
 *      rng_state:     .skip 2     ; estado do LFSR (game.S)
 *      result:        .skip 1
 *      disp_left:     .skip 1     ; índice de fonte do display ESQUERDO (Jogador)
 *      disp_right:    .skip 1     ; índice de fonte do display DIREITO  (Banca)
 *      flags:         .skip 1
 *
 *  No C, declare o que precisar acessar (volatile, pois muda em ISR/ASM):
 *      extern volatile uint8_t player_cards[3], banker_cards[3];
 *      extern volatile uint8_t player_count, banker_count;
 * ==========================================================================*/

/* ==========================================================================
 *  API DO C  (lcd_direto.c)  —  assinaturas travadas aqui:
 *
 *      void lcd_init(void);
 *      void lcd_message(uint8_t msg_id);            // 1o arg -> r24
 *      void lcd_scores(uint8_t player, uint8_t banker); // r24, r22
 *      void lcd_cards(uint8_t who);   // who: 0=Jogador, 1=Banca
 *                                     // lê os arrays/contadores via extern
 * ==========================================================================*/

/* ==========================================================================
 *  CONVENÇÃO DE CHAMADA (ABI)  —  Assembly <-> C  (padrão avr-gcc, para TUDO)
 *
 *  Argumentos (8 bits):  1o -> r24,  2o -> r22,  3o -> r20,  4o -> r18, ...
 *  Argumentos 16 bits:   pares r25:r24, r23:r22, ...
 *  Retorno:              8 bits -> r24 ;  16 bits -> r25:r24 (r24 = byte baixo)
 *  Call-saved (callee preserva):    r2..r17, r28(YL), r29(YH)
 *  Call-clobbered (caller salva):   r0, r18..r27, r30, r31
 *  r1 DEVE valer 0 ao retornar (o C assume r1 == 0; faça "clr r1" se mexer).
 *
 *  ISR: curta, em Assembly puro, salva/restaura o que mexer (SREG incluso),
 *       comunica via SRAM (flags/variáveis). NUNCA chamar o LCD de dentro de
 *       uma ISR — o LCD (C/I2C) só é chamado a partir do laço principal.
 * ==========================================================================*/

#endif /* DEFS_H */