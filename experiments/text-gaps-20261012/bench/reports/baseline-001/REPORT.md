# Fresh text-gap comparison

All six cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| csv_aggregate/large | checked-baseline | 65.371 | 1.067 [1.062, 1.072] | 1.307 [1.301, 1.313] | 1.018 [1.013, 1.022] | 0.821 [0.817, 0.829] |
| csv_aggregate/small | checked-baseline | 4.061 | 1.146 [1.140, 1.161] | 1.439 [1.429, 1.454] | 1.040 [1.037, 1.051] | 0.800 [0.797, 0.809] |
| json_transform/large | checked-baseline | 229.092 | 1.101 [1.097, 1.127] | 1.386 [1.378, 1.419] | 2.107 [2.089, 2.166] | 0.473 [0.469, 0.486] |
| json_transform/small | checked-baseline | 13.575 | 1.220 [1.214, 1.228] | 1.695 [1.674, 1.711] | 2.020 [1.996, 2.045] | 0.465 [0.462, 0.468] |
| string_split/large | checked-baseline | 65.456 | 1.065 [1.056, 1.069] | 1.138 [1.129, 1.144] | 2.413 [2.394, 2.425] | 0.997 [0.990, 1.001] |
| string_split/small | checked-baseline | 1.127 | 1.101 [1.093, 1.109] | 1.190 [1.178, 1.196] | 2.093 [2.073, 2.113] | 1.098 [1.091, 1.107] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| csv_aggregate/large | 1008 | target | 50.27 | False | none |
| csv_aggregate/small | 18228 | target | 51.23 | False | none |
| json_transform/large | 476 | target | 51.26 | False | none |
| json_transform/small | 7956 | target | 53.02 | False | none |
| string_split/large | 1968 | target | 52.98 | False | none |
| string_split/small | 103519 | target | 55.18 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| csv_aggregate/large | checked-baseline | 1988 [1984, 1988] | 118160 | 211723600 | 3262402 |
| csv_aggregate/large | zig-safe | 2756 [2756, 2756] | unavailable | unavailable | unavailable |
| csv_aggregate/large | zig-fast | 2540 [2536, 2540] | unavailable | unavailable | unavailable |
| csv_aggregate/large | rust | 2576 [2548, 2720] | unavailable | unavailable | unavailable |
| csv_aggregate/large | go | 7848 [7848, 7848] | unavailable | unavailable | unavailable |
| csv_aggregate/small | checked-baseline | 1828 [1824, 1828] | 8192 | 243246048 | 3755137 |
| csv_aggregate/small | zig-safe | 2596 [2592, 2596] | unavailable | unavailable | unavailable |
| csv_aggregate/small | zig-fast | 2380 [2380, 2380] | unavailable | unavailable | unavailable |
| csv_aggregate/small | rust | 2528 [2368, 2544] | unavailable | unavailable | unavailable |
| csv_aggregate/small | go | 7988 [7528, 8008] | unavailable | unavailable | unavailable |
| json_transform/large | checked-baseline | 2308 [2308, 2308] | 287408 | 347815720 | 4663103 |
| json_transform/large | zig-safe | 2916 [2916, 2916] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2700 [2696, 2700] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2716 [2696, 2724] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8632 [8212, 8704] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 1988 [1984, 1988] | 18592 | 359521128 | 4925161 |
| json_transform/small | zig-safe | 2596 [2596, 2596] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2380 [2380, 2380] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2404 [2360, 2404] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8288 [8128, 8288] | unavailable | unavailable | unavailable |
| string_split/large | checked-baseline | 2340 [2340, 2340] | 401440 | 647304280 | 8074881 |
| string_split/large | zig-safe | 2556 [2556, 2556] | unavailable | unavailable | unavailable |
| string_split/large | zig-fast | 2552 [2548, 2552] | unavailable | unavailable | unavailable |
| string_split/large | rust | 2696 [2688, 2716] | unavailable | unavailable | unavailable |
| string_split/large | go | 7808 [7808, 7808] | unavailable | unavailable | unavailable |
| string_split/small | checked-baseline | 1860 [1860, 1860] | 7528 | 640167704 | 7142892 |
| string_split/small | zig-safe | 2396 [2396, 2396] | unavailable | unavailable | unavailable |
| string_split/small | zig-fast | 2392 [2388, 2392] | unavailable | unavailable | unavailable |
| string_split/small | rust | 2400 [2388, 2400] | unavailable | unavailable | unavailable |
| string_split/small | go | 8128 [8060, 8128] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ, including owned MyLang split fragments versus borrowed Rust/Zig slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
