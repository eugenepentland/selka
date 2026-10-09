# FU-X: lanes F2 and U1 integrated on `main` `ab85c16c2`, qualified and timed (2026-10-09)

**Who.** The coordinating Claude session wrote this report. The lanes were opus-lane agents:
- U1, uniqueness and state: `experiments/u1-state-20261009/REPORT.md`.
- F2, index facts: `experiments/f2-index-20261009/REPORT.md`, rebased onto `ab85c16c2` at the user's request.

**Branch** `claude/fu-x`, in worktree `claude-parity-measure`. Not merged into `main`, not pushed.

| commit | what |
|---|---|
| `6d03c7693` | the Lox VM confirmation |
| `608fea290` | merge of U1 |
| `3d39b6f1b` | merge of `main` `ab85c16c2`: concurrency P1 and Juice; clean, with `SPEC.md` auto-merged |
| `96706fe79` | merge of F2. The conflicts were only adjacent additions: `passes.zig` runs F2's `index_checks`, then U1's `forward`, both after ownership; `MemoryState` takes both lanes' fields; `root_test.zig` registers both test files |
| `5c8decfd4` | coordinator test fix, below |

**Base.** `main` `ab85c16c2`, with the ReleaseFast compiler `~/.cache/mylang/main-ab85c16c`. **Final** is `~/.cache/mylang/fu-final-x`.

## Correctness (attempt 3, `5c8decfd4`)

| gate | result |
|---|---|
| `zig build test --summary all` | 91/91 steps, 2172 tests |
| fmt-check | pass |
| `qualify_merge` | qualified; conformance 1518/0/0 in debug and in release (`qualify-fux3/`) |
| frozen fuzz 9×200 | all 9 kinds PASS (`fuzz200-fux3/`) |
| Lox | 974/974 (246 + 246 + 241 + 241) |
| Lox port tests | 65/65 |
| EDA | 310/310; 34/34 goldens |
| counting on and off | identical on 48 Lox cells, 34 EDA cases, 4 parity programs and 46 rows |
| final against base | identical output on all 132 |

**Two receipts are cached.** In attempt 3, the Lox port tests and the EDA tests reported "0 passed, 65/310 cached, 0 failed". The compiler is byte-identical to attempt 2's (hash `52206a81…`; only a test file changed), and attempt 2 ran both fresh: 65/65 and 310/310 (`attempt2-sabotage-msg/logs/`).

**Earlier attempts:**
- **Attempt 1** (`attempt1-diskfull/`): `/home/epentland/ai` was 100% full, and every build failed with "No space left on device". With the user's go, `scripts/prune-caches.sh --apply` then freed 412 GiB.
- **Attempt 2** (`attempt2-sabotage-msg/`): one test failed: F2's `NEW-CORE-F2-FIELD-3` probe. That probe sabotages a field interval and expects verify to catch it at the read of `s.v`. With U1's field forwarding (NEW-CORE-U1-STATE-1) the read becomes the stored value, so verify catches the wrong interval one step later, at `s.v * 2` ("range [6, 12]: value 14"), in the same function and on the same line. Verification still works. The fix, `5c8decfd4`, makes the test assert the trap in `small` at line 101 instead of the exact range.

## Speed: final ÷ base, wall time on CPU 10

The machine carried load 3–9 from other sessions during the timing, so the absolute times are noisy. Every comparison is interleaved within one session.

| corpus | final ÷ base | final position |
|---|---:|---|
| **Lox VM, 13 cells** | **0.787** | 1.62× Zig ReleaseSafe (was 1.96), 2.47× Zig ReleaseFast |
| Lox tree-walker, 13 cells | 0.928 | 0.99× Zig ReleaseSafe |
| parity, `my` arm, 27 programs | 0.943 (geomean) | **0.74× Zig ReleaseSafe** (was 0.79); 0.91× Zig ReleaseFast |
| parity, all 44 arms | 0.926 | |
| EDA, 34 designs | 0.995 | 1.21× Zig ReleaseSafe, 1.32× Zig ReleaseFast |
| rows, 46 × 2 | **0.951** (geomean of 3-batch medians) | |

**The lanes' targets, in wall time (÷ Zig ReleaseSafe unless noted):**
- str_build 1.80 → **0.76** (U1 ≤ 1.0, met);
- sort_quick 1.20 → **1.00** (F2 ≤ 1.0, met);
- nbody 1.61 → **1.39** (U1 ≤ 1.35 was met in cycles on CPU 6; wall time is just over);
- Lox vm/string_equality **0.583×** base (F2 ≤ 0.80, met);
- Lox VM cells 0.80–0.84× base, against U1's step-loop target of 0.85.

**Other notable cells:**
- rows record_update and record_construct: **0.37–0.39×** (F2's field intervals);
- matmul_flat: 0.26×;
- list_filter/64: 0.86×;
- lox_eval: 0.89×;
- binary_search/4096: 0.89×.

**Still above 1.1× Zig ReleaseSafe:** text_ops 2.61, nbody 1.39, scan_split 1.30. These are lanes S2 and R.

## Cells above 1.03×, reviewed

| cell | CPU 10 | CPU 8 instructions | CPU 8 cycles | verdict |
|---|---|---:|---:|---|
| rows result_propagate/4096 | 1.067, 1.075, 1.070 | 1.000 | 1.081 | layout: branch misses 72 k → 209 k with the same instructions; the same pattern FS-X saw |
| rows packet_decode/4096 | 1.097, 1.090, 1.014 | 1.010 | 1.063 | small and real: U1 traced it to setup comprehensions that gained in-register state, after which LLVM re-scheduled `main` |
| rows packet_decode/64 | 1.061, 1.062, 1.011 | 1.011 | 1.043 | same |
| parity list_records `my` | 1.049 (confidence intervals overlap) | **0.910** | about 1.05, noisy (128–146 M) | memory-bound; 9% fewer instructions |
| parity list_records `my-wrapping` | 1.036 | 0.912 | about 0.97 | noise |

## Rows method (changed for this run)

`measure_all46.py` refused to run: its frozen Rust, Zig and Go reference runner (`runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin`) was removed by today's cache prune.

`tools/rows_mylang.py` measures final against base only, with `measure_all40`'s own `sample` (perf cycles on CPU 10), units, seed and startup subtraction, in 3 batches of 7 interleaved rounds. Its results are `results/rows-mylang-{1,2,3}.json`.

The reference runner needs a rebuild (`benchmarks/runtime/expanded/run.py --build-only`) before rows can be compared with Rust and Zig again. Its worktree should then be marked `prune-keep`.

## Not in this integration

`main` has moved past `ab85c16c2`:
- `d21b2dfa9`: the readable syntax redesign;
- `e23651f6a`: optimized debug guest builds.

Merging `claude/fu-x` into `main` therefore needs a port:
- merge the new `main`;
- migrate the lanes' new fixtures and embedded test sources with `mylang fix`;
- run the gates again;
- compare LLVM to see which timing carries over.

The external Lox and EDA ports are in the old syntax and need migrating too. The port runs on branch `claude/fu-port`.
