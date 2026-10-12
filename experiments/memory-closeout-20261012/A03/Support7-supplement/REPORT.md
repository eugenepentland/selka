# A03 Support7-supplement census

Compiler commit: `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
Compiler SHA-256: `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
Ownership request: `opt-in`.

Executed 40 guests; 40 passed output, exit, RC and managed-leak checks.
Observed RC in 0 runs; managed exit leaks in 0 runs.

This supplemental manifest is separate from the original 30 and pinned 81-case matrix; its cases do not change either denominator.

| Configuration/status | Cases |
| --- | ---: |
| debug/passed | 6 |
| no_facts/passed | 6 |
| optimized_debug/passed | 6 |
| release/passed | 6 |
| verify/passed | 6 |

Classification describes storage required by source semantics and concrete optimization opportunities. It does not attribute every allocation to one category.
Formatting/concatenation intermediates are actionable candidates only after an owner demonstrates a semantics-preserving removal.
Explicit copies and independent return storage must retain their documented independence. Growth is legitimate allocation work.
Task infrastructure is covered separately by the expanded task cases and A01's scheduler decomposition.

For every admitted executable, machine-readable results preserve source/binary/LLVM hashes, output, workload and whole-program counters, and LLVM/linked-symbol audit results.
`raw-json.tar.gz` contains the command receipts and complete counted reports. Full native binaries and LLVM remain in the recorded scratch run directory.
Managed peak is never subtracted as traffic and is not process RSS. Native dictionaries, sort scratch, provider buffers, task stacks and allocator overhead lie outside these counters.
Copy-traffic telemetry is distinct from allocation traffic: A09's 8ba337fd6 correction adds previously unrecorded recursive child-list copies without changing allocations, freed bytes, or managed peak. A C0/candidate difference in list-copy counts or bytes alone is not a new allocation cost.
Admission receipts record queue wait separately for batched runs; command receipts mark whether wait is excluded. These are not compile-performance measurements. A09 owns runtime/RSS/compile timings.

