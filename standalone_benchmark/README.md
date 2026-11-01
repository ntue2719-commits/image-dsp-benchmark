# Standalone KR260 + Orange Pi Image-DSP Benchmark (Final)

This package runs independently on each board.

## KR260

The local web application compares the same input through:

1. Python golden model
2. Native ARM C Median-Sobel baseline
3. FPGA RTL accelerator through `/home/ubuntu/TueNT/image_dsp/main`

The final KR260 flow measures:

- `arm_c.compute_ms`: ARM C kernel-only time
- `fpga_rtl.input_mmio_internal_ms`: input MMIO loop time inside `main.c`
- `fpga_rtl.start_to_done_internal_ms`: internal software-visible FPGA START-to-DONE time
- `fpga_rtl.start_to_done_observed_ms`: complete `main --start` subprocess wall time (diagnostic only)
- `fpga_rtl.output_mmio_internal_ms`: output MMIO loop time inside `main.c`
- `ratios.arm_compute_over_fpga_internal_start_done`: ARM C / FPGA internal START-to-DONE ratio

`start_to_done_internal_ms` begins immediately before the START MMIO write and ends when READ|DONE is observed using tight polling. It excludes sudo/process startup, `/dev/mem` open, `mmap`, input transfer, output transfer, and process cleanup, but it still contains MMIO and userspace polling overhead. It is not a pure PL cycle-counter measurement.

## Fixed algorithm

- input: noisy grayscale 8-bit frame
- Median 3x3
- Sobel Gx/Gy
- magnitude: `abs(Gx)+abs(Gy)`
- threshold 100: `>=100 -> FF`, otherwise `00`
- valid dense output region: `(W-4)*(H-4)`

Default KR260 hardware configuration: 64x64 input = 4096 pixels, 3600 dense outputs.

## KR260 setup

This final package intentionally does not run `apt update` or `apt upgrade`.

```bash
cd image_dsp_standalone_benchmark_final
./scripts/install_kr260.sh
```

The FPGA MMIO binary is expected at:

```text
/home/ubuntu/TueNT/image_dsp/main
```

The final timed version of its source is included as:

```text
kr260/main_timed.c
```

If the existing board `main.c` has not yet been updated, copy/compile it manually:

```bash
cp kr260/main_timed.c /home/ubuntu/TueNT/image_dsp/main.c
cd /home/ubuntu/TueNT/image_dsp
gcc -O2 -std=c11 -Wall -Wextra main.c -o main
```

Allow only that binary through passwordless sudo:

```bash
sudo visudo -f /etc/sudoers.d/image-dsp-benchmark
```

Add:

```text
ubuntu ALL=(root) NOPASSWD: /home/ubuntu/TueNT/image_dsp/main
```

Verify FPGA state and MMIO binary:

```bash
cat /sys/class/fpga_manager/fpga0/state
sudo -n /home/ubuntu/TueNT/image_dsp/main --probe
```

Start the KR260 web application:

```bash
cd image_dsp_standalone_benchmark_final
.venv/bin/python kr260/app.py
```

Default port is 8081:

```text
http://<KR260-IP>:8081
```

Override if needed:

```bash
PORT=8090 .venv/bin/python kr260/app.py
```

## Orange Pi setup

```bash
cd image_dsp_standalone_benchmark_final
./scripts/install_orangepi.sh
.venv/bin/python orangepi/app.py
```

Default Orange Pi URL:

```text
http://<ORANGE-PI-IP>:8080
```

Orange Pi compares Python vs native ARM C only. It does not control the KR260.

## Result artifacts

Each run creates:

```text
kr260/results/<timestamp>/
orangepi/results/<timestamp>/
```

Common files include:

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

## Current verified KR260 reference result

For the controlled 64x64 `noisy.hex` test used during development:

- Python web golden numerically matched the original `expected.hex`: 4096/4096 pixels, 0 differences.
- ARM C: 20/20 runs bit-exact.
- ARM C mean kernel time: 4.817457 ms.
- FPGA internal START-to-DONE mean: 0.023008 ms.
- Mean ARM-C-to-FPGA internal latency ratio: 209.40x.
- FPGA correctness remains intermittent: 15/20 runs contained one mismatch at dense index 2306, coordinate (28,40), actual `00`, expected `FF`.

Therefore the 209.40x value is a measured performance observation of the current physical implementation, not a final validated accelerator speedup.
