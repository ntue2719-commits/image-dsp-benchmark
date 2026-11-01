# Standalone KR260 + Orange Pi Image-DSP Benchmark

This package provides a standalone benchmark environment for the Median-Sobel image-processing project.

The benchmark is designed to run independently on the AMD Kria KR260 and Orange Pi platforms while using the same image-processing algorithm and compatible input/output formats.

The current verified platform is the **AMD Kria KR260**. Orange Pi support is included for the later ARM CPU comparison and should be considered pending validation until it is executed on the target board.

---

## 1. Benchmark Overview

### KR260

The KR260 benchmark compares the same noisy grayscale input through three implementations:

1. Python golden model;
2. native ARM C Median-Sobel implementation;
3. FPGA RTL accelerator controlled through Linux MMIO.

The FPGA MMIO executable is expected at:

```text
/home/ubuntu/TueNT/image_dsp/main
```

The benchmark web application collects correctness and timing information from all three paths.

### Orange Pi

The Orange Pi benchmark is intended to compare:

1. Python golden model;
2. native ARM C Median-Sobel implementation.

The Orange Pi does not control the KR260 FPGA accelerator.

---

## 2. Fixed Image-Processing Algorithm

All implementations use the same algorithm and arithmetic conventions.

Input:

```text
8-bit noisy grayscale image
```

Processing sequence:

```text
Median 3x3
    ->
Sobel Gx/Gy
    ->
|Gx| + |Gy|
    ->
Threshold
```

Gradient magnitude:

```text
M = abs(Gx) + abs(Gy)
```

Threshold:

```text
M >= 100 -> 0xFF
M <  100 -> 0x00
```

No padding is applied.

For an input image of size:

```text
W x H
```

the final dense valid-output region contains:

```text
(W - 4) x (H - 4)
```

pixels.

The current physical KR260 configuration uses:

```text
Input resolution : 64 x 64
Input pixels     : 4096
Valid outputs    : 3600
Threshold        : 100
```

---

## 3. Benchmark Timing Fields

The KR260 benchmark reports several timing values.

### ARM C

```text
arm_c.compute_ms
```

Measures the native ARM C Median-Sobel kernel execution time.

File I/O and process startup are excluded from the kernel timer.

### FPGA input transfer

```text
fpga_rtl.input_mmio_internal_ms
```

Measures the software-controlled loop that writes input pixels through MMIO.

### FPGA START-to-DONE software-visible interval

```text
fpga_rtl.start_to_done_internal_ms
```

Starts immediately before the START MMIO write and ends when the Linux userspace program observes the accelerator in the READ/DONE state using tight polling.

It excludes:

- process startup;
- `sudo` startup;
- `/dev/mem` open;
- `mmap()`;
- input-frame transfer;
- output-frame transfer;
- process cleanup.

However, it still contains MMIO and Linux userspace polling overhead.

It is therefore **not a hardware cycle-counter measurement**.

### Complete FPGA subprocess observation

```text
fpga_rtl.start_to_done_observed_ms
```

Measures the complete `main --start` subprocess wall time.

This value is retained for diagnostic purposes only and must not be interpreted as FPGA kernel latency.

### FPGA output transfer

```text
fpga_rtl.output_mmio_internal_ms
```

Measures the software-controlled loop that reads the dense FPGA output through MMIO.

### Diagnostic ARM-to-FPGA ratio

```text
ratios.arm_compute_over_fpga_internal_start_done
```

This value is calculated from:

```text
ARM C kernel time / software-visible FPGA START-to-DONE interval
```

The ratio is retained for diagnostic observation only.

It is **not currently a validated CPU-to-FPGA speedup**.

---

## 4. KR260 Installation

The package intentionally does not run:

```text
apt update
apt upgrade
```

automatically.

From the repository root:

```bash
cd standalone_benchmark
./scripts/install_kr260.sh
```

The installation script prepares the Python environment and benchmark dependencies.

---

## 5. KR260 FPGA MMIO Program

The FPGA MMIO executable is expected at:

```text
/home/ubuntu/TueNT/image_dsp/main
```

The timed source used during the current benchmark development is included as:

```text
kr260/main_timed.c
```

If the board-side `main.c` has not yet been updated, copy and compile it manually:

```bash
cp kr260/main_timed.c /home/ubuntu/TueNT/image_dsp/main.c

cd /home/ubuntu/TueNT/image_dsp

gcc -O2 -std=c11 -Wall -Wextra main.c -o main
```

Verify that the binary exists:

```bash
ls -l /home/ubuntu/TueNT/image_dsp/main
```

---

## 6. Passwordless MMIO Execution

The benchmark web application launches the FPGA MMIO program through `sudo`.

Allow only the required executable through passwordless sudo:

```bash
sudo visudo -f /etc/sudoers.d/image-dsp-benchmark
```

Add:

```text
ubuntu ALL=(root) NOPASSWD: /home/ubuntu/TueNT/image_dsp/main
```

Save and exit.

Verify the rule:

```bash
sudo -n /home/ubuntu/TueNT/image_dsp/main --probe
```

If the command executes without asking for a password, the sudo configuration is correct.

---

## 7. Verify the KR260 FPGA State

Before starting the web benchmark, verify that the FPGA bitstream is loaded:

```bash
cat /sys/class/fpga_manager/fpga0/state
```

Expected state:

```text
operating
```

Then probe the accelerator:

```bash
sudo -n /home/ubuntu/TueNT/image_dsp/main --probe
```

For the current hardware configuration, the probe should report values equivalent to:

```text
WIDTH     = 64
HEIGHT    = 64
THRESHOLD = 100
STATUS    = IDLE
```

The exact output formatting depends on the current version of the MMIO program.

---

## 8. Start the KR260 Web Application

From the repository root:

```bash
cd standalone_benchmark
.venv/bin/python kr260/app.py
```

The default port is:

```text
8081
```

Open from another computer on the same network:

```text
http://<KR260-IP>:8081
```

For example:

```text
http://192.168.x.x:8081
```

To use another port:

```bash
PORT=8090 .venv/bin/python kr260/app.py
```

Then open:

```text
http://<KR260-IP>:8090
```

---

## 9. Running a Benchmark from the Web Interface

For the verified KR260 test, use the same controlled 64x64 noisy grayscale HEX input used during project development.

The normal workflow is:

1. Open the KR260 benchmark page.
2. Select the noisy input HEX file.
3. Start the benchmark.
4. Wait for the Python, ARM C, and FPGA executions to finish.
5. Inspect the correctness summary.
6. Inspect timing values.
7. Check the mismatch section if the FPGA result differs from the golden reference.
8. Inspect the generated result directory for complete logs and output files.

The same input is processed through:

```text
Python
ARM C
FPGA RTL
```

The Python implementation generates the numerical golden reference.

The ARM C and FPGA outputs are then compared with the corresponding golden output.

---

## 10. Expected Correctness Behavior

### Python golden model

The Python model defines the expected numerical result.

For the controlled 64x64 development input, the web-generated Python result was independently compared against the original `expected.hex`.

Result:

```text
4096 / 4096 values identical
0 numerical differences
```

### ARM C

For the current reference input:

```text
20 / 20 runs bit-exact
```

No ARM C mismatches were observed.

### FPGA RTL

The FPGA result is currently intermittent for the noisy reference image.

Across the controlled 20-run benchmark:

```text
5 / 20 runs bit-exact
15 / 20 runs contain exactly one mismatch
```

Every failing run contains the same mismatch:

```text
Dense index    : 2306
Coordinate     : (28, 40)
FPGA value     : 0x00
Expected value : 0xFF
```

The behavior is therefore intermittent across executions but spatially deterministic when the failure occurs.

---

## 11. KR260 Web Debugging

If the web page cannot execute the FPGA path, debug the FPGA interface independently of Flask first.

### Step 1: Check FPGA Manager

```bash
cat /sys/class/fpga_manager/fpga0/state
```

Expected:

```text
operating
```

### Step 2: Check MMIO access

```bash
sudo -n /home/ubuntu/TueNT/image_dsp/main --probe
```

Verify:

```text
WIDTH     = 64
HEIGHT    = 64
THRESHOLD = 100
STATUS    = IDLE
```

If this fails, debug the FPGA/MMIO environment before debugging the web application.

### Step 3: Check sudo configuration

```bash
sudo -n /home/ubuntu/TueNT/image_dsp/main --probe
```

If a password is requested, inspect:

```bash
sudo visudo -f /etc/sudoers.d/image-dsp-benchmark
```

and verify:

```text
ubuntu ALL=(root) NOPASSWD: /home/ubuntu/TueNT/image_dsp/main
```

### Step 4: Check Flask console output

Keep the terminal running:

```bash
.venv/bin/python kr260/app.py
```

When a benchmark is launched from the browser, inspect this terminal for Python exceptions, subprocess failures, missing files, or permission errors.

### Step 5: Inspect the generated run artifacts

Every benchmark run creates a timestamped directory.

For KR260:

```text
kr260/results/<timestamp>/
```

Inspect the contents:

```bash
ls -lah kr260/results/<timestamp>/
```

Important files include:

```text
input.hex
golden_full.hex
golden_dense.hex
arm_output.hex
fpga_output.hex
fpga_console.log
result.json
```

### Step 6: Check the FPGA console log

```bash
cat kr260/results/<timestamp>/fpga_console.log
```

This contains the output produced by the board-side FPGA MMIO executable.

Use this file when the web application reports an FPGA execution failure or an unexpected accelerator state.

### Step 7: Compare FPGA output with the dense golden output

From the run directory:

```bash
diff golden_dense.hex fpga_output.hex
```

For a bit-exact run, `diff` should produce no output.

If the FPGA mismatches the golden model, inspect:

```text
result.json
```

for the recorded mismatch index and values.

---

## 12. Debugging the Current Known FPGA Mismatch

For the current intermittent failing case:

```text
Dense index    : 2306
Coordinate     : (28, 40)
FPGA           : 0x00
Golden         : 0xFF
```

The corresponding expected Sobel input after Median filtering is:

```text
A6 91 91
91 88 88
88 84 88
```

The expected gradients are:

```text
Gx = -39
Gy = -65
```

Therefore:

```text
M = abs(-39) + abs(-65)
  = 104
```

Since:

```text
104 >= 100
```

the expected threshold output is:

```text
0xFF
```

Other tested locations with the same gradient magnitude of 104 produce the correct FPGA output. Therefore, the current evidence does not support a simple global threshold-comparator bug.

The post-route critical path passes through the Median compare-swap network, but static timing analysis reports positive setup and hold slack. Timing sensitivity is therefore a hypothesis, not a confirmed root cause.

Recommended next debugging steps include:

```text
1. Observe the Median output around coordinate (28,40).
2. Observe the second 3x3 window.
3. Observe Gx and Gy.
4. Observe gradient magnitude.
5. Observe valid and coordinate alignment.
6. Observe the Phase 2 execution state.
```

An ILA is the preferred method for direct cycle-level observation.

A controlled lower-frequency FPGA build can also be used as an experiment to determine whether the mismatch rate changes with additional timing margin.

---

## 13. FPGA Timing Consistency Check

The current benchmark records a mean software-visible FPGA START-to-DONE value of:

```text
0.023008 ms
```

or approximately:

```text
23.008 us
```

However, the current Phase 2 architecture must feed all 4096 input pixels into the streaming core.

At a 100-MHz PL clock and a maximum input rate of one accepted pixel per cycle:

```text
4096 cycles / 100 MHz = 40.96 us
```

This is only the theoretical input-feed lower bound.

The actual START-to-DONE interval must additionally include:

```text
ST_PREP
synchronous Input Memory response
pipeline fill
pipeline flush
final output commit
transition to READ/DONE
```

Therefore:

```text
23.008 us < 40.96 us
```

is architecturally inconsistent with the intended START-to-DONE interval.

The recorded software timing value is retained only as a diagnostic observation.

It must **not** currently be reported as validated FPGA kernel latency.

---

## 14. CPU-to-FPGA Speedup Interpretation

Using the current software-visible timer, the benchmark previously calculated a mean ratio of approximately:

```text
209.40x
```

This value must not be treated as a validated accelerator speedup because its FPGA denominator is based on the inconsistent `23.008 us` timing measurement.

Therefore:

```text
209.40x
```

is retained only as a diagnostic software-timer ratio.

A valid FPGA speedup result requires a trusted FPGA kernel latency measurement.

Recommended measurement methods are:

```text
1. Hardware cycle counter
2. Integrated Logic Analyzer (ILA)
```

A hardware counter should count PL clock cycles from accepted START to datapath completion.

Only after obtaining a cycle-accurate FPGA kernel time should the processor-to-FPGA kernel speedup be calculated as:

```text
speedup = ARM C kernel time / FPGA kernel time
```

System-level performance should additionally distinguish:

```text
T_FPGA_E2E =
    T_input
  + T_control
  + T_kernel
  + T_output
```

because the current AXI4-Lite implementation transfers pixels individually through MMIO.

---

## 15. Current Verified KR260 Reference Results

For the controlled 64x64 `noisy.hex` development input:

### Python

```text
Original expected.hex vs web-generated Python golden:
4096 / 4096 identical
0 differences
```

### ARM C

```text
Correct runs       : 20 / 20
Mean kernel time   : 4.817457 ms
Median             : 4.820223 ms
Minimum            : 4.753018 ms
Maximum            : 4.918889 ms
Standard deviation : 0.040068 ms
```

### FPGA correctness

```text
Bit-exact runs : 5 / 20
Failing runs   : 15 / 20
Failing rate   : 75%
```

Each failing run contains exactly one mismatch:

```text
Dense index    : 2306
Coordinate     : (28,40)
FPGA           : 0x00
Golden         : 0xFF
```

### FPGA diagnostic software timing

```text
Mean    : 0.023008 ms
Median  : 0.022915 ms
Minimum : 0.022670 ms
Maximum : 0.023561 ms
Std dev : 0.000265 ms
```

These FPGA timing values are retained for debugging only and are not validated accelerator-latency results.

### Current benchmark status

```text
Python reference          : PASS
ARM C correctness         : PASS
FPGA MMIO integration     : PASS
FPGA black-frame test     : PASS
FPGA noisy-frame result   : INTERMITTENT
FPGA kernel latency       : NOT VALIDATED
CPU-to-FPGA speedup       : NOT VALIDATED
```

---

## 16. Result Artifacts

Each execution generates a timestamped result directory.

KR260:

```text
kr260/results/<timestamp>/
```

Orange Pi:

```text
orangepi/results/<timestamp>/
```

Common artifacts may include:

```text
input.hex
golden_full.hex
golden_dense.hex
arm_output.hex
result.json
```

KR260 additionally stores:

```text
fpga_output.hex
fpga_console.log
```

These files are intended to make benchmark runs reproducible and allow correctness failures to be inspected without relying only on the web interface.

---

## 17. Orange Pi Setup

Orange Pi support is intended for a later native ARM CPU comparison.

From the repository root:

```bash
cd standalone_benchmark
./scripts/install_orangepi.sh
```

Then start the Orange Pi web application:

```bash
.venv/bin/python orangepi/app.py
```

Default port:

```text
8080
```

Open:

```text
http://<ORANGE-PI-IP>:8080
```

The Orange Pi benchmark compares:

```text
Python golden model
vs
native ARM C
```

It does not access or control the KR260 FPGA accelerator.

Orange Pi results should not be presented as validated project measurements until the benchmark has been executed and checked on the physical Orange Pi target.

---

## 18. Repository Layout

The standalone benchmark directory is organized as:

```text
standalone_benchmark/
├── common/
├── kr260/
├── orangepi/
├── scripts/
├── static/
├── templates/
├── README.md
└── requirements.txt
```

### `common/`

Shared benchmark logic, Python utilities, and native ARM C implementation.

### `kr260/`

KR260-specific web entry point, FPGA control integration, and MMIO source.

### `orangepi/`

Orange Pi benchmark entry point.

### `scripts/`

Platform installation and setup scripts.

### `static/`

Web application static assets.

### `templates/`

HTML templates used by the benchmark web interface.

---

## 19. Current Limitations

The current benchmark has the following known limitations:

1. The physical KR260 FPGA noisy-image result is not yet consistently bit-exact.
2. The current Linux userspace START-to-DONE timer does not produce an architecturally valid FPGA latency.
3. The reported `209.40x` ratio is diagnostic only and is not a validated accelerator speedup.
4. Frame data are transferred through per-pixel AXI4-Lite MMIO transactions.
5. AXI DMA and AXI4-Stream are not currently used.
6. The physical FPGA configuration is currently limited to 64x64 images.
7. Larger 512x512 and 640x480 cases have been verified in RTL simulation but not with equivalent full-frame physical KR260 memories.
8. Orange Pi execution remains pending physical-board validation.

---

## 20. Recommended Next Steps

The highest-priority development tasks are:

1. Localize the intermittent FPGA mismatch using ILA.
2. Perform a controlled lower-frequency experiment.
3. Add a hardware cycle counter for START-to-DONE latency.
4. Re-run repeated FPGA correctness tests.
5. Calculate CPU-to-FPGA speedup only after the FPGA timing is validated.
6. Replace per-pixel AXI4-Lite frame transfers with DMA or AXI4-Stream for higher system throughput.
7. Run and validate the native ARM C benchmark on Orange Pi.