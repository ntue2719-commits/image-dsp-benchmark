# Technical Specification — Phase 2 AXI Memory-Mapped Image DSP Accelerator

> **Status:** Phase 2 architecture specification  
> **Phase 1 status:** COMPLETE — `Python == RTL`, mismatch = 0  
> **Purpose:** Define a strict, implementation-ready contract for the AXI-controlled `dsp_image` accelerator.

---

# 1. Normative Language

The terms **MUST**, **MUST NOT**, **SHALL**, **SHALL NOT**, and **MAY** are normative.

If RTL behavior differs from this document, the RTL is considered incorrect until this specification is intentionally revised.

---

# 2. Phase 2 Hierarchy

Phase 2 has two levels.

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

System view:

```text
ARM PS
  |
AXI4-Lite
  |
  v
dsp_image_axi_wrapper
  |
  | internal request/response bus
  v
dsp_image_top
  |
  +--> Arbiter
  +--> FSM & CTRL
  +--> Input Memory
  +--> Datapath
  +--> Output Memory
```

**No DMA is part of Phase 2.**

---

# 3. Phase 1 Frozen Contract

`dsp_image_datapath` SHALL instantiate or wrap the already-verified Phase 1 streaming core.

Phase 1 algorithm:

```text
line_buffer #1
-> window_3x3 #1
-> median_3x3
-> line_buffer #2
-> window_3x3 #2
-> sobel_3x3
-> gradient_mag
-> threshold
```

The following behavior MUST remain unchanged.

Median valid region:

```text
x = 1 ... W-2
y = 1 ... H-2
count = (W-2)*(H-2)
```

Final Sobel valid region:

```text
x = 2 ... W-3
y = 2 ... H-3
count = (W-4)*(H-4)
```

Sobel:

```text
Gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22

Gy = -p00 - 2*p01 - p02
     +p20 + 2*p21 + p22
```

Magnitude:

```text
M = |Gx| + |Gy|
```

Threshold:

```text
THRESHOLD = 100
M >= THRESHOLD -> 255
M <  THRESHOLD -> 0
```

Any wrapper/refactor SHALL preserve:

```text
Python == RTL
mismatch = 0
```

---

# 4. Clock and Reset

All custom Phase 2 RTL SHALL use one clock:

```verilog
i_clk
```

Reset:

```verilog
i_rst
```

Rules:

```text
i_rst is active-high.
All custom control state is synchronous to i_clk.
No gated clock is allowed.
No generated internal clock is allowed.
```

The Vivado-generated AXI wrapper MAY use the Vivado naming style internally, but the custom core boundary SHALL normalize clock/reset to `i_clk` and `i_rst`.

---

# 5. AXI Wrapper / Core Boundary

The raw AXI channels SHALL terminate inside `dsp_image_axi_wrapper`.

`dsp_image_top` SHALL NOT depend directly on:

```text
AWVALID
AWREADY
WVALID
WREADY
BVALID
BREADY
ARVALID
ARREADY
RVALID
RREADY
```

The wrapper SHALL translate AXI operations into the following internal request/response interface.

## 5.1 `dsp_image_top` external interface

```verilog
module dsp_image_top #(
    parameter IMAGE_WIDTH  = 64,
    parameter IMAGE_HEIGHT = 64,
    parameter MEM_ADDR_W   = 12
)(
    input  wire        i_clk,
    input  wire        i_rst,

    // Write request
    input  wire        i_bus_wr_req,
    input  wire [31:0] i_bus_wr_addr,
    input  wire [31:0] i_bus_wr_data,
    input  wire [3:0]  i_bus_wr_strb,
    output wire        o_bus_wr_ack,
    output wire        o_bus_wr_err,

    // Read request
    input  wire        i_bus_rd_req,
    input  wire [31:0] i_bus_rd_addr,
    output wire        o_bus_rd_ack,
    output wire [31:0] o_bus_rd_data,
    output wire        o_bus_rd_err,

    // Optional interrupt/status outputs
    output wire        o_irq_done,
    output wire        o_irq_error
);
```

`MEM_ADDR_W` SHALL satisfy:

```text
2^MEM_ADDR_W >= max(N_INPUT, N_OUTPUT)
```

where:

```text
N_INPUT  = IMAGE_WIDTH * IMAGE_HEIGHT
N_OUTPUT = (IMAGE_WIDTH-4) * (IMAGE_HEIGHT-4)
```

---

# 6. Internal Bus Transaction Contract

A request remains active until acknowledged by `dsp_image_top`.

Write completion:

```text
write_fire = i_bus_wr_req && o_bus_wr_ack
```

Read completion:

```text
read_fire = i_bus_rd_req && o_bus_rd_ack
```

Rules:

- The wrapper SHALL hold request address/data stable until ACK.
- `o_bus_*_ack` SHALL pulse only when the operation has completed.
- `o_bus_*_err` SHALL be valid together with the corresponding ACK.
- Register access MAY complete faster than BRAM-backed access.
- Output Memory read latency SHALL be hidden behind the request/ACK contract.
- The AXI wrapper SHALL not assume combinational memory read data.

This rule is required because BRAM read paths are synchronous.

---

# 7. Baseline AXI Data Mapping

Phase 2 baseline uses a simple, verification-friendly format:

```text
one 8-bit pixel per 32-bit AXI word
```

For an input pixel write:

```text
pixel = i_bus_wr_data[7:0]
i_bus_wr_strb MUST equal 4'b0001
```

For an output pixel read:

```text
o_bus_rd_data[7:0]   = pixel
o_bus_rd_data[31:8]  = 0
```

Pixel `k` is addressed using a 4-byte stride:

```text
pixel_address = REGION_BASE + (k << 2)
```

A future packed-four-pixels-per-word optimization MAY be added, but it is not part of the Phase 2 baseline and SHALL require a specification revision.

---

# 8. Logical Address Map

The following are offsets inside the IP address space.

```text
0x0000_0000 : CTRL
0x0000_0004 : STATUS
0x0000_0008 : INFO_WIDTH      (read-only)
0x0000_000C : INFO_HEIGHT     (read-only)
0x0000_0010 : INFO_THRESHOLD  (read-only)

0x0010_0000 : INPUT_BASE
0x0110_0000 : OUTPUT_BASE
```

Input pixel `k`:

```text
INPUT_BASE + 4*k
```

Output valid-region pixel `k`:

```text
OUTPUT_BASE + 4*k
```

Output Memory stores only final valid-region pixels densely in raster order.

For output index `k`:

```text
x = 2 + (k % (IMAGE_WIDTH-4))
y = 2 + (k / (IMAGE_WIDTH-4))
```

This avoids undefined/stale border memory.

---

# 9. CTRL Register

`CTRL` is command-based, not a persistent mode register.

```text
bit 0 = LOAD
bit 1 = START
bit 2 = STOP
```

Rules:

- A command is generated only on an acknowledged CTRL write.
- Exactly one of bits `[2:0]` SHALL be set per command write.
- Multiple command bits set simultaneously SHALL return bus error and assert access error.
- `CTRL` reads MAY return zero.

Legal state:

```text
LOAD  only in IDLE
START only in LOAD
STOP  only in READ
```

---

# 10. STATUS Register

Recommended mapping:

```text
bit 0 = IDLE
bit 1 = LOAD
bit 2 = EXEC
bit 3 = READ
bit 4 = BUSY
bit 5 = DONE
bit 6 = ERROR
bits 31:7 = 0
```

Definitions:

```text
BUSY = state is LOAD or EXEC or READ
DONE = state is READ
ERROR = state is ERROR
```

STATUS reads SHALL be legal in every state.

---

# 11. Core Control Hierarchy

The control hierarchy SHALL be interpreted exactly as follows.

```text
FSM
    = defines WHEN an operation/access is legal

Arbiter
    = decodes host requests and ENFORCES the FSM permissions

Datapath
    = performs internal memory access during EXEC

Memory
    = passive storage; it does not make policy decisions
```

This ownership rule is normative.

---

# 12. `dsp_image_fsm_ctrl`

## 12.1 Interface

```verilog
module dsp_image_fsm_ctrl (
    input  wire       i_clk,
    input  wire       i_rst,

    // Commands from Arbiter
    input  wire       i_load_cmd,
    input  wire       i_start_cmd,
    input  wire       i_stop_cmd,
    input  wire       i_access_error,

    // Datapath feedback
    input  wire       i_datapath_done,
    input  wire       i_datapath_error,

    // State / permission outputs
    output reg  [2:0] o_state,
    output wire       o_allow_input_write,
    output wire       o_allow_output_read,

    // Datapath control
    output reg        o_datapath_start,

    // Status
    output wire       o_busy,
    output wire       o_done,
    output wire       o_error
);
```

## 12.2 States

```verilog
ST_IDLE  = 3'd0;
ST_LOAD  = 3'd1;
ST_EXEC  = 3'd2;
ST_READ  = 3'd3;
ST_ERROR = 3'd4;
```

## 12.3 State transitions

```text
IDLE --LOAD--> LOAD
LOAD --START--> EXEC
EXEC --datapath_done--> READ
READ --STOP--> IDLE

Any state --access_error/datapath_error--> ERROR
ERROR --reset--> IDLE
```

## 12.4 Permission outputs

```text
o_allow_input_write = 1 only in LOAD
o_allow_output_read = 1 only in READ
```

## 12.5 Datapath start

`o_datapath_start` SHALL be a one-cycle pulse on the accepted transition:

```text
LOAD -> EXEC
```

The datapath SHALL then run autonomously until `i_datapath_done`.

---

# 13. `dsp_image_arbiter`

## 13.1 Responsibility

The Arbiter SHALL:

```text
- decode CTRL/STATUS/INFO/Input/Output addresses
- generate LOAD/START/STOP commands
- gate host Input Memory writes using FSM permission
- gate host Output Memory reads using FSM permission
- route register/status read data
- route Output Memory read data
- report illegal host transactions
- generate bus ACK/ERR responses
```

The Arbiter SHALL NOT:

```text
- sequence Median/Sobel cycles
- generate datapath pixel addresses during EXEC
- write Output Memory during EXEC
- read Input Memory during EXEC
```

Those EXEC-side operations belong to the Datapath.

## 13.2 Interface

```verilog
module dsp_image_arbiter #(
    parameter MEM_ADDR_W = 12
)(
    input  wire                    i_clk,
    input  wire                    i_rst,

    // Internal bus from AXI wrapper
    input  wire                    i_bus_wr_req,
    input  wire [31:0]             i_bus_wr_addr,
    input  wire [31:0]             i_bus_wr_data,
    input  wire [3:0]              i_bus_wr_strb,
    output reg                     o_bus_wr_ack,
    output reg                     o_bus_wr_err,

    input  wire                    i_bus_rd_req,
    input  wire [31:0]             i_bus_rd_addr,
    output reg                     o_bus_rd_ack,
    output reg  [31:0]             o_bus_rd_data,
    output reg                     o_bus_rd_err,

    // FSM state/permissions/status
    input  wire [2:0]              i_fsm_state,
    input  wire                    i_allow_input_write,
    input  wire                    i_allow_output_read,
    input  wire                    i_fsm_busy,
    input  wire                    i_fsm_done,
    input  wire                    i_fsm_error,

    // Commands / access error to FSM
    output reg                     o_load_cmd,
    output reg                     o_start_cmd,
    output reg                     o_stop_cmd,
    output reg                     o_access_error,

    // Host-side Input Memory write port
    output reg                     o_in_host_we,
    output reg  [MEM_ADDR_W-1:0]   o_in_host_waddr,
    output reg  [7:0]              o_in_host_wdata,

    // Host-side Output Memory read port
    output reg                     o_out_host_re,
    output reg  [MEM_ADDR_W-1:0]   o_out_host_raddr,
    input  wire [7:0]              i_out_host_rdata,
    input  wire                    i_out_host_rvalid
);
```

---

# 14. Arbiter Access Policy

## 14.1 Always legal

```text
STATUS read
INFO_WIDTH read
INFO_HEIGHT read
INFO_THRESHOLD read
```

## 14.2 IDLE

Legal:

```text
CTRL.LOAD
```

Illegal:

```text
Input Memory write
Output Memory read
CTRL.START
CTRL.STOP
```

## 14.3 LOAD

Legal:

```text
Input Memory write
CTRL.START
STATUS/INFO read
```

Illegal:

```text
Output Memory read
CTRL.LOAD
CTRL.STOP
```

## 14.4 EXEC

Legal:

```text
STATUS/INFO read
```

Illegal host data access:

```text
Input Memory write
Output Memory read
LOAD/START/STOP
```

## 14.5 READ

Legal:

```text
Output Memory read
CTRL.STOP
STATUS/INFO read
```

Illegal:

```text
Input Memory write
CTRL.LOAD
CTRL.START
```

An illegal transaction SHALL:

```text
ACK the request
assert corresponding bus ERR
pulse o_access_error
```

and the FSM SHALL enter `ST_ERROR`.

---

# 15. Input Memory

Module:

```text
dsp_image_input_memory.v
```

The memory SHALL expose two logical ports:

```text
Port A: host write port from Arbiter
Port B: datapath read port
```

## 15.1 Interface

```verilog
module dsp_image_input_memory #(
    parameter MEM_ADDR_W = 12
)(
    input  wire                    i_clk,

    // Host write port
    input  wire                    i_host_we,
    input  wire [MEM_ADDR_W-1:0]   i_host_waddr,
    input  wire [7:0]              i_host_wdata,

    // Datapath read port
    input  wire                    i_dp_re,
    input  wire [MEM_ADDR_W-1:0]   i_dp_raddr,
    output reg  [7:0]              o_dp_rdata,
    output reg                     o_dp_rvalid
);
```

## 15.2 Ownership

```text
LOAD:
Arbiter/host may write Port A.
Datapath read MUST be inactive.

EXEC:
Host writes MUST be blocked by Arbiter.
Datapath may read Port B.

IDLE/READ/ERROR:
No Input Memory transaction is required.
```

BRAM-style datapath read is synchronous:

```text
i_dp_re at cycle N
-> o_dp_rvalid/o_dp_rdata at cycle N+1
```

---

# 16. Datapath Wrapper

Module:

```text
dsp_image_datapath.v
```

## 16.1 Responsibility

The Datapath SHALL:

```text
1. accept one-cycle i_start
2. reset internal frame counters for the new execution
3. request Input Memory pixels in row-major order
4. account for Input Memory read latency
5. feed Phase 1 i_valid/i_pixel
6. capture Phase 1 o_valid/o_pixel/o_x/o_y
7. write only final valid-region pixels to Output Memory
8. maintain input/output counts
9. assert o_done after the final output write
```

## 16.2 Interface

```verilog
module dsp_image_datapath #(
    parameter IMAGE_WIDTH  = 64,
    parameter IMAGE_HEIGHT = 64,
    parameter MEM_ADDR_W   = 12
)(
    input  wire                    i_clk,
    input  wire                    i_rst,
    input  wire                    i_start,

    // Input Memory read
    output reg                     o_in_re,
    output reg  [MEM_ADDR_W-1:0]   o_in_raddr,
    input  wire [7:0]              i_in_rdata,
    input  wire                    i_in_rvalid,

    // Output Memory write
    output reg                     o_out_we,
    output reg  [MEM_ADDR_W-1:0]   o_out_waddr,
    output reg  [7:0]              o_out_wdata,

    // Status
    output reg                     o_busy,
    output reg                     o_done,
    output reg                     o_error
);
```

## 16.3 Input count

```text
N_INPUT = IMAGE_WIDTH * IMAGE_HEIGHT
```

Input count SHALL advance when a memory-read response is actually fed into Phase 1:

```text
phase1_input_fire = i_in_rvalid
```

## 16.4 Output count

```text
N_OUTPUT = (IMAGE_WIDTH-4)*(IMAGE_HEIGHT-4)
```

Output count SHALL advance only when Phase 1 final `o_valid` causes an Output Memory write.

## 16.5 Output addressing

Output Memory stores valid results densely:

```text
o_out_waddr = output_count
```

This is independent of full-frame `x/y`.

The full-frame coordinate corresponding to output index `k` is:

```text
x = 2 + (k % (IMAGE_WIDTH-4))
y = 2 + (k / (IMAGE_WIDTH-4))
```

## 16.6 Completion

`o_done` SHALL pulse/assert only after the final valid result has been written:

```text
output_count == N_OUTPUT
```

The last input request by itself SHALL NOT imply completion.

---

# 17. Output Memory

Module:

```text
dsp_image_output_memory.v
```

The memory SHALL expose two logical ports:

```text
Port A: datapath write port
Port B: host read port through Arbiter
```

## 17.1 Interface

```verilog
module dsp_image_output_memory #(
    parameter MEM_ADDR_W = 12
)(
    input  wire                    i_clk,

    // Datapath write port
    input  wire                    i_dp_we,
    input  wire [MEM_ADDR_W-1:0]   i_dp_waddr,
    input  wire [7:0]              i_dp_wdata,

    // Host read port
    input  wire                    i_host_re,
    input  wire [MEM_ADDR_W-1:0]   i_host_raddr,
    output reg  [7:0]              o_host_rdata,
    output reg                     o_host_rvalid
);
```

## 17.2 Ownership

```text
EXEC:
Datapath may write Port A.
Host reads MUST be blocked by Arbiter.

READ:
Datapath write MUST be inactive.
Arbiter/host may read Port B.

IDLE/LOAD/ERROR:
No Output Memory transaction is required.
```

Host read is synchronous:

```text
i_host_re at cycle N
-> o_host_rvalid/o_host_rdata at cycle N+1
```

The Arbiter SHALL wait for `o_host_rvalid` before acknowledging the bus read.

---

# 18. Exact Memory Control Relationships

This section is normative and removes ambiguity.

## 18.1 Input Memory

```text
AXI Wrapper
    |
    v
Arbiter
    |
    | o_in_host_we
    | o_in_host_waddr
    | o_in_host_wdata
    v
Input Memory
    ^
    |
    | o_in_re / o_in_raddr
    | i_in_rdata / i_in_rvalid
    |
Datapath
```

FSM relationship:

```text
FSM o_allow_input_write
    -> Arbiter
    -> gates host write permission
```

The FSM does not carry pixel data.

## 18.2 Output Memory

```text
Datapath
    |
    | o_out_we
    | o_out_waddr
    | o_out_wdata
    v
Output Memory
    |
    | o_host_rdata
    | o_host_rvalid
    v
Arbiter
    |
    v
AXI Wrapper
```

FSM relationship:

```text
FSM o_allow_output_read
    -> Arbiter
    -> gates host read permission
```

The Arbiter does not generate EXEC-side output writes.

---

# 19. `dsp_image_top` Internal Connections

The top module SHALL connect signals exactly by role:

```text
Arbiter -> FSM:
load_cmd
start_cmd
stop_cmd
access_error

FSM -> Arbiter:
state
allow_input_write
allow_output_read
busy
done
error

FSM -> Datapath:
datapath_start

Datapath -> FSM:
datapath_done
datapath_error

Arbiter -> Input Memory:
host_we
host_waddr
host_wdata

Datapath -> Input Memory:
dp_re
dp_raddr

Input Memory -> Datapath:
dp_rdata
dp_rvalid

Datapath -> Output Memory:
dp_we
dp_waddr
dp_wdata

Arbiter -> Output Memory:
host_re
host_raddr

Output Memory -> Arbiter:
host_rdata
host_rvalid
```

No other block SHALL bypass the ownership rules above.

---

# 20. Reset Behavior

On `i_rst`:

```text
FSM -> IDLE
all command pulses -> 0
access error -> 0
datapath busy/done/error -> 0
datapath counters -> 0
pending bus transaction state -> idle
```

Memory contents do not need to be cleared because:

```text
Input Memory is fully rewritten before START.
Output Memory exposes only entries written during the current EXEC.
```

Software SHALL read exactly `N_OUTPUT` valid results after successful completion.

---

# 21. Resource Constraint

The architecture uses internal BRAM-backed frame buffers.

A 512x512 8-bit input frame requires:

```text
262144 bytes
```

A dense 508x508 8-bit output requires:

```text
258064 bytes
```

Therefore a dual-buffer full 512x512 implementation SHALL NOT be assumed to fit on every target.

Requirements:

- `IMAGE_WIDTH`, `IMAGE_HEIGHT`, and memory depths SHALL be parameterized.
- The chosen hardware frame size SHALL fit the actual BRAM budget.
- EBAZ4205 hardware bring-up MAY use a smaller resolution.
- If full 512x512 on a small device becomes mandatory, the architecture SHALL be revised to use external memory, tiling, memory reuse, or a streaming scheme.

This resource rule does not change the Phase 1 512x512 algorithmic reference.

---

# 22. Verification Plan

Verification order SHALL be:

```text
1. Input Memory TB
2. Output Memory TB
3. Datapath Wrapper TB
4. FSM TB
5. Arbiter TB
6. dsp_image_top TB without AXI
7. AXI wrapper TB
8. synthesis
9. implementation
10. ARM software test
```

## 22.1 Memory TB

Verify:

```text
synchronous read latency
address ordering
write/read correctness
rvalid behavior
```

## 22.2 Datapath Wrapper TB

Verify:

```text
Input Memory -> Phase 1 stream
row-major ordering
exact input count
exact output count
dense output addressing
datapath_done timing
Python == output
```

## 22.3 FSM TB

Verify every legal transition and every illegal-command path.

## 22.4 Arbiter TB

Verify:

```text
address decode
CTRL command legality
STATUS reads in every state
Input writes only in LOAD
Output reads only in READ
bus ACK/ERR timing
Output Memory read wait for rvalid
```

## 22.5 `dsp_image_top` TB

Required sequence:

```text
reset
LOAD
write N_INPUT pixels
START
wait until READ/DONE
read N_OUTPUT pixels
STOP
compare with Python
```

Pass:

```text
mismatch = 0
ERROR = 0
```

## 22.6 AXI Wrapper TB

Verify the Vivado AXI wrapper correctly translates AXI transactions into the internal request/ACK interface.

---

# 23. Synthesis / Implementation Rules

Custom RTL SHALL remain:

```text
Verilog-2001
synthesizable
single-clock
```

Custom synthesizable RTL SHALL NOT use:

```text
$fopen
$fdisplay
testbench-only delays
gated clocks
generated clocks
SystemVerilog-only constructs
```

Required reports:

```text
synthesis PASS
implementation PASS
LUT
FF
BRAM
DSP
timing
Fmax
```

---

# 24. Definition of Done

## Core RTL

- [ ] `dsp_image_input_memory.v`
- [ ] `dsp_image_output_memory.v`
- [ ] `dsp_image_datapath.v`
- [ ] `dsp_image_fsm_ctrl.v`
- [ ] `dsp_image_arbiter.v`
- [ ] `dsp_image_top.v`

## Core Verification

- [ ] memory TBs PASS
- [ ] datapath wrapper TB PASS
- [ ] FSM TB PASS
- [ ] Arbiter TB PASS
- [ ] `dsp_image_top` TB PASS
- [ ] Python == `dsp_image_top`
- [ ] mismatch = 0

## AXI

- [ ] Vivado AXI4-Lite wrapper generated
- [ ] request/ACK bridge implemented
- [ ] AXI write path PASS
- [ ] AXI read path PASS
- [ ] CTRL/STATUS PASS
- [ ] Input/Output region access PASS

## FPGA

- [ ] synthesis PASS
- [ ] implementation PASS
- [ ] timing PASS
- [ ] utilization reported
- [ ] ARM can LOAD input
- [ ] ARM can START processing
- [ ] ARM can poll STATUS
- [ ] ARM can READ output
- [ ] ARM can STOP/return core to IDLE

---

# 25. Final Engineering Rule

```text
AXI wrapper
    = protocol boundary

FSM
    = legal-time / state authority

Arbiter
    = host transaction decode, routing, and enforcement

Datapath
    = EXEC-side memory user and image computation

Memories
    = passive storage
```

> Verify `dsp_image_top` without AXI first. Only after the core is correct shall it be wrapped by the Vivado-generated AXI4-Lite interface.
