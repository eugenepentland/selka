| script/engine | mylang:release | mylang-base:release | zig:release | zig:release-safe | rust:release | go:release |
|---|---|---|---|---|---|---|
| binary_trees/vm | 1238 ms (2.17x) | 1524 ms (2.67x) | 571 ms (1.00x) | 1353 ms (2.37x) | 709 ms (1.24x) | 884 ms (1.55x) |
| binary_trees/tree | 237 ms (1.80x) | 264 ms (2.01x) | 132 ms (1.00x) | 259 ms (1.97x) | 160 ms (1.22x) | 191 ms (1.46x) |
| closures/vm | 1661 ms (2.14x) | 2066 ms (2.67x) | 775 ms (1.00x) | 1139 ms (1.47x) | 973 ms (1.26x) | 1060 ms (1.37x) |
| closures/tree | 300 ms (1.66x) | 333 ms (1.84x) | 181 ms (1.00x) | 288 ms (1.59x) | 248 ms (1.37x) | 232 ms (1.28x) |
| equality/vm | 1862 ms (1.95x) | 2411 ms (2.53x) | 954 ms (1.00x) | 1086 ms (1.14x) | 1174 ms (1.23x) | 1221 ms (1.28x) |
| equality/tree | 326 ms (1.79x) | 358 ms (1.96x) | 198 ms (1.09x) | 224 ms (1.23x) | 218 ms (1.20x) | 183 ms (1.00x) |
| fib/vm | 1523 ms (2.39x) | 1897 ms (2.98x) | 637 ms (1.00x) | 799 ms (1.25x) | 859 ms (1.35x) | 740 ms (1.16x) |
| fib/tree | 145 ms (1.51x) | 156 ms (1.62x) | 96 ms (1.00x) | 165 ms (1.71x) | 139 ms (1.45x) | 117 ms (1.21x) |
| instantiation/vm | 978 ms (2.45x) | 1184 ms (2.97x) | 398 ms (1.00x) | 566 ms (1.42x) | 639 ms (1.60x) | 770 ms (1.93x) |
| instantiation/tree | 170 ms (1.36x) | 170 ms (1.36x) | 125 ms (1.00x) | 229 ms (1.83x) | 139 ms (1.11x) | 184 ms (1.47x) |
| invocation/vm | 2905 ms (3.82x) | 3644 ms (4.80x) | 760 ms (1.00x) | 1307 ms (1.72x) | 1450 ms (1.91x) | 1375 ms (1.81x) |
| invocation/tree | 534 ms (1.28x) | 566 ms (1.36x) | 417 ms (1.00x) | 788 ms (1.89x) | 486 ms (1.17x) | 625 ms (1.50x) |
| method_call/vm | 2527 ms (2.57x) | 3199 ms (3.25x) | 985 ms (1.00x) | 1358 ms (1.38x) | 1395 ms (1.42x) | 1295 ms (1.31x) |
| method_call/tree | 533 ms (1.81x) | 570 ms (1.94x) | 294 ms (1.00x) | 504 ms (1.72x) | 364 ms (1.24x) | 485 ms (1.65x) |
| properties/vm | 2509 ms (2.86x) | 3277 ms (3.74x) | 876 ms (1.00x) | 1398 ms (1.60x) | 1558 ms (1.78x) | 1307 ms (1.49x) |
| properties/tree | 556 ms (1.52x) | 586 ms (1.60x) | 366 ms (1.00x) | 665 ms (1.82x) | 452 ms (1.23x) | 541 ms (1.48x) |
| string_equality/vm | 1380 ms (2.47x) | 2367 ms (4.24x) | 558 ms (1.00x) | 736 ms (1.32x) | 976 ms (1.75x) | 1115 ms (2.00x) |
| string_equality/tree | 475 ms (2.88x) | 527 ms (3.19x) | 165 ms (1.00x) | 220 ms (1.33x) | 426 ms (2.58x) | 183 ms (1.11x) |
| strings/vm | 1143 ms (1.88x) | 1356 ms (2.23x) | 608 ms (1.00x) | 1211 ms (1.99x) | 674 ms (1.11x) | 791 ms (1.30x) |
| strings/tree | 160 ms (1.63x) | 185 ms (1.89x) | 98 ms (1.00x) | 173 ms (1.76x) | 141 ms (1.44x) | 132 ms (1.35x) |
| trees/vm | 2714 ms (2.47x) | 3260 ms (2.97x) | 1096 ms (1.00x) | 1610 ms (1.47x) | 1533 ms (1.40x) | 1470 ms (1.34x) |
| trees/tree | 268 ms (1.76x) | 283 ms (1.86x) | 152 ms (1.00x) | 251 ms (1.65x) | 184 ms (1.21x) | 219 ms (1.44x) |
| zoo/vm | 2647 ms (2.78x) | 3232 ms (3.39x) | 953 ms (1.00x) | 1485 ms (1.56x) | 1568 ms (1.65x) | 1398 ms (1.47x) |
| zoo/tree | 584 ms (1.51x) | 591 ms (1.53x) | 387 ms (1.00x) | 678 ms (1.75x) | 525 ms (1.36x) | 622 ms (1.61x) |
| zoo_batch/vm | 2405 ms (2.65x) | 2914 ms (3.21x) | 907 ms (1.00x) | 1372 ms (1.51x) | 1447 ms (1.60x) | 1259 ms (1.39x) |
| zoo_batch/tree | 457 ms (1.48x) | 503 ms (1.63x) | 308 ms (1.00x) | 523 ms (1.70x) | 391 ms (1.27x) | 471 ms (1.53x) |
