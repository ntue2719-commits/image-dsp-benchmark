# Contributing

Thanks for contributing to the Embedded DSP Image Processing Benchmark.
This document covers the development workflow and commit message rules.
For the algorithm/RTL specification itself, see [`docs/SPEC.md`](docs/SPEC.md).

## Development order

Follow the order below — do not write `rtl/image_dsp_top.v` before each
sub-module has passed its own individual simulation:

```
Python Golden Model → C → each RTL primitive → each window
→ Median → Sobel → top → simulation → synthesis
```

## Branching

- `main` — always buildable, always passes `Python == C == RTL` verification.
- Feature branches: `<scope>/<short-description>`, e.g. `rtl/median-3x3`,
  `python/golden-model`, `fpga-ebaz/synthesis-constraints`.
- Open a PR into `main`; do not push directly to `main` for RTL or C changes.

## Commit Convention

This project follows **Conventional Commits**:

```
<type>(<scope>): <short imperative summary>

[optional body]

[optional footer]
```

- Subject line ≤ 72 characters, imperative mood ("add", not "added"/"adds").
- One logical change per commit — don't mix Python, C, and RTL changes in
  the same commit unless it's a single cross-language sync commit
  (`sync:`, see below).
- Body explains **why**, not just what, when the change isn't obvious.

### Commit types

| Type | Purpose |
| --- | --- |
| `feat` | New feature / new module / new pipeline stage |
| `fix` | Bug fix (algorithm, RTL logic, off-by-one, build) |
| `docs` | Documentation only (README, spec, comments-as-docs) |
| `test` | Adding or updating tests / testbenches / verification scripts |
| `perf` | Performance/optimization change with no behavior change |
| `refactor` | Code restructuring with no functional or output change |
| `build` | Build system, synthesis scripts, Makefiles, toolchain config |
| `ci` | CI/CD pipeline changes |
| `chore` | Repo maintenance (gitignore, formatting, housekeeping) |
| `data` | Adding/updating HEX golden vectors, benchmark inputs |
| `sync` | Cross-language sync commit to keep Python/C/RTL behavior aligned |

### Scopes (map to repository structure)

Use a scope that matches the directory or module touched:

| Scope | Applies to |
| --- | --- |
| `python` | `python/` — golden model, preprocessing, noise, verify, benchmark scripts |
| `c` | `c/` — CPU implementation |
| `rtl` | `rtl/` — Verilog-2001 modules |
| `tb` | `tb/` — RTL testbenches |
| `fpga-ebaz` | `fpga/ebaz/` — EBAZ4205 synthesis/bitstream/constraints |
| `fpga-kr260` | `fpga/kr260/` — KR260 synthesis/bitstream/constraints |
| `data` | `data/` — HEX golden vectors and input images |
| `results` | `results/` — benchmark CSVs, plots |
| `docs` | `README.md`, `docs/SPEC.md` |
| `repo` | Top-level repo config not tied to one module |

### Examples by purpose

**Golden model / Python**
```
feat(python): implement 3x3 median filter in golden_model.py
fix(python): correct Sobel valid-region loop bounds to range(2, H-2)
test(python): add non-square 640x480 case to verify.py
```

**C implementation**
```
feat(c): implement median_3x3() with uint8_t buffers
fix(c): use int16_t for gx/gy to prevent overflow
perf(c): vectorize median compare-swap network
sync(c): align median loop range with spec section 6.1
```

**RTL**
```
feat(rtl): add line_buffer.v with parameterized IMAGE_WIDTH
feat(rtl): implement median_3x3.v compare-swap network
fix(rtl): correct sobel_result_valid range to 2 <= x <= W-3
refactor(rtl): split window_3x3.v center pixel calc per spec section 8.3
```

**Testbench / verification**
```
test(tb): add tb_image_dsp_top.v streaming testbench
fix(tb): compare rtl_output.hex against expected.hex byte-exact
docs(tb): document PASS criteria (mismatch = 0)
```

**FPGA**
```
build(fpga-ebaz): add Vivado synthesis project for EBAZ4205
build(fpga-kr260): add constraints file for KR260 PL
chore(fpga-ebaz): report LUT/FF/BRAM/DSP utilization in results/
```

**Data / benchmark results**
```
data: add noisy.hex generated with seed=12345, noise_probability=5%
data: add 1024x1024 benchmark input set
chore(results): update benchmark.csv with Case E/F FPGA numbers
```

**Docs**
```
docs: add README with pipeline overview and repo structure
docs: update latency budget table in spec section 8.2
```

**Cross-cutting**
```
sync: update IMAGE_WIDTH/IMAGE_HEIGHT parameters across C and RTL
ci: add GitHub Actions job to run Python vs C verification on push
chore: update .gitignore for build artifacts and *.hex outputs
```

### Rules specific to this project

- Any change to the **valid-region logic** or the **latency budget
  table** (spec §6, §8.2) must use `fix` or `refactor`, never `feat`, and
  must reference the affected stage(s) in the body — this logic is
  load-bearing across Python/C/RTL.
- A commit that changes the Gx/Gy formula, threshold value, or noise
  parameters must be `fix` (not `feat`) and must state in the body
  whether golden vectors in `data/` need to be regenerated.
- Never commit a change to `rtl/` without a corresponding `test(tb)` or
  `sync` commit demonstrating `Python == C == RTL` still holds, unless
  explicitly marked `wip` in the subject (e.g. `feat(rtl): [wip] sobel_3x3.v skeleton`).
- `results/benchmark.csv` and `results/plots/` are only touched by
  `data` or `chore(results)` commits — never mixed into a `feat`/`fix`
  commit for a source module.

## Pull requests

- PR title should follow the same `type(scope): summary` convention as
  commits.
- Before opening a PR that touches `rtl/`, run the testbench and paste
  the verification result (mismatch count) in the PR description.
- Before opening a PR that touches `python/` or `c/`, run
  `python/verify.py` against your changes and confirm `Python == C`
  still holds.