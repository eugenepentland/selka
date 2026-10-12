# Lox and EDA with checked ownership

Status: application correctness and final registered verification have passed.
The complete 34-design EDA comparison is available; the 26-cell Lox comparison
is still running. No full-suite Lox result is claimed yet.

The full Lox interpreter and EDA renderer have been migrated to checked zero-RC
ownership. The compiler remains `mylang`; checked ownership is selected with
`--experimental-zero-rc`. Ordinary RC is retained as a comparison control. Lox's
own guest-object garbage collector and EDA's output semantics are preserved.

## Frozen compiler and verification

- Compiler source: `e2893d2707cbe057a09abf94e04c4b12d16b7b8b`.
- Compiler SHA256: `6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d`.
- Complete registered verification: 45 fresh actions, 135/135 build steps, PASS.
- The compiler change adds bounded, read-only optional provider arguments for
  Lox's real clock. Provider storage and escaping providers remain refused.
- Compiler identity and initial raw verification: [coordinator/compiler-identity.json](coordinator/compiler-identity.json).
- Final integrated verification at `4034a2fab29e3300b6f70549ce84727d647761db`: 22 executed actions, 11 always-fresh actions and 12 reused actions; stable inputs, exit 0, Guardian 88/88.
- That gate rebuilt the compiler executable to SHA256 `8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa` from unchanged production sources. All benchmark guests retain their original `6e7938...` compiler provenance and frozen executable hashes; their measurements are not relabelled as results of the gate rebuild. See [final gate identity](coordinator/integrated-gate-identity.json).

## Application qualification

| Application | Evidence |
| --- | --- |
| Lox | 65 unit tests; 974 conformance checks in each of five builds; both tree and VM engines, normal and GC-stress execution; matching smoke output and guest GC statistics across three release arms. |
| EDA | All 121 source/test modules checked; 310 tests in original RC, migrated RC, zero-RC verified release and zero-RC debug; 34 complete golden designs across five builds (170 byte-identical output sets); nine error-path comparisons. |

The EDA integration also requires a copy/update/publish rewrite for nested list
child-field mutation. The unsupported direct-write shape and its diagnostic are
preserved as a reproducer; no RC fallback was introduced.

Lox's smaller counted smoke corpus has 26 cases and three arms (78 runs): all have
zero managed exit-live bytes, and every checked-ownership run has zero RC traffic.
`release_unique` is a direct-destruction counter, not a reference-count operation.
Full-size counted results are collected separately and must not be substituted
with these smaller smoke inputs.

## Comparison method

The complete matrix has 26 Lox cells (13 workloads in each engine) and 34 EDA
designs. Each cell compares original RC, migrated RC, and migrated zero-RC built
with the same frozen compiler, plus frozen Zig ReleaseFast, Zig ReleaseSafe, Rust
and Go reference executables. See [frozen references](bench/frozen-references.json).

Uninstrumented timing uses two warmup rounds, nine alternating measured rounds,
and three separate GNU-time child peak-RSS runs on CPU8. Exclusive timing leases
share the repository's admission queue. Queue wait is not guest runtime. Longer
Lox cases are split into bounded leases so native qualification jobs can proceed.
A guest exceeding120 seconds is retained as a censored arm; no full-suite ratio
is produced from an incomplete subset. Failed arms are not repeatedly retried by
later chunks of the same case.

Separate counted executables measure whole-program allocations, reallocations,
allocated bytes, peak live managed bytes, exit-live bytes and RC operations.
These include application startup and input processing. Managed counters exclude
some native metadata, provider storage and allocator overhead; they are not RSS.
Instrumented wall times are not timing samples.

Stored October9 results remain separately identified in
[historical.json](bench/historical.json). They used CPU10 and fewer/different
measurement rounds, and reference artifact identities can differ. Fresh paired
comparisons are the primary controls. Host details are in
[measurement-host.json](bench/measurement-host.json).

## Complete EDA results

Across all 34 designs, checked zero-RC takes **10.380x** the original RC wall
time and **10.458x** the migrated RC wall time (geometric means). Migrated RC
takes **0.993x** original RC time; that small difference is not a speedup claim.
Every arm passed the entire output oracle, with no failed or censored EDA run.

Matched-case peak RSS has a geometric ratio of **1.355x** zero-RC / original RC.
The largest case, `rds3+flat`, rises from **52.699 to 88.020 MiB** (median of
three child peak-RSS measurements). RSS is distinct from managed memory.

The 34 separately instrumented checked runs allocate **24.325 GB cumulatively**,
versus **3.119 GB** in either RC control (decimal GB, sum of independent runs).
The largest observed live managed peak is **86,587,128 bytes** with zero-RC and
**51,415,480 bytes** with original RC. Every counted arm-case run ends with zero
managed live bytes; checked runs have zero compiler/runtime/shared RC events.
Cumulative traffic is not simultaneous storage or an RSS measurement.

The detailed [EDA comparison](bench/EDA-COMPARISON.md) includes all seven arms,
per-case ranges and the separately identified historical Zig/Rust/Go results.
Existing competitor executables were copied, hashed and rerun on this machine;
they were not rebuilt in this session.

## Initial complete Lox results

These are individual cases, not aggregate estimates. Runtime is the median of
nine runs; RSS is the median of three separate runs.

| Workload | Original RC | Migrated RC | Zero-RC | Zero-RC / original | Original / zero-RC RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Lox tree Fibonacci | 161.58 ms | 153.49 ms | 323.84 ms | 2.00x | 5836 / 7848 KiB |
| Lox VM Fibonacci | 1.2923 s | 1.3191 s | 31.6937 s | 24.53x | 2636 / 2764 KiB |

Raw samples: [initial Fibonacci receipts](bench/results/initial-fib).
The performance regressions are being recorded without further optimization,
as requested. The final report will replace this initial table with the complete
comparison, including failures or censored cases.

## Running the migrated applications

From the integration checkout after building its compiler:

```sh
zig-out/bin/mylang build experiments/lox-eda-zero-rc-20261012/lox/migrated/main.my --release --experimental-zero-rc -o /tmp/lox-owned
/tmp/lox-owned --engine=vm program.lox
/tmp/lox-owned --engine=tree program.lox

zig-out/bin/mylang build experiments/lox-eda-zero-rc-20261012/eda/source/src/main.my --release --experimental-zero-rc -o /tmp/eda-owned
/tmp/eda-owned --model model.sexp --project-dir project --out-dir output
```

Detailed source provenance, migration burden, exact commands and application
receipts accompany each application. The [item ledger](ledger.json) distinguishes
completed correctness work from the measurements still in progress.
