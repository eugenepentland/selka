# Microbenchmark ownership evidence

Validated 91/91 receipts; 0 pending. This report keeps each case and documented iteration unit separate. No overall score pools unrelated workloads.

Current MyLang guests use the supported LLVM-only command path. Historical my-llvm/my-qbe receipts retain their original compiler and executable identities; there is no fresh QBE measurement. Parity compares six arms and uses the canonical Rust native-target policy; expanded compares seven arms and uses portable Rust, Go GOAMD64=v1, and host-default Zig. Canonical parity MyLang ports retain fixed literal bounds, while supplied Zig opaqueN and Rust black_box obscure loop bounds. These are the supplied canonical ports, not a claim of uniform optimization barriers or target policy. Target/API differences remain part of each suite comparison.

Parity time is full-process wall time, including startup; very short cases can be sensitive to the launch floor. Expanded time is native kernel ns per documented CLI iteration, excluding fixture setup. Child peak RSS is the median of three separate uninstrumented GNU-time runs and includes setup/runtime state. Counted runs are separate: allocation/reallocation/cumulative bytes, managed peak, exit-live and RC events include the whole program and fixture setup. Direct destruction is not an RC event. Foreign allocation counters are unavailable.

Ratios are numerator/comparison arm; above one means slower. Intervals use a deterministic 95% paired bootstrap of the ratio of medians, jointly resampling matched round indices. Intervals containing one do not establish a speed difference. These single-session exploratory intervals need independent confirmation. Counted time never supplies a timing sample.

The inherited calibration can label <5% growth termination as slowest_arm_budget even when the fastest pilot is just below 50 ms and the slowest is well below 1 s. Raw fastest/slowest durations and all limits appear below; that reason alone does not establish reaching the slowest cap.

Sibling activity above5%: 0 cell/sibling entries; full percentages are retained in JSON. Average activity cannot rule out brief interference or enforce exclusive CPU ownership.

## Per-case comparisons

| Cell | Unit/time | Original RC | Migrated RC | Zero RC | Zero/original [95%] | Migrated/original [95%] | Zero/migrated [95%] |
|---|---|---:|---:|---:|---|---|---|
| parity/alloc_churn | wall ns/execution | 53409511.000 | 53452269.000 | 53497003.000 | 1.002 [0.995, 1.004] | 1.001 [0.996, 1.004] | 1.001 [0.998, 1.003] |
| parity/bytes_scan | wall ns/execution | 16382766.000 | 16271312.000 | 16516112.000 | 1.008 [0.975, 1.030] | 0.993 [0.970, 1.011] | 1.015 [0.999, 1.037] |
| parity/calls | wall ns/execution | 105021767.000 | 105347295.000 | 105393315.000 | 1.004 [0.999, 1.015] | 1.003 [0.998, 1.008] | 1.000 [0.995, 1.011] |
| parity/dict_count | wall ns/execution | 9880491.000 | 9571836.000 | 51176167.000 | 5.180 [4.781, 5.454] | 0.969 [0.899, 1.040] | 5.347 [5.095, 5.522] |
| parity/fib | wall ns/execution | 52887473.000 | 52181483.000 | 52986567.000 | 1.002 [0.997, 1.012] | 0.987 [0.975, 1.000] | 1.015 [1.010, 1.023] |
| parity/float_loop | wall ns/execution | 32243722.000 | 32391362.000 | 32383532.000 | 1.004 [1.001, 1.017] | 1.005 [1.001, 1.032] | 1.000 [0.985, 1.005] |
| parity/intloop | wall ns/execution | 103797387.000 | 103836048.000 | 103800653.000 | 1.000 [0.995, 1.010] | 1.000 [0.987, 1.002] | 1.000 [0.998, 1.010] |
| parity/list_append_sum | wall ns/execution | 42935735.000 | 42963042.000 | 42140175.000 | 0.981 [0.960, 1.003] | 1.001 [0.969, 1.035] | 0.981 [0.956, 1.019] |
| parity/list_records | wall ns/execution | 51405539.000 | 50762479.000 | 51476697.000 | 1.001 [0.980, 1.036] | 0.987 [0.961, 1.044] | 1.014 [0.992, 1.037] |
| parity/records | wall ns/execution | 63208718.000 | 63212368.000 | 63199361.000 | 1.000 [0.997, 1.007] | 1.000 [0.998, 1.016] | 1.000 [0.987, 1.005] |
| parity/str_build | wall ns/execution | 38732316.000 | 38240392.000 | 40246021.000 | 1.039 [1.012, 1.072] | 0.987 [0.970, 1.014] | 1.052 [1.021, 1.092] |
| expanded/alloc_retained/large | ns/iteration: one complete SIZE-element dataset operation | 8255.191 | 7783.566 | 7759.429 | 0.940 [0.859, 1.030] | 0.943 [0.908, 0.999] | 0.997 [0.944, 1.093] |
| expanded/alloc_retained/small | ns/iteration: one complete SIZE-element dataset operation | 511.761 | 514.600 | 460.355 | 0.900 [0.879, 0.908] | 1.006 [0.982, 1.013] | 0.895 [0.884, 0.909] |
| expanded/alloc_short/large | ns/iteration: one complete SIZE-element dataset operation | 1249.156 | 1248.467 | 1245.361 | 0.997 [0.995, 1.000] | 0.999 [0.996, 1.003] | 0.998 [0.995, 1.001] |
| expanded/alloc_short/small | ns/iteration: one complete SIZE-element dataset operation | 89.876 | 89.973 | 88.237 | 0.982 [0.977, 0.983] | 1.001 [0.998, 1.003] | 0.981 [0.978, 0.985] |
| expanded/binary_search/large | ns/iteration: one complete pass over SIZE fixtures | 1369.305 | 1370.415 | 1372.056 | 1.002 [0.992, 1.009] | 1.001 [0.994, 1.007] | 1.001 [0.992, 1.008] |
| expanded/binary_search/small | ns/iteration: one complete pass over SIZE fixtures | 46.653 | 46.588 | 45.535 | 0.976 [0.967, 0.987] | 0.999 [0.990, 1.004] | 0.977 [0.972, 0.992] |
| expanded/branch_mixed/large | ns/iteration: one complete pass over SIZE fixtures | 1627.706 | 1619.135 | 1623.634 | 0.997 [0.991, 1.004] | 0.995 [0.987, 1.004] | 1.003 [0.995, 1.009] |
| expanded/branch_mixed/small | ns/iteration: one complete pass over SIZE fixtures | 33.281 | 33.256 | 33.044 | 0.993 [0.990, 0.997] | 0.999 [0.994, 1.005] | 0.994 [0.988, 1.000] |
| expanded/branch_predictable/large | ns/iteration: one complete pass over SIZE fixtures | 1624.257 | 1626.991 | 1620.579 | 0.998 [0.994, 1.004] | 1.002 [0.999, 1.007] | 0.996 [0.991, 1.001] |
| expanded/branch_predictable/small | ns/iteration: one complete pass over SIZE fixtures | 33.180 | 33.351 | 33.112 | 0.998 [0.991, 1.003] | 1.005 [0.999, 1.008] | 0.993 [0.990, 0.999] |
| expanded/bytes_scan/large | ns/iteration: one full byte-buffer scan | 46.883 | 46.829 | 44.678 | 0.953 [0.952, 0.955] | 0.999 [0.997, 1.005] | 0.954 [0.949, 0.956] |
| expanded/bytes_scan/small | ns/iteration: one full byte-buffer scan | 3.476 | 3.457 | 3.478 | 1.001 [0.995, 1.010] | 0.995 [0.990, 1.001] | 1.006 [1.004, 1.011] |
| expanded/call_direct/large | ns/iteration: one complete pass over SIZE fixtures | 273.022 | 273.244 | 273.036 | 1.000 [0.996, 1.002] | 1.001 [0.997, 1.004] | 0.999 [0.996, 1.003] |
| expanded/call_direct/small | ns/iteration: one complete pass over SIZE fixtures | 5.473 | 5.490 | 5.494 | 1.004 [0.994, 1.016] | 1.003 [0.996, 1.014] | 1.001 [0.984, 1.010] |
| expanded/call_indirect/large | ns/iteration: one complete pass over SIZE fixtures | 274.550 | 274.564 | 274.239 | 0.999 [0.988, 1.009] | 1.000 [0.988, 1.013] | 0.999 [0.992, 1.004] |
| expanded/call_indirect/small | ns/iteration: one complete pass over SIZE fixtures | 5.571 | 5.571 | 5.684 | 1.020 [1.013, 1.028] | 1.000 [0.993, 1.017] | 1.020 [1.000, 1.029] |
| expanded/csv_aggregate/large | ns/iteration: one complete CSV parse/validate/group/fold job | 69575.078 | 69503.896 | 67140.441 | 0.965 [0.960, 0.968] | 0.999 [0.995, 1.000] | 0.966 [0.964, 0.969] |
| expanded/csv_aggregate/small | ns/iteration: one complete CSV parse/validate/group/fold job | 4254.771 | 4257.617 | 4145.140 | 0.974 [0.967, 0.990] | 1.001 [0.986, 1.006] | 0.974 [0.968, 0.989] |
| expanded/dict_lookup/large | ns/iteration: one complete SIZE-element dataset operation | 14248.826 | 14226.983 | 14228.207 | 0.999 [0.988, 1.011] | 0.998 [0.991, 1.011] | 1.000 [0.988, 1.010] |
| expanded/dict_lookup/small | ns/iteration: one complete SIZE-element dataset operation | 229.970 | 230.434 | 230.064 | 1.000 [0.997, 1.007] | 1.002 [0.995, 1.005] | 0.998 [0.996, 1.004] |
| expanded/dict_lookup_str/large | ns/iteration: one complete SIZE-element dataset operation | 23127.441 | 22701.100 | 28921.923 | 1.251 [1.236, 1.279] | 0.982 [0.964, 1.005] | 1.274 [1.270, 1.296] |
| expanded/dict_lookup_str/small | ns/iteration: one complete SIZE-element dataset operation | 303.260 | 303.828 | 380.697 | 1.255 [1.246, 1.258] | 1.002 [0.998, 1.006] | 1.253 [1.249, 1.256] |
| expanded/dict_update/large | ns/iteration: one complete SIZE-element dataset operation | 217826.772 | 217836.614 | 214870.798 | 0.986 [0.980, 0.995] | 1.000 [0.996, 1.007] | 0.986 [0.981, 0.992] |
| expanded/dict_update/small | ns/iteration: one complete SIZE-element dataset operation | 2765.804 | 2765.327 | 2736.627 | 0.989 [0.969, 0.995] | 1.000 [0.978, 1.010] | 0.990 [0.979, 0.997] |
| expanded/dict_update_str/large | ns/iteration: one complete SIZE-element dataset operation | 307501.696 | 306982.143 | 456234.248 | 1.484 [1.479, 1.500] | 0.998 [0.993, 1.003] | 1.486 [1.480, 1.505] |
| expanded/dict_update_str/small | ns/iteration: one complete SIZE-element dataset operation | 3847.638 | 3850.454 | 6728.585 | 1.749 [1.718, 1.765] | 1.001 [0.990, 1.024] | 1.747 [1.695, 1.761] |
| expanded/float_math/large | ns/iteration: one complete pass over SIZE fixtures | 4198.880 | 4204.641 | 4192.670 | 0.999 [0.995, 1.005] | 1.001 [0.997, 1.007] | 0.997 [0.993, 1.003] |
| expanded/float_math/small | ns/iteration: one complete pass over SIZE fixtures | 68.426 | 68.529 | 68.522 | 1.001 [0.997, 1.006] | 1.002 [0.998, 1.006] | 1.000 [0.995, 1.003] |
| expanded/int_format/large | ns/iteration: one signed decimal formatting and output fold | 14.308 | 14.281 | 27.014 | 1.888 [1.882, 1.894] | 0.998 [0.995, 1.005] | 1.892 [1.882, 1.895] |
| expanded/int_format/small | ns/iteration: one signed decimal formatting and output fold | 13.338 | 13.332 | 25.753 | 1.931 [1.925, 1.956] | 1.000 [0.995, 1.006] | 1.932 [1.924, 1.955] |
| expanded/int_parse/large | ns/iteration: one strict signed decimal parse | 6.511 | 6.482 | 6.565 | 1.008 [1.002, 1.021] | 0.996 [0.985, 1.007] | 1.013 [1.003, 1.024] |
| expanded/int_parse/small | ns/iteration: one strict signed decimal parse | 6.137 | 6.138 | 6.135 | 1.000 [0.995, 1.004] | 1.000 [0.995, 1.006] | 1.000 [0.993, 1.003] |
| expanded/integer_math/large | ns/iteration: one complete pass over SIZE fixtures | 328.936 | 329.147 | 328.597 | 0.999 [0.986, 1.008] | 1.001 [0.991, 1.019] | 0.998 [0.975, 1.007] |
| expanded/integer_math/small | ns/iteration: one complete pass over SIZE fixtures | 8.173 | 8.174 | 8.146 | 0.997 [0.991, 0.999] | 1.000 [0.996, 1.003] | 0.997 [0.993, 1.000] |
| expanded/json_transform/large | ns/iteration: one complete JSON parse/filter/transform/serialize/fold job | 161179.606 | 161464.118 | 231444.809 | 1.436 [1.424, 1.443] | 1.002 [0.994, 1.006] | 1.433 [1.427, 1.440] |
| expanded/json_transform/small | ns/iteration: one complete JSON parse/filter/transform/serialize/fold job | 9562.029 | 9583.934 | 13743.859 | 1.437 [1.430, 1.444] | 1.002 [0.998, 1.005] | 1.434 [1.430, 1.443] |
| expanded/list_append/large | ns/iteration: one complete SIZE-element dataset operation | 5869.883 | 5852.403 | 5706.680 | 0.972 [0.964, 0.983] | 0.997 [0.994, 1.004] | 0.975 [0.968, 0.985] |
| expanded/list_append/small | ns/iteration: one complete SIZE-element dataset operation | 98.561 | 98.529 | 104.371 | 1.059 [1.055, 1.070] | 1.000 [0.992, 1.007] | 1.059 [1.055, 1.071] |
| expanded/list_filter/large | ns/iteration: one complete SIZE-element dataset operation | 6560.308 | 6581.779 | 6531.553 | 0.996 [0.989, 1.010] | 1.003 [0.995, 1.018] | 0.992 [0.985, 1.003] |
| expanded/list_filter/small | ns/iteration: one complete SIZE-element dataset operation | 121.793 | 122.366 | 127.795 | 1.049 [1.042, 1.054] | 1.005 [0.999, 1.008] | 1.044 [1.037, 1.051] |
| expanded/list_scan/large | ns/iteration: one complete SIZE-element dataset operation | 3662.098 | 3665.909 | 3622.076 | 0.989 [0.985, 0.996] | 1.001 [0.998, 1.007] | 0.988 [0.984, 0.993] |
| expanded/list_scan/small | ns/iteration: one complete SIZE-element dataset operation | 60.449 | 60.325 | 59.105 | 0.978 [0.975, 0.981] | 0.998 [0.995, 1.001] | 0.980 [0.976, 0.984] |
| expanded/lox_eval/large | ns/iteration: one complete bytecode program execution with SIZE loop iterations | 11202.441 | 11199.829 | 11209.173 | 1.001 [0.995, 1.005] | 1.000 [0.994, 1.002] | 1.001 [0.998, 1.005] |
| expanded/lox_eval/small | ns/iteration: one complete bytecode program execution with SIZE loop iterations | 746.789 | 746.023 | 757.914 | 1.015 [1.005, 1.019] | 0.999 [0.991, 1.003] | 1.016 [1.008, 1.021] |
| expanded/mutate_nested/large | ns/iteration: one complete SIZE-element dataset operation | 2295.447 | 2224.356 | 26293.257 | 11.455 [11.392, 11.863] | 0.969 [0.959, 1.024] | 11.821 [11.496, 11.922] |
| expanded/mutate_nested/small | ns/iteration: one complete SIZE-element dataset operation | 180.948 | 180.902 | 1627.660 | 8.995 [8.943, 9.084] | 1.000 [0.993, 1.010] | 8.997 [8.937, 9.106] |
| expanded/mutate_shared/large | ns/iteration: one contract operation | 71.718 | 71.796 | 82.298 | 1.148 [1.142, 1.156] | 1.001 [0.998, 1.008] | 1.146 [1.139, 1.154] |
| expanded/mutate_shared/small | ns/iteration: one contract operation | 10.708 | 10.736 | 12.942 | 1.209 [1.191, 1.231] | 1.003 [0.953, 1.025] | 1.205 [1.181, 1.229] |
| expanded/mutate_unique/large | ns/iteration: one contract operation | 3.414 | 3.409 | 3.347 | 0.980 [0.979, 0.983] | 0.999 [0.997, 1.001] | 0.982 [0.980, 0.984] |
| expanded/mutate_unique/small | ns/iteration: one contract operation | 3.411 | 3.412 | 3.346 | 0.981 [0.980, 0.983] | 1.000 [0.998, 1.004] | 0.981 [0.978, 0.983] |
| expanded/option_handle/large | ns/iteration: one complete pass over SIZE fixtures | 1824.914 | 1826.327 | 1818.253 | 0.996 [0.994, 1.002] | 1.001 [0.997, 1.009] | 0.996 [0.992, 1.000] |
| expanded/option_handle/small | ns/iteration: one complete pass over SIZE fixtures | 36.227 | 36.172 | 35.757 | 0.987 [0.973, 1.009] | 0.998 [0.989, 1.011] | 0.989 [0.980, 1.009] |
| expanded/packet_decode/large | ns/iteration: one complete pass over SIZE fixtures | 841.308 | 843.205 | 838.769 | 0.997 [0.992, 1.010] | 1.002 [0.993, 1.011] | 0.995 [0.986, 1.010] |
| expanded/packet_decode/small | ns/iteration: one complete pass over SIZE fixtures | 55.626 | 55.737 | 56.101 | 1.009 [0.989, 1.015] | 1.002 [0.994, 1.007] | 1.007 [0.990, 1.010] |
| expanded/record_construct/large | ns/iteration: one complete pass over SIZE fixtures | 2078.007 | 2075.304 | 2072.839 | 0.998 [0.992, 1.000] | 0.999 [0.994, 1.001] | 0.999 [0.997, 1.001] |
| expanded/record_construct/small | ns/iteration: one complete pass over SIZE fixtures | 34.463 | 34.501 | 34.407 | 0.998 [0.988, 1.012] | 1.001 [0.989, 1.011] | 0.997 [0.986, 1.009] |
| expanded/record_reads/large | ns/iteration: one contract operation | 3.958 | 3.966 | 3.955 | 0.999 [0.994, 1.013] | 1.002 [0.996, 1.010] | 0.997 [0.992, 1.011] |
| expanded/record_reads/small | ns/iteration: one contract operation | 3.827 | 3.820 | 3.822 | 0.999 [0.995, 1.001] | 0.998 [0.995, 1.001] | 1.000 [0.998, 1.003] |
| expanded/record_update/large | ns/iteration: one complete pass over SIZE fixtures | 5592.744 | 5596.726 | 5589.603 | 0.999 [0.995, 1.004] | 1.001 [0.997, 1.005] | 0.999 [0.994, 1.003] |
| expanded/record_update/small | ns/iteration: one complete pass over SIZE fixtures | 92.047 | 91.508 | 92.057 | 1.000 [0.995, 1.007] | 0.994 [0.982, 1.001] | 1.006 [0.997, 1.022] |
| expanded/result_propagate/large | ns/iteration: one complete pass over SIZE fixtures | 5177.696 | 5151.942 | 5466.646 | 1.056 [1.038, 1.063] | 0.995 [0.978, 1.004] | 1.061 [1.048, 1.065] |
| expanded/result_propagate/small | ns/iteration: one complete pass over SIZE fixtures | 78.478 | 78.540 | 78.477 | 1.000 [0.997, 1.006] | 1.001 [0.996, 1.010] | 0.999 [0.994, 1.006] |
| expanded/set_dedup/large | ns/iteration: one complete SIZE-element dataset operation | 23685.631 | 23568.846 | 23264.764 | 0.982 [0.975, 0.994] | 0.995 [0.988, 1.005] | 0.987 [0.979, 0.994] |
| expanded/set_dedup/small | ns/iteration: one complete SIZE-element dataset operation | 437.773 | 438.788 | 428.901 | 0.980 [0.977, 0.984] | 1.002 [0.994, 1.009] | 0.977 [0.972, 0.985] |
| expanded/sort_int/large | ns/iteration: one complete SIZE-element dataset operation | 16886.285 | 16814.510 | 16822.795 | 0.996 [0.961, 1.048] | 0.996 [0.968, 1.041] | 1.000 [0.956, 1.042] |
| expanded/sort_int/small | ns/iteration: one complete SIZE-element dataset operation | 147.383 | 147.190 | 149.618 | 1.015 [1.011, 1.018] | 0.999 [0.995, 1.001] | 1.017 [1.013, 1.021] |
| expanded/sort_records/large | ns/iteration: one complete SIZE-element dataset operation | 27196.773 | 27599.018 | 62573.525 | 2.301 [2.070, 2.324] | 1.015 [0.922, 1.106] | 2.267 [2.047, 2.304] |
| expanded/sort_records/small | ns/iteration: one complete SIZE-element dataset operation | 544.828 | 544.407 | 905.868 | 1.663 [1.646, 1.668] | 0.999 [0.989, 1.006] | 1.664 [1.645, 1.669] |
| expanded/string_equal/large | ns/iteration: one string equality comparison | 11.776 | 11.818 | 11.834 | 1.005 [0.995, 1.008] | 1.004 [0.996, 1.007] | 1.001 [0.993, 1.006] |
| expanded/string_equal/small | ns/iteration: one string equality comparison | 4.058 | 4.009 | 4.061 | 1.001 [0.987, 1.011] | 0.988 [0.983, 1.007] | 1.013 [0.985, 1.022] |
| expanded/string_join/large | ns/iteration: one full fragment join and output fold | 4397.797 | 4225.928 | 5766.001 | 1.311 [1.285, 1.374] | 0.961 [0.945, 1.005] | 1.364 [1.308, 1.378] |
| expanded/string_join/small | ns/iteration: one full fragment join and output fold | 82.704 | 82.623 | 95.152 | 1.151 [1.139, 1.161] | 0.999 [0.990, 1.009] | 1.152 [1.144, 1.156] |
| expanded/string_search/large | ns/iteration: one substring search | 102.166 | 102.032 | 102.116 | 1.000 [0.995, 1.005] | 0.999 [0.996, 1.004] | 1.001 [0.996, 1.007] |
| expanded/string_search/small | ns/iteration: one substring search | 16.317 | 16.319 | 16.405 | 1.005 [1.000, 1.013] | 1.000 [0.994, 1.005] | 1.005 [1.000, 1.012] |
| expanded/string_split/large | ns/iteration: one full document split and result fold | 57485.251 | 57405.536 | 113631.301 | 1.977 [1.961, 1.990] | 0.999 [0.994, 1.006] | 1.979 [1.966, 1.993] |
| expanded/string_split/small | ns/iteration: one full document split and result fold | 973.274 | 983.115 | 1854.413 | 1.905 [1.834, 1.958] | 1.010 [0.973, 1.032] | 1.886 [1.841, 1.907] |
| expanded/tagged_stack/large | ns/iteration: one contract operation | 7.373 | 7.348 | 7.351 | 0.997 [0.991, 1.002] | 0.997 [0.991, 1.003] | 1.000 [0.993, 1.007] |
| expanded/tagged_stack/small | ns/iteration: one contract operation | 7.376 | 7.393 | 7.356 | 0.997 [0.991, 1.005] | 1.002 [0.991, 1.007] | 0.995 [0.990, 1.004] |
| expanded/word_count/large | ns/iteration: one complete tokenize/count/fold job | 2436.760 | 2425.791 | 9690.910 | 3.977 [3.931, 4.000] | 0.995 [0.983, 1.001] | 3.995 [3.961, 4.031] |
| expanded/word_count/small | ns/iteration: one complete tokenize/count/fold job | 322.583 | 322.896 | 827.806 | 2.566 [2.514, 2.588] | 1.001 [0.986, 1.015] | 2.564 [2.505, 2.583] |

## Foreign comparisons

| Cell | MyLang arm | / Zig Safe [95%] | / Zig Fast [95%] | / Rust [95%] | / Go [95%] |
|---|---|---|---|---|---|
| parity/alloc_churn | mylang-original-rc | 0.766 [0.761, 0.771] | 0.823 [0.788, 0.830] | 0.689 [0.683, 0.692] | not in parity suite |
| parity/alloc_churn | mylang-migrated-rc | 0.766 [0.763, 0.769] | 0.824 [0.789, 0.831] | 0.689 [0.682, 0.693] | not in parity suite |
| parity/alloc_churn | mylang-zero-rc | 0.767 [0.764, 0.768] | 0.825 [0.789, 0.831] | 0.690 [0.684, 0.694] | not in parity suite |
| parity/bytes_scan | mylang-original-rc | 0.383 [0.365, 0.424] | 0.469 [0.462, 0.481] | 1.188 [1.165, 1.216] | not in parity suite |
| parity/bytes_scan | mylang-migrated-rc | 0.380 [0.367, 0.412] | 0.466 [0.461, 0.471] | 1.180 [1.158, 1.186] | not in parity suite |
| parity/bytes_scan | mylang-zero-rc | 0.386 [0.376, 0.414] | 0.473 [0.466, 0.478] | 1.198 [1.179, 1.214] | not in parity suite |
| parity/calls | mylang-original-rc | 0.985 [0.975, 0.989] | 1.008 [1.005, 1.010] | 1.263 [1.257, 1.267] | not in parity suite |
| parity/calls | mylang-migrated-rc | 0.988 [0.977, 0.994] | 1.012 [1.005, 1.014] | 1.267 [1.257, 1.276] | not in parity suite |
| parity/calls | mylang-zero-rc | 0.988 [0.974, 1.001] | 1.012 [1.005, 1.022] | 1.268 [1.260, 1.286] | not in parity suite |
| parity/dict_count | mylang-original-rc | 0.319 [0.308, 0.342] | 0.413 [0.397, 0.444] | 0.195 [0.188, 0.210] | not in parity suite |
| parity/dict_count | mylang-migrated-rc | 0.309 [0.302, 0.328] | 0.400 [0.396, 0.427] | 0.189 [0.187, 0.202] | not in parity suite |
| parity/dict_count | mylang-zero-rc | 1.652 [1.609, 1.690] | 2.138 [2.091, 2.191] | 1.010 [0.989, 1.041] | not in parity suite |
| parity/fib | mylang-original-rc | 0.922 [0.911, 0.929] | 1.820 [1.797, 1.835] | 1.656 [1.628, 1.675] | not in parity suite |
| parity/fib | mylang-migrated-rc | 0.910 [0.906, 0.915] | 1.796 [1.789, 1.810] | 1.634 [1.624, 1.644] | not in parity suite |
| parity/fib | mylang-zero-rc | 0.924 [0.919, 0.930] | 1.823 [1.816, 1.834] | 1.659 [1.647, 1.674] | not in parity suite |
| parity/float_loop | mylang-original-rc | 1.000 [0.996, 1.005] | 0.998 [0.988, 1.003] | 0.990 [0.987, 0.996] | not in parity suite |
| parity/float_loop | mylang-migrated-rc | 1.005 [0.995, 1.032] | 1.003 [0.994, 1.035] | 0.994 [0.992, 1.023] | not in parity suite |
| parity/float_loop | mylang-zero-rc | 1.004 [0.998, 1.017] | 1.002 [0.993, 1.019] | 0.994 [0.990, 1.006] | not in parity suite |
| parity/intloop | mylang-original-rc | 1.027 [1.023, 1.039] | 1.037 [1.034, 1.052] | 1.069 [1.062, 1.085] | not in parity suite |
| parity/intloop | mylang-migrated-rc | 1.027 [1.014, 1.031] | 1.037 [1.036, 1.039] | 1.069 [1.064, 1.075] | not in parity suite |
| parity/intloop | mylang-zero-rc | 1.027 [1.013, 1.034] | 1.037 [1.036, 1.047] | 1.069 [1.062, 1.080] | not in parity suite |
| parity/list_append_sum | mylang-original-rc | 0.943 [0.929, 0.970] | 0.977 [0.946, 1.018] | 0.937 [0.917, 0.963] | not in parity suite |
| parity/list_append_sum | mylang-migrated-rc | 0.944 [0.908, 0.984] | 0.978 [0.942, 1.017] | 0.938 [0.906, 0.970] | not in parity suite |
| parity/list_append_sum | mylang-zero-rc | 0.926 [0.904, 0.956] | 0.959 [0.918, 1.000] | 0.920 [0.907, 0.956] | not in parity suite |
| parity/list_records | mylang-original-rc | 1.032 [0.993, 1.045] | 1.137 [1.080, 1.176] | 1.190 [1.148, 1.232] | not in parity suite |
| parity/list_records | mylang-migrated-rc | 1.019 [0.971, 1.041] | 1.123 [1.075, 1.160] | 1.175 [1.109, 1.243] | not in parity suite |
| parity/list_records | mylang-zero-rc | 1.034 [0.989, 1.066] | 1.139 [1.091, 1.175] | 1.192 [1.147, 1.256] | not in parity suite |
| parity/records | mylang-original-rc | 0.910 [0.906, 0.913] | 0.826 [0.823, 0.831] | 0.983 [0.980, 0.988] | not in parity suite |
| parity/records | mylang-migrated-rc | 0.910 [0.908, 0.925] | 0.826 [0.824, 0.842] | 0.983 [0.981, 1.001] | not in parity suite |
| parity/records | mylang-zero-rc | 0.910 [0.907, 0.916] | 0.826 [0.824, 0.832] | 0.983 [0.981, 0.991] | not in parity suite |
| parity/str_build | mylang-original-rc | 0.787 [0.776, 0.808] | 0.988 [0.925, 1.025] | 0.934 [0.915, 0.950] | not in parity suite |
| parity/str_build | mylang-migrated-rc | 0.777 [0.767, 0.798] | 0.976 [0.932, 1.007] | 0.922 [0.906, 0.940] | not in parity suite |
| parity/str_build | mylang-zero-rc | 0.818 [0.797, 0.850] | 1.027 [0.979, 1.094] | 0.970 [0.942, 1.009] | not in parity suite |
| expanded/alloc_retained/large | mylang-original-rc | 0.438 [0.411, 0.455] | 0.451 [0.425, 0.470] | 0.428 [0.403, 0.446] | 0.342 [0.323, 0.356] |
| expanded/alloc_retained/large | mylang-migrated-rc | 0.413 [0.403, 0.418] | 0.425 [0.419, 0.433] | 0.403 [0.395, 0.410] | 0.323 [0.317, 0.326] |
| expanded/alloc_retained/large | mylang-zero-rc | 0.411 [0.390, 0.427] | 0.424 [0.402, 0.442] | 0.402 [0.382, 0.441] | 0.322 [0.305, 0.334] |
| expanded/alloc_retained/small | mylang-original-rc | 0.432 [0.428, 0.441] | 0.441 [0.437, 0.451] | 0.413 [0.412, 0.422] | 0.292 [0.291, 0.298] |
| expanded/alloc_retained/small | mylang-migrated-rc | 0.434 [0.428, 0.439] | 0.444 [0.434, 0.448] | 0.416 [0.410, 0.419] | 0.294 [0.290, 0.296] |
| expanded/alloc_retained/small | mylang-zero-rc | 0.388 [0.384, 0.394] | 0.397 [0.387, 0.402] | 0.372 [0.368, 0.375] | 0.263 [0.260, 0.265] |
| expanded/alloc_short/large | mylang-original-rc | 0.244 [0.243, 0.244] | 352.258 [348.167, 356.382] | 1.316 [1.310, 1.318] | 0.661 [0.658, 0.664] |
| expanded/alloc_short/large | mylang-migrated-rc | 0.243 [0.243, 0.244] | 352.064 [347.272, 355.741] | 1.315 [1.309, 1.318] | 0.660 [0.658, 0.664] |
| expanded/alloc_short/large | mylang-zero-rc | 0.243 [0.242, 0.243] | 351.188 [347.509, 355.055] | 1.312 [1.307, 1.314] | 0.659 [0.658, 0.662] |
| expanded/alloc_short/small | mylang-original-rc | 0.272 [0.271, 0.273] | 26.179 [25.882, 26.533] | 1.476 [1.472, 1.482] | 0.629 [0.628, 0.631] |
| expanded/alloc_short/small | mylang-migrated-rc | 0.272 [0.272, 0.273] | 26.207 [25.997, 26.548] | 1.478 [1.474, 1.482] | 0.629 [0.629, 0.631] |
| expanded/alloc_short/small | mylang-zero-rc | 0.267 [0.266, 0.268] | 25.701 [25.479, 26.035] | 1.449 [1.444, 1.453] | 0.617 [0.615, 0.620] |
| expanded/binary_search/large | mylang-original-rc | 0.269 [0.268, 0.271] | 0.704 [0.699, 0.709] | 0.334 [0.332, 0.336] | 0.577 [0.575, 0.581] |
| expanded/binary_search/large | mylang-migrated-rc | 0.269 [0.268, 0.271] | 0.704 [0.699, 0.708] | 0.334 [0.332, 0.336] | 0.578 [0.574, 0.582] |
| expanded/binary_search/large | mylang-zero-rc | 0.269 [0.267, 0.271] | 0.705 [0.698, 0.710] | 0.334 [0.331, 0.337] | 0.578 [0.573, 0.583] |
| expanded/binary_search/small | mylang-original-rc | 0.603 [0.599, 0.609] | 0.628 [0.622, 0.632] | 0.796 [0.789, 0.800] | 0.469 [0.465, 0.474] |
| expanded/binary_search/small | mylang-migrated-rc | 0.602 [0.598, 0.607] | 0.627 [0.622, 0.630] | 0.794 [0.788, 0.797] | 0.468 [0.465, 0.471] |
| expanded/binary_search/small | mylang-zero-rc | 0.589 [0.586, 0.594] | 0.613 [0.610, 0.619] | 0.777 [0.771, 0.783] | 0.458 [0.455, 0.464] |
| expanded/branch_mixed/large | mylang-original-rc | 0.186 [0.185, 0.188] | 0.349 [0.347, 0.352] | 0.343 [0.341, 0.346] | 0.205 [0.204, 0.207] |
| expanded/branch_mixed/large | mylang-migrated-rc | 0.186 [0.185, 0.187] | 0.347 [0.347, 0.351] | 0.341 [0.340, 0.345] | 0.204 [0.204, 0.206] |
| expanded/branch_mixed/large | mylang-zero-rc | 0.186 [0.186, 0.187] | 0.348 [0.348, 0.350] | 0.342 [0.341, 0.344] | 0.205 [0.204, 0.206] |
| expanded/branch_mixed/small | mylang-original-rc | 0.261 [0.259, 0.262] | 0.469 [0.466, 0.471] | 0.464 [0.463, 0.466] | 0.318 [0.316, 0.320] |
| expanded/branch_mixed/small | mylang-migrated-rc | 0.261 [0.259, 0.263] | 0.469 [0.467, 0.471] | 0.464 [0.463, 0.466] | 0.317 [0.316, 0.321] |
| expanded/branch_mixed/small | mylang-zero-rc | 0.259 [0.258, 0.261] | 0.466 [0.463, 0.468] | 0.461 [0.460, 0.462] | 0.315 [0.314, 0.319] |
| expanded/branch_predictable/large | mylang-original-rc | 0.222 [0.221, 0.223] | 0.512 [0.510, 0.519] | 0.406 [0.404, 0.409] | 0.252 [0.251, 0.253] |
| expanded/branch_predictable/large | mylang-migrated-rc | 0.223 [0.222, 0.224] | 0.513 [0.511, 0.521] | 0.407 [0.405, 0.410] | 0.253 [0.252, 0.254] |
| expanded/branch_predictable/large | mylang-zero-rc | 0.222 [0.221, 0.223] | 0.511 [0.508, 0.519] | 0.405 [0.404, 0.408] | 0.252 [0.251, 0.253] |
| expanded/branch_predictable/small | mylang-original-rc | 0.286 [0.285, 0.288] | 0.655 [0.652, 0.661] | 0.523 [0.517, 0.527] | 0.333 [0.332, 0.336] |
| expanded/branch_predictable/small | mylang-migrated-rc | 0.287 [0.287, 0.287] | 0.659 [0.655, 0.662] | 0.526 [0.520, 0.528] | 0.334 [0.334, 0.335] |
| expanded/branch_predictable/small | mylang-zero-rc | 0.285 [0.284, 0.287] | 0.654 [0.651, 0.659] | 0.522 [0.517, 0.524] | 0.332 [0.331, 0.334] |
| expanded/bytes_scan/large | mylang-original-rc | 0.032 [0.031, 0.033] | 0.068 [0.067, 0.068] | 0.045 [0.045, 0.045] | 0.046 [0.045, 0.046] |
| expanded/bytes_scan/large | mylang-migrated-rc | 0.032 [0.031, 0.032] | 0.068 [0.067, 0.068] | 0.045 [0.045, 0.045] | 0.046 [0.045, 0.047] |
| expanded/bytes_scan/large | mylang-zero-rc | 0.031 [0.030, 0.031] | 0.065 [0.064, 0.065] | 0.043 [0.043, 0.043] | 0.044 [0.043, 0.044] |
| expanded/bytes_scan/small | mylang-original-rc | 0.126 [0.125, 0.128] | 0.285 [0.282, 0.288] | 0.198 [0.197, 0.199] | 0.149 [0.147, 0.150] |
| expanded/bytes_scan/small | mylang-migrated-rc | 0.126 [0.125, 0.127] | 0.283 [0.280, 0.287] | 0.197 [0.196, 0.198] | 0.148 [0.146, 0.149] |
| expanded/bytes_scan/small | mylang-zero-rc | 0.126 [0.125, 0.128] | 0.285 [0.283, 0.289] | 0.198 [0.197, 0.199] | 0.149 [0.147, 0.150] |
| expanded/call_direct/large | mylang-original-rc | 0.096 [0.096, 0.096] | 0.144 [0.143, 0.144] | 0.144 [0.143, 0.144] | 0.086 [0.086, 0.086] |
| expanded/call_direct/large | mylang-migrated-rc | 0.096 [0.096, 0.096] | 0.144 [0.143, 0.144] | 0.144 [0.143, 0.144] | 0.086 [0.086, 0.086] |
| expanded/call_direct/large | mylang-zero-rc | 0.096 [0.096, 0.096] | 0.144 [0.143, 0.144] | 0.144 [0.143, 0.144] | 0.086 [0.085, 0.086] |
| expanded/call_direct/small | mylang-original-rc | 0.090 [0.089, 0.090] | 0.115 [0.115, 0.116] | 0.125 [0.124, 0.126] | 0.087 [0.087, 0.088] |
| expanded/call_direct/small | mylang-migrated-rc | 0.090 [0.089, 0.091] | 0.116 [0.115, 0.117] | 0.125 [0.125, 0.126] | 0.088 [0.087, 0.088] |
| expanded/call_direct/small | mylang-zero-rc | 0.090 [0.089, 0.091] | 0.116 [0.115, 0.117] | 0.125 [0.124, 0.126] | 0.088 [0.087, 0.088] |
| expanded/call_indirect/large | mylang-original-rc | 0.029 [0.029, 0.029] | 0.047 [0.046, 0.047] | 0.041 [0.040, 0.041] | 0.035 [0.034, 0.035] |
| expanded/call_indirect/large | mylang-migrated-rc | 0.029 [0.029, 0.029] | 0.047 [0.047, 0.047] | 0.041 [0.040, 0.041] | 0.035 [0.034, 0.035] |
| expanded/call_indirect/large | mylang-zero-rc | 0.029 [0.029, 0.029] | 0.047 [0.046, 0.047] | 0.041 [0.040, 0.041] | 0.034 [0.034, 0.035] |
| expanded/call_indirect/small | mylang-original-rc | 0.035 [0.035, 0.035] | 0.055 [0.055, 0.055] | 0.050 [0.050, 0.050] | 0.043 [0.043, 0.043] |
| expanded/call_indirect/small | mylang-migrated-rc | 0.035 [0.035, 0.036] | 0.055 [0.055, 0.056] | 0.050 [0.050, 0.051] | 0.043 [0.043, 0.044] |
| expanded/call_indirect/small | mylang-zero-rc | 0.036 [0.036, 0.036] | 0.056 [0.056, 0.057] | 0.051 [0.051, 0.051] | 0.044 [0.043, 0.044] |
| expanded/csv_aggregate/large | mylang-original-rc | 1.102 [1.095, 1.107] | 1.354 [1.338, 1.363] | 1.061 [1.057, 1.070] | 0.869 [0.866, 0.881] |
| expanded/csv_aggregate/large | mylang-migrated-rc | 1.101 [1.093, 1.103] | 1.353 [1.337, 1.358] | 1.060 [1.056, 1.065] | 0.868 [0.864, 0.879] |
| expanded/csv_aggregate/large | mylang-zero-rc | 1.063 [1.057, 1.067] | 1.307 [1.292, 1.313] | 1.024 [1.021, 1.030] | 0.838 [0.835, 0.849] |
| expanded/csv_aggregate/small | mylang-original-rc | 1.173 [1.165, 1.183] | 1.481 [1.450, 1.495] | 1.065 [1.058, 1.075] | 0.832 [0.823, 0.838] |
| expanded/csv_aggregate/small | mylang-migrated-rc | 1.174 [1.160, 1.179] | 1.482 [1.453, 1.490] | 1.065 [1.055, 1.076] | 0.832 [0.817, 0.837] |
| expanded/csv_aggregate/small | mylang-zero-rc | 1.143 [1.134, 1.161] | 1.443 [1.409, 1.468] | 1.037 [1.029, 1.056] | 0.810 [0.800, 0.825] |
| expanded/dict_lookup/large | mylang-original-rc | 0.281 [0.277, 0.283] | 0.351 [0.347, 0.353] | 0.354 [0.350, 0.356] | 0.484 [0.478, 0.487] |
| expanded/dict_lookup/large | mylang-migrated-rc | 0.281 [0.278, 0.283] | 0.350 [0.348, 0.353] | 0.353 [0.350, 0.356] | 0.483 [0.480, 0.487] |
| expanded/dict_lookup/large | mylang-zero-rc | 0.281 [0.276, 0.283] | 0.350 [0.347, 0.353] | 0.353 [0.350, 0.356] | 0.483 [0.478, 0.491] |
| expanded/dict_lookup/small | mylang-original-rc | 0.477 [0.473, 0.486] | 0.927 [0.922, 0.940] | 0.373 [0.367, 0.376] | 0.522 [0.516, 0.534] |
| expanded/dict_lookup/small | mylang-migrated-rc | 0.478 [0.474, 0.487] | 0.929 [0.922, 0.943] | 0.374 [0.367, 0.376] | 0.523 [0.515, 0.534] |
| expanded/dict_lookup/small | mylang-zero-rc | 0.478 [0.473, 0.489] | 0.927 [0.924, 0.942] | 0.373 [0.367, 0.376] | 0.522 [0.517, 0.535] |
| expanded/dict_lookup_str/large | mylang-original-rc | 0.377 [0.368, 0.382] | 0.482 [0.470, 0.489] | 0.405 [0.395, 0.410] | 0.585 [0.569, 0.592] |
| expanded/dict_lookup_str/large | mylang-migrated-rc | 0.370 [0.366, 0.372] | 0.473 [0.469, 0.476] | 0.398 [0.394, 0.399] | 0.574 [0.565, 0.575] |
| expanded/dict_lookup_str/large | mylang-zero-rc | 0.471 [0.469, 0.480] | 0.603 [0.599, 0.613] | 0.507 [0.503, 0.515] | 0.731 [0.724, 0.743] |
| expanded/dict_lookup_str/small | mylang-original-rc | 0.607 [0.605, 0.610] | 0.798 [0.795, 0.804] | 0.352 [0.350, 0.354] | 0.556 [0.551, 0.570] |
| expanded/dict_lookup_str/small | mylang-migrated-rc | 0.608 [0.606, 0.611] | 0.800 [0.797, 0.803] | 0.352 [0.350, 0.355] | 0.557 [0.552, 0.571] |
| expanded/dict_lookup_str/small | mylang-zero-rc | 0.762 [0.760, 0.765] | 1.002 [0.999, 1.006] | 0.441 [0.438, 0.444] | 0.698 [0.687, 0.716] |
| expanded/dict_update/large | mylang-original-rc | 0.367 [0.364, 0.368] | 0.504 [0.502, 0.507] | 0.474 [0.470, 0.476] | 0.432 [0.428, 0.435] |
| expanded/dict_update/large | mylang-migrated-rc | 0.367 [0.365, 0.367] | 0.504 [0.503, 0.507] | 0.474 [0.472, 0.475] | 0.432 [0.427, 0.436] |
| expanded/dict_update/large | mylang-zero-rc | 0.362 [0.358, 0.364] | 0.498 [0.494, 0.501] | 0.467 [0.464, 0.470] | 0.426 [0.422, 0.430] |
| expanded/dict_update/small | mylang-original-rc | 0.573 [0.571, 0.614] | 1.128 [1.121, 1.210] | 0.458 [0.448, 0.491] | 0.340 [0.337, 0.367] |
| expanded/dict_update/small | mylang-migrated-rc | 0.573 [0.571, 0.580] | 1.128 [1.118, 1.140] | 0.458 [0.447, 0.464] | 0.340 [0.337, 0.343] |
| expanded/dict_update/small | mylang-zero-rc | 0.567 [0.564, 0.574] | 1.116 [1.108, 1.122] | 0.453 [0.442, 0.456] | 0.337 [0.334, 0.339] |
| expanded/dict_update_str/large | mylang-original-rc | 0.379 [0.377, 0.381] | 0.432 [0.429, 0.434] | 0.327 [0.316, 0.329] | 0.468 [0.463, 0.470] |
| expanded/dict_update_str/large | mylang-migrated-rc | 0.378 [0.377, 0.380] | 0.431 [0.428, 0.433] | 0.327 [0.316, 0.328] | 0.467 [0.463, 0.468] |
| expanded/dict_update_str/large | mylang-zero-rc | 0.562 [0.560, 0.568] | 0.641 [0.638, 0.648] | 0.485 [0.470, 0.491] | 0.694 [0.688, 0.701] |
| expanded/dict_update_str/small | mylang-original-rc | 0.606 [0.596, 0.612] | 0.796 [0.787, 0.810] | 0.282 [0.279, 0.284] | 0.407 [0.404, 0.409] |
| expanded/dict_update_str/small | mylang-migrated-rc | 0.606 [0.599, 0.617] | 0.797 [0.789, 0.816] | 0.282 [0.280, 0.287] | 0.408 [0.404, 0.415] |
| expanded/dict_update_str/small | mylang-zero-rc | 1.059 [1.037, 1.068] | 1.392 [1.363, 1.414] | 0.493 [0.485, 0.495] | 0.712 [0.700, 0.715] |
| expanded/float_math/large | mylang-original-rc | 0.707 [0.700, 0.709] | 1.027 [1.020, 1.031] | 0.666 [0.659, 0.667] | 0.681 [0.678, 0.684] |
| expanded/float_math/large | mylang-migrated-rc | 0.708 [0.703, 0.710] | 1.029 [1.022, 1.033] | 0.667 [0.658, 0.669] | 0.682 [0.679, 0.685] |
| expanded/float_math/large | mylang-zero-rc | 0.706 [0.701, 0.709] | 1.026 [1.019, 1.032] | 0.665 [0.658, 0.667] | 0.680 [0.677, 0.684] |
| expanded/float_math/small | mylang-original-rc | 0.661 [0.658, 0.664] | 0.969 [0.964, 0.971] | 0.646 [0.642, 0.648] | 0.662 [0.660, 0.664] |
| expanded/float_math/small | mylang-migrated-rc | 0.662 [0.659, 0.664] | 0.970 [0.967, 0.973] | 0.647 [0.643, 0.649] | 0.663 [0.661, 0.667] |
| expanded/float_math/small | mylang-zero-rc | 0.662 [0.658, 0.664] | 0.970 [0.966, 0.972] | 0.647 [0.643, 0.650] | 0.663 [0.661, 0.665] |
| expanded/int_format/large | mylang-original-rc | 0.342 [0.340, 0.344] | 0.406 [0.401, 0.407] | 0.960 [0.952, 0.962] | 0.829 [0.819, 0.836] |
| expanded/int_format/large | mylang-migrated-rc | 0.341 [0.340, 0.343] | 0.405 [0.400, 0.408] | 0.958 [0.950, 0.964] | 0.827 [0.818, 0.837] |
| expanded/int_format/large | mylang-zero-rc | 0.645 [0.643, 0.648] | 0.766 [0.761, 0.770] | 1.813 [1.798, 1.817] | 1.565 [1.548, 1.578] |
| expanded/int_format/small | mylang-original-rc | 0.339 [0.336, 0.341] | 0.421 [0.415, 0.424] | 0.930 [0.925, 0.933] | 0.834 [0.830, 0.840] |
| expanded/int_format/small | mylang-migrated-rc | 0.339 [0.336, 0.340] | 0.421 [0.415, 0.423] | 0.930 [0.926, 0.933] | 0.834 [0.831, 0.839] |
| expanded/int_format/small | mylang-zero-rc | 0.654 [0.650, 0.662] | 0.812 [0.803, 0.821] | 1.796 [1.791, 1.814] | 1.610 [1.607, 1.629] |
| expanded/int_parse/large | mylang-original-rc | 0.973 [0.963, 0.980] | 1.059 [1.053, 1.067] | 1.283 [1.273, 1.313] | 0.245 [0.244, 0.247] |
| expanded/int_parse/large | mylang-migrated-rc | 0.969 [0.957, 0.976] | 1.055 [1.044, 1.065] | 1.277 [1.258, 1.311] | 0.244 [0.242, 0.247] |
| expanded/int_parse/large | mylang-zero-rc | 0.981 [0.970, 0.992] | 1.068 [1.058, 1.081] | 1.294 [1.283, 1.329] | 0.248 [0.246, 0.251] |
| expanded/int_parse/small | mylang-original-rc | 1.079 [1.075, 1.083] | 1.094 [1.089, 1.105] | 1.404 [1.394, 1.412] | 0.262 [0.260, 0.264] |
| expanded/int_parse/small | mylang-migrated-rc | 1.079 [1.074, 1.086] | 1.094 [1.091, 1.107] | 1.404 [1.394, 1.416] | 0.262 [0.261, 0.264] |
| expanded/int_parse/small | mylang-zero-rc | 1.079 [1.074, 1.084] | 1.094 [1.090, 1.103] | 1.404 [1.392, 1.413] | 0.262 [0.260, 0.264] |
| expanded/integer_math/large | mylang-original-rc | 0.047 [0.046, 0.047] | 0.052 [0.052, 0.052] | 0.062 [0.062, 0.063] | 0.046 [0.046, 0.046] |
| expanded/integer_math/large | mylang-migrated-rc | 0.047 [0.046, 0.048] | 0.052 [0.052, 0.053] | 0.062 [0.062, 0.064] | 0.046 [0.046, 0.047] |
| expanded/integer_math/large | mylang-zero-rc | 0.047 [0.046, 0.047] | 0.052 [0.051, 0.052] | 0.062 [0.062, 0.063] | 0.046 [0.046, 0.046] |
| expanded/integer_math/small | mylang-original-rc | 0.067 [0.067, 0.067] | 0.076 [0.075, 0.076] | 0.089 [0.089, 0.090] | 0.068 [0.068, 0.069] |
| expanded/integer_math/small | mylang-migrated-rc | 0.067 [0.067, 0.067] | 0.076 [0.075, 0.076] | 0.089 [0.089, 0.090] | 0.068 [0.068, 0.069] |
| expanded/integer_math/small | mylang-zero-rc | 0.067 [0.067, 0.067] | 0.075 [0.075, 0.076] | 0.089 [0.089, 0.089] | 0.068 [0.068, 0.068] |
| expanded/json_transform/large | mylang-original-rc | 0.770 [0.767, 0.778] | 0.975 [0.969, 0.981] | 1.469 [1.464, 1.482] | 0.334 [0.331, 0.338] |
| expanded/json_transform/large | mylang-migrated-rc | 0.771 [0.769, 0.776] | 0.977 [0.970, 0.981] | 1.472 [1.466, 1.483] | 0.335 [0.332, 0.337] |
| expanded/json_transform/large | mylang-zero-rc | 1.106 [1.103, 1.112] | 1.400 [1.391, 1.406] | 2.110 [2.100, 2.126] | 0.479 [0.474, 0.484] |
| expanded/json_transform/small | mylang-original-rc | 0.853 [0.847, 0.860] | 1.182 [1.173, 1.195] | 1.428 [1.415, 1.438] | 0.328 [0.327, 0.329] |
| expanded/json_transform/small | mylang-migrated-rc | 0.855 [0.849, 0.860] | 1.184 [1.177, 1.194] | 1.431 [1.421, 1.439] | 0.328 [0.327, 0.330] |
| expanded/json_transform/small | mylang-zero-rc | 1.227 [1.216, 1.236] | 1.698 [1.688, 1.715] | 2.053 [2.037, 2.066] | 0.471 [0.469, 0.474] |
| expanded/list_append/large | mylang-original-rc | 0.502 [0.499, 0.505] | 1.078 [1.065, 1.084] | 0.992 [0.982, 0.994] | 0.548 [0.545, 0.552] |
| expanded/list_append/large | mylang-migrated-rc | 0.501 [0.500, 0.504] | 1.074 [1.067, 1.081] | 0.989 [0.981, 0.992] | 0.547 [0.545, 0.551] |
| expanded/list_append/large | mylang-zero-rc | 0.488 [0.485, 0.494] | 1.048 [1.037, 1.057] | 0.964 [0.954, 0.972] | 0.533 [0.530, 0.538] |
| expanded/list_append/small | mylang-original-rc | 0.393 [0.389, 0.395] | 0.843 [0.837, 0.850] | 0.624 [0.616, 0.627] | 0.450 [0.446, 0.451] |
| expanded/list_append/small | mylang-migrated-rc | 0.393 [0.390, 0.395] | 0.843 [0.837, 0.849] | 0.624 [0.616, 0.628] | 0.450 [0.445, 0.452] |
| expanded/list_append/small | mylang-zero-rc | 0.416 [0.412, 0.420] | 0.893 [0.889, 0.905] | 0.660 [0.655, 0.666] | 0.476 [0.473, 0.480] |
| expanded/list_filter/large | mylang-original-rc | 0.658 [0.654, 0.662] | 0.919 [0.913, 0.923] | 1.093 [1.086, 1.098] | 0.613 [0.605, 0.617] |
| expanded/list_filter/large | mylang-migrated-rc | 0.660 [0.657, 0.666] | 0.922 [0.915, 0.931] | 1.096 [1.090, 1.106] | 0.615 [0.608, 0.620] |
| expanded/list_filter/large | mylang-zero-rc | 0.655 [0.650, 0.661] | 0.915 [0.909, 0.924] | 1.088 [1.081, 1.099] | 0.610 [0.603, 0.616] |
| expanded/list_filter/small | mylang-original-rc | 0.589 [0.587, 0.591] | 0.867 [0.857, 0.872] | 0.729 [0.725, 0.735] | 0.442 [0.440, 0.444] |
| expanded/list_filter/small | mylang-migrated-rc | 0.591 [0.589, 0.593] | 0.871 [0.856, 0.875] | 0.733 [0.728, 0.737] | 0.444 [0.441, 0.446] |
| expanded/list_filter/small | mylang-zero-rc | 0.618 [0.614, 0.621] | 0.910 [0.894, 0.914] | 0.765 [0.760, 0.770] | 0.464 [0.461, 0.466] |
| expanded/list_scan/large | mylang-original-rc | 0.841 [0.836, 0.844] | 1.134 [1.129, 1.138] | 1.496 [1.490, 1.501] | 1.222 [1.215, 1.228] |
| expanded/list_scan/large | mylang-migrated-rc | 0.842 [0.839, 0.846] | 1.136 [1.132, 1.141] | 1.498 [1.494, 1.504] | 1.223 [1.219, 1.230] |
| expanded/list_scan/large | mylang-zero-rc | 0.832 [0.829, 0.836] | 1.122 [1.119, 1.127] | 1.480 [1.476, 1.487] | 1.208 [1.205, 1.215] |
| expanded/list_scan/small | mylang-original-rc | 0.869 [0.867, 0.871] | 1.121 [1.117, 1.127] | 1.454 [1.444, 1.460] | 1.164 [1.157, 1.170] |
| expanded/list_scan/small | mylang-migrated-rc | 0.867 [0.865, 0.872] | 1.119 [1.115, 1.125] | 1.451 [1.439, 1.461] | 1.162 [1.154, 1.168] |
| expanded/list_scan/small | mylang-zero-rc | 0.850 [0.847, 0.853] | 1.096 [1.092, 1.103] | 1.422 [1.411, 1.429] | 1.139 [1.131, 1.144] |
| expanded/lox_eval/large | mylang-original-rc | 0.373 [0.372, 0.375] | 0.386 [0.383, 0.389] | 0.988 [0.984, 0.995] | 0.908 [0.896, 0.915] |
| expanded/lox_eval/large | mylang-migrated-rc | 0.373 [0.372, 0.374] | 0.386 [0.383, 0.389] | 0.988 [0.983, 0.993] | 0.908 [0.894, 0.912] |
| expanded/lox_eval/large | mylang-zero-rc | 0.373 [0.372, 0.375] | 0.386 [0.383, 0.388] | 0.988 [0.985, 0.995] | 0.909 [0.897, 0.913] |
| expanded/lox_eval/small | mylang-original-rc | 0.382 [0.381, 0.385] | 0.393 [0.392, 0.398] | 0.982 [0.975, 0.986] | 0.941 [0.931, 0.948] |
| expanded/lox_eval/small | mylang-migrated-rc | 0.382 [0.380, 0.384] | 0.393 [0.391, 0.397] | 0.981 [0.972, 0.985] | 0.940 [0.931, 0.944] |
| expanded/lox_eval/small | mylang-zero-rc | 0.388 [0.386, 0.390] | 0.399 [0.397, 0.403] | 0.996 [0.986, 1.001] | 0.955 [0.942, 0.961] |
| expanded/mutate_nested/large | mylang-original-rc | 0.119 [0.115, 0.120] | 0.129 [0.125, 0.130] | 0.116 [0.112, 0.117] | 0.135 [0.130, 0.136] |
| expanded/mutate_nested/large | mylang-migrated-rc | 0.115 [0.114, 0.119] | 0.125 [0.124, 0.129] | 0.112 [0.111, 0.116] | 0.131 [0.130, 0.135] |
| expanded/mutate_nested/large | mylang-zero-rc | 1.365 [1.358, 1.373] | 1.479 [1.473, 1.494] | 1.325 [1.321, 1.334] | 1.549 [1.543, 1.566] |
| expanded/mutate_nested/small | mylang-original-rc | 0.157 [0.155, 0.157] | 0.171 [0.170, 0.172] | 0.156 [0.155, 0.156] | 0.161 [0.158, 0.162] |
| expanded/mutate_nested/small | mylang-migrated-rc | 0.157 [0.155, 0.157] | 0.171 [0.170, 0.172] | 0.156 [0.155, 0.157] | 0.161 [0.158, 0.162] |
| expanded/mutate_nested/small | mylang-zero-rc | 1.408 [1.398, 1.420] | 1.540 [1.529, 1.555] | 1.403 [1.394, 1.416] | 1.447 [1.426, 1.460] |
| expanded/mutate_shared/large | mylang-original-rc | 0.490 [0.487, 0.492] | 0.634 [0.630, 0.636] | 1.072 [1.058, 1.080] | 0.124 [0.123, 0.125] |
| expanded/mutate_shared/large | mylang-migrated-rc | 0.490 [0.489, 0.494] | 0.634 [0.633, 0.638] | 1.073 [1.066, 1.085] | 0.124 [0.124, 0.126] |
| expanded/mutate_shared/large | mylang-zero-rc | 0.562 [0.560, 0.567] | 0.727 [0.723, 0.733] | 1.230 [1.218, 1.244] | 0.143 [0.142, 0.144] |
| expanded/mutate_shared/small | mylang-original-rc | 0.680 [0.675, 0.699] | 1.066 [1.052, 1.080] | 1.007 [0.996, 1.024] | 0.198 [0.197, 0.206] |
| expanded/mutate_shared/small | mylang-migrated-rc | 0.682 [0.675, 0.698] | 1.069 [1.053, 1.091] | 1.010 [0.998, 1.033] | 0.199 [0.196, 0.204] |
| expanded/mutate_shared/small | mylang-zero-rc | 0.822 [0.816, 0.847] | 1.288 [1.271, 1.315] | 1.217 [1.205, 1.240] | 0.240 [0.238, 0.245] |
| expanded/mutate_unique/large | mylang-original-rc | 0.916 [0.913, 0.918] | 0.954 [0.949, 0.957] | 1.180 [1.164, 1.186] | 1.023 [1.018, 1.027] |
| expanded/mutate_unique/large | mylang-migrated-rc | 0.915 [0.912, 0.916] | 0.953 [0.949, 0.956] | 1.179 [1.162, 1.186] | 1.022 [1.015, 1.026] |
| expanded/mutate_unique/large | mylang-zero-rc | 0.898 [0.895, 0.900] | 0.935 [0.931, 0.938] | 1.157 [1.141, 1.163] | 1.003 [1.000, 1.006] |
| expanded/mutate_unique/small | mylang-original-rc | 0.916 [0.912, 0.917] | 0.954 [0.950, 0.957] | 1.176 [1.171, 1.180] | 1.023 [1.020, 1.024] |
| expanded/mutate_unique/small | mylang-migrated-rc | 0.916 [0.912, 0.919] | 0.954 [0.951, 0.959] | 1.177 [1.171, 1.182] | 1.023 [1.021, 1.027] |
| expanded/mutate_unique/small | mylang-zero-rc | 0.898 [0.895, 0.900] | 0.936 [0.932, 0.939] | 1.154 [1.147, 1.158] | 1.003 [1.002, 1.006] |
| expanded/option_handle/large | mylang-original-rc | 0.294 [0.291, 0.295] | 0.371 [0.369, 0.373] | 0.810 [0.802, 0.813] | 0.298 [0.294, 0.299] |
| expanded/option_handle/large | mylang-migrated-rc | 0.294 [0.293, 0.296] | 0.371 [0.370, 0.374] | 0.811 [0.806, 0.814] | 0.298 [0.295, 0.300] |
| expanded/option_handle/large | mylang-zero-rc | 0.293 [0.291, 0.294] | 0.370 [0.369, 0.372] | 0.807 [0.802, 0.809] | 0.297 [0.294, 0.299] |
| expanded/option_handle/small | mylang-original-rc | 0.338 [0.334, 0.342] | 0.441 [0.436, 0.445] | 0.778 [0.769, 0.786] | 0.363 [0.359, 0.367] |
| expanded/option_handle/small | mylang-migrated-rc | 0.338 [0.335, 0.340] | 0.440 [0.439, 0.443] | 0.777 [0.773, 0.780] | 0.363 [0.361, 0.365] |
| expanded/option_handle/small | mylang-zero-rc | 0.334 [0.331, 0.340] | 0.435 [0.432, 0.444] | 0.768 [0.763, 0.783] | 0.359 [0.357, 0.366] |
| expanded/packet_decode/large | mylang-original-rc | 0.735 [0.731, 0.740] | 1.547 [1.539, 1.557] | 1.207 [1.203, 1.214] | 0.508 [0.505, 0.510] |
| expanded/packet_decode/large | mylang-migrated-rc | 0.737 [0.732, 0.743] | 1.551 [1.538, 1.568] | 1.210 [1.201, 1.221] | 0.509 [0.505, 0.513] |
| expanded/packet_decode/large | mylang-zero-rc | 0.733 [0.730, 0.741] | 1.542 [1.537, 1.562] | 1.203 [1.200, 1.218] | 0.506 [0.504, 0.511] |
| expanded/packet_decode/small | mylang-original-rc | 0.767 [0.764, 0.775] | 1.516 [1.505, 1.529] | 1.207 [1.194, 1.219] | 0.528 [0.526, 0.533] |
| expanded/packet_decode/small | mylang-migrated-rc | 0.769 [0.767, 0.773] | 1.519 [1.511, 1.526] | 1.209 [1.196, 1.218] | 0.529 [0.528, 0.531] |
| expanded/packet_decode/small | mylang-zero-rc | 0.774 [0.763, 0.791] | 1.529 [1.502, 1.536] | 1.217 [1.198, 1.232] | 0.533 [0.525, 0.544] |
| expanded/record_construct/large | mylang-original-rc | 0.221 [0.219, 0.222] | 0.253 [0.252, 0.255] | 0.332 [0.331, 0.334] | 0.232 [0.231, 0.234] |
| expanded/record_construct/large | mylang-migrated-rc | 0.220 [0.219, 0.221] | 0.253 [0.252, 0.254] | 0.332 [0.330, 0.333] | 0.232 [0.231, 0.233] |
| expanded/record_construct/large | mylang-zero-rc | 0.220 [0.219, 0.220] | 0.252 [0.252, 0.254] | 0.331 [0.330, 0.333] | 0.232 [0.230, 0.232] |
| expanded/record_construct/small | mylang-original-rc | 0.217 [0.215, 0.219] | 0.255 [0.253, 0.257] | 0.321 [0.318, 0.323] | 0.234 [0.232, 0.237] |
| expanded/record_construct/small | mylang-migrated-rc | 0.217 [0.215, 0.220] | 0.256 [0.253, 0.258] | 0.321 [0.318, 0.325] | 0.234 [0.232, 0.236] |
| expanded/record_construct/small | mylang-zero-rc | 0.217 [0.215, 0.219] | 0.255 [0.253, 0.257] | 0.320 [0.319, 0.324] | 0.233 [0.232, 0.235] |
| expanded/record_reads/large | mylang-original-rc | 0.735 [0.727, 0.743] | 0.823 [0.816, 0.828] | 1.031 [1.024, 1.038] | 0.851 [0.838, 0.856] |
| expanded/record_reads/large | mylang-migrated-rc | 0.737 [0.730, 0.745] | 0.824 [0.821, 0.828] | 1.033 [1.029, 1.038] | 0.853 [0.841, 0.858] |
| expanded/record_reads/large | mylang-zero-rc | 0.735 [0.728, 0.746] | 0.822 [0.816, 0.832] | 1.030 [1.025, 1.043] | 0.851 [0.840, 0.861] |
| expanded/record_reads/small | mylang-original-rc | 0.729 [0.725, 0.731] | 0.786 [0.783, 0.787] | 1.018 [1.011, 1.022] | 0.840 [0.837, 0.843] |
| expanded/record_reads/small | mylang-migrated-rc | 0.728 [0.724, 0.730] | 0.784 [0.782, 0.787] | 1.017 [1.011, 1.018] | 0.838 [0.836, 0.840] |
| expanded/record_reads/small | mylang-zero-rc | 0.728 [0.724, 0.730] | 0.785 [0.781, 0.787] | 1.017 [1.010, 1.020] | 0.839 [0.836, 0.841] |
| expanded/record_update/large | mylang-original-rc | 0.557 [0.555, 0.559] | 0.685 [0.675, 0.690] | 0.899 [0.894, 0.904] | 0.616 [0.615, 0.623] |
| expanded/record_update/large | mylang-migrated-rc | 0.557 [0.555, 0.560] | 0.686 [0.675, 0.692] | 0.899 [0.896, 0.905] | 0.617 [0.615, 0.623] |
| expanded/record_update/large | mylang-zero-rc | 0.556 [0.554, 0.559] | 0.685 [0.677, 0.692] | 0.898 [0.894, 0.904] | 0.616 [0.614, 0.623] |
| expanded/record_update/small | mylang-original-rc | 0.559 [0.555, 0.561] | 0.682 [0.677, 0.685] | 0.872 [0.863, 0.875] | 0.619 [0.616, 0.623] |
| expanded/record_update/small | mylang-migrated-rc | 0.556 [0.549, 0.559] | 0.678 [0.668, 0.683] | 0.867 [0.850, 0.872] | 0.616 [0.606, 0.621] |
| expanded/record_update/small | mylang-zero-rc | 0.560 [0.556, 0.562] | 0.682 [0.676, 0.685] | 0.873 [0.863, 0.877] | 0.619 [0.617, 0.624] |
| expanded/result_propagate/large | mylang-original-rc | 0.765 [0.756, 0.775] | 1.073 [1.057, 1.094] | 1.654 [1.639, 1.675] | 0.659 [0.654, 0.667] |
| expanded/result_propagate/large | mylang-migrated-rc | 0.761 [0.752, 0.768] | 1.068 [1.056, 1.082] | 1.646 [1.631, 1.663] | 0.656 [0.654, 0.662] |
| expanded/result_propagate/large | mylang-zero-rc | 0.808 [0.796, 0.811] | 1.133 [1.121, 1.148] | 1.746 [1.729, 1.757] | 0.696 [0.691, 0.697] |
| expanded/result_propagate/small | mylang-original-rc | 0.724 [0.720, 0.728] | 1.106 [1.099, 1.112] | 1.327 [1.323, 1.334] | 0.612 [0.608, 0.614] |
| expanded/result_propagate/small | mylang-migrated-rc | 0.724 [0.720, 0.730] | 1.107 [1.097, 1.114] | 1.328 [1.324, 1.340] | 0.612 [0.608, 0.614] |
| expanded/result_propagate/small | mylang-zero-rc | 0.724 [0.721, 0.730] | 1.106 [1.098, 1.116] | 1.327 [1.325, 1.336] | 0.612 [0.610, 0.615] |
| expanded/set_dedup/large | mylang-original-rc | 0.303 [0.301, 0.305] | 0.431 [0.429, 0.435] | 0.396 [0.392, 0.398] | 0.355 [0.352, 0.357] |
| expanded/set_dedup/large | mylang-migrated-rc | 0.302 [0.300, 0.304] | 0.429 [0.427, 0.433] | 0.394 [0.391, 0.397] | 0.354 [0.349, 0.356] |
| expanded/set_dedup/large | mylang-zero-rc | 0.298 [0.296, 0.300] | 0.424 [0.421, 0.428] | 0.389 [0.386, 0.392] | 0.349 [0.346, 0.352] |
| expanded/set_dedup/small | mylang-original-rc | 0.747 [0.741, 0.748] | 1.532 [1.525, 1.539] | 0.462 [0.459, 0.463] | 0.393 [0.390, 0.395] |
| expanded/set_dedup/small | mylang-migrated-rc | 0.749 [0.736, 0.753] | 1.535 [1.525, 1.545] | 0.463 [0.459, 0.466] | 0.394 [0.391, 0.397] |
| expanded/set_dedup/small | mylang-zero-rc | 0.732 [0.726, 0.735] | 1.501 [1.497, 1.507] | 0.452 [0.450, 0.455] | 0.385 [0.383, 0.388] |
| expanded/sort_int/large | mylang-original-rc | 0.261 [0.251, 0.265] | 0.379 [0.366, 0.384] | 0.268 [0.257, 0.272] | 0.073 [0.071, 0.074] |
| expanded/sort_int/large | mylang-migrated-rc | 0.260 [0.252, 0.268] | 0.378 [0.368, 0.391] | 0.267 [0.259, 0.275] | 0.073 [0.071, 0.076] |
| expanded/sort_int/large | mylang-zero-rc | 0.260 [0.251, 0.271] | 0.378 [0.366, 0.393] | 0.267 [0.255, 0.277] | 0.073 [0.070, 0.076] |
| expanded/sort_int/small | mylang-original-rc | 0.558 [0.556, 0.560] | 0.912 [0.905, 0.917] | 0.649 [0.647, 0.651] | 0.143 [0.142, 0.143] |
| expanded/sort_int/small | mylang-migrated-rc | 0.557 [0.555, 0.559] | 0.911 [0.903, 0.916] | 0.648 [0.645, 0.650] | 0.143 [0.142, 0.143] |
| expanded/sort_int/small | mylang-zero-rc | 0.566 [0.564, 0.568] | 0.926 [0.919, 0.931] | 0.659 [0.655, 0.661] | 0.145 [0.144, 0.146] |
| expanded/sort_records/large | mylang-original-rc | 0.240 [0.238, 0.261] | 0.299 [0.297, 0.324] | 0.539 [0.532, 0.584] | 0.022 [0.022, 0.024] |
| expanded/sort_records/large | mylang-migrated-rc | 0.244 [0.239, 0.271] | 0.303 [0.296, 0.339] | 0.547 [0.535, 0.597] | 0.023 [0.022, 0.025] |
| expanded/sort_records/large | mylang-zero-rc | 0.553 [0.537, 0.558] | 0.688 [0.668, 0.696] | 1.240 [1.202, 1.251] | 0.051 [0.050, 0.052] |
| expanded/sort_records/small | mylang-original-rc | 0.711 [0.708, 0.719] | 0.996 [0.990, 1.003] | 0.804 [0.779, 0.813] | 0.077 [0.077, 0.078] |
| expanded/sort_records/small | mylang-migrated-rc | 0.711 [0.709, 0.716] | 0.995 [0.990, 1.001] | 0.804 [0.780, 0.809] | 0.077 [0.077, 0.078] |
| expanded/sort_records/small | mylang-zero-rc | 1.182 [1.172, 1.190] | 1.656 [1.641, 1.661] | 1.338 [1.305, 1.343] | 0.128 [0.127, 0.129] |
| expanded/string_equal/large | mylang-original-rc | 0.183 [0.182, 0.184] | 0.235 [0.234, 0.237] | 0.385 [0.383, 0.388] | 0.322 [0.320, 0.324] |
| expanded/string_equal/large | mylang-migrated-rc | 0.183 [0.183, 0.184] | 0.236 [0.235, 0.237] | 0.386 [0.384, 0.388] | 0.323 [0.321, 0.325] |
| expanded/string_equal/large | mylang-zero-rc | 0.184 [0.182, 0.184] | 0.236 [0.234, 0.237] | 0.386 [0.383, 0.388] | 0.323 [0.320, 0.325] |
| expanded/string_equal/small | mylang-original-rc | 1.011 [1.004, 1.015] | 1.065 [1.059, 1.068] | 1.366 [1.357, 1.371] | 0.910 [0.900, 0.925] |
| expanded/string_equal/small | mylang-migrated-rc | 0.998 [0.992, 1.017] | 1.052 [1.047, 1.070] | 1.350 [1.342, 1.375] | 0.899 [0.888, 0.917] |
| expanded/string_equal/small | mylang-zero-rc | 1.011 [0.994, 1.021] | 1.066 [1.050, 1.074] | 1.367 [1.347, 1.378] | 0.911 [0.894, 0.927] |
| expanded/string_join/large | mylang-original-rc | 0.250 [0.240, 0.254] | 0.270 [0.259, 0.275] | 0.330 [0.317, 0.337] | 0.176 [0.169, 0.179] |
| expanded/string_join/large | mylang-migrated-rc | 0.240 [0.239, 0.250] | 0.260 [0.258, 0.271] | 0.317 [0.315, 0.330] | 0.169 [0.168, 0.177] |
| expanded/string_join/large | mylang-zero-rc | 0.328 [0.326, 0.330] | 0.355 [0.352, 0.357] | 0.433 [0.431, 0.436] | 0.231 [0.229, 0.233] |
| expanded/string_join/small | mylang-original-rc | 0.268 [0.266, 0.269] | 0.313 [0.309, 0.315] | 0.378 [0.368, 0.380] | 0.210 [0.208, 0.212] |
| expanded/string_join/small | mylang-migrated-rc | 0.268 [0.267, 0.269] | 0.312 [0.310, 0.314] | 0.378 [0.369, 0.380] | 0.210 [0.209, 0.212] |
| expanded/string_join/small | mylang-zero-rc | 0.308 [0.306, 0.310] | 0.360 [0.357, 0.361] | 0.435 [0.425, 0.438] | 0.242 [0.240, 0.244] |
| expanded/string_search/large | mylang-original-rc | 0.035 [0.035, 0.035] | 0.039 [0.039, 0.039] | 0.079 [0.079, 0.080] | 0.160 [0.159, 0.160] |
| expanded/string_search/large | mylang-migrated-rc | 0.035 [0.035, 0.035] | 0.039 [0.039, 0.039] | 0.079 [0.079, 0.080] | 0.160 [0.159, 0.160] |
| expanded/string_search/large | mylang-zero-rc | 0.035 [0.035, 0.035] | 0.039 [0.039, 0.039] | 0.079 [0.079, 0.080] | 0.160 [0.159, 0.161] |
| expanded/string_search/small | mylang-original-rc | 0.183 [0.183, 0.184] | 0.221 [0.220, 0.222] | 0.385 [0.383, 0.388] | 0.669 [0.667, 0.674] |
| expanded/string_search/small | mylang-migrated-rc | 0.183 [0.182, 0.184] | 0.221 [0.220, 0.222] | 0.385 [0.383, 0.387] | 0.669 [0.665, 0.674] |
| expanded/string_search/small | mylang-zero-rc | 0.184 [0.184, 0.186] | 0.222 [0.221, 0.223] | 0.387 [0.386, 0.389] | 0.673 [0.671, 0.678] |
| expanded/string_split/large | mylang-original-rc | 0.930 [0.922, 0.934] | 0.991 [0.987, 1.011] | 2.106 [2.069, 2.123] | 0.869 [0.855, 0.875] |
| expanded/string_split/large | mylang-migrated-rc | 0.929 [0.921, 0.934] | 0.990 [0.985, 0.996] | 2.103 [2.066, 2.115] | 0.868 [0.855, 0.872] |
| expanded/string_split/large | mylang-zero-rc | 1.839 [1.820, 1.848] | 1.960 [1.947, 1.972] | 4.163 [4.090, 4.193] | 1.718 [1.697, 1.729] |
| expanded/string_split/small | mylang-original-rc | 0.947 [0.939, 0.985] | 1.019 [1.012, 1.052] | 1.798 [1.759, 1.875] | 0.944 [0.934, 0.981] |
| expanded/string_split/small | mylang-migrated-rc | 0.956 [0.944, 0.982] | 1.029 [1.018, 1.060] | 1.816 [1.769, 1.867] | 0.954 [0.939, 0.980] |
| expanded/string_split/small | mylang-zero-rc | 1.804 [1.791, 1.864] | 1.941 [1.925, 2.012] | 3.426 [3.367, 3.540] | 1.799 [1.787, 1.859] |
| expanded/tagged_stack/large | mylang-original-rc | 0.693 [0.686, 0.697] | 0.686 [0.676, 0.689] | 1.278 [1.258, 1.287] | 1.208 [1.198, 1.214] |
| expanded/tagged_stack/large | mylang-migrated-rc | 0.691 [0.685, 0.694] | 0.683 [0.675, 0.687] | 1.273 [1.258, 1.284] | 1.204 [1.194, 1.210] |
| expanded/tagged_stack/large | mylang-zero-rc | 0.691 [0.685, 0.695] | 0.684 [0.676, 0.689] | 1.274 [1.255, 1.286] | 1.204 [1.193, 1.215] |
| expanded/tagged_stack/small | mylang-original-rc | 0.690 [0.683, 0.695] | 0.685 [0.679, 0.690] | 1.271 [1.262, 1.283] | 1.216 [1.210, 1.223] |
| expanded/tagged_stack/small | mylang-migrated-rc | 0.692 [0.682, 0.696] | 0.687 [0.681, 0.694] | 1.274 [1.266, 1.281] | 1.219 [1.211, 1.228] |
| expanded/tagged_stack/small | mylang-zero-rc | 0.688 [0.681, 0.694] | 0.683 [0.677, 0.687] | 1.267 [1.261, 1.278] | 1.213 [1.204, 1.223] |
| expanded/word_count/large | mylang-original-rc | 0.780 [0.775, 0.788] | 0.982 [0.973, 0.999] | 0.642 [0.639, 0.651] | 0.246 [0.244, 0.249] |
| expanded/word_count/large | mylang-migrated-rc | 0.776 [0.771, 0.784] | 0.977 [0.968, 0.986] | 0.639 [0.637, 0.647] | 0.245 [0.243, 0.246] |
| expanded/word_count/large | mylang-zero-rc | 3.100 [3.080, 3.129] | 3.905 [3.873, 3.940] | 2.554 [2.536, 2.584] | 0.980 [0.972, 0.986] |
| expanded/word_count/small | mylang-original-rc | 1.328 [1.297, 1.349] | 1.690 [1.682, 1.729] | 0.924 [0.911, 0.938] | 0.504 [0.490, 0.512] |
| expanded/word_count/small | mylang-migrated-rc | 1.330 [1.302, 1.349] | 1.691 [1.686, 1.718] | 0.925 [0.911, 0.940] | 0.504 [0.491, 0.512] |
| expanded/word_count/small | mylang-zero-rc | 3.409 [3.314, 3.432] | 4.336 [4.295, 4.380] | 2.371 [2.324, 2.391] | 1.292 [1.251, 1.304] |

## Separate RSS and managed counts

All byte/count values below are whole-program totals at the recorded iteration count, not per-iteration allocation. Raw compiler/runtime/shared RC components and uniqueness tests are retained in JSON/CSV.

| Cell | Arm | Child RSS KiB | Allocs | Reallocs | Cumulative bytes | Managed peak bytes | Exit-live bytes | RC events | Unique tests | Direct destructions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| parity/alloc_churn | mylang-original-rc | 1708 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/alloc_churn | mylang-migrated-rc | 1708 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/alloc_churn | mylang-zero-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/alloc_churn | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/alloc_churn | zig-safe | 528 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/alloc_churn | rust | 2184 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/bytes_scan | mylang-original-rc | 17988 | 8 | 13 | 16786480 | 16785328 | 0 | 3 | 1 | 0 |
| parity/bytes_scan | mylang-migrated-rc | 17988 | 8 | 13 | 16786480 | 16785328 | 0 | 3 | 1 | 0 |
| parity/bytes_scan | mylang-zero-rc | 17984 | 9 | 13 | 16786608 | 16785328 | 0 | 0 | 0 | 4 |
| parity/bytes_scan | zig-fast | 8480 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/bytes_scan | zig-safe | 8892 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/bytes_scan | rust | 10388 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/calls | mylang-original-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/calls | mylang-migrated-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/calls | mylang-zero-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/calls | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/calls | zig-safe | 540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/calls | rust | 2164 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/dict_count | mylang-original-rc | 1864 | 3014 | 3 | 234288 | 96888 | 0 | 4000 | 0 | 2 |
| parity/dict_count | mylang-migrated-rc | 1928 | 3014 | 3 | 234288 | 96888 | 0 | 4000 | 0 | 2 |
| parity/dict_count | mylang-zero-rc | 1864 | 2003014 | 3 | 128234288 | 152720 | 0 | 0 | 0 | 2000002 |
| parity/dict_count | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/dict_count | zig-safe | 672 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/dict_count | rust | 2348 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/fib | mylang-original-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/fib | mylang-migrated-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/fib | mylang-zero-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/fib | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/fib | zig-safe | 540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/fib | rust | 2184 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/float_loop | mylang-original-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/float_loop | mylang-migrated-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/float_loop | mylang-zero-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/float_loop | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/float_loop | zig-safe | 624 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/float_loop | rust | 2244 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/intloop | mylang-original-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/intloop | mylang-migrated-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/intloop | mylang-zero-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/intloop | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/intloop | zig-safe | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/intloop | rust | 2220 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/list_append_sum | mylang-original-rc | 126624 | 6 | 17 | 134222904 | 134221784 | 0 | 0 | 0 | 1 |
| parity/list_append_sum | mylang-migrated-rc | 126624 | 6 | 17 | 134222904 | 134221784 | 0 | 0 | 0 | 1 |
| parity/list_append_sum | mylang-zero-rc | 126624 | 6 | 17 | 134222904 | 134221784 | 0 | 0 | 0 | 1 |
| parity/list_append_sum | zig-fast | 125280 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/list_append_sum | zig-safe | 125632 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/list_append_sum | rust | 127176 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/list_records | mylang-original-rc | 64068 | 4 | 16 | 67113784 | 67112920 | 0 | 0 | 0 | 1 |
| parity/list_records | mylang-migrated-rc | 64068 | 4 | 16 | 67113784 | 67112920 | 0 | 0 | 0 | 1 |
| parity/list_records | mylang-zero-rc | 64064 | 4 | 16 | 67113784 | 67112920 | 0 | 0 | 0 | 1 |
| parity/list_records | zig-fast | 62720 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/list_records | zig-safe | 63140 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/list_records | rust | 64780 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/records | mylang-original-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/records | mylang-migrated-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/records | mylang-zero-rc | 1712 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| parity/records | zig-fast | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/records | zig-safe | 392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/records | rust | 2228 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/str_build | mylang-original-rc | 126624 | 10 | 17 | 134223128 | 134221784 | 0 | 1 | 1 | 1 |
| parity/str_build | mylang-migrated-rc | 126628 | 10 | 17 | 134223128 | 134221784 | 0 | 1 | 1 | 1 |
| parity/str_build | mylang-zero-rc | 126624 | 11 | 17 | 134223192 | 134221848 | 0 | 0 | 0 | 3 |
| parity/str_build | zig-fast | 125280 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/str_build | zig-safe | 125688 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| parity/str_build | rust | 127160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/large | mylang-original-rc | 1992 | 5990491 | 17448 | 435557704 | 82704 | 0 | 5955594 | 0 | 5817 |
| expanded/alloc_retained/large | mylang-migrated-rc | 1996 | 5990491 | 17448 | 435557704 | 82704 | 0 | 5955594 | 0 | 5817 |
| expanded/alloc_retained/large | mylang-zero-rc | 1992 | 5990491 | 17448 | 435557704 | 82704 | 0 | 0 | 0 | 5822 |
| expanded/alloc_retained/large | rust | 2416 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/large | go | 6840 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/large | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/small | mylang-original-rc | 1832 | 7901822 | 0 | 597332512 | 5888 | 0 | 7329226 | 0 | 114520 |
| expanded/alloc_retained/small | mylang-migrated-rc | 1836 | 7901822 | 0 | 597332512 | 5888 | 0 | 7329226 | 0 | 114520 |
| expanded/alloc_retained/small | mylang-zero-rc | 1832 | 7901822 | 0 | 597332512 | 5888 | 0 | 0 | 0 | 114525 |
| expanded/alloc_retained/small | rust | 2352 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/small | go | 6680 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_retained/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/large | mylang-original-rc | 1832 | 11 | 0 | 9096 | 8936 | 0 | 10 | 0 | 1 |
| expanded/alloc_short/large | mylang-migrated-rc | 1832 | 11 | 0 | 9096 | 8936 | 0 | 10 | 0 | 1 |
| expanded/alloc_short/large | mylang-zero-rc | 1832 | 11 | 0 | 9096 | 8936 | 0 | 0 | 0 | 6 |
| expanded/alloc_short/large | rust | 2256 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/large | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/large | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/small | mylang-original-rc | 1828 | 11 | 0 | 1408 | 1248 | 0 | 10 | 0 | 1 |
| expanded/alloc_short/small | mylang-migrated-rc | 1836 | 11 | 0 | 1408 | 1248 | 0 | 10 | 0 | 1 |
| expanded/alloc_short/small | mylang-zero-rc | 1832 | 11 | 0 | 1408 | 1248 | 0 | 0 | 0 | 6 |
| expanded/alloc_short/small | rust | 2388 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/small | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/alloc_short/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/large | mylang-original-rc | 1968 | 779 | 0 | 95104 | 29632 | 0 | 518 | 0 | 5 |
| expanded/binary_search/large | mylang-migrated-rc | 1904 | 779 | 0 | 95104 | 29632 | 0 | 518 | 0 | 5 |
| expanded/binary_search/large | mylang-zero-rc | 1968 | 779 | 0 | 95104 | 29632 | 0 | 0 | 0 | 262 |
| expanded/binary_search/large | rust | 2180 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/large | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/large | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/large | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/small | mylang-original-rc | 1744 | 59 | 0 | 6528 | 2496 | 0 | 38 | 0 | 5 |
| expanded/binary_search/small | mylang-migrated-rc | 1744 | 59 | 0 | 6528 | 2496 | 0 | 38 | 0 | 5 |
| expanded/binary_search/small | mylang-zero-rc | 1744 | 59 | 0 | 6528 | 2496 | 0 | 0 | 0 | 22 |
| expanded/binary_search/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/binary_search/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/branch_mixed/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/branch_mixed/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/branch_mixed/large | rust | 2676 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/branch_mixed/small | mylang-migrated-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/branch_mixed/small | mylang-zero-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/branch_mixed/small | rust | 2192 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_mixed/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/branch_predictable/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/branch_predictable/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/branch_predictable/large | rust | 2676 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/large | zig-safe | 2660 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/small | mylang-original-rc | 1804 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/branch_predictable/small | mylang-migrated-rc | 1804 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/branch_predictable/small | mylang-zero-rc | 1808 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/branch_predictable/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/branch_predictable/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/large | mylang-original-rc | 2000 | 12 | 0 | 37552 | 37424 | 0 | 11 | 0 | 1 |
| expanded/bytes_scan/large | mylang-migrated-rc | 2004 | 12 | 0 | 37552 | 37424 | 0 | 11 | 0 | 1 |
| expanded/bytes_scan/large | mylang-zero-rc | 2052 | 14 | 0 | 37680 | 37488 | 0 | 0 | 0 | 9 |
| expanded/bytes_scan/large | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/large | go | 2660 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/large | zig-safe | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/large | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/small | mylang-original-rc | 1840 | 12 | 0 | 1248 | 1120 | 0 | 11 | 0 | 1 |
| expanded/bytes_scan/small | mylang-migrated-rc | 1844 | 12 | 0 | 1248 | 1120 | 0 | 11 | 0 | 1 |
| expanded/bytes_scan/small | mylang-zero-rc | 1892 | 14 | 0 | 1376 | 1184 | 0 | 0 | 0 | 9 |
| expanded/bytes_scan/small | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/small | go | 2660 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/small | zig-safe | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/bytes_scan/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/call_direct/large | mylang-migrated-rc | 2288 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/call_direct/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/call_direct/large | rust | 2676 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/call_direct/small | mylang-migrated-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/call_direct/small | mylang-zero-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/call_direct/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_direct/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/call_indirect/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/call_indirect/large | mylang-zero-rc | 2220 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/call_indirect/large | rust | 2676 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/small | mylang-original-rc | 1804 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/call_indirect/small | mylang-migrated-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/call_indirect/small | mylang-zero-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/call_indirect/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/call_indirect/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/large | mylang-original-rc | 2000 | 3060968 | 994 | 198788504 | 118032 | 0 | 2801072 | 6351740 | 1252 |
| expanded/csv_aggregate/large | mylang-migrated-rc | 2004 | 3060968 | 994 | 198788504 | 118032 | 0 | 2801072 | 6351740 | 1252 |
| expanded/csv_aggregate/large | mylang-zero-rc | 2052 | 3366814 | 994 | 218362648 | 118160 | 0 | 0 | 0 | 311362 |
| expanded/csv_aggregate/large | rust | 2576 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/large | go | 7844 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/large | zig-safe | 2692 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/large | zig-fast | 2496 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/small | mylang-original-rc | 1840 | 3454562 | 0 | 223898368 | 8064 | 0 | 3138890 | 6207422 | 17554 |
| expanded/csv_aggregate/small | mylang-migrated-rc | 1844 | 3454562 | 0 | 223898368 | 8064 | 0 | 3138890 | 6207422 | 17554 |
| expanded/csv_aggregate/small | mylang-zero-rc | 1892 | 3770194 | 0 | 244098816 | 8192 | 0 | 0 | 0 | 385876 |
| expanded/csv_aggregate/small | rust | 2436 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/small | go | 7844 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/small | zig-safe | 2532 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/csv_aggregate/small | zig-fast | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/large | mylang-original-rc | 2152 | 20 | 0 | 164832 | 131704 | 0 | 10 | 0 | 1 |
| expanded/dict_lookup/large | mylang-migrated-rc | 2156 | 20 | 0 | 164832 | 131704 | 0 | 10 | 0 | 1 |
| expanded/dict_lookup/large | mylang-zero-rc | 2152 | 20 | 0 | 164832 | 131704 | 0 | 0 | 0 | 6 |
| expanded/dict_lookup/large | rust | 2400 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/large | go | 2200 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/large | zig-safe | 2616 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/large | zig-fast | 2648 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/small | mylang-original-rc | 1832 | 14 | 0 | 3304 | 2664 | 0 | 10 | 0 | 1 |
| expanded/dict_lookup/small | mylang-migrated-rc | 1836 | 14 | 0 | 3304 | 2664 | 0 | 10 | 0 | 1 |
| expanded/dict_lookup/small | mylang-zero-rc | 1832 | 14 | 0 | 3304 | 2664 | 0 | 0 | 0 | 6 |
| expanded/dict_lookup/small | rust | 2352 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/small | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup/small | zig-fast | 2324 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/large | mylang-original-rc | 2632 | 8213 | 0 | 754696 | 721536 | 0 | 16394 | 0 | 2 |
| expanded/dict_lookup_str/large | mylang-migrated-rc | 2636 | 8213 | 0 | 754696 | 721536 | 0 | 16394 | 0 | 2 |
| expanded/dict_lookup_str/large | mylang-zero-rc | 2952 | 12309 | 0 | 1016840 | 950904 | 0 | 0 | 0 | 7 |
| expanded/dict_lookup_str/large | rust | 3184 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/large | go | 2520 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/large | zig-safe | 4088 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/large | zig-fast | 3912 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/small | mylang-original-rc | 1832 | 143 | 0 | 12560 | 11888 | 0 | 266 | 0 | 2 |
| expanded/dict_lookup_str/small | mylang-migrated-rc | 1836 | 143 | 0 | 12560 | 11888 | 0 | 266 | 0 | 2 |
| expanded/dict_lookup_str/small | mylang-zero-rc | 1832 | 207 | 0 | 16656 | 15472 | 0 | 0 | 0 | 7 |
| expanded/dict_lookup_str/small | rust | 2256 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/small | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/small | zig-safe | 2484 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_lookup_str/small | zig-fast | 2312 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/large | mylang-original-rc | 2132 | 2519 | 0 | 59872184 | 234216 | 0 | 238 | 0 | 1 |
| expanded/dict_update/large | mylang-migrated-rc | 2136 | 2519 | 0 | 59872184 | 234216 | 0 | 238 | 0 | 1 |
| expanded/dict_update/large | mylang-zero-rc | 2128 | 2519 | 0 | 59872184 | 234216 | 0 | 0 | 0 | 234 |
| expanded/dict_update/large | rust | 2860 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/large | go | 6680 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/large | zig-safe | 2624 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/large | zig-fast | 2528 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/small | mylang-original-rc | 1828 | 102476 | 0 | 84924400 | 4400 | 0 | 20503 | 0 | 1 |
| expanded/dict_update/small | mylang-migrated-rc | 1836 | 102476 | 0 | 84924400 | 4400 | 0 | 20503 | 0 | 1 |
| expanded/dict_update/small | mylang-zero-rc | 1832 | 102476 | 0 | 84924400 | 4400 | 0 | 0 | 0 | 20499 |
| expanded/dict_update/small | rust | 2392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/small | go | 6840 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/small | zig-safe | 2296 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/large | mylang-original-rc | 2760 | 9975 | 0 | 42879104 | 824048 | 0 | 2646026 | 0 | 163 |
| expanded/dict_update_str/large | mylang-migrated-rc | 2764 | 9975 | 0 | 42879104 | 824048 | 0 | 2646026 | 0 | 163 |
| expanded/dict_update_str/large | mylang-zero-rc | 3432 | 1988343 | 0 | 169494656 | 1282824 | 0 | 0 | 0 | 659624 |
| expanded/dict_update_str/large | rust | 4064 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/large | go | 7236 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/large | zig-safe | 4128 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/large | zig-fast | 3956 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/small | mylang-original-rc | 1992 | 65860 | 0 | 54479400 | 13624 | 0 | 3365002 | 0 | 13146 |
| expanded/dict_update_str/small | mylang-migrated-rc | 1996 | 65860 | 0 | 54479400 | 13624 | 0 | 3365002 | 0 | 13146 |
| expanded/dict_update_str/small | mylang-zero-rc | 1992 | 2589508 | 0 | 215992872 | 20816 | 0 | 0 | 0 | 854367 |
| expanded/dict_update_str/small | rust | 2512 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/small | go | 6680 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/small | zig-safe | 2484 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/dict_update_str/small | zig-fast | 2312 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/float_math/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/float_math/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/float_math/large | rust | 2672 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/float_math/small | mylang-migrated-rc | 1808 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/float_math/small | mylang-zero-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/float_math/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/float_math/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/large | mylang-original-rc | 2000 | 3603276 | 5 | 230643176 | 33288 | 0 | 3603272 | 0 | 1 |
| expanded/int_format/large | mylang-migrated-rc | 2004 | 3603276 | 5 | 230643176 | 33288 | 0 | 3603272 | 0 | 1 |
| expanded/int_format/large | mylang-zero-rc | 2052 | 7206539 | 5 | 461252008 | 33480 | 0 | 0 | 0 | 7206529 |
| expanded/int_format/large | rust | 2588 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/large | go | 7524 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/large | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/large | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/small | mylang-original-rc | 1840 | 3898986 | 0 | 249535872 | 1248 | 0 | 3898983 | 0 | 1 |
| expanded/int_format/small | mylang-migrated-rc | 1844 | 3898986 | 0 | 249535872 | 1248 | 0 | 3898983 | 0 | 1 |
| expanded/int_format/small | mylang-zero-rc | 1892 | 7797960 | 0 | 499070208 | 1376 | 0 | 0 | 0 | 7797951 |
| expanded/int_format/small | rust | 2404 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/small | go | 7684 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/small | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_format/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/large | mylang-original-rc | 2160 | 7526 | 5 | 515176 | 208136 | 0 | 5473 | 683 | 1 |
| expanded/int_parse/large | mylang-migrated-rc | 2164 | 7526 | 5 | 515176 | 208136 | 0 | 5473 | 683 | 1 |
| expanded/int_parse/large | mylang-zero-rc | 2212 | 7528 | 5 | 515304 | 208264 | 0 | 0 | 0 | 2737 |
| expanded/int_parse/large | rust | 2736 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/large | go | 7844 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/large | zig-safe | 3020 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/large | zig-fast | 2812 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/small | mylang-original-rc | 1840 | 133 | 0 | 9280 | 3840 | 0 | 97 | 11 | 1 |
| expanded/int_parse/small | mylang-migrated-rc | 1844 | 133 | 0 | 9280 | 3840 | 0 | 97 | 11 | 1 |
| expanded/int_parse/small | mylang-zero-rc | 1892 | 135 | 0 | 9408 | 3968 | 0 | 0 | 0 | 49 |
| expanded/int_parse/small | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/small | go | 7524 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/small | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/int_parse/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/integer_math/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/integer_math/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/integer_math/large | rust | 2676 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/integer_math/small | mylang-migrated-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/integer_math/small | mylang-zero-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/integer_math/small | rust | 2192 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/integer_math/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/large | mylang-original-rc | 2160 | 3244892 | 3726 | 221670312 | 202520 | 0 | 5600572 | 1746310 | 2 |
| expanded/json_transform/large | mylang-migrated-rc | 2164 | 3244892 | 3726 | 221670312 | 202520 | 0 | 5600572 | 1746310 | 2 |
| expanded/json_transform/large | mylang-zero-rc | 2372 | 4555944 | 3726 | 343737832 | 287408 | 0 | 0 | 0 | 2306392 |
| expanded/json_transform/large | rust | 2748 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/large | go | 8544 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/large | zig-safe | 2852 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/large | zig-fast | 2656 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/small | mylang-original-rc | 2000 | 3575167 | 0 | 238963720 | 13024 | 0 | 6040456 | 1823370 | 2 |
| expanded/json_transform/small | mylang-migrated-rc | 2004 | 3575167 | 0 | 238963720 | 13024 | 0 | 6040456 | 1823370 | 2 |
| expanded/json_transform/small | mylang-zero-rc | 2052 | 4915137 | 0 | 362269416 | 18592 | 0 | 0 | 0 | 2497162 |
| expanded/json_transform/small | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/small | go | 7904 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/small | zig-safe | 2532 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/json_transform/small | zig-fast | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/large | mylang-original-rc | 1992 | 9801 | 0 | 321223992 | 66320 | 0 | 9800 | 0 | 1 |
| expanded/list_append/large | mylang-migrated-rc | 1996 | 9801 | 0 | 321223992 | 66320 | 0 | 9800 | 0 | 1 |
| expanded/list_append/large | mylang-zero-rc | 1992 | 9801 | 0 | 321223992 | 66320 | 0 | 0 | 0 | 9796 |
| expanded/list_append/large | rust | 2400 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/large | go | 7480 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/large | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/small | mylang-original-rc | 1832 | 510849 | 0 | 277897280 | 1792 | 0 | 510848 | 0 | 1 |
| expanded/list_append/small | mylang-migrated-rc | 1836 | 510849 | 0 | 277897280 | 1792 | 0 | 510848 | 0 | 1 |
| expanded/list_append/small | mylang-zero-rc | 1832 | 510849 | 0 | 277897280 | 1792 | 0 | 0 | 0 | 510844 |
| expanded/list_append/small | rust | 2240 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/small | go | 6840 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_append/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/large | mylang-original-rc | 1992 | 61030 | 34868 | 438952056 | 82744 | 0 | 8727 | 0 | 8718 |
| expanded/list_filter/large | mylang-migrated-rc | 1996 | 61030 | 34868 | 438952056 | 82744 | 0 | 8727 | 0 | 8718 |
| expanded/list_filter/large | mylang-zero-rc | 1992 | 61030 | 34868 | 438952056 | 82744 | 0 | 0 | 0 | 17440 |
| expanded/list_filter/large | rust | 2396 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/large | go | 6840 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/large | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/small | mylang-original-rc | 1832 | 2064741 | 0 | 462500928 | 2240 | 0 | 412956 | 0 | 412947 |
| expanded/list_filter/small | mylang-migrated-rc | 1836 | 2064741 | 0 | 462500928 | 2240 | 0 | 412956 | 0 | 412947 |
| expanded/list_filter/small | mylang-zero-rc | 1832 | 2064741 | 0 | 462500928 | 2240 | 0 | 0 | 0 | 825898 |
| expanded/list_filter/small | rust | 2256 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/small | go | 7020 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_filter/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/large | mylang-original-rc | 1992 | 11 | 0 | 33672 | 33512 | 0 | 10 | 0 | 1 |
| expanded/list_scan/large | mylang-migrated-rc | 1996 | 11 | 0 | 33672 | 33512 | 0 | 10 | 0 | 1 |
| expanded/list_scan/large | mylang-zero-rc | 1992 | 11 | 0 | 33672 | 33512 | 0 | 0 | 0 | 6 |
| expanded/list_scan/large | rust | 2372 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/large | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/large | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/small | mylang-original-rc | 1832 | 11 | 0 | 1408 | 1248 | 0 | 10 | 0 | 1 |
| expanded/list_scan/small | mylang-migrated-rc | 1836 | 11 | 0 | 1408 | 1248 | 0 | 10 | 0 | 1 |
| expanded/list_scan/small | mylang-zero-rc | 1832 | 11 | 0 | 1408 | 1248 | 0 | 0 | 0 | 6 |
| expanded/list_scan/small | rust | 2352 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/small | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/list_scan/small | zig-fast | 2324 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/large | mylang-original-rc | 1832 | 23726 | 0 | 1824264 | 3144 | 0 | 10 | 0 | 14230 |
| expanded/lox_eval/large | mylang-migrated-rc | 1836 | 23726 | 0 | 1824264 | 3144 | 0 | 10 | 0 | 14230 |
| expanded/lox_eval/large | mylang-zero-rc | 1832 | 23726 | 0 | 1824264 | 3144 | 0 | 0 | 0 | 14235 |
| expanded/lox_eval/large | rust | 2272 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/large | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/large | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/small | mylang-original-rc | 1832 | 359836 | 0 | 27635584 | 1216 | 0 | 10 | 0 | 215896 |
| expanded/lox_eval/small | mylang-migrated-rc | 1836 | 359836 | 0 | 27635584 | 1216 | 0 | 10 | 0 | 215896 |
| expanded/lox_eval/small | mylang-zero-rc | 1832 | 359836 | 0 | 27635584 | 1216 | 0 | 0 | 0 | 215901 |
| expanded/lox_eval/small | rust | 2256 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/small | go | 1880 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/lox_eval/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/large | mylang-original-rc | 2152 | 46206 | 0 | 188893464 | 123832 | 0 | 46300284 | 22585 | 2 |
| expanded/mutate_nested/large | mylang-migrated-rc | 2156 | 46206 | 0 | 188893464 | 123832 | 0 | 46300284 | 22585 | 2 |
| expanded/mutate_nested/large | mylang-zero-rc | 2152 | 23150661 | 0 | 1666133144 | 156440 | 0 | 0 | 0 | 22592 |
| expanded/mutate_nested/large | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/large | go | 6680 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/large | zig-safe | 2448 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/large | zig-fast | 2488 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/small | mylang-original-rc | 1832 | 554374 | 0 | 186250176 | 8608 | 0 | 36029444 | 277149 | 2 |
| expanded/mutate_nested/small | mylang-migrated-rc | 1836 | 554374 | 0 | 186250176 | 8608 | 0 | 36029444 | 277149 | 2 |
| expanded/mutate_nested/small | mylang-zero-rc | 1832 | 18014761 | 0 | 1285977408 | 10496 | 0 | 0 | 0 | 277156 |
| expanded/mutate_nested/small | rust | 2240 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/small | go | 6840 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_nested/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/large | mylang-original-rc | 1880 | 753674 | 0 | 6228320904 | 16848 | 0 | 5 | 0 | 753669 |
| expanded/mutate_shared/large | mylang-migrated-rc | 1876 | 753674 | 0 | 6228320904 | 16848 | 0 | 5 | 0 | 753669 |
| expanded/mutate_shared/large | mylang-zero-rc | 1780 | 753674 | 0 | 6228320904 | 16816 | 0 | 0 | 0 | 753669 |
| expanded/mutate_shared/large | rust | 2192 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/large | go | 7876 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/large | zig-safe | 2284 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/large | zig-fast | 2160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/small | mylang-original-rc | 1720 | 4960006 | 0 | 2856960864 | 1472 | 0 | 5 | 0 | 4960001 |
| expanded/mutate_shared/small | mylang-migrated-rc | 1716 | 4960006 | 0 | 2856960864 | 1472 | 0 | 5 | 0 | 4960001 |
| expanded/mutate_shared/small | mylang-zero-rc | 1784 | 4960006 | 0 | 2856960864 | 1440 | 0 | 0 | 0 | 4960001 |
| expanded/mutate_shared/small | rust | 2252 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/small | go | 7140 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/small | zig-safe | 2284 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_shared/small | zig-fast | 2160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/large | mylang-original-rc | 1780 | 6 | 0 | 8552 | 8552 | 0 | 5 | 0 | 1 |
| expanded/mutate_unique/large | mylang-migrated-rc | 1716 | 6 | 0 | 8552 | 8552 | 0 | 5 | 0 | 1 |
| expanded/mutate_unique/large | mylang-zero-rc | 1720 | 6 | 0 | 8552 | 8552 | 0 | 0 | 0 | 1 |
| expanded/mutate_unique/large | rust | 2240 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/large | go | 1968 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/large | zig-safe | 2284 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/large | zig-fast | 2160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/small | mylang-original-rc | 1716 | 6 | 0 | 864 | 864 | 0 | 5 | 0 | 1 |
| expanded/mutate_unique/small | mylang-migrated-rc | 1716 | 6 | 0 | 864 | 864 | 0 | 5 | 0 | 1 |
| expanded/mutate_unique/small | mylang-zero-rc | 1720 | 6 | 0 | 864 | 864 | 0 | 0 | 0 | 1 |
| expanded/mutate_unique/small | rust | 2184 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/small | go | 1968 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/small | zig-safe | 2284 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/mutate_unique/small | zig-fast | 2160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/option_handle/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/option_handle/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/option_handle/large | rust | 2656 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/option_handle/small | mylang-migrated-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/option_handle/small | mylang-zero-rc | 1804 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/option_handle/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/option_handle/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/large | mylang-original-rc | 1904 | 779 | 0 | 95104 | 29632 | 0 | 518 | 0 | 5 |
| expanded/packet_decode/large | mylang-migrated-rc | 1904 | 779 | 0 | 95104 | 29632 | 0 | 518 | 0 | 5 |
| expanded/packet_decode/large | mylang-zero-rc | 1904 | 779 | 0 | 95104 | 29632 | 0 | 0 | 0 | 262 |
| expanded/packet_decode/large | rust | 2176 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/large | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/large | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/large | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/small | mylang-original-rc | 1808 | 59 | 0 | 6528 | 2496 | 0 | 38 | 0 | 5 |
| expanded/packet_decode/small | mylang-migrated-rc | 1744 | 59 | 0 | 6528 | 2496 | 0 | 38 | 0 | 5 |
| expanded/packet_decode/small | mylang-zero-rc | 1808 | 59 | 0 | 6528 | 2496 | 0 | 0 | 0 | 22 |
| expanded/packet_decode/small | rust | 2192 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/packet_decode/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/record_construct/large | mylang-migrated-rc | 2288 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/record_construct/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/record_construct/large | rust | 2672 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/record_construct/small | mylang-migrated-rc | 1808 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/record_construct/small | mylang-zero-rc | 1804 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/record_construct/small | rust | 2176 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_construct/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/large | mylang-original-rc | 2264 | 4106 | 6 | 362280 | 360808 | 0 | 4101 | 0 | 1 |
| expanded/record_reads/large | mylang-migrated-rc | 2132 | 4106 | 6 | 362280 | 360808 | 0 | 4101 | 0 | 1 |
| expanded/record_reads/large | mylang-zero-rc | 2200 | 4106 | 6 | 362280 | 360808 | 0 | 0 | 0 | 1 |
| expanded/record_reads/large | rust | 2672 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/large | go | 2288 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/large | zig-safe | 2600 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/small | mylang-original-rc | 1784 | 74 | 0 | 7464 | 5992 | 0 | 69 | 0 | 1 |
| expanded/record_reads/small | mylang-migrated-rc | 1716 | 74 | 0 | 7464 | 5992 | 0 | 69 | 0 | 1 |
| expanded/record_reads/small | mylang-zero-rc | 1720 | 74 | 0 | 7464 | 5992 | 0 | 0 | 0 | 1 |
| expanded/record_reads/small | rust | 2192 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/small | go | 1968 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/small | zig-safe | 2280 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_reads/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/large | mylang-original-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/record_update/large | mylang-migrated-rc | 2284 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/record_update/large | mylang-zero-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/record_update/large | rust | 2672 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/record_update/small | mylang-migrated-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/record_update/small | mylang-zero-rc | 1808 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/record_update/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/record_update/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/large | mylang-original-rc | 2288 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/result_propagate/large | mylang-migrated-rc | 2224 | 12299 | 0 | 1512072 | 463560 | 0 | 8198 | 0 | 5 |
| expanded/result_propagate/large | mylang-zero-rc | 2288 | 12299 | 0 | 1512072 | 463560 | 0 | 0 | 0 | 4102 |
| expanded/result_propagate/large | rust | 2656 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/large | go | 2300 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/large | zig-safe | 2664 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/large | zig-fast | 2476 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/small | mylang-original-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/result_propagate/small | mylang-migrated-rc | 1808 | 203 | 0 | 24232 | 7912 | 0 | 134 | 0 | 5 |
| expanded/result_propagate/small | mylang-zero-rc | 1744 | 203 | 0 | 24232 | 7912 | 0 | 0 | 0 | 70 |
| expanded/result_propagate/small | rust | 2196 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/small | go | 1980 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/small | zig-safe | 2344 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/result_propagate/small | zig-fast | 2156 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/large | mylang-original-rc | 1992 | 17443 | 0 | 36222504 | 45880 | 0 | 2189 | 0 | 1 |
| expanded/set_dedup/large | mylang-migrated-rc | 1996 | 17443 | 0 | 36222504 | 45880 | 0 | 2189 | 0 | 1 |
| expanded/set_dedup/large | mylang-zero-rc | 1992 | 17443 | 0 | 36222504 | 45880 | 0 | 0 | 0 | 2185 |
| expanded/set_dedup/large | rust | 2552 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/large | go | 6840 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/large | zig-safe | 2296 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/large | zig-fast | 2324 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/small | mylang-original-rc | 1832 | 342633 | 0 | 43857024 | 1504 | 0 | 171321 | 0 | 1 |
| expanded/set_dedup/small | mylang-migrated-rc | 1836 | 342633 | 0 | 43857024 | 1504 | 0 | 171321 | 0 | 1 |
| expanded/set_dedup/small | mylang-zero-rc | 1832 | 342633 | 0 | 43857024 | 1504 | 0 | 0 | 0 | 171317 |
| expanded/set_dedup/small | rust | 2392 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/small | go | 6680 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/small | zig-safe | 2296 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/set_dedup/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/large | mylang-original-rc | 1992 | 2900 | 0 | 94815984 | 66320 | 0 | 2899 | 0 | 1 |
| expanded/sort_int/large | mylang-migrated-rc | 1996 | 2900 | 0 | 94815984 | 66320 | 0 | 2899 | 0 | 1 |
| expanded/sort_int/large | mylang-zero-rc | 1992 | 2900 | 0 | 94815984 | 66320 | 0 | 0 | 0 | 2895 |
| expanded/sort_int/large | rust | 2368 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/large | go | 6520 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/large | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/large | zig-fast | 2312 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/small | mylang-original-rc | 1832 | 340264 | 0 | 185099040 | 1792 | 0 | 340263 | 0 | 1 |
| expanded/sort_int/small | mylang-migrated-rc | 1836 | 340264 | 0 | 185099040 | 1792 | 0 | 340263 | 0 | 1 |
| expanded/sort_int/small | mylang-zero-rc | 1832 | 340264 | 0 | 185099040 | 1792 | 0 | 0 | 0 | 340259 |
| expanded/sort_int/small | rust | 2244 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/small | go | 6972 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_int/small | zig-fast | 2312 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/large | mylang-original-rc | 2152 | 3267 | 0 | 213601224 | 295880 | 0 | 3266 | 0 | 1 |
| expanded/sort_records/large | mylang-migrated-rc | 2156 | 3267 | 0 | 213601224 | 295880 | 0 | 3266 | 0 | 1 |
| expanded/sort_records/large | mylang-zero-rc | 2152 | 3267 | 0 | 213601224 | 263040 | 0 | 0 | 0 | 2448 |
| expanded/sort_records/large | rust | 2708 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/large | go | 6520 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/large | zig-safe | 2452 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/large | zig-fast | 2488 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/small | mylang-original-rc | 1828 | 377031 | 0 | 405674928 | 5552 | 0 | 377030 | 0 | 1 |
| expanded/sort_records/small | mylang-migrated-rc | 1832 | 377031 | 0 | 405674928 | 5552 | 0 | 377030 | 0 | 1 |
| expanded/sort_records/small | mylang-zero-rc | 1832 | 377031 | 0 | 405674928 | 4976 | 0 | 0 | 0 | 282771 |
| expanded/sort_records/small | rust | 2400 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/small | go | 7000 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/small | zig-safe | 2292 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/sort_records/small | zig-fast | 2328 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/large | mylang-original-rc | 2000 | 94 | 0 | 81656 | 38008 | 0 | 112 | 3 | 3 |
| expanded/string_equal/large | mylang-migrated-rc | 2004 | 94 | 0 | 81656 | 38008 | 0 | 112 | 3 | 3 |
| expanded/string_equal/large | mylang-zero-rc | 2052 | 102 | 0 | 82168 | 38136 | 0 | 0 | 0 | 84 |
| expanded/string_equal/large | rust | 2592 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/large | go | 2724 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/large | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/large | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/small | mylang-original-rc | 1840 | 58 | 0 | 4576 | 1664 | 0 | 76 | 3 | 3 |
| expanded/string_equal/small | mylang-migrated-rc | 1844 | 58 | 0 | 4576 | 1664 | 0 | 76 | 3 | 3 |
| expanded/string_equal/small | mylang-zero-rc | 1892 | 66 | 0 | 5088 | 1792 | 0 | 0 | 0 | 48 |
| expanded/string_equal/small | rust | 2428 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/small | go | 2724 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/small | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_equal/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/large | mylang-original-rc | 2000 | 12033 | 0 | 242068264 | 95712 | 0 | 28145 | 0 | 4 |
| expanded/string_join/large | mylang-migrated-rc | 2004 | 12033 | 0 | 242068264 | 95712 | 0 | 28145 | 0 | 4 |
| expanded/string_join/large | mylang-zero-rc | 2372 | 28149 | 0 | 484324984 | 380168 | 0 | 0 | 0 | 36064 |
| expanded/string_join/large | rust | 2752 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/large | go | 7964 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/large | zig-safe | 2496 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/large | zig-fast | 2492 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/small | mylang-original-rc | 1840 | 620717 | 0 | 218489088 | 2080 | 0 | 1241481 | 0 | 4 |
| expanded/string_join/small | mylang-migrated-rc | 1844 | 620717 | 0 | 218489088 | 2080 | 0 | 1241481 | 0 | 4 |
| expanded/string_join/small | mylang-zero-rc | 1892 | 1241485 | 0 | 436980416 | 6688 | 0 | 0 | 0 | 1862116 |
| expanded/string_join/small | rust | 2428 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/small | go | 8220 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/small | zig-safe | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_join/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/large | mylang-original-rc | 1840 | 26 | 0 | 17984 | 12880 | 0 | 28 | 1 | 3 |
| expanded/string_search/large | mylang-migrated-rc | 1844 | 26 | 0 | 17984 | 12880 | 0 | 28 | 1 | 3 |
| expanded/string_search/large | mylang-zero-rc | 1892 | 29 | 0 | 18176 | 13008 | 0 | 0 | 0 | 22 |
| expanded/string_search/large | rust | 2428 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/large | go | 2724 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/large | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/large | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/small | mylang-original-rc | 1840 | 20 | 0 | 1440 | 768 | 0 | 22 | 1 | 3 |
| expanded/string_search/small | mylang-migrated-rc | 1844 | 20 | 0 | 1440 | 768 | 0 | 22 | 1 | 3 |
| expanded/string_search/small | mylang-zero-rc | 1892 | 23 | 0 | 1632 | 896 | 0 | 0 | 0 | 16 |
| expanded/string_search/small | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/small | go | 2724 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/small | zig-safe | 2540 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_search/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/large | mylang-original-rc | 1996 | 7558158 | 11058 | 605949008 | 139168 | 0 | 7556723 | 0 | 4 |
| expanded/string_split/large | mylang-migrated-rc | 2004 | 7558158 | 11058 | 605949008 | 139168 | 0 | 7556723 | 0 | 4 |
| expanded/string_split/large | mylang-zero-rc | 2372 | 15111184 | 11058 | 1089342672 | 401504 | 0 | 0 | 0 | 15101552 |
| expanded/string_split/large | rust | 2736 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/large | go | 7744 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/large | zig-safe | 2496 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/large | zig-fast | 2488 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/small | mylang-original-rc | 1840 | 6259005 | 0 | 560952624 | 3304 | 0 | 5986937 | 0 | 4 |
| expanded/string_split/small | mylang-migrated-rc | 1844 | 6259005 | 0 | 560952624 | 3304 | 0 | 5986937 | 0 | 4 |
| expanded/string_split/small | mylang-zero-rc | 1892 | 12064511 | 0 | 932505008 | 7528 | 0 | 0 | 0 | 11792310 |
| expanded/string_split/small | rust | 2432 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/small | go | 7904 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/small | zig-safe | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/string_split/small | zig-fast | 2332 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/large | mylang-original-rc | 1880 | 7 | 0 | 33192 | 33192 | 0 | 5 | 0 | 2 |
| expanded/tagged_stack/large | mylang-migrated-rc | 1808 | 7 | 0 | 33192 | 33192 | 0 | 5 | 0 | 2 |
| expanded/tagged_stack/large | mylang-zero-rc | 1880 | 7 | 0 | 33192 | 33192 | 0 | 0 | 0 | 2 |
| expanded/tagged_stack/large | rust | 2396 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/large | go | 1968 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/large | zig-safe | 2284 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/large | zig-fast | 2160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/small | mylang-original-rc | 1780 | 7 | 0 | 928 | 928 | 0 | 5 | 0 | 2 |
| expanded/tagged_stack/small | mylang-migrated-rc | 1716 | 7 | 0 | 928 | 928 | 0 | 5 | 0 | 2 |
| expanded/tagged_stack/small | mylang-zero-rc | 1720 | 7 | 0 | 928 | 928 | 0 | 0 | 0 | 2 |
| expanded/tagged_stack/small | rust | 2192 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/small | go | 1968 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/small | zig-safe | 2284 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/tagged_stack/small | zig-fast | 2160 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/large | mylang-original-rc | 2000 | 124046 | 0 | 9925480 | 20336 | 0 | 123786 | 1 | 4 |
| expanded/word_count/large | mylang-migrated-rc | 2004 | 124046 | 0 | 9925480 | 20336 | 0 | 123786 | 1 | 4 |
| expanded/word_count/large | mylang-zero-rc | 2052 | 10828768 | 41172 | 795322680 | 27384 | 0 | 0 | 0 | 5331785 |
| expanded/word_count/large | rust | 2428 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/large | go | 8064 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/large | zig-safe | 2532 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/large | zig-fast | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/small | mylang-original-rc | 1840 | 1488050 | 0 | 119043712 | 1824 | 0 | 1488030 | 1 | 4 |
| expanded/word_count/small | mylang-migrated-rc | 1840 | 1488050 | 0 | 119043712 | 1824 | 0 | 1488030 | 1 | 4 |
| expanded/word_count/small | mylang-zero-rc | 1892 | 10912052 | 0 | 801539840 | 2976 | 0 | 0 | 0 | 4712011 |
| expanded/word_count/small | rust | 2416 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/small | go | 8064 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/small | zig-safe | 2532 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| expanded/word_count/small | zig-fast | 2336 | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |

## Calibration, refusals and failures

| Cell | Iterations | Fastest pilot ms | Slowest pilot ms | Reason | Limited |
|---|---:|---:|---:|---|---|
| expanded/alloc_retained/large | 5816 | 49.092 | 136.273 | slowest_arm_budget | True |
| expanded/alloc_retained/small | 114519 | 52.020 | 198.039 | target | False |
| expanded/alloc_short/large | 195289 | 0.665 | 996.022 | slowest_arm_budget | True |
| expanded/alloc_short/small | 2724726 | 9.649 | 899.450 | pilot_limit | True |
| expanded/binary_search/large | 36931 | 49.876 | 189.731 | slowest_arm_budget | True |
| expanded/binary_search/small | 1113440 | 50.689 | 111.108 | target | False |
| expanded/branch_mixed/large | 30923 | 50.032 | 268.439 | target | False |
| expanded/branch_mixed/small | 1578673 | 51.549 | 199.252 | target | False |
| expanded/branch_predictable/large | 30995 | 50.227 | 225.235 | target | False |
| expanded/branch_predictable/small | 1601929 | 53.019 | 187.175 | target | False |
| expanded/bytes_scan/large | 724625 | 32.397 | 1049.678 | slowest_arm_budget | True |
| expanded/bytes_scan/small | 10000000 | 34.779 | 275.678 | iteration_cap | True |
| expanded/call_direct/large | 179729 | 49.013 | 573.453 | slowest_arm_budget | True |
| expanded/call_direct/small | 9328849 | 51.374 | 585.567 | target | False |
| expanded/call_indirect/large | 104270 | 28.467 | 995.727 | slowest_arm_budget | True |
| expanded/call_indirect/small | 6312791 | 34.314 | 999.039 | slowest_arm_budget | True |
| expanded/csv_aggregate/large | 993 | 50.651 | 79.083 | target | False |
| expanded/csv_aggregate/small | 17535 | 50.719 | 95.628 | target | False |
| expanded/dict_lookup/large | 3448 | 48.884 | 173.711 | slowest_arm_budget | True |
| expanded/dict_lookup/small | 228961 | 50.951 | 141.082 | target | False |
| expanded/dict_lookup_str/large | 2134 | 47.892 | 130.063 | slowest_arm_budget | True |
| expanded/dict_lookup_str/small | 174263 | 52.787 | 152.794 | target | False |
| expanded/dict_update/large | 228 | 50.356 | 138.332 | target | False |
| expanded/dict_update/small | 20493 | 49.816 | 166.710 | slowest_arm_budget | True |
| expanded/dict_update_str/large | 161 | 49.688 | 147.995 | slowest_arm_budget | True |
| expanded/dict_update_str/small | 13144 | 50.243 | 178.694 | target | False |
| expanded/float_math/large | 12400 | 49.606 | 77.522 | slowest_arm_budget | True |
| expanded/float_math/small | 752852 | 51.142 | 78.964 | target | False |
| expanded/int_format/large | 3603261 | 51.059 | 151.610 | target | False |
| expanded/int_format/small | 3898972 | 50.985 | 153.206 | target | False |
| expanded/int_parse/large | 9651031 | 49.146 | 253.143 | slowest_arm_budget | True |
| expanded/int_parse/small | 10000000 | 44.004 | 233.158 | iteration_cap | True |
| expanded/integer_math/large | 139759 | 46.253 | 993.841 | slowest_arm_budget | True |
| expanded/integer_math/small | 6148983 | 50.035 | 746.866 | target | False |
| expanded/json_transform/large | 465 | 50.973 | 221.453 | target | False |
| expanded/json_transform/small | 7927 | 52.985 | 230.778 | target | False |
| expanded/list_append/large | 9790 | 52.878 | 115.252 | target | False |
| expanded/list_append/small | 510838 | 50.183 | 128.062 | target | False |
| expanded/list_filter/large | 8717 | 51.894 | 93.024 | target | False |
| expanded/list_filter/small | 412946 | 50.274 | 113.893 | target | False |
| expanded/list_scan/large | 20473 | 54.984 | 89.272 | target | False |
| expanded/list_scan/small | 1215489 | 50.254 | 85.039 | target | False |
| expanded/lox_eval/large | 4743 | 52.766 | 141.321 | target | False |
| expanded/lox_eval/small | 71965 | 53.390 | 138.334 | target | False |
| expanded/mutate_nested/large | 22585 | 49.842 | 592.424 | slowest_arm_budget | True |
| expanded/mutate_nested/small | 277149 | 50.236 | 458.744 | target | False |
| expanded/mutate_shared/large | 753668 | 49.909 | 427.265 | slowest_arm_budget | True |
| expanded/mutate_shared/small | 4960000 | 50.019 | 266.298 | target | False |
| expanded/mutate_unique/large | 10000000 | 28.837 | 37.207 | iteration_cap | True |
| expanded/mutate_unique/small | 10000000 | 28.777 | 37.217 | iteration_cap | True |
| expanded/option_handle/large | 27551 | 50.108 | 170.886 | target | False |
| expanded/option_handle/small | 1430962 | 50.071 | 151.878 | target | False |
| expanded/packet_decode/large | 96629 | 52.613 | 160.205 | target | False |
| expanded/packet_decode/small | 1395080 | 51.253 | 146.393 | target | False |
| expanded/record_construct/large | 24060 | 49.770 | 227.257 | slowest_arm_budget | True |
| expanded/record_construct/small | 1465265 | 50.059 | 231.529 | target | False |
| expanded/record_reads/large | 10000000 | 38.540 | 53.642 | iteration_cap | True |
| expanded/record_reads/small | 10000000 | 37.604 | 52.397 | iteration_cap | True |
| expanded/record_update/large | 8827 | 49.177 | 88.398 | slowest_arm_budget | True |
| expanded/record_update/small | 563885 | 51.856 | 92.924 | target | False |
| expanded/result_propagate/large | 15511 | 48.870 | 122.256 | slowest_arm_budget | True |
| expanded/result_propagate/small | 877419 | 52.690 | 112.447 | target | False |
| expanded/set_dedup/large | 2179 | 50.542 | 169.828 | target | False |
| expanded/set_dedup/small | 171311 | 48.936 | 192.609 | slowest_arm_budget | True |
| expanded/sort_int/large | 2889 | 48.770 | 663.036 | slowest_arm_budget | True |
| expanded/sort_int/small | 340253 | 50.056 | 350.077 | target | False |
| expanded/sort_records/large | 814 | 21.590 | 994.118 | slowest_arm_budget | True |
| expanded/sort_records/small | 94255 | 51.879 | 665.382 | target | False |
| expanded/string_equal/large | 4383426 | 50.048 | 282.995 | target | False |
| expanded/string_equal/small | 10000000 | 29.761 | 45.339 | iteration_cap | True |
| expanded/string_join/large | 12018 | 50.497 | 301.132 | target | False |
| expanded/string_join/small | 620702 | 51.130 | 243.963 | target | False |
| expanded/string_search/large | 341066 | 34.757 | 996.597 | slowest_arm_budget | True |
| expanded/string_search/small | 3315860 | 53.414 | 291.140 | target | False |
| expanded/string_split/large | 1843 | 51.075 | 209.804 | target | False |
| expanded/string_split/small | 90710 | 51.605 | 180.709 | target | False |
| expanded/tagged_stack/large | 8679962 | 49.698 | 93.481 | slowest_arm_budget | True |
| expanded/tagged_stack/small | 8784535 | 49.849 | 94.050 | slowest_arm_budget | True |
| expanded/word_count/large | 20586 | 50.055 | 206.278 | target | False |
| expanded/word_count/small | 248000 | 47.765 | 208.525 | slowest_arm_budget | True |

## Investigation priorities

Application evidence sets the practical order: first investigate the snapshot/copy boundaries behind Lox VM frame execution and EDA list slicing/accessors. The full application report records zero/migrated EDA wall ratio 10.458; Lox VM has three uninstrumented 120 s censors and counted Fibonacci 2,712,877,890 allocations versus 460 in RC. The application report retains its own compiler/reference identities; these ratios are context rather than pooled micro evidence. These application observations and micro counters corroborate an allocation/copy investigation; they do not measure CPU attribution or establish an unavoidable zero-RC lower bound.

The migrated RC versus original RC comparison identifies shared source-migration changes. Checked zero-RC versus migrated RC uses the same migrated source and isolates the mode comparison within that implementation. Original RC versus foreign code exposes an already-existing compiler/backend/library gap. Investigations must preserve local checked borrows/moves and explicit independent copies. Separate necessary value snapshots from avoidable intermediate copies; these priorities do not propose RC/COW, lifetime syntax or broad whole-program ownership inference. No optimization has been made by this analysis.

- expanded/mutate_nested/large: mode on shared migrated source; 11.821 [11.496, 11.922]. independent-snapshot contract requires explicit copy; this measures necessary deep-copy semantics, not automatically a correctness or optimizer bug; cumulative traffic and peak/RSS remain separate.
- expanded/mutate_nested/small: mode on shared migrated source; 8.997 [8.937, 9.106]. independent-snapshot contract requires explicit copy; this measures necessary deep-copy semantics, not automatically a correctness or optimizer bug; cumulative traffic and peak/RSS remain separate.
- parity/dict_count: mode on shared migrated source; 5.347 [5.095, 5.522]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/word_count/large: mode on shared migrated source; 3.995 [3.961, 4.031]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/word_count/small: mode on shared migrated source; 2.564 [2.505, 2.583]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/sort_records/large: mode on shared migrated source; 2.267 [2.047, 2.304]. equal allocation count and cumulative bytes distinguish an implementation cost from extra allocation; core_sort.c owned keyed sort at849 uses in-place permutation cycles, versus RC copied output at827; source-supported follow-up hypothesis, not sampled CPU attribution.
- expanded/string_split/large: mode on shared migrated source; 1.979 [1.966, 1.993]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/int_format/small: mode on shared migrated source; 1.932 [1.924, 1.955]. kernel includes formatting and checksum encoding; extra allocation is attributed to text::score text.encode() at text.my:31, not established numeric formatter cost; investigate borrowed byte reads/avoidable intermediates while preserving owned encode-result semantics.
- expanded/int_format/large: mode on shared migrated source; 1.892 [1.882, 1.895]. kernel includes formatting and checksum encoding; extra allocation is attributed to text::score text.encode() at text.my:31, not established numeric formatter cost; investigate borrowed byte reads/avoidable intermediates while preserving owned encode-result semantics.
- expanded/string_split/small: mode on shared migrated source; 1.886 [1.841, 1.907]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/dict_update_str/small: mode on shared migrated source; 1.747 [1.695, 1.761]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/sort_records/small: mode on shared migrated source; 1.664 [1.645, 1.669]. equal allocation count and cumulative bytes distinguish an implementation cost from extra allocation; core_sort.c owned keyed sort at849 uses in-place permutation cycles, versus RC copied output at827; source-supported follow-up hypothesis, not sampled CPU attribution.
- expanded/dict_update_str/large: mode on shared migrated source; 1.486 [1.480, 1.505]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/json_transform/small: mode on shared migrated source; 1.434 [1.430, 1.443]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/json_transform/large: mode on shared migrated source; 1.433 [1.427, 1.440]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/string_join/large: mode on shared migrated source; 1.364 [1.308, 1.378]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/dict_lookup_str/large: mode on shared migrated source; 1.274 [1.270, 1.296]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/dict_lookup_str/small: mode on shared migrated source; 1.253 [1.249, 1.256]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.
- expanded/mutate_shared/small: mode on shared migrated source; 1.205 [1.181, 1.229]. independent-snapshot contract requires explicit copy; this measures necessary deep-copy semantics, not automatically a correctness or optimizer bug; cumulative traffic and peak/RSS remain separate.
- expanded/string_join/small: mode on shared migrated source; 1.152 [1.144, 1.156]. investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution.

The parity alloc_churn case records zero managed heap allocations in every current MyLang mode. Despite its name it no longer isolates heap-allocation cost; its timing must not be read as allocator throughput.

Expanded alloc_short likewise does not isolate managed heap churn: checked counters show11 setup allocations (<outside>5, main6) and batch_result0 at both sizes. Ordinary scalar replacement/arithmetic simplification is permitted by the canonical contract; its large foreign gap is an existing optimization/native-port difference, not allocator throughput.

int_format includes formatting plus checksum encoding. Raw checked counters attribute the extra allocation to text::score/text.encode() at text.my:31. This is not established numeric formatter cost. Independent mutate_nested snapshots require explicit nested.copy(); their traffic is necessary value-snapshot semantics. sort_records instead has equal mode allocation counts/cumulative bytes and lower checked managed peak; its mode gap needs a distinct keyed-sort implementation investigation.

Known-core-RC symbol audit: /home/epentland/ai/canopy/mylang-memory-20261012/experiments/micro-ownership-20261012/coordinator/symbol-audit.json (SHA256 ae95cee039faf398152dbf462e55b1899dcfcac415d4b2cd6e929c4afdc472d3). Symbol absence is a static audit separate from executed counters; neither proves arbitrary unreachable code behavior.

## Historical context

history.json records the complete October3 expanded-v1 baseline, the complete expanded-v2 final730a86e6 run and available October4 independently confirmed B1/G2/G4 subsets, with their own source/tool/target/host metadata. current_to_historical rows compare only the historical my-llvm arm descriptively. Historical QBE is never pooled into a current mode comparison. Cross-date ratios have no paired interval and establish no causal compiler/ownership speedup. G4 is a later confirmed six-case subset, not a complete replacement baseline.

Application comparison source: /home/epentland/ai/canopy/mylang-memory-20261012/experiments/lox-eda-zero-rc-20261012/bench/full-final/COMPARISON.md (SHA256 935f3a5cec87042e4cfe00158b867a525b84d9365760b9dc0fcf43acad375a76).

Pending receipts: none.
