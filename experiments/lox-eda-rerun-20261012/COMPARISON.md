# Lox and EDA: fresh rerun with the 3× Zig cutoff

All 60 cases were attempted: 34 EDA designs, 13 Lox tree cases and 13 Lox VM cases. Completed arms have two warmups, nine alternating runtime samples, three separate child peak-RSS samples, and verified output oracles. Checked-ownership invocations exceeding three times the five-sample Zig ReleaseFast calibration median stop immediately; later runtime, RSS and counted runs for that checked case are skipped. The absolute ceiling is 120 seconds. A cutoff is not a measured median ratio. All missing results stay in the denominator.

The compiler, application sources, executable hashes, command lines and workload inputs are recorded in [README.md](README.md), build receipts and specifications. No compiler or application changes were made for this rerun. The Zig/Rust/Go executable bytes match the previous run and were freshly executed. Original RC and migrated RC are same-compiler controls; the checked arm uses the same source as migrated RC.

Ratios below are elapsed runtime divided by the comparison arm; lower is better. A group gets a ratio only when every case in that group completes. No subset is presented as the full benchmark.

| Group | Arm | Complete | vs Zig Fast | vs Zig Safe | vs Rust | vs Go | Largest case-median peak RSS (MiB) |
|---|---|---:|---:|---:|---:|---:|---:|
| lox/tree | Checked ownership | 1/13 | — | — | — | — | — |
| lox/tree | Original RC | 13/13 | 1.805 | 1.103 | 1.384 | 1.352 | 46.46 |
| lox/tree | Migrated RC | 13/13 | 1.770 | 1.082 | 1.358 | 1.326 | 46.63 |
| lox/tree | Zig ReleaseFast | 13/13 | 1.000 | 0.611 | 0.767 | 0.749 | 35.34 |
| lox/tree | Zig ReleaseSafe | 13/13 | 1.636 | 1.000 | 1.255 | 1.226 | 41.48 |
| lox/tree | Rust | 13/13 | 1.304 | 0.797 | 1.000 | 0.977 | 40.56 |
| lox/tree | Go | 13/13 | 1.335 | 0.816 | 1.024 | 1.000 | 68.08 |
| lox/vm | Checked ownership | 0/13 | — | — | — | — | — |
| lox/vm | Original RC | 13/13 | 2.209 | 1.467 | 1.498 | 1.518 | 166.95 |
| lox/vm | Migrated RC | 13/13 | 2.309 | 1.534 | 1.566 | 1.587 | 167.00 |
| lox/vm | Zig ReleaseFast | 13/13 | 1.000 | 0.664 | 0.678 | 0.687 | 142.31 |
| lox/vm | Zig ReleaseSafe | 13/13 | 1.505 | 1.000 | 1.021 | 1.035 | 150.88 |
| lox/vm | Rust | 13/13 | 1.475 | 0.980 | 1.000 | 1.014 | 155.09 |
| lox/vm | Go | 13/13 | 1.455 | 0.966 | 0.986 | 1.000 | 155.42 |
| eda | Checked ownership | 0/34 | — | — | — | — | — |
| eda | Original RC | 34/34 | 1.229 | 1.121 | 1.122 | 0.478 | 52.70 |
| eda | Migrated RC | 34/34 | 1.240 | 1.131 | 1.132 | 0.482 | 52.68 |
| eda | Zig ReleaseFast | 34/34 | 1.000 | 0.912 | 0.913 | 0.389 | 80.13 |
| eda | Zig ReleaseSafe | 34/34 | 1.096 | 1.000 | 1.001 | 0.426 | 80.12 |
| eda | Rust | 34/34 | 1.095 | 0.999 | 1.000 | 0.425 | 43.95 |
| eda | Go | 34/34 | 2.574 | 2.348 | 2.350 | 1.000 | 67.52 |

Completed checked cases are listed individually below; this selected set does not represent the full suite.

| Checked case | Median (s) | vs Zig Fast | vs Rust | vs Go | Median peak RSS (MiB) |
|---|---:|---:|---:|---:|---:|
| lox/tree/equality | 0.539886 | 2.791 | 2.671 | 3.235 | 10.05 |

The detailed CSV includes each arm’s runtime range, RSS range, allocation count, reallocation count, allocation traffic, managed peak, exit-live bytes, and prior Oct12/Oct9 observations. Missing counted data is unavailable, never zero. Allocation traffic is cumulative; managed peak and RSS are separate per-process high-water measurements. RSS is GNU time’s child peak RSS, excluding the Python harness. This rerun does not claim compiler-time or compiler-RSS comparisons; build durations include admission/setup.

| Group | Counted arm | Completed | Allocation traffic over completed cases (MiB) | Largest managed peak over completed cases (MiB) |
|---|---|---:|---:|---:|
| lox/tree | Checked ownership | 1/13 | 2575.00 | 7.06 |
| lox/tree | Original RC | 13/13 | 4623.42 | 46.45 |
| lox/tree | Migrated RC | 13/13 | 4685.83 | 46.72 |
| lox/vm | Checked ownership | 0/13 | — | — |
| lox/vm | Original RC | 13/13 | 9472.84 | 166.00 |
| lox/vm | Migrated RC | 13/13 | 9502.45 | 166.17 |
| eda | Checked ownership | 0/34 | — | — |
| eda | Original RC | 34/34 | 2974.46 | 49.03 |
| eda | Migrated RC | 34/34 | 2974.58 | 49.03 |

All completed counted guests exit with zero live managed bytes. Completed checked runs also have zero compiler/runtime/shared retains and releases, share marks and uniqueness tests. Direct destruction and the Lox application’s own garbage collector remain valid. Counter rows with different coverage must not be compared as total traffic for the same workload set.

For completed checked cases, the same-case memory comparisons are:

| Case | Arm | Allocations | Reallocations | Allocation traffic (MiB) | Managed peak (MiB) | Median peak RSS (MiB) |
|---|---|---:|---:|---:|---:|---:|
| lox/tree/equality | Checked ownership | 38129545 | 43 | 2575.00 | 7.06 | 10.05 |
| lox/tree/equality | Original RC | 600385 | 42 | 20.91 | 3.45 | 5.70 |
| lox/tree/equality | Migrated RC | 600438 | 42 | 21.48 | 3.48 | 5.69 |

| Group | Reference | Oct9 original RC / reference | Prior Oct12 checked / reference | Fresh checked / reference |
|---|---|---:|---:|---:|
| lox/tree | Zig ReleaseFast | 1.623 | 4.213 | — |
| lox/tree | Zig ReleaseSafe | 1.007 | 2.565 | — |
| lox/tree | Rust | 1.263 | 3.220 | — |
| lox/tree | Go | 1.249 | 3.134 | — |
| lox/vm | Zig ReleaseFast | 2.926 | — | — |
| lox/vm | Zig ReleaseSafe | 1.957 | — | — |
| lox/vm | Rust | 1.989 | — | — |
| lox/vm | Go | 2.060 | — | — |
| eda | Zig ReleaseFast | 1.290 | 12.850 | — |
| eda | Zig ReleaseSafe | 1.166 | 11.707 | — |
| eda | Rust | 1.145 | 11.708 | — |
| eda | Go | 0.474 | 4.976 | — |

Historical numbers are context, not paired speedup evidence. Oct9 used CPU 10 and different artifacts; Oct12 uses CPU 8. This run pins Go GOMAXPROCS=1, GOGC=100 and GOMEMLIMIT=off, while the prior full-app run did not record those overrides. Historical Lox RSS used the maximum across timing rounds; current RSS uses the median of three separate measurements. The current CPU-time environment can vary between leases despite exclusive cooperating-job admission.

| Case | Checked result | Zig calibration median (s) | Checked deadline (s) | Checked median (s), if complete |
|---|---|---:|---:|---:|
| eda/Cyclops-Flex | relative_timeout | 0.011026 | 0.033078 | — |
| eda/adf5901 | relative_timeout | 0.012427 | 0.037281 | — |
| eda/barracuda | relative_timeout | 0.032352 | 0.097055 | — |
| eda/barracuda-base | relative_timeout | 0.035229 | 0.105687 | — |
| eda/barracuda-via-fence | relative_timeout | 0.027099 | 0.081298 | — |
| eda/black-canyon | relative_timeout | 0.025086 | 0.075257 | — |
| eda/black-canyon+flat | relative_timeout | 0.021735 | 0.065206 | — |
| eda/blinky-breakout | relative_timeout | 0.002864 | 0.008593 | — |
| eda/cyclops-analog | relative_timeout | 0.028792 | 0.086377 | — |
| eda/cyclops-analog+no-vendor-symbols | relative_timeout | 0.018667 | 0.056000 | — |
| eda/cyclops-breakout | relative_timeout | 0.013233 | 0.039699 | — |
| eda/cyclops-digital-pcb | relative_timeout | 0.029362 | 0.088087 | — |
| eda/cyclops-interposer | relative_timeout | 0.021096 | 0.063288 | — |
| eda/cyclops-kband | relative_timeout | 0.024157 | 0.072471 | — |
| eda/cyclops-kband-breakout | relative_timeout | 0.022892 | 0.068677 | — |
| eda/cyclops-kband-pcb | relative_timeout | 0.023544 | 0.070633 | — |
| eda/cyclops-xband-sip | relative_timeout | 0.018238 | 0.054714 | — |
| eda/dual-flash | relative_timeout | 0.011850 | 0.035549 | — |
| eda/labstation | relative_timeout | 0.044454 | 0.133362 | — |
| eda/labstation+no-vendor-symbols | relative_timeout | 0.035262 | 0.105786 | — |
| eda/lmk05318b-clock | relative_timeout | 0.014840 | 0.044520 | — |
| eda/max860-inverter | relative_timeout | 0.010922 | 0.032765 | — |
| eda/poe-pd-flyback-tps23757 | relative_timeout | 0.014718 | 0.044153 | — |
| eda/rds3 | relative_timeout | 0.053808 | 0.161425 | — |
| eda/rds3+flat | relative_timeout | 0.059929 | 0.179788 | — |
| eda/rds3-rf-selector | relative_timeout | 0.011349 | 0.034047 | — |
| eda/remora-base | relative_timeout | 0.024599 | 0.073797 | — |
| eda/remora-rf | relative_timeout | 0.024345 | 0.073035 | — |
| eda/rf-switch-8way | relative_timeout | 0.013569 | 0.040706 | — |
| eda/rf-switch-eval | relative_timeout | 0.013636 | 0.040908 | — |
| eda/stm32n6 | relative_timeout | 0.033159 | 0.099476 | — |
| eda/straps | relative_timeout | 0.024277 | 0.072832 | — |
| eda/straps-base | relative_timeout | 0.034521 | 0.103564 | — |
| eda/w55rp20 | relative_timeout | 0.015578 | 0.046734 | — |
| lox/tree/binary_trees | relative_timeout | 0.120426 | 0.361277 | — |
| lox/tree/closures | relative_timeout | 0.167253 | 0.501759 | — |
| lox/tree/equality | complete | 0.193804 | 0.581411 | 0.539886 |
| lox/tree/fib | relative_timeout | 0.095593 | 0.286780 | — |
| lox/tree/instantiation | relative_timeout | 0.122955 | 0.368865 | — |
| lox/tree/invocation | relative_timeout | 0.414834 | 1.244503 | — |
| lox/tree/method_call | relative_timeout | 0.278432 | 0.835296 | — |
| lox/tree/properties | relative_timeout | 0.325373 | 0.976118 | — |
| lox/tree/string_equality | relative_timeout | 0.144576 | 0.433727 | — |
| lox/tree/strings | relative_timeout | 0.086846 | 0.260539 | — |
| lox/tree/trees | relative_timeout | 0.140805 | 0.422416 | — |
| lox/tree/zoo | relative_timeout | 0.352433 | 1.057298 | — |
| lox/tree/zoo_batch | relative_timeout | 0.300264 | 0.900793 | — |
| lox/vm/binary_trees | relative_timeout | 0.495874 | 1.487622 | — |
| lox/vm/closures | relative_timeout | 0.762675 | 2.288024 | — |
| lox/vm/equality | relative_timeout | 0.934502 | 2.803507 | — |
| lox/vm/fib | relative_timeout | 0.601509 | 1.804527 | — |
| lox/vm/instantiation | relative_timeout | 0.388096 | 1.164289 | — |
| lox/vm/invocation | relative_timeout | 0.751254 | 2.253763 | — |
| lox/vm/method_call | relative_timeout | 0.904860 | 2.714581 | — |
| lox/vm/properties | relative_timeout | 0.787442 | 2.362326 | — |
| lox/vm/string_equality | relative_timeout | 0.476071 | 1.428212 | — |
| lox/vm/strings | relative_timeout | 0.519184 | 1.557551 | — |
| lox/vm/trees | relative_timeout | 0.977267 | 2.931800 | — |
| lox/vm/zoo | relative_timeout | 0.873490 | 2.620470 | — |
| lox/vm/zoo_batch | relative_timeout | 0.752925 | 2.258774 | — |

Raw data: [per-cell.csv](per-cell.csv), [results.json](results.json), [runtime-summary.json.gz](runtime-summary.json.gz), and the runtime/counting receipts. All runtime input/binary identities and host snapshot hashes were revalidated after measurement. The timeout harness passed four regression tests covering completion, cutoff, chunk carry-over, failed reference calibration and descendant-process termination.
