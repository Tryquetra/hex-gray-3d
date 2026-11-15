# Hexagonal Gray Code (`hex-gray-3d`): $Q_3$ Hypercube Mapping of `q + r + s = 0` on FPGA

**Live 3D Visualizer (GitHub Pages):** https://tryquetra.github.io/hex-gray-3d/

Interactive 3D (Three-Dimensional) Three.js visualizer, mathematical formalization, combinatorial proofs, comparative benchmarks, and live **Sipeed Tang Nano 20K (`GW2AR-18C`)** FPGA (Field-Programmable Gate Array, a reconfigurable digital integrated circuit) implementation mapping the 7-state balanced ternary hexagon (`q + r + s = 0`) plus fault Sentinel onto a 3-bit Boolean hypercube $Q_3$.

---

## Core State Encoding

All $2^3 = 8$ states of 3 flip-flops (`gray_state[2:0]`) are assigned:

| Binary Code | Role | Cube Coords `(q, r, s)` | Ring Angle | Transition Property |
| :---: | :--- | :---: | :---: | :--- |
| `3'b000` | Center | `(0, 0, 0)` | Center | 1-bit bridge to `001` (`CCW`) or `010` (`CW`) |
| `3'b001` | Ring 1 | `(+1, 0, -1)` | `0 deg` | Flips `b[1]` to `011` (`CCW`) / `b[2]` to `101` (`CW`) |
| `3'b011` | Ring 2 | `(0, +1, -1)` | `60 deg` | Flips `b[0]` to `010` (`CCW`) / `b[1]` to `001` (`CW`) |
| `3'b010` | Ring 3 | `(-1, +1, 0)` | `120 deg` | Flips `b[2]` to `110` (`CCW`) / `b[0]` to `011` (`CW`) |
| `3'b110` | Ring 4 | `(-1, 0, +1)` | `180 deg` | Flips `b[0]` to `111` (`CCW`) / `b[2]` to `010` (`CW`) |
| `3'b111` | Ring 5 | `(0, -1, +1)` | `240 deg` | Flips `b[1]` to `101` (`CCW`) / `b[0]` to `110` (`CW`) |
| `3'b101` | Ring 6 | `(+1, -1, 0)` | `300 deg` | Flips `b[2]` to `001` (`CCW`) / `b[1]` to `111` (`CW`) |
| `3'b100` | Sentinel | Fault / Invalid | Fault | 1-bit bridge to `101` (`CCW`) or `110` (`CW`) |

Every adjacent rotational step (`+60 deg` Counter-Clockwise or `-60 deg` Clockwise) flips strictly **1 bit** (`d_H = 1`).

---

## Formalization, Proofs, and Empirical Findings

Read the complete English formalization, bipartite cycle-optimality proof, skew-invariant CDC (Clock Domain Crossing, signal transfer across asynchronous clock domains) proof, and hardware tables in:
* [`docs/FORMALIZATION_AND_PROOFS.md`](docs/FORMALIZATION_AND_PROOFS.md)
* Exhaustive finite-domain verification script: [`docs/verify_proofs.js`](docs/verify_proofs.js)

### Key Measured Highlights (`Tang Nano 20K` + `iverilog -g2005`)
* **50% lower switching activity on ring steps**: `1.0000` flips/cycle (`0` multi-bit events) vs `1.9998` (`bin3`), `2.0000` (`onehot7`), and `3.0000` (`trit2b`).
* **0 `CDC` torn words under routing skew**: `0.0 ppm` (parts per million) failures across `76,244` asynchronous cross-clock samples (`27.0 MHz` to `41.17 MHz` with `0` to `3.9 ns` wire skew), compared to `42,482 ppm` (`onehot7`), `43,308 ppm` (`bin3`), and `59,388 ppm` (`trit2b`).
* **Minimal area for control**: `609 LUT4` (4-input Look-Up Table) and `385 DFF` (D-type Flip-Flop) across a routed 64-lane bank at `180.12 MHz` (matching `bin3` at `609 LUT4`, half of `onehot7` at `1,109 LUT4`, and 4.2x smaller than `trit2b` at `2,564 LUT4`).
* **ALU tradeoff**: Multi-step phase accumulation (`delta in {-2..+2}`) incurs `+18%` `LUT4` overhead (`2,660` vs `2,253` for `bin3`) due to combinational Gray encode/decode stages, while cutting register toggling (`1.30` vs `1.50` flips/cycle).

---

## Repository Structure

* [`src/app.js`](src/app.js), [`index.html`](index.html), [`server.js`](server.js): Real-time 3D WebGL visualizer (linked $Q_3$ Boolean cube, 3-wire live delta bus, 7-cell `Tryte6` rosette, and auto-orbit).
* [`fpga/hex_gray_top.v`](fpga/hex_gray_top.v): Tang Nano 20K RTL (Register-Transfer Level) top module with debounced dual-button combo, active-low `LED` output, `UART` telemetry, and `HDMI` output.
* [`fpga/hex_gray_hdmi.v`](fpga/hex_gray_hdmi.v): Procedural `640x480 @ 60 Hz` `HDMI` (`TMDS`) renderer (`0` BRAM) using a multiplier-free shift-only Voronoi selector (`3,945 LUT4`, `427 DFF`, `0 BSRAM`, `130.60 MHz` `clk_sys`, `35.10 MHz` `clk_pix`).
* [`fpga/hex_gray_uart.v`](fpga/hex_gray_uart.v) & [`fpga/serial_ctrl.js`](fpga/serial_ctrl.js): `115200 8N1` UART interface (`?`, `c`, `a`, `0`, `1..6`, `s`, `g<bbb>`, `o`, `r`).
* [`fpga/bench/`](fpga/bench/run_bench.sh): Reproducible benchmark suite running `iverilog`, `yosys`, and `nextpnr-himbaechel` across `bin3`, `onehot7`, `trit2b`, and `hex_gray3`.
* [`CITATION.cff`](CITATION.cff) & [`LICENSE`](LICENSE): Academic citation metadata and MIT License.

---

## Quickstart

### 1. Verify Combinatorial & Geometric Proofs
```bash
bun docs/verify_proofs.js
```

### 2. Run the 3D Interactive Visualizer (Port `4174`)
```bash
bun install
bun run dev
```

### 3. Synthesize and Flash to Tang Nano 20K
Requires `yosys`, `nextpnr-himbaechel`, `gowin_pack`, and `openFPGALoader`:
```bash
./fpga/build.sh --flash
bun fpga/serial_ctrl.js /dev/ttyUSB1 '?' c c a s g110 '0' c o
```

### 4. Re-run Comparative FPGA & Simulation Benchmarks
```bash
./fpga/bench/run_bench.sh
```

---

## Citation

See [`CITATION.cff`](CITATION.cff) or cite:

```bibtex
@software{cassiano2026hexgray3d,
  author       = {Cassiano, Robson},
  title        = {Hexagonal Gray Code (hex-gray-3d): Zero-Glitch 3-Bit Boolean Hypercube Mapping of q + r + s = 0, FPGA Synthesis, and Combinatorial Proofs},
  year         = {2026},
  version      = {0.1.0},
  url          = {https://github.com/Tryquetra/hex-gray-3d},
  license      = {MIT}
}
```
