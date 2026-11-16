# Hexagonal Gray Code (`hex-gray-3d`): $Q_3$ Hypercube Mapping of `q + r + s = 0` on FPGA

**Live 3D Visualizer (GitHub Pages):** https://tryquetra.github.io/hex-gray-3d/

Interactive 3D (Three-Dimensional) Three.js visualizer, mathematical formalization, combinatorial proofs, comparative benchmarks, and live **Sipeed Tang Nano 20K (`GW2AR-18C`)** FPGA (Field-Programmable Gate Array, a reconfigurable digital integrated circuit) implementation mapping the 7-state balanced ternary hexagon (`q + r + s = 0`) plus fault Sentinel onto a 3-bit Boolean hypercube $Q_3$.

---

## Plain-Language Overview: Why This Encoding Matters

Representing a 7-position hexagonal compass (the stationary center plus 6 surrounding directions separated by $60^\circ$) inside standard binary chips typically takes **6 or 7 wires** (`2` bits per ternary coordinate or `one-hot`), wasting routing tracks and flipping multiple wires simultaneously on each turn.

**Hexagonal Gray Code compresses all 7 positions plus an explicit fault alarm into just 3 wires** arranged as a loop on a 3D cube:
1. **Half the dynamic wire switching energy**: rotating step by step around the ring flips exactly **1 wire per transition** (`1.0` toggle/step vs `2.0` in standard binary/one-hot and `3.0` in direct 6-wire ternary).
2. **Zero cross-clock corruption**: because adjacent steps change only 1 wire, two subsystems running on unsynchronized clocks always sample either the complete previous state or the complete next state (`0` torn words across `76,244` skewed samples vs `3,239` to `4,528` failures in traditional baselines).
3. **Minimum silicon area**: matches the smallest binary controller (`609 LUT4` and `385 DFF` at 64 parallel lanes, `180.12 MHz`), taking half the logic of `onehot7` (`1,109 LUT4`) and a quarter of 6-wire `trit2b` (`2,564 LUT4`).
4. **Explicit boundary on arithmetic**: when jumping or summing multiple steps at once (`delta` in `{-2..+2}`), translating Gray code back and forth costs `+18%` LUTs and `~7%` peak clock relative to plain binary (`bin3`), making standard binary preferable for dense multi-step `ALU` (Arithmetic Logic Unit) datapaths with single-clock reads.

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

## Prior Art, Novelty Scope, and Applications

### Literature Context and Unification
Three established hardware techniques converge in this encoding:
* **Unit-distance reflected codes**: introduced by Frank Gray at Bell Labs (U.S. Patent `2,632,058`, filed 1947, granted 1953) for `PCM` (Pulse-Code Modulation) encoders so adjacent steps toggle strictly 1 bit (standardized as *Gray code* by IEEE and ACM).
* **6-step 3-bit cycles in power electronics**: `BLDC` (Brushless Direct Current) Hall-effect sequences and `SVPWM` (Space Vector Pulse Width Modulation) 3-phase inverters traverse 6 active hexagonal sectors around a null center state with minimal switching transitions.
* **Zero-sum cube coordinates (`q + r + s = 0`)**: spatial computing pipelines, computer graphics, and ternary grid processors address 6 equidistant neighbors via balanced ternary digits `{-1, 0, +1}`.

While power drives apply 6-step cycles solely to inverter gate switching and ternary FPGA prototypes typically use wider `6`-bit (`2 bits/trit`) or `7`-to-`9`-bit `one-hot` buses, **Hexagonal Gray** establishes an exact 3-wire algebraic bridge between them: the 6-edge cycle on $Q_3$ directly encodes the unit balanced ternary hexagon, keeps `3'b000` (`(0,0,0)`) at Hamming distance `1` from entry edges, and reserves `3'b100` as a built-in fault sentinel (`87.5%` geometric code density).

### Market Applications
* **Three-Phase Motor Drives & Solar Inverters (`BLDC` / `SVPWM`)**: maps directly to 6 active sectors, null zero-vector (`3'b000`), and hardware fault trip (`3'b100`), preventing torn multi-bit commands across PWM/control clock boundaries.
* **Hexagonal `NoC` (Network-on-Chip) Mesh Routers**: encodes 6 equidistant neighbor ports plus local-core sink (`Center`) in 3 wires instead of 6, halving bus toggling and avoiding FIFO synchronization overhead between clock islands.
* **Rotary Encoders & Industrial Actuators**: eliminates transient reading errors across `60 deg` sectors when sampled asynchronously by microcontrollers or FPGAs.
* **Low-Power Directional `IoT` (Internet of Things) Telemetry**: cuts pin transition count by `50%` to `67%` relative to binary and 6-wire ternary codes in step-driven protocols.

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
