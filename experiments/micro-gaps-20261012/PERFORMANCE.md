# Four performance gaps: paired qualification

Candidate/baseline below 1 means faster. Both arms use checked ownership and unchanged sources. Raw samples, counters and source/compiler hashes are retained in report.json and results/.

| Case | Size | Candidate/C0 [95% interval] | Allocations C0 → candidate | RSS KiB C0 → candidate |
| --- | --- | --- | --- | --- |
| dict_count | fixed | 0.275 [0.272, 0.289] | 2,003,014 → 4,014 | 1,864 → 1,864 |
| dict_lookup_str | large | 0.975 [0.961, 0.998] | 12,309 → 12,309 | 2,948 → 2,948 |
| dict_lookup_str | small | 0.995 [0.992, 1.000] | 207 → 207 | 1,828 → 1,828 |
| dict_update_str | large | 0.941 [0.929, 0.954] | 1,447,187 → 967,955 | 3,428 → 3,428 |
| dict_update_str | small | 0.946 [0.926, 0.966] | 1,513,691 → 1,021,979 | 1,988 → 1,988 |
| int_format | large | 0.597 [0.594, 0.602] | 6,632,221 → 3,316,119 | 2,020 → 2,020 |
| int_format | small | 0.586 [0.582, 0.590] | 6,950,258 → 3,475,137 | 1,860 → 1,860 |
| sort_records | large | 0.477 [0.472, 0.489] | 5,915 → 5,915 | 2,148 → 2,148 |
| sort_records | small | 0.656 [0.653, 0.660] | 348,851 → 348,851 | 1,828 → 1,828 |
| string_split | large | 0.580 [0.576, 0.584] | 6,266,621 → 3,137,277 | 2,340 → 2,340 |
| string_split | small | 0.618 [0.614, 0.622] | 6,029,636 → 3,128,196 | 1,856 → 1,860 |
| word_count | large | 0.245 [0.243, 0.246] | 11,100,184 → 127,144 | 2,016 → 2,020 |
| word_count | small | 0.395 [0.393, 0.398] | 7,221,904 → 984,850 | 1,860 → 1,860 |

Counts use the calibrated iteration count for that row; compare only within a row. Sorting scratch uses native malloc and is absent from managed allocation counters. The full report retains traffic, managed peak, exit-live, RSS and time separately.

## Managed memory

| Case | Size | Cumulative allocated bytes C0 → candidate | Peak live bytes C0 → candidate | Reallocations C0 → candidate |
| --- | --- | --- | --- | --- |
| dict_count | fixed | 128,234,288 → 298,288 | 152,720 → 152,656 | 3 → 3 |
| dict_lookup_str | large | 1,016,840 → 1,016,840 | 950,904 → 950,904 | 0 → 0 |
| dict_lookup_str | small | 16,656 → 16,656 | 15,472 → 15,472 | 0 → 0 |
| dict_update_str | large | 123,344,640 → 92,673,792 | 1,282,824 → 1,282,760 | 0 → 0 |
| dict_update_str | small | 126,257,720 → 94,788,152 | 20,816 → 20,752 | 0 → 0 |
| int_format | large | 424,495,656 → 212,265,128 | 33,480 → 33,416 | 5 → 5 |
| int_format | small | 444,817,280 → 222,409,536 | 1,376 → 1,376 | 0 → 0 |
| sort_records | large | 387,288,840 → 387,288,840 | 263,040 → 263,040 | 0 → 0 |
| sort_records | small | 375,353,248 → 375,353,248 | 4,976 → 4,976 | 0 → 0 |
| string_split | large | 451,774,520 → 251,496,504 | 401,504 → 401,440 | 4,584 → 4,584 |
| string_split | small | 466,050,008 → 280,357,848 | 7,528 → 7,528 | 0 → 0 |
| word_count | large | 815,256,792 → 10,173,288 | 27,384 → 20,464 | 42,204 → 0 |
| word_count | small | 530,481,696 → 78,787,680 | 2,976 → 1,952 | 0 → 0 |

Validated 91 cells, 2598 timing samples, 524 warmups, 546 RSS probes and 182 counter runs. All counted runs have zero RC events and zero live managed bytes at exit.

## Tradeoffs and remaining differences

Wide owned record sorting uses one additional native scratch allocation per sort: 1,536 bytes for size 64 and 98,304 bytes for size 4,096. Its managed counters are unchanged; a refused optional scratch allocation uses the tested cycle fallback. RSS medians do not resolve this extra temporary storage.

RSS is a separate uninstrumented process high-water measurement. Page granularity and the launch footprint mask small differences; unchanged RSS is not proof that peak total memory is unchanged. Compilation throughput and the full Lox/EDA applications were not remeasured in this four-gap micro campaign.

No cell exceeded the 5% median runtime review threshold. Smaller repeatable slowdowns remain:
- expanded/lox_eval/large: 1.046× [1.042, 1.048].
- expanded/lox_eval/small: 1.035× [1.031, 1.042].
- expanded/list_scan/small: 1.027× [1.021, 1.032].
- expanded/binary_search/small: 1.027× [1.017, 1.043].
- expanded/option_handle/small: 1.016× [1.010, 1.028].
- expanded/set_dedup/small: 1.010× [1.006, 1.013].

These are observations of the integrated batch; no single-pass causal attribution is established. Further tuning stopped after the green verification gate at the user’s request.

The bounded calibration marked 33 of 80 expanded cells as below the nominal fastest-arm target at the final pilot (iteration cap or bounded-growth stop). Their raw pilots and all samples remain included. See report.json for each reason and range, and all-cells.csv for every measured cell.
