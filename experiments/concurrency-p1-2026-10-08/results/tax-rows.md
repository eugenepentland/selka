Wall times are native CLOCK_MONOTONIC kernel times, with the median
one-iteration startup subtracted. Each time below is the median of
the three batch medians; each ratio is the median of the three
within-batch ratios. Consequently ratios need not equal the ratio
of the two displayed times.

| corpus / arm | cells | wall geomean vs base | cells >1.03 | verdict |
|---|---:|---:|---:|---|
| 46 rows / p1 | 92 | 0.998711 | 4 | FAIL |

CPU 10 under cpu10.lock. One-minute load across timed samples: 1.53–3.19.

| row | size | base ms | p1 ms | p1/base |
|---|---:|---:|---:|---:|
| record_reads | 4096 | 15.3431 | 15.3746 | 1.00142 |
| record_reads | 64 | 15.3048 | 15.3605 | 1.00364 |
| tagged_stack | 4096 | 29.3186 | 29.3703 | 1.00039 |
| tagged_stack | 64 | 29.4234 | 29.2754 | 0.99872 |
| mutate_unique | 4096 | 12.8734 | 12.8292 | 0.99656 |
| mutate_unique | 64 | 12.8941 | 12.8753 | 1.00230 |
| mutate_shared | 4096 | 0.2599 | 0.2556 | 0.97011 |
| mutate_shared | 64 | 0.2439 | 0.2474 | 1.01722 |
| record_construct | 4096 | 22.8154 | 23.0578 | 1.01062 |
| record_construct | 64 | 22.9941 | 22.9480 | 0.99726 |
| record_update | 4096 | 22.9662 | 23.2056 | 1.00326 |
| record_update | 64 | 23.7573 | 23.7521 | 0.99978 |
| option_handle | 4096 | 7.6091 | 7.6152 | 1.00380 |
| option_handle | 64 | 8.6347 | 8.6426 | 1.01429 |
| result_propagate | 4096 | 14.4260 | 14.5644 | 1.00721 |
| result_propagate | 64 | 13.7788 | 13.8417 | 0.99432 |
| list_scan | 4096 | 15.1744 | 15.0631 | 0.99549 |
| list_scan | 64 | 15.7072 | 15.4564 | 0.98403 |
| list_append | 4096 | 24.1508 | 24.6696 | 1.02148 |
| list_append | 64 | 24.9831 | 25.6212 | 1.02554 |
| list_filter | 4096 | 28.6299 | 28.8245 | 1.00788 |
| list_filter | 64 | 33.7592 | 33.5647 | 0.99424 |
| alloc_short | 4096 | 4.5067 | 4.5814 | 1.00204 |
| alloc_short | 64 | 4.6257 | 4.6343 | 1.00122 |
| alloc_retained | 4096 | 32.1438 | 31.9296 | 0.99171 |
| alloc_retained | 64 | 32.3954 | 32.5044 | 1.00341 |
| mutate_nested | 4096 | 4.7404 | 4.6492 | 0.99940 |
| mutate_nested | 64 | 5.6017 | 5.6107 | 0.99851 |
| bytes_scan | 4096 | 0.1969 | 0.1974 | 1.01915 |
| bytes_scan | 64 | 0.9118 | 0.9362 | 1.03434 |
| string_equal | 4096 | 2.3710 | 2.3567 | 0.99400 |
| string_equal | 64 | 0.6950 | 0.6833 | 0.96872 |
| string_search | 4096 | 4.0992 | 4.1030 | 1.00229 |
| string_search | 64 | 0.6413 | 0.6632 | 1.03401 |
| string_split | 4096 | 24.0596 | 23.7869 | 0.98866 |
| string_split | 64 | 25.6321 | 25.7190 | 1.00339 |
| string_join | 4096 | 4.3135 | 4.2550 | 0.99061 |
| string_join | 64 | 5.0222 | 5.1264 | 1.00698 |
| dict_lookup | 4096 | 57.8025 | 57.6759 | 0.99876 |
| dict_lookup | 64 | 56.6232 | 56.8577 | 1.00443 |
| dict_lookup_str | 4096 | 88.3080 | 84.8793 | 0.96271 |
| dict_lookup_str | 64 | 74.8585 | 73.8888 | 0.98705 |
| dict_update | 4096 | 228.8548 | 225.1271 | 0.98637 |
| dict_update | 64 | 175.4902 | 177.3997 | 1.00036 |
| dict_update_str | 4096 | 303.8593 | 308.8104 | 1.01629 |
| dict_update_str | 64 | 232.5027 | 235.1244 | 1.01128 |
| set_dedup | 4096 | 94.8390 | 94.8225 | 1.00406 |
| set_dedup | 64 | 111.2336 | 110.0485 | 0.98935 |
| int_parse | 4096 | 25.4366 | 26.1010 | 1.02876 |
| int_parse | 64 | 24.3168 | 24.1252 | 0.99212 |
| int_format | 4096 | 63.7959 | 63.3788 | 0.99550 |
| int_format | 64 | 58.7727 | 58.2485 | 0.99108 |
| call_indirect | 4096 | 1.1752 | 1.1613 | 0.99694 |
| call_indirect | 64 | 1.1732 | 1.2080 | 1.00683 |
| sort_int | 4096 | 16.7936 | 16.8407 | 1.00276 |
| sort_int | 64 | 3.5796 | 3.5398 | 0.99082 |
| sort_records | 4096 | 11.7794 | 11.7469 | 0.99718 |
| sort_records | 64 | 15.3891 | 14.7682 | 0.95966 |
| int_math | 4096 | 1.3705 | 1.3870 | 1.00653 |
| int_math | 64 | 1.8661 | 1.8438 | 0.99400 |
| float_math | 4096 | 5.7500 | 5.8200 | 1.00178 |
| float_math | 64 | 6.2957 | 6.3226 | 1.00021 |
| call_direct | 4096 | 1.2051 | 1.1834 | 1.00947 |
| call_direct | 64 | 1.2270 | 1.2161 | 0.99796 |
| branch_predictable | 4096 | 1.5476 | 1.5470 | 0.99342 |
| branch_predictable | 64 | 1.8774 | 1.8834 | 1.00190 |
| branch_mixed | 4096 | 1.5467 | 1.5289 | 0.98924 |
| branch_mixed | 64 | 1.8862 | 1.8902 | 0.99736 |
| binary_search | 4096 | 11.7774 | 11.1965 | 0.95275 |
| binary_search | 64 | 6.8839 | 6.8204 | 0.99816 |
| word_count | 4096 | 13.3966 | 12.9090 | 0.96230 |
| word_count | 64 | 17.9932 | 17.9283 | 0.99023 |
| csv_aggregate | 4096 | 44.1378 | 44.1674 | 1.00067 |
| csv_aggregate | 64 | 40.5859 | 41.1675 | 1.01273 |
| json_transform | 4096 | 51.5794 | 53.6428 | 1.04001 |
| json_transform | 64 | 53.6671 | 55.4151 | 1.03265 |
| packet_decode | 4096 | 5.8236 | 5.6596 | 0.97631 |
| packet_decode | 64 | 5.6247 | 5.5327 | 0.99312 |
| lox_eval | 4096 | 8.0783 | 8.1261 | 0.99820 |
| lox_eval | 64 | 8.1371 | 8.1830 | 1.00044 |
| tree_build_walk | 4096 | 18.6150 | 17.8077 | 0.96210 |
| tree_build_walk | 64 | 13.7837 | 12.9511 | 0.95502 |
| record_pass | 4096 | 10.8854 | 10.9605 | 0.99659 |
| record_pass | 64 | 13.3038 | 13.1020 | 1.00302 |
| grid_dp | 4096 | 21.4872 | 21.5960 | 1.00437 |
| grid_dp | 64 | 17.7335 | 17.6621 | 0.99597 |
| union_find | 4096 | 29.4788 | 29.4495 | 0.99901 |
| union_find | 64 | 16.5631 | 16.5765 | 1.01305 |
| float_format | 4096 | 10.7724 | 10.8736 | 1.00940 |
| float_format | 64 | 12.1163 | 12.1258 | 0.99893 |
| buffer_write | 4096 | 12.6719 | 12.7230 | 1.00235 |
| buffer_write | 64 | 14.3582 | 14.2679 | 0.99371 |
