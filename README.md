# Embedded DSP Image Processing Benchmark

[![Verilog](https://img.shields.io/badge/RTL-Verilog--2001-blue)]()
[![Verification](https://img.shields.io/badge/verification-Python%20%3D%3D%20C%20%3D%3D%20RTL-brightgreen)]()
[![License](https://img.shields.io/badge/license-MIT-lightgrey)]()

A classical (non-AI, non-FFT, integer-only) image DSP pipeline — **salt-and-pepper
noise removal + Sobel edge detection** — implemented three times (Python golden
model, C, and synthesizable Verilog-2001 RTL) and benchmarked across three
embedded platforms: **Orange Pi Zero 3W**, **AMD Kria KR260**, and **EBAZ4205
(Zynq-7010)**.

The three implementations are verified to be bit-exact:
`Python == C == RTL` (mismatch = 0).

```
Original RGB → Grayscale → Salt & Pepper Noise → 3x3 Median → Sobel 3x3
             → |Gx| + |Gy| → Threshold → Binary Edge Image
```

## Contents

- [Features](#features)
- [Repository structure](#repository-structure)
- [Requirements](#requirements)
- [Quick start](#quick-start)
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

## Repository Structure

```
image-dsp-benchmark/
├── README.md
├── docs/
│   └── SPEC.md            # full technical specification
├── data/                  # HEX golden vectors and input images
├── python/                # golden model + noise/median/sobel + verify/benchmark
├── c/                      # CPU implementation
├── rtl/                    # Verilog-2001 RTL modules
├── tb/                     # RTL testbenches
├── fpga/
│   ├── ebaz/                # EBAZ4205 synthesis project
│   └── kr260/                # KR260 synthesis project
└── results/                 # benchmark.csv + plots
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
# 1. Generate golden reference data (synthesized test pattern by default —
#    to use a real photo instead, see "Using a real image" below)
cd python
python golden_model.py

# 2. Build and run the C implementation
cd ../c
make
./benchmark ../data/noisy.hex

# 3. Simulate the RTL and verify against the golden model
cd ../tb
make sim
python ../python/verify.py --expected ../data/expected.hex --actual rtl_output.hex
```

`golden_model.py` produces all pipeline data as ASCII `.hex` files (one
two-digit hex byte per line). Both the C implementation and the RTL
testbench read `.hex` directly — the testbench loads it with Verilog's
`$readmemh`, so copy `noisy.hex` and `expected.hex` into `tb/` before
running `make sim`.

### Using a real image

To run the golden model against a real photo instead of the built-in test
pattern:

1. Download any image (prefer one with sharp edges/detail, for a more
   interesting Sobel result).
2. Rename it `input.png` or `input.jpg`.
3. Place it in `python/`, next to `golden_model.py`.
4. Run `python golden_model.py` — it detects the file, converts it to
   grayscale, and resizes it to 512×512 automatically.

This also produces `debug_gray.png`, `debug_noisy.png`,
`debug_median.png`, and `debug_expected.png` in `python/` so you can
visually inspect each pipeline stage. Full details in
[`docs/SPEC.md §10`](docs/SPEC.md#10-python-reference-implementation).

See [`docs/SPEC.md`](docs/SPEC.md) for exact algorithm formulas, coordinate
convention, valid-region rules, and RTL module interfaces.

## Verification

Every implementation must pass:

- Python golden model == C output (mismatch = 0)
- Python golden model == RTL output (mismatch = 0)
- Non-square test case (e.g. 640×480) passes
- Intermediate (median-stage) output verified separately from final output

## Benchmarking

| Case | Board | Compute | Language |
| --- | --- | --- | --- |
| A | Zero 3W | CPU | Python |
| B | Zero 3W | CPU | C |
| C | EBAZ4205 | ARM CPU | C |
| D | KR260 | ARM CPU | C |
| E | EBAZ4205 | FPGA | Median+Sobel+Threshold |
| F | KR260 | FPGA | Median+Sobel+Threshold |

Metrics: latency (kernel / end-to-end), FPS, CPU/RAM usage, LUT/FF/BRAM/DSP,
Fmax. Results are stored in [`results/benchmark.csv`](results/) and
[`results/plots/`](results/plots/).

## Documentation

- [`docs/SPEC.md`](docs/SPEC.md) — full technical specification (algorithm,
  datatypes, coordinate convention, valid-region rules, RTL module specs,
  latency budget, FPGA architecture, Definition of Done)

## Contributing

Commit message rules, branch conventions, and the module-development order
are in [`CONTRIBUTING.md`](CONTRIBUTING.md). In short: this repo uses
[Conventional Commits](https://www.conventionalcommits.org/) scoped to the
touched module, e.g. `feat(rtl): add median_3x3.v compare-swap network`.

## License

MIT (or your project's chosen license — update this section before publishing).