from __future__ import annotations

from pathlib import Path
from typing import Iterable
import json


def read_hex_u8(path: str | Path, expected_count: int | None = None) -> list[int]:
    vals: list[int] = []
    with open(path, "r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            s = line.strip()
            if not s:
                continue
            try:
                v = int(s, 16)
            except ValueError as e:
                raise ValueError(f"{path}:{lineno}: invalid hex byte {s!r}") from e
            if not 0 <= v <= 0xFF:
                raise ValueError(f"{path}:{lineno}: value out of 8-bit range: {s}")
            vals.append(v)
    if expected_count is not None and len(vals) != expected_count:
        raise ValueError(f"{path}: expected {expected_count} pixels, found {len(vals)}")
    return vals


def write_hex_u8(path: str | Path, vals: Iterable[int]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for v in vals:
            f.write(f"{int(v) & 0xFF:02X}\n")


def median9(values: list[int]) -> int:
    # Small deterministic reference sorter; intentionally simple and readable.
    a = list(values)
    for i in range(1, 9):
        key = a[i]
        j = i - 1
        while j >= 0 and a[j] > key:
            a[j + 1] = a[j]
            j -= 1
        a[j + 1] = key
    return a[4]


def golden_from_noisy(noisy: list[int], width: int, height: int, threshold: int = 100):
    if width < 5 or height < 5:
        raise ValueError("width and height must both be >= 5")
    if len(noisy) != width * height:
        raise ValueError(f"expected {width*height} input pixels, got {len(noisy)}")

    median = [0] * (width * height)
    for y in range(1, height - 1):
        base = y * width
        for x in range(1, width - 1):
            w = []
            for yy in (y - 1, y, y + 1):
                row = yy * width
                w.extend((noisy[row + x - 1], noisy[row + x], noisy[row + x + 1]))
            median[base + x] = median9(w)

    full = [0] * (width * height)
    dense: list[int] = []
    magnitudes: list[int] = []
    for y in range(2, height - 2):
        for x in range(2, width - 2):
            p00 = median[(y - 1) * width + (x - 1)]
            p01 = median[(y - 1) * width + x]
            p02 = median[(y - 1) * width + (x + 1)]
            p10 = median[y * width + (x - 1)]
            p12 = median[y * width + (x + 1)]
            p20 = median[(y + 1) * width + (x - 1)]
            p21 = median[(y + 1) * width + x]
            p22 = median[(y + 1) * width + (x + 1)]
            gx = -p00 + p02 - 2 * p10 + 2 * p12 - p20 + p22
            gy = -p00 - 2 * p01 - p02 + p20 + 2 * p21 + p22
            mag = abs(gx) + abs(gy)
            out = 0xFF if mag >= threshold else 0x00
            full[y * width + x] = out
            dense.append(out)
            magnitudes.append(mag)
    return full, dense, magnitudes


def dense_index_to_xy(k: int, width: int) -> tuple[int, int]:
    valid_w = width - 4
    return 2 + (k % valid_w), 2 + (k // valid_w)


def compare_dense(actual: list[int], expected: list[int], width: int, limit: int = 20):
    n = min(len(actual), len(expected))
    mismatches = []
    for k in range(n):
        if actual[k] != expected[k]:
            x, y = dense_index_to_xy(k, width)
            mismatches.append({"k": k, "x": x, "y": y, "actual": actual[k], "expected": expected[k]})
            if len(mismatches) >= limit:
                break
    total = sum(1 for i in range(n) if actual[i] != expected[i]) + abs(len(actual) - len(expected))
    return total, mismatches


def save_json(path: str | Path, obj) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=False)
