/* ==========================================================================
 *  lcd_interface.c  —  Driver do LCD 16x2 (HD44780) via I2C/PCF8574
 *
 *  Pilha: TWI por hardware (ATmega328P) -> PCF8574 -> HD44780 em modo 4 bits.
 *  Sem dependência do Arduino core. Compilar com avr-gcc.
 *
 *  Fiação padrão do módulo I2C (igual ao SimulIDE):
 *      P0=RS  P1=RW  P2=EN  P3=Backlight  P4..P7 = D4..D7
 * ==========================================================================*/
#include "defs.h"            /* F_CPU, LCD_I2C_ADDR, CARD_*, MSG_* */
#include "lcd_interface.h"
#include <util/delay.h>

/* --- variáveis compartilhadas vindas do Assembly (state.S, .global) ------- */
extern volatile uint8_t player_cards[3], banker_cards[3];
extern volatile uint8_t player_count, banker_count;

/* --- bits do PCF8574 ------------------------------------------------------ */
#define LCD_RS  0x01
#define LCD_RW  0x02
#define LCD_EN  0x04
#define LCD_BL  0x08         /* backlight */

static uint8_t lcd_backlight = LCD_BL;

/* ============================ camada I2C (bit-bang em PC4/PC5) =============
 * Substitui o TWI por hardware para compatibilidade com o SimulIDE,
 * que não simula corretamente o módulo TWI do ATmega (TWINT nunca seta).
 * GPIO puro é simulado com precisão em qualquer versão do SimulIDE.
 *   SDA = PC4 (A4)   SCL = PC5 (A5)  — mesmos pinos do TWI físico.
 * ========================================================================== */
#define SDA_BIT  PC4
#define SCL_BIT  PC5

#define SDA_H()  (PORTC |=  (1<<SDA_BIT))
#define SDA_L()  (PORTC &= ~(1<<SDA_BIT))
#define SCL_H()  (PORTC |=  (1<<SCL_BIT))
#define SCL_L()  (PORTC &= ~(1<<SCL_BIT))
#define I2C_DLY() _delay_us(5)            /* meio-período ~100 kHz */

static void i2c_init(void) {
    DDRC  |= (1<<SDA_BIT) | (1<<SCL_BIT); /* SDA e SCL como saída */
    SDA_H(); SCL_H();                      /* barramento inativo */
    _delay_ms(1);
}
static void i2c_start(void) {
    SDA_H(); SCL_H(); I2C_DLY();
    SDA_L();          I2C_DLY();  /* SDA cai com SCL alto = START */
    SCL_L();          I2C_DLY();
}
static void i2c_stop(void) {
    SDA_L(); SCL_H(); I2C_DLY();
    SDA_H();          I2C_DLY();  /* SDA sobe com SCL alto = STOP */
}
static void i2c_write(uint8_t data) {
    for (int8_t i = 7; i >= 0; i--) {
        if (data & (1 << i)) SDA_H(); else SDA_L();
        I2C_DLY();
        SCL_H(); I2C_DLY();
        SCL_L(); I2C_DLY();
    }
    SDA_H(); I2C_DLY();            /* libera SDA para o slave enviar ACK */
    SCL_H(); I2C_DLY();            /* pulsa clock do ACK (ignoramos o valor) */
    SCL_L(); I2C_DLY();
}

/* escreve um byte no PCF8574 (já com o backlight) */
static void pcf_write(uint8_t data) {
    i2c_start();
    i2c_write(LCD_I2C_ADDR << 1);      /* byte de endereço + escrita */
    i2c_write(data | lcd_backlight);
    i2c_stop();
}

/* ============================ camada HD44780 ============================= */
static void lcd_pulse(uint8_t data) {
    pcf_write(data | LCD_EN);
    _delay_us(1);
    pcf_write(data & ~LCD_EN);
    _delay_us(50);
}
/* envia um nibble (4 bits baixos) em P4..P7; rs=0 comando, rs=1 dado */
static void lcd_nibble(uint8_t nibble, uint8_t rs) {
    lcd_pulse((nibble << 4) | (rs ? LCD_RS : 0));
}
/* envia um byte completo (dois nibbles) */
static void lcd_send(uint8_t value, uint8_t rs) {
    lcd_nibble(value >> 4, rs);
    lcd_nibble(value & 0x0F, rs);
}
static void lcd_command(uint8_t c) { lcd_send(c, 0); }
static void lcd_data(uint8_t d)    { lcd_send(d, 1); }

static void lcd_print_char(char c)       { lcd_data((uint8_t)c); }
static void lcd_print_str(const char *s) { while (*s) lcd_print_char(*s++); }
void lcd_clear(void)                     { lcd_command(0x01); _delay_ms(2); }
static void lcd_set_cursor(uint8_t col, uint8_t row) {
    static const uint8_t row_off[2] = { 0x00, 0x40 };
    lcd_command(0x80 | (col + row_off[row & 1]));
}

/* ============================ rótulos das cartas ========================= */
/* índice = rank (1..13); o "11" do baccará vira "J" aqui na tela */
static const char *const card_labels[14] = {
    "", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"
};
static void lcd_print_card(uint8_t rank) {
    lcd_print_str(card_labels[rank]);
}

/* ============================ textos dos MSG_* =========================== */
static const char *const messages[] = {
    "Faca sua aposta",   /* MSG_PLACE_BET   */
    "Aposta: Jogador",   /* MSG_BET_PLAYER  */
    "Aposta: Banca",     /* MSG_BET_BANKER  */
    "Aposta: Empate",    /* MSG_BET_TIE     */
    "Distribuindo...",   /* MSG_DEALING     */
    "Jogador vence",     /* MSG_PLAYER_WINS */
    "Banca vence",       /* MSG_BANKER_WINS */
    "Empate",            /* MSG_TIE         */
    "Voce ganhou!",      /* MSG_YOU_WIN     */
    "Voce perdeu"        /* MSG_YOU_LOSE    */
};

/* ============================ API pública =============================== */
void lcd_init(void) {
    i2c_init();
    lcd_backlight = LCD_BL;
    _delay_ms(50);                          /* espera o LCD ligar */

    lcd_nibble(0x03, 0); _delay_ms(5);      /* sequência de init em 4 bits */
    lcd_nibble(0x03, 0); _delay_us(150);
    lcd_nibble(0x03, 0); _delay_us(150);
    lcd_nibble(0x02, 0);                    /* entra em modo 4 bits */

    lcd_command(0x28);                      /* 4 bits, 2 linhas, 5x8 */
    lcd_command(0x08);                      /* display off */
    lcd_clear();                            /* limpa */
    lcd_command(0x06);                      /* entrada: incrementa cursor */
    lcd_command(0x0C);                      /* display on, cursor off */
}

void lcd_message(uint8_t msg_id) {
    lcd_clear();
    lcd_set_cursor(0, 0);
    lcd_print_str(messages[msg_id]);
}

void lcd_scores(uint8_t player, uint8_t banker) {
    lcd_clear();
    lcd_set_cursor(0, 0);
    lcd_print_str("Jogador: ");
    lcd_print_char('0' + player);
    lcd_set_cursor(0, 1);
    lcd_print_str("Banca:   ");
    lcd_print_char('0' + banker);
}

void lcd_cards(uint8_t who) {
    volatile uint8_t *cards = who ? banker_cards : player_cards;
    uint8_t n               = who ? banker_count  : player_count;

    lcd_set_cursor(0, who & 1);             /* Jogador na linha 0, Banca na 1 */
    lcd_print_str(who ? "B:" : "J:");
    for (uint8_t i = 0; i < n; i++) {
        lcd_print_char(' ');
        lcd_print_card(cards[i]);           /* deixa o espaço pro "10" caber */
    }
}
