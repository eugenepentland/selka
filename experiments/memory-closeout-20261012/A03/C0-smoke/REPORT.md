# A03 C0-smoke census

Compiler commit: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Compiler SHA-256: `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
Ownership request: `opt-in`.

Executed 6 guests; 6 passed output, exit, RC and managed-leak checks.
Observed RC in 0 runs; managed exit leaks in 0 runs.

| Original 30, migrated workload | Allocate | Allocation-free | Execute RC | Refused | Failed | Unmeasured |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| n=4; denominator 30 | 0 | 1 | 0 | 0 | 0 | 29 |
| n=11; denominator 30 | 0 | 1 | 0 | 0 | 0 | 29 |

The original unmigrated source checks admitted 1, refused 0, and left 29 unmeasured.
These checks are a separate source-migration inventory; they are not counted as migrated execution successes.

| Configuration/status | Cases |
| --- | ---: |
| release/passed | 3 |

All following measurements are fresh release-mode input-11 observations. Workload totals exclude startup/teardown (`<outside>`).

| Original ID | Status | Workload blocks / reallocs | Workload cumulative bytes | Whole-program peak / exit-live bytes | Source cost classification |
| --- | --- | ---: | ---: | ---: | --- |
| 01_scalar | passed | 0 / 0 | 0 | 832 / 0 | scalar control |

Classification describes storage required by source semantics and concrete optimization opportunities. It does not attribute every allocation to one category.
Formatting/concatenation intermediates are actionable candidates only after an owner demonstrates a semantics-preserving removal.
Explicit copies and independent return storage must retain their documented independence. Growth is legitimate allocation work.
Task infrastructure is covered separately by the expanded task cases and A01's scheduler decomposition.

For every admitted executable, machine-readable results preserve source/binary/LLVM hashes, output, workload and whole-program counters, and LLVM/linked-symbol audit results.
`raw-json.tar.gz` contains the command receipts and complete counted reports. Full native binaries and LLVM remain in the recorded scratch run directory.
Managed peak is never subtracted as traffic and is not process RSS. Native dictionaries, sort scratch, provider buffers, task stacks and allocator overhead lie outside these counters.
Compilation receipts include admission wait; they are not compile-performance evidence. A09 owns runtime/RSS/compile timings.

