/* ==========================================================================
 * lcd_interface.c  —  Driver do LCD 16x2 (HD44780) via Pinos Analógicos
 *
 * Pilha: ATmega328P (PORTC) -> HD44780 em modo 4 bits.
 * Protegido contra interrupções via SREG/cli() e com uso de PROGMEM (Flash).
 *
 * Mapeamento de pinos (Arduino Nano A0-A5):
 * RS -> A0 (PC0)
 * EN -> A1 (PC1)
 * D4 -> A2 (PC2)
 * D5 -> A3 (PC3)
 * D6 -> A4 (PC4)
 * D7 -> A5 (PC5)
 * ==========================================================================*/
#include "defs.h"
#include "lcd_interface.h"
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include <avr/pgmspace.h>

/* --- variáveis compartilhadas vindas do Assembly (state.S, .global) ------- */
extern volatile uint8_t player_cards[3], banker_cards[3];
extern volatile uint8_t player_count, banker_count;

/* --- Mapeamento de Pinos (PORTC) ------------------------------------------ */
#define RS PC0
#define EN PC1
// D4 a D7 estão mapeados em PC2 a PC5 sequencialmente.

/* ============================ camada HD44780 (Driver Físico) ============== */

// lcd_send4: escreve um nibble (4 bits) e gera pulso EN
static void lcd_send4(uint8_t v) {
    // 1. Limpa APENAS as linhas de dados (PC2 a PC5), mantendo RS e EN intactos
    PORTC &= ~((1<<PC2)|(1<<PC3)|(1<<PC4)|(1<<PC5));

    // 2. Desloca os 4 bits de dados 2 posições para a esquerda para alinhar com PC2..PC5
    // Ex: Se v = 0x0F (0000 1111), v << 2 vira (0011 1100), encaixando perfeitamente.
    PORTC |= ((v & 0x0F) << 2);

    // 3. Pulso EN protegido e preciso
    PORTC |= (1 << EN);
    _delay_us(1);
    PORTC &= ~(1 << EN);

    // 4. Atraso para processamento do LCD
    _delay_us(40);
}

// lcd_cmd: envia comando e protege a janela de pulso desabilitando ISRs
static void lcd_cmd(uint8_t c) {
    uint8_t sreg = SREG;   // salva status das interrupções
    cli();                 // desabilita interrupções temporariamente
    
    PORTC &= ~(1<<RS);     // RS = 0 -> comando
    lcd_send4(c >> 4);     // nibble alto
    lcd_send4(c & 0x0F);   // nibble baixo
    
    SREG = sreg;           // restaura interrupções
    _delay_ms(2);          // delay de segurança para comandos longos
}

// lcd_data: envia dado e protege a janela de pulso desabilitando ISRs
static void lcd_data(uint8_t d) {
    uint8_t sreg = SREG;
    cli();
    
    PORTC |= (1<<RS);      // RS = 1 -> dado
    lcd_send4(d >> 4);
    lcd_send4(d & 0x0F);
    
    SREG = sreg;
    _delay_us(40);
}

static void lcd_soft_reset(void) {
    PORTC &= ~(1<<RS);
    lcd_send4(0x03);
    _delay_ms(5);
    lcd_send4(0x03);
    _delay_us(150);
    lcd_send4(0x03);
    lcd_send4(0x02);
    lcd_cmd(0x28);
    lcd_cmd(0x0C);
    lcd_cmd(0x06);
}

void lcd_clear(void) {
    lcd_soft_reset();
    lcd_cmd(0x01);
}

static void lcd_set_cursor(uint8_t col, uint8_t row) {
    lcd_cmd(0x80 + (row ? 0x40 : 0) + col);
}

/* Imprime string armazenada na Flash (PROGMEM) para salvar RAM */
static void lcd_print_str_P(const char *s) {
    uint8_t c;
    while ( (c = pgm_read_byte(s)) ) {
        lcd_data(c);
        s++;
    }
}

/* Imprime string armazenada na RAM */
static void lcd_print_str(const char *s) {
    while (*s) {
        lcd_data((uint8_t)*s++);
    }
}

/* ============================ Dados em PROGMEM (Flash) =================== */

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
    msg_5, msg_6, msg_7, msg_8, msg_9
};

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
    c_8, c_9, c_10, c_11, c_12, c_13
};

/* ============================ API Pública (Jogo de Bacará) =============== */

void lcd_init(void) {
    // Configura os pinos PC0 até PC5 como saída analógica (0x3F)
    DDRC |= (1<<PC0)|(1<<PC1)|(1<<PC2)|(1<<PC3)|(1<<PC4)|(1<<PC5);

    _delay_ms(50);
    PORTC &= ~(1<<RS); // Garante que começamos em modo comando

    // Sequência de inicialização 4-bit obrigatória
    lcd_send4(0x03);
    _delay_ms(5);
    lcd_send4(0x03);
    _delay_us(150);
    lcd_send4(0x03);
    lcd_send4(0x02); // Muda para 4 bits

    lcd_cmd(0x28); // 4-bit, 2 lines, 5x8
    lcd_cmd(0x0C); // Display ON, Cursor OFF
    lcd_cmd(0x06); // Auto-incremento do cursor
    lcd_clear();
}

void lcd_message(uint8_t msg_id) {
    lcd_clear();
    lcd_set_cursor(0, 0);
    
    // Lê o ponteiro da string que está na PROGMEM e imprime
    const char *ptr = (const char *)pgm_read_word(&messages[msg_id]);
    lcd_print_str_P(ptr);
}

void lcd_scores(uint8_t player, uint8_t banker) {
    lcd_clear();
    
    lcd_set_cursor(0, 0);
    lcd_print_str("Jogador: ");
    lcd_data('0' + player);
    
    lcd_set_cursor(0, 1);
    lcd_print_str("Banca:   ");
    lcd_data('0' + banker);
}

void lcd_cards(uint8_t who) {
    volatile uint8_t *cards = who ? banker_cards : player_cards;
    uint8_t n               = who ? banker_count  : player_count;

    lcd_set_cursor(0, who & 1); 
    lcd_print_str(who ? "B:" : "J:");
    
    for (uint8_t i = 0; i < n; i++) {
        lcd_data(' ');
        
        // Extrai a string da carta da PROGMEM
        const char *card_ptr = (const char *)pgm_read_word(&card_labels[cards[i]]);
        lcd_print_str_P(card_ptr);
    }
}