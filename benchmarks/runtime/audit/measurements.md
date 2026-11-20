# Audited targets

Each value is runtime divided by the fastest saved median for that benchmark and size. Lower is better; these fixed targets allow future ratios below 1.00. Full precision, sizes, units and intervals are in [evidence.json](evidence.json).

| Benchmark | Small LLVM / QBE | Large LLVM / QBE | Small / large winner |
|---|---:|---:|---|
| `record_reads` | 1.41 / 2.86 | 1.49 / 3.17 | rust / rust |
| `tagged_stack` | 4.37 / 5.52 | 4.37 / 5.52 | rust / rust |
| `mutate_unique` | 1.70 / 9.50 | 1.69 / 9.47 | rust / rust |
| `mutate_shared` | 11.33 / 16.00 | 3.41 / 4.23 | zig-fast / rust |
| `integer_math` | 2.11 / 10.41 | 2.21 / 11.32 | rust / rust |
| `float_math` | 2.43 / 13.98 | 2.57 / 15.17 | zig-fast / zig-fast |
| `branch_predictable` | 3.05 / 13.44 | 3.21 / 13.71 | zig-fast / zig-fast |
| `branch_mixed` | 2.17 / 10.16 | 2.23 / 9.93 | rust / rust |
| `record_construct` | 2.44 / 9.63 | 2.53 / 10.35 | rust / rust |
| `record_update` | 2.69 / 13.90 | 2.84 / 15.13 | rust / rust |
| `call_direct` | 2.99 / 16.93 | 4.02 / 24.34 | rust / rust |
| `call_indirect` | 1.62 / 7.38 | 1.69 / 7.95 | zig-fast / zig-fast |
| `option_handle` | 3.97 / 22.27 | 5.21 / 29.09 | rust / rust |
| `result_propagate` | 3.90 / 17.88 | 4.51 / 21.00 | rust / rust |
| `binary_search` | 2.30 / 12.61 | 2.02 / 17.40 | rust / rust |
| `packet_decode` | 2.16 / 10.92 | 2.50 / 12.60 | zig-fast / zig-fast |
| `list_scan` | 2.00 / 5.70 | 1.55 / 4.59 | rust / rust |
| `list_append` | 2.82 / 5.38 | 2.21 / 4.86 | zig-fast / zig-fast |
| `list_filter` | 2.60 / 5.06 | 2.35 / 5.81 | zig-fast / rust |
| `dict_lookup` | 2.06 / 3.31 | 1.77 / 2.59 | zig-fast / go |
| `dict_lookup_str` | 1.49 / 2.57 | 1.68 / 2.39 | zig-fast / go |
| `dict_update` | 6.15 / 8.57 | 2.64 / 3.44 | zig-fast / zig-fast |
| `dict_update_str` | 2.86 / 3.78 | 1.67 / 2.04 | zig-fast / go |
| `set_dedup` | 11.90 / 16.27 | 3.98 / 5.27 | zig-fast / zig-fast |
| `alloc_short` | 1211.99 / 1616.29 | 18929.50 / 25384.72 | zig-fast / zig-fast |
| `alloc_retained` | 2.34 / 3.52 | 2.28 / 3.34 | zig-fast / zig-fast |
| `mutate_nested` | 1.00 / 1.17 | 1.00 / 1.18 | my-llvm / my-llvm |
| `sort_int` | 1.65 / 3.18 | 1.00 / 1.28 | zig-fast / my-llvm |
| `sort_records` | 2.13 / 3.44 | 1.19 / 1.91 | zig-fast / rust |
| `lox_eval` | 7.00 / 7.84 | 7.11 / 7.78 | rust / rust |
| `bytes_scan` | 1.00 / 7.82 | 1.00 / 9.50 | my-llvm / my-llvm |
| `string_equal` | 5.30 / 12.00 | 1.45 / 23.26 | rust / rust |
| `string_search` | 1.00 / 1.53 | 1.04 / 1.00 | my-llvm / my-qbe |
| `string_split` | 6.46 / 8.00 | 7.81 / 9.57 | rust / rust |
| `string_join` | 1.92 / 2.53 | 1.75 / 2.14 | rust / rust |
| `int_parse` | 2.24 / 4.00 | 2.09 / 3.71 | rust / rust |
| `int_format` | 4.39 / 6.12 | 4.61 / 6.01 | rust / rust |
| `word_count` | 11.98 / 15.97 | 8.56 / 11.56 | zig-fast / zig-fast |
| `csv_aggregate` | 7.91 / 11.59 | 7.44 / 10.83 | zig-fast / zig-fast |
| `json_transform` | 22.60 / 30.41 | 24.88 / 33.46 | rust / rust |
