Expanded runtime benchmark: **subset**.

4 cases; 5 measured rounds; 1 warmups; 240 measured samples across all six configurations.

Optimized default build policies; instruction sets are not matched across arms. No forced target tuning or disabled MyLang checks.

Times below are **ns per CLI iteration**, not necessarily per element. See the unit column and contracts. Application and native-library workloads include their documented algorithms. Ratios are medians of paired rounds against Go; 95% intervals use 2,000 bootstrap resamples. No aggregate ranking pools different workloads.

| Case / profile | Level | Unit | Arm | Median ns/iteration | Min–max | Ratio to Go | 95% interval |
|---|---|---|---|---:|---:|---:|---:|
| mutate_unique / small | micro | one contract operation | my-llvm | 4.22 | 4.21–5.28 | 1.264 | 1.255–1.581 |
| mutate_unique / small | micro | one contract operation | my-qbe | 21.07 | 21.00–21.12 | 6.309 | 6.278–6.325 |
| mutate_unique / small | micro | one contract operation | rust | 2.92 | 2.90–2.94 | 0.873 | 0.870–0.881 |
| mutate_unique / small | micro | one contract operation | go | 3.34 | 3.33–3.36 | 1.000 | 1.000–1.000 |
| mutate_unique / small | micro | one contract operation | zig-safe | 3.74 | 3.73–3.75 | 1.120 | 1.117–1.123 |
| mutate_unique / small | micro | one contract operation | zig-fast | 3.59 | 3.58–3.60 | 1.074 | 1.068–1.082 |
| mutate_unique / large | micro | one contract operation | my-llvm | 4.25 | 4.22–4.31 | 1.271 | 1.242–1.290 |
| mutate_unique / large | micro | one contract operation | my-qbe | 21.06 | 21.03–21.16 | 6.287 | 6.223–6.331 |
| mutate_unique / large | micro | one contract operation | rust | 2.92 | 2.89–2.95 | 0.876 | 0.856–0.880 |
| mutate_unique / large | micro | one contract operation | go | 3.35 | 3.34–3.40 | 1.000 | 1.000–1.000 |
| mutate_unique / large | micro | one contract operation | zig-safe | 3.75 | 3.72–3.75 | 1.115 | 1.103–1.121 |
| mutate_unique / large | micro | one contract operation | zig-fast | 3.59 | 3.59–3.71 | 1.073 | 1.055–1.107 |
| mutate_shared / small | micro | one contract operation | my-llvm | 110.62 | 110.10–110.79 | 2.061 | 2.057–2.069 |
| mutate_shared / small | micro | one contract operation | my-qbe | 153.90 | 153.87–154.03 | 2.873 | 2.858–2.881 |
| mutate_shared / small | micro | one contract operation | rust | 10.32 | 10.25–10.38 | 0.192 | 0.191–0.194 |
| mutate_shared / small | micro | one contract operation | go | 53.62 | 53.41–53.84 | 1.000 | 1.000–1.000 |
| mutate_shared / small | micro | one contract operation | zig-safe | 15.66 | 15.49–15.83 | 0.292 | 0.289–0.295 |
| mutate_shared / small | micro | one contract operation | zig-fast | 9.98 | 9.85–10.13 | 0.186 | 0.184–0.189 |
| mutate_shared / large | micro | one contract operation | my-llvm | 226.95 | 225.72–227.27 | 0.392 | 0.385–0.397 |
| mutate_shared / large | micro | one contract operation | my-qbe | 269.95 | 268.99–270.46 | 0.465 | 0.460–0.472 |
| mutate_shared / large | micro | one contract operation | rust | 65.49 | 64.69–66.11 | 0.113 | 0.110–0.115 |
| mutate_shared / large | micro | one contract operation | go | 579.84 | 572.40–586.99 | 1.000 | 1.000–1.000 |
| mutate_shared / large | micro | one contract operation | zig-safe | 147.00 | 146.14–148.32 | 0.252 | 0.250–0.259 |
| mutate_shared / large | micro | one contract operation | zig-fast | 113.45 | 113.09–113.78 | 0.196 | 0.193–0.198 |
| record_reads / small | micro | one contract operation | my-llvm | 5.36 | 5.34–5.38 | 1.172 | 1.169–1.178 |
| record_reads / small | micro | one contract operation | my-qbe | 11.64 | 11.61–11.96 | 2.552 | 2.537–2.615 |
| record_reads / small | micro | one contract operation | rust | 3.80 | 3.79–3.87 | 0.833 | 0.831–0.846 |
| record_reads / small | micro | one contract operation | go | 4.57 | 4.56–4.58 | 1.000 | 1.000–1.000 |
| record_reads / small | micro | one contract operation | zig-safe | 5.27 | 5.26–5.27 | 1.153 | 1.149–1.155 |
| record_reads / small | micro | one contract operation | zig-fast | 4.88 | 4.87–4.90 | 1.068 | 1.068–1.073 |
| record_reads / large | micro | one contract operation | my-llvm | 5.61 | 5.54–5.70 | 1.195 | 1.175–1.225 |
| record_reads / large | micro | one contract operation | my-qbe | 14.14 | 13.60–15.69 | 3.036 | 2.904–3.373 |
| record_reads / large | micro | one contract operation | rust | 3.88 | 3.85–3.88 | 0.829 | 0.817–0.833 |
| record_reads / large | micro | one contract operation | go | 4.68 | 4.65–4.71 | 1.000 | 1.000–1.000 |
| record_reads / large | micro | one contract operation | zig-safe | 5.44 | 5.32–5.56 | 1.155 | 1.135–1.184 |
| record_reads / large | micro | one contract operation | zig-fast | 4.82 | 4.81–4.86 | 1.027 | 1.019–1.043 |
| tagged_stack / small | micro | one contract operation | my-llvm | 16.69 | 16.67–16.77 | 2.782 | 2.763–2.796 |
| tagged_stack / small | micro | one contract operation | my-qbe | 21.49 | 21.32–21.56 | 3.573 | 3.531–3.599 |
| tagged_stack / small | micro | one contract operation | rust | 5.70 | 5.68–5.71 | 0.950 | 0.941–0.953 |
| tagged_stack / small | micro | one contract operation | go | 6.00 | 5.99–6.04 | 1.000 | 1.000–1.000 |
| tagged_stack / small | micro | one contract operation | zig-safe | 10.50 | 10.47–10.53 | 1.748 | 1.738–1.758 |
| tagged_stack / small | micro | one contract operation | zig-fast | 10.61 | 10.58–10.75 | 1.772 | 1.752–1.795 |
| tagged_stack / large | micro | one contract operation | my-llvm | 16.68 | 16.66–16.78 | 2.776 | 2.751–2.794 |
| tagged_stack / large | micro | one contract operation | my-qbe | 21.40 | 21.30–21.43 | 3.565 | 3.526–3.580 |
| tagged_stack / large | micro | one contract operation | rust | 5.71 | 5.68–5.75 | 0.951 | 0.937–0.957 |
| tagged_stack / large | micro | one contract operation | go | 6.01 | 5.99–6.06 | 1.000 | 1.000–1.000 |
| tagged_stack / large | micro | one contract operation | zig-safe | 10.49 | 10.47–10.52 | 1.748 | 1.727–1.755 |
| tagged_stack / large | micro | one contract operation | zig-fast | 10.61 | 10.58–10.77 | 1.772 | 1.762–1.784 |

Calibration limits: mutate_unique/small (iteration_cap), mutate_unique/large (iteration_cap), mutate_shared/small (slowest_arm_budget), record_reads/small (iteration_cap), record_reads/large (iteration_cap), tagged_stack/small (slowest_arm_budget), tagged_stack/large (slowest_arm_budget).

Per-core activity: {"2": 98.89889889889889, "3": 0.15018773466833543}.
Governor: powersave.
Sibling reservation is operator-managed; busy counters record average load and cannot exclude short interference.

Operation inventory coverage does not establish 80% of everyday CPU time. Separate application profiles are required.
