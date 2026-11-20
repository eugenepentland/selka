# A test run that costs what the edit costs (plan, 9 November 2026)

**Status:** asked for by the user on 9 November, after the audit of the language against its goals (answered in the session,
not written up) found the test loop to be the largest gap: `mylang test` reruns exactly the tests an edit can reach, but
deciding that costs far more than the edit, and the cost grows faster than the project. This plan removes that cost. The
user answered its three decisions on 9 November (section 8) and said on 10 November that the other compiler work had
finished and the lanes could start. Section 10 has the re-check against main `fef979d1b` and the lanes.

**Part B (section 9)** was added the same evening at the user's request ("add these items to the plan"): the ownership model
stated as four verbs and three rules, the holes where the compiler does not follow them, and one verdict for `check` and
`build`. The user accepted its three open decisions as recommended the same evening (section 9.7); the fourth waits for the
spike. It started on 10 November with Part A (section 10).

It continues lane T (`experiments/test-keys-20261106/status.md`), whose three open items are stages 3 and 4 here. Scripts:
`experiments/test-loop-20261109/` (`gen.py`, `probe.py`, `profile.sh`). Evidence:
`~/ai/canopy/mylang-evidence-archive/experiments/test-loop-20261109/`.

## 1. What a test run costs today

**The probe.** `gen.py N` writes a project of N modules. Each module imports a module every module imports (`common`) and two
others, and declares ten functions and two tests; `main.my` imports them all. The compiler is the pin `g3-s1b5-f5834a8f`
(ReleaseFast, main `47f39d067`) with private stores. The machine was loaded (load 14 to 40), so the sound number is user
instructions (`perf stat --no-scale -e instructions:u`, the process tree, P cores); CPU seconds are indicative.

Billions of instructions, with CPU seconds in brackets:

| Step | 100 modules, 200 tests | 400 modules, 800 tests | 1,600 modules, 3,200 tests |
| --- | ---: | ---: | ---: |
| Cold directory run, every test runs | 15.4 (7.5) | 46.7 (23.6) | 217.9 (132) |
| Unchanged run | 0.07 | 0.25 | 1.22 (0.2) |
| A comment line added to `common`: 0 tests rerun | 0.65 (0.2) | 2.67 (0.6) | 13.2 (3.6-4.3) |
| A body in `common` no test reaches: 0 rerun | 0.65 (0.2) | 2.67 (0.7) | 13.2 (2.9) |
| A leaf body: **2 tests rerun** | 2.0 (0.5) | 8.7-9.7 (3.4-4.0) | **54-69 (35-46)** |
| A body in `common` half the tests reach | 2.0 (0.7) | 9.3 (3.8) | 62.9 (39) |
| The same leaf edit, `mylang build main.my` | 0.42 (0.15) | 1.21 (0.29) | 4.2-4.5 (1.1-1.35) |
| The same leaf edit, `mylang test` of the leaf file alone | | 0.50 (0.11) | 0.69 (0.2) |

The selection is right in every row: 2 tests, none, none, and exactly the half that reaches the body. Three things are wrong.

1. **Rerunning 2 tests costs what rerunning 1,600 does.** At 1,600 modules a leaf edit costs 54 to 69 G, a quarter to a third of a
   cold run of everything, 13 to 16 times the build of the whole program after the same edit, and about 80 to 100 times a run
   of the leaf file alone.
2. **The cost grows faster than the project.** From 400 to 1,600 modules the leaf edit grows about 6 to 8 times, for 4 times
   the code. The wall time was 68 to 114 s at 1,600 modules; part of that is the loaded machine.
3. **A run with no rerun still costs 3 times the build** (13.2 G against 4.2 G at 1,600 modules).

**The port** (lane T, 6 November, 1,443 tests in 162 entries, `experiments/test-keys-20261106/status.md`): a comment edit reruns
0 tests and costs 70 to 81 CPU-s; a body edit that reaches 389 tests costs 199 CPU-s. The only change to the test runner
since is two lines that read a renamed counter (lane SK).

**Two counts** that are not about time:

- **A test runs once for each root that reaches it.** With `main.my` removed, the 1,600-module project has 800 roots (the modules
  no other module imports), and a cold directory run executed 47,270 tests for 3,200 distinct ones (3,492 G instructions,
  2,423 CPU-s). The documented rule is that a library's tests run "as part of that root"; with several roots that is once each.
- **A file run and a directory run do not share passes.** Right after a directory run passed everything,
  `mylang test m0400.my` ran 44 tests and served none; after that file run passed, the directory run ran the file's two edited
  tests again (`rows-test50.json`: `directory_after_single_entry`).

The port avoids the first count only because its tests sit in `_test.my` files that nothing imports. Tests written beside the
code they test, in modules other modules import, meet it in full.

## 2. Where it goes

`profile.sh` records the second leaf-edit directory run by symbol. The shape is the same at both sizes
(`profile-400-flat.txt`, `profile-1600-flat.txt`):

| Share of instructions | 400 modules | 1,600 modules |
| --- | ---: | ---: |
| `fs.path.resolvePosix` | 22.1% | 20.1% |
| `mem.eqlBytes`, `memcpy`, arena allocation and growth | 22.2% | 25.2% |
| string hash maps (`getOrPut`, `grow`, `Wyhash`) | 11.0% | 9.4% |
| `test_runner_portable.carrierTypes`, `refusal`, `Paths.addSource`, `Paths.relative` | 11.2% | 15.2% |
| real paths (`dirRealPathFilePosix`, `realPathPosix`) and the kernel | 5.0% | 4.4% |
| `build_equality.declaration`, `validateModule` | 0.3% | 5.6% |
| BLAKE3 | 2.9% | 7.1% |
| emission (`emit_units`, `emit_constants`, `emit_llvm`) | 1.7% | 4.2% |
| `zig` (compile and link of the test program) | 15.6% | 1.8% |

The first five rows are 71% and 74% of the run. A flat profile cannot say who called the generic rows (byte comparison, copies,
the arena, the string maps), but they are what `Paths.addSource` does for each file, the call paths below lead there, and the
totals fit its count, tests times source files. So most of that share is one mechanism; stage 0's counters make it exact.

**C1. The portability rule reads the whole program for every test.** `test_runner_portable.zig` decides whether a test's record
may go to the per-user shared tier. Every call does work in the size of the program, not of the test:

- `Paths.addSource` walks every source file of the merged program and, for each, resolves its path, takes its real path (a
  system call) and stores it in a new hash map. If the rule runs once for each test of the root, as the totals suggest, that is
  1,602 files for each of 3,200 tests at 1,600 modules: about 5 million path resolutions. This is the quadratic term, and its
  system calls are in the wall time, not in the instruction counts.
- `refusal` scans every function for an `extern func` and computes `carrierTypes` twice over every record of the program, then
  walks the test's call tree.

Who calls it (`profile-400-lbr-inclusive.txt`, call paths only; how many tests each path covers is stage 0's first counter):

- `test_runner_decide.observeAttached` → `settle` → `test_runner_engine.recordWith` → `Engine.fetch` → `lookup` → `tierFor` →
  `shareAllows` → `eligibility.Table.decide` → `portable.executionRefusal` → `Paths.addSource`: when an entry ends, each pass
  is recorded, the record's publication asks the tier's filter, and the filter runs the rule.
- `test_runner.select` → `liveEffects` → `portable.refusal` for every ready test, and `programIdentity` → `publishes` →
  `refusal` again for a test keyed from its own lowering.

A run in which every test is served records no new pass, and the rule is decided only when the tier is first consulted for a
record, which fits the 0-rerun rows costing a fifth of the 2-rerun row. `select`'s proof runs in every row.

**C2. `test_runner_discover.within`** compares each function's module name with every module (functions × modules, 0.6% at
1,600 modules, the same shape of growth).

**C3. A root that declares `main` runs as a child process and checks its whole program** (lane T: 52% of the port's comment
edit; 41% of that is `ownership_cache.Cache.validate` hashing every body tree again, the rest `sema.checkProgram` restoring
cached bodies). `mylang check` after the same kind of edit costs 0.13 CPU-s at 99k lines.

**C4. Key derivation hashes body trees** to find each function's lowering key (lane T: 30%), because the union check does not
carry the `body:` parts of `module-check` that a build keys lowering by. The call-path profile shows
`lowering_cache.TreeWalk.run` under the entry's check here too.

**C5. One record load for each function's fact, on every run that checks** (4,800 at 400 modules: `cache.work` reports
`facts.reused 4800, decoded 4800`; 66,802 on the port).

**C6. A pass is keyed by its root.** `receipt.settingsWithBudget` hashes `entryPath` into the settings digest of both
arguments, so the same test under another root, or under its own file, is another query. That is the cause of both counts in
section 1.

**C7. The tests that do run.** `zig` costs 1.0 to 1.4 G at both sizes (constant, as it should be). Emission grows with the root
(4.2% at 1,600 modules) and `build_equality` appears at scale (5.6%); neither has a known call site yet.

## 3. Exits

Measured with a ReleaseFast pin of the landing commit, private stores, instructions as in section 1 and CPU seconds in a timing
window on a calm machine. Today's value is in brackets.

| # | Exit | Target |
| --- | --- | --- |
| E1 | 1,600 modules, leaf edit, 2 reruns: directory run | at most 9 G: twice the build of the same edit plus a run of the leaf file [54-69 G] |
| E2 | The same from 400 to 1,600 modules | grows at most 4.5 times [about 6 to 8] |
| E3 | 1,600 modules, a comment in `common`, 0 reruns | at most 6.5 G, 1.5 times the build [13.2 G] |
| E4 | The port, lane T's rows B, C and F (comment, shifted line, new function; 0 reruns) | at most 10 CPU-s each [70-93] |
| E5 | The port, row D (a body 389 tests reach) | at most 130 CPU-s: today's 120 for building and running the 389 (row D less row B) plus E4's 10 [199] |
| E6 | 1,600 modules without `main.my`, cold directory run | 3,200 tests executed [47,270] |
| E7 | A file run after a directory run, and the reverse | 0 tests run [44; 2] |
| E8 | Unchanged run at 1,600 modules | no more than today [1.22 G] |
| E9 | Exactness | the reruns equal the per-test oracle's (`MYLANG_TEST_KEYS=per-test`) and the child-per-root oracle's (`MYLANG_TEST_CHILDREN=1`) on `tests/lang` and the port; `MYLANG_ENGINE_VERIFY=16` clean; the complete gate green at each landing |

E1 to E3 and E6 to E8 need only the probe. E4 and E5 need the port and lane T's `measure.sh`.

**E5 restated on 10 November (stage 0).** The port now has 1,873 tests, and lane T's edited file was rewritten, so the rows were
measured again on the port's main `675e2ae` with a compiler of `fef979d1b`: the comment rows cost 100 to 152 CPU-s, and the body
edit reruns 515 tests for 230 CPU-s. E5's rule is unchanged (the body row less the comment row, plus E4's 10), which gives
**at most 140 CPU-s for 515 reruns**. E4 stays at 10 CPU-s for each row. The baseline of every exit is in
`experiments/test-loop-20261109/status.md`.

## 4. Stages

### Stage 0. Counters and the baseline (3-5 lane-hours)

- Run `probe.py` at 100, 400 and 1,600 modules and lane T's rows A to F on the port's main, in timing windows, and write the
  baseline to `experiments/test-loop-20261109/status.md`.
- Add to the run's work report (`cache.work`, `test_runner_work.zig`) what a profiler was needed for today: `rule.evaluations`
  (runs of the tier's rule), `rule.paths` (paths it resolved), `proofs` (calls of `portable.refusal`). A test asserts them on a
  two-root fixture.
- Name the call sites of `build_equality.declaration` and of emission in the leaf-edit run (a profile with call stacks from a
  pin built with frame pointers, or counters). They decide whether stage 5 exists.

### Stage 1. The rule reads the program once (C1, C2; 5-9 lane-hours)

In `test_runner_portable.zig`, a value built once for each checked program of a run and shared by every test of it:

- whether the program declares an `extern func`, and the two carrier tables (`host`, `callable`);
- the path table: whether the settings lie inside the root, and each source's root-relative name or "outside". One resolution
  and one real path for each source in a run, not for each test;
- `refusal`, `shareable`, `shareableKnown` and `executionRefusal` take it. What stays per test is the walk of its own call
  tree.

`eligibility.Subject` carries a pointer to it; its lifetime is the entry's run, and `Table.release` already drops an entry's
declarations when the entry ends. `select` keeps each test's proof and hands it to `programIdentity` and to the rule, so a
test is proved once in a run, not up to three times. `discover.within` looks modules up in a map.

**Soundness.** The predicates and their inputs are unchanged; only how often they are computed changes. The old functions stay
as the test oracle: a differential test runs both on every test of the fixture projects (an extern, a `Host` value, a
callback beside `function_digest`, a source outside the root, an asset outside the root, a symlinked source) and asserts equal
answers and equal refusal texts. A file that changes during a run is already an error (`SourceChanged`), so reading a real path
once is what the run assumes anyway.

**Expected (an estimate from the profile shares, not a measurement):** the leaf edit at 1,600 modules falls from 54-69 G to
about 15 G, and at 400 from 8.7 to about 2.5 G, so E2 should hold after this stage alone. E3's row falls by what `select`'s
proofs cost, which the profile does not separate.

**Stop:** an answer of the new value that differs from the old function on any fixture or on the port.

### Stage 2. A pass belongs to the test, not to the root (C6; 8-14 lane-hours)

Two changes that go together.

**(a) The IR-key argument leaves out the entry's path**, wherever `receipt.entryPath` feeds it (the settings digest, and the
program key of a test keyed from its own lowering). What a passing verdict can depend on besides the test's reachable program,
with what binds it after the change:

| Input | Bound by |
| --- | --- |
| The test's reachable functions, strings, types, embedded assets | the IR key (unchanged) |
| The test's own cases entry and the cases file's bytes; a cases file belongs to an entry | the settings (unchanged): two roots with different cases for one test keep two keys |
| Provider fixtures of the entry | the settings (unchanged); such a root already runs alone |
| Limits and policy from `mylang.json`, the build mode, budgets, seed, leak and fact modes, the keyed environment | the settings (unchanged) |
| The entry's own `main`, or the stub appended to an entry without one | not reachable from a test unless the test calls `main`, and then it is in the IR key |
| The path a trap or a failed assertion prints | failures are never recorded (D-T1-1, items 2 to 4) |
| The test's qualified name | the argument (unchanged): the same in every root |

The program-digest argument (tag `p`) is unchanged: it names the linked program, which differs by root. The settings domain
moves (`core-test-settings-v4`), so every stored pass misses once.

**(b) A directory run gives each test to one root.** After the roots are planned, a test (by qualified name) is selected in the
first root, in sorted path order, whose import closure declares it, and in no other. The report lists it once. A single-file
run still runs every test its closure declares, as today, and now finds the directory run's passes.

**Tests:** two roots that import one library run its tests once and report them once; a file run after a directory run runs
nothing, and the reverse; two roots with different cases for one library test keep two verdicts; `--filter` and
`--affected` select as before; the child-per-root oracle agrees.

**Stop:** any way found for the root to change a passing verdict that the table does not bind. Keep the entry in the key for
that class of test and report it.

### Stage 3. The check under a test run costs what `check` costs (C3; 8-16 lane-hours, a profile first)

Lane T's first open item. The work is to find why a child's check of a root that declares `main` costs tens of CPU seconds
where `mylang check` of the same tree costs a fraction of one, and remove the difference. Known candidates: the ownership
cache validates by hashing every body tree, where a build takes its proofs from the engine's `ownership-proof` records; the
checker restores every cached body, where `check` and `build` read the merged program lazily and let summaries stand in.

**Exit of the stage:** on the port after a comment edit, the front end of a child root is within 1.5 times `mylang check` of
that root.

**Stop:** a fix that needs the root's `main` checked differently from how `mylang check` checks it.

### Stage 4. Keys from what the build already has (C4, C5; 10-18 lane-hours)

Lane T's second and third open items.

- The union check runs with the engine deciding its modules, so key derivation takes each function's lowering key from the
  `body:` part of `module-check`, as builds have since G3g step 1, and hashes no body tree.
- A root's facts are stored as chunks for each group of functions under one head, as the optimizer's rows are
  (`optimizer_chunks.zig`): a group with no changed function costs one digest comparison, and a run reads the facts of the
  functions it recomputes.

**Exit of the stage:** E4.

### Stage 5. The tests that do run (C7; 0-12 lane-hours, only if E1 or E5 is still missed)

Decided by stage 0's attribution and a re-measure after stage 4. Candidates: emit only the units the missed tests reach;
remove the `build_equality` scan. Skipped if the exits are met.

## 5. Not in this plan

- The build's own per-project cost (4.2 G for a one-line edit at 1,600 modules): that is the deferred engine move (G4d).
- Reuse for tests this plan leaves live: a call tree that reaches an `extern func` or a `Host` capability, and every run with
  `--link`.
- Whether tests should build with the lean debug code generation instead of LLVM `-O0`.
- The interface a test file should have (tests beside code against `_test.my` files). Stage 2 makes both cost the same.

## 6. Order, lanes and gates

Stages 0, 1 and 2 in that order, one lane: they edit the same files (`test_runner*.zig`). Stages 3 and 4 follow in a second
lane or the same one; stage 3 touches the front end's session and the ownership cache, stage 4 the key derivation and its
store. Never two lanes in `test_runner*.zig` at once.

Each stage lands alone: the lane's complete gate, a merge of main, the main gate, then the map refresh. Stages 2 and 4 change
key domains, so the first gate after each reruns the language suites once. Every landing reports E1 to E3 and E6 to E8 from
`probe.py`; stages 3 and 4 add the port's rows.

## 7. Estimates

| Stage | Lane-hours | Delivers |
| --- | ---: | --- |
| 0. Counters and the baseline | 3-5 | the numbers the exits are judged against |
| 1. The rule reads the program once | 5-9 | most of E1, E2 |
| 2. A pass belongs to the test | 8-14 | E6, E7 |
| 3. The check under a test run | 8-16 | part of E4, E5 |
| 4. Keys from what the build has | 10-18 | E3, E4 |
| 5. The tests that do run | 0-12 | the rest of E1, E5 |
| **All** | **34-74** | |

Stages 0 to 2 are 16 to 28 hours and remove the two counts and most of the leaf-edit cost.

## 8. Decisions (answered by the user on 9 November)

- **D1. One root for each test in a directory run (stage 2b).** Today a library's tests run and are listed once for each root
  that imports it. **Decided: once, under the first root in path order** ("go with once under the first root path").
- **D2. The exits' numbers** (section 3), E1 and E4 above all: twice the build for a leaf edit, 10 CPU-s for a comment edit on
  the port. **Decided: accepted as written** ("D2 exit numbers sound good").
- **D3. When.** It needs one lane. The recommendation was the first free slot. **Decided otherwise: the plan waits until the
  other compiler work finishes, and starts after that** ("we are going to wait until the other compiler work finishes and
  then start after that"). As understood on 9 November, that work is the stage-fit fix and the check-and-build fixes found
  by the port. The user says when it has finished; no lane is started from this plan before then. **10 November: the user
  said the other work had finished and to start** (section 10).

## 9. Part B: the ownership model as four verbs and three rules

The audit counted 54 ownership rules in a 2,637-line reference, and the user asked whether the model can be made simpler
without giving back the copies its additions removed. It can: the model underneath is small. What is large is the number of
names for one rule, and the places where the compiler does not yet follow it. Scripts: `experiments/ownership-matrix-20261109/`
(`matrix.py`, `text_frame_repro.my`). Evidence: `~/ai/canopy/mylang-evidence-archive/experiments/ownership-matrix-20261109/`.

### 9.1 The model

Every use of a managed value is one of four verbs:

| Verb | Spelled | In a signature |
| --- | --- | --- |
| lend | the name | a plain parameter; a result under `from p` |
| lend for writing | `mut name` | a `mut` parameter |
| give | `own name` | an `own` parameter; a result without `from` |
| duplicate | `copy(name)` | |

Three rules:

1. **Escape.** A lent value cannot be stored or given anywhere that outlives its lender.
2. **Exclusion.** A lender cannot change or be given away while something it lent is in use, and a loan for writing is the
   only loan.
3. **Gone.** After `own`, the name cannot be used until it is assigned again.

A value built from lent parts is itself lent. Resources, task groups and pending Results are these rules applied to a value
that cannot be duplicated, a scope that borrows, and a value that must be consumed.

### 9.2 What was measured

**The matrix.** `matrix.py` writes one program for each cell of: where the value comes from (a local, a plain, `own` or `mut`
parameter, a field, an element, a slice, the result of a `from` function, a fresh call) by where it is used (15 positions:
bindings, a record, an option, a list or a dictionary that stays local or leaves, a plain or `own` argument, a return) by verb
(bare, `own`, `copy`) by type (`str`, `bytes`, `int[]`, a record). Each is checked, and built when the check accepts it. The
compiler is the pin `g3-s1b5-f5834a8f` (main `47f39d067`).

| | Cells |
| --- | ---: |
| All | 1,775 |
| Accepted and built | 930 |
| Refused by `check` | 839 |
| Accepted by `check`, failed in `build` | 6 |

- **One rule under ten names.** 812 of the 839 refusals (97%) are rule 1. They are reported under four codes and ten rule
  ids: `E_OWN_MARKER` (B2, W2), `E_SINGLE_OWNER_BORROW` (R1, B7, B8, M1, R3), `E_SLICE_ESCAPES` (V2, W4) and
  `E_BORROW_UNDECLARED` (R4). The other 27 are R5 (`E_BORROW_MIXED`).
- **A bare name does not always lend.** In the eight positions that stay inside the function, with a source other than a fresh
  call, a bare name is refused or fails the build in 114 of 312 cells:

| Hole | Cells | Today | Cause |
| --- | ---: | --- | --- |
| H1. `mut c = place`, assigned once | 39 | refused; the same local assigned twice borrows (B9) | checker |
| H2. `Some(place)` as a local | 39 | refused; `Box(value=place)` and `[place]` are accepted | checker, perhaps the option's payload |
| H3. A `from` function's result into a local record, list or dictionary | 12 | refused; the field read directly is accepted | 3 checker (records, R3), 9 representation (text, bytes, lists: a view) |
| H4. A slice into a local record, list, dictionary or rebound local | 12 | refused (V2) | representation |
| H5. A plain `str`, `bytes` or list parameter into a local list or dictionary | 6 | refused (R1); a record parameter is accepted | representation |
| H6. A `const`-bound `str` field or `from` result passed to a plain-parameter helper | 6 | `check` accepts, `build` fails | a defect (9.6) |

H3 is the one that shapes code: wrapping a field in an accessor loses what the bare field can do.

**The port** (126,614 non-test lines at `675e2ae`, 5,662 functions):

- `own` appears 2,730 times and `copy(` 3,343 times; there are 36 `own` parameter declarations against 2,291 `mut` ones. The port
  almost never passes ownership into a function. `own` is used when a value is built.
- Friction entries that name a code (294 entries; an entry can name several, so the minutes overlap):

| Code | Entries | Minutes | Rules behind it |
| --- | ---: | ---: | --- |
| `E_SINGLE_OWNER_BORROW` | 58 | 591 | 11 (B7, B8, B9, R1, R3, R4, R6, M1, M4, P4, X2) |
| `E_SINGLE_OWNER_OVERLAP` | 29 | 393 | 6 (R2, R7, M5, M6, X1, X2) |
| `E_CORE_UNSUPPORTED` | 13 | 353 | Z3: `check` accepts, `build` refuses |
| `E_OWN_MARKER` | 10 | 191 | B2, W2, B9 |
| `E_SLICE_ESCAPES` | 11 | 110 | V2 to V5, W4, K3 |
| `E_BORROW_MIXED` | 6 | 74 | R5 |

### 9.3 Stages

**O0. Cost the stages (2-3 lane-hours).** The ranges below are rough: they were not costed against the code. O0 reads the
checker and the lowering for H1 to H3 and replaces them, and brings the decisions of 9.7 to the user.

**O1. The reference says the model (4-8 lane-hours).** `docs/ownership-rules.md` opens with 9.1. Every existing rule keeps its
id and is filed under the rule it applies (escape, exclusion, gone), under "current limits" (each with what would remove it:
R5, B8, H3 to H5, the dictionary limit of X2, Z3), or under "applications" (P, K, L). The entries that describe accepted
behaviour or a retired restriction (the ones with `Codes: none`: T1, B4, B5, W1, V1, V7, P5, Z1, Z2, and C2, which is about
contracts) move to an appendix. `docs/managed-memory.md` and the guide teach the four verbs first. No compiler change.

**O2. One message for rule 1 (6-12 lane-hours).** Every refusal of rule 1 says the same four things in the same order: what is
lent, who lends it, where it would outlive the lender, and the two repairs (`own name` to give it, `copy(name)` to keep both),
with the repair as a `fix` where it is certain. The codes and rule ids stay (D5, decided). A test asserts the shape on the matrix's
refused cells. `mylang reference --query CODE` names which of the three rules a code enforces.

**O3. The checker-only holes (10-20 lane-hours, after O0).**
- H2: `Some(place)` as a local is an option of a borrow, as it already is inside a record or a collection of borrows.
- H3 for records: the result of a `from` function goes where the field it returns goes.
- H1 (D4, decided): `mut c = place` borrows whether it is assigned once or more; a write through it is refused with rule 1's
  message at the write.
- Each case lands with its accepted and refused examples in `tests/lang`, the matrix's rows, and no change to what `copy` or
  `own` mean.

**Stop:** a case that needs a change to the ownership validator (`src/core/validate_ownership.zig`) or the Lean proof
(`proofs/ownership`). Report it with its cost; do not decide it.

**O4. A spike on one shape for text, bytes and lists (4-6 lane-hours, no landing).** H3 (text, bytes, lists), H4 and H5 have one
cause: an owner is a block and a view is a pointer and a length, so a view cannot sit where a field expects an owner. Two ways
are known: frame blocks (RB1, landed for records that hold a view parameter) and one value shape that is either (the list form
RB2 built and withdrew for its proof cost, kept on `own/record-collections-from-repr`). The spike prices both for the 27 cells
and the port's remaining sites (PB's re-count: 53 at the frame-block limit, 38 new collections under `from`, 93 records
returned from bytes or text parameters), in lane-hours, run time and proof work, and brings one recommendation. Building it is a
later decision (D7).

**O5. One verdict (2-4 lane-hours for the gate, plus the fixes).**
- The matrix joins the gate: a cell `check` accepts must build. On 9 November 6 did not (9.6); on main `fef979d1b` all do.
  Lane CB's corpus test (`src/core/check_build_corpus_test.zig`) builds every function the check accepts in the language suites
  and in `test/fixtures/check-build`; the matrix's cells are not among them yet.
- The check-and-build disagreements known on 9 November are fixed on main: the `text_frame` defect (9.6) and the port's F-PB-1
  to F-PB-3 (lane CB).
- O0 also answers what it would cost for `check` to run the placement of ownership operations that `build` runs, so that Z3
  stops being a rule. That is costed there, not assumed here.

### 9.4 Exits

| # | Exit | Target |
| --- | --- | --- |
| X1 | The reference | opens with the four verbs and three rules; every rule is filed under one of them, a limit or an application |
| X2 | Rule 1's refusals in the matrix | one message shape on all of them [four codes, ten rule ids] |
| X3 | Bare names in function-local positions | refused only for the representation holes H3 (text, bytes, lists), H4 and H5 [114 of 312 cells; 108 on 10 November] |
| X4 | Cells `check` accepts | all build, and a gate test holds it [6 did not; 0 on 10 November, ungated] |
| X5 | Nothing accepted today is refused | the matrix's accepted cells (930; 936 on 10 November) stay accepted; `tests/lang` and the port's `check` unchanged |
| X6 | The complete gate | green at each landing |

### 9.5 Not in Part B

- Dropping the `own` and `mut` markers. In a record a bare name lends and `own` gives, so the marker is the difference between
  two programs. Most of the port's marker friction was tooling: one missing marker reported per run (fixed on 7 November) and
  `mylang fix` not being part of the workflow.
- Reference counting, arenas, lifetimes and copies the compiler inserts by itself. Each was decided against earlier.
- Rule 2's precision (393 logged minutes: reading one field while a `mut` call holds the whole record). Making it more precise
  adds to the model; it is a separate question.
- R5, one kind of return, and B8, no partial record moves. They are listed as limits in O1; O4 says what R5 would cost.

### 9.6 The defect the matrix found

`experiments/ownership-matrix-20261109/text_frame_repro.my`, 12 lines: a `str` field bound with `const` and passed to a helper
with a plain `str` parameter, in a function called from `main`. `check` accepts it. A Debug compiler reports
`E_CORE_INVALID_IR: invalid Core IR in main b0 %15: a view escapes through text_frame`; a ReleaseFast compiler emits LLVM that
clang refuses. It fails in every build mode except `--unoptimized`, and it builds when the field is `bytes` or when the function
is called from a test, which is why the port and `tests/lang` did not meet it. RB1's frame blocks are the likely cause. It was
proposed as a separate task on 9 November.

**Fixed on main by 10 November.** On a ReleaseFast compiler of `fef979d1b` the program checks and builds in every mode, and all
six cells build. Lanes CB and HC landed in between (`check` and the build agree; hidden copies), and the proposed task was
withdrawn. What is left is the gate: no test holds these cells (O5).

### 9.7 Order, estimates and decisions

Part B shares no file with Part A. Among its own stages O1 and O2 come first; O3 waits for O0, for the `text_frame` fix and for
the F-PB lane, which edit the same checker and lowering (both landed by 10 November); O4 has no dependency. The user gave no
separate start for Part B: like Part A it started when the user said the other compiler work had finished (10 November).

| Stage | Lane-hours (rough) | Delivers |
| --- | ---: | --- |
| O0. Cost the stages | 2-3 | real estimates, the decisions below |
| O1. The reference says the model | 4-8 | X1 |
| O2. One message for rule 1 | 6-12 | X2 |
| O3. The checker-only holes | 10-20 | X3 |
| O4. The spike | 4-6 | the cost of the representation holes |
| O5. One verdict | 2-4, plus the fix lanes | X4 |
| **All** | **28-53** | |

The user answered D4 to D6 on 9 November with "Ownership rules sound good", after the three were listed with their
recommendations; each is recorded as its recommendation.

- **D4. `mut c = place`, assigned once (H1).** Under rule 1 it borrows, like `const` and like the same local assigned twice;
  a write through it is then the refusal, at the write. Today the binding is refused and the repair (`own` or `copy`) is at the
  binding, which is closer to the mistake when the author meant to change `c`. **Decided: it borrows, with the message at the
  write naming the binding and both repairs.**
- **D5. Codes.** **Decided: keep the four codes and give them one message shape.** (The alternative, one new code, changes
  every `# doc: expect-error` line and every test that names one.)
- **D6. The entries that are not rules.** **Decided: move them to an appendix and keep their ids.** (Retiring the ids changes
  the rule table the compiler's tests assert; it can be asked again after O1.)
- **D7. The representation work, after O4.** **Decided on 10 November: build H5 by frame blocks** (section 10.2).

## 10. The start (10 November)

The user said the other compiler work had finished, asked that the new work be checked against this plan, and said to start
the lanes.

### 10.1 What landed between the plan's compiler and main

The plan was measured with the pin `g3-s1b5-f5834a8f` (main `47f39d067`). Main is `fef979d1b`, 26 commits later: DL4 (gate shard
plans and per-step costs), SK (a stage record that does not fit is a logged miss), J4 (two wrong drop plans), CB (`check` and the
build agree on F-PB-1 to F-PB-3, the corpus test, `E_BORROW_SOURCE` for a `from` clause whose sources cannot lend) and HC (hidden
copies of trims and generic `from` sources). The port's main is unchanged (`675e2ae`).

Both probes were run again on a ReleaseFast compiler of `fef979d1b` (`~/ai/.home-cache/mylang-pins/tl-fef979d1b`), on a calm
machine. Rows: `~/ai/canopy/mylang-evidence-archive/experiments/{test-loop,ownership-matrix}-20261109/recheck-fef979d1b/`.

**Part A is unchanged.** Billions of instructions, 9 November against 10 November:

| Step | 100 modules | 400 modules |
| --- | ---: | ---: |
| Unchanged run | 0.07, 0.07 | 0.25, 0.25 |
| A comment line added to `common` | 0.65, 0.66 | 2.67, 2.68 |
| A leaf body, 2 tests rerun | 2.0, 2.0-2.1 | 8.7-9.7, 8.8-9.9 |
| A body in `common` half the tests reach | 2.0, 2.0 | 9.3, 9.5 |
| The leaf file alone | | 0.50, 0.51 |

A file run after a directory run still serves none of its 44 tests, and the directory run after it still reruns the 2. The
1,600-module rows, the run without `main.my` and the port's rows were not repeated; they are stage 0's baseline. On the calm
machine the 400-module leaf edit is 1.5 to 2.1 CPU-s (3.4 to 4.0 under load on 9 November), which is why the exits are in
instructions.

**Part B: the six build failures are gone and nothing else moved.**

| | 9 November | 10 November |
| --- | ---: | ---: |
| Accepted and built | 930 | 936 |
| Refused by `check` | 839 | 839 |
| Accepted by `check`, failed in `build` | 6 | 0 |

The 839 refusals are the same cells with the same codes and rule ids, so `E_BORROW_SOURCE` reaches no cell. H6 is closed, and a
bare name is now refused in 108 of 312 function-local cells (H1 to H5). What this changes in the plan:

- 9.6: the defect is fixed; its proposed task was withdrawn.
- O5: the port's F-PB fixes are landed and lane CB's corpus test exists. What is left is putting the matrix in the gate (exit X4
  is met today and held by no test) and O0's costing of Z3.
- O3: both things it waited for have landed, so it waits only for O0.
- X3's bracket is now 108 of 312, X4's is 0, and X5's count of accepted cells is 936.

**Corrected the same day (stage O5).** The re-run above used a ReleaseFast compiler, which validates no ownership
certificate and runs no `--verify-facts`. With a Debug compiler lane OC found seven accepted cells that did not build:

- Six (`return` under `from` of an element or a slice of a parameter, beside a `mut` list, with the result unread): the
  validator refused the drop plan (J4: the root was freed before the borrow was taken out of the call's result). Fixed in the
  drop placement (`own.zig`), not in the validator, with stage O5.
- One (`keep(p[0:2])` where `keep` takes `own s: bytes`): `check` accepts it and a `--verify-facts` build refuses it with
  `E_CORE_HIDDEN_COPY`. The `str` cell passes only because its copy is optimised away. List slices are already refused by the
  check (W4). It is pinned in `test/fixtures/ownership-matrix/known-build-failures.tsv` and is decision D8 below.

The matrix is in the gate since stage O5 (`test/ownership_matrix_cli_test.zig`): every cell's verdict, code and rule id is
pinned in `verdicts.tsv`, and the accepted cells are built and run in the default mode and with `--debug-o0 --verify-facts`.

- **D8. A text or bytes slice given to an `own` parameter.** **Decided by the user on 10 November: the check refuses it**, as
  it refuses a list slice (W4), with `copy(...)` as the certain fix carried for `mylang fix` and a fix-migration corpus. The
  alternative was to let the hidden-copy rule allow this copy.

### 10.2 What the stages found

**Stage 1 (landed 10 November): the rule reads the program once; E2 is not met yet.** Billions of instructions, with a
compiler of the stage's commit:

| | Stage 0 | Stage 1 | Target |
| --- | ---: | ---: | ---: |
| E1, leaf edit at 1,600 modules | 54-70 | 34.9-35.3 | 9 |
| The same at 400 modules | 8.7-9.8 | 7.5 | |
| E2, growth from 400 to 1,600 | 6.2-7.2 | 4.65 | 4.5 |
| E3, comment in `common` | 13.2 | 10.27 | 6.5 |
| E8, unchanged run | 1.22 | 1.22 | 1.22 |

- The rule now resolves 1,603 paths in a run, not 1,603 for each test, and walks each test's call tree once (3,200 proofs, was
  9,602). The 3,200 evaluations a leaf edit still makes cost about 0.4 G together, so the per-test program argument needs no
  fix of its own.
- **The plan's estimate for this stage was wrong.** It expected about 15 G at 1,600 modules and 2.5 G at 400, and E2 met by
  this stage alone. The profile it rested on was sampled by frequency and over-weighted the rule; a fixed-period profile of
  the baseline gives the rule 50% and emission 26%.
- **Stage 5 exists.** Emission is now about 60% of the leaf edit at 1,600 modules: the test program's units are all rendered
  again on each run, and each unit's render validates the whole module (`emit_llvm.renderScratch`, `validateModule`), builds the
  constant catalog and scans for fast paths, which grows faster than the program. The lane's re-estimate is 14 to 21 G of
  emission at 1,600 modules. E2 is left as written and is judged after stage 5 (the coordinator's decision; the stage landed
  short of it by 0.15).
**Stage 5, step 1 (landed 10 November, `c9fe77b08`): emission reads the whole module once for a program.** Each unit's
render used to validate the module's equality declarations, scan for the testing counter, parse three preludes and walk the
constant catalog twice; that is now done once (`emit_survey.zig`, `emit_fast_paths.zig`), for every debug build and not only
tests. No unit's text changed in 3,009 units of the 747-program corpus, debug and release.

| 1,600 modules, G instructions | Stage 1 | Stage 5, step 1 | Target |
| --- | ---: | ---: | ---: |
| E1, leaf edit, 2 reruns | 35 | 27 | 9 |
| E2, growth from 400 modules | 4.65 | 4.21 | 4.5 (met) |
| E3, comment in `common` | 10.3 | 10.3 | 6.5 |
| E8, unchanged run | 1.22 | 1.22 | 1.22 |
| Cold directory run | 184 | 176 | no more than before |

- **Serving the test program's stages eagerly costs more than it saves** (steps 2 and 3, built on the side branch
  `testloop/emission-served`, not landed): the leaf edit rose to 30-36 G, the cold run to 213-219 G and the work directory
  from 199 to 446-497 MB. Without demand every function is keyed on every run, and for small functions a key costs about what
  the function costs to build. The served program was byte-identical to the cold one after every probe edit.
- **What is left of the leaf edit's 27 G:** about 13 G of back end (passes 6, rendering 6), 4 G of lowering, 4.5 G of the
  entry's check (stage 3) and 4.5 G of `select` and key derivation (stage 4).
- **Stage 5b (the coordinator's decision, 10 November): the test program is served through demand, after stage 4.** A build
  avoids the keys because `module-check` records give the prepared keys, unchanged bodies are never loaded and unchanged units
  are served as handles. Stage 4 puts the union check on the same records, so stage 5b follows it and reuses its keys:
  12 to 20 lane-hours (the lane's estimate). E1 cannot reach 9 G without it: stages 3 and 4 remove at most about 9 G of the 27.
  The alternative that serves only unit text (about 2.5 G saved, a dearer cold run) is not built.

**Stage 2 (landed 10 November, `281ab9d82`): a pass belongs to the test, and a directory run gives each test to one root.**
The entry's path leaves the settings digest and the two IR keys, so every stored pass missed once. In a directory run each
module that declares tests belongs to the first root, in sorted path order, whose import closure holds it; a root also runs
the tests its own cases file names, so two roots with different cases for one test keep two verdicts.

| | Stage 0 | Stage 2 | Exit |
| --- | ---: | ---: | --- |
| E6, 1,600 modules without `main.my`: executions for 3,200 tests | 47,270 | 3,200 | met |
| The same run cold, G instructions | 3,513 | 430.5 | |
| E7, file run after a directory run on the port (`connect_test.my`, 20 tests): tests run | 20 | 0 | met |
| E7, probe: file run after a directory run and an edit of 2 tests | 64 | 2 | met |
| E8, unchanged run, G | 1.22 | 1.22 (+0.16% on equal footing) | met |
| E9, exactness | | oracles agree on `tests/lang` (3,006 tests) and on the port's 515 key misses | met |

- One input outside the plan's table was found and fixed: the stored report was named by settings, root and filter, so with
  the entry gone two entries of one root would have shared it. It now names the entry and the modules the run left out.
- A child root is told which modules to leave out (`--skip-test-modules FILE`), not which it owns, so a test no root claims
  still runs.
- With stage 5's step 1 merged: E1 27 G (target 9), E2 4.20 (met), E3 10.3 G (target 6.5). E4 and E5 are stage 4's.
- Not done, and needed by no exit: without `main.my` each of the 800 roots reads the shared check's program once (1.28 M
  paths where 1,603 would do).

**Stage 3 (landed 10 November, `ed3cbfc0f`): a test run finds held ownership proofs by their receipts, as `check` does.**
The profile first: on the port the stage's exit already held for one root (a root's front end under `mylang test` cost less
than `mylang check` of it), and the directory run's 279 G was its 190 child processes: ownership validation hashing every
body 24%, key derivation 22% (stage 4), restoring cached bodies 9%, re-checking the edited module in each child 9%. On the
1,600-module probe the test run's front end was 1.7 times `check`. The fix is in `ownership_cache.zig`: a session that keeps
every tree and has no lowering host asks the planner about each unchanged body, which forms its receipt, and reuses the proof
held under it; a function with no receipt is proven by its tree's digest as before. `MYLANG_OWNERSHIP_RECEIPTS=0` is the
oracle; 39 runs with the route on and off (the language suites, the matrix fixtures, the port; cold, forced, and after
edits) gave the same statuses, verdicts and diagnostics byte for byte.

| | Before | Stage 3 | Target |
| --- | ---: | ---: | ---: |
| Probe, front end of `mylang test main.my` against `check`, leaf edit | 1.65 | 1.11 | 1.5 (met) |
| The same after a comment in `common` | 1.73 | 1.12 | 1.5 (met) |
| E1, leaf edit, G | 27.3 | 25.7 | 9 |
| E3, comment in `common`, G | 10.3 | 8.7 | 6.5 |
| E8, unchanged run, G | 1.22 | 1.22 | 1.22 |
| Port, directory run after a body edit, G | 279 | 181 | |

- Restoring cached bodies (about 1 G on the probe, 26 G on the port) is not stage 3's: a test run needs the typed trees
  because key derivation and the program's lowering walk them. It goes with stages 4 and 5b.
- **A compiler crash was seen three times on 10 November** (a general protection exception in `BorrowedCollections.init`,
  at an `@memset` of a fresh allocation): on the first H2 build, on the H1 head, and in a doctest of this stage's first gate
  run (the rerun passed). **It is the known machine fault F22**
  (`experiments/guest-build-engine-20261031/F22/REPORT.md`), logged over a dozen times since 8 October at `@memset` sites of
  Debug compilers in different functions and worktrees, never reproduced and unexplained: the traces have its signature
  (`si_code=0x80 trap=13`, the code bytes of `rep movsb`, every address canonical, swap nearly exhausted). The coordinator
  first read it as heap corruption in the ownership check and sent lane OC to find it; that was withdrawn within the hour.
  A gate that fails on this signature is rerun; H1 was held back by it for about an hour.

**Stage 5b, the design and its first landing (10 November, `3cf27f6f3`).** The test program is to be built as `mylang build`
builds after an edit: lowering keyed by `module-check`'s `body:` parts, lazy bodies, demand passes, receipts and native
handles, in a store of the entry's own. The check stays as stage 3 left it, because key derivation and the shared tier's
proof walk still read the typed tree of everything a test reaches. A child root or a single entry needs nothing from stage
4; roots that share the union check keep today's path until stage 4 gives that check a cached session.

- **A blocker the design missed:** every test program runs under a step and frame budget, applied by rewriting every
  function's body after lowering, and demand keeps unchanged bodies unloaded. `mylang build` turns demand off for the same
  reason whenever a run budget is installed. Without the lazy part 5b gains nothing over today.
- **The coordinator's decision: two landings.** The first makes the rewrite a per-function operation (`run_budget.Run` and
  `test_runner_budget.Test`: `declare` once for the module, then `function` for each index), with `instrument` still calling
  it for every function, so nothing is keyed differently and no record misses. It is byte-identical: a differential test
  against a copy of the old code, 745 of 749 corpus programs under a run budget and 393 of 395 `tests/lang` test programs
  with identical LLVM (the others are the compiler-identity constants of one file and programs that fail both ways), and a
  test pinned at exactly 438 steps before and after. The second landing is 5b itself, with the hook that rewrites a body
  when demand materializes it and the budget's digest in the demand keys of the functions it touches.
- Estimates (the lane's): the second landing 14 to 21 lane-hours; the probe's leaf edit about 12 G from 5b alone and about
  8.5 G with stage 4, against the target of 9.

**Stage 4 (landed 10 November, `57c212fca`): keys from what the build already has.** Key derivation keys lowering by the
engine's `module-check` `body:` parts and hashes no body tree (oracle `MYLANG_ENGINE_DECIDE_LOWERING=0`), the shared check's
session reaches the roots that share it, and a root's facts are read as group records of about six functions (oracle
`MYLANG_TEST_FACT_GROUPS=0`). On the port, keys from parts against trees and with groups against without differ for 0 of
1,873 tests.

| 1,600 modules, G instructions | Stage 3 | Stage 4 | Target |
| --- | ---: | ---: | ---: |
| E1, leaf edit (without stage 5b) | 25.7 | 23.0 | 9 |
| E2, growth from 400 modules | 4.2 | 4.2 | 4.5 (met) |
| E3, comment in `common` | 8.7 | 6.38 | 6.5 (met) |
| E6, executions for 3,200 tests | 3,200 | 3,200 | met |
| E8, unchanged run | 1.22 | 1.22 | 1.22 |

- **E4 is not met and this stage cannot meet it.** The port's comment edits cost 180 to 295 G, about 70 to 95 CPU-s untimed,
  against 10 CPU-s. Every root that imports the edited module is checked again: `sema.checkProgram` is 42% of the row (store
  reads 14%, body re-checks 11%), `replayRoots` 11%, the portability walk 5%, ownership validation 4%. Meeting it needs a new
  route: a root whose `module-check` parts are all unchanged takes its tests' keys from a record keyed by those parts, with
  no check and no lowering, and the check as fallback and oracle. That is stage 6, costed before it is built.
- **E5 is not shown:** row D's instructions did not move (787 G against 781 G) and its CPU seconds were not timed.
- The port's rows vary by 2 to 7% between fresh stores, and same-compiler pairs of the body edit by more (609 against 695 G);
  the final measurement needs timing windows on a calm machine.

**Stage 6, first half (landed 10 November, `1c4712e7f`): a comment edit or a line shift replays the stored report.** A
report is recorded twice: under its files' bytes, asked first, so an unchanged run still reads file stats only; and under
the new engine kind `module-tokens`, the lexer's tokens of each source without comments, blank lines, trailing whitespace
or line numbers. Modules a printed diagnostic names, modules with docstring examples and every file that is not a source are
read by bytes in both. Oracle `MYLANG_TEST_TOKEN_REPORTS=0`.

| | Stage 4 | Stage 6, first half | Target |
| --- | ---: | ---: | ---: |
| Port row B, a comment reworded | 295 G, 78 CPU-s | 9.9 G, 2.4 CPU-s | 10 CPU-s (met) |
| Port row C, a comment line added | 290 G, 70 CPU-s | 9.9 G, 1.9 CPU-s | 10 CPU-s (met) |
| Port row F, a new function | 292 G, 89 CPU-s | 283 G | 10 CPU-s (not met) |
| Port row D, a body 515 tests reach | 787 G | 786 G | E5: 140 CPU-s (not shown) |
| E3, comment in `common`, 1,600 modules | 6.38 G | 1.33 G | 6.5 G (met) |
| E8, unchanged run | 1.221 G | 1.221 G | 1.22 G |

- Differentials on against off, 0 different: the port (cold, unchanged, B, C, trailing whitespace, a string edit, an
  indentation edit, D, F) and `tests/lang` file by file (61 files, 436 tests). The first run found one real difference, 5
  docstring examples whose keys move with a line shift, which is why modules with examples are read by bytes.
- **A correction to step A:** the port has no docstring examples and its shared check is not skipped; it fails with
  `E_PRIVATE_SYMBOL`, because a `foo_test.my` is checked as module `foo` and uses its private declarations. So each of the
  139 roots that import an edited module runs as a child.
- **What would meet row F and move row D, costed and not built:** (1) by reach, 16 to 28 lane-hours: a root is served when
  every declaration its tests reach is unchanged, the changed modules check clean alone and every importer's `module-check`
  record is still valid; row F about 10 to 12 G, row D about 590 G. (2) The shared check with each test file overlaid into
  its sibling module, 8 to 16 lane-hours and riskier: one check where there are 139; row D about 630 G and one check on a
  cold run. Both are the user's decision.

**Stage 5b, closed without landing (10 November).** Its rule was that the port's body-edit row must come out at least 20%
below today's in a timing window; it came out 3.7 to 4.5% above (814 to 822 G against 784 to 787 G), because the row builds
only 45 programs and the rest of it does not change with demand. The branch `testloop/demand` (`c8eee9258`) stays unmerged.
What it established: the test program can be built through demand with identical bytes (221 of 221 families after the fix);
two whole-module rewrites sit between lowering and the passes (the step budget, landed per function; `retainTraceOwners`,
fixed on the branch) and a guard now catches a third; the budget's key need carry no controls for an original function; on
the 1,600-module probe the leaf edit was 15.3 G against 23 G; on the port a cold run cost +5 to +15% instructions and 1.4
to 2.3 times the work directory. **E1 therefore stays at about 23 G against its target of 9.** A later attempt needs a
profile showing the builds are over a quarter of the row, and the many-roots lowering assembly.

**Left from Part B, recorded and not planned:** lowering recomputes the checker's tables (`borrowedMutLocals`,
`BorrowedCollections`) from the typed tree by itself, and sema decides a local's origin by its last store, so an
unchecked-lowering fixture can change shape unnoticed; the matrix labels its cells by position, not by cause (the 6
`Some(view)` cells were counted under H2). The silent per-iteration copy in `readOnlyArgument` is being fixed by lane OC by
the user's decision of 10 November.

- Soundness: the old per-call functions are kept as the oracle. Differential tests on eight fixture programs, 4,946
  evaluations and 7,451 proofs on the port, and the per-test and child-per-root oracles on `tests/lang` (2,998 tests) agree.
- The port's rows did not move beyond their noise (body edit 1,182 G against 1,226 G; comment edits vary by a third from run
  to run). Their cost is stages 3 and 4.

**O2 (landed 10 November): 755 cells in the shape, 57 in a marker wording.** The plan counted 812 refusals as rule 1. Of
those, 57 refuse an `own` that takes nothing (an `own` argument of a plain parameter, `return own` of an owner, `own` on a
fresh value), so nothing escapes and they keep a short marker message in the same vocabulary. The other 755 say, on one line:
what is lent, who lends it, what would keep it (with "after the call returns" or "after `a` ends" only where that is certain,
and "needs its own value" otherwise), and the repair, which names the edit the structured fix makes. There were 17 wordings
before. No verdict, code, rule id, location or fix changed on any of the 1,775 cells. X2 is met with that count.

**O0 (10 November): the checker holes, costed.** None is expected to need the validator or the Lean proof. All hours are
the lane's estimates.

| Hole | Cells that move | Estimate | Note |
| --- | ---: | --- | --- |
| H2. `Some(place)` as a local | 32 | 5-8 h | 3 cells (a text, bytes or list parameter as the source) need a new IR combination; a refusal by the validator stops those 3 only |
| H3 for records | 3 (4 with H2) | 3-6 h | |
| H1 (D4) | 36 | 6-10 h | after O2; slices stay refused (3 cells); nothing accepted today is refused |
| **O3** | | **14-24 h** | the plan said 10-20 |

**O4 (10 November): the spike's answer is to build neither shape.** Write-up:
`experiments/ownership-matrix-20261109/SPIKE-O4.md`. Of the 27 cells, 24 are representation cells and 3 are not.

| | Frame blocks | A value that is either a view or an owner |
| --- | --- | --- |
| Cells it takes | H5's 6 | all 24 |
| The port's sites it takes (53, 38, 93) | 0 | 0 in the local form |
| Lane-hours (estimates) | 3-5 | 23-49; 80-150 if every slot is widened |
| Code that does not use it | no function differs in 751 programs (measured on a prototype) | unchanged (estimate) |
| Proof and rules | A18's text gains a clause | a verifier exception, a validator condition, Lean fixtures, and a new rule: a record or list that holds a view cannot be passed whole to a function |

- **H5 by frame blocks (6 cells, 3-5 h, estimate):** a plain `str`, `bytes` or list parameter stored in a local list or
  dictionary holds its frame block, the mechanism the user approved for records on 9 November (RB1, A18). A 7-line prototype
  accepts the six cells with every certificate validated; they run in four modes under the leak check. This is D7's question.
- **H4's rebound local (3 cells) is a checker hole:** `mut c = p[0:2]` assigned again already has the representation it needs
  (a view phi). It joins O3 with H1.
- **H3 for text, bytes and lists, and H4's stored slices (18 cells), stay refused** and are listed as limits. Frame blocks take
  them only with a copy the compiler inserts in each loop iteration; the either-shape takes them at the price of the new rule.
- **The cells are about the model's regularity, not speed.** No site of the port is in these positions and stays inside its
  function: the port's 53, 38 and 93 sites all leave their function, and are 0.01% and 0.10-0.12% of its wall time.
- **R5** (a `from` function that returns a borrow on one path and a fresh owner on another): frame blocks cannot do it; under
  the either-shape it is 20 to 40 lane-hours (estimate), changes the signature of 107 of the port's 236 `from` functions and
  meets the proof problem that withdrew RB2's form.

- **D7. After the spike.** **Decided by the user on 10 November: build H5 by frame blocks**, and leave the 18 cells as
  documented limits. The either-shape is not built. X3 now reads "refused only for H3 (text, bytes, lists) and H4's stored
  slices". Lane OC builds H5 and D8's refusal after H1, in its own files, each as its own landing.

**Z3, costed for the user, not planned.** For `check` to run the placement of ownership operations that `build` runs: 10 to
20 lane-hours; a cold check of the port roughly doubles (about +1.5 to +3 CPU-s) and a one-function edit costs about +0.05 to
0.2 s more (a sampled profile on a loaded machine); LLVM and clang failures stay outside it. The coordinator's recommendation
is to defer it: the gate now holds two tests of the disagreement (lane CB's corpus test and the matrix).

**D8's count.** A probe compiler found no site outside the matrix that gives a text or bytes slice to an `own` parameter:
none in `tests/`, `examples/`, `bench/`, `src/stdlib`, the 747-program corpus or the port. The refusal would move two cells
to `E_SLICE_ESCAPES` (W4), and `mylang fix` would write `keep(copy(p[0:2]))`.

**O3's H2 landed** (`d9a8aa532`): `Some(place)` bound to a local is an option of a borrow. 32 cells moved from refused to
accepted (the other 7 of the 39 have a fresh call as the source and were never refused), no other cell changed, and rule 1's
shape now covers 780 refused cells.

**O3's H3 for records landed** (`460d22270`): the record a `from` function returns is lent where the field it returns would
be, so it can be a field of a borrowed record, an element of a local list or dictionary of borrows, or the payload of a
`const` option local. 4 cells moved from refused to accepted (the fourth is H2's `Some` of a `from` result). One refused
cell, `item__from_call__dict_local__own`, now reports only its marker error, with a correct repair. Rule 1's shape covers
776 refused cells. A record built from such results and returned under `from` is newly accepted as well. The port checks
with 0 errors as before, and no existing function of 750 corpus programs emits different LLVM. H4's rebound local is costed
at 2 to 4 lane-hours in the checker only (the lane's estimate).

**O3's H1 landed (D4)** (`89bd0ca79`): `mut c = place` stored once borrows the place, as a `const` does and as a `mut` local
assigned more than once already did. A write through `c` is refused at the write, in the Escape shape, with the code and
rule the binding had before and both repairs named at the binding; `mylang fix` writes the copy in one round and settles.
36 cells moved from refused to accepted (12 B2, 8 M1, and 4 each of B7, B8, R1 and R3), no other cell moved, and rule 1's
shape covers 740 refused cells. Nothing accepted before is refused: the port checks with 0 errors and the same warnings, no
existing function of 750 corpus programs emits different LLVM, and 42 existing tests that pinned the old refusal of a
read-only `mut c = place` now pin D4. The validator and the Lean model are unchanged.

**D8 landed** (`f999d6158`): the check refuses a text or bytes slice given to an `own` parameter, as it refuses a list slice
(`E_SLICE_ESCAPES`, W4, at the slice, in the Escape shape), with `copy(...)` around the slice as the certain fix. A slice
written with `own` keeps its marker refusal (B2), which names the same copy; without that the two repairs alternated. Two
cells moved from accepted to refused, no other cell moved, the table of known build failures is empty, and rule 1's shape
covers 742 refused cells. **X4 holds without an exception: every cell the check accepts builds.** No site outside the matrix
is refused, over 1,668 inputs (`tests/`, `examples/`, `bench/`, `src/stdlib`, the 750-program corpus and the port). The
migration corpus is `test/fixtures/fix-migration/text-slice-own.my`: `mylang fix` writes its 10 edits in one round and a
second pass finds nothing.

**O3's H4, the slice in a `mut` local, landed** (`c62566298`): a text, bytes or list slice stored into a `mut` local that is
only read borrows the slice's source, whether the local is stored once or assigned again. 6 cells moved from refused to
accepted (the 3 rebound-local cells, and the 3 once-stored cells H1 had left for this stage); no other cell moved, and rule
1's shape covers 736 refused cells. A list slice stored this way lowers to a view (`listSliceView`), with no copy; text and
bytes already did. The validator and the Lean model are unchanged, `E_CORE_HIDDEN_COPY` is silent, no existing function of
750 corpus programs emits different LLVM, and over 1,668 inputs no file gains or loses an error. A write through the local,
a store of it, a return without `from` or a change of its owner while it is live keeps the slice's refusal (V2) with
`copy(...)`. 12 existing tests that pinned the old refusal of a read-only slice local now make the local an owner to keep
what they test.

**O3's H5 by frame blocks landed, and Part B's stages are complete** (`5fcf9f170`). A plain `str`, `bytes` or list parameter
stored in a local list or dictionary holds its frame block (RB1's mechanism): one copy per call, freed before every return,
reported by `--stats`. 6 cells moved. Every escape is still refused (a returned collection, a `mut` out-parameter, a record
that holds the collection, an element returned under `from`). The spike's prototype failed certificate validation on a
dictionary write and on a parameter read in a loop, so the frame block is decided from the typed read, as RB1 decides it
for a record field. **The user approved on 10 November widening trust point A18's wording** to "the block a borrowed
record, or an element of a local collection of borrows (H5), holds"; the validator and the Lean model are unchanged and no
trust point was added.

| Part B | Start (10 November) | End |
| --- | ---: | ---: |
| Cells accepted and built | 936 | 1,018 |
| Refused by `check` | 839 | 757 |
| Accepted by `check`, failing in `build` | 0 with a ReleaseFast compiler, 7 with a Debug one | 0 |
| Function-local cells where a bare name lends | 204 of 312 | 288 of 312 |

Moves to accepted: H2 32, H3 for records 4, H1 36, H4 6, H5 6. Moves to refused: D8 2.

- **X1** met (O1). **X2** met (O2): one shape on 730 refused rule-1 cells, 57 marker wordings beside it. **X4** met and
  gated, with no exception since D8. **X5** met except where the user decided otherwise (D8's two cells). **X6** met at each
  landing.
- **X3, reworded by the coordinator:** in function-local positions a bare name is refused only where a view would be held
  in a local aggregate: a `from` result or a slice of text, bytes or a list stored in a local record, list, dictionary or
  option. That is 24 of 312 cells, not the 18 counted earlier: the 6 more are the option form (`Some(view)` as a local),
  left over from H2. `docs/ownership-rules.md` lists them under Current limits with what would remove them (the either-shape
  for local aggregates, 23 to 49 lane-hours by the spike's estimate; or views kept as fields of a record's value for the 6
  record cells, 3 to 6 lane-hours).

**A task's option argument builds** (`27d199a97`, found while testing H2): `check` accepted `g.submit(f, s)` with `s: str?`
and the build refused the thunk, for an owned option on main as well as for the lent ones H2 added. The thunk now lends each
argument as `parallel.map` does. Over 748 corpus programs only the three option thunks of the new test emit different LLVM.
A general protection fault of the compiler seen once on the first H2 build did not recur in 20 reruns of `tests/lang` on a
Debug compiler (it is the machine fault F22; see the stage 3 note in this section).

### 10.3 Lanes

Three lanes at most (the user's limit), each in its own worktree and branch. Each stage lands alone: the lane merges main and runs
the complete gate, the coordinator fast-forwards main and runs main's gate. Briefs: `~/ai/.home-cache/goals/`.

| Lane | Stages | Worktree, branch | Files it owns |
| --- | --- | --- | --- |
| TL | Part A: 0, 1, 2 (landed), then 4 | `mylang-devloop`, `testloop/stages` | `src/core/test_runner*.zig` |
| OD | O1, then O2 | `mylang-editcheck`, `own/model-reference` | `docs/ownership-rules.md`, the wording of rule 1's refusals |
| OC | O5's gate, O0, then O3 | `mylang-gate`, `own/bare-lends` | what the checker accepts; lowering |
| EM | Part A: 5 (step 1 landed), then 3 | `mylang-editcheck`, `testloop/emission` | emission; the unit path of `pipeline.zig`; stage 3's files once its profile names them |

O4 (the spike, no landing) takes the first lane that frees up. Progress is in `experiments/test-loop-20261109/status.md` and
`experiments/ownership-matrix-20261109/DECISIONS.md` as the lanes write them.

### 10.4 Where the run ended (10 November)

**Part A, the final measurement** on main `1473ac3dd`, a ReleaseFast compiler, the port's rows each in its own timing window
and run in two orders (`experiments/test-loop-20261109/status.md`, "Final measurement, 10 November").

| Exit | Target | Stage 0 | Final | Met |
| --- | --- | --- | --- | --- |
| E1, leaf edit at 1,600 modules | 9 G | 54 to 70 G | 23.2 to 23.5 G | no |
| E2, growth from 400 to 1,600 modules | 4.5 times | 6.3 to 7.2 | 4.26 | yes |
| E3, comment in `common` | 6.5 G | 13.2 G | 1.33 G | yes |
| E4, port row B (a comment reworded) | 10 CPU-s | 70 to 93 | 1.5 to 1.6 | yes |
| E4, port row C (a comment line added) | 10 CPU-s | 70 to 93 | 1.7; 69.8 when it follows a reverted body edit | in one order |
| E4, port row F (a new function) | 10 CPU-s | 70 to 93 | 70 to 71 | no |
| E5, port row D less B plus 10 | 140 CPU-s | 199 | 152 to 169 | no |
| E6, executions for 3,200 tests | 3,200 | 47,270 | 3,200 | yes |
| E7, a file run after a directory run, and the reverse | 0 run | 64; 2 | 0; 0 | yes |
| E8, unchanged run at 1,600 modules | 1.22 G | 1.22 G | 1.224 G | 0.3% over |
| E9, exactness | same verdicts | | 3,034 tests the same in every mode; verify clean | yes |

- **E1** is not met: stage 5b, which built the test program through demand, closed without landing (10.2). The leaf edit
  went from 54-70 G to 23 G by stages 1, 3, 4 and 5's step 1.
- **E4's row F and E5** are not met. **The user decided on 10 November not to build either costed route** (by reach, 16 to
  28 lane-hours; the shared check with test files overlaid, 8 to 16 lane-hours); both are in the lane's DECISIONS.md
  (D-TL6-5, D-TL6-6).
- **Row C in the other order:** a report argument keeps one record, so a comment edit made right after a body edit is
  reverted finds the body edit's record and misses. Keeping a few records for each argument would fix it; not built.
- **E8** is 0.3% over (about 4 M instructions since stage 6's own measurement of 1.221 G); not profiled.

**Part B** is complete (10.2): X1, X2, X4, X5 and X6 met, X3 met as reworded (24 cells are documented limits), the matrix at
1,018 accepted, 757 refused and 0 that the check accepts and the build refuses.

**The user's decisions during the run:** D7, build H5 by frame blocks; D8, the check refuses a text or bytes slice given to
an `own` parameter; A18's wording widened to elements of a local collection of borrows; the silent per-iteration copy in
`readOnlyArgument` to be refused in lowering; no further work on the port's rows F and D.

**Found and left for later, none caused by this run unless said:**

- `mylang build --verify-facts` of `tests/lang/live_place_iteration.my` and `test/core/i_live_place.my` fails with
  `E_CORE_INVALID_IR` (an operand that does not dominate its use, in the functions that append inside a loop with
  `continue`), debug and release, on the compiler of `fef979d1b` as well. A plain build and `mylang test` pass, so no gate
  sees it.
- The machine fault F22 (a Debug compiler dying at an `@memset`) was seen three times; it failed one lane gate, which passed
  on rerun.
- The port's shared check fails with `E_PRIVATE_SYMBOL` and falls back to one child for each root without saying so.
- A docstring example's key holds its docstring's line numbers, so a line shift reruns examples and keeps their modules off
  the token route.
- For a later attempt at stage 5b: names of a headerless entry are qualified after lowering, so its deferred bodies never
  restore; two preparation steps walk every function of a test program even when nearly all are deferred; the test-program
  store should compact once for a directory run.
- From Part B: lowering recomputes the checker's tables by itself; the matrix labels cells by position, not by cause.

**The silent copy is refused (landed 10 November, `9be6cad73`).** Where lowering would lend a text or bytes view as a
borrowed block, `view_materialize` copied it with no `copy(...)` written; a `--verify-facts` build reported that, and a
plain build of a ReleaseFast compiler did not. Lowering now refuses there in every mode (Z3, `hiddenViewBorrow`), as it
already does for a view field of a borrowed record. No program reaches it: 0 hidden copies over 757 programs, the three
language suites and the port's 86 test files; the check's verdicts are unchanged over 1,676 inputs; no function's LLVM
changes.
