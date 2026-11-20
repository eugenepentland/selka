# The lane kit

An audit of 34 lanes (15 November 2026) found that a lane writes its fix in minutes and then spends 60 to 70 per cent of its
steps proving it, with a harness it rebuilds by hand each time: a baseline compiler, clones of the projects prepared by the old
compiler, a sweep script, a cost script and a block of store variables. The kit is that harness, written once, as scripts under
`scripts/lane/`. Nothing here is wired into `zig build` or the gate, and Python is fine in it.

Every script has a usage line on `-h`, prints at most 25 lines on success (the details go to a file it names), runs at most three
compiler processes at a time, and sets the cache variables (`XDG_CACHE_HOME`, `SELKA_CORE_RUNTIME_CACHE`,
`SELKA_STAGE_SHARED_CACHE`) on the commands it runs only, on stores under the kit, never under `~/.cache/selka`.

| Script | What it does |
| --- | --- |
| `kit.sh prepare [REV]` | Makes `~/ai/.home-cache/aw/kit/<short REV>/` once (REV defaults to main's head): `base/` a Debug compiler of REV, `proj/` four projects prepared by the base compiler's `selka fix` only, `proj-base/` the base compiler's check of each, `PROJECTS.txt`. A no-op when the `READY` file is there. |
| `with-stores.sh DIR COMMAND...` | Runs COMMAND with the three store variables under DIR, for that command only. Refuses a DIR under `~/.cache`. |
| `newly-refused.sh COMPILER [KIT]` | Checks every prepared project with COMPILER, compares with `proj-base/` error by error (file, line, code), counts COMPILER's `selka fix --check` edits on the old-prepared trees by code. Exit 0 when nothing is newly refused. |
| `cost-check.sh BASE NEW [KIT]` | A warm check of the port, base against new, three pairs: user-mode instructions and CPU seconds; one line with the median ratio against 1.02. Refuses to start while a gate or a compiler build runs. |
| `probe.sh [--compiler PATH] [--asan] [--limit S] FILE.selka...` | Per file: `check`, `run` with the leak check, `run --release`; one line each, then a count line and `exit status N; details DIR`. Waits at most 270 seconds; `probe.sh --wait DIR` waits again. |
| `../focused_test.py TARGET FILTER`, `../focused_test.py --wait PID` | (in `scripts/`) A focused Zig test run that waits in the foreground (270 seconds) and prints one line on a pass, only the failing tests on a failure, and always `exit status N; log PATH` last. See "Test runs that wait". |
| `probe-skeleton.selka` | A program that passes `check`, with the list of slips lanes make in probe programs. |
| `finish.sh` | For the coordinator, in a lane's worktree after it hands back: dirty-tree refusal, `git merge main`, the repair of `CHANGES.md`'s dropped blank lines, the complete gate with `--fail-fast` (rerun once for a known machine signature), `corpus_exact.py`. |
| `handback.sh [BASE]` | In the lane's worktree before it hands back: the checks of the repair pass's common rules that apply to the files changed since BASE (default: the merge base with `main`; uncommitted and untracked files count), one line each, `--only NAME` to rerun one, `--plan` to see which apply and why. It never builds and never runs the gate, the edit check or a test root. |
| `selftest.sh` | Everything above that can be proved without a gate, in a few minutes. |
| `../where.py QUERY...` | (in `scripts/`, not `scripts/lane/`) Where a diagnostic code is raised, built, fixed, tested and documented; the same from a piece of its message; or a function's definition, callers and tests. At most 25 lines, under a second, no build and no index. With `--body` the lines of each named declaration; `--around PATH:LINE` the declaration that holds a line. |
| `../precommit.sh` | (in `scripts/`, not `scripts/lane/`) Was the commit hook's Guardian check without committing. Guardian was turned off on 18 November 2026 (GH-2): it prints `Guardian is off since GH-2; nothing to check` and exits 0, and stays only because lane cards and `handback.sh` call it. |

`kit-base.sh`, `kitproj.py` and `lib.sh` are parts the others call.

## The kit

```bash
scripts/lane/kit.sh prepare          # main's head; scripts/lane/kit.sh prepare REV for another commit
scripts/lane/kit.sh path             # where that kit is
```

The base compiler is built in a detached worktree under the kit with its own `ZIG_LOCAL_CACHE_DIR`, through
`scripts/build-slot.sh build`. A commit from before GH-2 (18 November 2026) names `.guardian = .{ .path = "../guardian-zig" }`
in `build.zig.zon`, and before GH-3a (19 November 2026) the seed build of `selfhost/components.zig` links a sibling `guardian-zig`; a scratch
worktree has no sibling (the `no module named 'guardian'` every lane met), so for such a commit the build tree sits in
`base.build/` beside a symlink `guardian-zig` to `~/ai/canopy/guardian-zig` (`KIT_GUARDIAN`). A commit that needs neither
gets no symlink. The repository's build files are untouched and the worktree is removed at the end.

The projects are `netlisp-selka-redo` (the port), `selka-protobuf`, `selka-sqlite` (clones at their heads) and
`artifacts-site` (`git archive HEAD` of its tracked source; that folder is read only). Each is prepared with the **base**
compiler's `selka fix` only, never a lane's own: a refusal that carries a repair is hidden by the repair
(`RULES.md`, "Counting newly refused"). A project whose base check does not pass is recorded as it is. `PROJECTS.txt` lists the
units, one line each, tab separated: `prepare NAME DIR fix TARGET` and `check NAME DIR check TARGET --warnings --no-cache`, run in
`DIR` inside the project. `proj-base/` holds, per check unit, `<unit>.out` (the raw output), `<unit>.diag` (one line per
diagnostic: severity, file:line, code), `<unit>.rc`, `SUMMARY.txt`, and `fixcheck.txt` (what the base compiler's own
`fix --check` would still edit, none on a prepared tree).

```console
$ scripts/lane/kit.sh prepare
kit 1ab811cfd4: starting; memory available 20 GiB, disk free 421G
kit 1ab811cfd4: base compiler (Debug, selka commit 1ab811cfd457) in 42s
kit 1ab811cfd4: clones in 2s
kit 1ab811cfd4: prepared with the base compiler's selka fix in 646s
kit 1ab811cfd4: base check and fix --check of every unit in 592s
  artifacts-site: 5 units, base check 1 errors, 61 warnings, 1 units not clean
  netlisp-selka-redo: 1 units, base check 0 errors, 311 warnings, 0 units not clean
  selka-protobuf: 21 units, base check 23 errors, 0 warnings, 19 units not clean
  selka-sqlite: 7 units, base check 7 errors, 1 warnings, 3 units not clean
  base fix --check: 0 files would still change
kit 1ab811cfd4: READY at /home/epentland/ai/.home-cache/aw/kit/1ab811cfd4, 741M, total 1240s
```

The times are those of a machine shared with three other lanes. The kit is a few hundred megabytes; remove a kit of a
commit nobody uses with `rm -rf`.

## with-stores.sh

```bash
scripts/lane/with-stores.sh ~/ai/.home-cache/aw/mylane/stores zig-out/bin/selka run probe.sh.selka
scripts/lane/with-stores.sh ~/.cache/selka/x true     # refused: with-stores.sh: ... is under ~/.cache (the per-user stores)
```

The three variables point at `DIR/xdg`, `DIR/rt` and `DIR/stage` for that command only; the caller's shell is untouched. On this
machine `~/.cache/selka` is a symlink into `~/ai/.home-cache/mylang`, so both the logical and the resolved path are refused.

## newly-refused.sh

```bash
scripts/lane/newly-refused.sh zig-out/bin/selka          # the newest READY kit
scripts/lane/newly-refused.sh /path/to/selka KITDIR
```

```console
$ scripts/lane/newly-refused.sh zig-out/bin/selka
newly-refused: selka commit 646aa7546468, identity 9a415e6fe727 against kit 646aa75464 (base 646aa7546468), 34 units in 356s
artifacts-site: newly refused 0, no longer refused 0, warnings +0 -0, fix --check edits by code: none
netlisp-selka-redo: newly refused 0, no longer refused 0, warnings +0 -0, fix --check edits by code: none
selka-protobuf: newly refused 0, no longer refused 0, warnings +0 -0, fix --check edits by code: none
selka-sqlite: newly refused 0, no longer refused 0, warnings +0 -0, fix --check edits by code: none
full comparison: .../kit/646aa75464/refused/9a415e6fe727/COMPARISON.txt (raw output per unit beside it)
```

With a compiler that refuses something, the sqlite line and the places below it read (an invented example, from the self test):

```console
selka-sqlite: newly refused 2, no longer refused 0, warnings +1 -0, fix --check edits by code: E_METHOD_REMOVED 2, W_MATCH_ELSE 1
NEW selka-sqlite lib lib/x.selka:12 E_FAKE
NEW selka-sqlite fix --check would edit lib/y.selka (2 edits, E_METHOD_REMOVED)
```

Output: one line per project, up to ten newly refused places (`NEW project unit file:line CODE`, or `NEW project fix --check
would edit FILE (N edits, CODES)`), the path of the full comparison. An edit that `fix --check` would still make under an `E_`
code is a newly refused place that a repair would have hidden; a `W_` edit is counted by code and is not a refusal. A line of
`fix --check` that lists two codes counts under both joined with `+`.

## cost-check.sh

```bash
scripts/lane/cost-check.sh KIT_BASE_COMPILER zig-out/bin/selka
scripts/build-slot.sh timing scripts/lane/cost-check.sh BASE NEW      # in an exclusive window
```

```console
$ scripts/lane/cost-check.sh .../kit/1ab811cfd4/base/bin/selka .../kit/646aa75464/base/bin/selka
cost-check: warm check of the port (kit 646aa75464), base against new, 3 pairs, 135s
  pair 1: 29.173 G vs 29.193 G instructions, ratio 1.001; CPU 7.12 s vs 7.13 s
  pair 2: 27.756 G vs 27.728 G instructions, ratio 0.999; CPU 6.98 s vs 6.99 s
  pair 3: 27.770 G vs 27.747 G instructions, ratio 0.999; CPU 6.97 s vs 6.96 s
median instruction ratio 0.999 (CPU seconds median ratio 1.001): WITHIN 1.02; details .../kit/646aa75464/cost/
```

That run compared the Debug compilers of main at `1ab811cfd4` and at `646aa75464`, on a calm machine. Both compilers should be
Debug compilers of the same kind. It copies the old-prepared port twice, runs one cold check each, then
three pairs (base, new, back to back): a new function is appended to `src/main.selka` and `check src --warnings` is timed under
`taskset -c 0-11` (`COST_CPUS` changes the cores) with `perf stat --no-scale -e cpu_core/instructions/u`. It refuses to start
while `verify_cache.py` or a `zig build` is running (`--ignore-busy` for a dry run whose numbers are not evidence). Exit 0 when
the median ratio is at most 1.02.

## probe.sh and the skeleton

```bash
cp scripts/lane/probe-skeleton.selka /path/to/scratch/p1.selka
scripts/lane/probe.sh /path/to/scratch/p1.selka /path/to/scratch/p2.selka
scripts/lane/probe.sh --compiler ~/ai/.../base/bin/selka --asan p1.selka     # AddressSanitizer on the debug run
```

```console
$ scripts/lane/probe.sh scripts/lane/probe-skeleton.selka refused.selka trap.selka
scripts/lane/probe-skeleton.selka: check ok | debug+leakcheck ok | release ok | same | out: probe=1|
refused.selka: check REFUSED E_UNUSED_CAPABILITY at line 1 (status 1), not run
trap.selka: check ok | debug+leakcheck status 1 R_LIST_BOUNDS | release status 1 R_LIST_BOUNDS | same | out: (no stdout) err: trap.selka:4:16: error[R_LIST_BOUNDS]: native execution failed (index 3, length 2)
probe: 3 files, 1 check REFUSED, 1 run not ok, 0 debug and release DIFFERENT, in 18s
exit status 0; details (every step's output) .../kit/probe-out/261115-190112
```

The compiler defaults to `zig-out/bin/selka` of the worktree the script is in. With `--asan` the debug step runs under
AddressSanitizer (`SELKA_CORE_SANITIZE=address`, `--max-memory 0`) and its label says so. The skeleton's comment block lists the
slips lanes make in probe programs, each checked against the compiler.

## Test runs that wait and print only what failed

An audit of 52 lanes (18 November 2026) found 530 turns that only waited for a test run, polled it or read its log, because the
runner printed the last 60 build lines and the next turn grepped the log. `scripts/focused_test.py`, `scripts/dev_loop.py test`
and `probe.sh` now wait in the foreground and print the answer; `scripts/failure_report.py` is the one reader they share (import
it: `failure_report.render(text, exit_status, what, seconds)` returns the lines, `closing(status, log)` the last line).

```console
$ python3 scripts/focused_test.py units arena --no-watch
PASS units 'arena': 34 passed, 0 skipped (34 selected) in 41.2s
exit status 0; log /.../.selka-cache/focused-tests/units-arena-20261118-101500.log

$ python3 scripts/focused_test.py cli directory --no-watch
FAIL cli 'directory': 0 passed, 1 failed, 0 skipped in 38.0s
FAILED integration.test.a directory test run ends with one line for the warnings it withheld, each counted once, ...
  expected 1, found 3
  at test/integration.zig:8220  try testing.expectEqual(@as(usize, 1), std.mem.count(u8, ran.stderr, "warnings: "));
exit status 1; log /.../.selka-cache/focused-tests/cli-directory-20261118-101540.log

$ python3 scripts/focused_test.py full
still running after 270s (pid 24817): full
wait: python3 scripts/focused_test.py --wait 24817
exit status 124; log /.../.selka-cache/focused-tests/full-full-20261118-101600.log
```

- **The exit status is the verdict.** The reader only chooses what to print. A failed run in which no known form is found prints
  the last 20 lines and says `no known failure form in the log`; a run that exits 0 but whose text shows a failure prints FAIL and
  `focused_test.py` exits 1 (`dev_loop.py test` keeps the binary's status exactly). A passing log is never a pass for a nonzero
  status.
- **A failure is at most 30 lines**: each failing test's full name, then its `expected N, found M` line, or the first difference
  of two strings (`first difference at line 3`, `expected: ...`, `found: ...`), or the panic line, then `at FILE:LINE  source
  line` of the test and, when an inner repository frame differs, `error from FILE:LINE  source line`. With more failures than fit,
  every name that fits and `... and K more failing tests (names: grep ...)`.
- **Forms read**, each from a real log kept in `scripts/run-report-fixtures/` (its `README.txt` says which are constructed):
  expect failures (integers, strings, a bare `expect`), an error returned from inside, a panic (`exited with code 134 with
  stderr:`), a leak, a test killed at its deadline (`test deadline: ... killed`), a compile error in a test root, a filter that
  named no test, the F22 signature (`trap=13`: it says to run the test once more), a run still queued for a build slot
  (`build-slot: FIFO ticket N, position P; ... waiting`), and the test binary's own form that `dev_loop.py test` runs (`N
  name...FAIL (Err)`, the message before it, the trace after).
- **At the limit** (`--limit`, default 270 seconds, under the lane card's 280) the run goes on in a session of its own and the
  wrapper says so with the process id and the one command that waits again; `--wait PID` prints the same result as a run that had
  finished, and may be repeated. Exit status 124 means "not finished", never a pass. `kill -TERM -- -PID` ends the run (its own
  process group). If the run's shell is killed before it wrote a status, `--wait` says so and exits 1.
- `focused_test.py` still runs the watcher's binaries when this worktree's watcher runs (`dev_loop.py test`, printed the same way,
  without a time limit of its own); `--no-watch` builds.
- `probe.sh` prints one line a file as before, then `probe: N files, K check REFUSED, M run not ok, D debug and release DIFFERENT,
  in Ns` and `exit status 0; details DIR`. A refused or failing file is a line, not a failing exit status. At the limit it prints
  the lines so far, `still running ... (pid N): 2 of 3 files done; not yet: NAME...`, `wait: scripts/lane/probe.sh --wait DIR` and
  exits 124.

The tests are `tests/test_focused_test.py` (the reader on every fixture, the limit and `--wait` on real shell commands, `probe.sh`
with a stand-in compiler) and one case of `scripts/dev_loop_test.py`.

## finish.sh

```bash
scripts/lane/finish.sh               # in the lane's worktree, after it hands back
scripts/lane/finish.sh --merge-only  # stop after the merge and the repair of CHANGES.md
scripts/lane/finish.sh --headings     # list the ### headings of CHANGES.md without a blank line before; changes nothing
```

```console
$ scripts/lane/finish.sh --merge-only
finish: lane: merged main ee492b8799 cleanly (Merge made by the 'ort' strategy.), now at 89bf7392c4
finish: CHANGES.md: put back the blank line before 1 ### heading(s) the union merge dropped; committed, now at 3f1c0d52ab
```

A whole run ends with the gate's verdict line and commit, the exactness line and the log path (from the self test, with stand-ins
for the gate and the corpus):

```console
finish: gate at bf35997c47: verification: PASS; in 1.0 s; 51 reused, 0 executed; log: x (first run: RERUN deadline; rerun once by itself)
finish: corpus_exact: builds 3: identical 3, different 0, failed both ways 0, failed one way 0
finish: log .../finish-logs/lane-190504-rerun.log, 0s in all
```

It refuses a dirty tree and branch `main`, stops on a merge conflict, and after a clean merge puts back the blank line that the
union merge dropped before a `###` heading of `CHANGES.md`: it commits that one file as "CHANGES.md: the blank line the union merge
dropped" (no trailer; the commit hook runs as for any commit), prints the one line above and goes on. It stops, with the file
restored and nothing staged, if the repair would be anything but one added blank line for each heading in `CHANGES.md` alone.
Then the complete gate (`--fail-fast`); a failure that carries
only a `test deadline:`, `shared compiler cache: WriteFailed` or the F22 signature (`General protection exception`, `trap=13`,
or a segmentation fault at a `memset`) is rerun once by itself, and a log with a `(failed)` test is never rerun. Last
`corpus_exact.py` on the tree's Debug compiler (rebuilt first when it is not of HEAD). Logs go to the kit's `finish-logs/`. The
real gate was not run by the lane that wrote the script: the self test runs the whole path against stand-ins for
`verify_cache.py`, `corpus_exact.py` and the compiler, and the classifier on saved log text. The classifier is a heuristic.

**Which worktree gates (15 November, from `scripts/verify_cache.py` and the day's gate logs).** Evidence is not kept per
worktree. `prior_success` looks an action's key up in one store that every worktree of the user shares (`shared_cache_location`:
`--shared-cache-dir`, then `SELKA_VERIFICATION_SHARED_CACHE`, else `$XDG_CACHE_HOME/selka/verification-shared`, which is
`~/.cache/selka/verification-shared` unless `XDG_CACHE_HOME` is set); the worktree's own `.selka-
cache/verification-v3/actions/` receipts count only when no shared store is open. Keys hold no checkout path: all 560 actions in
the ten worktrees' `last-run.json` say `path_free: true`, and the environment digest is the same in `selka-editcheck`, `selka-
gate` and `mylang-lane-fr4`. Reuse across worktrees happens: the B2 gate in `mylang-checkbuild` (17 reused) and `mylang-gate`
hold the same 17 action keys. What a gate reuses is whatever a gate of the same inputs left, wherever it ran (`many-agents.md`,
"One gate per landing": content, mode, owner and untracked files of every input), so a worktree matters only through its files
and through `XDG_CACHE_HOME`: a shell that exports it to a scratch folder gates against an empty store. A scripts-and-docs lane
merged onto a main whose tree was gated reuses the actions that read `src/` and runs the ones that read `scripts/` and `docs/`:
KIT (37.1 s) and B4 (24.1 s) were 45 reused, 6 executed, both in `mylang-gate`. B5 (scripts and docs) took 650 s with 0 of 51
reused, in `mylang-lane-fr4`: it was gated on main just after lane C2 landed, and C2's own gate had passed with one flaky test
rerun alone (`1 flaky test(s) passed when rerun alone`). A request that needed a flaky rerun publishes nothing
(`scripts/verify_cache.py`, the comment at the rerun), so the next gate of that tree finds no evidence and runs every action.
So the worktree does not matter. What to read is the previous gate's verdict line: when it names a flaky rerun, the next gate
on that tree is a full one, and a scripts-and-docs lane then costs ten minutes where 30 seconds would do.
`finish.sh` is unchanged for this: no safe option was found, and `verify_cache.py` is not touched.

## handback.sh

```bash
scripts/lane/handback.sh                 # every check that applies to what changed since the merge base with main
scripts/lane/handback.sh --plan          # which checks apply and why, running nothing
scripts/lane/handback.sh --only my-lint  # rerun one (a guide page: --only doctest:docs/io.md); --with NAME forces one that does not apply
scripts/lane/handback.sh --rest          # run what the last run left LATER
scripts/lane/handback.sh --only newly-refused --bg   # a check too long for one command, detached; then:
scripts/lane/handback.sh --wait          # up to 270 s for it, then its lines (the same command again when it says STILL RUNNING)
```

It replaces the ten or so turns at the end of a lane that ran the checks of the common rules one or two at a time. One line per
check, `PASS name (Ns)`, `FAIL name (Ns): the first problem line`, `SKIP name: why it does not apply` or `LATER name: why it did not
run`; then at most ten lines of detail for each failure; then `handback: N passed, M failed, K skipped, L later; exit E; log PATH`
(every check's full output is in that folder). Exit 0: every check that applies passed. 1: one failed. 2: a host problem (the
compiler is missing or older than a compiler input of the tree, `$ZIG` is not set, no such base): one line, nothing is run, nothing
is built. 3: nothing failed but a check is still to run. A check's exit status alone decides its verdict; what it printed only
chooses which lines to show, and a check that prints "passed" and exits non-zero is a FAIL.

```console
$ scripts/lane/handback.sh                 # a lane that changed two guide pages
SKIP zig-fmt: no Zig file changed
PASS precommit (0s)
PASS cheap-checks (3s): cheap checks: passed (zig-format 1.0 s, coverage 0.6 s, my_format 2.0 s, doc-coverage 0.4 s...
SKIP my-fmt: no live .selka file changed
...
PASS doc-coverage (0s): doc-coverage: 0 failures
PASS doctest:docs/concurrency.md (3s): 1 files scanned, 19 blocks found, 12 run, 6 checked, 0 skipped, 0 mis-tagged, 0 failed
PASS doctest:docs/functions.md (4s): 1 files scanned, 20 blocks found, 19 run, 1 checked, 0 skipped, 0 mis-tagged, 0 failed
SKIP newly-refused: no compiler source that decides a verdict changed (non-test Zig under src/, src/stdlib/*.selka)
handback: 5 passed, 0 failed, 10 skipped, 0 later; exit 0; log ~/ai/.home-cache/aw/kit/handback-logs/mylang-lane-s4/261118-011608
$ scripts/lane/handback.sh --only zig-fmt,my-fmt,my-lint   # one badly formatted file of each kind
FAIL zig-fmt (0s): needs `zig fmt`: test/zz_handback_demo.zig
FAIL my-fmt (0s): 1 of 1 file(s): tests/lang/zz_handback_demo.selka:3:23: formatting differs: line 3 reads `public func test_demo( )  -> bool:` and the format...
FAIL my-lint (1s): 1 of 1 file(s): zz_handback_demo.selka:3:13: error[L_TEST_NO_ASSERTION]: test-no-assertion: test zz_handback_demo::test_demo has no assert statement
handback: 0 passed, 3 failed, 0 skipped, 0 later; exit 1; log ~/ai/.home-cache/aw/kit/handback-logs/mylang-lane-s4/261118-011514
```

**What each check is and when it applies.** The changed files are `git diff --name-status BASE` of the working tree (staged and unstaged
changes included, a rename as a delete and an add) plus the untracked files that git does not ignore.

| Check | Runs when | What it runs |
| --- | --- | --- |
| `zig-fmt` | a `.zig` file was added or changed | `"$ZIG" fmt --check` on those files |
| `precommit` | always | `scripts/precommit.sh` |
| `cheap-checks` | always | `scripts/gate_cheap_checks.py --compiler ... --zig "$ZIG"` (zig-format, coverage of test inputs, my_format, doc-coverage) |
| `my-fmt`, `my-lint` | a `.selka` file under a live root (`scripts/check_my_format.py`'s roots, minus its exclusion manifest) was added or changed | `selka fmt FILE --check` and `selka lint FILE --gate`, a file at a time |
| `union-tags` | a `.selka` file with a `public func test_` was **added** | `selka build ... --stats -o ...`; its `union-tags:` line must say 0 (a missing line is a failure) |
| `noalloc`, `programs` | a `.selka` file, or something under `src/`, `selfhost/`, `bench/`, `benchmarks/`, `examples/` changed | `scripts/check_noalloc.py`, `scripts/check_programs.py` |
| `doc-coverage` | something under `docs/`, `src/`, `selfhost/`, or `README.md`, `SPEC.md` changed | `selka doc-coverage .` |
| `doctest:PAGE` | a page of `README.md`, `SPEC.md`, `docs/**/*.md` was added or changed | `selka doctest . --filter PAGE`; a page doctest does not scan, or one with no `selka` example, is a SKIP |
| `producers` | a Zig file the tooling root (`src/tooling_root_test.zig`) imports was added, or the root, `verification_producers.py` or its test changed | every file the root reaches must be named in `CLOSURES['tooling-units']`, then `verification_producers_test` |
| `shard-plans` | a line `test ...` was added to a Zig file (untracked files included), or a shard plan changed | `verification_shard_plan_test` (names in sorted order) |
| `incremental-diff`, `newly-refused` | compiler source that decides a verdict changed: a non-test `.zig` under `src/` (not `src/core/runtime/`, not a pure tooling unit named in `CLOSURES['tooling-units']`), or a `.selka` under `src/stdlib/` or `selfhost/components/` | `tests/incremental_diff.py --steps 120`; `scripts/lane/newly-refused.sh` |

The rule for the last row is a decision of the script, not of the compiler: a `.zig` under `src/` that is no test, no C runtime and
no tooling unit may change what `selka check` accepts or prints, so both checks run; `--with NAME` forces one for a change the rule
does not see, `--only NAME` reruns one. A new guest test file is built through a stand-in when it has no `main`: a copy in the log
folder (with the sibling modules it imports) whose `main` calls each test that takes no parameter, with `try` for one that `fails`,
because a `main` that calls nothing lowers nothing and would count 0 whatever the tests hold; the PASS line says how many tests take
parameters and were not called, and a file with no callable test is a SKIP. A file that already has a `main` is built as it is.
Only added test files are built: a changed one may carry counts it already had.

**Time.** A docs-only change takes 10 to 15 seconds. Checks that need no compiler run beside compiler checks, at most three compiler
processes at once (`cheap-checks` holds all three: `gate_cheap_checks.py` runs its own `selka fmt` pool for about 3 seconds). A check
whose estimate (a table in the script) does not fit in the 270 seconds a run may start is not started: it is a `LATER` line with its
command, and `--rest` runs what the last run left. A check that outlives the budget is ended and listed LATER too, never passed.
`newly-refused` (about 6 minutes) is always LATER in a foreground run; start it with `--only newly-refused --bg` at the start of the
hand-back and `--wait` for it. **Left out on purpose:** the focused tests of what the lane changed (name them yourself: `focused_test.py
units FILTER`), `edit_check.py`, the gate, a changed (not added) guest test file's `union-tags`, and the check that a new Zig test's name
is in its shard plan (about a quarter of the tests are in no plan; the unit test of the plans decides the order only).

Logs: `~/ai/.home-cache/aw/kit/handback-logs/<worktree>/<UTC time>/` (`NAME.log` for each check, `handback.log` for the answer,
`standin/N/` for the stand-ins); `last.json` beside them names what was left LATER. `scripts/lane/handback_test.py` (about 20
seconds) proves each selection rule on a scratch repository with stand-in tools, that the exit status decides, that a stale compiler
stops the run, and the `--rest`, `--bg` and `--wait` paths; `selftest.sh` runs it.

## where.py

```bash
scripts/where.py E_OWN_MARKER        # a code: E_, W_, L_ or R_ and capitals
scripts/where.py "expected a name"   # a piece of a message: anything with a space or a quote (--text WORD for one word)
scripts/where.py takeNamedModifier   # a function
scripts/where.py --all QUERY         # no cap on the lists; --selftest runs the hand-checked queries
scripts/where.py A B "a message" --body    # several queries in one call; with --body each one's declaration, code included
scripts/where.py --around src/parser.zig:465    # the declaration that holds that line, the line marked `>`
```

Each argument is one query (quote a piece of a message); a call of several queries, or with `--body` or `--around`, prints at most
150 lines, a fair share to each. A single query without `--body` is answered as before.

It replaces the 7 to 15 steps a lane spent on `grep` and `sed -n` finding where a diagnostic is raised and where its tests are
(the audit of 15 November 2026). `git grep` of the working tree, new files included, answers each query; nothing is built or kept.
A code answers in this order: its row in `src/diagnostic_codes.zig`; each function that raises it (`file:line: function`, the other
lines of one function in brackets, a constant that holds the code followed to its uses); the `*Message` functions called at those
sites; whether a `fix` is set in the raising function or only elsewhere in its file; the tests that name it by kind, per file
`count (first three lines)`; the guide page the row names, with the heading of its first mention, and the other pages.

```console
$ scripts/where.py E_OWN_MARKER
E_OWN_MARKER: a code; 14 raising lines in 11 functions of 4 files, 3 lines that read it or list it (2 files)
  table: src/diagnostic_codes.zig:274: an `own` marker is missing where a named binding moves, or written where no marker be
  src/core/single_owner.zig:40: const own_read
  src/core/single_owner.zig:4322: rejectConstEscape (+2: 4328, 4333)
  ...
message: built by escapeMessage src/core/single_owner.zig:4817; escapeMessageAmong src/core/single_owner.zig:4828; ...
fix: yes, set in the raising function: src/sema_calls.zig:1114: checkMutationMarkers; ...
tests: 446 lines in 44 files (zig 37, golden 5, guest 2)
  zig    test/fix_cli_test.zig: 33 (228, 402, 403)
  ...
guide: docs/managed-memory.md:771 under "## Checked ownership" (1 mention)
```

It does not parse Zig. The function around a line is the nearest `fn NAME(` or `test "name"` above it at a smaller indentation; a
`///` or `//` line is neither a raise site nor a caller; a line that compares the code (`eql(`, `==`) is counted as a read, not a
raise. A function query counts callers by name, so two functions of one name are counted together (it says so). A `fix` set by a
helper the raising function calls shows as "in a raising file, not in the raising function".

### --body and --around

`--body` answers each name with the lines of its declaration, so that the next step can edit without a `grep -n` and a `sed -n`. A
name is a function, type, constant or test of a Zig file (`src/`, `test/`), a C function, macro, type or global
(`src/core/runtime/`), a Selka `func`, `record`, `enum`, `const` or `type` (`src/stdlib/`, `tests/lang/`, `test/`), or a Python or
shell function or assignment (`scripts/`). The header is `path:first-last: kind name`, where `first` is the first line of the doc
comment or decorators above it; then the code with its line numbers; a declaration over 60 lines is cut with the range that is
left (`not shown: path:1021-1096`, read it with the Read tool and an offset). Also taken: `A.b` (the `b` inside a declaration
named `A`, or in a file `A.*`, as `strings.join`), `PATH:NAME` and `PATH:LINE` (one file; the path may be a suffix,
`parser.zig:name`), a code (its table row and the first function that raises it; the others by first line) and a piece of a
message (the function that builds it).

```console
$ scripts/where.py reservedNameFailure init --body
src/parser.zig:462-467: fn reservedNameFailure
462:     /// A reserved word where a name belongs: say which word it is, so the
463:     /// reader renames the declaration instead of hunting for a syntax slip.
464:     fn reservedNameFailure(self: *Parser, token: lex.Token) diagnostic.Error {
...
467:     }

init: 158 declarations; name the file to choose one
  src/check_cache.zig:23: pub fn init(allocator: std.mem.Allocator, max_bytes: usize) Cache {
  ...
  ... 146 more
  choose: where.py src/check_cache.zig:23 --body  (PATH:LINE when one file declares it twice)
```

A name declared more than once is never printed in full: each match's first line, then how to choose (`PATH:NAME`, or `PATH:LINE`
when one file declares it twice). A local `const` (an indented one in Selka or Zig) is offered only when nothing else has the
name. `--around PATH:LINE [N]` takes the place a compiler error or a failed test names (`PATH:LINE:COL` too): the declaration that
holds the line with that line marked `>`; a declaration over 60 lines shows 60 lines around the line; `N` lines around the line
when a count is given or when no declaration holds it (21 lines). It does not parse: comments and the inside of strings are
blanked by a regular expression and a declaration is a line that starts like one (`scripts/where_body.py`), so a macro that
defines functions or a declaration in a language it does not know is missed or cut short. `python3 scripts/where_test.py` proves
it on a scratch repository (about 10 seconds; the gate does not run it, like `--selftest`). The Edit tool still wants the lines
opened with the Read tool: the range in the header is the one to open.

## selftest.sh

```console
$ scripts/lane/selftest.sh
ok    kit 646aa75464 is READY with a base compiler (selka commit 646aa7546468)
ok    kit.sh prepare is a no-op on a READY kit
ok    with-stores.sh refuses a folder under ~/.cache
...
ok    classifier: no verdict line
selftest: all checks passed
```

About seven minutes on a calm machine (six of them `newly-refused.sh`, the base compiler against itself); `SELFTEST_FAST=1`
skips that one. It makes the kit of main's head when it is missing (twelve minutes). The kit's stores, runs and logs stay
outside git, under `~/ai/.home-cache/aw/kit/`.
