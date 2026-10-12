# Full-size Lox counted memory measurements

All 26 performance cells used their frozen full-size inputs and three frozen counted guests. These instrumented runs provide memory and ownership counters; elapsed times here are not runtime comparisons. Each cell ran under shared admission on CPU 8 with a 120-second guest deadline. No censored run was retried or scaled down. Exact commands, inputs, qualification receipts, and raw counters are retained alongside this summary.

Completed cases: original RC 26/26, migrated RC 26/26, checked zero RC 20/26. Checked unavailable cases: lox/vm/equality, lox/vm/invocation, lox/vm/method_call, lox/vm/properties, lox/vm/string_equality, lox/vm/zoo_batch. Their metrics remain unavailable; neither RC nor exit-live status is inferred.

Every successful checked run has zero compiler retain/release/uniqueness-test counts, zero runtime/shared retain/release counts, and zero managed bytes live at exit. Every successful RC run also has zero managed bytes live at exit. `release_unique` records direct destruction, separately from reference counting (see `src/core/emit_count.zig:30`, `src/core/emit_llvm.zig:3448`, and `src/core/count_test.zig:691`). Lox's own guest-object garbage collector is unchanged; these counters concern host runtime storage.

Aggregate traffic uses only the common completed three-arm subset, **20/26** cases. Per-cell peak memory remains in `summary.json`; peaks are not added into a global memory claim.

| Arm | Allocations | Reallocations | Cumulative allocated bytes |
| --- | ---: | ---: | ---: |
| mylang-original-rc | 114,979,544 | 725 | 10,024,638,912 |
| mylang-migrated-rc | 114,997,063 | 740 | 10,121,124,840 |
| mylang-zero-rc | 16,578,222,271 | 751 | 7,466,718,651,880 |

Guest provenance remains compiler source `e2893d2707cbe057a09abf94e04c4b12d16b7b8b`, executable SHA256 `6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d`. Later gate rebuilds do not change this provenance. Frozen guest hashes are verified in `summary.json`.

A concrete copy-cost example is full-size VM fib: checked zero RC allocates 2,712,877,890 times and accumulates 664,969,560,232 allocated bytes, versus 460 allocations and 505,496 bytes for each RC arm. Peak managed storage is 831,536 versus 416,368 bytes, with exit-live zero. The raw function counters attribute 2,491,415,465 allocations and 621,857,290,208 allocation bytes to `vm::run`, consistent with the explicit frame copy per opcode at `migrated/vm.my:434`. Cumulative traffic is not resident memory or RSS. The conservative ownership migration retains this copy cost.

Large per-case summaries and raw counters are losslessly gzip-compressed. `compressed-evidence-manifest.json` binds both compressed and uncompressed SHA256 identities; exact uncompressed copies are also retained in the local disposable artifact directory.
