# selka — working rules

A statically checked language with Python-inspired indentation and explicit declarations. Zig compiler (`src/`) whose back end is
the new core (`src/core/`): the checked program becomes Core IR, then LLVM text, which
the pinned Zig toolchain's clang (`zig cc`) compiles and links with the core C runtime
(`src/core/runtime/`), amd64 Linux only. `selka run` builds the program and executes
it. There is no interpreter, no QBE, no bytecode and no garbage collector: memory is
checked ownership with direct destruction. Zig is the stable release `.zigversion`
names, 0.17.1 since GH-4 (19 November 2026): the gate, CI and native reuse want exactly
that release; the build itself accepts any 0.17 release from 0.17.1 on and panics on
anything else, development snapshots included.

Checked ownership is the only memory model. `--experimental-zero-rc` and
`--experimental-single-owner` exit 2 with a reference-counting removal message.

## Build

- `zig build` — compiles **and installs** `zig-out/bin/selka`, the one compiler
  (front end and new core; the separate core executable merged into it in S5). Run this after any
  `src/` change before using `zig-out/bin/selka`.
- `zig build test` — runs the full gate. Focused `test-core`, `test-units` and
  `test-cli` **do not install**. After a `src/` change, run plain `zig build` before
  using `zig-out/bin/selka` directly.
- `zig build test-compile` — type-checks every Zig test root without running anything.
- **Building and using selka needs no Python.** `zig build` (the install graph) and
  every command of the installed compiler run none; `USE-WITHOUT-PYTHON-1` in
  `test/integration.zig` runs the user commands under an empty `PATH`. Python is
  fine in `zig build test` drivers, developer scripts, `bench/`, `velocity/` and
  `experiments/`. Never wire a Python step into the install graph or spawn one from
  `src/`.
- Use `zig build -Doptimize=ReleaseFast --prefix /path/to/install` for a compiler
  installation used by application agents, or to time the compiler itself. Default
  `zig build` produces a Debug compiler: it parses, checks and plans more slowly, but
  the compiler's optimization mode does not choose the guest's build mode
  (`--release` does). `-Dcompiler-only=true` is accepted for older scripts and
  changes nothing.
- `scripts/build-slot.sh build|gate|timing …` admits a job only when a slot and enough memory are
  free. It matters on a machine that several builds share and is optional on a single-user laptop. A
  maintainer's machine-specific set-up (admission directory, shared caches, timers, evidence
  archive, worktree practice) lives in an untracked `CLAUDE.local.md`, which Claude Code loads
  beside this file.
- Never point two source trees (a base checkout and a worktree) at one
  `ZIG_LOCAL_CACHE_DIR`. Zig reuses the cached configure phase across them, and the
  project's absolute configure-time paths name the first tree.
- Guardian, the lint and gate tool that checked the compiler's Zig sources, was turned
  off on 18 November 2026 (GH-2): the build imports no sibling checkout, and no step
  and no commit hook runs it. `-Dgate-install=true` is accepted for older scripts and
  changes nothing.
- The two Selka components (`selfhost/components/`: the test index and the cache plan,
  installed in `libexec/selka/components`) are compiled by the compiler this `zig build`
  has just built (GH-3a, 19 November 2026). There is no seed compiler: a build needs no
  git history and no sibling checkout. A `src/` edit changes the compiler, so the next
  `zig build` compiles both components again (about 10 CPU-s with a Debug compiler).
  **For the inner loop of compiler edits use `zig build -Dcomponents=reference`:** it
  installs no component, and the compiler then answers with its built-in test index and
  cache plan (the reference the components are tested against) and says so in one line
  on standard error. It leaves out only the component path itself, which a plain
  `zig build`, `zig build test-components` and the gate cover. A folder that is present
  but wrong stays an error (`ComponentManifest`, `ComponentDigest`). A component's
  receipt is keyed by the compiler, the sources, the Zig distribution and the compiler's
  toolchain identity (`selka native show --digest`), so a changed system library makes
  a new receipt, never a "not reproducible" failure (GH-3f).
  `zig build affected-compiler` installs at `zig-out/focus/selka`; normal builds
  install at `zig-out/bin/selka`, using the configured cache and optimization.

## Measuring guest programs

Time a guest with a `--release` build: `selka build prog.selka -o prog --release`
emits the whole program as one optimized LLVM unit, while a plain build is the
debug edit-loop build (one unit per module; Core's facts passes; lean code generation: LLVM's IR
passes off except on units of at most 50,000 bytes, its code generation at `-O2`; `--debug-o0` gives LLVM `-O0`). Time the
binary, not `selka run`, or use `selka run prog.selka --release --timings`
(`timings: native_ns=N`, the build excluded). Build a ReleaseFast compiler only
to time the compiler itself or to hand a compiler to other agents. Timing runs
use `scripts/build-slot.sh timing …`, with any CPU pinning inside that command.
The parity, Juice runtime and debug-runtime developer harnesses own admission;
run them directly. Do not wrap a timing coordinator in a build/gate slot.

An edit build's cost is measured in CPU seconds (user + sys) with the machine calm, not in wall
seconds. A ReleaseFast compiler on the 99k and 400k ports (part 2, 4 November): a one-line edit
costs 0.26-0.42 CPU-s at 99k and 0.98-1.37 at 400k, a new-shape type edit 1.13 and 4.25, `check`
after an edit 0.13 and 0.51, an unchanged build replays in 0.01 s, and a fresh worktree's first edit
is 1.0-1.25x a warm one. A cold build (an empty work directory, the per-user object store warm)
costs 6.7 CPU-s at 99k and 26 at 400k, 0.52x and 0.73x of the 31 October compiler's. Comment edits
use a new line count each rep, and a type edit a new shape each rep, or an earlier build serves
them. Anything that measures or scripts builds points `XDG_CACHE_HOME`, `SELKA_CORE_RUNTIME_CACHE`
and `SELKA_STAGE_SHARED_CACHE` at its own directories; otherwise a build outside the test suites
writes the real per-user stores.

## Fast loops (use these while iterating)

- `python3 scripts/edit_check.py` — **the inner loop for compiler edits** (the edit check, `docs/audits/edit-check-plan-2026-10-25.md`).
  It builds the compiler, the three Zig test binaries and the impact tool through build slots, selects the tests the
  working tree's edit can affect (`zig-out/tools/edit-check-impact`), runs them by exact name (`--test-list`),
  and runs the `tests/lang` guest files the edit reaches (a map without a guest root runs them all). Its output is at most 20 lines and ends with "this is not the landing gate". **It is not the
  landing gate:** `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete` stays mandatory before landing.
  It needs a coverage map at or before `HEAD` in
  `~/.cache/selka/edit-check` (`SELKA_EDIT_CHECK_STORE` to choose another); without one it runs
  `scripts/affected_tests.py` instead. `--select-only` prints the selection and runs nothing.
  **The map's age:** the selection compares the map's commit with the working tree, so every change since that
  commit is impacted. An old map is still correct, only slower, and the wrapper prints its commit. A build input
  (`build.zig`, `build_test_inputs.zig`, `build_coverage.zig`, `build.zig.zon`, `.zigversion`) or a new Zig file under
  `src/` or `test/` reaches the tests of the files that import it (through their changed lines) and of the walkers of its
  directory; under `selfhost/` it selects every test, and `--new-files everything` selects every test for any new file
  (the G3 recall study measured `reach`: 24 killed mutants, no miss). A changed function the map does not list (one that runs only at compile
  time has no machine code) selects its whole file and its importers. A changed function that a compile-time item (a
  container-level `const` or `var`, a container's field defaults and member constants, a `comptime` block, a type
  builder) calls or evaluates (a bare alias is a rename, not a use) selects that item's file and its importers the same
  way; so does a compile-time call of a function that a change outside functions impacts. The search reads tokens:
  a struct's methods are run-time code, naming a type or listing a function in a table is no call, and an importer
  reaches a file-level function only through its binding of that file (`tools/impact.zig` header). Importers default to `reexport`: a change reaches an importer's importers only through
  an importer that re-exports it as a public value or `usingnamespace` (about +28 tests per edit over `direct`, which
  misses such a constant; `closure` follows every importer). A map without the `unrecorded` list (older maps) is refused,
  and the edit check says so and starts a refresh. **Refresh the map** after each landing:
  `python3 scripts/edit_check_refresh.py` starts a detached refresh of main and returns at once (`--status` shows it,
  `--once` runs it in the foreground). It works in the sibling worktree `mylang-map-refresh`, collects in short
  low-priority admissions that yield to gates and timing requests, and publishes the new map atomically; a map with a
  failed test is refused and the last good map stays. The edit check starts one too when main has no map and its map
  is more than five commits behind main, and its first line says so. `scripts/edit_check_map.py` remains the foreground
  collection of the current checkout's HEAD (it takes the build slots itself, and the map tool refuses a map with a
  failed test). Shadow mode,
  `python3 scripts/edit_check_shadow.py --gate-log PATH`, records whether a complete gate's failures were in the
  selection; it appends to `<store>/shadow.jsonl`. Measured on 59 mutant kills: recall 1.000, 95% lower bound 0.939;
  the 99.5% target is not shown at this sample size.
- `zig build --watch -fincremental` — a compiler edit loop that rebuilds after each saved change and
  updates `zig-out/bin/selka`; watch results are not gate evidence. An `-fincremental` build is not
  always the same program as a normal build: on 29 October a deep-recursion test overflowed the
  stack only under it (one more saved register per frame), so confirm a watch-only failure with a
  normal build.
- `zig build test-core -Dtest-filter=SUBSTRING` — the new core's tests
  (`src/core/root_test.zig`: unit tests plus the end-to-end slice under
  `test/core`) whose name contains SUBSTRING, in one process; unfiltered it runs
  in `-Dcore-shards=N` shards (default 8).
- `zig build test-tooling-units -Dtest-filter=SUBSTRING` — the independent pure
  tooling root (`src/tooling_root_test.zig`); no compiler or component artifacts.
  `python3 scripts/focused_test.py tooling SUBSTRING` wraps this target.
  An unfiltered `test-units` includes this root; filtered `test-units` selects
  only the compiler unit root, and a no-match filter still fails.
- `zig build test-units -Dtest-filter=SUBSTRING` — `src/root_test.zig` (front end,
  diagnostics, tooling, and programs run through `native_execute`, which builds
  them with `selka run`). `zig build test-cli -Dtest-filter=…` does the same for
  `test/integration.zig`. Neither runs Python drivers or the install
  graph. The filter also applies to `zig build test` and `test-compile`. An
  explicitly empty `-Dtest-filter=` is rejected at configure time, and a filter
  that names nothing fails rather than reporting green, so filter one root at a
  time. These two steps are never sharded. A different filter reuses the complete
  test binary: the test runner (`tools/test_runner/`) selects tests by name at run
  time.
- `zig build test-units-gate test-cli-gate test-core-gate` — the compiler suites as the
  sharded steps `zig build test` runs, with a cached verdict per shard (test binary,
  compiler, environment and declared inputs): about 110 s after a `src/` edit including
  the compile, none after a docs or `tests/lang` edit, and 8 s on an unchanged tree.
  They print no per-test counts; use `test-units`, `test-cli` and `test-core` (always
  run, and honouring `-Dtest-filter`) when you want those. `python3 scripts/patch_gate.py
  --parallel` runs them in one `zig build` with the other checks.
- `python3 scripts/focused_test.py units fmt` — the supported wrapper over the
  same targets (`units`, `cli`, `golden`). It rejects an empty filter, prints the
  selected-test count and verdict, saves the full output under
  `.selka-cache/focused-tests/` and exits with the wrapped command's status.
- `python3 scripts/affected_tests.py` — diffs against the merge-base with `main`
  (`--base REF` to choose), maps each changed file to the tests that most directly
  cover it and runs only those; `--dry-run` prints the selection. It says on every
  run that it is **not the gate**. Run it through the build slot.
- `zig-out/bin/selka test <entry.selka|dir> --filter SUBSTRING` — guest (`.selka`) tests, each built
  by the new core and run in its own forked trial. A bare substring matches anywhere in the
  qualified name; `*`, `?` or `[` make it a glob. A directory runs every entry under it in parallel
  (`--jobs N`, `SELKA_JOBS`). Results are reused per test by the incremental engine
  (`docs/tooling/engine.md`): a record of a pass is served when its argument matches, first under
  the test's Core IR key (`cache.reason` `engine-hit`), then, after a compiler edit, under the
  digest of the linked program (`engine-program-hit`, `--json` `exec_receipts`), and a whole entry
  whose files are unchanged replays its stored report (`engine-report-hit`), so an unchanged rerun
  is near-free and a comment edit under `src/` reruns only tests whose program bytes changed;
  `--force` reruns. A record is never served for a program or settings digest the run did not build:
  every argument is made from the current check and build (D-48). `SELKA_ENGINE_VERIFY=N` runs one
  served record in N anyway and removes a record whose test now fails. The compiler identity a
  record may depend on digests a Zig source by its tokens (`std.zig.Tokenizer`), not its bytes, so a
  comment, a doc comment or a change of layout keeps every record, replay record and stage pack,
  `function_digest` ones included; any other file (the C runtime, the embedded `.selka` standard
  library) is digested by its bytes, and so is each build product `build.zig` embeds in the compiler
  (the number-text object), so a build setting moves the identity exactly when it changes those
  bytes. The integration gate's forced run (`verify_cache.py --integration`) reruns the language
  suites' debug members, which carry `--verify-facts` and `SELKA_CORE_LEAKCHECK=1`, with `--force`
  in a private cache; ordinary requests reuse their records.
- `zig build test-lang` — `tests/lang`, `tests/value_semantics` and `tests/ported`
  through `selka test`, at optimized debug with the leak check (`SELKA_CORE_LEAKCHECK=1`) and the
  facts verified (`--verify-facts`). Release builds are not tested for now, by the user's decision of 28 October 2026.
  To bring them back, `zig build test-lang -Dtest-release=true` adds each suite's release pass, and every Zig test's
  release build runs too (see the `-Dtest-release` bullet below). To run one release pass by hand:
  `SELKA_CORE_LEAKCHECK=1 zig-out/bin/selka test tests/lang --release --verify-facts --cache-dir .selka-cache/lang-tests-release`.
  Broad `--unoptimized` sweeps are deferred; targeted unoptimized compiler checks remain required. See
  `docs/tooling/test-layout.md` for the test matrix.
- `-Dtest-release=true` — the release-mode halves of the tests: the language suites' release passes (`test-lang`,
  and `ownership-proof` with their release certificates when `-Dproofs=true` is given too) and each Zig test's release
  build. Default `false`: the gate tests
  debug builds only, and a test whose release half is skipped is reported as skipped, never as passed. A test whose
  debug assertions follow a release use is skipped at that use (the list is in `docs/tooling/test-layout.md`).
- `-Dproofs=true` — the four Lean proof actions (`ownership-proof` with its facts half, `verify-ir-proof`, `arith-proof`,
  `cache-proof`), which need the Lean build tool `lake` (`SELKA_LAKE`, else `$HOME/.elan/bin/lake`). Default `false`
  (GH-3c, 19 November 2026): each of their steps prints one line that it was SKIPPED and exits 0, and nothing looks for
  `lake`, so `zig build test` needs no Lean. The build summary still counts such a step as a success; the printed line
  is the report. The coordinator (`scripts/verify_cache.py`) always passes `-Dproofs=true` and refuses an inventory
  exported without it, so the complete gate runs the proofs as before and fails when `lake` is missing.
- `zig build test-docs` — executes every fenced documentation example.
- `zig-out/bin/selka doc-coverage .` — checks the feature/doc contract (below).
- Developer commands: `selka dump-ir FILE.selka [--facts]`, `selka dump-typed
  FILE.selka`, `selka coverage FILE.selka`, and `selka build … --stats`,
  `--emit-llvm PATH`, `--cache-report`, `--verify-cache`.

## Where tests live

Language behaviour is tested in the language: a `public func test_*() -> bool` in
`tests/lang/<area>.selka`, run by `selka test` (`zig build test-lang`). The new core's
own tests (IR, passes, emission, driver, caches, test runner) are Zig tests under
`src/core/` with fixtures in `test/core`. Diagnostics, traps, host fixtures, caches,
formatting and allocation-failure tests are Zig tests in `src/root_test.zig`; CLI
behaviour is `test/integration.zig`. Write new guest-behaviour tests on the selka
side; the rule and the backlog of Zig tests still to move are in
`docs/tooling/test-layout.md`.

## Full gate (run before finishing)

The gate is **one command** (`$ZIG` is the Zig 0.17.1 executable that `.zigversion` names):

```
python3 scripts/verify_cache.py --zig "$ZIG" --profile complete
```

It runs everything `zig build test` runs, plus `fmt-check`, from the verification
inventory. It owns build/gate admission and checks reusable evidence before
requesting a shared slot, so never wrap it in `build-slot.sh`, and do not run
`zig build test` first: the coordinator forces its selected actions and reuses
its own receipts, so a preceding plain gate adds a full duplicate run.

Its terminal output is bounded: green prints at most 30 lines (verdict, elapsed
time, actions reused and executed, the slowest three actions, the log path); a
red run prints at most 60 lines plus 10 per further failure, naming each failing
action, its failing test names, the first `file:line` diagnostics and any
`test deadline:` line. The complete build stream is kept under
`.selka-cache/verification-v3/last-logs/`; `--verbose` streams it live, and
`python3 scripts/gate_summary.py PATH` prints the same summary for a log someone
already has (a reader, never a second gate).

`zig build test --summary all` and `zig build fmt-check` stay supported for
people and remain the underlying actions.

`python3 scripts/verify_cache.py --zig /path/to/pinned/zig` is the complete
inventory-based verification entry point. See `docs/tooling/many-agents.md` for
its freshness boundaries, force controls, normalized fixture environment and
evidence reports. Deadlines (below, `docs/tooling/runtime-budgets.md#deadlines`)
bound a hang at every level: one test (300 s), one build step (30 min) and one
coordinator gate (90 min, build 20 min); each defaults on and `0` turns it off.

`verify_cache.py --verify` rehashes every input while allowing valid action
receipts to be reused. `--force` also reruns the selected actions. Ordinary
requests may reuse a per-worktree digest only when the full recorded stat tuple
matches and its timestamps are outside the conservative racy-write window;
live mutation guards still protect execution and receipt publication.

`zig build test` runs `test-core`, the sharded `src/root_test.zig` and
`test/integration.zig` roots, `test-lang`, `test-guest`, `selka doc-coverage .`,
`selka doctest .`, the test runner's own tests (`test-test-runner`) and the tooling
drivers, all on the new core. The QBE-era steps
(`test-qbe`, `test-qbe-build`, the native C-runtime harnesses, the host-application
roots) are gone with the old back end.

Standalone programs no other group builds (`bench/`, `benchmarks/`, `examples/`,
`src/stdlib`, `selfhost/components`) are type-checked by `test-program-check`, with no
exclusions. The removed-form audit, the ownership corpora and the cleanup and
ownership-audit tooling groups (`removed_forms_audit`, `ownership_corpus`,
`cleanup_tooling`, `embedded_migration`) were retired on 2026-10-18 after the gate
profile found them at 72% of its CPU and the audit alone at about an hour; the
compiler's `E_*_REMOVED` rejections, `selka fix` and `test-migrate-embedded` remain.
See `docs/tooling/many-agents.md#what-the-complete-verification-contains`.

Test verdicts are cached like build outputs (the focused `test-units`, `test-cli` and
`test-core` steps always run; the shards of `zig build test` and of the `*-gate` steps
are cached). A
test shard, a Python driver or the
doctest re-runs only when its test binary, the compiler it runs, its command,
the live environment (recorded as a digest), or one of the repository files it
reads changes; those files are declared per step in
`build_test_inputs.zig`, and `zig build test` fails (`test-inputs-coverage`) when a
test names a repository path its step does not declare. An unchanged `zig build test`
reruns none of the compiler shards. An unchanged complete verification through the
coordinator reused all 41 cacheable actions without build or gate admission in
five R3 samples on 13 October: median 18.356 s, range 17.863–19.702 s. This
still exceeds the 10 s target. R3 compiler-edit verification failed its target
(one green 337.033 s sample and one failed 393.024 s sample); the earlier R2
243.593 s all-green median is not the final candidate's timing. See
`experiments/caching-closeout-20261013/status.md` and the closing acceptance
evidence for the exact source, final measurements and open criteria. Every gate root
depends on `zig build test-verification-registry`, which fails while any required
action is unregistered (`coverage.unknown_actions` in
`zig-out/verification/inventory.json` names it), because an unregistered action
sends every request to the original complete gate, the slow path the registry
exists to avoid. A `.selka` or doc edit re-runs only what reads it,
and any `src/` edit reruns every step that runs the compiler. A cached step
prints no test count, so the `Build Summary` total counts only what ran:
`-Dtest-rerun=true` re-runs every test step (full counts, or to rule out a stale
verdict you suspect). When a test starts reading a new fixture, declare it in
`build_test_inputs.zig`. Test steps always run in the live environment of the
`zig build` that runs them: never call `Step.Run.setEnvironmentVariable` in
`build.zig` (a cached configuration freezes the whole environment it copies, and
the build refuses to configure); pass variables through `withTools`. That live
environment is projected: `withTools` runs every command through `build-env
project`, so a test sees only the variables `src/environment_identity.zon` keys
or marks as placement, and the environment manifest keys exactly the keyed and
host ones (`docs/tooling/environment-identity.md#in-the-build-graph`). Test
binaries get the compiler through `SELKA_TEST_COMPILER` and fixture paths
relative to the build root, never an absolute path.

`zig build test` splits its slow Zig roots across processes: `src/core/root_test.zig`
into `-Dcore-shards=N` shards (default 8), `src/root_test.zig` into
`-Dtest-shards=N` shards (default 12) and `test/integration.zig` into `N/2`, each
one run of the same test binary under the test runner's `--test-shard=K/N` with its own
`max_rss`, so the shards run concurrently and print one `test wall` and one verdict
each. They partition the root — every test runs exactly once, and the shards' selected
counts sum to the unsharded count. `-Dtest-shards=1` restores one process per root, and
`-Dtest-filter=…` falls back to it automatically. See `docs/tooling/runtime-budgets.md`.

## Memory ceilings (why a runaway guest no longer kills the machine)

Every `selka run` and every `selka test` child runs under a byte ceiling: the
runtime counts its chunks and large blocks and traps `R_MEMORY_BUDGET` past it,
and lowers its own `RLIMIT_AS` to the ceiling plus 256 MiB. Precedence:
`--max-memory=SIZE` on `run`, `build --run` and `test`, then `SELKA_MEMORY_LIMIT`
(bytes, `K`/`M`/`G` suffixes), then `limits` in `selka.json`, then the defaults of
4 GiB for a run and 512 MiB per test child; `0` removes it. A binary from
`selka build -o` takes its ceiling from `--max-memory=SIZE` in `SELKA_OPTIONS`, else
`SELKA_MEMORY_LIMIT`, and has none when neither is set. Steps and frames: a run is unbounded unless
`--max-steps`/`--max-frames` is given (compiled into `main`; a frame reserves 32 KiB
of stack under the ceiling); a test defaults to 1,000,000 steps, 1,024 frames and
`--timeout-ms 60000`. The compiler caps itself at 8 GiB
(`SELKA_HOST_MEMORY_LIMIT`), and `selka test <dir>` fans out to `--jobs`,
`SELKA_JOBS` or the CPU count (not to free memory). Build steps declare `max_rss`
reservations, but the pinned Zig Maker's resumed-job accounting does not reliably
enforce their aggregate budget. `zig build --maxrss N` is therefore not a proven
whole-gate memory ceiling. See `docs/tooling/runtime-budgets.md` for the measured
limits and the distinction between reservations and process ceilings.

## Caches and worktrees (the disk fills up)

- Never share `.zig-cache` (`ZIG_LOCAL_CACHE_DIR`) between worktrees. Zig would allow
  it; the project's own absolute configure-time path (the build root realpath that
  `build_identity.zig` passes) ties it to one tree.
  Never share a `.selka-cache` between worktrees running
  different compilers: each compiler generation evicts the others' objects.
- **Evidence stays out of git.** Commit a run's write-ups and the small sources that reproduce it;
  keep logs, receipts, JSON or CSV data, captured outputs, archives and binaries out of the
  repository and cite where they are. `.gitignore` refuses data files under `experiments/`; never
  force-add them. See `experiments/README.md`.
- Builds keep content-keyed unit, runtime and number-text objects in one per-user store
  (`SELKA_CORE_RUNTIME_CACHE`, else `~/.cache/selka/core-runtime`) shared safely by every worktree,
  and linked programs, replay records, front-end caches and test records and replayable reports in
  the work directory (`--cache-dir`, default `.selka-cache/core`). Every `zig` process a build
  starts gets a private `ZIG_LOCAL_CACHE_DIR` in a staging directory removed when the build ends, so
  guest builds add nothing to `.zig-cache`. See `docs/tooling/native-build.md#the-caches`.
- Shared verification evidence, compiler artifacts (`SELKA_COMPILER_SHARED_CACHE`,
  namespace `compiler-artifacts-v2`) and the engine's shared test records
  (`SELKA_TEST_SHARED_CACHE`, `native-tests-v3`) default to their per-user stores
  after R4 qualification. Their locations are `~/.cache/selka/verification-shared`,
  `compiler-artifacts` and `native-tests` (under an absolute `XDG_CACHE_HOME` instead
  when set). A named variable selects another store; an empty value disables it. The complete gate is the exception
  (lane GATE3): its builds get empty compiler and test stores of the request's own
  (`.selka-cache/verification-v3/gate-stores`, removed when it ends; `--own-stores off` restores the per-user ones),
  a mismatch they log fails the request with status 5, and a build of the request that opened a per-user store fails
  it with status 6. A determinism mismatch is a miss, counted as `shared_mismatches` in
  `--report` and logged to the namespace's `mismatches.log`. Both stores use
  process leases and automatic LRU retention every 30 minutes, which runs beside builders
  when they hold the store (10 GiB compiler, 256 MiB tests, 100,000 entries each). Use `selka cache gc` to preview,
  `--apply` to collect, and `selka cache configure` to persist policy. Old v1
  namespaces remain separate and require idle-only manual cleanup. See
  `docs/tooling/cache-retention.md#native-cache-retention`.
- The stage store's shared half is on by default, so a fresh worktree's first edit build
  reuses the stages other worktrees built: `~/.cache/selka/stage-artifacts` (under an
  absolute `XDG_CACHE_HOME` instead when set), 4 GiB, `selka cache gc|configure --kind
  stages`; an empty `SELKA_STAGE_SHARED_CACHE` disables it. The build graph's `build-env
  project` and the verification coordinator give every test and driver an empty one unless
  the caller names a store, and a request whose own builds wrote the default store fails
  (status 6). A test about the default or about sharing sets its own variable.

## Conventions that no tool checks (Guardian is off)

Guardian was turned off on 18 November 2026 (GH-2). Its test runner stays as two files,
`tools/test_runner/` (MIT, copied from guardian-zig; the header of each file says what the
rename changed): the `--test-*` flags, the `SELKA_TEST_*` variables and the `test:` output lines
are this repository's names for Guardian's flags, variables and output lines (the headers list the
old ones). `scripts/precommit.sh` prints one line and exits 0, and there is no
`guardian.toml`, no `.guardian/` and no commit hook. What Guardian enforced stays as
conventions; a review may ask for them, but no build, test or gate fails on them.

- **A behavioral change ships with a test change** in the same diff.
  `SPEC.md` is frozen history since 19 October 2026: no new bullet and no `// spec:` tag
  is needed.
- **Structs: at most 7 fields. Functions: at most 6 parameters.** Group into a struct.
- **`///` doc comment on every `pub` declaration** (fn, type, const). Say what it does,
  not that it exists.
- **No `@import` cycles**, and every new `src/*.zig` file is reachable from a test root.
- **No RNG** outside the sanctioned module; no wall clock, no hardcoded absolute paths.
- **Do not widen a struct without a reason.** The type-size ratchet and its recorded
  sizes went with Guardian.
- **Tests need at least one `expect*` assertion** and **no `if`/`while`/`switch` or extra
  `for` at the top level of a test body**. Write straight-line assertions.

## Breaking changes land with their `selka fix` migration

A change that turns previously accepted code into a diagnostic must carry the
repair as a structured `fix` on that diagnostic (`diagnostic.Fix`, rendered as
`diagnostic-v1` `fix.edits`) wherever the edit is certain, so `selka fix` moves
a project across it with no hand edits — no per-change script under `scripts/`.
Add a pre-change corpus under `test/fixtures/fix-migration/` with a test beside
`FIX-MIGRATION-1` (`test/fix_cli_test.zig`) proving `selka fix` migrates it to a
clean check. See `docs/tooling/fix.md`. `selka fix FILE` repairs errors only; a folder, or `--warnings`, repairs warnings too.
`selka fix` leaves a file whose first line says
`# generated by` alone unless that file is named on the command line (change the generator instead), and
`selka --version` prints the commit from `selka.commit` beside the binary, never from inside the compiler.

## Merging `SPEC.md` (run once per clone)

`SPEC.md` is frozen (see the conventions above), so this matters only for the rare
edit to it or for merging branches that predate the freeze.

```
sh scripts/setup-git.sh
```

It registers the `spec-bullets` merge driver that `.gitattributes` names for `SPEC.md`
(`scripts/merge_spec.py`) in the clone's shared `.git/config`, so every worktree gets it.
The driver merges bullets by tag: both sides' appends to one section are kept (ours,
then theirs), a bullet amended on one side keeps only the new text, and only a tag both
sides changed differently, or prose both sides edited, is left as a conflict. Without the
setup git ignores the attribute and falls back to its plain line merge, where parallel
appends conflict and a hand union can repeat an amended tag.
Tests: `zig build test-spec-merge`.

## Documentation gate

Every feature slug in `src/features.json` needs `{kind, summary, doc}` and the `doc`
anchor must resolve to a real section containing a runnable example. Language features
use a ```selka block; `kind: "tooling"` features may use a ```bash or ```console block.
`selka doc-coverage .` tells you exactly which slug is missing what.

## Where the language differs from Python

- **Locals have lexical block scope.** Declare immutable values with `const` and
  writable values with `mut`. A typed `const` may omit its initializer when every
  path reaching a read assigns it exactly once; later writes require `mut`.
  A declaration disappears at its block's end, and an active name cannot be shadowed.
  Declare a typed result before an `if` or loop when later code needs it.
  Loop variables and match payloads are readonly bindings scoped to their bodies, except that
  `for x in own xs:` consumes an owned list (a local, an `own` parameter, or the list a call returns:
  `for x in own rows():`) and `x` owns each element, and `match own name:` consumes an
  owned local so its bindings own their payloads. `take(mut place)` and `exchange(mut place, value)` reach
  locals, fields, list elements and `match mut` bindings; `take` leaves the type's default (an empty
  collection, `None`, or a record built from its field defaults).
  Ordinary copyable managed arguments borrow readonly for the call; scalar inputs
  are values, and a move-only argument (a resource) needs a parameter spelled `own`
  or `mut`: a plain parameter of a move-only type is refused with `E_OWN_PARAMETER`. A plain parameter of a `@linear`
  record borrows it read-only for the call; only `own` consumes it, and the same call cannot also pass that owner `own`
  or `mut`. A `mut`
  parameter updates caller storage, including scalar rebinding and nested fields or elements; a `mut` resource is an exclusive borrow. An `own` parameter takes its
  argument, spelling the marker at the call (`f(own value)`), so the caller's binding is unusable after the line and the callee stores or returns it without a copy.
  Every move of a named managed value needs `own`, including bindings, stores and
  constructors: `mut next = own value`, `Row(items=own items)`, `Some(own items)`.
  A bare `return value` or `fail value` needs no marker; `return own value` and
  `fail own value` are refused. A managed field still needs `own record.field`,
  consuming its record, and named constructor inputs still need their markers.
  Fresh values and scalars never take `own`; missing or misplaced markers report
  `E_OWN_MARKER`. For managed places, `const alias = place` always borrows read-only,
  even from a local or `own` parameter, and holds the place rather than the whole record (`const item = self.items[i]` leaves
  `self.links` writable while `item` is live); write `const alias = own owner` to transfer a bare owner,
  or `copy(place)` for independent storage. An element of a new list or dictionary (`rows()[i]`, where the
  call's result is not lent `from` an argument, or a list literal's) moves out when it is bound, stored,
  returned or passed `own`, and needs no `copy`. So does `CALL().unwrap_or(d)` when the call's result is not
  lent `from` an argument and `d` is a literal, a new value or `own name`; on an option a local holds,
  `options.take_or(own o, d)` moves the value. Borrowed returns keep their declared
  `from` contracts.
  Spell arrays `T[]`, options `T?`, fixed arrays `FixedArray[T, N]`, and unit `Unit`.
  A fallible function declares `-> T fails E`; extract a checked result with boundary
  `try`, or return its error with `fail`. `with arena():` remains retired.
- **`match mut <place>:` writes into the place it matches.** A payload binding is a name for its element's
  payload: reads and writes project through the place, the container is held until the arm's last use of a binding,
  and a binding cannot be moved or stored. A call result or temporary is refused (`E_MATCH_MUT`); a dictionary element
  is refused until its exchange lands. Two bindings of one arm, or of nested arms, are disjoint `mut` arguments of
  one call (`put(mut keys, mut vals)`), unless the matched place lies inside a list element.
  See `docs/match-expressions.md#mutable-element-matches`.
- **Use statements and named callbacks.** Build collections with explicit `for`/`if`
  loops and append, dictionary assignment, `sets.add(mut s, own v)` (takes the
  value) or `sets.include(mut s, v)` (borrows it, copies only a new one). There
  is no `s.add(...)` method. `range(...)` is a loop
  source, and `list(range(...))` collects its values. Lambdas, conditional
  expressions, value-producing match/yield expressions, comprehensions and generator
  expressions are retired. Use typed top-level functions, `if`/`else` assignments,
  and match statements whose arms assign a result or return.
  Unwrap an option or a result without a `match`: `const x = f() else:` with a block that leaves (`else Err(e):`
  for a result), or `if f() is Some(x):` when the other case does nothing; `check --warnings` names a `match`
  written the long way (`W_MATCH_ELSE`, `W_MATCH_IS`) and `selka fix` rewrites it. After `if x is None: return` (or
  `fail`, `break`, `continue`) a read of `x` is its payload, and `own x` moves that payload out of an owned local or
  `own` parameter with no copy, consuming the option (a bare `return x` does the same).
- **`func main() -> int`'s value is the process exit status**, truncated to the low 8
  bits (POSIX `status = value & 0xFF`), for `selka run`, `run-project` and a native
  executable — the way Python and Go return an exit code. `--print-result` still prints
  the value to stdout and is orthogonal to the status. A runtime trap outranks the
  return and exits 1; source/check errors exit 1, usage/host failures exit 2.
- **No tuples. No methods on classes. No closures.** Records are values; functions are
  top-level and take their state as parameters.
- **Operations are functions, not methods.** `x.name(...)` means `x` is a module, a capability, a handle or an
  option (`maybe.unwrap_or(d)`): write `strings.join(parts, ", ")`, `strings.encode(text)`, `bytes.find(b, x)`,
  `sets.remove(mut s, v)`, `fs.exists(p)` and the bare `round`, `sqrt`, `min`. The method forms on text, bytes,
  lists, sets and buffers and the second spellings (`math.sqrt`, a bare `unwrap_or(x, d)`, `exists(fs, p)`) are
  refused (`E_METHOD_REMOVED`, `E_REMOVED_SPELLING`), each with the rewrite `selka fix` applies; a module function
  needs its `import`, and `E_MODULE_NOT_IMPORTED` adds it. The standard library (`src/stdlib`) is written the same way and keeps no waiver; a library
  function whose body would be the method it replaces is a `builtin func`.
- **Managed collections have checked owners.** Assignment and stores transfer
  named lists, dictionaries, sets, byte buffers and managed aggregates with `own`;
  a bare owned return or fail transfers without a marker. `own record.field` consumes
  the whole record and destroys its remaining fields at that point. One statement may
  move several fields of one owned record (an `own` parameter, a local, a `match own`
  or `own x else:` payload, a `for x in own xs:` element), each field once:
  `total(own p.lo, own p.hi)`. The record is consumed at the first move and the fields no
  move names are destroyed there; a read of it after that, or a move in another
  statement, after `and`/`or`, in a branch or inside `append`, stays refused.
  Copyable managed ordinary arguments borrow; `copy(value)` creates independent
  storage. A move-only argument needs an `own` or `mut` parameter. A helper
  updates caller storage through a `mut` parameter and a marked argument.
  Use records and recursive unions for finite trees, and pool handles for graph
  identity. `class` and builtin `Cell` are rejected. See `docs/value-semantics.md`.
- **Memory uses checked ownership.** Live borrows prevent invalidating their
  owners, and an owner is destroyed directly when its lifetime ends. There is no
  collector or runtime memory-model choice. See `docs/managed-memory.md`.
- **File access needs a capability parameter on the entry point.** Write
  `func main(fs: Filesystem) -> int` and thread `fs` through; there is no ambient
  filesystem. `Network`, `Clock`, `Entropy`, `Environment` and `Process` (start a program and read its output, `--allow-process`) work the same way.
  So does `Stop` (no grant): a `main` that declares `stop: Stop` hears SIGTERM and Ctrl-C as
  `process.stop_requested(stop)` and ends itself, and a second signal ends it (the same signal from the same sender
  within half a second counts as the same stop); a program that does not declare it dies of the signal as before.
  `net.host("IP:PORT")` narrows a `Network` and takes only a literal; an address known at run time goes to
  `network.connect_to(net, address)`, `listen_at`, `open_poller_at` or `dial_to` (and the `_within_to` forms),
  checked against `--allow-endpoint` and `--allow-listen` under `--restrict`. The raw `acquire_resource` on a
  `Network` is refused outside the standard library (`E_INTERNAL_NAME`).
  A capability is a shareable handle, like `Stream`: copy it, store it in any record, list, dictionary or option
  and return it, with no `own` (copies share one provider; an `own` marker on one is
  `W_CAPABILITY_OWN`, and `mut` on a parameter the body never rebinds is `W_CAPABILITY_MUT`; `selka fix` removes
  both). A `parallel` task takes none (below). See `docs/io.md#records-that-hold-capabilities`.
- **Printing goes through a `Stream` parameter.** Write `func main(out: Stream) -> int`
  and call `print(out, ...)`; `err: Stream` is standard error. The runtime supplies both
  streams, so printing itself needs no host grant. Pass the stream explicitly to
  helpers that print. Source `effects(...)`, `noio` and trailing `noalloc` are
  retired; a violated `@noalloc` promise is a build/run/test error in Core. Bare `print(...)` is rejected with
  `E_OUTPUT_CAPABILITY`. See `docs/io.md`.
- **`selka run` grants every capability** unless you pass `--restrict` — it builds the
  program natively and runs it in a child process. A binary from `selka build` grants
  every capability too and hands `main` its argv unchanged; runtime options such as
  `--restrict`, `--allow-*` and `--print-result` go in the `SELKA_OPTIONS`
  environment variable instead (`SELKA_OPTIONS=--restrict ./prog`).
- **C interop is `extern func` plus `--link FILE.c`.** Scalar arguments only, `host:
  Host` first. `host func`, `selka invoke` and the host applications are retired.
- **Text literals take either quote, and format strings exist.** `'he said "hi"'` and
  `f'{name}="{value}"'` need no escaped quotes; a hole holds one expression. A
  triple-quoted string, plain or `f"""..."""`, spans lines and keeps every byte between its quotes (nothing is
  dedented); in a format string each hole closes on the line it opens, `{{` is a literal brace, and the literal ends
  at the first three unescaped quotes of its kind (`docs/text.md#triple-quoted-text`).
  `str(x)` and `repr(x)` of a list, set, dictionary, option, record, result or fixed array give the text `print`
  writes for it, and so does a format string's hole, so no join helper is needed to report a collection. A value
  that holds a function or a capability has no text: `print`, `str` and a hole refuse it at check time. The
  message of an `assert` is any text expression (`assert ok, "failed for: " + item`).
  See `docs/text.md#format-strings`.
- Integers have fixed width, conditions must be `bool`, lists are homogeneous, ranges
  take one to three arguments. A slice is contiguous: stepped slices are refused, and
  `strings.char_stride`, `lists.stride` are the stepped copies. `str` is bytes:
  `len(text)`, `text[i]` and `text[a:b]` read octets, and the `strings.char_*`
  helpers read scalars. A slice that ends inside a character traps (`R_TEXT_BOUNDARY`): cut a text to a width
  with `strings.cut_octets(text, n)`, which ends at a character, and `selka lint` reports a text slice whose
  bound is a constant (`L_TEXT_SLICE_OCTETS`).

- **Concurrency is structured.** `with parallel.group() as g:` (`g.submit(fn, ARGS)`, `t.result()`) and
  `parallel.map(values, fn, ARGS)` run tasks on one thread pool and join before they return. Tasks borrow their
  arguments read-only (a managed one is lent, not copied, a slice or a plain text, bytes or list parameter
  included), and `mut` arguments are refused. A task takes no capability
  (`Stream` included) and no record, list, dictionary, option or union that holds one (`E_TASK_CAPABILITY`): it
  computes and returns, and the caller reads before the group and writes after it. `--threads N` sets the pool. See
  `docs/concurrency.md`.
Details: `docs/python-syntax.md`, `docs/io.md`, `docs/effects.md`, `docs/statements.md`.

## Native builds

`selka build prog.selka -o prog` checks the program, builds Core IR, emits LLVM and
drives `zig cc` and the link itself — no Python. A plain build of `build`, `run`, `build --run`
and `run-project` is the lean debug build (one LLVM unit per source module, Core's facts passes, then
`zig cc -O2 -Xclang -disable-llvm-passes` plus seven `-mllvm` switches (six turn machine passes off, `-enable-ipra`
turns interprocedural register allocation on): no LLVM IR pass, code generation at
`-O2`; a unit of at most 50,000 bytes of LLVM text is compiled without `-Xclang -disable-llvm-passes`, so LLVM's `-O2` IR
passes run on it (`build_mode.lean_passes_cap`; no option, `--debug-o0` is the way back); an edit recompiles only the
units whose text changed). `--debug-o0` is the same Core passes with
LLVM `-O0` (the cheapest cold build; programs run 1.4 to 2.1 times as long), and `selka test` builds that
way by default (`--debug-lean` asks it for the lean build). `--optimize-debug` is the same with LLVM `-O2`,
and `--unoptimized` runs no Core pass. `--release` asks for the optimized whole program (one
LLVM unit; any edit recompiles it all), so iterate in debug and ship or time
`--release`. Unit objects are content-keyed in the per-user store; an unchanged build
replays its last identical build without checking or starting a process.
`--report` prints one `cache-report-v1` JSON line (units linked, reused, compiled,
verified; program `linked`, `reused` or `replayed`), `--cache-report` the same as
text, `--stats` what the release passes and the ownership plan did, and
`--verify-cache` recompiles every served unit and fails on a byte difference.
`--no-cache` builds through an empty private cache. The old back end's commands and
flags (`emit-qbe`, `dump-bytecode`, `invoke`, `compile-module`, `--backend`, `--lto`,
`--gc-runtime`, `--library`, …) are refused with a one-line reason. See
`docs/tooling/native-build.md` and `docs/tooling/guest-tests.md`.

- **The engine decides part of every build.** `module-check` records decide each module's prepared keys
  and key each lowered function by its `body:` part, `ownership-proof` records decide which functions are
  proven, and the four test kinds decide what `selka test` reuses. A test entry's stored report also reads
  its sources through `module-tokens` (the lexer's tokens without comments, blank lines or line numbers),
  so a comment edit or a line shift replays it; `SELKA_TEST_TOKEN_REPORTS=0` reads bytes only. The other compiler kinds
  (`project-graph`, `noalloc-closure`, `module-passes`, `program-diagnostics`, `unit-lower`,
  `program-facts`, `unit-optimize`, `unit-emit`) are observed only, under
  `SELKA_ENGINE_SHADOW_COMPILER=1` with `SELKA_ENGINE_DECIDE_COMPILER=0`. Lowering, the optimizer and
  emission are served by the stage store, local and shared. Moving them into the engine and deleting the
  stage store (G4d) is deferred, so `stage_store.zig`, `stage_pack.zig`, `stage_scopes.zig`,
  `stage_roots.zig` and `optimizer_shortcut.zig` are live code, not dead code. `selka engine
  kinds|closure|explain|query` show what the engine holds, and `selka test --engine-report` prints its
  counters (`build`, `run` and `check` refuse that flag). `SELKA_ENGINE_VERIFY=N` recomputes one served
  query in N, and a mismatch is `E_ENGINE_VERIFY` (exit 2). `SELKA_ENGINE_*` variables are placement:
  never export one in the shell tests run from. `build`, `run`, `test` and every project `check` read
  the merged program lazily (`SELKA_LAZY_SYNTAX=0` reads it whole), and `check` runs on `Session` like a
  build. See `docs/tooling/engine.md`.

- **Every compiler validates certificates.** `build`, `run`, `build --run`, `run-project` and `test` run the IR
  verifier and the ownership validator on every guest build. They also run the fact validator on every build that
  computed facts (`--release`; a debug build defers them). A demand build keeps its demand bodies and reuses a
  stored body only when the build that made it validated it. On the 99k port this costs a one-line edit 1.9% more
  instructions, a cold build 4.4% and a `--release` build 0.4% (11 November). A Debug compiler also validates
  every build with every body present. A rejection is an internal error (`E_OWNERSHIP_VALIDATION`,
  `E_FACT_VALIDATION`, exit 2), not a program diagnostic; its note names the way out, `--no-validate`, which also
  keeps the build's records out of the shared stage store. The complete gate adds `ownership-proof` (with its facts
  half), `arith-proof`, `verify-ir-proof` (the Zig IR verifier against its Lean copy) and `cache-proof`; these four
  need Lean and run only with `-Dproofs=true`, which the coordinator passes and a plain `zig build test` does not; see
  `docs/tooling/native-build.md#certificate-validators`.

- **System libraries key the caches; no machine is approved** (GH-3b, 19 November 2026). The toolchain digest in every
  native cache key holds the bytes of every file the loader could load for libc, libm, libgcc_s and libpthread: the
  loader, each `/etc/ld.so.cache` entry of those names, their candidates in the loader's default directories, and the
  files `/etc/ld.so.preload` names. So a machine reuses its own results with no step by anyone, and a library update is
  one cold cache. A file the user cannot read is keyed as unreadable, never an error. Reuse is off only for an `LD_*`
  variable, a Zig that is not the official 0.17.1 distribution (a later 0.17 release builds the compiler but its
  programs are not reused until its digests are in `src/core/tool_identity.zig`), a preload entry that cannot be resolved (a relative path, an unknown `$`
  token) or a loader cache or preload file over 64 MiB; `selka native show` prints the files, the digest and every
  reason reuse is off. `selka native approve` prints that it is no longer needed and exits 0;
  `~/.config/selka/native-approvals` and `SELKA_NATIVE_APPROVALS` are read by nothing. The saved list of files to
  hash (the inventory hint) is keyed by every constant of `src/core/native_closure.zig`; **when you change what
  `resolve`, `gather` or `locate` list without changing a constant, bump `rules_version` there**, or compilers trust a
  list an older compiler saved (that happened on 19 November: GH-3f). See
  `docs/tooling/native-build.md#system-libraries`.
