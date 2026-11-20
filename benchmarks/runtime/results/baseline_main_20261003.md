Runtime microbenchmark result: **complete**.

CPU 2; 15 sample rounds; 3 warmup rounds. Kernel time excludes initialization and final formatting. ns/op means one contract iteration (including snapshot copy for mutate_shared).

Optimized default build policies; instruction sets are not matched across arms. No forced target tuning or disabled MyLang checks.

Ratios pair each arm with Go in the same round. Intervals are deterministic 2,000-resample percentile bootstrap intervals for the median paired ratio. Small round counts cannot provide useful uncertainty estimates. Min/max show the raw observed spread; no overall score pools different workloads.

| Case / size | Arm | Iterations | Median ns/op | Min–max ns/op | Ratio to Go | 95% paired interval |
|---|---|---:|---:|---:|---:|---:|
| record_reads / small | my-llvm | 10000000 | 5.34 | 5.33–5.36 | 1.167 | 1.164–1.170 |
| record_reads / small | my-qbe | 10000000 | 10.89 | 10.83–10.97 | 2.380 | 2.368–2.388 |
| record_reads / small | rust | 10000000 | 3.80 | 3.78–3.82 | 0.830 | 0.827–0.832 |
| record_reads / small | go | 10000000 | 4.57 | 4.56–4.68 | 1.000 | 1.000–1.000 |
| record_reads / small | zig-safe | 10000000 | 5.27 | 5.24–5.33 | 1.153 | 1.148–1.156 |
| record_reads / small | zig-fast | 10000000 | 4.88 | 4.86–4.93 | 1.068 | 1.065–1.070 |
| record_reads / large | my-llvm | 10000000 | 5.74 | 5.70–5.84 | 1.229 | 1.215–1.237 |
| record_reads / large | my-qbe | 10000000 | 11.91 | 11.58–12.18 | 2.548 | 2.514–2.579 |
| record_reads / large | rust | 10000000 | 3.86 | 3.86–3.88 | 0.828 | 0.814–0.833 |
| record_reads / large | go | 10000000 | 4.66 | 4.63–4.76 | 1.000 | 1.000–1.000 |
| record_reads / large | zig-safe | 10000000 | 5.30 | 5.28–5.36 | 1.136 | 1.118–1.140 |
| record_reads / large | zig-fast | 10000000 | 4.85 | 4.81–4.93 | 1.036 | 1.030–1.046 |
| tagged_stack / small | my-llvm | 8710631 | 25.00 | 24.91–25.25 | 4.167 | 4.160–4.175 |
| tagged_stack / small | my-qbe | 8710631 | 31.85 | 31.64–32.05 | 5.299 | 5.289–5.319 |
| tagged_stack / small | rust | 8710631 | 5.71 | 5.68–5.91 | 0.949 | 0.947–0.953 |
| tagged_stack / small | go | 8710631 | 6.00 | 5.98–6.09 | 1.000 | 1.000–1.000 |
| tagged_stack / small | zig-safe | 8710631 | 10.63 | 10.54–10.73 | 1.769 | 1.762–1.783 |
| tagged_stack / small | zig-fast | 8710631 | 10.63 | 10.58–10.75 | 1.773 | 1.764–1.778 |
| tagged_stack / large | my-llvm | 8761562 | 25.06 | 24.96–27.83 | 4.170 | 4.158–4.181 |
| tagged_stack / large | my-qbe | 8761562 | 32.00 | 31.68–34.24 | 5.311 | 5.289–5.339 |
| tagged_stack / large | rust | 8761562 | 5.71 | 5.68–6.66 | 0.950 | 0.947–0.952 |
| tagged_stack / large | go | 8761562 | 6.01 | 5.99–6.89 | 1.000 | 1.000–1.000 |
| tagged_stack / large | zig-safe | 8761562 | 10.66 | 10.55–11.87 | 1.769 | 1.752–1.785 |
| tagged_stack / large | zig-fast | 8761562 | 10.66 | 10.60–12.37 | 1.775 | 1.764–1.784 |
| mutate_unique / small | my-llvm | 10000000 | 5.36 | 5.01–5.93 | 1.414 | 1.405–1.439 |
| mutate_unique / small | my-qbe | 10000000 | 29.55 | 27.95–32.46 | 7.850 | 7.775–8.177 |
| mutate_unique / small | rust | 10000000 | 3.28 | 2.91–3.66 | 0.870 | 0.865–0.892 |
| mutate_unique / small | go | 10000000 | 3.68 | 3.40–4.17 | 1.000 | 1.000–1.000 |
| mutate_unique / small | zig-safe | 10000000 | 4.25 | 3.73–4.71 | 1.118 | 1.082–1.141 |
| mutate_unique / small | zig-fast | 10000000 | 4.27 | 3.58–4.57 | 1.081 | 1.059–1.161 |
| mutate_unique / large | my-llvm | 10000000 | 5.39 | 5.01–6.10 | 1.399 | 1.333–1.433 |
| mutate_unique / large | my-qbe | 10000000 | 30.39 | 28.03–32.06 | 7.686 | 7.378–7.837 |
| mutate_unique / large | rust | 10000000 | 3.44 | 2.91–3.73 | 0.865 | 0.832–0.873 |
| mutate_unique / large | go | 10000000 | 3.96 | 3.34–4.33 | 1.000 | 1.000–1.000 |
| mutate_unique / large | zig-safe | 10000000 | 4.27 | 3.73–4.80 | 1.104 | 1.033–1.130 |
| mutate_unique / large | zig-fast | 10000000 | 4.36 | 3.60–4.71 | 1.054 | 1.012–1.079 |
| mutate_shared / small | my-llvm | 4960000 | 136.52 | 127.23–157.52 | 2.139 | 2.113–2.159 |
| mutate_shared / small | my-qbe | 4960000 | 192.62 | 178.92–215.14 | 3.025 | 2.942–3.084 |
| mutate_shared / small | rust | 4960000 | 12.64 | 11.45–16.13 | 0.196 | 0.194–0.205 |
| mutate_shared / small | go | 4960000 | 63.50 | 59.47–74.12 | 1.000 | 1.000–1.000 |
| mutate_shared / small | zig-safe | 4960000 | 19.11 | 17.58–21.48 | 0.293 | 0.291–0.301 |
| mutate_shared / small | zig-fast | 4960000 | 11.83 | 11.00–13.58 | 0.186 | 0.183–0.187 |
| mutate_shared / large | my-llvm | 748382 | 277.99 | 252.40–449.01 | 0.377 | 0.370–0.382 |
| mutate_shared / large | my-qbe | 748382 | 335.77 | 320.39–359.18 | 0.457 | 0.452–0.465 |
| mutate_shared / large | rust | 748382 | 83.94 | 76.43–88.38 | 0.113 | 0.112–0.116 |
| mutate_shared / large | go | 748382 | 732.20 | 706.67–756.31 | 1.000 | 1.000–1.000 |
| mutate_shared / large | zig-safe | 748382 | 188.48 | 161.73–203.72 | 0.256 | 0.254–0.259 |
| mutate_shared / large | zig-fast | 748382 | 145.86 | 143.72–155.25 | 0.199 | 0.197–0.204 |

Calibration hit a slowest-arm or iteration cap before the fastest arm reached its target: record_reads/small, record_reads/large, mutate_unique/small, mutate_unique/large. Inspect raw kernel durations before interpreting these cases.

Peak RSS is measured in separate processes and appears in the companion JSON. Process wall time is secondary. Sibling reservation is operator-managed; busy counters record average load and cannot exclude short interference.
