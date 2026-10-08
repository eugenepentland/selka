# VP3 generated tables

Every byte figure is bytes moved by copies the core emitted or the runtime made; `growth` is list, dictionary, buffer and text growth that moved contents.

## Lox (both engines; the larger N of each cell; per unit = per N)

| program | instructions | retains | releases | runtime count ops | unique tests (shared) | copies | record bytes | list/dict/buffer/text bytes | growth bytes | allocs | peak live | bytes copied per unit | bytes per instruction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| tree binary_trees N=5 (×3.40 vs N=4) | 35.86 G | 586.05 k | 616.20 k | 120.70 M | 155.37 k (17.41 k) | 1.49 M | 326.59 M | 4.45 G | 250.81 M | 45.27 k | 4.54 M | 1.00 G | 0.14 |
| tree closures N=100000 (×2.00 vs N=50000) | 4.76 G | 60.95 M | 63.89 M | 16.67 k | 17.51 M (1.73 M) | 166.21 M | 36.57 G | 220.34 M | 1.43 M | 2.95 M | 3.97 M | 367.94 k | 7.74 |
| tree equality N=200000 (×2.00 vs N=100000) | 8.02 G | 140.41 M | 141.20 M | 8.41 k | 24.19 M (400.00 k) | 297.12 M | 72.23 G | 105.31 M | 1.94 M | 800.48 k | 3.65 M | 361.67 k | 9.02 |
| tree fib N=27 (×1.62 vs N=26) | 3.06 G | 40.36 M | 41.63 M | 3.34 k | 10.80 M (635.62 k) | 110.25 M | 24.89 G | 26.07 M | 1.39 M | 1.27 M | 3.96 M | 922.92 M | 8.14 |
| tree instantiation N=10000 (×2.00 vs N=5000) | 1.25 G | 7.37 M | 8.87 M | 28.18 k | 5.79 M (310.00 k) | 46.41 M | 9.19 G | 78.66 G | 1.96 M | 1.52 M | 3.86 M | 8.79 M | 70.04 |
| tree invocation N=100000 (×2.00 vs N=50000) | 10.60 G | 79.73 M | 88.95 M | 16.29 k | 61.36 M (3.10 M) | 448.72 M | 88.24 G | 712.35 M | 1.43 M | 9.23 M | 3.38 M | 889.50 k | 8.39 |
| tree method_call N=400 (×2.26 vs N=200) | 108.60 G | 1.42 M | 1.50 M | 166.92 M | 470.82 k (36.83 k) | 3.96 M | 816.06 M | 12.06 G | 482.74 M | 85.93 k | 5.76 M | 33.41 M | 0.12 |
| tree properties N=50000 (×2.00 vs N=25000) | 7.02 G | 81.88 M | 86.50 M | 49.19 k | 33.69 M (1.55 M) | 263.42 M | 53.23 G | 506.83 M | 1.16 M | 4.62 M | 3.05 M | 1.07 M | 7.66 |
| tree string_equality N=500 (×1.73 vs N=250) | 7.42 G | 13.07 M | 13.07 M | 8.32 M | 1.62 M (1.01 k) | 23.97 M | 5.95 G | 933.52 M | 632.00 k | 7.58 k | 2.53 M | 13.77 M | 0.93 |
| tree strings N=200000 (×2.00 vs N=100000) | 3.39 G | 41.35 M | 43.17 M | 14.87 k | 9.29 M (1.03 M) | 106.14 M | 24.64 G | 334.50 M | 1.85 M | 1.83 M | 3.84 M | 124.90 k | 7.38 |
| tree zoo N=1000000 (×2.00 vs N=500000) | 5.33 G | 59.51 M | 62.84 M | 8.22 k | 24.83 M (1.17 M) | 200.29 M | 40.96 G | 156.62 M | 1.43 M | 3.34 M | 3.31 M | 41.12 k | 7.71 |
| tree zoo_batch N=30 (×2.00 vs N=15) | 10.36 G | 116.72 M | 123.32 M | 10.38 k | 48.01 M (2.40 M) | 387.61 M | 79.67 G | 394.70 M | 1.56 M | 6.61 M | 3.44 M | 2.67 G | 7.73 |
| vm binary_trees N=7 (×2.95 vs N=6) | 74.58 G | 9.46 M | 9.55 M | 284.34 M | 2.33 M (68.17 k) | 39.73 M | 4.29 G | 7.97 G | 99.42 k | 102.75 k | 7.73 M | 1.75 G | 0.16 |
| vm closures N=100000 (×2.00 vs N=50000) | 7.42 G | 127.08 M | 127.69 M | 29.93 k | 29.64 M (420.67 k) | 606.11 M | 66.22 G | 124.38 M | 2.24 M | 621.81 k | 4.20 M | 663.42 k | 8.94 |
| vm equality N=200000 (×2.00 vs N=100000) | 16.29 G | 380.01 M | 380.41 M | 4.94 k | 91.40 M (400.57 k) | 1.17 G | 125.16 G | 103.06 M | 132.70 k | 401.22 k | 424.75 k | 626.30 k | 7.69 |
| vm fib N=27 (×1.62 vs N=26) | 5.42 G | 98.52 M | 98.52 M | 1.56 k | 22.25 M (129) | 449.71 M | 48.77 G | 41.59 k | 133.15 k | 532 | 416.85 k | 1.81 G | 9.00 |
| vm instantiation N=400 (×3.60 vs N=200) | 37.66 G | 1.03 M | 1.04 M | 144.32 M | 228.39 k (12.85 k) | 4.47 M | 488.45 M | 4.04 G | 148.63 k | 25.46 k | 2.17 M | 11.32 M | 0.12 |
| vm invocation N=100000 (×2.00 vs N=50000) | 14.21 G | 268.02 M | 268.12 M | 111.22 k | 47.90 M (101.01 k) | 1.08 G | 115.15 G | 28.40 M | 69.76 k | 102.22 k | 447.17 k | 1.15 M | 8.10 |
| vm method_call N=20000 (×2.00 vs N=10000) | 8.03 G | 140.10 M | 141.03 M | 34.90 k | 29.79 M (934.47 k) | 611.00 M | 65.73 G | 343.23 M | 69.66 k | 935.61 k | 435.96 k | 3.30 M | 8.23 |
| vm properties N=50000 (×2.00 vs N=25000) | 8.67 G | 156.53 M | 156.58 M | 198.28 k | 28.45 M (51.87 k) | 654.57 M | 70.17 G | 18.06 M | 72.32 k | 53.67 k | 465.41 k | 1.40 M | 8.09 |
| vm string_equality N=2000 (×1.97 vs N=1000) | 5.08 G | 103.06 M | 103.08 M | 265.05 k | 27.02 M (15.58 k) | 375.13 M | 40.34 G | 487.07 M | 84.48 k | 26.28 k | 679.93 k | 20.42 M | 8.04 |
| vm strings N=200000 (×2.00 vs N=100000) | 6.45 G | 112.18 M | 113.21 M | 6.68 k | 25.70 M (625.39 k) | 498.54 M | 53.69 G | 320.41 M | 135.82 k | 1.03 M | 426.74 k | 270.07 k | 8.38 |
| vm zoo N=1000000 (×2.00 vs N=500000) | 6.94 G | 117.84 M | 118.01 M | 14.95 k | 22.83 M (167.14 k) | 547.35 M | 59.09 G | 43.08 M | 134.34 k | 167.82 k | 426.31 k | 59.14 k | 8.52 |
| vm zoo_batch N=20 (×2.00 vs N=10) | 9.09 G | 155.01 M | 155.21 M | 19.82 k | 31.00 M (200.59 k) | 722.24 M | 77.95 G | 103.02 M | 132.74 k | 201.35 k | 428.17 k | 3.90 G | 8.59 |
| **Lox total** | 405.50 G | 2.31 G | 2.35 G | 725.45 M | 596.27 M (15.37 M) | 8.81 G | 1.16 T | 112.14 G | 751.78 M | 35.98 M | 7.73 M |  | 3.15 |

## EDA (34 designs; per unit = per design run)

| program | instructions | retains | releases | runtime count ops | unique tests (shared) | copies | record bytes | list/dict/buffer/text bytes | growth bytes | allocs | peak live | bytes copied per unit | bytes per instruction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| rds3+flat **(slowest six)** | 1.79 G | 11.08 M | 3.11 M | 10.16 M | 256.48 k (2.89 k) | 60.63 M | 3.01 G | 166.22 M | 500.04 M | 1.88 M | 51.61 M | 3.67 G | 2.05 |
| rds3 **(slowest six)** | 1.09 G | 3.06 M | 3.53 M | 1.37 M | 210.79 k (3.13 k) | 48.94 M | 2.45 G | 6.66 M | 36.49 M | 2.15 M | 11.71 M | 2.49 G | 2.28 |
| labstation **(slowest six)** | 896.97 M | 2.71 M | 2.82 M | 1.37 M | 154.81 k (2.71 k) | 40.72 M | 2.03 G | 6.59 M | 31.93 M | 1.69 M | 12.15 M | 2.07 G | 2.31 |
| cyclops-digital-pcb **(slowest six)** | 849.67 M | 4.74 M | 1.89 M | 4.39 M | 131.88 k (2.15 k) | 33.91 M | 1.67 G | 30.34 M | 113.68 M | 1.12 M | 24.45 M | 1.82 G | 2.14 |
| straps-base **(slowest six)** | 833.58 M | 3.18 M | 2.26 M | 2.36 M | 155.62 k (2.25 k) | 34.71 M | 1.72 G | 27.80 M | 64.13 M | 1.38 M | 21.17 M | 1.81 G | 2.17 |
| stm32n6 | 700.59 M | 2.21 M | 2.19 M | 1.29 M | 113.77 k (2.11 k) | 32.41 M | 1.61 G | 7.73 M | 31.69 M | 1.31 M | 12.21 M | 1.65 G | 2.35 |
| labstation+no-vendor-symbols | 693.26 M | 2.17 M | 2.10 M | 1.17 M | 147.65 k (2.64 k) | 28.08 M | 1.42 G | 6.67 M | 42.99 M | 1.29 M | 11.45 M | 1.47 G | 2.12 |
| barracuda-base | 690.58 M | 1.95 M | 2.25 M | 862.93 k | 96.88 k (1.79 k) | 33.43 M | 1.66 G | 3.33 M | 19.36 M | 1.34 M | 9.86 M | 1.68 G | 2.44 |
| barracuda | 633.38 M | 1.72 M | 2.10 M | 687.36 k | 87.04 k (1.81 k) | 31.08 M | 1.54 G | 1.78 M | 13.65 M | 1.25 M | 8.51 M | 1.56 G | 2.46 |
| cyclops-kband-pcb **(slowest six)** | 563.49 M | 2.69 M | 1.46 M | 2.17 M | 88.40 k (1.56 k) | 24.71 M | 1.22 G | 14.26 M | 35.83 M | 857.22 k | 16.14 M | 1.27 G | 2.25 |
| barracuda-via-fence | 545.86 M | 1.47 M | 1.82 M | 579.52 k | 71.00 k (1.48 k) | 27.25 M | 1.35 G | 1.50 M | 10.88 M | 1.08 M | 8.20 M | 1.36 G | 2.49 |
| cyclops-analog | 538.33 M | 1.52 M | 1.78 M | 674.45 k | 80.54 k (1.73 k) | 26.41 M | 1.31 G | 2.37 M | 12.14 M | 1.06 M | 8.39 M | 1.32 G | 2.45 |
| straps | 504.23 M | 1.48 M | 1.63 M | 685.87 k | 73.07 k (1.42 k) | 24.78 M | 1.22 G | 3.02 M | 13.39 M | 974.20 k | 8.08 M | 1.24 G | 2.46 |
| cyclops-kband | 502.13 M | 1.40 M | 1.66 M | 630.95 k | 74.19 k (1.60 k) | 24.87 M | 1.23 G | 2.48 M | 11.19 M | 986.77 k | 8.27 M | 1.24 G | 2.47 |
| remora-base | 496.92 M | 1.41 M | 1.62 M | 640.67 k | 63.23 k (1.21 k) | 25.02 M | 1.24 G | 2.87 M | 14.97 M | 963.10 k | 8.54 M | 1.25 G | 2.52 |
| remora-rf | 475.10 M | 1.33 M | 1.57 M | 549.04 k | 63.65 k (1.04 k) | 23.93 M | 1.18 G | 2.28 M | 10.34 M | 928.46 k | 8.15 M | 1.20 G | 2.52 |
| cyclops-kband-breakout | 421.90 M | 1.21 M | 1.37 M | 593.75 k | 59.68 k (1.26 k) | 20.99 M | 1.03 G | 2.64 M | 11.25 M | 810.99 k | 7.83 M | 1.05 G | 2.48 |
| black-canyon+flat | 416.33 M | 1.26 M | 1.29 M | 678.11 k | 47.27 k (933) | 20.52 M | 1.01 G | 5.45 M | 17.74 M | 763.63 k | 11.38 M | 1.03 G | 2.47 |
| black-canyon | 392.94 M | 1.03 M | 1.33 M | 372.62 k | 41.99 k (986) | 20.64 M | 1.01 G | 770.59 k | 5.86 M | 792.13 k | 7.78 M | 1.02 G | 2.60 |
| cyclops-interposer | 385.56 M | 1.09 M | 1.27 M | 511.22 k | 49.21 k (1.08 k) | 19.63 M | 963.81 M | 2.37 M | 8.59 M | 747.26 k | 7.76 M | 974.78 M | 2.53 |
| cyclops-xband-sip | 357.19 M | 966.48 k | 1.20 M | 404.48 k | 40.75 k (850) | 18.99 M | 930.90 M | 1.33 M | 6.02 M | 705.36 k | 7.71 M | 938.25 M | 2.63 |
| cyclops-analog+no-vendor-symbols | 355.58 M | 1.03 M | 1.12 M | 503.54 k | 76.34 k (1.70 k) | 14.50 M | 730.66 M | 2.68 M | 12.49 M | 694.55 k | 5.74 M | 745.83 M | 2.10 |
| w55rp20 | 303.15 M | 870.74 k | 1.02 M | 377.29 k | 28.82 k (471) | 16.66 M | 816.67 M | 1.52 M | 5.25 M | 586.67 k | 7.59 M | 823.44 M | 2.72 |
| lmk05318b-clock | 299.37 M | 839.41 k | 1.01 M | 336.38 k | 25.32 k (379) | 16.67 M | 816.86 M | 1.06 M | 4.92 M | 579.41 k | 7.50 M | 822.83 M | 2.75 |
| rf-switch-eval | 271.26 M | 708.96 k | 937.09 k | 249.42 k | 23.26 k (525) | 15.32 M | 746.19 M | 780.95 k | 2.92 M | 547.66 k | 7.36 M | 749.89 M | 2.76 |
| cyclops-breakout | 269.66 M | 750.17 k | 909.41 k | 348.61 k | 24.77 k (668) | 14.91 M | 725.07 M | 1.57 M | 4.38 M | 528.91 k | 7.30 M | 731.02 M | 2.71 |
| poe-pd-flyback-tps23757 | 267.39 M | 707.84 k | 928.36 k | 235.84 k | 19.19 k (428) | 15.48 M | 755.52 M | 212.53 k | 2.79 M | 535.83 k | 7.44 M | 758.53 M | 2.84 |
| rf-switch-8way | 258.76 M | 710.69 k | 883.24 k | 272.64 k | 20.14 k (377) | 14.70 M | 716.18 M | 604.11 k | 3.50 M | 509.85 k | 7.33 M | 720.28 M | 2.78 |
| adf5901 | 236.40 M | 628.70 k | 820.37 k | 214.37 k | 15.04 k (257) | 13.88 M | 675.71 M | 355.65 k | 2.40 M | 470.93 k | 7.32 M | 678.47 M | 2.87 |
| dual-flash | 226.74 M | 598.01 k | 788.67 k | 197.90 k | 13.34 k (220) | 13.45 M | 653.97 M | 203.58 k | 2.07 M | 452.81 k | 7.31 M | 656.24 M | 2.89 |
| rds3-rf-selector | 214.96 M | 562.87 k | 755.79 k | 176.21 k | 9.80 k (185) | 13.03 M | 632.51 M | 76.44 k | 1.35 M | 431.75 k | 7.28 M | 633.94 M | 2.95 |
| max860-inverter | 211.01 M | 550.68 k | 743.60 k | 170.04 k | 8.39 k (156) | 12.89 M | 625.46 M | 45.43 k | 1.15 M | 424.06 k | 7.24 M | 626.66 M | 2.97 |
| Cyclops-Flex | 203.61 M | 531.37 k | 719.31 k | 163.30 k | 7.54 k (135) | 12.55 M | 608.26 M | 23.76 k | 1.01 M | 409.36 k | 7.22 M | 609.29 M | 2.99 |
| blinky-breakout | 31.52 M | 94.00 k | 98.48 k | 43.31 k | 6.57 k (164) | 1.43 M | 71.41 M | 164.99 k | 855.26 k | 62.31 k | 1.95 M | 72.43 M | 2.30 |
| **six slowest** | 6.02 G | 27.47 M | 15.06 M | 21.82 M | 997.97 k (14.69 k) | 243.63 M | 12.09 G | 251.86 M | 782.09 M | 9.08 M | 51.61 M |  | 2.18 |
| **other 28** | 10.90 G | 30.81 M | 35.91 M | 13.62 M | 1.39 M (27.61 k) | 553.51 M | 27.28 G | 55.90 M | 275.14 M | 21.24 M | 12.21 M |  | 2.53 |
| **EDA total** | 16.93 G | 58.28 M | 50.98 M | 35.45 M | 2.39 M (42.30 k) | 797.13 M | 39.37 G | 307.75 M | 1.06 G | 30.32 M | 51.61 M |  | 2.41 |

## Parity programs (per unit as named)

| program | instructions | retains | releases | runtime count ops | unique tests (shared) | copies | record bytes | list/dict/buffer/text bytes | growth bytes | allocs | peak live | bytes copied per unit | bytes per instruction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nbody (per steps) | 8.37 G | 0 | 1 | 0 | 75.00 M (0) | 1.13 G | 63.00 G | 0 | 0 | 1 | 320 | 12.60 k | 7.53 |
| str_build (per appends) | 1.68 G | 0 | 2 | 0 | 0 (0) | 0 | 0 | 0 | 134.22 M | 27 | 201.33 M | 8 | 0.08 |
| matmul (per multiply-adds) | 1.31 G | 0 | 3 | 1.50 k | 0 (0) | 0 | 0 | 0 | 8.19 k | 1.51 k | 6.07 M | 0 | 0.00 |
| knucleotide (per sequence bytes) | 2.85 G | 67 | 6.72 M | 283.21 k | 0 (0) | 0 | 0 | 0 | 20.95 M | 7.00 M | 15.68 M | 21 | 0.01 |

## The 46 rows (per unit = per element or iteration of the row's timed size)

| program | instructions | retains | releases | runtime count ops | unique tests (shared) | copies | record bytes | list/dict/buffer/text bytes | growth bytes | allocs | peak live | bytes copied per unit | bytes per instruction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| record_reads | 173.20 M | 0 | 1 | 4.10 k | 0 (0) | 0 | 0 | 0 | 75.14 k | 4.11 k | 360.74 k | 0 | 0.00 |
| tagged_stack | 321.25 M | 0 | 2 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 6 | 33.13 k | 0 | 0.00 |
| mutate_unique | 224.30 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| mutate_shared | 634.62 k | 0 | 401 | 4 | 0 (0) | 400 | 0 | 13.11 M | 0 | 405 | 65.94 k | 8 | 20.65 |
| record_construct | 491.92 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| record_update | 541.20 M | 0 | 2 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 6 | 131.41 k | 0 | 0.00 |
| option_handle | 197.01 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| result_propagate | 373.95 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| list_scan | 360.81 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| list_append | 642.10 M | 0 | 4.00 k | 4 | 0 (0) | 0 | 0 | 0 | 0 | 4.00 k | 33.06 k | 0 | 0.00 |
| list_filter | 732.82 M | 0 | 8.00 k | 4 | 0 (0) | 0 | 0 | 0 | 3.84 M | 28.00 k | 49.49 k | 0 | 0.01 |
| alloc_short | 110.81 M | 0 | 0 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 4 | 256 | 0 | 0.00 |
| alloc_retained | 652.03 M | 0 | 1.00 k | 4.10 M | 0 (0) | 0 | 0 | 0 | 9.20 M | 4.10 M | 295.21 k | 2 | 0.01 |
| mutate_nested | 121.57 M | 0 | 801 | 3.28 M | 400 (400) | 800 | 0 | 13.12 M | 0 | 4.90 k | 340.94 k | 8 | 0.11 |
| bytes_scan | 3.58 M | 0 | 6 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 10 | 37.36 k | 0 | 0.00 |
| string_equal | 41.53 M | 1 | 16 | 12 | 24.57 k (6) | 9 | 0 | 11 | 65.20 k | 80 | 70.52 k | 0 | 0.00 |
| string_search | 86.16 M | 1 | 9 | 5 | 4.10 k (1) | 1 | 0 | 0 | 8.14 k | 21 | 12.75 k | 0 | 0.00 |
| string_split | 523.17 M | 4.10 k | 808 | 1.64 M | 0 (0) | 0 | 0 | 0 | 3.69 M | 1.64 M | 368.42 k | 2 | 0.01 |
| string_join | 124.25 M | 4.10 k | 2.01 k | 6 | 0 (0) | 0 | 0 | 0 | 0 | 1.01 k | 95.65 k | 0 | 0.00 |
| dict_lookup | 1.05 G | 0 | 4 | 4 | 0 (0) | 0 | 0 | 0 | 98.11 k | 17 | 131.64 k | 0 | 0.00 |
| dict_lookup_str | 1.41 G | 4.10 k | 5 | 12.29 k | 0 (0) | 0 | 0 | 0 | 98.11 k | 8.21 k | 721.47 k | 0 | 0.00 |
| dict_update | 2.93 G | 0 | 1.00 k | 4 | 0 (0) | 0 | 0 | 0 | 196.42 M | 11.01 k | 234.12 k | 48 | 0.07 |
| dict_update_str | 4.60 G | 8.19 M | 1.00 k | 8.20 M | 0 (0) | 0 | 0 | 0 | 196.42 M | 19.20 k | 823.95 k | 48 | 0.04 |
| set_dedup | 1.85 G | 0 | 4.00 k | 4 | 0 (0) | 0 | 0 | 0 | 65.02 M | 32.01 k | 45.78 k | 4 | 0.04 |
| int_parse | 365.60 M | 1 | 2.73 k | 2.74 k | 683 (0) | 1.37 k | 0 | 2.05 k | 23.39 k | 7.52 k | 208.07 k | 0 | 0.00 |
| int_format | 975.15 M | 1 | 4.00 M | 4 | 0 (0) | 0 | 0 | 0 | 960 | 4.00 M | 33.22 k | 0 | 0.00 |
| call_indirect | 13.77 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| sort_int | 212.41 M | 0 | 400 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 404 | 33.06 k | 0 | 0.00 |
| sort_records | 245.40 M | 0 | 1.20 k | 404 | 0 (0) | 0 | 0 | 0 | 537.60 k | 3.20 k | 262.62 k | 0 | 0.00 |
| int_math | 19.91 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| float_math | 78.37 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| call_direct | 13.77 M | 0 | 1 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 5 | 33.06 k | 0 | 0.00 |
| branch_predictable | 22.00 M | 0 | 2 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 6 | 37.20 k | 0 | 0.00 |
| branch_mixed | 22.07 M | 0 | 2 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 6 | 37.20 k | 0 | 0.00 |
| binary_search | 182.22 M | 0 | 2 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 6 | 65.87 k | 0 | 0.00 |
| word_count | 291.26 M | 1 | 409 | 6.10 k | 1 (0) | 6.10 k | 0 | 48.11 k | 60.93 k | 10.61 k | 317.39 k | 0 | 0.00 |
| csv_aggregate | 863.48 M | 1 | 848.04 k | 987.14 k | 4.61 M (823.30 k) | 827.39 k | 0 | 51.20 k | 1.07 M | 2.01 M | 1.89 M | 7 | 0.00 |
| json_transform | 1.02 G | 1.04 M | 2.30 M | 608.96 k | 449.21 k (4.10 k) | 4.10 k | 0 | 47.10 k | 8.79 M | 2.32 M | 3.25 M | 108 | 0.01 |
| packet_decode | 118.28 M | 0 | 4.10 k | 4.10 k | 0 (0) | 0 | 0 | 0 | 262.14 k | 12.29 k | 328.21 k | 0 | 0.00 |
| lox_eval | 158.57 M | 0 | 121 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 205 | 1.25 k | 0 | 0.00 |
| tree_build_walk | 318.88 M | 0 | 272 | 1.11 M | 0 (0) | 0 | 0 | 0 | 0 | 1.11 M | 262.40 k | 0 | 0.00 |
| record_pass | 267.66 M | 0 | 0 | 4 | 0 (0) | 3.78 M | 363.03 M | 0 | 0 | 4 | 256 | 96 | 1.36 |
| grid_dp | 369.67 M | 0 | 3.08 k | 197.38 k | 0 (0) | 0 | 0 | 0 | 0 | 200.46 k | 70.98 k | 0 | 0.00 |
| union_find | 349.62 M | 0 | 698 | 4 | 0 (0) | 0 | 0 | 0 | 0 | 702 | 33.06 k | 0 | 0.00 |
| float_format | 184.53 M | 0 | 163.84 k | 4 | 0 (0) | 0 | 0 | 0 | 0 | 163.84 k | 320 | 0 | 0.00 |
| buffer_write | 117.55 M | 0 | 230 | 4 | 471.04 k (0) | 0 | 0 | 0 | 3.77 M | 1.73 k | 49.49 k | 8 | 0.03 |
| **46 rows total** | 23.78 G | 9.24 M | 7.35 M | 20.15 M | 5.56 M (827.80 k) | 4.62 M | 363.03 M | 26.38 M | 489.44 M | 15.70 M | 3.25 M |  | 0.04 |

## Copy patterns: share of bytes moved, per corpus

| pattern | lox | eda | parity | rows | all (mean of corpora) |
|---|---:|---:|---:|---:|---:|
| P1 record moved into a phi slot at a join | 44.0% | 28.2% | 0.0% | 41.5% | 28.4% |
| P3 element copied out of a list | 0.4% | 4.3% | 66.5% | 0.0% | 17.8% |
| P14 dictionary, buffer or text growth | 0.0% | 0.1% | 0.2% | 53.5% | 13.5% |
| P2 whole-record copy before a field store | 20.6% | 16.8% | 0.0% | 0.0% | 9.4% |
| P4 record written back into a list element | 3.2% | 0.1% | 33.3% | 0.0% | 9.1% |
| P7 record returned through sret | 8.0% | 20.6% | 0.0% | 0.0% | 7.1% |
| P8 other record copy (record_get) | 11.4% | 15.7% | 0.0% | 0.0% | 6.8% |
| P9 copy-on-write of a whole list | 8.8% | 0.7% | 0.0% | 3.0% | 3.1% |
| P13 list growth (class move or realloc) | 0.1% | 2.5% | 0.0% | 2.0% | 1.1% |
| P6 record pushed into a list | 0.0% | 3.8% | 0.0% | 0.0% | 1.0% |
| P8 other record copy (release) | 0.1% | 3.5% | 0.0% | 0.0% | 0.9% |
| P8 other record copy (union_payload) | 0.0% | 3.5% | 0.0% | 0.0% | 0.9% |
| P5 old element copied out to release it | 2.2% | 0.1% | 0.0% | 0.0% | 0.6% |
| P8 other record copy (retain) | 1.1% | 0.0% | 0.0% | 0.0% | 0.3% |
| P8 other record copy (list_get_field) | 0.2% | 0.0% | 0.0% | 0.0% | 0.1% |
| bytes moved (all patterns) | 1.28 T | 40.73 G | 63.16 G | 875.16 M |  |

## Top 20 functions by bytes copied (all corpora; ranked by share of their corpus's bytes)

1. **parity `advance`**: 63.00 GB, 99.8% of parity (P3 67%; P4 33%)
   - `bench/parity/suite/nbody.my:113:13` record_copy/list_get → P3 element copied out of a list: 5.60 GB in 100.00 M copies
   - `bench/parity/suite/nbody.my:114:13` record_copy/list_get → P3 element copied out of a list: 5.60 GB in 100.00 M copies
   - `bench/parity/suite/nbody.my:115:13` record_copy/list_get → P3 element copied out of a list: 5.60 GB in 100.00 M copies
   - `bench/parity/suite/nbody.my:116:13` record_copy/list_get → P3 element copied out of a list: 5.60 GB in 100.00 M copies
2. **lox `vm::run`**: 669.31 GB, 52.4% of lox (P1 74%; P2 13%; P4 5%; P5 3%)
   - `vm.my:429:5` record_copy/jump → P1 record moved into a phi slot at a join: 492.91 GB in 4.51 G copies — `def run(rt: mut heap.Runtime, o: mut output.Output) -> InterpretResult:`
   - `vm.my:433:9` record_copy/record_set → P2 whole-record copy before a field store: 25.20 GB in 125.99 M copies — `rt.frames[rt.frame_count - 1] = frame`
   - `vm.my:534:9` record_copy/record_set → P2 whole-record copy before a field store: 25.20 GB in 125.99 M copies — `rt.frames[rt.frame_count - 1] = frame`
   - `vm.my:433:9` record_copy/list_set → P4 record written back into a list element: 17.13 GB in 251.98 M copies — `rt.frames[rt.frame_count - 1] = frame`
3. **rows `row_record_pass::batch_result`**: 363.03 MB, 41.5% of rows (P1 100%)
   - `row_record_pass.my:48:5` record_copy/jump → P1 record moved into a phi slot at a join: 363.03 MB in 3.78 M copies
4. **eda `sexpr_tokenizer::advance`**: 13.57 GB, 33.3% of eda (P2 40%; P1 40%; P7 20%)
   - `sexpr_tokenizer.my:90:5` record_copy/jump → P1 record moved into a phi slot at a join: 5.43 GB in 113.08 M copies — `def advance(src: bytes, t: mut Cursor):`
   - `sexpr_tokenizer.my:90:5` record_copy/ret → P7 record returned through sret: 2.71 GB in 56.54 M copies — `def advance(src: bytes, t: mut Cursor):`
   - `sexpr_tokenizer.my:97:9` record_copy/record_set → P2 whole-record copy before a field store: 2.71 GB in 56.54 M copies — `t.pos += 1`
   - `sexpr_tokenizer.my:96:13` record_copy/record_set → P2 whole-record copy before a field store: 2.65 GB in 55.24 M copies — `t.col += 1`
5. **rows `row_dict_update::batch_result`**: 196.42 MB, 22.4% of rows (P14 100%)
6. **rows `row_dict_update_str::batch_result`**: 196.42 MB, 22.4% of rows (P14 100%)
7. **eda `sexpr_parser::parse_list`**: 5.48 GB, 13.4% of eda (P8 42%; P8 17%; P8 17%; P1 12%)
   - `sexpr_parser.my:218:17` record_copy/record_get → P8 other record copy (record_get): 1.26 GB in 24.26 M copies — `token = next_token(mut tok, mut diag)?`
   - `sexpr_parser.my:224:17` record_copy/record_get → P8 other record copy (record_get): 1.04 GB in 18.53 M copies — `child = parse_node(mut tok, token, depth + 1, mut diag)?`
   - `sexpr_parser.my:213:5` record_copy/jump → P1 record moved into a phi slot at a join: 679.28 MB in 12.13 M copies — `def parse_list(tok: mut tokenizer_mod.Tokenizer, open_span: ast.Span, depth: int, diag: mut ParseDia`
   - `sexpr_parser.my:218:17` record_copy/union_payload → P8 other record copy (union_payload): 485.20 MB in 12.13 M copies — `token = next_token(mut tok, mut diag)?`
8. **eda `sexpr_tokenizer::next`**: 4.28 GB, 10.5% of eda (P8 41%; P2 30%; P7 30%)
   - `sexpr_tokenizer.my:269:5` record_copy/record_set → P2 whole-record copy before a field store: 1.26 GB in 24.29 M copies — `t.cur = cur`
   - `sexpr_tokenizer.my:270:5` record_copy/ret → P7 record returned through sret: 1.26 GB in 24.29 M copies — `return r`
   - `sexpr_tokenizer.my:268:9` record_copy/record_get → P8 other record copy (record_get): 1.17 GB in 24.29 M copies — `r = next_in(src, mut cur)`
   - `sexpr_tokenizer.my:267:11` record_copy/record_get → P8 other record copy (record_get): 583.07 MB in 12.15 M copies — `cur = t.cur`
9. **eda `sexpr_parser::next_token`**: 3.40 GB, 8.4% of eda (P8 37%; P7 34%; P8 14%; P8 14%)
   - `sexpr_parser.my:116:11` record_copy/record_get → P8 other record copy (record_get): 1.26 GB in 24.29 M copies — `match tokenizer_mod.next(mut tok):`
   - `sexpr_parser.my:118:13` record_copy/ret → P7 record returned through sret: 1.17 GB in 24.29 M copies — `return Ok(token)`
   - `sexpr_parser.my:116:5` record_copy/union_payload → P8 other record copy (union_payload): 485.90 MB in 12.15 M copies — `match tokenizer_mod.next(mut tok):`
   - `sexpr_parser.my:116:11` record_copy/release → P8 other record copy (release): 485.90 MB in 12.15 M copies — `match tokenizer_mod.next(mut tok):`
10. **rows `row_set_dedup::batch_result`**: 65.02 MB, 7.4% of rows (P14 100%)
11. **eda `kicad_sch_textbox::overlaps_of`**: 2.77 GB, 6.8% of eda (P3 34%; P6 33%; P13 30%; P1 3%)
   - `kicad_sch_textbox.my:137:18` record_copy/list_get → P3 element copied out of a list: 901.30 MB in 18.78 M copies — `for b in ordered[i + 1:len(ordered)]:`
   - `kicad_sch_textbox.my:137:18` record_copy/list_push → P6 record pushed into a list: 901.30 MB in 18.78 M copies — `for b in ordered[i + 1:len(ordered)]:`
   - `kicad_sch_textbox.my:137:18` list_push/list_push → P13 list growth (class move or realloc): 840.89 MB — `for b in ordered[i + 1:len(ordered)]:`
   - `kicad_sch_textbox.my:131:5` record_copy/jump → P1 record moved into a phi slot at a join: 92.07 MB in 1.28 M copies — `def overlaps_of(items: list[Item]) -> Report:`
12. **lox `interpreter::instantiate`**: 81.44 GB, 6.4% of lox (P9 97%; P2 1%; P8 1%; P1 0%)
   - `interpreter.my:472:5` list_copy/list_copy → P9 copy-on-write of a whole list: 79.21 GB in 302.18 k copies — `it.rt.stack[callee_slot] = value.Value.obj(instance)`
   - `interpreter.my:471:5` record_copy/record_set → P2 whole-record copy before a field store: 149.88 MB in 604.36 k copies — `it.rt = __wb_413`
   - `interpreter.my:472:5` record_copy/record_set → P2 whole-record copy before a field store: 149.88 MB in 604.36 k copies — `it.rt.stack[callee_slot] = value.Value.obj(instance)`
   - `interpreter.my:496:5` record_copy/record_set → P2 whole-record copy before a field store: 149.88 MB in 604.36 k copies — `it.rt = __wb_428`
13. **eda `sexpr_tokenizer::skip_whitespace_and_comments`**: 2.38 GB, 5.8% of eda (P1 75%; P7 25%)
   - `sexpr_tokenizer.my:104:5` record_copy/jump → P1 record moved into a phi slot at a join: 1.79 GB in 37.37 M copies — `def skip_whitespace_and_comments(src: bytes, t: mut Cursor):`
   - `sexpr_tokenizer.my:104:5` record_copy/ret → P7 record returned through sret: 583.07 MB in 12.15 M copies — `def skip_whitespace_and_comments(src: bytes, t: mut Cursor):`
14. **lox `interpreter::evaluate`**: 64.09 GB, 5.0% of lox (P7 37%; P8 34%; P2 26%; P8 3%)
   - `interpreter.my:360:13` record_copy/record_set → P2 whole-record copy before a field store: 9.77 GB in 39.38 M copies — `it.rt = __wb_318`
   - `interpreter.my:376:20` record_copy/record_get → P8 other record copy (record_get): 5.83 GB in 19.71 M copies — `return get_variable(mut it, node.name_ref, node.hops, node.slot, node.name.line)`
   - `interpreter.my:376:13` record_copy/ret → P7 record returned through sret: 5.83 GB in 19.71 M copies — `return get_variable(mut it, node.name_ref, node.hops, node.slot, node.name.line)`
   - `interpreter.my:361:13` record_copy/ret → P7 record returned through sret: 5.83 GB in 19.69 M copies — `return Ok(None)`
15. **lox `interpreter::execute`**: 55.32 GB, 4.3% of lox (P2 37%; P8 31%; P7 16%; P1 16%)
   - `interpreter.my:624:13` record_copy/record_set → P2 whole-record copy before a field store: 10.00 GB in 40.33 M copies — `it.rt = __wb_521`
   - `interpreter.my:614:5` record_copy/jump → P1 record moved into a phi slot at a join: 8.70 GB in 29.38 M copies — `def execute(it: mut Interpreter, id: int) -> Result[Flow, RuntimeError]:`
   - `interpreter.my:692:5` record_copy/ret → P7 record returned through sret: 6.39 GB in 21.57 M copies — `return Ok(Flow.NORMAL)`
   - `interpreter.my:621:13` record_copy/record_get → P8 other record copy (record_get): 5.97 GB in 20.16 M copies — `evaluate(mut it, expr)?`
16. **lox `heap::allocate`**: 53.69 GB, 4.2% of lox (P2 40%; P9 22%; P1 20%; P7 10%)
   - `heap.my:117:12` list_copy/list_copy → P9 copy-on-write of a whole list: 12.00 GB in 28.84 k copies — `public def allocate(rt: mut Runtime, obj: object.Obj) -> value.ObjRef:`
   - `heap.my:117:12` record_copy/jump → P1 record moved into a phi slot at a join: 5.42 GB in 27.09 M copies — `public def allocate(rt: mut Runtime, obj: object.Obj) -> value.ObjRef:`
   - `heap.my:118:5` record_copy/record_set → P2 whole-record copy before a field store: 5.42 GB in 27.09 M copies — `rt.bytes_allocated = rt.bytes_allocated + object.cost(obj)`
   - `heap.my:128:5` record_copy/record_set → P2 whole-record copy before a field store: 5.42 GB in 27.09 M copies — `rt.allocations = rt.allocations + 1`
17. **eda `sexpr_tokenizer::next_in`**: 1.65 GB, 4.0% of eda (P7 65%; P8 35%)
   - `sexpr_tokenizer.my:290:19` record_copy/record_get → P8 other record copy (record_get): 301.30 MB in 6.85 M copies — `return Ok(read_atom(src, mut t, s))`
   - `sexpr_tokenizer.my:290:9` record_copy/ret → P7 record returned through sret: 301.30 MB in 6.85 M copies — `return Ok(read_atom(src, mut t, s))`
   - `sexpr_tokenizer.my:281:9` record_copy/ret → P7 record returned through sret: 251.91 MB in 5.73 M copies — `return Ok(make_token(src, TokenTag.lparen, s.offset, t.pos, s))`
   - `sexpr_tokenizer.my:284:9` record_copy/ret → P7 record returned through sret: 251.91 MB in 5.73 M copies — `return Ok(make_token(src, TokenTag.rparen, s.offset, t.pos, s))`
18. **lox `interpreter::binary`**: 50.05 GB, 3.9% of lox (P2 37%; P8 33%; P1 21%; P7 8%)
   - `interpreter.my:170:5` record_copy/jump → P1 record moved into a phi slot at a join: 10.75 GB in 36.32 M copies — `def binary(it: mut Interpreter, node: ast.BinaryExpr) -> Result[None, RuntimeError]:`
   - `interpreter.my:199:5` record_copy/record_set → P2 whole-record copy before a field store: 6.59 GB in 26.56 M copies — `it.rt = __wb_187`
   - `interpreter.my:202:5` record_copy/record_set → P2 whole-record copy before a field store: 6.59 GB in 26.56 M copies — `it.rt = __wb_188`
   - `interpreter.my:171:5` record_copy/record_get → P8 other record copy (record_get): 3.93 GB in 13.28 M copies — `evaluate(mut it, node.left)?`
19. **lox `heap::sweep`**: 39.91 GB, 3.1% of lox (P1 41%; P2 41%; P3 8%; P9 4%)
   - `heap.my:356:5` record_copy/jump → P1 record moved into a phi slot at a join: 16.19 GB in 80.93 M copies — `def sweep(rt: mut Runtime):`
   - `heap.my:362:13` record_copy/record_set → P2 whole-record copy before a field store: 5.39 GB in 26.93 M copies — `rt.bytes_allocated = rt.bytes_allocated - object.cost(rt.objects[i])`
   - `heap.my:363:13` record_copy/record_set → P2 whole-record copy before a field store: 5.39 GB in 26.93 M copies — `rt.objects[i] = object.Obj.free`
   - `heap.my:364:13` record_copy/record_set → P2 whole-record copy before a field store: 5.39 GB in 26.93 M copies — `rt.free_slots.append(i)`
20. **eda `sexpr_tokenizer::read_atom`**: 1.27 GB, 3.1% of eda (P1 76%; P7 24%)
   - `sexpr_tokenizer.my:248:5` record_copy/jump → P1 record moved into a phi slot at a join: 966.28 MB in 20.13 M copies — `def read_atom(src: bytes, t: mut Cursor, s: ast.Span) -> Token:`
   - `sexpr_tokenizer.my:252:5` record_copy/ret → P7 record returned through sret: 301.30 MB in 6.85 M copies — `return make_token(src, TokenTag.atom, start, t.pos, s)`

## Static ownership estimate

| corpus | programs | geomean net saving (every retain becomes a copy) | geomean saving if copies were free (upper bound) | programs ≥ 10% net | programs ≥ 10% upper bound |
|---|---:|---:|---:|---|---|
| lox | 24 | -389.01% | 16.39% | 0:  | 18: lox-vm-closures-100000, lox-vm-equality-200000, lox-vm-fib-27, lox-vm-invocation-100000, lox-vm-method_call-20000, lox-vm-properties-50000, lox-vm-string_equality-2000, lox-vm-strings-200000 |
| eda | 34 | -14.77% | 4.73% | 0:  | 0:  |
| parity | 4 | 1.11% | 1.11% | 0:  | 0:  |
| rows | 46 | 0.47% | 0.83% | 1: row-mutate_nested | 1: row-mutate_nested |
