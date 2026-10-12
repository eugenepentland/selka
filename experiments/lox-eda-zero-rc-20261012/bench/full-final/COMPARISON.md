# Fresh full-application comparisons

Current results use CPU 8, the same frozen compiler for all three mylang arms, unchanged canonical inputs, and four existing competitor executables copied and hashed, then freshly rerun; these references were not rebuilt in this session. Each complete arm has two warmups, nine alternating wall samples, and three separate GNU-time child peak-RSS samples. Wall time includes CLI launch and startup. Every completed guest run passes its output oracles; failed or censored guests remain explicit and cannot establish full-size output qualification. Instrumentation is separate.

Ratios below are wall time divided by the comparison arm. Only full groups receive geometric means. Failed or censored arms remain in the stated group denominator; unavailable ratios are not replaced by a subset estimate.

| Group | Arm | Complete cells | vs original RC | vs migrated RC | vs Zig Fast | vs Zig Safe | vs Rust | vs Go | Largest case-median peak RSS (MiB) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| lox/tree | original RC | 13/13 | 1.000 | 1.019 | 1.815 | 1.105 | 1.387 | 1.350 | 46.45 |
| lox/tree | migrated RC | 13/13 | 0.981 | 1.000 | 1.781 | 1.084 | 1.361 | 1.324 | 46.63 |
| lox/tree | checked zero-RC | 13/13 | 2.322 | 2.366 | 4.213 | 2.565 | 3.220 | 3.134 | 95.99 |
| lox/tree | Zig Fast | 13/13 | 0.551 | 0.562 | 1.000 | 0.609 | 0.764 | 0.744 | 35.34 |
| lox/tree | Zig Safe | 13/13 | 0.905 | 0.922 | 1.642 | 1.000 | 1.255 | 1.222 | 41.60 |
| lox/tree | Rust | 13/13 | 0.721 | 0.735 | 1.308 | 0.797 | 1.000 | 0.973 | 40.56 |
| lox/tree | Go | 13/13 | 0.741 | 0.755 | 1.344 | 0.819 | 1.028 | 1.000 | 73.08 |
| lox/vm | original RC | 13/13 | 1.000 | 0.970 | 2.185 | 1.460 | 1.485 | 1.518 | 166.95 |
| lox/vm | migrated RC | 13/13 | 1.031 | 1.000 | 2.252 | 1.505 | 1.531 | 1.565 | 167.00 |
| lox/vm | checked zero-RC | 10/13 | — (10/13) | — (10/13) | — (10/13) | — (10/13) | — (10/13) | — (10/13) | — |
| lox/vm | Zig Fast | 13/13 | 0.458 | 0.444 | 1.000 | 0.668 | 0.680 | 0.695 | 142.38 |
| lox/vm | Zig Safe | 13/13 | 0.685 | 0.664 | 1.496 | 1.000 | 1.017 | 1.039 | 151.00 |
| lox/vm | Rust | 13/13 | 0.674 | 0.653 | 1.472 | 0.983 | 1.000 | 1.022 | 155.09 |
| lox/vm | Go | 13/13 | 0.659 | 0.639 | 1.440 | 0.962 | 0.978 | 1.000 | 155.42 |
| eda | original RC | 34/34 | 1.000 | 1.007 | 1.238 | 1.128 | 1.128 | 0.479 | 52.70 |
| eda | migrated RC | 34/34 | 0.993 | 1.000 | 1.229 | 1.119 | 1.119 | 0.476 | 52.75 |
| eda | checked zero-RC | 34/34 | 10.380 | 10.458 | 12.850 | 11.707 | 11.708 | 4.976 | 88.02 |
| eda | Zig Fast | 34/34 | 0.808 | 0.814 | 1.000 | 0.911 | 0.911 | 0.387 | 80.25 |
| eda | Zig Safe | 34/34 | 0.887 | 0.893 | 1.098 | 1.000 | 1.000 | 0.425 | 80.12 |
| eda | Rust | 34/34 | 0.887 | 0.893 | 1.098 | 1.000 | 1.000 | 0.425 | 44.05 |
| eda | Go | 34/34 | 2.086 | 2.102 | 2.582 | 2.353 | 2.353 | 1.000 | 65.05 |

Uninstrumented guest failures/censors are listed below. These cells stay in their full group denominator; the affected group ratios remain unavailable.

| Cell | Arm | Status | Phase | Deadline (s) |
|---|---|---|---|---:|
| lox/vm/equality | mylang-zero-rc | timeout | warmup | 120.0 |
| lox/vm/invocation | mylang-zero-rc | timeout | warmup | 120.0 |
| lox/vm/string_equality | mylang-zero-rc | timeout | warmup | 120.0 |

| VM case | Original RC median (s) | Migrated RC median (s) | Zero-RC median (s) or status | Zero / original | Zero / migrated | Original / zero-RC peak RSS (MiB) |
|---|---:|---:|---:|---:|---:|---:|
| binary_trees | 0.980956 | 0.987544 | 18.873640 | 19.240 | 19.112 | 20.543 / 20.441 |
| closures | 1.379695 | 1.457564 | 54.645939 | 39.607 | 37.491 | 5.543 / 5.336 |
| equality | 1.386636 | 1.557202 | timeout | — | — | 2.574 / unavailable |
| fib | 1.292256 | 1.319054 | 31.693742 | 24.526 | 24.028 | 2.574 / 2.699 |
| instantiation | 0.904148 | 0.911970 | 32.124424 | 35.530 | 35.225 | 4.918 / 5.176 |
| invocation | 2.372767 | 2.397412 | timeout | — | — | 2.730 / unavailable |
| method_call | 2.005157 | 2.059669 | 77.101112 | 38.451 | 37.434 | 2.730 / 2.789 |
| properties | 2.057081 | 2.067517 | 101.314636 | 49.252 | 49.003 | 2.730 / 2.793 |
| string_equality | 1.136042 | 1.200246 | timeout | — | — | 3.043 / unavailable |
| strings | 0.795385 | 0.835142 | 52.931717 | 66.549 | 63.381 | 2.574 / 2.699 |
| trees | 2.053791 | 2.089627 | 40.520505 | 19.730 | 19.391 | 166.949 / 166.773 |
| zoo | 2.186573 | 2.192805 | 41.860773 | 19.144 | 19.090 | 2.574 / 2.699 |
| zoo_batch | 1.778681 | 1.819640 | 81.869407 | 46.028 | 44.992 | 2.574 / 2.695 |

| Group | Comparison reference | Historical mylang / reference | Current checked zero-RC / reference |
|---|---|---:|---:|
| lox/tree | Zig Fast | 1.623 | 4.213 |
| lox/tree | Zig Safe | 1.007 | 2.565 |
| lox/tree | Rust | 1.263 | 3.220 |
| lox/tree | Go | 1.249 | 3.134 |
| lox/vm | Zig Fast | 2.926 | incomplete |
| lox/vm | Zig Safe | 1.957 | incomplete |
| lox/vm | Rust | 1.989 | incomplete |
| lox/vm | Go | 2.060 | incomplete |
| eda | Zig Fast | 1.290 | 12.850 |
| eda | Zig Safe | 1.166 | 11.707 |
| eda | Rust | 1.145 | 11.708 |
| eda | Go | 0.474 | 4.976 |

Historical context is preserved per case in per-cell.csv. The Oct9 receipts used CPU 10 and different compiler/executable identities; no cross-date ratio establishes a compiler or ownership speedup. EDA historical RSS uses rss_exact_mib, excluding the launching Python wait4 high-water floor. Historical Lox RSS is GNU-time child peak RSS maximized across timing rounds; current Lox RSS is the median of three separately measured child peak samples. Their RSS estimators therefore differ. The distinct reader/printer EDA subset and expanded Lox bytecode subset are excluded.

This conservative migration increases Lox explicit copy sites from 2 to 184, with 76 staging temporaries; EDA increases from 3 to 843 copy sites across 121 modules, with source lines increasing from 21,792 to 21,856. Its measured costs describe this migration, not an inherent lower bound for every possible zero-RC implementation. The original RC arm isolates the current compiler on the modern original application source. Migrated RC and checked zero-RC share the same migrated source: their comparison includes the cost of implementing explicit value snapshots under each memory mode. RC can retain/share such copies and defer copying until mutation; checked zero-RC owns independent snapshots. Allocation/copy counters are needed to explain that cost; RSS alone cannot show cumulative allocation traffic.

Across the 13 tree cases, the matched-case geometric ratio of zero-RC to original RC child peak RSS is 1.5932. Both largest case-median peaks occur in tree/trees: 47,568 KiB for original RC and 98,296 KiB for zero-RC. These are child resident-memory measurements, separate from managed counters.

Allocation attribution supplies a concrete explanation for the copy burden, without constituting CPU profiling. Full-size VM Fibonacci counted runs record 2,712,877,890 allocations and 664,969,560,232 cumulative allocated bytes in checked zero-RC, versus 460 allocations and 505,496 bytes in both RC arms. Managed peak is 831,536 versus 416,368 bytes, with zero exit-live bytes. vm::run accounts for 621,857,290,208 allocation bytes; its per-opcode frame.copy() boundary appears at migrated vm.my line 434.

EDA rds3+flat counted runs record 2,588,797,232 cumulative allocated bytes in zero-RC versus 191,320,104 in original RC. kicad_sch_textbox::overlaps_of accounts for 1,123,681,184 bytes of allocation plus reallocation growth, and sexpr_ast::as_list for 429,875,760 bytes. The textbox path iterates ordered[i+1:len(ordered)] on each outer iteration (kicad_sch_textbox.my line 137); the core slice builder constructs a fresh list and explicitly copies managed elements in zero_rc (build_list_methods.zig lines 274–300). sexpr_ast.my lines 81–84 returns children.copy() from as_list. These source paths corroborate the allocation counters; they do not prove the fraction of CPU time spent at each site.

All 102 full-size EDA counted runs completed correctly (34 designs across three mylang arms). Cumulative allocated bytes summed over those independent runs are 3,118,944,232 for original RC, 3,119,064,808 for migrated RC and 24,324,668,504 for zero-RC. The matched-case cumulative-allocation geometric ratio of zero-RC to migrated RC is 7.0514. Largest managed peak is 51,415,480 bytes for either RC arm versus 86,587,128 for zero-RC; all exit-live bytes are zero. Zero-RC compiler/runtime/shared retain-release, share-mark and uniqueness-test events are zero. See ../eda-counted-summary.json and its raw gzip archive for complete metrics.

Across the 34 EDA cases, the matched-case geometric zero/original child peak-RSS ratio is 1.3550. Both largest case-median child peaks occur in rds3+flat: 53,964 KiB for original RC versus 90,132 KiB for zero-RC. This is separate from managed peak and cumulative allocation traffic.

Full-size Lox counted coverage is 26/26 cells for each RC arm and 20/26 for checked zero-RC. Six VM instrumented runs were censored at 120 seconds: equality, invocation, method_call, properties, string_equality and zoo_batch. On the exact common 20-cell subset, cumulative allocated bytes summed across independent runs are 10,024,638,912 for original RC, 10,121,124,840 for migrated RC and 7,466,718,651,880 for zero-RC. These sums measure allocation traffic; managed peak remains a per-case quantity. On those same 20 cases, original RC allocates 114,979,544 times, migrated RC 114,997,063 times and zero-RC 16,578,222,271 times. All completed counted runs exit with zero live managed bytes; zero-RC compiler/runtime/shared retain-release and uniqueness-test counts are zero. Its 16,576,177,741 direct destructions are not RC events.

Counted guest runs have their own 120-second deadline. A counted VM censor does not imply an uninstrumented runtime censor; the runtime status and denominators above are derived solely from uninstrumented receipts.

Benchmark mylang guests were built with compiler SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d. The later final integration gate rebuilt the compiler to 8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa with unchanged production source bytes. Existing benchmark guests were not rebuilt or relabeled.
