# Five application improvements: measured comparison

All 60 frozen inputs remain in the denominator: 13 tree, 13 VM and 34 EDA. The compiler and foreign executable bytes are unchanged; candidate application sources changed. Completed cases have two warmups, nine alternating wall samples, three separate child peak-RSS samples, and complete output checks. Both checked sources stop at 3× the fresh five-sample Zig Fast calibration median (absolute ceiling 120 s). A cutoff has no exact runtime ratio; remaining runtime/RSS/counters are skipped.

Ratios are runtime divided by the reference, lower is better. Full-group ratios require every case to complete. Raw samples, statuses and hashes are in runtime-summary.json.gz, per-cell.csv and results.json.

| Group | Arm | Complete | vs previous checked | vs Zig Fast | vs Zig Safe | vs Rust | vs Go |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| lox/tree | Improved checked source | 12/13 | — | — | — | — | — |
| lox/tree | Previous checked source | 1/13 | — | — | — | — | — |
| lox/tree | Original RC control | 13/13 | — | 1.875 | 1.124 | 1.478 | 1.313 |
| lox/tree | Improved source / RC | 13/13 | — | 1.562 | 0.936 | 1.231 | 1.094 |
| lox/vm | Improved checked source | 11/13 | — | — | — | — | — |
| lox/vm | Previous checked source | 0/13 | — | — | — | — | — |
| lox/vm | Original RC control | 13/13 | — | 2.220 | 1.468 | 1.503 | 1.520 |
| lox/vm | Improved source / RC | 13/13 | — | 2.566 | 1.696 | 1.736 | 1.756 |
| eda | Improved checked source | 27/34 | — | — | — | — | — |
| eda | Previous checked source | 0/34 | — | — | — | — | — |
| eda | Original RC control | 34/34 | — | 1.348 | 1.221 | 1.209 | 0.480 |
| eda | Improved source / RC | 34/34 | — | 1.348 | 1.220 | 1.208 | 0.480 |

The following geometric means cover only completed case pairs. Each ratio includes its eligible-pair count; cutoff cases remain in the full inventory.

| Group | Completed candidate cases | vs Zig Fast (pairs) | vs Zig Safe (pairs) | vs Rust (pairs) | vs Go (pairs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| lox/tree | 12/13 | 1.634 (12) | 0.985 (12) | 1.276 (12) | 1.150 (12) |
| lox/vm | 11/13 | 2.360 (11) | 1.608 (11) | 1.596 (11) | 1.679 (11) |
| eda | 27/34 | 1.800 (27) | 1.626 (27) | 1.596 (27) | 0.646 (27) |

The RC source controls expose a separate tradeoff: the rewritten VM source is 1.156× the original RC source across all 13 cases, with eight case medians more than 5% slower. Tree source under RC improves to 0.833×; EDA is 1.000× overall with individual-case variation. These compare different application sources under RC. They do not isolate a compiler or memory-mode effect, and the exact VM hot-spot cause has not been profiled. The regression is recorded for review; no further optimization was performed after the green gate.

Candidate cases that did not complete the requested timing protocol remain below. A deadline is an execution limit, not an observed complete runtime.

| Candidate case | Status | Checked deadline s |
| --- | --- | ---: |
| eda/Cyclops-Flex | relative_timeout | 0.039192 |
| eda/barracuda-base | relative_timeout | 0.127850 |
| eda/cyclops-analog | relative_timeout | 0.099377 |
| eda/cyclops-kband | relative_timeout | 0.102517 |
| eda/cyclops-xband-sip | relative_timeout | 0.078783 |
| eda/labstation | relative_timeout | 0.187215 |
| eda/labstation+no-vendor-symbols | relative_timeout | 0.132762 |
| lox/tree/zoo_batch | relative_timeout | 1.011277 |
| lox/vm/binary_trees | relative_timeout | 3.361042 |
| lox/vm/string_equality | relative_timeout | 1.430048 |

Process memory below uses the three separate child peak-RSS observations per completed case. Ratios are candidate/reference geometric means, followed by the number of eligible pairs. The range spans per-case median peak RSS, not a combined process-tree peak.

| Group | Candidate RSS range MiB | vs Zig Fast (pairs) | vs Rust (pairs) | vs Go (pairs) |
| --- | ---: | ---: | ---: | ---: |
| lox/tree | 5.11–47.29 | 2.319 (12) | 1.313 (12) | 0.647 (12) |
| lox/vm | 2.60–166.75 | 3.148 (11) | 1.153 (11) | 0.890 (11) |
| eda | 4.86–59.21 | 0.465 (27) | 1.272 (27) | 0.637 (27) |

Managed counters use separate instrumented runs. Coverage is shown against the full group denominator; cases skipped after a runtime cutoff remain in per-cell.csv. The peak column is the largest individual observation, not a sum of peaks.

| Group | Candidate counters completed | Largest candidate managed peak MiB | Previous counters completed |
| --- | ---: | ---: | ---: |
| lox/tree | 12/13 | 48.704 | 1/13 |
| lox/vm | 11/13 | 173.152 | 0/13 |
| eda | 27/34 | 55.146 | 0/34 |

Direct before/after managed-memory comparisons are available only where both checked versions completed counting. Traffic is cumulative; peak is a separate high-water observation.

| Case | Before traffic MiB | After traffic MiB | Before managed peak KiB | After managed peak KiB |
| --- | ---: | ---: | ---: | ---: |
| lox/tree/equality | 2575.002 | 60.809 | 7224.984 | 5923.344 |

| Completed candidate case | Median seconds | vs previous checked | vs Zig Fast | vs Rust | vs Go | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| eda/adf5901 | 0.047720 | — | 1.724 | 1.489 | 0.617 | 10.00 |
| eda/barracuda | 0.133004 | — | 1.984 | 1.802 | 0.705 | 15.17 |
| eda/barracuda-via-fence | 0.114993 | — | 1.951 | 1.740 | 0.699 | 14.07 |
| eda/black-canyon | 0.071978 | — | 1.661 | 1.563 | 0.618 | 11.25 |
| eda/black-canyon+flat | 0.082890 | — | 1.724 | 1.557 | 0.633 | 15.16 |
| eda/blinky-breakout | 0.008882 | — | 1.741 | 1.363 | 0.760 | 4.86 |
| eda/cyclops-analog+no-vendor-symbols | 0.075379 | — | 2.130 | 1.917 | 0.790 | 11.57 |
| eda/cyclops-breakout | 0.051743 | — | 1.829 | 1.631 | 0.587 | 9.85 |
| eda/cyclops-digital-pcb | 0.136751 | — | 2.177 | 1.716 | 0.711 | 29.30 |
| eda/cyclops-interposer | 0.077429 | — | 1.764 | 1.651 | 0.642 | 11.85 |
| eda/cyclops-kband-breakout | 0.087408 | — | 1.747 | 1.659 | 0.644 | 12.14 |
| eda/cyclops-kband-pcb | 0.045370 | — | 1.737 | 1.515 | 0.656 | 19.74 |
| eda/dual-flash | 0.032753 | — | 1.493 | 1.691 | 0.674 | 9.84 |
| eda/lmk05318b-clock | 0.066960 | — | 1.958 | 1.573 | 0.621 | 11.50 |
| eda/max860-inverter | 0.043035 | — | 1.641 | 1.454 | 0.536 | 9.64 |
| eda/poe-pd-flyback-tps23757 | 0.055367 | — | 1.700 | 1.475 | 0.547 | 10.21 |
| eda/rds3 | 0.117092 | — | 2.009 | 1.805 | 0.761 | 21.73 |
| eda/rds3+flat | 0.146191 | — | 1.917 | 1.692 | 0.711 | 59.21 |
| eda/rds3-rf-selector | 0.039135 | — | 1.631 | 1.391 | 0.534 | 9.77 |
| eda/remora-base | 0.048456 | — | 1.712 | 1.637 | 0.678 | 14.39 |
| eda/remora-rf | 0.070890 | — | 1.762 | 1.576 | 0.592 | 13.76 |
| eda/rf-switch-8way | 0.048295 | — | 1.790 | 1.506 | 0.552 | 10.01 |
| eda/rf-switch-eval | 0.024889 | — | 1.645 | 1.397 | 0.587 | 9.93 |
| eda/stm32n6 | 0.072655 | — | 2.073 | 1.753 | 0.750 | 19.16 |
| eda/straps | 0.043888 | — | 1.734 | 1.565 | 0.637 | 13.29 |
| eda/straps-base | 0.072109 | — | 1.963 | 1.680 | 0.706 | 26.41 |
| eda/w55rp20 | 0.026786 | — | 1.609 | 1.463 | 0.589 | 11.81 |
| lox/tree/binary_trees | 0.245242 | — | 1.955 | 1.478 | 1.277 | 7.25 |
| lox/tree/closures | 0.300291 | — | 1.782 | 1.223 | 1.339 | 6.00 |
| lox/tree/equality | 0.369504 | 0.483 | 1.289 | 1.292 | 1.504 | 6.57 |
| lox/tree/fib | 0.210352 | — | 1.521 | 1.031 | 1.167 | 5.38 |
| lox/tree/instantiation | 0.448940 | — | 1.785 | 1.651 | 1.003 | 5.57 |
| lox/tree/invocation | 0.805896 | — | 1.023 | 0.919 | 0.664 | 5.13 |
| lox/tree/method_call | 0.639925 | — | 1.845 | 1.589 | 1.187 | 5.23 |
| lox/tree/properties | 1.301449 | — | 1.694 | 1.423 | 1.015 | 5.17 |
| lox/tree/string_equality | 0.771453 | — | 1.912 | 0.909 | 1.553 | 6.33 |
| lox/tree/strings | 0.351193 | — | 1.766 | 1.283 | 1.186 | 5.83 |
| lox/tree/trees | 0.290354 | — | 1.669 | 1.451 | 1.250 | 47.29 |
| lox/tree/zoo | 1.084625 | — | 1.650 | 1.330 | 0.969 | 5.11 |
| lox/vm/closures | 1.571698 | — | 1.934 | 1.491 | 1.510 | 5.33 |
| lox/vm/equality | 2.253792 | — | 2.455 | 2.096 | 2.001 | 2.75 |
| lox/vm/fib | 1.387951 | — | 2.329 | 1.687 | 1.985 | 2.60 |
| lox/vm/instantiation | 0.917305 | — | 2.341 | 1.435 | 1.207 | 5.32 |
| lox/vm/invocation | 1.962659 | — | 2.607 | 1.362 | 1.578 | 2.82 |
| lox/vm/method_call | 2.389393 | — | 2.821 | 1.881 | 2.061 | 2.82 |
| lox/vm/properties | 1.812996 | — | 2.302 | 1.311 | 1.549 | 2.82 |
| lox/vm/strings | 1.090616 | — | 2.109 | 1.980 | 1.683 | 2.75 |
| lox/vm/trees | 2.379045 | — | 2.428 | 1.698 | 1.815 | 166.75 |
| lox/vm/zoo | 2.076959 | — | 2.370 | 1.379 | 1.601 | 2.72 |
| lox/vm/zoo_batch | 1.773342 | — | 2.379 | 1.451 | 1.676 | 2.72 |

| Guest compilation | Cache | Before median s | After median s | After / before paired ratio |
| --- | --- | ---: | ---: | ---: |
| lox | cold-guest-cache | 6.559 | 6.336 | 1.057 |
| lox | warm-guest-cache | 0.026 | 0.026 | 0.984 |
| eda | cold-guest-cache | 24.599 | 21.630 | 0.836 |
| eda | warm-guest-cache | 0.041 | 0.020 | 0.651 |

Compilation uses three alternating before/after pairs, each with a fresh private guest cache followed by warm replay. Admission wait is excluded; OS and shared host-tool caches are not flushed. GNU-time build RSS is retained per observation but is not an aggregate concurrent process-tree peak.

Lox cold-build pair ratios vary from 0.951 to 1.276; the geometric mean of 1.057 is dominated by one slower pair and does not establish a repeatable regression. EDA cold builds improved in all three pairs. Warm compilations are very short and variable; treat their ratios cautiously. The earlier polling-timer attempt remains archived and is excluded from these results.

Allocation traffic is cumulative; managed peak and GNU-time child peak RSS are separate high-water observations. Instrumented elapsed time is excluded from runtime ratios. Counter totals with different case coverage are not comparable corpus totals. All completed checked counters have zero RC/uniqueness events and zero managed exit-live bytes. Direct destruction and Lox’s own object GC remain valid. Qualification build logs include admission; only the separate compilation table supplies paired compiler-time measurements. Host snapshots before and after each timing chunk record possible contention, without proving the absence of interference during samples. The prior rerun and older historical comparisons retain their original identities.

During the final VM trees RSS block, expected-output files disappeared from another worktree’s cache. All 26 expected outputs were recovered into this experiment with hashes matching the original pins. The interrupted RSS journal is preserved in input-recovery/interrupted-attempt. Only that incomplete three-round RSS block was repeated for all eligible arms; its nine wall samples and inherited cutoff statuses were unchanged. Later receipts identify the resolver and manifest. No external worktree was modified.
