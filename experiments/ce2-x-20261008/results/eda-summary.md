# EDA runtime, final against base (CE-X, CPU 10, median of 10 rounds)

All outputs verified: True. Sorted by final/base.

| design | final ms | base ms | Zig ms | final/base | final/Zig | base/Zig |
|---|---:|---:|---:|---:|---:|---:|
| rf-switch-eval | 16.9 | 18.2 | 12.8 | 0.932 | 1.32 | 1.42 |
| lmk05318b-clock | 18.1 | 19.4 | 14.3 | 0.932 | 1.26 | 1.36 |
| w55rp20 | 18.4 | 19.6 | 15.4 | 0.936 | 1.19 | 1.27 |
| cyclops-kband-breakout | 24.9 | 26.5 | 21.9 | 0.938 | 1.14 | 1.21 |
| rf-switch-8way | 16.1 | 17.2 | 12.3 | 0.940 | 1.31 | 1.39 |
| Cyclops-Flex | 13.1 | 13.9 | 10.1 | 0.942 | 1.29 | 1.37 |
| dual-flash | 14.4 | 15.3 | 11.1 | 0.943 | 1.29 | 1.37 |
| black-canyon | 24.1 | 25.5 | 21.3 | 0.943 | 1.13 | 1.20 |
| max860-inverter | 13.6 | 14.4 | 10.3 | 0.943 | 1.31 | 1.39 |
| cyclops-xband-sip | 21.5 | 22.7 | 17.4 | 0.945 | 1.24 | 1.31 |
| cyclops-interposer | 23.3 | 24.6 | 20.4 | 0.946 | 1.14 | 1.21 |
| poe-pd-flyback-tps23757 | 17.0 | 17.9 | 14.0 | 0.946 | 1.21 | 1.28 |
| cyclops-breakout | 16.4 | 17.3 | 12.6 | 0.947 | 1.30 | 1.38 |
| straps | 29.6 | 31.3 | 23.5 | 0.947 | 1.26 | 1.33 |
| rds3-rf-selector | 13.8 | 14.6 | 10.8 | 0.948 | 1.28 | 1.35 |
| cyclops-analog+no-vendor-symbols | 21.6 | 22.8 | 17.4 | 0.948 | 1.24 | 1.31 |
| cyclops-kband | 30.1 | 31.7 | 23.8 | 0.949 | 1.26 | 1.33 |
| remora-rf | 28.9 | 30.4 | 23.6 | 0.950 | 1.23 | 1.29 |
| adf5901 | 15.0 | 15.8 | 11.8 | 0.953 | 1.27 | 1.33 |
| barracuda-base | 40.7 | 42.6 | 34.6 | 0.955 | 1.18 | 1.23 |
| barracuda-via-fence | 33.1 | 34.7 | 26.9 | 0.956 | 1.23 | 1.29 |
| cyclops-kband-pcb | 29.1 | 30.4 | 22.7 | 0.957 | 1.28 | 1.34 |
| stm32n6 | 40.7 | 42.4 | 32.9 | 0.959 | 1.24 | 1.29 |
| remora-base | 29.8 | 31.0 | 24.1 | 0.960 | 1.23 | 1.29 |
| labstation+no-vendor-symbols | 40.9 | 42.6 | 34.9 | 0.960 | 1.17 | 1.22 |
| cyclops-analog | 32.4 | 33.7 | 25.5 | 0.961 | 1.27 | 1.32 |
| black-canyon+flat | 25.3 | 26.3 | 20.7 | 0.964 | 1.23 | 1.27 |
| barracuda | 38.2 | 39.4 | 31.7 | 0.969 | 1.21 | 1.24 |
| blinky-breakout | 2.9 | 3.0 | 1.9 | 0.969 | 1.57 | 1.62 |
| labstation | 52.1 | 53.6 | 44.2 | 0.972 | 1.18 | 1.21 |
| straps-base | 47.4 | 48.7 | 34.2 | 0.974 | 1.39 | 1.42 |
| rds3 | 63.8 | 65.5 | 54.4 | 0.974 | 1.17 | 1.20 |
| rds3+flat | 81.5 | 83.0 | 59.9 | 0.982 | 1.36 | 1.39 |
| cyclops-digital-pcb | 42.2 | 42.7 | 28.8 | 0.988 | 1.46 | 1.48 |

| binary | geomean vs zig-fast | zig-safe | rust | go | peak RSS MiB |
|---|---:|---:|---:|---:|---:|
| mylang-base | 1.318 | 1.205 | 1.200 | 0.494 | 52.5 |
| mylang-final | 1.257 | 1.149 | 1.144 | 0.471 | 52.5 |
