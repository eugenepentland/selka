# FS-X: lanes F1 and S1 and the shared-row fix, integrated, qualified and timed (2026-10-09)

**Who.** The coordinating Claude session wrote this report. The lanes were opus-lane agents:
- F1, aliasing and overflow facts: `experiments/f1-facts-20261009/REPORT.md`.
- S1, substring views: `experiments/s1-views-20261009/REPORT.md`.
- The shared-row wrong-answer fix: `experiments/fix-row-cow-20261009/REPORT.md`.

**Branch** `claude/fs-x`, in worktree `claude-parity-measure`. Not merged into `main`, not pushed.

| commit | what |
|---|---|
| `e1e9600a5` | the CPU-10 confirmation of wave PM's bounds, on `main` `cafe7fea7` |
| `baec7a434` | merge of F1 |
| `09b408b2a` | merge of S1 |
| `62bba8967` | merge of `claude/fix-row-cow` |
| `860b7426a` | coordinator fix NEW-CORE-FSX-VERSION-1 (below), plus run 1's evidence in `run1/` |
| `5b7756893` | run 2's tools |

**Base.** `main` `cafe7fea7`, timed with the PM-1 compiler `~/.cache/mylang/pm-a677da7a`, which has the same source. **Final** is `~/.cache/mylang/fs-final-x`, a ReleaseFast build of `5b7756893`.

## Result

**Correctness: every gate passes on run 2's final commit.**

| gate | run 2 (`5b7756893`) |
|---|---|
| `zig build test --summary all` | 88/88 steps, 2117 tests |
| fmt-check | pass |
| `qualify_merge` | qualified; conformance 1518/0/0 in debug and in release, with leak check and `--verify` (`qualify-fsx2/`) |
| frozen fuzz 9×200 | all 9 kinds PASS (`fuzz200-2/`) |
| Lox | 974/974 (vm 246+246, tree 241+241, normal and gc-stress); port tests 65/65 |
| EDA | 310/310 tests; 34/34 goldens |
| counting on and off | identical output on 48 Lox cells, 34 EDA cases, 4 parity programs and 46 rows |
| final against base | identical output on all 132 |

**Speed.** Wall time on CPU 10, final against base. Lox, EDA and parity come from run 1. llvm_diff shows run 2's LLVM is byte-identical to run 1's for all of them (below).

| corpus | final ÷ base | final position |
|---|---:|---|
| parity, `my` arm, 27 programs | **0.843** (geomean) | 0.78× Zig ReleaseSafe (was 0.93); 0.95× Zig ReleaseFast (was 1.13); 0.85× Rust with overflow checks |
| parity, all 44 arms | 0.878 | |
| EDA, 34 designs | 0.987 | 1.17× Zig ReleaseSafe, 1.29× Zig ReleaseFast, 1.15× Rust |
| Lox VM, 13 cells | 0.995 | 1.96× Zig ReleaseSafe, 2.93× Zig ReleaseFast (unchanged; not these lanes' target) |
| Lox tree-walker, 13 cells | 1.002 | 1.01× Zig ReleaseSafe |
| rows, 46 × 2 sizes | 0.994 (geomean of medians) | |

**The lane exits, in wall time** (parity, `my` arm, ÷ Zig ReleaseSafe; base is its same-session ratio to Zig ReleaseFast, rescaled by the final run's ReleaseFast/ReleaseSafe ratio):

| program | base | final | final ÷ base | exit |
|---|---:|---:|---:|---|
| matmul | 2.41 | **0.31** | 0.126 | F1 ≤ 0.4 ✓ |
| bytes_scan | 1.16 | **0.38** | 0.331 | F1 ≤ 0.4 ✓ |
| sieve | 1.18 | **0.86** | 0.739 | F1 ≤ 0.9 ✓ |
| calls | 1.08 | **0.99** | 0.914 | F1 ≤ 1.02 ✓ |
| knucleotide | 1.97 | **0.88** | 0.443 | S1 ≤ 1.0 ✓ |

Still above 1.1× Zig ReleaseSafe: text_ops 2.48, nbody 1.79, str_build 1.79, scan_split 1.34. These are the remaining lanes' (S2 and U1).

## Run 1 found a regression; the fix is NEW-CORE-FSX-VERSION-1

**What run 1 timed.** Run 1 (`62bba8967`) put `binary_search`/4096 at **3.74×** base in all three row batches. It also put `string_split`/4096 at 1.03–1.05×.

**Cause.**
- F1's callee return intervals bound each `search(...)` result. That made `total += search(...)` a reduction the pre-existing pass `version.versionReductions` could clone under a trip-count guard.
- In the clone, LLVM's x86 cmov converter turned the inlined binary search's conditional moves into branches.
- Those branches mispredict on random keys: 5.0 M branch misses against 0.11 M, with the same instruction count. Built with `-x86-cmov-converter=false`, the misses fall back to 4.5 k.
- `string_split` was newly versioned the same way.

**Fix** (`860b7426a`). A reduction loop is versioned only when its body makes no call and holds no other loop.
- The clone saves one check per trip. That pays only where LLVM can then vectorize or unroll a small body.
- Around a call or an inner loop it saves nothing measurable.
- The test in `cost_test.zig` fails without the fix.

**After the fix.**
- `llvm_diff.py` compared run 2's LLVM with run 1's for 94 programs: every parity program, every row, Lox and EDA. Only `binary_search` and `string_split` changed.
- Both are now at or below base: `binary_search`/4096 0.962 and `string_split`/4096 0.996 (CPU 8).

## Rows still above 1.03× in run 2, reviewed

Each row was measured with `perf stat` on CPU 8: 5 interleaved rounds, base against final binaries. Its LLVM was also compared after normalizing names, TBAA tags and site numbers.

| row | CPU 10 batches | CPU 8 instructions | CPU 8 cycles | what differs | verdict |
|---|---|---:|---:|---|---|
| string_search/64 | 1.19 1.20 1.20 | 0.977 | 1.18 | Setup code, and branch misses up from 3.2 k to 23 k. The hot loop is a runtime `find` call. The run is 3 ms. | layout: fewer instructions, more mispredictions |
| result_propagate/4096 | 1.09 1.07 1.06 | 1.000 | 1.06 | Only F1's zero-instruction memory barrier in the inlined free. Misses 71 k → 194 k. | layout |
| option_handle/64 | 1.05 1.02 1.07 | 1.000 | 1.08 | The barrier and 4 renumbered lines. Misses 148 k → 253 k. | layout |
| union_find/4096 | 1.03 1.03 1.03 | **1.0245** | 1.034 | F1 removes one overflow check (`components += 1`); nothing else changed. LLVM then makes a different choice. F1 alone reproduces it; TBAA and the barrier do not. | real but small: a downstream LLVM choice on strictly simpler input |
| sort_records/4096 | 1.24 1.18 1.00 | 1.000 | 1.010 | | noise |
| alloc_retained/4096 | 1.03 0.95 1.04 | 1.000 | 1.003 | only the barrier | noise |
| string_equal/64 | 1.04 0.97 1.04 | 1.000 | 0.995 | | noise |

**The parity arms at 1.03–1.06** (binary_trees `my-arena`, list_append_sum, list_records) differ from base only by the barrier line, and their confidence intervals overlap. They are noise.

**What's left.** Three rows lose 6–18% in the same way, through branch layout with identical or fewer instructions, plus `union_find`'s 2.5%. Everything else is at or below base.

## Not done here

- **The Lox VM ladder confirmation** (rungs 0, 2, 5 and 6, and `checks+norc`) is still to come, before F2 and U1.
- **The memory barrier.** F1's barrier in the inlined free (NEW-CORE-F1-TBAA-2) is what the TBAA soundness argument needs. It costs no instructions, but it shifts code layout. A narrower ordering, such as a barrier only between a free and a reuse inside one function, could be tried in lane R.

## Files

- **Tools:** `tools/`.
  - `run-fsx.sh` and `run-fsx2.sh` are the drivers. `part1a.sh`, `part1b.sh`, `timing-prep.sh` and `part3.sh` run the stages.
  - `llvm_diff.py`, `summarize.py`, `ce.py`, `identity.py` and `parity_locked.py`.
- **Run 2:**
  - logs: `logs/`;
  - timing: `results/` (rows; Lox, EDA and parity copied from run 1);
  - `results/llvm-run1-vs-run2.json`;
  - `qualify-fsx2/`, `fuzz200-2/`, `raw/`.
- **Run 1:** `run1/`. Its raw counters and fuzz command logs were removed to stay under 10 MB; their summaries remain.
