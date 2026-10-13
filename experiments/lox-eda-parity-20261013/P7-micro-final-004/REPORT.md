# C4 fresh six-cell micro comparison

Ratios below1 mean lower kernel time per iteration. All comparisons use fresh matched rounds; historical samples are not pooled. Runtime, process RSS and instrumented managed memory remain separate.

| Case | Candidate µs | /ZigSafe | /ZigFast | /Rust | /Go | /checked baseline | /checked common |
|---|---:|---:|---:|---:|---:|---:|---:|
| csv_aggregate.large | 43.841 | 0.707 [0.700,0.715] | 0.878 [0.869,0.883] | 0.677 [0.671,0.684] | 0.552 [0.548,0.557] | 0.669 [0.663,0.673] | 1.003 [0.990,1.010] |
| csv_aggregate.small | 2.761 | 0.783 [0.779,0.786] | 0.983 [0.976,0.988] | 0.709 [0.700,0.711] | 0.546 [0.540,0.549] | 0.682 [0.677,0.685] | 0.998 [0.987,1.003] |
| json_transform.large | 108.882 | 0.528 [0.524,0.533] | 0.668 [0.665,0.674] | 1.027 [1.019,1.034] | 0.226 [0.225,0.228] | 0.478 [0.475,0.481] | 1.005 [0.997,1.013] |
| json_transform.small | 7.863 | 0.613 [0.590,0.620] | 0.862 [0.834,0.876] | 1.012 [0.988,1.043] | 0.229 [0.219,0.234] | 0.491 [0.483,0.503] | 1.013 [0.995,1.034] |
| string_split.large | 28.003 | 0.460 [0.457,0.464] | 0.489 [0.487,0.492] | 1.050 [1.045,1.059] | 0.430 [0.427,0.434] | 0.431 [0.429,0.436] | 1.009 [1.005,1.019] |
| string_split.small | 0.466 | 0.459 [0.456,0.467] | 0.497 [0.492,0.503] | 0.880 [0.874,0.903] | 0.458 [0.453,0.464] | 0.416 [0.414,0.423] | 1.006 [0.989,1.018] |

| Case | Arm | RSS KiB median [min,max] | Managed allocations | Cumulative bytes | Managed peak bytes | Exit-live bytes | RC events |
|---|---|---:|---:|---:|---:|---:|---:|
| csv_aggregate.large | checked-baseline | 1988 [1988,1988] | 3656950 | 237327008 | 118160 | 0 | 0 |
| csv_aggregate.large | checked-common | 1992 [1988,1992] | 2036273 | 133603680 | 118064 | 0 | 0 |
| csv_aggregate.large | checked-candidate | 1992 [1992,1992] | 2036273 | 133603680 | 118064 | 0 | 0 |
| csv_aggregate.large | zig-safe | 2752 [2748,2752] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.large | zig-fast | 2480 [2480,2480] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.large | rust | 2712 [2544,2728] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.large | go | 7712 [7652,7856] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.small | checked-baseline | 1828 [1824,1828] | 3893157 | 252186528 | 8192 | 0 | 0 |
| csv_aggregate.small | checked-common | 1832 [1832,1832] | 2211218 | 144542432 | 8096 | 0 | 0 |
| csv_aggregate.small | checked-candidate | 1832 [1828,1832] | 2211218 | 144542432 | 8096 | 0 | 0 |
| csv_aggregate.small | zig-safe | 2592 [2592,2592] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.small | zig-fast | 2320 [2320,2320] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.small | rust | 2436 [2416,2704] | unavailable | unavailable | unavailable | unavailable | unavailable |
| csv_aggregate.small | go | 7872 [7712,7980] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.large | checked-baseline | 2308 [2308,2308] | 4545695 | 339061384 | 287408 | 0 | 0 |
| json_transform.large | checked-common | 2152 [2152,2152] | 1119036 | 123461368 | 213464 | 0 | 0 |
| json_transform.large | checked-candidate | 2152 [2152,2152] | 1119036 | 123461368 | 213464 | 0 | 0 |
| json_transform.large | zig-safe | 2912 [2912,2912] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.large | zig-fast | 2640 [2640,2640] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.large | rust | 2720 [2716,2748] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.large | go | 8536 [8224,8544] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.small | checked-baseline | 1988 [1988,1988] | 4254784 | 310586856 | 18592 | 0 | 0 |
| json_transform.small | checked-common | 1832 [1832,1988] | 1134119 | 116576328 | 13728 | 0 | 0 |
| json_transform.small | checked-candidate | 1992 [1992,1992] | 1134119 | 116576328 | 13728 | 0 | 0 |
| json_transform.small | zig-safe | 2532 [2532,2532] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.small | zig-fast | 2320 [2320,2320] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.small | rust | 2404 [2400,2432] | unavailable | unavailable | unavailable | unavailable | unavailable |
| json_transform.small | go | 7904 [7904,8064] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.large | checked-baseline | 2328 [2328,2328] | 7467933 | 598650168 | 401440 | 0 | 0 |
| string_split.large | checked-common | 2344 [2344,2344] | 5932 | 119684344 | 401312 | 0 | 0 |
| string_split.large | checked-candidate | 2344 [2344,2344] | 5932 | 119684344 | 401312 | 0 | 0 |
| string_split.large | zig-safe | 2496 [2492,2496] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.large | zig-fast | 2492 [2492,2492] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.large | rust | 2720 [2696,2744] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.large | go | 7776 [7616,7776] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.small | checked-baseline | 1848 [1848,1848] | 7385979 | 661953936 | 7528 | 0 | 0 |
| string_split.small | checked-common | 1864 [1864,1864] | 107122 | 223509840 | 7944 | 0 | 0 |
| string_split.small | checked-candidate | 1864 [1860,1864] | 107122 | 223509840 | 7944 | 0 | 0 |
| string_split.small | zig-safe | 2336 [2332,2336] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.small | zig-fast | 2332 [2328,2332] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.small | rust | 2424 [2376,2428] | unavailable | unavailable | unavailable | unavailable | unavailable |
| string_split.small | go | 7776 [7776,7936] | unavailable | unavailable | unavailable | unavailable | unavailable |

All six candidate/ZigFast ratios are below1, including CSVsmall0.983[0.976,0.988]. The candidate is within roughly1% of checkedcommon in these fresh pairs; string_split.large has a small measured1.009[1.005,1.019] ratio. These preserve historical improvements against checkedbaseline, rather than demonstrate a new speedup over checkedcommon. Candidate managed headline metrics exactly match checkedcommon in allsixcells. RSS remains a separate processmaximum, not managedpeak.

| Case | Checked arm | Managed list/dict/buffer/text copy bytes | Realloc moved bytes (allocator observation) |
|---|---|---:|---:|
| csv_aggregate.large | checked-baseline | 0 / 0 / 0 / 786303 | 1193280 |
| csv_aggregate.large | checked-common | 0 / 0 / 0 / 269 | 1193280 |
| csv_aggregate.large | checked-candidate | 0 / 0 / 0 / 269 | 1193280 |
| csv_aggregate.small | checked-baseline | 0 / 0 / 0 / 756133 | 0 |
| csv_aggregate.small | checked-common | 0 / 0 / 0 / 29 | 0 |
| csv_aggregate.small | checked-candidate | 0 / 0 / 0 / 29 | 0 |
| json_transform.large | checked-baseline | 1266176 / 15210496 / 0 / 15426892 | 6697591 |
| json_transform.large | checked-common | 0 / 0 / 0 / 8708830 | 8818282 |
| json_transform.large | checked-candidate | 0 / 0 / 0 / 8708830 | 8818282 |
| json_transform.small | checked-baseline | 1099936 / 13200256 / 0 / 13218735 | 0 |
| json_transform.small | checked-common | 0 / 0 / 0 / 7601552 | 0 |
| json_transform.small | checked-candidate | 0 / 0 / 0 / 7601552 | 0 |
| string_split.large | checked-baseline | 0 / 0 / 0 / 25362900 | 0 |
| string_split.large | checked-common | 0 / 0 / 0 / 13940 | 0 |
| string_split.large | checked-candidate | 0 / 0 / 0 / 13940 | 0 |
| string_split.small | checked-baseline | 0 / 0 / 0 / 23121300 | 0 |
| string_split.small | checked-common | 0 / 0 / 0 / 228 | 0 |
| string_split.small | checked-candidate | 0 / 0 / 0 / 228 | 0 |

Representation/library policies differ: MyLang split returns owned API results and optimized immediate consumers can eliminate fragment materialization; Rust/Zig use borrowed slices. Foreign managed counters unavailable. All15samples retained; paired10000-resample intervals are exploratory single-session95%CIs, not causal attribution to an individual change. Kernel times exclude process startup; process_wall_ns raw values retained separately. No aggregate score, no censored ratio inference.

Concurrent-work limitation: bootstrap analysis ran on CPU0 without admission during log-boundUTC09:40:56.969985–09:41:06.331041. Archive compression also ran CPU0 without admission: tar birth09:44:41.099428, finalwrite09:44:45.020575. Verification followed09:44:45.036491 and completed before subsequent handoffcreation09:47:03.617796; exact finish was not logged, so this is a conservative upperbound. These are filesystem bounds, not explicit process-clock receipts. Ownmicro cells finished09:39:19.139149 before this work, but coordinator application samples may overlap. CPU0affinity does not exclude shared-cache/memory/I/O effects; retain allsamples and review overlap/noise flags. No reruns performed. concurrent-analysis-context.json preserves these limitations; future substantial archive work requires admission or application completion.
