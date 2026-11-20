# Development-loop tooling — 2026-09-23

This report covers the quick wins from §1, §2 and part of §4 of the
[development-speed audit](development-speed-audit-2026-09-23.md). The work is
on branch `devloop/tooling`, from `base/devloop` (`e54d1bd7`). Nothing under
`src/` changed.

## What changed

| audit item | change |
|---|---|
| §1 measure with the Debug compiler | `CLAUDE.md` gains a "Measuring guest programs" section, and its ReleaseFast bullet now says a ReleaseFast compiler is for timing the compiler itself or handing one to other agents. `experiments/perf-parity-plan-20260922/bench.py` now defaults to `zig-out/bin/mylang` (it used to point at a `.tmp/` ReleaseFast install) and fails with a clear message if that file is missing. `bench_parity.py` / `zig build bench-parity` already used the checkout's compiler; `docs/performance.md` and `bench/parity/README.md` now say so. A new `bench_parity.py same-binaries --other PATH` builds every mylang arm with two compilers and requires identical bytes. |
| §2 machine-sharing wrapper | New `scripts/build-slot.sh build\|gate CMD…`. It admits a job only when a flock slot is free **and** `MemAvailable` is above the kind's threshold. Admissions are serialized and spaced 5 s apart so each check sees the previous job's memory. Jobs run under `taskset` without the reserved `MYLANG_TIMING_CPUS`. Locks live in `$XDG_RUNTIME_DIR/mylang-slots`, else `~/.cache/mylang/slots`. The workflow is in [`docs/tooling/many-agents.md`](../tooling/many-agents.md), linked from `CLAUDE.md` and `runtime-budgets.md`. |
| §2 reserved timing cores | `bench_parity.py` and `bench.py` default `--cpu` to the first of `MYLANG_TIMING_CPUS` (CPU 2). `-Dbench-cpu` is now optional in `build.zig`, so the environment decides when it is absent. Both harnesses build with the reserved CPUs masked off. Both sample the timing CPU and its SMT sibling for a second before timing and warn when either is busy. `bench.py` now records `sibling_busy` as `bench_parity.py` already did, and warns per program past 25%. |
| §4 load-sensitive test | `integration.test "guest benchmarks write a candidate and enforce an approved baseline immutably"` now reaches its verdicts by construction (below). It also asserts the verdict itself (`pass`, `ceiling`) and prints the child's stderr on an unexpected exit status. The other two benchmark CLI tests print stderr the same way. |

## Measured peaks (this machine: i7-12700H, 20 threads, 30 GB)

Each job ran in its own `systemd-run --scope` cgroup. The table gives the
cgroup's peak anonymous memory (sampled every 0.5 s), `memory.peak` (which also
counts page cache), and `/usr/bin/time -v`'s largest single process.

| job | wall | peak anon | `memory.peak` | largest process |
|---|---:|---:|---:|---:|
| Debug `zig build`, warm cache, one `src/` file changed (4 compiler executables relinked) | 11 s | 0.78 GB | 1.17 GB | 0.36 GB |
| Debug `zig build`, fresh local cache (Zig's global cache warm) | 10 s | 0.96 GB | 1.37 GB | 0.38 GB |
| ReleaseFast `-Dcompiler-only=true -j2`, fresh local cache, loaded machine | 277 s | 2.95 GB | 3.01 GB | 2.97 GB |
| `zig build test`, fresh local cache (18 shards) | 217 s | 2.12 GB | 3.87 GB | — |
| `zig build test-qbe`, fresh local cache | 48 s | 0.68 GB | 1.08 GB | — |
| `test-qbe-build` / `test-schematic` / `test-byte-io` | 1–2 s | 0.29 GB | 0.30 GB | — |

`memory.peak` is exact. Peak anon is sampled, so it can miss a short spike
across concurrent shards. The thresholds are therefore set from `memory.peak`.

**Defaults chosen.**
- `MYLANG_BUILD_MEM=4G`: the ReleaseFast compiler build is the largest build
  (3.0 GB), plus 1 GB to spare. A Debug build needs about 1.2 GB.
- `MYLANG_GATE_MEM=6G`: `zig build test` peaks at 3.9 GB, plus 2 GB for guest
  children that grow toward their 512 MiB ceilings. The audit guessed 8 GB; the
  measured peak is half that.
- Slots stay at 3 builds and 1 gate, the counts that worked last night. At the
  measured peaks the worst case is 3 × 3.0 + 3.9 ≈ 13 GB. That fits in the
  roughly 20 GB of `MemAvailable` this machine shows with its usual servers and
  agents running.
- Timing CPUs are `2,3,10,11`. `lscpu -e` shows CPUs 0–11 as six P-cores with
  adjacent SMT pairs and 12–19 as E-cores, so these are two whole P-cores.

## Debug and ReleaseFast compilers emit the same binaries

This builds every mylang arm of `bench/parity` (`suite`, `lib`, `micro`: 44
programs, checked and `--unchecked`) with the Debug `zig-out/bin/mylang` and with
the ReleaseFast `-Dcompiler-only=true` install, each compiler with its own object
cache. Result: **88 of 88 binaries byte-identical.** Building them took 146 s in
total with the Debug compiler and 132 s with the ReleaseFast one, 4 at a time, so
the Debug compiler costs about 0.2 s more per guest build. Measuring a lane's
programs this way costs that fraction of a second, where a ReleaseFast compiler
build costs 3 to 5 minutes. `bench_parity.py same-binaries --other PATH` repeats
the check. It is a manual command, not a gate step, because it needs a
ReleaseFast compiler, which costs 3.0 GB and about 3 to 5 minutes to build.

## The load-sensitive benchmark test

**It failed three times, for two different reasons.**

| gate log | failing assertion | cause |
|---|---|---|
| `perf-plan-20260922/gate/textsort-test.log` (2026-09-22 21:45) | candidate run exited 2 | host failure: the same log has `mylang: host failure: DiskQuota` and 84 `NativeToolFailed`, and two other tests in the shard also exited 2 |
| `lox-fixes/gate/test2.log` (22:12) | candidate run exited 2 | the same `/tmp` quota outage (49 failures in that gate); the lane predates `d87dd687`/`43dedc7c`, which moved guest-test scratch to `TMPDIR` |
| `perf-plan-20260922/gate/loops-test.log` (2026-09-23 04:44) | the passing baseline check exited 1 | **timing**: the only real flake |

Exit status 2 from `mylang test` means a host failure, not a verdict. Those two
failures came from the `/tmp` quota outage the audit describes, and the move of
test scratch to `TMPDIR` has already fixed them. The test can do nothing about a
machine out of disk. The only change there is that it now prints the child's
stderr, so the next such failure names its cause in the gate log.

**The timing failure.** The test measures `bench_loop(10)` with two 1 ms batches
(`--bench-batches 2 --bench-batch-ms 1`). It promotes the result to a baseline,
then checks a second run against a "passing" policy:

- `allowed_growth_percent: 1000` with `minimum_meaningful_delta_ns: 0`;
- no `noise` block, so the default spread budget of **25%** applies.

Two routes from load to a red run:

- **Noise.** One batch stalled by preemption, CPU throttling or reclaim differs
  from the other by more than half the median, so the spread exceeds 25%. The
  runner then takes its one confirmation run. If the four pooled batches are
  still over budget, the verdict is `inconclusive`, and that exits 1
  (`applyNoiseBudget`, `NATIVE-BENCH-4`).
- **Growth.** A loaded check run more than 11 times slower than the quiet run
  that made the baseline is a `regression`.

**Reproduced, then fixed.** The scratch harness ran the check with the old and
the new policy in a `CPUQuota=5%` scope. That emulates the stalls a throttled or
reclaiming cgroup sees during a gate. Forty runs each:

| policy | pass | inconclusive (exit 1) | regression (exit 1) |
|---|---:|---:|---:|
| old passing policy | 31 | 7 | 2 |
| new passing policy | 40 | 0 | 0 |
| new ceiling policy (20 runs) | 0 | 0 | 0 (all 20 `ceiling`, exit 1, as intended) |

**Why the fix does not weaken the test.** The fix makes each verdict a matter of
construction, not machine speed:

- The passing policy sets `minimum_meaningful_delta_ns` and `max_ns_per_op` to 1 s
  per operation, and `noise.max_relative_spread_percent` to 10⁹. No measurement of
  this loop can be a regression or inconclusive.
- The ceiling policy keeps its 10⁻⁷ ns ceiling, which every measurement exceeds.
  It takes the same noise budget, so the failure is always the ceiling.

The test still covers the whole CLI path: candidate, promotion, the
comparable-identity check, required coverage, the exit statuses, and the
immutable baseline. It is also stronger now. It reads each run's report and
asserts the verdict `pass` or `ceiling`. The old test accepted exit 1 for any
reason, including noise. The growth, noise-budget and confirmation arithmetic
keep their deterministic unit tests in `src/native_bench.zig` ("noise policy
requests at most one confirmation near a limit", "unresolved noise is
inconclusive and required coverage must be present").

## Other timing-dependent tests

A search of `test/integration.zig` and `src/*_test.zig` for sleeps, timeouts,
wall-clock reads, benchmark sampling and `MemAvailable`-derived widths found:

| test | dependence | verdict |
|---|---|---|
| `native_test_execute`: "native test child timeout is bounded and classified…" | 10 ms timeout on `sleep 5` | safe: load can only make the child slower, so the timeout always fires |
| "a wrong benchmark result or trap fails the run…" | benchmark sampling | safe: the verdict comes from a wrong value and a trap, never a timing; it now prints stderr on a wrong exit |
| "a directory benchmark run measures sequentially…" | benchmark sampling, no baseline | safe: no comparison, exit 0 unless the host fails; it now prints stderr |
| `memory_budget`: "the machine reports free bytes…", doctest/`native_test_command` fan-out tests | live `MemAvailable` | safe: they assert `>= 1` or use injected values |
| the guest programs' `time.now(clock)` fixtures (`integration.zig`) | wall clock | safe: they subtract an instant from itself, or only `check` |

None of the others needs a fix. The audit's other "new failures under load"
(nine in one gate) were out-of-memory kills and exit-2 host failures, not timing
assertions. The memory check in `scripts/build-slot.sh` addresses those.

## Gate

Every step ran on a fresh local cache through `scripts/build-slot.sh`, which
shared the coordinator's `slots/` directory, and `~/capbuild`. Each log was
compared with `gate_diff.py` against the green `vecblock` base logs.

| step | result | new failures vs base |
|---|---|---:|
| `zig build` (Guardian) | ok | — |
| `zig build test` | 81/81 steps, 1781 tests passed | 0 |
| `zig build test-qbe` | 50/50 steps, 311/311 tests | 0 |
| `zig build test-qbe-build` | 32/32 steps | 0 |
| `zig build test-schematic` | 29/29 steps | 0 |
| `zig build test-byte-io` | 28/28 steps | 0 |
| `zig build fmt-check` | ok | 0 |

## How agents invoke builds and benchmarks now

```bash
export ZIG_LOCAL_CACHE_DIR=$HOME/.cache/mylang/zig-local-cache-<lane>
export TMPDIR=$HOME/.cache/mylang-tmp/<lane>; mkdir -p "$TMPDIR"
scripts/build-slot.sh build zig build                          # Debug compiler, ~15 s
scripts/build-slot.sh build zig build test-cli -Dtest-filter=X
scripts/build-slot.sh gate  zig build test --summary all
python3 bench/parity/bench_parity.py run --filter sieve        # Debug compiler, CPU 2, not through the wrapper
zig build bench-parity -Dbench-filter=micro/                   # same, through the build step
```

Not done here: kernel-level CPU isolation (`isolcpus`, or `AllowedCPUs` on
`user.slice`). Both need root; `many-agents.md` documents them as options.
