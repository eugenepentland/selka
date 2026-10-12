# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| csv_aggregate/large | checked-baseline | 74.258 | 1.049 [1.033, 1.066] | 1.309 [1.282, 1.320] | 1.022 [0.986, 1.033] | 0.845 [0.833, 0.856] |
| csv_aggregate/large | checked-common | 51.762 | 0.731 [0.721, 0.744] | 0.913 [0.902, 0.925] | 0.712 [0.691, 0.721] | 0.589 [0.581, 0.599] |
| csv_aggregate/large | checked-candidate | 49.668 | 0.701 [0.696, 0.716] | 0.876 [0.867, 0.888] | 0.684 [0.664, 0.693] | 0.565 [0.560, 0.577] |
| csv_aggregate/small | checked-baseline | 4.314 | 1.135 [1.127, 1.142] | 1.433 [1.428, 1.442] | 1.033 [1.028, 1.039] | 0.811 [0.806, 0.817] |
| csv_aggregate/small | checked-common | 3.034 | 0.798 [0.788, 0.804] | 1.008 [0.999, 1.016] | 0.726 [0.719, 0.732] | 0.570 [0.563, 0.575] |
| csv_aggregate/small | checked-candidate | 2.933 | 0.771 [0.764, 0.782] | 0.975 [0.970, 0.989] | 0.702 [0.697, 0.711] | 0.551 [0.547, 0.560] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| csv_aggregate/large | 1018 | target | 52.11 | False | none |
| csv_aggregate/small | 17324 | target | 51.14 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| csv_aggregate/large | checked-baseline | 2052 [2052, 2052] | 118160 | 213822240 | 3294742 |
| csv_aggregate/large | checked-common | 1992 [1988, 1992] | 118064 | 120377824 | 1834673 |
| csv_aggregate/large | checked-candidate | 1988 [1988, 1992] | 118064 | 120377824 | 1834673 |
| csv_aggregate/large | zig-safe | 2704 [2704, 2704] | unavailable | unavailable | unavailable |
| csv_aggregate/large | zig-fast | 2492 [2492, 2492] | unavailable | unavailable | unavailable |
| csv_aggregate/large | rust | 2544 [2540, 2608] | unavailable | unavailable | unavailable |
| csv_aggregate/large | go | 7928 [7780, 8100] | unavailable | unavailable | unavailable |
| csv_aggregate/small | checked-baseline | 1892 [1888, 1892] | 8192 | 231183072 | 3568913 |
| csv_aggregate/small | checked-common | 1832 [1832, 1832] | 8096 | 132504480 | 2027060 |
| csv_aggregate/small | checked-candidate | 1832 [1832, 1832] | 8096 | 132504480 | 2027060 |
| csv_aggregate/small | zig-safe | 2544 [2528, 2544] | unavailable | unavailable | unavailable |
| csv_aggregate/small | zig-fast | 2332 [2328, 2332] | unavailable | unavailable | unavailable |
| csv_aggregate/small | rust | 2388 [2380, 2548] | unavailable | unavailable | unavailable |
| csv_aggregate/small | go | 7780 [7460, 7928] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ. MyLang split returns owned results at the API level; optimized immediate consumers can eliminate fragment materialization. Rust/Zig use borrowed slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
