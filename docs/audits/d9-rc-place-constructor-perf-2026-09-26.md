# Combined constructor and runtime n12 measurement

The fully gated `2b42a543` compiler combines the fresh-constructor transfer proof,
explicit frame-journal initialization, drain descriptor cache and private-loan
mutable-path correction. Against immutable `19e16e1d`, five interleaved n12
instruction samples on CPU 11 show a **19.99% QBE** and **17.39% LLVM** reduction.
These are measured cumulative results, not products of isolated agent ratios.

| Backend | Before | Combined | Combined / before |
|---|---:|---:|---:|
| QBE | 599,762,562 | 479,893,513 | 0.800139 |
| LLVM O3/full LTO | 329,524,802 | 272,214,089 | 0.826081 |

All runs print the exact expected output. Before/after ABI3 counters are identical:
669,060 heap allocations and retirements, 19 O acquisitions, 669,079 O releases,
no H tokens, 33 uniqueness checks and no clones or limit refusals. The compiler
is the same Debug binary used for the full gate and both 851-assertion RC sweeps,
SHA-256 `0fcd8e4a799a76c9a7405812fa3db2db28c8e38cabd82a526656c54f4df53841`.

The accepted GC n12 reference medians remain 105,803,367 QBE and 50,532,284 LLVM
instructions. The combined RC result is therefore still about 4.54× QBE and
5.39× LLVM on this diagnostic. WP-4 instruction/RSS acceptance is not met.
The GC reference was not remeasured in this local comparison.

The [archive](../../experiments/d9-rc-place-constructor-perf-20260926/README.md)
contains every raw sample, exact build/perf commands, source and native-binary
hashes, backend manifests, counter records and the original measurement driver.
GC remains the default. The separate nbody refinements are not present in this
compiler and require their own combined validation.
