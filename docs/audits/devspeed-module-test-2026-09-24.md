# Development-speed lane: `mylang test` on per-module artifacts (stage 1d) — 24 September 2026

Branch `devspeed/module-test`, from `7acb57b8` (`devspeed/integration` with
the module-projects work). What was asked, and what was done:

| Asked | Status |
| --- | --- |
| 1. `mylang test` on the per-module artifacts: the program-wide function-value and codec unions for test facts | **Done** (MODULE-TEST-1). |
| Canonical (sorted) wire and codec tables | **Done** (MODULE-TEST-2). |
| NATIVE-TEST-SCALE-1 restated for the per-module path, same intent | **Done.** After a body edit, exactly the dependent tests rebuild and re-run. |
| `--whole-program` kept as the oracle; identical output; verdict caching works | **Done.** 207 of 207 programs report identically, with and without `--gc-stress`. Verdicts now also replay across the two paths. |
| 2. Cold `check` no slower than `main` | **Done** (MODULE-CHECK-2). 200k: 1.73 s, against 1.64 s on `main` and 2.47 s before. |
| Cheapest cold-build items toward 200k cold ≤ 10 s | **Partly done.** 200k cold build is 14–15 s, against 22.2 s on `main`. The ≤ 10 s target is not reached; see *Cold build*. |
| Measure 200k edit → test and cold check/build against `main` | **Done.** See *Result*. |

## Update: runs never wait (MODULE-TEST-6), 25 September

Branch `devspeed/module-nowait`, from `devspeed/integration` at `ba2ccc54`.
The coordinator's fix before `main`: a run must never wait on the background
module compile.

**What changed:**

- **No wait for the path.** A test run that cannot claim the project's stable
  snapshot path stages at a private path. The path is held by a seeder or by
  another run. Such a run is always the whole-program run, which replays the
  receipts' verdicts and starts no seeder. Stage 1d made it wait for a
  seeder, since module records are keyed by the stable path.
- **No wait for a variant.** A test run takes the whole-program path while
  anything holds its program's module variant or the standard modules'
  shared one. Only the seeder waits. A check already behaved this way.
- **The seeder is paused.** Both seeders now run at nice 19. That is not
  enough on this machine (6 P-cores with SMT and a shared power budget):
  - with a seeder at nice 19, the edit run right after a cold run took
    4.8–5.1 s;
  - with the seeder under `SCHED_IDLE`, it took 4.9–5.1 s;
  - with the seeder stopped, it took 2.7 s
    (`experiments/module-nowait-20260925/results/seeder-modes-t200k.json`).

  So the seeder now writes its pid into its mark, and a run staged beside it
  stops the seeder's process group (SIGSTOP) for the run's length, then
  continues it (SIGCONT). It stops only a process that leads its own group
  and carries `MYLANG_TEST_SEED=1`, so a stale mark whose process is gone
  stops nothing. A run killed in between leaves the seeder stopped until the
  next run beside it ends.
- **Trace.** Each run records how it was staged: `stage stable DIR`,
  `stage private` or `stage seeding`, plus `pause-seeder` when it stopped
  the seeder.

**Measured** with ReleaseFast compilers, 3 repeats each, the 1-minute load at
3–13 from other agents. The rerun starts the moment the previous run returns.
Tool: `experiments/module-nowait-20260925/measure.py`, with results under
`results/`.

| 200k, `mylang test` | this branch | stage 1d | main |
| --- | ---: | ---: | ---: |
| cold | 5.2–5.6 s | 5.1–5.2 s | 4.8–5.1 s |
| unchanged, right after cold | **0.24–0.27 s** | 19.1–19.5 s | 0.25–0.26 s |
| body edit, right after that | **3.0–3.2 s** | 1.15–1.18 s | 2.6–2.8 s |
| seeder done after | 20 s | 0 s (the first rerun did its work) | — |
| then: no-op | 0.21–0.23 s | 0.20–0.21 s | 0.23–0.26 s |
| then: body edit | **0.70–0.73 s** | 0.66–0.67 s | 1.54–1.57 s |

| 50k, `mylang test` | this branch | stage 1d | main |
| --- | ---: | ---: | ---: |
| unchanged, right after cold | 0.056 s | 4.9–5.0 s | 0.050–0.057 s |
| body edit, right after that | 0.87–0.93 s | 0.50–0.51 s | 0.69–0.73 s |
| then: body edit | 0.20–0.22 s | 0.18–0.19 s | 0.42–0.43 s |

Every run reports the same counts on all three: 480 cached for an
unchanged run, and 240 run with 240 cached for an edit.

- **During seeding.** The edit rerun costs 3.0–3.2 s, against 2.6–2.8 s on
  `main`. With an idle fake seeder (`results/private-idle-t200k.json`) the
  run takes 3.05–3.09 s, so the remaining gap is the private path. The
  whole-program session's path-keyed caches were filled at the stable path,
  so parsed modules and fragment packs are rebuilt.
- **Stage 1d's 1.15 s edit** comes after the 19.5 s wait, which had already
  compiled every module.
- **The seeder.** It takes about 5 s longer in total, because it stands still
  while the two runs work.

**Tests** (MODULE-TEST-6, in `test/integration.zig`). A stand-in seeder is a
`sleep` process that leads its own group, carries `MYLANG_TEST_SEED=1`, and
is named in the mark on a stable path whose owner lock the test holds. The
test checks that:

- an unchanged run and an edit run return;
- both report the verdicts the receipts hold: 4 cached, then 3 run and 1
  cached;
- neither compiles a module;
- each stops the stand-in once and leaves it running;
- a mark naming a process without `MYLANG_TEST_SEED=1` stops nothing.

The MODULE-CHECK-2 test now holds the check variant's lock and checks that
a check returns the whole-program check's output and writes no records. The
MODULE-TEST-5 test checks that the seeder's compiles run at nice 19.

**Gate** on this code (the report and results were added after it):

- `zig build test --maxrss 8000000000`: 101/101 steps, 2,042 tests, 0
  failed, with Guardian's 88 checks and the four module oracles at 207/207;
- `test-qbe`: 47/47 steps, 423 tests;
- `test-qbe-build`: 29/29 steps;
- `fmt-check`: clean;
- `mylang test tests/lang`: 640 passed, and the same with `--gc-stress`;
- `tests/module_test_oracle.py … --gc-stress`: 207/207.

## Result

Measurements use ReleaseFast compilers, pinned with `taskset -c 0-11`. Other
agents shared the machine: the 1-minute load average was 3.5–12 on the final
ladder. Each no-op and edit figure is the minimum of 3 samples, and every sample
makes its own edit. The tool is `experiments/module-test-20260924/measure.py`,
and its raw output is under `results/`:

- `final-*`: this branch's final code, with every step. `main` and `base`
  were measured again for `test` only, to get the rerun just after the cold run;
- `pre-seed-*`: this branch before test seeding (MODULE-TEST-5), with every
  step for all three compilers. The `check` and `build` columns of `main` and
  `base` below come from this ladder.

The three compilers are:

- **1d:** this branch. The final ladder's build predates two later changes,
  and neither is on a measured path: the claim retry (NATIVE-TEST-STABLE-1)
  and the test roots' `compiler_language`.
- **base:** the module-projects lane's compiler (`362a4f7c`), the code of
  this lane's base.
- **main:** `main` at `4d54b210`, the shared ReleaseFast baseline compiler.

| 200k (481 modules, 480 tests) | 1d | base | main |
| --- | ---: | ---: | ---: |
| **body edit → test** | **0.646 s** | 1.309 s | 1.416 s |
| no-op test | 0.203 s | 0.202 s | 0.209 s |
| cold test | 4.36 s | 4.29 s | 4.32 s |
| rerun started right after the cold test | 19.5 s | 0.23 s | 0.25 s |
| cold test before seeding (MODULE-TEST-5) | 19.0 s | 4.12 s | 4.23 s |
| largest process, body edit → test | **314 MB** | 1,111 MB | 1,111 MB |
| body edit → check | **0.022 s** | 0.023 s | 0.456 s |
| interface edit → check | **0.026 s** | 0.030 s | 0.462 s |
| no-op / cold check | 0.017 / **1.73 s** | 0.018 / 2.47 s | 0.067 / 1.64 s |
| body edit → build | **0.437 s** | 0.385 s | 1.669 s |
| no-op / cold build | 0.045 / **15.0 s** | 0.040 / 14.4 s | 0.194 / 22.2 s |

| 50k (121 modules, 120 tests) | 1d | base | main |
| --- | ---: | ---: | ---: |
| **body edit → test** | **0.156 s** | 0.332 s | 0.323 s |
| no-op / cold test | 0.046 / 1.22 s | 0.047 / 1.20 s | 0.040 / 1.12 s |
| rerun started right after the cold test | 4.69 s | 0.050 s | 0.042 s |
| body edit → check | **0.015 s** | 0.012 s | 0.111 s |
| no-op / cold check | 0.008 / 0.43 s | 0.006 / 0.64 s | 0.020 / 0.38 s |
| body edit → build | **0.110 s** | 0.133 s | 0.400 s |
| no-op / cold build | 0.014 / 3.43 s | 0.015 / 3.66 s | 0.058 / 5.53 s |

In every body-edit test run, 240 of 480 tests (60 of 120 at 50k) execute and
the rest replay, on all three compilers. That is the dependent set.

**The one regression** was a test run started while the seeder that a cold
run left was still working. That run waited for the seeder, up to the
seeder's length: 19.5 s at 200k and 4.7 s at 50k. It is fixed: see *Update:
runs never wait*, where the same rerun takes 0.24–0.27 s.

## `mylang test` module by module (MODULE-TEST-1 to 4)

A test run of a project now uses the scheduler from stage 1c in a third mode,
`tests`, beside `build` and `check`. Each stale module compiles as
`compile-module --tests`. Besides its objects and interface, that compile
writes `NAME.tests.json` (`module-tests-v1`), which holds:

- **its share of the test facts** (`native_test_facts.Share`): every function
  it emits, described as the whole program's `native-test-graph-v3` describes
  it, except for the two program-wide edge sets. The share also lists the
  functions its bodies take as values (`values`) and the codec functions its
  program declares (`codecs`);
- **its own entry of the declaration contracts** (`Index.contractModule`);
- **the schema and export description** of each of its tests and benchmarks;
- **its wire and codec tables.**

The run merges the documents (`module_build.mergeTests`), and keeps the merge
for runs in which no module changed. Four pieces make the merge equal the
whole-program session:

1. **The unions (MODULE-TEST-1).** `native_test_facts.mergeShares` takes each
   function once. Every body whose reasons say
   `conservative-indirect-target-set` gets `indirect` edges to the union of
   every share's `values`. When any share declares a codec, every body gets
   `codec` edges to the union of the `codecs` sets. The result is the facts of
   the tests' closure, which the planner and receipts read exactly as before.
2. **Canonical tables (MODULE-TEST-2).** `qbe_wire.describe` sorts wire types
   by name. `qbe_codecs.canonical` sorts codec types by name with their
   descriptors, codecs by domain, and callbacks by symbol, and numbers each
   method by its callback's position. The whole-program library uses the same
   form, so the tables merged from modules are that library's, as the host
   tables became in MODULE-HOST-1.
3. **One test executable (MODULE-TEST-3).** The first version linked a
   shared library from the module objects, as the session does. At 200k the
   edit → test was then 3.46 s: every test process loaded and relocated a
   library of the whole program. The run now links the tests it executes into
   one executable, with the harness, from:
   - the modules' objects;
   - the program-wide metadata unit;
   - a wrapper exporting those tests (`qbe_build.ModuleProgram.library`).

   The harness is compiled once per cache as an object with
   `MYLANG_TEST_LINKED`, which calls the adapter directly instead of through
   `dlopen`. The edit → test fell to 0.62 s. Reports are unchanged: value,
   failure text, trap and captured output.
4. **Contracts from the modules (MODULE-TEST-4).** Tests are discovered from
   the merged contract entries, sorted by module as `list-interfaces
   --contracts` sorts them. So the run starts no declaration-check child.

**What still takes the whole-program path:** `--whole-program` itself,
`--no-cache`, `--release`, explicit link inputs, `--affected`, benchmarks,
`--diagnostics=json`, a case configuration that names provider fixtures, and
a project the modules cannot build. The session then reports the problem as
before.

### The ratchet, restated (NATIVE-TEST-SCALE-1)

The old counters described the session (one `native-test-compile`,
`lowered_functions` = 7). A new CLI test keeps their intent in module terms,
on the same four-module chain, where module K's test depends on modules 0..K:

| Step | Asserted |
| --- | --- |
| Cold | 5 modules compiled, 1 executable linked, 4 tests run, no `native-test-compile`, no `list-interfaces`; the stored facts cover the closure only (`m0::f` present, `m2::unused` absent) |
| Unchanged rerun | 0 modules compiled, nothing linked, no compiler child, 4 replayed |
| Body edit in `m1` | `m1` compiled and `m0` not; 1 executable linked; the tests of modules 1–3 run and module 0's replays |
| Edit that no test reaches (`m2::unused`) | `m2` compiled; nothing linked; nothing runs |

`m2` and `m3` recompile after the `m1` edit because `f` is small enough to
inline: its body is in the interface they read. The existing whole-program
ratchet tests still run, with `--whole-program`: the C4 environment fixtures
now pin that flag, since they count the session's children.

### Equivalence

- **`tests/module_test_oracle.py`** (in `test-module-compile`) covers
  `tests/lang` and the five module fixtures: 207 programs and 327 modules. It
  runs each program twice over fresh caches, once module by module and once
  with `--whole-program`, and requires:
  - the same exit status and stdout;
  - no whole-program session on the per-module run;
  - an unchanged rerun that compiles no module, and that links nothing
    unless a test that is not cacheable executes.

  207 of 207 are equal, with and without `--gc-stress`.
- **The build, check and compile oracles, and the incremental walks**, all run
  by the gate, are unchanged and green.
- **`MODULE-TEST-3`**: a trapping test and a printing test report the same
  stdout and exit status on both paths.

### Receipts now replay across the paths

Stage 1b's contract entry serialized `"test": null` on every declaration.
`list-interfaces --contracts` omits null fields. So the contract identity in
every receipt differed, and switching paths re-ran every test. A module's
entry is now rendered the way `list-interfaces` renders it. A verdict recorded
on either path now replays on the other (MODULE-TEST-5). Cold seeding below
depends on this.

## Cold check (MODULE-CHECK-2)

Per-module check made the 200k cold check 2.47 s, against 1.64 s on `main`.
The ladder is one import chain, so its 481 check-only compiles run one after
another. Now:

- **The first check** of a project of at least 64 modules, while its check
  variant holds no records, is the whole-program check. One pass is cheaper
  than a chain of module checks. `MYLANG_CHECK_SEED_MODULES` sets the count.
- **A detached seeder** is then started: `mylang check` of the same entry
  with `MYLANG_CHECK_SEED=1`. It has no standard streams and nothing waits for
  it. It checks every module and saves the records, and prints nothing. At
  200k its records appear 0.96 s after the cold check returns.
  `MYLANG_CHECK_SEED=off` starts no seeder.
- **A check never waits** for a held variant. While a seeder or another check
  holds it, the whole-program check answers.

The result: 200k cold check 1.73 s (main 1.64 s), and the next check is the
warm per-module one (0.022 s after a body edit).

## Cold test (MODULE-TEST-5)

Module by module, a first test run compiles every module, as a first `build`
does. The whole-program session lowers and compiles only the tests' closure.
At 200k that made the cold test 19.0 s, against 4.2 s on `main`. The fix
follows the cold check:

- **The first run** of a project of at least 64 modules, while its test
  variant holds no records, is the whole-program run.
  `MYLANG_TEST_SEED_MODULES` sets the count.
- **The run then starts a detached seeder:** `mylang test` with the same
  arguments and `MYLANG_TEST_SEED=1`. The seeder:
  - waits until the run has released the project's stable snapshot path;
  - claims the path and marks it as the seeder's;
  - compiles every module into the test variant;
  - exits, running no test and printing nothing.

  `MYLANG_TEST_SEED=off` starts none.
- **A run beside the seeder does not wait for it** (MODULE-TEST-6, see
  *Update: runs never wait*). It stages at a private path and is the
  whole-program run, which replays the verdicts, and it stops the seeder while
  it runs.
- **Once the seeder is done, runs are module by module**, and replay the
  earlier runs' verdicts through the receipts, which now match. At 200k: a
  no-op is 0.203 s with 480 replayed, and a body edit 0.646 s.

## Cold build (MODULE-SCHEDULE-6)

- **Profile** (200k cold build, CPU by process): the assembler
  (`zig clang -cc1as`) 39%, `qbe` 34%, `mylang` 27%. The batches already
  assemble with `-cc1as`, without the driver.
- **Done:** once a compile has published its interface, it lowers its own
  priority to nice 10 (`result.json` records it). The compiles on the import
  chain's critical path, which still build interfaces, then get the cores
  ahead of the code generation behind them. A/B under load: 21.0 s became
  17–18 s. On the quieter ladder the effect is within noise: 14.2–15.0 s,
  against 14.4 s for `base`. Both are about two-thirds of `main`'s 22.2 s.
- **Not reached:** the ≤ 10 s target. Once the interface chain has moved on,
  the three tool stages keep the cores busy, so scheduling alone gains little
  more. The remaining levers, none measured in this lane:
  1. batch sizing: each batch is one `qbe` process and one `-cc1as` process,
     so fewer, larger batches per module save process starts. This is cheap to
     try, and its gain is unknown;
  2. emit objects directly from QBE, which removes the assembler's 39% of the
     CPU. On this profile it is the only lever that reaches 10 s. It is a
     backend project, not a scheduling change.

## Found on the way

- **Stable-snapshot claim lost to a sweep (NATIVE-TEST-STABLE-1).** Any
  process that stages owned scratch reclaims `.pending/*` directories whose
  marker it can lock. Such a sweep can take a stable path's fresh marker
  between its creation and the run's lock, and delete the tree. The run then
  staged at a private path. The module variant is keyed by the entry's path,
  so the next run recompiled every module. The test oracle hit this once in
  207 programs under six parallel jobs. A claim that loses the race
  (`Attempt.lost`) is now made again, at most three times. A path held by a
  live run still stages privately, as before.
- **Contract `"test": null`** (above): receipts were keyed apart by the two
  paths for no semantic reason.
- **The unit root did not compile.** With the per-module path,
  `native_test_command` reaches `module_build`, which reads the language
  through the `mylang` module. The two test roots that hold every file in
  one module (`src/root_test.zig` and `src/native_test_cli_test.zig`) have
  no such module. Filtered runs (`test-units -Dtest-filter=…`) compile only
  the selected tests, so they did not show it. `test-compile` and the full
  gate did. The roots now hand the module over as `compiler_language`, the
  way they already hand `native_test_snapshot` its project loader
  (`snapshot_project`).

## Gate

This gate ran on the final code (this report and the results are the only
later additions). Each step ran through the shared gate slot.

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 101/101 steps succeeded; 2,041 tests run in the shards, 0 failed. Includes Guardian (88 checks) and `test-module-compile`: the build, compile, check and test oracles at 207/207 equal, the `--release` compile oracle at 5/5, and the build differentials |
| `zig build test-qbe --summary all` | 47/47 steps, 423/423 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 640 passed across 112 programs |
| `zig-out/bin/mylang test tests/lang --gc-stress` | 640 passed across 112 programs |
| `tests/module_test_oracle.py … --gc-stress` (run by hand) | 207/207 equal |

The new MODULE-TEST-5 CLI test also passed 15 repeated runs by hand
(`-Dtest-rerun=true`).

## What changed

- `src/native_test_facts.zig`: `Share`, `renderShare`, `mergeShares` with the
  value and codec unions.
- `src/qbe_wire.zig`, `src/qbe_codecs.zig`: the canonical tables
  (`qbe_codecs.canonical`).
- `src/interfaces.zig`: `contractModule`, one module's contract entry, which
  `renderContracts` now uses.
- `src/project_compile.zig`: `testShare`.
- `src/module_compile.zig`, `src/module_compile_command.zig`: `--tests` and
  the `module-tests-v1` document; contracts rendered without null fields; the
  nice-after-ready priority.
- `src/module_build.zig`: the `tests` mode (`openTests`, `Tests.link`,
  `mergeTests`); the check seeder and the cold fallback; `Wait`, which says
  which held variants a session waits for.
- `src/qbe_build.zig`: `ModuleProgram.library`, the wrapper linked in place of
  an entry.
- `src/native_test_command.zig`, `src/native_test_session.zig`,
  `src/native_test_execute.zig`, `src/native_test_runner.c`,
  `src/native_test_options.zig`: the per-module run, the linked test
  executable, `--whole-program`, the test seeder and the wait for it.
- `src/native_test_snapshot.zig`: `claimStableWaiting`, `markSeeding`,
  `heldBySeeder`, and the claim retry.
- `src/main.zig`: the check seeder's environment. `src/main.zig`,
  `src/root_test.zig` and `src/native_test_cli_test.zig` export
  `compiler_language`, which `module_build` reads through
  `native_test_root`.
- Tests:
  - `tests/module_test_oracle.py` (new, in `test-module-compile`);
  - CLI tests MODULE-TEST-1/3/4/5, MODULE-CHECK-2 and MODULE-SCHEDULE-6, and
    the restated NATIVE-TEST-SCALE-1;
  - unit tests for `mergeShares`, `qbe_codecs.canonical` and the seeder
    marker.
- Docs: `docs/tooling/guest-tests.md` (*Tests module by module*),
  `docs/tooling/module-interfaces.md` (the cold check), the `module-test`
  feature entry, and SPEC bullets MODULE-TEST-1 to 5, MODULE-CHECK-2 and
  MODULE-SCHEDULE-6.

## Reproduction

```bash
M=zig-out/bin/mylang
P="tests/fixtures/interfaces/main.my tests/fixtures/interfaces_generic/main.my tests/fixtures/incremental/main.my tests/fixtures/module_compile/main.my tests/fixtures/module_projects/main.my"
python3 tests/module_test_oracle.py $M tests/lang $P
python3 tests/module_test_oracle.py $M tests/lang $P --gc-stress
python3 experiments/build-loop-20260924/gen_scale.py t200k 480 38
python3 experiments/module-test-20260924/measure.py $RELEASEFAST t200k/mylang work --samples 3
```
