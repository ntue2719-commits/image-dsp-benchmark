from __future__ import annotations

import hashlib
import re
import subprocess
import time
from pathlib import Path

from dsp_common import (
    read_hex_u8,
    write_hex_u8,
    golden_from_noisy,
    compare_dense,
    save_json,
)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()

    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)

    return h.hexdigest()


def run_cmd(cmd, cwd=None, allow_failure=False):
    t0 = time.perf_counter_ns()

    p = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    t1 = time.perf_counter_ns()

    if p.returncode != 0 and not allow_failure:
        raise RuntimeError(
            f"command failed ({p.returncode}): "
            f"{' '.join(map(str, cmd))}\n{p.stdout}"
        )

    return p.returncode, p.stdout, (t1 - t0) / 1e6


def parse_metric(text: str, key: str):
    """
    Parse machine-readable lines such as:

        CPU_COMPUTE_MS=4.801234
        FPGA_START_TO_DONE_INTERNAL_MS=0.023230
        FPGA_START_TO_DONE_INTERNAL_NS=23230
    """
    m = re.search(
        rf"^{re.escape(key)}=([0-9.]+)$",
        text,
        flags=re.M,
    )

    return float(m.group(1)) if m else None


def benchmark_python(
    input_path: Path,
    work: Path,
    w: int,
    h: int,
    threshold: int,
):
    noisy = read_hex_u8(input_path, w * h)

    t0 = time.perf_counter_ns()
    full, dense, mags = golden_from_noisy(
        noisy,
        w,
        h,
        threshold,
    )
    t1 = time.perf_counter_ns()

    full_path = work / "golden_full.hex"
    dense_path = work / "golden_dense.hex"

    write_hex_u8(full_path, full)
    write_hex_u8(dense_path, dense)

    return {
        "compute_ms": (t1 - t0) / 1e6,
        "full_path": str(full_path),
        "dense_path": str(dense_path),
        "dense": dense,
        "magnitudes": mags,
    }


def benchmark_arm(
    cpu_bin: Path,
    input_path: Path,
    work: Path,
    w: int,
    h: int,
    threshold: int,
    golden_dense: list[int],
):
    out_path = work / "arm_output.hex"

    rc, text, wall_ms = run_cmd(
        [
            str(cpu_bin),
            str(input_path),
            str(out_path),
            str(w),
            str(h),
            str(threshold),
        ]
    )

    compute_ms = parse_metric(
        text,
        "CPU_COMPUTE_MS",
    )

    actual = read_hex_u8(out_path)

    errors, examples = compare_dense(
        actual,
        golden_dense,
        w,
    )

    return {
        "compute_ms": compute_ms,
        "process_wall_ms": wall_ms,
        "errors_vs_python": errors,
        "mismatches": examples,
        "output_path": str(out_path),
        "stdout": text,
    }


def _extract_internal_ms(text: str, label: str):
    """
    Parse the existing main.c human-readable timing logs:

        END input write; 0.691 ms
        END output read; 1.200 ms
    """
    patterns = {
        "input": r"END input write;\s*([0-9.]+)\s*ms",
        "output": r"END output read;\s*([0-9.]+)\s*ms",
    }

    m = re.search(
        patterns[label],
        text,
        flags=re.I,
    )

    return float(m.group(1)) if m else None


def benchmark_fpga(
    main_bin: Path,
    input_path: Path,
    work: Path,
    w: int,
    h: int,
    threshold: int,
    golden_full_path: Path,
    golden_dense: list[int],
    sudo: bool = True,
):
    if w != 64 or h != 64:
        raise ValueError(
            "current KR260 FPGA benchmark is restricted "
            "to the 64x64 hardware build"
        )

    prefix = ["sudo", "-n"] if sudo else []

    log = []

    total0 = time.perf_counter_ns()

    out_path = work / "fpga_output.hex"

    write_text = ""
    write_wall = None

    start_text = ""
    start_wall = None

    read_text = ""
    read_wall = None

    read_rc = None

    def step(
        name,
        args,
        allow_failure=False,
    ):
        rc, text, wall_ms = run_cmd(
            prefix + [str(main_bin)] + args,
            allow_failure=allow_failure,
        )

        log.append(
            f"===== {name} "
            f"rc={rc} "
            f"wall_ms={wall_ms:.6f} =====\n"
            f"{text}"
        )

        return rc, text, wall_ms

    try:
        step(
            "probe",
            ["--probe"],
        )

        step(
            "load",
            ["--load"],
        )

        _, write_text, write_wall = step(
            "write-frame",
            [
                "--write-frame",
                str(input_path),
            ],
        )

        _, start_text, start_wall = step(
            "start",
            ["--start"],
        )

        read_rc, read_text, read_wall = step(
            "read-frame",
            [
                "--read-frame",
                str(golden_full_path),
                str(out_path),
            ],
            allow_failure=True,
        )

    finally:
        # STOP is legal only in READ, so cleanup is best-effort.
        try:
            step(
                "stop",
                ["--stop"],
                allow_failure=True,
            )

        except Exception as e:
            log.append(
                f"STOP cleanup exception: {e}\n"
            )

    total1 = time.perf_counter_ns()

    log_path = work / "fpga_console.log"

    log_path.write_text(
        "\n".join(log),
        encoding="utf-8",
    )

    if not out_path.exists():
        raise RuntimeError(
            "FPGA output file was not produced; "
            "see fpga_console.log"
        )

    actual = read_hex_u8(out_path)

    errors, examples = compare_dense(
        actual,
        golden_dense,
        w,
    )

    # New timing generated by the modified main.c.
    start_internal_ns = parse_metric(
        start_text,
        "FPGA_START_TO_DONE_INTERNAL_NS",
    )

    start_internal_ms = parse_metric(
        start_text,
        "FPGA_START_TO_DONE_INTERNAL_MS",
    )

    return {
        # MMIO transfer measurements produced inside main.c.
        "input_mmio_internal_ms": _extract_internal_ms(
            write_text,
            "input",
        ),

        "input_command_wall_ms": write_wall,

        # NEW:
        # Measured inside main.c from the START MMIO write
        # until READ|DONE is observed by tight STATUS polling.
        "start_to_done_internal_ns": start_internal_ns,
        "start_to_done_internal_ms": start_internal_ms,

        # Old measurement retained for diagnostics.
        # Includes sudo/process/open/mmap/cleanup overhead.
        "start_to_done_observed_ms": start_wall,

        "output_mmio_internal_ms": _extract_internal_ms(
            read_text,
            "output",
        ),

        "output_command_wall_ms": read_wall,

        "backend_wall_ms": (
            total1 - total0
        ) / 1e6,

        "errors_vs_python": errors,
        "mismatches": examples,
        "read_frame_returncode": read_rc,

        "output_path": str(out_path),
        "log_path": str(log_path),
    }


def run_benchmark(
    board: str,
    input_path: Path,
    results_root: Path,
    cpu_bin: Path,
    w=64,
    h=64,
    threshold=100,
    fpga_main: Path | None = None,
    fpga_sudo=True,
):
    stamp = (
        time.strftime("%Y%m%d-%H%M%S")
        + f"-{time.time_ns() % 1000000:06d}"
    )

    work = results_root / stamp

    work.mkdir(
        parents=True,
        exist_ok=False,
    )

    copied = work / "input.hex"

    copied.write_bytes(
        input_path.read_bytes()
    )

    result = {
        "board": board,
        "timestamp": stamp,
        "width": w,
        "height": h,
        "threshold": threshold,
        "input_sha256": sha256_file(copied),
        "input_pixels": w * h,
        "output_pixels": (w - 4) * (h - 4),
    }

    # --------------------------------------------------------
    # Python golden reference
    # --------------------------------------------------------

    py = benchmark_python(
        copied,
        work,
        w,
        h,
        threshold,
    )

    result["python"] = {
        "compute_ms": py["compute_ms"],
        "errors_vs_python": 0,
    }

    # --------------------------------------------------------
    # Native ARM C baseline
    # --------------------------------------------------------

    arm = benchmark_arm(
        cpu_bin,
        copied,
        work,
        w,
        h,
        threshold,
        py["dense"],
    )

    result["arm_c"] = {
        k: v
        for k, v in arm.items()
        if k not in (
            "stdout",
            "output_path",
        )
    }

    # --------------------------------------------------------
    # FPGA RTL accelerator
    # --------------------------------------------------------

    if fpga_main is not None:
        fpga = benchmark_fpga(
            fpga_main,
            copied,
            work,
            w,
            h,
            threshold,
            Path(py["full_path"]),
            py["dense"],
            sudo=fpga_sudo,
        )

        result["fpga_rtl"] = {
            k: v
            for k, v in fpga.items()
            if k not in (
                "output_path",
                "log_path",
            )
        }

        ratios = {}

        # Preferred comparison:
        # ARM C kernel-only time divided by the internally
        # measured host-observed FPGA START->DONE interval.
        if (
            arm["compute_ms"] is not None
            and fpga.get(
                "start_to_done_internal_ms"
            ) is not None
            and fpga[
                "start_to_done_internal_ms"
            ] > 0
        ):
            ratios[
                "arm_compute_over_fpga_internal_start_done"
            ] = (
                arm["compute_ms"]
                / fpga[
                    "start_to_done_internal_ms"
                ]
            )

        # Keep the old process-wall ratio only as a diagnostic.
        if (
            arm["compute_ms"] is not None
            and fpga.get(
                "start_to_done_observed_ms"
            ) is not None
            and fpga[
                "start_to_done_observed_ms"
            ] > 0
        ):
            ratios[
                "arm_compute_over_fpga_process_observed"
            ] = (
                arm["compute_ms"]
                / fpga[
                    "start_to_done_observed_ms"
                ]
            )

        if ratios:
            result["ratios"] = ratios

    # --------------------------------------------------------
    # Measurement notes
    # --------------------------------------------------------

    result["notes"] = {
        "python": (
            "Reference correctness model; Python timing is "
            "interpreter execution time on this board."
        ),

        "arm_c": (
            "Native ARM C Median-Sobel kernel time excludes "
            "input file parsing and output file writing; "
            "process_wall_ms includes file I/O and process startup."
        ),

        "fpga_internal_start_done": (
            "start_to_done_internal_ms is measured inside main.c "
            "from immediately before the START MMIO write until "
            "READ|DONE is observed using tight STATUS polling. "
            "It includes the START MMIO write, STATUS MMIO polling, "
            "and small userspace timing overhead. It excludes sudo, "
            "process startup, /dev/mem open, mmap, input transfer, "
            "output transfer, and process cleanup. It is therefore "
            "a host-observed accelerator latency, not a pure PL "
            "cycle-counter measurement."
        ),

        "fpga_process_observed": (
            "start_to_done_observed_ms is the wall-clock duration "
            "of the complete `main --start` subprocess as observed "
            "by Python. It includes Linux/process/sudo/MMIO setup "
            "overhead and must not be used as pure FPGA kernel time."
        ),

        "fpga_mmio": (
            "input_mmio_internal_ms and output_mmio_internal_ms "
            "are measured inside main.c around frame MMIO transfer "
            "loops when available."
        ),
    }

    save_json(
        work / "result.json",
        result,
    )

    return result, work
