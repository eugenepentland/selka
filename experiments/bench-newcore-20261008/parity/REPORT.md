# Parity suite on the new core: 2026-10-08

This is mylang's parity benchmark (`bench/parity`, 27 timed programs against Zig and Rust), rerun with the **new compiler core** (Core IR → LLVM → `zig cc`, `mylang build --release`) at `main` 5a6b501d. It is compared with the old QBE core's 2026-09-23 baseline in `bench/parity/thresholds.json` (batch `2026-09-23-cpu2-quiet`).

## Headline

| column | n | geomean | median | min | max |
|---|---:|---:|---:|---:|---:|
| **new core** my ÷ Zig ReleaseFast | 27 | **1.22** | **1.07** | 0.30 | 8.97 (nbody) |
| new core my ÷ Zig ReleaseSafe | 27 | 1.02 | 1.03 | 0.26 | 8.97 |
| new core my ÷ Rust | 24 | 1.24 | 1.10 | 0.18 | 7.77 |
| new core my ÷ Rust with overflow checks | 24 | 1.12 | 1.06 | 0.18 | 7.72 |
| old core my ÷ Zig ReleaseFast (2026-09-23) | 27 | 1.18 | 1.17 | 0.26 | 3.83 (matmul) |
| new ÷ old, per program | 27 | 1.03 | 1.00 | 0.36 | 4.50 |

- **Geomean against median.** The geomean moved from 1.18× to 1.22× Zig ReleaseFast, while the median improved from 1.17× to 1.07×.
  - Two large new regressions pull the geomean up: **nbody** (1.99× → 8.97×) and **str_build** (1.17× → 4.21×).
  - Without those two programs, the other 25 come to **1.07×** on the new core against 1.16× on the old one.
- **Programs slower than the references:**
  - 17 of 27 are slower than Zig ReleaseFast, 14 of them by more than 5%. The old core had 19 of 27.
  - 16 of 24 are slower than Rust, 14 of them by more than 5%.
  - 13 of 24 are slower than Rust with overflow checks.
- **By group** (geomean my ÷ Zig ReleaseFast, new against old):
  - suite (13 programs): 1.35 against 1.20;
  - lib (3): 0.98 against 0.93;
  - micro (11): 1.15 against 1.23.
- **The plan's suite targets are missed** (geomean ≤ 1.2, worst ≤ 1.5), because of nbody, matmul, knucleotide and text_ops.
- **Correctness:** every mylang arm (45, including the variants) built and printed its `.expected` output byte for byte.

## Per program

How the columns are computed:
- **Ratios** are wall time: the median of 9 per-round ratios, each mylang run paired with the reference's run in the same round.
- **÷ zig-safe, ÷ rust, ÷ rust-checked** are medians of the paired ratios my/arm taken in the same rounds.
- **Old** is the 2026-09-23 `my` baseline ratio from `thresholds.json`.
- **new/old** is the new ratio divided by the old one. Below 1 means the new core is closer to Zig.
- **instr** is the user-space instruction count from one `perf stat` run: mylang ÷ Zig ReleaseFast, and mylang ÷ Rust.
- The lib programs have no Rust port.

| group | program | zig-fast ms | my ms | my/zig-fast (95% CI) | my/zig-safe | my/rust | my/rust-checked | old my/zig-fast | new/old | instr my/zig | instr my/rust |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| suite | binary_trees | 220.6 | 211.6 | 0.96 (0.88-0.98) | 0.87 | 0.57 | 0.55 | 0.47 | 2.03 | 1.94 | 0.52 |
| suite | fannkuch_redux | 261.0 | 225.7 | 0.87 (0.85-0.87) | 0.72 | 0.83 | 0.86 | 1.14 | 0.76 | 0.85 | 0.94 |
| suite | knucleotide | 156.9 | 413.5 | 2.64 (2.58-2.69) | 2.34 | 1.67 | 1.66 | 1.49 | 1.77 | 2.68 | 1.40 |
| suite | mandelbrot | 183.8 | 184.5 | 1.01 (1.00-1.01) | 1.00 | 0.98 | 0.98 | 1.02 | 0.99 | 1.02 | 1.00 |
| suite | matmul | 57.2 | 230.3 | 4.04 (4.03-4.05) | 2.73 | 2.00 | 1.47 | 3.83 | 1.06 | 2.64 | 0.75 |
| suite | nbody | 203.7 | 1836.4 | 8.97 (8.86-9.05) | 8.97 | 7.77 | 7.72 | 1.99 | 4.50 | 5.83 | 5.97 |
| suite | raytrace | 101.7 | 108.9 | 1.07 (1.06-1.09) | 1.02 | 1.09 | 1.07 | 1.43 | 0.75 | 1.37 | 1.63 |
| suite | sieve | 138.3 | 181.1 | 1.35 (1.26-1.37) | 1.07 | 1.29 | 1.19 | 1.79 | 0.75 | 2.88 | 2.29 |
| suite | sort_builtin | 290.3 | 151.9 | 0.52 (0.49-0.53) | 0.45 | 1.61 | 1.62 | 0.49 | 1.06 | 0.77 | 1.30 |
| suite | sort_quick | 243.1 | 308.0 | 1.27 (1.23-1.31) | 1.11 | 1.34 | 1.31 | 1.28 | 0.99 | 1.24 | 1.96 |
| suite | sort_records | 161.0 | 48.0 | 0.30 (0.30-0.30) | 0.26 | 0.70 | 0.70 | 0.26 | 1.16 | 0.22 | 0.40 |
| suite | spectral_norm | 226.5 | 225.7 | 1.00 (1.00-1.00) | 0.77 | 1.00 | 0.88 | 1.13 | 0.88 | 1.16 | 1.17 |
| suite | text_ops | 37.8 | 78.5 | 2.08 (2.07-2.10) | 2.60 | 1.41 | 1.39 | 3.76 | 0.55 | 2.46 | 1.28 |
| lib | scan_count | 197.1 | 172.7 | 0.88 (0.85-1.36) | 0.46 |  |  | 0.68 | 1.29 | 1.26 |  |
| lib | scan_replace | 231.7 | 108.7 | 0.47 (0.46-0.48) | 0.28 |  |  | 0.35 | 1.35 | 0.67 |  |
| lib | scan_split | 49.8 | 116.4 | 2.28 (2.14-2.37) | 1.46 |  |  | 3.43 | 0.66 | 3.84 |  |
| micro | alloc_churn | 102.8 | 85.0 | 0.83 (0.82-0.83) | 0.76 | 0.69 | 0.69 | 1.93 | 0.43 | 0.45 | 0.17 |
| micro | bytes_scan | 54.7 | 80.5 | 1.44 (1.43-1.44) | 1.23 | 3.39 | 1.04 | 1.35 | 1.07 | 1.65 | 4.98 |
| micro | calls | 167.5 | 183.7 | 1.10 (1.09-1.10) | 1.08 | 1.38 | 1.34 | 1.00 | 1.10 | 0.68 | 0.89 |
| micro | dict_count | 34.8 | 13.8 | 0.40 (0.39-0.41) | 0.30 | 0.18 | 0.18 | 1.11 | 0.36 | 0.38 | 0.17 |
| micro | fib | 42.4 | 89.8 | 2.12 (2.10-2.15) | 1.04 | 1.90 | 0.90 | 2.12 | 1.00 | 1.50 | 1.58 |
| micro | float_loop | 51.4 | 51.8 | 1.01 (1.00-1.02) | 1.01 | 1.01 | 0.99 | 1.01 | 1.00 | 0.99 | 0.97 |
| micro | intloop | 162.7 | 168.3 | 1.03 (1.01-1.04) | 1.03 | 1.06 | 1.21 | 0.94 | 1.10 | 0.89 | 1.22 |
| micro | list_append_sum | 70.7 | 74.7 | 1.08 (1.04-1.10) | 1.03 | 1.00 | 0.95 | 1.17 | 0.93 | 1.13 | 1.12 |
| micro | list_records | 76.2 | 82.9 | 1.10 (1.06-1.14) | 1.03 | 1.11 | 0.99 | 1.37 | 0.80 | 3.18 | 2.69 |
| micro | records | 128.2 | 103.1 | 0.81 (0.80-0.83) | 0.90 | 0.97 | 1.08 | 0.93 | 0.88 | 0.93 | 1.18 |
| micro | str_build | 59.2 | 246.6 | 4.21 (3.84-4.25) | 3.10 | 3.64 | 3.58 | 1.17 | 3.61 | 10.37 | 9.42 |

### Variant arms (my-variant ÷ Zig ReleaseFast)

| program | variant | new core | old core (2026-09-23) |
|---|---|---:|---:|
| binary_trees | my-arena | 0.98 | 0.77 |
| fannkuch_redux | my-array | **3.44** | 0.87 |
| fannkuch_redux | my-tuned | **2.74** | 0.96 |
| knucleotide | my-arena | 2.63 | 3.21 |
| knucleotide | my-tuned | 0.66 | 1.36 |
| matmul | my-flat | 1.77 | 2.73 |
| matmul | my-tuned | 2.49 | 4.46 |
| nbody | my-class | **8.83** | 1.66 |
| raytrace | my-tuned | 1.06 | 1.25 |
| sieve | my-tuned | 1.34 | 1.82 |
| sort_records | my-keyed | 0.30 | 0.34 |
| sort_records | my-sorted | 0.30 | 0.26 |
| spectral_norm | my-tuned | 1.00 | 1.02 |
| text_ops | my-tuned | 0.94 | 0.66 |
| alloc_churn | my-arena | 0.83 | 1.58 |
| bytes_scan | my-wrapping | 0.58 | 1.35 |
| list_records | my-wrapping | 0.98 | 1.17 |

**Threshold check.** The harness checked 44 thresholded arms against `thresholds.json`.
- **10 exceeded their limit on both passes:**
  - binary_trees `my` and `my-arena`;
  - fannkuch_redux `my-array` and `my-tuned`;
  - knucleotide `my`;
  - nbody `my` and `my-class`;
  - text_ops `my-tuned`;
  - scan_replace `my`;
  - str_build `my`.
- **17 arms** came in under their baseline by more than the tolerance.
- **sort_records** `my` and `my-sorted` exceeded their limit on the first pass only (noise).
- **Interpretation:** the thresholds were set on the old core, so these results are information, not errors to fix. `thresholds.json` was not rewritten.

## Biggest remaining gaps (new core ÷ Zig ReleaseFast)

1. **nbody 8.97×** (old 1.99×). Five bodies are stepped 5,000,000 times with float arithmetic over a `list[Body]` of records, updated in place through `bodies[i].field = ...`.
   - It runs 5.8× Zig's instructions at IPC 1.60, against Zig's 2.48.
   - The `my-class` variant, the same value-record program, is just as slow (8.83×).
   - The emitted LLVM for `advance` is 20,767 lines, with 315 `memcpy` and 18 `myl_core_list_copy` call sites; every other function is about 300 lines.
   - This suggests each element-field store goes through a copy-on-write check and a record copy, not a single field store. Not confirmed beyond the call-site counts.
2. **str_build 4.21×** (old 1.17×; the confirmation pass gave 3.88×). Sixteen million 8-byte appends into a growable byte buffer.
   - It runs 10.4× Zig's instructions.
   - In the emitted IR, every append is an out-of-line call to `myl_core_buffer_range_valid` plus `myl_core_buffer_append_checked`.
   - CPU 10's SMT sibling was 38% busy while this program was timed. Both passes and the instruction ratio still agree that the gap is real.
3. **matmul 4.04×** (old 3.83×). A 500×500 float matrix multiply over `list[list[float]]`.
   - It runs 2.6× Zig's instructions, at IPC 2.03 against Zig's 3.19.
   - The flat-storage variant `my-flat` is 1.77× (old 2.73×).
4. **knucleotide 2.64×** (old 1.49×). Counts k-mers of a 1M-base sequence in a `dict[str, int]` keyed by substrings.
   - It runs 2.7× Zig's instructions.
   - `my-tuned` is 0.66× (old 1.36×).
5. **scan_split 2.28×** (old 3.43×). `str.split` over a 4 MB text.
   - It runs 3.8× Zig's instructions and has 9× Zig's cache misses per thousand instructions.
   - Peak RSS is 36.6 MB against Zig's 4.5 MB.
6. **fib 2.12×** (unchanged). Naive `fib(36)`, the call and frame protocol.
   - It is level with Zig ReleaseSafe (1.04×) and Rust with overflow checks (0.90×), so the remaining cost looks like the overflow checks.
7. **text_ops 2.08×** (old 3.76×). Builds, splits, parses and rewrites a 200,000-line text.
   - `my-tuned` is 0.94×.
8. **fannkuch_redux variants:** `my-array` 3.44× (old 0.87×) and `my-tuned` 2.74× (old 0.96×). These are the fixed-size-array forms of the permutation kernel.
   - Their IR has 29 `memcpy` and 19 `memmove` call sites.
   - The idiomatic `my` port improved to 0.87× at the same time.

## Biggest changes against the old core

**Largest improvements** (new ratio ÷ old ratio):
- **dict_count 0.36** (1.11× → 0.40×): it now beats Zig's `StringHashMap`, and is 0.18× of Rust's default-hasher map.
- **alloc_churn 0.43** (1.93× → 0.83×); its arena variant went from 1.58× to 0.83×.
- **text_ops 0.55** (3.76× → 2.08×) and **scan_split 0.66** (3.43× → 2.28×).
- **raytrace, sieve and fannkuch_redux 0.75** each.
- **Variants:** bytes_scan `my-wrapping` 1.35× → 0.58×; knucleotide `my-tuned` 1.36× → 0.66×; matmul `my-tuned` 4.46× → 2.49×.

**Largest regressions:**
- **nbody 4.50** (1.99× → 8.97×), and nbody `my-class` (1.66× → 8.83×).
- **str_build 3.61** (1.17× → 4.21×).
- **fannkuch_redux `my-array`** (3.95) and **`my-tuned`** (2.85).
- **binary_trees 2.03** (0.47× → 0.96×). It is still level with Zig's arena port and 0.57× of Rust's `Box` tree. The old core's 0.47× came from its tracing heap.
- **knucleotide 1.77** (1.49× → 2.64×).
- **Smaller:**
  - scan_replace 1.35 (0.35× → 0.47×);
  - scan_count 1.29 (wide interval);
  - sort_records 1.16;
  - calls 1.10;
  - intloop 1.10.

## Protocol

- **Compiler:** `$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang`, a ReleaseFast build of `main` 5a6b501d (sha256 `dce72f99ac4dd773a2b1fdc6bfdbffe3509f0d60b0f255845a42db9e52590b62`).
  - mylang arms are built with `--release`.
- **Harness:** `bench/parity/bench_parity.py run`, run directly with python3; the exact command is in `run.sh`.
- **Toolchains:** zig 0.17.0-dev.1683+5ceec001b and rustc 1.98.1 (at `~/.cargo/bin/rustc`). These are the same as on 2026-09-23.
- **Arms:** `my` and every mylang variant; `zig-fast` (the reference), `zig-safe` and the Zig variants; `rust`, `rust-checked` (`-C overflow-checks=on`) and the Rust variants.
  - That is 153 arms over 28 benchmarks.
  - 27 programs were timed; `binary_trees_recursive` has only a mylang port.
- **Machine:** i7-12700H. Every timed process was pinned to **CPU 10**.
  - The whole run (build, qualify and time) held `flock /run/user/1000/mylang-slots/cpu10.lock`.
- **Rounds:** 2 warm-ups, then **9 rounds** per program, with the arm order shuffled in each round and a fresh process for each sample.
- **Extra runs:** one `/usr/bin/time` run per arm for peak RSS, and one `perf stat` run per arm on CPU 10.
- **Times:** started 2026-10-08T07:56:55Z, ended around 08:08Z.
- **Load:** the 1/5/15-minute load average was 11.0/7.6/4.1 at the start and 8.7/8.6/6.3 at the end, from other agents.
  - CPU 11 (CPU 10's SMT sibling) was at most 9% busy while each program was timed, except during str_build (38%, flagged by the harness).
- **Confirmation:** the 8 programs over threshold got a fresh 9-round pass. Each reproduced its first pass within a few percent.
- **Deviations:**
  - `prebuild.py` built and qualified all arms once, outside the lock and on other CPUs, to warm caches. The measured run rebuilt every arm itself.
  - `TMPDIR` and `ZIG_GLOBAL_CACHE_DIR` were under `.mylang-cache/bench/parity/`.
  - The harness exited 1 because thresholds were exceeded, which is expected against an old-core baseline.

## Caveats

- **One batch against a pooled baseline.** The old-core baseline pooled two quiet 9-round batches on CPU 2; this run is one batch on CPU 10, with other agents active.
  - Changes under about 15% (calls, intloop, sort_records, scan_count) need a second batch before they count as real.
  - The large changes have narrow intervals, matching confirmation passes, and matching instruction counts.
- **scan_count's interval is wide** (0.85–1.36).
- **Instruction counts** come from one user-space `perf stat` run per arm.
- **Diagnoses are suggestions.** Those for nbody, str_build and fannkuch `my-array` rest on IR call-site counts only (`--emit-llvm` output under `.mylang-cache/bench/parity/ir/`, not kept here).
- **No tuning.** Nothing under `bench/parity`, `src/` or the programs was changed.

The run was made by a benchmark agent. The agent returned this report as text, and the coordinator wrote this file from it.
