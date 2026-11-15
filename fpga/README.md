# Tang Nano 20K FPGA Hardware: Hexagonal Gray Code (`Q3`)

Implementacao em Verilog sintetizada para a **Sipeed Tang Nano 20K (`GW2AR-LV18QN88C8/I7`)** do mapeamento de 3 bits no cubo booleano $Q_3$ para o espaco hexagonal de 7 estados (`q + r + s = 0`) mais o estado Sentinela `3'b100`.

## Codificacao dos 8 Estados (`gray_state[2:0]`)

| Codigo | Papel | Coordenadas `(q, r, s)` | Angulo |
| :--- | :--- | :--- | :--- |
| `3'b000` | Centro | `(0, 0, 0)` | `nil` |
| `3'b001` | Anel 1 | `(+1, 0, -1)` | `000` |
| `3'b011` | Anel 2 | `(0, +1, -1)` | `060` |
| `3'b010` | Anel 3 | `(-1, +1, 0)` | `120` |
| `3'b110` | Anel 4 | `(-1, 0, +1)` | `180` |
| `3'b111` | Anel 5 | `(0, -1, +1)` | `240` |
| `3'b101` | Anel 6 | `(+1, -1, 0)` | `300` |
| `3'b100` | Sentinela | invalido / falha | `err` |

Cada passo adjacente de `+60` ou `-60` graus ao longo do anel altera exatamente 1 bit (`dlt=1`).

## Perifericos Fisicos

- **Botoes (`I_btn[1:0]`, pins 88 e 87)**:
  - `BTN0` (pin 88): passo `+60 deg` CCW (`next_ccw`).
  - `BTN1` (pin 87): passo `-60 deg` CW (`next_cw`).
  - Toque simultaneo (`BTN0 + BTN1`): alterna entre Centro `3'b000` e `3'b001`.
  - Pressao longa simultanea (`>= 800 ms`): reset para `3'b001` e pausa de auto-orbita.
- **LEDs ativos em nivel baixo (`O_led_n[5:0]`, pins 15..20)**:
  - `LED[2:0]`: reflete diretamente `gray_state[2:0]` (apenas 1 LED muda por passo no anel).
  - `LED[3]`: alerta da Sentinela (`3'b100`).
  - `LED[4]`: pulso de comando ou modo auto-orbita ativo.
  - `LED[5]`: batimento de lock da PLL HDMI.
- **HDMI procedural (`640x480 @ 60 Hz`, 0 BRAM)**:
  - Esquerda: projecao 2D do cubo $Q_3$ destacando as 6 arestas do ciclo hamiltoniano e o vertice ativo.
  - Centro: barramento de 3 fios (`b[2]`, `b[1]`, `b[0]`) com realce dourado no bit alterado em `last_delta`.
  - Direita: roseta `Tryte6` de 7 celulas com selecao Voronoi por deslocamentos (`shift-only`) e emblema da Sentinela.
- **UART (`115200 8N1`, `/dev/ttyUSB1`)**:
  - Telemetria: `HG code=3'b011 qrs=( 0,+1,-1) ang=060 dlt=1 role=ring orb=0`

## Compilacao, Gravacao e Teste

```bash
cd /home/robson/coding/hex-gray-3d
chmod +x fpga/build.sh
./fpga/build.sh --flash
bun fpga/serial_ctrl.js /dev/ttyUSB1 '?' c c a s g110 '0' c o
```
