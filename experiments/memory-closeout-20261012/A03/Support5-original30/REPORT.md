# A03 Support5-original30 census

Compiler commit: `a1f19edf255c8c0886731d8d7cce450d5f657720`.
Compiler SHA-256: `8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
Ownership request: `opt-in`.

This is the coordinator-requested original-30 release sanity pass on an interim
compiler, not final C1 or complete five-mode qualification. The separate 51
expanded cases are unmeasured on this artifact. Its staged installed components
retain the coordinator-disclosed legacy support4 package boundary.

`comparison-C0.json` pairs all 72 executions with identical pinned sources,
inputs, environments and expected outputs from C0. Workload and whole-program
allocation traffic, recorded list-copy metrics, and managed peaks are identical
in every pair. This is counted evidence only; it makes no runtime or RSS claim.

Executed 72 guests; 72 passed output, exit, RC and managed-leak checks.
Observed RC in 0 runs; managed exit leaks in 0 runs.

| Original 30, migrated workload | Allocate | Allocation-free | Execute RC | Refused | Failed | Unmeasured |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| n=4; denominator 30 | 23 | 7 | 0 | 0 | 0 | 0 |
| n=11; denominator 30 | 23 | 7 | 0 | 0 | 0 | 0 |

The original unmigrated source checks admitted 21, refused 9, failed outside a source diagnostic 0, and left 0 unmeasured.
These checks are a separate source-migration inventory; they are not counted as migrated execution successes.

| Configuration/status | Cases |
| --- | ---: |
| release/passed | 30 |

All following measurements are fresh release-mode input-11 observations. Workload totals exclude startup/teardown (`<outside>`).

| Original ID | Status | Workload blocks / reallocs | Workload cumulative bytes | Whole-program peak / exit-live bytes | Source cost classification |
| --- | --- | ---: | ---: | ---: | --- |
| 01_scalar | passed | 0 / 0 | 0 | 832 / 0 | scalar control |
| 02_local_list | passed | 0 / 0 | 0 | 832 / 0 | bounded local list; stack-eligible control |
| 03_borrowed_reader | passed | 0 / 0 | 0 | 832 / 0 | borrowed bounded list; stack-eligible control |
| 04_returned_list | passed | 0 / 0 | 0 | 832 / 0 | independent result storage; caller destination opportunity |
| 05_mut_destination | passed | 0 / 0 | 0 | 832 / 0 | caller destination; stack-eligible control |
| 06_dynamic_list | passed | 1 / 0 | 128 | 960 / 0 | independent list storage and growth |
| 07_large_list | passed | 1 / 0 | 4840 | 5672 / 0 | large list storage and growth |
| 08_snapshot_read | passed | 0 / 0 | 0 | 832 / 0 | two borrowed reads; stack-eligible control |
| 09_snapshot_mutate | passed | 3 / 0 | 384 | 1216 / 0 | explicit independent copy and growth |
| 10_loop_snapshots | passed | 13 / 0 | 1344 | 2176 / 0 | explicit saved copies |
| 11_record_scalar | passed | 0 / 0 | 0 | 832 / 0 | scalar aggregate control |
| 12_record_list | passed | 1 / 0 | 128 | 960 / 0 | owned child storage and growth |
| 13_record_snapshot | passed | 4 / 0 | 384 | 1152 / 0 | explicit aggregate/child copy and growth |
| 14_nested_lists | passed | 25 / 0 | 1696 | 2080 / 0 | independent child storage and outer growth |
| 15_managed_elements | passed | 45 / 0 | 3040 | 2528 / 0 | independent text/list children; formatting intermediates |
| 16_branch_alias | passed | 3 / 0 | 192 | 1024 / 0 | explicit branch copy and growth |
| 17_indirect_reader | passed | 1 / 0 | 64 | 896 / 0 | list storage across indirect borrowed call; promotion opportunity |
| 18_recursive_reader | passed | 1 / 0 | 64 | 896 / 0 | list storage across recursive borrowed call; promotion opportunity |
| 19_return_field | passed | 2 / 0 | 128 | 960 / 0 | explicit independent returned-field copy |
| 20_loop_carried | passed | 5 / 0 | 1120 | 1664 / 0 | owned in-place growth; prior artificial sharing removed by migration |
| 21_dict_unique | passed | 2 / 0 | 448 | 1280 / 0 | dictionary storage/growth; native side tables excluded |
| 22_dict_snapshot | passed | 3 / 0 | 736 | 1408 / 0 | explicit dictionary copy/growth; native side tables excluded |
| 23_dict_managed | passed | 57 / 0 | 3968 | 1952 / 0 | dictionary/owned text storage; formatting/replacement intermediates |
| 24_text_builder | passed | 3 / 0 | 224 | 992 / 0 | owned text growth |
| 25_text_snapshot | passed | 4 / 0 | 320 | 1024 / 0 | explicit text copy and growth |
| 26_text_slice | passed | 3 / 0 | 224 | 992 / 0 | owned text growth; returned view borrows without materialization |
| 27_buffer_builder | passed | 6 / 0 | 352 | 992 / 0 | buffer growth |
| 28_buffer_snapshot | passed | 7 / 0 | 448 | 1024 / 0 | explicit independent bytes materialization and buffer growth |
| 29_list_filter | passed | 4 / 0 | 608 | 1408 / 0 | source and independent filtered-result storage/growth |
| 30_sort_scratch | passed | 1 / 0 | 2536 | 3368 / 0 | list storage; native sort scratch excluded |

Classification describes storage required by source semantics and concrete optimization opportunities. It does not attribute every allocation to one category.
Formatting/concatenation intermediates are actionable candidates only after an owner demonstrates a semantics-preserving removal.
Explicit copies and independent return storage must retain their documented independence. Growth is legitimate allocation work.
Task infrastructure is covered separately by the expanded task cases and A01's scheduler decomposition.

For every admitted executable, machine-readable results preserve source/binary/LLVM hashes, output, workload and whole-program counters, and LLVM/linked-symbol audit results.
`raw-json.tar.gz` contains the command receipts and complete counted reports. Full native binaries and LLVM remain in the recorded scratch run directory.
Managed peak is never subtracted as traffic and is not process RSS. Native dictionaries, sort scratch, provider buffers, task stacks and allocator overhead lie outside these counters.
Copy-traffic telemetry is distinct from allocation traffic: A09's 8ba337fd6 correction adds previously unrecorded recursive child-list copies without changing allocations, freed bytes, or managed peak. A C0/candidate difference in list-copy counts or bytes alone is not a new allocation cost.
Admission receipts record queue wait separately for batched runs; command receipts mark whether wait is excluded. These are not compile-performance measurements. A09 owns runtime/RSS/compile timings.
