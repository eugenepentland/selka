# EDA runtime, final against base (CE-X, CPU 10, median of 10 rounds)

All outputs verified: True. Sorted by final/base.

| design | final ms | base ms | Zig ms | final/base | final/Zig | base/Zig |
|---|---:|---:|---:|---:|---:|---:|
| rds3+flat | 95.3 | 192.2 | 64.9 | 0.496 | 1.47 | 2.96 |
| cyclops-digital-pcb | 49.3 | 81.3 | 32.8 | 0.606 | 1.50 | 2.48 |
| cyclops-kband-pcb | 36.7 | 54.3 | 24.8 | 0.675 | 1.48 | 2.19 |
| straps-base | 57.7 | 84.9 | 39.0 | 0.680 | 1.48 | 2.18 |
| stm32n6 | 50.5 | 66.7 | 38.4 | 0.757 | 1.31 | 1.74 |
| barracuda | 45.4 | 59.7 | 35.9 | 0.760 | 1.26 | 1.66 |
| straps | 35.4 | 45.9 | 26.2 | 0.771 | 1.35 | 1.75 |
| barracuda-base | 50.5 | 65.0 | 38.6 | 0.777 | 1.31 | 1.68 |
| labstation+no-vendor-symbols | 51.1 | 65.5 | 41.0 | 0.780 | 1.25 | 1.60 |
| remora-rf | 36.1 | 46.3 | 27.1 | 0.780 | 1.33 | 1.71 |
| cyclops-interposer | 26.2 | 33.4 | 22.3 | 0.784 | 1.17 | 1.50 |
| w55rp20 | 23.1 | 29.3 | 17.6 | 0.787 | 1.31 | 1.66 |
| adf5901 | 18.5 | 23.4 | 14.1 | 0.788 | 1.31 | 1.66 |
| cyclops-analog | 39.1 | 49.4 | 28.0 | 0.790 | 1.39 | 1.76 |
| cyclops-kband | 36.4 | 45.8 | 27.2 | 0.795 | 1.34 | 1.68 |
| labstation | 63.4 | 79.5 | 50.2 | 0.797 | 1.26 | 1.58 |
| lmk05318b-clock | 22.5 | 28.2 | 16.4 | 0.797 | 1.37 | 1.71 |
| remora-base | 38.0 | 46.8 | 28.9 | 0.812 | 1.32 | 1.62 |
| cyclops-analog+no-vendor-symbols | 25.4 | 31.3 | 20.4 | 0.813 | 1.25 | 1.54 |
| cyclops-breakout | 19.4 | 23.9 | 14.9 | 0.813 | 1.30 | 1.60 |
| black-canyon | 30.4 | 37.3 | 24.3 | 0.815 | 1.25 | 1.53 |
| dual-flash | 18.0 | 22.0 | 14.0 | 0.819 | 1.29 | 1.57 |
| rds3 | 76.4 | 93.2 | 60.6 | 0.820 | 1.26 | 1.54 |
| max860-inverter | 17.6 | 21.4 | 13.0 | 0.823 | 1.36 | 1.65 |
| cyclops-xband-sip | 27.1 | 32.6 | 20.0 | 0.829 | 1.35 | 1.63 |
| rf-switch-8way | 19.3 | 23.2 | 14.3 | 0.834 | 1.35 | 1.62 |
| Cyclops-Flex | 15.9 | 19.1 | 11.7 | 0.834 | 1.37 | 1.64 |
| blinky-breakout | 3.5 | 4.2 | 2.2 | 0.835 | 1.60 | 1.91 |
| cyclops-kband-breakout | 31.5 | 37.7 | 25.2 | 0.836 | 1.25 | 1.50 |
| rf-switch-eval | 19.5 | 23.4 | 14.8 | 0.836 | 1.32 | 1.58 |
| black-canyon+flat | 31.4 | 37.0 | 24.1 | 0.847 | 1.30 | 1.54 |
| barracuda-via-fence | 42.8 | 50.4 | 32.1 | 0.849 | 1.33 | 1.57 |
| rds3-rf-selector | 17.2 | 19.6 | 12.8 | 0.876 | 1.35 | 1.54 |
| poe-pd-flyback-tps23757 | 21.6 | 24.3 | 16.6 | 0.889 | 1.30 | 1.46 |

| binary | geomean vs zig-fast | zig-safe | rust | go | peak RSS MiB |
|---|---:|---:|---:|---:|---:|
| mylang-base | 1.701 | 1.583 | 1.552 | 0.629 | 52.9 |
| mylang-final | 1.334 | 1.241 | 1.217 | 0.493 | 52.5 |
