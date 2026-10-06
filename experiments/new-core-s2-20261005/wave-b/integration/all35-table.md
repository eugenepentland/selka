# All 35 rows, both sizes

Measured compiler source: `090dabd5`. Native-code reuse is qualified for repaired integration `996d9baad0e00ef98b4d3e7b59dc3616809fa013`: all 35 new native rows rebuild, and every complete emitted LLVM module is byte-identical to the measured module. Runtime, emitter, driver, clock and row sources are unchanged. `rows-after-fact.txt` and `.json` record the exact command and source-bound proof; no measurements or count audit were rerun.

Each numeric cell is `4096 / 64`. Values are CPU-10 user cycles per listed unit, seven interleaved rounds after startup subtraction. Every one of the 2,800 old/new/Rust/Zig samples exits successfully, prints the required checksum/time shape and matches checksums. `I/P/N` gives static tagged count-store sites in timed innermost loops / parent-exclusive loops / timed nonloop cleanup. This includes allocation initialization and conditional release arms; it is not a dynamic update count. Runtime effects, initialization subsets, missing metadata and the concrete surviving stores are explained in `count-notes.md`.

| Row | Unit | Old | New | Zig ReleaseSafe | Rust | New/Zig | New/Rust | I/P/N |
|---|---|---:|---:|---:|---:|---:|---:|---|
| record_reads | iteration | 24.472 / 24.496 | 17.783 / 17.632 | 23.912 / 23.910 | 17.401 / 17.262 | 0.744 / 0.737 | 1.022 / 1.021 | 0/0/0 |
| tagged_stack | iteration | 63.284 / 63.270 | 33.330 / 33.309 | 47.931 / 47.856 | 25.940 / 25.905 | 0.695 / 0.696 | 1.285 / 1.286 | 0/0/0 |
| mutate_unique | iteration | 17.138 / 17.091 | 14.577 / 14.583 | 16.960 / 16.936 | 13.169 / 13.129 | 0.859 / 0.861 | 1.107 / 1.111 | 0/0/0 |
| mutate_shared | element | 0.955 / 7.123 | 0.637 / 0.637 | 1.121 / 0.999 | 0.627 / 0.642 | 0.568 / 0.637 | 1.015 / 0.992 | 0/0/0 |
| record_construct | element | 11.627 / 11.717 | 2.304 / 2.396 | 10.494 / 11.031 | 6.902 / 7.330 | 0.220 / 0.217 | 0.334 / 0.327 | 0/0/0 |
| record_update | element | 11.719 / 11.790 | 6.183 / 6.290 | 11.161 / 11.638 | 6.904 / 7.330 | 0.554 / 0.540 | 0.896 / 0.858 | 0/0/0 |
| option_handle | element | 4.036 / 4.055 | 1.954 / 2.496 | 6.506 / 7.411 | 2.415 / 3.156 | 0.300 / 0.337 | 0.809 / 0.791 | 0/0/0 |
| result_propagate | element | 6.201 / 5.605 | 4.043 / 3.970 | 7.095 / 7.456 | 3.513 / 4.118 | 0.570 / 0.532 | 1.151 / 0.964 | 0/0/0 |
| list_scan | element | 3.847 / 4.011 | 3.968 / 4.035 | 4.569 / 4.658 | 2.703 / 2.792 | 0.868 / 0.866 | 1.468 / 1.445 | 0/0/1 |
| list_append | element | 7.239 / 14.086 | 7.068 / 9.682 | 12.283 / 16.792 | 6.200 / 10.211 | 0.575 / 0.577 | 1.140 / 0.948 | 0/2/0 |
| list_filter | element | 9.262 / 17.611 | 7.900 / 10.621 | 10.592 / 13.847 | 5.737 / 10.052 | 0.746 / 0.767 | 1.377 / 1.057 | 0/3/0 |
| alloc_short | element | 244.897 / 249.942 | 4.722 / 5.075 | 21.812 / 22.193 | 5.013 / 5.329 | 0.216 / 0.229 | 0.942 / 0.952 | unknown (manual 0) |
| alloc_retained | element | 142.927 / 152.561 | 36.249 / 37.742 | 80.661 / 78.560 | 80.263 / 82.051 | 0.449 / 0.480 | 0.452 / 0.460 | 1/1/0 |
| mutate_nested | element | 29.188 / 46.418 | 12.283 / 14.675 | 75.435 / 73.896 | 81.281 / 72.220 | 0.163 / 0.199 | 0.151 / 0.203 | 2/0/0 |
| bytes_scan | element | 0.083 / 0.246 | 1.246 / 1.736 | 1.372 / 1.815 | 1.135 / 1.201 | 0.908 / 0.956 | 1.098 / 1.446 | 0/0/5 |
| string_equal | iteration | 53.707 / 16.679 | 134.607 / 15.260 | 277.655 / 16.809 | 135.459 / 12.711 | 0.485 / 0.908 | 0.994 / 1.201 | 0/0/5 |
| string_search | iteration | 420.276 / 79.811 | 1081.894 / 89.172 | 12923.277 / 387.888 | 5584.115 / 182.514 | 0.084 / 0.230 | 0.194 / 0.489 | 0/0/5 |
| string_split | element | 201.801 / 210.588 | 69.675 / 71.658 | 65.569 / 69.066 | 27.999 / 35.783 | 1.063 / 1.038 | 2.488 / 2.003 | 0/1/5 |
| string_join | element | 6.122 / 9.958 | 5.822 / 6.579 | 18.116 / 20.372 | 13.878 / 14.936 | 0.321 / 0.323 | 0.419 / 0.440 | 0/1/5 |
| dict_lookup | element | 31.080 / 16.984 | 15.668 / 15.124 | 52.235 / 30.957 | 41.943 / 41.013 | 0.300 / 0.489 | 0.374 / 0.369 | 0/0/4 |
| dict_lookup_str | element | 61.795 / 28.868 | 22.487 / 19.502 | 62.413 / 31.877 | 60.300 / 57.605 | 0.360 / 0.612 | 0.373 / 0.339 | 0/0/4 |
| dict_update | element | 828.676 / 733.364 | 196.748 / 200.324 | 550.219 / 309.074 | 414.143 / 400.552 | 0.358 / 0.648 | 0.475 / 0.500 | 0/1/4 |
| dict_update_str | element | 1016.314 / 852.210 | 282.968 / 265.426 | 729.773 / 404.923 | 919.045 / 860.744 | 0.388 / 0.655 | 0.308 / 0.308 | 0/2/4 |
| set_dedup | element | 175.418 / 168.280 | 24.547 / 29.841 | 81.057 / 37.629 | 62.648 / 62.484 | 0.303 / 0.793 | 0.392 / 0.478 | 0/1/4 |
| int_parse | iteration | 46.212 / 41.438 | 29.089 / 26.527 | 28.864 / 24.338 | 21.992 / 19.216 | 1.008 / 1.090 | 1.323 / 1.380 | 0/0/4 |
| int_format | iteration | 221.152 / 216.686 | 68.646 / 62.790 | 214.758 / 197.557 | 63.711 / 62.190 | 0.320 / 0.318 | 1.077 / 1.010 | 0/1/4 |
| call_indirect | element | 5.013 / 5.080 | 0.302 / 0.312 | 9.013 / 9.502 | 7.192 / 7.825 | 0.033 / 0.033 | 0.042 / 0.040 | 0/0/0 |
| sort_int | element | 45.474 / 11.705 | 46.678 / 9.691 | 67.428 / 17.721 | 70.051 / 15.486 | 0.692 / 0.547 | 0.666 / 0.626 | 0/1/0 |
| sort_records | element | 55.648 / 66.818 | 31.429 / 39.289 | 117.653 / 50.766 | 40.781 / 44.783 | 0.267 / 0.774 | 0.771 / 0.877 | 0/5/0 |
| int_math | element | 8.696 / 9.069 | 0.357 / 0.493 | 7.808 / 8.314 | 5.706 / 6.183 | 0.046 / 0.059 | 0.063 / 0.080 | 0/0/0 |
| float_math | element | 8.297 / 8.428 | 1.568 / 1.709 | 6.515 / 7.029 | 6.970 / 7.323 | 0.241 / 0.243 | 0.225 / 0.233 | 0/0/0 |
| call_direct | element | 3.039 / 3.147 | 0.300 / 0.321 | 3.020 / 4.115 | 2.017 / 2.934 | 0.099 / 0.078 | 0.149 / 0.109 | 0/0/0 |
| branch_predictable | element | 4.024 / 4.149 | 0.395 / 0.496 | 7.679 / 7.943 | 3.198 / 3.252 | 0.051 / 0.063 | 0.123 / 0.153 | 0/0/0 |
| branch_mixed | element | 4.119 / 4.128 | 0.398 / 0.498 | 9.244 / 9.062 | 4.870 / 4.518 | 0.043 / 0.055 | 0.082 / 0.110 | 0/0/0 |
| binary_search | element | 143.777 / 32.984 | 32.877 / 18.453 | 137.108 / 27.887 | 37.633 / 19.493 | 0.240 / 0.662 | 0.874 / 0.947 | 0/0/1 |

All 70 row/size pairs pass the 1.10 Zig gate. The tightest ratio is `int_parse/64` at 1.0899657224757722. No binary-search noise exception was needed for this measurement.
