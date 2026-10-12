# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| csv_aggregate/large | checked-baseline | 67.228 | 1.047 [1.041, 1.054] | 1.294 [1.284, 1.308] | 1.004 [0.981, 1.017] | 0.831 [0.827, 0.836] |
| csv_aggregate/large | checked-candidate | 58.078 | 0.905 [0.900, 0.912] | 1.118 [1.109, 1.132] | 0.867 [0.851, 0.879] | 0.717 [0.714, 0.723] |
| csv_aggregate/small | checked-baseline | 4.161 | 1.143 [1.136, 1.148] | 1.442 [1.426, 1.448] | 1.039 [1.032, 1.045] | 0.810 [0.806, 0.813] |
| csv_aggregate/small | checked-candidate | 3.569 | 0.981 [0.971, 0.987] | 1.237 [1.226, 1.245] | 0.891 [0.881, 0.900] | 0.695 [0.688, 0.700] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| csv_aggregate/large | 990 | target | 50.73 | False | none |
| csv_aggregate/small | 16928 | near_target_growth | 49.34 | True | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| csv_aggregate/large | checked-baseline | 2052 [2052, 2052] | 118160 | 207946048 | 3204190 |
| csv_aggregate/large | checked-candidate | 1988 [1984, 1988] | 118160 | 126828864 | 1936734 |
| csv_aggregate/large | zig-safe | 2752 [2752, 2752] | unavailable | unavailable | unavailable |
| csv_aggregate/large | zig-fast | 2540 [2536, 2540] | unavailable | unavailable | unavailable |
| csv_aggregate/large | rust | 2580 [2548, 2720] | unavailable | unavailable | unavailable |
| csv_aggregate/large | go | 7936 [7688, 8008] | unavailable | unavailable | unavailable |
| csv_aggregate/small | checked-baseline | 1892 [1892, 1892] | 8192 | 225898848 | 3487337 |
| csv_aggregate/small | checked-candidate | 1824 [1824, 1828] | 8192 | 139226464 | 2133081 |
| csv_aggregate/small | zig-safe | 2592 [2592, 2592] | unavailable | unavailable | unavailable |
| csv_aggregate/small | zig-fast | 2380 [2380, 2380] | unavailable | unavailable | unavailable |
| csv_aggregate/small | rust | 2548 [2380, 2716] | unavailable | unavailable | unavailable |
| csv_aggregate/small | go | 8008 [7528, 8008] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ, including owned MyLang split fragments versus borrowed Rust/Zig slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
