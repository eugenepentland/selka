### vm engine: median wall seconds over 3 rounds (x Zig ReleaseFast)

| script | mylang new core | Zig ReleaseFast | Zig ReleaseSafe | Rust | Go | mylang x Rust | mylang x Go |
|---|---|---|---|---|---|---|---|
| closures | 17.95 (23.48x) | 0.76 (1.00x) | 1.13 (1.47x) | 0.96 (1.26x) | 0.97 (1.27x) | 18.66x | 18.54x |
| equality | 22.85 (24.70x) | 0.93 (1.00x) | 0.99 (1.07x) | 1.06 (1.15x) | 1.11 (1.20x) | 21.47x | 20.66x |
| fib | 19.46 (31.15x) | 0.62 (1.00x) | 0.79 (1.26x) | 0.84 (1.34x) | 0.72 (1.16x) | 23.25x | 26.93x |
| invocation | 25.51 (33.06x) | 0.77 (1.00x) | 1.32 (1.71x) | 1.44 (1.86x) | 1.24 (1.60x) | 17.76x | 20.62x |
| method_call | 23.19 (25.90x) | 0.90 (1.00x) | 1.19 (1.33x) | 1.26 (1.41x) | 1.16 (1.30x) | 18.33x | 19.91x |
| properties | 19.91 (25.16x) | 0.79 (1.00x) | 1.21 (1.53x) | 1.38 (1.74x) | 1.16 (1.47x) | 14.43x | 17.15x |
| string_equality | 25.84 (53.25x) | 0.49 (1.00x) | 0.61 (1.26x) | 0.80 (1.65x) | 1.00 (2.05x) | 32.20x | 25.93x |
| strings | 10.50 (20.27x) | 0.52 (1.00x) | 0.98 (1.90x) | 0.55 (1.06x) | 0.64 (1.24x) | 19.15x | 16.36x |
| zoo | 24.44 (27.67x) | 0.88 (1.00x) | 1.32 (1.49x) | 1.49 (1.69x) | 1.25 (1.42x) | 16.42x | 19.48x |
| zoo_batch | 21.43 (28.91x) | 0.74 (1.00x) | 1.09 (1.47x) | 1.22 (1.64x) | 1.03 (1.40x) | 17.58x | 20.71x |
| **geomean** | **28.35x** | **1.00x** | **1.43x** | **1.46x** | **1.39x** | **19.46x** | **20.39x** |

Median (max-min)/median across rounds, all vm cells: 4.2% (max 31.0%)

### tree engine: median wall seconds over 3 rounds (x Zig ReleaseFast)

| script | mylang new core | Zig ReleaseFast | Zig ReleaseSafe | Rust | Go | mylang x Rust | mylang x Go |
|---|---|---|---|---|---|---|---|
| closures | 0.84 (5.08x) | 0.17 (1.00x) | 0.28 (1.68x) | 0.24 (1.46x) | 0.22 (1.30x) | 3.48x | 3.90x |
| equality | 0.97 (5.02x) | 0.19 (1.00x) | 0.22 (1.16x) | 0.20 (1.03x) | 0.16 (0.85x) | 4.87x | 5.89x |
| fib | 0.44 (4.50x) | 0.10 (1.00x) | 0.16 (1.65x) | 0.14 (1.41x) | 0.11 (1.16x) | 3.19x | 3.89x |
| instantiation | 7.15 (58.49x) | 0.12 (1.00x) | 0.23 (1.85x) | 0.13 (1.10x) | 0.18 (1.49x) | 53.22x | 39.19x |
| invocation | 1.52 (3.65x) | 0.42 (1.00x) | 0.74 (1.79x) | 0.44 (1.07x) | 0.58 (1.40x) | 3.42x | 2.61x |
| properties | 1.25 (3.79x) | 0.33 (1.00x) | 0.56 (1.69x) | 0.38 (1.16x) | 0.44 (1.34x) | 3.28x | 2.82x |
| string_equality | 1.28 (8.99x) | 0.14 (1.00x) | 0.18 (1.28x) | 0.37 (2.57x) | 0.16 (1.15x) | 3.50x | 7.79x |
| strings | 0.38 (4.39x) | 0.09 (1.00x) | 0.15 (1.73x) | 0.12 (1.38x) | 0.11 (1.27x) | 3.18x | 3.45x |
| zoo | 1.50 (4.26x) | 0.35 (1.00x) | 0.59 (1.68x) | 0.45 (1.27x) | 0.51 (1.45x) | 3.35x | 2.93x |
| zoo_batch | 1.31 (4.43x) | 0.30 (1.00x) | 0.50 (1.68x) | 0.38 (1.27x) | 0.43 (1.46x) | 3.49x | 3.04x |
| **geomean** | **6.08x** | **1.00x** | **1.60x** | **1.32x** | **1.27x** | **4.59x** | **4.78x** |

Median (max-min)/median across rounds, all tree cells: 3.1% (max 27.5%)

### Peak RSS, MiB (max over rounds)

| script/engine | mylang new core | Zig ReleaseFast | Zig ReleaseSafe | Rust | Go | mylang x Zig | mylang x Rust |
|---|---|---|---|---|---|---|---|
| closures/tree | 6.7 | 2.4 | 2.8 | 4.4 | 9.1 | 2.8x | 1.5x |
| closures/vm | 5.5 | 2.2 | 2.9 | 4.5 | 10.4 | 2.4x | 1.2x |
| equality/tree | 5.8 | 2.4 | 3.5 | 4.4 | 8.0 | 2.4x | 1.3x |
| equality/vm | 2.7 | 0.7 | 1.2 | 2.4 | 2.3 | 3.9x | 1.1x |
| fib/tree | 6.0 | 2.1 | 2.9 | 4.3 | 9.2 | 2.9x | 1.4x |
| fib/vm | 2.5 | 0.7 | 1.2 | 2.4 | 2.3 | 3.6x | 1.0x |
| instantiation/tree | 5.6 | 2.1 | 2.7 | 4.2 | 9.2 | 2.7x | 1.3x |
| invocation/tree | 5.0 | 2.1 | 2.7 | 3.9 | 8.7 | 2.4x | 1.3x |
| invocation/vm | 2.7 | 0.7 | 1.2 | 2.5 | 2.6 | 3.9x | 1.0x |
| method_call/vm | 2.7 | 0.7 | 1.2 | 2.6 | 2.5 | 3.9x | 1.0x |
| properties/tree | 4.9 | 2.1 | 2.7 | 4.1 | 9.8 | 2.3x | 1.2x |
| properties/vm | 2.7 | 0.7 | 1.2 | 2.5 | 2.6 | 3.9x | 1.1x |
| string_equality/tree | 5.4 | 2.2 | 2.7 | 4.4 | 6.2 | 2.4x | 1.2x |
| string_equality/vm | 3.0 | 0.7 | 1.2 | 2.5 | 2.8 | 4.3x | 1.2x |
| strings/tree | 5.6 | 2.2 | 3.7 | 4.4 | 9.0 | 2.5x | 1.3x |
| strings/vm | 2.7 | 0.7 | 1.2 | 2.3 | 7.1 | 3.9x | 1.1x |
| zoo/tree | 5.0 | 2.1 | 2.7 | 4.2 | 8.6 | 2.4x | 1.2x |
| zoo/vm | 2.7 | 0.7 | 1.2 | 2.5 | 2.5 | 3.9x | 1.1x |
| zoo_batch/tree | 5.1 | 2.1 | 2.7 | 4.2 | 8.7 | 2.4x | 1.2x |
| zoo_batch/vm | 2.7 | 0.7 | 1.2 | 2.5 | 2.5 | 3.9x | 1.1x |
| **geomean ratio** |  | | | | | **3.1x** | **1.2x** |

quiet waits: 0, total 0 s; load per round: 4.61, 3.26, 1.02, 0.92
