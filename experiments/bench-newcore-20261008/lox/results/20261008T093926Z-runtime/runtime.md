| script/engine | mylang:release | zig:release | zig:release-safe | rust:release | go:release |
|---|---|---|---|---|---|
| closures/vm | 17952 ms (23.48x) | 765 ms (1.00x) | 1128 ms (1.47x) | 962 ms (1.26x) | 968 ms (1.27x) |
| closures/tree | 841 ms (5.08x) | 166 ms (1.00x) | 278 ms (1.68x) | 242 ms (1.46x) | 215 ms (1.30x) |
| equality/vm | 22847 ms (24.70x) | 925 ms (1.00x) | 992 ms (1.07x) | 1064 ms (1.15x) | 1106 ms (1.20x) |
| equality/tree | 968 ms (5.89x) | 193 ms (1.17x) | 225 ms (1.37x) | 199 ms (1.21x) | 164 ms (1.00x) |
| fib/vm | 19459 ms (31.15x) | 625 ms (1.00x) | 785 ms (1.26x) | 837 ms (1.34x) | 723 ms (1.16x) |
| fib/tree | 445 ms (4.50x) | 99 ms (1.00x) | 163 ms (1.65x) | 139 ms (1.41x) | 114 ms (1.16x) |
| instantiation/tree | 7148 ms (58.49x) | 122 ms (1.00x) | 226 ms (1.85x) | 134 ms (1.10x) | 182 ms (1.49x) |
| invocation/vm | 25514 ms (33.06x) | 772 ms (1.00x) | 1320 ms (1.71x) | 1436 ms (1.86x) | 1238 ms (1.60x) |
| invocation/tree | 1518 ms (3.65x) | 416 ms (1.00x) | 745 ms (1.79x) | 443 ms (1.07x) | 582 ms (1.40x) |
| method_call/vm | 23190 ms (25.90x) | 895 ms (1.00x) | 1194 ms (1.33x) | 1265 ms (1.41x) | 1165 ms (1.30x) |
| properties/vm | 19913 ms (25.16x) | 792 ms (1.00x) | 1211 ms (1.53x) | 1380 ms (1.74x) | 1161 ms (1.47x) |
| properties/tree | 1254 ms (3.79x) | 331 ms (1.00x) | 561 ms (1.69x) | 383 ms (1.16x) | 444 ms (1.34x) |
| string_equality/vm | 25843 ms (53.25x) | 485 ms (1.00x) | 610 ms (1.26x) | 802 ms (1.65x) | 997 ms (2.05x) |
| string_equality/tree | 1279 ms (8.99x) | 142 ms (1.00x) | 182 ms (1.28x) | 366 ms (2.57x) | 164 ms (1.15x) |
| strings/vm | 10502 ms (20.27x) | 518 ms (1.00x) | 983 ms (1.90x) | 548 ms (1.06x) | 642 ms (1.24x) |
| strings/tree | 377 ms (4.39x) | 86 ms (1.00x) | 149 ms (1.73x) | 119 ms (1.38x) | 109 ms (1.27x) |
| zoo/vm | 24440 ms (27.67x) | 883 ms (1.00x) | 1320 ms (1.49x) | 1489 ms (1.69x) | 1255 ms (1.42x) |
| zoo/tree | 1499 ms (4.26x) | 352 ms (1.00x) | 594 ms (1.68x) | 448 ms (1.27x) | 511 ms (1.45x) |
| zoo_batch/vm | 21425 ms (28.91x) | 741 ms (1.00x) | 1090 ms (1.47x) | 1219 ms (1.64x) | 1035 ms (1.40x) |
| zoo_batch/tree | 1314 ms (4.43x) | 296 ms (1.00x) | 498 ms (1.68x) | 376 ms (1.27x) | 433 ms (1.46x) |
