# EDA runtime, final against base (main ab85c16c2, CPU 10, median of 10 rounds)

All outputs verified: True. Sorted by final/base.

| design | final ms | base ms | Zig ms | final/base | final/Zig | base/Zig |
|---|---:|---:|---:|---:|---:|---:|
| cyclops-analog | 35.4 | 37.1 | 27.0 | 0.954 | 1.31 | 1.38 |
| cyclops-analog+no-vendor-symbols | 24.2 | 25.0 | 18.6 | 0.967 | 1.30 | 1.34 |
| barracuda | 41.3 | 42.5 | 32.9 | 0.973 | 1.26 | 1.29 |
| cyclops-kband | 33.7 | 34.6 | 25.8 | 0.975 | 1.31 | 1.34 |
| barracuda-via-fence | 35.6 | 36.4 | 27.9 | 0.976 | 1.28 | 1.31 |
| cyclops-interposer | 26.7 | 27.2 | 21.9 | 0.984 | 1.22 | 1.24 |
| straps | 33.3 | 33.8 | 25.2 | 0.985 | 1.32 | 1.34 |
| straps-base | 53.1 | 53.9 | 36.5 | 0.986 | 1.46 | 1.48 |
| rds3 | 71.1 | 72.1 | 57.2 | 0.986 | 1.24 | 1.26 |
| labstation | 58.5 | 59.3 | 46.6 | 0.986 | 1.25 | 1.27 |
| stm32n6 | 46.8 | 47.3 | 34.5 | 0.989 | 1.36 | 1.37 |
| black-canyon+flat | 28.5 | 28.8 | 22.6 | 0.990 | 1.26 | 1.28 |
| remora-rf | 32.7 | 33.0 | 25.4 | 0.991 | 1.29 | 1.30 |
| cyclops-kband-pcb | 32.6 | 32.9 | 23.9 | 0.991 | 1.36 | 1.37 |
| cyclops-digital-pcb | 46.4 | 46.8 | 30.0 | 0.992 | 1.55 | 1.56 |
| rds3+flat | 89.5 | 90.2 | 63.5 | 0.992 | 1.41 | 1.42 |
| lmk05318b-clock | 20.7 | 20.8 | 15.3 | 0.992 | 1.35 | 1.36 |
| remora-base | 33.7 | 33.9 | 25.5 | 0.993 | 1.32 | 1.33 |
| adf5901 | 16.3 | 16.4 | 12.6 | 0.993 | 1.29 | 1.30 |
| black-canyon | 26.5 | 26.6 | 22.3 | 0.996 | 1.19 | 1.19 |
| poe-pd-flyback-tps23757 | 19.1 | 19.1 | 14.9 | 0.997 | 1.28 | 1.28 |
| cyclops-kband-breakout | 27.2 | 27.3 | 23.2 | 0.997 | 1.17 | 1.18 |
| labstation+no-vendor-symbols | 46.5 | 46.6 | 36.6 | 0.998 | 1.27 | 1.27 |
| cyclops-xband-sip | 24.9 | 24.8 | 19.1 | 1.001 | 1.30 | 1.30 |
| cyclops-breakout | 19.0 | 19.0 | 14.1 | 1.001 | 1.35 | 1.35 |
| rf-switch-8way | 18.5 | 18.4 | 13.9 | 1.005 | 1.33 | 1.32 |
| barracuda-base | 45.1 | 44.9 | 35.4 | 1.006 | 1.27 | 1.27 |
| Cyclops-Flex | 15.0 | 14.9 | 11.7 | 1.008 | 1.29 | 1.28 |
| dual-flash | 16.5 | 16.3 | 12.7 | 1.008 | 1.29 | 1.28 |
| rf-switch-eval | 19.8 | 19.6 | 14.6 | 1.010 | 1.36 | 1.35 |
| rds3-rf-selector | 15.7 | 15.5 | 12.2 | 1.013 | 1.29 | 1.27 |
| blinky-breakout | 3.2 | 3.2 | 1.9 | 1.021 | 1.69 | 1.66 |
| max860-inverter | 15.9 | 15.4 | 11.5 | 1.030 | 1.38 | 1.34 |
| w55rp20 | 21.3 | 20.7 | 16.2 | 1.032 | 1.31 | 1.27 |

| binary | geomean vs zig-fast | zig-safe | rust | go | peak RSS MiB |
|---|---:|---:|---:|---:|---:|
| mylang-base | 1.325 | 1.213 | 1.180 | 0.484 | 52.6 |
| mylang-final | 1.318 | 1.206 | 1.173 | 0.481 | 52.7 |
