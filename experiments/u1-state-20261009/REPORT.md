# Lane U1 report: uniqueness and state (2026-10-09)

**Who wrote this file.** An opus-lane agent ran lane U1 of `docs/audits/runtime-parity-plan-2026-10-08.md` §8. Its tool refused report files, so the coordinating Claude session wrote this file from the agent's final message, after checking the receipts in `gates/`:
- `zig-build-test-ceb4291ed.log`: 88/88 steps, 2128 tests;
- fmt-check: exit 0;
- `qualify-ceb4291ed/summary.json`: qualified on `ceb4291ed`; conformance 1518/0/0 in debug and in release;
- `fuzz50-ceb4291ed/matrix.json`: qualified, complete, with the source and the oracles unchanged; 9/9 kinds pass;
- Lox: 246 + 246 + 241 + 241; port tests 65 passed;
- EDA tests: 310 passed.

**Where.** Branch `claude/u1-state`, based on `main` `35df839be`. The ReleaseFast compiler is `~/.cache/mylang/u1-ceb4291ed`. Nothing was merged or pushed.

## Exit (CPU 6; instructions exact; cycles comparable only within one interleaved run)

| exit item | result | met |
|---|---|---|
| `unique_test` once per loop | str_build 16,000,000 → 1; nbody 75,000,001 → 5,000,001 (one per `advance` call, covering its loop nest) | yes |
| nbody ≤ 1.35× Zig ReleaseSafe | 1.336× (0.825× of today) | yes, narrowly |
| str_build ≤ 1.0× Zig ReleaseSafe | **0.47×** (0.29× of today) | yes |
| Lox VM step loop ≤ 0.85× today | **0.897×** cycles, 0.898× instructions | **no** |
| nothing else > 1.03× | parity, Lox and EDA: none. Rows: 8 cells flagged, explained below | see rows |
| gates | all pass on `ceb4291ed` | yes |

## Commits

| step | commit | what |
|---|---|---|
| 1a | `bee3ee6be` | large byte buffers grow with `realloc` (NEW-CORE-U1-GROW-1) |
| 2a | `1ca6105fe` | uniqueness tests hoisted onto loop entry edges (NEW-CORE-U1-HOIST-1) |
| 3a | `e291680a1` | scalar record fields a loop carries stay in SSA values: `forward.zig` (NEW-CORE-U1-STATE-1) |
| 1b | `f2be30f9a` | the buffer `realloc` path lives in `core_bytes.c`; `core_rt.c` is identical to `main`'s, a layout fix |
| 3b | `aacc87521` | frame stores sink to the ladder arms that observe them (NEW-CORE-U1-SINK-1) |
| 3c | `8abaeb25d` | list and buffer length and capacity in registers while a loop appends: `emit_state.zig` (NEW-CORE-U1-STATE-2) |
| 2b | `7237773f7` | loops hoisted one at a time, each judged on the code the earlier ones left |
| fix | `ceb4291ed` | a sunk store copies its operands before appending them to `extra` (the gate caught a read of freed memory) |
| evidence | `0181b65c0` | gate receipts, measurements, counters, tools |

## Step 1: why str_build was 39% slower than its own C transcription

`core_buffer_grow` allocated a fresh block at every doubling, copied every byte in use, and freed the old one. For a 128 MB buffer that meant twice the page faults (64,091 against 31,343) and about 7× the L1 misses. Large lists already grew with `realloc`, which glibc serves with `mremap`. Buffers now do too.

| str_build (CPU 6) | instructions | cycles |
|---|---:|---:|
| `main` | 255 M | 139 M |
| after the growth fix | 242 M | 65 M |
| C transcription (ladder rung 0) | 210 M | 99 M |
| Zig ReleaseSafe | 339 M | 87 M |
| final, after steps 2 and 3 | 130 M | 41 M (= ladder rung 2) |

## Step 2: uniqueness tests hoisted (`own.zig`)

**What it does.** When an update that tests its count is reached through a loop header's phi, one `is_unique` test goes on each edge entering the loop. If the value is shared it is copied there. The join then counts as fresh for `staticallyUnique`, so every update in the loop runs in place.

**Why it is safe:**
- The entering value must be owned, and its edge must be its last use, so the test sees every owner.
- The loop cannot share it: `staticallyUnique`'s sharing walk rejects copies kept across the update, appends or stores into other values, calls that may keep it, and an entering value needed after the loop.
- The join is *not* fresh for `exclusiveChildren`, because a copy shares its rows. NEW-CORE-ROW-COW-1/-2 are untouched.
- Verify builds assert `count == 1` at every in-place update.

**Cost.** A loop that never reaches its update still copies a value that was shared on entry. In the Lox port that is one extra `list_copy` per vm/fib run and 30 per vm/invocation run.

## Step 3: state in registers

**(a) `forward.zig`.** After ownership, a read of a scalar field becomes the value last stored to it: through stores to other fields, `record_make`, and record phis (as a phi of the field). Stores are unchanged, so calls, copies, returns and traps still see memory. Only fields written in the loop get a phi; new values take the facts' field interval, which verify builds assert. On the Lox VM, `frame.ip`, `frame.base`, `rt.stack_top` and `rt.frame_count` become loop phis, and loads drop 15%.

**(b) Frame-store sinking (`stores.zig`).**
- **What changed.** CE2-A's one-level sinking is now iterated (up to 48 levels), and a store can split into two observing successors.
- **Effect on the Lox VM.** `rt.frames[rt.frame_count - 1] = frame` and its uniqueness test now run only in the opcode arms that read the frames, call or return.
- **Why it is safe.** Each step is CE2-A's own proof. The bounds check stays at the original position, and the sunk copies are marked `.proven`.

**(c) Length and capacity in registers (`emit_state.zig`).**
- **What is promoted.** A web of in-place pushes, appends and their phis inside loops keeps its length and capacity in `alloca`s that LLVM promotes to registers.
- **When it applies.** Nothing else in the loops may read a member.
- **How memory stays correct.** Entry edges load the header; growth stores the length back, calls the runtime and reloads the capacity; every exit edge stores the length into the header of the value current there.
- **Two bugs caught by the fixtures during development, both fixed:** two webs sharing an exit edge, and a push *of* a web value.

## Counters, before → after (`counters-ceb4291ed.txt`)

| program | `unique_test` | other |
|---|---|---|
| str_build | 16 M → 1 | releases 2 → 1 |
| nbody | 75 M → 5 M | |
| Lox vm/step | 260 M → 160 M (1.63 → 1.00 per dispatch) | bounds checks 1120 M → 970 M |
| Lox vm/string_equality | 835 M → 322 M | |
| Lox vm/fib, invocation, method_call | −17% to −20% | 1–30 extra releases, from the entry copies |
| EDA rds3+flat, labstation | 430 k → 305 k; 313 k → 256 k | |

## No regression

**Lox and EDA** (÷ `main`):
- vm/step 0.898 instructions, 0.897 cycles;
- vm/fib 0.962 / 0.950;
- vm/string_equality 0.823 / 0.841;
- vm/invocation 0.970 / 0.894;
- vm/method_call 0.961 / 0.916;
- tree/invocation 1.002 / 1.009;
- tree/equality 1.000 / 1.000;
- EDA 0.996 / 0.992 and 0.995 / 0.999.

**Parity, 45 programs.** None is above 1.005× instructions or 1.03× cycles. Gains:
- list_append_sum 0.894 / 0.790;
- text_ops_tuned 0.895 / 0.920;
- sort_quick 0.873 / 0.982;
- sieve 0.961 / 0.920.

**46 rows, 7 rounds.** Eight cells were flagged:

| row | instructions | cycles | explanation |
|---|---:|---:|---|
| mutate_nested/4096 | 1.000 | 1.076 | LLVM byte-identical; only the runtime object moved. Layout. |
| word_count/4096, /64 | 1.000 | 1.048, 1.056 | same |
| int_math/64 | 1.025 | 1.002 | the setup comprehension's in-register state; the extra instructions are executed alignment padding |
| call_direct/64, branch_predictable/64 | 1.031, 1.023 | 0.999, 0.997 | same pattern, not checked separately |
| packet_decode/4096, /64 | 1.031, 1.032 | 1.016, 0.977 | only setup comprehensions changed; LLVM re-scheduled `main` |

int_parse is +1.1% in instructions; it was not flagged and not investigated. **The layout-sensitive rows (word_count, mutate_nested, packet_decode) are to be checked on CPU 10 at integration.**

## Gate receipts (all on `ceb4291ed`)

| gate | result |
|---|---|
| Guardian | 88/88 |
| `zig build test --summary all` | 88/88 steps, 2128 tests (the earlier run on `7237773f7` failed on the sinking bug, fixed in `ceb4291ed`) |
| fmt-check | exit 0 |
| `qualify_merge` | qualified: test-core 537/0/0; conformance 1518/0/0 in debug and in release |
| fuzz 9×50 | 9/9 pass |
| Lox | 974/974; port tests 65/65 |
| EDA | 34/34 goldens; 310/310 tests |
| parity `.expected` | 45/45 |
| counting on and off | identical: 45 parity, 7 Lox, 34 EDA |

## Touches outside U1's areas

- **F2's areas:** no edits.
  - `facts.zig` is used read-only (`facts.shape`).
  - `forward.zig` writes `Facts.ranges` for its new values, from `Aggregates.fields`.
  - `passes.zig` runs `forward.run` after ownership.
- **`stores.zig` (CE2-A):** iterated sinking, `.proven` sunk checks, and the operand-copy fix.
- **`emit_llvm.zig`:** edge blocks in `branchTo`, loads and stores at `jump`, `listPush` → `slotPush`, and `MemoryState.states`.
- **`emit_bytes.zig`:** `append` uses the in-register state.
- **`count_runtime.zig`:** new anchors.

## Limits

- **The Lox exit (≤ 0.85×) is not met:** the result is 0.897.
  - The step loop is limited by instruction throughput (6.6 instructions per cycle), not by memory. So ladder rungs 5 and 6, which assumed frame reloads, overstated what state promotion buys.
  - Making every remaining `is_unique` in `vm::run` true is worth only −1.7% of cycles.
- **What is left is mostly F2's:**
  - the `rt.frames[rt.frame_count - 1]` index computation at the dispatch head and latch: about 19 instructions per dispatch for the wrap, the bounds check and the overflow check;
  - the ip and stack index checks.
- **`rt.stack` tests remain** (about 8 per 16 dispatches). Hoisting across the `mut rt` calls needs an interprocedural "preserves uniqueness" summary; worth at most about 2% of cycles.
- **Speculative entry copies:** a loop that never reaches its update still copies a value shared at its entry.
- **Field forwarding** costs up to +0.3% instructions on call-heavy VM cells.
- **Rung 7** (ADD/LESS operands read once) was not attempted; the ladder shows no gain.
