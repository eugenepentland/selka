# Many agents on one machine

The development box (i7-12700H: 20 hardware threads, 30 GB of RAM) often runs
several agents at once, each with its own worktree. Three things keep them from
slowing each other down:

- a cap on concurrent builds and gates that also checks free memory;
- exclusive timing windows, while ordinary work uses all allowed CPUs;
- a private cache and temporary directory for each worktree.

The 2026-09-22 parity run ran without these. Gates took 3 to 5 times longer,
out-of-memory kills showed up as test failures, identical binaries timed up to
1.8× apart, and a full `/tmp` stopped every agent for an hour
([development-speed audit](../audits/development-speed-audit-2026-09-23.md) §2).

## Run builds and gates through `scripts/build-slot.sh`

```bash
scripts/build-slot.sh build zig build
scripts/build-slot.sh build zig build test-cli -Dtest-filter=benchmark
scripts/build-slot.sh gate  zig build test --summary all
scripts/build-slot.sh timing taskset -c 2 ./prebuilt-program
scripts/build-slot.sh status            # slots, MemAvailable, CPUs builds may use
```

`build` covers any compile or install, the focused `test-units`/`test-cli`
steps, `fmt-check` and `selka test <dir>`. `gate` covers the full gate,
`zig build test`. `timing` covers runtime and compiler-speed measurements.
The wrapper runs a job only when a slot of its kind is free **and**
`MemAvailable` is at least that kind's threshold. Otherwise it waits and says
why. When it finally runs the job it prints how long it took, and it passes the
job's exit status through unchanged.

That time is real: it runs from the start of `build-slot.sh` (before its Python
interpreter and the shadow observer start) to the moment the command is started, so
it counts the queue, the cache trim and the settle hand-off, and it has millisecond
resolution (`build-slot: build slot 1, FIFO ticket 7 after 0.412s`; it printed whole
polls, usually `after 0s`, until 13 November 2026).

The job's environment also carries that figure as `SELKA_ADMISSION_WAIT_S`: the
seconds, with milliseconds (`451.232`), from the request to the start of the command,
under the default backend and the scheduler alike. A wrapper whose own clock starts after
the queue, such as a lane's build-telemetry tool, reads it and records the time its
job spent queued behind other lanes' timing windows (F-S0-6 of the G3 port). The
variable is a placement setting, so it never enters a cache key, and an outer
job's value is replaced, never inherited. `SELKA_ADMISSION_STARTED_US`, the request's
start in microseconds since the epoch, is how `build-slot.sh` hands that start to the
admission that follows it; it is removed before the command starts.

```bash
scripts/build-slot.sh build sh -c 'echo "queued for $SELKA_ADMISSION_WAIT_S s"'
```

The following scheduling and timing rules describe the default shadow/legacy
backend. The opt-in scheduler can admit builds beside timing on disjoint reserved
CPUs; its contracts and required real-traffic qualification are documented in
[the development loop](development-loop.md).

Ordinary jobs use all CPUs allowed to the caller (20 logical CPUs on this host).
An explicitly set `SELKA_TIMING_CPUS` still excludes those CPUs from builds and
gates. It does not restrict timing commands, which inherit the caller's affinity;
put `taskset` inside the timing command when pinning a benchmark.

Timing has its own FIFO queue. Once a measurement is queued, new builds and gates
pause. Existing jobs finish normally; the oldest measurement holds admission
while draining every existing build/gate slot, including higher-numbered slots
created by another worktree. It then runs alone among cooperating jobs. Pending
measurements run serially before ordinary admissions resume. A cancelled waiter,
failed command, or killed measurement releases its locks. A continuous stream of
timing requests can delay ordinary work, so keep measurement windows bounded.
Queueing and drain time are outside a benchmark's own measured intervals.

Prepare benchmark binaries under `build`, then request `timing` for execution.
For a compiler-speed experiment, the compilation being measured belongs inside
`timing`. Do not request timing while holding a build/gate slot: it would wait
for itself. Nested shell admission fails with a diagnostic. Python developer
harnesses use `scripts/build_admission.py` to acquire and release individual
phases; they restore affinity and release admission when a phase raises.

Waiting jobs receive monotonically numbered **FIFO tickets**, separately for
`build` and `gate`. Only the oldest live ticket of a kind may claim a slot of
that kind. A newer arrival cannot overtake it by polling faster. Waiting output
includes the ticket number and current position; `status` lists queued PIDs and
their wait times. Multiple slots still admit multiple jobs, and a queued gate
does not block the independent build queue.

**A waiter is woken by the lock it waits for.** When every slot is busy, or the
admission lock is held (a settle window, a measurement), the oldest waiter blocks on
that lock for at most `SELKA_SLOT_POLL` seconds, so it starts the moment the lock is
released, not at the next poll (with several slots, any of the others may free first:
that is noticed within a second). A waiter behind another looks at the queue front
every `SELKA_SLOT_POLL` seconds without a lock or a process, and properly (the look
that reaps a killed waiter's ticket) at least once a second. A waiter short of memory
retries once a second, or every poll if that is longer, because each retry starts
processes and this is the wait that lasts. The poll was 5 s until 13 November 2026, and
a job that had just been released waited out the rest of it.

**The settle window ends with the job.** An admitted job holds the admission lock
for `SELKA_SLOT_SETTLE` seconds so the next job's memory check sees its footprint.
A job that has exited has no footprint, so the window now ends as soon as the last
holder of the job's slot lock is gone (a detached timer waits on that lock for at
most the settle seconds). A command that finishes in a second no longer makes the
next one wait five. A job that is still running, or has left a process holding the
slot, keeps its window as before, so the memory rule is unchanged: the next job is
admitted only when `MemAvailable` is at least its threshold, and never earlier than
before.

Cancelling a waiter removes its ticket. If it is killed without cleanup, the
next admission or status check removes the stale ticket. Liveness includes the
PID, process start time and boot identity, so a reused PID or a previous boot
cannot keep a dead job at the front. The oldest job retains its position while
waiting for memory; lower-memory newcomers of the same kind cannot jump ahead.
FIFO prevents overtaking, but cannot bound the duration of a running job or
provide memory that is unavailable.

| variable | default | meaning |
|---|---|---|
| `SELKA_BUILD_SLOTS` | 3 | concurrent `build` jobs |
| `SELKA_GATE_SLOTS` | 1 | concurrent `gate` jobs |
| `SELKA_BUILD_MEM` | `4G` | `MemAvailable` needed to start a build |
| `SELKA_GATE_MEM` | `6G` | `MemAvailable` needed to start a gate |
| `SELKA_TIMING_MEM` | `4G` | `MemAvailable` needed to start measurement after draining |
| `SELKA_TIMING_CPUS` | empty | optional CPUs excluded from ordinary jobs |
| `SELKA_SLOT_SETTLE` | 5 | at most this many seconds before the next job is admitted, so this job's memory counts; the window ends when the job has exited |
| `SELKA_SLOT_POLL` | 0.25 | seconds a waiter waits (blocked on a lock, or asleep) between looks; a decimal, `> 0`; a memory shortage retries at most once a second |
| `SELKA_SLOT_DIR` | `$XDG_RUNTIME_DIR/selka-slots`, else `~/.cache/selka/slots` | shared slot locks and FIFO tickets |

The thresholds come from peaks measured on this machine with `/usr/bin/time -v`,
and from the peak anonymous memory of the job's cgroup. All builds used Zig's
default `-j`, except the ReleaseFast one, which used `-j2`. They were measured
on 2026-09-23, before the S5 switch to the compiler's core. The report is
[`docs/audits/devloop-tooling-2026-09-23.md`](../audits/devloop-tooling-2026-09-23.md).

| job | wall | peak anon | cgroup `memory.peak` |
|---|---:|---:|---:|
| Debug `zig build` after a `src/` change | 11 s | 0.8 GB | 1.2 GB |
| ReleaseFast `-Dcompiler-only=true -j2`, clean cache | 277 s | 3.0 GB | 3.0 GB |
| `zig build test`, clean cache | 217 s | 2.1 GB | 3.9 GB |

The thresholds are those peaks rounded up with 1 to 2 GB to spare: 4 GB for a
build and 6 GB for a gate. In the worst case, three ReleaseFast builds and one
gate peak at about 13 GB together. A 30 GB machine has room for that next to the
agents and editors themselves. The wrapper does not cap memory. For a hard cap,
put a cgroup inside it:

```bash
scripts/build-slot.sh gate systemd-run --user --scope -p MemoryMax=16G -p MemoryHigh=14G zig build test
```

The lock files have the same names as the coordinator's earlier
`.tmp/perf-plan-20260922/slot.sh` (`build1.lock` … `gate1.lock`). Point
`SELKA_SLOT_DIR` at that script's `slots/` directory and both share one set of
slots while some agents still use the old script.

FIFO ordering applies to callers using the updated wrapper and the same slot
directory. Old wrapper versions and direct `flock buildN.lock` / `gateN.lock`
reservations still respect mutual exclusion, but bypass the ticket queues.
The wrapper of 13 November 2026 (lock-woken waiters, a settle window that ends
with its job, a trim that decides on recorded sizes) keeps every file format an older one reads: the
ticket (`pid start boot enqueued`), the owner record (`pid start boot worktree`),
`admit.lock` and `KINDn.lock`. Old and new wrappers compete for one slot
directory in either order and through a timing request (`experiments/dev-loop-audit-20261112/DL1.md`),
so a worktree on the old scripts needs to do nothing; it only keeps its old 5 s
poll and its fixed 5 s window.
Do not use raw slot reservations to jump ahead. Worktrees on older revisions
can invoke the updated wrapper by absolute path without changing their source
tree. Already running wrappers retain the admission policy they started with.
Benchmark harnesses that reserve these slot files directly also need to enter
through this queue before system-wide FIFO ordering can be claimed.

Timing keeps `admit.lock` for the entire measurement, so old wrappers using that
lock also pause. Old benchmark scripts and raw slot holders do not participate in
timing admission: update them or wrap their measurement command with `timing`.
All participants must use the same `SELKA_SLOT_DIR`; private directories isolate
tests, not production measurements.

Run the admission regression tests without a compiler build:

```bash
python3 -B scripts/build_slot_test.py -v
```

They use real processes and private lock directories under `.tmp/`, so they do
not occupy or alter the machine's live slots.

## Reuse verification evidence before admission

For an agent, this is the gate, and the only one it needs to run:

```
source ~/.config/selka/dev-env.sh
python3 scripts/verify_cache.py --zig "$ZIG" --profile complete
```

Do not also run `zig build test`: the coordinator forces the actions it selects
and does not reuse a plain gate's step verdicts, so the plain gate only adds a
duplicate run. Its output is bounded for an agent's context: green prints at
most 30 lines (verdict, elapsed, reused and executed actions, the slowest three
actions, the log path), red prints 60 lines plus 10 per further failure with the
failing action, test names, `file:line` and any `test deadline:` line. A red
summary always names something: a failed step and its first lines (a driver's
own output when no line of it looks like an error, such as `formatting differs`),
else the steps the build's tree marks failed, the supervisor's leftover report,
an expired deadline, inputs that changed, the coordinator's error, or the log's
last lines. A step is failed when the tree marks it so (`failure`, a failed test
count) or its `--fail-fast` beacon says so, never because its block ends in a
`failed command:` line, which the build runner prints for a green step that wrote
to standard error too. A preparation build that fails (a compile error) is named
from its own log before the coordinator's one-line error. Full
output is under `.selka-cache/verification-v3/last-logs/`; `--verbose` streams
it, and `scripts/gate_summary.py LOG` prints the summary for a saved log: a file,
or the directory of a gate's logs. A green gate's verdict (`Build Summary`) is in
`stderr.log`, so pointing it at a gate step's `stdout.log` or `stderr.log` reads
both files of that step; the other log files of the directory stay unread.

The cheap checks run first. `scripts/gate_cheap_checks.py` runs the commands of
the gate actions that need no test: `zig fmt --check` over the paths `build.zig`
formats, the three commands of `test-inputs-coverage`,
the `.selka` format check and `selka doc-coverage .`, and the inventory's list of
unregistered actions (`test-verification-registry` fails on any). The coordinator
starts them once the inventory and the source watches are in place, beside the
preparation build; the two that need the compiler start at once when the prepared
artifacts are reused, else when preparation ends, beside the cache lookup. A
finding ends the gate there, before the gate build and any test action: the
preparation build still running is ended, nothing is recorded, the summary names
each action and its `file:line`, `last-run.json` has `stage: cheap_checks` and
`cheap_checks` (each check's seconds and findings), and `last-logs/cheap/` holds
the findings for `gate_summary.py`. A check that passes decides nothing; the gate
still runs its own action, so a gate that passed before passes and one that
failed fails. A finding for an action reused from a prior success leaves that
success standing, with a warning that an input may be undeclared. The `quick`
profile and `--dry-run` run no cheap check. Each check has 120 s from its start;
one still running then is abandoned with one line and decides nothing. A run that
reuses the inventory or the prepared artifacts empties those builds' old logs, so
`gate_summary.py` on `last-logs` reads only this run. `python3 scripts/edit_check.py`
runs the same checks beside its build, which also builds
`test-verification-registry`; it prints a finding when it arrives, still builds and
runs the selected tests, and ends failed with the findings repeated (only the gate
stops before any test). Measured times are in
`experiments/dev-loop-audit-20261112/DL4a.md`.

Inputs that change before any gate command was sent (while the inventory or the
artifacts are prepared, during the cheap checks or the cache lookup, while the gate
waits in the queue, or with everything reused) no longer fail the request: the coordinator prints the changed path,
takes a new snapshot and starts the request again, at most twice. Nothing of the
abandoned attempt is used; each attempt takes its own snapshots, keys, cheap checks
and admission, and reuses only content-keyed records (inventory, preparation and
digest records, receipts) that it checks against its own snapshot. A third change
fails with all three paths. A change after the gate command started fails as
before, naming the path, and so does a change to the coordinator's own loaded code
or its interpreter (a restart in the same process would keep the old code). A
changed tool on `PATH` restarts like any input (decision D4, confirmed by the user;
`RESTART_ON_TOOL_CHANGE` in `verify_cache.py` reverses it). A restarted gate takes
a new place at the back of the queue. The verdict line says `restarted N time(s):
PATH changed`.

Immediately before the first admission a request really needs (a fully reused
request needs none) the coordinator reads `/proc/pressure/io`; while the disk's
`full avg60` is above 25% (root's nightly backup held it near 60% for hours on 13
November, and every gate that overlapped failed) it waits, with one line when the
wait starts and one when it ends, for at most 20 minutes, and then starts anyway
saying so. It waits before taking the shared per-action locks. Without pressure accounting it waits for nothing; `--no-disk-wait`
turns it off, and a timing window or `--dry-run` never waits. The 90-minute gate
deadline counts from the gate command's start, so the wait cannot eat it. The
verdict line says `waited N s for the disk`; `last-run.json` has `disk_wait`.

After the verdict of a gate that failed on named tests (telemetry rows or guest
tests; not a cheap finding, an incomplete action, changed inputs, a deadline, or a
failure that names no test), with every lock, lease and watch released, the
coordinator starts `scripts/edit_check_shadow.py --failed ...` detached (a session
of its own, no pipes), prints `recording whether the edit check would have
selected the failing test`, and exits at once with its own status. The shadow
appends to the edit check's store (`shadow.jsonl`) whether the selection held those
tests; it ends the impact tool's whole process group after 180 s, and a run that
cannot decide (no map, no impact tool, a timeout, a list of more than 50 names cut
short) records why, with `covered` undecided.

A test that fails in a gate and then passes alone no longer fails it (decision D5,
the user's), when the coordinator can prove the gate eligible (D-DL4-19): the build
exited 1 and printed its Build Summary, whose failed count equals the members its
tree marks failed; each failed member reported every test it ran and has failed
tests of its own (a `tests/lang`-style suite: exactly one `selka test` report);
there is no crash, timeout or leak count, no deadline line, no failed build step,
no leftover process and no guard error; and at most five tests failed. Each is then
rerun once, alone, under a gate admission after the per-action locks are released
(30 minutes for the phase): the same command for that one test, with the same binary
and environment, a guest file forced in a private cache, bounded by the native idle
bound (300 s), the test's deadline or 600 s. A rerun passes only if its runner says
that one test ran and passed; a skip or a cached answer does not. If all pass alone
the gate passes, its verdict line says `N flaky test(s) passed when rerun alone`, the
summary names each, and, once the verdict stands, each goes into
`~/.cache/selka/flaky-tests/flaky.jsonl` (load, disk pressure, free swap, F22
signature); `python3 scripts/verification_rerun.py --log` groups it by test. Such a
gate records no receipt. If any fails again the gate fails as before and says which.
Not eligible, so failing as before: a crash (the F22 fault included), a timeout, a
killed child or build runner, a member that did not report, a failure that names no
test, more than five failing tests. `--fail-fast` runs past up to five named-test
beacons so the rerun can decide. `--no-flaky-rerun` asks for the strict verdict;
`FLAKY_RERUN` in `verify_cache.py` turns the rule off. The risk: a change that makes
a test fail one time in two can land. Before trusting a gate with flaky tests, read
the log: a test never flaky before, or one that reads files this head changes, is
more likely the change than the machine. A step over its declared memory bound fails
no step (the build counts it as succeeded); the summary names it in one note line.

The supervisor of an admitted build gives a process it has sent SIGKILL up to 60 s
to die (a process in disk wait cannot act on the signal until its I/O ends) before
it reports it as having "survived being killed"; one alive at the action's normal
end still makes a green action incomplete (125), as before.

A hang now fails inside its deadline instead of holding the gate. A native test
that exceeds `SELKA_TEST_DEADLINE_SECONDS` (default 300 s) is killed with its
whole process group, named in one `test deadline:` line, recorded `timed_out`
and fails the step. A build step that exceeds `SELKA_STEP_DEADLINE_SECONDS`
(default 30 min) is killed the same way. The coordinator defaults to a 90-minute
gate and a 20-minute preparation command, queue time excluded. `0` turns any of
them off, and both variables are placement-only, so changing one never
invalidates a receipt. See [runtime budgets](runtime-budgets.md#deadlines).

`--fail-fast` ends a failing gate at its first failure instead of after the last
action. The pinned build runner prints a failure only when every step is over, so
a failing gate used to cost its full run (LT's first gate of 8 November failed on
one `lazy_readers` test and still took 11 minutes). With the option, the first
failed test of a native step, or the first failing driver (`quiet-driver.sh`),
leaves a beacon `fail-fast.*.txt` in the gate's telemetry directory the moment it
fails; the coordinator, polling every 0.2 s, ends the build's process group like a
timeout, adds the beacon's failure block to `last-logs/gate/stderr.log` after a
`Build Summary: ended by --fail-fast` line, and prints the bounded red summary as
it always does, plus a line saying the build was stopped. Nothing is recorded as a
success: the gate publishes receipts only when the whole build passed, so an
ended build leaves none, and the actions that had finished run again next time. A
passing run is the same as without the option, and the next request reuses its
receipts as usual. What starts no beacon (the `bounded`
Python steps of `build.zig` that bypass `quiet-driver.sh`, a build that fails
before any step runs) still fails the run at the end as before, except what the
cheap checks above find first. A new test that
runs `quiet-driver.sh` or the native proxy on a command that is meant to fail must
remove `SELKA_VERIFICATION_TELEMETRY_DIR` from that command's environment, or its
failure ends the real gate. `last-run.json` has `fail_fast` (`requested`,
`stopped`, `beacons`).

A new `src/*.zig` file is a failure the edit check finds in seconds and the gate
finds late: `src/lazy_readers_test.zig` reads the `src/` tree and fails for a file
that reads the merged syntax tables without an entry in `src/lazy_readers.zig`.
`python3 scripts/edit_check.py` selects it for any new `src/` file ("walks src")
and failed it in 21 s on 9 November, so run the edit check after adding a file, not
only the gate.

`python3 scripts/verify_cache.py --zig /path/to/pinned/zig` owns admission for
the complete `test` plus `fmt-check` inventory. Run it directly, after setting
the worktree's `TMPDIR` and Zig cache directories as usual. Optional build
controls follow `--`, for example `-- -j3 --maxrss 8589934592`. Do not put a
second `build-slot.sh` around this command.
The coordinator fixes Zig's test/scheduling seed to `0`; `-- --seed=123` selects
another seed and a separate evidence identity. Native CPU features, process
limits, CPU affinity and umask also participate in that identity.

The coordinator exports the actual build graph with `verification-plan` and
prepares exact native executable identities with `verification-prepare` under
build admission when needed. Valid unchanged preparation skips that admission.
It then checks each registered action's inputs and successful receipt outside
the gate slot. Missing and freshness-required actions share one normal FIFO
gate invocation, retaining the build graph's dependency and memory scheduling.
Once the gate slot is granted and the inputs are revalidated, the coordinator
looks every missing action's key up again and reuses a success another request
published while this one queued; the gate command then names only what is still
missing, and a request whose every action was published meanwhile releases the
slot without running anything. `reuse_lookups` in `last-run.json` counts the
reuses found before the queue (`pre_queue`) and after admission
(`post_admission`). A request does not wait for work another request is still
running: an action that is unpublished when this request is admitted executes here.
New unregistered checks force execution of the original complete gate.

Optional admitted-command deadlines, advisory loop targets, bounded logs and
dependency explanations are described in [development loop measurements](development-loop.md).

The output distinguishes `reused`, `execute`, and `fresh`. The SPEC history
replay (git history), input-coverage membership checks, generated-output validation, and guest suites with execution-time effect
decisions remain fresh. Guest suites retain their compiler-managed per-test
receipts (both receipt tiers of [guest tests](guest-tests.md#reusing-unaffected-results),
so an unchanged request executes no guest test); fact/leak runs keep receipts
under their own modes. `--force` discards prior action evidence and executes the
full inventory. `--dry-run` prepares, computes every action key and reuse verdict,
writes them with the full `common` identity to
`.selka-cache/verification-v3/dry-run.json` and runs no gate; comparing two
worktrees' exports shows whether they would share evidence. Every build of the request runs against an empty compiler store and an
empty test store of its own (`--own-stores fresh`, the default; `off` leaves them to the caller's environment), a store the caller
names stays the caller's, a mismatch they log is status 5 and a build that opened the user's store instead is status 6
([the gate's own stores](development-loop.md#the-gates-own-compiler-and-test-stores)). `--integration` is the integration gate the nightly runs: the complete request against empty
compiler and test stores of its own, then one forced fact/leak run, the two-run test step and a check
that its own stores logged no mismatch, each with its own status
([integration gate](development-loop.md#integration-gate)). Filtered and explicit
`-Dtest-rerun=true` requests cannot supply ordinary full-gate receipts.

Keys include declared file membership/content, native artifacts, toolchain and
host-tool contents, loader libraries, environment, configuration and inventory.
Linux inotify watches span hashing, queueing, execution and publication. Input
changes, including changes restored to their original bytes, reject publication;
rerun the command after edits settle. Missing inputs, unknown schemas and watcher
failures cannot certify a pass. Worktrees of one repository share one Git object
store, and the Guardian cohort watched it until Guardian was turned off (GH-2,
18 November 2026); the paragraph below records how. Objects are written once and named by
content, so one added after the watch was installed (a commit, `git add` or fetch in
any worktree, or git's temporary file for it) does not reject a run, and neither does
git touching or hard-linking an object it already has. A delete, rename, content
write or mode change of an object, pack or index that was there at installation, any
change under `objects/info`, a moved `refs/heads/main` or `master`, a rewritten
`packed-refs` and a repack (which deletes the loose objects it packs) still reject it,
with `inputs changed while awaiting admitted work`; rerun once the repository settles.
Host tool overrides that lack a complete contract
force fresh actions. Fixture Git commands use isolated global/system config and
empty templates; Python user-site loading and timestamp-bytecode reads are
disabled. Shell startup hooks and exported Bash functions are removed, and PATH
contains only the absolute, existing directories covered by the tool watches.
These normalized
settings are also the settings executed by workers. Workers receive the launcher
environment projected through the [environment identity contract](environment-identity.md)
(keyed, host and placement variables only), and the key holds its host-scope
digest and no checkout path, so another agent's session variables or a different
`TMPDIR` share every receipt ([receipt identities](development-loop.md#receipt-identities-schema-3)).

Reviewed cohorts can declare their own prepared artifact dependencies. A pure
script check need not repeat because an unrelated native executable changed;
selected component checks bind their builder, component or test executable.
Unreviewed cohorts keep the complete artifact identity. Build configuration,
inventory, tools, environment and host identity still invalidate all cohorts,
and the complete artifact snapshot remains watched through publication. The
input-coverage checker stays fresh because it probes whether source-named paths
exist, including paths outside its explicit source list.

Evidence lives in `.selka-cache/verification-v3/`. `last-run.json` records every
required cohort, the verdict, elapsed time, and admitted build/gate seconds.
These durations include admission validation and are operational observations,
not isolated performance benchmarks. Admission events separate wait/startup,
validation after admission, worker time and the observed held interval. The held
interval starts at the admitted child's greeting, so it excludes the wrapper's
short startup after acquiring the slot. Phase timings also show source/action
snapshotting, preparation/lookup outside admission, final validation and
publication; nested phase durations must not be added as independent intervals.
Two coordinators for one checkout serialize
on a local lock before requesting shared server slots. Normal `zig build test`
and `zig build fmt-check` remain supported.

For repeated requests in one worktree, a supervisor can keep
`python3 scripts/cache_session.py` open and submit JSON Lines requests for
`verify`, `fuzz` or `perf`. The process retains bounded watched input inventories
between requests and reports new hashing, discovery and snapshot reuse work.
Requests execute sequentially, under the startup environment. Ordinary commands
do not attach automatically. See [the session protocol](cache-retention.md#warm-validation).
Native compile/link and eligible shared-test claims separately coalesce matching
work across independent compiler processes and worktrees. Waiting on those
claims requires no additional server admission.

The coordinator is developer tooling; it adds no Python dependency to compiler
installation or installed Selka commands. Run its lightweight adversarial tests
with `python3 -B scripts/verify_cache_test.py` and
`python3 -B scripts/verification_snapshot_test.py`; they are also in the gate.

## One gate per landing

A lane merges `main` into its branch and runs the complete gate on that tree; the coordinator then fast-forwards `main` to
it and gates `main`, which finds every receipt the lane's gate recorded and runs almost nothing. Receipts live in the shared
evidence store and their keys hold no checkout path, so a gate in one worktree is evidence for the same tree in another.
Measured on 9 November: lane DL3's gate of `253848a89` (17 reused, 31 executed, 510.7 s) and the gate of `main` at the same
commit (43 reused, 5 executed, 36.1 s). Do not gate `main` before the lane has, and do not rebuild a tree on `main` that
the lane already gated: merge `main` into the branch, gate, and let the coordinator fast-forward.

The five actions `main` still ran were three that read a directory of the checkout and two that never reuse (Guardian and
the SPEC history, which "run fresh every time"). The three were `verification_session` (reads `scripts/`), `doc-coverage` and
`doctest` (read `docs/`), and each missed because that checkout held an input the lane's did not:

- **File modes.** Every input file is keyed by its sha256, size, **mode, uid and gid**. Git records only the executable bit,
  so a checkout made under `umask 077` holds `0600` files and one made under `umask 002` holds `0664` ones, and the same
  tree has two keys. `main` held 226 tracked files at `0600` (the older `docs/audits/`, `examples/`, `experiments/`,
  `scripts/migrate_*.py` and `selfhost/` files) against none in a lane worktree. Check a tree with
  `git ls-files -z | xargs -0 stat -c %a | sort | uniq -c`; a healthy checkout shows only `664` and `775`.
- **Untracked files.** An untracked file inside an input directory is an input. `main` held an untracked
  `docs/audits/language-surface-audit-2026-10-19.md`, which no lane's `docs/` has, and so changed `doc-coverage` and `doctest`.

Two worktrees share evidence when `python3 scripts/verify_cache.py --dry-run` gives them the same action keys: compare
`.selka-cache/verification-v3/dry-run.json` of the two (`actions[].action_key`, and `.selka-cache/verification-v3/
diagnostics/ACTION.json` names the file whose identity differs).

## What the complete verification contains

The complete verification is the `test` plus `fmt-check` inventory, grouped by
what a group protects. `zig-out/verification/inventory.json` (from
`zig build verification-plan`) lists every registered action;
`coverage.unknown_actions` is empty when the inventory is complete, and
`test-verification-registry` fails while it is not.

The complete verification runs the four Lean proof actions (`ownership-proof`, `verify-ir-proof`, `arith-proof`,
`cache-proof`), which a plain `zig build test` skips unless it is given `-Dproofs=true` (they need `lake`). The coordinator
adds `-Dproofs=true` to every `zig build` it runs, drops any other `-Dproofs=` value, and refuses an inventory whose
`configuration.proofs` is not true; `verification_profiles.coverage` also never completes the gate for such a plan. So a
receipt for a proof action always means the proof ran, and a machine without Lean cannot pass the complete gate (the
proof actions fail, naming `lake`).

- **Compiler and runtime:** `core`, `unit`, `cli`, `golden`, `language`,
  `guest`, `doctest`, `doc-coverage`, `incremental`, `interfaces` and the small
  compiler-facing groups. A change under `src/` reruns these.
- **Standalone programs:** `program_check` (step `test-program-check`) runs
  `selka check` over every `.selka` file under `bench/`, `benchmarks/`,
  `examples/`, `src/stdlib` and `selfhost/components` in about six seconds.
  No other group builds those trees. There is no exclusion list: a program
  that stops checking fails the gate, so repair it or move it out of those
  roots.
- **The goals register:** `goals_register` (step `test-goals`) runs `tests/goals_register.py`, which reads `docs/goals.md`
  and the pinned examples under `test/fixtures/goals` and fails when a path, Lean theorem or gate action the page names does
  not exist, an example id or an exception count disagrees with its page, or a pinned example fails (it runs
  `selka doctest` on the pins). Its inputs are the page, the pins and the kinds of file the page names, so an edit to any
  of them reruns it; it takes about half a second warm. The edit check does not select it (no Zig test reads the page), so
  run `zig build test-goals` after editing `docs/goals.md` or a pin. The format is the section "How this page is checked"
  of `docs/goals.md`.
- **Build modes agree:** `mode_differential` (step `test-mode-differential`) runs `tests/mode_differential.py`, which
  writes small valid programs from fixed seeds (its own pseudo-random generator, so a seed is the same program on every
  machine), builds each with the plain build, `--release` and `selka test`, one in four also with `--debug-o0`,
  `--unoptimized` and `selka test --unoptimized`, and fails when the modes disagree on a function's printed value, trap
  or test verdict, or when a mode stops with an internal compiler error or a panic. It is the one place `--release`
  builds run in the default gate. Its input is the driver alone, so it reruns when the compiler or the driver changes.
  Every build uses private stores (the C runtime objects in `.selka-cache/mode-differential/runtime`, kept between runs);
  a failing program is kept under `.selka-cache/mode-differential/kept` and the failure prints its seed, its path and
  one line per mode.
- **Tooling self-tests:** the verification coordinator, cache, Juice and fuzz
  groups, and `migrate_embedded` (step `test-migrate-embedded`), which tests
  the embedded-source migrator that `selka fix` migrations reuse.

On 18 October 2026 four groups were retired because a profile found them at 72%
of the gate's CPU and, in the case of the removed-form audit, on its whole
critical path (about 3,360 s in one single-threaded Python process): the
removed-form audit (`removed_forms_audit`), the ownership corpora A, B and C
(`ownership_corpus`), the cleanup rewriter tests (`cleanup_tooling`) and the
ownership-audit helper tests (`embedded_migration`). They re-verified a finished
migration and mostly their own tooling. What they guarded is enforced
elsewhere: the compiler's own `E_*_REMOVED`, `E_REMOVED_SPELLING` and
`E_HOST_RETIRED` rejections have unit tests, `selka fix` has its
`test/fixtures/fix-migration` corpora, and `language`, `doctest`, `cli` and
`golden` compile the live sources. The scripts, the pin table
`tests/removed_forms_allowlist.json` and the `-Daudit-jobs` build option are
gone; `git log --diff-filter=D -- scripts/audit_removed_forms.py` finds the
commit that has them. A new driver that walks the whole repository should
justify its cost against the six seconds of `program_check`. The measured
before and after are in
`experiments/project-ladder-20261018/gate-retirement.md`.

## Timing windows and CPU placement

On the i7-12700H, CPUs 0–11 are six P-cores with two SMT threads each, and the
threads of one core are adjacent (2/3, 10/11). CPUs 12–19 are E-cores. Check with
`lscpu -e`: rows with the same `CORE` are siblings. Explicitly setting
`SELKA_TIMING_CPUS=2,3,10,11` retains the old two-P-core reservation, if needed
while migrating an older benchmark. The normal default reserves no CPUs.

Run these harnesses directly; they own admission:

- `bench/parity/bench_parity.py` (`zig build bench-parity`) admits parallel arm
  builds and correctness qualification as ordinary work, then requests timing
  for measurements and any confirmation pass. It pins measurements to CPU 2 by
  default, or `--cpu`/`-Dbench-cpu` (first of `SELKA_TIMING_CPUS` when set).
- `scripts/juice_runtime_bench.py` requests timing for its prebuilt-pair suite
  and retains the legacy collector lock to detect older concurrent timers.
- `scripts/benchmark_debug_runtime.py` requests timing for its experiment,
  because it measures compilation as well as guest execution.

Other benchmark commands, including historical experiment scripts, need an
explicit `scripts/build-slot.sh timing …` wrapper. Do not run simultaneous
timers on different cores: caches, memory bandwidth and package power are shared.
Parity still samples the timing core and its sibling before timing and records
`sibling_busy`; those checks can catch unrelated load outside admission.

This is cooperative scheduling, not OS-wide isolation. Agent shells, editors,
language servers, kernel work and commands bypassing admission can still affect
measurements. CPU pinning alone does not remove that interference. Preserve raw
samples and report variability; use a dedicated machine for stronger isolation.

## How many agents

Three build slots and one gate slot allow four concurrent heavy jobs outside
timing windows. Each may already use multiple CPUs; one gate is not one core.
More agents can read and edit while their heavy work queues. Keep these slot
counts until current-workload throughput and peak memory justify changing them;
the measurements above predate the current backend. Admission checks available
memory at startup, not a reservation of every job's future peak. Reuse verification
evidence and limit per-job parallelism before simply adding more full gates.

## Per-worktree environment

Developer verification, fuzz and Juice coordinators can share exact evidence
through `--shared-cache-dir DIR`, separate from their private worktree caches.
Use a dedicated directory outside checkouts. The shared store has process leases,
retention pins and an explicit collector; see [cache retention](cache-retention.md).
The verification coordinator also reads `SELKA_VERIFICATION_SHARED_CACHE` and has
a per-user default enabled after R4 default-store qualification
([default store](cache-retention.md#the-verification-coordinators-default-store)).
An explicitly empty flag or variable disables sharing.
Its action keys hold no checkout path and ignore per-worktree placement such as
`ZIG_LOCAL_CACHE_DIR` and `TMPDIR`; actions that depend on a native executable
still identified by its bytes (whose debug information names the checkout) stay
distinct across worktrees, and `last-run.json` marks them `path_free: false`.

On the shared development machine, `source ~/.config/selka/dev-env.sh` in the
worktree sets all of this: the pinned Zig, the worktree's own
`ZIG_LOCAL_CACHE_DIR` (`<worktree>/.zig-cache`) and `TMPDIR`
(`<worktree>/.tmp/work`), and `SELKA_SLOT_DIR=~/.cache/selka/slots`, the one
admission directory every agent shares. Elsewhere, set the two directories
yourself:

```bash
export ZIG_LOCAL_CACHE_DIR=$HOME/.cache/selka/zig-local-cache-<lane>
export TMPDIR=$HOME/.cache/selka-tmp/<lane>
mkdir -p "$TMPDIR"
```

- **One `ZIG_LOCAL_CACHE_DIR` per worktree.** The configure phase records the
  build root's real path (`build_identity.zig`), so two trees sharing one cache
  once embedded the wrong runtime.
- **Admission bounds an active worktree's own cache.** A build or gate request
  compares the worktree's `.zig-cache` with `SELKA_ZIG_CACHE_CAP_GB` (default
  30 GiB, `0` off) and its regenerable `.selka-cache/core` tiers with
  `SELKA_CACHE_TIERS_CAP_GB` (default 10 GiB, `0` off). When over, and no other
  admitted job of the same worktree is active (a `--watch` holding a slot
  counts), the directory is renamed aside, the job starts cold, and the old
  cache is deleted in the background; one line names the worktree and size.
  A running `verify_cache.py` coordinator holds no slot while it waits for
  admitted work, but it watches the prepared artifacts in `.zig-cache` from
  `prepare` to the end of its request, and a rename of that directory fails the
  run with `inputs changed while awaiting admitted work` (F48). So while it
  holds `.selka-cache/verification-v3/coordinator.lock`, no admission of the
  worktree, the coordinator's own gate admission included, trims `.zig-cache`
  (the tiers and test caches it does not watch are bounded as before), and the
  coordinator applies the `.zig-cache` cap itself, once, before it takes its
  first snapshot: it reads the sizes record, and only when over the cap takes
  the admission lock and renames. If that lock stays busy for 15 s it warns and
  leaves the cap to the next admission. `--dry-run` and
  `--timing-window-seconds` requests apply none.
  An admission decides on **recorded sizes** and walks nothing: `prune-caches.sizes`
  (and `.selka-cache/test-cache-sizes.tsv` for the test suites) hold what the last
  measurement found. The measurement, a `du` of each cache and a scan for
  deletions an earlier trim left half done (millions of entries on a busy
  worktree), runs in a detached background process, at most once in ten minutes
  per worktree (`.selka-cache/trim-measured` in the worktree is the stamp), outside the
  admission lock; it renames nothing, so a cache is never moved under a running
  job. A worktree nobody has measured yet is trimmed by the admission after the
  measurement. A record that says "over the cap" for a cache that has changed
  since is confirmed with a bounded (2 s) `du` before the cache is renamed, so a
  cache emptied by hand is not condemned on an old figure; a `du` that times out
  leaves the cache alone, and one that finds it under the cap is written back so no
  later admission repeats it. A measurement merges its figures into the shared
  record as it is when the walk ends, so it never restores a row another
  worktree's trim removed. Another worktree's cache is never touched. The whole `.selka-cache` is never
  removed, because it can hold protected evidence. The deletion runs in a
  background session of its own, so it is never part of the job it serves; an
  admission inside a supervised job of the same worktree (a test that starts
  one with a private slot directory; the supervisor exports the directory as
  `SELKA_ADMISSION_SUPERVISED`) trims nothing, since the supervisor would
  count the deletion as a leftover, end the action 125 and kill it half done.
  An admission inside a supervised action of any other worktree (a fixture)
  starts no background process at all, neither a measurement nor a deletion;
  a worktree that only runs gates is measured by its gate's own admission and by
  the coordinator, which run outside any action.
  A deletion cut off anyway (a restart) is finished by the next background
  measurement, which deletes any `.trim-N` directory untouched for 15 minutes.
- **Admission bounds the test suites' caches too.** The suites' work
  directories (`.selka-cache/unit-tests`, `core-tests`, `guest-tests`,
  `lang-tests`, `ported-tests`, `value-semantics-tests`, and the `-release`
  and `-unoptimized` copies of each) are bounded together by
  `SELKA_TEST_CACHES_CAP_GB` (default 8 GiB, `0` off). A work directory is one
  that holds the compiler's `.retention.lock`: the whole directory of a
  language suite, one per core test, one per unit-test program. The outermost
  directory that holds a lease is the unit, so a cache made of several leased
  parts takes a lease of its own to be removed whole: a variant of the runtime
  seed (`.selka-cache/core-tests/runtime_seed/<variant>`, an object `store`
  and a `work` directory) does, and `runtime_seed.zig` touches that lease on
  every use. The compiler
  bounds the tiers inside each one, but a worktree holds over a thousand of
  them. When their total is over the bound, admission removes whole work
  directories, least recently used first (the newest modification time of the
  directory and its entries), until it is under; it takes each one's lease
  exclusively first and skips any that a running build or test holds, and it
  prints one line. The sizes come from `.selka-cache/test-cache-sizes.tsv`,
  which a background measurement rewrites at most every ten minutes, so an
  admission never walks the caches. A removed directory costs its next run a
  colder build, never an error.
- **Test steps see a projected environment.** Every command `zig build` wraps
  (test roots, shards, Python and guest drivers) runs through `build-env
  project`, which passes only the keyed, host and placement variables of
  `src/environment_identity.zon`; session variables such as `CODEX_THREAD_ID`,
  `TERM` or `PWD` never reach a test and never invalidate a cached verdict.
  A test that needs a new variable must have it classified first
  ([environment identity](environment-identity.md#in-the-build-graph)).
- **`TMPDIR` on disk, not the `/tmp` tmpfs.** `/tmp` has a per-user quota. When
  other sessions filled it, every command that writes scratch under `TMPDIR`
  failed with `DiskQuota`.
- **Measure guest programs with the Debug compiler** (`CLAUDE.md`, "Measuring
  guest programs"). A Debug and a ReleaseFast compiler emit identical binaries,
  so a lane that only times programs never needs a ReleaseFast build.
  `python3 bench/parity/bench_parity.py same-binaries --other PATH/bin/selka`
  checks that claim for every parity program.
