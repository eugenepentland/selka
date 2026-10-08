| script/engine | mylang:release | mylang-base:release | zig:release | zig:release-safe | rust:release | go:release |
|---|---|---|---|---|---|---|
| binary_trees/vm | 1562 ms (2.79x) | 2889 ms (5.16x) | 560 ms (1.00x) | 1366 ms (2.44x) | 715 ms (1.28x) | 885 ms (1.58x) |
| binary_trees/tree | 257 ms (2.00x) | 265 ms (2.06x) | 128 ms (1.00x) | 276 ms (2.15x) | 172 ms (1.34x) | 200 ms (1.56x) |
| closures/vm | 2269 ms (2.44x) | 4426 ms (4.75x) | 931 ms (1.00x) | 1340 ms (1.44x) | 1148 ms (1.23x) | 1077 ms (1.16x) |
| closures/tree | 347 ms (1.89x) | 369 ms (2.01x) | 184 ms (1.00x) | 307 ms (1.67x) | 270 ms (1.47x) | 242 ms (1.32x) |
| equality/vm | 2333 ms (2.31x) | 7382 ms (7.32x) | 1009 ms (1.00x) | 1103 ms (1.09x) | 1249 ms (1.24x) | 1356 ms (1.34x) |
| equality/tree | 360 ms (1.90x) | 366 ms (1.93x) | 214 ms (1.13x) | 241 ms (1.27x) | 231 ms (1.22x) | 190 ms (1.00x) |
| fib/vm | 1987 ms (2.94x) | 4521 ms (6.69x) | 676 ms (1.00x) | 879 ms (1.30x) | 921 ms (1.36x) | 801 ms (1.19x) |
| fib/tree | 153 ms (1.51x) | 169 ms (1.66x) | 102 ms (1.00x) | 174 ms (1.72x) | 154 ms (1.52x) | 124 ms (1.22x) |
| instantiation/vm | 1240 ms (2.75x) | 2185 ms (4.85x) | 451 ms (1.00x) | 649 ms (1.44x) | 712 ms (1.58x) | 878 ms (1.95x) |
| instantiation/tree | 170 ms (1.31x) | 182 ms (1.40x) | 130 ms (1.00x) | 252 ms (1.94x) | 155 ms (1.19x) | 209 ms (1.60x) |
| invocation/vm | 3556 ms (4.34x) | 5991 ms (7.31x) | 819 ms (1.00x) | 1376 ms (1.68x) | 1567 ms (1.91x) | 1370 ms (1.67x) |
| invocation/tree | 606 ms (1.38x) | 597 ms (1.36x) | 440 ms (1.00x) | 821 ms (1.87x) | 520 ms (1.18x) | 668 ms (1.52x) |
| method_call/vm | 2888 ms (3.11x) | 5988 ms (6.45x) | 929 ms (1.00x) | 1291 ms (1.39x) | 1331 ms (1.43x) | 1201 ms (1.29x) |
| method_call/tree | 496 ms (1.73x) | 558 ms (1.95x) | 287 ms (1.00x) | 471 ms (1.64x) | 339 ms (1.18x) | 446 ms (1.55x) |
| properties/vm | 2812 ms (3.54x) | 4831 ms (6.08x) | 794 ms (1.00x) | 1244 ms (1.57x) | 1354 ms (1.71x) | 1210 ms (1.52x) |
| properties/tree | 497 ms (1.52x) | 540 ms (1.66x) | 326 ms (1.00x) | 560 ms (1.72x) | 384 ms (1.18x) | 474 ms (1.45x) |
| string_equality/vm | 2112 ms (4.38x) | 6717 ms (13.92x) | 483 ms (1.00x) | 614 ms (1.27x) | 824 ms (1.71x) | 1091 ms (2.26x) |
| string_equality/tree | 522 ms (3.31x) | 520 ms (3.30x) | 158 ms (1.00x) | 205 ms (1.30x) | 387 ms (2.46x) | 187 ms (1.19x) |
| strings/vm | 1201 ms (2.00x) | 2658 ms (4.43x) | 600 ms (1.00x) | 1167 ms (1.94x) | 620 ms (1.03x) | 736 ms (1.23x) |
| strings/tree | 153 ms (1.76x) | 156 ms (1.80x) | 87 ms (1.00x) | 151 ms (1.73x) | 120 ms (1.38x) | 114 ms (1.31x) |
| trees/vm | 3256 ms (3.30x) | 5377 ms (5.46x) | 985 ms (1.00x) | 1453 ms (1.47x) | 1461 ms (1.48x) | 1327 ms (1.35x) |
| trees/tree | 247 ms (1.72x) | 255 ms (1.78x) | 144 ms (1.00x) | 229 ms (1.59x) | 173 ms (1.21x) | 196 ms (1.37x) |
| zoo/vm | 3291 ms (3.34x) | 5868 ms (5.96x) | 985 ms (1.00x) | 1551 ms (1.57x) | 1675 ms (1.70x) | 1510 ms (1.53x) |
| zoo/tree | 562 ms (1.47x) | 618 ms (1.62x) | 382 ms (1.00x) | 669 ms (1.75x) | 499 ms (1.31x) | 568 ms (1.49x) |
| zoo_batch/vm | 2679 ms (3.22x) | 5355 ms (6.44x) | 832 ms (1.00x) | 1276 ms (1.53x) | 1313 ms (1.58x) | 1154 ms (1.39x) |
| zoo_batch/tree | 500 ms (1.56x) | 545 ms (1.70x) | 321 ms (1.00x) | 550 ms (1.71x) | 410 ms (1.28x) | 499 ms (1.55x) |
