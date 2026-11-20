# Edit check: run only the tests an edit can affect (plan, 2026-10-25)

Working on the compiler today means waiting for the complete verification after every
change. It takes 140 to 300 s on this machine, plus 15 to 30 s to build, and it reruns
all of the roughly 5,000 Zig tests after any `src/` edit. This plan builds an **edit
check**: a command that finds the tests an edit can change and runs only those, measured
against the full suite before anyone relies on it. The complete verification stays the
landing gate (decision D1).

**Inputs.**
- The gate measurements of 25 October, in §1.
- `scripts/affected_tests.py`, today's heuristic selector. It is explicitly not the gate,
  and nobody has measured what it misses.
- `../guardian-zig`: its test runner (`--guardian-test-filter`, shards, shard plans) and
  its `mutate` step, which writes mutants for changed lines.
- The pinned Zig's `-ffuzz` instrumentation (`lib/fuzzer.zig`): LLVM's inline 8-bit
  edge counters (`__sancov_cntrs`) and PC table (`__sancov_pcs1`).

## 1. Why a compiler edit costs minutes today

Measured on 25 October on main `baac01fe3`, 20 logical CPUs, 31 GiB:

| Part | Time | Note |
| --- | --- | --- |
| Coordinator preparation | about 10 to 15 s | single-threaded Python snapshot and planning |
| `zig build` start-up | about 10 s | configure and cache checks; Guardian runs beside it |
| Incremental compile after an edit | 15 to 30 s | Debug compiler and three test binaries |
| Tests | 90 to 250 s | about 5,000 Zig tests in 28 shards, plus guest, language, golden and tooling suites |

- **What the tests cost:**
  - The unit root has 2,335 tests (about 155 test-seconds).
  - The CLI root has 640 (about 360 test-seconds).
  - The core root has 1,970 (about 480 test-seconds).
  - Most CLI and core tests start the compiler or build guest programs.
- **Scheduling isn't the problem.** Run alone, the three sharded roots take about 88 s however the shards are planned or the memory cap is set. They keep the CPUs busy, so the only way to make them faster is to run fewer tests.
- **Why everything reruns.** A shard's cached verdict is keyed to its whole test binary and the whole compiler, so any compiler edit reruns every shard.
- **Guest tests are already cheap.** `tests/lang` reuses per-test receipts keyed by the program a test builds, so a compiler edit reruns only the guest tests whose programs changed. The Zig roots have nothing like that, and they're what this plan addresses.

## 2. What the edit check does

```
edit → incremental build → impacted code → selected tests → run them → report
```

1. **Coverage map.** For every Zig test, the compiler functions it executes, recorded by
   an instrumented build at a known commit, including the code of any `mylang`
   processes the test starts.
2. **Impacted code.** The functions and declarations the working tree changed since that
   commit, found by comparing the two versions of each changed Zig file declaration by
   declaration, with the token digest the compiler identity already uses.
3. **Selection.** Every test that executed an impacted function, plus every test the map
   doesn't know (new tests), plus every test in a changed test file, plus the
   conservative classes of §EC2.
4. **Run.** The selected Zig tests through Guardian's runner across all cores, the guest
   tests through `mylang test` (receipts already make these cheap), Guardian on the diff,
   and `fmt` on changed files. Print what was selected, why, and how long it took, and say
   that this is not the landing gate.

### Expected gain

| Part | Complete verification today | Edit check |
| --- | --- | --- |
| Incremental build | 15 to 30 s | 15 to 30 s (unchanged) |
| Coordinator and `zig build` start-up | about 25 s | about 5 to 10 s |
| Choosing tests | none | about 2 to 5 s |
| Tests | 90 to 250 s | about 10 to 35 s at a 10 to 25% selection |
| **Total** | **140 to 300 s** | **about 40 to 65 s** |

- **Typical edit:** about 3 times faster.
- **Leaf edits** (one diagnostic, one checker rule, one lowering, one stdlib module): about 25 to 35 s, 5 to 10 times faster.
- **Central edits** (shared types, the checker or lowering paths every end-to-end test passes through): select nearly everything, so no faster than today.
- **Per landed change,** with five iterations and one complete verification before landing: about 1,000 s today against about 450 s.
- **What dominates next:** the build. Pairing the edit check with the incremental watch build, measured at 7 to 11 s per compiler edit, would bring leaf edits under 20 s.

## 3. Packages

### EC0. Baseline (3 to 4 h)

1. Record today's inner loop on a quiet machine, three samples each, measured from the
   save to a verdict:
   - `scripts/affected_tests.py`;
   - a focused `test-core`;
   - the complete verification.
2. Record per-test durations for the three Zig roots and whether each test starts a
   compiler process. The verification reports' native telemetry already has the
   durations (`scripts/verification_shard_plan.py observations`).
3. Pick the replay set for EC4: the last 40 first-parent commits on main that change Zig
   code under `src/`. Note each commit's parent.
4. Write the numbers into `status.md`.

### EC1. Per-test coverage (15 to 25 h; starts with a 2 h spike)

**Spike, before anything else.** Show that a `-ffuzz` build of `mylang` and of one test
binary can record which PC-table entries ran, without Zig's fuzzer runtime taking over.

- **Approach to try first.** Provide `__sanitizer_cov_8bit_counters_init` and
  `__sanitizer_cov_pcs_init` in a small coverage runtime linked only into the coverage
  variant. At process exit, write the indices of nonzero counters.
- **If the pinned toolchain forces its fuzzer runtime and the symbols collide,** try in
  order:
  1. counters read through the fuzzer runtime's own entry points;
  2. Intel PT through `perf record -e intel_pt//` (this CPU supports it) for the
     nightly map;
  3. `valgrind --tool=callgrind` for a slow nightly map.
- **Record which one worked, and stop if none does** (hard stop 1).

Then:

1. **Coverage variant.** Add a `coverage` build step that installs `mylang` and the unit,
   CLI and core test binaries with `fuzz = true` and the coverage runtime into
   `zig-out/coverage/`. Keep it out of the install graph and the gate.
2. **Test boundaries.**
   - In-process tests: the Guardian test runner zeroes the counters before each test and writes the hit set after it, under the test's name.
   - Compiler processes a test starts: they inherit `MYLANG_COVERAGE_DIR` and `MYLANG_COVERAGE_TEST` and write their own hit set at exit.
   - The runner change goes into `../guardian-zig` behind a feature flag that `build.zig` checks with `@hasDecl`, the same way `shard_plan` is handled (decision D4).
3. **Map PCs to source.**
   - A Zig developer tool, `tools/coverage_map.zig`, reads the coverage binaries' DWARF with `std.debug`. It maps every PC-table entry to (file, function), and follows inlined-subroutine records, so code inlined into a caller counts for the inlined function as well as the caller.
   - Generic instances map to their source function.
   - The tool writes `coverage-<commit>.json.zst`: test name → sorted list of function ids, where a function id is (file, function name, token digest of its body at that commit).
4. **Collection run.**
   - `zig build coverage-map` runs all three roots once with the coverage variant, through `scripts/build-slot.sh`, and writes the map to a per-user store: `MYLANG_EDIT_CHECK_STORE`, else `~/.cache/mylang/edit-check`, with the same retention style as the other stores.
   - Budget: at most twice a normal gate's test phase.
   - Nondeterministic tests (threads, hash order): union the hit sets of two runs, and list the tests whose sets differ.
5. **Tests.**
   - An inlined helper's change selects its caller's tests.
   - A generic function's change selects every instance's tests.
   - A function no test runs selects nothing.
   - A compiler process started by a CLI test contributes to that test's set.
6. **Go/no-go.** With the first map, compute the selection size for each EC0 replay
   commit, using EC2's rules applied by hand or by a first cut of the tool. If the median
   selection is above 50% of the Zig tests, stop and report (hard stop 5): most tests run
   most of the compiler, and the rest of the plan would not pay for itself. This caps the
   risk at about a third of the plan's hours.

### EC2. From an edit to the impacted code (8 to 12 h)

A Zig tool, `tools/impact.zig`, compares the working tree with the map's commit:

| Change | Impact |
| --- | --- |
| A function body (token digest differs) | that function |
| A new function | nothing by itself: it runs only through a changed caller |
| A deleted or renamed function | its old id: tests that ran it are selected |
| A type, `const`, global, `comptime` block or `usingnamespace` | every function in the file, then every test that ran any of them |
| A test in a test file | that test |
| `build.zig`, `build_test_inputs.zig`, `.zigversion`, the Guardian pin, a new Zig file the map has never seen | everything (the full suite) |
| A file a test step declares in `build_test_inputs.zig` | every test of that step |
| An embedded `.my` standard-library module, a C runtime file, an embedded doc | the conservative class decided in EC2 step 2 |

1. Comments and layout never count. The token digest already ignores them, as the
   compiler identity does.
2. Decide the classes for embedded `.my` files and the C runtime from EC0's data and log
   the choice. The default is every test that runs the code that loads or links them,
   plus all guest tests through their receipts.
3. Print each impacted id with the reason that selected it.

### EC3. The command (8 to 12 h)

1. **`zig build edit-check`**, with `scripts/edit_check.py` as its wrapper:
   - build incrementally;
   - load the newest map no newer than `HEAD` (§EC5 staleness rule);
   - select;
   - run.
2. **Running the selection.**
   - Zig roots go through a new Guardian option `--guardian-test-list FILE` of exact names (D4). Until that exists, use the OR substring filter `--guardian-test-filter`.
   - Shard the selection across the cores with the existing shard machinery.
   - Run guest tests with `mylang test` and its receipts.
   - Run Guardian diff-scoped, and `zig fmt` / `mylang fmt --check` on changed files.
3. **Output.** At most 20 lines:
   - selected / total per root, and the five largest reasons;
   - time per part;
   - failures with their first `file:line`;
   - the line "edit check passed; this is not the landing gate".
4. **No map.** With no map at all, the edit check says so and runs `affected_tests.py`'s
   selection.

### EC4. Prove it before anyone relies on it (10 to 16 h)

1. **Replay.**
   - For each EC0 commit, compute the selection from a map at or before its parent.
   - Run the full suite and the selection on the commit and its parent.
   - A test whose verdict differs between parent and commit but isn't selected is a **miss**.
2. **Mutants.**
   - For each replay commit, take up to 5 Guardian `mutate` mutants on its changed lines (about 200 in total).
   - Run the full suite and the selection on each.
   - A mutant the full suite kills but the selection doesn't is a miss.
3. **Targets.**
   - Zero replay misses.
   - At least 99.5% of killed mutants killed by the selection.
   - Median selection at most 25% of the Zig tests.
   - Median edit check at most 60 s from save to verdict on a quiet machine, including the incremental build.
4. **Fixes.** Classify every miss: coverage gap, an impact class, a nondeterministic
   test, or a test that reads data the map doesn't know. Fix it and rerun the study once.
   Missing a recall target after that one round is hard stop 2.
5. Write the results table into `REPORT.md`.

### EC5. Into the workflow (3 to 4 h)

1. `CLAUDE.md` "Fast loops": the edit check becomes the inner loop for compiler work. The
   complete verification remains the step before landing.
2. **Map refresh.** After each landing on main, a background job under `build-slot.sh`
   builds the coverage variant and refreshes the map (D5). It is cancelled if another
   landing arrives.
3. **Staleness.** A map from commit B used on tree T compares B with T, so everything
   changed since B is impacted. An old map is still correct, only slower, and the edit
   check prints its age.
4. `affected_tests.py` calls the edit check when a map exists. Its heuristics remain the
   fallback.

## 4. Order

EC0, then the EC1 spike. Stop there if hard stop 1 applies. Then EC1, ending with its
go/no-go (step 6). Stop if hard stop 5 applies. Then EC2, EC3 and EC4. Only after EC4 meets its targets does EC5 change `CLAUDE.md` or the default
workflow. Each landing is a fast-forward after the complete verification.

## 5. Done criteria

| # | Criterion |
| --- | --- |
| EX1 | `zig build edit-check` runs on a clean tree and after a one-function edit, and prints its selection, reasons and times |
| EX2 | EC4's targets hold: no replay miss, ≥ 99.5% of killed mutants caught, median selection ≤ 25%, median edit check ≤ 60 s |
| EX3 | The complete verification, its receipts and its action keys are unchanged: the edit check adds steps and reads reports, and changes nothing the gate depends on |
| EX4 | Nothing new in the install graph or `src/` runs Python. The coverage variant and tools build only on request |
| EX5 | The EC1 tests (inlining, generics, untested function, child process) pass in the complete verification |

## 6. Decisions

Recommended, accepted at launch unless struck:
- **D1.** The edit check never replaces the complete verification before landing. The
  alternative, landing on an edit check plus a nightly full run, would be faster, but a
  broken landing would be found hours later.
- **D2.** Function granularity, with whole-file impact for non-function declarations. A
  file-only map is simpler but selects much more after an edit to a large file such as
  `single_owner.zig`.
- **D3.** Coverage from `-ffuzz` edge counters, if the spike works. Otherwise Intel PT
  for the nightly map.
- **D4.** Guardian gains an exact test-list option and a per-test coverage hook, behind
  feature flags in `../guardian-zig`, landed there first.
- **D5.** The map refreshes after every landing, not nightly.

## 7. Risks

| Risk | Answer |
| --- | --- |
| Code that runs at compile time (`comptime`, type layout) has no PCs | non-function declarations impact their whole file (EC2) |
| Inlining hides a helper inside its caller | the map follows DWARF inline records; an EC1 test pins it |
| A test reads fixtures, not code | declared inputs in `build_test_inputs.zig` select their step |
| Nondeterministic tests run different code each time | union of two runs; listed in the report |
| Instrumented builds are slow | they run in the background after landings, never in the loop |
| The machine is shared | every measurement records load and queue wait; timing samples repeat |

## 8. Not in this plan

- Making the complete verification itself faster. Its measured levers are in
  `experiments/gate-speed-20261025/`.
- Self-hosting. It wouldn't give the Zig test roots finer caching, and this plan does.
- Caching verdicts of selected tests across edits.

## 9. Operating rules and launch instruction for Codex

The operating rules of `docs/audits/ownership-rules-plan-2026-10-24.md` §10 apply, with
these changes:
- Decisions go in `experiments/edit-check-20261025/DECISIONS.md`, progress in
  `status.md`, the finish in `REPORT.md`. Data goes to
  `~/ai/canopy/mylang-evidence-archive/experiments/edit-check-20261025/`.
- Work in an idle, merged worktree on branch `edit-check/integration` from main. Claim it
  with `git worktree lock --reason`.
- Hard stops:
  1. no coverage mechanism works (EC1 spike);
  2. EC4 misses a recall target after one round of fixes;
  3. any change would alter the complete verification's behaviour, receipts or action
     keys;
  4. the Guardian changes are refused;
  5. the median replay selection is above 50% at EC1's go/no-go.

```text
You are implementing docs/audits/edit-check-plan-2026-10-25.md in ~/ai/canopy/mylang:
build an edit check that runs only the tests a compiler edit can affect, from a
per-test coverage map, and prove it against the full suite before it enters the
workflow. Read the plan fully, then CLAUDE.md, scripts/affected_tests.py and Guardian's
test runner in ../guardian-zig. Claim an idle merged worktree, run
`git switch -c edit-check/integration main` there, and start with EC0 and the EC1
spike. Decide, log in experiments/edit-check-20261025/DECISIONS.md, and continue; stop
only for the plan's hard stops. Land each package by fast-forward after the complete
verification. Keep status.md current, write a handoff there when your context runs low,
and finish with REPORT.md.
```
