# Software — KR260 AXI MMIO Control and Debug

This directory contains the userspace software used to control and debug the Image DSP accelerator on the **AMD Kria KR260**.

Current hardware/software context:

```text
Board       : AMD Kria KR260 / K26 Zynq UltraScale+ MPSoC
Vivado      : 2022.2
OS          : Ubuntu Linux on ARM PS
Accelerator : AXI4-Lite memory-mapped Image DSP
Base addr   : 0xA0000000
HW frame    : 64x64
Threshold   : 100
```

> The current KR260 design has working PS-PL AXI communication, but the FPGA output is **not yet bit-exact** on real hardware. Current observed results are 2 mismatches on one frame and 4 mismatches on a repeated frame out of 3600 valid outputs.

---

# Directory Structure

```text
software/
│
├── README.md
│
└── kr260/
    ├── main.c
    └── load_bitstream.sh
```

Files:

| File | Purpose |
|---|---|
| `kr260/main.c` | Linux userspace AXI MMIO controller/debug program |
| `kr260/load_bitstream.sh` | Loads the FPGA bitstream through the Linux FPGA manager |

`main.c` is **not** the CPU-only C implementation of the Median-Sobel algorithm.

It only controls and verifies the FPGA accelerator through `/dev/mem`.

---

# 1. Copy Required Files to the KR260

Recommended board working directory:

```bash
/home/ubuntu/TueNT/image_dsp
```

The directory should contain at least:

```text
design_1_wrapper.bit
load_bitstream.sh
main.c
noisy.hex
expected.hex
```

After running tests, the following files may also appear:

```text
main
debug.log
rtl_output.hex
rtl_output_2.hex
rtl_output_3.hex
```

Example connection:

```bash
ssh ubuntu@<KR260_IP>
```

Then:

```bash
cd /home/ubuntu/TueNT/image_dsp
pwd
ls -lh
```

Do not assume an old board IP is still valid.

---

# 2. Load the FPGA Bitstream

Inspect the script before running it:

```bash
cat load_bitstream.sh
```

Make it executable:

```bash
chmod +x load_bitstream.sh
```

Load the FPGA design:

```bash
sudo ./load_bitstream.sh
```

Check FPGA manager state:

```bash
cat /sys/class/fpga_manager/fpga0/state
```

Expected:

```text
operating
```

Important:

```text
operating
```

only confirms that the FPGA manager reports a programmed device. It does not prove:

- the correct bitstream was loaded;
- the address map is correct;
- timing closure passed;
- FPGA output is bit-exact.

---

# 3. Build `main.c`

Compile natively on the KR260:

```bash
gcc -O2 -std=c11 -Wall -Wextra main.c -o main
```

Check the generated executable:

```bash
ls -lh main
file main
```

The program accesses physical FPGA registers through:

```text
/dev/mem
```

Therefore most commands require:

```bash
sudo
```

---

# 4. Current AXI Address Map

Accelerator physical base:

```text
0xA0000000
```

Register map:

| Offset | Physical address | Function |
|---:|---:|---|
| `0x00000000` | `0xA0000000` | CTRL |
| `0x00000004` | `0xA0000004` | STATUS |
| `0x00000008` | `0xA0000008` | INFO_WIDTH |
| `0x0000000C` | `0xA000000C` | INFO_HEIGHT |
| `0x00000010` | `0xA0000010` | INFO_THRESHOLD |
| `0x00100000` | `0xA0100000` | Input pixel memory |
| `0x01100000` | `0xA1100000` | Dense output memory |

Pixel address:

```text
BASE + REGION_OFFSET + 4*k
```

One 8-bit pixel is stored in each 32-bit address slot.

---

# 5. CTRL Commands

CTRL commands are:

```text
0x01 = LOAD
0x02 = START
0x04 = STOP
```

Legal sequence:

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

Exactly one command bit must be written at a time.

---

# 6. STATUS Bits

```text
bit 0 = IDLE
bit 1 = LOAD
bit 2 = EXEC
bit 3 = READ
bit 4 = BUSY
bit 5 = DONE
bit 6 = ERROR
```

Observed values on the KR260:

```text
0x01 = IDLE
0x12 = LOAD + BUSY
0x38 = READ + BUSY + DONE
```

If `ERROR` becomes set, the design uses a sticky error state and normally requires reset/reload before retrying.

---

# 7. Important Write Rule

The current RTL requires:

```text
WSTRB = 4'b0001
```

for:

- CTRL writes;
- input pixel writes.

`main.c` therefore uses aligned 8-bit MMIO stores:

```c
*(volatile uint8_t *)(...) = value;
```

Do not casually replace these with 32-bit writes.

A 32-bit store may generate:

```text
WSTRB = 1111
```

which violates the current accelerator contract.

---

# 8. Safe Debug Workflow

Do not start with a full `--run` on an unverified bitstream.

Use the individual commands below first.

## T1 — Read-only probe

```bash
sudo ./main --log debug.log --probe
```

Expected checks:

```text
INFO_WIDTH     = 64
INFO_HEIGHT    = 64
INFO_THRESHOLD = 100
STATUS         = 0x01
```

Expected state:

```text
IDLE
```

---

## T2 — Enter LOAD state

```bash
sudo ./main --log debug.log --load
```

Expected STATUS:

```text
0x12
```

Meaning:

```text
LOAD + BUSY
```

---

## T3 — Write one input pixel

Example:

```bash
sudo ./main --log debug.log --write-pixel 0 0x00
```

The accelerator must still remain in LOAD state after the write.

---

## T4 — Write a complete frame

For the current 64x64 build:

```bash
sudo ./main --log debug.log --write-frame noisy.hex
```

Expected input count:

```text
4096 pixels
```

Important:

```bash
--write-frame
```

does **not** issue `LOAD`.

If the FPGA is still in IDLE, the program will intentionally report:

```text
State check FAILED: wanted LOAD
```

This is software protection, not an AXI failure.

---

## T5 — Start processing

```bash
sudo ./main --log debug.log --start
```

The software issues:

```text
CTRL.START
```

and waits for:

```text
READ + DONE
```

Expected STATUS:

```text
0x38
```

---

## T6 — Read individual output pixels

Useful when debugging known mismatch indices.

```bash
sudo ./main --log debug.log --read-pixel 1948
sudo ./main --log debug.log --read-pixel 2007
sudo ./main --log debug.log --read-pixel 2306
sudo ./main --log debug.log --read-pixel 2774
```

Known dense index mapping:

| Dense index | Full-frame coordinate |
|---:|---|
| 1948 | `(30,34)` |
| 2007 | `(29,35)` |
| 2306 | `(28,40)` |
| 2774 | `(16,48)` |

---

## T7 — Read and compare complete output frame

```bash
sudo ./main --log debug.log --read-frame \
    expected.hex \
    rtl_output.hex
```

For 64x64:

```text
input  = 4096 pixels
output = 3600 pixels
```

FPGA output is dense.

Dense output index `k` maps to:

```text
x = 2 + (k % 60)
y = 2 + (k / 60)
```

The golden reference is full-frame, so comparison uses:

```text
golden_index = y * 64 + x
```

---

## T8 — Return to IDLE

```bash
sudo ./main --log debug.log --stop
```

Expected STATUS:

```text
0x01
```

---

# 9. Full Run

After the individual steps are verified:

```bash
sudo ./main --log debug.log --run \
    noisy.hex \
    expected.hex \
    rtl_output.hex
```

This sequence performs:

```text
IDLE
 -> LOAD
 -> write input
 -> START
 -> wait READ/DONE
 -> read output
 -> compare golden
 -> STOP
 -> IDLE
```

Do not use a run without a golden file as proof of correctness.

Correctness requires:

```text
errors = 0
```

---

# 10. Inspect Debug Logs

Show the latest log entries:

```bash
sudo tail -n 50 debug.log
```

Inspect file sizes:

```bash
wc -l noisy.hex expected.hex rtl_output.hex
```

For the current 64x64 build:

```text
noisy.hex       = 4096 lines
expected.hex    = 4096 lines
rtl_output.hex  = 3600 lines
```

Check hashes:

```bash
sha256sum noisy.hex expected.hex
```

Known controlled input hashes from the current KR260 debug session:

```text
noisy.hex:
8204db52ce7e02bff2e8bb7c89ab20aae49719c6f380dbb8adbe80657b678ff7

expected.hex:
9e8309f8f0a93ec386879af88f1bdc9cd4c0a053afa557d9bc61475b01fb6925
```

---

# 11. Compare Repeated FPGA Outputs

After two runs:

```bash
cmp rtl_output.hex rtl_output_2.hex
```

or:

```bash
cmp -s rtl_output.hex rtl_output_2.hex && echo "OUTPUT STABLE"
```

If there is no output from the first `cmp`, the files are identical.

If the same input produces different outputs, investigate:

- per-frame Phase 1 reset;
- datapath `ST_PREP`;
- BRAM timing;
- valid/data alignment;
- timing closure.

---

# 12. Current Hardware Mismatch Status

Current real-board evidence:

## Frame 1

```text
2 mismatches / 3600
```

| k | x | y | FPGA | Golden |
|---:|---:|---:|---:|---:|
| 2306 | 28 | 40 | `00` | `FF` |
| 2774 | 16 | 48 | `00` | `FF` |

## Frame 2

```text
4 mismatches / 3600
```

| k | x | y | FPGA | Golden |
|---:|---:|---:|---:|---:|
| 1948 | 30 | 34 | `FF` | `00` |
| 2007 | 29 | 35 | `00` | `FF` |
| 2306 | 28 | 40 | `00` | `FF` |
| 2774 | 16 | 48 | `00` | `FF` |

Therefore:

```text
KR260 hardware verification != PASS
```

until repeated runs produce:

```text
mismatch = 0
```

---

# 13. Generate a Black Test Frame

A zero-image is useful for isolating state/timing problems.

```bash
python3 - <<'PY'
with open('black.hex', 'w') as f:
    f.write('00\n' * 4096)
PY
```

Run only after returning the FPGA FSM to IDLE:

```bash
sudo ./main --log debug.log --run black.hex
```

For a fully zero image, the expected valid output region is also all zeros.

---

# 14. Common Failure Cases

## `State check FAILED: wanted LOAD`

Cause:

```text
--write-frame was called before --load
```

Fix:

```bash
sudo ./main --load
sudo ./main --write-frame noisy.hex
```

---

## FPGA remains in READ

Run:

```bash
sudo ./main --stop
```

Then verify:

```bash
sudo ./main --probe
```

Expected:

```text
STATUS = 0x01
```

---

## Sticky ERROR

If STATUS contains:

```text
0x40
```

the accelerator is in ERROR.

Reload/reset the design before continuing.

---

## Program stops after `BEFORE WRITE8`

If the log shows:

```text
BEFORE WRITE8 ...
```

but never:

```text
AFTER WRITE8 ...
```

the MMIO transaction may be blocked.

Possible causes include:

- wrong bitstream;
- wrong physical address;
- AXI slave not responding;
- reset/clock issue;
- broken wrapper handshake.

Use the board serial console when investigating possible MMIO hangs.

---

## SSH disconnects during MMIO debug

Do not automatically conclude that AXI caused the disconnect.

After reconnecting, inspect:

```bash
uptime -s
```

and, if available:

```bash
sudo journalctl -b -1 -k --no-pager | tail -n 100
```

Possible causes include:

- board reset;
- network interruption;
- kernel or MMIO fault;
- non-responsive AXI transaction.

---

# 15. FPGA Manager Check

At any point:

```bash
cat /sys/class/fpga_manager/fpga0/state
```

Expected:

```text
operating
```

Again, this does not prove bit-exact correctness.

---

# 16. Recommended Debug Order

When testing a new bitstream:

```text
1. Load bitstream
2. Check fpga_manager state
3. Run --probe
4. Check INFO registers
5. Run --load
6. Write one pixel
7. Write complete frame
8. Run --start
9. Read individual known locations
10. Read complete frame
11. Compare with golden
12. Run --stop
13. Repeat same input
14. Compare repeated outputs
```

Do not jump directly to full-frame execution if earlier steps have not been validated.

---

# 17. Current Debug Priorities

Before modifying DSP arithmetic:

1. verify post-route Timing Summary;
2. record WNS and WHS;
3. check unconstrained paths;
4. regenerate Python golden from the exact board `noisy.hex`;
5. run a black-frame test;
6. reproduce the same input in XSim;
7. inspect repeated-frame reset timing;
8. audit Input BRAM read latency;
9. audit Output BRAM write timing;
10. add ILA probes if necessary.

Suggested ILA probes:

```text
AXI AW/W/B
AXI AR/R
internal wr_req / wr_ack / wr_err
internal rd_req / rd_ack / rd_err
Input BRAM address / enable / data
Output BRAM address / enable / data
datapath valid / pixel / x / y
FSM state transitions
```

---

# 18. Important Notes

- Phase 2 custom RTL uses active-low `i_rst_n`.
- The frozen Phase 1 DSP core uses active-high `i_rst`.
- The datapath converts reset polarity locally.
- Do not change Phase 1 Median/Sobel arithmetic during AXI bring-up debugging.
- Output memory stores only dense valid-region pixels.
- Current hardware resolution is 64x64.
- Do not use 512x512 HEX files with the current 64x64 bitstream.
- Input/CTRL writes use 8-bit MMIO stores.
- INFO/STATUS/output reads use 32-bit MMIO reads.
- `main.c` is a hardware control/debug tool, not the CPU DSP benchmark.
- Simulation PASS does not imply real FPGA bit-exact PASS.

---

# 19. Definition of Hardware PASS

The KR260 hardware stage is considered complete only when:

```text
bitstream load         PASS
INFO registers         PASS
LOAD                    PASS
input writes            PASS
START                   PASS
READ/DONE               PASS
output reads            PASS
STOP                    PASS
mismatch                0
repeated-frame mismatch 0
timing                   PASS
```

Recommended final stress test:

```text
10+ identical frames
same input hash
mismatch = 0 on every frame
identical output on every frame
```
