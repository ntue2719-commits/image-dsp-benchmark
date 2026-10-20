# Technical Specification — Phase 2 Structured DSP Accelerator

> This document defines the Phase 2 architecture of the Embedded DSP Image Processing Benchmark.
>
> Phase 1 — the standalone streaming DSP core — has been completed and verified:
>
> ```text
> Python Golden Model == RTL
> mismatch = 0
> PASS
> ```
>
> Phase 2 must preserve all Phase 1 algorithm, datatype, coordinate, border, and valid-region behavior.

---

# 1. Phase 2 Objective

Phase 2 converts the already-verified Phase 1 streaming DSP core into a structured hardware accelerator.

The architecture shall contain five main functional blocks:

```text
1. Arbiter
2. FSM Controller
3. Input Interface / Buffer
4. DSP Datapath
5. Output Interface / Buffer
```

Top-level hierarchy:

```text
image_dsp_accel_top
│
├── image_dsp_arbiter
├── image_dsp_fsm_ctrl
├── image_dsp_input
├── image_dsp_datapath
└── image_dsp_output
```

The design must remain:

```text
Verilog-2001
synthesizable
parameterized
deterministic
bit-exact with Phase 1
```

SystemVerilog constructs are not permitted in the RTL baseline.

---

# 2. Phase 1 Completion Contract

Phase 1 implements:

```text
input pixel stream
        |
        v
line_buffer #1
        |
        v
window_3x3 #1
        |
        v
median_3x3
        |
        v
line_buffer #2
        |
        v
window_3x3 #2
        |
        v
sobel_3x3
        |
        v
gradient_mag
        |
        v
threshold
        |
        v
output edge stream
```

The following behavior is frozen for Phase 2.

## 2.1 Median Filter

For:

```text
p00 p01 p02
p10 p11 p12
p20 p21 p22
```

the output is the fifth ordered value after sorting the nine pixels:

```text
median = sort(p00...p22)[4]
```

Valid median region:

```text
x in [1, W-2]
y in [1, H-2]

size = (W-2)*(H-2)
```

---

## 2.2 Sobel Filter

The Sobel stage consumes the median-filtered stream.

```text
Gx = -p00 + p02
     -2*p10 + 2*p12
     -p20 + p22

Gy = -p00 - 2*p01 - p02
     +p20 + 2*p21 + p22
```

Final valid region:

```text
x in [2, W-3]
y in [2, H-3]

size = (W-4)*(H-4)
```

For 512x512:

```text
valid outputs = 508*508 = 258064
```

---

## 2.3 Gradient Magnitude

Phase 1 uses the L1 approximation:

```text
M = |Gx| + |Gy|
```

Maximum:

```text
Mmax = 2040
```

Required magnitude width:

```text
12 bits unsigned
```

---

## 2.4 Threshold

Default threshold:

```text
THRESHOLD = 100
```

Output:

```text
M >= THRESHOLD -> 255
M <  THRESHOLD -> 0
```

---

# 3. Phase 2 Architectural Principle

Phase 2 separates:

```text
Control Plane
and
Data Plane
```

Control Plane:

```text
Arbiter
    |
    v
FSM Controller
```

Data Plane:

```text
Input Buffer
    |
    v
Verified DSP Datapath
    |
    v
Output Buffer
```

Complete architecture:

```text
                    Host / Future AXI Wrapper
                              |
             +----------------+----------------+
             |                                 |
             | command / status                | pixel data
             v                                 v
      +----------------+                +---------------+
      |    Arbiter     |                | Input Buffer  |
      +----------------+                +---------------+
             |                                 |
             | accepted commands               |
             v                                 v
      +----------------+             +----------------------+
      | FSM Controller |------------>| Verified DSP Datapath|
      +----------------+             +----------------------+
             |                                 |
             |                                 v
             |                         +---------------+
             +------------------------>| Output Buffer |
                                       +---------------+
                                              |
                                              v
                                             Host
```

---

# 4. Arbiter Specification

Module:

```text
image_dsp_arbiter.v
```

## 4.1 Role

The Arbiter is the highest-level control coordinator.

Its responsibilities are:

```text
- accept host commands
- reject illegal commands
- issue one-cycle command pulses
- report accelerator status
- control command ownership
- provide future AXI-Lite control endpoint
```

The Arbiter must not implement:

```text
- pixel arithmetic
- Median filtering
- Sobel filtering
- pipeline latency control
- line buffering
```

Conceptually:

```text
Arbiter = command policy / ownership
FSM     = time sequencing
Datapath = image processing
```

---

## 4.2 Arbiter Interface

```verilog
module image_dsp_arbiter (
    input  wire i_clk,
    input  wire i_rst,

    // Host-side commands
    input  wire i_cmd_start,
    input  wire i_cmd_clear_done,

    // FSM status
    input  wire i_fsm_busy,
    input  wire i_fsm_done,
    input  wire i_fsm_error,

    // Command pulses to FSM
    output reg  o_start_pulse,
    output reg  o_clear_done_pulse,

    // External status
    output wire o_busy,
    output wire o_done,
    output wire o_error
);
```

---

## 4.3 Arbiter Signal Meaning

| Signal | Dir | Width | Meaning |
|---|---|---:|---|
| `i_clk` | in | 1 | accelerator clock |
| `i_rst` | in | 1 | synchronous active-high reset |
| `i_cmd_start` | in | 1 | host requests a new frame operation |
| `i_cmd_clear_done` | in | 1 | host clears sticky DONE |
| `i_fsm_busy` | in | 1 | FSM reports an active operation |
| `i_fsm_done` | in | 1 | FSM reports frame completion |
| `i_fsm_error` | in | 1 | FSM reports protocol/state error |
| `o_start_pulse` | out | 1 | accepted one-cycle START pulse |
| `o_clear_done_pulse` | out | 1 | accepted one-cycle DONE-clear pulse |
| `o_busy` | out | 1 | accelerator BUSY status |
| `o_done` | out | 1 | accelerator DONE status |
| `o_error` | out | 1 | accelerator ERROR status |

---

## 4.4 Arbiter Command Rules

START is valid only when:

```text
BUSY = 0
FSM = IDLE
```

Legal case:

```text
i_cmd_start = 1
i_fsm_busy  = 0

=> o_start_pulse = 1 for one cycle
```

Illegal case:

```text
i_cmd_start = 1
i_fsm_busy  = 1
```

Required response:

```text
do not restart datapath
set ERROR
```

`CLEAR_DONE` must not generate a new operation.

---

# 5. FSM Controller Specification

Module:

```text
image_dsp_fsm_ctrl.v
```

## 5.1 Required States

```text
ST_IDLE
ST_LOAD
ST_WORK
ST_DRAIN
ST_DONE
ST_ERROR
```

Recommended encoding:

```verilog
localparam ST_IDLE  = 3'd0;
localparam ST_LOAD  = 3'd1;
localparam ST_WORK  = 3'd2;
localparam ST_DRAIN = 3'd3;
localparam ST_DONE  = 3'd4;
localparam ST_ERROR = 3'd5;
```

---

## 5.2 State Flow

```text
                  START
        +----------------------+
        |                      v
     +------+               +------+
     | IDLE |-------------->| LOAD |
     +------+               +------+
                                |
                                | input path ready
                                v
                            +------+
                            | WORK |
                            +------+
                                |
                                | last input accepted
                                v
                           +-------+
                           | DRAIN |
                           +-------+
                                |
                                | final output accepted
                                v
                            +------+
                            | DONE |
                            +------+
                                |
                                | CLEAR_DONE
                                v
                              IDLE
```

Any fatal protocol violation:

```text
any state -> ERROR
```

---

# 6. FSM State Meaning

## `IDLE`

```text
BUSY = 0
DONE = 0
input disabled
waiting for START
```

Transition:

```text
START -> LOAD
```

---

## `LOAD`

Purpose:

```text
prepare input path / buffer
clear frame counters
prepare datapath for new frame
```

LOAD is intentionally separated from WORK so the accelerator has a clean setup phase.

Transition:

```text
input path ready -> WORK
```

---

## `WORK`

Purpose:

```text
accept input pixels
feed verified Phase 1 datapath
count accepted input pixels
capture valid output pixels
```

Input transaction:

```text
input_fire = input_valid && input_ready
```

Output transaction:

```text
output_fire = output_valid && output_ready
```

Expected input count:

```text
N_INPUT = IMAGE_WIDTH * IMAGE_HEIGHT
```

When the last input pixel is accepted:

```text
WORK -> DRAIN
```

---

## `DRAIN`

Purpose:

```text
stop accepting new frame data
allow remaining pipeline results to propagate
capture all remaining valid output results
```

Expected output count:

```text
N_OUTPUT = (IMAGE_WIDTH-4)*(IMAGE_HEIGHT-4)
```

When the last valid output result has been accepted:

```text
DRAIN -> DONE
```

---

## `DONE`

Purpose:

```text
BUSY = 0
DONE = 1
```

DONE must be sticky.

It remains high until:

```text
CLEAR_DONE
or
reset
```

---

## `ERROR`

Purpose:

```text
freeze accelerator control
preserve error indication
prevent silent corrupted processing
```

Recovery:

```text
reset
```

An explicit future error-clear command may be added later.

---

# 7. FSM Interface

```verilog
module image_dsp_fsm_ctrl #(
    parameter IMAGE_WIDTH  = 512,
    parameter IMAGE_HEIGHT = 512
)(
    input  wire i_clk,
    input  wire i_rst,

    input  wire i_start_pulse,
    input  wire i_clear_done_pulse,

    input  wire i_input_ready,
    input  wire i_input_fire,
    input  wire i_output_fire,

    input  wire i_input_overflow,
    input  wire i_output_overflow,

    output reg  o_accept_input,
    output reg  o_enable_datapath,
    output reg  o_accept_output,

    output reg  o_busy,
    output reg  o_done,
    output reg  o_error
);
```

---

## 7.1 FSM Signal Meaning

| Signal | Dir | Width | Meaning |
|---|---|---:|---|
| `i_clk` | in | 1 | accelerator clock |
| `i_rst` | in | 1 | synchronous reset |
| `i_start_pulse` | in | 1 | accepted START from Arbiter |
| `i_clear_done_pulse` | in | 1 | accepted DONE clear |
| `i_input_ready` | in | 1 | input path is ready for frame processing |
| `i_input_fire` | in | 1 | one input pixel successfully transferred |
| `i_output_fire` | in | 1 | one output record successfully transferred |
| `i_input_overflow` | in | 1 | input buffering failure |
| `i_output_overflow` | in | 1 | output buffering failure |
| `o_accept_input` | out | 1 | enables input acceptance |
| `o_enable_datapath` | out | 1 | datapath operation is enabled |
| `o_accept_output` | out | 1 | output path capture/read enabled |
| `o_busy` | out | 1 | frame operation active |
| `o_done` | out | 1 | sticky frame completion |
| `o_error` | out | 1 | sticky fatal control/data error |

---

# 8. Input Interface / Buffer Specification

Module:

```text
image_dsp_input.v
```

Recommended implementation:

```text
small synchronous FIFO
```

The FIFO exists to decouple host timing from the verified streaming datapath.

It is not a full-frame memory.

---

## 8.1 Input Interface

```verilog
module image_dsp_input #(
    parameter FIFO_DEPTH = 16
)(
    input  wire       i_clk,
    input  wire       i_rst,

    // Host side
    input  wire       i_valid,
    input  wire [7:0] i_pixel,
    output wire       o_ready,

    // Datapath side
    output wire       o_valid,
    output wire [7:0] o_pixel,
    input  wire       i_ready,

    // Status
    output wire       o_empty,
    output wire       o_full,
    output wire       o_overflow
);
```

---

## 8.2 Input Signal Meaning

| Signal | Dir | Width | Meaning |
|---|---|---:|---|
| `i_clk` | in | 1 | clock |
| `i_rst` | in | 1 | reset |
| `i_valid` | in | 1 | host presents a valid input pixel |
| `i_pixel` | in | 8 | grayscale input pixel |
| `o_ready` | out | 1 | FIFO can accept another input pixel |
| `o_valid` | out | 1 | FIFO has a pixel for the datapath |
| `o_pixel` | out | 8 | next pixel in row-major order |
| `i_ready` | in | 1 | downstream is allowed to consume pixel |
| `o_empty` | out | 1 | FIFO contains no pixel |
| `o_full` | out | 1 | FIFO has no free entry |
| `o_overflow` | out | 1 | host attempted illegal write when full |

---

## 8.3 Input Handshake

Write:

```text
push = i_valid && o_ready
```

Read:

```text
pop = o_valid && i_ready
```

Required properties:

```text
- FIFO ordering preserved
- no duplicated pixels
- no lost pixels
- no pointer update without push/pop
```

---

# 9. DSP Datapath Specification

Module:

```text
image_dsp_datapath.v
```

This module wraps the verified Phase 1 core.

It must not reimplement the Median/Sobel algorithm.

---

## 9.1 Datapath Interface

```verilog
module image_dsp_datapath #(
    parameter IMAGE_WIDTH  = 512,
    parameter IMAGE_HEIGHT = 512,
    parameter THRESHOLD    = 100,
    parameter COORD_W      = 12
)(
    input  wire               i_clk,
    input  wire               i_rst,

    input  wire               i_valid,
    input  wire [7:0]         i_pixel,

    output wire               o_valid,
    output wire [7:0]         o_pixel,
    output wire [11:0]        o_mag,
    output wire [COORD_W-1:0] o_x,
    output wire [COORD_W-1:0] o_y
);
```

---

## 9.2 Datapath Signal Meaning

| Signal | Dir | Width | Meaning |
|---|---|---:|---|
| `i_clk` | in | 1 | DSP clock |
| `i_rst` | in | 1 | DSP reset |
| `i_valid` | in | 1 | input pixel valid |
| `i_pixel` | in | 8 | grayscale input pixel |
| `o_valid` | out | 1 | final DSP result valid |
| `o_pixel` | out | 8 | thresholded result, 0 or 255 |
| `o_mag` | out | 12 | `abs(Gx)+abs(Gy)` |
| `o_x` | out | `COORD_W` | output x coordinate |
| `o_y` | out | `COORD_W` | output y coordinate |

---

## 9.3 Datapath Wrapper Rule

Recommended implementation:

```verilog
image_dsp_top #(
    .IMAGE_WIDTH  (IMAGE_WIDTH),
    .IMAGE_HEIGHT (IMAGE_HEIGHT),
    .THRESHOLD    (THRESHOLD),
    .COORD_W      (COORD_W)
) u_phase1_verified_core (
    .i_clk   (i_clk),
    .i_rst   (i_rst),
    .i_valid (i_valid),
    .i_pixel (i_pixel),

    .o_valid (o_valid),
    .o_pixel (o_pixel),
    .o_x     (o_x),
    .o_y     (o_y),
    .o_mag   (o_mag)
);
```

If the exact Phase 1 top-level port names differ, the wrapper may adapt the names only.

The internal mathematical behavior must remain unchanged.

---

# 10. Output Interface / Buffer Specification

Module:

```text
image_dsp_output.v
```

Recommended implementation:

```text
small synchronous FIFO
```

One output FIFO entry is an atomic result record:

```text
{
    pixel,
    magnitude,
    x,
    y
}
```

---

## 10.1 Output Interface

```verilog
module image_dsp_output #(
    parameter FIFO_DEPTH = 16,
    parameter COORD_W    = 12
)(
    input  wire               i_clk,
    input  wire               i_rst,

    // Datapath side
    input  wire               i_valid,
    input  wire [7:0]         i_pixel,
    input  wire [11:0]        i_mag,
    input  wire [COORD_W-1:0] i_x,
    input  wire [COORD_W-1:0] i_y,
    output wire               o_ready,

    // Host side
    output wire               o_valid,
    output wire [7:0]         o_pixel,
    output wire [11:0]        o_mag,
    output wire [COORD_W-1:0] o_x,
    output wire [COORD_W-1:0] o_y,
    input  wire               i_ready,

    // Status
    output wire               o_empty,
    output wire               o_full,
    output wire               o_overflow
);
```

---

## 10.2 Output Signal Meaning

| Signal | Dir | Width | Meaning |
|---|---|---:|---|
| `i_clk` | in | 1 | clock |
| `i_rst` | in | 1 | reset |
| `i_valid` | in | 1 | datapath result is valid |
| `i_pixel` | in | 8 | binary edge result |
| `i_mag` | in | 12 | gradient magnitude |
| `i_x` | in | `COORD_W` | result X coordinate |
| `i_y` | in | `COORD_W` | result Y coordinate |
| `o_ready` | out | 1 | output FIFO has free space |
| `o_valid` | out | 1 | host-visible result exists |
| `o_pixel` | out | 8 | output binary edge |
| `o_mag` | out | 12 | corresponding magnitude |
| `o_x` | out | `COORD_W` | corresponding X coordinate |
| `o_y` | out | `COORD_W` | corresponding Y coordinate |
| `i_ready` | in | 1 | host consumes current result |
| `o_empty` | out | 1 | no result buffered |
| `o_full` | out | 1 | no free output entry |
| `o_overflow` | out | 1 | result arrived while buffer could not accept it |

---

# 11. Accelerator Top-Level Specification

Module:

```text
image_dsp_accel_top.v
```

---

## 11.1 Top-Level Interface

```verilog
module image_dsp_accel_top #(
    parameter IMAGE_WIDTH    = 512,
    parameter IMAGE_HEIGHT   = 512,
    parameter THRESHOLD      = 100,
    parameter COORD_W        = 12,
    parameter IN_FIFO_DEPTH  = 16,
    parameter OUT_FIFO_DEPTH = 16
)(
    input  wire               i_clk,
    input  wire               i_rst,

    // Control
    input  wire               i_start,
    input  wire               i_clear_done,

    // Input stream
    input  wire               i_in_valid,
    input  wire [7:0]         i_in_pixel,
    output wire               o_in_ready,

    // Output stream
    output wire               o_out_valid,
    output wire [7:0]         o_out_pixel,
    output wire [11:0]        o_out_mag,
    output wire [COORD_W-1:0] o_out_x,
    output wire [COORD_W-1:0] o_out_y,
    input  wire               i_out_ready,

    // Status
    output wire               o_busy,
    output wire               o_done,
    output wire               o_error
);
```

---

## 11.2 Top-Level Signal Meaning

| Signal | Dir | Width | Meaning |
|---|---|---:|---|
| `i_clk` | in | 1 | accelerator clock |
| `i_rst` | in | 1 | synchronous reset |
| `i_start` | in | 1 | host requests one frame operation |
| `i_clear_done` | in | 1 | host clears sticky DONE |
| `i_in_valid` | in | 1 | host input pixel valid |
| `i_in_pixel` | in | 8 | grayscale input pixel |
| `o_in_ready` | out | 1 | accelerator can accept input |
| `o_out_valid` | out | 1 | valid output record available |
| `o_out_pixel` | out | 8 | output edge pixel |
| `o_out_mag` | out | 12 | output gradient magnitude |
| `o_out_x` | out | `COORD_W` | output X coordinate |
| `o_out_y` | out | `COORD_W` | output Y coordinate |
| `i_out_ready` | in | 1 | host is ready to consume result |
| `o_busy` | out | 1 | frame operation active |
| `o_done` | out | 1 | frame operation complete |
| `o_error` | out | 1 | fatal command/dataflow error |

---

# 12. Internal Signal Contract

Recommended internal names:

```text
arb_start_pulse
arb_clear_done_pulse

fsm_accept_input
fsm_enable_datapath
fsm_accept_output

in_valid
in_pixel
in_ready
in_empty
in_full
in_overflow

dp_valid
dp_pixel
dp_mag
dp_x
dp_y

out_ready
out_valid
out_pixel
out_mag
out_x
out_y
out_empty
out_full
out_overflow

input_fire
output_fire
```

Definitions:

```text
input_fire  = in_valid  && datapath_input_accept
output_fire = out_valid && i_out_ready
```

Counters must update only on completed transactions.

---

# 13. Input and Output Count Rules

Input frame size:

```text
INPUT_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT
```

Final valid output count:

```text
OUTPUT_PIXELS = (IMAGE_WIDTH-4)*(IMAGE_HEIGHT-4)
```

Examples:

```text
64x64:
input  = 4096
output = 3600

512x512:
input  = 262144
output = 258064

640x480:
input  = 307200
output = 302736
```

The FSM must never infer frame completion only from time or latency.

Completion must be based on actual accepted transaction counts.

---

# 14. Backpressure Constraint

The verified Phase 1 core uses a valid-driven streaming architecture and does not currently expose a full ready/stall interface.

Therefore Phase 2 must not silently stall internal datapath state after a pixel has been accepted into the core.

Initial Phase 2 policy:

```text
- use input FIFO to absorb source gaps
- use output FIFO to absorb short sink stalls
- keep the verified datapath progressing normally
- treat output FIFO overflow as ERROR
```

Do not drop a result silently.

A future fully stallable datapath is allowed only as a separate revision and requires full Python-vs-RTL regression.

---

# 15. Error Conditions

At minimum, Phase 2 shall detect:

```text
1. START while BUSY
2. accepted input count > IMAGE_WIDTH*IMAGE_HEIGHT
3. accepted output count > (IMAGE_WIDTH-4)*(IMAGE_HEIGHT-4)
4. input FIFO overflow
5. output FIFO overflow
6. unexpected result after frame completion
7. DONE reached with incorrect frame counts
```

Required behavior:

```text
o_error = 1
FSM -> ST_ERROR
```

No silent recovery.

---

# 16. Reset Behavior

On `i_rst = 1`:

```text
FSM            -> IDLE
BUSY           -> 0
DONE           -> 0
ERROR          -> 0
input_count    -> 0
output_count   -> 0
input FIFO     -> empty
output FIFO    -> empty
```

The Phase 1 datapath must also receive reset.

---

# 17. Phase 2 Timing / Synthesis Rules

All Phase 2 modules shall be synchronous to:

```text
i_clk
```

No generated internal clock is permitted.

Use:

```text
clock enable
valid
ready
state
```

instead of gated clocks.

The following must remain synthesizable:

```text
Arbiter
FSM
FIFO control
datapath wrapper
status logic
frame counters
```

Simulation-only constructs such as:

```text
$fopen
$fdisplay
$readmemh for runtime hardware behavior
```

must remain in the testbench only.

`$readmemh` may still be used in simulation memories for verification.

---

# 18. Phase 2 Verification Plan

## 18.1 Arbiter Testbench

Verify:

```text
START in IDLE -> accepted
START while BUSY -> ERROR
CLEAR_DONE -> clears DONE
reset -> clean state
```

---

## 18.2 FSM Testbench

Verify:

```text
IDLE
-> LOAD
-> WORK
-> DRAIN
-> DONE
-> IDLE
```

Also verify:

```text
overflow -> ERROR
illegal count -> ERROR
```

---

## 18.3 Input Buffer Testbench

Verify:

```text
FIFO push
FIFO pop
empty
full
ordering
no loss
no duplication
overflow
```

---

## 18.4 Output Buffer Testbench

Verify:

```text
pixel/mag/x/y stay aligned
FIFO push/pop
backpressure
ordering
overflow
```

---

## 18.5 Datapath Regression

The Phase 2 datapath wrapper must still pass the existing Phase 1 test.

Required:

```text
Python == RTL
mismatch = 0
```

---

## 18.6 Full Accelerator Test

Sequence:

```text
1. reset
2. assert START
3. stream IMAGE_WIDTH*IMAGE_HEIGHT input pixels
4. allow datapath to process
5. capture all valid outputs
6. wait for DONE
7. compare against Python golden result
```

Required:

```text
input_count  = W*H
output_count = (W-4)*(H-4)
mismatch     = 0
ERROR        = 0
```

---

# 19. Phase 2 Definition of Done

## RTL

- [ ] `image_dsp_accel_top.v`
- [ ] `image_dsp_arbiter.v`
- [ ] `image_dsp_fsm_ctrl.v`
- [ ] `image_dsp_input.v`
- [ ] `image_dsp_datapath.v`
- [ ] `image_dsp_output.v`

## Control

- [ ] START accepted only when idle
- [ ] BUSY correct
- [ ] DONE sticky
- [ ] CLEAR_DONE correct
- [ ] ERROR sticky
- [ ] illegal START detected

## Data

- [ ] correct row-major input order
- [ ] correct output order
- [ ] no lost input pixel
- [ ] no duplicated input pixel
- [ ] no lost output record
- [ ] no duplicated output record
- [ ] pixel/magnitude/coordinate alignment preserved

## Verification

- [ ] Phase 1 regression still PASS
- [ ] Arbiter TB PASS
- [ ] FSM TB PASS
- [ ] Input Buffer TB PASS
- [ ] Output Buffer TB PASS
- [ ] Full accelerator TB PASS
- [ ] Python == Phase 2 RTL
- [ ] mismatch = 0

## Synthesis

- [ ] Verilog-2001 only
- [ ] no inferred gated clock
- [ ] no latch
- [ ] synthesis PASS
- [ ] implementation PASS
- [ ] timing constraint defined
- [ ] LUT / FF / BRAM / DSP reported
- [ ] Fmax reported

---

# 20. Phase 3 Preview — AXI Integration

Phase 2 intentionally defines a bus-independent accelerator.

Phase 3 shall wrap it with:

```text
AXI-Lite
for:
    START
    CLEAR_DONE
    STATUS
    configuration

AXI4-Stream / DMA
for:
    input image stream
    output image stream
```

Future architecture:

```text
                         ARM PS
                            |
            +---------------+---------------+
            |                               |
         AXI-Lite                        AXI DMA
            |                               |
            v                               v
      +-------------+                AXI4-Stream
      | AXI Control |                     |
      +-------------+                     |
            |                              |
            +---------------+--------------+
                            |
                            v
                +-----------------------+
                | Phase 2 Accelerator   |
                |                       |
                | Arbiter               |
                | FSM                   |
                | Input Buffer          |
                | Verified Datapath     |
                | Output Buffer         |
                +-----------------------+
```

AXI protocol logic must remain outside the verified DSP datapath.

---

# 21. Final Phase 2 Engineering Rule

The Phase 2 architecture must follow this ownership model:

```text
Arbiter
    = command authority

FSM Controller
    = execution sequencing authority

Input / Output
    = data transport and buffering

Datapath
    = verified image-processing computation
```

The Phase 1 DSP core is the algorithmic reference.

> Phase 2 must integrate the verified core without changing its mathematical behavior.
