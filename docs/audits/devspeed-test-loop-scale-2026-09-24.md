# Development-speed lane: test-loop scale — 24 September 2026

Branch `devspeed/test-loop-scale`. It started from `devspeed/integration` `fc742bd4` and
merged `devspeed/integration` again at `d7885ab2`, after the `check-at-scale` lane
landed. The lane asked why `mylang test` after a one-line body edit took 1.8 s at 50k
lines and 14.5 s at 200k, when `go test ./...` takes 1.06 s and 5.45 s, and what makes
it scale with the edit instead of the project. It owns `src/native_test_*.zig`, the
`test` command path in `src/main.zig`, and the test verdict and cache code.

## Result

Setup:

- The scale ladder: `gen_scale.py`, tiers 50k = `120 38` and 200k = `480 38`.
- The edit changes the first function body of the middle module. About half of the
  tests' closures contain that function.
- Commands: `run_scale.py TIER --langs mylang-debug --samples 3` for the edit rows, and
  the lane's `tl.py` (the same commands and edit) for cold and no-op `test`. Everything
  is pinned to `taskset -c 0-11`.
- Compilers, all ReleaseFast:
  - `fc742bd4`, the shared wave baseline;
  - `d7885ab2`, `devspeed/integration` with `check-at-scale` merged, built from an
    export of that commit;
  - this branch, built at `f65fb2e6`. The head `590df777` changes only docs.
- Rows are the minimum of 3 samples, in seconds. Go, Rust and Zig are the audit's
  figures.

| Step | fc742bd4 | d7885ab2 | **lane** | Go | Rust | Zig |
| --- | --- | --- | --- | --- | --- | --- |
| 50k edit → test | 1.87 | 1.29 | **0.37** | 1.06 | 0.64 | 0.35 |
| 50k edit → check, for reference | 0.57 | 0.10 | 0.10 | 0.13 | 0.53 | 0.41 |
| 50k no-op test | 1.00 | 0.52 | **0.041** | | | |
| 50k no-op check | 0.077 | 0.018 | 0.017 | | | |
| 50k cold test | 2.59 | 1.91 | **1.03** | | | |
| 200k edit → test | 15.81 | 12.28 | **1.24** | 5.45 | 2.58 | 0.48 |
| 200k edit → check, for reference | 2.59 | 0.41 | 0.43 | 0.47 | 2.15 | 1.10 |
| 200k no-op test | 6.58 | 3.53 | **0.19** | | | |
| 200k no-op check | 0.43 | 0.066 | 0.066 | | | |
| 200k cold test | 26.3 | 21.2 | **4.46** | | | |

Load averages (1-minute), with times in UTC:

| Runs | Load |
| --- | --- |
| Ladder, 50k (08:58–08:59) | 2.0–2.6 |
| Ladder, 200k (08:59–09:04) | 2.4–2.8 |
| `tl.py`, 50k | 1.6–1.9 |
| `tl.py`, 200k | 1.6 at the lane's start, 3.5–3.8 during the two baselines |

Another lane was running its own 200k ladder during part of this, so the integrator
should re-measure on a quiet machine.

Acceptance:

| Target | Result |
| --- | --- |
| edit → test at 50k ≤ 0.8 s | **met**, 0.37 s (0.10 s of it is the edited project's check) |
| edit → test at 200k ≤ 4 s, under Go's 5.45 s | **met**, 1.24 s; below Rust's 2.58 s too |
| no-op `test` close to no-op `check` | **met**: 0.041 against 0.017 s at 50k, 0.19 against 0.066 s at 200k. It starts one compiler child, a verdict replay. |
| cold `test` does not regress | **met**: 1.03 s (was 2.59) and 4.46 s (was 26.3) |
| tests outside the edit's closure are neither rebuilt nor re-run; tests inside it re-run | **met**, and ratcheted by a counter test (below) |

`check-at-scale` alone (the `d7885ab2` column) took edit → test from 1.87 to 1.29 s at
50k and from 15.8 to 12.3 s at 200k. This lane took it the rest of the way, 3.5× and
9.9× on top of that.

## Where the time went (before)

Method:

- `strace -f -tt -e execve,exit_group,openat` of `mylang test main.my` after the edit.
  The trace is split at process starts and exits, and at the files each step writes
  (`facts.json`, `native-test-select.txt`, `native-test-selected.json`). The script is
  the worktree's `.tmp/lane/phases.py`.
- `perf` of the parent and of the compile child for the CPU inside each step.
- Each column below is the fastest of three edits after the first; the first edit
  follows the cold run.
- The declaration check overlaps the session's check in the lane's column, so rows do
  not add up to the total.

200k, after the edit, in seconds:

| Phase | fc742bd4 (load 2.3) | d7885ab2 (load 4.4) | lane (load 4.6) |
| --- | --- | --- | --- |
| total (under strace) | 15.575 | 14.310 | 1.542 |
| parent start-up (capture, snapshot) | 0.347 | 0.103 | 0.033 |
| declaration check (`list-interfaces`) | 0.487 | 0.201 | 0.211, overlapped |
| session check + facts | 2.935 | 1.554 | 0.889 |
| parent: facts parse, graph store, plan | 2.185 | 2.543 | 0.084 |
| session: selective lower + emit | 0.458 | 0.506 | 0.113 |
| build child (manifest, codegen, link) | 0.218 | 0.295 | 0.218 |
| of which link (`zig cc` + `ld.lld`) | 0.085 | 0.102 | 0.113 |
| harness compile (`zig cc -O2`) | 0.107 | 0.115 | 0 |
| tests executed / execution span | 240 / 8.086 | 240 / 8.577 | 240 / 0.120 |
| parent tail (receipts, verify, report) | 0.519 | 0.218 | 0.066 |
| processes started / compiler children | 257 / 3 | 257 / 3 | 251 / 3 |
| links | 2 (library, harness) | 2 | 1 |

50k, after the edit:

| Phase | fc742bd4 (load 3.9) | d7885ab2 (load 3.4) | lane (load 3.0) |
| --- | --- | --- | --- |
| total (under strace) | 2.049 | 1.405 | 0.438 |
| parent start-up | 0.099 | 0.026 | 0.014 |
| declaration check | 0.138 | 0.056 | 0.060, overlapped |
| session check + facts | 0.821 | 0.445 | 0.243 |
| parent: facts parse, graph store, plan | 0.157 | 0.170 | 0.013 |
| session: selective lower + emit | 0.125 | 0.111 | 0.031 |
| build child | 0.097 | 0.099 | 0.090 |
| of which link | 0.052 | 0.053 | 0.052 |
| harness compile | 0.127 | 0.129 | 0 |
| tests executed / execution span | 60 / 0.281 | 60 / 0.276 | 60 / 0.023 |
| parent tail | 0.140 | 0.043 | 0.017 |
| processes started | 77 | 77 | 71 |

200k, unchanged rerun (after the edits above):

| Phase | fc742bd4 | d7885ab2 | lane |
| --- | --- | --- | --- |
| total (under strace) | 3.689 | 2.606 | 0.239 |
| parent start-up | 0.339 | 0.092 | 0.071 (start-up and graph load) |
| declaration check | 0.487 | 0.187 | 0 (cached) |
| validity check (`check-project`) | 0.347 | 0.076 | 0.082 (verdict replay) |
| parent tail (plan 480 tests, receipts, verify, report) | 2.355 | 2.084 | 0.086 |
| compiler children | 2 | 2 | 1 |

Right after a cold run, the old no-op was slower still: 6.6 s at 200k. Its
`check-project` re-checked every body, 2.8 s, because the verdict it needed had never
been recorded (item 3).

What that shows, in the order it cost:

1. **Tests ran one at a time, each forked from the whole parent.**
   - `Executor.execute` used `std.process.run`, which forks.
   - At 200k the parent holds the parsed facts graph and its indexes, about 2 GB
     resident, so every fork copied its page tables: 33 ms per test.
   - The 240 tests ran in sequence: 8.1 s of the 15.6 s. At 50k it was 5 ms per test
     and 0.28 s.
2. **Planning was quadratic in the project.**
   - For each selected test, the planner rebuilt a symbol index over every function in
     the graph.
   - The command also scanned every manifest entry and every schema entry to find each
     test.
   - At 200k that is 480 tests × 18,721 functions: 2.2 s after an edit, and most of the
     2.4 s tail of a no-op.
3. **A fresh snapshot path on every run defeated every path-keyed cache.**
   - Each run materialized its sources under a random `$TMPDIR/.pending/<hex>/`.
   - The compiler's check verdicts, parsed-module entries and emitted-fragment packs all
     key on the source path, so none of them ever answered a test run.
   - The validity check of an unchanged project re-checked bodies, and every edit
     re-emitted all 720 selected functions (`emitted_fragments` reused 0).
   - The `native-test-compile` session never recorded a verdict either, so even a
     stable path would have missed on the first unchanged run.
4. **The facts and schemas covered the whole program.**
   - The session rendered facts for all 18,721 functions (0.59 s at 200k), though the
     tests reach 960.
   - The result was an 11 MB graph that the parent parsed, re-serialized, hashed and
     stored: 13 MB per edit, never evicted.
   - Selective lowering rendered the schema of every public function (3 MB).
   - It marked its selection by scanning all functions for each name: 720 × 18,721
     string comparisons.
5. **The declaration check ran before the body check started.**
   `list-interfaces --contracts` (0.14 s at 50k, 0.49 s at 200k) finished before the
   compile session was spawned. It also ran again on every no-op.
6. **The source identity lexed every module twice.** Capture resolved the import
   closure with the project loader, which lexes whole files to read their headers.
   `verify` then did the same at the end: 0.33 s each at 200k.
7. **The test harness was compiled on every run** that executed a test (`zig cc -O2`,
   0.11–0.13 s). The compile session's teardown (0.03–0.11 s) also sat between the build
   and the first test.

Two candidates from the brief were checked and ruled out:

- **The per-graph `mylang build --library` child.** It costs 0.09–0.22 s and forks
  once. Its link, 0.05–0.11 s, is the build-residue lane's.
- **Re-keying verdicts on the built test's objects.** Verdict reuse is already keyed on
  the semantic closure: the implementation hash of every function a test reaches, plus
  tools, settings and limits. It re-ran exactly the tests whose closure changed, and
  keying it on built objects would only add a build before every decision. A module
  constant is a getter function in the checked program, so an edit to it reaches its
  readers' closures like any other callee.

## What changed

Five commits on the lane plus the merge: `7fb00053`, `16d75d09`, `0bfef352`, the merge
`3d6ec564`, `f65fb2e6` and `590df777`. Every behaviour has a SPEC bullet and a test.

1. **Parallel test execution (`NATIVE-TEST-PARALLEL-1`, `native_test_execute.zig`).**
   - `executeAll` writes every request first. Then `width` workers — this thread and
     `width − 1` more — each run one child at a time:
     - start it through `qbe_build_spawn.start` (`clone(CLONE_VM | CLONE_VFORK)`), so a
       start copies nothing of the parent;
     - poll its stderr pipe until it closes, or until its `--timeout-ms` deadline
       passes, which kills it and reports `Timeout`;
     - reap it.
   - Workers keep a child's start-up scratch in a private arena, reset after each child.
   - The runner takes `--response FILE` and points its protocol channel (fd 1) at that
     file, so a child needs no stdout pipe. Without the flag it still answers on stdout,
     which benchmarks and `mylang invoke` keep using.
   - Outcomes land in their call's slot, and they are parsed on the calling thread after
     every worker has joined.
   - The width is `--jobs`, then `MYLANG_JOBS`, then the cores the run may use, capped by
     how many per-test ceilings `MemAvailable` holds (`memory_budget.workers`).
   - A directory run passes each child `--jobs max(1, width / programs in flight)`.
2. **Harness cache (`NATIVE-TEST-RUNNER-1`).**
   - `execute.runner` publishes the compiled harness by rename under
     `<cache>/runner/<BLAKE3 of the sources, the flags and the zig stamp>`.
   - `--no-cache` compiles a private copy.
   - The trace records a compile as `native-test-runner`, so a test can count it.
3. **Stable snapshot path and a recorded verdict (`NATIVE-TEST-STABLE-1`).**
   - `snapshot.claimStable` gives each (cache, project root, entry) triple one path,
     `$TMPDIR/.pending/snapshot-<key>`.
   - A run claims that path through the `.owner` exclusive-lock protocol the scratch
     sweeper already honours. A claim clears whatever a killed run left.
   - While another run holds the claim, a run of the same project uses a fresh private
     path, as before.
   - Release removes the tree and then drops the lock, so `NATIVE-SCRATCH-ROOT-2`'s
     "nothing left behind" still holds.
   - The `native-test-compile` session records the `check-project` verdict of the
     project it checked (`rememberSessionVerdict` in `main.zig`), unless a configured
     `warnings: "deny"` rejects that project.
   - Together, these make an unchanged rerun's validity check a verdict replay. They
     also let an edit's emission reuse every unchanged unit.
4. **Declaration contracts cache (`NATIVE-TEST-INTERFACES-1`).**
   - The answer of the production `list-interfaces --contracts` is kept in one sealed
     slot per test entry under `<cache>/interfaces/`.
   - The slot records the resolved source identity it answers for. That identity covers
     the resolved sources and the configuration.
   - Only a clean answer is kept: exit status 0, and nothing on stderr but `--report`
     records.
   - `--force` and `--no-cache` always run the check.
5. **Overlapped preparation (`NATIVE-TEST-OVERLAP-1`).**
   - When no case configuration names a provider fixture, `speculate` loads the stored
     graph, or begins the compile session, before the declaration check.
     `Compile.begin` sends the facts request without waiting for the answer.
   - The body check and the declaration pass therefore run side by side.
   - If the declaration check fails, or the selection never uses the session,
     `Compile.discard` kills it without forwarding its output.
   - `Compile.quit` lets the session tear down while the library links, not before the
     first test.
6. **Closure-scoped facts (`NATIVE-TEST-FACTS-2`).**
   - The session's facts describe only the dependency closure of the functions a test
     run can select: every discovered test and every exported `bench_` function. The
     schema holds just their signatures.
   - Code: `emitNativeTestFactsScoped` and `testEntryRoots` in `project_compile.zig`,
     and the closure walk in `native_test_facts.render`.
   - The address-taken target set is a walk of every body. It is now collected only
     when a described or selected body invokes a function value.
   - Selective emission describes only its selected roots (`selectedRoots`), and marks
     its selection with one table lookup per name (`selectFunctions`).
   - The one-shot `native-test-graph` command keeps whole-program facts, which
     `mylang invoke` plans against.
   - The graph is stored as the bytes the session wrote, not parsed and re-serialized.
     At 200k a stored graph is 0.65 MB instead of 13 MB.
7. **Check summaries in the session (`NATIVE-TEST-SUMMARY-1`, after the merge).**
   - The `native-test-compile` session now reads its entry's check summaries facts-only,
     like the build frontend (`CHECK-SUMMARY-2`). This is one arm of `openSummaries` in
     `main.zig`.
   - It still checks every body, because facts and lowering need the checked tree.
   - The effect and mutation passes walk only changed bodies.
   - Measured at 50k on the merged tree, it took the session's check and facts from
     0.34 to 0.24 s, and edit → test from 0.45 to 0.32 s.
   - Before the merge, the lane's edit → test at 200k was 3.1 s, most of it the
     session's check; after the merge and this change it is 1.24 s.
8. **Planning index (`NATIVE-TEST-PLAN-2`).**
   - `planner.Index` reads a graph once — symbol positions, resolved dependency edges,
     facts — and each plan walks only its own closure over it.
   - The command looks tests up in per-graph tables, and computes each module's contract
     identity once.
   - The plan key is BLAKE3 (`native-test-plan-v2`).
   - A published receipt leaves out the closure's symbol list, which its key already
     binds.
9. **Import memo and a cheap verify (`NATIVE-TEST-IDENTITY-1`).**
   - The resolved source identity walks memoized import lists (`snapshot.Imports`). The
     memo is one sealed file per entry under `<cache>/imports/`, keyed by each module's
     BLAKE3 and role.
   - A module the memo lacks is loaded alone to read its header. Anything the walk
     cannot resolve falls back to the full load.
   - File fingerprints are BLAKE3.
   - `verify` compares the re-read tree byte for byte with the capture, and resolves
     imports again only if something changed.
10. **Docs.** `docs/tooling/guest-tests.md` now covers:
    - concurrency and `--jobs`;
    - the stable snapshot path;
    - what an unchanged rerun runs;
    - what an edit rebuilds.

    `NATIVE-TEST-6` now says the declaration check runs only when its contracts are not
    cached.

## After

The lane's column in the tables above shows where an edit now spends its time at 200k:

| Phase | Seconds |
| --- | --- |
| session check, which checks every body, plus facts | 0.89 |
| declaration check, overlapped with the session | 0.21 |
| build child: 0.11 s link, 0.008 s codegen, the rest manifest and planning | 0.22 |
| selective lowering and emission of the 720-function closure | 0.11 |
| 240 test processes | 0.12 |
| planning | 0.08 |
| tail | 0.07 |
| start-up | 0.03 |

At 50k the session check is 0.24 s of the 0.44 s. The rest is 0.09 s of build child
(0.05 s link), 0.03 s of lowering, 0.02 s of tests, and a few milliseconds each of
planning, start-up and tail.

`mylang check` after the same edit takes 0.10 s at 50k and 0.43 s at 200k. The
difference is the session's full body check (item 7), plus the build.

## Ratchet and correctness tests

The ratchet is a deterministic-counter CLI test in `test/integration.zig`: *"after a
body edit in module k exactly the tests that depend on k are rebuilt and re-run, and an
unchanged rerun only replays a verdict"*. It tags `NATIVE-TEST-SCALE-1`,
`NATIVE-TEST-FACTS-2` and `NATIVE-TEST-SUMMARY-1`.

The fixture is a four-module chain. The test of module K reaches `f` in modules 0..K,
and every module has an `unused` function no test reaches.

| Step | Asserted counters |
| --- | --- |
| cold | 4 executed. The stored facts name `m0::f` and not `m2::unused`. |
| unchanged | 0 executed, 4 cached. Exactly one compiler child, `check-project`, whose `checked_bodies` is `skipped` (a verdict replay). No `list-interfaces`, `native-test-compile`, `build` or harness compile. |
| body edit in module 1 | 3 executed (modules 1–3), 1 cached. One session, one build, no harness compile. `lowered_functions` = 7: the three tests and the four `f`. Emitted fragments reused > 0 and performed < 7. The session's `checked_bodies` reused = 0, because summaries served it. |
| edit to `unused` in module 2 | 0 executed, 4 cached, no build |

A second CLI test covers correctness after an edit. Making `f` in module 1 divide by
zero:

- fails exactly the three dependent tests;
- gives each a trace that names `in m1::f at m1.my:6:`.

Then:

- an unchanged rerun executes the three failures again, because a failure is never a
  receipt;
- `--filter test_m2` selects one case.

The existing C4, P1, R3, PURE-SKIP and scratch-staging CLI tests pass unchanged.

Unit tests (`zig build test-native-tests`, 198 passed):

- `native_test_execute`:
  - A parallel run over six fake children returns every outcome in its call's slot. Four
    children answer, one outlives a 400 ms timeout, and one exits 3 with stderr
    (`NATIVE-TEST-PARALLEL-1`).
  - The harness is compiled once per source and tool stamp and reused after that, and
    compiled privately when there is no cache (`NATIVE-TEST-RUNNER-1`).
- `native_test_directory`: a directory run splits its width between the programs in
  flight and passes `--jobs` to each child.
- `native_test_snapshot`:
  - The stable root is one path per seed, held by one run at a time, cleared of a killed
    run's files, and gone after release (`NATIVE-TEST-STABLE-1`).
  - The memoized identity equals the full-load identity through edits, a newly imported
    module and a damaged memo, and a warm capture learns nothing
    (`NATIVE-TEST-IDENTITY-1`).
- `native_test_session`: contracts are reused for an unchanged identity, one slot per
  entry, and never for a warning, a refusal, `--force` or `--no-cache`
  (`NATIVE-TEST-INTERFACES-1`).
- `native_test_command`:
  - The session is spawned before the declaration check and consumed by the graph.
  - An unused session is killed.
  - A provider fixture keeps the ordered preparation (`NATIVE-TEST-OVERLAP-1`).
  - A module's contract identity is computed once.
- `native_test_plan` / `native_test_receipts`, for `NATIVE-TEST-PLAN-2`:
  - One index plans every entry as a fresh plan does, and fails only the plans that
    reach a malformed unit.
  - Index construction releases everything on each allocation failure.
  - A receipt without the closure list still hits.

I also compared behaviour by hand against the baseline compiler on one fixture. It
holds a pass, a wrong result, a division trap, a failed `assert` with a message, a test
that prints and fails, and a step-limit spin. Output, trap traces and exit status were
identical, and so was the `Timeout` at `--timeout-ms 100`.

## Known gaps and what remains

- **The session's full body check is now most of the loop:** 0.24 of 0.44 s at 50k,
  0.89 of 1.54 s at 200k (under strace).
  - Facts and selective lowering both read the checked tree, so the session checks
    every body.
  - The next lever is to check fully only the bodies the selected closure lowers, and
    serve the other facts from summaries. It crosses into the check and emission code.
- **The first edit after a cold run is slower than the next ones.** The ladder's first
  samples were 0.56 s at 50k and 2.04 s at 200k, against 0.37 and 1.24 s later.
  - The cold run links every test's closure; the edit run links only the affected ones.
    Most QBE batches therefore have different members once, and recompile.
  - Later edits with the same affected set hit.
  - Keeping batch objects valid across member changes is build-residue work.
- **Lowering re-lowers the unchanged part of the affected closure** (0.03 s at 50k,
  0.11 s at 200k). Emission reuses every unchanged unit, but bytecode lowering has no
  cache keyed by checked body.
- **The link runs through the `zig cc` driver** (0.05 s at 50k, 0.11 s at 200k). The
  driver probes the host C compiler (`cc -E -Wp,-v`, `cc -print-file-name=crt1.o`)
  before running `ld.lld` on every link. This is the build-residue lane's.
- **A test process costs about 1.7 ms**: `exec`, dynamic loading and `dlopen` of the
  test library. A fork server that loads the library once would cut that, but a test
  would no longer start from a fresh `exec`. Not done.
- **The no-op still plans every test** (0.07–0.09 s at 200k: 480 receipt reads,
  contract identities, a byte comparison of the tree). A whole-run receipt keyed by the
  resolved identity could skip it.
- **The checked-facts graph store still has no eviction.** This predates the lane. Each
  edit adds one graph, now 0.65 MB at 200k instead of 13 MB. The new interfaces cache
  and import memo keep one slot per test entry.
- **Provider fixtures keep the ordered preparation.** A case file that names a provider
  turns the overlapped check off, by design (`NATIVE-TEST-5`).
- **Receipt writes race on the results directory's `.pending` folder** when a directory
  run's children write receipts at the same moment. This predates the lane. The retry in
  `Context.temporary` handles it, and a Debug compiler prints an `unexpected errno`
  trace for it now and then.

## For the integrator

- **Changes outside the lane's own files are small:**
  - `src/main.zig`:
    - The `native-test-compile` arm of `listModulesWithCache` calls the new
      `rememberSessionVerdict`.
    - `emitNativeTestFacts` takes a `FactsScope`: the session asks for `.closure`,
      `native-test-graph` for `.all`.
    - `openSummaries` lists `native-test-compile` with the lowering commands.
  - `src/project_compile.zig`:
    - New: `FactsScope`, `emitNativeTestFactsScoped`, `testEntryRoots`,
      `selectedRoots`.
    - `emitQbeSelected` computes its roots after the selection, and `selectFunctions`
      uses a name table.
    - The merge with `check-at-scale` conflicted only in the file's import lines.
  - No change to `src/qbe_build*.zig`. Execution uses `qbe_build_spawn.start`, `pump`
    and `reap` as they are.
- **SPEC.md:**
  - Ten new bullets after `GUEST-TEST-GC-STRESS-1`: `NATIVE-TEST-SCALE-1`,
    `-PARALLEL-1`, `-RUNNER-1`, `-STABLE-1`, `-INTERFACES-1`, `-OVERLAP-1`, `-FACTS-2`,
    `-PLAN-2`, `-IDENTITY-1` and `-SUMMARY-1`.
  - One sentence of `NATIVE-TEST-6` is amended.
- **Cache formats:**
  - The plan key moved to BLAKE3 (`native-test-plan-v2`), so every existing test
    receipt misses once.
  - New directories under the test cache: `runner/`, `interfaces/` and `imports/`.
  - Stored graphs are smaller, because they are closure-scoped.
  - While a run holds it, the source snapshot lives at `$TMPDIR/.pending/snapshot-<key>`.
- **`--jobs` means a little more now.** It also bounds the test processes of a single
  program, and a directory run passes `--jobs` to each child.
- **Measurement scripts** are in the worktree's `.tmp/lane/`:
  - `ladder.sh` and `final_ladders.sh`: the official `run_scale.py` with a chosen
    compiler;
  - `tl.py` and `final_tl.sh`: cold, no-op and edit timings;
  - `basetrace.sh` and `final_traces.sh`, with `phases.py` and `phasetable.py`: strace
    phase splits;
  - `lowerprobe.sh`: selective-lowering timings;
  - the raw results: `ladder-*.out`, `results-*.json`, `tl-*.out` and `phases-*.jsonl`.

## Gate

Run at `590df777`, the head before this report, through the machine's gate slot. The
report commit adds only this file.

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 90/90 steps; 1,877 tests passed (the rest are other shards' selections) |
| `zig build test-qbe --summary all` | 51/51 steps, 372/372 tests |
| `zig build test-qbe-build --summary all` | 33/33 steps |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |
