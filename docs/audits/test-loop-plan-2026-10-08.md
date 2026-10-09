# Test loop after an edit: plan for items 4 and 5, 2026-10-08

Status, 2026-10-08 (end of day): **everything in this plan is done and merged into `main`**: items 1–3 (§2, §6), T3b (§3, §6b), item 4 (§4, §6c), fast launches and the cache sync (§6d), and item 5 (§5, §6e). The benchmark rerun on the merged `main` is §6f. **What is left, deliberately deferred, is §8**: where the remaining time goes, three further levers with their estimated cost and payoff, and when to come back to them.

The text below was first written as the plan for items 4 and 5, when only items 1–3 were done. Two smaller pieces from the investigation, T3b and the jobserver fallback, were included because they feed the same goal.

**Goal.** A test step after an edit on the EDA port that is at or below Go's. The benchmark medians to beat are 1.19 s (Go), 1.64 s (Rust) and 2.20 s (Zig).

## 1. What the investigation found

Measured on 2026-10-08 with the compiler that the EDA benchmark used (ReleaseFast `main` `5a6b501d`). EDA has 310 tests in 58 test files. The probe scripts are in `experiments/test-loop-20261008/`.

| cost | size | where |
|---|---|---|
| the harness gave mylang `--jobs 4`, but Go, Cargo and Zig used every CPU | about half the hub-edit time | `eda-bench` `harness/langs.toml` |
| test files ran in fixed waves; a wave waits for its slowest member | 1.4 s of idle slots in one hub-edit run | `test_runner_directory.zig` |
| each test lowers and hashes its own program, to find its receipt key | about 20 ms per test (13 ms lowering, 7 ms hashing); 0.6 s for the 28-test file | `test_runner.zig` `select` |
| every test file is its own `mylang test FILE --json` process, 58 of them | 45% of all CPU is kernel time: 754k page faults, 128k `statx`, 13k `mmap` | directory runner |
| every test is its own native process, run one after another | about 13 ms each; 0.33 s of the 28-test file | `runSelected` → `executeBatches` |

Even a comment-only edit, where every test replays, cost 1.3–2.1 s, because every file that imports the edited module recomputes every test's key. Receipt identities are stable: comment edits replay all 310 tests, and changing `--jobs` changes no identity.

## 2. Items 1–3 (done)

- **Item 1.** The `eda-bench` harness's `[mylang-new]` and `[mylang-new-release]` test steps drop `--jobs 4` (`claude/eda-bench-newcore` `4c6bdac`).
- **Item 2: a work queue, NEW-CORE-TEST-QUEUE-1** (`claude/test-loop`).
  - Directory runs start roots largest file first.
  - A worker starts the next root as soon as its child exits.
  - A child's `--jobs` is the budget divided by the children that can still run beside it, so the tail of a run gets the freed cores.
  - A program's own test processes are taken from a queue too.
- **Item 3: a whole-file receipt key, NEW-CORE-TEST-WHOLE-1** (`claude/test-loop`).
  - A program keys all its ready tests at once: the combined program the runner builds for them, plus their cases.
  - When that key has a receipt, every test is `cached` with one lowering and one hash instead of one each.
  - On a miss, the exact per-test keys decide what reruns, as before.

**Results:** see §6.

## 3. T3b: exact per-test keys from one lowering

**Status, 2026-10-08: done on `claude/t3b-identity`** (NEW-CORE-TEST-KEYS-1 and -2; results in §6b). The text below is the plan as written. The implementation follows it, with two changes:
- the whole-file key now joins the derived per-test keys;
- loop ids are left out of both kinds of key: the instability §6 observed came from them.

**Why.** On a whole-file miss (the file the edit touches), `select` still lowers and hashes each test's program separately: 0.6 s of the 28-test file's 1.4 s, all on the critical path.

**What.** Lower the file's tests once, then derive each test's key from the functions it reaches.
- Compute a digest for each function. It is canonical, meaning it does not depend on where the function sits in the shared module:
  - callees by name and signature;
  - strings by their bytes;
  - compound types structurally, safe against cycles (recursive types close through `box`).
- A test's key hashes the sorted digests of its reachable functions, plus the inputs its entry is generated from:
  - its streams and parameter families;
  - its parameter and result type names;
  - the schema digest, when it has generated parameters or a non-`bool` result;
  - the settings already in `base`.

**References to canonicalize.** Every one must be covered; a missed one gives false cache hits.
- `call.a` and `func_ref.data` hold function indices.
- `str_const.data` holds a string index.
- `unreachable.data` with `flags.assertion_trap`: the low 32 bits are a string index.
- Runtime declarations from `build_render.zig` carry a string index in their symbol name (`declaration_prefix{index}_{id}`). `build_host.zig` metadata is also a string.
- Types: `Inst.ty`, `Signature.params`/`ret`, and `Compound` children.
- Not references: `Block` and `Loop` hold only block ids.

**Exit:**
- **The new keys are never coarser than today's.** Over seeded body, type, string and call-graph edits on `tests/lang`, Lox and EDA, the set of tests whose key changes must include every test today's key would rerun. A missed test is a stop.
- **No over-invalidation for body edits.** It should be equal for body edits; record any test that reruns needlessly.
- **Speed:** the 28-test file's select falls from 0.6 s to under 0.15 s.

**Owns:** a new `src/core/test_runner_identity.zig`, `select` in `test_runner.zig`, and the NEW-CORE-S4-TEST-6 bullet.

**Estimate:** 6–10 h.

## 4. Item 4: one process per batch of tests

**Status, 2026-10-08: done on `claude/test-batch`** (NEW-CORE-TEST-BATCH-1; results in §6c). The implementation follows the plan below, with three changes:
- **No runtime reset was needed.** The harness already forks every trial from a parent that runs no guest code, so stand-ins, captured output, budgets and the managed heap start fresh for each test by construction. The audit of runtime globals reduced to that.
- **No `isolate: true` cases-file setting.** With a fork per trial, a batch shares nothing a test can observe. `MYLANG_TEST_ISOLATE=1` (one process per test) stays as the differential oracle.
- **A timeout is not rerun.** A trial's wall-clock limit is now exact to the millisecond (`setitimer`, not whole-second `alarm`), so a trial killed by `SIGALRM` gets `timed out after N ms`, the reason it gets alone, without paying the timeout twice. Any other ending is rerun alone, as planned.

**Why.** Every test is its own native process, launched one at a time, at about 13 ms each. The hub edit launches 111 of them, and the 28-test file spends 0.33 s just launching.

**What.**
- **Batches.** `runSelected` already sends each test through `property_execute.executeBatches`, as a batch of one call with one input. The native harness already answers many inputs per process for property tests, flushing each answer as it finishes. Extend a batch to hold calls to several test functions of the same executable: the dispatch table already indexes them.
- **Batch width:** about `ceil(pending / jobs)` tests per process, taken from the queue.
- **Isolation to keep, per test, inside one process:**
  - fresh capability stand-ins seeded as today;
  - captured stdout and stderr per test;
  - step, frame and memory budgets reset per test: the managed-heap byte count, and the leak check's live set when `MYL_CORE_LEAKCHECK` is on;
  - no state carried between tests: module constants are immortal and unchanged, and no guest-visible global exists.
- **A test that crashes, traps the process or times out** keeps the answers of the tests before it. It is rerun alone in its own process, as today, to get its own verdict. The rest of the batch continues in a new process. This is the same rule property batches follow (PROPERTY-TEST-4).
- **Opt-out:** a cases-file setting, `isolate: true`, for a test that must run alone.

**Exit:**
- **Same results in both modes.** Every suite (`tests/lang`, `src/stdlib` fixtures, Lox, EDA, `test/core` runner fixtures) gives byte-identical verdicts, reasons and traces batched and isolated (`--force` both ways).
- **New fixtures.** A segfaulting extern mid-batch (`c_runner_signal.c` already exists), a test that exhausts its memory budget followed by one that allocates, and a test that prints followed by one that checks its output is empty.
- **Speed:** the 28-test file's run phase drops from 0.33 s to under 0.08 s, and the hub edit's launches from 111 to about 20.

**Owns:** `runSelected` and `executeWorkers` in `test_runner.zig`; the batch call in `property_execute.zig`; the test entry and runtime reset in `test_runner_batch.zig` and `runtime/core_test.c`. A new spec tag; the PROPERTY-TEST-4 wording stays as it is.

**Estimate:** 6–10 h.

**Risk:** process-wide runtime state that a test can observe. Before turning batching on, list every runtime global in `core_test.c`, `core_rt.c` and `core_io.c`, and give each one a reset or a reason it can't leak.

## 5. Item 5: one-process directory runs

**Status, 2026-10-08: done on `claude/test-union`** (NEW-CORE-TEST-UNION-1; results in §6d and §6e), after two smaller changes that the profiling for it turned up (§6d). Where it departs from the plan below:
- **T5a is a shared check, not a multi-entry session.** The roots of one project that miss their recorded reports are checked once, as a synthetic entry that imports each of them. Each root then reads its share: the modules its own imports reach, with the synthetic entry's source segment named after the root, so an instruction without a span of its own is located, traced and keyed exactly as in the root's own check. Directory discovery loads the same roots through one such entry too, instead of one load per root.
- **Eligibility, not every root.** A root shares the check when it opens with its `module` header and declares no `main`, its configuration names no import policy and no interface files, its cases file names no providers, and the run selects by no git revision. Every other root, and every root of a project whose shared check fails, keeps its child process, where its own check reports its own diagnostics. `MYLANG_TEST_CHILDREN=1` is the oracle.
- **T5b is a permit pool, not a step scheduler.** Each root still selects, builds and runs on its worker. Each of its test processes holds one of the run's `overall` permits, and a child root holds its share for as long as it runs. The root that is still working therefore uses the cores the finished roots gave back, and the run never has more test processes than the budget.
- **Found and fixed on the way:**
  - the schema digest now covers only the types a test reaches, not every type of the program;
  - a span-0 instruction was keyed by the entry file's name;
  - `ETXTBSY` from a sibling thread's child is retried;
  - the process-placement oracles no longer enter receipt keys.

**Why.** 58 child processes each:
- start a 50 MB compiler;
- reload and re-hash the same cached modules (`persist_codec.decode`, BLAKE3, SHA-256);
- fault in their memory from scratch.

That is most of the 45% kernel time. It is also why a finished small file's cores can't help the big one: the children don't share a scheduler.

**What.** `mylang test DIR` does it all in one process, as `go test ./...` does with its one `go` command.
1. **T5a, one check.** One frontend session checks the union of the roots' import closures once. Each root's discovery and `select` read the shared checked modules.
   - A root with test providers needs its own overlay session. It gets one, in process, as `runGroup` does today.
   - The per-root report and receipt manifest are unchanged.
2. **T5b, one scheduler.** One pool of `overall` workers runs the work of every root: select, build, then run batches (item 4). A file's tests can then use every idle core, which removes the critical path the big file sets today.
   - At most `overall` guest test processes run at once, exactly the bound the per-child division gives today. The memory ceilings (CLAUDE.md, "Memory ceilings") are unchanged.
3. **T5c, unchanged contracts.** These stay as they are:
   - the merged report, in root order;
   - the `sources` accounting (every test-declaring source loaded);
   - `SourceChanged` detection;
   - exit statuses;
   - receipt and manifest formats.

   The child-process path stays behind `MYLANG_TEST_CHILDREN=1` for one release, as the differential oracle.

**Exit:**
- **Same results both ways.** The child and one-process modes give identical reports on:
  - the directory-run fixtures: orphan libraries, providers, an invalid cases file (status 2), `SourceChanged`, and test-declaring sources not loaded;
  - `tests/lang`, Lox and EDA.
- **Speed and memory, on the EDA ladder at all CPUs:**
  - the comment-only edit at or under 0.5 s;
  - hub, leaf and interface edits at or under Go's 1.19 s median;
  - peak compiler RSS under 1 GB.

**Owns:** `test_runner_directory.zig` and the `run`/`runGroup` split in `test_runner.zig`, plus `frontend.Session` if it needs a multi-entry check. Docs: guest-tests "Directory runs". Spec tags NEW-CORE-S4-TEST-1/2 and S5-FANOUT-1 are amended.

**Estimate:** 15–25 h.

**Risks:**
- Thread safety of lowering and emission: today each process runs one at a time. Mitigation: keep checking single-threaded, give each worker its own arena, and audit `ModuleBuilder` and `pipeline.finish` for shared state.
- A compiler crash now fails the whole run instead of one file. That is acceptable; report it as a failed run.

**Fallback if item 5 is deferred: a jobserver.** The directory runner hands its children a make-style token pipe. A child takes a token before each extra build thread or test process and returns it when that ends, so cores a finished file frees flow to the running ones without breaking the `overall` bound. Token traffic must not touch receipt identity, so its variable belongs with `MYLANG_JOBS` in `placement_variables`. Estimate 4–6 h. Superseded by T5b.

## 6. Results of items 1–3

**Setup:** EDA, 310 tests. Medians of 3 rounds, one after another, under `bench-compile.lock`.
- **Before:** ReleaseFast `main` `5a6b501d`.
- **After:** ReleaseFast `claude/test-loop` (items 2 and 3).

Each compiler has its own warm cache. The raw rows are in `experiments/test-loop-20261008/matrix.out`.

| edit | tests rerun | `--jobs 4` before | `--jobs 4` after | all CPUs before | all CPUs after |
|---|---:|---:|---:|---:|---:|
| hub body (`sexpr_parser`) | 111 | 3.81 s | **1.93 s** | 2.59 s | **1.99 s** |
| leaf body (`kicad_sch_stagger`) | 31 | 2.32 s | **1.83 s** | 2.07 s | **1.82 s** |
| interface (new public function) | 0 | 2.55 s | **1.11 s** | 2.0–2.6 s ¹ | **0.67 s** |
| comment only | 0 | 2.33 s | **1.07 s** | 1.45 s | **0.69 s** |

¹ One base round hit 13.3 s under outside load. The other two were 2.61 s and 2.02 s.

**Against the benchmark.** As the benchmark now runs, with item 1 at all CPUs, the median of the three timed edits is **1.82 s**. Before, it was 4.86 s in the benchmark run and 2.55 s here at `--jobs 4`. That puts mylang between Rust (1.64 s) and Zig (2.20 s); Go is 1.19 s.

**What is left.**
- **Hub and leaf edits stay at about 1.8–2.0 s even at all CPUs.** They are bound by one file, `export_kicad_sch_test` (28 tests), which the edit touches. Its time splits as:
  - check: 0.2 s;
  - per-test keys: 0.6 s (T3b);
  - build: 0.4 s;
  - 28 test processes, one after another: 0.33 s (item 4).

  A child that starts first gets one job, so neither item 2's tail rebalancing nor more CPUs helps it. Item 5's shared pool and T3b do.
- **Observed with both compilers, not explained yet.** The *first* interface edit of each matrix cell reran 7–76 tests whose own code it doesn't touch; later rounds, with a different function name and value, reran none.
  - So adding any public function to `sexpr_parser` changes some reached tests' Core IR, consistently, the same way each time.
  - The likely cause is a typed function id leaking into lowering, such as a specialization or lambda name. That is spurious invalidation, not a wrong answer.
  - Worth a small follow-up beside T3b, whose canonical digests would hide it.
- **Edits that rerun nothing** (comment, interface) are now 0.7 s. The whole-file key turned 58 children's per-test lowering into one lowering per file. What remains is mostly the 58 process starts and cache reloads (item 5).

## 6b. Results of T3b

**Correctness: `keys_differential.py`.**
- **Setup:**
  - 56 seeded edits over EDA (24), Lox (16) and `tests/lang` (16): body statements, new string literals, new public functions, line-moving comments, and 18 *break* edits. A break edit is an assertion that fails at run time, inserted into a function.
  - Every edit and every revert ran with the derived keys and with the `MYLANG_TEST_KEYS=per-test` oracle, each in its own cache.
- **Result:**
  - 0 tests missed and 0 extra;
  - identical failing tests on every one of the 112 runs per mode, including break edits that failed up to 111 tests;
  - no reruns after a revert. Before the loop-id fix (NEW-CORE-TEST-KEYS-2), *both* modes reran 26–102 untouched tests on some interface edits and reverts.
- **Evidence:** `keys-{eda,lox,lang}.json`.

**Speed: `matrix-t3b.sh`.** Medians of 3, the items 1–3 compiler against T3b, each in its own warm cache, load 1–6.

| edit | `--jobs 4` items 1–3 | `--jobs 4` T3b | all CPUs items 1–3 | all CPUs T3b |
|---|---:|---:|---:|---:|
| hub body (111 rerun) | 1.90 s | 1.76 s | 2.08 s | **1.39 s** |
| leaf body (31 rerun) | 1.77 s | **1.28 s** | 1.97 s | **1.22 s** |
| interface (0 rerun) | 0.95 s | 1.13 s | 0.72 s | 0.74 s |
| comment only (0 rerun) | 0.97 s | 1.14 s | 0.71 s | 0.80 s |

**The `--jobs 4` no-rerun rows are a load artifact.** The two compilers ran one after the other while load rose. In a 5-round interleaved rerun (`interleave-t3b.out`, load 8–29), T3b's median was at or below items 1–3 in every cell:
- interface at `--jobs 4`: 1.48 s against 2.59 s;
- comment-only: 1.57 s against 1.58 s.

**Phase timing.** On the 28-test file, the shared key path costs 27 ms of lowering and 26 ms of digests and keys. It replaces about 600 ms of per-test lowering and hashing.

**Against the benchmark** (all CPUs, the three timed edits): hub 1.39 s, leaf 1.22 s, interface 0.74 s; the median is **1.22 s**. Go's is 1.19 s, Rust's 1.64 s and Zig's 2.20 s.

## 6c. Results of item 4

**Correctness: `batch_differential.py`.** Every corpus ran with `--force` batched and with the `MYLANG_TEST_ISOLATE=1` oracle (one process per test), then again after each of 14 seeded break edits (an assertion that fails at run time, inserted into a function).
- **Corpora:** EDA (310 tests, 6 breaks), Lox (65, 4 breaks), `tests/lang` (1505, 4 breaks), and the six `test/core` runner fixtures that need no linked helper (35 tests, 16 of them failing by design: traps, shrinks, discards, captured output, typed expectations).
- **Result:** the same status, reason and property evidence for every test on every run, and the same exit status. The break edits failed up to 47 tests (EDA) and 23 (Lox).
- **Fixtures** (`src/core/runner_batch_test.zig`): output, the memory ceiling and the timeout stay per test inside one process; a test that ends its process at its second trial (a linked probe) is rerun alone and the rest continue, all passing; a test whose every trial exits early fails with the same ending in both modes; the probe counts 1 process batched against 3 isolated.
- **Evidence:** `batch-{eda,lox,lang,core}.json` (the `core` file is the clean run only).

**Speed: the 28-test file** (`export_kicad_sch_test`, `--force`, all tests rerun, medians of 3):

| `--jobs` | T3b | item 4 |
|---:|---:|---:|
| 1 | 1.10 s | **0.66 s** |
| 4 | 0.69 s | **0.59 s** |
| 16 | 0.67 s | **0.64 s** |

Its tests now run in about 0.11 s of processes at `--jobs 4`, against 0.33 s. Batched against isolated with the same compiler at `--jobs 1`, each extra process costs about 15 ms, nearly all system time: the compiler forks its own 300–500 MB address space for every launch (Zig's `std.process.run` uses `fork`). The test binary itself starts in about 2 ms.

**Speed: the EDA edits** (`interleave-batch.sh`, 5 interleaved rounds, each compiler in its own warm cache, load about 6; medians):

| edit | all CPUs T3b | all CPUs item 4 | `--jobs 4` T3b | `--jobs 4` item 4 |
|---|---:|---:|---:|---:|
| hub body (111 rerun) | 1.40 s | **1.03 s** | 1.64 s | **1.44 s** |
| leaf body (31 rerun) | 1.20 s | **0.85 s** | 1.17 s | **0.82 s** |
| interface (0 rerun) | 0.70 s | 0.70 s | 1.09 s | 1.12 s |
| comment only (0 rerun) | 0.71 s | 0.72 s | 1.07 s | 1.10 s |

**Against the benchmark** (all CPUs, the three timed edits): hub 1.03 s, leaf 0.85 s, interface 0.70 s; the median is **0.85 s**, under Go's 1.19 s. T3b measured 1.20 s in the same rounds, matching its 1.22 s in §6b. These are the probe's numbers under outside load, not a benchmark-harness run.

**What is left.**
- **Process launches still fork the compiler** (about 13 ms of system time each, serialized on its address space). A `vfork`-style spawn (`clone` with `CLONE_VM | CLONE_VFORK`, then `execve`) would make each launch cost about what it costs from a shell. It matters more for item 5, where one large process would launch every test of the directory.
- **The edited file's own check and build** (about 0.5 s on the hub edit's critical path) and the **58 child compilers** (no-rerun edits at 0.7 s) are item 5's.

## 6d. Fast launches and the cache sync

**Fast launches (NEW-CORE-SPAWN-1, `process_spawn.zig`).** The core now starts test processes, build tools, directory-run children and the program `mylang run` runs with `clone(CLONE_VM | CLONE_VFORK)` and `execve`, instead of Zig's `fork`.
- **Effect on launches:** on the 28-test file run isolated (one process per test), system time fell from 0.55 s to 0.16 s, and wall time from 1.08–1.49 s to 0.69–0.95 s.
- **Effect on the EDA edits:** none measurable (`interleave-spawn.out`). After item 4, launches were no longer on the critical path.
- **Correctness:** against `main`, it gives the same verdicts on every runner fixture and on an EDA break edit.

**The semantic cache's sync (SEMANTIC-CACHE-15 amended).**
- **The cause:** phase timing showed that after an edit, 89% of the directory run's child time was the front-end check, 200–270 ms per root. One root's check ran 150 ms with the semantic cache and 110 ms without it.
- **The stall:** the cache ended every publication batch with `syncfs`. That waits for every dirty page of the filesystem, so on a busy machine a single check stalled for up to a second. The entries were already checksummed and renamed atomically, so the sync bought only durability, which a cache does not need. It is gone.
- **Results** (`interleave-nosync.out`, 5 rounds, load about 3.5; fast launch plus no sync, against `main`):
  - all CPUs: hub 1.12 → 0.94 s, leaf 0.97 → 0.86 s, interface 0.78 → 0.56 s, comment 0.73 → 0.54 s;
  - `--jobs 4`: hub 1.48 → 1.14 s.

## 6e. Results of item 5

**Where the time went, and what changed.** On a comment edit, 28 roots each rechecked much the same import graph, 3.6 s of check in all. Now:
- **Discovery:** one shared load, about 90 ms → 25–29 ms.
- **The shared check:** 170–200 ms once. It runs without the semantic cache, which measured 40–50 ms slower here.
- **Each root:** selects, builds and runs from its share of that check.
- **Test processes:** a root's processes take the permits the finished roots return, so the hub edit's last root (`export_kicad_sch_test`, 28 tests) no longer runs its tests on one core.

**Correctness.**
- **Against children (`batch_differential.py --oracle MYLANG_TEST_CHILDREN`):** EDA, Lox and `tests/lang` with 14 break edits gave identical verdicts and exit statuses (`union-{eda,lox,lang}.json`).
- **The first run found 22 differences, all `FileBusy`.** A sibling thread's child held a test executable's write descriptor between its `clone` and its `execve`. The spawn now retries `ETXTBSY` with a short backoff.
- **Receipts carry across modes on EDA:**
  - after a leaf edit, a run in children reruns exactly the 31 tests an in-process run reruns;
  - a revert replays all 310 in either mode.

  Two fixes made this possible: span-0 locations, and the schema digest scoped to reachable types.
- **Regression checks on the final compiler:**
  - `keys_differential.py`, 28 edits: 0 missed and 0 wrong (`final-keys-*.json`);
  - the item 4 differential on EDA, 4 break edits: 0 differences (`final-batch-eda.json`).
- **Gate:** 88/88, in 72 s.

**Speed** (`interleave-final.out`: 5 interleaved rounds against `main` `4b666d7e9` (item 4), each in its own warm cache; outside load 11–13, so absolute numbers are high; medians):

| edit | all CPUs `main` | all CPUs now | `--jobs 4` `main` | `--jobs 4` now |
|---|---:|---:|---:|---:|
| hub body (111 rerun) | 1.01 s | **0.61 s** | 1.59 s | **0.65 s** |
| leaf body (31 rerun) | 0.87 s | **0.52 s** | 0.82 s | **0.52 s** |
| interface (0 rerun) | 0.76 s | **0.40 s** | 1.14 s | **0.42 s** |
| comment only (0 rerun) | 0.75 s | **0.40 s** | 1.07 s | **0.42 s** |

A run with nothing changed is also faster: 0.46 s → 0.34 s in the same session.

**Against the benchmark** (all CPUs, the three timed edits): hub 0.61 s, leaf 0.52 s, interface 0.40 s. The median is **0.52 s**, against Go's 1.19 s, Rust's 1.64 s and Zig's 2.20 s.

> **Correction (§6f).** The benchmark harness measured more for the body edits than this: leaf 0.95 s and hub 0.90 s. The interface edit matched, at 0.42 s.
> - **Why the probe read low:** the probe repeated each edit in the same warm cache, and a repeat reuses the objects the first edit rebuilt.
> - **Why the harness reads higher:** it empties its cache every repetition, so it always times the first edit.
> - **What still holds:** the relative gains above, since both compilers were probed the same way.
> - **The benchmark-level claim does not.** The benchmark's test step is 0.90 s, against Go's 0.75 s in the same run, not 0.52 s.

**What is left.**
- **The hub edit:** its critical path is now the shared check (about 200 ms), then the largest root's select, build and run. The build is lowering, LLVM emission and `zig cc` of the changed units.
- **No-rerun edits:** discovery, the shared check, and each root's key derivation (about 50–70 ms for the largest root).

## 6f. The benchmark on the merged `main`

**What ran.** The EDA stage-1 benchmark, rerun on `main` `fc31e55bb`. That `main` is the morning's new core plus everything merged since: copy elimination, items 1–5, fast launches and the removed cache sync.
- **Compiler:** a ReleaseFast build at `~/.cache/mylang/bench-main-352d9396` (sha256 prefix `ae4b4ba68304a33e`).
- **Harness:** `eda-bench` `claude/eda-bench-newcore` `d45e0cd`, the same entries re-pinned to that compiler, with no `--jobs` (item 1).
- **Protocol:** the morning run's (`experiments/bench-newcore-20261008/eda/`), in `experiments/test-loop-20261008/bench-main/run.sh`.
  - Development loop: `bench.py time --repeat 3` for Zig, Go, Rust and mylang back to back, 19:52–20:00 UTC, under `bench-compile.lock` and the build-slot wrapper (16 CPUs).
  - Runtime: on CPU 10 under `cpu10.lock`, 10 rounds after a warm-up, with every output checked against the goldens.
- **Load:**
  - Zig, Go and Rust ran at a one-minute load of about 3–6.
  - mylang's edits ran while it rose to 12, as another session's gate started.
  - The runtime run was at load about 4.
  - The morning run had load 5–14 for the loop timings, so every language is faster now. **Compare within a run, not across runs.**

**Correctness.**
- `equiv`: 34/34 byte-identical in the debug build (3.1 s of run time, was 5.4 s) and in `--release` (1.3 s, was 2.8 s).
- `test`: 310 passed, 3.7 s from an empty cache (was 11.1 s).
- Runtime: every output of every round matched the goldens.

**Development loop after a one-line edit.** Medians of 3 repetitions. The morning run's figure is in brackets.

| step | mylang | Go | Rust | Zig |
|---|---:|---:|---:|---:|
| cold build | 6.95 s (12.54) | 3.35 s (5.35) | 2.67 s (3.30) | 65.09 s (132.59) |
| clean build | 0.44 s (1.50) | 0.74 s (1.18) | 2.64 s (2.95) | 1.28 s (2.08) |
| check, leaf / hub / interface | 0.16 / 0.16 / 0.16 s | 0.50 / 0.60 / 0.71 s | 0.53 / 0.64 / 0.50 s | 0.70 / 0.70 / 0.72 s |
| build, leaf / hub / interface | 0.45 / 0.46 / 0.40 s | 0.37 / 0.21 / 0.64 s | 0.66 / 0.81 / 0.63 s | 0.61 / 0.56 / 0.54 s |
| **test, leaf / hub / interface** | **0.95 / 0.90 / 0.42 s** | 0.70 / 0.75 / 1.18 s | 2.11 / 1.50 / 1.50 s | 1.23 / 1.22 / 1.15 s |
| median of the three edits: check | **0.16 s** (0.28) | 0.60 s (0.99) | 0.53 s (0.71) | 0.70 s (1.19) |
| build | 0.45 s (0.80) | **0.37 s** (0.55) | 0.66 s (0.85) | 0.56 s (1.02) |
| test | 0.90 s (4.86) | **0.75 s** (1.19) | 1.50 s (1.64) | 1.22 s (2.20) |

- **The test step** went from 4.1× Go's (4.86 s against 1.19 s) to 1.2× (0.90 s against 0.75 s) in the same-run comparison.
  - It is now faster than Zig's and Rust's.
  - It is the fastest of the four on the interface edit.
  - It trails Go on the two body edits.
- **Check plus build plus test** after an edit: mylang 1.51 s, Go 1.72 s, Zig 2.48 s, Rust 2.69 s (sums of the per-step medians).
- **Peak memory** of mylang's test step: 352 MiB (leaf), 514 MiB (hub), 138 MiB (interface).

**Why the body edits read higher than §6e's 0.52–0.61 s.** It is the cache, not the load (`probe-rounds.out`, `shift.out`).
- **In the probe's fresh cache,** the first leaf and hub edits took 0.94 and 0.88 s, as in the harness. Repeating the same edits took 0.58–0.75 s.
- **A one-line shift:**
  - first time: 0.95 s;
  - again with another constant: 0.57 s;
  - a new two-line shift: 0.96 s;
  - that two-line shift repeated: 0.70 s.

  The same 31 tests reran each time.
- **The harness** empties its cache every repetition and times each edit once. So it always pays for rebuilding the code that only moved. §6e's probe repeated edits in one warm cache, and mostly did not.
- **Lever 0 in §8** is the fix.

**Program runtime, optimised builds over the 34 designs.** The geometric mean of per-design ratios; the morning run's figure is in brackets.

| binary | total (median of 10) | peak RSS | mylang's time as a multiple of this |
|---|---:|---:|---:|
| Zig ReleaseFast | 0.883 s | 80 MiB | **1.37×** (1.82×) |
| Zig ReleaseSafe | 0.973 s | 80 MiB | 1.26× (1.67×) |
| Rust `--release` | 1.004 s | 44 MiB | 1.20× (1.65×) |
| Go | 2.455 s | 74 MiB | 0.49× (0.67×) |
| mylang `--release` | 1.213 s (1.593 s) | 53 MiB | — |

That gain is copy elimination's, which was merged into `main` before this branch. The test-loop work does not touch generated code.

## 7. Order and rules

- **Order:**
  - T3b and item 4 first, one after the other: both change `test_runner.zig`.
  - Then item 5.
  - Measure after each with `experiments/test-loop-20261008/matrix.sh`, the hub, leaf, interface and comment-only edits at `--jobs 4` and at all CPUs.
- **Machine rules:**
  - builds through `scripts/build-slot.sh`;
  - timing under `flock bench-compile.lock`;
  - at most four build-heavy agents;
  - never the full gate beside a fuzz matrix;
  - the slow-step rule: anything over about 5 minutes gets a speed investigation.
- **Correctness first.** A test reported `cached` that would fail if run is a wrong answer. Every package's differential must show it can't happen before the speedup counts.
- **Repository rules** as in `CLAUDE.md`:
  - a spec tag per behavioural change;
  - at most 7 struct fields and 6 parameters;
  - `///` on pub declarations;
  - no pushes; nothing merged into `main` without the user's go.

## 8. Deferred: what is left, and when to come back

**Decision, 2026-10-08.** The user chose to stop here: merge, rerun the benchmark (§6f), and keep this section so the work can be resumed.

Where things stand, by the benchmark run of §6f:
- **The test step:** median 0.90 s, against Go 0.75 s, Zig 1.22 s and Rust 1.50 s in the same run. It was 4.1× Go's in the morning run.
  - mylang is fastest on the interface edit: 0.42 s, against Go's 1.18 s.
  - It trails Go on the two body edits: 0.90–0.95 s, against 0.70–0.75 s.
- **The whole loop after an edit** (check + build + test): mylang is the fastest of the four, because its check is 0.16 s.

The levers left cost days each, except lever 1. Lever 0, found by the benchmark, is the largest for body edits.

**Where the time goes now.** The phase probes below ran on the final branch, at load about 8, on all CPUs. They repeated each edit in a warm cache, so they leave out the cost of lever 0: about 0.3 s on a body edit's first run, which is what the benchmark times (§6f). The probes were temporary `elapsed` prints, built and then reverted (§6e).

| phase | comment or interface edit (0 rerun, wall ≈ 0.42 s) | hub edit (111 rerun, wall ≈ 0.65 s) |
|---|---:|---:|
| start, header discovery (one shared load) | 25 ms | 25 ms |
| replay of roots outside the edit's reach | to 32 ms | — |
| the shared check (uncached, whole union) | to 215 ms (≈ 180 ms of it) | to 220 ms |
| the in-process roots: selection, keys, input hashing, receipts; for the hub, also build and run | to 428 ms (≈ 210 ms) | to 649 ms (≈ 430 ms) |
| of that, the hub's largest root (`export_kicad_sch_test`, 28 tests) build | — | ≈ 280 ms: lowering, LLVM emission, `zig cc` |

**Further levers, cheapest first.** The gains are estimates from the probes above, not measurements.

0. **Objects that do not depend on where their code sits (body edits; measure first, then probably 1–3 days).**
   - **What the benchmark found** (§6f, `shift.out`): in one cache, the leaf edit's test step took:
     - 0.95 s the first time;
     - 0.57 s for a second edit with the same line shift and a different constant;
     - 0.96 s for a new, two-line shift;
     - 0.70 s for a repeat of that two-line shift.

     The same 31 tests reran each time.
   - **Probable cause:** a body edit moves every function below it in the file, and their objects carry source line numbers (debug locations). So the object cache misses for code that did not change. A repeat with the same shift finds them.
   - **The lever:** keep positions out of an object's identity, so only the edited function's object is rebuilt. Options:
     - emit line information relative to each function's start, and add the base when the unit is linked or in a small per-unit table;
     - or key objects on position-free IR, and regenerate only the line table.
   - **Verify first:** count the units compiled on a first edit against a repeat (the test runner has no build report; use the unit cache's new files, or a temporary counter). This confirms that line-shifted units are what rebuilds.
   - **Expected:** the leaf and hub test steps 0.90–0.95 s → about 0.6 s. That would be under Go's 0.70–0.75 s. The `build` step after a body edit (0.45 s) gains for the same reason.
   - **Correctness:** debug line numbers in backtraces and trap reports must still be right after a shift. Add a test that edits above a trapping function and checks the reported line.
1. **One set of keys for the whole directory run (cheap: about half a day to a day).**
   - **What repeats now:** each in-process root calls `sharedKeys` in `test_runner.zig`. That lowers the reachable program of its own ready tests (`build.buildRootsSource`) and digests every function of it (`test_runner_identity.Shared.build`). The roots share most of their import graph, so the same shared-module functions are lowered and digested once per root, 28 times on EDA.
   - **The change:** build one `Shared` over the union program once, in the directory run, beside the shared check, and hand it to each root through `test_runner_shared.View`. A root then only maps its tests to function indices and hashes their reach (`test_keys.key`).
   - **Also share:** the source digests that `checkedInputs` computes per root (every module of the root's closure is read and hashed again), and the settings key from `receipt.settings`.
   - **Measure first:** add a phase probe inside the roots' ≈ 210 ms, split across `sharedKeys`, `checkedInputs`, discovery and receipt writes. That shows how much this lever can reach.
   - **Correctness:**
     - a T3b function digest must not depend on which other functions share the lowering (it is canonical: references by name, no positions or table indices), so the keys from the union lowering must equal the per-root ones;
     - check it with a key-equality differential (union keys vs per-root keys on EDA, Lox and `tests/lang`), plus `keys_differential.py` and `batch_differential.py --oracle MYLANG_TEST_CHILDREN`;
     - a root that fails the union `Shared` (for example `UnknownMetadata`) falls back to its own `sharedKeys`.
   - **Expected:** comment and interface edits about 0.40 s → 0.25–0.30 s; hub and leaf edits save the same 100–150 ms where they wait on key derivation.
2. **An incremental shared check (days of front-end work).**
   - **The cost:** the shared check reruns the whole program's checking every time, ≈ 180 ms on EDA (about 26k lines). That includes the whole-program summary and mutation passes.
   - **Why the cache doesn't help:** the per-module semantic cache made this check 40–50 ms *slower* here (§6e), so the check runs uncached.
   - **The lever:** re-run the whole-program passes only for the modules whose interface or body digest changed, keeping the rest from the previous run.
   - **Why it matters later:** the cost grows with the project, not with the edit. At the EDA port's ~100k-line stage it could pass a second, and at that point this lever matters more than everything else here. It would also speed up `mylang check`, `run` and `build`, not only tests.
   - **Expected now:** maybe 100+ ms off every edit.
3. **Faster debug code generation for the rebuilt test file (40–80 h).**
   - **The cost:** the hub edit's critical path ends with one root's build, ≈ 280 ms of lowering, LLVM emission and `zig cc`.
   - **The plan:** this is `docs/audits/debug-llvm-plan-2026-10-07.md` (the custom debug back end, deferred until its DL package reports).
   - **Expected:** maybe 150 ms off edits that rerun tests.
4. **A resident process, a daemon or watch mode (a different product).** It keeps the checked program and the lowering in memory between edits, so there is no start-up, discovery or reload at all. Consider it only if levers 1–3 fall short at the large stages.

**The estimated ceiling with levers 0–3:**
- body edits, by the benchmark's measure: about 0.4–0.5 s, from 0.90–0.95 s;
- edits that rerun nothing: about 0.15–0.20 s, from 0.42 s.

Levers 0 and 1 are the cheap ones, and they take most of it.

**When to come back.**
- **When the EDA port reaches its ~100k-line stage** (`eda-port-benchmark-plan`): rerun the probes above at that size. If the shared check has grown past about 0.5 s, do lever 2 first. Otherwise do lever 1.
- **To get the test step under Go's on body edits** (it is 0.90 s against 0.75 s in §6f): do lever 0 first, then lever 1. Measure with the `bench.py time` protocol of §6f, which empties the cache every repetition. The warm-cache probe reads body edits about 0.3 s low.
- **When the debug back end is taken up** for build speed: lever 3 comes with it.

**How to resume.**
- **Timing:**
  - the interleaved scripts in `experiments/test-loop-20261008/` (`interleave-final.sh` is the template: two compilers, five rounds, each in its own warm cache);
  - `probe.sh` for single runs;
  - the benchmark protocol in `experiments/test-loop-20261008/bench-main/run.sh`.
- **The differentials every change must pass:**
  - `keys_differential.py` (0 missed, 0 wrong);
  - `batch_differential.py --oracle MYLANG_TEST_ISOLATE` and `--oracle MYLANG_TEST_CHILDREN`, with `--breaks`.
- **The oracle variables:** `MYLANG_TEST_KEYS=per-test`, `MYLANG_TEST_ISOLATE=1` and `MYLANG_TEST_CHILDREN=1`.
