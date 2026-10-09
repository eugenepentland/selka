# One key derivation per directory run: package TK, 2026-10-08

Status: **ready for Codex.** This is lever 1 of `docs/audits/test-loop-plan-2026-10-08.md` §8, which the user asked to have planned on 2026-10-08.
- **Size:** one package, about 6–10 hours, measurement and differentials included.
- **What it changes:** only how in-process directory-run roots derive their receipt keys. Verdicts, keys and receipts must come out exactly as they are now.
- **It starts with a measurement that can stop it** (TK-0). The gain depends on numbers we do not have yet.

## Launch instruction (for Codex)

> Implement package TK of `docs/audits/test-keys-once-plan-2026-10-08.md` (branch `claude/test-keys-once-plan`) on `codex/test-keys-once`, created from `claude/test-keys-once-plan`.
> - Start with TK-0's measurement and apply its decision rule before writing product code.
> - Follow §7's rules.
> - Never merge into `main` and never push.
> - Finish with TK's report (§6) and stop.

## 1. Why

**Where the test step stands.** It was measured by the benchmark on `main` `6ff48bb65` (`test-loop-plan` §6f, `experiments/test-loop-20261008/bench-main/`):

| edit | tests rerun | mylang | Go |
|---|---:|---:|---:|
| leaf body | 31 | 0.95 s | 0.70 s |
| hub body | 111 | 0.90 s | 0.75 s |
| interface (new public function at the end of the hub module) | 0 | 0.42 s | 1.18 s |
| comment at the end of the hub module (probe, not in the benchmark) | 0 | 0.42 s | — |

**What an edit that reruns nothing still costs.** The phase probes of `test-loop-plan` §6e/§8 split the ≈ 0.42 s of an interface or comment edit:

| phase | time |
|---|---|
| start and header discovery | 25 ms |
| replay of the roots the edit cannot reach | to 32 ms |
| the shared check of the project's roots (`test_runner_union.together`) | ≈ 180 ms, ending at 215 ms |
| the 28 roots that import the edited module, run in process on the worker pool, until each finds its whole-file receipt | ≈ 210 ms, ending at 428 ms |

The last row is this package's target.

**What repeats in each root.** Each of those 28 roots runs `test_runner.finish` on its share of the one shared check (`test_runner_shared.View`).

| | work | where | shareable? |
|---|---|---|---|
| a | **Lowering of the root's ready tests and digests of every lowered function.** `sharedKeys` → `rootsFor`, `build.buildRootsSource`, `test_keys.Shared.build`. The roots import much the same graph, so the shared modules' functions are lowered and digested once per root, up to 28 times. | `test_runner.zig` `sharedKeys` | yes: TK-1 |
| b | **The type schema of the whole program** (`property_schema.definitions(checked.program)` then `property_types.Schema.init`), for a root with a test that generates or encodes values. In a shared check the program is the union, larger than the root's own. | `sharedKeys` | yes: TK-2 |
| c | **The digests of every module in the root's closure** (`checkedInputs` → `receipt.capturedModules`, hashing in-memory sources), then the end-of-run `receipt.unchanged`, which re-reads and re-hashes them from disk. | `finish` | start digests yes, end check no: TK-3 |
| d | discovery, `screen`, case settings, `receipt.hit` per key, the report | `finish`, `select` | small; measure only |

**Why the gain is uncertain.**
- **Today:** the 28 derivations of (a) run *in parallel* on the worker pool, so only the critical root's derivation is on the wall clock.
- **After TK-1:** one lowering of the union runs *once*, but serially. The union's closure is not much larger than the largest root's.
- **Consequence:** TK-1 saves a lot of CPU but possibly little wall time unless the union work is parallelised or overlapped (TK-1 parts 4 and 5).

TK-0 measures this before anything is built.

**Expected:** no-rerun edits 0.42 s → 0.30–0.35 s, and up to 0.25 s if (a) dominates and overlaps well. Body edits save the same amount where they wait on key derivation.

**The bigger lever for body edits is lever 0:** objects carry line positions, so code that only moved is rebuilt. It is not part of this package.

## 2. Scope

**In:**
- the key derivation of roots that a directory run runs in process from a shared check (NEW-CORE-TEST-UNION-1);
- sharing (b) and the start digests of (c) when TK-0 says they matter;
- the tests, the SPEC bullet, the documentation sentence and the evidence.

**Out:**
- children (`MYLANG_TEST_CHILDREN=1`, ineligible roots);
- single-file runs;
- the shared check itself (lever 2);
- code generation and objects (lever 0, lever 3);
- what a key binds. It is a hard requirement that every key stay bit-identical to today's: no key version bump and no receipt churn.
- `src/core/ir.zig`, which is frozen.

## 3. Steps

### TK-0. Measure (about 1–2 h; decides the rest)

1. **Instrument a scratch build.**
   - Add temporary phase timers using `std.Io.Timestamp.now(io, .awake)`, the monotonic clock `driver.zig` already uses.
   - Time in each in-process root: `start`, the replay lookup, `checkedInputs`, discovery and `case_settings`, `select` without `sharedKeys`, and `receipt.unchanged`. Inside `sharedKeys`, time `rootsFor`, `buildRootsSource`, `Shared.build`, the schema, and the per-test `key` loop.
   - Print one line per root to stderr at the root's end: name, start offset from process start, and each phase.
   - Also time, once and in the directory run after `together`, an experimental **union lowering**: `buildRootsSource` over every member root's discovered cases, followed by `Shared.build`.
   - Keep the instrumentation out of `src/` commits. Save it as `experiments/test-keys-once-<date>/phases.patch` so it can be reapplied.
2. **Build and time.**
   - Build a ReleaseFast compiler (`zig build -Doptimize=ReleaseFast --prefix …` through `scripts/build-slot.sh`).
   - Time EDA (eda-bench stage 1, `mylang/`, `mylang test src` with the harness's flags, all CPUs except 2, 3, 10 and 11) for four edits: comment at the end of `src/sexpr_parser.my`, the harness's interface edit, its leaf edit and its hub edit.
   - **Time first edits only.** Warm a cache once, keep it as a template, and copy the template to a new directory for every timed run. A repeated edit in one cache reuses objects and reads body edits about 0.3 s low (`test-loop-plan` §6f, `shift.out`).
   - Run 5 rounds, under `flock /run/user/1000/mylang-slots/bench-compile.lock`.
3. **Record:**
   - per phase, the sum over roots (CPU) and the critical root's value (wall);
   - the union lowering's cost;
   - the load average.
4. **Decision rule.** Write the decision in the report, with the numbers.
   - **TK-1** goes ahead if the critical root's (a) is at least 40 ms *and* the union lowering plus digests, done once, costs at most the critical root's (a) minus 30 ms. If the second test fails but the sum of (a) over roots is at least 300 ms, TK-1 goes ahead only with part 5 (overlap) planned from the start.
   - **TK-2** goes ahead if (b) on the critical root is at least 15 ms. On EDA it may be zero: most of its tests return `bool` and take no parameters.
   - **TK-3** goes ahead if the start digests of (c) on the critical root are at least 15 ms.
   - **If nothing qualifies,** write the report with the measurements and stop. That is a valid outcome.

### TK-1. One lowering and one set of digests for the shared check's roots

1. **Where.**
   - A new file, `src/core/test_runner_union_keys.zig`, keeps `test_runner_union.zig` and `test_runner.zig` from growing.
   - It computes a `UnionKeys` value right after `test_runner_union.together` checks the members.
   - `test_runner_shared.View` gains `keys: ?*const UnionKeys` (null means derive as today).
   - `sharedKeys` takes the union path when `view.keys` is set and covers every ready case of the root; otherwise it runs unchanged.
2. **What gets lowered.**
   - Run discovery for each member root as its own run will (`discover.within`, or the same call `discoverLoaded` makes, with the member's closure modules).
   - Keep the cases that `publishes` accepts (no `Host`) and that `screen` accepts under the member's case settings.
   - Lower them all once with `rootsFor` (which adds the invariant roots of generated parameters) and `build.buildRootsSource(program, roots, src)`. Use the union's own `checked.src`, the unrooted one.
   - Record a map from typed `FunctionId` to lowered index. `rootsFor` lists roots first, so a root's index in the roots list is its lowered index, as `sharedKeys` already assumes.
   - **If the builder refuses, or `Shared.build` returns `UnknownMetadata`,** set `keys = null` for the whole project: every root derives as today. Count it in the report.
3. **Positions: the one thing that differs between roots.**
   - A digest locates positions as path, line and column (`Canon.locate`). A span in the merged source's first segment (span 0 in practice, the synthetic entry `mylang_directory_run`) is located at the *root's* file in a root's own run, because `test_runner_union.rooted` relabels that segment. So a union digest of a function that locates such a span would differ from the root's.
   - Every other position, string, type and callee is root-independent:
     - a callee is hashed by name and signature, not by its body's digest, so one function's digest never depends on another's;
     - the lowering reads the source only to resolve embedded assets (`build_bytes.blob`).
   - **So:** `Shared.build`, in `test_runner_identity.zig`, also returns the indices of functions whose digest located a span in the first segment.
   - For each root, recompute only those functions' digests, with a `Canon` prepared over the same lowered module and the root's rooted locator (`pipeline.locator(&view.checked.src)`). Overlay them on the shared digests before `reach`.
   - Expect few or none. The report must give the count on EDA, Lox and `tests/lang`.
4. **Parallel digests (if TK-0 shows `Shared.build` is a large part of the union cost).**
   - Shard the per-function loop of `Shared.build` across the run's workers, each shard with its own `Canon`. The `Canon` memo is only a cache, so the digests are the same by construction.
   - The lowering itself stays serial.
5. **Overlap (only if the serial union work is still on the critical path).**
   - Start the union computation as a task right after the check. A root that reaches `sharedKeys` before it finishes waits for it. Its discovery, screening and input digests run meanwhile.
   - Use the `std.Io` primitives already in the directory runner (`Io.Semaphore`, `Io.Mutex`, or an `Io` future). Never block a worker on anything that waits for that same worker.
6. **The per-test part stays per root:** `testTarget`, `entryDigest`, `schemaDigest` and `test_keys.key` with the root's `source_path` and `base`. Then the whole-file key, unchanged.

### TK-2. One schema per shared check (if TK-0 qualifies it)

- `property_schema.definitions` and `property_types.Schema.init` depend only on the checked program, which every member shares. Build the schema at most once per shared check, lazily under a mutex, on the first root that needs it.
- Expose it through `UnionKeys`, or a sibling in the `View`, and keep it read-only afterwards.
- `schemaDigest` is already scoped to the types a test's parameters and result reach (NEW-CORE-TEST-KEYS-1), so a root's digest from the union schema equals the digest from its own. Verify it in the TK-1 differentials anyway.

### TK-3. Start digests once (if TK-0 qualifies them)

- The shared check holds every member module's source in memory. Digest each module once in the directory run: path → digest, including its embeds as `receipt.loaded` records them.
- Let `capturedModules` take a root's digests from that map.
- **Leave the end-of-run `receipt.unchanged` per root.** It must re-read the files after the root's own execution, and sharing one read across roots that end at different times would weaken the guarantee.
- If TK-0 shows `unchanged` is large, write that in the report as a follow-up. Do not change it in this package.

### TK-4. Timing and the report

- **Interleaved first-edit timing:** `main` against TK, 5 rounds, the four edits of TK-0, with cache templates copied per run.
- **The benchmark harness:**
  - create a worktree from eda-bench branch `claude/eda-bench-newcore` (`d45e0cd`) as `codex/eda-bench-tk`;
  - re-pin `[mylang-new]` to the TK compiler;
  - run `bench.py time mylang-new --stage 1 --repeat 3` under the bench lock.
  - Do not touch the Claude worktree `eda-bench-wt/claude-eda-bench-newcore`.
- **Where:** `experiments/test-keys-once-<date>/`, within the 10 MB evidence limit.

## 4. Owns

- **Code:**
  - `src/core/test_runner_union_keys.zig` (new; reachable from `src/core/root_test.zig`);
  - `src/core/test_runner_shared.zig` (`View`);
  - `src/core/test_runner_union.zig` (`together` builds `UnionKeys`);
  - `src/core/test_runner.zig` (`sharedKeys`, plus `finish` and `checkedInputs` for TK-3);
  - `src/core/test_runner_identity.zig` (`Shared.build` reports the first-segment functions, and a per-root re-digest; optional sharding);
  - `src/core/test_runner_receipt.zig` (TK-3 only).
- **Docs and evidence:**
  - `SPEC.md`;
  - `docs/tooling/guest-tests.md`: one sentence in "Directory runs";
  - the Status line of this plan;
  - `experiments/test-keys-once-<date>/`.
- **Nothing else.** In particular, not `ir.zig`, the front end, the build or emit modules, or `test_runner_execute.zig`.

## 5. Gates

**Spec.**
- A new bullet `[NEW-CORE-TEST-KEYS-3]`: a directory run that checks roots together lowers those roots' ready tests once and digests each function once. Each root re-digests, with its own locations, only the functions that locate a position in the shared entry. Every key equals the key the root's own lowering gives (NEW-CORE-TEST-KEYS-1). A refused or unrecognised union lowering leaves every root deriving its own keys.
- Add `[NEW-CORE-TEST-SCHEMA-1]`, or extend the bullet, for TK-2 if it is done.
- One `// spec:` test per bullet; further tests carry `// spec-case:`.

**Zig tests** (in the new file or in `test_runner_project_test.zig`; straight-line bodies, no `if`, `while`, `switch` or extra `for` at the top level):
1. Two roots sharing a dependency, one of them with a span-0 constant in a test: every ready test's union key equals its key from the root's own `sharedKeys`.
2. A union whose lowering the builder refuses: `keys` is null and every root's keys equal today's.
3. `Shared.build` reports the first-segment functions, and re-digesting them under a rooted locator gives the root's own digests.
4. For TK-2: the union schema's digest equals the root's own.
5. Each new `catch` gets a test that names its enclosing function (Guardian).

**Key equality on real corpora: the receipt-set differential.**
- Receipts are files named by key, in `<cache>/tests/receipts-v2/`.
- Write `experiments/test-keys-once-<date>/receipt_differential.py`. For each corpus of `experiments/test-loop-20261008/batch_differential.py` (`eda`, `lox`, `lang`, `core`):
  1. use a fresh cache;
  2. run once with `--force` in the default mode (in process, union keys);
  3. list the receipt files;
  4. run again with `--force` and `MYLANG_TEST_CHILDREN=1` (each root in its own process, with its own check and its own lowering);
  5. require that **no new receipt file appears**;
  6. repeat with the order reversed in another fresh cache.
- Equal sets in both orders mean equal keys. `MYLANG_TEST_CHILDREN` is already left out of receipt keys.
- **Required: 0 extra receipts in both orders.**
- Add the same check after each of 6 seeded edits, reusing `keys_differential.py`'s edit sites.

**The existing differentials, rerun with the TK compiler:**
- `keys_differential.py` (eda, lox, lang): 0 missed and 0 wrong;
- `batch_differential.py --oracle MYLANG_TEST_CHILDREN --breaks 4` (eda, lox, lang): 0 differences;
- `batch_differential.py --oracle MYLANG_TEST_ISOLATE` on eda: 0 differences.

**Repository gate:**
- `zig build test --summary all` (88/88) and `zig build fmt-check`. `test-qbe` and `test-qbe-build` no longer exist.
- Never run the full gate beside a fuzz matrix.

**Merge criterion** (the report states whether it was met):
- first-edit medians against `main`: the comment and interface edits at least 40 ms faster;
- the leaf and hub edits no more than 20 ms slower;
- every differential at 0.

If the code is correct but the criterion is missed, say so. The branch then stays unmerged with its numbers.

## 6. Report

`experiments/test-keys-once-<date>/REPORT.md` should give:
1. TK-0's phase table and the decision it took;
2. what was built (TK-1 parts 1–6, TK-2, TK-3), and the first-segment function counts;
3. the differentials;
4. the gate;
5. the interleaved first-edit table and the harness's `time` medians, with load;
6. whether the merge criterion was met;
7. anything surprising: for example `unchanged`'s cost, or a refusal of the union lowering on a corpus.

Subagents cannot write `REPORT.md` files. If a subagent writes the report, it returns the text and the coordinator writes it.

## 7. Rules

- **Branches:** work only on `codex/test-keys-once` (and `codex/eda-bench-tk` in eda-bench). Never merge into `main`, never push, and never modify Claude worktrees or branches.
- **Builds:**
  - every build through `scripts/build-slot.sh`;
  - ReleaseFast installs for timing, and Debug for the gate;
  - at most four build-heavy processes.
- **Timing:**
  - under `flock /run/user/1000/mylang-slots/bench-compile.lock`, on CPUs other than 2, 3, 10 and 11;
  - record the load average beside every timing;
  - TMPDIR and every cache on disk, never `/tmp` on tmpfs.
- **Guardian** (it blocks inside `zig build test`):
  - a spec tag per behavioural change;
  - structs ≤ 7 fields; functions ≤ 6 parameters;
  - `///` on every `pub` declaration;
  - explicit error sets;
  - no `std.debug.print` in committed code;
  - no hardcoded `std.heap.page_allocator`;
  - no wall clock outside sanctioned code (the TK-0 timers stay in the patch file);
  - every new file reachable from a Guardian root.
- **Correctness first.** A test reported `cached` that would fail if run is a wrong answer. Every differential must be at 0 before any timing counts.
- **The slow-step rule:** a step that takes more than about 5 minutes gets a speed investigation before it is repeated.
