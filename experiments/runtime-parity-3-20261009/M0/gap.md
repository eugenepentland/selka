# M0 gap — current-main base

Base: `41ed360fb361c49938488ad111795bad8a726b73`. Ratios below divide mylang by the named reference; smaller is faster.

CPU 10 runs hold the timing lock and all build/gate slots. Parity uses 9 rounds and 2 warmups; Lox 3 rounds; EDA 10 rounds and 1 warmup. Rows use the median of the three within-batch ratios (7 rounds per batch, startup-subtracted cycles per unit), as in FU-X.

A dash means the corpus has no such arm. Lox and EDA provide plain Rust only; its ratio is evidence, not a checked-Rust gate result. The `met` column applies only to the available gated references. Missing checked-Rust coverage remains explicit. binary_trees_recursive has only a mylang arm; it is timed and qualified, but its relative gate is unavailable and it is excluded from reference geomeans.

## Parity

| program / arm | ÷ Zig RS | ÷ rust-checked | ÷ Zig RF | ÷ plain Rust | ÷ Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---|
| alloc_churn/my | 0.752 | 0.638 | 0.819 | 0.634 | — | 1.10 | met |
| alloc_churn/my-arena | 0.758 | 0.643 | 0.825 | 0.639 | — | 1.10 | met |
| binary_trees/my | 0.884 | 0.569 | 0.978 | 0.582 | — | 1.10 | met |
| binary_trees/my-arena | 0.886 | 0.571 | 0.980 | 0.584 | — | 1.10 | met |
| binary_trees_recursive/my | — | — | — | — | — | 1.10 | unavailable |
| bytes_scan/my | 0.342 | 0.306 | 0.432 | 1.191 | — | 1.10 | met |
| bytes_scan/my-wrapping | 0.342 | 0.306 | 0.432 | 1.191 | — | 1.10 | met |
| calls/my | 0.994 | 1.239 | 1.015 | 1.271 | — | 1.10 | over |
| dict_count/my | 0.270 | 0.170 | 0.364 | 0.169 | — | 1.10 | met |
| fannkuch_redux/my | 0.678 | 0.803 | 0.808 | 0.783 | — | 1.10 | met |
| fannkuch_redux/my-array | 2.668 | 3.159 | 3.178 | 3.081 | — | 1.10 | over |
| fannkuch_redux/my-tuned | 2.255 | 2.670 | 2.686 | 2.603 | — | 1.10 | over |
| fib/my | 0.912 | 0.807 | 1.804 | 1.650 | — | 1.10 | met |
| float_loop/my | 0.994 | 0.989 | 1.000 | 0.984 | — | 1.10 | met |
| intloop/my | 1.045 | 1.226 | 1.047 | 1.088 | — | 1.10 | over |
| knucleotide/my | 0.885 | 0.728 | 0.998 | 0.736 | — | 1.10 | met |
| knucleotide/my-arena | 0.904 | 0.745 | 1.020 | 0.753 | — | 1.10 | met |
| knucleotide/my-tuned | 0.591 | 0.487 | 0.667 | 0.492 | — | 1.10 | met |
| list_append_sum/my | 0.952 | 0.905 | 0.987 | 0.940 | — | 1.10 | met |
| list_records/my | 1.046 | 1.009 | 1.160 | 1.215 | — | 1.10 | met |
| list_records/my-wrapping | 0.828 | 0.798 | 0.918 | 0.961 | — | 1.10 | met |
| mandelbrot/my | 1.004 | 0.973 | 1.007 | 0.984 | — | 1.10 | met |
| matmul/my | 0.325 | 0.187 | 0.506 | 0.238 | — | 1.10 | met |
| matmul/my-flat | 0.318 | 0.183 | 0.496 | 0.233 | — | 1.10 | met |
| matmul/my-tuned | 1.645 | 0.946 | 2.563 | 1.205 | — | 1.10 | over |
| nbody/my | 1.332 | 1.159 | 1.331 | 1.153 | — | 1.10 | over |
| nbody/my-class | 1.337 | 1.163 | 1.335 | 1.157 | — | 1.10 | over |
| raytrace/my | 1.012 | 1.058 | 1.073 | 1.084 | — | 1.10 | met |
| raytrace/my-tuned | 1.017 | 1.063 | 1.078 | 1.089 | — | 1.10 | met |
| records/my | 0.904 | 1.090 | 0.820 | 0.981 | — | 1.10 | met |
| scan_count/my | 0.477 | — | 0.949 | — | — | 1.10 | met |
| scan_replace/my | 0.266 | — | 0.474 | — | — | 1.10 | met |
| scan_split/my | 1.404 | — | 2.139 | — | — | 1.10 | over |
| sieve/my | 0.789 | 0.899 | 1.078 | 1.052 | — | 1.10 | met |
| sieve/my-tuned | 0.794 | 0.905 | 1.085 | 1.058 | — | 1.10 | met |
| sort_builtin/my | 0.441 | 1.691 | 0.513 | 1.705 | — | 1.10 | over |
| sort_quick/my | 0.976 | 1.193 | 1.142 | 1.231 | — | 1.10 | over |
| sort_records/my | 0.235 | 0.707 | 0.275 | 0.691 | — | 1.10 | met |
| sort_records/my-keyed | 0.233 | 0.700 | 0.272 | 0.684 | — | 1.10 | met |
| sort_records/my-sorted | 0.234 | 0.703 | 0.273 | 0.687 | — | 1.10 | met |
| spectral_norm/my | 0.751 | 0.872 | 0.997 | 0.998 | — | 1.10 | met |
| spectral_norm/my-tuned | 0.735 | 0.854 | 0.976 | 0.977 | — | 1.10 | met |
| str_build/my | 0.773 | 0.899 | 0.963 | 0.888 | — | 1.10 | met |
| text_ops/my | 2.659 | 1.400 | 2.214 | 1.413 | — | 1.10 | over |
| text_ops/my-tuned | 0.908 | 0.478 | 0.756 | 0.482 | — | 1.10 | met |

Primary-arm geomean (27 programs with both Zig references) ÷ Zig RS: 0.741; ÷ Zig RF: 0.893.

## Lox

| program / arm | ÷ Zig RS | ÷ rust-checked | ÷ Zig RF | ÷ plain Rust | ÷ Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---|
| binary_trees/tree | 0.862 | — | 1.780 | 1.413 | 1.209 | 1.10 | met |
| binary_trees/vm | 0.897 | — | 2.074 | 1.655 | 1.373 | 1.50 | met |
| closures/tree | 1.010 | — | 1.692 | 1.167 | 1.302 | 1.10 | met |
| closures/vm | 1.316 | — | 1.931 | 1.556 | 1.604 | 1.50 | met |
| equality/tree | 1.415 | — | 1.544 | 1.517 | 1.831 | 1.10 | over |
| equality/vm | 1.721 | — | 1.848 | 1.630 | 1.558 | 1.50 | over |
| fib/tree | 0.856 | — | 1.478 | 0.994 | 1.215 | 1.10 | met |
| fib/vm | 1.878 | — | 2.330 | 1.694 | 2.019 | 1.50 | over |
| instantiation/tree | 0.720 | — | 1.220 | 1.228 | 0.907 | 1.10 | met |
| instantiation/vm | 1.760 | — | 2.411 | 1.468 | 1.279 | 1.50 | over |
| invocation/tree | 0.681 | — | 1.238 | 1.157 | 0.897 | 1.10 | met |
| invocation/vm | 2.054 | — | 3.419 | 1.789 | 2.116 | 1.50 | over |
| method_call/tree | 1.006 | — | 1.651 | 1.458 | 1.122 | 1.10 | met |
| method_call/vm | 1.861 | — | 2.661 | 1.767 | 1.971 | 1.50 | over |
| properties/tree | 0.830 | — | 1.428 | 1.221 | 1.034 | 1.10 | met |
| properties/vm | 1.861 | — | 2.870 | 1.684 | 1.968 | 1.50 | over |
| string_equality/tree | 2.420 | — | 3.045 | 1.175 | 2.612 | 1.10 | over |
| string_equality/vm | 1.883 | — | 2.408 | 1.438 | 1.164 | 1.50 | over |
| strings/tree | 0.948 | — | 1.632 | 1.170 | 1.271 | 1.10 | met |
| strings/vm | 0.906 | — | 1.757 | 1.643 | 1.434 | 1.50 | met |
| trees/tree | 1.003 | — | 1.517 | 1.421 | 1.238 | 1.10 | met |
| trees/vm | 1.674 | — | 2.411 | 1.636 | 1.840 | 1.50 | over |
| zoo/tree | 0.821 | — | 1.383 | 1.091 | 0.946 | 1.10 | met |
| zoo/vm | 1.777 | — | 2.716 | 1.545 | 1.865 | 1.50 | over |
| zoo_batch/tree | 0.848 | — | 1.393 | 1.141 | 0.960 | 1.10 | met |
| zoo_batch/vm | 1.782 | — | 2.605 | 1.564 | 1.880 | 1.50 | over |

vm geomean ÷ Zig RS: 1.595; tree geomean ÷ Zig RS: 0.972.

## EDA

| program / arm | ÷ Zig RS | ÷ rust-checked | ÷ Zig RF | ÷ plain Rust | ÷ Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---|
| Cyclops-Flex | 1.172 | — | 1.295 | 1.133 | 0.471 | 1.10 | over |
| adf5901 | 1.204 | — | 1.298 | 1.158 | 0.414 | 1.10 | over |
| barracuda | 1.104 | — | 1.200 | 1.152 | 0.483 | 1.10 | over |
| barracuda-base | 1.097 | — | 1.195 | 1.150 | 0.482 | 1.10 | met |
| barracuda-via-fence | 1.141 | — | 1.238 | 1.155 | 0.480 | 1.10 | over |
| black-canyon | 1.069 | — | 1.160 | 1.149 | 0.482 | 1.10 | met |
| black-canyon+flat | 1.099 | — | 1.221 | 1.147 | 0.478 | 1.10 | met |
| blinky-breakout | 1.538 | — | 1.673 | 1.196 | 0.587 | 1.10 | over |
| cyclops-analog | 1.163 | — | 1.286 | 1.169 | 0.465 | 1.10 | over |
| cyclops-analog+no-vendor-symbols | 1.173 | — | 1.288 | 1.184 | 0.512 | 1.10 | over |
| cyclops-breakout | 1.228 | — | 1.335 | 1.151 | 0.458 | 1.10 | over |
| cyclops-digital-pcb | 1.330 | — | 1.451 | 1.217 | 0.509 | 1.10 | over |
| cyclops-interposer | 1.080 | — | 1.181 | 1.153 | 0.467 | 1.10 | met |
| cyclops-kband | 1.153 | — | 1.259 | 1.157 | 0.479 | 1.10 | over |
| cyclops-kband-breakout | 1.060 | — | 1.156 | 1.154 | 0.467 | 1.10 | met |
| cyclops-kband-pcb | 1.205 | — | 1.314 | 1.178 | 0.490 | 1.10 | over |
| cyclops-xband-sip | 1.154 | — | 1.257 | 1.149 | 0.468 | 1.10 | over |
| dual-flash | 1.222 | — | 1.339 | 1.153 | 0.410 | 1.10 | over |
| labstation | 1.092 | — | 1.198 | 1.173 | 0.478 | 1.10 | met |
| labstation+no-vendor-symbols | 1.093 | — | 1.196 | 1.188 | 0.517 | 1.10 | met |
| lmk05318b-clock | 1.195 | — | 1.316 | 1.127 | 0.410 | 1.10 | over |
| max860-inverter | 1.242 | — | 1.350 | 1.123 | 0.471 | 1.10 | over |
| poe-pd-flyback-tps23757 | 1.145 | — | 1.264 | 1.147 | 0.407 | 1.10 | over |
| rds3 | 1.069 | — | 1.165 | 1.158 | 0.485 | 1.10 | met |
| rds3+flat | 1.262 | — | 1.364 | 1.217 | 0.549 | 1.10 | over |
| rds3-rf-selector | 1.168 | — | 1.289 | 1.131 | 0.473 | 1.10 | over |
| remora-base | 1.154 | — | 1.261 | 1.160 | 0.472 | 1.10 | over |
| remora-rf | 1.131 | — | 1.238 | 1.167 | 0.482 | 1.10 | over |
| rf-switch-8way | 1.222 | — | 1.343 | 1.150 | 0.416 | 1.10 | over |
| rf-switch-eval | 1.225 | — | 1.346 | 1.140 | 0.467 | 1.10 | over |
| stm32n6 | 1.150 | — | 1.267 | 1.164 | 0.472 | 1.10 | over |
| straps | 1.150 | — | 1.277 | 1.179 | 0.471 | 1.10 | over |
| straps-base | 1.269 | — | 1.395 | 1.214 | 0.508 | 1.10 | over |
| w55rp20 | 1.149 | — | 1.232 | 1.134 | 0.454 | 1.10 | over |

EDA geomean ÷ Zig RS: 1.171.

## Rows

All 46 rows at both registered sizes. Rust is the existing row reference. The historical row threshold is 1.10× Zig RS; its Rust ratio is reported alongside it.

| program / arm | ÷ Zig RS | ÷ rust-checked | ÷ Zig RF | ÷ plain Rust | ÷ Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---|
| alloc_retained/4096 | 0.451 | — | 0.481 | 0.452 | 0.304 | 1.10 | met |
| alloc_retained/64 | 0.458 | — | 0.470 | 0.438 | 0.303 | 1.10 | met |
| alloc_short/4096 | 0.219 | — | 937.673 | 0.954 | 0.592 | 1.10 | met |
| alloc_short/64 | 0.229 | — | 20.281 | 0.947 | 0.519 | 1.10 | met |
| binary_search/4096 | 0.228 | — | 0.560 | 0.849 | 0.303 | 1.10 | met |
| binary_search/64 | 0.657 | — | 0.649 | 0.935 | 0.537 | 1.10 | met |
| branch_mixed/4096 | 0.043 | — | 0.079 | 0.081 | 0.047 | 1.10 | met |
| branch_mixed/64 | 0.055 | — | 0.108 | 0.110 | 0.068 | 1.10 | met |
| branch_predictable/4096 | 0.051 | — | 0.124 | 0.124 | 0.059 | 1.10 | met |
| branch_predictable/64 | 0.063 | — | 0.150 | 0.153 | 0.074 | 1.10 | met |
| buffer_write/4096 | 0.665 | — | — | 0.757 | 0.819 | 1.10 | met |
| buffer_write/64 | 0.667 | — | — | 0.745 | 0.825 | 1.10 | met |
| bytes_scan/4096 | 0.039 | — | 0.073 | 0.047 | 0.052 | 1.10 | met |
| bytes_scan/64 | 0.134 | — | 0.301 | 0.201 | 0.131 | 1.10 | met |
| call_direct/4096 | 0.100 | — | 0.149 | 0.149 | 0.089 | 1.10 | met |
| call_direct/64 | 0.078 | — | 0.100 | 0.110 | 0.076 | 1.10 | met |
| call_indirect/4096 | 0.033 | — | 0.050 | 0.042 | 0.036 | 1.10 | met |
| call_indirect/64 | 0.033 | — | 0.047 | 0.041 | 0.036 | 1.10 | met |
| csv_aggregate/4096 | 1.126 | — | 1.335 | 1.005 | 0.849 | 1.10 | over |
| csv_aggregate/64 | 1.132 | — | 1.393 | 1.045 | 0.861 | 1.10 | over |
| dict_lookup/4096 | 0.296 | — | 0.365 | 0.368 | 0.499 | 1.10 | met |
| dict_lookup/64 | 0.494 | — | 0.943 | 0.374 | 0.554 | 1.10 | met |
| dict_lookup_str/4096 | 0.364 | — | 0.460 | 0.372 | 0.560 | 1.10 | met |
| dict_lookup_str/64 | 0.605 | — | 0.768 | 0.336 | 0.557 | 1.10 | met |
| dict_update/4096 | 0.349 | — | 0.498 | 0.463 | 0.379 | 1.10 | met |
| dict_update/64 | 0.610 | — | 1.159 | 0.471 | 0.357 | 1.10 | met |
| dict_update_str/4096 | 0.386 | — | 0.451 | 0.306 | 0.423 | 1.10 | met |
| dict_update_str/64 | 0.639 | — | 0.831 | 0.299 | 0.421 | 1.10 | met |
| float_format/4096 | 0.737 | — | — | 0.737 | 1.160 | 1.10 | met |
| float_format/64 | 0.736 | — | — | 0.779 | 1.150 | 1.10 | met |
| float_math/4096 | 0.240 | — | 0.363 | 0.225 | 0.240 | 1.10 | met |
| float_math/64 | 0.242 | — | 0.363 | 0.233 | 0.246 | 1.10 | met |
| grid_dp/4096 | 0.725 | — | — | 0.851 | 0.573 | 1.10 | met |
| grid_dp/64 | 0.944 | — | — | 1.004 | 0.502 | 1.10 | met |
| int_format/4096 | 0.289 | — | 0.326 | 0.973 | 0.872 | 1.10 | met |
| int_format/64 | 0.287 | — | 0.342 | 0.938 | 0.863 | 1.10 | met |
| int_math/4096 | 0.046 | — | 0.051 | 0.063 | 0.047 | 1.10 | met |
| int_math/64 | 0.060 | — | 0.067 | 0.080 | 0.062 | 1.10 | met |
| int_parse/4096 | 0.936 | — | 1.051 | 1.193 | 0.248 | 1.10 | met |
| int_parse/64 | 1.047 | — | 1.119 | 1.325 | 0.262 | 1.10 | met |
| json_transform/4096 | 0.934 | — | 1.207 | 1.511 | 0.324 | 1.10 | met |
| json_transform/64 | 0.954 | — | 1.262 | 1.385 | 0.358 | 1.10 | met |
| list_append/4096 | 0.527 | — | 1.181 | 1.046 | 0.555 | 1.10 | met |
| list_append/64 | 0.395 | — | 0.900 | 0.647 | 0.449 | 1.10 | met |
| list_filter/4096 | 0.685 | — | 0.966 | 1.262 | 0.634 | 1.10 | met |
| list_filter/64 | 0.576 | — | 0.856 | 0.795 | 0.433 | 1.10 | met |
| list_scan/4096 | 0.840 | — | 1.067 | 1.420 | 1.227 | 1.10 | met |
| list_scan/64 | 0.833 | — | 1.051 | 1.390 | 1.131 | 1.10 | met |
| lox_eval/4096 | 0.361 | — | 0.368 | 1.115 | 0.885 | 1.10 | met |
| lox_eval/64 | 0.364 | — | 0.371 | 1.106 | 0.959 | 1.10 | met |
| mutate_nested/4096 | 0.148 | — | 0.165 | 0.137 | 0.142 | 1.10 | met |
| mutate_nested/64 | 0.179 | — | 0.199 | 0.185 | 0.176 | 1.10 | met |
| mutate_shared/4096 | 0.641 | — | 0.890 | 1.008 | 0.199 | 1.10 | met |
| mutate_shared/64 | 0.652 | — | 1.027 | 0.990 | 0.149 | 1.10 | met |
| mutate_unique/4096 | 0.860 | — | 0.893 | 1.104 | 0.959 | 1.10 | met |
| mutate_unique/64 | 0.861 | — | 0.894 | 1.107 | 0.964 | 1.10 | met |
| option_handle/4096 | 0.307 | — | 0.379 | 0.832 | 0.311 | 1.10 | met |
| option_handle/64 | 0.342 | — | 0.470 | 0.799 | 0.385 | 1.10 | met |
| packet_decode/4096 | 0.800 | — | 1.764 | 1.456 | 0.555 | 1.10 | met |
| packet_decode/64 | 0.768 | — | 1.636 | 1.419 | 0.540 | 1.10 | met |
| record_construct/4096 | 0.219 | — | 0.260 | 0.334 | 0.240 | 1.10 | met |
| record_construct/64 | 0.217 | — | 0.262 | 0.327 | 0.241 | 1.10 | met |
| record_pass/4096 | 0.664 | — | — | 1.022 | 0.255 | 1.10 | met |
| record_pass/64 | 0.683 | — | — | 1.050 | 0.271 | 1.10 | met |
| record_reads/4096 | 0.741 | — | 0.825 | 1.014 | 0.850 | 1.10 | met |
| record_reads/64 | 0.729 | — | 0.785 | 1.010 | 0.842 | 1.10 | met |
| record_update/4096 | 0.206 | — | 0.260 | 0.334 | 0.237 | 1.10 | met |
| record_update/64 | 0.206 | — | 0.262 | 0.327 | 0.240 | 1.10 | met |
| result_propagate/4096 | 0.480 | — | 0.684 | 0.980 | 0.422 | 1.10 | met |
| result_propagate/64 | 0.454 | — | 0.710 | 0.804 | 0.385 | 1.10 | met |
| set_dedup/4096 | 0.302 | — | 0.426 | 0.392 | 0.356 | 1.10 | met |
| set_dedup/64 | 0.755 | — | 1.490 | 0.454 | 0.385 | 1.10 | met |
| sort_int/4096 | 0.691 | — | 0.989 | 0.667 | 0.195 | 1.10 | met |
| sort_int/64 | 0.572 | — | 0.943 | 0.657 | 0.151 | 1.10 | met |
| sort_records/4096 | 0.322 | — | 0.399 | 0.874 | 0.030 | 1.10 | met |
| sort_records/64 | 0.734 | — | 1.035 | 0.833 | 0.081 | 1.10 | met |
| string_equal/4096 | 0.182 | — | 0.231 | 0.375 | 0.321 | 1.10 | met |
| string_equal/64 | 0.882 | — | 0.911 | 1.171 | 0.738 | 1.10 | met |
| string_join/4096 | 0.252 | — | 0.273 | 0.328 | 0.176 | 1.10 | met |
| string_join/64 | 0.268 | — | 0.312 | 0.373 | 0.209 | 1.10 | met |
| string_search/4096 | 0.033 | — | 0.037 | 0.075 | 0.144 | 1.10 | met |
| string_search/64 | 0.210 | — | 0.257 | 0.442 | 0.764 | 1.10 | met |
| string_split/4096 | 0.942 | — | 0.994 | 2.228 | 0.921 | 1.10 | met |
| string_split/64 | 0.998 | — | 1.060 | 1.938 | 1.023 | 1.10 | met |
| tagged_stack/4096 | 0.691 | — | 0.685 | 1.276 | 1.216 | 1.10 | met |
| tagged_stack/64 | 0.692 | — | 0.685 | 1.277 | 1.217 | 1.10 | met |
| tree_build_walk/4096 | 0.681 | — | — | 0.721 | 0.858 | 1.10 | met |
| tree_build_walk/64 | 0.697 | — | — | 0.766 | 0.991 | 1.10 | met |
| union_find/4096 | 1.090 | — | — | 1.087 | 0.920 | 1.10 | met |
| union_find/64 | 0.949 | — | — | 1.063 | 0.701 | 1.10 | met |
| word_count/4096 | 0.701 | — | 0.889 | 0.522 | 0.216 | 1.10 | met |
| word_count/64 | 0.910 | — | 1.177 | 0.696 | 0.279 | 1.10 | met |
