# Making mylang's own test loop faster — 2026-09-23

Branch `devloop/test-loop`, from `main` at `e54d1bd7`, with `main` merged in at
`4e332f70` and `d18304c1`. It asks where `zig build test` spends its time, makes
unchanged and small-change reruns cheap without removing anything from the gate,
and adds an affected-test command for the inner loop. Scripts and raw numbers:
[`experiments/test-loop-speed-20260923/`](../../experiments/test-loop-speed-20260923/).

## Headline

All runs used the Debug compiler, a private Zig cache and the machine-wide gate
slot. The machine was never quiet: other agents kept the 1-minute load between 2
and 25 on 20 threads, and the load is given for every run in the measurements
file. Treat single numbers as ±20 %.

| case | before (`e54d1bd7`) | after | load (1 min), before → after |
|---|---:|---:|---|
| (a) clean cache, `zig build test` | 253 s | 182 s | 1.5–14 → 10–21 |
| (b) nothing changed since the last run | 125 s | **4.7–5.7 s** | 9–11 → 8–20 |
| (c) one-line edit, `src/sema.zig` | 135 s | 114 s | 2–6 → 7–16 |
| (c) one-line edit, `src/qbe.zig` | 143 s | 112 s | 7–10 → 15 |
| (c) one-line edit, `src/native_text.c` | 196 s | 161 s | 7–11 → 15–19 |
| (c) one-line edit, `tests/lang/python_core.my` | 150 s | **5.1 s** | 8–11 → 17–18 |
| (c) one-line edit, `docs/io.md` | 134 s | **27 s** | 8–12 → 17–22 |

The inner-loop command on the same edits (`python3 scripts/affected_tests.py
--base HEAD`, load 6–10):

| edit | what it ran | wall |
|---|---|---:|
| `src/sema.zig` (comment line) | the compiler, 8 guest smoke areas | 14 s |
| `src/qbe.zig` (comment line) | 119 Zig tests from `qbe_test`, `qbe_frame_map_test` and `qbe.zig` over 8 shards, guest smoke | 57 s |
| `src/native_text.c` | `test-native-memory`, `test-native-heap`, 5 text guest areas | 25 s |
| `tests/lang/python_core.my` | that file | 1.0 s |
| `docs/io.md` | its doctest, `doc-coverage` | 1.9 s |

What remains of (c) for a compiler edit is work, not waiting. Every one of the
1,809 Zig tests, the 600 guest tests, the 945 documentation blocks and the Python
drivers runs the compiler, so a compiler change re-runs all of them, behind a
35–55 s recompile of `src/root_test.zig`. The gate still has to do that. The
inner loop no longer does.

## Where the time went (measured before the change)

Method: `--summary all` gave per-step durations and `/usr/bin/time -v` the whole
build. A 0.5 s sampler of the build runner's process tree gave a timeline of
every step process. `strace -f` of a whole no-change run showed which files each
step reads.

**(a) clean cache, 253 s.** The critical path is the unit root. Compiling
`src/root_test.zig` took 34 s (81 s on a busy machine), then its 12 shards ran
26–60 s each. Around them:

- the CLI shards, 18–31 s;
- the schematic root, 50 s;
- `native_boundary_matrix.py`, 52 s, and `idiom_probes.py`, 41 s, each running
  one compiler invocation at a time;
- `mylang test tests/lang`, 34 s, and `mylang doctest`, 20 s;
- the C runtime suites, 12 s, one `cc` at a time.

Everything else was under 10 s. The run used 1,185 s of CPU in 253 s of wall.

**(b) nothing changed, 125 s.** 719 s of CPU went to re-proving verdicts that
could not have changed. The unit and CLI shards were `has_side_effects = true`,
so that `test-units` always reports its count, and so were the Python drivers
and doctest. Together they re-ran everything except the compiles. Only the host
roots (board, byte I/O, schematic) were cached, and they declared no inputs, so
an edit to their guest sources could leave a stale green.

**(c) one-line edits, 134–196 s.** Each was (b) plus the recompile the edit
needs. A `.my` or documentation edit changes no binary, so it cost exactly (b).

Three further findings from the timelines:

- **Declared memory decided the schedule.** The build runner starts a step only
  while the `max_rss` of all running steps fits in `--maxrss`, which defaults to
  all 30 GiB. The declarations summed to far more: 12 × 1.5 GiB unit shards,
  3 GiB per compile, 1 GiB even for Python self-tests. A clean `zig build test`
  never held more than 5.8 GiB at once, yet shards waited up to a minute for
  reservations nobody used. On the same loaded machine, a full test rerun took
  136 s at the default budget and 81 s with `--maxrss 100G`.
- **Two installs of one artifact made cache keys random.** `mylang` was
  installed twice, once to `zig-out/bin` and once to `zig-out/focus` for focused
  tests. A run step names an artifact by whichever install ran last. The
  prebuilt-runtime step and the drivers therefore saw `./zig-out/bin/mylang` in
  one run and `./zig-out/focus/mylang` in the next, and re-ran for nothing.
- **The build runner serialises dispatch once its thread pool is full.** Zig's
  `Io.Threaded` allows cores − 1 = 19 concurrent step tasks. Past that,
  `Group.async` runs the next ready step *inline*, in the thread that finished
  its dependency. That thread dispatches the remaining dependants only after the
  inline step returns. So when `src/root_test.zig` finishes compiling, 3 of its
  12 shards start at once and the other 9 wait for one of them. On a sema edit,
  even with `--maxrss 60G`, shards started at 55.9 s and 94.1 s. The cause is in
  the toolchain, not in `build.zig`. `-Dtest-shards=8` measured the same as 12:
  75 s against 81 s, within noise.

## What changed

All changes are in `build.zig`, `build_test_inputs.zig`, three drivers and two
new checks. No compiler source changed.

1. **Test verdicts are cached on declared inputs.** These steps are no longer
   side-effecting: the unit and CLI shards, the host roots, the
   `test-qbe`/`test-qbe-build` roots, the Python drivers and `mylang doctest`.
   Each is keyed on:
   - its command and environment;
   - its test binary;
   - the emitted compiler and `qbe` it runs, whose bytes are declared because
     the environment names them by an installed path the key cannot see;
   - the repository files listed for it in `build_test_inputs.zig`.

   A directory entry declares every file under it. `tests/input_manifest.py`
   expands every list on every build (0.15 s) into a content manifest, and each
   step declares its manifest, so an edited, added, removed or renamed file
   re-runs exactly the steps that read it. The first version expanded the lists
   in `build.zig` and relied on `dependOnDirectory` to see new files. That
   function is a no-op in this Zig version (`Maker.zig`: `.directory => {}, //
   TODO`), so a new doc page kept doctest's cached verdict until the walk moved
   to make time. The lists come from the `strace` of every step, not from
   reading code. The `test-units`/`test-cli` whole-root runs stay uncached, as
   their contract requires. Four things still run every time, about 4 s in all:
   Guardian, `doc-coverage`, the guest suites (which have their own receipts)
   and the SPEC-merge replay (which reads git history).
2. **Drivers report through standard error.** A cached driver is a checked step,
   and the build runner discards a checked step's standard output. Each driver
   therefore runs under `sh -c 'exec "$@" 1>&2'`, so a failing driver's report
   still shows.
3. **A check keeps the declarations honest.** `test-inputs-coverage`
   (`tests/test_inputs_coverage.py`) reads every test source the cached roots
   compile and collects the repository paths it names, both literals and path
   joins. It fails the gate when an existing path is not covered by that root's
   list. `-Dtest-rerun=true` re-runs every cached test step, for anyone who
   suspects a stale verdict or wants full counts.
4. **The slow drivers run in parallel.** Each keeps its reporting order and
   honours `MYLANG_JOBS`:
   - `native_boundary_matrix.py`: 58 s → 10 s (15 s cold);
   - `idiom_probes.py`, cold: 30 s → 5.6 s;
   - `test_native_memory.py`: 10.5 s → 2.4 s.
5. **Memory declarations follow measured peaks.** With these ceilings, a full
   test rerun went from 136 s to 98 s at the default budget. The observations
   are recorded next to each ceiling in `build.zig`.

   | step | before | after | measured peak |
   |---|---:|---:|---|
   | unit shard | 1.5 GiB | 1 GiB | largest process 570 MiB |
   | CLI shard | 1 GiB | 0.75 GiB | largest process 141 MiB |
   | host roots, `tests/guest` | 2.5 GiB | 1.5 GiB | |
   | Guardian | 1 GiB | 0.5 GiB | |
   | checks that run no compiler | 1 GiB | 0.25 GiB | |
   | idiom and hint drivers | 2 GiB | 1 GiB | |
6. **One install per artifact.** The focused copies of `mylang` and `qbe` are
   file copies of the emitted binaries. The runtime prebuild waits for the one
   real install. Cache keys no longer flip between runs.
7. **Inner-loop support.**
   - `-Dtest-filter` is repeatable.
   - `test-units-sharded`/`test-cli-sharded` run a filtered selection as shards.
     The `qbe_test` selection took 80–90 s in one process and 45 s in 8.
   - `affected-compiler` installs just `mylang` and `qbe` to `zig-out/focus`.

Nothing left the gate. Every step `zig build test` ran before still runs on a
clean cache. The final gate matched its base: 1,809 tests in `test` and 322 in
`test-qbe`, with no new failures in any step. Two steps joined the gate:
`test-inputs-coverage` and `test-affected-selection`.

## The inner loop: `scripts/affected_tests.py`

The script diffs against the merge-base with `main`, plus staged, unstaged and
untracked files; `--base REF` chooses another base. It prints every selection
with its reason. It runs the Zig selections concurrently with the build steps,
then the guest commands. Every run, pass or fail, ends with the full-gate
commands. The mapping:

| changed | runs |
|---|---|
| `src/<m>.zig` | its inline tests, `<m>_test.zig` and test files importing it; for a module split out of a facade (`qbe_frame.zig` behind `qbe.zig`), the facade's test files; 8 broad `tests/lang` areas as a guest smoke |
| a diff line with `spec: TAG`, a SPEC bullet `[TAG]`, a diagnostic code or a changed `fn` | Zig tests carrying that tag, asserting that code or calling that function, and guest tests carrying the tag; a token that hits over 40 tests is dropped as too common |
| `src/*.c`, `src/*.h` | `test-native-memory`, `test-native-heap`, and the `tests/lang` areas named for that runtime part (`text` → strings, text, print…) |
| `tests/lang/*.my`, `tests/guest/*.my` | `mylang test` on that file, or on the areas importing a changed case module |
| `test/integration.zig` | the CLI tests whose declaration or body the diff touches |
| `experiments/llvm-backend/*` | `test-llvm-adapter` and an LLVM (`--mode ReleaseFast`) guest smoke |
| a Markdown page | `mylang doctest --filter <page>` and `doc-coverage` |
| a driver or its fixtures under `tests/`, `velocity/`, `scripts/` | the build step that runs it |
| host sources (`src/schematic/`, `src/board_trial/`, …) | that application's step |
| `build.zig`, `build_*.zig` | nothing; it says that only the gate covers the build graph |

`tests/test_affected_tests.py` pins the mapping on a synthetic repository, and
the gate runs it. The script makes a selection, not a proof. `src/sema.zig` has
no test file, so a sema edit that names no tag, code or function gets only the
guest smoke, and the script says so.

## Declined or left for later

- **Reusing the gate's unit-root binary for a focused run.** Zig applies
  `--test-filter` in the compiler, so every new filter set recompiles the root
  in about 25–35 s. A runtime filter in Guardian's test runner would let the
  inner loop run the already-built binary. That is a `guardian-zig` change.
- **`-fincremental`.** Tried on the focused unit root after an edit: 80 s with
  and without it.
- **Splitting `src/root_test.zig` into several roots**, so that its 35–80 s
  compile parallelises. It is the biggest remaining item on both the clean path
  and the compiler-edit path. It restructures the test layout, not the loop.
- **Doctest receipts per page.** A doc edit re-runs the whole 25 s doctest,
  because the command has no per-page cache.
- **Caching the always-run steps.** None is a pure function of files: Guardian
  gates the tree it sees, the guest runners have their own receipts, and the
  SPEC-merge replay reads git history.
- **`scripts/focused_test.py full`.** It sums the selected counts it sees, and a
  cached step no longer prints one; `-Dtest-rerun=true` gives full counts. The
  script belongs to the tooling lane and is unchanged.
- **The dispatch serialisation above.** It needs a Zig change, or a build runner
  that queues steps instead of running them inline. Fewer shards did not help
  measurably.
