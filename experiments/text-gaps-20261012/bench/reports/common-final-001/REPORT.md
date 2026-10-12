# Fresh text-gap comparison

All 6 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| csv_aggregate/large | checked-baseline | 78.722 | 1.047 [1.035, 1.061] | 1.303 [1.279, 1.317] | 1.019 [1.002, 1.031] | 0.853 [0.835, 0.863] |
| csv_aggregate/large | checked-candidate | 55.000 | 0.731 [0.727, 0.741] | 0.910 [0.895, 0.918] | 0.712 [0.703, 0.721] | 0.596 [0.586, 0.601] |
| csv_aggregate/small | checked-baseline | 4.710 | 1.139 [1.126, 1.151] | 1.438 [1.394, 1.445] | 1.032 [1.022, 1.043] | 0.814 [0.804, 0.822] |
| csv_aggregate/small | checked-candidate | 3.281 | 0.794 [0.781, 0.802] | 1.002 [0.966, 1.013] | 0.719 [0.709, 0.730] | 0.567 [0.557, 0.576] |
| json_transform/large | checked-baseline | 256.030 | 1.109 [1.098, 1.115] | 1.440 [1.407, 1.446] | 2.114 [2.094, 2.123] | 0.480 [0.474, 0.486] |
| json_transform/large | checked-candidate | 131.846 | 0.571 [0.565, 0.576] | 0.742 [0.727, 0.746] | 1.089 [1.075, 1.096] | 0.247 [0.243, 0.250] |
| json_transform/small | checked-baseline | 14.960 | 1.225 [1.214, 1.235] | 1.718 [1.705, 1.733] | 2.018 [1.995, 2.044] | 0.473 [0.466, 0.475] |
| json_transform/small | checked-candidate | 8.054 | 0.660 [0.652, 0.667] | 0.925 [0.916, 0.933] | 1.086 [1.066, 1.105] | 0.254 [0.251, 0.256] |
| string_split/large | checked-baseline | 70.586 | 1.117 [1.108, 1.126] | 1.190 [1.183, 1.198] | 2.412 [2.356, 2.429] | 1.020 [1.012, 1.029] |
| string_split/large | checked-candidate | 28.170 | 0.446 [0.443, 0.449] | 0.475 [0.473, 0.479] | 0.963 [0.940, 0.973] | 0.407 [0.405, 0.411] |
| string_split/small | checked-baseline | 1.493 | 1.172 [1.149, 1.189] | 1.281 [1.258, 1.300] | 2.097 [2.061, 2.137] | 1.147 [1.123, 1.167] |
| string_split/small | checked-candidate | 0.565 | 0.443 [0.434, 0.455] | 0.485 [0.475, 0.496] | 0.794 [0.774, 0.818] | 0.434 [0.419, 0.445] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| csv_aggregate/large | 892 | near_target_growth | 49.70 | True | none |
| csv_aggregate/small | 15014 | target | 50.10 | False | none |
| json_transform/large | 428 | target | 53.91 | False | none |
| json_transform/small | 7901 | target | 56.34 | False | none |
| string_split/large | 1863 | target | 52.31 | False | none |
| string_split/small | 99085 | near_target_growth | 48.49 | True | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| csv_aggregate/large | checked-baseline | 1988 [1984, 1988] | 118160 | 187379376 | 2887258 |
| csv_aggregate/large | checked-candidate | 1988 [1988, 1992] | 118064 | 105498736 | 1607873 |
| csv_aggregate/large | zig-safe | 2704 [2704, 2704] | unavailable | unavailable | unavailable |
| csv_aggregate/large | zig-fast | 2492 [2488, 2492] | unavailable | unavailable | unavailable |
| csv_aggregate/large | rust | 2524 [2520, 2532] | unavailable | unavailable | unavailable |
| csv_aggregate/large | go | 7976 [7936, 8040] | unavailable | unavailable | unavailable |
| csv_aggregate/small | checked-baseline | 1828 [1824, 1828] | 8192 | 200358432 | 3093053 |
| csv_aggregate/small | checked-candidate | 1832 [1832, 1832] | 8096 | 114837600 | 1756790 |
| csv_aggregate/small | zig-safe | 2544 [2544, 2544] | unavailable | unavailable | unavailable |
| csv_aggregate/small | zig-fast | 2332 [2328, 2332] | unavailable | unavailable | unavailable |
| csv_aggregate/small | rust | 2564 [2432, 2708] | unavailable | unavailable | unavailable |
| csv_aggregate/small | go | 8096 [7880, 8096] | unavailable | unavailable | unavailable |
| json_transform/large | checked-baseline | 2308 [2308, 2308] | 287408 | 312798376 | 4193471 |
| json_transform/large | checked-candidate | 2152 [2152, 2152] | 213464 | 113892568 | 1032276 |
| json_transform/large | zig-safe | 2864 [2864, 2864] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2652 [2648, 2652] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2684 [2656, 2688] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8288 [8288, 8408] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 1988 [1988, 1988] | 18592 | 357036008 | 4891116 |
| json_transform/small | checked-candidate | 1832 [1832, 1832] | 13728 | 134011208 | 1303739 |
| json_transform/small | zig-safe | 2544 [2540, 2544] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2332 [2332, 2332] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2376 [2364, 2400] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8288 [8128, 8448] | unavailable | unavailable | unavailable |
| string_split/large | checked-baseline | 2340 [2340, 2340] | 401440 | 612786160 | 7644276 |
| string_split/large | checked-candidate | 2332 [2332, 2332] | 401312 | 122504112 | 5975 |
| string_split/large | zig-safe | 2508 [2508, 2508] | unavailable | unavailable | unavailable |
| string_split/large | zig-fast | 2492 [2488, 2492] | unavailable | unavailable | unavailable |
| string_split/large | rust | 2692 [2684, 2720] | unavailable | unavailable | unavailable |
| string_split/large | go | 7680 [7680, 7680] | unavailable | unavailable | unavailable |
| string_split/small | checked-baseline | 1860 [1856, 1860] | 7528 | 612747848 | 6836946 |
| string_split/small | checked-candidate | 1852 [1852, 1852] | 7944 | 206895624 | 99165 |
| string_split/small | zig-safe | 2348 [2348, 2348] | unavailable | unavailable | unavailable |
| string_split/small | zig-fast | 2332 [2332, 2332] | unavailable | unavailable | unavailable |
| string_split/small | rust | 2388 [2364, 2432] | unavailable | unavailable | unavailable |
| string_split/small | go | 8000 [7840, 8160] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ. MyLang split returns owned results at the API level; optimized immediate consumers can eliminate fragment materialization. Rust/Zig use borrowed slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
