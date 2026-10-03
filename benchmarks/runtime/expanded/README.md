This suite expands the original four cases to **40 cases: 35 microbenchmarks and
five application workloads**, across MyLang main LLVM/QBE, Rust, Go, and Zig
ReleaseSafe/ReleaseFast. It preserves the original suite and its saved baseline.
The compiler/runtime source remains pinned to main
`6df58b02554401f9d37564cceffd14277a835ae1`.

Run from the repository root:

```sh
python3 benchmarks/runtime/expanded/run.py --quick --rounds 1 --warmups 0 --output .mylang-cache/runtime-expanded/smoke.json
python3 benchmarks/runtime/expanded/run.py --skip-build --output benchmarks/runtime/expanded/results/main.json
python3 benchmarks/runtime/expanded/verify.py benchmarks/runtime/expanded/results/main.json --check-artifacts
python3 -m unittest discover -s benchmarks/runtime/expanded -p 'test_*.py'
python3 benchmarks/runtime/assessment/assess.py --help
```

The first command builds all 24 executables (four program groups × six compiler
configurations), checks all 40 cases against Python references, and runs a smoke
profile. The second rejects stale builds, calibrates common iteration counts,
and measures 15 rounds after three warmups. A full baseline has **7200 samples**,
1440 warmups, 720 qualification probes, and 480 separate peak-RSS probes.
Each of the 80 case/size combinations runs every compiler in shuffled order.
`--build-only` prepares binaries without measuring. `--only CASE ...` selects
timing cases but still qualifies all cases; its report is explicitly a subset.

The [coverage inventory](coverage.json) maps every microbenchmark to the eight
requested operation areas. Contracts and Python reference implementations are
maintained with each group:

| Group | Cases | Contract |
|---|---:|---|
| Original records, stack, and mutation | 4 | [Original](../CONTRACT.md) |
| Numbers, branches, calls, records, options/errors, search, packets | 12 | [Compute](compute/CONTRACT.md) |
| Lists, maps/sets, allocation, snapshots, sorting, Lox execution | 14 | [Collections](collections/CONTRACT.md) |
| Bytes, strings, conversion, word counting, CSV, JSON | 10 | [Text](text/CONTRACT.md) |

One CLI iteration has a case-specific meaning: it can be one primitive operation,
a dataset pass, or a complete application execution. Reports therefore show
**ns/iteration and its unit**. Compare languages within a case; do not average
unrelated timings. The retained JSON field `median_ns_per_op` means one documented
CLI iteration. The Python references use cycle summation only where the repeated
work has a proved periodic result; the ports still express the full native work.
All fixtures depend on runtime arguments and preserve an observable checksum.
There are no per-operation optimization barriers or forced noinline annotations.

Cases cover both map key types, successful/missing lookups, predictable/mixed
branches, successful/failed Result propagation, transient/retained allocation,
unique/nested shared mutation, Unicode and early/late string mismatches, valid
and malformed decimals, quoted CSV commas/quotes, and stable record sorting.
The JSON workload uses native libraries: MyLang's stdlib, `serde_json` in Rust,
Go's `encoding/json`, and Zig's `std.json`. Its Rust dependencies are pinned by
Cargo.toml and Cargo.lock; Cargo release builds remain portable. Native sorting
and JSON are explicitly library comparisons. Container workloads also include
each language's normal allocation and ownership behavior, as their contracts
explain.

The Lox workload executes a fixed documented bytecode program with tagged values,
variables, branches, loops, an operand stack, and calls/returns. It measures a
small Lox-compatible execution subset; it is not a complete Lox implementation
and excludes scanning, parsing, classes, closures, and dynamic name lookup.
The CSV fixture grammar supports quoted commas and doubled quotes but does not
include embedded newlines or malformed CSV syntax. Network/file waits and
multithreading are outside this suite's scope.

Build policy and validation follow the [original runner](../README.md): same
optimized default target policies, normal MyLang checks and RC, normal Go GC,
separate build/timing phases, pinned guest CPU, recorded sibling activity,
strict checksum/output/status validation, and before/after identities. MyLang
adds `--keep-symbols`, a measurement-only link option, so CPU profiles can name
functions while retaining release optimization. Cargo tuning/wrapper environment
overrides are removed and its RUSTC is the audited compiler used by other Rust
ports. Exact commands, source/dependency/tool/runtime/binary hashes, build logs,
raw samples, and paired bootstrap intervals are retained.

Calibration targets 50 ms for the fastest configuration, with a one-second
slowest-configuration budget, 10-million-iteration cap, and ten-pilot limit.
Every limit is reported; it does not silently qualify a short sample as reaching
the target. Peak RSS is separate process-wide evidence, including setup and
runtime state. In particular, compute ports prepare common fixture arrays even
for kernels that do not use all of them, so their RSS is not an isolated kernel
allocation measurement. Incomplete recovery samples are stored in scratch
`progress.json` and never reused in a successful baseline. A failed invocation
does not replace an older successful output file.

**The coverage goal is representative everyday code.** The requested “80%” is a
practical breadth target: competitive results across common operations should
support confidence in applications built from those operations. It is not a
CPU-time attribution threshold or a measured percentage of all software.

The [coverage inventory](coverage.json) records covered scenarios and limits for
each operation family and application. The [current assessment](../assessment/README.md)
compares every family across all six configurations, keeps individual weaknesses
visible, and separates the five composed application workloads. Case counts are
counts within this suite; there is no overall language score, population
weighting, or automatic pass threshold. An interval overlapping Go does not
establish equivalent performance.

The current suite provides a broad starting point for single-threaded application
logic. Large working sets, recursion/graphs, map deletion and diverse keys,
long-lived heap churn, varied document shapes, concurrency and I/O remain
confidence gaps. Native sorting/JSON APIs and ownership policies are part of
those specific comparisons and must not be generalized to all algorithms.

The CPU profiler, `profile.py`, is for optional hotspot diagnostics. New reports
record primitive-symbol attribution and sampling-quality warnings without an
80% coverage target. The saved version-1 `results/profiles/` captures retain legacy
target fields from the earlier misinterpretation; they are historical diagnostic
evidence, not an acceptance criterion. CPU sampling can help investigate a slow
case; it is not a test of whether this suite represents everyday programming.
Sampling throttling in those captures does not invalidate the separate
uninstrumented baseline timings.

The saved 2026-10-03 baseline predates these documentation/coverage and diagnostic-reporter corrections.
Use the verifier without `--check-artifacts` to check that saved evidence against
its oracle/statistics; current documentation and diagnostic-helper hashes intentionally differ. The
assessment also checks recorded source hashes against the original Git revision
`b725360f5f86ac67bc405db9407ae51c332a9931`. Full current-artifact verification of
that historical run requires its original source checkout and local tools/binaries.
For a new baseline, rebuild before using `--skip-build`.
