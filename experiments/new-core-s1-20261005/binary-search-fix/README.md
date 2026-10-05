# binary_search at Rust's speed with every check kept (S1 checkpoint A, 2026-10-05)

Kernel: `test/core/binary_search.my`, function `search`
(`while low < high: middle = (low + high) // 2; if values[middle] < key: low = middle + 1 else: high = middle`).
No language change, and no check is removed without a proof: every check in `search` is
now *proven*, and `--verify-facts` asserts each fact the proofs use at run time.

## Result

Cycles and branch misses per search, `perf stat -e cpu_core/cycles/u,cpu_core/branch-misses/u`,
CPU 10, median of 7 interleaved rounds, start-up subtracted, every checksum identical
(`measure_regression.py`, raw output in `results/regression-kernels.txt`):

| Build | 4096 × 400: cycles | misses | 64 × 25000: cycles | misses |
|---|---:|---:|---:|---:|
| new core, end of S0 (93e516dc) | 139.5 | 3.09 | 30.7 | 0.022 |
| **new core, checkpoint A** | **30.4** | **0.072** | **17.9** | **0.013** |
| Rust (frozen campaign binary) | 37.6 | 0.207 | 19.5 | 0.036 |
| Zig ReleaseSafe | 137.2 | 2.86 | 28.0 | 0.045 |
| Zig ReleaseFast (separate 7-round run) | 55.1 | 0.455 | 28.2 | 0.032 |

Checkpoint A / Rust: **0.81×** at 4096 and **0.92×** at 64 (target ≤ 1.10×).

**No regression elsewhere** (same run; after/before cycles per element):

| | integer_math | float_math | call_direct | branch_predictable | branch_mixed |
|---|---:|---:|---:|---:|---:|
| single-kernel, 4096 / 64 | 1.005 / 0.997 | 1.002 / 0.999 | 0.994 / 1.011 | 1.004 / 1.005 | 0.994 / 0.996 |
| `compute_s0` (`--multi`), 4096 / 64 | 1.000 / 0.997 | 1.004 / 1.002 | 0.995 / 0.990 | 1.006 / 1.004 | 1.001 / 0.997 |

`compute_s0`'s binary_search kind: 91.7 → 31.9 (4096) and 31.5 → 18.5 (64).

## What changed, and what each part bought

| Stage (pipeline builds unless noted) | 4096 | misses | 64 |
|---|---:|---:|---:|
| S0 | 139.5 | 3.09 | 30.7 |
| 1. threshold widening + `nuw nsw` / unsigned emission | 76.0 | 1.40 | 23.9 |
| S0 analysis variant D rebuilt from its diffs (same idea, hand-edited) | 89.2 | 1.77 | 26.0 |
| 2. + length bounds (bounds check proven) | 40.2 | 0.22 | 23.4 |
| 3. + innermost loops aligned to 64 bytes (shipped) | 30.4 | 0.072 | 17.9 |

1. **Threshold widening** (`facts.zig` `widen`, NEW-CORE-FACTS-4). A phi that keeps changing
   widens each growing bound to the nearest of 0, 2^47 and 2^47 + 1 instead of the type's
   range; only phis widen. Facts now: `low, high ∈ [0, 2^47]`, `low + high ∈ [1, 2^48 − 1]`,
   `middle ∈ [0, 2^47 − 1]`. That proves both overflow checks, makes the floor division
   `udiv` (a shift), and decides `middle < 0`, so the negative-index normalization folds.
   The first attempt widened every value and failed: `low + high` grows to 2^48, past every
   threshold, jumped to the type range and dragged the phis with it.
2. **Emission** (`emit_llvm.zig`, NEW-CORE-LLVM-2): proven `+ - *` with non-negative operands
   and result as `nuw nsw`; comparisons of two proven non-negative values unsigned. Not in
   verify builds.
3. **The bounds check needed a proof of our own.** The S0 analysis said LLVM removes it in
   variant D. Rebuilt from the four diffs, D keeps it (`cmp; jae trap` in the loop) and runs
   at 89 cycles here; the ~37 measured in S0 is not reproducible and was probably a lucky
   layout (see 4). LLVM cannot derive `high ≤ len`: it is an invariant through a loop phi,
   which constraint elimination and SCEV do not prove. Rust keeps its bounds check too
   (`cmp; ja panic` in its loop); it is fast because of layout, not because the check is gone.
   So the fact pass now tracks **length bounds** (NEW-CORE-FACTS-5): `value ≤ len(p)` or
   `< len(p)` for a list *parameter* `p`, through conversions, `x + c`, `x + 1` under
   `x < len`, `x // d`, the midpoint `(x + y) // 2` under a dominating `x < y` (strictly
   below `y`), and phis. `high = phi(len, middle)` is `≤ len`, `middle < high`, hence
   `values[middle]` is in bounds; `values[low]` after `low < len(values)` is proven the same
   way. Optimistic (SCCP-style) and monotone; the verify build asserts every bound.
4. **Layout.** With every check gone, the loop is Rust's instruction for instruction
   (`lea; shr; cmp mem; jge; inc; cmp; jb`), and the remaining difference was placement:
   the same `.ll` relinked by hand ran 35.4 instead of 40.2, and 22.8 instead of 23.4.
   Shifting all of `main` by 0–3104 bytes (inline-asm padding at its entry, 8 offsets,
   3 rounds each):

   | Loop alignment | 4096: cycles (range over 8 offsets) | 64: cycles |
   |---|---|---|
   | LLVM default (16 bytes) | 30.1 – 88.3 (misses 0.06 – 2.0) | 17.8 – 26.7 |
   | every loop 64 (`-falign-loops=64`) | 31.0 – 45.0 | 17.6 – 18.3 |
   | **innermost loops 64** (shipped) | **32.4 – 39.7** | **17.6 – 18.6** |
   | Rust (same runs) | 35.9 – 37.7 | 19.5 |

   Rust's search loop happens to start on a 64-byte boundary. Golden Cove's uop cache and
   branch predictor work in 64-byte windows; the 33-byte loop straddling two of them pays
   two lookups per iteration, and its four branches are predicted from different windows
   depending on where the straddle falls. `target.zig` now passes
   `-mllvm -x86-experimental-pref-innermost-loop-alignment=6` (innermost loops only, so
   padding stays small and outer code is not spread out). It is a general policy for the
   one target (L4), justified by the window size, not by this benchmark; it changed nothing
   measurable on the other ten kernel rows (±1.1%). The option is marked experimental in
   LLVM; Zig pins the LLVM version, but an upgrade has to re-check it.

## Soundness and coverage

- `zig build test-core`: 40 tests pass (33 from S0, 7 new: widening unit test, the search's
  widened phis, binary search proven, three near-miss searches and an `<= len` read that
  must keep their checks, emission, verify asserts, verify and both new sabotage rules
  end to end).
- **Fuzz** (`fuzz.py`, extended: half the programs get a list-parameter helper, a binary
  search, strided scan or guarded read, half of them with an off-by-one mutation that the
  old core traps on; `results/fuzz.txt`): S0's size, 25 cases, **375 comparisons, 0
  mismatches, 0 `R_CORE_FACT`**; 200 cases, **3000 comparisons, 0 mismatches, 0 facts**.
- **Sabotage** (60 cases each): the S0 remainder rule caught in 52 of 60 (S0: 55 of 60,
  different programs now); `--sabotage-facts=widening` (a growing bound rounded to the
  threshold on the wrong side) caught in 35 of 60; `--sabotage-facts=length` (`len(p)`
  taken to be below itself) caught in 59 of 59 built. binary_search's verify build traps
  `R_CORE_FACT` under each (`range [0, 0]: value 3`, `below the list length`).
- **One fuzz failure, pre-existing:** seed 80 case 36's *release* build emits invalid LLVM
  IR (a vector-lowering resume phi used where it does not dominate). The S0 compiler fails
  the same way and the program has no list probe; repro in
  `results/vector-dominance-repro.my`. Not fixed here (vector.zig, outside this checkpoint).
- **Extra checks proven**, every function analysed alone (`mylang-core coverage`, which now
  prints `proven=P exact=E`), S0 rules (93e516dc plus the same counting) against checkpoint A:
  - coverage corpus (`coverage.py`, 974 accepted functions): checks left in reachable code
    **907 → 886**, proven 736 → 753;
  - `test/core` fixtures: **103 → 91** left, 180 → 184 proven;
  - 13 functions improve and none gets worse: `search` in binary_search, compute_s0 and the
    compute benchmark (6 checks → 0), `sort::is_sorted_ints/min_int/max_int` (bench/parity),
    `main::fold` (collections), `main::sum_values` (examples), `discard_names::after_the_loops`,
    `all_true` — reads `xs[j]` under `j < len(xs)` of a parameter.
- **Unconverged ranges fixed.** S0 kept the ranges of a function whose iteration did not
  settle (nothing proven) in the table the emitter reads for `!range` and `i32` narrowing;
  they are now cleared. No S0 fixture hit it.

## Not done, and found on the way

- Conditions joined by `and` (`if i >= 0 and i < len(xs)`) become a boolean phi, and edge
  refinement does not look through it, so neither the interval nor the length bound applies.
  The S0 analysis has the same gap; nested `if`s work.
- Length bounds cover list parameters only. A list built in the function is one value per
  iteration of its fill loop, so relating it needs dominance care; it keeps S0's length facts.
- **Pre-existing S0 memory-safety bug (not caused here):** `copy = xs; copy.append(v)` on a
  list parameter compiles to `list_push(param0, v)`; `myl_core_list_reserve` reallocates and
  frees the caller's block, so later reads see freed memory (garbage output at debug and
  release, S0 and checkpoint A; the old core prints `43 3`). The checker forbids appending
  to `xs` itself, but not to a copy. S1's ownership pass (uniqueness, copy on write) is
  where it belongs; when `mut` parameters or `append`/`pop` reach parameters, length bounds
  must exclude lists whose length can change.

## Files

- `measure_search.py`: binary_search builds against Rust, Zig Safe and Fast (cycles and misses
  per search).
- `measure_regression.py`: the S0 kernels before and after, single-kernel or `--multi`.
- `results/`: raw tables of the runs above.
