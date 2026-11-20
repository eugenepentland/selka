# Runtime benchmarks

The ownership rebaseline uses the current native compiler, all 40 cases and both
prescribed sizes. It keeps the historical iteration counts and independent
Python checksum oracle, measures three fixed native samples per case and size,
and records the host load. It uses ordinary build admission without a timing
window, load qualification or confirmation runs:

```sh
source ~/.config/selka/dev-env.sh
scripts/build-slot.sh build python3 scripts/ownership_rebaseline.py --compiler zig-out/bin/selka --zig "$(command -v zig)" --suite runtime --work .tmp/runtime-ownership-baseline
```

Use a new ignored work directory for each requested observation. Full samples
remain there; baseline summaries report median nanoseconds per contract
iteration. Programs use checked ownership, with explicit copies for independent
mutation and deterministic cleanup.

## Checked-ownership baseline (2026-10-17)

All 40 cases at both sizes pass the independent checksum oracle in all three
fixed samples: **240/240** correct, with positive kernel times and empty stderr.
Start load was **22.383 / 18.788 / 14.252**; end load was
**21.978 / 19.083 / 14.520**. Sizes and iteration counts match the saved
2026-10-03 plans. Each value below is the median kernel nanoseconds per
contract iteration; units differ by case, so these rows are not pooled into
an overall score. Full samples remain in ignored scratch.

Against the saved October 3 Selka LLVM medians, 33 case-size observations
are faster and 47 are slower. The largest ratio is **6.230×** for
`mutate_nested` at size 1,024 (the size-64 ratio is **6.095×**). These are
comparisons across compiler, language, runtime and host-load changes, not an
isolated measurement of ownership. The new baseline preserves these outcomes.

| Case | Small size | Small ns/iteration | Large size | Large ns/iteration |
|---|---:|---:|---:|---:|
| `alloc_retained` | 64 | 2,282.361 | 1,024 | 35,837.002 |
| `alloc_short` | 64 | 289.493 | 1,024 | 3,414.989 |
| `binary_search` | 16 | 182.634 | 256 | 5,383.258 |
| `branch_mixed` | 64 | 259.412 | 4,096 | 19,085.733 |
| `branch_predictable` | 64 | 221.539 | 4,096 | 16,118.894 |
| `bytes_scan` | 64 | 8.462 | 4,096 | 126.265 |
| `call_direct` | 64 | 154.659 | 4,096 | 7,952.094 |
| `call_indirect` | 64 | 191.316 | 4,096 | 11,231.161 |
| `csv_aggregate` | 16 | 8,832.561 | 256 | 147,070.362 |
| `dict_lookup` | 64 | 703.830 | 4,096 | 43,834.853 |
| `dict_lookup_str` | 64 | 1,222.611 | 4,096 | 106,011.977 |
| `dict_update` | 64 | 8,468.747 | 4,096 | 614,594.878 |
| `dict_update_str` | 64 | 18,864.889 | 4,096 | 2,024,713.479 |
| `float_math` | 64 | 171.626 | 4,096 | 13,978.153 |
| `int_format` | 64 | 38.898 | 4,096 | 31.290 |
| `int_parse` | 64 | 17.627 | 4,096 | 17.010 |
| `integer_math` | 64 | 230.530 | 4,096 | 10,711.071 |
| `json_transform` | 16 | 31,956.142 | 256 | 315,531.170 |
| `list_append` | 64 | 197.898 | 4,096 | 25,785.435 |
| `list_filter` | 64 | 509.788 | 4,096 | 25,450.102 |
| `list_scan` | 64 | 177.818 | 4,096 | 7,800.558 |
| `lox_eval` | 16 | 2,032.364 | 256 | 34,169.221 |
| `mutate_nested` | 64 | 4,552.917 | 1,024 | 44,430.284 |
| `mutate_shared` | 64 | 42.113 | 1,024 | 279.798 |
| `mutate_unique` | 64 | 11.983 | 1,024 | 8.080 |
| `option_handle` | 64 | 244.808 | 4,096 | 13,121.569 |
| `packet_decode` | 16 | 189.753 | 256 | 3,035.634 |
| `record_construct` | 64 | 314.543 | 4,096 | 19,677.333 |
| `record_reads` | 64 | 12.206 | 4,096 | 11.274 |
| `record_update` | 64 | 382.306 | 4,096 | 23,438.885 |
| `result_propagate` | 64 | 255.062 | 4,096 | 18,564.700 |
| `set_dedup` | 64 | 1,423.694 | 4,096 | 83,870.349 |
| `sort_int` | 64 | 456.819 | 4,096 | 61,703.624 |
| `sort_records` | 64 | 2,351.229 | 4,096 | 105,473.296 |
| `string_equal` | 64 | 11.553 | 4,096 | 32.843 |
| `string_join` | 64 | 287.091 | 4,096 | 18,599.870 |
| `string_search` | 64 | 56.948 | 4,096 | 210.029 |
| `string_split` | 64 | 1,208.062 | 4,096 | 73,681.524 |
| `tagged_stack` | 64 | 16.557 | 4,096 | 17.086 |
| `word_count` | 16 | 713.474 | 256 | 9,838.059 |

## Historical multi-language baseline (2026-10-03)

The following commands and methodology describe the saved pre-retirement
six-arm baseline. Its QBE and GC-specific details are historical and do not
describe the current compiler.

The [representative performance assessment](assessment/README.md) is the historical
entry point for judging coverage of everyday code and performance by operation
family. It uses the saved 40-case baseline; CPU-sample attribution is not a
coverage acceptance criterion.

The [expanded suite](expanded/README.md) covers 40 cases across the eight everyday
operation areas and five application workloads, using all four languages. The
commands below run the original four-case contract with a recorded candidate
compiler. Follow [candidate build and identity instructions](CANDIDATES.md) to
create `compiler-receipt.json` first.

Run from the repository with Python 3:

```sh
python3 benchmarks/runtime/runner.py --candidate-id candidate-smoke --compiler-receipt compiler-receipt.json --quick --rounds 1 --warmups 0
python3 benchmarks/runtime/runner.py --candidate-id candidate-full --compiler-receipt compiler-receipt.json
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
`--selka`, `--rustc`, `--go`, `--zig`, `--cc`, `--work`, and `--output` provide
overrides. `--profile smoke` is an alias for `--quick`. Scratch builds live in
`.selka-cache/runtime-baseline`; results default to
`benchmarks/runtime/results/runtime.json` with a companion Markdown report.

`--skip-build` requires a matching manifest: contract, oracle, runner, ports,
compiler executables and installed runtime/QBE assets, build commands and
environment, native clock object, and guest binary hashes must match. Before
and after sampling identities must also match. All builds finish before
qualification and timing. Build commands go through `scripts/build-slot.sh`
with private disk temporary directories and caches; their commands and logs
are recorded. Selka links the small native clock helper compiled by the
system C compiler. Selka LLVM uses ReleaseFast/O3/LTO; QBE uses ReleaseFast;
Rust uses portable `-O`; Go uses normal `go build`; Zig uses its default host target with ReleaseSafe/ReleaseFast. These are
optimized default build policies, with different instruction sets across arms.
Selka LLVM derives its first target CPU and merged features from Zig/Clang
(including host features); Selka QBE uses amd64_sysv, Rust uses its default
x86_64 target, and Go uses GOAMD64=v1. The identity records each policy and the
Zig/Clang probe CPU entries and feature list. No forced target tuning or disabled
Selka checks are introduced.

Go runs with `GOMAXPROCS=1`, `GOGC=100`, `GOMEMLIMIT=off`, `GOAMD64=v1`, and
empty `GOFLAGS`/`GOEXPERIMENT`; `GOTOOLCHAIN=local` prevents implicit toolchain
replacement. Inherited SELKA_* settings, compiler tuning flags and Go debug
settings are removed. Selected environment settings are recorded. The compiler
source revision for new runs comes from the checked compiler build receipt.
Historical `runtime-v1` evidence retains its original CONTRACT compiler pin;
new `runtime-v2` evidence cannot silently reuse that identity. Compiler binary
hashes, supported version output, source hashes and exact commands provide
identity. Selka has no supported version query, so its recorded identity uses
the compiler receipt's source revision and binary SHA. The Rust
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
