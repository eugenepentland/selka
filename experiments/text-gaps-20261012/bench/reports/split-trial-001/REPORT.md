# Fresh text-gap comparison

All 2 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| string_split/large | checked-baseline | 65.222 | 1.057 [1.054, 1.067] | 1.133 [1.127, 1.139] | 2.390 [2.359, 2.402] | 0.990 [0.987, 0.995] |
| string_split/large | checked-candidate | 47.605 | 0.772 [0.769, 0.777] | 0.827 [0.823, 0.830] | 1.745 [1.723, 1.750] | 0.723 [0.720, 0.726] |
| string_split/small | checked-baseline | 1.132 | 1.104 [1.100, 1.114] | 1.187 [1.182, 1.201] | 2.097 [2.062, 2.120] | 1.100 [1.096, 1.112] |
| string_split/small | checked-candidate | 0.756 | 0.737 [0.734, 0.739] | 0.793 [0.790, 0.798] | 1.401 [1.379, 1.404] | 0.735 [0.732, 0.737] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| string_split/large | 1861 | target | 50.46 | False | none |
| string_split/small | 97550 | target | 52.74 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| string_split/large | checked-baseline | 2340 [2340, 2340] | 401440 | 612128672 | 7636074 |
| string_split/large | checked-candidate | 2212 [2212, 2212] | 335800 | 336088 | 4113 |
| string_split/large | zig-safe | 2556 [2552, 2556] | unavailable | unavailable | unavailable |
| string_split/large | zig-fast | 2552 [2552, 2552] | unavailable | unavailable | unavailable |
| string_split/large | rust | 2720 [2704, 2720] | unavailable | unavailable | unavailable |
| string_split/large | go | 7808 [7808, 7960] | unavailable | unavailable | unavailable |
| string_split/small | checked-baseline | 1860 [1856, 1860] | 7528 | 603255408 | 6731031 |
| string_split/small | checked-candidate | 1892 [1892, 1892] | 5920 | 6208 | 81 |
| string_split/small | zig-safe | 2396 [2392, 2396] | unavailable | unavailable | unavailable |
| string_split/small | zig-fast | 2392 [2392, 2392] | unavailable | unavailable | unavailable |
| string_split/small | rust | 2376 [2356, 2400] | unavailable | unavailable | unavailable |
| string_split/small | go | 7808 [7808, 8128] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ, including owned MyLang split fragments versus borrowed Rust/Zig slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
