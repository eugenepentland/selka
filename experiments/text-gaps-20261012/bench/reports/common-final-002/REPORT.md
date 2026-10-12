# Fresh text-gap comparison

All 6 selected cells passed oracle, identity, round-order, RSS and counted ownership validation.

Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.

| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |
| --- | --- | ---: | --- | --- | --- | --- |
| csv_aggregate/large | checked-baseline | 73.521 | 1.050 [1.010, 1.071] | 1.291 [1.277, 1.329] | 1.014 [1.006, 1.042] | 0.840 [0.825, 0.859] |
| csv_aggregate/large | checked-common | 52.241 | 0.746 [0.723, 0.755] | 0.917 [0.898, 0.938] | 0.721 [0.706, 0.737] | 0.597 [0.581, 0.611] |
| csv_aggregate/large | checked-candidate | 49.454 | 0.706 [0.673, 0.718] | 0.868 [0.857, 0.889] | 0.682 [0.662, 0.695] | 0.565 [0.550, 0.575] |
| csv_aggregate/small | checked-baseline | 4.538 | 1.142 [1.121, 1.162] | 1.440 [1.412, 1.477] | 1.039 [1.021, 1.059] | 0.823 [0.809, 0.839] |
| csv_aggregate/small | checked-common | 3.114 | 0.783 [0.777, 0.806] | 0.988 [0.978, 1.018] | 0.713 [0.702, 0.731] | 0.565 [0.557, 0.578] |
| csv_aggregate/small | checked-candidate | 3.066 | 0.771 [0.761, 0.788] | 0.973 [0.962, 0.993] | 0.702 [0.692, 0.719] | 0.556 [0.547, 0.568] |
| json_transform/large | checked-baseline | 255.474 | 1.108 [1.084, 1.125] | 1.434 [1.332, 1.460] | 2.104 [2.011, 2.133] | 0.476 [0.450, 0.486] |
| json_transform/large | checked-common | 129.400 | 0.561 [0.553, 0.576] | 0.726 [0.647, 0.740] | 1.066 [1.027, 1.092] | 0.241 [0.230, 0.249] |
| json_transform/large | checked-candidate | 123.205 | 0.534 [0.523, 0.543] | 0.692 [0.620, 0.701] | 1.015 [0.933, 1.028] | 0.230 [0.221, 0.235] |
| json_transform/small | checked-baseline | 14.622 | 1.217 [1.208, 1.227] | 1.713 [1.693, 1.717] | 2.044 [2.007, 2.053] | 0.470 [0.465, 0.474] |
| json_transform/small | checked-common | 7.866 | 0.655 [0.646, 0.660] | 0.922 [0.904, 0.925] | 1.099 [1.072, 1.105] | 0.253 [0.248, 0.255] |
| json_transform/small | checked-candidate | 7.412 | 0.617 [0.610, 0.626] | 0.869 [0.853, 0.880] | 1.036 [1.011, 1.058] | 0.238 [0.234, 0.243] |
| string_split/large | checked-baseline | 69.256 | 1.103 [1.087, 1.118] | 1.170 [1.158, 1.185] | 2.398 [2.367, 2.437] | 1.015 [1.002, 1.027] |
| string_split/large | checked-common | 28.007 | 0.446 [0.442, 0.447] | 0.473 [0.469, 0.476] | 0.970 [0.960, 0.979] | 0.410 [0.404, 0.414] |
| string_split/large | checked-candidate | 27.972 | 0.445 [0.442, 0.447] | 0.473 [0.469, 0.476] | 0.969 [0.956, 0.982] | 0.410 [0.406, 0.414] |
| string_split/small | checked-baseline | 1.190 | 1.146 [1.139, 1.153] | 1.233 [1.226, 1.240] | 2.081 [2.071, 2.113] | 1.135 [1.129, 1.143] |
| string_split/small | checked-common | 0.485 | 0.467 [0.465, 0.471] | 0.503 [0.501, 0.506] | 0.849 [0.844, 0.863] | 0.463 [0.461, 0.466] |
| string_split/small | checked-candidate | 0.484 | 0.467 [0.463, 0.468] | 0.502 [0.497, 0.504] | 0.847 [0.840, 0.858] | 0.462 [0.458, 0.464] |

| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |
| --- | ---: | --- | ---: | --- | --- |
| csv_aggregate/large | 1050 | target | 51.24 | False | none |
| csv_aggregate/small | 16058 | target | 50.15 | False | none |
| json_transform/large | 455 | target | 52.88 | False | none |
| json_transform/small | 7935 | target | 57.07 | False | none |
| string_split/large | 1840 | target | 51.23 | False | none |
| string_split/small | 107425 | target | 52.28 | False | none |

Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.

| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| csv_aggregate/large | checked-baseline | 2052 [2048, 2052] | 118160 | 220537888 | 3398230 |
| csv_aggregate/large | checked-common | 1992 [1992, 1992] | 118064 | 124156640 | 1892273 |
| csv_aggregate/large | checked-candidate | 1992 [1992, 1992] | 118064 | 124156640 | 1892273 |
| csv_aggregate/large | zig-safe | 2692 [2692, 2692] | unavailable | unavailable | unavailable |
| csv_aggregate/large | zig-fast | 2480 [2480, 2480] | unavailable | unavailable | unavailable |
| csv_aggregate/large | rust | 2704 [2544, 2716] | unavailable | unavailable | unavailable |
| csv_aggregate/large | go | 7776 [7492, 7812] | unavailable | unavailable | unavailable |
| csv_aggregate/small | checked-baseline | 1892 [1888, 1892] | 8192 | 214289568 | 3308117 |
| csv_aggregate/small | checked-common | 1832 [1828, 1832] | 8096 | 122822112 | 1878938 |
| csv_aggregate/small | checked-candidate | 1832 [1832, 1832] | 8096 | 122822112 | 1878938 |
| csv_aggregate/small | zig-safe | 2532 [2532, 2532] | unavailable | unavailable | unavailable |
| csv_aggregate/small | zig-fast | 2320 [2316, 2320] | unavailable | unavailable | unavailable |
| csv_aggregate/small | rust | 2556 [2372, 2560] | unavailable | unavailable | unavailable |
| csv_aggregate/small | go | 7740 [7332, 7760] | unavailable | unavailable | unavailable |
| json_transform/large | checked-baseline | 2372 [2372, 2372] | 287408 | 332495632 | 4457639 |
| json_transform/large | checked-common | 2152 [2152, 2152] | 213464 | 121069168 | 1097346 |
| json_transform/large | checked-candidate | 2152 [2148, 2152] | 213464 | 121069168 | 1097346 |
| json_transform/large | zig-safe | 2852 [2852, 2852] | unavailable | unavailable | unavailable |
| json_transform/large | zig-fast | 2640 [2640, 2640] | unavailable | unavailable | unavailable |
| json_transform/large | rust | 2676 [2672, 2724] | unavailable | unavailable | unavailable |
| json_transform/large | go | 8544 [8224, 8596] | unavailable | unavailable | unavailable |
| json_transform/small | checked-baseline | 2052 [2052, 2052] | 18592 | 358572264 | 4912162 |
| json_transform/small | checked-common | 1992 [1832, 1992] | 13728 | 134587848 | 1309349 |
| json_transform/small | checked-candidate | 1992 [1832, 1992] | 13728 | 134587848 | 1309349 |
| json_transform/small | zig-safe | 2532 [2528, 2532] | unavailable | unavailable | unavailable |
| json_transform/small | zig-fast | 2320 [2320, 2320] | unavailable | unavailable | unavailable |
| json_transform/small | rust | 2368 [2360, 2368] | unavailable | unavailable | unavailable |
| json_transform/small | go | 8384 [8064, 8384] | unavailable | unavailable | unavailable |
| string_split/large | checked-baseline | 2340 [2340, 2340] | 401440 | 605225048 | 7549953 |
| string_split/large | checked-common | 2332 [2328, 2332] | 401312 | 120995864 | 5952 |
| string_split/large | checked-candidate | 2328 [2328, 2332] | 401312 | 120995864 | 5952 |
| string_split/large | zig-safe | 2496 [2496, 2496] | unavailable | unavailable | unavailable |
| string_split/large | zig-fast | 2476 [2476, 2476] | unavailable | unavailable | unavailable |
| string_split/large | rust | 2720 [2692, 2720] | unavailable | unavailable | unavailable |
| string_split/large | go | 7632 [7552, 7688] | unavailable | unavailable | unavailable |
| string_split/small | checked-baseline | 1860 [1860, 1860] | 7528 | 664322408 | 7412406 |
| string_split/small | checked-common | 1852 [1852, 1852] | 7944 | 224309544 | 107505 |
| string_split/small | checked-candidate | 1852 [1852, 1852] | 7944 | 224309544 | 107505 |
| string_split/small | zig-safe | 2336 [2336, 2336] | unavailable | unavailable | unavailable |
| string_split/small | zig-fast | 2316 [2312, 2316] | unavailable | unavailable | unavailable |
| string_split/small | rust | 2384 [2376, 2396] | unavailable | unavailable | unavailable |
| string_split/small | go | 7872 [7552, 7872] | unavailable | unavailable | unavailable |

Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.
Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.
Representation/library policies differ. MyLang split returns owned results at the API level; optimized immediate consumers can eliminate fragment materialization. Rust/Zig use borrowed slices. Ports remain unchanged.
Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.
