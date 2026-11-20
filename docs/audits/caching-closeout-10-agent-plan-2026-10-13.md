# Caching closeout: coordinator plus ten workers (2026-10-13)

Prepared 13 October 2026 as the execution handoff for
[the caching closeout plan](caching-closeout-plan-2026-10-13.md) (lanes H1 to
H6, done criteria K1 to K9). One coordinator and ten workers, W01 to W10, finish
the development-loop caching work so that the ownership migration and the
parity lanes that follow it run on a fast loop. The user set the order of work:
this closeout first, then ownership as the default with reference counting
removed, then the [parity lanes](lox-eda-zig-parity-plan-2026-10-13.md), then
self-hosting.

## Base and what is already there

Plan base, local `main` (the closeout plan and this plan are on branch
`claude/caching-closeout-plan-20261013`, local `main` plus the plan documents;
`C0` is that branch's tip):

```text
76180573b5c2cd8081cf8218e374166eb9677c44
```

Recheck the development lineage before starting and pin the actual base as
`C0`. `origin/main` is a separately published snapshot; do not merge it into the
development lineage because both are called main. Main already contains the
output-keyed shared receipts integration (lanes A to G5), the development-loop
ten-session closeout (S01 to S10), and the Lox/EDA parity publication. Preserve
all of it.

A read-only survey of `C0` on 13 October corrected several assumptions in the
closeout plan. Workers start from these facts, not from the closeout plan's
first estimates:

| Item | Closeout plan said | `C0` actually has |
| --- | --- | --- |
| Gate concurrency | right-size RSS | `build.zig:28-87` declares 2,560 MiB per unit shard and 1,024 MiB per core shard; the 13 October gate (`experiments/lox-eda-parity-20261013/publication-main-20261013/gate-005/`) measured 65–143 MB (unit), 282–578 MB (core), 64–296 MB (cli). `verify_cache.py:1636-1639` silently adds `-j3 --maxrss 8589934592`, so at most three unit shards run at once |
| Shard balance | `index % N` | `guardian-zig/src/test_runner.zig:206-210` (`position % count`); per-test wall times are already recorded by `scripts/verification_native_telemetry.py` into `last-run.json` (`actions[].test_telemetry[member].tests[].elapsed_ns`). gate-005 per-shard sums: unit 3.5–46.5 s, core 58–80 s, cli 7.0–70.5 s; slowest single tests: cli 57.7 s, unit 37.4 s (`nominal_providers`), core 19.2 s |
| `.again` sites | 46 budget sweeps | 43 are deliberate cache tests (`Projects.again` in `test_runner_portable_test.zig`, `compiler_shared_cache_test.zig`); 3 are budget sweeps: `nominal_providers_test.zig:175` (110 budgets), `resource_source_test.zig:260` (90), `resource_io_test.zig:216` (85), each a fresh `mylang run --max-steps=N` build, run serially. `SPEC.md:126` (NATIVE-ARGV-1) says budgets are compiled in |
| Per-test cache dirs | 43 core files | 59 `src/core/*_test.zig` files pass `--cache-dir`; about 43 make no cache assertions. The unit root already has a suite cache (`build.zig:703-707`, `src/wiring/core_runner.zig:78-96`); the core root has none |
| Scheduler | to be built | `scripts/verification/scheduler.py` exists (SQLite WAL; key dedupe, subscribers with leases, priorities with aging, exclusive jobs, generation tokens, publish and coalesce) but only `scripts/verify.py --scheduler` uses it; `build-slot.sh`, `build_admission.py` and `verify_cache.py` do not. No per-worktree fair share. `MYLANG_TIMING_CPUS` only removes CPUs from builds; timing still drains every build and gate |
| Publication race | as stated | Confirmed: receipts are saved after the admitted child exits (`verify_cache.py:1475-1512`); the pre-queue miss path calls `shared.invalidate_success` (`:1399-1401`) under a lock keyed by the worktree root (`:1290-1293`), so another worktree's fresh receipt can be invalidated |
| F15 | producer identities bind DWARF paths | `verification_producers.py:90,201` binds the test binary's bytes for `tooling-units` and `text-scalar-units`; path-free recipe producers for both already exist (`build_verification.zig:248-249`, `verify_cache.py:845-875`) |
| F16 | absolute `../guardian-zig` paths | `verification_snapshot.py:565-573,620-624` records resolved paths outside the root as absolute; `path_free` only searches for `str(root)` |
| F17 | 94 unshareable tests | `test_runner_portable.zig:33-70` refusals; execution receipts (`core-test-exec-v3`, `core-test-whole-exec-v3`) live only in the private `{cache}/tests/receipts-v3/` |
| Default sharing | two blocking tests | three: `verify_cache_test.py:1823` and `:1961`, and `compiler_shared_cache_test.zig:327-345` (`swapRemove` of the variable; set it to empty instead) |
| Warm path | key Guardian, spec-history, juice | Eleven groups are `cacheable=false` and always run: component-preparation, input-discovery, environment-discovery, spec-history, juice, juice-runtime, identity-qualification, coverage, guest, language, guardian. Skipping admission when everything is reused already exists (`verify_cache.py:1440`) and never triggers because of them. Language members replay for 10–23 s; identity-qualification 5–10 s. `bounded()` (`build.zig:301-305`) makes every selected target wait on `install_all`, which runs install-wired Guardian and `component_build` |
| Test filter | runtime | `-Dtest-filter` is passed to `addTest(.filters)` (`build.zig:460,663,675,686,722,838`), so each filter compiles a new binary, and a filtered request makes every group uncacheable |
| Copies | reflinks | ext4, no reflinks. `build_verification.zig:337-338` installs 10 artifacts (749 MB per worktree) into `zig-out/verification/bin`, which nothing reads |
| Unit store | 1.87 M files | 2,437,201 entries in one flat `units-v1` directory; `scripts/prune-caches.sh` cannot take its exclusive lock while builds hold shared leases; `src/native_cache_retention.zig` already implements leased mtime LRU for the shared namespaces |
| Runtime in unit keys | yes | any `src/core/runtime/*.c` edit changes `runtime.abi` (`driver.zig:376-392`), a field of every unit key (`unit_cache.zig:37-53`) |
| Revalidation tests | two failures | `scripts/verification_revalidation_test.py` targets a retired coordinator path; its four tests were ported into `verify_cache_test.py:240…`; it is not registered in the gate |
| Commit hook | `GUARDIAN_AGAINST` | the hook runs whole-tree `all . --gate`; a large merge fails because `git diff` output over 64 MiB (`guardian-zig/src/git.zig:16`) is misreported as `GitSpawnFailed` |
| Timers | none | no systemd user timer or cron entry for pruning or nightly `--integration`; one manual `--integration` run passed (gate-005, `505d2ca34`) |

## Targets

The closeout plan's done criteria, unchanged; W10 measures every row on `C0`
before anything lands and on the final candidate:

| # | Criterion | Today |
| --- | --- | --- |
| K1 | One-line compiler edit, then complete verification: green in at most 300 s on one worktree | 763 s (cohort C3) |
| K2 | Unchanged complete verification: at most 10 s, no gate slot | 24–37 s, median 29.9 s, gate 14.4 s; 11 groups always fresh |
| K3 | Fresh worktree at a known commit: every cacheable action and at least 99 % of guest tests reused | 33 of 35 actions; 94 guest tests unshareable |
| K4 | Ten simultaneous requests at one commit: one execution per group, nine hits, none of the nine takes a gate slot; a timing window pins its CPUs and never blocks a build | ten requests serialize through one gate slot; timing drains the machine |
| K5 | Sharing on by default; the gate passes with the default stores; a nightly `--integration` run is green | off; no nightly |
| K6 | `zig build` after a one-line compiler edit about 1 s warm; a new test filter compiles no new binary; development installs are not gated | 2–7 s plus Guardian and a 239 MB install; every filter compiles |
| K7 | Unit store sharded and bounded, eviction on a timer, a fresh worktree's first build shares unit objects | flat, 2.44 M entries, no eviction |
| K8 | No gate test fails under load twice in a week; no obsolete or cwd-dependent test; large merges commit through the hook | four load-sensitive tests, one obsolete file, one cwd-dependent file, hook fails over 64 MiB |
| K9 | All rows re-measured on the closing commit and recorded | — |

Report each row as passed, failed or not qualified. A row that misses stays open
with its measured value and the next step; do not drop a slow row or change the
denominator.

## Coordinator startup

1. Read `CLAUDE.md`, the closeout plan, this plan, and
   `docs/tooling/development-loop.md`. Inspect worktree status before switching
   or merging anything. The usual main checkout is
   `/home/epentland/ai/canopy/mylang-debug-speedup-main`; it may carry another
   party's uncommitted documentation. Do not touch it; work in a new worktree.
2. Pin `C0`. Create `codex/caching-closeout-20261013-integration` at `C0` in its
   own worktree, and one worktree and branch per worker,
   `codex/caching-closeout-20261013-wNN`.
3. Create `experiments/caching-closeout-20261013/status.md`: base, owners, claimed
   files and functions, fixed commits handed in, integration rounds, evidence,
   open rows of K1–K9.
4. Ask W10 for the `C0` baseline (below) before any worker's change is
   integrated. Workers start their audits and implementation at once.
5. Identify the memory-management (ownership) owner. The ownership default and
   reference-counting removal are the next program and will touch
   `src/core/driver.zig`, the runtime and lowering. W02 and W09 touch
   `driver.zig`, `unit_cache.zig`, `run_budget.zig` and `core_test.c`; record
   their claims in the ledger and exchange patch requests rather than editing
   the same functions in parallel.

### Capacity

One coordinator and ten worker sessions. All ten can read, implement and build
concurrently; complete gates and timing windows still go through admission.
If fewer slots are available, keep the ten assignments and run them in batches:
W01/W03/W06/W10, then W02/W04/W05/W07, then W08/W09. Workers do not start
subteams.

## Ownership and operating rules

**Coordinator only:** `build.zig`, `build_test_inputs.zig`,
`build_verification.zig`, `build_identity.zig`, `guardian.toml`, `SPEC.md`,
`CLAUDE.md`, `docs/tooling/development-loop.md`,
`docs/tooling/many-agents.md`, existing test-root imports, and the ledger.
Workers send small patch requests (the hunk, its reason, the test that covers
it); the coordinator applies them in order.

**`scripts/verify_cache.py` and `scripts/verify_cache_test.py`** are claimed by
function. W05 owns the admission and publication path (`run_admitted` and the
admitted child, `prior_success`/invalidation, `save_receipt` and
`shared.publish_success` call sites, `recheck_after_admission`). W06 owns
`action_payload`, `artifact_identities` and `DEFAULT_SHARING`. W07 owns the
fresh-group decision (`:1383-1386`) and the warm selection path. W01 owns
`parse_options` defaults. Any other edit is a patch request. The coordinator
merges these in the round order below and resolves conflicts.

**`guardian-zig`** is a separate repository and the build dependency of every
worktree (`../guardian-zig`). Only W01 changes it, in its own guardian-zig
worktree and branch. The coordinator never updates the sibling checkout;
merging into guardian-zig is the user's decision. Every mylang change that uses
a new Guardian option must still pass with the current Guardian (fall back to
`% N`, compile-time filters, current diff behaviour). Do not edit
`guardian-zig/FEEDBACK.md`.

**Operational rules** (as in `CLAUDE.md`): `source ~/.config/mylang/dev-env.sh`
in every worktree; a private `ZIG_LOCAL_CACHE_DIR` and an on-disk `TMPDIR` per
worktree (`/tmp` has a per-user quota other sessions fill); the shared Zig
global cache; builds and focused native tests through `scripts/build-slot.sh
build`; run `scripts/verify_cache.py` directly (it owns admission); timing only
through `build-slot.sh timing` or the cohort runner. Do not clear shared caches
to manufacture a cold result. Keep every failure fail-closed: timeouts,
crashes, source mutation, missing inputs and incomplete coverage never publish
success.

**Gates:** workers run focused checks and the normal commit hook. Complete
verification belongs to integrated candidates; the coordinator runs it once per
round. No worker runs a full gate for its own branch unless the coordinator
asks.

**Commits:** workers commit fixed SHAs and a `handoff.md` in
`experiments/caching-closeout-20261013/WNN/`. Only the coordinator integrates.
No worker merges main, pushes, rewrites another branch or edits another
worktree. Nobody pushes; merging the integration branch into main is the user's
decision.

**Defaults and scheduled jobs:** the closeout plan's targets K5 and K7 require
flipping default sharing and installing two systemd user timers (store eviction
and a nightly `--integration`). They happen only in round R4, after the gate
passes with the default stores and the timers' dry runs are reviewed, with the
unit files committed under `scripts/systemd/` and an install script. The
coordinator's final report says exactly what was installed on the host.

## Ten workers

| Worker | Lane | Main responsibility | First deliverable |
| --- | --- | --- | --- |
| W01 | H1 | Gate concurrency and Guardian runner | Right-sized RSS and `-j` patch with measured shard concurrency |
| W02 | H1 | Budget sweeps built once | SPEC amendment proposal and a working harness-only runtime budget |
| W03 | H1 | Shared warm cache for core tests | Classified list of the 59 files and the shared-cache helper |
| W04 | H2 | Scheduler as the admission backend | `build-slot.sh` client over `scheduler.py` running in shadow mode |
| W05 | H2 | Coordinator publication and deduplication | Receipts published inside the slot; cross-worktree invalidation lock |
| W06 | H3 | Finish sharing | F15 and F16 fixes with a two-worktree reuse check |
| W07 | H4 | Warm path | Per-group key or profile for each of the 11 always-fresh groups |
| W08 | H5 | Inner loop | Runtime test filtering on the mylang side; ungated development install |
| W09 | H5, H6 | Unit store and compiler fixed costs | Sharded store with lazy migration and a size ledger |
| W10 | K1–K9, H6 | Measurement, hygiene and qualification | `C0` baseline of K1–K9 and the attribution of C3's 763 s |

### W01 — Gate concurrency and Guardian runner (H1)

**Own:** the `rss` constants (patch request to `build.zig:28-87`), shard counts
(`-Dcore-shards`, `-Dtest-shards`), `parse_options` defaults in
`verify_cache.py`, a new `scripts/verification_shard_plan.py` and its test,
`docs/tooling/runtime-budgets.md:211-245` (patch request), and a guardian-zig
branch.

1. Declare `max_rss` from observed peaks with headroom (gate-005 and W10's
   baseline), and replace the hidden `-j3 --maxrss 8 GiB` with a documented
   default that lets the machine run the shards it has room for. Revisit core
   and unit shard counts once concurrency is no longer the limit.
2. Generate a shard plan by longest-processing-time assignment from
   `last-run.json` per-test times; unknown tests fall back to `% N`. The plan
   enters the run step's cache key (`addFileArg`).
3. On the guardian-zig branch: `--guardian-shard-plan=FILE` in
   `test_runner.zig` (std-only; unknown names fall back to `% N`), a runtime
   name filter that skips non-matching tests through the existing shard-skip
   path (for W08), and a streamed or raised `git diff` limit with a correct
   error for the 64 MiB case (for K8).
4. The single slowest tests bound each root (cli 57.7 s, unit 37.4 s until W02
   lands). Report them; splitting a test's body is a patch request to its owner.

**Accept:** a forced complete gate runs the shards concurrently that memory
allows (record the observed concurrency); selected test counts per root sum to
the unsharded count with and without a plan; per-root shard maximum within
1.25× of the root's largest single test or of the mean, whichever is larger;
all mylang changes pass with the current Guardian.

### W02 — Budget sweeps built once (H1)

**Own:** `src/native_execute.zig` (`Batch`, `runAll`, `execute`, `adopt`,
`afterBuild`, `restore`), `src/run_budget.zig`, the budget handling in
`src/core/runtime/core_test.c` and `src/cli_args.zig`/`src/core/pipeline.zig`,
and the three sweep tests. SPEC changes (NATIVE-ARGV-1, QBE-STEP-ACCOUNTING-1)
go to the coordinator. Coordinate `run_budget.zig` and `core_test.c` with the
ownership owner.

The three sweeps build 285 programs that differ only in a compiled-in step
budget. Add a build used only by the test harness that compiles step accounting
in and reads the limit at start; user-facing `build --max-steps` stays a usage
error and user binaries keep compiled-in budgets. `Batch` groups jobs by
compilation, builds each once (`native_execute.executable()`), and runs the
binary per budget. Keep the first and last budget of each sweep on the
compiled-in path as a cross-check that both paths agree.

**Accept:** the three sweeps build 3 programs plus the 6 compiled-in
cross-checks instead of 285; the unit shards that held them drop from 44–46 s to
under 10 s; outputs, traps and budget-exhaustion diagnostics identical to `C0`
at every budget; SPEC amended with the harness-only scope.

### W03 — Shared warm cache for core tests (H1)

**Own:** the core test files W03 claims from the classified list, a shared
suite-cache helper (in `src/core/test_paths.zig` or a new support module), and
the core root's cache option (patch request to `addCore`, `build.zig:444-526`).

Classify the 59 files: about 43 make no cache assertions and can use one shared,
content-addressed suite cache per core root, as the unit root does; the files
that assert cache behaviour (`cli_flags`, `compiler_shared_cache`,
`driver_cache`, `driver_native_cache`, `entry_path`, `test_runner*`,
`runner_property_campaign`, `cost_query`, `inline_scalar_reader`, `byte_index`,
`ce2_effects`, `textgap_split`) stay private. Writes are already atomic and
content-addressed (`native_execute.write`), so shards can share.

**Accept:** published file list with the reason for each; core shard walls
before and after on a cold and a warm gate; no test reads another test's
outputs (run the core root twice in reverse shard order); a test that asserts
cache behaviour still gets a private cache.

### W04 — Scheduler as the admission backend (H2)

**Own:** `scripts/verification/scheduler.py`, `scripts/build-slot.sh`,
`scripts/build_admission.py`, their tests (`tests/verification/test_scheduler.py`
and the admission tests), and `scripts/verification_measurement_test.py`.

1. Make `scheduler.py` the admission backend and `build-slot.sh` a thin client
   with the same command line, exit statuses and environment
   (`MYLANG_SLOT_DIR`, `GATE_SLOTS`, `BUILD_MEM`, `--admitted`, `--hold`). One
   admission directory; `build_admission.py` stops duplicating the shell's
   directory logic.
2. Add per-worktree fair share and one token pool for compile, link and test
   work; keep FIFO order within a priority and aging across priorities.
3. Timing windows: reserve `MYLANG_TIMING_CPUS` for the measurement (cpuset and
   affinity) and keep admitting builds and gates on the other CPUs, instead of
   draining the machine. Builds never run on reserved CPUs while a window is
   open; a window never starts while a job holds its CPUs.
4. Expose keyed jobs with subscribers to W05 (publish, coalesce, cancel without
   losing work another subscriber needs). Freeze the API early in `handoff.md`.
5. Run in shadow mode beside the current admission for one day of real agent
   traffic, logging decisions, before switching.
6. Make `verification_measurement_test.py` deterministic (no 0.05 s windows
   that depend on load).

**Accept:** the existing admission tests pass unchanged against the new
backend; crash, kill and lease-expiry cases release slots; a timing window and
two builds run at once on disjoint CPUs; mean admission wait for warm requests
under 10 s in W10's C5 run; the shadow log shows no decision that would have
starved a kind.

### W05 — Coordinator publication and deduplication (H2)

**Own:** the `verify_cache.py` admission and publication functions listed above,
`publish_success` and `invalidate_success` in `scripts/fuzz_campaign_store.py`
(the shared evidence store, also used by fuzz campaigns: keep its existing
callers' contract), and their tests.

1. Write local receipts and shared publications inside the admitted child,
   before the gate slot is released, so a waiting peer's post-admission
   re-lookup (F19) finds them.
2. Take the invalidation lock by store and action key, not by worktree root, and
   re-check under it before `invalidate_success`, so no request invalidates a
   receipt a peer published after its pre-queue miss.
3. Submit gate work to W04's scheduler keyed by the action key: identical
   concurrent requests subscribe to one execution and wait without a gate slot;
   cancellation of one subscriber keeps the work another still needs.

**Accept:** C5 (ten requests at one commit): one execution per group, nine
coalesced or reused, none of the nine admitted to a gate slot; a test that
publishes between a peer's miss and its invalidation keeps its receipt;
interrupted publication publishes nothing; the coordinator tests pass.

### W06 — Finish sharing (H3)

**Own:** `scripts/verification_producers.py`, `scripts/verification_snapshot.py`,
`action_payload`/`artifact_identities`/`DEFAULT_SHARING` in `verify_cache.py`,
`src/core/test_runner_portable.zig`, `src/core/test_runner_receipt.zig`,
`src/shared_cache_policy.zig`, `src/core/compiler_shared_cache_test.zig`, and the
two `verify_cache_test.py` assertions on default sharing.

1. **F15:** use the path-free recipe producers for `tooling-units` and
   `text-scalar-units` instead of the test binaries' bytes.
2. **F16:** record resolved paths outside the root relative to a declared
   sibling root (`../guardian-zig/...`), and extend `path_free` to flag any
   absolute path, not only `str(root)`.
3. **F17:** publish execution receipts (`core-test-exec-v3`,
   `core-test-whole-exec-v3`) to the shared test store under the same
   validation as the IR tier: program bytes and runner identity are the key;
   host-capability, C-extern and live-effect tests stay private and report why.
4. Default sharing: fix the three assertions (set the variable to empty
   instead of removing it), flip `default_sharing` and `DEFAULT_SHARING` on a
   branch, and run the complete gate with the default stores. Integration of
   the flip waits for round R4.
5. `--integration`: run it live once on the integrated candidate; ship a
   systemd user timer and service for a nightly run with its log location
   (installed in R4).

**Accept:** a second worktree at the same commit reuses every cacheable action
(no action key differs; record the inventory) and at least 99 % of guest tests;
F16's extended check finds no absolute path; the gate passes three times with
the default stores; `--integration` green.

### W07 — Warm path (H4)

**Own:** the fresh-group decision and warm selection in `verify_cache.py`,
`scripts/verification_profiles.py`, `scripts/verification_qualification.py`,
`tests/test_spec_merge.py` inputs, and the group registrations (patch requests
to `build.zig` `register(...)` calls and `build_verification.zig`).

For each of the 11 always-fresh groups choose one, with evidence:

- **Key it:** Guardian on its binary digest, `guardian.toml`, the in-scope file
  bytes and the merge base; spec-history on its 18 fixed merge commits and its
  two scripts; identity-qualification and coverage on their declared inputs;
  language and guest on the compiler artifact identity, the test sources'
  closure and the projected environment, so an unchanged tree skips the
  10–23 s receipt replay entirely.
- **Move it to the qualification profile:** juice and juice-runtime
  (`verification_qualification.py` `OBLIGATIONS`), reported as owed, never as
  passed.
- **Keep it fresh but make it cheap:** input- and environment-discovery and
  component-preparation, which feed the keys. Do not reintroduce mtime-only
  memoization (S08 rejected it); stat checks may skip a rehash only together
  with inode, size and change time, with full rehash on doubt.

Stop selected test-only targets from waiting on `install_all` (`bounded()`),
so a fresh language group does not run install-wired Guardian and
`component_build`.

**Accept:** two consecutive unchanged complete verifications report zero fresh
groups, zero admissions and at most 10 s request time (C1); every newly keyed
group re-executes when one of its inputs changes (one mutation test per group);
qualification-profile runs still execute juice.

### W08 — Inner loop (H5)

**Own:** the mylang side of runtime test filtering (patch requests to the
`addTest(.filters)` sites and `forwardFilters`), `-Dgate-install` (patch
request to `build.zig:711-712`), removal of `stage.sh` and its mentions, the
`zig-out/verification/bin` install (`build_verification.zig:337-338`, patch
request), `component_build`'s caching (`build.zig:625`, `selfhost/components.zig`),
and `docs/tooling/development-loop.md` sections it changes (patch request).

1. With W01's Guardian runtime filter, stop compiling filters into test
   binaries; a new filter reuses the existing binary. Until that Guardian change
   is merged, keep compile-time filters as the fallback. A filtered request
   should stay cacheable for the groups the filter does not touch.
2. `-Dgate-install=false` installs without the Guardian gate for development;
   the gate and commit hook still run Guardian.
3. Delete `stage.sh`; point its mentions at `zig build affected-compiler`.
4. Stop installing the 749 MB `zig-out/verification/bin` copy, or hardlink it
   if a reader is found (ext4 has no reflinks).
5. Key `component_build` on `component_inputs` with an output stamp, so an
   unchanged gate does not run it.
6. Measure `zig build --watch -fincremental` for the compiler executable on a
   one-line edit; document it if it works on the pinned Zig, or report why not.

**Accept:** K6 rows measured (one-line edit to installed compiler; second
filter compiles no new binary; ungated install time); `component_build`
reported cached on an unchanged gate; per-worktree disk saved.

### W09 — Unit store and compiler fixed costs (H5, H6)

**Own:** `src/core/unit_cache.zig` (`Store`, `key`, `unchanged`),
`src/core/build_replay.zig`, the runtime identity in `src/core/driver.zig`
(`runtimeForMode` and `Settings.runtime`), `src/native_cache_retention.zig`
where reused, `scripts/prune-caches.sh`, and the store timer unit files.
Coordinate `driver.zig` with the ownership owner, who will remove the
reference-counting runtime variant next.

1. Shard the store as `units-v1/ab/<key>`: new writes sharded, reads try the
   sharded path then the flat one, and a background mover migrates the 2.44 M
   flat entries without blocking builds.
2. A size ledger and leased LRU eviction reusing `native_cache_retention.zig`;
   fix `prune-caches.sh`'s exclusive lock against builds' shared leases; ship a
   systemd user timer (installed in R4).
3. Key guest unit objects on what they actually depend on from the runtime
   (headers, declarations, layout and ABI flags) instead of the whole runtime
   source, so a runtime `.c` body edit relinks instead of recompiling every
   unit. Prove the boundary with a test that edits a runtime body and one that
   edits a declaration.
4. A stat fast path before rehashing replay dependencies in
   `unit_cache.unchanged`, using inode, size, modification and change time, with
   full rehash on any difference and under `--verify-cache`.

**Accept:** a fresh worktree's first build serves unit objects from the shared
store; store size held under its cap by the timer's dry run and one real run;
a runtime body edit recompiles no guest unit; replay of an unchanged program
does no content hashing; `--verify-cache` still detects a corrupted object.

### W10 — Measurement, hygiene and qualification (K1–K9, H6)

**Own:** `experiments/caching-closeout-20261013/` measurement and the cohort
runner (`experiments/output-keyed-receipts-20261012/cohorts.py`), the
load-sensitive tests (`src/component_protocol_test.zig:66-68,242-245`,
`src/core/durable_test.zig:45-70` with `durable_fixture.c`, the property batch at
`test/integration.zig:9326-9331`), `scripts/verification_revalidation_test.py`
(delete; its tests live in `verify_cache_test.py`),
`scripts/verification_process_test.py` (no cwd dependence), and the worktree
hand-off note in `docs/tooling/many-agents.md` (patch request).

1. **R0 baseline on `C0`:** cohorts C1 to C5 and the compile-edit gate in
   exclusive windows, five samples where the protocol says five, queue time
   beside each sample. Attribute C3's 763 s by phase: Zig test-binary
   compilation, each shard root's run, guest groups, waiting. Publish this
   within the first day; W01 to W03 aim at whatever dominates.
2. Fix the load-sensitive tests with deterministic budgets (no 10 ms deadline
   expecting a process exit; no 0.05 s windows), or quarantine one with a named
   owner and an issue.
3. Measure each integration round (C1, C3, C5 at least) and the final candidate
   (all of K1–K9); write the results into the closeout plan's outcome and
   `docs/tooling/development-loop.md` (patch requests).

**Accept:** baseline published before the first integration; every K row has a
`C0` value, per-round values and a final value; the gate passes ten times in a
row under ordinary agent load without a test-only failure.

## Rounds

1. **R0, baseline and claims (day 0).** Coordinator pins `C0` and the ledger;
   W10 publishes the K1–K9 baseline and C3's attribution. Every worker starts.
2. **R1, cold gate and identities (days 1–2).** Integrate W01's RSS, `-j` and
   shard-plan changes (without the Guardian flag), W03, W02 after the SPEC
   amendment is accepted, W06's F15 and F16, and W10's test fixes. Coordinator
   runs the complete gate; W10 measures C3 (K1).
3. **R2, admission and publication (days 2–4).** Integrate W05's in-slot
   publication and lock, W06's F17, and W04's scheduler in shadow mode; switch
   to the scheduler after its shadow day; then W05's keyed subscription.
   W10 measures C5 (K4).
4. **R3, warm path and inner loop (days 4–6).** Integrate W07, W08 and W09.
   W10 measures C1 (K2), C4 (K3) and K6.
5. **R4, defaults and freeze (days 6–7).** Run the gate three times with the
   default stores, integrate W06's flip, install the eviction and nightly
   timers, freeze the candidate, run the complete verification and formatting,
   and have W10 measure all of K1–K9. Changes after the freeze invalidate the
   affected evidence.
6. **Delivery.** Commit the acceptance report, updated developer docs and
   `CLAUDE.md` sections (the full-gate paragraph, the caches section), and
   present the exact integration commit for the user to merge. Guardian changes
   are presented separately as a guardian-zig branch.

The ownership migration starts after R2, when K1 and K4 have their first
measured improvements; W02 and W09 hand their `driver.zig`, `run_budget.zig` and
`core_test.c` claims to the ownership owner at that point.

## Handoff format

Each worker commits `experiments/caching-closeout-20261013/WNN/handoff.md` with:
`C0` and the fixed implementation SHAs; owned files and patch requests; what
changed and the contracts it relies on; exact commands, exit statuses and logs;
before and after counts (actions executed and reused, tests executed and reused,
processes, bytes); timing only from W10's windows or marked as operational; and
open items, rejected alternatives and dependencies.

## Copy-and-paste instruction for the coordinator

```text
Use docs/audits/caching-closeout-10-agent-plan-2026-10-13.md as the execution
plan, with docs/audits/caching-closeout-plan-2026-10-13.md as its rationale.
Both are on branch claude/caching-closeout-plan-20261013 (local main
76180573b5c2cd8081cf8218e374166eb9677c44 plus the plan documents), checked out at
/home/epentland/ai/canopy/mylang-caching-closeout-plan-20261013; read them there
but do not work in that worktree. Pin C0 at that branch's tip. If local main has
moved past 76180573b, build C0 from current local main plus that branch's
documentation commits, and record C0's full SHA. origin/main is a separate
published snapshot; do not merge it. Run one coordinator and ten workers
W01–W10.

Give every worker its own worktree and branch from C0 and its assignment from
the plan. Enforce the ownership ledger: the coordinator alone edits build.zig,
build_test_inputs.zig, build_verification.zig, build_identity.zig,
guardian.toml, SPEC.md, CLAUDE.md and the development-loop docs;
verify_cache.py is claimed by function as listed. Only W01 changes
guardian-zig, on its own branch; never update the sibling guardian-zig checkout.

W10 publishes the K1–K9 baseline and the attribution of the 763 s compile-edit
gate before anything is integrated. Integrate fixed worker commits in rounds
R0–R4, running the complete verification once per round. Use shared admission
for builds and gates; run verify_cache.py directly; timing only in exclusive
windows. Do not clear shared caches or edit other sessions' worktrees.

Flip default sharing and install the two systemd user timers only in R4, after
the gate passes three times with the default stores. Report every K row as
passed, failed or not qualified with its measured value. Workers do not merge
main or push; nobody pushes. Coordinate driver.zig, run_budget.zig and
core_test.c with the ownership (memory-management) owner. Deliver the
integration commit, the acceptance report and the guardian-zig branch for the
user's review.
```

For a manually opened worker session, give it this plan, `C0`, its worktree and
the instruction: "Execute WNN only; follow its ownership and acceptance
contract; commit fixed SHAs and return the handoff."
