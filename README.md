# Embedded DSP Image Processing Benchmark

[![Verilog](https://img.shields.io/badge/RTL-Verilog--2001-blue)](https://en.wikipedia.org/wiki/Verilog)
[![Verification](https://img.shields.io/badge/verification-Python%20%3D%3D%20C%20%3D%3D%20RTL-brightgreen)](#verification)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](#license)

A classical (non-AI, non-FFT, integer-only) image DSP pipeline — **salt-and-pepper
noise removal + Sobel edge detection** — implemented three times (Python golden
model, C, and synthesizable Verilog-2001 RTL) and benchmarked across three
embedded platforms: **Orange Pi Zero 3W**, **AMD Kria KR260**, and **EBAZ4205
(Zynq-7010)**.

The target verification flow is:

`Python == C == RTL` with mismatch = 0.

```text
Original RGB → Grayscale → Salt & Pepper Noise → 3x3 Median → Sobel 3x3
             → |Gx| + |Gy| → Threshold → Binary Edge Image
```

## Contents

- [Features](#features)
- [RTL Architecture](#rtl-architecture)
- [Repository Structure](#repository-structure)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Verification](#verification)
- [Benchmarking](#benchmarking)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Features

- Deterministic salt-and-pepper noise generation (fixed seed, reproducible across runs)
- 3×3 median filter (compare-swap sorting network) + 3×3 Sobel edge detector
- Fixed-point / integer-only math throughout — no floating point in RTL
- Golden-model-driven verification pipeline (`Python == C == RTL`)
- Parameterized RTL (`IMAGE_WIDTH`, `IMAGE_HEIGHT`), non-square image support
- CPU vs FPGA benchmarking across 3 boards (latency, FPS, LUT/FF/BRAM/DSP, Fmax)

## RTL Architecture

### Top-Level Interface

The RTL core is exposed through a compact streaming interface. Input pixels are
accepted with `i_valid`, while the processed pixel, output-valid flag, image
coordinates, and gradient magnitude are exposed on the output side.

![image_dsp_top top-level interface](docs/images/image_dsp_top_interface.png)

Main interface:

```text
Inputs
------
i_clk
i_rst_n
i_pixel[7:0]
i_valid

Outputs
-------
o_valid
o_pixel[7:0]
o_x[11:0]
o_y[11:0]
o_mag[11:0]
```

### Internal DSP Pipeline

`image_dsp_top.v` connects the line-buffer/window-generation logic to the
Median, Sobel, gradient-magnitude, and threshold stages.

![image_dsp_top internal DSP pipeline](docs/images/image_dsp_pipeline.png)

High-level RTL data path:

```text
i_pixel / i_valid
        |
        v
+----------------+
|  line_buffer   |
+----------------+
        |
        v
+----------------+
|   window_3x3   |
+----------------+
        |
        v
+----------------+
|   median_3x3   |
+----------------+
        |
        v
+----------------+
|   sobel_3x3    |
+----------------+
        |
        v
+----------------+
|  gradient_mag  |
+----------------+
        |
        v
+----------------+
|   threshold    |
+----------------+
        |
        v
o_pixel / o_valid / o_x / o_y / o_mag
```

The RTL keeps the image coordinates aligned with the streaming data so that
`o_valid` is asserted only inside the final valid Sobel region.

## Repository Structure

```text
image-dsp-benchmark/
├── README.md
├── docs/
│   ├── SPEC.md
│   └── images/
│       ├── image_dsp_top_interface.png
│       └── image_dsp_pipeline.png
├── data/                  # HEX golden vectors and input images
├── python/                # golden model + noise/median/sobel + verify/benchmark
├── c/                     # CPU implementation
├── rtl/                   # Verilog-2001 RTL modules
├── tb/                    # RTL testbenches
├── fpga/
│   ├── ebaz/              # EBAZ4205 synthesis project
│   └── kr260/             # KR260 synthesis project
└── results/               # benchmark.csv + plots
```

## Requirements

| Component | Tool |
| --- | --- |
| Golden model | Python 3.x, NumPy |
| CPU implementation | GCC / Clang (C99+) |
| RTL simulation | Icarus Verilog / Verilator / Vivado Simulator |
| FPGA synthesis | Vivado (EBAZ4205, KR260) |

## Quick Start

```bash
# 1. Generate golden reference data
cd python
python golden_model.py

# Example custom resolution
python golden_model.py --width 640 --height 480

# 2. Build and run the C implementation
cd ../c
make
./benchmark ../data/noisy.hex

# 3. Simulate the RTL and verify against the golden model
cd ../tb
make sim
python ../python/verify.py --expected ../data/expected.hex --actual rtl_result.hex
```

`golden_model.py` produces pipeline data as ASCII `.hex` files. The RTL
testbench loads the test vectors with Verilog's `$readmemh`.

### Using a real image

To run the golden model against a real photo instead of the built-in test
pattern:

1. Download any image, preferably one with sharp edges/detail.
2. Rename it `input.png` or `input.jpg`.
3. Place it in `python/`, next to `golden_model.py`.
4. Run `python golden_model.py`.

The script generates debug images such as:

```text
debug_gray.png
debug_noisy.png
debug_median.png
debug_gradient.png
debug_expected.png
```

See [`docs/SPEC.md`](docs/SPEC.md) for exact algorithm formulas, coordinate
convention, valid-region rules, and RTL module interfaces.

## Verification

Every implementation must pass:

- Python golden model == C output (mismatch = 0)
- Python golden model == RTL output (mismatch = 0)
- Non-square test case (e.g. 640×480) passes
- Intermediate median-stage output verified separately from final output
- Expected output count is `(W-4) × (H-4)` for the final Sobel valid region

Confirmed RTL baseline:

```text
W=512 H=512 GAPS=0 frames=1
outputs=258064 (expected 258064)
errors=0
PASS
```

## Benchmarking

| Case | Board | Compute | Language |
| --- | --- | --- | --- |
| A | Zero 3W | CPU | Python |
| B | Zero 3W | CPU | C |
| C | EBAZ4205 | ARM CPU | C |
| D | KR260 | ARM CPU | C |
| E | EBAZ4205 | FPGA | Median + Sobel + Threshold |
| F | KR260 | FPGA | Median + Sobel + Threshold |

Metrics:

- CPU: Median latency, Sobel latency, total DSP latency, FPS, CPU utilization, RAM
- FPGA: kernel latency, end-to-end latency, FPS, LUT, FF, BRAM, DSP, Fmax

Results are stored in:

- [`results/benchmark.csv`](results/benchmark.csv)
- [`results/plots/`](results/plots/)

## Documentation

- [`docs/SPEC.md`](docs/SPEC.md) — full technical specification:
  - algorithm
  - datatypes
  - coordinate convention
  - valid-region rules
  - RTL module specifications
  - latency budget
  - FPGA architecture
  - Definition of Done

## Contributing

Commit message rules, branch conventions, and module-development order are in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

This repository uses
[Conventional Commits](https://www.conventionalcommits.org/)
scoped to the touched module, for example:

```text
feat(rtl): add median_3x3.v compare-swap network
```

