# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| json_transform/large | checked-baseline | 227.158 | 1.095 [1.088, 1.104] | 1.386 [1.378, 1.397] | 2.103 [2.099, 2.121] | 0.471 [0.468, 0.476] |
| json_transform/large | checked-candidate | 188.397 | 0.908 [0.901, 0.912] | 1.149 [1.141, 1.157] | 1.744 [1.737, 1.755] | 0.391 [0.388, 0.393] |
| json_transform/small | checked-baseline | 13.569 | 1.220 [1.210, 1.225] | 1.687 [1.676, 1.702] | 2.019 [2.001, 2.030] | 0.465 [0.463, 0.467] |
| json_transform/small | checked-candidate | 11.258 | 1.012 [1.005, 1.015] | 1.400 [1.392, 1.410] | 1.675 [1.659, 1.684] | 0.386 [0.384, 0.387] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| json_transform/large | 485 | target | 52.25 | False | none |
| json_transform/small | 7902 | target | 53.42 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| json_transform/large | checked-baseline | 2372 [2368, 2372] | 287408 | 354381472 | 4751159 |
| json_transform/large | checked-candidate | 2312 [2312, 2312] | 287408 | 239001008 | 2453713 |
| json_transform/large | zig-safe | 2912 [2908, 2912] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2700 [2700, 2700] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2676 [2676, 2676] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8288 [8268, 8604] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 2052 [2052, 2052] | 18592 | 357081192 | 4891735 |
| json_transform/small | checked-candidate | 1988 [1988, 1992] | 18592 | 239751272 | 2544840 |
| json_transform/small | zig-safe | 2592 [2592, 2592] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2380 [2380, 2380] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2400 [2368, 2400] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8128 [7968, 8288] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ, including owned MyLang split fragments versus borrowed Rust/Zig slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
