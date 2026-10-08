# Test loop after an edit: plan for items 4 and 5, 2026-10-08

Status: **items 1–3 are done** (§2). This plan covers what is left: item 4 (batch a program's tests into one process) and item 5 (one-process directory runs). Two smaller pieces from the investigation, T3b and the jobserver fallback, are included because they feed the same goal. Nothing in this plan is implemented.

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
