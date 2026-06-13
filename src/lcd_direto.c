/* ==========================================================================
 * lcd_direto.c  —  Driver HD44780 16×2 ligado direto em PORTC (sem I2C)
 *
 * Mapeamento (pinos analógicos do Arduino Nano):
 *   RS  →  A0  (PC0)     RW  →  GND (fio no hardware)
 *   EN  →  A1  (PC1)
 *   D4  →  A2  (PC2)     D5  →  A3  (PC3)
 *   D6  →  A4  (PC4)     D7  →  A5  (PC5)
 *
 * OBRIGATÓRIO: pino RW do LCD deve ser aterrado no hardware (não flutua).
 * Flutuar RW=HIGH coloca o LCD em modo leitura → conflito de barramento.
 *
 * Compila com: avr-gcc -mmcu=atmega328p -DF_CPU=16000000UL -Os -I src
 * ==========================================================================*/
#include "defs.h"
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include <avr/pgmspace.h>

/* Variáveis compartilhadas com o Assembly (alocadas em main.S) */
extern volatile uint8_t player_cards[3], banker_cards[3];
extern volatile uint8_t player_count, banker_count;

/* Pinos no PORTC */
#define RS PC0 /* Register Select: 0 = comando, 1 = dado */
#define EN PC1 /* Enable (pulso ativo-alto)               */
/* D4-D7 mapeados em PC2-PC5 sequencialmente                 */

/* --------------------------------------------------------------------------
 *  lcd_send4  —  envia o nibble baixo de v para D4..D7 e pulsa EN.
 *  DEVE ser chamada dentro de cli() — sem reentrância.
 *
 *  Temporização (HD44780U datasheet, Fig. 25):
 *    tAS  (setup RS→EN↑)   ≥ 40 ns   — garantido pelas instruções anteriores
 *    PWEH (EN alto)        ≥ 450 ns  — _delay_us(1) = 1 µs >> 450 ns  ✓
 *    tH   (hold EN↓→dado)  ≥ 10 ns   — garantido pela instrução PORTC &=
 *    t43  (ciclo mínimo)   ≥ 37 µs   — _delay_us(40) cobre  ✓
 * --------------------------------------------------------------------------*/
static void lcd_send4(uint8_t v)
{
    /* Atualiza D4-D7 sem tocar RS(PC0) e EN(PC1) */
    PORTC = (PORTC & ~((1 << PC2) | (1 << PC3) | (1 << PC4) | (1 << PC5))) | ((v & 0x0F) << 2);

    PORTC |= (1 << EN); /* EN alto */
    _delay_us(1);
    PORTC &= ~(1 << EN); /* EN baixo — LCD trava o nibble nesta borda */
    _delay_us(40);       /* espera execução do comando no LCD (≥37 µs) */
}

/* --------------------------------------------------------------------------
 *  lcd_cmd / lcd_data  —  envia byte completo (2 nibbles) ao LCD.
 *  Desabilita interrupções durante o pulso de EN para não corromper timing.
 * --------------------------------------------------------------------------*/
static void lcd_cmd(uint8_t c)
{
    uint8_t sreg = SREG;
    cli();
    PORTC &= ~(1 << RS); /* RS=0: registrador de comando */
    lcd_send4(c >> 4);   /* nibble alto */
    lcd_send4(c & 0x0F); /* nibble baixo */
    SREG = sreg;         /* restaura I-flag (pode re-habilitar ISRs) */
    _delay_ms(2);        /* margem para comandos lentos               */
}

static void lcd_data(uint8_t d)
{
    uint8_t sreg = SREG;
    cli();
    PORTC |= (1 << RS); /* RS=1: registrador de dados */
    lcd_send4(d >> 4);
    lcd_send4(d & 0x0F);
    SREG = sreg;
    _delay_us(40); /* ≥37 µs para escrita de dado */
}

/* --------------------------------------------------------------------------
 *  Funções auxiliares
 * --------------------------------------------------------------------------*/
void lcd_clear(void)
{
    lcd_cmd(0x01); /* Clear Display (executa em até 1,52 ms) */
    _delay_ms(2);  /* delay extra → total ≈ 4 ms, bem acima do spec */
}

static void lcd_set_cursor(uint8_t col, uint8_t row)
{
    lcd_cmd(0x80 + (row ? 0x40 : 0x00) + col);
}

/* Imprime string da Flash (PROGMEM) — toda string de texto vai para Flash */
static void lcd_print_str_P(const char *s)
{
    uint8_t c;
    while ((c = pgm_read_byte(s++)))
        lcd_data(c);
}

/* ==========================================================================
 *  Dados em PROGMEM (Flash) — libera SRAM para o stack e variáveis
 * ==========================================================================*/

/* Mensagens (indexadas por MSG_*) */
static const char msg_0[] PROGMEM = "Faca sua aposta";
static const char msg_1[] PROGMEM = "Aposta: Jogador";
static const char msg_2[] PROGMEM = "Aposta: Banca";
static const char msg_3[] PROGMEM = "Aposta: Empate";
static const char msg_4[] PROGMEM = "Distribuindo...";
static const char msg_5[] PROGMEM = "Jogador vence";
static const char msg_6[] PROGMEM = "Banca vence";
static const char msg_7[] PROGMEM = "Empate";
static const char msg_8[] PROGMEM = "Voce ganhou!";
static const char msg_9[] PROGMEM = "Voce perdeu";

static const char *const messages[] PROGMEM = {
    msg_0, msg_1, msg_2, msg_3, msg_4,
    msg_5, msg_6, msg_7, msg_8, msg_9};

/* Rótulos de cartas (rank 0..13; 0 = sem carta) */
static const char c_0[] PROGMEM = "";
static const char c_1[] PROGMEM = "A";
static const char c_2[] PROGMEM = "2";
static const char c_3[] PROGMEM = "3";
static const char c_4[] PROGMEM = "4";
static const char c_5[] PROGMEM = "5";
static const char c_6[] PROGMEM = "6";
static const char c_7[] PROGMEM = "7";
static const char c_8[] PROGMEM = "8";
static const char c_9[] PROGMEM = "9";
static const char c_10[] PROGMEM = "10";
static const char c_11[] PROGMEM = "J";
static const char c_12[] PROGMEM = "Q";
static const char c_13[] PROGMEM = "K";

static const char *const card_labels[] PROGMEM = {
    c_0, c_1, c_2, c_3, c_4, c_5, c_6, c_7,
    c_8, c_9, c_10, c_11, c_12, c_13};

/* Prefixos para lcd_scores e lcd_cards (também em Flash) */
static const char str_jog[] PROGMEM = "Jogador: ";
static const char str_ban[] PROGMEM = "Banca:   ";
static const char str_j[] PROGMEM = "J:";
static const char str_b[] PROGMEM = "B:";

/* ==========================================================================
 *  API pública  (assinaturas travadas em defs.h)
 * ==========================================================================*/

/*
 * lcd_init  —  inicializa PORTC e o HD44780 em modo 4 bits.
 *
 * Sequência obrigatória per HD44780U datasheet p. 46:
 *   1. Power on + wait >40 ms
 *   2. Enviar 0x3 (nibble), wait >4,1 ms   ← reset de 8 bits #1
 *   3. Enviar 0x3 (nibble), wait >100 µs   ← reset de 8 bits #2
 *   4. Enviar 0x3 (nibble)                 ← reset de 8 bits #3
 *   5. Enviar 0x2 (nibble)                 ← troca para 4 bits
 *   6. Function Set (0x28)
 *   7. Display OFF (0x08)
 *   8. Clear Display (0x01)
 *   9. Entry Mode Set (0x06)
 *  10. Display ON (0x0C)
 *
 * Chamada APÓS sei() em main.S; por isso cada lcd_send4 é protegida com cli.
 * O Timer2 ISR toca só PORTD/PORTB — não corrompe PORTC.
 */
void lcd_init(void)
{
    uint8_t sreg;

    /* Configura PC0-PC5 como saídas e zera todos os pinos */
    DDRC |= (1 << PC0) | (1 << PC1) | (1 << PC2) | (1 << PC3) | (1 << PC4) | (1 << PC5);
    PORTC &= ~((1 << PC0) | (1 << PC1) | (1 << PC2) | (1 << PC3) | (1 << PC4) | (1 << PC5));

    _delay_ms(50); /* LCD precisa de >40 ms após VCC estável */

    /* Passo 2: 1º reset em 8 bits */
    sreg = SREG;
    cli();
    lcd_send4(0x03);
    SREG = sreg;
    _delay_ms(5); /* datasheet: >4,1 ms */

    /* Passo 3: 2º reset em 8 bits */
    sreg = SREG;
    cli();
    lcd_send4(0x03);
    SREG = sreg;
    _delay_us(200); /* datasheet: >100 µs; adicionamos margem */

    /* Passos 4-5: 3º reset + troca para 4 bits (sem delay entre eles:
     * o EN já pulsou no send4 anterior — o LCD aceitou o comando)     */
    sreg = SREG;
    cli();
    lcd_send4(0x03); /* 3º reset */
    lcd_send4(0x02); /* troca para 4 bits */
    SREG = sreg;

    /* Passos 6-10: inicialização em 4 bits (sequência obrigatória) */
    lcd_cmd(0x28); /* Function Set: 4 bits, 2 linhas, fonte 5×8 */
    lcd_cmd(0x08); /* Display OFF  ← obrigatório antes do Clear  */
    lcd_clear();   /* Clear Display (inclui delay ≥ 4 ms)         */
    lcd_cmd(0x06); /* Entry Mode Set: cursor avança, sem shift     */
    lcd_cmd(0x0C); /* Display ON, cursor off, blink off            */
}

void lcd_message(uint8_t msg_id)
{
    lcd_clear();
    lcd_set_cursor(0, 0);
    lcd_print_str_P((const char *)pgm_read_word(&messages[msg_id]));
}

void lcd_scores(uint8_t player, uint8_t banker)
{
    lcd_clear();
    lcd_set_cursor(0, 0);
    lcd_print_str_P(str_jog);
    lcd_data('0' + player);
    lcd_set_cursor(0, 1);
    lcd_print_str_P(str_ban);
    lcd_data('0' + banker);
}

void lcd_cards(uint8_t who)
{
    volatile uint8_t *cards = who ? banker_cards : player_cards;
    uint8_t n = who ? banker_count : player_count;

    lcd_set_cursor(0, who & 1);
    lcd_print_str_P(who ? str_b : str_j);

    for (uint8_t i = 0; i < n; i++)
    {
        lcd_data(' ');
        lcd_print_str_P(
            (const char *)pgm_read_word(&card_labels[cards[i]]));
    }
}
