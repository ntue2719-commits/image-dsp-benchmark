# Embedded DSP Image Processing Benchmark

[![RTL](https://img.shields.io/badge/RTL-Verilog--2001-blue)](https://en.wikipedia.org/wiki/Verilog)
[![Phase 1](https://img.shields.io/badge/Phase%201-PASS-brightgreen)](#current-status)
[![Phase 2](https://img.shields.io/badge/Phase%202-AXI%20Accelerator-orange)](#phase-2--axi-memory-mapped-accelerator)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](#license)

A classical integer-only image DSP project for **salt-and-pepper noise removal and Sobel edge detection**, implemented with a Python golden model, CPU C code, and synthesizable Verilog-2001 RTL.

Target platforms:

- **Orange Pi Zero 3W** — CPU baseline and web demo
- **EBAZ4205 / Zynq-7010** — ARM PS + FPGA PL
- **AMD Kria KR260** — ARM PS + FPGA PL

Final verification target:

```text
Python == C == RTL
mismatch = 0
```

Current verified RTL status:

```text
Python == RTL
mismatch = 0
PASS
```

---

## DSP Pipeline

```text
RGB Image
   |
   v
Grayscale
   |
   v
Salt & Pepper Noise
   |
   v
Median 3x3
   |
   v
Sobel 3x3
   |
   v
|Gx| + |Gy|
   |
   v
Threshold
   |
   v
Binary Edge Image
```

---

## Current Status

### Phase 1 — Verified Streaming DSP Core

**Status: COMPLETE**

Confirmed baseline:

```text
W=512 H=512
outputs=258064
expected=258064
errors=0
PASS
```

The verified Phase 1 datapath is frozen as the compute reference:

```text
image_dsp_top
│
├── line_buffer #1
├── window_3x3 #1
├── median_3x3
├── line_buffer #2
├── window_3x3 #2
├── sobel_3x3
├── gradient_mag
└── threshold
```

Phase 2 may wrap this core but must not silently change its algorithm, coordinate convention, border behavior, valid-region behavior, or output ordering.

---

# Phase 2 — AXI Memory-Mapped Accelerator

**Status: CURRENT**

Phase 2 contains two clear hierarchy levels:

```text
dsp_image_axi_wrapper
│
├── Vivado-generated AXI4-Lite slave logic
│
└── dsp_image_top
    ├── dsp_image_arbiter
    ├── dsp_image_fsm_ctrl
    ├── dsp_image_input_memory
    ├── dsp_image_datapath
    └── dsp_image_output_memory
```

The AXI wrapper handles AXI protocol behavior. `dsp_image_top` contains the complete custom accelerator.

### Control Ownership

```text
FSM
    = defines when an access/operation is legal

Arbiter
    = decodes and routes host transactions
      and enforces FSM permissions

Datapath
    = reads Input Memory and writes Output Memory during EXEC

Memories
    = passive storage
```

### State Flow

```text
IDLE
  |
  | LOAD
  v
LOAD
  |
  | START
  v
EXEC
  |
  | datapath_done
  v
READ
  |
  | STOP
  v
IDLE
```

### Memory Ownership

```text
LOAD:
AXI -> Arbiter -> Input Memory write

EXEC:
Datapath -> Input Memory read
Datapath -> Output Memory write

READ:
Output Memory -> Arbiter -> AXI read
```

Detailed module interfaces, exact signal names, bus handshakes, memory ownership rules, error rules, and verification requirements are defined in:

[`docs/SPEC_PHASE2.md`](docs/SPEC_PHASE2.md)

---

## RTL Architecture

### Phase 1 Top-Level Interface

```text
Inputs
------
i_clk
i_rst
i_valid
i_pixel[7:0]

Outputs
-------
o_valid
o_pixel[7:0]
o_x[11:0]
o_y[11:0]
o_mag[11:0]
```

![image_dsp_top top-level interface](docs/images/image_dsp_top_interface.png)

### Internal DSP Pipeline

![image_dsp_top internal DSP pipeline](docs/images/image_dsp_pipeline.png)

Coordinates and valid timing remain aligned through the complete streaming datapath.

---

## Repository Structure

```text
image-dsp-benchmark/
│
├── README.md
├── PROJECT_CONTEXT.md
│
├── docs/
│   ├── SPEC_PHASE1.md
│   ├── SPEC_PHASE2.md
│   └── images/
│
├── python/
├── c/
├── rtl/
├── tb/
├── fpga/
│   ├── ebaz/
│   └── kr260/
└── results/
```

| Folder | Purpose |
| --- | --- |
| `docs/` | Technical specifications and architecture documentation |
| `docs/images/` | Block diagrams and RTL schematics |
| `python/` | Golden model, reference DSP, verification and HEX/PNG utilities |
| `c/` | CPU DSP implementation and benchmark |
| `rtl/` | Synthesizable Verilog-2001 RTL |
| `tb/` | RTL simulation and regression testbenches |
| `fpga/` | Board-specific Vivado integration and implementation |
| `results/` | Golden vectors, RTL outputs, images and benchmark results |

Python usage is documented in [`python/README.md`](python/README.md).

---

## Verification

Current confirmed result:

```text
Python == RTL
mismatch = 0
PASS
```

Phase 2 must independently pass:

```text
Python == dsp_image_top
mismatch = 0
```

and after AXI wrapping:

```text
Python == AXI-controlled Phase 2 RTL
mismatch = 0
```

Final Sobel valid-output count:

```text
(W - 4) * (H - 4)
```

| Resolution | Valid outputs |
| --- | ---: |
| 64x64 | 3600 |
| 512x512 | 258064 |
| 640x480 | 302736 |

---

## Resource Note

Phase 2 uses BRAM-backed Input/Output Memory. A full 512x512 8-bit input frame plus a full-size 8-bit output buffer is too large to assume portable across all targets, especially Zynq-7010.

Therefore:

- memory depth is parameterized;
- simulation may use any supported resolution;
- hardware frame size must fit the target BRAM budget;
- full 512x512 storage on a small target may require external memory, tiling, memory reuse, or a later streaming architecture.

The Phase 1 512x512 verification result remains the algorithmic reference.

---

## Benchmark Targets

| Case | Board | Compute | Implementation |
| --- | --- | --- | --- |
| A | Orange Pi Zero 3W | CPU | Python |
| B | Orange Pi Zero 3W | CPU | C |
| C | EBAZ4205 | ARM PS | C |
| D | KR260 | ARM PS | C |
| E | EBAZ4205 | FPGA PL | RTL Accelerator |
| F | KR260 | FPGA PL | RTL Accelerator |

FPGA metrics:

- kernel latency
- end-to-end latency
- FPS
- LUT
- FF
- BRAM
- DSP
- Fmax

---

## Development Roadmap

```text
Phase 1
Verified DSP Core
[DONE]

    |
    v

Phase 2
dsp_image_top + Vivado AXI4-Lite Wrapper
[CURRENT]

    |
    v

Phase 3
Hardware Bring-up / ARM Software Integration

    |
    v

Phase 4
CPU vs FPGA Benchmark

    |
    v

Phase 5
Web Demonstration
```

---

## Documentation

- [`docs/SPEC_PHASE1.md`](docs/SPEC_PHASE1.md) — verified DSP algorithm/RTL contract
- [`docs/SPEC_PHASE2.md`](docs/SPEC_PHASE2.md) — strict Phase 2 accelerator contract
- [`python/README.md`](python/README.md) — Python and verification commands
- [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) — project handoff context

---

## License

MIT License.
