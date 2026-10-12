# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| json_transform/large | checked-baseline | 247.003 | 1.116 [1.104, 1.125] | 1.432 [1.415, 1.448] | 2.113 [2.086, 2.130] | 0.480 [0.476, 0.484] |
| json_transform/large | checked-common | 125.402 | 0.566 [0.563, 0.572] | 0.727 [0.721, 0.735] | 1.073 [1.064, 1.084] | 0.244 [0.242, 0.247] |
| json_transform/large | checked-candidate | 124.329 | 0.562 [0.559, 0.569] | 0.721 [0.712, 0.732] | 1.064 [1.056, 1.076] | 0.242 [0.240, 0.244] |
| json_transform/small | checked-baseline | 14.154 | 1.214 [1.206, 1.226] | 1.699 [1.677, 1.715] | 2.012 [1.986, 2.059] | 0.466 [0.462, 0.471] |
| json_transform/small | checked-common | 7.646 | 0.656 [0.651, 0.675] | 0.918 [0.909, 0.936] | 1.087 [1.073, 1.130] | 0.252 [0.250, 0.259] |
| json_transform/small | checked-candidate | 7.581 | 0.651 [0.643, 0.655] | 0.910 [0.894, 0.915] | 1.078 [1.061, 1.100] | 0.250 [0.246, 0.252] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| json_transform/large | 473 | target | 56.01 | False | none |
| json_transform/small | 7551 | target | 53.91 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| json_transform/large | checked-baseline | 2372 [2372, 2372] | 287408 | 345627136 | 4633751 |
| json_transform/large | checked-common | 2152 [2152, 2152] | 213464 | 125853568 | 1140726 |
| json_transform/large | checked-candidate | 2216 [2216, 2216] | 213464 | 125853568 | 1140726 |
| json_transform/large | zig-safe | 2864 [2860, 2864] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2652 [2652, 2652] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2684 [2676, 2692] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8480 [8380, 8608] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 2052 [2052, 2052] | 18592 | 341221608 | 4674466 |
| json_transform/small | checked-common | 1992 [1832, 1992] | 13728 | 128075208 | 1245989 |
| json_transform/small | checked-candidate | 1896 [1896, 2056] | 13728 | 128075208 | 1245989 |
| json_transform/small | zig-safe | 2544 [2544, 2544] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2332 [2332, 2332] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2356 [2356, 2416] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8000 [8000, 8320] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ. MyLang split returns owned results at the API level; optimized immediate consumers can eliminate fragment materialization. Rust/Zig use borrowed slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
