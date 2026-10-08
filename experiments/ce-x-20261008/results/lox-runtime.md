| script/engine | mylang:release | mylang-base:release | zig:release | zig:release-safe | rust:release | go:release |
|---|---|---|---|---|---|---|
| closures/vm | 3943 ms (5.13x) | 18574 ms (24.16x) | 769 ms (1.00x) | 1129 ms (1.47x) | 962 ms (1.25x) | 971 ms (1.26x) |
| closures/tree | 362 ms (1.92x) | 907 ms (4.82x) | 188 ms (1.00x) | 312 ms (1.66x) | 265 ms (1.41x) | 244 ms (1.30x) |
| equality/vm | 7646 ms (8.29x) | 23653 ms (25.66x) | 922 ms (1.00x) | 1003 ms (1.09x) | 1086 ms (1.18x) | 1132 ms (1.23x) |
| equality/tree | 315 ms (1.91x) | 964 ms (5.86x) | 193 ms (1.17x) | 209 ms (1.27x) | 200 ms (1.22x) | 165 ms (1.00x) |
| fib/vm | 4123 ms (6.50x) | 19421 ms (30.60x) | 635 ms (1.00x) | 814 ms (1.28x) | 868 ms (1.37x) | 756 ms (1.19x) |
| fib/tree | 155 ms (1.53x) | 449 ms (4.43x) | 101 ms (1.00x) | 164 ms (1.62x) | 143 ms (1.42x) | 120 ms (1.18x) |
| instantiation/tree | 160 ms (1.21x) | 7353 ms (55.52x) | 132 ms (1.00x) | 229 ms (1.73x) | 140 ms (1.06x) | 194 ms (1.46x) |
| invocation/vm | 5931 ms (7.49x) | 25503 ms (32.22x) | 792 ms (1.00x) | 1369 ms (1.73x) | 1500 ms (1.89x) | 1348 ms (1.70x) |
| invocation/tree | 546 ms (1.28x) | 1549 ms (3.64x) | 425 ms (1.00x) | 763 ms (1.79x) | 464 ms (1.09x) | 621 ms (1.46x) |
| method_call/vm | 5625 ms (6.26x) | 23346 ms (25.97x) | 899 ms (1.00x) | 1289 ms (1.43x) | 1345 ms (1.50x) | 1256 ms (1.40x) |
| properties/vm | 4528 ms (5.76x) | 21876 ms (27.81x) | 787 ms (1.00x) | 1228 ms (1.56x) | 1351 ms (1.72x) | 1190 ms (1.51x) |
| properties/tree | 529 ms (1.62x) | 1263 ms (3.87x) | 326 ms (1.00x) | 561 ms (1.72x) | 383 ms (1.17x) | 464 ms (1.42x) |
| string_equality/vm | 6300 ms (13.21x) | 25580 ms (53.62x) | 477 ms (1.00x) | 609 ms (1.28x) | 815 ms (1.71x) | 1001 ms (2.10x) |
| string_equality/tree | 467 ms (3.28x) | 1285 ms (9.02x) | 142 ms (1.00x) | 180 ms (1.27x) | 365 ms (2.57x) | 165 ms (1.16x) |
| strings/vm | 2379 ms (4.60x) | 10820 ms (20.91x) | 517 ms (1.00x) | 1003 ms (1.94x) | 554 ms (1.07x) | 646 ms (1.25x) |
| strings/tree | 156 ms (1.80x) | 377 ms (4.33x) | 87 ms (1.00x) | 149 ms (1.71x) | 121 ms (1.39x) | 111 ms (1.27x) |
| zoo/vm | 5124 ms (5.89x) | 25322 ms (29.10x) | 870 ms (1.00x) | 1361 ms (1.56x) | 1492 ms (1.71x) | 1266 ms (1.45x) |
| zoo/tree | 546 ms (1.56x) | 1523 ms (4.34x) | 351 ms (1.00x) | 586 ms (1.67x) | 443 ms (1.26x) | 511 ms (1.46x) |
| zoo_batch/vm | 4521 ms (6.10x) | 21283 ms (28.71x) | 741 ms (1.00x) | 1104 ms (1.49x) | 1210 ms (1.63x) | 1046 ms (1.41x) |
| zoo_batch/tree | 473 ms (1.60x) | 1317 ms (4.45x) | 296 ms (1.00x) | 493 ms (1.67x) | 370 ms (1.25x) | 437 ms (1.48x) |
