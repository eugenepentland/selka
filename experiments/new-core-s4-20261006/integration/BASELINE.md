# S4-0 runtime baseline

Source: `d357bbda0` (ordered design and row merges from S3 exit `82c125dd`).

CPU 10; seven interleaved rounds, three startup samples, frozen Zig ReleaseSafe and Rust references for the inherited rows, locally built S4 references. All 46 rows have matching checksums across all four measured configurations. **88/92 cells meet both 1.10 gates**; the four misses are the known S4-V work: `grid_dp` and `union_find` at both sizes.

| Row | new / Zig 4096 | new / Zig 64 | new / old 4096 | new / old 64 |
|---|---:|---:|---:|---:|
| `record_reads` | 0.7326 | 0.7267 | 0.7205 | 0.7092 |
| `tagged_stack` | 0.6893 | 0.6930 | 0.5263 | 0.5258 |
| `mutate_unique` | 0.8603 | 0.8600 | 0.8398 | 0.8489 |
| `mutate_shared` | 0.5642 | 0.6447 | 0.6717 | 0.0918 |
| `record_construct` | 0.2187 | 0.2172 | 0.1984 | 0.2044 |
| `record_update` | 0.5554 | 0.5452 | 0.5281 | 0.5376 |
| `option_handle` | 0.3058 | 0.3321 | 0.4952 | 0.6025 |
| `result_propagate` | 0.4997 | 0.4699 | 0.5871 | 0.6271 |
| `list_scan` | 0.8739 | 0.8676 | 1.0401 | 1.0211 |
| `list_append` | 0.5758 | 0.5659 | 0.9812 | 0.6771 |
| `list_filter` | 0.7677 | 0.7538 | 0.8788 | 0.5948 |
| `alloc_short` | 0.2231 | 0.2289 | 0.0199 | 0.0205 |
| `alloc_retained` | 0.4249 | 0.4798 | 0.2339 | 0.2412 |
| `mutate_nested` | 0.1696 | 0.1957 | 0.4421 | 0.3172 |
| `bytes_scan` | 0.0373 | 0.1416 | 0.6132 | 1.0023 |
| `string_equal` | 0.1816 | 0.9097 | 0.9483 | 0.9248 |
| `string_search` | 0.0335 | 0.1766 | 1.0300 | 0.8583 |
| `string_split` | 0.9322 | 0.9417 | 0.3020 | 0.3086 |
| `string_join` | 0.2567 | 0.2979 | 0.7559 | 0.5960 |
| `dict_lookup` | 0.2959 | 0.4930 | 0.4985 | 0.8961 |
| `dict_lookup_str` | 0.3681 | 0.6193 | 0.3747 | 0.6882 |
| `dict_update` | 0.3463 | 0.5899 | 0.2298 | 0.2493 |
| `dict_update_str` | 0.3715 | 0.6159 | 0.2645 | 0.2844 |
| `set_dedup` | 0.3040 | 0.7642 | 0.1405 | 0.1702 |
| `int_parse` | 0.9979 | 1.0901 | 0.6228 | 0.6397 |
| `int_format` | 0.3184 | 0.3171 | 0.3200 | 0.2997 |
| `call_indirect` | 0.0333 | 0.0326 | 0.0599 | 0.0610 |
| `sort_int` | 0.6921 | 0.5365 | 1.0275 | 0.8112 |
| `sort_records` | 0.2642 | 0.7894 | 0.5704 | 0.6045 |
| `int_math` | 0.0456 | 0.0591 | 0.0409 | 0.0542 |
| `float_math` | 0.2407 | 0.2424 | 0.1890 | 0.2020 |
| `call_direct` | 0.0992 | 0.0780 | 0.0986 | 0.1010 |
| `branch_predictable` | 0.0514 | 0.0632 | 0.0978 | 0.1197 |
| `branch_mixed` | 0.0427 | 0.0546 | 0.0957 | 0.1196 |
| `binary_search` | 0.2380 | 0.6373 | 0.2283 | 0.5436 |
| `word_count` | 0.7528 | 0.9725 | 0.1220 | 0.1322 |
| `csv_aggregate` | 1.0800 | 1.0658 | 0.2285 | 0.2539 |
| `json_transform` | 0.9978 | 1.0422 | 0.2072 | 0.2114 |
| `packet_decode` | 0.8338 | 0.8222 | 1.0442 | 1.0616 |
| `lox_eval` | 0.4077 | 0.4092 | 0.3272 | 0.3248 |
| `tree_build_walk` | 0.7040 | 0.7070 | 0.2368 | 0.2367 |
| `record_pass` | 0.6768 | 0.7074 | 0.5047 | 0.5299 |
| `grid_dp` | 3.4427 | 3.5705 | 2.4213 | 0.8266 |
| `union_find` | 2.0485 | 2.2628 | 1.0433 | 0.8939 |
| `float_format` | 0.7349 | 0.7421 | 0.5717 | 0.5690 |
| `buffer_write` | 0.8846 | 0.8677 | 1.0391 | 1.0136 |

Raw samples, commands and ratios: `base-all46-run01.json`; build command logs: `.mylang-cache/s4/base-all46/build-logs/` (to be archived with the qualification receipts).

## Coverage

The four inherited corpora reproduce S3: 3,633/3,639 functions accepted. All modules of each pinned port were checked from private copies, including test-only modules. Lox: **279/462 real functions**; EDA: **1,755/1,756 real functions**. Adding the 25 and 118 generated `main` stubs reproduces the plan's 304/487 and 1,873/1,874. The stubs are excluded from the real-function totals. The only port refusals are 183 capability-field functions and one dynamic assert message.

Authoritative coverage: `base-coverage-run04/summary.json` and six retained stdout/stderr pairs. Earlier entry-only and synthetic aggregate-entry experiments are retained as preflight runs 01–03.
