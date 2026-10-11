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
steps, `fmt-check` and `mylang test <dir>`. `gate` covers the full gate,
`zig build test`. `timing` covers runtime and compiler-speed measurements.
The wrapper runs a job only when a slot of its kind is free **and**
`MemAvailable` is at least that kind's threshold. Otherwise it waits and says
why. When it finally runs the job it prints how long it waited, and it passes the
job's exit status through unchanged.

Ordinary jobs use all CPUs allowed to the caller (20 logical CPUs on this host).
An explicitly set `MYLANG_TIMING_CPUS` still excludes those CPUs from builds and
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

Cancelling a waiter removes its ticket. If it is killed without cleanup, the
next admission or status check removes the stale ticket. Liveness includes the
PID, process start time and boot identity, so a reused PID or a previous boot
cannot keep a dead job at the front. The oldest job retains its position while
waiting for memory; lower-memory newcomers of the same kind cannot jump ahead.
FIFO prevents overtaking, but cannot bound the duration of a running job or
provide memory that is unavailable.

| variable | default | meaning |
|---|---|---|
| `MYLANG_BUILD_SLOTS` | 3 | concurrent `build` jobs |
| `MYLANG_GATE_SLOTS` | 1 | concurrent `gate` jobs |
| `MYLANG_BUILD_MEM` | `4G` | `MemAvailable` needed to start a build |
| `MYLANG_GATE_MEM` | `6G` | `MemAvailable` needed to start a gate |
| `MYLANG_TIMING_MEM` | `4G` | `MemAvailable` needed to start measurement after draining |
| `MYLANG_TIMING_CPUS` | empty | optional CPUs excluded from ordinary jobs |
| `MYLANG_SLOT_SETTLE` | 5 | seconds before the next job is admitted, so this job's memory counts |
| `MYLANG_SLOT_POLL` | 5 | seconds between admission attempts |
| `MYLANG_SLOT_DIR` | `$XDG_RUNTIME_DIR/mylang-slots`, else `~/.cache/mylang/slots` | shared slot locks and FIFO tickets |

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
`MYLANG_SLOT_DIR` at that script's `slots/` directory and both share one set of
slots while some agents still use the old script.

FIFO ordering applies to callers using the updated wrapper and the same slot
directory. Old wrapper versions and direct `flock buildN.lock` / `gateN.lock`
reservations still respect mutual exclusion, but bypass the ticket queues.
Do not use raw slot reservations to jump ahead. Worktrees on older revisions
can invoke the updated wrapper by absolute path without changing their source
tree. Already running wrappers retain the admission policy they started with.
Benchmark harnesses that reserve these slot files directly also need to enter
through this queue before system-wide FIFO ordering can be claimed.

Timing keeps `admit.lock` for the entire measurement, so old wrappers using that
lock also pause. Old benchmark scripts and raw slot holders do not participate in
timing admission: update them or wrap their measurement command with `timing`.
All participants must use the same `MYLANG_SLOT_DIR`; private directories isolate
tests, not production measurements.

Run the admission regression tests without a compiler build:

```bash
python3 -B scripts/build_slot_test.py -v
```

They use real processes and private lock directories under `.tmp/`, so they do
not occupy or alter the machine's live slots.

## Reuse verification evidence before admission

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
New unregistered checks force execution of the original complete gate.

Optional admitted-command deadlines, advisory loop targets, bounded logs and
dependency explanations are described in [development loop measurements](development-loop.md).

The output distinguishes `reused`, `execute`, and `fresh`. Guardian, git-history
checks, input-coverage membership checks, generated-output validation, and guest suites with execution-time effect
decisions remain fresh. Guest suites retain their compiler-managed per-test
receipts; fact/leak runs preserve their existing modes. `--force` discards prior
action evidence and executes the full inventory. Filtered and explicit
`-Dtest-rerun=true` requests cannot supply ordinary full-gate receipts.

Keys include declared file membership/content, native artifacts, toolchain and
host-tool contents, loader libraries, environment, configuration and inventory.
Linux inotify watches span hashing, queueing, execution and publication. Input
changes, including changes restored to their original bytes, reject publication;
rerun the command after edits settle. Missing inputs, unknown schemas and watcher
failures cannot certify a pass. Host tool overrides that lack a complete contract
force fresh actions. Fixture Git commands use isolated global/system config and
empty templates; Python user-site loading and timestamp-bytecode reads are
disabled. Shell startup hooks and exported Bash functions are removed, and PATH
contains only the absolute, existing directories covered by the tool watches.
These normalized
settings are also the settings executed by workers.

Reviewed cohorts can declare their own prepared artifact dependencies. A pure
script check need not repeat because an unrelated native executable changed;
selected component checks bind their builder, component or test executable.
Unreviewed cohorts keep the complete artifact identity. Build configuration,
inventory, tools, environment and host identity still invalidate all cohorts,
and the complete artifact snapshot remains watched through publication. The
input-coverage checker stays fresh because it probes whether source-named paths
exist, including paths outside its explicit source list.

Evidence lives in `.mylang-cache/verification-v1/`. `last-run.json` records every
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

## Timing windows and CPU placement

On the i7-12700H, CPUs 0–11 are six P-cores with two SMT threads each, and the
threads of one core are adjacent (2/3, 10/11). CPUs 12–19 are E-cores. Check with
`lscpu -e`: rows with the same `CORE` are siblings. Explicitly setting
`MYLANG_TIMING_CPUS=2,3,10,11` retains the old two-P-core reservation, if needed
while migrating an older benchmark. The normal default reserves no CPUs.

Run these harnesses directly; they own admission:

- `bench/parity/bench_parity.py` (`zig build bench-parity`) admits parallel arm
  builds and correctness qualification as ordinary work, then requests timing
  for measurements and any confirmation pass. It pins measurements to CPU 2 by
  default, or `--cpu`/`-Dbench-cpu` (first of `MYLANG_TIMING_CPUS` when set).
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
Path-sensitive action identities remain distinct across worktrees.

```bash
export ZIG_LOCAL_CACHE_DIR=$HOME/.cache/mylang/zig-local-cache-<lane>
export TMPDIR=$HOME/.cache/mylang-tmp/<lane>
mkdir -p "$TMPDIR"
```

- **One `ZIG_LOCAL_CACHE_DIR` per worktree.** Zig's configure cache ignores the
  build root, so two trees sharing one cache once embedded the wrong runtime.
- **`TMPDIR` on disk, not the `/tmp` tmpfs.** `/tmp` has a per-user quota. When
  other sessions filled it, every command that writes scratch under `TMPDIR`
  failed with `DiskQuota`.
- **Measure guest programs with the Debug compiler** (`CLAUDE.md`, "Measuring
  guest programs"). A Debug and a ReleaseFast compiler emit identical binaries,
  so a lane that only times programs never needs a ReleaseFast build.
  `python3 bench/parity/bench_parity.py same-binaries --other PATH/bin/mylang`
  checks that claim for every parity program.
