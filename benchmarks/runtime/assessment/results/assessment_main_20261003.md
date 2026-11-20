# Runtime operation-family assessment

80% is a qualitative design aspiration for representative everyday-codebase breadth; no population percentage or CPU-time coverage is measured.

The saved baseline was independently verified: 40 cases, two sizes, all six configurations, 15 sample rounds and 3 warmups. No benchmark was rerun. This assessment adds no acceptance gate, population weighting or overall language score.

For each case and size, select the lowest observed median kernel time per iteration among all six configurations. All exact median ties are fastest; the first tied arm in ARMS order is the fixed bootstrap reference. Never select a different winner for each round.

2,000 paired-round index resamples; each replicate divides the arm median by the fixed-reference median. Percentile endpoints use sorted indexes 49 and 1949. Deterministic seeds include case/size/arm/reference. Exploratory intervals condition on the observed winner and do not account for winner selection.

Exact observed median winners are fastest. For other arms, intervals wholly above 1 are slower, intervals containing 1 are overlapping, and intervals wholly below 1 are explicitly interval_below_reference despite the observed point ratio being at least 1. This is descriptive evidence, not an equivalence proof or acceptance threshold; multiple comparisons are not adjusted.

Counts describe these selected test/profile comparisons only, not percentages of real codebases or operation frequencies.

Baseline SHA256: `b595d9638e243e18692b5cef491c2b5273949c93ebf22a0ae604a08704c1d3f7`. Historical measurement sources: **verified_historical_sources** at `b725360f5f86ac67bc405db9407ae51c332a9931`. Current artifacts were not checked. Recorded compiler source revision: `6df58b02554401f9d37564cceffd14277a835ae1`; this tool does not independently establish compiler-source equivalence.

- alloc_short permits optimizer elimination of nonescaping allocations; fastest saved pilots are exceptionally short. It is not evidence for the cost of physical allocation.
- sort_int/sort_records use each language native sorting API and compare language/library policies, rather than one identical algorithm.
- Ownership, snapshot, copy-on-write, reference-counting, GC and allocator semantics differ as documented; equivalent observable behavior does not imply equivalent physical copying.
- Optimized default build policies use different instruction sets across arms. Rust default x86_64 and Go v1 differ from default Zig/Clang-derived host features.
- Intervals use paired raw resampling of ratio-of-medians against a fixed observed winner, not transformed Go-relative intervals. Winner-selection uncertainty is not included. Paired intervals and raw spread describe the saved run. They do not guarantee performance on another machine, input, lifetime or workload.

## Eight operation families

Family counts include small and large profiles separately. Each case/profile uses its own fixed observed fastest reference. Ranges and worst cases refer to individual ratios of observed medians, not a pooled average. Every cell below is ratio to fastest [95% paired bootstrap interval] and classification; exact per-iteration times and units follow in the appendix.

### numbers and branches

Covers: integer and exact floating-point arithmetic; predictable and mixed conditions; runtime-dependent loop work.

Limits: bounded integer ranges and exact dyadic floats; repeated warm fixtures; no broader numerical kernels or varied branch histories.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 8 | 0 | 2.114–3.209× | branch_predictable / large (3.209×) |
| my-qbe | 0 | 0 | 8 | 0 | 9.925–15.175× | float_math / large (15.175×) |
| rust | 4 | 1 | 3 | 0 | 1.000–1.584× | float_math / large (1.584×) |
| go | 0 | 0 | 8 | 0 | 1.320–2.000× | branch_predictable / large (2.000×) |
| zig-safe | 0 | 0 | 8 | 0 | 1.342–2.269× | branch_predictable / large (2.269×) |
| zig-fast | 4 | 1 | 3 | 0 | 1.000–1.208× | integer_math / large (1.208×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| integer_math / small | rust; rust | 2.114× [2.107–2.125] slower | 10.412× [10.375–10.463] slower | 1.00× [1.000–1.000] fastest | 1.320× [1.316–1.328] slower | 1.342× [1.336–1.348] slower | 1.188× [1.184–1.195] slower |
| integer_math / large | rust; rust | 2.215× [2.204–2.226] slower | 11.316× [11.267–11.361] slower | 1.00× [1.000–1.000] fastest | 1.358× [1.351–1.362] slower | 1.346× [1.339–1.355] slower | 1.208× [1.203–1.213] slower |
| float_math / small | zig-fast; zig-fast | 2.433× [2.419–2.444] slower | 13.985× [13.905–14.048] slower | 1.530× [1.522–1.537] slower | 1.472× [1.464–1.482] slower | 1.473× [1.463–1.481] slower | 1.00× [1.000–1.000] fastest |
| float_math / large | zig-fast; zig-fast | 2.567× [2.559–2.575] slower | 15.175× [15.119–15.238] slower | 1.584× [1.578–1.592] slower | 1.514× [1.509–1.524] slower | 1.486× [1.481–1.492] slower | 1.00× [1.000–1.000] fastest |
| branch_predictable / small | zig-fast; zig-fast | 3.052× [3.016–3.079] slower | 13.437× [13.405–13.512] slower | 1.000× [0.996–1.007] overlapping | 1.916× [1.911–1.930] slower | 2.249× [2.240–2.264] slower | 1.00× [1.000–1.000] fastest |
| branch_predictable / large | zig-fast; zig-fast | 3.209× [3.192–3.215] slower | 13.709× [13.643–13.726] slower | 1.016× [1.008–1.023] slower | 2.000× [1.989–2.003] slower | 2.269× [2.258–2.277] slower | 1.00× [1.000–1.000] fastest |
| branch_mixed / small | rust; rust | 2.166× [2.155–2.177] slower | 10.164× [10.111–10.193] slower | 1.00× [1.000–1.000] fastest | 1.487× [1.473–1.494] slower | 1.802× [1.795–1.810] slower | 1.001× [0.997–1.005] overlapping |
| branch_mixed / large | rust; rust | 2.231× [2.220–2.241] slower | 9.925× [9.884–9.966] slower | 1.00× [1.000–1.000] fastest | 1.714× [1.707–1.722] slower | 1.886× [1.878–1.895] slower | 1.004× [1.001–1.009] slower |

### lists and iteration

Covers: list scans; dynamic growth; filtering; unique mutation.

Limits: small warm working sets; limited record/list shape variety; no large cache-miss-heavy traversal.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 8 | 0 | 1.549–2.817× | list_append / small (2.817×) |
| my-qbe | 0 | 0 | 8 | 0 | 4.590–9.505× | mutate_unique / small (9.505×) |
| rust | 5 | 0 | 3 | 0 | 1.000–1.344× | list_append / small (1.344×) |
| go | 0 | 0 | 8 | 0 | 1.145–1.953× | list_filter / large (1.953×) |
| zig-safe | 0 | 0 | 8 | 0 | 1.279–2.107× | list_append / small (2.107×) |
| zig-fast | 3 | 0 | 5 | 0 | 1.000–1.298× | list_filter / large (1.298×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| list_scan / small | rust; rust | 2.002× [1.852–2.102] slower | 5.700× [5.289–5.914] slower | 1.00× [1.000–1.000] fastest | 1.260× [1.158–1.322] slower | 1.681× [1.563–1.731] slower | 1.266× [1.173–1.354] slower |
| list_scan / large | rust; rust | 1.549× [1.372–1.805] slower | 4.590× [4.331–5.083] slower | 1.00× [1.000–1.000] fastest | 1.195× [1.132–1.342] slower | 1.762× [1.662–1.909] slower | 1.210× [1.129–1.518] slower |
| list_append / small | zig-fast; zig-fast | 2.817× [2.739–2.843] slower | 5.384× [5.273–5.485] slower | 1.344× [1.306–1.365] slower | 1.836× [1.801–1.871] slower | 2.107× [2.062–2.138] slower | 1.00× [1.000–1.000] fastest |
| list_append / large | zig-fast; zig-fast | 2.212× [2.166–2.253] slower | 4.859× [4.782–4.973] slower | 1.044× [1.012–1.081] slower | 1.840× [1.811–1.905] slower | 2.005× [1.954–2.045] slower | 1.00× [1.000–1.000] fastest |
| list_filter / small | zig-fast; zig-fast | 2.599× [2.583–2.622] slower | 5.055× [5.005–5.094] slower | 1.099× [1.088–1.106] slower | 1.903× [1.890–1.919] slower | 1.418× [1.404–1.431] slower | 1.00× [1.000–1.000] fastest |
| list_filter / large | rust; rust | 2.350× [2.329–2.360] slower | 5.807× [5.742–5.842] slower | 1.00× [1.000–1.000] fastest | 1.953× [1.921–1.966] slower | 1.807× [1.775–1.817] slower | 1.298× [1.284–1.313] slower |
| mutate_unique / small | rust; rust | 1.695× [1.688–1.702] slower | 9.505× [9.467–9.535] slower | 1.00× [1.000–1.000] fastest | 1.148× [1.143–1.153] slower | 1.287× [1.280–1.293] slower | 1.232× [1.226–1.236] slower |
| mutate_unique / large | rust; rust | 1.693× [1.680–1.709] slower | 9.467× [9.406–9.530] slower | 1.00× [1.000–1.000] fastest | 1.145× [1.141–1.157] slower | 1.279× [1.270–1.287] slower | 1.229× [1.224–1.239] slower |

### strings and bytes

Covers: bytes and UTF-8 text; equality and search; split and join; valid and malformed decimal conversion.

Limits: repetitive text and limited Unicode shapes; no large documents, normalization or regular expressions.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 3 | 0 | 11 | 0 | 1.000–7.808× | string_split / large (7.808×) |
| my-qbe | 1 | 0 | 13 | 0 | 1.000–23.264× | string_equal / large (23.264×) |
| rust | 10 | 0 | 4 | 0 | 1.000–13.193× | string_search / large (13.193×) |
| go | 0 | 0 | 14 | 0 | 1.122–6.553× | string_search / large (6.553×) |
| zig-safe | 0 | 0 | 14 | 0 | 1.277–30.354× | string_search / large (30.354×) |
| zig-fast | 0 | 0 | 14 | 0 | 1.229–26.786× | string_search / large (26.786×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| bytes_scan / small | my-llvm; my-llvm | 1.00× [1.000–1.000] fastest | 7.818× [7.777–7.855] slower | 2.059× [2.048–2.074] slower | 2.772× [2.725–2.848] slower | 3.241× [3.192–3.275] slower | 1.411× [1.394–1.425] slower |
| bytes_scan / large | my-llvm; my-llvm | 1.00× [1.000–1.000] fastest | 9.499× [9.468–9.559] slower | 2.999× [2.992–3.013] slower | 2.866× [2.827–2.886] slower | 3.762× [3.724–3.921] slower | 1.980× [1.968–1.993] slower |
| string_equal / small | rust; rust | 5.300× [5.232–5.373] slower | 11.999× [11.837–12.052] slower | 1.00× [1.000–1.000] fastest | 1.508× [1.488–1.531] slower | 1.361× [1.342–1.370] slower | 1.272× [1.257–1.277] slower |
| string_equal / large | rust; rust | 1.446× [1.437–1.459] slower | 23.264× [23.220–23.348] slower | 1.00× [1.000–1.000] fastest | 1.217× [1.208–1.228] slower | 2.101× [2.094–2.105] slower | 1.632× [1.624–1.636] slower |
| string_search / small | my-llvm; my-llvm | 1.00× [1.000–1.000] fastest | 1.532× [1.527–1.537] slower | 2.162× [2.155–2.176] slower | 1.252× [1.244–1.255] slower | 4.517× [4.504–4.529] slower | 3.767× [3.756–3.786] slower |
| string_search / large | my-qbe; my-qbe | 1.041× [1.032–1.047] slower | 1.00× [1.000–1.000] fastest | 13.193× [13.102–13.256] slower | 6.553× [6.510–6.586] slower | 30.354× [30.161–30.504] slower | 26.786× [26.630–26.905] slower |
| string_split / small | rust; rust | 6.455× [6.382–6.582] slower | 7.999× [7.909–8.052] slower | 1.00× [1.000–1.000] fastest | 1.883× [1.859–1.902] slower | 1.876× [1.854–1.891] slower | 1.739× [1.713–1.758] slower |
| string_split / large | rust; rust | 7.808× [7.688–7.830] slower | 9.572× [9.447–9.600] slower | 1.00× [1.000–1.000] fastest | 2.380× [2.354–2.394] slower | 2.237× [2.209–2.249] slower | 2.099× [2.079–2.106] slower |
| string_join / small | rust; rust | 1.918× [1.905–1.924] slower | 2.527× [2.506–2.534] slower | 1.00× [1.000–1.000] fastest | 1.851× [1.836–1.858] slower | 1.425× [1.410–1.436] slower | 1.229× [1.215–1.241] slower |
| string_join / large | rust; rust | 1.753× [1.742–1.765] slower | 2.135× [2.120–2.153] slower | 1.00× [1.000–1.000] fastest | 1.916× [1.901–1.929] slower | 1.336× [1.323–1.340] slower | 1.241× [1.232–1.248] slower |
| int_parse / small | rust; rust | 2.245× [2.234–2.276] slower | 4.004× [3.995–4.027] slower | 1.00× [1.000–1.000] fastest | 5.358× [5.339–5.383] slower | 1.277× [1.273–1.287] slower | 1.275× [1.270–1.284] slower |
| int_parse / large | rust; rust | 2.094× [2.081–2.106] slower | 3.712× [3.698–3.720] slower | 1.00× [1.000–1.000] fastest | 5.350× [5.332–5.366] slower | 1.332× [1.326–1.336] slower | 1.233× [1.221–1.237] slower |
| int_format / small | rust; rust | 4.386× [4.331–4.412] slower | 6.124× [6.050–6.144] slower | 1.00× [1.000–1.000] fastest | 1.122× [1.102–1.125] slower | 2.777× [2.726–2.789] slower | 2.237× [2.214–2.249] slower |
| int_format / large | rust; rust | 4.614× [4.475–4.640] slower | 6.010× [5.829–6.057] slower | 1.00× [1.000–1.000] fastest | 1.159× [1.123–1.172] slower | 2.822× [2.731–2.844] slower | 2.376× [2.300–2.399] slower |

### dictionaries and sets

Covers: integer and string keys; lookup hits and misses; updates and growth; deduplication.

Limits: compact keys and repeated insertion patterns; no deletion/tombstones or large diverse-key workloads.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 10 | 0 | 1.494–11.902× | set_dedup / small (11.902×) |
| my-qbe | 0 | 0 | 10 | 0 | 2.041–16.270× | set_dedup / small (16.270×) |
| rust | 0 | 0 | 10 | 0 | 1.072–3.308× | set_dedup / small (3.308×) |
| go | 3 | 0 | 7 | 0 | 1.000–3.939× | set_dedup / small (3.939×) |
| zig-safe | 0 | 0 | 10 | 0 | 1.218–2.104× | set_dedup / small (2.104×) |
| zig-fast | 7 | 0 | 3 | 0 | 1.000–1.382× | dict_lookup / large (1.382×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| dict_lookup / small | zig-fast; zig-fast | 2.058× [2.051–2.073] slower | 3.314× [3.301–3.331] slower | 2.472× [2.437–2.492] slower | 1.826× [1.784–1.860] slower | 1.952× [1.944–1.963] slower | 1.00× [1.000–1.000] fastest |
| dict_lookup / large | go; go | 1.766× [1.741–1.774] slower | 2.585× [2.554–2.603] slower | 1.363× [1.350–1.375] slower | 1.00× [1.000–1.000] fastest | 1.752× [1.734–1.769] slower | 1.382× [1.363–1.394] slower |
| dict_lookup_str / small | zig-fast; zig-fast | 1.494× [1.485–1.507] slower | 2.572× [2.563–2.587] slower | 2.222× [2.206–2.235] slower | 1.431× [1.407–1.454] slower | 1.332× [1.327–1.343] slower | 1.00× [1.000–1.000] fastest |
| dict_lookup_str / large | go; go | 1.681× [1.668–1.699] slower | 2.390× [2.373–2.417] slower | 1.451× [1.443–1.472] slower | 1.00× [1.000–1.000] fastest | 1.558× [1.545–1.571] slower | 1.219× [1.205–1.228] slower |
| dict_update / small | zig-fast; zig-fast | 6.147× [6.112–6.185] slower | 8.574× [8.534–8.621] slower | 2.457× [2.449–2.476] slower | 3.367× [3.342–3.390] slower | 2.001× [1.985–2.033] slower | 1.00× [1.000–1.000] fastest |
| dict_update / large | zig-fast; zig-fast | 2.641× [2.625–2.663] slower | 3.443× [3.433–3.450] slower | 1.072× [1.064–1.081] slower | 1.177× [1.170–1.185] slower | 1.384× [1.381–1.393] slower | 1.00× [1.000–1.000] fastest |
| dict_update_str / small | zig-fast; zig-fast | 2.856× [2.773–2.886] slower | 3.779× [3.699–3.804] slower | 2.733× [2.661–2.753] slower | 1.965× [1.913–1.985] slower | 1.314× [1.286–1.331] slower | 1.00× [1.000–1.000] fastest |
| dict_update_str / large | go; go | 1.666× [1.660–1.672] slower | 2.041× [2.033–2.048] slower | 1.518× [1.495–1.537] slower | 1.00× [1.000–1.000] fastest | 1.218× [1.213–1.224] slower | 1.064× [1.060–1.069] slower |
| set_dedup / small | zig-fast; zig-fast | 11.902× [11.862–11.953] slower | 16.270× [16.155–16.356] slower | 3.308× [3.296–3.329] slower | 3.939× [3.916–3.964] slower | 2.104× [2.091–2.112] slower | 1.00× [1.000–1.000] fastest |
| set_dedup / large | zig-fast; zig-fast | 3.983× [3.965–4.015] slower | 5.268× [5.260–5.299] slower | 1.101× [1.094–1.109] slower | 1.243× [1.240–1.252] slower | 1.437× [1.433–1.444] slower | 1.00× [1.000–1.000] fastest |

### records and calls

Covers: record reads, construction and updates; direct and runtime-selected calls.

Limits: small scalar records and helpers; no recursion, captured closures, FFI or managed-field record workloads.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 10 | 0 | 1.408–4.025× | call_direct / large (4.025×) |
| my-qbe | 0 | 0 | 10 | 0 | 2.860–24.339× | call_direct / large (24.339×) |
| rust | 8 | 0 | 2 | 0 | 1.000–1.143× | call_indirect / large (1.143×) |
| go | 0 | 0 | 10 | 0 | 1.203–1.680× | call_direct / large (1.680×) |
| zig-safe | 0 | 0 | 10 | 0 | 1.384–1.613× | call_indirect / large (1.613×) |
| zig-fast | 2 | 1 | 7 | 0 | 1.000–1.333× | record_update / large (1.333×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| record_reads / small | rust; rust | 1.408× [1.404–1.412] slower | 2.860× [2.853–2.866] slower | 1.00× [1.000–1.000] fastest | 1.203× [1.201–1.205] slower | 1.384× [1.382–1.387] slower | 1.285× [1.282–1.287] slower |
| record_reads / large | rust; rust | 1.493× [1.484–1.508] slower | 3.168× [3.130–3.217] slower | 1.00× [1.000–1.000] fastest | 1.215× [1.196–1.220] slower | 1.387× [1.378–1.395] slower | 1.242× [1.237–1.246] slower |
| record_construct / small | rust; rust | 2.444× [2.439–2.451] slower | 9.631× [9.613–9.658] slower | 1.00× [1.000–1.000] fastest | 1.380× [1.377–1.382] slower | 1.487× [1.484–1.497] slower | 1.270× [1.263–1.275] slower |
| record_construct / large | rust; rust | 2.533× [2.518–2.540] slower | 10.347× [10.200–10.420] slower | 1.00× [1.000–1.000] fastest | 1.416× [1.393–1.419] slower | 1.494× [1.484–1.503] slower | 1.330× [1.317–1.338] slower |
| record_update / small | rust; rust | 2.693× [2.688–2.705] slower | 13.901× [13.878–13.986] slower | 1.00× [1.000–1.000] fastest | 1.381× [1.376–1.390] slower | 1.561× [1.553–1.573] slower | 1.261× [1.257–1.268] slower |
| record_update / large | rust; rust | 2.842× [2.837–2.850] slower | 15.133× [15.109–15.193] slower | 1.00× [1.000–1.000] fastest | 1.441× [1.437–1.449] slower | 1.595× [1.585–1.605] slower | 1.333× [1.316–1.355] slower |
| call_direct / small | rust; rust | 2.989× [2.984–2.997] slower | 16.935× [16.904–16.994] slower | 1.00× [1.000–1.000] fastest | 1.444× [1.443–1.450] slower | 1.404× [1.401–1.408] slower | 1.084× [1.081–1.087] slower |
| call_direct / large | rust; rust | 4.025× [4.014–4.032] slower | 24.339× [24.275–24.427] slower | 1.00× [1.000–1.000] fastest | 1.680× [1.674–1.683] slower | 1.496× [1.490–1.501] slower | 1.002× [0.997–1.005] overlapping |
| call_indirect / small | zig-fast; zig-fast | 1.623× [1.612–1.637] slower | 7.380× [7.350–7.409] slower | 1.100× [1.095–1.104] slower | 1.303× [1.294–1.308] slower | 1.553× [1.545–1.560] slower | 1.00× [1.000–1.000] fastest |
| call_indirect / large | zig-fast; zig-fast | 1.694× [1.658–1.707] slower | 7.952× [7.903–8.027] slower | 1.143× [1.137–1.155] slower | 1.363× [1.352–1.373] slower | 1.613× [1.605–1.623] slower | 1.00× [1.000–1.000] fastest |

### optional values and errors

Covers: optional values; success and error propagation; tagged operand-stack values.

Limits: fixed variant shapes and error mixes; no large recursive variants or complex unwinding.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 0 | 0 | 6 | 0 | 3.898–5.212× | option_handle / large (5.212×) |
| my-qbe | 0 | 0 | 6 | 0 | 5.518–29.085× | option_handle / large (29.085×) |
| rust | 6 | 0 | 0 | 0 | 1.000–1.000× | tagged_stack / small (1.000×) |
| go | 0 | 0 | 6 | 0 | 1.051–2.705× | option_handle / large (2.705×) |
| zig-safe | 0 | 0 | 6 | 0 | 1.770–2.748× | option_handle / large (2.748×) |
| zig-fast | 0 | 0 | 6 | 0 | 1.178–2.190× | option_handle / large (2.190×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| tagged_stack / small | rust; rust | 4.369× [4.353–4.372] slower | 5.518× [5.500–5.524] slower | 1.00× [1.000–1.000] fastest | 1.051× [1.049–1.052] slower | 1.847× [1.841–1.868] slower | 1.863× [1.857–1.867] slower |
| tagged_stack / large | rust; rust | 4.373× [4.363–4.383] slower | 5.524× [5.511–5.541] slower | 1.00× [1.000–1.000] fastest | 1.052× [1.050–1.054] slower | 1.869× [1.848–1.877] slower | 1.862× [1.858–1.878] slower |
| option_handle / small | rust; rust | 3.969× [3.941–4.000] slower | 22.269× [22.152–22.439] slower | 1.00× [1.000–1.000] fastest | 2.143× [2.133–2.149] slower | 2.297× [2.287–2.306] slower | 1.771× [1.763–1.774] slower |
| option_handle / large | rust; rust | 5.212× [5.192–5.239] slower | 29.085× [28.971–29.186] slower | 1.00× [1.000–1.000] fastest | 2.705× [2.692–2.746] slower | 2.748× [2.739–2.767] slower | 2.190× [2.178–2.205] slower |
| result_propagate / small | rust; rust | 3.898× [3.887–3.928] slower | 17.883× [17.851–17.945] slower | 1.00× [1.000–1.000] fastest | 2.104× [2.095–2.113] slower | 1.770× [1.763–1.784] slower | 1.178× [1.171–1.181] slower |
| result_propagate / large | rust; rust | 4.513× [4.482–4.535] slower | 21.001× [20.862–21.074] slower | 1.00× [1.000–1.000] fastest | 2.396× [2.379–2.403] slower | 2.055× [2.034–2.063] slower | 1.482× [1.468–1.494] slower |

### allocation and ownership

Covers: short and retained dynamic lists; shared snapshots; nested mutation preserving prior values.

Limits: short-allocation work may be optimized away; no long-lived mixed-lifetime heap churn or tail-latency evidence; snapshot costs include native COW versus explicit cloning.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 2 | 0 | 6 | 0 | 1.000–18929.496× | alloc_short / large (18929.496×) |
| my-qbe | 0 | 0 | 8 | 0 | 1.165–25384.725× | alloc_short / large (25384.725×) |
| rust | 1 | 0 | 7 | 0 | 1.000–321.066× | alloc_short / large (321.066×) |
| go | 0 | 0 | 8 | 0 | 1.294–520.405× | alloc_short / large (520.405×) |
| zig-safe | 0 | 0 | 8 | 0 | 1.032–1397.620× | alloc_short / large (1397.620×) |
| zig-fast | 5 | 0 | 3 | 0 | 1.000–2.548× | mutate_nested / large (2.548×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| alloc_short / small | zig-fast; zig-fast | 1211.985× [1192.136–1270.162] slower | 1616.293× [1589.490–1694.399] slower | 20.865× [20.353–22.110] slower | 38.677× [37.830–40.655] slower | 88.853× [87.468–93.102] slower | 1.00× [1.000–1.000] fastest |
| alloc_short / large | zig-fast; zig-fast | 18929.496× [17312.351–19029.641] slower | 25384.725× [23199.230–25509.874] slower | 321.066× [291.914–325.880] slower | 520.405× [475.245–526.269] slower | 1397.620× [1278.432–1406.903] slower | 1.00× [1.000–1.000] fastest |
| alloc_retained / small | zig-fast; zig-fast | 2.338× [2.323–2.354] slower | 3.519× [3.490–3.536] slower | 1.069× [1.060–1.075] slower | 1.501× [1.487–1.508] slower | 1.032× [1.021–1.049] slower | 1.00× [1.000–1.000] fastest |
| alloc_retained / large | zig-fast; zig-fast | 2.284× [2.256–2.295] slower | 3.339× [3.302–3.359] slower | 1.047× [1.036–1.055] slower | 1.294× [1.280–1.305] slower | 1.039× [1.023–1.049] slower | 1.00× [1.000–1.000] fastest |
| mutate_shared / small | zig-fast; zig-fast | 11.326× [11.298–11.458] slower | 16.004× [15.963–16.187] slower | 1.041× [1.028–1.058] slower | 5.236× [5.205–5.305] slower | 1.551× [1.543–1.572] slower | 1.00× [1.000–1.000] fastest |
| mutate_shared / large | rust; rust | 3.405× [3.384–3.413] slower | 4.228× [4.205–4.247] slower | 1.00× [1.000–1.000] fastest | 8.654× [8.572–8.712] slower | 2.177× [2.165–2.181] slower | 1.696× [1.685–1.706] slower |
| mutate_nested / small | my-llvm; my-llvm | 1.00× [1.000–1.000] fastest | 1.165× [1.161–1.168] slower | 1.571× [1.563–1.578] slower | 1.553× [1.545–1.558] slower | 1.590× [1.584–1.628] slower | 1.469× [1.450–1.495] slower |
| mutate_nested / large | my-llvm; my-llvm | 1.00× [1.000–1.000] fastest | 1.181× [1.166–1.193] slower | 2.817× [2.797–2.831] slower | 2.436× [2.421–2.451] slower | 2.790× [2.764–2.806] slower | 2.548× [2.533–2.568] slower |

### sorting and searching

Covers: native integer sorting; native stable record sorting; binary search.

Limits: specific library APIs and input patterns; Go sort.Slice/sort.SliceStable, not generic slices APIs; limited key distributions.

| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |
|---|---:|---:|---:|---:|---:|---|
| my-llvm | 1 | 0 | 5 | 0 | 1.000–2.302× | binary_search / small (2.302×) |
| my-qbe | 0 | 0 | 6 | 0 | 1.280–17.397× | binary_search / large (17.397×) |
| rust | 3 | 0 | 3 | 0 | 1.000–1.427× | sort_int / large (1.427×) |
| go | 0 | 0 | 6 | 0 | 1.644–24.301× | sort_records / large (24.301×) |
| zig-safe | 0 | 0 | 6 | 0 | 1.392–3.545× | binary_search / large (3.545×) |
| zig-fast | 2 | 0 | 4 | 0 | 1.000–1.780× | sort_records / large (1.780×) |

| Case / profile | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|
| sort_int / small | zig-fast; zig-fast | 1.654× [1.637–1.669] slower | 3.178× [3.146–3.207] slower | 1.343× [1.330–1.354] slower | 6.321× [6.249–6.364] slower | 1.594× [1.578–1.608] slower | 1.00× [1.000–1.000] fastest |
| sort_int / large | my-llvm; my-llvm | 1.00× [1.000–1.000] fastest | 1.280× [1.278–1.285] slower | 1.427× [1.426–1.432] slower | 5.256× [5.250–5.280] slower | 1.469× [1.465–1.474] slower | 1.015× [1.010–1.019] slower |
| sort_records / small | zig-fast; zig-fast | 2.134× [2.108–2.156] slower | 3.441× [3.387–3.481] slower | 1.177× [1.164–1.191] slower | 12.928× [12.704–13.079] slower | 1.392× [1.375–1.409] slower | 1.00× [1.000–1.000] fastest |
| sort_records / large | rust; rust | 1.188× [1.179–1.201] slower | 1.914× [1.907–1.930] slower | 1.00× [1.000–1.000] fastest | 24.301× [24.179–24.504] slower | 2.222× [2.214–2.241] slower | 1.780× [1.770–1.796] slower |
| binary_search / small | rust; rust | 2.302× [2.293–2.316] slower | 12.611× [12.563–12.688] slower | 1.00× [1.000–1.000] fastest | 1.944× [1.929–1.958] slower | 1.514× [1.504–1.524] slower | 1.450× [1.444–1.458] slower |
| binary_search / large | rust; rust | 2.021× [2.012–2.030] slower | 17.397× [17.270–17.496] slower | 1.00× [1.000–1.000] fastest | 1.644× [1.629–1.650] slower | 3.545× [3.532–3.555] slower | 1.369× [1.363–1.376] slower |

## Five composed applications

Large-profile whole-job median time in microseconds; ratio to fastest and 95% paired bootstrap interval. Each application keeps its own unit and interpretation. Both sizes appear in the full appendix.

| Application / large size | Unit | Fastest arm(s); interval reference | my-llvm | my-qbe | rust | go | zig-safe | zig-fast |
|---|---|---|---|---|---|---|---|---|
| word_count / 256 | one complete tokenize/count/fold job | zig-fast; zig-fast | 21.140 µs; 8.561× [8.484–8.603] slower | 28.543 µs; 11.558× [11.493–11.638] slower | 3.892 µs; 1.576× [1.566–1.586] slower | 9.959 µs; 4.033× [4.010–4.060] slower | 3.129 µs; 1.267× [1.261–1.275] slower | 2.469 µs; 1.00× [1.000–1.000] fastest |
| csv_aggregate / 256 | one complete CSV parse/validate/group/fold job | zig-fast; zig-fast | 396.749 µs; 7.443× [7.393–7.457] slower | 577.140 µs; 10.827× [10.749–10.861] slower | 68.713 µs; 1.289× [1.278–1.297] slower | 82.812 µs; 1.554× [1.530–1.560] slower | 66.520 µs; 1.248× [1.233–1.251] slower | 53.306 µs; 1.00× [1.000–1.000] fastest |
| json_transform / 256 | one complete JSON parse/filter/transform/serialize/fold job | rust; rust | 3091.020 µs; 24.881× [22.461–24.883] slower | 4157.304 µs; 33.464× [29.815–33.464] slower | 124.234 µs; 1.00× [1.000–1.000] fastest | 543.441 µs; 4.374× [4.242–4.471] slower | 230.414 µs; 1.855× [1.722–1.979] slower | 187.251 µs; 1.507× [1.451–1.528] slower |
| packet_decode / 256 | one complete pass over SIZE fixtures | zig-fast; zig-fast | 1.642 µs; 2.496× [2.458–2.582] slower | 8.290 µs; 12.599× [12.221–13.239] slower | 0.787 µs; 1.196× [1.150–1.224] slower | 1.951 µs; 2.965× [2.868–3.152] slower | 1.342 µs; 2.039× [2.000–2.150] slower | 0.658 µs; 1.00× [1.000–1.000] fastest |
| lox_eval / 256 | one complete bytecode program execution with SIZE loop iterations | rust; rust | 75.794 µs; 7.107× [7.049–7.184] slower | 82.979 µs; 7.781× [7.725–7.846] slower | 10.664 µs; 1.00× [1.000–1.000] fastest | 12.636 µs; 1.185× [1.175–1.206] slower | 30.533 µs; 2.863× [2.837–2.889] slower | 29.790 µs; 2.794× [2.773–2.818] slower |

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

| Case / profile / size | Level | Unit | Arm | Median µs/iteration | Min–max µs | Fastest arm(s); interval reference | Ratio to fastest [95% interval] | Classification |
|---|---|---|---|---:|---:|---|---:|---|
| record_reads / small / 64 | micro | one contract operation | my-llvm | 0.005347 | 0.005326–0.005462 | rust; rust | 1.41× [1.404–1.412] | slower |
| record_reads / small / 64 | micro | one contract operation | my-qbe | 0.010861 | 0.010804–0.010974 | rust; rust | 2.86× [2.853–2.866] | slower |
| record_reads / small / 64 | micro | one contract operation | rust | 0.003798 | 0.003783–0.003816 | rust; rust | 1.00× [1.000–1.000] | fastest |
| record_reads / small / 64 | micro | one contract operation | go | 0.004570 | 0.004558–0.004755 | rust; rust | 1.20× [1.201–1.205] | slower |
| record_reads / small / 64 | micro | one contract operation | zig-safe | 0.005258 | 0.005242–0.005284 | rust; rust | 1.38× [1.382–1.387] | slower |
| record_reads / small / 64 | micro | one contract operation | zig-fast | 0.004880 | 0.004867–0.004923 | rust; rust | 1.28× [1.282–1.287] | slower |
| record_reads / large / 4096 | micro | one contract operation | my-llvm | 0.005778 | 0.005667–0.005870 | rust; rust | 1.49× [1.484–1.508] | slower |
| record_reads / large / 4096 | micro | one contract operation | my-qbe | 0.012267 | 0.011897–0.012790 | rust; rust | 3.17× [3.130–3.217] | slower |
| record_reads / large / 4096 | micro | one contract operation | rust | 0.003872 | 0.003855–0.003891 | rust; rust | 1.00× [1.000–1.000] | fastest |
| record_reads / large / 4096 | micro | one contract operation | go | 0.004702 | 0.004625–0.004749 | rust; rust | 1.21× [1.196–1.220] | slower |
| record_reads / large / 4096 | micro | one contract operation | zig-safe | 0.005369 | 0.005295–0.005492 | rust; rust | 1.39× [1.378–1.395] | slower |
| record_reads / large / 4096 | micro | one contract operation | zig-fast | 0.004807 | 0.004767–0.004874 | rust; rust | 1.24× [1.237–1.246] | slower |
| tagged_stack / small / 64 | micro | one contract operation | my-llvm | 0.024925 | 0.024788–0.025005 | rust; rust | 4.37× [4.353–4.372] | slower |
| tagged_stack / small / 64 | micro | one contract operation | my-qbe | 0.031481 | 0.031357–0.044096 | rust; rust | 5.52× [5.500–5.524] | slower |
| tagged_stack / small / 64 | micro | one contract operation | rust | 0.005705 | 0.005686–0.006091 | rust; rust | 1.00× [1.000–1.000] | fastest |
| tagged_stack / small / 64 | micro | one contract operation | go | 0.005994 | 0.005986–0.006051 | rust; rust | 1.05× [1.049–1.052] | slower |
| tagged_stack / small / 64 | micro | one contract operation | zig-safe | 0.010539 | 0.010486–0.011735 | rust; rust | 1.85× [1.841–1.868] | slower |
| tagged_stack / small / 64 | micro | one contract operation | zig-fast | 0.010629 | 0.010567–0.010877 | rust; rust | 1.86× [1.857–1.867] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | my-llvm | 0.024921 | 0.024841–0.025033 | rust; rust | 4.37× [4.363–4.383] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | my-qbe | 0.031475 | 0.031318–0.031682 | rust; rust | 5.52× [5.511–5.541] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | rust | 0.005698 | 0.005684–0.005755 | rust; rust | 1.00× [1.000–1.000] | fastest |
| tagged_stack / large / 4096 | micro | one contract operation | go | 0.005995 | 0.005981–0.006089 | rust; rust | 1.05× [1.050–1.054] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | zig-safe | 0.010652 | 0.010497–0.010722 | rust; rust | 1.87× [1.848–1.877] | slower |
| tagged_stack / large / 4096 | micro | one contract operation | zig-fast | 0.010613 | 0.010571–0.010897 | rust; rust | 1.86× [1.858–1.878] | slower |
| mutate_unique / small / 64 | micro | one contract operation | my-llvm | 0.004934 | 0.004890–0.004996 | rust; rust | 1.70× [1.688–1.702] | slower |
| mutate_unique / small / 64 | micro | one contract operation | my-qbe | 0.027666 | 0.027574–0.027885 | rust; rust | 9.50× [9.467–9.535] | slower |
| mutate_unique / small / 64 | micro | one contract operation | rust | 0.002911 | 0.002892–0.002940 | rust; rust | 1.00× [1.000–1.000] | fastest |
| mutate_unique / small / 64 | micro | one contract operation | go | 0.003342 | 0.003327–0.003424 | rust; rust | 1.15× [1.143–1.153] | slower |
| mutate_unique / small / 64 | micro | one contract operation | zig-safe | 0.003747 | 0.003714–0.003964 | rust; rust | 1.29× [1.280–1.293] | slower |
| mutate_unique / small / 64 | micro | one contract operation | zig-fast | 0.003585 | 0.003571–0.003620 | rust; rust | 1.23× [1.226–1.236] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | my-llvm | 0.004947 | 0.004899–0.005112 | rust; rust | 1.69× [1.680–1.709] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | my-qbe | 0.027666 | 0.027507–0.027841 | rust; rust | 9.47× [9.406–9.530] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | rust | 0.002922 | 0.002892–0.002969 | rust; rust | 1.00× [1.000–1.000] | fastest |
| mutate_unique / large / 1024 | micro | one contract operation | go | 0.003346 | 0.003335–0.003423 | rust; rust | 1.15× [1.141–1.157] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | zig-safe | 0.003737 | 0.003718–0.003780 | rust; rust | 1.28× [1.270–1.287] | slower |
| mutate_unique / large / 1024 | micro | one contract operation | zig-fast | 0.003593 | 0.003568–0.004700 | rust; rust | 1.23× [1.224–1.239] | slower |
| mutate_shared / small / 64 | micro | one contract operation | my-llvm | 0.117836 | 0.116804–0.120251 | zig-fast; zig-fast | 11.33× [11.298–11.458] | slower |
| mutate_shared / small / 64 | micro | one contract operation | my-qbe | 0.166507 | 0.165550–0.167892 | zig-fast; zig-fast | 16.00× [15.963–16.187] | slower |
| mutate_shared / small / 64 | micro | one contract operation | rust | 0.010826 | 0.010668–0.011249 | zig-fast; zig-fast | 1.04× [1.028–1.058] | slower |
| mutate_shared / small / 64 | micro | one contract operation | go | 0.054478 | 0.053979–0.055188 | zig-fast; zig-fast | 5.24× [5.205–5.305] | slower |
| mutate_shared / small / 64 | micro | one contract operation | zig-safe | 0.016133 | 0.015805–0.016526 | zig-fast; zig-fast | 1.55× [1.543–1.572] | slower |
| mutate_shared / small / 64 | micro | one contract operation | zig-fast | 0.010404 | 0.010206–0.010573 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| mutate_shared / large / 1024 | micro | one contract operation | my-llvm | 0.230293 | 0.229166–0.231996 | rust; rust | 3.41× [3.384–3.413] | slower |
| mutate_shared / large / 1024 | micro | one contract operation | my-qbe | 0.285986 | 0.284568–0.289910 | rust; rust | 4.23× [4.205–4.247] | slower |
| mutate_shared / large / 1024 | micro | one contract operation | rust | 0.067633 | 0.067303–0.068802 | rust; rust | 1.00× [1.000–1.000] | fastest |
| mutate_shared / large / 1024 | micro | one contract operation | go | 0.585297 | 0.578130–0.597169 | rust; rust | 8.65× [8.572–8.712] | slower |
| mutate_shared / large / 1024 | micro | one contract operation | zig-safe | 0.147212 | 0.146344–0.148548 | rust; rust | 2.18× [2.165–2.181] | slower |
| mutate_shared / large / 1024 | micro | one contract operation | zig-fast | 0.114702 | 0.114102–0.117959 | rust; rust | 1.70× [1.685–1.706] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.192705 | 0.191754–0.195007 | rust; rust | 2.11× [2.107–2.125] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.949251 | 0.946955–0.952197 | rust; rust | 10.41× [10.375–10.463] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.091171 | 0.090209–0.092307 | rust; rust | 1.00× [1.000–1.000] | fastest |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.120381 | 0.119577–0.139852 | rust; rust | 1.32× [1.316–1.328] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.122313 | 0.121435–0.122822 | rust; rust | 1.34× [1.336–1.348] | slower |
| integer_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.108300 | 0.107854–0.109226 | rust; rust | 1.19× [1.184–1.195] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 11.749879 | 11.732915–11.837052 | rust; rust | 2.21× [2.204–2.226] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 60.039210 | 59.868397–61.093201 | rust; rust | 11.32× [11.267–11.361] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 5.305529 | 5.272949–5.341601 | rust; rust | 1.00× [1.000–1.000] | fastest |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | go | 7.203462 | 7.153455–7.268153 | rust; rust | 1.36× [1.351–1.362] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 7.138923 | 7.110526–7.247674 | rust; rust | 1.35× [1.339–1.355] | slower |
| integer_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 6.410349 | 6.353946–6.506538 | rust; rust | 1.21× [1.203–1.213] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.172203 | 0.171772–0.173765 | zig-fast; zig-fast | 2.43× [2.419–2.444] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.989858 | 0.983979–1.006460 | zig-fast; zig-fast | 13.98× [13.905–14.048] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.108331 | 0.107864–0.109176 | zig-fast; zig-fast | 1.53× [1.522–1.537] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.104219 | 0.103820–0.104774 | zig-fast; zig-fast | 1.47× [1.464–1.482] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.104251 | 0.103378–0.105063 | zig-fast; zig-fast | 1.47× [1.463–1.481] | slower |
| float_math / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.070782 | 0.070265–0.074735 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.588389 | 10.552745–10.614173 | zig-fast; zig-fast | 2.57× [2.559–2.575] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 62.601260 | 62.296268–63.193574 | zig-fast; zig-fast | 15.17× [15.119–15.238] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.535994 | 6.477919–6.575606 | zig-fast; zig-fast | 1.58× [1.578–1.592] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | go | 6.245548 | 6.218834–6.277262 | zig-fast; zig-fast | 1.51× [1.509–1.524] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 6.131444 | 6.097713–6.221732 | zig-fast; zig-fast | 1.49× [1.481–1.492] | slower |
| float_math / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.125319 | 4.091627–4.160860 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.160090 | 0.153649–0.161662 | zig-fast; zig-fast | 3.05× [3.016–3.079] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.704839 | 0.703984–0.717072 | zig-fast; zig-fast | 13.44× [13.405–13.512] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.052478 | 0.051832–0.053433 | zig-fast; zig-fast | 1.00× [0.996–1.007] | overlapping |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.100504 | 0.099799–0.101141 | zig-fast; zig-fast | 1.92× [1.911–1.930] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.117958 | 0.117021–0.118918 | zig-fast; zig-fast | 2.25× [2.240–2.264] | slower |
| branch_predictable / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.052455 | 0.051820–0.053131 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.409001 | 10.359319–11.037683 | zig-fast; zig-fast | 3.21× [3.192–3.215] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 44.473554 | 44.413943–44.682942 | zig-fast; zig-fast | 13.71× [13.643–13.726] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 3.297517 | 3.249678–3.372168 | zig-fast; zig-fast | 1.02× [1.008–1.023] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | go | 6.487171 | 6.459352–6.502082 | zig-fast; zig-fast | 2.00× [1.989–2.003] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 7.360620 | 7.327128–7.410439 | zig-fast; zig-fast | 2.27× [2.258–2.277] | slower |
| branch_predictable / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 3.244133 | 3.219684–3.329906 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.154812 | 0.153584–0.156254 | rust; rust | 2.17× [2.155–2.177] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.726290 | 0.724196–0.729949 | rust; rust | 10.16× [10.111–10.193] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.071458 | 0.070953–0.072228 | rust; rust | 1.00× [1.000–1.000] | fastest |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.106293 | 0.105139–0.107434 | rust; rust | 1.49× [1.473–1.494] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.128780 | 0.127340–0.129798 | rust; rust | 1.80× [1.795–1.810] | slower |
| branch_mixed / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.071538 | 0.071064–0.071831 | rust; rust | 1.00× [0.997–1.005] | overlapping |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.382506 | 10.291656–10.538149 | rust; rust | 2.23× [2.220–2.241] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 46.189616 | 46.072686–46.306747 | rust; rust | 9.93× [9.884–9.966] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 4.653777 | 4.624084–4.699375 | rust; rust | 1.00× [1.000–1.000] | fastest |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | go | 7.977431 | 7.931565–8.043350 | rust; rust | 1.71× [1.707–1.722] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 8.778942 | 8.701574–8.817611 | rust; rust | 1.89× [1.878–1.895] | slower |
| branch_mixed / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.674686 | 4.658924–4.721610 | rust; rust | 1.00× [1.001–1.009] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.263024 | 0.261579–0.274428 | rust; rust | 2.44× [2.439–2.451] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.036736 | 1.034055–1.061848 | rust; rust | 9.63× [9.613–9.658] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.107642 | 0.106787–0.108246 | rust; rust | 1.00× [1.000–1.000] | fastest |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.148511 | 0.147555–0.148746 | rust; rust | 1.38× [1.377–1.382] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.160053 | 0.158330–0.161339 | rust; rust | 1.49× [1.484–1.497] | slower |
| record_construct / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.136662 | 0.134975–0.141740 | rust; rust | 1.27× [1.263–1.275] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 16.260138 | 16.231827–18.955625 | rust; rust | 2.53× [2.518–2.540] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 66.409317 | 65.617064–79.054219 | rust; rust | 10.35× [10.200–10.420] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.418310 | 6.317029–8.383817 | rust; rust | 1.00× [1.000–1.000] | fastest |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | go | 9.089556 | 9.047254–10.332526 | rust; rust | 1.42× [1.393–1.419] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 9.586188 | 9.521103–11.233766 | rust; rust | 1.49× [1.484–1.503] | slower |
| record_construct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 8.538261 | 8.299855–8.877199 | rust; rust | 1.33× [1.317–1.338] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.293010 | 0.292036–0.294212 | rust; rust | 2.69× [2.688–2.705] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.512647 | 1.507554–1.531641 | rust; rust | 13.90× [13.878–13.986] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.108813 | 0.107983–0.109125 | rust; rust | 1.00× [1.000–1.000] | fastest |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.150275 | 0.149081–0.173664 | rust; rust | 1.38× [1.376–1.390] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.169850 | 0.167619–0.171079 | rust; rust | 1.56× [1.553–1.573] | slower |
| record_update / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.137168 | 0.136289–0.140876 | rust; rust | 1.26× [1.257–1.268] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 18.148822 | 18.082666–18.523361 | rust; rust | 2.84× [2.837–2.850] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 96.629376 | 96.377048–97.901494 | rust; rust | 15.13× [15.109–15.193] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.385214 | 6.325509–6.431624 | rust; rust | 1.00× [1.000–1.000] | fastest |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | go | 9.200067 | 9.155209–9.320884 | rust; rust | 1.44× [1.437–1.449] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 10.183884 | 10.109562–10.359739 | rust; rust | 1.59× [1.585–1.605] | slower |
| record_update / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 8.510524 | 8.321131–9.364473 | rust; rust | 1.33× [1.316–1.355] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.130449 | 0.129982–0.134730 | rust; rust | 2.99× [2.984–2.997] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.738973 | 0.734833–0.746920 | rust; rust | 16.93× [16.904–16.994] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.043636 | 0.043362–0.043805 | rust; rust | 1.00× [1.000–1.000] | fastest |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.063032 | 0.062773–0.063451 | rust; rust | 1.44× [1.443–1.450] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.061246 | 0.060789–0.061526 | rust; rust | 1.40× [1.401–1.408] | slower |
| call_direct / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.047309 | 0.046777–0.047520 | rust; rust | 1.08× [1.081–1.087] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 7.696961 | 7.681808–7.752065 | rust; rust | 4.02× [4.014–4.032] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 46.546155 | 46.471275–47.011000 | rust; rust | 24.34× [24.275–24.427] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 1.912433 | 1.898958–1.927066 | rust; rust | 1.00× [1.000–1.000] | fastest |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | go | 3.212544 | 3.195632–3.229860 | rust; rust | 1.68× [1.674–1.683] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 2.860276 | 2.843208–2.875215 | rust; rust | 1.50× [1.490–1.501] | slower |
| call_direct / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 1.915685 | 1.894055–1.926440 | rust; rust | 1.00× [0.997–1.005] | overlapping |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.166058 | 0.164394–0.171765 | zig-fast; zig-fast | 1.62× [1.612–1.637] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 0.755318 | 0.751618–0.778873 | zig-fast; zig-fast | 7.38× [7.350–7.409] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.112592 | 0.111779–0.115657 | zig-fast; zig-fast | 1.10× [1.095–1.104] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.133307 | 0.132574–0.138084 | zig-fast; zig-fast | 1.30× [1.294–1.308] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.158968 | 0.158044–0.180480 | zig-fast; zig-fast | 1.55× [1.545–1.560] | slower |
| call_indirect / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.102346 | 0.101646–0.103704 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 10.101111 | 9.759967–10.348584 | zig-fast; zig-fast | 1.69× [1.658–1.707] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 47.432067 | 47.224255–47.969274 | zig-fast; zig-fast | 7.95× [7.903–8.027] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 6.818840 | 6.776822–6.973399 | zig-fast; zig-fast | 1.14× [1.137–1.155] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | go | 8.130980 | 7.976353–8.197193 | zig-fast; zig-fast | 1.36× [1.352–1.373] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 9.617974 | 9.578465–9.694659 | zig-fast; zig-fast | 1.61× [1.605–1.623] | slower |
| call_indirect / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 5.964501 | 5.861051–6.020392 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.186275 | 0.179615–0.191190 | rust; rust | 3.97× [3.941–4.000] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.045043 | 1.036652–1.068586 | rust; rust | 22.27× [22.152–22.439] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.046928 | 0.046211–0.047148 | rust; rust | 1.00× [1.000–1.000] | fastest |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.100554 | 0.100191–0.101709 | rust; rust | 2.14× [2.133–2.149] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.107772 | 0.106486–0.108694 | rust; rust | 2.30× [2.287–2.306] | slower |
| option_handle / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.083105 | 0.081179–0.083431 | rust; rust | 1.77× [1.763–1.774] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 11.887652 | 11.805762–12.487106 | rust; rust | 5.21× [5.192–5.239] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 66.335723 | 66.021438–66.990915 | rust; rust | 29.09× [28.971–29.186] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 2.280723 | 2.252810–2.301438 | rust; rust | 1.00× [1.000–1.000] | fastest |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | go | 6.168273 | 6.113385–6.289092 | rust; rust | 2.70× [2.692–2.746] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 6.266359 | 6.202591–6.578687 | rust; rust | 2.75× [2.739–2.767] | slower |
| option_handle / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.993837 | 4.943862–5.053117 | rust; rust | 2.19× [2.178–2.205] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | my-llvm | 0.238349 | 0.237270–0.248663 | rust; rust | 3.90× [3.887–3.928] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | my-qbe | 1.093452 | 1.091478–1.106372 | rust; rust | 17.88× [17.851–17.945] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | rust | 0.061146 | 0.060551–0.061652 | rust; rust | 1.00× [1.000–1.000] | fastest |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | go | 0.128641 | 0.127482–0.130314 | rust; rust | 2.10× [2.095–2.113] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | zig-safe | 0.108203 | 0.106780–0.109746 | rust; rust | 1.77× [1.763–1.784] | slower |
| result_propagate / small / 64 | micro | one complete pass over SIZE fixtures | zig-fast | 0.072009 | 0.070940–0.072668 | rust; rust | 1.18× [1.171–1.181] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | my-llvm | 14.950026 | 14.905583–15.298923 | rust; rust | 4.51× [4.482–4.535] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | my-qbe | 69.574562 | 69.398186–70.075523 | rust; rust | 21.00× [20.862–21.074] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | rust | 3.312894 | 3.268359–3.349116 | rust; rust | 1.00× [1.000–1.000] | fastest |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | go | 7.936098 | 7.904821–8.011889 | rust; rust | 2.40× [2.379–2.403] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | zig-safe | 6.807218 | 6.729390–7.517787 | rust; rust | 2.05× [2.034–2.063] | slower |
| result_propagate / large / 4096 | micro | one complete pass over SIZE fixtures | zig-fast | 4.910073 | 4.803569–5.066655 | rust; rust | 1.48× [1.468–1.494] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | my-llvm | 0.118963 | 0.118488–0.120308 | rust; rust | 2.30× [2.293–2.316] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | my-qbe | 0.651689 | 0.647742–0.660896 | rust; rust | 12.61× [12.563–12.688] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | rust | 0.051678 | 0.051117–0.052189 | rust; rust | 1.00× [1.000–1.000] | fastest |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | go | 0.100487 | 0.099043–0.101923 | rust; rust | 1.94× [1.929–1.958] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | zig-safe | 0.078241 | 0.077273–0.079126 | rust; rust | 1.51× [1.504–1.524] | slower |
| binary_search / small / 16 | micro | one complete pass over SIZE fixtures | zig-fast | 0.074917 | 0.074540–0.075228 | rust; rust | 1.45× [1.444–1.458] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | my-llvm | 2.960449 | 2.947367–2.985492 | rust; rust | 2.02× [2.012–2.030] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | my-qbe | 25.487808 | 25.292795–25.881202 | rust; rust | 17.40× [17.270–17.496] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | rust | 1.465053 | 1.456156–1.472099 | rust; rust | 1.00× [1.000–1.000] | fastest |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | go | 2.408317 | 2.384007–2.430817 | rust; rust | 1.64× [1.629–1.650] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | zig-safe | 5.192899 | 5.147432–5.220232 | rust; rust | 3.54× [3.532–3.555] | slower |
| binary_search / large / 256 | micro | one complete pass over SIZE fixtures | zig-fast | 2.005368 | 1.988378–2.022163 | rust; rust | 1.37× [1.363–1.376] | slower |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | my-llvm | 0.101021 | 0.088804–0.125456 | zig-fast; zig-fast | 2.16× [1.867–2.381] | slower |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | my-qbe | 0.510565 | 0.436483–0.646296 | zig-fast; zig-fast | 10.92× [10.276–12.014] | slower |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | rust | 0.050895 | 0.044797–0.066864 | zig-fast; zig-fast | 1.09× [0.964–1.217] | overlapping |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | go | 0.126515 | 0.106154–0.157461 | zig-fast; zig-fast | 2.71× [2.382–2.947] | slower |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | zig-safe | 0.088118 | 0.073988–0.112292 | zig-fast; zig-fast | 1.89× [1.785–2.050] | slower |
| packet_decode / small / 16 | application | one complete pass over SIZE fixtures | zig-fast | 0.046737 | 0.038550–0.056075 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | my-llvm | 1.642064 | 1.564220–1.834406 | zig-fast; zig-fast | 2.50× [2.458–2.582] | slower |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | my-qbe | 8.289854 | 7.554027–9.033782 | zig-fast; zig-fast | 12.60× [12.221–13.239] | slower |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | rust | 0.787011 | 0.736534–0.838469 | zig-fast; zig-fast | 1.20× [1.150–1.224] | slower |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | go | 1.950685 | 1.827110–2.490381 | zig-fast; zig-fast | 2.96× [2.868–3.152] | slower |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | zig-safe | 1.341826 | 1.219492–1.726965 | zig-fast; zig-fast | 2.04× [2.000–2.150] | slower |
| packet_decode / large / 256 | application | one complete pass over SIZE fixtures | zig-fast | 0.657970 | 0.638675–0.693757 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.097029 | 0.094162–0.106421 | rust; rust | 2.00× [1.852–2.102] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.276329 | 0.266035–0.305045 | rust; rust | 5.70× [5.289–5.914] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.048475 | 0.045608–0.055936 | rust; rust | 1.00× [1.000–1.000] | fastest |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.061060 | 0.058423–0.075253 | rust; rust | 1.26× [1.158–1.322] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.081493 | 0.078298–0.092001 | rust; rust | 1.68× [1.563–1.731] | slower |
| list_scan / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.061390 | 0.058558–0.081685 | rust; rust | 1.27× [1.173–1.354] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 4.907286 | 4.580818–5.986948 | rust; rust | 1.55× [1.372–1.805] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 14.543074 | 13.662591–16.289529 | rust; rust | 4.59× [4.331–5.083] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 3.168305 | 2.752799–3.754718 | rust; rust | 1.00× [1.000–1.000] | fastest |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | go | 3.787343 | 3.390372–4.644621 | rust; rust | 1.20× [1.132–1.342] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 5.583677 | 4.914296–6.766743 | rust; rust | 1.76× [1.662–1.909] | slower |
| list_scan / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 3.832294 | 3.457328–5.069698 | rust; rust | 1.21× [1.129–1.518] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.387726 | 0.375732–0.396281 | zig-fast; zig-fast | 2.82× [2.739–2.843] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.740914 | 0.709612–0.807093 | zig-fast; zig-fast | 5.38× [5.273–5.485] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.184971 | 0.179250–0.192160 | zig-fast; zig-fast | 1.34× [1.306–1.365] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.252617 | 0.240809–0.267114 | zig-fast; zig-fast | 1.84× [1.801–1.871] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.289934 | 0.274746–0.309702 | zig-fast; zig-fast | 2.11× [2.062–2.138] | slower |
| list_append / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.137627 | 0.132819–0.151790 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 13.829897 | 13.367929–14.154150 | zig-fast; zig-fast | 2.21× [2.166–2.253] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 30.378034 | 29.721807–31.418467 | zig-fast; zig-fast | 4.86× [4.782–4.973] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 6.526121 | 6.272476–7.050786 | zig-fast; zig-fast | 1.04× [1.012–1.081] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | go | 11.507343 | 11.111685–12.960203 | zig-fast; zig-fast | 1.84× [1.811–1.905] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 12.538219 | 11.996828–13.233674 | zig-fast; zig-fast | 2.01× [1.954–2.045] | slower |
| list_append / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 6.252465 | 5.855742–6.384041 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.394648 | 0.390167–0.414366 | zig-fast; zig-fast | 2.60× [2.583–2.622] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.767658 | 0.760834–0.794603 | zig-fast; zig-fast | 5.06× [5.005–5.094] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.166869 | 0.165007–0.175093 | zig-fast; zig-fast | 1.10× [1.088–1.106] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.289041 | 0.287259–0.300968 | zig-fast; zig-fast | 1.90× [1.890–1.919] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.215339 | 0.212744–0.227067 | zig-fast; zig-fast | 1.42× [1.404–1.431] | slower |
| list_filter / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.151847 | 0.149646–0.166328 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 13.200490 | 13.127760–13.310690 | rust; rust | 2.35× [2.329–2.360] | slower |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 32.620213 | 32.374313–33.169240 | rust; rust | 5.81× [5.742–5.842] | slower |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 5.617805 | 5.562111–5.960629 | rust; rust | 1.00× [1.000–1.000] | fastest |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | go | 10.973084 | 10.914254–11.205725 | rust; rust | 1.95× [1.921–1.966] | slower |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 10.153294 | 10.119610–10.279985 | rust; rust | 1.81× [1.775–1.817] | slower |
| list_filter / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 7.292773 | 7.224573–7.550933 | rust; rust | 1.30× [1.284–1.313] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.518922 | 0.514858–0.532531 | zig-fast; zig-fast | 2.06× [2.051–2.073] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.835392 | 0.824148–0.865489 | zig-fast; zig-fast | 3.31× [3.301–3.331] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.623228 | 0.611799–0.646031 | zig-fast; zig-fast | 2.47× [2.437–2.492] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.460281 | 0.404676–0.474762 | zig-fast; zig-fast | 1.83× [1.784–1.860] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.492036 | 0.486508–0.497069 | zig-fast; zig-fast | 1.95× [1.944–1.963] | slower |
| dict_lookup / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.252098 | 0.249769–0.253922 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 52.693528 | 51.817611–54.385366 | go; go | 1.77× [1.741–1.774] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 77.152857 | 75.766499–77.727927 | go; go | 2.59× [2.554–2.603] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 40.688170 | 40.496917–41.290001 | go; go | 1.36× [1.350–1.375] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | go | 29.844554 | 29.440762–30.535072 | go; go | 1.00× [1.000–1.000] | fastest |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 52.287567 | 51.502816–53.163798 | go; go | 1.75× [1.734–1.769] | slower |
| dict_lookup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 41.244549 | 40.812173–41.918633 | go; go | 1.38× [1.363–1.394] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.583534 | 0.577489–0.834205 | zig-fast; zig-fast | 1.49× [1.485–1.507] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 1.004668 | 1.001452–1.015405 | zig-fast; zig-fast | 2.57× [2.563–2.587] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.867826 | 0.852189–0.883996 | zig-fast; zig-fast | 2.22× [2.206–2.235] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.559186 | 0.538136–0.570795 | zig-fast; zig-fast | 1.43× [1.407–1.454] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.520346 | 0.514887–0.526091 | zig-fast; zig-fast | 1.33× [1.327–1.343] | slower |
| dict_lookup_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.390639 | 0.387491–0.397357 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 67.611924 | 66.620147–68.518422 | go; go | 1.68× [1.668–1.699] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 96.110971 | 95.678178–97.774801 | go; go | 2.39× [2.373–2.417] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 58.349514 | 57.471236–66.203668 | go; go | 1.45× [1.443–1.472] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | go | 40.213548 | 39.521159–40.910912 | go; go | 1.00× [1.000–1.000] | fastest |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 62.646477 | 61.703606–63.941023 | go; go | 1.56× [1.545–1.571] | slower |
| dict_lookup_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 49.028400 | 48.087553–49.968332 | go; go | 1.22× [1.205–1.228] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 15.249135 | 15.137220–15.571205 | zig-fast; zig-fast | 6.15× [6.112–6.185] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 21.271190 | 21.104892–21.782200 | zig-fast; zig-fast | 8.57× [8.534–8.621] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | rust | 6.096233 | 6.050791–6.229926 | zig-fast; zig-fast | 2.46× [2.449–2.476] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | go | 8.354001 | 8.153644–8.634723 | zig-fast; zig-fast | 3.37× [3.342–3.390] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 4.963520 | 4.873928–5.157785 | zig-fast; zig-fast | 2.00× [1.985–2.033] | slower |
| dict_update / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 2.480908 | 2.458896–2.611547 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 1146.283522 | 1138.439287–1175.669374 | zig-fast; zig-fast | 2.64× [2.625–2.663] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 1494.704426 | 1486.699191–1510.602226 | zig-fast; zig-fast | 3.44× [3.433–3.450] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 465.484000 | 459.779548–475.491217 | zig-fast; zig-fast | 1.07× [1.064–1.081] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | go | 510.847713 | 505.808713–528.861148 | zig-fast; zig-fast | 1.18× [1.170–1.185] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 600.634661 | 597.671035–619.386409 | zig-fast; zig-fast | 1.38× [1.381–1.393] | slower |
| dict_update / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 434.066600 | 431.970887–440.488235 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 14.128393 | 13.958477–14.460473 | zig-fast; zig-fast | 2.86× [2.773–2.886] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 18.691992 | 18.549229–19.064667 | zig-fast; zig-fast | 3.78× [3.699–3.804] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | rust | 13.520708 | 13.384818–13.973506 | zig-fast; zig-fast | 2.73× [2.661–2.753] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | go | 9.718816 | 9.548165–9.776346 | zig-fast; zig-fast | 1.96× [1.913–1.985] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 6.500960 | 6.455262–6.886654 | zig-fast; zig-fast | 1.31× [1.286–1.331] | slower |
| dict_update_str / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 4.946870 | 4.835212–5.147636 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 1134.125324 | 1128.169577–1141.103563 | go; go | 1.67× [1.660–1.672] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 1389.167197 | 1378.903169–1400.186958 | go; go | 2.04× [2.033–2.048] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 1032.946662 | 979.037620–1051.544606 | go; go | 1.52× [1.495–1.537] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | go | 680.597479 | 670.265211–688.141592 | go; go | 1.00× [1.000–1.000] | fastest |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 828.660775 | 821.010183–841.907887 | go; go | 1.22× [1.213–1.224] | slower |
| dict_update_str / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 724.441817 | 716.417239–732.950986 | go; go | 1.06× [1.060–1.069] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 3.438448 | 3.408387–3.481854 | zig-fast; zig-fast | 11.90× [11.862–11.953] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 4.700406 | 4.659676–5.434568 | zig-fast; zig-fast | 16.27× [16.155–16.356] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.955582 | 0.948947–1.010891 | zig-fast; zig-fast | 3.31× [3.296–3.329] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.138039 | 1.114885–1.184988 | zig-fast; zig-fast | 3.94× [3.916–3.964] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.607950 | 0.600737–0.667081 | zig-fast; zig-fast | 2.10× [2.091–2.112] | slower |
| set_dedup / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.288900 | 0.286682–0.344891 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 220.853279 | 218.091425–224.600655 | zig-fast; zig-fast | 3.98× [3.965–4.015] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 292.050624 | 290.131026–296.362979 | zig-fast; zig-fast | 5.27× [5.260–5.299] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 61.052304 | 60.324826–62.513331 | zig-fast; zig-fast | 1.10× [1.094–1.109] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | go | 68.907769 | 68.465688–70.048182 | zig-fast; zig-fast | 1.24× [1.240–1.252] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 79.666972 | 79.370513–82.429078 | zig-fast; zig-fast | 1.44× [1.433–1.444] | slower |
| set_dedup / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 55.443204 | 54.990542–55.766476 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 4.538856 | 4.502503–5.064882 | zig-fast; zig-fast | 1211.99× [1192.136–1270.162] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 6.052979 | 6.002195–6.131194 | zig-fast; zig-fast | 1616.29× [1589.490–1694.399] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.078138 | 0.075776–0.084522 | zig-fast; zig-fast | 20.86× [20.353–22.110] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | go | 0.144844 | 0.141435–0.147699 | zig-fast; zig-fast | 38.68× [37.830–40.655] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.332753 | 0.328381–0.340079 | zig-fast; zig-fast | 88.85× [87.468–93.102] | slower |
| alloc_short / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.003745 | 0.003529–0.004127 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | my-llvm | 70.329891 | 70.026282–70.953208 | zig-fast; zig-fast | 18929.50× [17312.351–19029.641] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | my-qbe | 94.313391 | 93.663117–97.297726 | zig-fast; zig-fast | 25384.72× [23199.230–25509.874] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | rust | 1.192876 | 1.147815–1.225761 | zig-fast; zig-fast | 321.07× [291.914–325.880] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | go | 1.933491 | 1.873820–1.974002 | zig-fast; zig-fast | 520.40× [475.245–526.269] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | zig-safe | 5.192662 | 5.155872–5.281318 | zig-fast; zig-fast | 1397.62× [1278.432–1406.903] | slower |
| alloc_short / large / 1024 | micro | one complete SIZE-element dataset operation | zig-fast | 0.003715 | 0.003690–0.004689 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 2.823544 | 2.783429–2.858556 | zig-fast; zig-fast | 2.34× [2.323–2.354] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 4.248896 | 4.211015–4.335933 | zig-fast; zig-fast | 3.52× [3.490–3.536] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | rust | 1.290242 | 1.269383–1.309687 | zig-fast; zig-fast | 1.07× [1.060–1.075] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.812933 | 1.789856–1.822735 | zig-fast; zig-fast | 1.50× [1.487–1.508] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 1.245983 | 1.225771–1.316111 | zig-fast; zig-fast | 1.03× [1.021–1.049] | slower |
| alloc_retained / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 1.207437 | 1.193840–1.277185 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | my-llvm | 44.919344 | 44.505053–45.355082 | zig-fast; zig-fast | 2.28× [2.256–2.295] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | my-qbe | 65.667291 | 65.038699–66.559270 | zig-fast; zig-fast | 3.34× [3.302–3.359] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | rust | 20.588485 | 20.351041–21.206318 | zig-fast; zig-fast | 1.05× [1.036–1.055] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | go | 25.445855 | 25.174425–25.854379 | zig-fast; zig-fast | 1.29× [1.280–1.305] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | zig-safe | 20.442672 | 19.990476–20.915713 | zig-fast; zig-fast | 1.04× [1.023–1.049] | slower |
| alloc_retained / large / 1024 | micro | one complete SIZE-element dataset operation | zig-fast | 19.669600 | 19.474230–20.275376 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.746951 | 0.743765–0.767033 | my-llvm; my-llvm | 1.00× [1.000–1.000] | fastest |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.870354 | 0.865068–0.880132 | my-llvm; my-llvm | 1.17× [1.161–1.168] | slower |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | rust | 1.173336 | 1.160039–1.216407 | my-llvm; my-llvm | 1.57× [1.563–1.578] | slower |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.160251 | 1.143612–1.190173 | my-llvm; my-llvm | 1.55× [1.545–1.558] | slower |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 1.187669 | 1.173509–1.260868 | my-llvm; my-llvm | 1.59× [1.584–1.628] | slower |
| mutate_nested / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 1.097470 | 1.066189–1.177013 | my-llvm; my-llvm | 1.47× [1.450–1.495] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | my-llvm | 7.131864 | 7.047165–7.212595 | my-llvm; my-llvm | 1.00× [1.000–1.000] | fastest |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | my-qbe | 8.423610 | 8.272391–8.596646 | my-llvm; my-llvm | 1.18× [1.166–1.193] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | rust | 20.093748 | 19.711181–20.948217 | my-llvm; my-llvm | 2.82× [2.797–2.831] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | go | 17.374169 | 17.204728–17.915328 | my-llvm; my-llvm | 2.44× [2.421–2.451] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | zig-safe | 19.898725 | 19.705410–20.285184 | my-llvm; my-llvm | 2.79× [2.764–2.806] | slower |
| mutate_nested / large / 1024 | micro | one complete SIZE-element dataset operation | zig-fast | 18.171501 | 17.941106–18.718541 | my-llvm; my-llvm | 2.55× [2.533–2.568] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 0.278555 | 0.277652–0.280964 | zig-fast; zig-fast | 1.65× [1.637–1.669] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 0.535166 | 0.532113–0.539260 | zig-fast; zig-fast | 3.18× [3.146–3.207] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.226090 | 0.224134–0.232662 | zig-fast; zig-fast | 1.34× [1.330–1.354] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | go | 1.064548 | 1.058134–1.069040 | zig-fast; zig-fast | 6.32× [6.249–6.364] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.268392 | 0.267132–0.269502 | zig-fast; zig-fast | 1.59× [1.578–1.608] | slower |
| sort_int / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.168408 | 0.162707–0.171256 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 44.236096 | 43.981024–44.599008 | my-llvm; my-llvm | 1.00× [1.000–1.000] | fastest |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 56.625583 | 56.394649–56.951887 | my-llvm; my-llvm | 1.28× [1.278–1.285] | slower |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 63.128697 | 62.973009–63.389690 | my-llvm; my-llvm | 1.43× [1.426–1.432] | slower |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | go | 232.509963 | 231.934770–234.672319 | my-llvm; my-llvm | 5.26× [5.250–5.280] | slower |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 64.987206 | 64.281153–65.681913 | my-llvm; my-llvm | 1.47× [1.465–1.474] | slower |
| sort_int / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 44.883897 | 44.521495–45.229922 | my-llvm; my-llvm | 1.01× [1.010–1.019] | slower |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | my-llvm | 1.201025 | 1.193473–1.229869 | zig-fast; zig-fast | 2.13× [2.108–2.156] | slower |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | my-qbe | 1.936476 | 1.928154–2.049764 | zig-fast; zig-fast | 3.44× [3.387–3.481] | slower |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | rust | 0.662666 | 0.659666–0.691894 | zig-fast; zig-fast | 1.18× [1.164–1.191] | slower |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | go | 7.276274 | 7.243401–7.308134 | zig-fast; zig-fast | 12.93× [12.704–13.079] | slower |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | zig-safe | 0.783526 | 0.777360–0.809957 | zig-fast; zig-fast | 1.39× [1.375–1.409] | slower |
| sort_records / small / 64 | micro | one complete SIZE-element dataset operation | zig-fast | 0.562819 | 0.555685–0.582483 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | my-llvm | 61.564986 | 60.782515–62.203752 | rust; rust | 1.19× [1.179–1.201] | slower |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | my-qbe | 99.196706 | 98.441356–99.801028 | rust; rust | 1.91× [1.907–1.930] | slower |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | rust | 51.816163 | 50.606986–52.428659 | rust; rust | 1.00× [1.000–1.000] | fastest |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | go | 1259.208020 | 1250.843823–1274.320156 | rust; rust | 24.30× [24.179–24.504] | slower |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | zig-safe | 115.154033 | 114.564141–118.119429 | rust; rust | 2.22× [2.214–2.241] | slower |
| sort_records / large / 4096 | micro | one complete SIZE-element dataset operation | zig-fast | 92.222970 | 91.257039–93.724396 | rust; rust | 1.78× [1.770–1.796] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 5.022591 | 5.000789–5.117619 | rust; rust | 7.00× [6.937–7.038] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 5.622215 | 5.581530–5.676234 | rust; rust | 7.84× [7.763–7.870] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | rust | 0.717446 | 0.709752–0.733109 | rust; rust | 1.00× [1.000–1.000] | fastest |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | go | 0.811824 | 0.805464–0.832602 | rust; rust | 1.13× [1.117–1.147] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 1.979158 | 1.962691–2.137206 | rust; rust | 2.76× [2.730–2.776] | slower |
| lox_eval / small / 16 | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 1.920326 | 1.915799–1.941165 | rust; rust | 2.68× [2.654–2.688] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 75.793706 | 75.370103–81.777047 | rust; rust | 7.11× [7.049–7.184] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 82.979434 | 82.499577–85.337014 | rust; rust | 7.78× [7.725–7.846] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | rust | 10.663957 | 10.558434–11.198932 | rust; rust | 1.00× [1.000–1.000] | fastest |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | go | 12.636007 | 12.524790–13.347812 | rust; rust | 1.18× [1.175–1.206] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 30.532537 | 30.204245–34.114986 | rust; rust | 2.86× [2.837–2.889] | slower |
| lox_eval / large / 256 | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 29.790073 | 29.427315–33.176441 | rust; rust | 2.79× [2.773–2.818] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | my-llvm | 0.008584 | 0.008489–0.008844 | my-llvm; my-llvm | 1.00× [1.000–1.000] | fastest |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | my-qbe | 0.067104 | 0.066451–0.067851 | my-llvm; my-llvm | 7.82× [7.777–7.855] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | rust | 0.017677 | 0.017485–0.017801 | my-llvm; my-llvm | 2.06× [2.048–2.074] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | go | 0.023797 | 0.022452–0.025868 | my-llvm; my-llvm | 2.77× [2.725–2.848] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | zig-safe | 0.027821 | 0.026511–0.028624 | my-llvm; my-llvm | 3.24× [3.192–3.275] | slower |
| bytes_scan / small / 64 | micro | one full byte-buffer scan | zig-fast | 0.012115 | 0.011873–0.012708 | my-llvm; my-llvm | 1.41× [1.394–1.425] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | my-llvm | 0.354322 | 0.352110–0.359734 | my-llvm; my-llvm | 1.00× [1.000–1.000] | fastest |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | my-qbe | 3.365649 | 3.349289–3.404748 | my-llvm; my-llvm | 9.50× [9.468–9.559] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | rust | 1.062588 | 1.059031–1.070593 | my-llvm; my-llvm | 3.00× [2.992–3.013] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | go | 1.015552 | 0.983385–1.043996 | my-llvm; my-llvm | 2.87× [2.827–2.886] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | zig-safe | 1.332787 | 1.301821–1.449408 | my-llvm; my-llvm | 3.76× [3.724–3.921] | slower |
| bytes_scan / large / 4096 | micro | one full byte-buffer scan | zig-fast | 0.701500 | 0.694144–0.724749 | my-llvm; my-llvm | 1.98× [1.968–1.993] | slower |
| string_equal / small / 64 | micro | one string equality comparison | my-llvm | 0.015973 | 0.015816–0.017229 | rust; rust | 5.30× [5.232–5.373] | slower |
| string_equal / small / 64 | micro | one string equality comparison | my-qbe | 0.036159 | 0.035810–0.036473 | rust; rust | 12.00× [11.837–12.052] | slower |
| string_equal / small / 64 | micro | one string equality comparison | rust | 0.003014 | 0.002985–0.003183 | rust; rust | 1.00× [1.000–1.000] | fastest |
| string_equal / small / 64 | micro | one string equality comparison | go | 0.004544 | 0.004446–0.004883 | rust; rust | 1.51× [1.488–1.531] | slower |
| string_equal / small / 64 | micro | one string equality comparison | zig-safe | 0.004100 | 0.004079–0.004155 | rust; rust | 1.36× [1.342–1.370] | slower |
| string_equal / small / 64 | micro | one string equality comparison | zig-fast | 0.003833 | 0.003812–0.003887 | rust; rust | 1.27× [1.257–1.277] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | my-llvm | 0.044741 | 0.044146–0.045692 | rust; rust | 1.45× [1.437–1.459] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | my-qbe | 0.719654 | 0.718259–0.723891 | rust; rust | 23.26× [23.220–23.348] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | rust | 0.030934 | 0.030655–0.032733 | rust; rust | 1.00× [1.000–1.000] | fastest |
| string_equal / large / 4096 | micro | one string equality comparison | go | 0.037661 | 0.036921–0.038552 | rust; rust | 1.22× [1.208–1.228] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | zig-safe | 0.065006 | 0.064713–0.065106 | rust; rust | 2.10× [2.094–2.105] | slower |
| string_equal / large / 4096 | micro | one string equality comparison | zig-fast | 0.050498 | 0.050203–0.056745 | rust; rust | 1.63× [1.624–1.636] | slower |
| string_search / small / 64 | micro | one substring search | my-llvm | 0.019868 | 0.019754–0.020526 | my-llvm; my-llvm | 1.00× [1.000–1.000] | fastest |
| string_search / small / 64 | micro | one substring search | my-qbe | 0.030441 | 0.030334–0.030994 | my-llvm; my-llvm | 1.53× [1.527–1.537] | slower |
| string_search / small / 64 | micro | one substring search | rust | 0.042948 | 0.042553–0.043372 | my-llvm; my-llvm | 2.16× [2.155–2.176] | slower |
| string_search / small / 64 | micro | one substring search | go | 0.024878 | 0.024502–0.025238 | my-llvm; my-llvm | 1.25× [1.244–1.255] | slower |
| string_search / small / 64 | micro | one substring search | zig-safe | 0.089753 | 0.089531–0.090168 | my-llvm; my-llvm | 4.52× [4.504–4.529] | slower |
| string_search / small / 64 | micro | one substring search | zig-fast | 0.074835 | 0.074550–0.078400 | my-llvm; my-llvm | 3.77× [3.756–3.786] | slower |
| string_search / large / 4096 | micro | one substring search | my-llvm | 0.102400 | 0.101344–0.104497 | my-qbe; my-qbe | 1.04× [1.032–1.047] | slower |
| string_search / large / 4096 | micro | one substring search | my-qbe | 0.098385 | 0.097235–0.099388 | my-qbe; my-qbe | 1.00× [1.000–1.000] | fastest |
| string_search / large / 4096 | micro | one substring search | rust | 1.297969 | 1.293860–1.311773 | my-qbe; my-qbe | 13.19× [13.102–13.256] | slower |
| string_search / large / 4096 | micro | one substring search | go | 0.644747 | 0.642029–0.662546 | my-qbe; my-qbe | 6.55× [6.510–6.586] | slower |
| string_search / large / 4096 | micro | one substring search | zig-safe | 2.986394 | 2.980326–3.555604 | my-qbe; my-qbe | 30.35× [30.161–30.504] | slower |
| string_search / large / 4096 | micro | one substring search | zig-fast | 2.635363 | 2.628279–2.663317 | my-qbe; my-qbe | 26.79× [26.630–26.905] | slower |
| string_split / small / 64 | micro | one full document split and result fold | my-llvm | 3.562898 | 3.533588–3.755087 | rust; rust | 6.46× [6.382–6.582] | slower |
| string_split / small / 64 | micro | one full document split and result fold | my-qbe | 4.414834 | 4.382319–4.529585 | rust; rust | 8.00× [7.909–8.052] | slower |
| string_split / small / 64 | micro | one full document split and result fold | rust | 0.551926 | 0.545457–0.580980 | rust; rust | 1.00× [1.000–1.000] | fastest |
| string_split / small / 64 | micro | one full document split and result fold | go | 1.039326 | 1.033963–1.062956 | rust; rust | 1.88× [1.859–1.902] | slower |
| string_split / small / 64 | micro | one full document split and result fold | zig-safe | 1.035447 | 1.024854–1.088771 | rust; rust | 1.88× [1.854–1.891] | slower |
| string_split / small / 64 | micro | one full document split and result fold | zig-fast | 0.959937 | 0.953558–0.969210 | rust; rust | 1.74× [1.713–1.758] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | my-llvm | 217.421568 | 214.577440–221.929673 | rust; rust | 7.81× [7.688–7.830] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | my-qbe | 266.544700 | 263.378543–269.355930 | rust; rust | 9.57× [9.447–9.600] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | rust | 27.847009 | 27.480374–28.498827 | rust; rust | 1.00× [1.000–1.000] | fastest |
| string_split / large / 4096 | micro | one full document split and result fold | go | 66.274384 | 65.799089–68.678658 | rust; rust | 2.38× [2.354–2.394] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | zig-safe | 62.281814 | 61.552984–65.371667 | rust; rust | 2.24× [2.209–2.249] | slower |
| string_split / large / 4096 | micro | one full document split and result fold | zig-fast | 58.462590 | 58.194322–60.331765 | rust; rust | 2.10× [2.079–2.106] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | my-llvm | 0.422322 | 0.419779–0.436478 | rust; rust | 1.92× [1.905–1.924] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | my-qbe | 0.556329 | 0.553527–0.566567 | rust; rust | 2.53× [2.506–2.534] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | rust | 0.220151 | 0.218380–0.230497 | rust; rust | 1.00× [1.000–1.000] | fastest |
| string_join / small / 64 | micro | one full fragment join and output fold | go | 0.407553 | 0.402779–0.416691 | rust; rust | 1.85× [1.836–1.858] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | zig-safe | 0.313697 | 0.309888–0.333320 | rust; rust | 1.42× [1.410–1.436] | slower |
| string_join / small / 64 | micro | one full fragment join and output fold | zig-fast | 0.270474 | 0.267170–0.280155 | rust; rust | 1.23× [1.215–1.241] | slower |
| string_join / large / 4096 | micro | one full fragment join and output fold | my-llvm | 23.537180 | 23.331554–23.738131 | rust; rust | 1.75× [1.742–1.765] | slower |
| string_join / large / 4096 | micro | one full fragment join and output fold | my-qbe | 28.673110 | 28.304805–29.174266 | rust; rust | 2.14× [2.120–2.153] | slower |
| string_join / large / 4096 | micro | one full fragment join and output fold | rust | 13.428394 | 13.298062–13.556592 | rust; rust | 1.00× [1.000–1.000] | fastest |
| string_join / large / 4096 | micro | one full fragment join and output fold | go | 25.722846 | 25.424163–26.095756 | rust; rust | 1.92× [1.901–1.929] | slower |
| string_join / large / 4096 | micro | one full fragment join and output fold | zig-safe | 17.940311 | 17.716939–18.315579 | rust; rust | 1.34× [1.323–1.340] | slower |
| string_join / large / 4096 | micro | one full fragment join and output fold | zig-fast | 16.667212 | 16.475515–16.982000 | rust; rust | 1.24× [1.232–1.248] | slower |
| int_parse / small / 64 | micro | one strict signed decimal parse | my-llvm | 0.010065 | 0.010013–0.010438 | rust; rust | 2.24× [2.234–2.276] | slower |
| int_parse / small / 64 | micro | one strict signed decimal parse | my-qbe | 0.017953 | 0.017728–0.018251 | rust; rust | 4.00× [3.995–4.027] | slower |
| int_parse / small / 64 | micro | one strict signed decimal parse | rust | 0.004484 | 0.004457–0.004564 | rust; rust | 1.00× [1.000–1.000] | fastest |
| int_parse / small / 64 | micro | one strict signed decimal parse | go | 0.024022 | 0.023736–0.024156 | rust; rust | 5.36× [5.339–5.383] | slower |
| int_parse / small / 64 | micro | one strict signed decimal parse | zig-safe | 0.005725 | 0.005697–0.005821 | rust; rust | 1.28× [1.273–1.287] | slower |
| int_parse / small / 64 | micro | one strict signed decimal parse | zig-fast | 0.005718 | 0.005681–0.005775 | rust; rust | 1.28× [1.270–1.284] | slower |
| int_parse / large / 4096 | micro | one strict signed decimal parse | my-llvm | 0.010593 | 0.010535–0.010986 | rust; rust | 2.09× [2.081–2.106] | slower |
| int_parse / large / 4096 | micro | one strict signed decimal parse | my-qbe | 0.018778 | 0.018614–0.019658 | rust; rust | 3.71× [3.698–3.720] | slower |
| int_parse / large / 4096 | micro | one strict signed decimal parse | rust | 0.005059 | 0.005037–0.005091 | rust; rust | 1.00× [1.000–1.000] | fastest |
| int_parse / large / 4096 | micro | one strict signed decimal parse | go | 0.027066 | 0.026970–0.027260 | rust; rust | 5.35× [5.332–5.366] | slower |
| int_parse / large / 4096 | micro | one strict signed decimal parse | zig-safe | 0.006737 | 0.006703–0.006769 | rust; rust | 1.33× [1.326–1.336] | slower |
| int_parse / large / 4096 | micro | one strict signed decimal parse | zig-fast | 0.006236 | 0.006182–0.006348 | rust; rust | 1.23× [1.221–1.237] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | my-llvm | 0.063616 | 0.063193–0.065410 | rust; rust | 4.39× [4.331–4.412] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | my-qbe | 0.088835 | 0.088288–0.089303 | rust; rust | 6.12× [6.050–6.144] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | rust | 0.014506 | 0.014414–0.014945 | rust; rust | 1.00× [1.000–1.000] | fastest |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | go | 0.016277 | 0.016097–0.016388 | rust; rust | 1.12× [1.102–1.125] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | zig-safe | 0.040278 | 0.039867–0.041021 | rust; rust | 2.78× [2.726–2.789] | slower |
| int_format / small / 64 | micro | one signed decimal formatting and output fold | zig-fast | 0.032447 | 0.032261–0.032961 | rust; rust | 2.24× [2.214–2.249] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | my-llvm | 0.070020 | 0.069665–0.070319 | rust; rust | 4.61× [4.475–4.640] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | my-qbe | 0.091211 | 0.090806–0.091690 | rust; rust | 6.01× [5.829–6.057] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | rust | 0.015176 | 0.014998–0.015763 | rust; rust | 1.00× [1.000–1.000] | fastest |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | go | 0.017594 | 0.017367–0.017930 | rust; rust | 1.16× [1.123–1.172] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | zig-safe | 0.042828 | 0.042256–0.044621 | rust; rust | 2.82× [2.731–2.844] | slower |
| int_format / large / 4096 | micro | one signed decimal formatting and output fold | zig-fast | 0.036053 | 0.035869–0.036363 | rust; rust | 2.38× [2.300–2.399] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | my-llvm | 2.278091 | 2.263251–2.350583 | zig-fast; zig-fast | 11.98× [11.916–12.029] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | my-qbe | 3.037653 | 3.028522–3.065568 | zig-fast; zig-fast | 15.97× [15.899–16.082] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | rust | 0.346405 | 0.343399–0.374670 | zig-fast; zig-fast | 1.82× [1.811–1.831] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | go | 0.643523 | 0.639258–0.660433 | zig-fast; zig-fast | 3.38× [3.360–3.398] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | zig-safe | 0.245155 | 0.242592–0.248623 | zig-fast; zig-fast | 1.29× [1.282–1.295] | slower |
| word_count / small / 16 | application | one complete tokenize/count/fold job | zig-fast | 0.190169 | 0.188813–0.194548 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| word_count / large / 256 | application | one complete tokenize/count/fold job | my-llvm | 21.140240 | 20.923469–21.799657 | zig-fast; zig-fast | 8.56× [8.484–8.603] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | my-qbe | 28.543348 | 28.348157–29.819489 | zig-fast; zig-fast | 11.56× [11.493–11.638] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | rust | 3.892369 | 3.859014–3.983232 | zig-fast; zig-fast | 1.58× [1.566–1.586] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | go | 9.959342 | 9.914094–10.512233 | zig-fast; zig-fast | 4.03× [4.010–4.060] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | zig-safe | 3.128602 | 3.087294–3.231162 | zig-fast; zig-fast | 1.27× [1.261–1.275] | slower |
| word_count / large / 256 | application | one complete tokenize/count/fold job | zig-fast | 2.469500 | 2.453288–2.547716 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | my-llvm | 24.019810 | 23.484361–24.230986 | zig-fast; zig-fast | 7.91× [7.843–7.972] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | my-qbe | 35.183806 | 34.656577–35.904679 | zig-fast; zig-fast | 11.59× [11.517–11.623] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | rust | 4.204205 | 4.130647–4.372587 | zig-fast; zig-fast | 1.38× [1.378–1.391] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | go | 5.351719 | 5.239254–5.582415 | zig-fast; zig-fast | 1.76× [1.754–1.783] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | zig-safe | 3.839362 | 3.757605–4.422693 | zig-fast; zig-fast | 1.26× [1.259–1.278] | slower |
| csv_aggregate / small / 16 | application | one complete CSV parse/validate/group/fold job | zig-fast | 3.036261 | 2.979408–3.080423 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | my-llvm | 396.748554 | 391.280003–399.291950 | zig-fast; zig-fast | 7.44× [7.393–7.457] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | my-qbe | 577.140198 | 572.226617–593.017811 | zig-fast; zig-fast | 10.83× [10.749–10.861] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | rust | 68.713250 | 67.705663–74.294227 | zig-fast; zig-fast | 1.29× [1.278–1.297] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | go | 82.811626 | 81.161951–88.679551 | zig-fast; zig-fast | 1.55× [1.530–1.560] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | zig-safe | 66.520100 | 65.403272–77.668633 | zig-fast; zig-fast | 1.25× [1.233–1.251] | slower |
| csv_aggregate / large / 256 | application | one complete CSV parse/validate/group/fold job | zig-fast | 53.305727 | 52.679354–59.815157 | zig-fast; zig-fast | 1.00× [1.000–1.000] | fastest |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 161.419804 | 160.060445–178.912919 | rust; rust | 22.60× [22.307–23.261] | slower |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 217.201112 | 213.343105–243.647008 | rust; rust | 30.41× [30.146–31.829] | slower |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 7.143203 | 6.845362–7.832951 | rust; rust | 1.00× [1.000–1.000] | fastest |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | go | 30.515255 | 30.151004–34.690366 | rust; rust | 4.27× [4.238–4.447] | slower |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 11.923693 | 11.615599–13.987789 | rust; rust | 1.67× [1.643–1.697] | slower |
| json_transform / small / 16 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 8.453003 | 8.252691–9.208665 | rust; rust | 1.18× [1.164–1.217] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 3091.019630 | 2750.473232–3235.734500 | rust; rust | 24.88× [22.461–24.883] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 4157.303953 | 3627.747504–4319.852453 | rust; rust | 33.46× [29.815–33.464] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 124.233978 | 112.671819–135.836062 | rust; rust | 1.00× [1.000–1.000] | fastest |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | go | 543.441420 | 479.191051–583.816754 | rust; rust | 4.37× [4.242–4.471] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 230.414435 | 212.943196–258.728188 | rust; rust | 1.85× [1.722–1.979] | slower |
| json_transform / large / 256 | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 187.251467 | 168.927873–204.137996 | rust; rust | 1.51× [1.451–1.528] | slower |
