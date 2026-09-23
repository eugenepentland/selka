# Many agents on one machine

The development box (i7-12700H: 20 hardware threads, 30 GB of RAM) often runs
several agents at once, each with its own worktree. Three things keep them from
slowing each other down:

- a cap on concurrent builds and gates that also checks free memory;
- a few CPUs reserved for timing, so benchmarks stay accurate;
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
scripts/build-slot.sh status            # slots, MemAvailable, CPUs builds may use
```

`build` covers any compile or install, the focused `test-units`/`test-cli`
steps, `fmt-check` and `mylang test <dir>`. `gate` covers the full gate steps:
`zig build test`, `test-qbe`, `test-qbe-build`, `test-schematic` and `test-byte-io`.
The wrapper runs a job only when a slot of its kind is free **and**
`MemAvailable` is at least that kind's threshold. Otherwise it waits and says
why. When it finally runs the job it prints how long it waited, and it passes the
job's exit status through unchanged.

| variable | default | meaning |
|---|---|---|
| `MYLANG_BUILD_SLOTS` | 3 | concurrent `build` jobs |
| `MYLANG_GATE_SLOTS` | 1 | concurrent `gate` jobs |
| `MYLANG_BUILD_MEM` | `4G` | `MemAvailable` needed to start a build |
| `MYLANG_GATE_MEM` | `6G` | `MemAvailable` needed to start a gate |
| `MYLANG_TIMING_CPUS` | `2,3,10,11` | CPUs no admitted job may use (`""` reserves none) |
| `MYLANG_SLOT_SETTLE` | 5 | seconds before the next job is admitted, so this job's memory counts |
| `MYLANG_SLOT_POLL` | 5 | seconds between admission attempts |
| `MYLANG_SLOT_DIR` | `$XDG_RUNTIME_DIR/mylang-slots`, else `~/.cache/mylang/slots` | lock files |

The thresholds come from peaks measured on this machine with `/usr/bin/time -v`,
and from the peak anonymous memory of the job's cgroup. All builds used Zig's
default `-j`, except the ReleaseFast one, which used `-j2`. The report is
[`docs/audits/devloop-tooling-2026-09-23.md`](../audits/devloop-tooling-2026-09-23.md).

| job | wall | peak anon | cgroup `memory.peak` |
|---|---:|---:|---:|
| Debug `zig build` after a `src/` change | 11 s | 0.8 GB | 1.2 GB |
| ReleaseFast `-Dcompiler-only=true -j2`, clean cache | 277 s | 3.0 GB | 3.0 GB |
| `zig build test`, clean cache | 217 s | 2.1 GB | 3.9 GB |
| `zig build test-qbe`, clean cache | 48 s | 0.7 GB | 1.1 GB |
| `test-qbe-build`, `test-schematic`, `test-byte-io` | 1–2 s each | 0.3 GB | 0.3 GB |

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

## Reserved timing cores

On the i7-12700H, CPUs 0–11 are six P-cores with two SMT threads each, and the
threads of one core are adjacent (2/3, 10/11). CPUs 12–19 are E-cores. Check with
`lscpu -e`: rows with the same `CORE` are siblings. The default
`MYLANG_TIMING_CPUS=2,3,10,11` reserves two whole P-cores. `scripts/build-slot.sh`
runs every job under `taskset` with those CPUs removed, so no gate or build it
admits lands on them.

Both benchmark harnesses use those cores by default:

- `bench/parity/bench_parity.py` (`zig build bench-parity`) and
  `experiments/perf-parity-plan-20260922/bench.py` pin timed runs to the first
  reserved CPU (CPU 2) unless `--cpu`/`-Dbench-cpu` names another.
- They build their arms with the reserved CPUs masked off.
- Before timing, each one samples the timing CPU and its SMT sibling for a second
  and warns if either is busy.
- Each records `sibling_busy` per program and warns past 25%.

Run a benchmark harness directly, not through the wrapper. The wrapper's jobs
cannot use the timing CPUs, and the harness refuses to run there. Two agents
timing at once should pick different reserved cores (`--cpu 10`).

The wrapper keeps only its own jobs off those CPUs. Agent shells, editors and
language servers can still be scheduled there. Stronger isolation needs root and
is **not applied** on this machine. The options are:

- `isolcpus=2,3,10,11 nohz_full=2,3,10,11` on the kernel command line, which takes
  the CPUs away from the scheduler except for explicit pinning;
- `systemctl set-property user.slice AllowedCPUs=0-1,4-9,12-19`, then run the
  benchmarks from a `systemd-run --scope -p AllowedCPUs=2,3,10,11` unit;
- `kernel.perf_event_paranoid=1`, already set. `bench-parity` then records
  instruction counts, which do not move with load. One run can settle most
  "did this get faster" questions without 9–11 timed rounds.

## How many agents

About four build-heavy agents fit this machine. Three build slots and one gate
slot already allow that many concurrent jobs. More lanes than that queue in the
wrapper anyway, and before the wrapper checked memory they also brought
out-of-memory kills and load-induced test failures. Agents that mostly read and
reason cost little, so they do not count toward the four.

## Per-worktree environment

```bash
export ZIG_LOCAL_CACHE_DIR=$HOME/.cache/mylang/zig-local-cache-<lane>
export TMPDIR=$HOME/.cache/mylang-tmp/<lane>
mkdir -p "$TMPDIR"
```

- **One `ZIG_LOCAL_CACHE_DIR` per worktree.** Two trees sharing one cache once
  embedded the wrong runtime. The build now refuses a configuration that belongs
  to another tree ([native builds](native-build.md#where-the-content-hash-comes-from)).
- **`TMPDIR` on disk, not the `/tmp` tmpfs.** `/tmp` has a per-user quota. When
  other sessions filled it, every command failed with `DiskQuota`, including the
  guest-test scratch that `mylang test` stages under `TMPDIR`.
- **Measure guest programs with the Debug compiler** (`CLAUDE.md`, "Measuring
  guest programs"). A Debug and a ReleaseFast compiler emit identical binaries,
  so a lane that only times programs never needs a ReleaseFast build.
  `python3 bench/parity/bench_parity.py same-binaries --other PATH/bin/mylang`
  checks that claim for every parity program.
