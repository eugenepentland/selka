# Parity benchmark — mylang against Zig and Rust

The standing performance benchmark of the parity plan
([`docs/audits/performance-parity-plan-2026-09-22.md`](../../docs/audits/performance-parity-plan-2026-09-22.md),
wave 5). It times mylang's release build against Zig ReleaseFast on matched
programs and fails when a program's **ratio** to Zig grows past its threshold.
It is opt-in: `zig build test` never builds or times it.

```bash
zig build bench-parity -Dcompiler-only=true             # everything, CPU 2, 7 rounds
zig build bench-parity -Dbench-filter=sieve -Dbench-cpu=10
zig build bench-parity -Dbench-filter=micro/ -Dbench-rounds=11
zig build bench-parity -Dbench-mylang=/opt/mylang/bin/mylang   # a prebuilt compiler
zig build bench-parity -- --json /tmp/parity.json --arms my zig-safe
```

Without `-Dbench-mylang` the step first installs this checkout's compiler (the
ordinary `zig build`, so a Debug compiler unless `-Doptimize` says otherwise).
On a shared machine, prepare that compiler with `scripts/build-slot.sh build zig
build`, then pass `-Dbench-mylang=zig-out/bin/mylang` or run the Python harness
directly. That keeps compiler preparation inside admission as well as the harness's
arm builds and measurements. Do not put the whole benchmark inside a build slot.
The compiler's own optimization changes only how long the builds take: the
programs are built with `mylang build --release` (the whole program as one
optimized LLVM unit; a compiler named by `-Dbench-mylang` must be a new-core one,
since the old `--backend`/`--llvm-opt`/`--lto` spellings are refused), and a Debug and a
ReleaseFast compiler emit byte-identical binaries
(`python3 bench/parity/bench_parity.py same-binaries --other PATH/bin/mylang`
checks every mylang arm; 88 of 88 matched on 2026-09-23).

## Layout

| path | contents |
|---|---|
| `suite/` | the 11-program suite (13 timed entries): `SUITE.md` fixes algorithm, sizes and output; `<bench>.{my,zig,rs,expected}` plus variants `<bench>_<variant>.<ext>` |
| `lib/` | runtime-library scans (`str.count`, `replace`, `split`) against the Zig standard library; `LIB.md`, `expected.py` (CPython oracle) |
| `micro/` | the eleven micro-kernels in all three languages; `MICRO.md` |
| `bench_parity.py` | the harness: `run`, `rebaseline`, `table` |
| `thresholds.json` | per-program, per-arm ratio thresholds and the batch they came from |

A benchmark is any `<name>.expected` in a group directory; its ports are the
files named `<name>.<ext>` and `<name>_<variant>.<ext>`. Adding a program is
adding its files (and a threshold, see below). The dated evidence the suite came
from stays in `experiments/perf-parity-plan-20260922/` and
`experiments/perf-parity-audit-20260921/micro/` with the porting notes, repros
and counterfactual tooling; this directory is the maintained copy.

## Arms

| arm | build |
|---|---|
| `my` | `mylang build --release` |
| `my-<variant>` | a variant file with the `my` flags (`_tuned`, `_arena`, `_class`, `_flat`, ...) |
| `zig-fast` | `zig build-exe -O ReleaseFast`: **the reference of every ratio** |
| `zig-safe`, `zig-<variant>` | `-O ReleaseSafe`; a Zig variant with ReleaseFast |
| `rust`, `rust-checked`, `rust-<variant>` | `rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -C target-cpu=native -C panic=abort`, `+ -C overflow-checks=on` |

Rust arms are skipped with a notice when no working `rustc` is found (`RUSTC`,
`PATH`, `~/.cargo/bin`); a Rust or other non-mylang arm that fails to build or
qualify is skipped with a notice. A mylang arm that fails either way, or a
`zig-fast` that does, fails the run.

## Method

1. **Build** every arm before anything is timed (`-- --jobs N`, default 4).
2. **Qualify**: one run per arm; stdout must equal `<name>.expected` byte for
   byte and the exit status must be 0.
3. **Measure** per program: peak RSS once per arm (`/usr/bin/time`), hardware
   counters once per arm when available, 2 warm-ups, then `-Dbench-rounds`
   rounds with the arm order shuffled inside each round. Every sample is a
   fresh process pinned to `-Dbench-cpu` with stdout to `/dev/null`; wall time
   and the child's CPU time (`wait4`) are both recorded.
4. **Report** each arm as the median of its per-round ratios to `zig-fast` with
   a 95% bootstrap interval. The table goes to stdout; the JSON (every sample,
   build command, binary hash, RSS, counters, verdict) to
   `.mylang-cache/bench-parity/result.json` unless `-- --json PATH`.
5. **Check** every mylang arm against `thresholds.json`. A program with an arm
   over its limit is **re-measured** once (fresh warm-ups and rounds, all its
   arms); the run fails only if the re-measured median is over the limit too.
   An excess the second pass does not repeat is printed as `noise`, not a
   failure. `-- --no-confirm` fails on the first pass.

Without `-Dbench-cpu` the timing CPU is the first of `MYLANG_TIMING_CPUS`
(CPU 2 when unset). Run the harness directly: it admits arm builds and correctness
checks as ordinary parallel work, then requests an exclusive timing window from
`scripts/build-slot.sh`. The window pauses new admissions and waits for existing
builds and gates to finish. Confirmation runs also request timing admission.
Ordinary jobs can use all allowed CPUs when no measurement is pending; explicitly
setting `MYLANG_TIMING_CPUS` still excludes those CPUs from ordinary work.
Do not wrap the harness in a build/gate slot. Before timing, it
warns when the timing CPU or its sibling is already busy
([many agents on one machine](../../docs/tooling/many-agents.md)). Otherwise,
pick a performance core (`lscpu -e`: on a hybrid Intel part the E-cores are
the high-numbered CPUs) that nothing else is pinned to **and whose SMT sibling
is idle** (the `CORE` column pairs them; CPU 10's sibling on the i7-12700H is
CPU 11). Interleaving makes a ratio fair to both arms against load that slows
both alike, but not against load that slows them differently: identical
binaries moved by up to 1.8× (`nbody`) between batches taken while other agents
shared the machine. A busy sibling, which takes core resources some programs
need more than their Zig ports do, is the likeliest cause (not yet isolated by
experiment). The harness records how busy the sibling was while each program was
timed (`sibling_busy` in the JSON) and prints a notice past 25%. Do not compare
milliseconds across runs at all.

## Thresholds

`thresholds.json` holds, per program and per mylang arm, a baseline `ratio`
(to `zig-fast`, wall time) and a `tolerance`. The limit is
`ratio × (1 + tolerance)`; a run fails when an arm's median ratio exceeds its
limit on both passes, naming the program, the arm, both ratios with their
intervals, and the threshold:

```text
REGRESSION sieve my: ratio 2.31x to zig-fast (95% CI 2.25-2.40) exceeds threshold 1.96x (baseline 1.70x + 15%); re-measured 2.28x (95% CI 2.20-2.35)
```

A ratio below `ratio × (1 − tolerance)` whose whole interval sits under it is
reported as `improved` (never a failure): re-baseline to lock the gain in.
An arm without a threshold is reported and not checked.

**Tolerance policy.** A re-baseline pools the per-round ratios of one or more
batches of the same compiler; the pooled median is the baseline `ratio`. The
`tolerance` is the largest of

- the default (`--tolerance`, 0.15),
- twice the upper half-width of the pooled 95% interval (noise within batches),
- 1.5 × the excess of the slowest batch's median over the pooled median (noise
  between batches),

rounded up to a percent and capped at 50%, so an arm that was noisy when it was
measured does not fail on that noise alone. Two batches are the minimum that
sees the second kind: on a loaded machine one arm's ratio moved 1.71× → 2.30×
between two batches of identical binaries (`spectral_norm`, whose Zig reference
itself moved 228 → 368 ms), and a single-batch baseline failed 3 of 71 arms of
the next batch at 15%.

**Updating thresholds** is deliberate, never a side effect of an ordinary run:

```bash
# two batches, then pool them
zig build bench-parity -Dbench-cpu=10 -Dbench-rounds=9 -- --json a.json
zig build bench-parity -Dbench-cpu=10 -Dbench-rounds=9 -- --json b.json
python3 bench/parity/bench_parity.py rebaseline a.json b.json --label quiet --note "..."
# or from the run you are making (one batch)
zig build bench-parity -Dbench-cpu=10 -Dbench-rounds=11 -- --write-thresholds --label quiet
```

Programs the results did not measure keep their entries, so a filtered run
re-baselines only what it timed. Each entry names its batch; `batches` records
the compiler hash, commit, and each run's CPU, rounds and load average, with a
label saying whether the machine was quiet or loaded. `--note` replaces the
file's `note`; a re-baseline without one drops the old note.

## Hardware counters

With `perf` installed and `kernel.perf_event_paranoid <= 2`, the harness runs
each qualified arm once more under `perf stat -e
instructions:u,cycles:u,branches:u,branch-misses:u,cache-misses:u`. That run is
pinned to the timing CPU, because on a hybrid part a P-core's cycles and an
E-core's are not comparable. The counts go in the JSON (`counters`). A second
table after the ratio table gives, per benchmark:

- mylang's instruction count against Zig's and Rust's;
- each arm's instructions per cycle;
- branch misses and last-level-cache misses per thousand instructions.

Instruction counts do not depend on machine load the way wall time does, so they
separate "does more work" from "runs slower on the same work". Without counters
the harness prints a notice and records none. The plan asks for `<= 1` so kernel
time can be counted as well. Lowering the setting needs root (`sysctl
kernel.perf_event_paranoid=1`, or a file in `/etc/sysctl.d/` to keep it); the
harness never changes it.

## Not covered

The S-expression parser (`experiments/perf-parity-plan-20260922/parser_bench.py`)
and the schematic tool (`experiments/schematic-parity-gap-20260922/scripts/bench_svg.py`)
are the plan's application benchmarks; they depend on other trees and
inputs and are not part of this step yet. Counterfactual and ladder arms stay
with the evidence snapshot (`bench.py --cf`).
