The [expanded suite](expanded/README.md) covers 40 cases across the eight everyday
operation areas and five application workloads, using all four languages. The
commands below retain the original four-case baseline for reproducibility.

Run from the repository with Python 3:

```sh
python3 benchmarks/runtime/runner.py --quick --rounds 1 --warmups 0
python3 benchmarks/runtime/runner.py
python3 -m unittest discover -s benchmarks/runtime -p 'test_*.py'
```

The first command is a smoke profile; it does not calibrate. The second builds
all six arms, qualifies every case against the independent Python evaluator,
calibrates common iteration counts, then runs three warmup rounds and fifteen
measurement rounds per case and size. Each round shuffles all arms with a fixed
seed. CPU 2 is the default; reserve its sibling and avoid competing workloads.
The environment records topology, governor/frequency settings, machine load,
and per-core busy percentages across sampling (including warmups and memory
probes). A sibling busy above 5% produces a warning. This records average
interference, and cannot enforce exclusive ownership or rule out brief loads.

Calibration targets the fastest arm at 50 ms by default (minimum permitted target
30 ms). All arms use the same iteration count for each case and size. A 2-second
slowest-arm cap and 10-million-iteration safety cap may prevent a fast arm from
reaching its target; these cases retain explicit `calibration.limited` evidence
and a summary warning. Measurements use fresh processes with normal runtime GC;
allocation and collection inside snapshot batches remain in kernel time.

`--only record_reads tagged_stack` selects cases, never language arms. Every
port still passes edge qualification for every case. Subset coverage and smoke
profiles are labeled explicitly and are not a complete baseline. `--rounds`,
`--warmups`, `--target-ms`, `--max-sample-ms`, `--max-iterations`, `--cpu`,
`--mylang`, `--rustc`, `--go`, `--zig`, `--cc`, `--work`, and `--output` provide
overrides. `--profile smoke` is an alias for `--quick`. Scratch builds live in
`.mylang-cache/runtime-baseline`; results default to
`benchmarks/runtime/results/runtime.json` with a companion Markdown report.

`--skip-build` requires a matching manifest: contract, oracle, runner, ports,
compiler executables and installed runtime/QBE assets, build commands and
environment, native clock object, and guest binary hashes must match. Before
and after sampling identities must also match. All builds finish before
qualification and timing. Build commands go through `scripts/build-slot.sh`
with private disk temporary directories and caches; their commands and logs
are recorded. MyLang links the small native clock helper compiled by the
system C compiler. MyLang LLVM uses ReleaseFast/O3/LTO; QBE uses ReleaseFast;
Rust uses portable `-O`; Go uses normal `go build`; Zig uses its default host target with ReleaseSafe/ReleaseFast. These are
optimized default build policies, with different instruction sets across arms.
MyLang LLVM derives its first target CPU and merged features from Zig/Clang
(including host features); MyLang QBE uses amd64_sysv, Rust uses its default
x86_64 target, and Go uses GOAMD64=v1. The identity records each policy and the
Zig/Clang probe CPU entries and feature list. No forced target tuning or disabled
MyLang checks are introduced.

Go runs with `GOMAXPROCS=1`, `GOGC=100`, `GOMEMLIMIT=off`, `GOAMD64=v1`, and
empty `GOFLAGS`/`GOEXPERIMENT`; `GOTOOLCHAIN=local` prevents implicit toolchain
replacement. Inherited MYLANG_* settings, compiler tuning flags and Go debug
settings are removed. Selected environment settings are recorded. The compiler
source revision is pinned by CONTRACT; supply an audited compiler built from
that revision. Compiler binary hashes, supported version output, source hashes
and exact commands provide identity. MyLang has no supported version query, so
its recorded identity uses the audited source revision and binary SHA. The Rust
invocation path is preserved even when it is a rustup shim; its actual toolchain
compiler is located via `--print sysroot` and hashed separately.

Primary measurements are the guest's monotonic kernel nanoseconds. Every
sample must have exact output, empty stderr, positive elapsed time, a correct
checksum and exit status zero. Process wall time is secondary. Peak RSS comes
from a separate fresh `/usr/bin/time` process after sampling, with its own
kernel and wall time; it is never substituted for a timed sample. Only the RSS
marker's stderr is permitted for these probes. Timeouts, malformed results,
missing coverage or changed artifacts abort without publishing a new successful
report. A previous result file may still exist after an aborted run; only a
successful invocation publishes the requested output.

The JSON retains pilots, qualification, warmups, raw samples, memory probes,
identity, and summary statistics. The Markdown report shows per-case median
ns/op, observed min/max, median ratios paired to Go in the same round, and
95% deterministic bootstrap intervals for those paired ratios. Here an operation
means one CONTRACT iteration, including snapshot preservation for shared mutation.
No overall score pools these different workloads. Small smoke round counts do
not provide useful uncertainty estimates. No builds occur during measurement.

The [2026-10-03 main baseline](results/README.md) includes the first complete
six-configuration run, its raw samples, interpretation, and validation receipts.
Validate its coverage, checksums, statistics, and current local artifacts with:

```sh
python3 benchmarks/runtime/verify_report.py benchmarks/runtime/results/baseline_main_20261003.json --check-artifacts
```

Omit `--check-artifacts` to validate the stored measurements after the original
local compiler and scratch binaries are no longer available.
