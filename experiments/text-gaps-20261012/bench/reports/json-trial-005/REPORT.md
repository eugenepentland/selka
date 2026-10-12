# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| json_transform/large | checked-baseline | 245.728 | 1.116 [1.023, 1.199] | 1.441 [1.389, 1.558] | 2.121 [2.062, 2.269] | 0.482 [0.473, 0.505] |
| json_transform/large | checked-candidate | 134.924 | 0.613 [0.611, 0.632] | 0.791 [0.772, 0.908] | 1.165 [1.150, 1.321] | 0.265 [0.258, 0.297] |
| json_transform/small | checked-baseline | 13.836 | 1.220 [1.205, 1.231] | 1.699 [1.676, 1.714] | 2.029 [2.003, 2.038] | 0.470 [0.467, 0.472] |
| json_transform/small | checked-candidate | 7.794 | 0.688 [0.679, 0.694] | 0.957 [0.946, 0.968] | 1.143 [1.128, 1.153] | 0.265 [0.263, 0.267] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| json_transform/large | 473 | target | 58.77 | False | checked-baseline, checked-candidate, zig-safe, zig-fast, rust, go |
| json_transform/small | 7941 | target | 54.13 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| json_transform/large | checked-baseline | 2304 [2304, 2304] | 287408 | 345627136 | 4633751 |
| json_transform/large | checked-candidate | 2152 [2148, 2152] | 213528 | 133619648 | 1262071 |
| json_transform/large | zig-safe | 2852 [2852, 2852] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2640 [2636, 2640] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2676 [2676, 2684] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8500 [8160, 8504] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 1984 [1984, 1984] | 18592 | 358843368 | 4915876 |
| json_transform/small | checked-candidate | 1988 [1832, 1992] | 13792 | 142822280 | 1437412 |
| json_transform/small | zig-safe | 2532 [2532, 2532] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2320 [2320, 2320] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2400 [2392, 2428] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8000 [8000, 8320] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ, including owned MyLang split fragments versus borrowed Rust/Zig slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
