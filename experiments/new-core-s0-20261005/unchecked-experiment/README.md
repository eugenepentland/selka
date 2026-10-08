# What the safety checks cost (2026-10-05)

Question: how fast would mylang be without its runtime checks? The checks are bounds,
integer overflow, division by zero, conversions, Python's negative-index normalization and
floor-division semantics.

## 1. New core, every check removed

- **Switch:** `unchecked-switch.diff` adds an experiment-only `--unchecked-experiment` to
  `mylang-core`. It marks every remaining `exact` check `proven`, so it emits `nsw`/`nuw`
  arithmetic, `udiv`, and indexing with no bounds check.
  - The diff is not applied on this branch.
  - The switch is an upper bound on what dropping the checks can gain: `udiv` assumes
    non-negative operands, which these benchmarks satisfy.
- **Method:** `measure.py`; `perf stat` user cycles and branch misses on CPU 10; 5 interleaved
  rounds with start-up subtracted.
  - Rust and Zig are the frozen campaign binaries in
    `runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin`.
  - Every checksum matches.
  - Confirmation B of the Codex campaign was running on CPU 2 at the same time.

Cycles per element, with branch misses per 1,000 elements in parentheses:

| Kernel (4096 × 4000) | New core, checked | New core, no checks | Rust | Zig ReleaseSafe | Zig ReleaseFast |
|---|---:|---:|---:|---:|---:|
| integer_math | 0.355 | 0.355 | 5.70 | 7.80 | 7.02 |
| float_math | 1.565 | 1.558 | 6.97 | 6.51 | 4.31 |
| call_direct | 0.301 | 0.301 | 2.02 | 3.02 | 2.02 |
| branch_predictable | 0.395 | 0.395 | 3.20 | 7.73 | 3.20 |
| branch_mixed | 0.395 | 0.394 | 4.87 | 9.26 | 5.00 |
| binary_search (per search) | 138.5 (3057) | 79.9 (1841) | 37.6 (201) | 136.7 (2840) | 55.5 (462) |

The 64 × 250000 size shows the same pattern: binary_search goes 30.6 → 19.2, with Rust
at 19.5; the other kernels change by 0–1%.

- **Five of six kernels:** removing every check changes nothing. The facts had already
  removed every check from the hot loops. The 22–37 trap sites still in each checked binary
  are in setup code (argument parsing, data building).
- **binary_search:** the checks cost 1.7×. The unchecked loop is Rust's shape (`lea`,
  `shr`, `cmp mem`, `jge`, `inc`, `jl`), but it still mispredicts nine times as often as
  Rust's.
  - Zig ReleaseFast, which has no checks, sits at 55.
  - The hand-edited variant C in `../binary-search-analysis` reached 32.
  - So once the checks are gone, this benchmark is decided by how well the branch predictor
    learns its key pattern for a particular code layout. Here LLVM unrolled the caller's
    loop and duplicated the search loop, which is one such layout difference. That is not a
    safety cost.

## 2. The whole 80-row suite: Zig ReleaseSafe against ReleaseFast

- **Source:** the same Zig source built with and without its checks (overflow, bounds,
  casts, unreachable). The figures are from
  `runtime-parity-20261003/experiments/runtime-levers-measurement-20261004/wp0/dashboard-L1.json`.
- **alloc_short is excluded** (78 rows): ReleaseSafe fills freed memory with `0xAA`, which
  makes it 89–1375× slower, and that is an allocator effect, not a check cost.

| Ratio | Geomean | Median |
|---|---:|---:|
| Zig ReleaseSafe / Zig ReleaseFast | 1.35 | 1.28 |
| Rust / Zig ReleaseFast | 0.93 | 0.88 |
| mylang LLVM (old core) / Zig ReleaseSafe | 1.17 | 1.21 |

- **The checks a compiler leaves in place cost about 28% (median).** Where Zig keeps them,
  that cost reaches 2–2.6× on branch_predictable, binary_search, bytes_scan and list_append.
- **Bounds checks alone are close to free.** Rust bounds-checks every index, wraps on
  overflow and is built for baseline x86-64, and it is still faster than Zig ReleaseFast on
  average.
- **What costs is overflow checking that is not removed,** together with check branches
  that the predictor cannot absorb.
