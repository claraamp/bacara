# Projeto Bacará - Programa de Software Báisco

## Integrantes da Equipe
- Cauã Marinho
- Clara Andrade 
- João Luis
- João Kishimoto
- Júlia Texeira

---

## Explicação do Funcionamento
A lógica do jogo funciona com uma função sorteia_carta que realizará a distribuição em sorteio das cartas para o jogador e a banca, esse sorteio é realizado com uma variavel rng_state que tem os seus bits deslocados para a direita, depois disso, utilizaremos uma subtração sucessiva do 13 (que seria equivalente a dividir por 13) até retornar um valor entre 0 e 12, somando 1 unidade em seguida. Depois, a função valor_carta irá verificar o valor, em que, se for de 1 a 9 ela devolve o próprio numero, se for 10,11,12 ou 13 devolve 0, que são os valores das respectivas cartas no jogo.  Para saber quanto cada um tem criamos a função calcula_pontuacao que vai utilizar os registradores r24, r22 e r20(para representar a terceira carta)continua...

[Escrevam aqui, com as palavras de vocês, a lógica por trás do jogo. Expliquem como o microcontrolador usa o LFSR para sortear, como foi feita a multiplexação dos displays e como a máquina de estados gerencia as rodadas.]

---

##  Relação de Materiais Utilizados
- 1x Arduino Nano (ATmega328P)
- 2x Displays de 7 Segmentos (Cátodo Comum)
- 3x Push Buttons
- [Liste o resto dos resistores, transistores, jumpers, módulo I2C, etc.]

---

## Guia de Utilização
[Façam um passo a passo para quem nunca jogou. Exemplo:]
1. **Ligar o sistema:** O display mostrará 0.
2. **Fazer a Aposta:** Pressione o Botão 1 para apostar no Jogador...
3. [Continuem a explicação de como o usuário interage com o jogo]

---

## Diagrama no SimulIDE
[Insira o link ou caminho para a pasta onde o arquivo do circuito está, e coloque uma foto]
![Diagrama SimulIDE](./assets/simulide_print.png)

---

## Fotos do Circuito Físico
[Coloquem as fotos da protoboard montada. O professor quer ver a fiação!]
![Foto Frontal](./assets/foto_circuito_1.jpg)
![Foto Detalhe](./assets/foto_circuito_2.jpg)

---

## 📂 Links para os Entregáveis
- [Código Fonte em Assembly (main.S)](./src/main.S)
- [Módulo de Regras (game.S)](./src/game.S)
- [Arquivo do SimulIDE](./circuit/bacara.sim1)