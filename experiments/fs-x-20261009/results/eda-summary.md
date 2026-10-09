# EDA runtime, final against base (main cafe7fea7, CPU 10, median of 10 rounds)

All outputs verified: True. Sorted by final/base.

| design | final ms | base ms | Zig ms | final/base | final/Zig | base/Zig |
|---|---:|---:|---:|---:|---:|---:|
| blinky-breakout | 3.0 | 3.0 | 1.9 | 0.974 | 1.60 | 1.64 |
| lmk05318b-clock | 18.6 | 19.0 | 14.3 | 0.979 | 1.30 | 1.33 |
| adf5901 | 15.3 | 15.6 | 11.9 | 0.979 | 1.29 | 1.32 |
| rf-switch-8way | 16.3 | 16.7 | 12.3 | 0.980 | 1.33 | 1.36 |
| barracuda-base | 41.2 | 42.0 | 33.9 | 0.982 | 1.21 | 1.24 |
| cyclops-interposer | 23.7 | 24.1 | 20.2 | 0.982 | 1.17 | 1.19 |
| black-canyon+flat | 25.4 | 25.8 | 20.8 | 0.982 | 1.22 | 1.24 |
| max860-inverter | 13.8 | 14.0 | 10.4 | 0.984 | 1.33 | 1.35 |
| w55rp20 | 18.8 | 19.1 | 15.2 | 0.984 | 1.24 | 1.26 |
| labstation | 52.3 | 53.1 | 42.7 | 0.984 | 1.23 | 1.25 |
| stm32n6 | 41.5 | 42.1 | 32.0 | 0.985 | 1.30 | 1.32 |
| black-canyon | 24.5 | 24.9 | 20.9 | 0.985 | 1.17 | 1.19 |
| cyclops-analog+no-vendor-symbols | 22.0 | 22.3 | 17.2 | 0.985 | 1.27 | 1.29 |
| remora-rf | 29.1 | 29.6 | 22.9 | 0.985 | 1.27 | 1.29 |
| dual-flash | 14.8 | 15.1 | 11.4 | 0.985 | 1.31 | 1.33 |
| straps-base | 47.2 | 47.9 | 33.3 | 0.985 | 1.42 | 1.44 |
| Cyclops-Flex | 13.4 | 13.5 | 10.5 | 0.987 | 1.28 | 1.29 |
| rds3 | 63.7 | 64.5 | 52.2 | 0.987 | 1.22 | 1.24 |
| straps | 30.0 | 30.4 | 23.2 | 0.988 | 1.29 | 1.31 |
| barracuda | 38.5 | 39.0 | 30.9 | 0.988 | 1.25 | 1.26 |
| cyclops-kband-pcb | 29.9 | 30.3 | 22.2 | 0.988 | 1.35 | 1.36 |
| cyclops-kband-breakout | 25.6 | 25.9 | 21.7 | 0.988 | 1.18 | 1.19 |
| cyclops-analog | 32.6 | 33.0 | 24.9 | 0.988 | 1.31 | 1.32 |
| remora-base | 30.0 | 30.3 | 23.3 | 0.988 | 1.29 | 1.30 |
| barracuda-via-fence | 33.5 | 33.9 | 26.3 | 0.989 | 1.27 | 1.29 |
| cyclops-kband | 30.6 | 31.0 | 23.5 | 0.989 | 1.31 | 1.32 |
| labstation+no-vendor-symbols | 41.4 | 41.8 | 33.9 | 0.990 | 1.22 | 1.23 |
| cyclops-xband-sip | 22.1 | 22.3 | 17.4 | 0.991 | 1.27 | 1.28 |
| rds3+flat | 81.3 | 82.0 | 58.7 | 0.992 | 1.38 | 1.40 |
| rf-switch-eval | 17.5 | 17.6 | 13.0 | 0.993 | 1.35 | 1.36 |
| rds3-rf-selector | 14.2 | 14.3 | 11.1 | 0.994 | 1.28 | 1.29 |
| cyclops-breakout | 16.8 | 16.9 | 12.8 | 0.994 | 1.31 | 1.32 |
| poe-pd-flyback-tps23757 | 17.5 | 17.5 | 13.9 | 0.995 | 1.26 | 1.26 |
| cyclops-digital-pcb | 42.3 | 42.5 | 28.5 | 0.996 | 1.49 | 1.49 |

| binary | geomean vs zig-fast | zig-safe | rust | go | peak RSS MiB |
|---|---:|---:|---:|---:|---:|
| mylang-base | 1.308 | 1.181 | 1.161 | 0.480 | 52.6 |
| mylang-final | 1.290 | 1.166 | 1.145 | 0.474 | 52.5 |
