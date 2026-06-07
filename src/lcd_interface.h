#ifndef LCD_INTERFACE_H
#define LCD_INTERFACE_H

#include <stdint.h>

/* API pública chamada pelo Assembly (assinaturas travadas no defs.h).
 * Convenção avr-gcc: 1o arg em r24, 2o em r22. */

void lcd_init(void);                              /* inicializa I2C + LCD     */
void lcd_message(uint8_t msg_id);                 /* mostra um texto MSG_*    */
void lcd_scores(uint8_t player, uint8_t banker);  /* pontuações 0..9          */
void lcd_cards(uint8_t who);                       /* 0 = Jogador, 1 = Banca   */
void lcd_clear(void);                              /* limpa o display          */

#endif /* LCD_INTERFACE_H */
