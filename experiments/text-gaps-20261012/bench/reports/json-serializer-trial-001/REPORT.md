# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| json_transform/large | checked-baseline | 344.261 | 1.048 [0.891, 1.277] | 1.536 [1.215, 1.620] | 2.234 [1.666, 2.407] | 0.407 [0.379, 0.605] |
| json_transform/large | checked-common | 171.873 | 0.523 [0.464, 0.738] | 0.767 [0.596, 0.968] | 1.115 [0.836, 1.419] | 0.203 [0.184, 0.314] |
| json_transform/large | checked-candidate | 172.726 | 0.526 [0.452, 0.586] | 0.771 [0.565, 0.920] | 1.121 [0.794, 1.340] | 0.204 [0.171, 0.303] |
| json_transform/small | checked-baseline | 14.244 | 1.221 [1.212, 1.235] | 1.710 [1.688, 1.741] | 2.039 [2.017, 2.062] | 0.470 [0.469, 0.475] |
| json_transform/small | checked-common | 7.612 | 0.652 [0.646, 0.657] | 0.914 [0.901, 0.926] | 1.089 [1.077, 1.101] | 0.251 [0.250, 0.253] |
| json_transform/small | checked-candidate | 7.371 | 0.632 [0.625, 0.638] | 0.885 [0.873, 0.901] | 1.055 [1.040, 1.072] | 0.243 [0.242, 0.246] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| json_transform/large | 471 | target | 55.75 | False | checked-baseline, checked-common, checked-candidate, zig-safe, zig-fast, rust, go |
| json_transform/small | 7923 | target | 56.12 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| json_transform/large | checked-baseline | 2372 [2372, 2372] | 287408 | 344168080 | 4614183 |
| json_transform/large | checked-common | 2152 [2148, 2152] | 213464 | 125321968 | 1135906 |
| json_transform/large | checked-candidate | 2216 [2216, 2216] | 213464 | 125321968 | 1135906 |
| json_transform/large | zig-safe | 2864 [2864, 2864] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2640 [2640, 2640] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2720 [2688, 2724] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8384 [8216, 8780] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 2052 [2052, 2052] | 18592 | 358030056 | 4904734 |
| json_transform/small | checked-common | 1832 [1828, 1832] | 13728 | 134384328 | 1307369 |
| json_transform/small | checked-candidate | 1832 [1832, 1832] | 13728 | 134384328 | 1307369 |
| json_transform/small | zig-safe | 2532 [2532, 2532] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2320 [2320, 2320] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2368 [2356, 2376] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8224 [8224, 8224] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ. MyLang split returns owned results at the API level; optimized immediate consumers can eliminate fragment materialization. Rust/Zig use borrowed slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
