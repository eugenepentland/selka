| script/engine | mylang:release | mylang-base:release | zig:release | zig:release-safe | rust:release | go:release |
|---|---|---|---|---|---|---|
| binary_trees/vm | 1296 ms (2.64x) | 2440 ms (4.96x) | 492 ms (1.00x) | 1146 ms (2.33x) | 633 ms (1.29x) | 743 ms (1.51x) |
| binary_trees/tree | 221 ms (1.76x) | 226 ms (1.79x) | 126 ms (1.00x) | 244 ms (1.94x) | 152 ms (1.21x) | 176 ms (1.40x) |
| closures/vm | 1852 ms (2.48x) | 3687 ms (4.94x) | 747 ms (1.00x) | 1112 ms (1.49x) | 949 ms (1.27x) | 903 ms (1.21x) |
| closures/tree | 283 ms (1.72x) | 319 ms (1.94x) | 165 ms (1.00x) | 273 ms (1.66x) | 235 ms (1.43x) | 210 ms (1.27x) |
| equality/vm | 1985 ms (2.19x) | 6318 ms (6.98x) | 906 ms (1.00x) | 966 ms (1.07x) | 1027 ms (1.13x) | 1061 ms (1.17x) |
| equality/tree | 305 ms (1.92x) | 299 ms (1.89x) | 189 ms (1.19x) | 208 ms (1.31x) | 193 ms (1.22x) | 159 ms (1.00x) |
| fib/vm | 1747 ms (2.97x) | 3927 ms (6.67x) | 588 ms (1.00x) | 733 ms (1.25x) | 810 ms (1.38x) | 667 ms (1.13x) |
| fib/tree | 138 ms (1.45x) | 151 ms (1.58x) | 95 ms (1.00x) | 158 ms (1.65x) | 136 ms (1.43x) | 112 ms (1.18x) |
| instantiation/vm | 1103 ms (2.86x) | 1890 ms (4.89x) | 386 ms (1.00x) | 547 ms (1.42x) | 630 ms (1.63x) | 723 ms (1.87x) |
| instantiation/tree | 159 ms (1.30x) | 157 ms (1.28x) | 123 ms (1.00x) | 219 ms (1.78x) | 132 ms (1.07x) | 175 ms (1.42x) |
| invocation/vm | 3270 ms (4.41x) | 5468 ms (7.37x) | 742 ms (1.00x) | 1238 ms (1.67x) | 1421 ms (1.91x) | 1197 ms (1.61x) |
| invocation/tree | 516 ms (1.29x) | 503 ms (1.25x) | 401 ms (1.00x) | 736 ms (1.84x) | 441 ms (1.10x) | 562 ms (1.40x) |
| method_call/vm | 2728 ms (3.22x) | 5094 ms (6.00x) | 848 ms (1.00x) | 1178 ms (1.39x) | 1252 ms (1.48x) | 1120 ms (1.32x) |
| method_call/tree | 450 ms (1.65x) | 497 ms (1.82x) | 273 ms (1.00x) | 455 ms (1.67x) | 315 ms (1.15x) | 406 ms (1.49x) |
| properties/vm | 2612 ms (3.37x) | 4352 ms (5.61x) | 776 ms (1.00x) | 1202 ms (1.55x) | 1327 ms (1.71x) | 1142 ms (1.47x) |
| properties/tree | 481 ms (1.46x) | 517 ms (1.57x) | 330 ms (1.00x) | 553 ms (1.68x) | 378 ms (1.15x) | 438 ms (1.33x) |
| string_equality/vm | 1799 ms (3.82x) | 6445 ms (13.68x) | 471 ms (1.00x) | 603 ms (1.28x) | 779 ms (1.65x) | 967 ms (2.05x) |
| string_equality/tree | 439 ms (3.23x) | 444 ms (3.26x) | 136 ms (1.00x) | 173 ms (1.27x) | 363 ms (2.67x) | 160 ms (1.18x) |
| strings/vm | 1021 ms (2.00x) | 2301 ms (4.51x) | 510 ms (1.00x) | 988 ms (1.94x) | 544 ms (1.07x) | 626 ms (1.23x) |
| strings/tree | 143 ms (1.67x) | 151 ms (1.77x) | 86 ms (1.00x) | 147 ms (1.72x) | 116 ms (1.35x) | 107 ms (1.24x) |
| trees/vm | 2855 ms (2.96x) | 5267 ms (5.47x) | 963 ms (1.00x) | 1423 ms (1.48x) | 1370 ms (1.42x) | 1257 ms (1.30x) |
| trees/tree | 234 ms (1.71x) | 243 ms (1.77x) | 137 ms (1.00x) | 217 ms (1.58x) | 157 ms (1.15x) | 191 ms (1.39x) |
| zoo/vm | 2793 ms (3.25x) | 5076 ms (5.90x) | 860 ms (1.00x) | 1312 ms (1.53x) | 1484 ms (1.73x) | 1226 ms (1.42x) |
| zoo/tree | 484 ms (1.41x) | 530 ms (1.54x) | 343 ms (1.00x) | 582 ms (1.70x) | 442 ms (1.29x) | 507 ms (1.48x) |
| zoo_batch/vm | 2340 ms (3.18x) | 4456 ms (6.06x) | 735 ms (1.00x) | 1091 ms (1.48x) | 1203 ms (1.64x) | 1015 ms (1.38x) |
| zoo_batch/tree | 424 ms (1.46x) | 461 ms (1.58x) | 291 ms (1.00x) | 489 ms (1.68x) | 365 ms (1.25x) | 433 ms (1.49x) |
