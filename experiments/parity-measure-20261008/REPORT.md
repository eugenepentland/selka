# Wave PM report: where the remaining gap to Zig and Rust comes from (2026-10-08)

**Who wrote this file.** An opus-lane agent ran wave PM of `docs/audits/runtime-parity-plan-2026-10-08.md`. Its tool refused report files, so the coordinating Claude session wrote this file from the agent's final message.

**Receipts the coordinator checked first:**
- `pm1/llvm-identity.log`: 94 of 94 LLVM texts byte-identical with counting off. The executables are identical after `objcopy --strip-debug`; they differed only in DWARF `comp_dir`.
- `pm1/gate-test-summary.log`: 88/88 steps, 2095 tests.
- `qualify/`: qualified on `a677da7a0`. test-core 504/0/0; conformance 1518/0/0 in debug and in release.
- `fuzz50/matrix.json`: qualified, with the source and the oracles unchanged.

**Where the work is.** Branch `claude/parity-measure`:
- `a677da7a0`: PM-1, the counters;
- `e15e92586`: the evidence.

The branch is based on `136335cb4`, which is the plan on `2141c4f6b`, the CE2 integration now in `main`. Nothing was merged or pushed.

## Short version

The gap is not one lever. Four facts carry most of it, and each hits a few programs hard. The bounds below are cycles relative to today. "cf" means the real release LLVM, edited to remove one kind of work, rebuilt with the driver's flags and runtime, and output-checked. "ladder" means hand-written ideal C.

1. **Element-type alias facts (TBAA by element type), plus no store-back of an unchanged element pointer.** matmul alone goes to **0.11**: 2.78× → about 0.31× Zig ReleaseSafe.
2. **Overflow facts for counters and loop variables.**
   - bytes_scan **0.29**: the check on `count += 1` blocks vectorization.
   - sieve 0.74.
3. **Views instead of materialized substrings and split pieces.**
   - knucleotide **0.44** (ladder);
   - scan_split **0.49**, and 0.40 with a lazy split (ladder);
   - most of text_ops and part of EDA.
4. **Count traffic, uniqueness tests, and loop-carried state kept in memory.**
   - Lox VM: checks plus counts give 0.49–0.71;
   - nbody **0.82**, from the uniqueness test;
   - str_build 0.90 (cf), and 0.42 (ladder) once len stays in a register.

**Bounds checks matter less than the plan assumed.** Only the Lox VM (0.73–0.92), sort_quick (0.93) and sieve (0.96) gain cycles from removing them. matmul's 0.45 without checks is really its aliasing.

**Several "over 1.1×" rows are not compiler levers:**
- calls and intloop against Rust: LLVM's unsigned magic-number modulo, plus calls' floor-mod fix-up (0.94). Both are level with Zig.
- fib against Zig ReleaseFast: needs the overflow check and `notail` both gone (0.45), which L1 forbids. fib is level with Zig ReleaseSafe (1.03).
- nbody's remaining 1.33×: the references use fixed `[5]Body` arrays, which unroll fully.
- sort_builtin against Rust: the runtime sort algorithm.
- fannkuch `my-array`: every element get and set copies the whole 80-byte array (622 M copies, 49.8 GB).

## PM-1: check-traffic counters (`a677da7a0`)

**Counting builds.** A counting build now counts every conditional trap the emitted code reaches. There is one site per check, recorded at `FunctionEmitter.trapBegin`, the one place where every conditional trap is emitted. The kinds:
- `bounds_check`: list, text and byte indexes, pop and index of an empty list, substring bounds;
- `overflow_check`;
- `division_check`;
- `shift_check`;
- `other_check`: casts, float conversions, fact verification and similar.

Unconditional traps are not counted.

**Cost output.** `mylang cost --counters` adds each function's checks by kind:
- in text, as `; checks: bounds N, overflow N, division N, shift N, other N`;
- in JSON, as a `checks` object beside `run`.

**Documentation.** `docs/tooling/counters.md` documents the new kinds, their limits, and the recipe for counts per instruction retired. The limits:
- checks the core removed are never counted;
- checks LLVM removes later still are;
- checks inside the runtime are not counted.

**Spec and files.**
- Spec: `NEW-CORE-COUNTERS-6` (the check sites) and `-7` (the cost output).
- Tests: `src/core/count_test.zig`, with the fixture `test/core/counters_checks.my`.
- Files changed:
  - `emit_count.zig`;
  - `emit_llvm.zig` (`checkKind`, and one line in `trapBegin`);
  - `runtime/core_count.c`;
  - `cost_dynamic.zig`.

**Gates on `a677da7a0`:**
- Guardian: 88/88.
- `zig build test --summary all`: 88/88 steps, 2095 tests.
- `fmt-check`: exit 0.
- `qualify_merge`: qualified. test-core 504/0/0; conformance 1518/0/0 in debug and in release.
- Frozen fuzz 9×50: qualified.
- **LLVM identity with counting off:** 94 of 94 identical. The base was a ReleaseFast build of a `git archive` export of `136335cb4`, compared with the PM-1 compiler, over release and debug, all 45 parity programs, Lox and EDA.
- Counting on against off: the same output on 15 parity programs, 4 Lox cells and 2 EDA designs.

## PM-2: profiles and attribution

**Method.**
- perf user events on CPU 8 (a P-core). Arms were interleaved and shuffled, and each figure is the median of 3–5 rounds.
- Instruction counts are exact. Cycles are relative within one run, on a shared machine with a load average of 5–10.
- perf record/annotate, each program repeated for 6–8 s at 1000 Hz.
- `tools/cf.py`. An unedited rebuild reproduced each real binary's instruction count exactly. A variant whose output changed is marked ✗ and is not a valid bound. The variants:
  - `bounds`, `overflow`, `checks`: trap branches never taken;
  - `unique`: `is_unique` returns true;
  - `norc`: retains and releases skipped, so blocks leak;
  - `tbaa`: element data tagged by scalar type;
  - `tail`: `notail` dropped;
  - `inline`: inline threshold 1000.

### Reference ratios

User cycles on CPU 8, mylang ÷ each reference.

| program | ÷ zig-fast | ÷ zig-safe | ÷ rust | ÷ rust-checked | IPC |
|---|---:|---:|---:|---:|---:|
| matmul | 4.26 | **2.78** | 2.05 | 1.50 | 2.02 |
| text_ops | 1.89 | **2.52** | 1.32 | 1.30 | 3.96 |
| knucleotide | 2.50 | **2.21** | 1.79 | 1.79 | 3.11 |
| str_build | 3.05 | **1.59** | 2.40 | 2.39 | 1.83 |
| nbody | 1.62 | **1.62** | 1.40 | 1.40 | 3.73 |
| scan_split | 1.68 | 1.14 | — | — | 3.42 |
| sieve | 1.61 | 1.14 | 1.56 | 1.33 | 2.03 |
| bytes_scan | 1.34 | 1.06 | 3.98 | 0.89 | 4.94 |
| sort_quick | 1.28 | 1.10 | 1.35 | 1.32 | 1.30 |
| sort_builtin | 0.50 | 0.43 | 1.76 | 1.79 | 1.79 |
| calls | 1.10 | 1.07 | 1.39 | 1.35 | 0.99 |
| intloop | 1.03 | 1.03 | 1.08 | 1.21 | 1.03 |
| fib | 2.13 | 1.03 | 1.92 | 0.90 | 2.97 |
| fannkuch `my-array` | 3.33 | 2.77 | 3.18 | 3.32 | 3.11 |
| Lox vm/fib | 2.80 | **2.22** | 2.01 | — | 5.23 |
| Lox vm/string_equality | 3.72 | **2.92** | 2.29 | — | 6.55 |
| Lox vm/invocation | 4.29 | **2.58** | 2.22 | — | 4.83 |
| Lox vm/method_call | 3.32 | **2.41** | 2.24 | — | 4.89 |
| Lox tree/invocation | 1.21 | 0.72 | 1.15 | — | 4.77 |
| Lox tree/equality | 1.54 | 1.43 | 1.54 | — | 5.90 |
| EDA rds3+flat | 1.60 | **1.44** | 1.21 | — | 3.61 |
| EDA labstation | 1.71 | **1.47** | 1.16 | — | 3.89 |

**Notes:**
- **L1 misses per thousand instructions** are high in four programs, mylang against Zig ReleaseSafe:
  - text_ops: 1.39 against 0.06;
  - str_build: 2.65 against 0.11;
  - scan_split: 1.42 against 0.30;
  - EDA: 2.1–2.5 against 1.1–1.6.
- **The `bench_parity.py` wall ratios** (`--cpu 8`) agree with these cycle ratios to within about 10%.

### Counterfactual attribution

Each cell is the variant ÷ the unedited rebuild, as instructions/cycles.

| program | bounds | overflow | checks | unique | norc | tbaa | combined |
|---|---|---|---|---|---|---|---|
| matmul | 0.54/0.45 | 1.00/1.00 | 0.54/0.45 | 1.00 | 1.00 | **0.11/0.11** | all three 0.09/0.11 |
| text_ops | 1.00/0.97 | 1.00/0.99 | 0.99/0.99 | 1.00 | 0.81/0.98 | 1.00 | |
| knucleotide | 1.00 | 0.99/1.01 | 0.98/1.00 | 1.00 | ✗ | 1.00 | |
| str_build | 1.00 | 1.00 | 1.00 | **0.69/0.90** | 0.81/0.95 | 1.00 | |
| nbody | 0.84/1.01 | 1.00 | 0.84/1.02 | **0.67/0.82** | 0.96/0.98 | 1.00 | |
| scan_split | ~1 | ~1 | 0.99/1.00 | 1.00/0.99 | 0.81/0.81 | 1.00 | |
| sieve | 0.86/0.96 | **0.79/0.74** | 0.60/0.73 | 1.00 | 1.00/1.06 | 1.00 | |
| bytes_scan | 1.00 | **0.20/0.29** | 0.20/0.29 | 1.00 | 1.00 | 1.00 | |
| sort_quick | 0.80/0.93 | 1.11/1.00 | 0.74/0.90 | 0.84/0.96 | 0.99/1.00 | 1.00 | all three 0.70/0.96 |
| calls | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | floor-mod fix-up removed by hand 0.94/0.94 |
| fib | 1.00 | 0.71/1.00 | 0.71/1.00 | 1.00 | 1.00 | 1.00 | overflow + tail 0.69/**0.45** |
| fannkuch `my-array` | 1.02/1.00 | 0.94/0.99 | 0.93/1.00 | 1.00 | 1.00 | 1.00 | |
| Lox vm/fib | 0.79/0.88 | 0.94/1.07 | 0.71/0.84 | ✗ | 0.77/0.80 | 1.00 | checks+norc 0.50/**0.69** |
| Lox vm/string_equality | 0.68/0.73 | 0.88/0.89 | 0.56/0.77 | ✗ | 0.93/0.93 | 1.00 | checks+norc 0.54/0.71 |
| Lox vm/invocation | 0.85/0.90 | 0.93/1.03 | 0.78/0.82 | ✗ | 0.69/0.66 | 1.00 | checks+norc 0.49/**0.49** |
| Lox vm/method_call | 0.83/0.87 | 0.93/1.00 | 0.76/0.83 | ✗ | 0.72/0.71 | 1.00 | checks+norc 0.49/0.57 |
| Lox tree/invocation | 0.93/0.93 | 0.95/0.97 | 0.86/0.90 | 0.87/0.92 | 0.72/0.83 | 1.00 | all three 0.75/0.83 |
| Lox tree/equality | 0.90/0.98 | 0.98/1.00 | 0.87/0.93 | 0.98/0.97 | **0.58/0.60** | 1.00 | |
| EDA rds3+flat, labstation | 0.99/0.98–1.00 | 0.98/0.99 | 0.97/0.99 | ✗ | ✗ | 1.00 | `reference_at` inlined 0.97/0.98 |

**The Lox VM's cycle response is non-monotonic.** In the step loop, removing bounds checks gives 0.92 of cycles and removing all checks gives 1.07. Cycles there depend on layout and memory-dependency chains.

**Counters per thousand instructions** (`counters/`):
- matmul: 572 bounds checks;
- nbody: 409 bounds checks, 21.5 uniqueness tests;
- str_build: 62.7 uniqueness tests;
- knucleotide, scan_split, text_ops: 2.5–3.3 allocations;
- fannkuch `my-array`: 78 record copies of 80 bytes;
- **the Lox VM, per dispatch:** about 7 bounds checks, 7 overflow checks and 1.6 uniqueness tests. `read_constant` does 3 retains and 3 releases per constant.

### Where mylang's extra instructions go

- **matmul.**
  - One `myl.data` TBAA tag covers both float elements and row-pointer slots.
  - `c[i][j] = …` stores c's row pointer back after every element.
  - So b[k]'s row pointer, its length and c[i]'s row are reloaded per element. The check can't hoist, and the loop can't vectorize.
  - The result is 3 floating-point instructions plus about 7 others per element.
- **bytes_scan:** the overflow check on `count += 1`.
- **sieve:**
  - overflow checks on `j = j + i` and `count += 1`;
  - bounds checks on `flags[j]`.
- **fib:**
  - the overflow check costs instructions but no cycles;
  - tail-recursion elimination needs both the check and `notail` gone. `notail` is emitted for DWARF trap caller chains (`emit_llvm.zig:3476`).
- **calls and intloop:** latency-bound on `% 1000003`. LLVM uses the unsigned magic sequence for known-non-negative operands, and calls also keeps the floor-mod fix-up in `step`.
- **nbody:** the per-pair uniqueness test. The residual is the references' fixed-length arrays.
- **str_build:** a uniqueness test per append. The untyped 8-byte `llvm.memmove` keeps len in memory, which makes a store-to-load-forwarding chain each iteration.
- **sort_quick:**
  - branch-miss bound, at 17 per thousand instructions;
  - Rust's partition runs half the instructions.
- **sort_builtin:** `myl_core_s2_sort_in_place` is 74% of instructions. That is the algorithm.
- **knucleotide:**
  - materialization 43%: `str_slice`, `str_from` and the ASCII re-scan;
  - allocation and free 12%;
  - hash and compare 19%.

  The dictionary itself is not the problem.
- **scan_split:**
  - allocation and free 39%;
  - piece copies 20%;
  - search 41%.
- **text_ops:**
  - allocation and free 28%;
  - materialization and copies 30%;
  - search, split and replace 33% (memmem 15%).
- **fannkuch `my-array`:** whole-array copies on every element get and set.
- **Lox VM:**
  - checks;
  - count traffic on the call-heavy cells: frame copies, and `read_constant`'s 3 retains and 3 releases;
  - the frame record spilled, with ip written back twice per dispatch;
  - `rt.stack_top` kept in memory;
  - Python's negative-index wrap on every index not provably non-negative.
- **Lox tree-walker:** equality is count traffic (0.60). invocation is already 0.72× Zig ReleaseSafe.
- **EDA:**
  - allocation and free are 24–29% of instructions: `block_alloc`, `free_block`, and the interpreted layout walk `reference_at` at 10.5%. Zig's arenas spend about 11%;
  - text materialization 10–12%, against Zig's 2%;
  - checks 1–3%;
  - the hot `verify` loop is clean: 8 instructions per test.

## PM-3: ideal-C ladders (`ladders/`, `zig cc -O3 -march=native`, checksummed)

### Matmul

Rung 0 is within +5% of mylang's instructions and −0.3% of its cycles.

| rung | what changes | Mcyc | cycles ÷ rung 0 |
|---|---|---:|---:|
| 0 | today: one data tag; b row and len reloaded; j checked; c row reloaded and stored back | 643 | 1.000 |
| 1 | rung 0 without the bounds check | 281 | 0.436 |
| 2 | row pointers and len hoisted, no store-back, check kept | 73 | **0.114** |
| 3 | rung 2 with the check hoisted | 72 | 0.112 |
| 4 | rung 3 with `restrict` rows | 74 | 0.115 |
| 5 | rung 0 with typed element data (strict aliasing), nothing else | 207 | 0.322 |
| 6 | rung 5 with the check hoisted (loop versioning) | 73 | **0.113** |

References, in Mcyc:
- mylang 645;
- Zig ReleaseSafe 230;
- Zig ReleaseFast 160;
- Rust with overflow checks 436;
- Rust 320.

### Lox VM step

The script is `ladders/lox/step.lox`: 16 dispatches per iteration. Rung 0 is −17% of mylang's instructions and −3% of its cycles.

| rung | what changes | Mcyc | cycles ÷ rung 0 |
|---|---|---:|---:|
| 0 | today | 2459 | 1.000 |
| 1 | overflow checks removed | 2342 | 0.952 |
| 2 | index checks and wraps removed | 1829 | **0.744** |
| 3 | uniqueness tests hoisted | 1688 | 0.687 |
| 4 | count traffic removed | 1687 | 0.686 |
| 5 | frame in registers | 1425 | **0.579** |
| 6 | stack_top in a register | 1375 | 0.559 |
| 7 | ADD/LESS operands read once | 1385 | 0.563 |

References, in Mcyc:
- mylang 2536;
- Zig ReleaseSafe 1098;
- Zig ReleaseFast 1004;
- Rust 1178.

The ideal is about **1.25× Zig ReleaseSafe**.

### knucleotide

Rung 0 is −14% of mylang's instructions and −10% of its cycles.

| rung | what changes | Mcyc | cycles ÷ rung 0 |
|---|---|---:|---:|
| 0 | today: slice materialized (alloc, copy, ASCII re-scan); one fused probe with a `str_eq` call; slice freed | 818 | 1.000 |
| 1 | views: hash and compare in place; allocate only on insert | 361 | **0.441** |
| 2 | short-key compare inlined | 299 | **0.366** |
| 3 | span hash inlined | 303 | 0.371 |

References, in Mcyc:
- mylang 905;
- `my-tuned` 254;
- Zig ReleaseSafe 414;
- Zig ReleaseFast 370;
- Rust with overflow checks 518.

### scan_split

Rung 0 is −11% of mylang's instructions and −10% of its cycles.

| rung | what changes | Mcyc | cycles ÷ rung 0 |
|---|---|---:|---:|
| 0 | today: a list of fresh strings | 222 | 1.000 |
| 1 | views: pieces as (offset, length) | 109 | **0.492** |
| 2 | no list: the split iterated in place | 88 | **0.397** |

References, in Mcyc:
- mylang 248;
- Zig ReleaseSafe 221;
- Zig ReleaseFast 147.

### str_build (extra)

Rung 0 is −18% of mylang's instructions and −31% of its cycles.

| rung | what changes | Mcyc | cycles ÷ rung 0 |
|---|---|---:|---:|
| 0 | today | 96 | 1.000 |
| 1 | uniqueness test hoisted | 68 | 0.714 |
| 2 | len and cap in registers, typed store | 41 | **0.424** |

References, in Mcyc:
- mylang 139;
- Zig ReleaseSafe 88;
- Zig ReleaseFast 46;
- Rust with overflow checks 58.

## PM-4: ranked levers and proposed waves

| # | lever | bound, in cycles | where the fact comes from | work | wave |
|---|---|---|---|---|---|
| 1 | TBAA by element type; no store-back of an unchanged element pointer | matmul **0.11** (2.78 → 0.31× Zig RS) | type; union payloads and integer-word aggregate copies keep the generic tag | 6–10 h | F1 |
| 2 | substring views as dict keys and slices | knucleotide **0.44** (0.37), 2.21 → 0.97 (0.82); part of text_ops and EDA | value semantics | 12–20 h | S1 |
| 3 | split views or a lazy split | scan_split **0.49** (0.40), 1.14 → 0.56 (0.46); text_ops; EDA | value semantics, loop shape | 12–20 h | S2 |
| 4 | overflow facts: counters bounded by the trip count, loop variables by the loop condition, floor-mod ranges into callees | bytes_scan **0.29**, sieve 0.74, calls 0.94; VM increments 0.89–0.93 | loop shape, ranges | 8–12 h | F1 |
| 5 | count traffic: nested-field borrows, frame copies on call and return, generated per-layout release | Lox vm/invocation 0.66, method_call 0.71, fib 0.80, tree/equality **0.60**, tree/invocation 0.83; EDA allocation and free at 24–29% of instructions | value semantics, layout | 12–16 h | U2 |
| 6 | index facts: check hoisting and versioning; no negative-index wrap for indexes ≥ 0 | Lox VM 0.73–0.92 (ladder rung 2: 0.74), sort_quick 0.93, sieve 0.96 | loop shape, ranges, lengths | 12–20 h | F2 |
| 7 | uniqueness-test hoisting and promotion of loop-carried state | nbody **0.82**, str_build 0.90 (ladder 0.42), sort_quick 0.96, Lox ladder −8% and −15%, tree/invocation 0.92 | value semantics | 10–16 h | U1 |
| 8 | fixed-array element access in place | fannkuch `my-array` 3.33×, `my-tuned` 2.77× → about `my` (0.87×) | static | 4–8 h | R |
| 9 | runtime i64 sort algorithm | sort_builtin 1.79× Rust with overflow checks | runtime | 6–10 h | R or S |
| 10 | tail calls | fib against Zig ReleaseFast only, and only together with dropping overflow checks | — | — | not planned (L1) |

**Projected cycles against Zig ReleaseSafe, today → after the levers:**

| program | today | after |
|---|---:|---|
| matmul | 2.78 | 0.31 |
| knucleotide | 2.21 | 0.97 (0.82 with the inlined compare) |
| str_build | 1.59 | about 1.4 with hoisting; about 0.7 with state promotion |
| nbody | 1.62 | 1.33 |
| scan_split | 1.14 | 0.56 |
| sieve | 1.14 | 0.83 |
| bytes_scan | 1.06 | 0.31 |
| sort_quick | 1.10 | 0.99 |
| calls | 1.07 | 1.00 |
| Lox vm/fib | 2.22 | 1.53; about 1.25 with state promotion |
| Lox vm/invocation | 2.58 | 1.26 |
| Lox vm/string_equality | 2.92 | 2.07; about 1.5 with state promotion |
| Lox tree/equality | 1.43 | 0.86 |
| EDA | 1.44–1.47 | about 1.15–1.2 (estimate) |
| text_ops | 2.52 | about 1.5 (estimate) |

**Proposed lanes and exits.** Each exit is stated in counters, plus CPU-10 timing at each X integration. Every lane also keeps "nothing else slower than 1.03×".

- **F1: aliasing and overflow facts** (levers 1 and 4; 14–22 h).
  - matmul ≤ 0.4× Zig ReleaseSafe; bytes_scan ≤ 0.4×; sieve ≤ 0.9×; calls ≤ 1.02×.
  - `overflow_check` 0 at bytes_scan:17 and sieve:16/21.
- **F2: index facts** (lever 6; 12–20 h).
  - Lox VM bounds checks per dispatch from about 7 to ≤ 2.
  - vm/string_equality ≤ 0.80× today's cycles.
  - sort_quick ≤ 1.0× Zig ReleaseSafe.
  - No wrap on provably non-negative indexes.
- **U1: uniqueness hoisting and state promotion** (lever 7; 10–16 h).
  - nbody and str_build: `unique_test` per loop, not per iteration.
  - nbody ≤ 1.35× Zig ReleaseSafe; str_build ≤ 1.0×.
  - Lox step loop ≤ 0.85× today's cycles.
- **U2: borrow misses and release cost** (lever 5; 12–16 h).
  - `read_constant`'s retains and releases at 0.
  - vm/invocation ≤ 0.70× today's cycles; tree/equality ≤ 0.65×.
  - EDA allocation and free ≤ 15% of instructions.
- **S1: substring views as keys** (lever 2; 12–20 h).
  - knucleotide ≤ 1.0× Zig ReleaseSafe.
  - At most 0.05 allocations per position, on insert only.
- **S2: split views, lazy split, search** (lever 3; 12–20 h; starts with a text_ops ladder).
  - scan_split ≤ 0.6× Zig ReleaseSafe; text_ops ≤ 1.5×.
  - EDA text materialization halved.
- **R: leftovers** (levers 8 and 9, plus CE2's sret sharing and EDA P6; 8–12 h).
  - fannkuch `my-array` and `my-tuned` ≤ 1.05× `my`.
  - sort_builtin ≤ 1.2× Rust with overflow checks.

**Order:**
1. F1 and S1, the largest bounds, in disjoint code.
2. F2 with U1 for the Lox VM. They coordinate on index lowering in `emit_llvm`.
3. U2, S2 and R.

## Where the data contradicts the plan's hypotheses

1. **"Checks block inner-loop optimization."**
   - **True for:**
     - bytes_scan (×3.4);
     - sieve;
     - the Lox VM.
   - **False for:**
     - matmul, where aliasing is the blocker;
     - nbody, where checks cost instructions, not cycles;
     - intloop and calls, where no checks remain;
     - fib, where the check alone costs 0 cycles;
     - sort_builtin.
   - **Small:** sort_quick gains only 10%.
2. **"Header reloads of len and the data pointer."**
   - The header already has its own TBAA tag.
   - matmul reloads element data (row pointers), because of the single data tag plus the store-back.
   - str_build's len reload is real. It comes from the untyped memmove plus the per-iteration uniqueness test.
3. **"Most of the VM's 2× is uniqueness tests and counts."**
   - Counts matter on call-heavy cells (0.66–0.80), not on dispatch-heavy ones (0.93–0.94).
   - Uniqueness tests are about 8%.
   - Checks (0.77–0.88) and state kept in memory (about 15%) matter as much.
4. **Strings.** The cost is materialization (allocation, copy, ASCII re-scan), not hashing or probing.
5. **fib.** The check alone costs 0 cycles; only check plus tail calls gives 0.45.
6. **calls and intloop against Rust with overflow checks.** These are LLVM's modulo code and the floor-mod fix-up. Both are level with Zig.
7. **nbody's residual** is the references' fixed-length arrays.
8. **sort_builtin** is the runtime algorithm, which the plan did not cover.
9. **EDA** is allocation and free plus text materialization, not checks (1–3%).

## Remaining unknowns

- text_ops and EDA have no ladder; their bounds are estimates from instruction shares.
- **The Lox VM's last 25%** is unexplained: ladder rung 7 is still 1.26× Zig ReleaseSafe. The candidates are the dispatch shape and the `{i8,[1×i64]}` Value representation.
- The VM's cycle response is non-monotonic. Lane F2 should not claim cycles without CPU-10 confirmation.
- **str_build** costs 45% more cycles than its transcription at a similar instruction mix. Its L1 misses suggest realloc growth placement.
- **TBAA by element type** is only a counterfactual: output-checked on all parity programs, Lox and EDA, not proven sound. Union payloads and integer-word aggregate copies must keep the generic tag.
- All cycles were measured on CPU 8 of a shared machine. The ratios are within-run.

**Wall-time confirmations for the coordinator on CPU 10:**
- matmul ladder rungs 0, 2 and 6, and `tbaa`;
- bytes_scan `overflow`;
- knucleotide and scan_split ladder rungs 0–2;
- str_build ladder rungs 0–2;
- Lox VM ladder rungs 0, 2, 5 and 6, and `checks+norc` on vm/fib, string_equality and invocation;
- nbody `unique`;
- sieve `checks`.

## Housekeeping

- **A rebuilt baseline.** Edits landed while the first baseline compiler was building. The agent killed only its own process and rebuilt the baseline from a clean `git archive` export.
- **One scratch file outside the worktree.** A redirect created `/tmp/claude-1000/null.out`, which was deleted right away. All other scratch stayed in `.tmp/pm/`, and the large scratch was deleted at the end.
- **Compilers kept:**
  - `~/.cache/mylang/pm-base-136335cb`;
  - `~/.cache/mylang/pm-a677da7a`.
- **Reusable tools** (`tools/`):
  - `cf.py`, the counterfactual builder;
  - `ladder.py`, `pstat.py`, `prof.sh`, `symgroups.py`, `summarize.py`, `llvm_identity.sh`.
- **CPU rules held:** no wall time was taken on CPU 10, and no heavy work ran on CPUs 2, 3, 10 or 11.
