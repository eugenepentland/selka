# Lane F1 report: aliasing and overflow facts (2026-10-09)

**Who wrote this file.** An opus-lane agent ran lane F1 of `docs/audits/runtime-parity-plan-2026-10-08.md` §8. Its tool refused report files, so the coordinating Claude session wrote this file from the agent's final message, after checking the gate receipts.

**What the coordinator checked:**
- `gates/zig-build-test.log`: 88/88 steps, 2106 tests (the base's 2095 plus 11 new).
- `gates/fmt-check.log`: exit 0.
- `gates/f1-qualify-d6e32de12/summary.json`: qualified on `d6e32de12`. Conformance 1518/0/0 in debug and in release.
- `gates/fuzz50-d6e32de12/matrix.json`: qualified, complete, with the source and the oracles unchanged.
- `gates/lox-conformance.log`: 246 + 246 and 241 + 241.
- `gates/lox-port-tests.log`: 65 passed.
- `gates/eda-tests.log`: 310 passed.

**Where.** Branch `claude/f1-facts`, based on `main` `cafe7fea7`. Nothing was merged or pushed.

## Commits

| step | commit | what |
|---|---|---|
| 1 | `f7746c50a` | TBAA by element scalar type, plus a compiler barrier in the inline free (NEW-CORE-F1-TBAA-1, -2) |
| 2 | `7c4de0399` | no store-back of an unchanged element pointer (NEW-CORE-F1-STOREBACK-1) |
| 3 | `d6e32de12` | overflow facts: counters, loop conditions including `x*x <= y`, callee return intervals, masked 32-bit division, and `--sabotage-facts=overflow` (NEW-CORE-F1-OVERFLOW-1..5) |
| evidence | `154d1d959` | gate receipts and the Lox/EDA measurements |

## Exit

CPU 8, user cycles, `perf stat`, 5 interleaved shuffled rounds, medians.

| program | instr ÷ base | cycles ÷ base | base ÷ Zig RS | F1 ÷ Zig RS | exit |
|---|---:|---:|---:|---:|---|
| matmul | 0.109 | 0.111 | 2.797 | **0.310** | ≤ 0.4: met |
| bytes_scan | 0.204 | 0.285 | 1.041 | **0.296** | ≤ 0.4: met |
| sieve | 0.755 | 0.744 | 1.171 | **0.871** | ≤ 0.9: met |
| calls | 0.912 | 0.918 | 1.074 | **0.987** | ≤ 1.02: met |

Across the agent's earlier runs, the ratios to Zig ReleaseSafe ranged:
- matmul: 0.304–0.310;
- bytes_scan: 0.296–0.344;
- sieve: 0.835–0.871 (the thinnest margin);
- calls: 0.984–1.007.

### Overflow checks executed (counting builds; `checks-before.json`, `checks-after.json`)

| site | before | after |
|---|---:|---:|
| bytes_scan:17 | 8,388,608 | **0** |
| sieve:16 | 46,588,036 | **0** |
| sieve:21 | 1,270,607 | **0** |
| calls:5 | 30,000,000 | 0 |
| sieve:11 (the condition's own `i*i`) | 4,472 | 4,472 |

### The matmul inner loop

It is now vectorized: unrolled four times over `<4 x double>`. Per element there is one load of `b[k]`, one load and one store of `c[i]`, then `fmul` and `fadd`. Row pointers and lengths are hoisted, and there is no store-back.

### No regression

- **Parity:** all 45 programs.
  - Instruction counts equal the base's everywhere except matmul, bytes_scan, sieve, sieve_tuned, calls and scan_split (0.997).
  - No cycle ratio is above 1.010. The highest is knucleotide_arena, with identical instructions.
  - Raw data: `step3/measure-all.json.gz`.
- **Lox and EDA** (`gates/lox-eda-measure.json`):
  - instructions 0.999–1.001;
  - cycles 0.955–1.019. tree/equality's 1.019 comes with identical instructions.

## Step 1: TBAA soundness

**The tags.** Six scalar types are children of `myl.data`: `double`, `i64`, `i32`, `i16`, `i8` and `ptr`. A flag, `FunctionEmitter.element_tags`, is on only inside `listGet`, `listSet`, `listSetField`, `listGetField` and `listPush`. While it is on, each scalar leaf is tagged by its storage type, and everything else falls back to the generic tag.

**Accesses that stay generic or untagged:**
- unions in any form: the tag word, the payload words, scalar payloads and niche pointers;
- `tag_of`;
- elements over four words, which are untagged memcpys or lent slot addresses;
- paths that cross a union (`Module.pathCrossesUnion`);
- vector, bytes, text, number and dictionary-entry code;
- homes, boxes, `%ret`/sret and stack slots.

**Freed and reused blocks.** `myl_core_list_new` and `myl_core_free` are inlined into guest code. So a free and a reallocation can sit in one function with no opaque call between them. The free-list link store at offset 0 does not order element accesses at offset 32 and above. `myl_core_free`'s push therefore now starts with `asm sideeffect "" ~{memory}` (NEW-CORE-F1-TBAA-2). This changed no parity program's instruction count. Every other allocation and free path calls the runtime.

**The runtime C code** is compiled separately (`zig cc -c -O2`) and linked without LTO. No runtime C reaches a guest module as LLVM.

**Stack-promoted lists** get one `alloca` per `list_new` instruction, and no lifetime markers are emitted.

**Records inline in list elements** are tagged by each field's scalar type at its offset, so whole-record copies done field by field use the same tags.

**Remaining limit.** TBAA covers list elements only. Boxes, homes, in-memory record fields and dictionary entries stay generic.

## Step 2: store-back

`elements.storeBack` pairs a `list_set` (or a `list_set_field` of a block-pointer field that crosses no union) with the transferred read of the same element (`flags.transferredSlot`). It traces the stored value back through:
- in-place updates;
- copies and growth;
- phis.

**The outcomes:**
- **Every path is in place:** nothing is stored. matmul is this case.
- **Otherwise:** `icmp ne ptr new, old`, and a store only when the pointer changed.
- **Releases:** none either way, because the transferred read owns the old pointer.

## Step 3: overflow facts

- **Counters** (`reduction` with `growth`): the interval of `next − acc` within one iteration. It covers conditional increments and inner counted loops, with a budget of 64 values. A fact pass that does not converge now marks every block reachable.
- **Loop conditions.** `j <= n` was already refined per use. The new `refineSquare` bounds `x` by `isqrt(top(y))` under a dominating `x*x <= y`.
- **Floor-mod into callees.**
  - The first pass runs callees first, with every parameter unknown, and records each function's return interval: the hull of its reachable `ret` intervals.
  - Each direct call's result takes that interval, so `step`'s `a+b` is proven non-negative and the remainder becomes unsigned.
  - A negative argument at any call site keeps the fix-up.
- **Division:** a proven or unsigned 64-bit division whose operands fit in `u32` is masked with `and 0xffffffff`, so LLVM picks the short reciprocal sequence. An `i32 urem` version cost alloc_churn +6% instructions and was replaced. Verify builds never narrow.
- **Checkability:** every new fact is an instruction interval, which verify mode asserts at run time. `--sabotage-facts=overflow` makes each rule one off, and verify catches it: the counter, the square root and the return interval.

## Tests

`src/core/f1_facts_test.zig` holds 11 tests. Each fixture runs in debug, release and release with `--verify-facts`, under the leak check.

- **`test/core/f1_tbaa.my`:**
  - records copied whole, then field reads;
  - union lists, and records holding unions;
  - floats and a list of lists in one loop;
  - a block freed and reused for float, int and bool lists in one function;
  - `b = a; b[0][0] = …`.
- **`test/core/f1_storeback.my`:**
  - a shared row that copy on write must replace;
  - a row replaced in the loop;
  - `c[0] = c[1]`;
  - `break` and early return;
  - `bags[i].items.append` and `names[i] += …` with aliases.
- **`test/core/f1_overflow.my`:**
  - bytes_scan- and sieve-shaped counters;
  - a counter near the maximum, and an unbounded step, both of which must trap `R_OVERFLOW`;
  - loops whose bounds move in the body;
  - a negative argument at one call site of the modulo callee;
  - the sabotage probes.

## Gate receipts (all on `d6e32de12`)

| gate | result |
|---|---|
| Guardian | 88/88 |
| `zig build test --summary all` | 88/88 steps, 2106 tests |
| `fmt-check` | exit 0 |
| `qualify_merge` | qualified: test-core 515/0/0; conformance 1518/0/0 in debug and in release, with leak check and `--verify` |
| frozen fuzz 9×50 | all 9 kinds PASS |
| Lox conformance, both engines, with stress | 974/974 |
| Lox port tests | 65/65 |
| EDA goldens | 34/34, plain and counting builds |
| EDA tests | 310/310 |
| parity | 45/45 match `.expected` |
| counting on/off | identical on matmul, sieve, bytes_scan, calls, 6 Lox cells and 34 EDA cases |

## Files

**Changed:**
- `emit_llvm.zig`;
- `elements.zig`;
- `ir.zig` (`pathCrossesUnion`);
- `facts.zig`, `passes.zig`;
- `pipeline.zig` and `main.zig` (the sabotage flag);
- the tests;
- `SPEC.md`.

**Untouched:** none of S1's areas were touched.

## Remaining limits

- **A wrong answer in the base, not caused by F1.** `base-bug-inlined-mut-row-alias.my` prints `8.0 4.0` in debug and `8.0 8.0` in release.
  - The coordinator found the root shape is wider: a write to an element of a shared inner list inside a loop (`kb = b[1]; for i in range(2): b[i][0] = 7`) also changes `kb`. That happens in debug and release, on every new-core compiler back to the S5 merge `5a6b501d`.
  - Being fixed separately on `claude/fix-row-cow`.
- **sieve's margin is thin** (0.871 against ≤ 0.9). What remains belongs to lane F2:
  - the bounds checks on `flags[j]`;
  - the bounds checks on `for flag in flags`;
  - the condition's own `i*i` check.
- **Return intervals** assume nothing about parameters; they are not tightened by the callee's own parameter intervals.
- **Copy-on-write store-backs** keep one compare and branch, in debug builds and for `mut` parameters.
- **Wall time** is the coordinator's, on CPU 10 at the integration.
