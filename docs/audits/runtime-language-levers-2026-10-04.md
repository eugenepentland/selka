# Runtime performance: change the rules before more tuning — plan, 2026-10-04

**Status.** The user accepted decisions L1–L4 and the recommended one-count decisions D1–D4
on 2026-10-04.

**Revision 2 (2026-10-04).** This revision adds:
- the `integer_math` ideal-ladder pilot (§3.1);
- L4: a single platform for the optimized path;
- WP-6 on hold;
- two Claude-run decision lanes, WP-8 (direct-emitter spike) and WP-9 (ideal ladder study);
- a decision point at the end of Wave 1 (§5).

**Revision 4 (2026-10-05): scope change.** The user accepted the new-core plan
(`docs/audits/new-core-plan-2026-10-05.md`, decisions N1–N5).

What changes for this campaign:
- **Continue:** WP-0, WP-4 and WP-5 (one-count RC on the shared runtime), plus the dev-loop
  fixes DL-1 to DL-5 from that plan.
- **Finish in-flight items, then start no new performance work on the old back end:**
  WP-1's alignment policy, WP-3 Stages A–C, WP-10c–e, and the WP-11 typed-region route.
  The new core redoes these.
- **Keep:** correctness and real-program fixes on the old core (Lox, EDA).

**Revision 3 (2026-10-04).** This revision adds:
- the WP-9 ladder study's results (§3.2, full study in
  `experiments/runtime-ideal-ladder-20261004/README.md`);
- **WP-10**: implementation fixes the study found. They are independent of the Wave 1
  decision, so they can start now.

**Base.** `perf/runtime-parity-20261003` at `ac72a905` (integrated production source
`0d8a360c`), worktree `/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003`.

**Related documents.**
- `benchmarks/runtime/RUNTIME_110_GOAL.md` on that branch: the live campaign dashboard and
  timing protocol. The campaign coordinator owns it.
- `docs/audits/gc-retirement-and-one-count-plan-2026-10-03.md` on `claude/gc-retire-plan`
  (`66990f1e`): the GC-retirement and one-count RC plan this document defers to. It is not
  on `main` or the campaign branch yet. Read it with
  `git -C /home/epentland/ai/canopy/mylang show claude/gc-retire-plan:docs/audits/gc-retirement-and-one-count-plan-2026-10-03.md`.
- `benchmarks/runtime/audit/README.md`: the 2026-10-03 per-benchmark audit (packages P0–P9).

Audience: implementation agents (Codex). Every work package (WP) below lists its
dependencies, files, steps and acceptance. Section 6 holds the rules that apply to all of them.

**Where this plan lives.** Branch `claude/runtime-levers-plan`, which is the campaign branch
plus this file. Read it with
`git -C /home/epentland/ai/canopy/mylang show claude/runtime-levers-plan:docs/audits/runtime-language-levers-2026-10-04.md`.

## 0. Launch instruction

Give this to the coordinating agent:

> **Plan.** Implement `docs/audits/runtime-language-levers-2026-10-04.md` (branch
> `claude/runtime-levers-plan`) against the campaign worktree
> `/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003`.
>
> **Decisions.** L1–L3 and D1–D4 are accepted. Do not change language semantics beyond them.
>
> **Coordination.** The coordinator owns integration onto `perf/runtime-parity-20261003`,
> the dashboard in `benchmarks/runtime/RUNTIME_110_GOAL.md` and timing CPU 2.
> - First switch the dashboard to the L1 gate (WP-0).
> - Then pause new tuning of hold, loan and scope paths (WP-5).
>
> **Wave 1.** Run these as one lane each, in their own locked worktrees branched from the
> latest integrated head:
> - WP-0, WP-1, WP-2;
> - WP-4 steps 1–4;
> - WP-3 steps 1–2;
> - one-count G0/G1/C0 from the one-count plan.
>
> **Lane rules.** Follow section 6 for builds, gates, timing and hand-back reports. Run at
> most four build-heavy lanes at once.
>
> **Integration.** Integrate a lane only after reviewing its evidence and running the full
> gate yourself.
>
> **Scope change (revision 4, 2026-10-05).** A new compiler core is being built
> (`docs/audits/new-core-plan-2026-10-05.md`).
> - Continue WP-0, WP-4, WP-5 and the dev-loop fixes DL-1 to DL-5.
> - Finish in-flight work. Start no new performance work on the old back end: no new WP-1
>   policy work, WP-3 Stages A–C, WP-10c–e or WP-11.
> - Correctness and real-program fixes on the old core continue.
>
> **WP-10 status.** WP-10a and 10b may finish if already started. 10c–e move to the new core.
>
> **Held and reserved work.** WP-6 is on hold until the Wave 1 decision (§5). Claude agents
> run WP-8 and WP-9 on their own branches; Codex lanes do not take them or edit those
> branches.
>
> **End of each wave.** Run the integrated 80-row screen under L1 and report what moved.
> Do not merge into `main`.

## 1. Summary

The current campaign tunes the compiler one mechanism at a time inside fixed language rules.
Over about 11 hours it moved LLVM rows at or below 1.10× from 7 to 10, with no confirmations.
The median open LLVM row (excluding `alloc_short`) is 2.23×, so each needs about a 51% cut.
Accepted changes deliver 3–20% each, and some are later reversed by layout effects.

Most of what remains is set by three things, not by missing peephole work:

1. **Language rules the fastest arms do not pay.** Checked arithmetic with exact trap order,
   and a memory budget that makes every allocation observable.
2. **The two-count RC model.** Holds cost a third of all count operations. In `word_count`,
   37% of samples are spent taking holds on a dictionary for reads.
3. **LLVM receives QBE IL.** By the time LLVM sees the program, the facts value semantics
   guarantees (an immutable list cannot change during a loop) are gone. LLVM therefore
   reloads and re-checks values that Rust's LLVM proves invariant or in bounds.

This plan:
- changes the target (L1);
- changes two language rules (L2, L3);
- then attacks (2) and (3) in WP-5 and WP-6.

The campaign's measurement protocol stays: paired sessions, independent confirmation and
correctness receipts.

## 2. Decisions

| ID | Decision | Status |
|---|---|---|
| **L1** | Gate each case and size on **MyLang LLVM ≤ 1.10× Zig ReleaseSafe**, from the same session. Keep reporting fastest-of-six as a stretch number. | Accepted 2026-10-04 |
| **L2** | In release builds, a failing compiler-inserted check may trap anywhere in its effect-free region (rule below). Debug builds keep exact traps. | Accepted 2026-10-04 |
| **L3** | Remove the memory budget from the language. The OS-level process ceiling stays as a host safety net. | Accepted 2026-10-04 ("we don't need the memory budget in the language at all for now") |
| D1–D4 | One-count RC: live-place iteration, non-storable dictionary views, MUT-EXCLUSIVE-4, a saturating 32-bit count | Accepted 2026-10-04 (the recommended options in the one-count plan §4.2) |
| **L4** | The optimized (LLVM) path may target one platform for now: x86-64 Linux with AVX2 (the alderlake-class host). QBE stays the fast Debug backend and a correctness reference, with no performance goal. | Accepted 2026-10-04 ("I'm okay with it only working with one platform for now") |

### 2.1 L1: the comparator

Fastest-of-six is set by Rust on 37 rows and by Zig ReleaseFast on 30. Neither checks
integer overflow, and Zig ReleaseFast checks nothing. On the current dashboard, the other
arms also miss a 1.10× fastest-of-six bar:

| Arm | Rows ≤1.10× fastest-of-six (of 80) |
|---|---:|
| Rust | 47 |
| Go | 5 |
| Zig ReleaseSafe | 2 |
| MyLang LLVM | 10 |

Zig ReleaseSafe is the arm whose safety contract is closest to mylang's: checked overflow,
bounds checks and traps instead of undefined behaviour. Against it, MyLang LLVM is already
within 1.10× on 33/80 rows and within 1.5× on 54/80. The rows left open under L1 are the
ones where mylang's own design costs time: text, collections, allocation and RC.

- **Acceptance is unchanged except for the denominator.** The same 15-round/3-warmup
  sessions, the same independent confirmation, and the same paired 95% bounds apply. The
  upper bound of LLVM/Zig-ReleaseSafe must be ≤1.10 in both sessions.
- **No new measurements are needed to start.** Every existing raw report already contains
  the `zig-safe` arm.
- **`alloc_short` needs no redefinition under L1.** Zig ReleaseSafe performs the allocations:
  it is 88.6×/1374.8× slower than Zig ReleaseFast there. MyLang LLVM is 14.2×/14.3× Zig
  ReleaseSafe.
- **QBE remains tracked and is not gated.** Same-session before/after regression checks on
  both backends stay as they are.

### 2.2 L2: trap precision in release builds

Proposed SPEC rule (new tag, e.g. `TRAP-REGION-1`):

> **Visible effects.** A visible effect is:
> - a write to a `Stream`;
> - a call that crosses a capability, `extern` or native-provider boundary (Filesystem,
>   Network, Clock, Entropy, Environment, Host);
> - normal process exit.
>
> Heap and local mutations are not visible effects. Traps are fatal and tear the heap down
> (RC-TRAP-TEARDOWN-1), and there is no `try`/`except`.
>
> **Rule.** In a ReleaseFast build run without `--max-steps`, this rule applies to
> compiler-inserted checks: overflow, division by zero, index and key range, and checked
> conversions. When such a check fails, the program must trap. The trap may be raised at any point between the last visible effect before the
> failing operation and the first visible effect after it, in program order. The compiler may
> therefore hoist, defer or merge checks inside that region.
>
> **Constraints.**
> 1. No visible effect may be reordered across the trap.
> 2. No value produced by a failing operation may reach a visible effect.
> 3. A check may not be deferred across a loop or call that is not proven to terminate,
>    unless the deferred condition is tested on every iteration of it. A program that would
>    trap must never hang instead.
>
> **Reporting.** If several checks in one region would fail, any one of them may be
> reported. The trap report keeps its kind and names a position inside the region.
>
> **Unchanged.** Debug builds keep today's exact position and order. Explicit `assert`
> statements, error-return traces, `--max-steps`, `--max-frames` and `--timeout` are not
> affected.

L2 permits, in increasing order of effort:
- a single `high <= len` check before an affine index loop instead of one per iteration;
- overflow checks merged into one sticky flag tested at the region exit;
- vectorized checked reductions;
- deleting exact-fallback loop versions that exist only to preserve trap order.

**SPEC tags that pin exact traps today.** L2 adds a release-build exception to each of these.

| Tag | What it pins |
|---|---|
| QBE-STICKY-1 | "stops the program at the same instruction with the same code, trace and detail" |
| QBE-UNWIND-1 | "no guest instruction runs after the failure" |
| QBE-POSITION-1, QBE-POSITION-2 | the pc a trace names |
| QBE-TRAP-DETAIL-1 | the original index and length, or the evaluated operands |
| RELEASE-CHECKED-1 | "a guard is omitted only where the compiler has proved it cannot fire" |
| QBE-LOOP-VERSION-1 | a trap the guard cannot rule out is raised "by the original at the same iteration" |
| LLVM-STICKY-REDUCTION-1 | the restore-and-replay fallback |

Under L2, a merged or hoisted check may report detail that describes the merged condition
(for example, the loop's highest index against the length) rather than the first failing
element.

The audit's P2 rule ("the original fallback must preserve the first observable failure and
partial mutations", `benchmarks/runtime/audit/README.md`) is relaxed by exactly this much.

### 2.3 L3: no memory budget in the language

**Removed:**
- the `R_MEMORY_BUDGET` trap;
- allocation refusal as a guest-visible outcome;
- `--max-memory`/`MYLANG_MEMORY_LIMIT` as a language budget;
- runtime and compiler plumbing whose only purpose is to report refusal to the guest
  (refusal statuses and the status checks that follow allocations).

**Kept, as host policy rather than language semantics (assumption; revisit with the user):**
- the process address-space ceiling (`RLIMIT_AS`) on `mylang run`, `mylang test` children and
  native executables;
- the compiler's own ceiling (`MYLANG_HOST_MEMORY_LIMIT`);
- `mylang test <dir>` fan-out sizing from `MemAvailable`.

When the OS refuses memory, the runtime prints one fixed fatal message and exits 1. Where
this happens is unspecified.

**What L3 makes legal:**
- eliding, merging or stack-allocating any allocation whose result does not escape;
- borrowing a string's UTF-8 bytes instead of copying them for a read-only `encode()`
  consumer. The audit's P6 noted that "simply removing the copy changes an observed
  refusal"; under L3 only the lifetime proof remains;
- dropping refusal checks after allocation sites.

**Coupling to fix:** `--max-frames` currently reserves 32 KiB of `--max-memory` per frame
(`mylang run --help`; `src/memory_budget.zig`). The frame budget must stand on its own.

**Out of scope for L3:**
- **The static allocation effect is unchanged.** `managed_allocation`/`noalloc`
  (EFFECT-INDEX-1 and the effects docs) is a compile-time property of the source, not a
  runtime budget.
- **Counting builds may show different numbers.** Counting builds (`MYLANG_COW_COUNTING`,
  COW-STATS-1, RC counting) are diagnostics. Their counts may change when allocations are
  elided, and that is not a semantic change.

## 3. Evidence

Ratios come from the `RUNTIME_110_GOAL.md` dashboard as of 2026-10-04 12:20 UTC (integrated
source `1a398063`). Each row keeps its own evidence ID (B0, T9, T14, G4 or T23). They are
medians relative to the fastest arm in that row's session. Later T25 updates moved a few rows
by a few percent, so the counts below may shift slightly when WP-0 recomputes them.

**Profiles and disassembly (2026-10-04).**
- Guests were built from the campaign worktree with
  `mylang build <main.my> -o <out> --release --keep-symbols --link benchmarks/runtime/ports/native_clock.c`.
- They were profiled with `perf record` pinned to CPU 9, not the timing CPU.
- These are short profiles with few samples. They show where time goes; they are not
  timings.

| Row | What the hot code shows |
|---|---|
| `integer_math` (LLVM 1.85×/1.93×) | **MyLang loop, per iteration:** four `jo` overflow branches; roughly ten extra instructions for the sign corrections of Python floor `//` and `%`; the list length is reloaded from the header and bounds-checked; the data pointer and `kind` are reloaded from memory; `kind` is range-checked before the jump table. **Rust's loop:** no overflow checks, no bounds check, truncating division. Both keep one indirect jump per iteration for the `kind` dispatch, so the dispatch is not the difference. |
| `call_direct` (1.77×/2.26×) | `affine_a` is inlined. The rest of the loop is the same dispatch, checks and reloads as above, wrapped around a 3-instruction body. |
| `result_propagate` (2.41×/2.48×) | The `Result` is stored to stack slots each iteration. About 4% of samples are in `myl_qbe_error_trace_append_preserve_most`. |
| `word_count` (12.1×/8.7×) | 37% `scope_capture_dictionary` (holds on the dictionary's three backing blocks for reads such as `word in counts`), 12% `probe_text`, 12% `myl_native_dictionary_contains`. |
| `csv_aggregate` (6.1×/5.6×) | About 30% across `locate`, `myl_native_text_at`, `raw_bytes` and `offset_walk`. `for ch in text` maps every character index to a byte offset. |

**Placement noise.** Four candidates were rejected or deferred over the same 15–16% large
`string_search` slowdown:

| Candidate | Evidence | Large `string_search` slowdown |
|---|---|---|
| `965d416c` | T1 | ~15% |
| `99a4d071` | T6 | 16.3% |
| `52e6d074` | T8 | 16.8% |
| `0311796e` | T17 | 15.5% |

T21 showed that a 32-byte padding change alone moves that row from 1.149× to 1.008×.
The single-change gains being judged are about the same size as these layout effects.

### 3.1 Ideal-ladder pilot: `integer_math`

Source, commands and full results: `experiments/runtime-ideal-ladder-20261004/`.

**What was built.** The kernel was re-implemented in C as a ladder: each version gives the
compiler one more fact. Every version reproduces the benchmark checksum. These are
exploratory timings on a non-timing CPU of a busy host.

| Version | vs Rust (large) | Cycles/elem |
|---|---:|---:|
| mylang LLVM today | 1.87 | 11.4 |
| Rust (fastest arm) | 1.00 | 5.8 |
| + L2 sticky checks, immutable list, one bounds check | 2.04 | — |
| + element range 0..1008 (i64 and floor kept) | 0.31 | 1.75 |
| + u16 storage and u16 arithmetic, plain C | — | 2.4× better than the previous step (measured in a later, busier run: 0.87 vs 2.06) |
| Hand AVX2 intrinsics, i64 storage | 0.08 | 0.48 |
| Hand AVX2 intrinsics, u16 storage | 0.06 | 0.35 |

**What it shows.**

1. **The fact that matters is the element range.** It comes from the comprehension that
   builds `values`, which is never mutated, so value semantics makes it provable.
   - Rust and Zig lose that fact because the data passes through memory.
   - With the fact, checks are omitted under the existing RELEASE-CHECKED-1, and LLVM
     vectorizes on its own.
2. **L2-style checks gave nothing on this kernel.** WP-3's value is for data whose range is
   unknown.
3. **LLVM does not narrow i64 arithmetic itself.** The front end must emit the narrowest
   proven width.
   - QBE IL cannot express 16-bit arithmetic or vectors at all.
   - Hand vectorization adds another ~2× over LLVM's best from C.
   - The estimated hardware floor is ~0.25 cycles/elem.
4. **The levers need a front end that knows ranges, widths and loop shape.** These are
   exactly what the QBE IL → LLVM translation cannot carry without a growing comment-marker
   side channel. WP-8 tests the alternative.

### 3.2 Ideal-ladder study: eight more cases (WP-9)

**What was done.** The same method as §3.1 was applied to eight more cases: `float_math`,
`list_filter`, `dict_lookup`, `tagged_stack`, `string_split`, `branch_mixed`, the
`json_transform` parse component and the `lox_eval` dispatch loop.
- Every step reproduces the benchmark checksums.
- Every case has an input-from-file holdout and a baseline-x86-64 build.
- Source and tables: `experiments/runtime-ideal-ladder-20261004/README.md` (branch
  `claude/ideal-ladder-20261004`, fast-forwarded into this branch).
- The numbers are exploratory, from a shared host.

**Findings that change priorities.**
1. **Implementation fixes dominate the L1 gate.** In 6 of 8 cases, the largest step toward
   ≤1.10× Zig ReleaseSafe is an implementation fix that needs no new fact or language rule.
   The fixes are below, and form WP-10.

   | Case | Fix | Gain | Notes |
   |---|---|---|---|
   | `float_math` | Inline `int(float)` | 1.87× | Reaches Zig ReleaseSafe parity alone. It is a call into `myl_qbe_float_unary` today, which took 32% of samples in an independent check. |
   | `tagged_stack`, `lox_eval` | Build unions in place | 1.77×, 3.04× | Removes a store-forwarding stall. Independent check: 30,010 `ld_blocks.store_forward` in mylang against 36 in Rust for the same run. |
   | `dict_lookup` | Read-only probe that writes no hint | 1.78× | |
   | `string_split`, JSON | Non-escaping temporaries and `encode()` | ~3–4× | Already WP-4 steps 5–6. |
2. **`llvm.assume`/`!range` on values does not make LLVM narrow** `sitofp`/`fptosi` or the
   arithmetic: `float_math` v13 gained 1.00×. Emitting narrow types from the front end
   gained 2.3–2.5×. This is direct evidence that markers alone (WP-6a) cannot unlock the
   vector loops, and it supports WP-8.
3. **L2 sticky checks and hoisted bounds give 0.9–1.3×.** WP-3 Stages A–C stay behind
   everything else.
4. **File data does not need a range language feature (yet).** A runtime guard computed
   once over an immutable list (all elements within a bound), followed by the vector loop,
   recovered the whole gain in 3 of 4 cases.
5. **The dictionary gap is representation and protocol**, not LLVM facts:
   - two dependent cache lines per lookup;
   - hint writes on read-only lookups;
   - 0.5 branch mispredicts per lookup.

   A flat, well-hashed table gives 3.2× on sparse keys, and a branch-free AVX2 bucket probe
   5.3×. A further 3.3× on the fixture's sequential keys is hash luck and does not count.
6. **Some range facts cross function boundaries** (dictionary values, lists passed to
   helpers). Local analysis alone will not find them.

**Lever ranking toward faster-than-fastest**, by total gain across the nine cases:
1. range → emitted narrow types → vectorization;
2. SIMD library kernels (byte scan, bucketed probe, gather);
3. removing allocations and copies;
4. union materialization;
5. modular strength reduction;
6. RC protocol on unique locals;
7. fusion;
8. then typed decode, threaded dispatch, FMA, and last L2.

## 4. Work packages

Paths are relative to the campaign worktree. Sizes: S ≤ 1 day, M a few days, L a week or more.

### WP-0 Gate on Zig ReleaseSafe (L1) — S, start now

**Goal.** Make L1 computable and visible, without breaking the existing tooling or evidence.

**Files.**
- `benchmarks/runtime/goal110.py`. It uses `THRESHOLD = 1.10` and computes `fastest = min(medians)` in `session_rows`, with `SCHEMA = mylang-runtime-goal110-analysis-v1`.
- `benchmarks/runtime/test_goal110.py`.
- `benchmarks/runtime/GOAL110_REPORTING.md`.

**Steps.**
1. Add a comparator option, `--gate zig-safe|fastest`.
   - The new default is `zig-safe`.
   - The paired intervals for the gate become LLVM/zig-safe only.
   - Self-comparison stays exactly `[1, 1]`.
   - The fastest-of-six ratio and its intervals stay in every output as `stretch`.
2. Bump the schema to `…-v2`. Keep v1 readable and unchanged; old evidence must still replay.
3. Recompute the dashboard from the evidence already on disk: B0, G1–G4 and T23/T25. Do not
   run new timings.
4. Write a proposal table for the coordinator with four columns: L1 state, the LLVM/zig-safe
   ratio and its upper bound, the stretch ratio, and the QBE ratio.
5. Test the failure modes:
   - a session missing `zig-safe`;
   - zig-safe being the fastest arm;
   - a row whose upper bound crosses 1.10;
   - mixed v1/v2 inputs.

**Acceptance.**
- `python3 benchmarks/runtime/test_goal110.py` passes.
- Replaying the existing evidence under v1 reproduces every row's current dashboard values
  exactly.
- Under v2, the dashboard as of 12:20 UTC gives about 33 rows at or below 1.10. That figure
  is a hand count; T25 rows may move it slightly.

**Ownership.** The coordinator applies the dashboard change to `RUNTIME_110_GOAL.md`.

### WP-1 Placement control — S/M, start now

**Goal.** Stop accepting or rejecting changes because of layout. Then re-judge the
candidates that layout blocked.

**Facts.**
- No alignment flag is passed anywhere today.
  - clang `-cc1` flags come from `Compiler.probe` (`src/qbe_build_llvm_compile.zig:217-228`).
  - Full-LTO lld flags come from `fullLto` (`src/qbe_build.zig:1376-1387`).
  - ThinLTO flags come from `src/qbe_build_llvm_thin.zig:72-82`.
- These flags are not in the object cache key. A new one needs a field in `Environment`
  (`src/qbe_build.zig:232`) or in `Toggles.identity()` (`src/qbe_build_llvm.zig:59-68`).
- The deferred candidate `5818cee8` (branch `perf/goal110-natural-loop-align-20261004`) adds
  32-byte natural-loop alignment (LLVM-NATURAL-LOOP-ALIGN-1). It does so **in the same
  commit** as floor-result range facts (LLVM-FLOOR-RESULT-RANGE-1), so its direct-call cost
  cannot be attributed.

**Steps.**
1. **Layout-sensitivity harness.** Add a diagnostic mode that builds each MyLang guest at
   K ≥ 4 layouts and records the spread of medians per row. It is a separate, labelled
   report, never confirmation evidence. Two ways to vary the layout:
   - text-section padding before the hot units;
   - `-mllvm -align-all-functions=N` / `-align-all-nofallthru-blocks=N` variants passed
     through the lld `-mllvm` path.
2. **Run the harness once on the integrated head** and publish each row's layout band. Use it
   when judging later candidates:
   - a difference inside the band is "layout", not a regression;
   - a difference outside the band needs the existing instruction-count attribution.
3. **Choose one default alignment policy for MyLang output** by measuring these options alone,
   with no other code change:
   - function alignment 64 with loop headers 32;
   - function alignment 64 with loop headers 64;
   - LLVM defaults.

   The policy must enter the cache key. Pick the option with the narrowest bands that does
   not raise the suite-wide median. Then split `5818cee8`: land or reject the alignment half
   and the floor-result half separately.
4. **Re-screen the four deferred candidates** (`965d416c`, `99a4d071`, `52e6d074`,
   `0311796e`) on top of the chosen policy. Use the standard 5-round/1-warmup screen first,
   then the paired 15-round/3-warmup repeat.

**Acceptance.**
- The policy has a SPEC tag, a cache-key test and the full gate.
- Each re-screened candidate gets an explicit keep/reject with its band-adjusted evidence.

### WP-2 How much do value-semantics facts buy LLVM? — S, start now (decides WP-6)

**Goal.** Before any architecture work, measure what LLVM does with the facts mylang already
knows.

**Facts.**
- The translator makes every temporary an entry-block `alloca` slot. Pointer-width values
  are `i64`, and every memory access goes through `inttoptr`
  (`src/qbe_build_llvm_emit.zig:7-10, 370-399`).
- The only metadata is scoped `!alias.scope`/`!noalias` from IL comment markers (`# myl-obj`,
  `# myl-elem`, …; `src/qbe_build_llvm_il.zig:654-731`). There is no TBAA,
  `!invariant.load`, `!range`, `nonnull`, `dereferenceable`, `noalias` parameter,
  `llvm.assume` or `!llvm.loop`.
- No typed information reaches the translator except through IL text
  (`src/qbe_build_llvm_emit.zig` `Options`, :84-92).

**Steps.**
1. Dump the unoptimized `.ll` for the compute guest:
   `MYLANG_LLVM_DUMP=$DIR mylang build benchmarks/runtime/expanded/compute/main.my -o $OUT --release --cache-dir=$FRESH --link benchmarks/runtime/ports/native_clock.c`.
   A warm cache translates nothing, so use a fresh cache.
2. Hand-edit `main`'s module, changing **only** annotations and pointer forms:
   - add `!invariant.load` (or `llvm.invariant.start`) on the `values` header and storage
     loads, which never change after construction;
   - add `nonnull`/`dereferenceable` on that pointer;
   - replace `inttoptr(i64 slot)` with real `ptr` for the list base;
   - add `!range` on `kind`;
   - **as its own step**, add `!range` (or `llvm.assume`) on the element loads of `values`
     (0..1008) and on `phase` (0..16). The pilot (§3.1) shows this is the fact that unlocks
     vectorization, so measure it separately from the steps above.
3. Compile the hand-edited `.ll` with the same `-cc1`/LTO flags. Link it, and check that its
   checksums match the unedited build.
4. Inspect the assembly for `integer_math`, `call_direct`, `branch_predictable` and
   `list_scan`. Do the reloads and the bounds check leave the loop?
5. Time the edited guest against the unedited one in the same session (paired 15r/3w, both
   sizes, these four rows).

**Use of the result.** WP-2 is one of three inputs to the Wave 1 decision (§5). It
measures how far facts carried through today's translator get. For each step, report:
- the speed change;
- whether the in-loop bounds check, the reloads and the scalar loop are gone;
- whether LLVM vectorized.

**Deliverable.** An experiment note under `experiments/runtime-llvm-facts-20261004/`
containing the edited `.ll` diff, assembly extracts, checksums and the paired report.

### WP-3 Trap regions (L2) — M, spec now; Stages A–C after the Wave 1 decision

**Goal.** Implement L2, then use it to replace exact-fallback machinery with simpler, faster
code.

**Pilot finding (§3.1).** On `integer_math`, sticky overflow flags plus a hoisted bounds
check gave no gain. Range facts removed the checks under today's RELEASE-CHECKED-1 instead.
- Keep steps 1–2 (spec and mode plumbing) in Wave 1.
- Schedule Stages A–C after the Wave 1 decision. Prioritize loops whose data comes from
  input, where no range is known; that is where L2 is the only route to vectorization.

**Facts.**
- **Overflow checks** are emitted in `src/qbe_scalar.zig`:
  - `checkedAddSub` :200, `checkedMul` :263, `overflowTrap` :235;
  - cast :99, division :311;
  - also `src/qbe_constant_divisor.zig`.
- **List index checks** are in `src/qbe_managed.zig`:
  - `requireIndexBounds` :402, which is already skipped when `!self.checks` (the loop-version
    case);
  - `inlineIndexRead` :882, `inlineIndexWrite` :932;
  - fixed arrays: `src/qbe_aggregate.zig:225`.
- **Release builds without step or frame accounting already use a PC table for positions**
  (QBE-FRAMEMAP-1, `src/qbe_frame_map.zig`; `callSitePositions` in `src/qbe_il_passes.zig:201`).
  So relaxing precision mostly changes *which* pc and detail are reported. It does not remove
  any position stores.
- **Existing exact-order machinery that L2 makes optional:**
  - QBE-LOOP-FACTS-1/QBE-LOOP-VERSION-1 (`src/qbe_loop_facts.zig`, `src/qbe_loop_version.zig`);
  - LLVM-STICKY-REDUCTION-1 (`src/qbe_build_llvm_sticky.zig`). It already ORs overflow flags
    and checks them at loop exit, then restores frame cells and replays the original loop to
    find the exact trap. Under L2 the replay is unnecessary when the loop has no visible
    effect.

**Steps.**
1. **Spec.**
   - Add the TRAP-REGION-1 bullet (§2.2) to `SPEC.md`.
   - Add the release-build exception to each tag listed in §2.2.
   - Document it in `docs/statements.md` or the trap section of the docs, with an example
     whose Debug and ReleaseFast trap positions differ.
   - Add a guest test pair in `tests/lang/`:
     - The trap still fires in both modes.
     - Nothing printed before the region is lost.
     - Nothing is printed after the trap.
     - In Debug, the position is exact.
2. **Mode plumbing.** One compile-time switch, active only for ReleaseFast without
   `--max-steps`, decides whether region rules apply.
   - It must enter the object cache key.
   - Debug, libraries and `--max-steps` runs stay exact.
3. **Stage A, sticky replay removal (LLVM).**
   - When a loop region contains no visible effect, LLVM-STICKY-REDUCTION-1 traps directly at
     loop exit instead of restoring frame cells and replaying.
   - Keep the replay when the loop contains a visible effect.
   - Expect code-size and time reductions on `integer_math`, `float_math`, `list_scan` and
     `mutate_unique`.
4. **Stage B, hoisted bounds checks (both backends).**
   - For counted loops with affine indices into collections that are invariant in the region
     (no `mut` call, no append/pop on that collection), emit one preheader check of the
     extreme index against the length.
   - Delete the per-iteration check and keep the trap kind.
   - This generalizes QBE-LOOP-VERSION-1 without its exact fallback.
5. **Stage C, effect-free region merging.** In straight-line regions, overflow checks may
   share one cold block per region. Measure first; LLVM may already merge them once Stage A
   lands.
6. **Clean-up.** For each exact-order pass that Stage A/B makes redundant on a backend, delete
   its fallback path on that backend. Count the lines removed in the report.

**Termination guard.** Stage A/B must not move a check across a loop or call that is not
proven to terminate unless the condition is re-tested on each iteration. Add a test with a
`while True` loop that only exits by trapping.

**Acceptance.**
- Full gate, `test-qbe`, `test-qbe-build`, the Lox port and the 720/516 checks.
- A paired screen of the scalar, loop and list rows under L1, judged against WP-1 bands.
- Assembly extracts showing the per-iteration checks gone.

### WP-4 Remove the language memory budget (L3) — M, start now

**Goal.** Delete the guest-visible memory budget and allocation refusal, keep machine
protection, and then make allocation elision legal and used.

**Facts.**
- **SPEC tags:**
  - MEMORY-CEILING-1 (`R_MEMORY_BUDGET`, "memory budget exhausted", exit 1);
  - QBE-INLINE-ALLOC-1 (refusal at the per-object charge point);
  - QBE-DECODE-RANGE-1 (where a refused allocation is reported);
  - RC-LOCAL-LIST-1 (preserves "allocation totals, reuse epoch, trim accumulation and cache
    order" and allocation tickets).
- **Enforcement:**
  - `src/native_heap.c`: `alloc_object` :1129 with refusal at :1146–1150; also :1009,
    :1018 and :1103;
  - `src/native_rc_alloc.c`: `budget()` :137, `charge`/`discharge` :144/:148,
    `reserve()` :245;
  - mapping to the trap: `src/qbe_runtime_rc.c:21-22` and `src/qbe_runtime.c:87-91`;
  - parsing and defaults: `src/memory_budget.zig` (`MYLANG_MEMORY_LIMIT`, 4 GiB run,
    512 MiB test).
- **The narrow stack path (RC-LOCAL-LIST-1)** is `src/qbe_rc_local_list.zig` plus
  `myl_rc_storage_local_list` (`src/native_rc_alloc.c:545`).
  - At compile time it admits ≤16 int/bool elements, one constructor and no backedges.
  - At runtime it requires already-charged cache slots and settles real allocation tickets.
  - Most of that runtime admission exists to keep budget accounting exact.

**Steps.**
1. **Spec and docs.**
   - Retire MEMORY-CEILING-1's guest-visible half. Add a HOST-MEMORY-CEILING tag: the
     process `RLIMIT_AS` stays, and OS refusal gives one fixed fatal message and exit 1, at an
     unspecified point.
   - Update QBE-INLINE-ALLOC-1, QBE-DECODE-RANGE-1 and RC-LOCAL-LIST-1.
   - Update CLAUDE.md "Memory ceilings", `docs/tooling/runtime-budgets.md` and the `run`,
     `build` and `test` help text.
   - `--max-memory` and `MYLANG_MEMORY_LIMIT` keep working but only set `RLIMIT_AS`.
   - Decouple `--max-frames` from the memory figure.
2. **Runtime.**
   - Remove the budget charge, discharge and refusal paths.
   - Allocation failure from the OS goes to the single fatal path.
   - Keep the allocator's slab, cache and trim behaviour, which matters for speed.
   - Remove `heap.exhausted` and the `R_MEMORY_BUDGET` mapping.
3. **Compiler.**
   - Find every status check whose only failure is an allocation refusal: `ALLOCATION_REFUSED`
     returns in `src/native_rc*.c`, `src/qbe_runtime_rc.c` and the RC glue, plus the guest
     status tests after them.
   - Make those calls non-failing. Report the IL size change on the corpus.
4. **Tests.**
   - Allocation-failure and budget tests in `src/root_test.zig` and the `scripts/` drivers
     either become host-ceiling tests (the process exits 1 with the fixed message) or are
     deleted.
   - Remove or rewrite their SPEC bullets in the same change, so `// spec:` tags and SPEC.md
     stay matched for Guardian.
5. **Elision, after 1–4.**
   - Simplify RC-LOCAL-LIST-1's runtime admission now that tickets need not be exact.
   - Widen its compile-time admission: more element kinds, backedges with one allocation per
     iteration, records.
   - Then mark the allocator entry points for LLVM (`allocsize`, `noalias` returns and an
     `allockind` pair where the free path is a single call), so dead allocate/free pairs can
     be removed.
   - Measure `alloc_short`, `alloc_retained`, `record_construct`, `option_handle` and
     `string_split`.
6. **Borrowed `encode()`.** `str.encode()` always copies today: `src/qbe_bytes.zig:93`
   lowers to `myl_native_bytes_encode` (`src/native_bytes.c:481`). When the result is only
   read and does not escape, lower it to a view over `myl_native_text_storage`. This is the
   P6 item that was blocked on budget observability; it needs only a lifetime proof now.

**Acceptance.**
- Full gate, both RC sweeps and the Lox port.
- `mylang test <dir>` still cannot exhaust the machine: a runaway-allocation guest dies at
  the `RLIMIT_AS` ceiling with exit 1.
- Paired screens of the allocation and text rows under L1.

### WP-5 One-count RC — follow the existing plan; stop tuning hold paths meanwhile

**Goal.** Remove holds, the second RC count. They are a third of all count operations and
the largest single cost in `word_count` (37% in `scope_capture_dictionary`).

**Source of truth.** Use `docs/audits/gc-retirement-and-one-count-plan-2026-10-03.md` on
`claude/gc-retire-plan` (`66990f1e`) as written. Do not re-plan it here.
- **Part G** retires the tracing GC.
- **Part C** goes to one count:
  - C0: census and shadow modes;
  - C2: call pins become a PINNED bit;
  - C6: loans become static `+0` borrows;
  - C3–C5: the language decisions D1–D3;
  - C7–C8: drop `holds`, then the 16-byte header.

**Can start now (no language decision):**
- G0 docs;
- G1 model oracle and RC check mode;
- C0;
- after C0: C2 and C6, beside G2/G3 only, as that plan's §5 says.

**Language decisions:** D1–D4 were accepted on 2026-10-04.
- C1 still runs, to count and list the sites each rule changes.
- C3, C4, C5 and C8 now wait only on their technical prerequisites (G5, C7), per that plan's §5.

**Rule for the running campaign.** Do not start new optimizations whose main mechanism is in
hold, scope-capture or loan paths. That includes `scope_capture*` and `myl_rc_scope_*` in
`src/qbe_runtime_rc.c`, `qbe_rc_holds`, `qbe_rc_read_loans`, the loan roles in
`qbe_rc_values.zig`, and `rc_borrow_flow`. One-count rewrites those paths.

**Acceptance.** As in that plan's §4.4. In addition, re-run the `word_count`,
`dict_lookup*`, `dict_update*`, `set_dedup`, `lox_eval`, `tagged_stack` and
`mutate_shared` rows under L1 after C6 and after C7.

### WP-6 Give LLVM the facts — ON HOLD until the Wave 1 decision (§5)

**Hold.** Do not start 6a or 6b. They extend the comment-marker channel, which a direct
emitter (WP-8) would replace. 6c (typed collection operations) is useful on either path; it
may start after the decision, or earlier if the coordinator needs it for WP-5.

**Goal.** Make LLVM see what value semantics guarantees, so it can do the work that is
currently hand-built ahead of it. That pre-LLVM work today includes:

| File | Lines |
|---|---:|
| `src/qbe_loop_facts.zig` | 1280 |
| `src/qbe_build_llvm_sticky.zig` | 1372 |
| `src/qbe_loop_unswitch*.zig` (three files) | 411 |
| `src/qbe_loop_version.zig` | 323 |
| `src/qbe_rc_*_version.zig` | 685 |

**6a. Typed facts through the existing translator.** Do this first; it is the smallest change.
1. Extend the IL marker channel (`# myl-…` comments parsed in `src/qbe_build_llvm_il.zig`)
   with markers the emitter can prove:
   - `# myl-invariant %p`: the header or storage of a collection bound to a local that is
     never reassigned or passed `mut` inside the region. Value semantics means no alias can
     write it.
   - `# myl-nonnull %p`, plus `dereferenceable(N)` for headers.
   - `# myl-range %t lo hi`: generalize LLVM-FLOOR-RESULT-RANGE-1.
2. Translate these into `!invariant.load`/`llvm.invariant.start`, `nonnull`,
   `dereferenceable` and `!range`.
3. Emit real `ptr` values (not `i64` + `inttoptr`) for values marked as object bases, so
   that alias analysis and LICM work.
4. Keep every marker **checked**: an unproven marker is refused, as the existing marker
   parser refuses malformed ones.
5. Add a debug-build verifier mode that turns each invariant claim into an assert. Run the
   whole corpus under it.

**6b. Retire bespoke passes that LLVM now covers.** For each pass in the table above:
1. disable it under the new facts;
2. compare the benchmark rows and the assembly;
3. delete the pass if LLVM matches it.

Fewer passes means less to keep correct. QBE keeps the passes it still needs; this item is
about LLVM only.

**6c. Typed collection operations.** The integrated typed integer dictionary read
(`0d8a360c`, PY-DICT-4) gained 19.5%/21.1% on LLVM lookup. Apply the same approach (typed
probe entry points selected at compile time, generic fallback kept) to:
- `str` keys;
- sets of `int`/`str`;
- `list[T]` push/pop/index for plain variants (`tagged_stack`, `lox_eval`).

Prefer one generic implementation, specialized per key/value kind, over hand-written copies.
Coordinate with WP-5: these paths also carry hold/loan calls.

**6d. Superseded by WP-8**, the direct-emitter spike run in Wave 1.

**Acceptance per item.**
- Full gate (CLAUDE.md), `zig build test-qbe`, `zig build test-qbe-build` and `fmt-check`.
- The RC sweeps and the Lox port.
- The 720-qualification/516-holdout checks.
- A paired screen of every row the changed mechanism touches, judged against WP-1's layout
  bands.
- An assembly extract showing the intended instruction change.

### WP-7 Text iteration and short strings — M, start after WP-4 step 1

**Goal.** Remove the per-character cost in `csv_aggregate`, `json_transform`, `word_count`
and `string_split` without changing any surface syntax.

**Facts.**
- **`str` layout** (`src/native_text.h:19-24`): length in scalars, byte count, flags and
  hash, with the UTF-8 payload following.
  - Flags include ASCII, HASHED, VIEW, INDEXED, SAMPLED and STATIC_INDEX.
  - There is no inline or short-string form. Pieces under 9 octets are copied
    (`MYL_TEXT_VIEW_MIN`), not viewed.
- **`for ch in text`** lowers to one index read per iteration (`src/sema_loops.zig:309`):
  - `textAt` in `src/qbe_managed.zig:1296-1305` emits a bounds check and then
    `call $myl_native_text_at` (`src/native_text.c:741`).
  - **ASCII:** the call returns an entry from a per-heap 128-entry table and RC-acquires it.
  - **Non-ASCII:** the call runs `locate` (scalar index → byte offset) and allocates a fresh
    substring.
- **`str` equality** is already a direct `myl_native_text_equal` call
  (`src/qbe_managed.zig:1023-1027`).

**Steps.**
1. **Cursor lowering.**
   - Lower `for ch in s` (and `enumerate(s)`, comprehensions over `s`) to a forward UTF-8
     cursor: byte offset plus scalar count, decoding one scalar per step.
   - No `locate`, no per-step bounds call. The loop's existing iteration checks still apply.
   - The binding `ch` is still a `str`.
2. **Immortal one-scalar strings.**
   - Make the 128 ASCII scalar texts static image objects: immortal, so no RC acquire or
     release.
   - Build them once at image creation, not lazily per heap.
   - Comparisons such as `ch == "\""` against a literal can then compare the scalar value
     directly. Fall back to `myl_native_text_equal` when either side is not a one-scalar
     text.
3. **Measure, then decide on short strings.**
   - After steps 1–2, profile `word_count`, `csv_aggregate`, `string_split` and
     `json_transform`.
   - Only if allocation of short pieces is still hot, write a design note for an inline
     short-string form (≤ 15 octets in the value). That is an ABI change touching hashing,
     dictionary keys, views and the codecs; it does not start without a separate go-ahead.

**Acceptance.**
- Full gate.
- Unicode tests: mixed ASCII and non-ASCII, surrogate escapes, empty strings, and strings
  over 256 octets that take the INDEXED path.
- `tests/lang/standard_json.my` and `text_views.my`.
- Paired screens of the text rows and applications under L1.

### WP-8 Direct typed-bytecode → LLVM spike — Claude lane, Wave 1 (decision input)

**Owner and branch.**
- A Claude agent owns this lane, not a Codex lane.
- Branch `claude/llvm-direct-spike-20261004` from `claude/runtime-levers-plan` (the campaign's
  `ac72a905` plus these documents), in its own locked worktree.
- It is not integrated during Wave 1.
- The new path is off unless an environment flag enables it.

**Question.** Can mylang's compiler emit LLVM IR directly from typed bytecode, carrying the
facts value semantics proves? Does that reach the §3.1 hand-written levels automatically
while keeping mylang's semantics?

**Scope.**
- **Region shape.** A separate emitter path handles one region shape: a counted loop over an
  immutable `list[int]` (then `list[float]`) with a scalar body and a scalar reduction.
  Everything else in the function stays on today's path. Regions it cannot prove fall back
  unchanged.
- **Facts, derived from bytecode analysis and never hard-coded:**
  - the list is immutable after construction;
  - element ranges come from the constructing comprehension;
  - ranges of loop variables and invariants;
  - the trip count is at most the length.
- **What it emits:** real pointers with `noalias`/`readonly`; the narrowest proven integer
  width; and, in milestone B, explicit vector code for the reduction.
- **Checks:** none is emitted unless it is proven unnecessary. A region with an unproven
  check is refused in the spike.

**Milestones.**
- **A.** A single-kernel mylang program shaped like `integer_math` (same checksum) reaches at
  least the "element range" step of §3.1 automatically.
- **B.** Narrow width and an explicit vector reduction reach the u16 and hand-intrinsics
  steps.
- **C.** The same machinery runs on `float_math` and `list_scan` shapes. Report what the real
  compute benchmark's per-iteration `kind` dispatch requires.

**Deliverable.** `experiments/llvm-direct-spike-20261004/README.md` containing:
- the cycles/element ladder against Rust and today's mylang;
- IR and assembly extracts;
- what generalization needs: RC operations, trap traces (debug info or frame maps), the
  ABI with functions on the QBE path, and compile-time cost;
- a size estimate.

**Acceptance.**
- Identical checksums.
- Focused tests for the analysis, covering both admitted and refused regions.
- Guardian passes on every commit.
- Default compiler behaviour is unchanged.

### WP-9 Ideal ladder study — Claude lane, Wave 1 (decision input)

**Owner and branch.**
- A Claude agent owns this lane.
- Branch `claude/ideal-ladder-20261004` from `claude/runtime-levers-plan`, in its own locked
  worktree.
- Files only under `experiments/runtime-ideal-ladder-20261004/`.

**Cases.** Eight, in addition to `integer_math`:
- `float_math`, `branch_mixed`, `list_filter`, `dict_lookup`, `tagged_stack`,
  `string_split`;
- one component of `json_transform`;
- the dispatch loop of `lox_eval`.

**Method per case.**
1. Write a C ladder with `zig cc -O3` and native features, matching MyLang LLVM's policy.
2. Add one fact or representation choice per step. Every step must reproduce the
   benchmark checksum at both sizes.
3. Step 0 implements today's mylang semantics.
4. Make the last steps hand-vectorized or hand-structured where that applies.
5. Add one **holdout** step whose data comes from arguments or a file instead of
   in-program generation.

**Classify every fact** as one of:
- derivable by the compiler from today's source and rules;
- needing a language rule;
- needing the programmer to state it;
- true of the fixture only, which is not allowed.

**Measurement.**
- Seven interleaved rounds per version.
- Report cycles (`perf stat -e cpu_core/cycles/u`) and nanoseconds.
- Pin to CPU 10, never CPUs 2–3.
- The results are exploratory, not campaign evidence.

**Deliverable.** A README with:
- one ladder table per case;
- a cross-case table: fact → cases → gain → category → the WP or language feature it implies.

### WP-10 Implementation fixes from the ladder study — start now, independent of the decision

**Status.** These need no language rule, no new fact source and no backend decision. Each
moves gate rows directly. Run them as separate small lanes.

**Before and after each item:**
- Re-measure on the current integrated head (the study's reference binaries are B0, before
  PY-DICT-4).
- Show the mechanism moved, with counters or assembly, not only timings.

**10a. Inline checked float → integer conversion** (S). The highest value per line changed.
- **Today.** `int(float)` and the other f64 → integer conversions go through
  `myl_qbe_float_unary` (`src/qbe_runtime.c:764`), an out-of-line switch on an op code. They
  are emitted from `src/qbe.zig` (~3200, `.unary_float`) when
  `scalar_lower.floatUnary` declines.
- **Change.** Lower them inline on both backends: truncate (`cvttsd2si` on LLVM), then
  compare `a >= -2^63 && a < 2^63`. NaN fails the compare. The cold path raises the same
  `R_FLOAT_CONVERSION`.
- **Also check** `floor`, `ceil`, `trunc`, `abs`, negation and int → float, which go through
  the same helper.
- **Tests.** NaN, ±inf, ±2^63 boundaries, −0.0, and values just inside and outside the range.
  Trap kind and detail must be unchanged.
- **Rows.** `float_math` (study: 1.87×, reaching Zig ReleaseSafe parity), plus any row using
  `int(float)`.

**10b. Build unions and small records in place** (M).
- **Today.** A 16-byte union value is built in a stack temporary with two narrow stores, then
  copied with one 16-byte load. The QBE `blit` becomes `llvm.memmove`
  (`src/qbe_build_llvm_lower.zig` `onBlit`), which LLVM turns into a vector copy. The load
  cannot be forwarded from the two stores, so every step stalls.
- **Step 1 (smallest).** Lower constant-size blits of 32 bytes or less, at 8-byte alignment,
  as i64 load/store pairs. Do all loads first, which preserves overlap semantics. Compare
  `ld_blocks.store_forward` per step before and after.
- **Step 2.** Have the emitters construct unions and small records directly into their
  destination (list slot, local, field) with field-wise stores, so no temporary exists. Read
  them field-wise.
  - Look in `src/qbe_aggregate.zig`, the variant transfer code (`qbe_rc_native_variant.zig`,
    `native_variant_policy.zig`) and the list append/store paths.
  - Coordinate with WP-5 owners where these touch RC glue.
- **Tests.**
  - Aliasing: a union copied and then the source mutated.
  - Unions with managed payloads (the plain-variant path only applies to unmanaged ones).
  - Overlapping blits.
- **Rows and evidence.**
  - Study: `tagged_stack` 1.77×, `lox_eval` 3.04×; `record_construct` and `record_update` may
    also move.
  - Required counter: `cpu_core/ld_blocks.store_forward/u` per step should fall from ~1.8 to
    ~0 on `tagged_stack`.

**10c. Read-only dictionary probes** (S/M).
- **Today.** Every read writes the last-probe hint record (`recall` → `read_walk` → `locate` in
  `src/native_dictionary.c`), including reads in loops that never mutate the dictionary.
  PY-DICT-4's typed integer read still writes it.
- **Change.** Where the dictionary is not mutated in the region (no `mut` access and no write
  through the binding, which value semantics makes checkable), call a read-only probe entry
  point. It writes no hint, and the caller hoists the header fields.
- **Keep** the hint path for get-then-set sequences (PY-DICT-4).
- **Rows.** Study: `dict_lookup` 1.78×, sparse keys 1.72×; `dict_lookup_str` and
  `word_count` reads are likely to move too.
- **Coordinate with WP-5.** This must not touch hold/scope/loan paths. If a probe takes a
  hold today, leave that to one-count.

**10d. Modular strength reduction** (M).
- **Change.** Replace `%` by a positive constant when a range is known locally:
  - `x % M` with `x ∈ [0, 2M)` becomes a conditional subtract;
  - an affine `(a + b·j) % m` in a counted loop becomes an induction variable with
    compare-and-reset;
  - a cursor wrap `(c + 1) % n` becomes compare-and-reset.
- **Where.** `src/qbe_scalar.zig`, `src/qbe_constant_divisor.zig`, and the loop facts
  (`src/qbe_loop_facts.zig`; LLVM-FLOOR-RESULT-RANGE-1 already carries one such fact).
  Derive ranges locally, including loop-carried `x % M ∈ [0, M)`. This works at the bytecode
  level, so it helps under either backend route.
- **Tests.** Negative operands (Python floor semantics), `M` = 1, values exactly at the
  bound, and loops with zero trips.
- **Rows.** Study: `tagged_stack` 1.46×, the `dict_lookup` query key 1.81×, `list_filter`
  1.11×.

**10e. Follow-up, design first: dictionary table layout** (L).
- **Proposal.** Store `{key, value}` (or key/value arrays) in the slots, with load ≤ ½, a
  stronger multiplicative hash and a branch-free 4-slot bucket probe. Keep the entry list
  for insertion order.
- **Before starting.** Write a short design note with sparse-key, string-key and mixed-key
  measurements. The study's dense-key gains are fixture-shaped; the sparse table (3.2–5.3×)
  is the evidence to use.
- **Not in scope:** the hash-luck result.

**Not in WP-10, because they belong elsewhere:**
- RC/ready-call protocol on unique locals (WP-5, WP-6c);
- non-escaping temporaries and borrowed `encode()` (WP-4 steps 5–6);
- range → narrow emission and runtime range guards (the Wave 1 decision: WP-6a or the
  WP-8 route);
- threaded dispatch and typed JSON decode (later, after evidence on real programs).

**Acceptance for every item.**
- A SPEC tag and focused tests.
- The full gate (CLAUDE.md), `test-qbe` and `test-qbe-build`.
- The Lox port.
- The 720/516 checks.
- A paired screen of the named rows under L1, judged against WP-1's layout bands.
- The counter or assembly evidence named above.

## 5. Order, lanes and file ownership

```
Wave 1 (now):     WP-0 | WP-1 | WP-2 | WP-4 steps 1-4 | WP-3 steps 1-2 | one-count G0/G1/C0
                  + Claude lanes: WP-8 spike | WP-9 ladder study (done)
                  + WP-10a/10b as lanes free up, then 10c/10d (independent of the decision)
Decision:         markers (WP-6a/6b) or direct emitter (from WP-8), chosen by the user
Wave 2:           WP-4 steps 5-6 | WP-7 | one-count C2/C6 | the chosen LLVM-facts route
                  | WP-3 Stages A/B (data-from-input loops first)
Wave 3:           WP-6c | WP-3 clean-up | one-count C3-C8 (after G5)
Each wave ends:   integrated full 80-row screen under L1, then the independent confirmation
```

**Wave 1 decision point.** This happens before any Wave 2 lane starts.

The inputs:
- **WP-2:** how far facts carried through today's translator get.
- **WP-8:** whether a direct emitter reaches the hand-written levels automatically, and what
  generalizing it costs.
- **WP-9:** whether the same levers hold across eight more cases, and which facts need
  language features.

The choice, which the user makes:
- **(a) Continue WP-6a/6b** on the marker channel.
- **(b) Build a direct typed-bytecode → LLVM emitter.**
  - It goes function by function, falling back to today's path, and is LLVM-only per L4.
  - It replaces WP-6a/6b and, over time, the hand-built pre-LLVM loop passes.
  - QBE stays for Debug builds and as a correctness reference.

**One owner per shared file per wave.** Other lanes send interface requests or follow-up
patches to that owner.

| Area | Files | Owner |
|---|---|---|
| LLVM translator and build flags | `src/qbe_build_llvm_*.zig`, `src/qbe_build.zig` link paths | Wave 1: WP-1 (flags), then WP-10b step 1 (`onBlit`). Wave 2: the route chosen at the decision |
| Scalar and index checks | `src/qbe_scalar.zig`, `src/qbe_managed.zig` check emitters, `src/qbe_loop_*.zig` | Wave 1: WP-10a, then WP-10d (WP-3 is spec-only). Wave 2: WP-3 Stages A/B after WP-10d |
| Dictionary runtime | `src/native_dictionary.[ch]`, `src/qbe_rc_dictionary_*.zig` | WP-10c, then 10e; coordinate with WP-6c and WP-5 |
| Allocator and RC runtime | `src/native_rc_alloc.c`, `src/native_heap.c`, `src/qbe_runtime_rc.c`, `src/qbe_rc_local_list.zig` | WP-4, then one-count |
| Text runtime and lowering | `src/native_text.[ch]`, `src/qbe_managed.zig` text paths, `src/sema_loops.zig` | WP-7 |
| Hold, scope and loan paths | `qbe_rc_holds`, `qbe_rc_read_loans`, `rc_borrow_flow`, scope capture in `src/qbe_runtime_rc.c` | one-count only |

**Coordination with the running campaign.**
- The campaign coordinator owns `RUNTIME_110_GOAL.md`, `perf/runtime-parity-20261003` and
  timing CPU 2.
- New lanes branch from the coordinator's latest integrated head. They return commits plus
  an evidence directory, and the coordinator integrates.
- Small-batch tuning on rows that no WP here touches can continue. Tuning of hold, loan or
  scope paths stops (WP-5).

## 6. Rules for every lane

- **Worktree.** Use one worktree per lane under `/home/epentland/ai/canopy/mylang-worktrees/`.
  - Check `git worktree list` first.
  - Claim it with `git worktree lock --reason "<lane> <date>"` before use.
  - Never reuse a locked tree.
- **Builds.**
  - Build through `scripts/build-slot.sh` with a private Zig cache, a disk-backed `TMPDIR`
    and `-j2`.
  - Run at most four build-heavy lanes at once.
  - Use a Debug compiler for gates. Use a ReleaseFast compiler
    (`zig build -Doptimize=ReleaseFast --prefix …`) for any timing used as evidence.
- **Gates (CLAUDE.md).** Before handing back, run:
  - `zig build test --summary all`
  - `zig build test-qbe --summary all`
  - `zig build test-qbe-build --summary all`
  - `zig build fmt-check`
- **Guardian.**
  - Every behavioural change needs a `// spec: TAG` test and a matching `- [TAG]` SPEC.md
    bullet.
  - Every `pub` declaration needs a `///` comment.
  - Structs have at most 7 fields and functions at most 6 parameters.
  - Test bodies need straight-line assertions.
- **Language behaviour tests.** These are mylang tests under `tests/lang/`, run by
  `mylang test`. Diagnostics, traps and host behaviour are Zig tests in `src/root_test.zig`
  or `test/integration.zig`.
- **Timing.**
  - Use only the campaign runner (`benchmarks/runtime/expanded/run.py --only CASE …`). It
    takes the shared timing lock itself; never wrap it in another lock.
  - Screen with 5 rounds/1 warmup. Confirm with 15 rounds/3 warmups in two independent
    sessions.
  - Judge regressions against the WP-1 layout bands. Attribute anything outside a band with
    instruction counts or assembly before rejecting it.
- **Never edit benchmark ports, inputs, oracles or competitor sources.**
- **QBE must stay correct.** Report QBE before/after, but it is not gated.
- **Hand-back report.** It contains:
  - the hypothesis;
  - the files changed and the SPEC tags;
  - the tests added;
  - the gate output;
  - assembly or IR evidence for the intended change;
  - paired timings with raw-report paths;
  - regressions and the decision taken on each;
  - what remains open.

## 7. Not in this plan

- Changing Python floor `//` and `%` semantics. Range facts (LLVM-FLOOR-RESULT-RANGE-1 and
  WP-6a `!range`) remove the sign fixup where operands are proven non-negative.
- Wrapping integer arithmetic, or an `--unchecked` mode.
- Removing `--max-frames`, `--max-steps`, `--timeout` or error-return traces.
- QBE parity, beyond keeping QBE correct and recording regressions.
