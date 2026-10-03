# Runtime operation-family assessment

80% is a qualitative design aspiration for representative everyday-codebase breadth; no population percentage or CPU-time coverage is measured.

The saved baseline was independently verified: 40 cases, two sizes, all six configurations, 15 sample rounds and 3 warmups. No benchmark was rerun. This assessment adds no acceptance gate, population weighting or overall language score.

A paired 95% bootstrap interval wholly below 1 is faster than Go, wholly above 1 is slower, and containing 1 is overlapping. This is descriptive evidence, not an equivalence proof or acceptance threshold; multiple comparisons are not adjusted.

Counts describe these selected test/profile comparisons only, not percentages of real codebases or operation frequencies.

Baseline SHA256: `b595d9638e243e18692b5cef491c2b5273949c93ebf22a0ae604a08704c1d3f7`. Historical measurement sources: **verified_historical_sources** at `b725360f5f86ac67bc405db9407ae51c332a9931`. Current artifacts were not checked. Recorded compiler source revision: `6df58b02554401f9d37564cceffd14277a835ae1`; this tool does not independently establish compiler-source equivalence.

- alloc_short permits optimizer elimination of nonescaping allocations; fastest saved pilots are exceptionally short. It is not evidence for the cost of physical allocation.
- sort_int/sort_records use each language native sorting API and compare language/library policies, rather than one identical algorithm.
- Ownership, snapshot, copy-on-write, reference-counting, GC and allocator semantics differ as documented; equivalent observable behavior does not imply equivalent physical copying.
- Optimized default build policies use different instruction sets across arms. Rust default x86_64 and Go v1 differ from default Zig/Clang-derived host features.
- Paired intervals and raw spread describe the saved run. They do not guarantee performance on another machine, input, lifetime or workload.

## Eight operation families

Family counts include small and large profiles separately. Go is the reference, rather than a comparative win. Ranges and worst cases refer to individual median paired ratios, not a pooled average. Every cell below is ratio to Go [95% paired interval] and classification; exact per-iteration times and units follow in the appendix.

### numbers and branches

Covers: integer and exact floating-point arithmetic; predictable and mixed conditions; runtime-dependent loop work.

Limits: bounded integer ranges and exact dyadic floats; repeated warm fixtures; no broader numerical kernels or varied branch histories.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 8 | 0 | 1.299–1.696× | float_math / large (1.696×) |
| my-qbe | 0 | 0 | 8 | 0 | 5.787–10.004× | float_math / large (10.004×) |
| rust | 6 | 0 | 2 | 0 | 0.508–1.045× | float_math / large (1.045×) |
| go | 0 | 0 | 0 | 8 | 1.000–1.000× | Go reference |
| zig-safe | 2 | 1 | 5 | 0 | 0.979–1.210× | branch_mixed / small (1.210×) |
| zig-fast | 8 | 0 | 0 | 0 | 0.501–0.903× | integer_math / small (0.903×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| integer_math / small | 1.604× [1.600–1.607] slower | 7.885× [7.863–7.913] slower | 0.757× [0.754–0.760] faster | 1.000× [1.000–1.000] reference | 1.017× [1.009–1.020] slower | 0.903× [0.897–0.904] faster |
| integer_math / large | 1.632× [1.628–1.636] slower | 8.341× [8.323–8.355] slower | 0.737× [0.735–0.740] faster | 1.000× [1.000–1.000] reference | 0.994× [0.990–0.998] faster | 0.893× [0.890–0.894] faster |
| float_math / small | 1.652× [1.647–1.658] slower | 9.488× [9.451–9.533] slower | 1.039× [1.037–1.043] slower | 1.000× [1.000–1.000] reference | 1.000× [0.999–1.002] overlapping | 0.680× [0.677–0.681] faster |
| float_math / large | 1.696× [1.690–1.698] slower | 10.004× [9.982–10.040] slower | 1.045× [1.044–1.048] slower | 1.000× [1.000–1.000] reference | 0.979× [0.978–0.983] faster | 0.660× [0.656–0.663] faster |
| branch_predictable / small | 1.586× [1.577–1.606] slower | 7.017× [7.008–7.038] slower | 0.522× [0.519–0.526] faster | 1.000× [1.000–1.000] reference | 1.173× [1.168–1.176] slower | 0.522× [0.519–0.526] faster |
| branch_predictable / large | 1.604× [1.602–1.608] slower | 6.856× [6.846–6.868] slower | 0.508× [0.505–0.511] faster | 1.000× [1.000–1.000] reference | 1.137× [1.134–1.138] slower | 0.501× [0.499–0.503] faster |
| branch_mixed / small | 1.460× [1.447–1.467] slower | 6.844× [6.805–6.858] slower | 0.672× [0.668–0.679] faster | 1.000× [1.000–1.000] reference | 1.210× [1.207–1.220] slower | 0.673× [0.669–0.679] faster |
| branch_mixed / large | 1.299× [1.293–1.306] slower | 5.787× [5.779–5.801] slower | 0.581× [0.580–0.586] faster | 1.000× [1.000–1.000] reference | 1.099× [1.095–1.102] slower | 0.585× [0.584–0.588] faster |

### lists and iteration

Covers: list scans; dynamic growth; filtering; unique mutation.

Limits: small warm working sets; limited record/list shape variety; no large cache-miss-heavy traversal.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 8 | 0 | 1.203–1.606× | list_scan / small (1.606×) |
| my-qbe | 0 | 0 | 8 | 0 | 2.631–8.268× | mutate_unique / small (8.268×) |
| rust | 8 | 0 | 0 | 0 | 0.512–0.870× | mutate_unique / small (0.870×) |
| go | 0 | 0 | 0 | 8 | 1.000–1.000× | Go reference |
| zig-safe | 2 | 0 | 6 | 0 | 0.742–1.441× | list_scan / large (1.441×) |
| zig-fast | 4 | 1 | 3 | 0 | 0.526–1.074× | mutate_unique / large (1.074×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| list_scan / small | 1.606× [1.578–1.642] slower | 4.592× [4.309–4.705] slower | 0.797× [0.764–0.846] faster | 1.000× [1.000–1.000] reference | 1.334× [1.301–1.360] slower | 1.011× [0.994–1.047] overlapping |
| list_scan / large | 1.304× [1.172–1.520] slower | 3.840× [3.626–4.027] slower | 0.822× [0.804–0.837] faster | 1.000× [1.000–1.000] reference | 1.441× [1.373–1.534] slower | 1.038× [1.002–1.157] slower |
| list_append / small | 1.517× [1.499–1.563] slower | 2.932× [2.884–2.957] slower | 0.736× [0.715–0.749] faster | 1.000× [1.000–1.000] reference | 1.144× [1.127–1.171] slower | 0.552× [0.532–0.567] faster |
| list_append / large | 1.205× [1.182–1.216] slower | 2.631× [2.583–2.677] slower | 0.566× [0.554–0.569] faster | 1.000× [1.000–1.000] reference | 1.082× [1.049–1.094] slower | 0.535× [0.528–0.549] faster |
| list_filter / small | 1.365× [1.362–1.378] slower | 2.646× [2.640–2.672] slower | 0.578× [0.575–0.580] faster | 1.000× [1.000–1.000] reference | 0.742× [0.740–0.745] faster | 0.526× [0.522–0.532] faster |
| list_filter / large | 1.203× [1.197–1.205] slower | 2.969× [2.951–2.998] slower | 0.512× [0.510–0.515] faster | 1.000× [1.000–1.000] reference | 0.925× [0.923–0.931] faster | 0.663× [0.659–0.670] faster |
| mutate_unique / small | 1.476× [1.468–1.481] slower | 8.268× [8.248–8.279] slower | 0.870× [0.868–0.875] faster | 1.000× [1.000–1.000] reference | 1.120× [1.116–1.125] slower | 1.071× [1.068–1.076] slower |
| mutate_unique / large | 1.476× [1.472–1.487] slower | 8.253× [8.242–8.265] slower | 0.870× [0.865–0.875] faster | 1.000× [1.000–1.000] reference | 1.114× [1.106–1.119] slower | 1.074× [1.066–1.075] slower |

### strings and bytes

Covers: bytes and UTF-8 text; equality and search; split and join; valid and malformed decimal conversion.

Limits: repetitive text and limited Unicode shapes; no large documents, normalization or regular expressions.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 7 | 0 | 7 | 0 | 0.158–3.979× | int_format / large (3.979×) |
| my-qbe | 3 | 0 | 11 | 0 | 0.153–19.087× | string_equal / large (19.087×) |
| rust | 11 | 0 | 3 | 0 | 0.186–2.012× | string_search / large (2.012×) |
| go | 0 | 0 | 0 | 14 | 1.000–1.000× | Go reference |
| zig-safe | 7 | 0 | 7 | 0 | 0.239–4.633× | string_search / large (4.633×) |
| zig-fast | 9 | 0 | 5 | 0 | 0.230–4.091× | string_search / large (4.091×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| bytes_scan / small | 0.362× [0.351–0.366] faster | 2.824× [2.729–2.966] slower | 0.745× [0.734–0.757] faster | 1.000× [1.000–1.000] reference | 1.150× [1.127–1.194] slower | 0.507× [0.495–0.539] faster |
| bytes_scan / large | 0.348× [0.346–0.352] faster | 3.339× [3.287–3.391] slower | 1.047× [1.043–1.061] slower | 1.000× [1.000–1.000] reference | 1.322× [1.320–1.368] slower | 0.694× [0.688–0.700] faster |
| string_equal / small | 3.553× [3.459–3.565] slower | 7.934× [7.777–8.070] slower | 0.666× [0.652–0.672] faster | 1.000× [1.000–1.000] reference | 0.907× [0.889–0.914] faster | 0.843× [0.824–0.854] faster |
| string_equal / large | 1.191× [1.166–1.204] slower | 19.087× [19.014–19.339] slower | 0.821× [0.810–0.831] faster | 1.000× [1.000–1.000] reference | 1.724× [1.704–1.737] slower | 1.342× [1.321–1.348] slower |
| string_search / small | 0.802× [0.796–0.807] faster | 1.228× [1.224–1.236] slower | 1.733× [1.720–1.741] slower | 1.000× [1.000–1.000] reference | 3.616× [3.599–3.625] slower | 3.025× [3.002–3.043] slower |
| string_search / large | 0.158× [0.158–0.159] faster | 0.153× [0.152–0.154] faster | 2.012× [2.009–2.015] slower | 1.000× [1.000–1.000] reference | 4.633× [4.631–4.644] slower | 4.091× [4.085–4.097] slower |
| string_split / small | 3.430× [3.402–3.481] slower | 4.234× [4.215–4.260] slower | 0.531× [0.525–0.540] faster | 1.000× [1.000–1.000] reference | 0.998× [0.989–0.999] faster | 0.921× [0.917–0.928] faster |
| string_split / large | 3.263× [3.258–3.295] slower | 4.019× [4.000–4.023] slower | 0.421× [0.419–0.425] faster | 1.000× [1.000–1.000] reference | 0.940× [0.937–0.942] faster | 0.882× [0.880–0.885] faster |
| string_join / small | 1.040× [1.032–1.045] slower | 1.367× [1.363–1.372] slower | 0.543× [0.540–0.545] faster | 1.000× [1.000–1.000] reference | 0.773× [0.766–0.779] faster | 0.664× [0.659–0.674] faster |
| string_join / large | 0.917× [0.912–0.919] faster | 1.115× [1.109–1.119] slower | 0.521× [0.518–0.526] faster | 1.000× [1.000–1.000] reference | 0.695× [0.691–0.699] faster | 0.647× [0.644–0.652] faster |
| int_parse / small | 0.419× [0.417–0.425] faster | 0.748× [0.745–0.751] faster | 0.186× [0.186–0.187] faster | 1.000× [1.000–1.000] reference | 0.239× [0.238–0.240] faster | 0.238× [0.238–0.239] faster |
| int_parse / large | 0.392× [0.389–0.394] faster | 0.694× [0.691–0.696] faster | 0.187× [0.187–0.187] faster | 1.000× [1.000–1.000] reference | 0.249× [0.248–0.249] faster | 0.230× [0.229–0.231] faster |
| int_format / small | 3.901× [3.882–3.946] slower | 5.458× [5.446–5.484] slower | 0.893× [0.889–0.909] faster | 1.000× [1.000–1.000] reference | 2.478× [2.458–2.494] slower | 1.997× [1.994–2.004] slower |
| int_format / large | 3.979× [3.947–3.991] slower | 5.177× [5.155–5.211] slower | 0.865× [0.854–0.892] faster | 1.000× [1.000–1.000] reference | 2.429× [2.407–2.438] slower | 2.046× [2.034–2.060] slower |

### dictionaries and sets

Covers: integer and string keys; lookup hits and misses; updates and growth; deduplication.

Limits: compact keys and repeated insertion patterns; no deletion/tombstones or large diverse-key workloads.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 10 | 0 | 1.055–3.212× | set_dedup / large (3.212×) |
| my-qbe | 0 | 0 | 10 | 0 | 1.797–4.246× | set_dedup / large (4.246×) |
| rust | 4 | 0 | 6 | 0 | 0.731–1.543× | dict_lookup_str / small (1.543×) |
| go | 0 | 0 | 0 | 10 | 1.000–1.000× | Go reference |
| zig-safe | 4 | 0 | 6 | 0 | 0.535–1.749× | dict_lookup / large (1.749×) |
| zig-fast | 7 | 0 | 3 | 0 | 0.254–1.377× | dict_lookup / large (1.377×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| dict_lookup / small | 1.140× [1.115–1.157] slower | 1.836× [1.782–1.880] slower | 1.361× [1.333–1.385] slower | 1.000× [1.000–1.000] reference | 1.080× [1.053–1.095] slower | 0.549× [0.540–0.558] faster |
| dict_lookup / large | 1.758× [1.743–1.787] slower | 2.568× [2.558–2.593] slower | 1.365× [1.350–1.379] slower | 1.000× [1.000–1.000] reference | 1.749× [1.735–1.770] slower | 1.377× [1.375–1.398] slower |
| dict_lookup_str / small | 1.055× [1.028–1.067] slower | 1.797× [1.777–1.836] slower | 1.543× [1.532–1.589] slower | 1.000× [1.000–1.000] reference | 0.939× [0.917–0.946] faster | 0.696× [0.688–0.711] faster |
| dict_lookup_str / large | 1.676× [1.664–1.702] slower | 2.391× [2.384–2.407] slower | 1.453× [1.448–1.472] slower | 1.000× [1.000–1.000] reference | 1.554× [1.544–1.563] slower | 1.220× [1.199–1.225] slower |
| dict_update / small | 1.829× [1.822–1.834] slower | 2.553× [2.540–2.560] slower | 0.731× [0.727–0.734] faster | 1.000× [1.000–1.000] reference | 0.595× [0.592–0.598] faster | 0.298× [0.295–0.299] faster |
| dict_update / large | 2.247× [2.233–2.259] slower | 2.920× [2.893–2.941] slower | 0.910× [0.904–0.915] faster | 1.000× [1.000–1.000] reference | 1.179× [1.169–1.184] slower | 0.849× [0.845–0.855] faster |
| dict_update_str / small | 1.455× [1.443–1.470] slower | 1.932× [1.912–1.936] slower | 1.391× [1.385–1.407] slower | 1.000× [1.000–1.000] reference | 0.672× [0.666–0.675] faster | 0.510× [0.503–0.522] faster |
| dict_update_str / large | 1.666× [1.658–1.672] slower | 2.041× [2.036–2.049] slower | 1.516× [1.508–1.538] slower | 1.000× [1.000–1.000] reference | 1.222× [1.211–1.234] slower | 1.066× [1.062–1.069] slower |
| set_dedup / small | 3.025× [2.989–3.041] slower | 4.129× [4.097–4.175] slower | 0.843× [0.837–0.846] faster | 1.000× [1.000–1.000] reference | 0.535× [0.531–0.538] faster | 0.254× [0.253–0.257] faster |
| set_dedup / large | 3.212× [3.185–3.231] slower | 4.246× [4.217–4.261] slower | 0.883× [0.877–0.890] faster | 1.000× [1.000–1.000] reference | 1.155× [1.148–1.159] slower | 0.804× [0.797–0.805] faster |

### records and calls

Covers: record reads, construction and updates; direct and runtime-selected calls.

Limits: small scalar records and helpers; no recursion, captured closures, FFI or managed-field record workloads.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 10 | 0 | 1.168–2.396× | call_direct / large (2.396×) |
| my-qbe | 0 | 0 | 10 | 0 | 2.376–14.525× | call_direct / large (14.525×) |
| rust | 10 | 0 | 0 | 0 | 0.595–0.844× | call_indirect / small (0.844×) |
| go | 0 | 0 | 0 | 10 | 1.000–1.000× | Go reference |
| zig-safe | 2 | 0 | 8 | 0 | 0.892–1.190× | call_indirect / small (1.190×) |
| zig-fast | 8 | 0 | 2 | 0 | 0.595–1.068× | record_reads / small (1.068×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| record_reads / small | 1.168× [1.166–1.173] slower | 2.376× [2.360–2.380] slower | 0.832× [0.828–0.833] faster | 1.000× [1.000–1.000] reference | 1.151× [1.146–1.153] slower | 1.068× [1.066–1.070] slower |
| record_reads / large | 1.235× [1.233–1.240] slower | 2.609× [2.585–2.647] slower | 0.824× [0.823–0.833] faster | 1.000× [1.000–1.000] reference | 1.151× [1.136–1.158] slower | 1.022× [1.015–1.030] slower |
| record_construct / small | 1.774× [1.768–1.778] slower | 6.988× [6.972–6.994] slower | 0.725× [0.724–0.727] faster | 1.000× [1.000–1.000] reference | 1.078× [1.076–1.085] slower | 0.919× [0.916–0.923] faster |
| record_construct / large | 1.791× [1.790–1.793] slower | 7.278× [7.246–7.370] slower | 0.708× [0.706–0.718] faster | 1.000× [1.000–1.000] reference | 1.055× [1.054–1.061] slower | 0.940× [0.931–0.943] faster |
| record_update / small | 1.950× [1.944–1.953] slower | 10.071× [10.048–10.125] slower | 0.722× [0.720–0.726] faster | 1.000× [1.000–1.000] reference | 1.130× [1.122–1.133] slower | 0.914× [0.909–0.917] faster |
| record_update / large | 1.973× [1.964–1.977] slower | 10.505× [10.437–10.540] slower | 0.694× [0.689–0.696] faster | 1.000× [1.000–1.000] reference | 1.103× [1.099–1.113] slower | 0.927× [0.914–0.935] faster |
| call_direct / small | 2.070× [2.067–2.071] slower | 11.720× [11.694–11.755] slower | 0.692× [0.690–0.693] faster | 1.000× [1.000–1.000] reference | 0.970× [0.969–0.974] faster | 0.751× [0.749–0.752] faster |
| call_direct / large | 2.396× [2.389–2.403] slower | 14.525× [14.449–14.546] slower | 0.595× [0.594–0.598] faster | 1.000× [1.000–1.000] reference | 0.892× [0.888–0.893] faster | 0.595× [0.595–0.599] faster |
| call_indirect / small | 1.245× [1.237–1.249] slower | 5.667× [5.643–5.685] slower | 0.844× [0.842–0.850] faster | 1.000× [1.000–1.000] reference | 1.190× [1.189–1.197] slower | 0.766× [0.765–0.773] faster |
| call_indirect / large | 1.242× [1.219–1.256] slower | 5.850× [5.836–5.879] slower | 0.843× [0.838–0.845] faster | 1.000× [1.000–1.000] reference | 1.183× [1.175–1.190] slower | 0.734× [0.728–0.737] faster |

### optional values and errors

Covers: optional values; success and error propagation; tagged operand-stack values.

Limits: fixed variant shapes and error mixes; no large recursive variants or complex unwinding.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 6 | 0 | 1.850–4.154× | tagged_stack / large (4.154×) |
| my-qbe | 0 | 0 | 6 | 0 | 5.248–10.756× | option_handle / large (10.756×) |
| rust | 6 | 0 | 0 | 0 | 0.367–0.952× | tagged_stack / small (0.952×) |
| go | 0 | 0 | 0 | 6 | 1.000–1.000× | Go reference |
| zig-safe | 2 | 1 | 3 | 0 | 0.845–1.775× | tagged_stack / large (1.775×) |
| zig-fast | 4 | 0 | 2 | 0 | 0.560–1.773× | tagged_stack / small (1.773×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| tagged_stack / small | 4.153× [4.142–4.162] slower | 5.250× [5.243–5.255] slower | 0.952× [0.949–0.953] faster | 1.000× [1.000–1.000] reference | 1.758× [1.751–1.777] slower | 1.773× [1.764–1.776] slower |
| tagged_stack / large | 4.154× [4.147–4.164] slower | 5.248× [5.237–5.260] slower | 0.950× [0.949–0.952] faster | 1.000× [1.000–1.000] reference | 1.775× [1.761–1.781] slower | 1.771× [1.768–1.775] slower |
| option_handle / small | 1.850× [1.839–1.859] slower | 10.390× [10.340–10.480] slower | 0.467× [0.464–0.468] faster | 1.000× [1.000–1.000] reference | 1.070× [1.063–1.078] slower | 0.825× [0.825–0.827] faster |
| option_handle / large | 1.933× [1.914–1.942] slower | 10.756× [10.590–10.796] slower | 0.367× [0.366–0.371] faster | 1.000× [1.000–1.000] reference | 1.018× [0.998–1.022] overlapping | 0.810× [0.804–0.813] faster |
| result_propagate / small | 1.857× [1.850–1.862] slower | 8.518× [8.493–8.531] slower | 0.476× [0.473–0.478] faster | 1.000× [1.000–1.000] reference | 0.845× [0.835–0.851] faster | 0.560× [0.555–0.561] faster |
| result_propagate / large | 1.885× [1.878–1.890] slower | 8.768× [8.759–8.790] slower | 0.417× [0.414–0.420] faster | 1.000× [1.000–1.000] reference | 0.858× [0.852–0.861] faster | 0.619× [0.613–0.624] faster |

### allocation and ownership

Covers: short and retained dynamic lists; shared snapshots; nested mutation preserving prior values.

Limits: short-allocation work may be optimized away; no long-lived mixed-lifetime heap churn or tail-latency evidence; snapshot costs include native COW versus explicit cloning.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 3 | 0 | 5 | 0 | 0.393–36.430× | alloc_short / large (36.430×) |
| my-qbe | 3 | 0 | 5 | 0 | 0.483–48.808× | alloc_short / large (48.808×) |
| rust | 6 | 0 | 2 | 0 | 0.116–1.155× | mutate_nested / large (1.155×) |
| go | 0 | 0 | 0 | 8 | 1.000–1.000× | Go reference |
| zig-safe | 4 | 0 | 4 | 0 | 0.252–2.683× | alloc_short / large (2.683×) |
| zig-fast | 7 | 0 | 1 | 0 | 0.002–1.050× | mutate_nested / large (1.050×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| alloc_short / small | 31.346× [31.187–31.619] slower | 41.825× [41.531–42.238] slower | 0.544× [0.534–0.554] faster | 1.000× [1.000–1.000] reference | 2.289× [2.285–2.338] slower | 0.026× [0.025–0.026] faster |
| alloc_short / large | 36.430× [36.152–36.911] slower | 48.808× [48.451–49.571] slower | 0.617× [0.601–0.624] faster | 1.000× [1.000–1.000] reference | 2.683× [2.675–2.741] slower | 0.002× [0.002–0.002] faster |
| alloc_retained / small | 1.561× [1.550–1.568] slower | 2.343× [2.331–2.359] slower | 0.712× [0.710–0.716] faster | 1.000× [1.000–1.000] reference | 0.689× [0.685–0.700] faster | 0.667× [0.665–0.672] faster |
| alloc_retained / large | 1.767× [1.753–1.775] slower | 2.580× [2.561–2.589] slower | 0.807× [0.801–0.819] faster | 1.000× [1.000–1.000] reference | 0.801× [0.794–0.803] faster | 0.774× [0.766–0.780] faster |
| mutate_shared / small | 2.161× [2.144–2.173] slower | 3.052× [3.039–3.070] slower | 0.198× [0.196–0.200] faster | 1.000× [1.000–1.000] reference | 0.296× [0.294–0.299] faster | 0.191× [0.189–0.192] faster |
| mutate_shared / large | 0.393× [0.390–0.395] faster | 0.490× [0.487–0.492] faster | 0.116× [0.115–0.117] faster | 1.000× [1.000–1.000] reference | 0.252× [0.250–0.253] faster | 0.196× [0.196–0.198] faster |
| mutate_nested / small | 0.644× [0.643–0.646] faster | 0.750× [0.747–0.755] faster | 1.012× [1.008–1.015] slower | 1.000× [1.000–1.000] reference | 1.024× [1.020–1.037] slower | 0.945× [0.934–0.976] faster |
| mutate_nested / large | 0.410× [0.407–0.414] faster | 0.483× [0.482–0.491] faster | 1.155× [1.146–1.161] slower | 1.000× [1.000–1.000] reference | 1.142× [1.138–1.152] slower | 1.050× [1.043–1.052] slower |

### sorting and searching

Covers: native integer sorting; native stable record sorting; binary search.

Limits: specific library APIs and input patterns; Go sort.Slice/sort.SliceStable, not generic slices APIs; limited key distributions.

| Arm | Faster | Overlapping | Slower | Reference | Median ratio range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 4 | 0 | 2 | 0 | 0.049–1.234× | binary_search / large (1.234×) |
| my-qbe | 4 | 0 | 2 | 0 | 0.079–10.608× | binary_search / large (10.608×) |
| rust | 6 | 0 | 0 | 0 | 0.041–0.610× | binary_search / large (0.610×) |
| go | 0 | 0 | 0 | 6 | 1.000–1.000× | Go reference |
| zig-safe | 5 | 0 | 1 | 0 | 0.091–2.159× | binary_search / large (2.159×) |
| zig-fast | 6 | 0 | 0 | 0 | 0.073–0.835× | binary_search / large (0.835×) |

| Case / profile | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|
| sort_int / small | 0.262× [0.262–0.262] faster | 0.503× [0.502–0.506] faster | 0.213× [0.212–0.213] faster | 1.000× [1.000–1.000] reference | 0.252× [0.251–0.253] faster | 0.158× [0.157–0.160] faster |
| sort_int / large | 0.190× [0.189–0.191] faster | 0.243× [0.243–0.244] faster | 0.272× [0.271–0.272] faster | 1.000× [1.000–1.000] reference | 0.279× [0.278–0.280] faster | 0.193× [0.191–0.194] faster |
| sort_records / small | 0.165× [0.164–0.165] faster | 0.266× [0.266–0.268] faster | 0.091× [0.091–0.091] faster | 1.000× [1.000–1.000] reference | 0.108× [0.107–0.108] faster | 0.077× [0.077–0.079] faster |
| sort_records / large | 0.049× [0.049–0.049] faster | 0.079× [0.079–0.079] faster | 0.041× [0.041–0.041] faster | 1.000× [1.000–1.000] reference | 0.091× [0.091–0.092] faster | 0.073× [0.073–0.073] faster |
| binary_search / small | 1.185× [1.178–1.194] slower | 6.488× [6.446–6.536] slower | 0.512× [0.510–0.518] faster | 1.000× [1.000–1.000] reference | 0.778× [0.775–0.782] faster | 0.746× [0.742–0.749] faster |
| binary_search / large | 1.234× [1.227–1.236] slower | 10.608× [10.534–10.700] slower | 0.610× [0.606–0.613] faster | 1.000× [1.000–1.000] reference | 2.159× [2.148–2.166] slower | 0.835× [0.828–0.839] faster |

## Five composed applications

Large-profile whole-job median time in microseconds; paired ratio to Go and 95% interval. Each application keeps its own unit and interpretation. Both sizes appear in the full appendix.

| Application / large size | Unit | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| word_count / 256 | one complete tokenize/count/fold job | 21.140 µs; 2.116× [2.104–2.125] slower | 28.543 µs; 2.864× [2.853–2.873] slower | 3.892 µs; 0.391× [0.389–0.392] faster | 9.959 µs; 1.000× [1.000–1.000] reference | 3.129 µs; 0.314× [0.313–0.316] faster | 2.469 µs; 0.247× [0.246–0.248] faster |
| csv_aggregate / 256 | one complete CSV parse/validate/group/fold job | 396.749 µs; 4.791× [4.772–4.842] slower | 577.140 µs; 6.981× [6.935–7.038] slower | 68.713 µs; 0.837× [0.826–0.841] faster | 82.812 µs; 1.000× [1.000–1.000] reference | 66.520 µs; 0.806× [0.795–0.811] faster | 53.306 µs; 0.645× [0.641–0.650] faster |
| json_transform / 256 | one complete JSON parse/filter/transform/serialize/fold job | 3091.020 µs; 5.542× [5.513–5.684] slower | 4157.304 µs; 7.399× [7.266–7.599] slower | 124.234 µs; 0.231× [0.229–0.233] faster | 543.441 µs; 1.000× [1.000–1.000] reference | 230.414 µs; 0.440× [0.432–0.447] faster | 187.251 µs; 0.347× [0.339–0.349] faster |
| packet_decode / 256 | one complete pass over SIZE fixtures | 1.642 µs; 0.848× [0.815–0.863] faster | 8.290 µs; 4.147× [3.997–4.481] slower | 0.787 µs; 0.399× [0.382–0.409] faster | 1.951 µs; 1.000× [1.000–1.000] reference | 1.342 µs; 0.689× [0.647–0.719] faster | 0.658 µs; 0.336× [0.323–0.347] faster |
| lox_eval / 256 | one complete bytecode program execution with SIZE loop iterations | 75.794 µs; 6.018× [5.916–6.031] slower | 82.979 µs; 6.552× [6.496–6.594] slower | 10.664 µs; 0.840× [0.833–0.848] faster | 12.636 µs; 1.000× [1.000–1.000] reference | 30.533 µs; 2.416× [2.386–2.432] slower | 29.790 µs; 2.347× [2.334–2.369] slower |

word_count represents: text tokenization and dictionary counting.

word_count limits: five distinct words in an eight-token pattern; no high-cardinality corpus or streaming.

csv_aggregate represents: quote-aware text parsing, numeric validation and grouped aggregation.

csv_aggregate limits: declared CSV subset and repeated row shapes; no embedded newlines or large varied documents.

json_transform represents: native JSON parse, filter/rebuild and serialization.

json_transform limits: one schema and native library differences; no deep nesting, varied schemas or streaming.

packet_decode represents: byte decoding, validation and success/error handling.

packet_decode limits: fixed ten-byte format and validity mix; no networking or general protocol-throughput claim.

lox_eval represents: tagged values, operand stack, variables, control flow and function calls.

lox_eval limits: execution-only fixed bytecode subset; no complete frontend, classes, closures or dynamic name lookup.

## Calibration limits

37 profiles missed their requested fastest-arm target. The saved reason slowest_arm_budget also covers growth below 5%, even when close to the target; it does not establish that every such profile hit a hard time cap.

| Case / profile | Iterations | Fastest pilot ms | Slowest pilot ms | Reason |
|---|---:|---:|---:|---|
| record_reads / small | 10000000 | 37.864 | 106.017 | iteration_cap |
| record_reads / large | 10000000 | 38.990 | 123.382 | iteration_cap |
| mutate_unique / small | 10000000 | 29.052 | 273.471 | iteration_cap |
| mutate_unique / large | 10000000 | 29.590 | 271.880 | iteration_cap |
| integer_math / large | 9669 | 49.782 | 568.847 | slowest_arm_budget |
| branch_mixed / small | 711312 | 49.720 | 513.977 | slowest_arm_budget |
| record_construct / large | 7812 | 48.641 | 509.103 | slowest_arm_budget |
| call_direct / large | 21660 | 40.719 | 999.544 | slowest_arm_budget |
| call_indirect / small | 482451 | 49.026 | 361.925 | slowest_arm_budget |
| option_handle / small | 964568 | 44.882 | 998.494 | slowest_arm_budget |
| option_handle / large | 15196 | 33.952 | 999.181 | slowest_arm_budget |
| result_propagate / large | 14439 | 47.172 | 998.777 | slowest_arm_budget |
| list_scan / large | 19340 | 49.258 | 231.991 | slowest_arm_budget |
| list_filter / small | 349619 | 49.800 | 250.848 | slowest_arm_budget |
| dict_lookup / large | 1705 | 49.689 | 125.987 | slowest_arm_budget |
| dict_lookup_str / large | 1244 | 49.663 | 115.887 | slowest_arm_budget |
| dict_update / small | 20443 | 49.808 | 427.871 | slowest_arm_budget |
| dict_update / large | 115 | 49.486 | 168.342 | slowest_arm_budget |
| dict_update_str / small | 10133 | 49.885 | 186.051 | slowest_arm_budget |
| dict_update_str / large | 71 | 48.955 | 96.297 | slowest_arm_budget |
| set_dedup / small | 172180 | 49.454 | 796.426 | slowest_arm_budget |
| alloc_short / small | 166691 | 0.610 | 995.831 | slowest_arm_budget |
| alloc_short / large | 10638 | 0.046 | 992.193 | slowest_arm_budget |
| alloc_retained / small | 41122 | 49.626 | 174.727 | slowest_arm_budget |
| sort_int / large | 1121 | 49.432 | 258.941 | slowest_arm_budget |
| sort_records / large | 790 | 39.543 | 987.503 | slowest_arm_budget |
| bytes_scan / large | 142097 | 49.883 | 476.264 | slowest_arm_budget |
| string_equal / small | 10000000 | 30.480 | 358.490 | iteration_cap |
| string_equal / large | 1271218 | 38.927 | 902.769 | pilot_limit |
| string_search / large | 336110 | 33.102 | 999.961 | slowest_arm_budget |
| string_split / large | 1819 | 49.791 | 479.970 | slowest_arm_budget |
| int_parse / small | 10000000 | 44.676 | 239.408 | iteration_cap |
| int_parse / large | 9859222 | 49.796 | 266.548 | slowest_arm_budget |
| int_format / small | 3334872 | 49.075 | 296.245 | slowest_arm_budget |
| int_format / large | 3097187 | 47.622 | 283.436 | slowest_arm_budget |
| json_transform / small | 4732 | 32.028 | 996.356 | slowest_arm_budget |
| json_transform / large | 276 | 31.161 | 993.752 | slowest_arm_budget |

## Breadth gaps and excluded workloads

Confidence gaps: recursion and graph traversal; large working sets and cache-miss-heavy access; map deletion, high-cardinality and varied-length keys; long-lived mixed-lifetime allocation and reclamation; varied text, numeric and structured-data shapes; concurrency, synchronization, asynchronous scheduling and I/O.

Excluded workloads: filesystem and network waits; multithreading and scheduling; external database operations; compiler throughput; full Lox parser/classes/closures; production workload distributions.


## Full small/large appendix

Times are per documented CLI iteration, which may be a complete dataset/job rather than one scalar primitive. Raw observed min/max remain attached to each comparison. Lower ratios are faster; no units are pooled.

| Case / profile / size | Level | Unit | Arm | Median µs/iteration | Min–max µs | Paired ratio [95% interval] | Classification |
|---|---|---|---|---:|---:|---:|---|
| record_reads / small / 64 | micro | one contract operation | my-llvm | 0.005347 | 0.005326–0.005462 | 1.168× [1.166–1.173] | slower |
| record_reads / small / 64 | micro | one contract operation | my-qbe | 0.010861 | 0.010804–0.010974 | 2.376× [2.360–2.380] | slower |
| record_reads / small / 64 | micro | one contract operation | rust | 0.003798 | 0.003783–0.003816 | 0.832× [0.828–0.833] | faster |
| record_reads / small / 64 | micro | one contract operation | go | 0.004570 | 0.004558–0.004755 | 1.000× [1.000–1.000] | reference |
| record_reads / small / 64 | micro | one contract operation | zig-safe | 0.005258 | 0.005242–0.005284 | 1.151× [1.146–1.153] | slower |
| record_reads / small / 64 | micro | one contract operation | zig-fast | 0.004880 | 0.004867–0.004923 | 1.068× [1.066–1.070] | slower |
| record_reads / large / 4096 | micro | one contract operation | my-llvm | 0.005778 | 0.005667–0.005870 | 1.235× [1.233–1.240] | slower |
| record_reads / large / 4096 | micro | one contract operation | my-qbe | 0.012267 | 0.011897–0.012790 | 2.609× [2.585–2.647] | slower |
| record_reads / large / 4096 | micro | one contract operation | rust | 0.003872 | 0.003855–0.003891 | 0.824× [0.823–0.833] | faster |
| record_reads / large / 4096 | micro | one contract operation | go | 0.004702 | 0.004625–0.004749 | 1.000× [1.000–1.000] | reference |
| record_reads / large / 4096 | micro | one contract operation | zig-safe | 0.005369 | 0.005295–0.005492 | 1.151× [1.136–1.158] | slower |
| record_reads / large / 4096 | micro | one contract operation | zig-fast | 0.004807 | 0.004767–0.004874 | 1.022× [1.015–1.030] | slower |
| tagged_stack / small / 64 | micro | one contract operation | my-llvm | 0.024925 | 0.024788–0.025005 | 4.153× [4.142–4.162] | slower |
| tagged_stack / small / 64 | micro | one contract operation | my-qbe | 0.031481 | 0.031357–0.044096 | 5.250× [5.243–5.255] | slower |
| tagged_stack / small / 64 | micro | one contract operation | rust | 0.005705 | 0.005686–0.006091 | 0.952× [0.949–0.953] | faster |
| tagged_stack / small / 64 | micro | one contract operation | go | 0.005994 | 0.005986–0.006051 | 1.000× [1.000–1.000] | reference |
| tagged_stack / small / 64 | micro | one contract operation | zig-safe | 0.010539 | 0.010486–0.011735 | 1.758× [1.751–1.777] | slower |
| tagged_stack / small / 64 | micro | one contract operation | zig-fast | 0.010629 | 0.010567–0.010877 | 1.773× [1.764–1.776] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | my-llvm | 0.024921 | 0.024841–0.025033 | 4.154× [4.147–4.164] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | my-qbe | 0.031475 | 0.031318–0.031682 | 5.248× [5.237–5.260] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | rust | 0.005698 | 0.005684–0.005755 | 0.950× [0.949–0.952] | faster |
| tagged_stack / large / 4096 | micro | one contract operation | go | 0.005995 | 0.005981–0.006089 | 1.000× [1.000–1.000] | reference |
| tagged_stack / large / 4096 | micro | one contract operation | zig-safe | 0.010652 | 0.010497–0.010722 | 1.775× [1.761–1.781] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | zig-fast | 0.010613 | 0.010571–0.010897 | 1.771× [1.768–1.775] | slower |
| mutate_unique / small / 64 | micro | one contract operation | my-llvm | 0.004934 | 0.004890–0.004996 | 1.476× [1.468–1.481] | slower |
| mutate_unique / small / 64 | micro | one contract operation | my-qbe | 0.027666 | 0.027574–0.027885 | 8.268× [8.248–8.279] | slower |
| mutate_unique / small / 64 | micro | one contract operation | rust | 0.002911 | 0.002892–0.002940 | 0.870× [0.868–0.875] | faster |
| mutate_unique / small / 64 | micro | one contract operation | go | 0.003342 | 0.003327–0.003424 | 1.000× [1.000–1.000] | reference |
| mutate_unique / small / 64 | micro | one contract operation | zig-safe | 0.003747 | 0.003714–0.003964 | 1.120× [1.116–1.125] | slower |
| mutate_unique / small / 64 | micro | one contract operation | zig-fast | 0.003585 | 0.003571–0.003620 | 1.071× [1.068–1.076] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | my-llvm | 0.004947 | 0.004899–0.005112 | 1.476× [1.472–1.487] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | my-qbe | 0.027666 | 0.027507–0.027841 | 8.253× [8.242–8.265] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | rust | 0.002922 | 0.002892–0.002969 | 0.870× [0.865–0.875] | faster |
| mutate_unique / large / 1024 | micro | one contract operation | go | 0.003346 | 0.003335–0.003423 | 1.000× [1.000–1.000] | reference |
| mutate_unique / large / 1024 | micro | one contract operation | zig-safe | 0.003737 | 0.003718–0.003780 | 1.114× [1.106–1.119] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | zig-fast | 0.003593 | 0.003568–0.004700 | 1.074× [1.066–1.075] | slower |
| mutate_shared / small / 64 | micro | one contract operation | my-llvm | 0.117836 | 0.116804–0.120251 | 2.161× [2.144–2.173] | slower |
| mutate_shared / small / 64 | micro | one contract operation | my-qbe | 0.166507 | 0.165550–0.167892 | 3.052× [3.039–3.070] | slower |
| mutate_shared / small / 64 | micro | one contract operation | rust | 0.010826 | 0.010668–0.011249 | 0.198× [0.196–0.200] | faster |
| mutate_shared / small / 64 | micro | one contract operation | go | 0.054478 | 0.053979–0.055188 | 1.000× [1.000–1.000] | reference |
| mutate_shared / small / 64 | micro | one contract operation | zig-safe | 0.016133 | 0.015805–0.016526 | 0.296× [0.294–0.299] | faster |
| mutate_shared / small / 64 | micro | one contract operation | zig-fast | 0.010404 | 0.010206–0.010573 | 0.191× [0.189–0.192] | faster |
| mutate_shared / large / 1024 | micro | one contract operation | my-llvm | 0.230293 | 0.229166–0.231996 | 0.393× [0.390–0.395] | faster |
| mutate_shared / large / 1024 | micro | one contract operation | my-qbe | 0.285986 | 0.284568–0.289910 | 0.490× [0.487–0.492] | faster |
| mutate_shared / large / 1024 | micro | one contract operation | rust | 0.067633 | 0.067303–0.068802 | 0.116× [0.115–0.117] | faster |
| mutate_shared / large / 1024 | micro | one contract operation | go | 0.585297 | 0.578130–0.597169 | 1.000× [1.000–1.000] | reference |
| mutate_shared / large / 1024 | micro | one contract operation | zig-safe | 0.147212 | 0.146344–0.148548 | 0.252× [0.250–0.253] | faster |
| mutate_shared / large / 1024 | micro | one contract operation | zig-fast | 0.114702 | 0.114102–0.117959 | 0.196× [0.196–0.198] | faster |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.192705 | 0.191754–0.195007 | 1.604× [1.600–1.607] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.949251 | 0.946955–0.952197 | 7.885× [7.863–7.913] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.091171 | 0.090209–0.092307 | 0.757× [0.754–0.760] | faster |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.120381 | 0.119577–0.139852 | 1.000× [1.000–1.000] | reference |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.122313 | 0.121435–0.122822 | 1.017× [1.009–1.020] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.108300 | 0.107854–0.109226 | 0.903× [0.897–0.904] | faster |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 11.749879 | 11.732915–11.837052 | 1.632× [1.628–1.636] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 60.039210 | 59.868397–61.093201 | 8.341× [8.323–8.355] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 5.305529 | 5.272949–5.341601 | 0.737× [0.735–0.740] | faster |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | go | 7.203462 | 7.153455–7.268153 | 1.000× [1.000–1.000] | reference |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 7.138923 | 7.110526–7.247674 | 0.994× [0.990–0.998] | faster |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 6.410349 | 6.353946–6.506538 | 0.893× [0.890–0.894] | faster |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.172203 | 0.171772–0.173765 | 1.652× [1.647–1.658] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.989858 | 0.983979–1.006460 | 9.488× [9.451–9.533] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.108331 | 0.107864–0.109176 | 1.039× [1.037–1.043] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.104219 | 0.103820–0.104774 | 1.000× [1.000–1.000] | reference |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.104251 | 0.103378–0.105063 | 1.000× [0.999–1.002] | overlapping |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.070782 | 0.070265–0.074735 | 0.680× [0.677–0.681] | faster |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.588389 | 10.552745–10.614173 | 1.696× [1.690–1.698] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 62.601260 | 62.296268–63.193574 | 10.004× [9.982–10.040] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.535994 | 6.477919–6.575606 | 1.045× [1.044–1.048] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | go | 6.245548 | 6.218834–6.277262 | 1.000× [1.000–1.000] | reference |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 6.131444 | 6.097713–6.221732 | 0.979× [0.978–0.983] | faster |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.125319 | 4.091627–4.160860 | 0.660× [0.656–0.663] | faster |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.160090 | 0.153649–0.161662 | 1.586× [1.577–1.606] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.704839 | 0.703984–0.717072 | 7.017× [7.008–7.038] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.052478 | 0.051832–0.053433 | 0.522× [0.519–0.526] | faster |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.100504 | 0.099799–0.101141 | 1.000× [1.000–1.000] | reference |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.117958 | 0.117021–0.118918 | 1.173× [1.168–1.176] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.052455 | 0.051820–0.053131 | 0.522× [0.519–0.526] | faster |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.409001 | 10.359319–11.037683 | 1.604× [1.602–1.608] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 44.473554 | 44.413943–44.682942 | 6.856× [6.846–6.868] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 3.297517 | 3.249678–3.372168 | 0.508× [0.505–0.511] | faster |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | go | 6.487171 | 6.459352–6.502082 | 1.000× [1.000–1.000] | reference |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 7.360620 | 7.327128–7.410439 | 1.137× [1.134–1.138] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 3.244133 | 3.219684–3.329906 | 0.501× [0.499–0.503] | faster |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.154812 | 0.153584–0.156254 | 1.460× [1.447–1.467] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.726290 | 0.724196–0.729949 | 6.844× [6.805–6.858] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.071458 | 0.070953–0.072228 | 0.672× [0.668–0.679] | faster |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.106293 | 0.105139–0.107434 | 1.000× [1.000–1.000] | reference |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.128780 | 0.127340–0.129798 | 1.210× [1.207–1.220] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.071538 | 0.071064–0.071831 | 0.673× [0.669–0.679] | faster |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.382506 | 10.291656–10.538149 | 1.299× [1.293–1.306] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 46.189616 | 46.072686–46.306747 | 5.787× [5.779–5.801] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 4.653777 | 4.624084–4.699375 | 0.581× [0.580–0.586] | faster |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | go | 7.977431 | 7.931565–8.043350 | 1.000× [1.000–1.000] | reference |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 8.778942 | 8.701574–8.817611 | 1.099× [1.095–1.102] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.674686 | 4.658924–4.721610 | 0.585× [0.584–0.588] | faster |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.263024 | 0.261579–0.274428 | 1.774× [1.768–1.778] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.036736 | 1.034055–1.061848 | 6.988× [6.972–6.994] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.107642 | 0.106787–0.108246 | 0.725× [0.724–0.727] | faster |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.148511 | 0.147555–0.148746 | 1.000× [1.000–1.000] | reference |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.160053 | 0.158330–0.161339 | 1.078× [1.076–1.085] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.136662 | 0.134975–0.141740 | 0.919× [0.916–0.923] | faster |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 16.260138 | 16.231827–18.955625 | 1.791× [1.790–1.793] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 66.409317 | 65.617064–79.054219 | 7.278× [7.246–7.370] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.418310 | 6.317029–8.383817 | 0.708× [0.706–0.718] | faster |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | go | 9.089556 | 9.047254–10.332526 | 1.000× [1.000–1.000] | reference |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 9.586188 | 9.521103–11.233766 | 1.055× [1.054–1.061] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 8.538261 | 8.299855–8.877199 | 0.940× [0.931–0.943] | faster |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.293010 | 0.292036–0.294212 | 1.950× [1.944–1.953] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.512647 | 1.507554–1.531641 | 10.071× [10.048–10.125] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.108813 | 0.107983–0.109125 | 0.722× [0.720–0.726] | faster |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.150275 | 0.149081–0.173664 | 1.000× [1.000–1.000] | reference |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.169850 | 0.167619–0.171079 | 1.130× [1.122–1.133] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.137168 | 0.136289–0.140876 | 0.914× [0.909–0.917] | faster |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 18.148822 | 18.082666–18.523361 | 1.973× [1.964–1.977] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 96.629376 | 96.377048–97.901494 | 10.505× [10.437–10.540] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.385214 | 6.325509–6.431624 | 0.694× [0.689–0.696] | faster |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | go | 9.200067 | 9.155209–9.320884 | 1.000× [1.000–1.000] | reference |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 10.183884 | 10.109562–10.359739 | 1.103× [1.099–1.113] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 8.510524 | 8.321131–9.364473 | 0.927× [0.914–0.935] | faster |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.130449 | 0.129982–0.134730 | 2.070× [2.067–2.071] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.738973 | 0.734833–0.746920 | 11.720× [11.694–11.755] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.043636 | 0.043362–0.043805 | 0.692× [0.690–0.693] | faster |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.063032 | 0.062773–0.063451 | 1.000× [1.000–1.000] | reference |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.061246 | 0.060789–0.061526 | 0.970× [0.969–0.974] | faster |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.047309 | 0.046777–0.047520 | 0.751× [0.749–0.752] | faster |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 7.696961 | 7.681808–7.752065 | 2.396× [2.389–2.403] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 46.546155 | 46.471275–47.011000 | 14.525× [14.449–14.546] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 1.912433 | 1.898958–1.927066 | 0.595× [0.594–0.598] | faster |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | go | 3.212544 | 3.195632–3.229860 | 1.000× [1.000–1.000] | reference |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 2.860276 | 2.843208–2.875215 | 0.892× [0.888–0.893] | faster |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 1.915685 | 1.894055–1.926440 | 0.595× [0.595–0.599] | faster |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.166058 | 0.164394–0.171765 | 1.245× [1.237–1.249] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.755318 | 0.751618–0.778873 | 5.667× [5.643–5.685] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.112592 | 0.111779–0.115657 | 0.844× [0.842–0.850] | faster |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.133307 | 0.132574–0.138084 | 1.000× [1.000–1.000] | reference |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.158968 | 0.158044–0.180480 | 1.190× [1.189–1.197] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.102346 | 0.101646–0.103704 | 0.766× [0.765–0.773] | faster |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.101111 | 9.759967–10.348584 | 1.242× [1.219–1.256] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 47.432067 | 47.224255–47.969274 | 5.850× [5.836–5.879] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.818840 | 6.776822–6.973399 | 0.843× [0.838–0.845] | faster |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | go | 8.130980 | 7.976353–8.197193 | 1.000× [1.000–1.000] | reference |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 9.617974 | 9.578465–9.694659 | 1.183× [1.175–1.190] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 5.964501 | 5.861051–6.020392 | 0.734× [0.728–0.737] | faster |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.186275 | 0.179615–0.191190 | 1.850× [1.839–1.859] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.045043 | 1.036652–1.068586 | 10.390× [10.340–10.480] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.046928 | 0.046211–0.047148 | 0.467× [0.464–0.468] | faster |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.100554 | 0.100191–0.101709 | 1.000× [1.000–1.000] | reference |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.107772 | 0.106486–0.108694 | 1.070× [1.063–1.078] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.083105 | 0.081179–0.083431 | 0.825× [0.825–0.827] | faster |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 11.887652 | 11.805762–12.487106 | 1.933× [1.914–1.942] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 66.335723 | 66.021438–66.990915 | 10.756× [10.590–10.796] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 2.280723 | 2.252810–2.301438 | 0.367× [0.366–0.371] | faster |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | go | 6.168273 | 6.113385–6.289092 | 1.000× [1.000–1.000] | reference |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 6.266359 | 6.202591–6.578687 | 1.018× [0.998–1.022] | overlapping |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.993837 | 4.943862–5.053117 | 0.810× [0.804–0.813] | faster |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.238349 | 0.237270–0.248663 | 1.857× [1.850–1.862] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.093452 | 1.091478–1.106372 | 8.518× [8.493–8.531] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.061146 | 0.060551–0.061652 | 0.476× [0.473–0.478] | faster |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.128641 | 0.127482–0.130314 | 1.000× [1.000–1.000] | reference |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.108203 | 0.106780–0.109746 | 0.845× [0.835–0.851] | faster |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.072009 | 0.070940–0.072668 | 0.560× [0.555–0.561] | faster |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 14.950026 | 14.905583–15.298923 | 1.885× [1.878–1.890] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 69.574562 | 69.398186–70.075523 | 8.768× [8.759–8.790] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 3.312894 | 3.268359–3.349116 | 0.417× [0.414–0.420] | faster |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | go | 7.936098 | 7.904821–8.011889 | 1.000× [1.000–1.000] | reference |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 6.807218 | 6.729390–7.517787 | 0.858× [0.852–0.861] | faster |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.910073 | 4.803569–5.066655 | 0.619× [0.613–0.624] | faster |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | my-llvm | 0.118963 | 0.118488–0.120308 | 1.185× [1.178–1.194] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | my-qbe | 0.651689 | 0.647742–0.660896 | 6.488× [6.446–6.536] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | rust | 0.051678 | 0.051117–0.052189 | 0.512× [0.510–0.518] | faster |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | go | 0.100487 | 0.099043–0.101923 | 1.000× [1.000–1.000] | reference |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | zig-safe | 0.078241 | 0.077273–0.079126 | 0.778× [0.775–0.782] | faster |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | zig-fast | 0.074917 | 0.074540–0.075228 | 0.746× [0.742–0.749] | faster |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | my-llvm | 2.960449 | 2.947367–2.985492 | 1.234× [1.227–1.236] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | my-qbe | 25.487808 | 25.292795–25.881202 | 10.608× [10.534–10.700] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | rust | 1.465053 | 1.456156–1.472099 | 0.610× [0.606–0.613] | faster |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | go | 2.408317 | 2.384007–2.430817 | 1.000× [1.000–1.000] | reference |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | zig-safe | 5.192899 | 5.147432–5.220232 | 2.159× [2.148–2.166] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | zig-fast | 2.005368 | 1.988378–2.022163 | 0.835× [0.828–0.839] | faster |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | my-llvm | 0.101021 | 0.088804–0.125456 | 0.815× [0.792–0.841] | faster |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | my-qbe | 0.510565 | 0.436483–0.646296 | 4.108× [3.919–4.188] | slower |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | rust | 0.050895 | 0.044797–0.066864 | 0.415× [0.409–0.425] | faster |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | go | 0.126515 | 0.106154–0.157461 | 1.000× [1.000–1.000] | reference |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | zig-safe | 0.088118 | 0.073988–0.112292 | 0.702× [0.665–0.713] | faster |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | zig-fast | 0.046737 | 0.038550–0.056075 | 0.350× [0.348–0.384] | faster |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | my-llvm | 1.642064 | 1.564220–1.834406 | 0.848× [0.815–0.863] | faster |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | my-qbe | 8.289854 | 7.554027–9.033782 | 4.147× [3.997–4.481] | slower |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | rust | 0.787011 | 0.736534–0.838469 | 0.399× [0.382–0.409] | faster |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | go | 1.950685 | 1.827110–2.490381 | 1.000× [1.000–1.000] | reference |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | zig-safe | 1.341826 | 1.219492–1.726965 | 0.689× [0.647–0.719] | faster |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | zig-fast | 0.657970 | 0.638675–0.693757 | 0.336× [0.323–0.347] | faster |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.097029 | 0.094162–0.106421 | 1.606× [1.578–1.642] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.276329 | 0.266035–0.305045 | 4.592× [4.309–4.705] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.048475 | 0.045608–0.055936 | 0.797× [0.764–0.846] | faster |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.061060 | 0.058423–0.075253 | 1.000× [1.000–1.000] | reference |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.081493 | 0.078298–0.092001 | 1.334× [1.301–1.360] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.061390 | 0.058558–0.081685 | 1.011× [0.994–1.047] | overlapping |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 4.907286 | 4.580818–5.986948 | 1.304× [1.172–1.520] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 14.543074 | 13.662591–16.289529 | 3.840× [3.626–4.027] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 3.168305 | 2.752799–3.754718 | 0.822× [0.804–0.837] | faster |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | go | 3.787343 | 3.390372–4.644621 | 1.000× [1.000–1.000] | reference |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 5.583677 | 4.914296–6.766743 | 1.441× [1.373–1.534] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 3.832294 | 3.457328–5.069698 | 1.038× [1.002–1.157] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.387726 | 0.375732–0.396281 | 1.517× [1.499–1.563] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.740914 | 0.709612–0.807093 | 2.932× [2.884–2.957] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.184971 | 0.179250–0.192160 | 0.736× [0.715–0.749] | faster |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.252617 | 0.240809–0.267114 | 1.000× [1.000–1.000] | reference |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.289934 | 0.274746–0.309702 | 1.144× [1.127–1.171] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.137627 | 0.132819–0.151790 | 0.552× [0.532–0.567] | faster |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 13.829897 | 13.367929–14.154150 | 1.205× [1.182–1.216] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 30.378034 | 29.721807–31.418467 | 2.631× [2.583–2.677] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 6.526121 | 6.272476–7.050786 | 0.566× [0.554–0.569] | faster |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | go | 11.507343 | 11.111685–12.960203 | 1.000× [1.000–1.000] | reference |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 12.538219 | 11.996828–13.233674 | 1.082× [1.049–1.094] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 6.252465 | 5.855742–6.384041 | 0.535× [0.528–0.549] | faster |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.394648 | 0.390167–0.414366 | 1.365× [1.362–1.378] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.767658 | 0.760834–0.794603 | 2.646× [2.640–2.672] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.166869 | 0.165007–0.175093 | 0.578× [0.575–0.580] | faster |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.289041 | 0.287259–0.300968 | 1.000× [1.000–1.000] | reference |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.215339 | 0.212744–0.227067 | 0.742× [0.740–0.745] | faster |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.151847 | 0.149646–0.166328 | 0.526× [0.522–0.532] | faster |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 13.200490 | 13.127760–13.310690 | 1.203× [1.197–1.205] | slower |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 32.620213 | 32.374313–33.169240 | 2.969× [2.951–2.998] | slower |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 5.617805 | 5.562111–5.960629 | 0.512× [0.510–0.515] | faster |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | go | 10.973084 | 10.914254–11.205725 | 1.000× [1.000–1.000] | reference |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 10.153294 | 10.119610–10.279985 | 0.925× [0.923–0.931] | faster |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 7.292773 | 7.224573–7.550933 | 0.663× [0.659–0.670] | faster |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.518922 | 0.514858–0.532531 | 1.140× [1.115–1.157] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.835392 | 0.824148–0.865489 | 1.836× [1.782–1.880] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.623228 | 0.611799–0.646031 | 1.361× [1.333–1.385] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.460281 | 0.404676–0.474762 | 1.000× [1.000–1.000] | reference |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.492036 | 0.486508–0.497069 | 1.080× [1.053–1.095] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.252098 | 0.249769–0.253922 | 0.549× [0.540–0.558] | faster |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 52.693528 | 51.817611–54.385366 | 1.758× [1.743–1.787] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 77.152857 | 75.766499–77.727927 | 2.568× [2.558–2.593] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 40.688170 | 40.496917–41.290001 | 1.365× [1.350–1.379] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | go | 29.844554 | 29.440762–30.535072 | 1.000× [1.000–1.000] | reference |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 52.287567 | 51.502816–53.163798 | 1.749× [1.735–1.770] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 41.244549 | 40.812173–41.918633 | 1.377× [1.375–1.398] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.583534 | 0.577489–0.834205 | 1.055× [1.028–1.067] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 1.004668 | 1.001452–1.015405 | 1.797× [1.777–1.836] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.867826 | 0.852189–0.883996 | 1.543× [1.532–1.589] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.559186 | 0.538136–0.570795 | 1.000× [1.000–1.000] | reference |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.520346 | 0.514887–0.526091 | 0.939× [0.917–0.946] | faster |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.390639 | 0.387491–0.397357 | 0.696× [0.688–0.711] | faster |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 67.611924 | 66.620147–68.518422 | 1.676× [1.664–1.702] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 96.110971 | 95.678178–97.774801 | 2.391× [2.384–2.407] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 58.349514 | 57.471236–66.203668 | 1.453× [1.448–1.472] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | go | 40.213548 | 39.521159–40.910912 | 1.000× [1.000–1.000] | reference |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 62.646477 | 61.703606–63.941023 | 1.554× [1.544–1.563] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 49.028400 | 48.087553–49.968332 | 1.220× [1.199–1.225] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 15.249135 | 15.137220–15.571205 | 1.829× [1.822–1.834] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 21.271190 | 21.104892–21.782200 | 2.553× [2.540–2.560] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | rust | 6.096233 | 6.050791–6.229926 | 0.731× [0.727–0.734] | faster |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | go | 8.354001 | 8.153644–8.634723 | 1.000× [1.000–1.000] | reference |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 4.963520 | 4.873928–5.157785 | 0.595× [0.592–0.598] | faster |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 2.480908 | 2.458896–2.611547 | 0.298× [0.295–0.299] | faster |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 1146.283522 | 1138.439287–1175.669374 | 2.247× [2.233–2.259] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 1494.704426 | 1486.699191–1510.602226 | 2.920× [2.893–2.941] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 465.484000 | 459.779548–475.491217 | 0.910× [0.904–0.915] | faster |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | go | 510.847713 | 505.808713–528.861148 | 1.000× [1.000–1.000] | reference |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 600.634661 | 597.671035–619.386409 | 1.179× [1.169–1.184] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 434.066600 | 431.970887–440.488235 | 0.849× [0.845–0.855] | faster |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 14.128393 | 13.958477–14.460473 | 1.455× [1.443–1.470] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 18.691992 | 18.549229–19.064667 | 1.932× [1.912–1.936] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | rust | 13.520708 | 13.384818–13.973506 | 1.391× [1.385–1.407] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | go | 9.718816 | 9.548165–9.776346 | 1.000× [1.000–1.000] | reference |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 6.500960 | 6.455262–6.886654 | 0.672× [0.666–0.675] | faster |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 4.946870 | 4.835212–5.147636 | 0.510× [0.503–0.522] | faster |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 1134.125324 | 1128.169577–1141.103563 | 1.666× [1.658–1.672] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 1389.167197 | 1378.903169–1400.186958 | 2.041× [2.036–2.049] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 1032.946662 | 979.037620–1051.544606 | 1.516× [1.508–1.538] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | go | 680.597479 | 670.265211–688.141592 | 1.000× [1.000–1.000] | reference |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 828.660775 | 821.010183–841.907887 | 1.222× [1.211–1.234] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 724.441817 | 716.417239–732.950986 | 1.066× [1.062–1.069] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 3.438448 | 3.408387–3.481854 | 3.025× [2.989–3.041] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 4.700406 | 4.659676–5.434568 | 4.129× [4.097–4.175] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.955582 | 0.948947–1.010891 | 0.843× [0.837–0.846] | faster |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.138039 | 1.114885–1.184988 | 1.000× [1.000–1.000] | reference |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.607950 | 0.600737–0.667081 | 0.535× [0.531–0.538] | faster |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.288900 | 0.286682–0.344891 | 0.254× [0.253–0.257] | faster |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 220.853279 | 218.091425–224.600655 | 3.212× [3.185–3.231] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 292.050624 | 290.131026–296.362979 | 4.246× [4.217–4.261] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 61.052304 | 60.324826–62.513331 | 0.883× [0.877–0.890] | faster |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | go | 68.907769 | 68.465688–70.048182 | 1.000× [1.000–1.000] | reference |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 79.666972 | 79.370513–82.429078 | 1.155× [1.148–1.159] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 55.443204 | 54.990542–55.766476 | 0.804× [0.797–0.805] | faster |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 4.538856 | 4.502503–5.064882 | 31.346× [31.187–31.619] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 6.052979 | 6.002195–6.131194 | 41.825× [41.531–42.238] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.078138 | 0.075776–0.084522 | 0.544× [0.534–0.554] | faster |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.144844 | 0.141435–0.147699 | 1.000× [1.000–1.000] | reference |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.332753 | 0.328381–0.340079 | 2.289× [2.285–2.338] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.003745 | 0.003529–0.004127 | 0.026× [0.025–0.026] | faster |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | my-llvm | 70.329891 | 70.026282–70.953208 | 36.430× [36.152–36.911] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | my-qbe | 94.313391 | 93.663117–97.297726 | 48.808× [48.451–49.571] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | rust | 1.192876 | 1.147815–1.225761 | 0.617× [0.601–0.624] | faster |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | go | 1.933491 | 1.873820–1.974002 | 1.000× [1.000–1.000] | reference |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | zig-safe | 5.192662 | 5.155872–5.281318 | 2.683× [2.675–2.741] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | zig-fast | 0.003715 | 0.003690–0.004689 | 0.002× [0.002–0.002] | faster |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 2.823544 | 2.783429–2.858556 | 1.561× [1.550–1.568] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 4.248896 | 4.211015–4.335933 | 2.343× [2.331–2.359] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | rust | 1.290242 | 1.269383–1.309687 | 0.712× [0.710–0.716] | faster |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.812933 | 1.789856–1.822735 | 1.000× [1.000–1.000] | reference |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 1.245983 | 1.225771–1.316111 | 0.689× [0.685–0.700] | faster |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 1.207437 | 1.193840–1.277185 | 0.667× [0.665–0.672] | faster |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | my-llvm | 44.919344 | 44.505053–45.355082 | 1.767× [1.753–1.775] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | my-qbe | 65.667291 | 65.038699–66.559270 | 2.580× [2.561–2.589] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | rust | 20.588485 | 20.351041–21.206318 | 0.807× [0.801–0.819] | faster |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | go | 25.445855 | 25.174425–25.854379 | 1.000× [1.000–1.000] | reference |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | zig-safe | 20.442672 | 19.990476–20.915713 | 0.801× [0.794–0.803] | faster |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | zig-fast | 19.669600 | 19.474230–20.275376 | 0.774× [0.766–0.780] | faster |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.746951 | 0.743765–0.767033 | 0.644× [0.643–0.646] | faster |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.870354 | 0.865068–0.880132 | 0.750× [0.747–0.755] | faster |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | rust | 1.173336 | 1.160039–1.216407 | 1.012× [1.008–1.015] | slower |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.160251 | 1.143612–1.190173 | 1.000× [1.000–1.000] | reference |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 1.187669 | 1.173509–1.260868 | 1.024× [1.020–1.037] | slower |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 1.097470 | 1.066189–1.177013 | 0.945× [0.934–0.976] | faster |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | my-llvm | 7.131864 | 7.047165–7.212595 | 0.410× [0.407–0.414] | faster |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | my-qbe | 8.423610 | 8.272391–8.596646 | 0.483× [0.482–0.491] | faster |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | rust | 20.093748 | 19.711181–20.948217 | 1.155× [1.146–1.161] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | go | 17.374169 | 17.204728–17.915328 | 1.000× [1.000–1.000] | reference |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | zig-safe | 19.898725 | 19.705410–20.285184 | 1.142× [1.138–1.152] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | zig-fast | 18.171501 | 17.941106–18.718541 | 1.050× [1.043–1.052] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.278555 | 0.277652–0.280964 | 0.262× [0.262–0.262] | faster |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.535166 | 0.532113–0.539260 | 0.503× [0.502–0.506] | faster |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.226090 | 0.224134–0.232662 | 0.213× [0.212–0.213] | faster |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.064548 | 1.058134–1.069040 | 1.000× [1.000–1.000] | reference |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.268392 | 0.267132–0.269502 | 0.252× [0.251–0.253] | faster |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.168408 | 0.162707–0.171256 | 0.158× [0.157–0.160] | faster |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 44.236096 | 43.981024–44.599008 | 0.190× [0.189–0.191] | faster |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 56.625583 | 56.394649–56.951887 | 0.243× [0.243–0.244] | faster |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 63.128697 | 62.973009–63.389690 | 0.272× [0.271–0.272] | faster |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | go | 232.509963 | 231.934770–234.672319 | 1.000× [1.000–1.000] | reference |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 64.987206 | 64.281153–65.681913 | 0.279× [0.278–0.280] | faster |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 44.883897 | 44.521495–45.229922 | 0.193× [0.191–0.194] | faster |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 1.201025 | 1.193473–1.229869 | 0.165× [0.164–0.165] | faster |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 1.936476 | 1.928154–2.049764 | 0.266× [0.266–0.268] | faster |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.662666 | 0.659666–0.691894 | 0.091× [0.091–0.091] | faster |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | go | 7.276274 | 7.243401–7.308134 | 1.000× [1.000–1.000] | reference |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.783526 | 0.777360–0.809957 | 0.108× [0.107–0.108] | faster |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.562819 | 0.555685–0.582483 | 0.077× [0.077–0.079] | faster |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 61.564986 | 60.782515–62.203752 | 0.049× [0.049–0.049] | faster |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 99.196706 | 98.441356–99.801028 | 0.079× [0.079–0.079] | faster |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 51.816163 | 50.606986–52.428659 | 0.041× [0.041–0.041] | faster |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | go | 1259.208020 | 1250.843823–1274.320156 | 1.000× [1.000–1.000] | reference |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 115.154033 | 114.564141–118.119429 | 0.091× [0.091–0.092] | faster |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 92.222970 | 91.257039–93.724396 | 0.073× [0.073–0.073] | faster |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 5.022591 | 5.000789–5.117619 | 6.195× [6.081–6.237] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 5.622215 | 5.581530–5.676234 | 6.912× [6.831–6.964] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | rust | 0.717446 | 0.709752–0.733109 | 0.881× [0.878–0.896] | faster |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | go | 0.811824 | 0.805464–0.832602 | 1.000× [1.000–1.000] | reference |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 1.979158 | 1.962691–2.137206 | 2.434× [2.408–2.463] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 1.920326 | 1.915799–1.941165 | 2.373× [2.357–2.382] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 75.793706 | 75.370103–81.777047 | 6.018× [5.916–6.031] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 82.979434 | 82.499577–85.337014 | 6.552× [6.496–6.594] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | rust | 10.663957 | 10.558434–11.198932 | 0.840× [0.833–0.848] | faster |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | go | 12.636007 | 12.524790–13.347812 | 1.000× [1.000–1.000] | reference |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 30.532537 | 30.204245–34.114986 | 2.416× [2.386–2.432] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 29.790073 | 29.427315–33.176441 | 2.347× [2.334–2.369] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | my-llvm | 0.008584 | 0.008489–0.008844 | 0.362× [0.351–0.366] | faster |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | my-qbe | 0.067104 | 0.066451–0.067851 | 2.824× [2.729–2.966] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | rust | 0.017677 | 0.017485–0.017801 | 0.745× [0.734–0.757] | faster |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | go | 0.023797 | 0.022452–0.025868 | 1.000× [1.000–1.000] | reference |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | zig-safe | 0.027821 | 0.026511–0.028624 | 1.150× [1.127–1.194] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | zig-fast | 0.012115 | 0.011873–0.012708 | 0.507× [0.495–0.539] | faster |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | my-llvm | 0.354322 | 0.352110–0.359734 | 0.348× [0.346–0.352] | faster |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | my-qbe | 3.365649 | 3.349289–3.404748 | 3.339× [3.287–3.391] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | rust | 1.062588 | 1.059031–1.070593 | 1.047× [1.043–1.061] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | go | 1.015552 | 0.983385–1.043996 | 1.000× [1.000–1.000] | reference |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | zig-safe | 1.332787 | 1.301821–1.449408 | 1.322× [1.320–1.368] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | zig-fast | 0.701500 | 0.694144–0.724749 | 0.694× [0.688–0.700] | faster |
| string_equal / small / 64 | micro | one string equality comparison | my-llvm | 0.015973 | 0.015816–0.017229 | 3.553× [3.459–3.565] | slower |
| string_equal / small / 64 | micro | one string equality comparison | my-qbe | 0.036159 | 0.035810–0.036473 | 7.934× [7.777–8.070] | slower |
| string_equal / small / 64 | micro | one string equality comparison | rust | 0.003014 | 0.002985–0.003183 | 0.666× [0.652–0.672] | faster |
| string_equal / small / 64 | micro | one string equality comparison | go | 0.004544 | 0.004446–0.004883 | 1.000× [1.000–1.000] | reference |
| string_equal / small / 64 | micro | one string equality comparison | zig-safe | 0.004100 | 0.004079–0.004155 | 0.907× [0.889–0.914] | faster |
| string_equal / small / 64 | micro | one string equality comparison | zig-fast | 0.003833 | 0.003812–0.003887 | 0.843× [0.824–0.854] | faster |
| string_equal / large / 4096 | micro | one string equality comparison | my-llvm | 0.044741 | 0.044146–0.045692 | 1.191× [1.166–1.204] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | my-qbe | 0.719654 | 0.718259–0.723891 | 19.087× [19.014–19.339] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | rust | 0.030934 | 0.030655–0.032733 | 0.821× [0.810–0.831] | faster |
| string_equal / large / 4096 | micro | one string equality comparison | go | 0.037661 | 0.036921–0.038552 | 1.000× [1.000–1.000] | reference |
| string_equal / large / 4096 | micro | one string equality comparison | zig-safe | 0.065006 | 0.064713–0.065106 | 1.724× [1.704–1.737] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | zig-fast | 0.050498 | 0.050203–0.056745 | 1.342× [1.321–1.348] | slower |
| string_search / small / 64 | micro | one substring search | my-llvm | 0.019868 | 0.019754–0.020526 | 0.802× [0.796–0.807] | faster |
| string_search / small / 64 | micro | one substring search | my-qbe | 0.030441 | 0.030334–0.030994 | 1.228× [1.224–1.236] | slower |
| string_search / small / 64 | micro | one substring search | rust | 0.042948 | 0.042553–0.043372 | 1.733× [1.720–1.741] | slower |
| string_search / small / 64 | micro | one substring search | go | 0.024878 | 0.024502–0.025238 | 1.000× [1.000–1.000] | reference |
| string_search / small / 64 | micro | one substring search | zig-safe | 0.089753 | 0.089531–0.090168 | 3.616× [3.599–3.625] | slower |
| string_search / small / 64 | micro | one substring search | zig-fast | 0.074835 | 0.074550–0.078400 | 3.025× [3.002–3.043] | slower |
| string_search / large / 4096 | micro | one substring search | my-llvm | 0.102400 | 0.101344–0.104497 | 0.158× [0.158–0.159] | faster |
| string_search / large / 4096 | micro | one substring search | my-qbe | 0.098385 | 0.097235–0.099388 | 0.153× [0.152–0.154] | faster |
| string_search / large / 4096 | micro | one substring search | rust | 1.297969 | 1.293860–1.311773 | 2.012× [2.009–2.015] | slower |
| string_search / large / 4096 | micro | one substring search | go | 0.644747 | 0.642029–0.662546 | 1.000× [1.000–1.000] | reference |
| string_search / large / 4096 | micro | one substring search | zig-safe | 2.986394 | 2.980326–3.555604 | 4.633× [4.631–4.644] | slower |
| string_search / large / 4096 | micro | one substring search | zig-fast | 2.635363 | 2.628279–2.663317 | 4.091× [4.085–4.097] | slower |
| string_split / small / 64 | micro | one full document split and result fold | my-llvm | 3.562898 | 3.533588–3.755087 | 3.430× [3.402–3.481] | slower |
| string_split / small / 64 | micro | one full document split and result fold | my-qbe | 4.414834 | 4.382319–4.529585 | 4.234× [4.215–4.260] | slower |
| string_split / small / 64 | micro | one full document split and result fold | rust | 0.551926 | 0.545457–0.580980 | 0.531× [0.525–0.540] | faster |
| string_split / small / 64 | micro | one full document split and result fold | go | 1.039326 | 1.033963–1.062956 | 1.000× [1.000–1.000] | reference |
| string_split / small / 64 | micro | one full document split and result fold | zig-safe | 1.035447 | 1.024854–1.088771 | 0.998× [0.989–0.999] | faster |
| string_split / small / 64 | micro | one full document split and result fold | zig-fast | 0.959937 | 0.953558–0.969210 | 0.921× [0.917–0.928] | faster |
| string_split / large / 4096 | micro | one full document split and result fold | my-llvm | 217.421568 | 214.577440–221.929673 | 3.263× [3.258–3.295] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | my-qbe | 266.544700 | 263.378543–269.355930 | 4.019× [4.000–4.023] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | rust | 27.847009 | 27.480374–28.498827 | 0.421× [0.419–0.425] | faster |
| string_split / large / 4096 | micro | one full document split and result fold | go | 66.274384 | 65.799089–68.678658 | 1.000× [1.000–1.000] | reference |
| string_split / large / 4096 | micro | one full document split and result fold | zig-safe | 62.281814 | 61.552984–65.371667 | 0.940× [0.937–0.942] | faster |
| string_split / large / 4096 | micro | one full document split and result fold | zig-fast | 58.462590 | 58.194322–60.331765 | 0.882× [0.880–0.885] | faster |
| string_join / small / 64 | micro | one full fragment join and output fold | my-llvm | 0.422322 | 0.419779–0.436478 | 1.040× [1.032–1.045] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | my-qbe | 0.556329 | 0.553527–0.566567 | 1.367× [1.363–1.372] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | rust | 0.220151 | 0.218380–0.230497 | 0.543× [0.540–0.545] | faster |
| string_join / small / 64 | micro | one full fragment join and output fold | go | 0.407553 | 0.402779–0.416691 | 1.000× [1.000–1.000] | reference |
| string_join / small / 64 | micro | one full fragment join and output fold | zig-safe | 0.313697 | 0.309888–0.333320 | 0.773× [0.766–0.779] | faster |
| string_join / small / 64 | micro | one full fragment join and output fold | zig-fast | 0.270474 | 0.267170–0.280155 | 0.664× [0.659–0.674] | faster |
| string_join / large / 4096 | micro | one full fragment join and output fold | my-llvm | 23.537180 | 23.331554–23.738131 | 0.917× [0.912–0.919] | faster |
| string_join / large / 4096 | micro | one full fragment join and output fold | my-qbe | 28.673110 | 28.304805–29.174266 | 1.115× [1.109–1.119] | slower |
| string_join / large / 4096 | micro | one full fragment join and output fold | rust | 13.428394 | 13.298062–13.556592 | 0.521× [0.518–0.526] | faster |
| string_join / large / 4096 | micro | one full fragment join and output fold | go | 25.722846 | 25.424163–26.095756 | 1.000× [1.000–1.000] | reference |
| string_join / large / 4096 | micro | one full fragment join and output fold | zig-safe | 17.940311 | 17.716939–18.315579 | 0.695× [0.691–0.699] | faster |
| string_join / large / 4096 | micro | one full fragment join and output fold | zig-fast | 16.667212 | 16.475515–16.982000 | 0.647× [0.644–0.652] | faster |
| int_parse / small / 64 | micro | one strict signed decimal parse | my-llvm | 0.010065 | 0.010013–0.010438 | 0.419× [0.417–0.425] | faster |
| int_parse / small / 64 | micro | one strict signed decimal parse | my-qbe | 0.017953 | 0.017728–0.018251 | 0.748× [0.745–0.751] | faster |
| int_parse / small / 64 | micro | one strict signed decimal parse | rust | 0.004484 | 0.004457–0.004564 | 0.186× [0.186–0.187] | faster |
| int_parse / small / 64 | micro | one strict signed decimal parse | go | 0.024022 | 0.023736–0.024156 | 1.000× [1.000–1.000] | reference |
| int_parse / small / 64 | micro | one strict signed decimal parse | zig-safe | 0.005725 | 0.005697–0.005821 | 0.239× [0.238–0.240] | faster |
| int_parse / small / 64 | micro | one strict signed decimal parse | zig-fast | 0.005718 | 0.005681–0.005775 | 0.238× [0.238–0.239] | faster |
| int_parse / large / 4096 | micro | one strict signed decimal parse | my-llvm | 0.010593 | 0.010535–0.010986 | 0.392× [0.389–0.394] | faster |
| int_parse / large / 4096 | micro | one strict signed decimal parse | my-qbe | 0.018778 | 0.018614–0.019658 | 0.694× [0.691–0.696] | faster |
| int_parse / large / 4096 | micro | one strict signed decimal parse | rust | 0.005059 | 0.005037–0.005091 | 0.187× [0.187–0.187] | faster |
| int_parse / large / 4096 | micro | one strict signed decimal parse | go | 0.027066 | 0.026970–0.027260 | 1.000× [1.000–1.000] | reference |
| int_parse / large / 4096 | micro | one strict signed decimal parse | zig-safe | 0.006737 | 0.006703–0.006769 | 0.249× [0.248–0.249] | faster |
| int_parse / large / 4096 | micro | one strict signed decimal parse | zig-fast | 0.006236 | 0.006182–0.006348 | 0.230× [0.229–0.231] | faster |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | my-llvm | 0.063616 | 0.063193–0.065410 | 3.901× [3.882–3.946] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | my-qbe | 0.088835 | 0.088288–0.089303 | 5.458× [5.446–5.484] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | rust | 0.014506 | 0.014414–0.014945 | 0.893× [0.889–0.909] | faster |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | go | 0.016277 | 0.016097–0.016388 | 1.000× [1.000–1.000] | reference |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | zig-safe | 0.040278 | 0.039867–0.041021 | 2.478× [2.458–2.494] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | zig-fast | 0.032447 | 0.032261–0.032961 | 1.997× [1.994–2.004] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | my-llvm | 0.070020 | 0.069665–0.070319 | 3.979× [3.947–3.991] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | my-qbe | 0.091211 | 0.090806–0.091690 | 5.177× [5.155–5.211] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | rust | 0.015176 | 0.014998–0.015763 | 0.865× [0.854–0.892] | faster |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | go | 0.017594 | 0.017367–0.017930 | 1.000× [1.000–1.000] | reference |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | zig-safe | 0.042828 | 0.042256–0.044621 | 2.429× [2.407–2.438] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | zig-fast | 0.036053 | 0.035869–0.036363 | 2.046× [2.034–2.060] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | my-llvm | 2.278091 | 2.263251–2.350583 | 3.540× [3.530–3.576] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | my-qbe | 3.037653 | 3.028522–3.065568 | 4.738× [4.711–4.747] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | rust | 0.346405 | 0.343399–0.374670 | 0.538× [0.535–0.540] | faster |
| word_count / small / 16 | application | one complete tokenize/count/fold job | go | 0.643523 | 0.639258–0.660433 | 1.000× [1.000–1.000] | reference |
| word_count / small / 16 | application | one complete tokenize/count/fold job | zig-safe | 0.245155 | 0.242592–0.248623 | 0.381× [0.379–0.382] | faster |
| word_count / small / 16 | application | one complete tokenize/count/fold job | zig-fast | 0.190169 | 0.188813–0.194548 | 0.295× [0.294–0.298] | faster |
| word_count / large / 256 | application | one complete tokenize/count/fold job | my-llvm | 21.140240 | 20.923469–21.799657 | 2.116× [2.104–2.125] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | my-qbe | 28.543348 | 28.348157–29.819489 | 2.864× [2.853–2.873] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | rust | 3.892369 | 3.859014–3.983232 | 0.391× [0.389–0.392] | faster |
| word_count / large / 256 | application | one complete tokenize/count/fold job | go | 9.959342 | 9.914094–10.512233 | 1.000× [1.000–1.000] | reference |
| word_count / large / 256 | application | one complete tokenize/count/fold job | zig-safe | 3.128602 | 3.087294–3.231162 | 0.314× [0.313–0.316] | faster |
| word_count / large / 256 | application | one complete tokenize/count/fold job | zig-fast | 2.469500 | 2.453288–2.547716 | 0.247× [0.246–0.248] | faster |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | my-llvm | 24.019810 | 23.484361–24.230986 | 4.470× [4.412–4.486] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | my-qbe | 35.183806 | 34.656577–35.904679 | 6.558× [6.509–6.589] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | rust | 4.204205 | 4.130647–4.372587 | 0.784× [0.780–0.787] | faster |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | go | 5.351719 | 5.239254–5.582415 | 1.000× [1.000–1.000] | reference |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | zig-safe | 3.839362 | 3.757605–4.422693 | 0.715× [0.709–0.724] | faster |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | zig-fast | 3.036261 | 2.979408–3.080423 | 0.565× [0.561–0.570] | faster |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | my-llvm | 396.748554 | 391.280003–399.291950 | 4.791× [4.772–4.842] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | my-qbe | 577.140198 | 572.226617–593.017811 | 6.981× [6.935–7.038] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | rust | 68.713250 | 67.705663–74.294227 | 0.837× [0.826–0.841] | faster |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | go | 82.811626 | 81.161951–88.679551 | 1.000× [1.000–1.000] | reference |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | zig-safe | 66.520100 | 65.403272–77.668633 | 0.806× [0.795–0.811] | faster |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | zig-fast | 53.305727 | 52.679354–59.815157 | 0.645× [0.641–0.650] | faster |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 161.419804 | 160.060445–178.912919 | 5.291× [5.276–5.332] | slower |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 217.201112 | 213.343105–243.647008 | 7.101× [7.052–7.235] | slower |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 7.143203 | 6.845362–7.832951 | 0.231× [0.226–0.234] | faster |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | go | 30.515255 | 30.151004–34.690366 | 1.000× [1.000–1.000] | reference |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 11.923693 | 11.615599–13.987789 | 0.385× [0.383–0.389] | faster |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 8.453003 | 8.252691–9.208665 | 0.274× [0.273–0.279] | faster |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 3091.019630 | 2750.473232–3235.734500 | 5.542× [5.513–5.684] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 4157.303953 | 3627.747504–4319.852453 | 7.399× [7.266–7.599] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 124.233978 | 112.671819–135.836062 | 0.231× [0.229–0.233] | faster |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | go | 543.441420 | 479.191051–583.816754 | 1.000× [1.000–1.000] | reference |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 230.414435 | 212.943196–258.728188 | 0.440× [0.432–0.447] | faster |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 187.251467 | 168.927873–204.137996 | 0.347× [0.339–0.349] | faster |
