# Why `binary_search` is slower than Rust (2026-10-05)

## Setup
- Program: `test/core/binary_search.my`, compiled with `mylang-core --release --emit-llvm`.
- Variants: `.ll` hand-edits, shown in the diffs here, rebuilt with `zig cc -O3 -march=native`.
- Every variant prints the benchmark checksum: 46832836 for `4096 200 7` and 1314543 for
  `64 2000 13`.
- Measurement: `perf stat -e cpu_core/cycles/u,cpu_core/branch-misses/u` on CPU 10, five
  interleaved rounds, (220 − 20 iterations) × 4096 searches. These are exploratory numbers.

| Build | Cycles per search | Branch misses per search |
|---|---:|---:|
| new core today | 140 | 3.1 |
| A: no overflow check inside `low = middle + 1` | 134 | 2.9 |
| B: A, plus every check interval facts could remove (`low + high` overflow, floor-division fix-up, negative-index normalization) | 93 | 2.1 |
| C: B, plus no bounds check on `values[middle]` | **32** | **0.11** |
| D: B, plus `add nuw nsw` and an unsigned loop compare (LLVM then removes the bounds check itself) | **~37** | **~0.2** |
| Rust | 38–40 | 0.20–0.25 |
| Zig ReleaseSafe | 137 | 2.8 |

## Mechanism
- **Branchless code is not the difference.** Rust's search loop is branchy too: `cmp`, then
  `jge`.
- **The benchmark's keys follow a regular pattern,** so successive searches take nearly the
  same path, and the branch predictor learns them when the loop has only its two branches
  (the compare and the loop test).
- **Every extra conditional branch costs about 10× in mispredictions.** The extras are the
  bounds check, the overflow checks, Python's negative-index test and the floor-division
  fix-up. The bounds check matters most (B → C).
- Zig ReleaseSafe keeps a bounds check and an overflow check, and pays the same price.
- With random keys, every build would mispredict much more often and the gap would be
  smaller.

## Fix (no language change)
1. **Interval facts with threshold widening at the 2^47 platform bound** (NEW-CORE-FACTS-3)
   prove the following, which removes B's checks without relational analysis:
   - `0 ≤ low ≤ 2^47 + 1`;
   - `0 ≤ high ≤ len ≤ 2^47`;
   - `low + high` cannot overflow;
   - `middle ≥ 0`.
2. **Where the facts prove an operation non-negative and non-wrapping, emit `add nuw nsw`,
   `lshr` for `// 2`, and unsigned compares.** LLVM's own constraint elimination then proves
   `middle < high ≤ len` and drops the bounds check (D), so the new core needs no relational
   analysis of its own.
