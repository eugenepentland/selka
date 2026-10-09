# Runtime parity, wave 3: borrows and release (U2), split views and search (S2), leftovers (R) (2026-10-09)

Status: **ready for Codex.** This is the last wave of `runtime-parity-plan-2026-10-08.md` §8. That plan's targets, gates and its "no language change for speed" rule still apply. This document replaces its §8 rows for U2, S2 and R with exits re-based on today's `main`. It also adds the residuals that F1, S1, F2 and U1 reported.

- **Size (estimates):**

  | step | hours |
  |---|---|
  | M0 | 4–6 |
  | U2 | 14–20 |
  | S2 | 14–22 |
  | R | 14–20 |
  | X | 6–10 |

  About 2–3 days of wall time, with the three lanes in parallel.
- **No decisions are needed before the start.** Codex's defaults are in §8. The user decides afterwards on anything §8.3 lists as an exception.

## Launch instruction (for Codex)

> **One run: M0, then U2, S2 and R in parallel, then the integration X.**
> - Create `codex/runtime-parity-3` from `claude/runtime-parity-3-plan` in a worktree of your own. Record `main`'s hash (`0689d3407` or later) in `REPORT.md`.
> - Read this plan whole. Then read:
>   - `docs/audits/runtime-parity-plan-2026-10-08.md` §2, §6 and §8;
>   - `experiments/parity-measure-20261008/REPORT.md`;
>   - the five lane reports: `experiments/{f1-facts,s1-views,f2-index,u1-state}-20261009/REPORT.md` and `experiments/fu-x-20261009/REPORT.md`.
> - **Do M0 (§3) first** on `codex/runtime-parity-3`.
> - **Then run the three lanes** (§4–§6), each in its own worktree on `codex/rp3-u2`, `codex/rp3-s2` and `codex/rp3-r`, all branched from M0's last commit. Use subagents if you have them; otherwise run the lanes one after another in the order U2, S2, R.
> - **Then merge the lanes into `codex/runtime-parity-3`** with real merge commits, and do X (§7).
> - **Do not stop to ask** (§9). Decide, log the decision in `experiments/runtime-parity-3-<date>/DECISIONS.md`, and continue. Stop only at a §9 hard stop, or when X's report is written.
> - **Commit at every step,** with an updated progress section in `REPORT.md`.
> - **If `main` moves,** merge it into the integration branch with a real merge commit, then into any running lane. Rerun that step's gates.
> - **Never merge into `main` and never push.** Claude reviews the result, and the user decides the merge.

## 1. Where it starts

**`main` `0689d3407`.** It holds:
- F1, S1, F2 and U1;
- the shared-row fix;
- the syntax redesign;
- optimized debug, which runs the Core release passes under `--optimize-debug`;
- the front-end fixes.

The positions below are FU-X's CPU-10 wall times (`experiments/fu-x-20261009/results/`), taken before the syntax port. The port's LLVM is identical for 85 of 94 programs, so they carry over (`experiments/fu-port-20261009/REPORT.md`). M0 measures them again on the new base.

**The gate** (§2 of the parity plan): every parity program, EDA and the Lox tree-walker at or under 1.1× of both Zig ReleaseSafe ("Zig RS") and Rust with overflow checks (`rust-checked`); the Lox VM at or under 1.5× Zig RS.

| what | ÷ Zig RS | ÷ rust-checked | owner |
|---|---:|---:|---|
| parity `my` geomean (27 programs) | **0.74** | — | — |
| text_ops | **2.61** | 1.38 | S2 |
| scan_split | **1.30** | — (no Rust arm) | S2 |
| nbody (`my`, `my-class`) | **1.39** | 1.22 | R6 |
| sort_builtin | 0.45 | **1.68** | R2 |
| sort_quick | 1.00 | **1.21** | R6 |
| calls | 1.00 | **1.26** | R6 |
| intloop | 1.03 | **1.19** | R6 |
| records | 0.91 | **1.11** | R3, R6 |
| fannkuch `my-array`, `my-tuned` (alternate arms) | 2.66, 2.22 | 3.14, 2.62 | R1 |
| Lox VM, 13 cells | **1.62** (gate 1.5) | 1.69 (plain Rust) | U2 |
| worst VM cells: invocation, fib, string_equality, method_call | 2.22, 1.91, 1.88, 1.86 | | U2 (string_equality: S2) |
| Lox tree-walker, 13 cells | 0.99 | 1.24 (plain Rust) | — |
| tree cells over 1.1: string_equality, equality | 2.16, 1.45 | | U2, S2 |
| EDA, 34 designs | **1.21** (gate 1.1) | — | U2, S2, R4 |

**Already met.**
- The stretch target for the parity geomean: 0.906× Zig ReleaseFast.
- The rows were already faster than Zig RS and Rust at CE2-X. They have not been re-measured against the references since the prune (M0 step 4).

**Where the remaining instructions go** (PM-2, re-read against the lane reports):
- **Lox VM:**
  - count traffic on calls: frame copies, and `read_constant`'s 3 retains and 3 releases per constant;
  - 4.9 bounds checks per dispatch, all data-driven and also checked by a Zig RS port;
  - a redundant overflow check on `frame_count - 1` at the dispatch head;
  - `heap::peek` not inlined, because its body has checks.

  U1 found that the step loop is bound by instruction throughput (6.6 instructions per cycle), not memory, so promoting more state into registers buys little. The CPU-10 counterfactuals give vm/invocation **0.51×** of the old main with checks and counts removed, and **0.67×** with counts removed alone.
- **EDA:**
  - allocation and free are 24–29% of instructions. Of that, the interpreted layout walk `reference_at` (`src/core/runtime/core_rt.c:437`, also used in `core_dict.c`) is 10.5%. Zig's arenas spend about 11%;
  - text materialization is 10–12%, against Zig's 2%;
  - the `parse_list` record push copies 0.44 GB ("P6").
- **text_ops:**
  - allocation and free 28%;
  - materialization and copies 30%;
  - search, split and replace 33%, of which memmem is 15%.

  There is no ladder yet.
- **scan_split:**
  - allocation and free 39%;
  - piece copies 20%;
  - search 41%.

  Ladder (`experiments/parity-measure-20261008/ladders/scan_split.c`): views 0.49, and no list 0.40, of rung 0. CPU-10 confirmation projects 0.72 and 0.53 × Zig RS.
- **fannkuch `my-array`:** every element get and set copies the whole 80-byte array (622 M copies).
- **sort_builtin:** `myl_core_s2_sort_in_place` (`src/core/runtime/core_sort.c:752`) is 74% of instructions. That is the algorithm.
- **sort_quick:** branch-miss bound; Rust's partition runs half the instructions.
- **calls and intloop:** latency-bound on `% 1000003`; calls also keeps the floor-mod fix-up in `step`.
- **nbody:**
  - the references know N and unroll the pair loop over fixed arrays;
  - the per-pair uniqueness test is gone since U1.
- **sret sharing** (CE2-B) is off (`emit_homes.zig:37`, `share_sret = false`). Sharing dropped `noalias` and made a 12-field copy slower than the copy it saved.
- **F1's inline free** carries an asm memory barrier (NEW-CORE-F1-TBAA-2). It costs no instructions but shifts layout: result_propagate/4096 1.06–1.09 and option_handle/64 1.02–1.08 (FS-X), with branch misses up 2–3×.

## 2. Targets and rules for this wave

- **The gate is the target.** Each lane has its own exit (§4–§6). X reports every program against the gate.
- **Not reaching an exit is not a stop.** Report the measured bound and what blocks it, and continue.
- **The safety contract is fixed** (L1, 2026-10-04): bounds checks, overflow checks and counts stay. A check may be removed only when a fact proves it cannot fail.
- **Facts stay optimizer-only.** The programmer writes nothing new. No benchmark source changes to gain speed, except to fix a bug, which is logged.
- **Every lane must work in all three build kinds:** debug, `--optimize-debug` (it runs the release Core passes) and release. Each lane's tests run their fixtures under `--verify-facts` too, as F2's and U1's do.
- **Both runtime modes.** If concurrency part 2's package T (`single`/`threads` mode) has reached `main`, every count or release change must hold in both modes. Never change the count-word encoding (plain/shared/immortal) or the task ABI.
- **No wrong answers, ever.** Every merge reruns the gates (CE2-X found a wrong answer made of two individually correct lanes).
- **"Nothing else slower than 1.03×."** Each lane checks this:
  - by instructions on all 45 parity programs, the 46 rows, Lox and EDA;
  - X confirms it in wall time.

## 3. M0: base, tools and gap table (about 4–6 h; on `codex/runtime-parity-3`)

1. **Compilers.** Build ReleaseFast installs of the base: `zig build -Doptimize=ReleaseFast --prefix ~/.cache/mylang/rp3-base-<hash>`. Keep them for the whole run.
2. **External corpora, in the new syntax.**
   - **Copy, never edit:**
     - Lox from `/home/epentland/ai/canopy/mylang-worktrees/claude-main-ce/.mylang-cache/lox` (without `.tmp/` and `results/`);
     - EDA from `…/claude-main-ce/.mylang-cache/eda-src` (its `mylang.json` is in `src/`).
     Put both under your worktree's `.mylang-cache/`.
   - **Check they pass on the base:**
     - Lox 974/974 (`harness/lox_bench.py conformance --engine both --stress`) and port tests 65/65;
     - EDA tests 310/310 (`mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G`) and 34/34 goldens.
   - **If the base rejects them,** re-migrate the originals (`claude-main-ce/.tmp/{eda-src-orig,lox-mylang-orig}`) with `mylang fix` and `experiments/fu-port-20261009/tools/fix_loop.py`, and log what changed.
   - **EDA references** (Zig RS, Zig RF, Rust, Go) are at `/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/.cache/release`. They are read-only.
3. **Tools.** Retarget FU-X's timing tools to your worktree and the new-syntax corpora:
   - `experiments/fu-x-20261009/tools/`:
     - `timing-prep.sh`, `part3.sh`, `ce.py` and `parity_locked.py`;
     - `rows_mylang.py`;
     - `gate_ok.sh`, which accepts N/N steps.
   - PM's `experiments/parity-measure-20261008/tools/`: `cf.py`, `pstat.py`, `ladder.py`.
   - `experiments/parity-confirm-20261009/tools/`: `confirm.py`, `rows_perf.py`.

   Put the retargeted copies in `experiments/runtime-parity-3-<date>/tools/`.
4. **Rows references.** The 2026-10-09 cache prune deleted the frozen Rust/Zig/Go rows runner.
   - Rebuild it with `benchmarks/runtime/expanded/run.py --build-only --work <dir>`, where `<dir>` is a directory of your own under `~/.cache/mylang/`.
   - Mark its worktree `prune-keep` (`touch $(git rev-parse --git-dir)/prune-keep`), so `measure_all46.py` (`experiments/new-core-s4-20261006/integration/`) can compare rows with the references again.
   - If it cannot be rebuilt in about 2 h, use `rows_mylang.py` (base against final only) and log it.
5. **Gate oracles at the base.**
   - Run `qualify_merge.py` with the base compiler and record its exact result (`1516/4/0` at `b51a43b76`, with 4 renamed or added tests that have no frozen reference; it may differ after the front-end fixes). Every later run must equal it, including the same PROBLEM lines.
   - The frozen fuzz generator writes old syntax. Run `fuzz_matrix.py` through `experiments/fu-port-20261009/tools/mylang-migrating`, as FU-PORT did, and record the base's result.
6. **Gap table, CPU 10, under the lock.** Time all of:
   - parity, every arm including `zig-safe`, `zig-fast`, `rust` and `rust-checked`, 9 rounds and 2 warm-ups;
   - Lox, 13 + 13 cells, `mylang`, Zig RS and RF, Rust, Go;
   - EDA, 34 designs, 10 rounds;
   - the 46 rows against the references.

   Write `M0/gap.md`: every program against the gate, as in §1's table.
7. **Counterfactual bounds at the base.** Use `cf.py` on CPU 8, with cycles and instructions, confirmed in wall time on CPU 10 for the cells that set exits:
   - `norc` (counts removed) and `checks+norc` on vm/invocation, vm/fib, vm/method_call, vm/string_equality, tree/equality, tree/string_equality, and EDA `rds3+flat` and `labstation`;
   - `reference_at` inlined, and generated per-layout release if `cf.py` can stub it, on the same EDA designs.

   These set U2's exits in §4.

**M0's exit:**
- the base gates are green;
- `gap.md` is written;
- the counterfactual table is written;
- the tools are committed.

## 4. Lane U2: borrows and release cost (about 14–20 h; `codex/rp3-u2`)

**Owner of:**
- the Lox VM gate;
- most of EDA's allocation and free share;
- the tree-walker's equality cells.

**U2-a. `read_constant` and nested-field borrows.**
- A read through a nested field of a borrowed value is itself a borrow. Today `read_constant` does 3 retains and 3 releases per constant.
- Extend borrow inference in `own.zig` and the Core passes so that a value read from a field of a field of a borrowed parameter, and used only within the borrow's lifetime, takes no count.
- **Exit:** `read_constant` does 0 retains and 0 releases (the PM-1 counters, `NEW-CORE-COUNTERS-*`).

**U2-b. Frame copies on call and return.**
- Lox pushes and pops a frame record per call. Find what copies it (the counters' record-copy sites, and CE2-X's "Lox VM frame reloads 1.6 G") and remove the copies the value semantics do not need: build the frame in its slot; return without a copy-out when the caller discards or overwrites.
- **Exit:**
  - the counted record copies on vm/invocation and vm/method_call are at least 80% down;
  - the cell exits below hold.

**U2-c. Generated per-layout release.**
- Replace the interpreted `reference_at` walk (`core_rt.c:437`, and its uses in `core_dict.c`) with a release function emitted once per layout, which LLVM can inline and specialize. Keep the C walk as the fallback for layouts with no generated function.
- In `threads` mode, use the same count primitives the walk uses.
- **Exit:** EDA's allocation-plus-free share is at most 15% of instructions on `rds3+flat` and `labstation`, from 24–29% (`pstat.py`).

**U2-d. The Lox dispatch leftovers F2 reported.**
- The overflow check on `frame_count - 1` at the dispatch head is redundant by F2's header-edge argument; remove it with a fact.
- Inline `heap::peek` despite its body checks, if the cost model allows it; otherwise log why not.

**U2's exits, all measured against M0's base:**
- CPU 8 cycles at each checkpoint;
- CPU 10 wall time at X, which is binding.

| what | exit |
|---|---|
| vm/invocation, vm/fib, vm/method_call, tree/equality | each closes at least 60% of the gap between the base and M0's `norc` counterfactual |
| Lox VM, 13-cell group | at or under **1.50× Zig RS** (the gate), jointly with S2 and R at X |
| EDA, 34 designs | at or under 0.93× of the base (with S2 and R4 at X: at or under 1.1× Zig RS, the gate) |
| `read_constant` | 0 retains and 0 releases |
| everything else | not slower than 1.03× (instructions) |

**Spec tags:** `NEW-CORE-U2-BORROW-*`, `NEW-CORE-U2-FRAME-*`, `NEW-CORE-U2-RELEASE-*`, `NEW-CORE-U2-LOX-*`.

## 5. Lane S2: split views and search (about 14–22 h; `codex/rp3-s2`)

**Owner of:** text_ops, scan_split, EDA's text materialization, and the string-equality cells.

**S2-0. A text_ops ladder first** (about 2–3 h).
- Write `ladders/text_ops.c` in PM-3's style: a C transcription of today's text_ops, checksummed against mylang's output.
- Add rungs:
  1. views for slices;
  2. split pieces as views;
  3. no intermediate list;
  4. search with `memchr`/two-way;
  5. replace into one buffer.
- Measure each rung's cycles on CPU 8 and confirm the rungs that set the exit in wall time on CPU 10. This replaces PM's estimate of about 1.5× with a bound.

**S2-a. Split views.**
- A piece of `s.split(sep)` is a view into `s`, an (offset, length) pair, until it escapes into storage that outlives `s`'s block, or is mutated. Then it materializes.
- Where the list is only iterated (`for part in s.split(…)`), split lazily without building the list (PM's rung 2).
- Reuse S1's view machinery (`str_slice_view`, `fuse_slice_key.zig`, the ASCII inheritance) and its update guard.

**S2-b. Search fast paths.**
- `find`, `count`, `replace`, `startswith`/`endswith` and `in`:
  - single-byte needles use `memchr`;
  - short needles use a two-way or SSE2 search;
  - `replace` sizes its output once.

**S2-c. S1's remaining limits.**
- `fuse_text_split` re-probes with the materialized key on insert. Probe once.
- Byte-string slices allocate. Give them views as for `str`.
- Views stored in records, as in EDA's tokenizer, need substring blocks: a child block that borrows its parent's bytes and holds a count on the parent. Do this only if S2-0/PM's EDA profile shows it is worth at least 3% of EDA's instructions. Otherwise log it and skip it.
- Decide whether views stay release-only. `--optimize-debug` already runs the release passes. Plain debug may keep copies; log the decision.

**S2's exits:**

| what | exit |
|---|---|
| scan_split | at or under **0.75× Zig RS** (stretch 0.6) |
| text_ops | at or under **1.5× Zig RS**, and within 1.15× of the best ladder rung reachable without a language change |
| EDA text materialization | at most half of today's share of instructions (10–12% → 6% or less) |
| knucleotide | not slower; allocations per position stay at 0.05 or below |
| everything else | not slower than 1.03× (instructions) |

**Spec tags:** `NEW-CORE-S2-SPLIT-*`, `NEW-CORE-S2-SEARCH-*`, `NEW-CORE-S2-VIEW-*`.

## 6. Lane R: leftovers (about 14–20 h; `codex/rp3-r`)

R1–R5 are implementation work. R6 is a set of time-boxed investigations; implement any lever R6 finds that is worth at least 5% on its cell and needs no language change.

**R1. Fixed-array elements in place.**
- A get or set of one element of a `FixedArray[T, N]` (and of the `[N]T` value arms) reads or writes the element in place. It must not copy the whole array.
- **Exit:** fannkuch `my-array` and `my-tuned` at or under 1.05× of fannkuch `my`.

**R2. The runtime i64 sort.**
- Replace the algorithm in `core_sort.c` (`myl_core_s2_sort_in_place`) for integer keys with pattern-defeating quicksort, or an equivalent with branchless partitioning and an insertion sort for short runs.
- It must stay stable where the language promises stability. Check `docs/` and the tests, and keep stable sorts stable.
- **Exit:** sort_builtin at or under **1.2× rust-checked**; sort_records not slower.

**R3. sret sharing that keeps `noalias`.**
- Redo CE2-B's step 3 (`emit_homes.zig`, `Planner.shareable`) so the callee keeps `noalias`. For example, load every field before storing any, or share only when the planner proves the copied fields are disjoint.
- Turn `share_sret` back on only if the CE2-B programs gain and nothing is slower. Update NEW-CORE-CE2-RESULTS-5's test and bullet.
- **Exit:**
  - the rows' `record_pass` (CE2-X's "Run 1" regression, 1.15–1.19× with sharing on) is at or under 1.0× of sharing off, with its copies at 0;
  - no parity program, row, Lox cell or EDA design is slower than 1.03×.

**R4. EDA P6: a record pushed onto a list is built in its new slot.**
- Add the payload-destination ABI that the values-and-keys plan (`docs/audits/values-keys-trap-search-plan-2026-10-07.md`, near line 925) describes, so `parse_list`'s push constructs in place.
- **Exit:** P6's copied bytes at least 90% down (CE2-X counted 0.44 GB).

**R5. Narrow F1's inline-free barrier.**
- Replace the asm memory barrier on the inline free with the narrowest construct that keeps F1's soundness argument (`experiments/f1-facts-20261009/REPORT.md`). An example is a barrier on the freed block's memory only, or an `llvm.lifetime.end`-style marker; prove it with F1's tests.
- **Exit:**
  - result_propagate/4096 and option_handle/64 within 1.02× of M0's base with the barrier removed (a probe build), with branch misses back near that build's;
  - F1's TBAA tests still pass;
  - nothing is slower.

**R6. Investigations** (about 2–3 h each). Implement only a lever that is optimizer-only.

| cell | question | if a lever exists |
|---|---|---|
| nbody 1.39× Zig RS | Do the references' fixed N and unrolling explain the rest? Write a C ladder. Can a length fact for a list built from a literal and never resized give LLVM the same trip count? | Implement the length fact. **Exit:** nbody at or under 1.2× Zig RS. |
| calls 1.26×, intloop 1.19× rust-checked | Is the residual the floor-mod semantics (`%` is Python's) or codegen? When facts prove both operands non-negative, emit `urem` and drop the fix-up. | Implement. Otherwise record it as a semantic difference in §8.3's list. |
| sort_quick 1.21× rust-checked | Why does Rust's partition run half the instructions? `cf.py` checks/norc, then compare the LLVM. | Implement what is optimizer-only. |
| records 1.11× rust-checked | Is it the sret copy (R3) or something else? | Usually R3. |
| matmul `my-tuned` 1.65× Zig RS | Why is the tuned arm 5× slower than `my` (about 0.30× Zig RS)? | Implement if cheap; otherwise log. |

**Spec tags:** `NEW-CORE-R-ARRAY-*`, `NEW-CORE-R-SORT-*`, `NEW-CORE-R-SRET-*`, `NEW-CORE-R-PUSH-*`, `NEW-CORE-R-FREE-*`, `NEW-CORE-R-FACT-*`.

## 7. X: integration, qualification and timing (about 6–10 h; `codex/runtime-parity-3`)

1. **Merge the lanes** with real merge commits, in the order U2, S2, R. Then rerun every gate in §8.1 on the merged tree. Two correct lanes can make a wrong merge.
2. **Build a ReleaseFast compiler** of the final tree.
3. **Time on CPU 10, under the lock,** the base against the final, interleaved within one session. The corpora are M0's: parity (all arms), Lox (13 + 13), EDA (34) and rows (46, against the references). Follow FU-X's method (`experiments/fu-x-20261009/REPORT.md`, "Rows method"). Record the load at start and end.
4. **Review every cell slower than 1.03×** with CPU-8 instructions, cycles and branch misses, as FU-X's "Cells above 1.03×, reviewed" does. Fix real regressions. Layout-only cells are reported with their evidence.
5. **Write `X/gap.md`:** M0's gap table with the final column, every program against the gate, and what is left for each program above it.

**X's exit:**
- every gate is green;
- the lane exits are reported, met or with their measured bound;
- nothing is slower than 1.03× beyond noise;
- the gap table is written.

## 8. Gates, defaults and exceptions

### 8.1 Gates (each lane before its hand-off, and X after the merge)

- **Repository:** `zig build`, `zig build test --summary all` with every step green, and `zig build fmt-check` (including the `.my` formatting gate).
- **Conformance:** `qualify_merge.py --shards 64` equal to M0's base result in debug and release, with leak and fact verification. Use a fresh `--evidence` directory under `experiments/`, and never reuse a basename.
- **Fuzz:** the frozen matrix through the migrating wrapper, equal to M0's base result. Run 9×50 per lane and 9×200 at X, never beside the full gate.
- **Lox:** 974/974 and the port tests, 65/65.
- **EDA:** 34/34 goldens and 310/310 tests.
- **Parity:** every program's output equals its `.expected`.
- **Counting:** the same output with counting on and off.
- **Build kinds:** each lane's own tests run their fixtures in debug, `--optimize-debug`, release and `--verify-facts`.

### 8.2 Defaults Codex should take, and log

- **Lane order without subagents:** U2, S2, R. U2 carries the Lox VM gate.
- **Substring blocks (S2-c):** only with the ≥3% EDA evidence.
- **Views in plain debug:** Codex decides, and logs it.
- **The free barrier (R5):** if no narrower construct is provably sound, keep F1's barrier and report.
- **A lane that misses its exit** reports its measured bound and the blocker. It still hands off, and X still integrates it if it is correct and makes nothing slower.

### 8.3 Exceptions the user decides afterwards

These are listed in the report, never applied by Codex:
- a residual that is a language-semantics difference, not a compiler lever (for example floor-mod against Rust's `%`);
- a program whose remaining gap needs a language change, or a change to its benchmark source;
- any proposal to change the gate itself.

## 9. Rules and autonomy

**Branches and worktrees:**
- Use only `codex/runtime-parity-3`, `codex/rp3-u2`, `codex/rp3-s2` and `codex/rp3-r`, in your own worktrees.
- Lock each worktree: `git worktree lock --reason`. Check `git worktree list` before you reuse a pool tree.
- Make real merge commits; never rebase another run's commits.

**Builds:**
- Every build goes through `scripts/build-slot.sh`.
- Use ReleaseFast compilers for timing and instruction counts, and Debug for the gate.
- Run at most four build-heavy processes machine-wide. Other Codex runs share the machine: concurrency part 2, incremental stages and compiler memory.
- Never build a ReleaseSafe compiler for `mylang test`. It hangs on `/proc/meminfo` (an open defect).

**CPUs:**
- **CPU 10:** wall time and cycles that set an exit, only under `flock /run/user/1000/mylang-slots/cpu10.lock`, and with no build running while you hold it.
- **CPUs 2, 3, 10 and 11:** never run heavy work there.
- **Instruction counts** can run on any other CPU; they are insensitive to load.
- **For quick A/B checks while developing,** `mylang juice record/compare` (`docs/tooling/juice.md`) gives instructions per unit of work.

**Caches and temporary files:**
- Put `ZIG_LOCAL_CACHE_DIR`, `MYLANG_CORE_RUNTIME_CACHE` (per compiler tag; a shared one caches compile timings across compilers) and `TMPDIR` inside your worktree, on disk.
- Check `df -h /home/epentland/ai` before big builds; it filled once on 2026-10-09.
- Delete your scratch when a step is done.

**Processes:** kill only your own PIDs; never `pkill -f`.

**Evidence:**
- `experiments/runtime-parity-3-<date>/`, with `M0/`, `U2/`, `S2/`, `R/` and `X/`, plus `DECISIONS.md`, `REPORT.md` and `tools/`.
- Under 10 MB in total. Keep summaries and gzip raw JSON; drop raw command logs once they are summarized.

**Guardian:**
- one `// spec:` tag per `SPEC.md` bullet; extra tests carry `// spec-case:`;
- at most 7 struct fields and 6 parameters;
- `///` docs on `pub` declarations;
- straight-line test bodies.

**Known traps:**
- **Release builds drop unused functions.** A probe edit must change reachable code.
- **The Lox VM responds non-monotonically.** Confirm each step's effect; do not assume variants add up.
- **Versioning a loop that calls** can make LLVM's x86 cmov converter emit branches. `NEW-CORE-FSX-VERSION-1` versions only call-free, inner-loop-free loops; keep it.
- **The 2026-10-09 cache prune** deleted frozen runners. Mark anything long-lived `prune-keep`.

**Decide, log, continue.** Implementation choices, files and gate failures are yours to resolve.
- Record each decision in `DECISIONS.md` with the question, the options, the evidence, the choice and its reversibility.
- A flaky-looking failure gets one rerun; a repeat is real.
- Early measurements are checkpoints; X's CPU-10 timing is binding.

**Hard stops** (report and stop only for these):
1. **A semantic change.** This includes:
   - a change to the language surface or its value semantics;
   - weakening the L1 safety contract: a bounds or overflow check removed without a proving fact, or a count that is needed;
   - a change to which programs trap, or with which trap code.

   A trap's reported location may move within the same source line, as with F2 and U1's forwarding; log it.
2. **A forbidden file,** edited by you:
   - the frozen references and runners under `experiments/new-core-s5-20261007/` (`references/`, `frozen-old-core/`);
   - other packages' evidence under `experiments/`;
   - concurrency part 2's task and thread runtime (`src/core/runtime/core_tasks.c`, `src/core/runtime_mode.zig`, and any file named for tasks or threads);
   - the count-word encoding.

   Changes that arrive through a merge of `main` are not edits by you; merge them and log them.
3. **A relaxed gate:** lowering a threshold, or skipping or narrowing a gate. Measuring better is allowed and gets logged.
4. **A broken premise:**
   - M0 cannot establish the base: the corpora cannot be migrated or made to pass on the base, or the gate oracles disagree with `main`'s own result in a way you cannot explain;
   - a lane finds that a gate's oracle is itself wrong.
5. **An unfixable failure:** a correctness failure that about 8 hours of investigation does not fix.
6. **A touch outside the branch:** a merge into `main`, a push, a change to a Claude worktree or branch, or a prune of caches you do not own.
7. **Resources:** disk, memory or slots you cannot recover within your own files and processes.

## 10. Report

`experiments/runtime-parity-3-<date>/REPORT.md` should give:
1. the base hash, the final head, and the commits for each step;
2. M0's gap table and counterfactual table;
3. **for each lane:** what changed (with file:line), the spec tags, and each exit as measured (CPU 8 at hand-off, CPU 10 at X);
4. every gate receipt (steps and tests, conformance, fuzz, Lox, EDA, parity, counting);
5. X's final-against-base timing, the review of cells above 1.03×, and the final gap table against the gate;
6. a summary of `DECISIONS.md`: decisions that changed the plan, defaults taken, hard stops reached or narrowly avoided;
7. §8.3's exceptions for the user;
8. **what remains to the gate,** per program, with the next lever for each. This is read-only follow-on analysis chained onto the end of the run.

Subagents return report text; the coordinator writes the files.

## 11. Out of scope

- language changes for speed, including fixed-size syntax in the benchmarks;
- tail calls or `notail` removal for fib against Zig RF; the L1 contract rules this out;
- the debug back end (package DL);
- concurrency;
- the front end;
- compile-time work, unless a lane makes release compile time more than 10% slower on EDA or Lox. Report that in X.
