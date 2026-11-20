# EDA port: status at the pause, 23 October 2026

Paused at the user's request on 23 October, around 14:00 UTC, to resume in a few days.
- **The plan:** `docs/audits/eda-port-roadmap-2026-10-22.md`.
- **Live progress table:** the Claude Doc "EDA port roadmap" (https://claude.ai/artifact/EafeX6hW7tEEet1asJiDtW).

This page says where everything stands and what to do next.

## Where we are

- **Main is `f98d0b539`.**
- **Phases 1, 2 and 3 are done and their gates passed:** phase 1 on 22 October, phase 2 on 22 October, phase 3 on 23 October at 08:44.
- **Phase 4 is in progress,** started 23 October at 11:13. Its gate: G2's 34/34 goldens, and requirements R-1 to R-5 holding.
- **29 of 39 roadmap items are done.**

### Landed on 23 October
| item | main commit | what it gave |
|---|---|---|
| C1, C3 | a37f8d578 | `match mut` in-place payload updates; borrowing several fields of one record at once |
| E1 (E1a/b/c) | 03e60dfff, 0c1d79ea6 | task groups, `parallel.map` with lent arguments, `--threads`, `docs/concurrency.md`, a TSan step |
| K4 | 9039f11ba | four new parity kernels (JSON, union-find, hashing, hash-map churn) against Zig and Rust |
| K4F | 821a53dfe, ee14850a0 | dict iteration after deletes is O(n log n) (it was quadratic); a `check` crash fixed; typed binary reads `bytes.read_*` |
| CTI | b20fa910f | compile-time interfaces measured and **not** adopted; records of functions documented as the interface pattern; two checker fixes |
| CAPFN | f98d0b539 | function types that take a capability can be stored and passed (it unblocked G2's evaluator) |
| E2 | eda-bench `kernels/e2` 2f468fa | K3 and K1 on 1–8 threads, byte-identical, within 1.25x of Zig at the same thread count |

### Decisions the user took on 23 October
- **R-2** gates kernel *wall time* within 1.25x of Zig. Instruction counts are a diagnostic.
- **R-3** gates identical output at 1, 2, 4 and 8 threads, and Selka within 1.25x of an equivalent Zig parallel program at the same thread count. K1 is parallel at snapshot level, because netlisp routes nets one after another.
- **netlisp's server is in scope,** so E3 (shared mutable state across threads) is planned: designed after G2, landed before G3 reaches the server.
- **Compile-time interfaces:** stopped after measuring (P0). Records of functions are the pattern.
- **DL** (faster LLVM debug code generation) runs after F2b. A custom debug backend is decided later, from DL's report and G3's cold-build numbers. Release stays on LLVM.

## What is in flight (stopped cleanly at the pause, nothing landed)

| lane | worktree, branch | head at the pause | state |
|---|---|---|---|
| G2b: stage-2 foundation, checks and `main` | `eda-bench-wt/g2`, `g2/lane1-foundation` | d58e7f0 | foundation complete: Zig-order hash map, pdq sort, env, forms, infra_fs, and source transactions as one `with` per mutation. `component_classification` (10/10 tests) and `req_checks` (3/3) are done, with the dispatcher and the three requirement checkers. **Left: 58 holes in 11 files, plus about 250 production functions the skeleton omitted entirely,** the biggest in `pll_loop`, `frequency_plan`, `review` and `bom_resolve`. That's more than the skeleton suggested, so lane 1 is G2's long pole. Next, per its handoff: `eval_power_budget` (lane 2 needs it), `review.slugify` reusing `support_slug`, merging `g2/lane3-render`, the `erc` tests, then `main` |
| G2c: stage-2 evaluator | `eda-bench-wt/g2-eval`, `g2/lane2-evaluator` | d8cb321 | most evaluator files ported, and the F-G2c-18 ruling is applied; `materialize_block`, the form dispatcher and `evaluator_emit_child` are left; thermal 11/18 and net envelopes 19/19 pass in a scratch copy (the failures are stubbed lane-1 helpers) |
| G2d: stage-2 rendering | `eda-bench-wt/g2-render`, `g2/lane3-render` | 7083816 | every module type-checks; 16 test files pass; render_html 23/28 in a scratch copy; schematic_scene, review_html and render_html tests wait on lane 1; one BOM test needs a step-budget decision |
| F2b: R-5 edit loop at 400k lines | `mylang-e0`, `f2b/edit-loop` | 92bf1dd71 | three fixes committed: the stage-store LRU cache, the large-module check made linear (72k lines 2.86 s to 0.23 s), and partial interface cut-off (6,753 of 15,198 lowerings reused). The debug build after a leaf edit went from 19.1 s to about 14 s (loaded host). **Not done:** the complete verification hasn't passed on the final tree (one run was disturbed by an edit), and the quiet R-5 table is unrun (the driver `.tmp/f2b/r5_window.py` is written). The next term is about 4.9 s of front-end time after `check`; the suspect is `checkAllocationContracts`. R-5 isn't met yet |

Open lane questions at the pause:
- **The commit trailer:** about 24 G2 commits from Sonnet helper agents carry a Sonnet trailer instead of Haiku. Don't rewrite shared history; just note it.
- **How `main` builds the evaluator** (F-G2b-23): settled by the F-G2c-18 ruling, as a literal with no `err` stream. Lane 1 applies it in `main`.
- **Lane 2's ownership errors:** lane 1 found them in `eval_net_envelopes`, `eval_net_envelope_rules` and `eval_authored_rules`. G2c fixes them on resume.
- **Lane 3's BOM test:** it needs a step-budget decision.
- **Rebalancing:** the omitted-function count makes lane 1 the long pole. On resume, consider splitting lane 1's remaining files (`pll_loop`, `frequency_plan`, `review`, `bom_resolve`, …) across two lanes.

All G2 lanes use the compiler pin `~/ai/.home-cache/mylang-pins/capfn-b6bf28dff-rf`. It's code-identical to main `f98d0b539`. Lane notes live in `stage2/mylang/NOTES-G2.md` and `FRICTION.md` on each G2 branch, and evidence in `~/ai/canopy/mylang-evidence-archive/experiments/eda-roadmap-20261022/`.

## What remains

### To close phase 4
1. **Finish G2's bodies.**
   - **G2b:** the checks, the omitted helpers in power_budget, check_grammar, builtins, power_sequencing, stackup_presets, project_boards, attrs, forms and value_kind, then `main`'s design path. `main` builds the evaluator as a literal and prints its warnings list.
   - **G2c:** `materialize_block`, the dispatcher, `evaluator_emit_child`, and the ruling on F-G2c-18 (no `err: Stream` in the evaluator).
   - **G2d:** its blocked tests once lane 1 lands.
   - Each lane merges the others' branches as they need them.
2. **G2e, integration:**
   - merge the three branches;
   - 34/34 goldens (`harness/bench.py equiv mylang --stage 2`, first target `blinky-breakout`);
   - at most 1.5x Zig instructions on the stage benchmark;
   - measure the evaluator hooks' indirect-call cost;
   - write the Selka idiom guide (`PORTING-MYLANG.md` is outdated).
3. **F2b:**
   - instrument the front end's unnamed ~4.2 s;
   - stable-identity lowering keys, or a report on why not;
   - a quiet R-5 table comparing base main with its head (check ≤ 2 s, debug build after an edit ≤ 5 s).
   Then land it.
4. **DL,** after F2b.
5. **Decisions from G2's evidence:**
   - D1, D2, D3 (allocation; D3, scoped regions, is the user's decision if allocation stays above about 20% of a profile);
   - C4 (functions that return a mutable place). Several G2 workarounds are logged as C4 evidence;
   - C5 only follows D3.

### After phase 4
- **G3:** the full netlisp port (669k Zig lines), in slices, CLI tools first and the server last.
- **E3:** shared mutable state for the server.
- **H:** self-hosting, staged, after G2's language freeze.

## Waiting on the user
**A small language lane for the port's friction.** All six fixes are additive. Each one currently forces a workaround in G2:
1. pass a `with`-bound resource (an open file, a directory lock) as a `mut` argument;
2. return a record that holds capabilities from a function;
3. a `Stream` that tests can construct;
4. `sets.add` on a `mut` record field;
5. move a field out of a `mut` parameter, which costs one copy per call today;
6. a monotonic reading and `sleep` on `Clock`, which the server needs.

## Smaller follow-ups (logged, not scheduled)
- **Loop code generation:** `range`'s overflow guard, and loop-invariant bounds checks that LLVM doesn't hoist. Typed reads stay at 3.1x Zig's instructions because of it.
- **Checker messages:** R7's store advice names two refused forms. Checking a generic template on its own misses storing a borrowed value of an unconstrained type (the error comes at specialization).
- **Parallel API consistency:** `parallel.map` refuses a `Filesystem` trailing argument, and a fallible function with trailing arguments. A list slice given to a group task is copied while `parallel.map` refuses it. A borrowed call result given to a task needs `copy(...)`.
- **Small checker issues:** internal errors with an empty diagnostic sink still exit silently (add a guard); `ord()` is refused in generic bodies.
- **Smaller language gaps from G2:** `ZigStrMap` keys trap on non-UTF-8 text; `Unit()` isn't a value; a union with plain variants is refused; records with defaults must be built with every field; one BOM test hits the default step budget.
- **Benchmarks:** the `dict_count` threshold is stale and needs a rebaseline.
- **Toolchain:** Zig's SHA-NI SHA-256 path is about 10x slower on this machine. That's an upstream issue, and reporting it is the user's call.

## Update: second pause, 23 October around 16:30 UTC
The agents ran again from 14:30 to 16:30. **Main is now `59b44277a`.** It gained:
- F2b's three edit-loop fixes (`65f2dcd5d`);
- LANG1 item 1, typed holes (`d1e262f48`): ownership errors are no longer hidden, and debug and test builds turn a hole into a runtime trap;
- LANG1 items 2(a), 2(d), 4 and 5 (`59b44277a`): `with`-bound resources pass as `mut`, empty collection field defaults, a capturing test `Stream`, and `Clock` monotonic and `sleep`.

**G2, all on the pin `lang1-b2cda5a84-rf`, with tests running in the real tree:**
- **Lane 1 (G2b):**
  - ERC 85/85, power budget 16/16, check grammar 10/10, and `bom_resolve`;
  - `support_ohms` and the NaN fix in `near`;
  - next: `main`'s design path (evaluator literal, warnings drain, sidecar origins).
- **Lane 2 (G2c):**
  - connect, thermal and net envelopes all pass, and design block 110/111 (the last waits on `frequency_plan`);
  - next: `refdes_stability` (moved from lane 1), then its 191 unported test stubs, and adopting record defaults.
- **Lane 3 (G2d):**
  - review, coverage, review_html, review_profiles, schematic_scene and render_html all pass, and `pll_loop` 8/16 (a test step limit is set in `mylang.json`);
  - `frequency_plan` is in progress; next: `placement_outline` and `paths` (moved from lane 1);
  - plus a shared `support_math` porting Zig's `std.math`.

**LANG1, left on its branch:**
- item 3, `take(mut place)` / `exchange(mut place, value)`. Its own.zig rule is approved in principle, and the diff comes for review first;
- then 2(c), `sets.discard` on a field, built on `take`;
- 2(b), returning records that hold capabilities;
- 2(e), `grid[i][j] = v`. It needs an own.zig change, with a design note first.

**New findings:** Selka's `math` lacks `log10`, `exp`, `atan2` and float `pow` (the port uses `support_math`). The commit-trailer rule is now that a trailer names the model that actually wrote the commit. G2c's earlier rewrite of 7 Sonnet commits to a Haiku trailer is an attribution correction still to make.

**To resume:** restart the four lanes from their "Paused 23 Oct (2)" notes, with the same briefs. LANG1's item 3 (`take`/`exchange`) is done on its branch (`bfc8822a2`, head `6ce1a854e`, verification passed) with no own.zig change needed, but it's not landed yet. Land items 3 onward from that branch, then do 2(c), 2(b) and 2(e).

**Lane heads at the pause, every tree clean, nothing pushed:**
- G2b `07ee18c` (`g2/lane1-foundation`): lane 2 merged, so `erc_test` is 85/85, and `main` is ported (`d8974c8..d9458a2`). The golden run is blocked by F-G2b-34, which needs an owned capability.
- G2c `8a839ec`: record defaults adopted (F-G2c-14), and `refdes_stability` ported. 165 test stubs remain.
- G2d `f4e6c7c`: `frequency_plan` 12/12 and `pll_loop` 16/16. Next are `placement_outline` and `paths`.
- LANG1 `6ce1a854e`.

## Resume plan (decided by the user on 23 October)
**First, one language lane, before the G2 lanes restart.** It goes in this order, each item with tests, docs, the complete verification and the borrowed-returns matrix:
1. **Typed holes (tooling defects):**
   - (a) check every finished function even when others still have holes, treating a hole as a call that matches its declared signature, so ownership errors no longer hide behind holes;
   - (b) debug builds and `mylang test` compile a hole to a runtime trap (like Rust's `todo!()`), so finished modules can be tested before the whole program is hole-free. Release builds still refuse holes.
2. **Strictness fixes:**
   - pass a `with`-bound resource as a `mut` argument (an exclusive borrow, as the docs already say);
   - return a record that holds capabilities, as a move;
   - `sets.add` (and similar collection updates) on a set in a `mut` record field;
   - a record's field defaults should let construction omit those fields. Confirm this is a gap, not a design choice, first.
3. **`take` and `replace` for fields** (like Rust's `mem::take` / `mem::replace`): move a field out of a `mut` parameter while leaving an empty or given value behind, so the copy-and-clear workaround goes away.
4. **A test `Stream`** that captures output, beside `filesystem.memory`, `random.seeded_entropy` and the rest.
5. **`Clock`:** a monotonic reading and `sleep`.

All of these are additive: no existing program changes meaning, so R-6 holds. **Then** the G2 lanes switch to the new pin and remove their workarounds. Every site is listed in `stage2/mylang/FRICTION.md`. After that, G2 continues as below.

## How to resume
1. Read this page and the Claude Doc. Start the language lane above first.
2. Check that the four lanes' handoff notes exist and their worktrees are clean: `git -C <worktree> status`.
3. Restart the lanes from their notes, with the same briefs (`~/ai/canopy/mylang-evidence-archive/experiments/eda-roadmap-20261022/briefs/`): `BRIEF-G2BODY.md` for G2b, G2c and G2d, and `BRIEF-F2B.md` for F2b.
4. Recreate the 2-hourly roadmap timing check if it's still wanted. It was a session-only cron job and was cancelled at the pause.
5. Decide on the language-friction lane.
