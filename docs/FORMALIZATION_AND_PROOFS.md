# Formalization and Proofs: 3-Bit Hexagonal Gray Code on the Boolean Hypercube $Q_3$

This document presents the mathematical formalization, combinatorial proofs, timing-skew guarantees, and hardware verification results for the **Hexagonal Gray Code**, a compact 3-bit binary representation of the zero-sum balanced ternary hexagonal unit cell (`q + r + s = 0`) implemented on binary FPGA (Field-Programmable Gate Array, a reconfigurable digital integrated circuit) fabrics.

All combinatorial and geometric theorems below are independently verified over the entire finite domain by [`verify_proofs.js`](./verify_proofs.js) (`bun docs/verify_proofs.js`).

---

## 1. Domain Definitions

### 1.1 Zero-Sum Balanced Ternary Hexagonal Unit Space
Let $\mathbb{T} = \{-1, 0, +1\}$ denote the balanced ternary digit alphabet (signed trits). Define the unit hexagonal state set $\mathcal{H} \subset \mathbb{T}^3$ as all integer cube-coordinate vectors $(q, r, s)$ satisfying the coplanar zero-sum invariant:

$$\mathcal{H} = \left\{ (q, r, s) \in \mathbb{T}^3 \;\middle|\; q + r + s = 0 \right\}$$

The set $\mathcal{H}$ has exact cardinality $|\mathcal{H}| = 7$, partitioned by the $L_1$ taxicab norm $\|v\|_1 = |q| + |r| + |s|$ into:
1. **The Origin (Center)**: $\mathcal{H}_0 = \{(0, 0, 0)\}$ with norm $0$.
2. **The Unit Hexagonal Ring**: $\mathcal{H}_1 = \{v \in \mathcal{H} : \|v\|_1 = 2\}$, consisting of the $6$ cyclic unit vectors separated by $60^\circ$ angular steps:
   $$v_0 = (+1, 0, -1), \; v_1 = (0, +1, -1), \; v_2 = (-1, +1, 0), \; v_3 = (-1, 0, +1), \; v_4 = (0, -1, +1), \; v_5 = (+1, -1, 0).$$

Two ring vectors $v_i, v_j \in \mathcal{H}_1$ are geometric neighbors along the ring boundary iff $\|v_i - v_j\|_1 = 2$ (equivalently $j \equiv i \pm 1 \pmod 6$).

### 1.2 The 3-Bit Bijective Code Assignment $\Phi: \{0,1\}^3 \to \mathcal{H} \cup \{\bot\}$
Assign the $2^3 = 8$ vertices of the 3-dimensional Boolean hypercube $Q_3 = (\{0,1\}^3, E_H)$ to the 7 geometric states of $\mathcal{H}$ plus one explicit fault Sentinel state $\bot$:

| Binary Code $(b_2 b_1 b_0)$ | Role | Cube Coords $(q, r, s)$ | Ring Angle | Hamming Weight |
| :---: | :--- | :---: | :---: | :---: |
| `3'b000` | Center ($\mathcal{H}_0$) | $(0, 0, 0)$ | Center | $0$ |
| `3'b001` | Ring vertex $v_0$ | $(+1, 0, -1)$ | $0^\circ$ | $1$ |
| `3'b011` | Ring vertex $v_1$ | $(0, +1, -1)$ | $60^\circ$ | $2$ |
| `3'b010` | Ring vertex $v_2$ | $(-1, +1, 0)$ | $120^\circ$ | $1$ |
| `3'b110` | Ring vertex $v_3$ | $(-1, 0, +1)$ | $180^\circ$ | $2$ |
| `3'b111` | Ring vertex $v_4$ | $(0, -1, +1)$ | $240^\circ$ | $3$ |
| `3'b101` | Ring vertex $v_5$ | $(+1, -1, 0)$ | $300^\circ$ | $2$ |
| `3'b100` | Sentinel ($\bot$) | Fault / Invalid | Fault | $1$ |

---

## 2. Combinatorial and Algebraic Theorems

### Theorem 1: State Space Efficiency and Information Density
Under $\Phi$, the 7 valid geometric states occupy $7/8 = 87.5\%$ of the 3-bit code space while allocating the final code `3'b100` to an explicit hardware fault sentinel ($100\%$ defined state coverage). Useful geometric entropy per physical wire equals:

$$\eta_{\text{HexGray}} = \frac{\log_2(7)}{3} \approx 0.9358 \text{ bits/wire}$$

*Comparison against standard binary-encoded ternary baselines for the same 7-state hexagonal unit:*
* **7-state One-Hot (`onehot7`)**: $7 / 2^7 = 5.47\%$ density, $\log_2(7)/7 \approx 0.4011$ bits/wire.
* **2-bit-per-trit Cube (`trit2b`, 6 wires)**: $7 / 2^6 = 10.94\%$ density, $\log_2(7)/6 \approx 0.4679$ bits/wire.
* **Hexagonal Gray (`hex_gray3`, 3 wires)**: achieves minimal 3-wire width ($\lceil \log_2 7 \rceil = 3$) while retaining full Hamming-1 ring adjacency. $\blacksquare$

### Theorem 2: Cycle Optimality and Bipartite Parity Bound on $Q_3$
The sequence $C_6 = (001, 011, 010, 110, 111, 101)$ forms a simple cycle of length $6$ in $Q_3$, and $6$ is the strict maximum length of any cyclic Gray code capturing a proper subset of $Q_3$.

**Proof.**
1. *Verification of adjacency*: Computing $c_i \oplus c_{(i+1)\bmod 6}$ yields bit masks $(010, 001, 100, 001, 010, 100)$, each of Hamming weight $1$. Thus every edge $(c_i, c_{(i+1)\bmod 6})$ belongs to $E_H(Q_3)$.
2. *Absence of $7$-cycles (bipartite parity obstruction)*: Partition $V(Q_3)$ into even-parity vertices $E = \{x : \text{wt}(x) \equiv 0 \pmod 2\}$ (`000, 011, 110, 101`) and odd-parity vertices $O = \{x : \text{wt}(x) \equiv 1 \pmod 2\}$ (`001, 010, 111, 100`). Every edge of $Q_3$ flips 1 bit and strictly joins $E$ to $O$. Therefore $Q_3$ is bipartite and admits only even-length cycles. Consequently, no $7$-cycle exists in $Q_3$, and removing an adjacent even-odd edge pair (`000` in $E$ and `100` in $O$, separated by $d_H(000, 100) = 1$) leaves balanced classes $|E \cap C_6| = |O \cap C_6| = 3$, yielding the maximum nontrivial even cycle of length $6$. $\blacksquare$

### Theorem 3: Total Unitary Transition Coverage ($\text{d}_H = 1$ Across All 8 States)
Define the Counter-Clockwise ($\text{CCW}$, $+60^\circ$) and Clockwise ($\text{CW}$, $-60^\circ$) next-state operators $\delta_{\text{CCW}}, \delta_{\text{CW}}: \{0,1\}^3 \to \{0,1\}^3$ as implemented in [`hex_gray_top.v`](../fpga/hex_gray_top.v):

```text
CCW (+60): 001->011, 011->010, 010->110, 110->111, 111->101, 101->001, 000->001, 100->101
CW  (-60): 001->101, 101->111, 111->110, 110->010, 010->011, 011->001, 000->010, 100->110
```

For all $x \in \{0,1\}^3$ and both directions $d \in \{\text{CCW}, \text{CW}\}$, $d_H(x, \delta_d(x)) = 1$.

**Proof.** Exhaustive inspection of all $16$ pairs $(x, \delta_d(x))$:
* All $12$ transitions inside $C_6$ traverse edges of $C_6$ with $d_H = 1$.
* From Center (`000`): $d_H(000, 001) = 1$ (flips $b_0$) and $d_H(000, 010) = 1$ (flips $b_1$).
* From Sentinel (`100`): $d_H(100, 101) = 1$ (flips $b_0$) and $d_H(100, 110) = 1$ (flips $b_1$).
Every single directional step in the entire state machine switches strictly one flip-flop. $\blacksquare$

### Theorem 4: Skew-Invariant Zero-Glitch CDC Safety
Let source register $S(t)$ transition from $u$ to $v$ with $d_H(u, v) = 1$ at $t = 0$. Suppose each wire $k \in \{0, 1, 2\}$ arrives at an asynchronous destination register after arbitrary positive propagation skew $\tau_k \ge 0$, producing bus vector $W(t) = (w_2(t), w_1(t), w_0(t))$. Then for every sampling instant $t \in \mathbb{R}$, $W(t) \in \{u, v\}$.

**Proof.** Since $d_H(u, v) = 1$, there exists a unique index $m \in \{0, 1, 2\}$ such that $u_m \neq v_m$ and $u_k = v_k$ for all $k \neq m$. Thus, for all $k \neq m$, wire $w_k(t)$ remains constant at $u_k = v_k$ across the entire transition interval regardless of $\tau_k$. Only wire $w_m(t)$ changes, transitioning monotonically at $t = \tau_m$:

$$W(t) = \begin{cases} u & \text{if } t < \tau_m, \\ v & \text{if } t \ge \tau_m. \end{cases}$$

No third transient state (`torn word` or illegal state) can exist on the bus at any instant $t$, guaranteeing $0$ intermediate code corruption across asynchronous Clock Domain Crossing (`CDC`, transfer of signals between unrelated clock domains). $\blacksquare$

### Theorem 5: Single-LUT Combinational Next-State Depth on FPGA
On an SRAM-based FPGA (Static Random-Access Memory Field-Programmable Gate Array) built from `LUT4` (4-input Look-Up Table) primitives:
1. Both directional transition functions $\delta_{\text{CCW}}(b_2, b_1, b_0)$ and $\delta_{\text{CW}}(b_2, b_1, b_0)$ depend on 3 Boolean inputs and synthesize into at most **1 `LUT3` per output bit** (3 `LUT3` total, combinational logic depth $1$).
2. The combined bidirectional step function $\delta(b_2, b_1, b_0, \text{dir})$ depends on 4 Boolean inputs and fits inside **1 `LUT4` per output bit** (3 `LUT4` total, combinational logic depth $1$).

*Proof.* Every Boolean function $f: \{0,1\}^k \to \{0,1\}$ is realized directly in a single $2^k$-entry truth table inside a single `LUTk` cell without carry chains or multi-level cascades. $\blacksquare$

### Theorem 6: Multiplier-Free Shift-Only Voronoi Selector for 7-Cell Hexagonal Rasterization
For pointy-top regular hexagons arranged in a 7-cell `Tryte6` rosette (radius $R = 42$ px, centers separated by $\Delta x = 78$ px, $\Delta y = 68$ px on $640 \times 480$ HDMI), choosing the unique nearest hexagon owner via the shift-only metric

$$S(dx, dy) = \max\left(2|dx|,\; 2|dy| + |dx|\right)$$

produces zero owner mismatches relative to squared Euclidean distance across all $32{,}151$ interior hexagon pixels (`0` overlaps, `0` mismatches, checked exhaustively in `docs/verify_proofs.js`), eliminating adjacent diagonal bounding-box clipping without hardware multipliers or BRAM (Block Random-Access Memory). $\blacksquare$

---

## 3. Empirical Hardware Synthesis and Simulation Benchmarks

All four encodings implement identical 7-state ring and multi-step phase semantics (`0` equivalence mismatches across `70,000` cycles via `iverilog -g2005`, [`fpga/bench/tb_bench.v`](../fpga/bench/tb_bench.v)).

### 3.1 Switching Activity ($\alpha$) and Asynchronous `CDC` Error Rate

| Encoding | Sequential Ring Flips (`10k` cyc) | Avg Bits/Cycle ($\alpha_{\text{seq}}$) | Multi-Bit Events | Mixed Ring ($\alpha_{\text{mix}}$) | Phase ALU ($\alpha_{\text{alu}}$) | `CDC` Torn Words (`76,244` samples) | `CDC` Error Rate (`ppm`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`hex_gray3` (3b)** | **`10,000`** | **`1.0000`** | **`0`** | **`0.7911`** | **`1.3039`** | **`0` (`0` illegal)** | **`0.0`** |
| `bin3` (3b) | `19,998` | `1.9998` | `6,666` | `1.4111` | `1.5042` | `3,302` (`552` illegal) | `43,308.3` |
| `onehot7` (7b) | `20,000` | `2.0000` | `10,000` | `1.4832` | `1.7444` | `3,239` (`3,239` illegal) | `42,482.0` |
| `trit2b` (6b) | `30,000` | `3.0000` | `10,000` | `2.3249` | `2.6546` | `4,528` (`4,528` illegal) | `59,388.3` |

*Condition: source clock `27.0 MHz`, asynchronous destination clock `41.17 MHz`, wire routing skew `0 ns` to `3.9 ns`, `ppm` denotes parts per million.*

### 3.2 Gowin `GW2AR-LV18QN88C8/I7` (`Tang Nano 20K`) Area and Routed $F_{\max}$

| Configuration | Single-Core `LUT1-4` | Single-Core `DFF` | 64-Lane Routed `LUT4` | 64-Lane Routed `ALU` | 64-Lane Routed `DFF` | Routed $F_{\max}$ (`MHz`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `ring_bin3` | `7` | `3` | `609` | `0` | `385` | **`186.71`** |
| **`ring_hex_gray3`** | **`7`** | **`3`** | **`609`** | `0` | **`385`** | **`180.12`** |
| `ring_onehot7` | `14` | `7` | `1,109` | `0` | `641` | `158.88` |
| `ring_trit2b` | `97` | `6` | `2,564` | `0` | `577` | `136.39` |
| `alu_onehot7` | `100` | `7` | **`1,917`** | `0` | `641` | **`143.29`** |
| `alu_bin3` | **`16`** | `3` | `2,253` | `1,152` | `385` | `142.61` |
| **`alu_hex_gray3`** | `23` | `3` | `2,660` | `1,152` | **`385`** | `132.87` |
| `alu_trit2b` | `53` | `6` | `4,206` | `1,272` | `577` | `101.66` |

### 3.3 Architectural Tradeoff Summary
1. **Ring Control, Motor Commutation, Mesh Routing, and `CDC` Buses**: `hex_gray3` ties `bin3` for minimum FPGA area (`609 LUT4`, `385 DFF` at 64 lanes) and reaches `180.12 MHz`, cuts dynamic bit switching by **50%** (`1.0` bit/step vs `2.0` for `bin3`/`onehot7` and `3.0` for `trit2b`), and eliminates **100%** of cross-clock torn words under propagation skew.
2. **Multi-Step Phase Arithmetic (`delta in {-2..+2}`)**: Translating Gray back to binary index and re-encoding adds `18%` `LUT4` overhead (`2,660` vs `2,253`) and lowers $F_{\max}$ by `~7%` (`132.87 MHz` vs `142.61 MHz`) relative to natural `bin3`, while keeping lower register toggle activity (`1.30` vs `1.50`) and outperforming uncompressed 6-bit `trit2b` in both area (`37%` fewer `LUT4`) and frequency (`+30.7%`).
