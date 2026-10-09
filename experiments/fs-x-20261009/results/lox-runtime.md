| script/engine | mylang:release | mylang-base:release | zig:release | zig:release-safe | rust:release | go:release |
|---|---|---|---|---|---|---|
| binary_trees/vm | 1225 ms (2.52x) | 1290 ms (2.65x) | 487 ms (1.00x) | 1148 ms (2.36x) | 620 ms (1.27x) | 753 ms (1.55x) |
| binary_trees/tree | 223 ms (1.88x) | 223 ms (1.88x) | 119 ms (1.00x) | 243 ms (2.05x) | 150 ms (1.27x) | 176 ms (1.48x) |
| closures/vm | 1829 ms (2.42x) | 1837 ms (2.43x) | 757 ms (1.00x) | 1110 ms (1.47x) | 932 ms (1.23x) | 904 ms (1.19x) |
| closures/tree | 279 ms (1.69x) | 280 ms (1.69x) | 165 ms (1.00x) | 275 ms (1.67x) | 238 ms (1.44x) | 212 ms (1.28x) |
| equality/vm | 1988 ms (2.20x) | 1964 ms (2.17x) | 905 ms (1.00x) | 970 ms (1.07x) | 1027 ms (1.14x) | 1061 ms (1.17x) |
| equality/tree | 313 ms (1.97x) | 304 ms (1.92x) | 188 ms (1.19x) | 207 ms (1.31x) | 192 ms (1.21x) | 158 ms (1.00x) |
| fib/vm | 1652 ms (2.82x) | 1667 ms (2.84x) | 586 ms (1.00x) | 726 ms (1.24x) | 813 ms (1.39x) | 676 ms (1.15x) |
| fib/tree | 138 ms (1.48x) | 138 ms (1.48x) | 93 ms (1.00x) | 160 ms (1.72x) | 137 ms (1.47x) | 112 ms (1.21x) |
| instantiation/vm | 1107 ms (2.86x) | 1105 ms (2.85x) | 387 ms (1.00x) | 527 ms (1.36x) | 627 ms (1.62x) | 725 ms (1.87x) |
| instantiation/tree | 158 ms (1.21x) | 158 ms (1.22x) | 130 ms (1.00x) | 220 ms (1.69x) | 132 ms (1.02x) | 175 ms (1.35x) |
| invocation/vm | 3191 ms (4.28x) | 3141 ms (4.21x) | 746 ms (1.00x) | 1240 ms (1.66x) | 1427 ms (1.91x) | 1198 ms (1.61x) |
| invocation/tree | 511 ms (1.25x) | 512 ms (1.25x) | 410 ms (1.00x) | 736 ms (1.79x) | 441 ms (1.08x) | 561 ms (1.37x) |
| method_call/vm | 2760 ms (3.25x) | 2711 ms (3.20x) | 848 ms (1.00x) | 1178 ms (1.39x) | 1256 ms (1.48x) | 1122 ms (1.32x) |
| method_call/tree | 460 ms (1.66x) | 456 ms (1.64x) | 278 ms (1.00x) | 453 ms (1.63x) | 317 ms (1.14x) | 408 ms (1.47x) |
| properties/vm | 2598 ms (3.34x) | 2641 ms (3.39x) | 779 ms (1.00x) | 1199 ms (1.54x) | 1333 ms (1.71x) | 1141 ms (1.47x) |
| properties/tree | 478 ms (1.47x) | 479 ms (1.48x) | 325 ms (1.00x) | 552 ms (1.70x) | 380 ms (1.17x) | 439 ms (1.35x) |
| string_equality/vm | 1816 ms (3.85x) | 1806 ms (3.83x) | 471 ms (1.00x) | 604 ms (1.28x) | 784 ms (1.66x) | 971 ms (2.06x) |
| string_equality/tree | 446 ms (3.24x) | 444 ms (3.23x) | 138 ms (1.00x) | 172 ms (1.25x) | 365 ms (2.65x) | 161 ms (1.17x) |
| strings/vm | 1048 ms (2.06x) | 1029 ms (2.02x) | 510 ms (1.00x) | 992 ms (1.95x) | 550 ms (1.08x) | 627 ms (1.23x) |
| strings/tree | 143 ms (1.66x) | 142 ms (1.65x) | 86 ms (1.00x) | 146 ms (1.68x) | 118 ms (1.36x) | 108 ms (1.25x) |
| trees/vm | 2772 ms (2.90x) | 2869 ms (3.00x) | 956 ms (1.00x) | 1427 ms (1.49x) | 1424 ms (1.49x) | 1269 ms (1.33x) |
| trees/tree | 239 ms (1.70x) | 236 ms (1.68x) | 140 ms (1.00x) | 216 ms (1.54x) | 160 ms (1.14x) | 186 ms (1.33x) |
| zoo/vm | 2776 ms (3.21x) | 2818 ms (3.26x) | 864 ms (1.00x) | 1316 ms (1.52x) | 1511 ms (1.75x) | 1227 ms (1.42x) |
| zoo/tree | 488 ms (1.40x) | 492 ms (1.42x) | 347 ms (1.00x) | 584 ms (1.68x) | 440 ms (1.27x) | 507 ms (1.46x) |
| zoo_batch/vm | 2299 ms (3.13x) | 2296 ms (3.13x) | 734 ms (1.00x) | 1090 ms (1.48x) | 1223 ms (1.67x) | 1015 ms (1.38x) |
| zoo_batch/tree | 427 ms (1.47x) | 428 ms (1.47x) | 290 ms (1.00x) | 489 ms (1.68x) | 364 ms (1.25x) | 435 ms (1.50x) |
