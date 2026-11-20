# Compiler dev loop, part 2: the next cuts (plan, 2026-10-29)

**For:** an implementing agent working on the mylang (Selka) compiler in `~/ai/canopy/mylang`.
**Written by:** Claude, after part 1 (`docs/audits/compiler-dev-loop-plan-2026-10-28.md`) landed on 28–29 October.
**Goal:** a typical compiler edit check under 30 s on a quiet machine, and no edit check over 60 s. The complete gate
stays the landing check.

## 1. Where the loop stands (main 25e2388a3, quiet machine, load 3–16)

An agent changing the compiler runs the **edit check** after each edit (`python3 scripts/edit_check.py`; see
`CLAUDE.md` "Fast loops"). It rebuilds, selects the tests the edit can reach from a per-test coverage map, runs them,
and runs the guest suite. Before landing, the agent runs the **complete gate**
(`python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`).

Measured on 29 October with `experiments/compiler-dev-loop-20261028/loop_measure.sh`:

| Edit | Selected Zig tests | Build | Run (selected tests + guests, in parallel) | Total |
| --- | --- | --- | --- | --- |
| none | 0 | 15–28 s | 15–24 s (guests only) | 26–45 s |
| one function, `src/core/stage_compression.zig` | 935 of 5,311 | 15 s | 48 s | 64 s |
| back end, `src/core/emit_llvm.zig` | 1,939 | 17 s | 55 s | 73 s |
| front end, `src/sema.zig` | 3,691 (70%) | 24 s | 69 s | 95 s |
| complete gate after the back-end edit | everything (30 actions run, 17 reused) | — | — | 175 s |

In the mutant study (`experiments/edit-check-20261025/REPORT.md`) the median selection was 2.4% of the tests. So the
typical edit is a leaf edit that selects few tests, and it still pays the two fixed costs every time:
- **The build:** 15–28 s for the compiler, the three Zig test binaries and the impact tool, in Debug through `zig build`.
- **The guest suite:** 15–24 s. `mylang test tests/lang` runs on every edit check. With nothing changed it still
  reruns 196 of 2,213 tests (2,017 hit their receipts) and checks every test file to compute its keys.

Together these are 30–50 s of every edit check, whatever the edit, and they are the biggest lever.

## 2. Packages, ranked by expected saving per edit check

| # | Package | Expected saving (estimate) | Estimate |
| --- | --- | --- | --- |
| E1 | Incremental compiler build in the edit check | 10–20 s on every edit check | 4–8 h |
| E2 | Select guest tests instead of running the whole guest suite | 10–20 s on most edits | 8–16 h |
| E3 | Balance and order the selected tests by recorded duration | 20–30% of the run on broad edits (10–20 s) | 3–6 h |
| E4 | Finer impact rules for non-function declarations, new files and build inputs | depends on how often those edits occur; measure first | 8–14 h |
| E5 | Refresh the coverage map automatically after each landing | prevents stale-map selections from growing | 2–4 h |
| E6 | Shorten the complete gate (core critical path, test-runner keys) | 175 s → roughly 120–140 s, once per landing | 6–12 h |

Order: E1 and E2 first (they cut every edit check). E3 and E5 are small and independent. E4 and E6 come after, each
starting with its measurement.

### E1. Incremental compiler build

- **Why:** every edit check rebuilds the Debug compiler, three test binaries and the impact tool. That's 15–28 s, most
  of a leaf edit's time.
- **Measure first:** time `scripts/build-slot.sh build zig build` and the edit check's build step
  (`zig build edit-check-binaries edit-check-impact`) after a one-function edit. Then do the same with Zig's incremental
  compilation:
  - the repo's supported watcher, `scripts/build-slot.sh build zig build --watch -fincremental`, which updates
    `zig-out/bin/mylang` after each build summary (`CLAUDE.md`, "Fast loops");
  - and `-fincremental` without `--watch`, if the pinned Zig accepts it.
  Record which artifacts each mode updates. The three test binaries matter as much as the compiler.
- **Work:** make the edit check use the fastest correct path. That's either a persistent incremental build it starts
  and reuses, so it waits for the build summary of the current tree instead of starting a build, or plain
  `-fincremental`. It must detect a stale or failed incremental result and fall back to a normal build. A watcher must
  not hold a build slot while idle in a way that blocks gates. `CLAUDE.md` says the watch loop holds its slot, so
  either release it between builds or document the trade-off.
- **Exit:** the build step at most 8 s on a one-function edit, with binaries identical in behaviour to a normal build:
  the same selected tests pass, and a deliberately broken edit fails the same way. Covered by a test of the fallback.

### E2. Guest test selection

- **Why:** `mylang test tests/lang` costs 15–24 s on every edit check, including when no compiler code it reaches has
  changed.
- **Measure first:**
  - Why 196 of 2,213 guest tests never hit their receipts with nothing changed: list them and their reasons from
    `mylang test --json` (`cache.reason`).
  - How long the front-end key computation over all test files takes on its own.
- **Work:**
  1. Make the always-rerun tests cacheable where it is sound. If a test is uncacheable by design (it reads the clock, the
     environment or files outside its inputs), say so and keep it.
  2. Extend the coverage map to guest tests. With the coverage-variant compiler (`build_coverage.zig`), record per guest
     test file the compiler functions its `mylang test` run executes, in the same map format
     (`scripts/edit_check_collect.py`, `scripts/edit_check_map.py`).
  3. The impact tool (`tools/impact.zig`) then selects guest test files like Zig tests, and the edit check runs only
     those (`mylang test FILE…`). A change to `src/stdlib` or the runtime keeps today's rule: select the guests that
     load or link it.
- **Exit:** a leaf compiler edit that reaches no guest-path code runs no guest tests. A front-end edit still runs the
  guests it reaches. The mutant check of EC4 (`experiments/edit-check-20261025/ec4_*`), repeated for guest-reaching
  mutants, shows zero misses on at least 30 killed mutants.

### E3. Duration-balanced chunks

- **Why:** the edit check splits each binary's selection round-robin into chunks (`scripts/edit_check.py`, `chunks`).
  A few slow tests (for example the 9 s `driver_cache_test` cold build) land unevenly, so the run ends with the slowest
  chunk.
- **Work:**
  - Weight tests by their recorded durations: the per-test medians in `tests/shard-plans/<root>.json` and Guardian's
    `test wall` / `SLOW` lines.
  - Pack the chunks longest-first, and start the longest chunks first, before the guest suite.
- **Exit:** on the stage and back-end edits of §1, the run step at least 20% shorter, with the same tests run.

### E4. Finer impact rules

- **Why:** the impact tool's conservative rules widen selections.
  - A non-function declaration (type, `const`, global) impacts its whole file.
  - A new Zig file under `src/` or `test/` selects everything.
  - Any build input (`build.zig`, `build_test_inputs.zig`, `build_coverage.zig`, `build.zig.zon`, `.zigversion`)
    selects everything.
- **Measure first:** over the last 100 commits on main that touch `src/`, count how many hit each rule, and the selection
  size each rule produced. Use `--select-only`, against a map at each commit's parent where available, or the newest
  map with the staleness noted. Do only the rules that matter.
- **Possible work:**
  - A type or `const` change selects the tests that executed a function using it (reverse references from the map's
    functions, or Zig's own analysis), not the whole file.
  - A new file selects the tests of the functions that import it.
  - `build.zig` changes are classified by which steps or options they touch.
- **Exit:** recall unchanged: zero misses on the mutant set plus a new set of mutants on declarations. The selection
  size for each refined rule is reported before and after.

### E5. Automatic map refresh

- **Why:** the edit check diffs the working tree against the map's commit, so every change landed since the map was
  built is impacted. After big landings the map selects nearly everything until someone runs
  `python3 scripts/edit_check_map.py`. On a quiet machine that takes 4–5 minutes; under load it took 2 h 20 min.
- **Work:** refresh the map after each landing on main in the background, through build-slot admission, at low
  priority. It must yield to gates and timing windows: a queued timing request stops all admissions while it waits for
  running jobs, so the refresh must not sit in a slot for hours. A newer landing cancels a running refresh. Keep the
  last good map until the new one passes its "no failed tests" check. Add a one-line note to the edit check's output
  when the map is more than N commits behind.
- **Exit:** after a landing, a fresh map exists within 15 minutes on a quiet machine, with no gate delayed by it
  (record admission waits).

### E6. Shorter complete gate

- **Why:** the gate ends with the core Zig test shards (`src/core/root_test.zig`), and its total CPU is about 2,000 s.
  Two measured causes remain:
  - The in-process, compile-heavy core tests go cold on every compiler edit (8–32 s each; list in
    `experiments/compiler-dev-loop-20261028/DECISIONS.md`, lane T).
  - The test runner's own records stay keyed by the whole compiler identity: `test-graph-*`, `core-test-keys-v1`,
    `core-test-function-facts-v2` and `llvm-test` (`experiments/compiler-dev-loop-20261028/V/DECISIONS.md` §16–§18).
- **Work:**
  1. A quiet-machine shard balance check. Regenerate `tests/shard-plans/*.json` with
     `tests/shard-plans/regenerate.py` from three passing cohorts, because the current plans came from heavily loaded
     runs.
  2. Split the longest core tests.
  3. Key the test-runner records soundly by the runner identity (`src/build_identity_rules.zig`, `isRunnerSource`),
     following the M1 rules in `V/DECISIONS.md`.
- **Exit:** a quiet-machine compiler-edit gate at or under 140 s, three passing runs, and the same tests run.

## 3. How to measure

- **The inner loop:** `experiments/compiler-dev-loop-20261028/loop_measure.sh WORKTREE OUT`.
  - Run it on a clean worktree of main with a fresh coverage map.
  - It times the edit check on a stage, back-end and front-end edit, then one complete gate.
  - Edits come from `m0_edit.py`; tags must be at most nine characters.
- **Per-suite CPU of a gate:** lane T's tools in the same directory (`m0_run.py`, `m0_suites.py`, `m0_analyze.py`,
  `m0_gate.sh`). `m0_gate.sh` has a worktree path near its top that you must point at yours.
- **Timed gates:** use the coordinator's own window: `verify_cache.py --profile complete --timing-window-seconds 900`,
  run directly. Never run `verify_cache.py` inside `scripts/build-slot.sh timing`: it deadlocks admission machine-wide.
- **Record load** (`/proc/loadavg`) with every number. CPU seconds inflate under contention on this 20-thread hybrid
  machine, so compare runs at similar load and prefer timed windows for wall-clock claims.

## 4. Rules for the implementing agent

- **Setup.** Work in a worktree of your own, claimed with `git worktree lock --reason`, on a branch from main.
  `source ~/.config/mylang/dev-env.sh` before every build. Builds and focused tests go through
  `scripts/build-slot.sh build …`. Read `CLAUDE.md` first: its Guardian rules (≤7 struct fields, ≤6 parameters, `///`
  on pub declarations, straight-line tests, no import cycles) block commits.
- **Every change.**
  - A behavioural change under `src/` or `build.zig` ships with its test in the same diff.
  - Run the complete gate before calling a package ready.
  - Don't land or push without the owner's go-ahead. If you are allowed to land, fast-forward main only after a green
    complete gate.
- **Notes and evidence.** Decisions go in `experiments/compiler-dev-loop-20261029/DECISIONS.md`, with the question,
  options, evidence, choice and whether it can be reversed. Progress goes in `status.md`. Logs and data go to
  `~/ai/canopy/mylang-evidence-archive/experiments/compiler-dev-loop-20261029/`, never into git.
- **Waiting.** Wait for long jobs in the foreground with a bounded wait (`timeout 590 tail --pid=PID -f /dev/null`).
  Report results, not "still running" notices.
- **Shared machine.** Other agents share this machine.
  - Never kill a process by a pattern that could match theirs.
  - Don't change timers or the `mylang-services` worktree.
  - Keep `MYLANG_STAGE_SHARED_CACHE` unset: the shared stage store serialized every compiler on the machine until it
    was made opt-in on 28 October.
- **Hard stops (report and wait):**
  - any change that could let a real failure pass: a skipped test, a selection miss, or a weaker check;
  - output differing from a `--no-cache` build;
  - free space on `/home/epentland/ai` under 25 GB;
  - the machine actively swapping (sustained `vmstat` si/so, not merely full swap).
- **Not in scope:**
  - Release-build testing stays off by the user's decision. `-Dtest-release=true` restores it.
  - Porting the Python tooling is deferred.

## 5. Background

- **Part 1's results and decisions:** `docs/audits/compiler-dev-loop-plan-2026-10-28.md` and
  `experiments/compiler-dev-loop-20261028/`: lanes T (measurement), U (allocator race), V (M1), X (debug-only gate) and
  Y (defects).
- **The edit check's design and proof:** `docs/audits/edit-check-plan-2026-10-25.md`, and
  `experiments/edit-check-20261025/` (`DECISIONS.md` W1–W9, `REPORT.md`).
- **Shadow mode:** after each complete gate, run `python3 scripts/edit_check_shadow.py --gate-log PATH`. It records
  whether the gate's failures were in the selection, in `~/.cache/mylang/edit-check/shadow.jsonl`. Every package that
  changes selection must keep shadow samples miss-free.
- **The 53 unstable tests** in the current map (its `unstable` field) gave different coverage across two collection
  runs. They are kept as a union, which is safe. Investigating them is a small follow-up.
