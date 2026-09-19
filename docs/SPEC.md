# Technical Specification

> Full spec for the [Embedded DSP Image Processing Benchmark](../README.md).
> This document is the source of truth for algorithm formulas, datatypes,
> coordinate/valid-region rules, RTL module interfaces, and benchmark
> methodology. Every implementation (Python, C, RTL) must conform to it.

Golden Model (Python) → C implementation → RTL (Verilog-2001) must all
produce **bit-exact identical output** (mismatch = 0).

## 1. Project Goal

Build and benchmark an image DSP pipeline on three platforms:

| Platform | Compute |
| --- | --- |
| Orange Pi Zero 3W | CPU only |
| AMD Kria KR260 | Zynq UltraScale+ MPSoC (ARM PS + FPGA PL) |
| EBAZ4205 (Zynq-7010) | ARM PS + FPGA PL |

```
                     IMAGE
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
     Zero 3W         KR260        EBAZ4205
      CPU             CPU           CPU
       │               │             │
       │               ▼             ▼
       │             FPGA          FPGA
       │               │             │
       └───────────────┼─────────────┘
                        ▼
               Latency / FPS / CPU vs FPGA
```

Technical objectives:

- Golden Model in Python
- C implementation (CPU benchmark, runs on all 3 boards)
- RTL in Verilog-2001, **synthesizable**
- Verification: `Python == C == RTL`, mismatch = 0
- FPGA execution on EBAZ4205 / KR260, CPU vs FPGA benchmark

## 2. Problem & Algorithm Pipeline

A camera image is corrupted with salt-and-pepper noise → the system removes
the noise → edges are detected.

```
Original RGB Image
        │
        ▼
    Grayscale
        │
        ▼
Salt & Pepper Noise
        │
        ▼
   3×3 Median
        │
        ▼
   Sobel 3×3
     │     │
     ▼     ▼
    Gx     Gy
     \     /
      \   /
        ▼
  |Gx| + |Gy|
        │
        ▼
    Threshold
        │
        ▼
 Binary Edge Image
```

## 3. Algorithm Details

### 3.1 RGB → Grayscale

Standard luminance conversion:

$$
Y = 0.299R + 0.587G + 0.114B
$$

Hardware fixed-point approximation:

$$
\boxed{
Y = \left\lfloor
\frac{77R + 150G + 29B}{256}
\right\rfloor
}
$$

Since \(256=2^8\):

```text
Y = (77*R + 150*G + 29*B) >> 8
```

Output: `uint8`, range `0–255`.

---

### 3.2 Salt-and-Pepper Noise

Noise is generated **offline in Python** and stored as `noisy.hex`.
The FPGA does not generate random noise.

```text
noise_probability = 5%
seed              = 12345

pepper = 0
salt   = 255
```

For \(r\sim U(0,1)\):

$$
\boxed{
I_N =
\begin{cases}
0, & r < 0.025\\
255, & 0.025 \le r < 0.05\\
I, & r \ge 0.05
\end{cases}
}
$$

Thus:

```text
P(pepper) = 2.5%
P(salt)   = 2.5%
P(noise)  = 5%
```

---

### 3.3 Median Filter 3×3

Nonlinear order-statistic spatial filter.

```text
p00 p01 p02
p10 p11 p12
p20 p21 p22
```

Mathematical definition:

$$
\boxed{
I_M(x,y)=
\operatorname{median}
\{p_{00},p_{01},...,p_{22}\}
}
$$

After sorting:

$$
v_{(1)}\le v_{(2)}\le...\le v_{(9)}
$$

the output is:

$$
\boxed{I_M=v_{(5)}}
$$

Hardware implementation:

```text
9 pixels
   ↓
compare-swap sorting network
   ↓
5th ordered value
```

---

### 3.4 Sobel Filter 3×3

Applied to the **median-filtered image**.

Sobel kernels:

$$
\boxed{
K_x=
\begin{bmatrix}
-1&0&1\\
-2&0&2\\
-1&0&1
\end{bmatrix}
}
\qquad
\boxed{
K_y=
\begin{bmatrix}
-1&-2&-1\\
0&0&0\\
1&2&1
\end{bmatrix}
}
$$

$$
G_x=K_x*I_M
\qquad
G_y=K_y*I_M
$$

For the 3x3 window:

$$
\boxed{
G_x=-p_{00}+p_{02}-2p_{10}+2p_{12}-p_{20}+p_{22}
}
$$

$$
\boxed{
G_y=-p_{00}-2p_{01}-p_{02}
+p_{20}+2p_{21}+p_{22}
}
$$

Hardware implementation uses add/subtract and shift operations:

```text
2*p = p << 1
```

For 8-bit input:

$$
|G_x|_{\max}=|G_y|_{\max}=1020
$$

so signed 11-bit gradient values are sufficient.

---

### 3.5 Gradient Magnitude

The standard Euclidean gradient magnitude is:

$$
M_{L2}=
\sqrt{G_x^2+G_y^2}
$$

To avoid squaring and square-root hardware, this design uses the \(L_1\) approximation:

$$
\boxed{
M=|G_x|+|G_y|
}
$$

Maximum value:

$$
M_{\max}=1020+1020=2040
$$

Therefore:

```text
M: unsigned 12-bit
range: 0–2040
```

---

### 3.6 Threshold

Binary thresholding:

$$
\boxed{
B(x,y)=
\begin{cases}
255,&M(x,y)\ge T\\
0,&M(x,y)<T
\end{cases}
}
$$

Specified threshold:

```text
THRESHOLD = 100
```

Therefore:

$$
\boxed{
B=
\begin{cases}
255,&|G_x|+|G_y|\ge100\\
0,&|G_x|+|G_y|<100
\end{cases}
}
$$

Output: `uint8` binary edge image (`0` or `255`).


## 4. Input Specification

| Property | Value |
| --- | --- |
| Baseline resolution | 512 × 512 |
| Pixel depth | 8-bit unsigned |
| Format | HEX (ASCII, one two-digit hex value per line, e.g. `ff`, `00`) |
| Channels | 1 (grayscale) |
| Baseline pixel count | 262,144 |

All pipeline data (`gray`, `noisy`, `median`, `gradient`, `expected`, RTL
output) is stored as ASCII **`.hex`**: one two-digit hex byte per line,
row-major order, 262,144 lines for a 512×512 image. This format is used
consistently across Python, C, and RTL so no binary-to-hex conversion
step is ever needed — the RTL testbench loads it directly with Verilog's
`$readmemh`. See §13 for how the testbench consumes it.

Additional benchmark sizes: 128×128, 256×256, 512×512 (baseline), 1024×1024.
**No square-image assumption** — the golden model, C, and RTL must all
correctly handle `W ≠ H` (the test suite must include at least one
non-square case, e.g. 640×480).

RTL parameters:

```verilog
parameter IMAGE_WIDTH  = 512;
parameter IMAGE_HEIGHT = 512;
```

`IMAGE_WIDTH` → line buffer depth, column counter, end-of-line detection.
`IMAGE_HEIGHT` → frame boundary, row counter, end-of-frame detection,
verification.

## 5. Coordinate Convention

```
x = column = 0 ... IMAGE_WIDTH-1
y = row    = 0 ... IMAGE_HEIGHT-1
```

Pixel stream order is **row-major**:

```
(0,0) (1,0) ... (W-1,0) (0,1) (1,1) ... (0,2) ...
```

This convention applies consistently across Python / C / RTL / testbench.

## 6. Border & Valid Region Specification (most important)

The pipeline has **two chained 3×3 filter stages** (Median → Sobel). Since
Sobel may only consume *valid* median pixels, the two stages have
**different valid regions** — do not use a single number for the whole
pipeline.

### 6.1 Median — valid region

```
x ∈ [1, W-2]
y ∈ [1, H-2]
size: (W-2) × (H-2)
```

For 512×512 → **510 × 510**. Outside this region: `median_pixel = 0`.

### 6.2 Sobel — valid region

Sobel only uses median pixels within the Median valid region, so:

```
x ∈ [2, W-3]
y ∈ [2, H-3]
size: (W-4) × (H-4)
```

For 512×512 → **508 × 508**. Outside this region: `pixel_out = 0`.

### 6.3 Mandatory rule

**Wrong (do not do this):**

```
median → zero-pad border → Sobel runs on the full image → mask output afterward
```

**Correct:**

```
median valid → use only median valid → Sobel valid
```

Equivalent Python/C loop:

```python
# Median
for y in range(1, H-1):
    for x in range(1, W-1):
        ...

# Sobel — only runs on the region where median is guaranteed valid
for y in range(2, H-2):
    for x in range(2, W-2):
        ...
```

## 7. Datatype Specification

| Data | Type |
| --- | --- |
| RGB | uint8 |
| Grayscale | uint8 |
| Noisy image | uint8 |
| Median | uint8 |
| Sobel input | uint8 |
| Gx | signed 12-bit |
| Gy | signed 12-bit |
| Magnitude | unsigned 12-bit |
| Threshold | unsigned |
| Output | uint8 |

No floating-point anywhere in RTL.

## 8. Streaming RTL Design Principles

### 8.1 Coordinates must travel with the data

No single global row/col counter for the whole pipeline. Each stage knows
its own latency; the top level maintains a coordinate pipeline (delaying
x, y, valid by the number of cycles of latency of the previous stage).

```
pixel_in
   │ x0,y0
   ▼
[stage 0] ── x0,y0 ──▶ [stage 1] ── x0,y0 ──▶ [stage 2]
```

Example: Median stage has 2-cycle latency →

```
cycle 100: median input  = pixel(x=10,y=20)
cycle 102: median output = median(x=10,y=20)
```

`valid`, `x`, `y` must be delayed by exactly 2 cycles accordingly.

### 8.2 Latency budget (default design — must match the RTL implementation)

| Module | Latency | Note |
| --- | --- | --- |
| `line_buffer.v` | 1 cycle | registered output |
| `window_3x3.v` | 0 cycle | pure combinational (packs taps into p00..p22) |
| `median_3x3.v` | 1 cycle | compare-swap network combinational, registered output |
| `sobel_3x3.v` | 1 cycle | Gx/Gy registered |
| `gradient_mag.v` | 0 cycle | combinational abs+add |
| `threshold.v` | 0 cycle | combinational compare |

- Median stage total latency = `line_buffer(1) + window(0) + median(1)` = **2 cycles**
- Sobel stage total latency = `line_buffer(1) + window(0) + sobel(1)` = **2 cycles**
- `gradient_mag` + `threshold` = 0 cycles (pure combinational, chained right after Sobel)

If any module's latency changes during implementation (e.g. adding a
pipeline stage to hit Fmax), **this table must be updated first** — all
top-level coordinate-delay logic depends on it.

### 8.3 Window center pixel

When the current input pixel is `(x,y)`, the generated window has
**center = (x-1, y-1)**:

```
window_valid = 1
center_x = x - 1
center_y = y - 1
```

Example: current pixel = (10,20) →

```
(8,18)(9,18)(10,18)
(8,19)(9,19)(10,19)
(8,20)(9,20)(10,20)
center = (9,19)
```

→ `median(x=9, y=19)`.

Similarly at the second stage: once window #2 has
`median(x-1,y-1)...median(x+1,y+1)`, the Sobel center is `(x,y)`, only
valid when `2 <= x <= W-3` and `2 <= y <= H-3` → the final output has the
correct coordinate `pixel_out(x,y)`.

### 8.4 `stream_valid` vs `result_valid`

Two distinct valid signals, kept separate to control the architecture:

- **`stream_valid`**: runs continuously across the whole frame — needed
  because the next stage (next Line Buffer) requires a continuous pixel
  stream to operate, even when the value falls outside the valid region
  (value = 0).
- **`result_valid`**: only HIGH within the valid region.
  - `median_result_valid`: HIGH when `1 <= x <= W-2` and `1 <= y <= H-2`
  - `sobel_result_valid`: HIGH when `2 <= x <= W-3` and `2 <= y <= H-3`

### 8.5 Output file (testbench)

The testbench does **not** need to write `(x,y)` to file — RTL still
maintains its internal coordinate pipeline to generate `result_valid`
correctly, but `rtl_output.hex` is simply a plain row-major stream (like
the input), since the output is still the full 512×512 size and the
border is automatically 0.

## 9. Repository Structure

```
image-dsp-benchmark/
│
├── README.md
│
├── data/
│   ├── original.png
│   ├── gray.hex
│   ├── noisy.hex
│   ├── median.hex
│   ├── gradient.hex
│   └── expected.hex
│
├── python/
│   ├── preprocess.py
│   ├── noise.py
│   ├── median.py
│   ├── sobel.py
│   ├── golden_model.py
│   ├── benchmark.py
│   └── verify.py
│
├── c/
│   ├── image_io.c / .h
│   ├── median.c / .h
│   ├── sobel.c / .h
│   ├── pipeline.c / .h
│   └── benchmark.c
│
├── rtl/
│   ├── image_dsp_top.v
│   ├── line_buffer.v
│   ├── window_3x3.v
│   ├── median_3x3.v
│   ├── sobel_3x3.v
│   ├── gradient_mag.v
│   └── threshold.v
│
├── tb/
│   └── tb_image_dsp_top.v
│
├── fpga/
│   ├── ebaz/
│   └── kr260/
│
└── results/
    ├── benchmark.csv
    └── plots/
```

## 10. Python Reference Implementation

| File | Input | Output | Content |
| --- | --- | --- | --- |
| `preprocess.py` | `original.png` | `gray.hex` | read image, grayscale, resize if needed, save as `.hex` |
| `noise.py` | `gray.hex` | `noisy.hex` | `salt_pepper()`, uses `seed`, `noise_probability` |
| `median.py` | `noisy.hex` | `median.hex` | 3×3 median, loop `range(1,H-1)`/`range(1,W-1)` |
| `sobel.py` | `median.hex` | `gradient.hex` | Gx, Gy, abs, magnitude, threshold; loop `range(2,H-2)`/`range(2,W-2)` |
| `golden_model.py` | `input.png`/`input.jpg` if present, else a synthesized test pattern | `expected.hex` + `.hex` files (see below) | full pipeline chained together — **official reference behavior** |
| `verify.py` | `expected.hex`, C output, RTL output | report | mismatch count, max error, first-mismatch coordinate |
| `benchmark.py` | — | timing | measures Median/Sobel/Total latency + FPS |

### 10.1 Running `golden_model.py` with a real image

By default `golden_model.py` synthesizes a test pattern. To run it against
a real photo instead:

1. Download any image (prefer one with sharp edges/detail so the Sobel
   output is visually meaningful).
2. Rename it `input.png` or `input.jpg`.
3. Place it in the `python/` directory, next to `golden_model.py`.
4. Run:
   ```bash
   cd python
   python golden_model.py
   ```

When `input.png`/`input.jpg` is present, the script loads it, converts to
grayscale, and resizes it to the configured `IMAGE_WIDTH` × `IMAGE_HEIGHT`
(512×512 by default) per §4 — it does **not** fall back to the synthesized
test pattern in that case.

### 10.2 Output files

Each run produces, in `python/` (or `data/`, depending on your configured
output path):

**Debug images** (for visual inspection):

| File | Content |
| --- | --- |
| `debug_gray.png` | grayscale-converted image |
| `debug_noisy.png` | image with 5% salt-and-pepper noise applied |
| `debug_median.png` | after the 3×3 median filter (noise removed) |
| `debug_expected.png` | final output — Sobel + threshold (white edges on black) |

**`.hex` files for the RTL testbench:**

`golden_model.py` writes each pipeline stage's buffer (`noisy.hex`,
`median.hex`, `gradient.hex`, `expected.hex`) as ASCII `.hex` — one
two-digit hex byte per line, 262,144 lines for a 512×512 image. These
are meant to be copied into `tb/` and loaded directly with:

```verilog
$readmemh("noisy.hex", memory_array);
```

so the testbench doesn't need any custom binary-file reader. See §13 for
how `tb_image_dsp_top.v` consumes these files during simulation.

`golden_model.py` pseudo-code (must follow the exact ranges):

```python
median = zeros((H, W), uint8)
for y in range(1, H-1):
    for x in range(1, W-1):
        window = noisy[y-1:y+2, x-1:x+2]
        median[y, x] = median9(window)

output = zeros((H, W), uint8)
for y in range(2, H-2):
    for x in range(2, W-2):
        # 3×3 window taken from median[y,x] — always guaranteed valid
        gx = ...
        gy = ...
        magnitude = abs(gx) + abs(gy)
        output[y, x] = 255 if magnitude >= 100 else 0
```

Final goal: **Python == C == RTL**.

## 11. C Implementation

Role: (1) CPU benchmark, (2) cross-check against Python, (3) runs on Zero
3W, (4) runs on the ARM cores of KR260/EBAZ.

| File | Content |
| --- | --- |
| `image_io.c/.h` | `load_hex()`, `save_hex()` — parses/writes ASCII `.hex` (one two-digit byte per line); no DSP processing |
| `median.c/.h` | `median_3x3()` — `uint8_t*` input/output |
| `sobel.c/.h` | `sobel()`, `gradient()`, `threshold()` — intermediate `int16_t gx, gy` |
| `pipeline.c/.h` | chains `median()` → `sobel()` → `gradient()` → `threshold()` |
| `benchmark.c` | measures median/sobel/total time + FPS; **excludes** image load/save from kernel latency (end-to-end can be reported separately) |

**Required**: C must use the exact same loop ranges as Python
(`1..H-2` for Median, `2..H-3` for Sobel) — do not infer a different
border on your own.

## 12. RTL Specification — Verilog-2001 only

All RTL uses **Verilog-2001**. Not allowed: SystemVerilog, `logic`,
`always_ff`, `always_comb`, `typedef`, `interface`. Allowed only:
`module`, `reg`, `wire`, `always`, `assign`, `parameter`.

### 12.1 `line_buffer.v`

Stores the two previous image rows, producing three synchronized rows for
the 3×3 window.

| Signal | Dir | Width | Note |
| --- | --- | --- | --- |
| `clk` | in | 1 | |
| `rst` | in | 1 | |
| `pixel_valid` | in | 1 | |
| `pixel_in` | in | [7:0] | |
| `line_minus2` | out | [7:0] | row N-2 |
| `line_minus1` | out | [7:0] | row N-1 |
| `current_pixel` | out | [7:0] | row N |
| `valid_out` | out | 1 | |

Parameter: `IMAGE_WIDTH`. Latency: 1 cycle. Synthesizes to
memory/registers depending on the tool. Use **2 separate instances**
(Line Buffer #1 before Median, Line Buffer #2 before Sobel — same module,
independent state).

### 12.2 `window_3x3.v`

| Signal | Dir | Width |
| --- | --- | --- |
| `line_minus2, line_minus1, current_pixel` | in | [7:0] each |
| `valid_in` | in | 1 |
| `p00 ... p22` | out | [7:0] × 9 |
| `window_valid` | out | 1 |
| `center_x, center_y` (optional, debug) | out | ints |

Latency: 0 cycles (combinational).

### 12.3 `median_3x3.v`

Input: `p00...p22`, `window_valid`. Output: `median_pixel[7:0]`,
`median_result_valid`, `median_stream_valid`. Implementation:
compare-swap network (9 pixels → sort → take the 5th element). Latency:
1 cycle. Fully synthesizable.

### 12.4 `sobel_3x3.v`

Input: 3×3 window of the **median-filtered** stream. Output: `gx`
(signed 12-bit), `gy` (signed 12-bit), `sobel_result_valid`. Uses signed
arithmetic, formulas per §3.4. Latency: 1 cycle.

### 12.5 `gradient_mag.v`

Input: `gx`, `gy`. Output: `magnitude` (unsigned 12-bit) = `abs(gx) +
abs(gy)`. Latency: 0 cycles.

### 12.6 `threshold.v`

Input: `magnitude`. Parameter: `THRESHOLD = 100`. Output:
`pixel_out[7:0]` = 255 or 0. Latency: 0 cycles.

### 12.7 `image_dsp_top.v`

Connects the full pipeline:

```
pixel_in → line_buffer#1 → window#1 → median_3x3
         → line_buffer#2 → window#2 → sobel_3x3 → gx,gy
         → gradient_mag → threshold → pixel_out
```

Minimal interface:

```verilog
input         clk;
input         rst;
input         pixel_valid;
input  [7:0]  pixel_in;
output        pixel_valid_out;
output [7:0]  pixel_out;
parameter IMAGE_WIDTH  = 512;
parameter IMAGE_HEIGHT = 512;
```

**No AXI in the core DSP for the first version** — the DSP core stays
standalone until simulation/synthesis PASS.

## 13. RTL Testbench & Verification

`tb_image_dsp_top.v` loads its input directly from the ASCII `.hex` file
generated by `golden_model.py` (§10.2) using `$readmemh` — no custom
file-reading logic is needed in the testbench:

```verilog
reg [7:0] noisy_mem [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];
reg [7:0] expected_mem [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];

initial begin
    $readmemh("noisy.hex", noisy_mem);
    $readmemh("expected.hex", expected_mem);
end
```

Data flow:

```
noisy.hex → $readmemh → pixel_in → RTL → pixel_out → compare against expected_mem
```

The testbench streams `noisy_mem` into `pixel_in` in row-major order
(§5), drives `pixel_valid`, and compares each `pixel_out` (when
`pixel_valid_out` is HIGH) against the corresponding entry in
`expected_mem`, reporting mismatch count, max error, and the coordinate
of the first mismatch (mirroring what `verify.py` reports for the
Python/C comparison).

```
                noisy.hex
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
     Python         C          RTL ($readmemh)
        │           │           │
        ▼           ▼           ▼
    expected      c_out       rtl_out
        │           │           │
        └───────────┼───────────┘
                     ▼
                  Compare
```

**PASS** when: total pixel count matches, mismatch count = 0, max error =
0, `Python == C == RTL`.

## 14. FPGA Architecture

**EBAZ4205 (Zynq-7010)**

```
┌─────────────────┐
│      ARM PS      │
│  C application   │
└────────┬─────────┘
         │ control/data
         ▼
┌─────────────────┐
│     FPGA PL      │
│  image_dsp_top   │
└─────────────────┘
```

**KR260 (Zynq UltraScale+ MPSoC)** — similar architecture, larger PS/PL.

Phase 1: standalone DSP core, no AXI. Once simulation/synthesis PASS,
build the AXI wrapper/integration (Phase 2).

## 15. Benchmark Cases

| Case | Board | Compute | Language | Resolution |
| --- | --- | --- | --- | --- |
| A | Zero 3W | CPU | Python | 512×512 |
| B | Zero 3W | CPU | C | 512×512 |
| C | EBAZ4205 | ARM CPU | C | 512×512 |
| D | KR260 | ARM CPU | C | 512×512 |
| E | EBAZ4205 | FPGA | Median+Sobel+Threshold | 512×512 |
| F | KR260 | FPGA | Median+Sobel+Threshold | 512×512 |

**Metrics**

- **CPU:** Median latency, Sobel latency, Total latency, FPS, CPU
  utilization, RAM
- **FPGA:** Kernel latency, End-to-end latency, FPS, LUT, FF, BRAM, DSP,
  Fmax

```
Kernel latency:     FPGA start → FPGA done
End-to-end latency: CPU → transfer input → FPGA → transfer output → CPU
```

**Benchmark fairness (must be identical across every case)**

Input image, resolution, noise, noise seed, median kernel 3×3, Sobel
kernel, threshold, datatype, border rule, output format — **all must be
the SAME**. Do not benchmark JPEG decoding or network transfer if the
goal is to compare the DSP kernel alone (end-to-end can be reported
separately if building a real system).

## 16. Definition of Done

**Algorithm**

- [ ] Python pipeline
- [ ] C pipeline
- [ ] Median 3×3
- [ ] Sobel 3×3
- [ ] |Gx|+|Gy|
- [ ] Threshold

**Verification**

- [ ] Python == C
- [ ] Python == RTL
- [ ] Intermediate output verified (median stage separately)
- [ ] Final output mismatch = 0
- [ ] Non-square test case passed

**RTL**

- [ ] Verilog-2001 only
- [ ] Synthesizable
- [ ] 2 line-buffer/window stages with correct valid region (510×510 → 508×508)
- [ ] Parameterized `IMAGE_WIDTH`/`IMAGE_HEIGHT`
- [ ] `stream_valid`/`result_valid` correctly separated at both stages
- [ ] Coordinate pipeline matches the latency budget (§8.2)

**FPGA**

- [ ] EBAZ synthesis
- [ ] KR260 synthesis
- [ ] LUT/FF/BRAM/DSP reported
- [ ] Fmax reported

**Phase 2**

- [ ] AXI integration
- [ ] ARM → FPGA
- [ ] FPGA → ARM
- [ ] Real hardware latency
- [ ] End-to-end benchmark

## 17. Suggested Implementation Order

```
Python Golden Model → C → each RTL primitive → each window
→ Median → Sobel → top → simulation → synthesis
```

Do not write `image_dsp_top.v` directly before each sub-module has
passed its own individual simulation.

---