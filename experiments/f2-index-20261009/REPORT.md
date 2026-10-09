# Lane F2 report: index facts (2026-10-09)

**Who wrote this file.** An opus-lane agent ran lane F2 of `docs/audits/runtime-parity-plan-2026-10-08.md` §8. Its tool refused report files, so the coordinating Claude session wrote this file from the agent's final message, after checking the receipts in `gates/`:
- 91/91 steps, 2168 tests;
- `qualify-3d24b0048`: qualified, conformance 1518/0/0 in debug and in release;
- `fuzz50-21c4b551d`: qualified and complete, 9/9 kinds;
- Lox 246 + 246 + 241 + 241, port tests 65 passed;
- EDA 310 passed.

The commits after `541e801a7` hold evidence only.

**Where.** Branch `claude/f2-index`, rebased onto `main` `ab85c16c2` at the user's request.
- Rebased commits:
  - `01bf18b46`, step 1;
  - `12f6e0996`, step 2;
  - `c92d71805`, step 3;
  - `541e801a7`, step 3's fix.
- Evidence: `6c06a1b2f`, `3d24b0048`, `21c4b551d`, `5d4263765`.
- The ReleaseFast compiler is `~/.cache/mylang/f2-541e801a`.
- Nothing was merged or pushed.

## Exit (against `~/.cache/mylang/main-ab85c16c`, CPU 8, `perf stat`, 5 interleaved rounds)

| exit | result |
|---|---|
| Lox VM bounds checks ≤ 2 per dispatch | **not met: 4.875** (7.000 before); not soundly reachable, see below |
| vm/string_equality ≤ 0.80× today's cycles | **met: 0.761** |
| sort_quick ≤ 1.0× Zig ReleaseSafe | **met: 0.992** (1.105 before) |
| no wrap on an index proven ≥ 0 | met |
| nothing slower than 1.03× | met in cycles. One outlier in instructions: fannkuch_redux, 1.145× instructions but 0.936× cycles |
| gates | all pass on the rebased head |

## A wrong answer on `main`, fixed (NEW-CORE-F2-INDEX-1)

**The bug.** In release builds, a counted fill loop's length fact was applied inside the loop. So `zs[i]` read before `zs.append(i)` counted as in range, and the read went past the end: the release build printed 25 where debug traps `R_LIST_BOUNDS`.

**The fix.** The fact now holds only where the fill loop's exit dominates the value. It has a test.

## What changed

- **WRAP-1.**
  - A checked `xs[i]` with a signed `i` first compares the written `i` unsigned against the length. Below the length, the address uses `i`.
  - Negative or out-of-range indexes go to a cold block that normalizes, checks, and traps with the written index.
  - A later proven access reuses the value an earlier check computed.
- **INDEX-2 (`index_keys.zig`).**
  - Value keys see through fields, single-valued phis and constant offsets.
  - List length keys survive element writes, copies, sorts and phis. They are computed over strongly connected components; this removes nbody's 125 M checks.
  - A dominating `x < len(other)` proves accesses to any list with the same length key.
- **INDEX-3/4 (`index_checks.zig`, after ownership).** A check a dominating check already made is proven:
  - the read and write pair of `rt.frames[k] = frame`;
  - sort_quick's swap;
  - pop then push.

  `--sabotage-facts=index` probes it.
- **INDEX-5.** An access is proven when every edge into its loop header carries the same check. This removes the VM's dispatch-head `rt.frames[rt.frame_count - 1]` check.
- **FIELD-1..3 (`fields.zig`).**
  - Each integer or boolean field of a closed record type gets the hull of every value written into it.
  - Verify builds assert it at every read; `--sabotage-facts=field` probes it.
  - The table is `facts.FieldIntervals`, and `fieldsOf` falls back to it, which is how U1's forwarded phis can see it.
- **VERSION-1/2.**
  - A small, flat, counted loop that carries and leaves only scalars, indexing at `I + i`, `i - I` or `I - i`, is cloned with its checks proven. One guard before the loop range-tests every trip.
  - `--sabotage-facts=version` probes it.
  - Restricting it to loops that carry only scalars (`541e801a7`) fixed a compile-time blowup: `f1_tbaa.my` took 144 s and 2 GB under ownership.

## Why the field ranges are sound

**What can write a field.**
- A field is written only by `record_make`, `record_set` (including through `mut` callees) and `list_set_field`.
- Moving a record anywhere else copies it whole and writes no field.

**Which types get no intervals.** A type is open, and gets none, if any of these can hold it:
- a runtime, extern or host signature;
- the entry function's parameters;
- the parameters of any function a `func_ref` names;
- any operation other than the copies;
- an enclosing open type.

**Why every write is counted.** Indirect calls reach only module functions, and extern code never sees a closed type.

**Rounds.** The hull is computed in two rounds, each sound on the previous one's facts.

**The Lox fields get no interval.** `stack_top`, `ip`, `base` and `frame_count` are written unguarded with `x - 1`-style values, and Python indexes wrap. `frame_count >= 1` is actually false: after a runtime error `reset_stack` sets it to 0, and the dispatch tail indexes `frames[-1]`. `step3/frame-count-probe.log` has an assertion failing on `fun f() { return 1 + nil; } f();`.

## Measurements (against the new `main`)

**Lox VM step cell, per dispatch:**
- bounds checks 7.000 → 4.875;
- overflow checks 7.125 → 6.688;
- uniqueness tests 1.625, unchanged.

| Lox cell | instructions | cycles |
|---|---:|---:|
| vm/step | 0.789 | 0.808 |
| vm/fib | 0.854 | 0.805 |
| vm/string_equality | 0.759 | **0.761** |
| vm/invocation | 0.896 | 0.773 |
| vm/method_call | 0.875 | 0.801 |
| tree/invocation | 0.975 | 0.943 |
| tree/equality | 0.944 | 0.894 |

**Per site:**
- sort_quick: the swap's 41.1 M checks and `for v in values`'s 2 M are gone. The scan loops' 56.3 M remain; their trip counts depend on a sentinel.
- sieve: every bounds check is gone. It runs 0.817× instructions, and its cycles are unchanged (0.860× Zig ReleaseSafe).

**Juice.** sort_quick scores 79.6. On the multi-module Lox port `juice compare` fails with "InvalidExperiment: duplicate attribution identity", which looks like a Juice bug. The raw record counts agree with `perf`.

**No regression:**
- Parity: geomean 0.963× cycles and 0.929× instructions; highest cycles 1.012.
- EDA: 0.991 / 1.002 and 0.994 / 1.007.
- Rows, 46 × 2: geomean 0.953× cycles; no instruction ratio above 1.0022. record_update and record_construct run at about 0.37–0.39× cycles from the field intervals.
- Rows flagged at 5 rounds (mutate_nested/4096, bytes_scan/4096, binary_search/4096) came out at 0.988, 1.002 and 1.007 at 15 rounds, with identical instructions.

## Tests

- **Zig tests:** 18 in `src/core/f2_index_test.zig`.
- **Fixtures:** `test/core/f2_index.my`, `f2_fields.my`, `f2_version.my` and `f2_header.my`, each run in debug, release and verify under the leak check. They cover:
  - wraps;
  - one-path negatives;
  - the fill-loop trap;
  - pops and shrinking loops;
  - fields written far away;
  - same-length and shorter lists;
  - versioned loops with failing guards, `break`, prints before traps and huge offsets;
  - header edges;
  - a sabotage probe for each fact kind.
- **Updated tests:** `emit_llvm_test` (S5-COLD-INDEX-1) and `value_emit_test` now match the new emission.

## Limits

- **4.875 Lox bounds checks per dispatch remain.** All are driven by bytecode data or by state a call can change:
  - `code[ip]`: 1.5;
  - the dispatch-tail `frames[frame_count - 1]`: 1.0;
  - `heap::peek`: 0.69. It is not inlined, because its body has checks;
  - stack pops, pushes and locals: 1.38;
  - operands: 0.31.

  A Zig ReleaseSafe port checks these too.
- **The overflow check on `frame_count - 1` at the dispatch head** is redundant by the header-edge argument, but overflow checks are F1's area.
- **Unswitching clones nbody's inner loop 16 times** on `i < 0` tests the facts later prove false. This is existing behaviour; the clones are dead.
- **matmul_tuned's comprehension** is not versioned, because it carries a list.
