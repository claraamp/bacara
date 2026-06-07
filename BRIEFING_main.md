# Briefing para gerar `main.S` — Projeto Bacará (ATmega328P)

> Documento de contexto extraído do `bacara.sim1` (netlist real) + decisões de
> arquitetura já fechadas. Cole isto no Claude Code junto com os arquivos do
> projeto (`defs.h`, `state.S`, `display.S`, `interrupts.S`, `game.S`,
> `lcd_interface.c`) para que ele gere a `main.S` sem adivinhar pinagem nem contrato.

## 1. Plataforma
- MCU: ATmega328P (placa Arduino Nano), clock **16 MHz**.
- Toolchain: **avr-gcc** (.S maiúsculo, passa pelo pré-processador → `#include "defs.h"`).
- Simulador alvo: SimulIDE (`bacara.sim1`).

## 2. Pinagem CONFIRMADA pelo netlist do .sim1
(rótulo Arduino Nano → porta AVR → função)

### Botões (entrada, pull-up interno, pressionado = LOW)
| Botão | Nano | AVR  | Interrupção |
|-------|------|------|-------------|
| Joq   | D2   | PD2  | INT0  (__vector_1) |
| Ban   | D3   | PD3  | INT1  (__vector_2) |
| Emp   | D13  | PB5  | PCINT5 (__vector_3, grupo PCINT0) |

### Segmentos (saída, ativo em HIGH; cátodo comum + chave NPN no lado baixo)
| Seg | Nano | AVR  |   | Seg | Nano | AVR  |
|-----|------|------|---|-----|------|------|
| a   | D4   | PD4  |   | e   | D8   | PB0  |
| b   | D5   | PD5  |   | f   | D9   | PB1  |
| c   | D6   | PD6  |   | g   | D10  | PB2  |
| d   | D7   | PD7  |   |     |      |      |

### Seleção de display (saída, ativo em HIGH via base do BJT)
| Display          | Nano | AVR  | BJT     | Posição na tela |
|------------------|------|------|---------|-----------------|
| ESQUERDO (Jogador) | D12 | PB4  | BJT-58  | X=60  (esquerda) |
| DIREITO  (Banca)   | D11 | PB3  | BJT-18  | X=156 (direita)  |

> Conferido: Seven Segment-16 (X=60, esquerdo) é acionado pelo BJT cuja base
> está em PB4; Seven Segment-17 (X=156, direito) pelo BJT em PB3.
> Isso bate com `display.S` (PB4=esq/Jogador/disp_left, PB3=dir/Banca/disp_right).
> NÃO há inversão.

### LCD
- I2C: SDA = A4 = PC4, SCL = A5 = PC5 → PCF8574 (I2CToParallel) → HD44780 16x2.
- Tratado pela Pessoa 4 em `lcd_interface.c` (C). A main chama as funções de C dela.

## 3. Contrato (defs.h) — variáveis SRAM e o que cada módulo faz
> A main deve usar os nomes EXATOS do `defs.h` real do projeto. Abaixo, o papel
> de cada símbolo conforme o código existente. (Confirmar nomes/valores no defs.h.)

Variáveis em SRAM (alocadas no `state.S` da Pessoa 1):
- `bet_type`  — aposta escolhida (BET_PLAYER / BET_BANKER / BET_TIE). Gravada pelas ISRs.
- `flags`     — bitfield; bit `FLG_NEW_BET` levantado pelas ISRs quando há aposta nova.
- `rng_state` — estado do LFSR (8 bits). **Nasce em 0; PRECISA ser semeado != 0.**
- `disp_left`  — dígito/índice de fonte do display esquerdo (Jogador). Lido pela ISR do Timer2.
- `disp_right` — idem display direito (Banca).

Constantes: `BET_PLAYER/BANKER/TIE`, `RES_PLAYER/BANKER/TIE`, `FLG_NEW_BET`.
Índices de fonte do display: 0–9 = dígitos, 10 = apagado, 11 = traço "-".
(Se houver índice para letras como "K", confirmar no defs.h / tabela de fonte.)

## 4. Funções já prontas que a main ORQUESTRA

### display.S (Pessoa 3)
- `display_init` — chamar 1x antes do `sei`. Configura pinos + Timer2 (ISR varre sozinha).
- A varredura é automática (ISR Timer2). A main só escreve em `disp_left`/`disp_right`.

### interrupts.S (Pessoa 3)
- `buttons_init` — chamar 1x antes do `sei`. Configura PD2/PD3/PB5 + INT0/INT1/PCINT0.
- ISRs gravam `bet_type` e levantam `FLG_NEW_BET`. A main consome e limpa a flag.

### game.S (Pessoa 2, já CORRIGIDO) — todas usam ABI avr-gcc (r24=1º arg, r22=2º, r20=3º; retorno em r24)
- `sorteia_carta()` → r24 = **RANK 1..13** (1=Ás … 11=J,12=Q,13=K). Gira o LFSR.
- `valor_carta(rank)` → r24 = valor baccará 0..9 (10,J,Q,K → 0; aceita 0 como "sem carta").
- `calcula_pontuacao(c1,c2,c3)` → r24 = pontuação 0..9 (converte cada RANK p/ valor e soma mod 10; passar c3=0 se só 2 cartas).
- `checa_natural(score_jog, score_ban)` → r24 = 1 se 8/9 em qualquer mão, senão 0. (recebe VALOR 0..9)
- `decide_simples(score)` → r24 = 1 compra (0..5) / 0 fica (6..7). Usar p/ Jogador, e p/ Banca quando o jogador NÃO comprou.
- `decide_banca_p3(banker_score, p3)` → r24 = 1/0. Tabela da Banca quando o jogador COMPROU (p3 = valor 0..9 da 3ª carta do jogador).
- `define_vencedor(score_jog, score_ban)` → r24 = RES_PLAYER / RES_BANKER / RES_TIE. (recebe VALOR 0..9)

## 5. Responsabilidades que SÃO da main (não estão em nenhum módulo)

1. **Semeadura do LFSR**: `rng_state` nasce 0 e trava o LFSR. Semear com valor != 0 antes do 1º sorteio. Ideal: capturar `TCNT2` (timer livre) no 1º aperto de botão, para a sequência variar a cada power-on. (Pode ser feito na 1ª ISR ou na main ao ver o 1º FLG_NEW_BET.) Fallback se TCNT2==0: usar 0xA5.
2. **Regra da 3ª carta do JOGADOR**: se `decide_simples(score_jog)==1`, chamar `sorteia_carta`, guardar a carta, recalcular o placar do jogador, e LEMBRAR o p3 (valor) e o fato de ter comprado.
3. **Regra da 3ª carta da BANCA**:
   - se o jogador comprou → chamar `decide_banca_p3(score_ban, p3)`;
   - se o jogador NÃO comprou → chamar `decide_simples(score_ban)`.
   - se a decisão for comprar → `sorteia_carta`, guardar, **recalcular o placar da banca** (passo que não pode faltar).
4. **Mapear placar → display**: escrever em `disp_left`/`disp_right` os índices de fonte certos.
5. **Chamar o LCD** (funções C da Pessoa 4) para textos/rótulos. Nunca chamar LCD de dentro de ISR.

## 6. Máquina de estados sugerida (já acordada em conversa anterior)
1. **IDLE** — displays mostram "- -" (índice 11). Aguarda `FLG_NEW_BET`.
2. **APOSTOU** — lê `bet_type`, limpa `FLG_NEW_BET`. (1ª vez: semear LFSR aqui se ainda não semeado.)
3. **JOGANDO** — sorteia 2 cartas Jogador + 2 Banca (guardar como RANK), calcula placares (VALOR):
   - `checa_natural` → se natural, pula direto pro RESULTADO;
   - senão aplica as regras da 3ª carta (seção 5, itens 2–3).
   - mostra os valores nos dois displays.
4. **RESULTADO** — `define_vencedor`, compara com `bet_type`. Acertou → pisca "8 8" (vitória); errou → "0 0". LCD mostra detalhe.
5. volta para IDLE.

## 7. Esqueleto de boot da main (ordem importa)
```asm
    ; setup stack (avr-gcc costuma cuidar via crt, confirmar se há __init)
    rcall display_init
    rcall buttons_init
    ; (zerar flags / por displays em "- -")
    sei                     ; só habilita interrupção depois dos inits
loop:
    ; máquina de estados (seção 6)
    rjmp loop
```

## 8. Avisos de integração para alinhar com a equipe
- `game.S` mudou de interface: `regra_terceira_carta` foi REMOVIDA; agora são
  `decide_simples` + `decide_banca_p3`, e a ORDEM do jogo é responsabilidade da main.
  Avisar Pessoa 1 (main/state) e Pessoa 2 (game) antes do merge.
- Confirmar no `defs.h` real: nomes exatos das variáveis/constantes e se existe
  índice de fonte para letras (ex. "K") — o `sorteia_carta` agora preserva o rank,
  então o LCD pode exibir a carta real (Pessoa 4).
