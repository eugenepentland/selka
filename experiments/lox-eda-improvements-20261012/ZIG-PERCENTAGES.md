# Runtime percentages versus Zig ReleaseFast

100% means the same runtime as Zig; 160% means 60% slower. These are completed nine-sample medians. Cutoffs have no exact percentage. All 60 cases remain listed; see COMPARISON.md for methodology, RSS and managed counters.

| Group | Runtime as % of Zig | Slower than Zig | Completed pairs |
| --- | ---: | ---: | ---: |
| lox/tree | 163.4% | +63.4% | 12/13 |
| lox/vm | 236.0% | +136.0% | 11/13 |
| eda | 180.0% | +80.0% | 27/34 |

Group percentages are geometric means over completed pairs only.

| Case | Runtime as % of Zig | Difference from Zig |
| --- | ---: | ---: |
| eda/Cyclops-Flex | relative_timeout | — |
| eda/adf5901 | 172.4% | +72.4% |
| eda/barracuda | 198.4% | +98.4% |
| eda/barracuda-base | relative_timeout | — |
| eda/barracuda-via-fence | 195.1% | +95.1% |
| eda/black-canyon | 166.1% | +66.1% |
| eda/black-canyon+flat | 172.4% | +72.4% |
| eda/blinky-breakout | 174.1% | +74.1% |
| eda/cyclops-analog | relative_timeout | — |
| eda/cyclops-analog+no-vendor-symbols | 213.0% | +113.0% |
| eda/cyclops-breakout | 182.9% | +82.9% |
| eda/cyclops-digital-pcb | 217.7% | +117.7% |
| eda/cyclops-interposer | 176.4% | +76.4% |
| eda/cyclops-kband | relative_timeout | — |
| eda/cyclops-kband-breakout | 174.7% | +74.7% |
| eda/cyclops-kband-pcb | 173.7% | +73.7% |
| eda/cyclops-xband-sip | relative_timeout | — |
| eda/dual-flash | 149.3% | +49.3% |
| eda/labstation | relative_timeout | — |
| eda/labstation+no-vendor-symbols | relative_timeout | — |
| eda/lmk05318b-clock | 195.8% | +95.8% |
| eda/max860-inverter | 164.1% | +64.1% |
| eda/poe-pd-flyback-tps23757 | 170.0% | +70.0% |
| eda/rds3 | 200.9% | +100.9% |
| eda/rds3+flat | 191.7% | +91.7% |
| eda/rds3-rf-selector | 163.1% | +63.1% |
| eda/remora-base | 171.2% | +71.2% |
| eda/remora-rf | 176.2% | +76.2% |
| eda/rf-switch-8way | 179.0% | +79.0% |
| eda/rf-switch-eval | 164.5% | +64.5% |
| eda/stm32n6 | 207.3% | +107.3% |
| eda/straps | 173.4% | +73.4% |
| eda/straps-base | 196.3% | +96.3% |
| eda/w55rp20 | 160.9% | +60.9% |
| lox/tree/binary_trees | 195.5% | +95.5% |
| lox/tree/closures | 178.2% | +78.2% |
| lox/tree/equality | 128.9% | +28.9% |
| lox/tree/fib | 152.1% | +52.1% |
| lox/tree/instantiation | 178.5% | +78.5% |
| lox/tree/invocation | 102.3% | +2.3% |
| lox/tree/method_call | 184.5% | +84.5% |
| lox/tree/properties | 169.4% | +69.4% |
| lox/tree/string_equality | 191.2% | +91.2% |
| lox/tree/strings | 176.6% | +76.6% |
| lox/tree/trees | 166.9% | +66.9% |
| lox/tree/zoo | 165.0% | +65.0% |
| lox/tree/zoo_batch | relative_timeout | — |
| lox/vm/binary_trees | relative_timeout | — |
| lox/vm/closures | 193.4% | +93.4% |
| lox/vm/equality | 245.5% | +145.5% |
| lox/vm/fib | 232.9% | +132.9% |
| lox/vm/instantiation | 234.1% | +134.1% |
| lox/vm/invocation | 260.7% | +160.7% |
| lox/vm/method_call | 282.1% | +182.1% |
| lox/vm/properties | 230.2% | +130.2% |
| lox/vm/string_equality | relative_timeout | — |
| lox/vm/strings | 210.9% | +110.9% |
| lox/vm/trees | 242.8% | +142.8% |
| lox/vm/zoo | 237.0% | +137.0% |
| lox/vm/zoo_batch | 237.9% | +137.9% |
