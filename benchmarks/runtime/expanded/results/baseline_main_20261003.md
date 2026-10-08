Expanded runtime benchmark: **complete**.

40 cases; 15 measured rounds; 3 warmups; 7200 measured samples across all six configurations.

Optimized default build policies; instruction sets are not matched across arms. No forced target tuning or disabled MyLang checks.

Times below are **ns per CLI iteration**, not necessarily per element. See the unit column and contracts. Application and native-library workloads include their documented algorithms. Ratios are medians of paired rounds against Go; 95% intervals use 2,000 bootstrap resamples. No aggregate ranking pools different workloads.

| Case / profile | Level | Unit | Arm | Median ns/iteration | Min–max | Ratio to Go | 95% interval |
|---|---|---|---|---:|---:|---:|---:|
| record_reads / small | micro | one contract operation | my-llvm | 5.35 | 5.33–5.46 | 1.168 | 1.166–1.173 |
| record_reads / small | micro | one contract operation | my-qbe | 10.86 | 10.80–10.97 | 2.376 | 2.360–2.380 |
| record_reads / small | micro | one contract operation | rust | 3.80 | 3.78–3.82 | 0.832 | 0.828–0.833 |
| record_reads / small | micro | one contract operation | go | 4.57 | 4.56–4.76 | 1.000 | 1.000–1.000 |
| record_reads / small | micro | one contract operation | zig-safe | 5.26 | 5.24–5.28 | 1.151 | 1.146–1.153 |
| record_reads / small | micro | one contract operation | zig-fast | 4.88 | 4.87–4.92 | 1.068 | 1.066–1.070 |
| record_reads / large | micro | one contract operation | my-llvm | 5.78 | 5.67–5.87 | 1.235 | 1.233–1.240 |
| record_reads / large | micro | one contract operation | my-qbe | 12.27 | 11.90–12.79 | 2.609 | 2.585–2.647 |
| record_reads / large | micro | one contract operation | rust | 3.87 | 3.85–3.89 | 0.824 | 0.823–0.833 |
| record_reads / large | micro | one contract operation | go | 4.70 | 4.63–4.75 | 1.000 | 1.000–1.000 |
| record_reads / large | micro | one contract operation | zig-safe | 5.37 | 5.29–5.49 | 1.151 | 1.136–1.158 |
| record_reads / large | micro | one contract operation | zig-fast | 4.81 | 4.77–4.87 | 1.022 | 1.015–1.030 |
| tagged_stack / small | micro | one contract operation | my-llvm | 24.92 | 24.79–25.01 | 4.153 | 4.142–4.162 |
| tagged_stack / small | micro | one contract operation | my-qbe | 31.48 | 31.36–44.10 | 5.250 | 5.243–5.255 |
| tagged_stack / small | micro | one contract operation | rust | 5.71 | 5.69–6.09 | 0.952 | 0.949–0.953 |
| tagged_stack / small | micro | one contract operation | go | 5.99 | 5.99–6.05 | 1.000 | 1.000–1.000 |
| tagged_stack / small | micro | one contract operation | zig-safe | 10.54 | 10.49–11.73 | 1.758 | 1.751–1.777 |
| tagged_stack / small | micro | one contract operation | zig-fast | 10.63 | 10.57–10.88 | 1.773 | 1.764–1.776 |
| tagged_stack / large | micro | one contract operation | my-llvm | 24.92 | 24.84–25.03 | 4.154 | 4.147–4.164 |
| tagged_stack / large | micro | one contract operation | my-qbe | 31.48 | 31.32–31.68 | 5.248 | 5.237–5.260 |
| tagged_stack / large | micro | one contract operation | rust | 5.70 | 5.68–5.76 | 0.950 | 0.949–0.952 |
| tagged_stack / large | micro | one contract operation | go | 6.00 | 5.98–6.09 | 1.000 | 1.000–1.000 |
| tagged_stack / large | micro | one contract operation | zig-safe | 10.65 | 10.50–10.72 | 1.775 | 1.761–1.781 |
| tagged_stack / large | micro | one contract operation | zig-fast | 10.61 | 10.57–10.90 | 1.771 | 1.768–1.775 |
| mutate_unique / small | micro | one contract operation | my-llvm | 4.93 | 4.89–5.00 | 1.476 | 1.468–1.481 |
| mutate_unique / small | micro | one contract operation | my-qbe | 27.67 | 27.57–27.89 | 8.268 | 8.248–8.279 |
| mutate_unique / small | micro | one contract operation | rust | 2.91 | 2.89–2.94 | 0.870 | 0.868–0.875 |
| mutate_unique / small | micro | one contract operation | go | 3.34 | 3.33–3.42 | 1.000 | 1.000–1.000 |
| mutate_unique / small | micro | one contract operation | zig-safe | 3.75 | 3.71–3.96 | 1.120 | 1.116–1.125 |
| mutate_unique / small | micro | one contract operation | zig-fast | 3.58 | 3.57–3.62 | 1.071 | 1.068–1.076 |
| mutate_unique / large | micro | one contract operation | my-llvm | 4.95 | 4.90–5.11 | 1.476 | 1.472–1.487 |
| mutate_unique / large | micro | one contract operation | my-qbe | 27.67 | 27.51–27.84 | 8.253 | 8.242–8.265 |
| mutate_unique / large | micro | one contract operation | rust | 2.92 | 2.89–2.97 | 0.870 | 0.865–0.875 |
| mutate_unique / large | micro | one contract operation | go | 3.35 | 3.33–3.42 | 1.000 | 1.000–1.000 |
| mutate_unique / large | micro | one contract operation | zig-safe | 3.74 | 3.72–3.78 | 1.114 | 1.106–1.119 |
| mutate_unique / large | micro | one contract operation | zig-fast | 3.59 | 3.57–4.70 | 1.074 | 1.066–1.075 |
| mutate_shared / small | micro | one contract operation | my-llvm | 117.84 | 116.80–120.25 | 2.161 | 2.144–2.173 |
| mutate_shared / small | micro | one contract operation | my-qbe | 166.51 | 165.55–167.89 | 3.052 | 3.039–3.070 |
| mutate_shared / small | micro | one contract operation | rust | 10.83 | 10.67–11.25 | 0.198 | 0.196–0.200 |
| mutate_shared / small | micro | one contract operation | go | 54.48 | 53.98–55.19 | 1.000 | 1.000–1.000 |
| mutate_shared / small | micro | one contract operation | zig-safe | 16.13 | 15.81–16.53 | 0.296 | 0.294–0.299 |
| mutate_shared / small | micro | one contract operation | zig-fast | 10.40 | 10.21–10.57 | 0.191 | 0.189–0.192 |
| mutate_shared / large | micro | one contract operation | my-llvm | 230.29 | 229.17–232.00 | 0.393 | 0.390–0.395 |
| mutate_shared / large | micro | one contract operation | my-qbe | 285.99 | 284.57–289.91 | 0.490 | 0.487–0.492 |
| mutate_shared / large | micro | one contract operation | rust | 67.63 | 67.30–68.80 | 0.116 | 0.115–0.117 |
| mutate_shared / large | micro | one contract operation | go | 585.30 | 578.13–597.17 | 1.000 | 1.000–1.000 |
| mutate_shared / large | micro | one contract operation | zig-safe | 147.21 | 146.34–148.55 | 0.252 | 0.250–0.253 |
| mutate_shared / large | micro | one contract operation | zig-fast | 114.70 | 114.10–117.96 | 0.196 | 0.196–0.198 |
| integer_math / small | micro | one complete pass over SIZE fixtures | my-llvm | 192.70 | 191.75–195.01 | 1.604 | 1.600–1.607 |
| integer_math / small | micro | one complete pass over SIZE fixtures | my-qbe | 949.25 | 946.95–952.20 | 7.885 | 7.863–7.913 |
| integer_math / small | micro | one complete pass over SIZE fixtures | rust | 91.17 | 90.21–92.31 | 0.757 | 0.754–0.760 |
| integer_math / small | micro | one complete pass over SIZE fixtures | go | 120.38 | 119.58–139.85 | 1.000 | 1.000–1.000 |
| integer_math / small | micro | one complete pass over SIZE fixtures | zig-safe | 122.31 | 121.44–122.82 | 1.017 | 1.009–1.020 |
| integer_math / small | micro | one complete pass over SIZE fixtures | zig-fast | 108.30 | 107.85–109.23 | 0.903 | 0.897–0.904 |
| integer_math / large | micro | one complete pass over SIZE fixtures | my-llvm | 11749.88 | 11732.91–11837.05 | 1.632 | 1.628–1.636 |
| integer_math / large | micro | one complete pass over SIZE fixtures | my-qbe | 60039.21 | 59868.40–61093.20 | 8.341 | 8.323–8.355 |
| integer_math / large | micro | one complete pass over SIZE fixtures | rust | 5305.53 | 5272.95–5341.60 | 0.737 | 0.735–0.740 |
| integer_math / large | micro | one complete pass over SIZE fixtures | go | 7203.46 | 7153.45–7268.15 | 1.000 | 1.000–1.000 |
| integer_math / large | micro | one complete pass over SIZE fixtures | zig-safe | 7138.92 | 7110.53–7247.67 | 0.994 | 0.990–0.998 |
| integer_math / large | micro | one complete pass over SIZE fixtures | zig-fast | 6410.35 | 6353.95–6506.54 | 0.893 | 0.890–0.894 |
| float_math / small | micro | one complete pass over SIZE fixtures | my-llvm | 172.20 | 171.77–173.77 | 1.652 | 1.647–1.658 |
| float_math / small | micro | one complete pass over SIZE fixtures | my-qbe | 989.86 | 983.98–1006.46 | 9.488 | 9.451–9.533 |
| float_math / small | micro | one complete pass over SIZE fixtures | rust | 108.33 | 107.86–109.18 | 1.039 | 1.037–1.043 |
| float_math / small | micro | one complete pass over SIZE fixtures | go | 104.22 | 103.82–104.77 | 1.000 | 1.000–1.000 |
| float_math / small | micro | one complete pass over SIZE fixtures | zig-safe | 104.25 | 103.38–105.06 | 1.000 | 0.999–1.002 |
| float_math / small | micro | one complete pass over SIZE fixtures | zig-fast | 70.78 | 70.26–74.73 | 0.680 | 0.677–0.681 |
| float_math / large | micro | one complete pass over SIZE fixtures | my-llvm | 10588.39 | 10552.75–10614.17 | 1.696 | 1.690–1.698 |
| float_math / large | micro | one complete pass over SIZE fixtures | my-qbe | 62601.26 | 62296.27–63193.57 | 10.004 | 9.982–10.040 |
| float_math / large | micro | one complete pass over SIZE fixtures | rust | 6535.99 | 6477.92–6575.61 | 1.045 | 1.044–1.048 |
| float_math / large | micro | one complete pass over SIZE fixtures | go | 6245.55 | 6218.83–6277.26 | 1.000 | 1.000–1.000 |
| float_math / large | micro | one complete pass over SIZE fixtures | zig-safe | 6131.44 | 6097.71–6221.73 | 0.979 | 0.978–0.983 |
| float_math / large | micro | one complete pass over SIZE fixtures | zig-fast | 4125.32 | 4091.63–4160.86 | 0.660 | 0.656–0.663 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | my-llvm | 160.09 | 153.65–161.66 | 1.586 | 1.577–1.606 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | my-qbe | 704.84 | 703.98–717.07 | 7.017 | 7.008–7.038 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | rust | 52.48 | 51.83–53.43 | 0.522 | 0.519–0.526 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | go | 100.50 | 99.80–101.14 | 1.000 | 1.000–1.000 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | zig-safe | 117.96 | 117.02–118.92 | 1.173 | 1.168–1.176 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | zig-fast | 52.45 | 51.82–53.13 | 0.522 | 0.519–0.526 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | my-llvm | 10409.00 | 10359.32–11037.68 | 1.604 | 1.602–1.608 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | my-qbe | 44473.55 | 44413.94–44682.94 | 6.856 | 6.846–6.868 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | rust | 3297.52 | 3249.68–3372.17 | 0.508 | 0.505–0.511 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | go | 6487.17 | 6459.35–6502.08 | 1.000 | 1.000–1.000 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | zig-safe | 7360.62 | 7327.13–7410.44 | 1.137 | 1.134–1.138 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | zig-fast | 3244.13 | 3219.68–3329.91 | 0.501 | 0.499–0.503 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | my-llvm | 154.81 | 153.58–156.25 | 1.460 | 1.447–1.467 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | my-qbe | 726.29 | 724.20–729.95 | 6.844 | 6.805–6.858 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | rust | 71.46 | 70.95–72.23 | 0.672 | 0.668–0.679 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | go | 106.29 | 105.14–107.43 | 1.000 | 1.000–1.000 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | zig-safe | 128.78 | 127.34–129.80 | 1.210 | 1.207–1.220 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | zig-fast | 71.54 | 71.06–71.83 | 0.673 | 0.669–0.679 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | my-llvm | 10382.51 | 10291.66–10538.15 | 1.299 | 1.293–1.306 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | my-qbe | 46189.62 | 46072.69–46306.75 | 5.787 | 5.779–5.801 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | rust | 4653.78 | 4624.08–4699.38 | 0.581 | 0.580–0.586 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | go | 7977.43 | 7931.56–8043.35 | 1.000 | 1.000–1.000 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | zig-safe | 8778.94 | 8701.57–8817.61 | 1.099 | 1.095–1.102 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | zig-fast | 4674.69 | 4658.92–4721.61 | 0.585 | 0.584–0.588 |
| record_construct / small | micro | one complete pass over SIZE fixtures | my-llvm | 263.02 | 261.58–274.43 | 1.774 | 1.768–1.778 |
| record_construct / small | micro | one complete pass over SIZE fixtures | my-qbe | 1036.74 | 1034.06–1061.85 | 6.988 | 6.972–6.994 |
| record_construct / small | micro | one complete pass over SIZE fixtures | rust | 107.64 | 106.79–108.25 | 0.725 | 0.724–0.727 |
| record_construct / small | micro | one complete pass over SIZE fixtures | go | 148.51 | 147.55–148.75 | 1.000 | 1.000–1.000 |
| record_construct / small | micro | one complete pass over SIZE fixtures | zig-safe | 160.05 | 158.33–161.34 | 1.078 | 1.076–1.085 |
| record_construct / small | micro | one complete pass over SIZE fixtures | zig-fast | 136.66 | 134.97–141.74 | 0.919 | 0.916–0.923 |
| record_construct / large | micro | one complete pass over SIZE fixtures | my-llvm | 16260.14 | 16231.83–18955.63 | 1.791 | 1.790–1.793 |
| record_construct / large | micro | one complete pass over SIZE fixtures | my-qbe | 66409.32 | 65617.06–79054.22 | 7.278 | 7.246–7.370 |
| record_construct / large | micro | one complete pass over SIZE fixtures | rust | 6418.31 | 6317.03–8383.82 | 0.708 | 0.706–0.718 |
| record_construct / large | micro | one complete pass over SIZE fixtures | go | 9089.56 | 9047.25–10332.53 | 1.000 | 1.000–1.000 |
| record_construct / large | micro | one complete pass over SIZE fixtures | zig-safe | 9586.19 | 9521.10–11233.77 | 1.055 | 1.054–1.061 |
| record_construct / large | micro | one complete pass over SIZE fixtures | zig-fast | 8538.26 | 8299.86–8877.20 | 0.940 | 0.931–0.943 |
| record_update / small | micro | one complete pass over SIZE fixtures | my-llvm | 293.01 | 292.04–294.21 | 1.950 | 1.944–1.953 |
| record_update / small | micro | one complete pass over SIZE fixtures | my-qbe | 1512.65 | 1507.55–1531.64 | 10.071 | 10.048–10.125 |
| record_update / small | micro | one complete pass over SIZE fixtures | rust | 108.81 | 107.98–109.12 | 0.722 | 0.720–0.726 |
| record_update / small | micro | one complete pass over SIZE fixtures | go | 150.28 | 149.08–173.66 | 1.000 | 1.000–1.000 |
| record_update / small | micro | one complete pass over SIZE fixtures | zig-safe | 169.85 | 167.62–171.08 | 1.130 | 1.122–1.133 |
| record_update / small | micro | one complete pass over SIZE fixtures | zig-fast | 137.17 | 136.29–140.88 | 0.914 | 0.909–0.917 |
| record_update / large | micro | one complete pass over SIZE fixtures | my-llvm | 18148.82 | 18082.67–18523.36 | 1.973 | 1.964–1.977 |
| record_update / large | micro | one complete pass over SIZE fixtures | my-qbe | 96629.38 | 96377.05–97901.49 | 10.505 | 10.437–10.540 |
| record_update / large | micro | one complete pass over SIZE fixtures | rust | 6385.21 | 6325.51–6431.62 | 0.694 | 0.689–0.696 |
| record_update / large | micro | one complete pass over SIZE fixtures | go | 9200.07 | 9155.21–9320.88 | 1.000 | 1.000–1.000 |
| record_update / large | micro | one complete pass over SIZE fixtures | zig-safe | 10183.88 | 10109.56–10359.74 | 1.103 | 1.099–1.113 |
| record_update / large | micro | one complete pass over SIZE fixtures | zig-fast | 8510.52 | 8321.13–9364.47 | 0.927 | 0.914–0.935 |
| call_direct / small | micro | one complete pass over SIZE fixtures | my-llvm | 130.45 | 129.98–134.73 | 2.070 | 2.067–2.071 |
| call_direct / small | micro | one complete pass over SIZE fixtures | my-qbe | 738.97 | 734.83–746.92 | 11.720 | 11.694–11.755 |
| call_direct / small | micro | one complete pass over SIZE fixtures | rust | 43.64 | 43.36–43.81 | 0.692 | 0.690–0.693 |
| call_direct / small | micro | one complete pass over SIZE fixtures | go | 63.03 | 62.77–63.45 | 1.000 | 1.000–1.000 |
| call_direct / small | micro | one complete pass over SIZE fixtures | zig-safe | 61.25 | 60.79–61.53 | 0.970 | 0.969–0.974 |
| call_direct / small | micro | one complete pass over SIZE fixtures | zig-fast | 47.31 | 46.78–47.52 | 0.751 | 0.749–0.752 |
| call_direct / large | micro | one complete pass over SIZE fixtures | my-llvm | 7696.96 | 7681.81–7752.07 | 2.396 | 2.389–2.403 |
| call_direct / large | micro | one complete pass over SIZE fixtures | my-qbe | 46546.15 | 46471.27–47011.00 | 14.525 | 14.449–14.546 |
| call_direct / large | micro | one complete pass over SIZE fixtures | rust | 1912.43 | 1898.96–1927.07 | 0.595 | 0.594–0.598 |
| call_direct / large | micro | one complete pass over SIZE fixtures | go | 3212.54 | 3195.63–3229.86 | 1.000 | 1.000–1.000 |
| call_direct / large | micro | one complete pass over SIZE fixtures | zig-safe | 2860.28 | 2843.21–2875.21 | 0.892 | 0.888–0.893 |
| call_direct / large | micro | one complete pass over SIZE fixtures | zig-fast | 1915.68 | 1894.05–1926.44 | 0.595 | 0.595–0.599 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | my-llvm | 166.06 | 164.39–171.76 | 1.245 | 1.237–1.249 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | my-qbe | 755.32 | 751.62–778.87 | 5.667 | 5.643–5.685 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | rust | 112.59 | 111.78–115.66 | 0.844 | 0.842–0.850 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | go | 133.31 | 132.57–138.08 | 1.000 | 1.000–1.000 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | zig-safe | 158.97 | 158.04–180.48 | 1.190 | 1.189–1.197 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | zig-fast | 102.35 | 101.65–103.70 | 0.766 | 0.765–0.773 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | my-llvm | 10101.11 | 9759.97–10348.58 | 1.242 | 1.219–1.256 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | my-qbe | 47432.07 | 47224.25–47969.27 | 5.850 | 5.836–5.879 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | rust | 6818.84 | 6776.82–6973.40 | 0.843 | 0.838–0.845 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | go | 8130.98 | 7976.35–8197.19 | 1.000 | 1.000–1.000 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | zig-safe | 9617.97 | 9578.46–9694.66 | 1.183 | 1.175–1.190 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | zig-fast | 5964.50 | 5861.05–6020.39 | 0.734 | 0.728–0.737 |
| option_handle / small | micro | one complete pass over SIZE fixtures | my-llvm | 186.27 | 179.61–191.19 | 1.850 | 1.839–1.859 |
| option_handle / small | micro | one complete pass over SIZE fixtures | my-qbe | 1045.04 | 1036.65–1068.59 | 10.390 | 10.340–10.480 |
| option_handle / small | micro | one complete pass over SIZE fixtures | rust | 46.93 | 46.21–47.15 | 0.467 | 0.464–0.468 |
| option_handle / small | micro | one complete pass over SIZE fixtures | go | 100.55 | 100.19–101.71 | 1.000 | 1.000–1.000 |
| option_handle / small | micro | one complete pass over SIZE fixtures | zig-safe | 107.77 | 106.49–108.69 | 1.070 | 1.063–1.078 |
| option_handle / small | micro | one complete pass over SIZE fixtures | zig-fast | 83.11 | 81.18–83.43 | 0.825 | 0.825–0.827 |
| option_handle / large | micro | one complete pass over SIZE fixtures | my-llvm | 11887.65 | 11805.76–12487.11 | 1.933 | 1.914–1.942 |
| option_handle / large | micro | one complete pass over SIZE fixtures | my-qbe | 66335.72 | 66021.44–66990.92 | 10.756 | 10.590–10.796 |
| option_handle / large | micro | one complete pass over SIZE fixtures | rust | 2280.72 | 2252.81–2301.44 | 0.367 | 0.366–0.371 |
| option_handle / large | micro | one complete pass over SIZE fixtures | go | 6168.27 | 6113.38–6289.09 | 1.000 | 1.000–1.000 |
| option_handle / large | micro | one complete pass over SIZE fixtures | zig-safe | 6266.36 | 6202.59–6578.69 | 1.018 | 0.998–1.022 |
| option_handle / large | micro | one complete pass over SIZE fixtures | zig-fast | 4993.84 | 4943.86–5053.12 | 0.810 | 0.804–0.813 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | my-llvm | 238.35 | 237.27–248.66 | 1.857 | 1.850–1.862 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | my-qbe | 1093.45 | 1091.48–1106.37 | 8.518 | 8.493–8.531 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | rust | 61.15 | 60.55–61.65 | 0.476 | 0.473–0.478 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | go | 128.64 | 127.48–130.31 | 1.000 | 1.000–1.000 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | zig-safe | 108.20 | 106.78–109.75 | 0.845 | 0.835–0.851 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | zig-fast | 72.01 | 70.94–72.67 | 0.560 | 0.555–0.561 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | my-llvm | 14950.03 | 14905.58–15298.92 | 1.885 | 1.878–1.890 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | my-qbe | 69574.56 | 69398.19–70075.52 | 8.768 | 8.759–8.790 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | rust | 3312.89 | 3268.36–3349.12 | 0.417 | 0.414–0.420 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | go | 7936.10 | 7904.82–8011.89 | 1.000 | 1.000–1.000 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | zig-safe | 6807.22 | 6729.39–7517.79 | 0.858 | 0.852–0.861 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | zig-fast | 4910.07 | 4803.57–5066.66 | 0.619 | 0.613–0.624 |
| binary_search / small | micro | one complete pass over SIZE fixtures | my-llvm | 118.96 | 118.49–120.31 | 1.185 | 1.178–1.194 |
| binary_search / small | micro | one complete pass over SIZE fixtures | my-qbe | 651.69 | 647.74–660.90 | 6.488 | 6.446–6.536 |
| binary_search / small | micro | one complete pass over SIZE fixtures | rust | 51.68 | 51.12–52.19 | 0.512 | 0.510–0.518 |
| binary_search / small | micro | one complete pass over SIZE fixtures | go | 100.49 | 99.04–101.92 | 1.000 | 1.000–1.000 |
| binary_search / small | micro | one complete pass over SIZE fixtures | zig-safe | 78.24 | 77.27–79.13 | 0.778 | 0.775–0.782 |
| binary_search / small | micro | one complete pass over SIZE fixtures | zig-fast | 74.92 | 74.54–75.23 | 0.746 | 0.742–0.749 |
| binary_search / large | micro | one complete pass over SIZE fixtures | my-llvm | 2960.45 | 2947.37–2985.49 | 1.234 | 1.227–1.236 |
| binary_search / large | micro | one complete pass over SIZE fixtures | my-qbe | 25487.81 | 25292.80–25881.20 | 10.608 | 10.534–10.700 |
| binary_search / large | micro | one complete pass over SIZE fixtures | rust | 1465.05 | 1456.16–1472.10 | 0.610 | 0.606–0.613 |
| binary_search / large | micro | one complete pass over SIZE fixtures | go | 2408.32 | 2384.01–2430.82 | 1.000 | 1.000–1.000 |
| binary_search / large | micro | one complete pass over SIZE fixtures | zig-safe | 5192.90 | 5147.43–5220.23 | 2.159 | 2.148–2.166 |
| binary_search / large | micro | one complete pass over SIZE fixtures | zig-fast | 2005.37 | 1988.38–2022.16 | 0.835 | 0.828–0.839 |
| packet_decode / small | application | one complete pass over SIZE fixtures | my-llvm | 101.02 | 88.80–125.46 | 0.815 | 0.792–0.841 |
| packet_decode / small | application | one complete pass over SIZE fixtures | my-qbe | 510.56 | 436.48–646.30 | 4.108 | 3.919–4.188 |
| packet_decode / small | application | one complete pass over SIZE fixtures | rust | 50.90 | 44.80–66.86 | 0.415 | 0.409–0.425 |
| packet_decode / small | application | one complete pass over SIZE fixtures | go | 126.51 | 106.15–157.46 | 1.000 | 1.000–1.000 |
| packet_decode / small | application | one complete pass over SIZE fixtures | zig-safe | 88.12 | 73.99–112.29 | 0.702 | 0.665–0.713 |
| packet_decode / small | application | one complete pass over SIZE fixtures | zig-fast | 46.74 | 38.55–56.07 | 0.350 | 0.348–0.384 |
| packet_decode / large | application | one complete pass over SIZE fixtures | my-llvm | 1642.06 | 1564.22–1834.41 | 0.848 | 0.815–0.863 |
| packet_decode / large | application | one complete pass over SIZE fixtures | my-qbe | 8289.85 | 7554.03–9033.78 | 4.147 | 3.997–4.481 |
| packet_decode / large | application | one complete pass over SIZE fixtures | rust | 787.01 | 736.53–838.47 | 0.399 | 0.382–0.409 |
| packet_decode / large | application | one complete pass over SIZE fixtures | go | 1950.69 | 1827.11–2490.38 | 1.000 | 1.000–1.000 |
| packet_decode / large | application | one complete pass over SIZE fixtures | zig-safe | 1341.83 | 1219.49–1726.96 | 0.689 | 0.647–0.719 |
| packet_decode / large | application | one complete pass over SIZE fixtures | zig-fast | 657.97 | 638.67–693.76 | 0.336 | 0.323–0.347 |
| list_scan / small | micro | one complete SIZE-element dataset operation | my-llvm | 97.03 | 94.16–106.42 | 1.606 | 1.578–1.642 |
| list_scan / small | micro | one complete SIZE-element dataset operation | my-qbe | 276.33 | 266.04–305.04 | 4.592 | 4.309–4.705 |
| list_scan / small | micro | one complete SIZE-element dataset operation | rust | 48.48 | 45.61–55.94 | 0.797 | 0.764–0.846 |
| list_scan / small | micro | one complete SIZE-element dataset operation | go | 61.06 | 58.42–75.25 | 1.000 | 1.000–1.000 |
| list_scan / small | micro | one complete SIZE-element dataset operation | zig-safe | 81.49 | 78.30–92.00 | 1.334 | 1.301–1.360 |
| list_scan / small | micro | one complete SIZE-element dataset operation | zig-fast | 61.39 | 58.56–81.68 | 1.011 | 0.994–1.047 |
| list_scan / large | micro | one complete SIZE-element dataset operation | my-llvm | 4907.29 | 4580.82–5986.95 | 1.304 | 1.172–1.520 |
| list_scan / large | micro | one complete SIZE-element dataset operation | my-qbe | 14543.07 | 13662.59–16289.53 | 3.840 | 3.626–4.027 |
| list_scan / large | micro | one complete SIZE-element dataset operation | rust | 3168.30 | 2752.80–3754.72 | 0.822 | 0.804–0.837 |
| list_scan / large | micro | one complete SIZE-element dataset operation | go | 3787.34 | 3390.37–4644.62 | 1.000 | 1.000–1.000 |
| list_scan / large | micro | one complete SIZE-element dataset operation | zig-safe | 5583.68 | 4914.30–6766.74 | 1.441 | 1.373–1.534 |
| list_scan / large | micro | one complete SIZE-element dataset operation | zig-fast | 3832.29 | 3457.33–5069.70 | 1.038 | 1.002–1.157 |
| list_append / small | micro | one complete SIZE-element dataset operation | my-llvm | 387.73 | 375.73–396.28 | 1.517 | 1.499–1.563 |
| list_append / small | micro | one complete SIZE-element dataset operation | my-qbe | 740.91 | 709.61–807.09 | 2.932 | 2.884–2.957 |
| list_append / small | micro | one complete SIZE-element dataset operation | rust | 184.97 | 179.25–192.16 | 0.736 | 0.715–0.749 |
| list_append / small | micro | one complete SIZE-element dataset operation | go | 252.62 | 240.81–267.11 | 1.000 | 1.000–1.000 |
| list_append / small | micro | one complete SIZE-element dataset operation | zig-safe | 289.93 | 274.75–309.70 | 1.144 | 1.127–1.171 |
| list_append / small | micro | one complete SIZE-element dataset operation | zig-fast | 137.63 | 132.82–151.79 | 0.552 | 0.532–0.567 |
| list_append / large | micro | one complete SIZE-element dataset operation | my-llvm | 13829.90 | 13367.93–14154.15 | 1.205 | 1.182–1.216 |
| list_append / large | micro | one complete SIZE-element dataset operation | my-qbe | 30378.03 | 29721.81–31418.47 | 2.631 | 2.583–2.677 |
| list_append / large | micro | one complete SIZE-element dataset operation | rust | 6526.12 | 6272.48–7050.79 | 0.566 | 0.554–0.569 |
| list_append / large | micro | one complete SIZE-element dataset operation | go | 11507.34 | 11111.69–12960.20 | 1.000 | 1.000–1.000 |
| list_append / large | micro | one complete SIZE-element dataset operation | zig-safe | 12538.22 | 11996.83–13233.67 | 1.082 | 1.049–1.094 |
| list_append / large | micro | one complete SIZE-element dataset operation | zig-fast | 6252.46 | 5855.74–6384.04 | 0.535 | 0.528–0.549 |
| list_filter / small | micro | one complete SIZE-element dataset operation | my-llvm | 394.65 | 390.17–414.37 | 1.365 | 1.362–1.378 |
| list_filter / small | micro | one complete SIZE-element dataset operation | my-qbe | 767.66 | 760.83–794.60 | 2.646 | 2.640–2.672 |
| list_filter / small | micro | one complete SIZE-element dataset operation | rust | 166.87 | 165.01–175.09 | 0.578 | 0.575–0.580 |
| list_filter / small | micro | one complete SIZE-element dataset operation | go | 289.04 | 287.26–300.97 | 1.000 | 1.000–1.000 |
| list_filter / small | micro | one complete SIZE-element dataset operation | zig-safe | 215.34 | 212.74–227.07 | 0.742 | 0.740–0.745 |
| list_filter / small | micro | one complete SIZE-element dataset operation | zig-fast | 151.85 | 149.65–166.33 | 0.526 | 0.522–0.532 |
| list_filter / large | micro | one complete SIZE-element dataset operation | my-llvm | 13200.49 | 13127.76–13310.69 | 1.203 | 1.197–1.205 |
| list_filter / large | micro | one complete SIZE-element dataset operation | my-qbe | 32620.21 | 32374.31–33169.24 | 2.969 | 2.951–2.998 |
| list_filter / large | micro | one complete SIZE-element dataset operation | rust | 5617.80 | 5562.11–5960.63 | 0.512 | 0.510–0.515 |
| list_filter / large | micro | one complete SIZE-element dataset operation | go | 10973.08 | 10914.25–11205.72 | 1.000 | 1.000–1.000 |
| list_filter / large | micro | one complete SIZE-element dataset operation | zig-safe | 10153.29 | 10119.61–10279.99 | 0.925 | 0.923–0.931 |
| list_filter / large | micro | one complete SIZE-element dataset operation | zig-fast | 7292.77 | 7224.57–7550.93 | 0.663 | 0.659–0.670 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | my-llvm | 518.92 | 514.86–532.53 | 1.140 | 1.115–1.157 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | my-qbe | 835.39 | 824.15–865.49 | 1.836 | 1.782–1.880 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | rust | 623.23 | 611.80–646.03 | 1.361 | 1.333–1.385 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | go | 460.28 | 404.68–474.76 | 1.000 | 1.000–1.000 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | zig-safe | 492.04 | 486.51–497.07 | 1.080 | 1.053–1.095 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | zig-fast | 252.10 | 249.77–253.92 | 0.549 | 0.540–0.558 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | my-llvm | 52693.53 | 51817.61–54385.37 | 1.758 | 1.743–1.787 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | my-qbe | 77152.86 | 75766.50–77727.93 | 2.568 | 2.558–2.593 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | rust | 40688.17 | 40496.92–41290.00 | 1.365 | 1.350–1.379 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | go | 29844.55 | 29440.76–30535.07 | 1.000 | 1.000–1.000 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | zig-safe | 52287.57 | 51502.82–53163.80 | 1.749 | 1.735–1.770 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | zig-fast | 41244.55 | 40812.17–41918.63 | 1.377 | 1.375–1.398 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | my-llvm | 583.53 | 577.49–834.21 | 1.055 | 1.028–1.067 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | my-qbe | 1004.67 | 1001.45–1015.41 | 1.797 | 1.777–1.836 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | rust | 867.83 | 852.19–884.00 | 1.543 | 1.532–1.589 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | go | 559.19 | 538.14–570.79 | 1.000 | 1.000–1.000 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | zig-safe | 520.35 | 514.89–526.09 | 0.939 | 0.917–0.946 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | zig-fast | 390.64 | 387.49–397.36 | 0.696 | 0.688–0.711 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | my-llvm | 67611.92 | 66620.15–68518.42 | 1.676 | 1.664–1.702 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | my-qbe | 96110.97 | 95678.18–97774.80 | 2.391 | 2.384–2.407 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | rust | 58349.51 | 57471.24–66203.67 | 1.453 | 1.448–1.472 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | go | 40213.55 | 39521.16–40910.91 | 1.000 | 1.000–1.000 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | zig-safe | 62646.48 | 61703.61–63941.02 | 1.554 | 1.544–1.563 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | zig-fast | 49028.40 | 48087.55–49968.33 | 1.220 | 1.199–1.225 |
| dict_update / small | micro | one complete SIZE-element dataset operation | my-llvm | 15249.14 | 15137.22–15571.21 | 1.829 | 1.822–1.834 |
| dict_update / small | micro | one complete SIZE-element dataset operation | my-qbe | 21271.19 | 21104.89–21782.20 | 2.553 | 2.540–2.560 |
| dict_update / small | micro | one complete SIZE-element dataset operation | rust | 6096.23 | 6050.79–6229.93 | 0.731 | 0.727–0.734 |
| dict_update / small | micro | one complete SIZE-element dataset operation | go | 8354.00 | 8153.64–8634.72 | 1.000 | 1.000–1.000 |
| dict_update / small | micro | one complete SIZE-element dataset operation | zig-safe | 4963.52 | 4873.93–5157.78 | 0.595 | 0.592–0.598 |
| dict_update / small | micro | one complete SIZE-element dataset operation | zig-fast | 2480.91 | 2458.90–2611.55 | 0.298 | 0.295–0.299 |
| dict_update / large | micro | one complete SIZE-element dataset operation | my-llvm | 1146283.52 | 1138439.29–1175669.37 | 2.247 | 2.233–2.259 |
| dict_update / large | micro | one complete SIZE-element dataset operation | my-qbe | 1494704.43 | 1486699.19–1510602.23 | 2.920 | 2.893–2.941 |
| dict_update / large | micro | one complete SIZE-element dataset operation | rust | 465484.00 | 459779.55–475491.22 | 0.910 | 0.904–0.915 |
| dict_update / large | micro | one complete SIZE-element dataset operation | go | 510847.71 | 505808.71–528861.15 | 1.000 | 1.000–1.000 |
| dict_update / large | micro | one complete SIZE-element dataset operation | zig-safe | 600634.66 | 597671.03–619386.41 | 1.179 | 1.169–1.184 |
| dict_update / large | micro | one complete SIZE-element dataset operation | zig-fast | 434066.60 | 431970.89–440488.23 | 0.849 | 0.845–0.855 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | my-llvm | 14128.39 | 13958.48–14460.47 | 1.455 | 1.443–1.470 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | my-qbe | 18691.99 | 18549.23–19064.67 | 1.932 | 1.912–1.936 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | rust | 13520.71 | 13384.82–13973.51 | 1.391 | 1.385–1.407 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | go | 9718.82 | 9548.17–9776.35 | 1.000 | 1.000–1.000 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | zig-safe | 6500.96 | 6455.26–6886.65 | 0.672 | 0.666–0.675 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | zig-fast | 4946.87 | 4835.21–5147.64 | 0.510 | 0.503–0.522 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | my-llvm | 1134125.32 | 1128169.58–1141103.56 | 1.666 | 1.658–1.672 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | my-qbe | 1389167.20 | 1378903.17–1400186.96 | 2.041 | 2.036–2.049 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | rust | 1032946.66 | 979037.62–1051544.61 | 1.516 | 1.508–1.538 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | go | 680597.48 | 670265.21–688141.59 | 1.000 | 1.000–1.000 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | zig-safe | 828660.77 | 821010.18–841907.89 | 1.222 | 1.211–1.234 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | zig-fast | 724441.82 | 716417.24–732950.99 | 1.066 | 1.062–1.069 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | my-llvm | 3438.45 | 3408.39–3481.85 | 3.025 | 2.989–3.041 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | my-qbe | 4700.41 | 4659.68–5434.57 | 4.129 | 4.097–4.175 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | rust | 955.58 | 948.95–1010.89 | 0.843 | 0.837–0.846 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | go | 1138.04 | 1114.89–1184.99 | 1.000 | 1.000–1.000 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | zig-safe | 607.95 | 600.74–667.08 | 0.535 | 0.531–0.538 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | zig-fast | 288.90 | 286.68–344.89 | 0.254 | 0.253–0.257 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | my-llvm | 220853.28 | 218091.43–224600.66 | 3.212 | 3.185–3.231 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | my-qbe | 292050.62 | 290131.03–296362.98 | 4.246 | 4.217–4.261 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | rust | 61052.30 | 60324.83–62513.33 | 0.883 | 0.877–0.890 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | go | 68907.77 | 68465.69–70048.18 | 1.000 | 1.000–1.000 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | zig-safe | 79666.97 | 79370.51–82429.08 | 1.155 | 1.148–1.159 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | zig-fast | 55443.20 | 54990.54–55766.48 | 0.804 | 0.797–0.805 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | my-llvm | 4538.86 | 4502.50–5064.88 | 31.346 | 31.187–31.619 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | my-qbe | 6052.98 | 6002.20–6131.19 | 41.825 | 41.531–42.238 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | rust | 78.14 | 75.78–84.52 | 0.544 | 0.534–0.554 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | go | 144.84 | 141.43–147.70 | 1.000 | 1.000–1.000 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | zig-safe | 332.75 | 328.38–340.08 | 2.289 | 2.285–2.338 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | zig-fast | 3.74 | 3.53–4.13 | 0.026 | 0.025–0.026 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | my-llvm | 70329.89 | 70026.28–70953.21 | 36.430 | 36.152–36.911 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | my-qbe | 94313.39 | 93663.12–97297.73 | 48.808 | 48.451–49.571 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | rust | 1192.88 | 1147.82–1225.76 | 0.617 | 0.601–0.624 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | go | 1933.49 | 1873.82–1974.00 | 1.000 | 1.000–1.000 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | zig-safe | 5192.66 | 5155.87–5281.32 | 2.683 | 2.675–2.741 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | zig-fast | 3.72 | 3.69–4.69 | 0.002 | 0.002–0.002 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | my-llvm | 2823.54 | 2783.43–2858.56 | 1.561 | 1.550–1.568 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | my-qbe | 4248.90 | 4211.02–4335.93 | 2.343 | 2.331–2.359 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | rust | 1290.24 | 1269.38–1309.69 | 0.712 | 0.710–0.716 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | go | 1812.93 | 1789.86–1822.73 | 1.000 | 1.000–1.000 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | zig-safe | 1245.98 | 1225.77–1316.11 | 0.689 | 0.685–0.700 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | zig-fast | 1207.44 | 1193.84–1277.19 | 0.667 | 0.665–0.672 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | my-llvm | 44919.34 | 44505.05–45355.08 | 1.767 | 1.753–1.775 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | my-qbe | 65667.29 | 65038.70–66559.27 | 2.580 | 2.561–2.589 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | rust | 20588.48 | 20351.04–21206.32 | 0.807 | 0.801–0.819 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | go | 25445.85 | 25174.42–25854.38 | 1.000 | 1.000–1.000 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | zig-safe | 20442.67 | 19990.48–20915.71 | 0.801 | 0.794–0.803 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | zig-fast | 19669.60 | 19474.23–20275.38 | 0.774 | 0.766–0.780 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | my-llvm | 746.95 | 743.76–767.03 | 0.644 | 0.643–0.646 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | my-qbe | 870.35 | 865.07–880.13 | 0.750 | 0.747–0.755 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | rust | 1173.34 | 1160.04–1216.41 | 1.012 | 1.008–1.015 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | go | 1160.25 | 1143.61–1190.17 | 1.000 | 1.000–1.000 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | zig-safe | 1187.67 | 1173.51–1260.87 | 1.024 | 1.020–1.037 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | zig-fast | 1097.47 | 1066.19–1177.01 | 0.945 | 0.934–0.976 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | my-llvm | 7131.86 | 7047.16–7212.60 | 0.410 | 0.407–0.414 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | my-qbe | 8423.61 | 8272.39–8596.65 | 0.483 | 0.482–0.491 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | rust | 20093.75 | 19711.18–20948.22 | 1.155 | 1.146–1.161 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | go | 17374.17 | 17204.73–17915.33 | 1.000 | 1.000–1.000 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | zig-safe | 19898.72 | 19705.41–20285.18 | 1.142 | 1.138–1.152 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | zig-fast | 18171.50 | 17941.11–18718.54 | 1.050 | 1.043–1.052 |
| sort_int / small | micro | one complete SIZE-element dataset operation | my-llvm | 278.55 | 277.65–280.96 | 0.262 | 0.262–0.262 |
| sort_int / small | micro | one complete SIZE-element dataset operation | my-qbe | 535.17 | 532.11–539.26 | 0.503 | 0.502–0.506 |
| sort_int / small | micro | one complete SIZE-element dataset operation | rust | 226.09 | 224.13–232.66 | 0.213 | 0.212–0.213 |
| sort_int / small | micro | one complete SIZE-element dataset operation | go | 1064.55 | 1058.13–1069.04 | 1.000 | 1.000–1.000 |
| sort_int / small | micro | one complete SIZE-element dataset operation | zig-safe | 268.39 | 267.13–269.50 | 0.252 | 0.251–0.253 |
| sort_int / small | micro | one complete SIZE-element dataset operation | zig-fast | 168.41 | 162.71–171.26 | 0.158 | 0.157–0.160 |
| sort_int / large | micro | one complete SIZE-element dataset operation | my-llvm | 44236.10 | 43981.02–44599.01 | 0.190 | 0.189–0.191 |
| sort_int / large | micro | one complete SIZE-element dataset operation | my-qbe | 56625.58 | 56394.65–56951.89 | 0.243 | 0.243–0.244 |
| sort_int / large | micro | one complete SIZE-element dataset operation | rust | 63128.70 | 62973.01–63389.69 | 0.272 | 0.271–0.272 |
| sort_int / large | micro | one complete SIZE-element dataset operation | go | 232509.96 | 231934.77–234672.32 | 1.000 | 1.000–1.000 |
| sort_int / large | micro | one complete SIZE-element dataset operation | zig-safe | 64987.21 | 64281.15–65681.91 | 0.279 | 0.278–0.280 |
| sort_int / large | micro | one complete SIZE-element dataset operation | zig-fast | 44883.90 | 44521.50–45229.92 | 0.193 | 0.191–0.194 |
| sort_records / small | micro | one complete SIZE-element dataset operation | my-llvm | 1201.03 | 1193.47–1229.87 | 0.165 | 0.164–0.165 |
| sort_records / small | micro | one complete SIZE-element dataset operation | my-qbe | 1936.48 | 1928.15–2049.76 | 0.266 | 0.266–0.268 |
| sort_records / small | micro | one complete SIZE-element dataset operation | rust | 662.67 | 659.67–691.89 | 0.091 | 0.091–0.091 |
| sort_records / small | micro | one complete SIZE-element dataset operation | go | 7276.27 | 7243.40–7308.13 | 1.000 | 1.000–1.000 |
| sort_records / small | micro | one complete SIZE-element dataset operation | zig-safe | 783.53 | 777.36–809.96 | 0.108 | 0.107–0.108 |
| sort_records / small | micro | one complete SIZE-element dataset operation | zig-fast | 562.82 | 555.69–582.48 | 0.077 | 0.077–0.079 |
| sort_records / large | micro | one complete SIZE-element dataset operation | my-llvm | 61564.99 | 60782.52–62203.75 | 0.049 | 0.049–0.049 |
| sort_records / large | micro | one complete SIZE-element dataset operation | my-qbe | 99196.71 | 98441.36–99801.03 | 0.079 | 0.079–0.079 |
| sort_records / large | micro | one complete SIZE-element dataset operation | rust | 51816.16 | 50606.99–52428.66 | 0.041 | 0.041–0.041 |
| sort_records / large | micro | one complete SIZE-element dataset operation | go | 1259208.02 | 1250843.82–1274320.16 | 1.000 | 1.000–1.000 |
| sort_records / large | micro | one complete SIZE-element dataset operation | zig-safe | 115154.03 | 114564.14–118119.43 | 0.091 | 0.091–0.092 |
| sort_records / large | micro | one complete SIZE-element dataset operation | zig-fast | 92222.97 | 91257.04–93724.40 | 0.073 | 0.073–0.073 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 5022.59 | 5000.79–5117.62 | 6.195 | 6.081–6.237 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 5622.22 | 5581.53–5676.23 | 6.912 | 6.831–6.964 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | rust | 717.45 | 709.75–733.11 | 0.881 | 0.878–0.896 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | go | 811.82 | 805.46–832.60 | 1.000 | 1.000–1.000 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 1979.16 | 1962.69–2137.21 | 2.434 | 2.408–2.463 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 1920.33 | 1915.80–1941.17 | 2.373 | 2.357–2.382 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 75793.71 | 75370.10–81777.05 | 6.018 | 5.916–6.031 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 82979.43 | 82499.58–85337.01 | 6.552 | 6.496–6.594 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | rust | 10663.96 | 10558.43–11198.93 | 0.840 | 0.833–0.848 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | go | 12636.01 | 12524.79–13347.81 | 1.000 | 1.000–1.000 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 30532.54 | 30204.24–34114.99 | 2.416 | 2.386–2.432 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 29790.07 | 29427.32–33176.44 | 2.347 | 2.334–2.369 |
| bytes_scan / small | micro | one full byte-buffer scan | my-llvm | 8.58 | 8.49–8.84 | 0.362 | 0.351–0.366 |
| bytes_scan / small | micro | one full byte-buffer scan | my-qbe | 67.10 | 66.45–67.85 | 2.824 | 2.729–2.966 |
| bytes_scan / small | micro | one full byte-buffer scan | rust | 17.68 | 17.49–17.80 | 0.745 | 0.734–0.757 |
| bytes_scan / small | micro | one full byte-buffer scan | go | 23.80 | 22.45–25.87 | 1.000 | 1.000–1.000 |
| bytes_scan / small | micro | one full byte-buffer scan | zig-safe | 27.82 | 26.51–28.62 | 1.150 | 1.127–1.194 |
| bytes_scan / small | micro | one full byte-buffer scan | zig-fast | 12.12 | 11.87–12.71 | 0.507 | 0.495–0.539 |
| bytes_scan / large | micro | one full byte-buffer scan | my-llvm | 354.32 | 352.11–359.73 | 0.348 | 0.346–0.352 |
| bytes_scan / large | micro | one full byte-buffer scan | my-qbe | 3365.65 | 3349.29–3404.75 | 3.339 | 3.287–3.391 |
| bytes_scan / large | micro | one full byte-buffer scan | rust | 1062.59 | 1059.03–1070.59 | 1.047 | 1.043–1.061 |
| bytes_scan / large | micro | one full byte-buffer scan | go | 1015.55 | 983.39–1044.00 | 1.000 | 1.000–1.000 |
| bytes_scan / large | micro | one full byte-buffer scan | zig-safe | 1332.79 | 1301.82–1449.41 | 1.322 | 1.320–1.368 |
| bytes_scan / large | micro | one full byte-buffer scan | zig-fast | 701.50 | 694.14–724.75 | 0.694 | 0.688–0.700 |
| string_equal / small | micro | one string equality comparison | my-llvm | 15.97 | 15.82–17.23 | 3.553 | 3.459–3.565 |
| string_equal / small | micro | one string equality comparison | my-qbe | 36.16 | 35.81–36.47 | 7.934 | 7.777–8.070 |
| string_equal / small | micro | one string equality comparison | rust | 3.01 | 2.98–3.18 | 0.666 | 0.652–0.672 |
| string_equal / small | micro | one string equality comparison | go | 4.54 | 4.45–4.88 | 1.000 | 1.000–1.000 |
| string_equal / small | micro | one string equality comparison | zig-safe | 4.10 | 4.08–4.16 | 0.907 | 0.889–0.914 |
| string_equal / small | micro | one string equality comparison | zig-fast | 3.83 | 3.81–3.89 | 0.843 | 0.824–0.854 |
| string_equal / large | micro | one string equality comparison | my-llvm | 44.74 | 44.15–45.69 | 1.191 | 1.166–1.204 |
| string_equal / large | micro | one string equality comparison | my-qbe | 719.65 | 718.26–723.89 | 19.087 | 19.014–19.339 |
| string_equal / large | micro | one string equality comparison | rust | 30.93 | 30.66–32.73 | 0.821 | 0.810–0.831 |
| string_equal / large | micro | one string equality comparison | go | 37.66 | 36.92–38.55 | 1.000 | 1.000–1.000 |
| string_equal / large | micro | one string equality comparison | zig-safe | 65.01 | 64.71–65.11 | 1.724 | 1.704–1.737 |
| string_equal / large | micro | one string equality comparison | zig-fast | 50.50 | 50.20–56.74 | 1.342 | 1.321–1.348 |
| string_search / small | micro | one substring search | my-llvm | 19.87 | 19.75–20.53 | 0.802 | 0.796–0.807 |
| string_search / small | micro | one substring search | my-qbe | 30.44 | 30.33–30.99 | 1.228 | 1.224–1.236 |
| string_search / small | micro | one substring search | rust | 42.95 | 42.55–43.37 | 1.733 | 1.720–1.741 |
| string_search / small | micro | one substring search | go | 24.88 | 24.50–25.24 | 1.000 | 1.000–1.000 |
| string_search / small | micro | one substring search | zig-safe | 89.75 | 89.53–90.17 | 3.616 | 3.599–3.625 |
| string_search / small | micro | one substring search | zig-fast | 74.84 | 74.55–78.40 | 3.025 | 3.002–3.043 |
| string_search / large | micro | one substring search | my-llvm | 102.40 | 101.34–104.50 | 0.158 | 0.158–0.159 |
| string_search / large | micro | one substring search | my-qbe | 98.39 | 97.23–99.39 | 0.153 | 0.152–0.154 |
| string_search / large | micro | one substring search | rust | 1297.97 | 1293.86–1311.77 | 2.012 | 2.009–2.015 |
| string_search / large | micro | one substring search | go | 644.75 | 642.03–662.55 | 1.000 | 1.000–1.000 |
| string_search / large | micro | one substring search | zig-safe | 2986.39 | 2980.33–3555.60 | 4.633 | 4.631–4.644 |
| string_search / large | micro | one substring search | zig-fast | 2635.36 | 2628.28–2663.32 | 4.091 | 4.085–4.097 |
| string_split / small | micro | one full document split and result fold | my-llvm | 3562.90 | 3533.59–3755.09 | 3.430 | 3.402–3.481 |
| string_split / small | micro | one full document split and result fold | my-qbe | 4414.83 | 4382.32–4529.58 | 4.234 | 4.215–4.260 |
| string_split / small | micro | one full document split and result fold | rust | 551.93 | 545.46–580.98 | 0.531 | 0.525–0.540 |
| string_split / small | micro | one full document split and result fold | go | 1039.33 | 1033.96–1062.96 | 1.000 | 1.000–1.000 |
| string_split / small | micro | one full document split and result fold | zig-safe | 1035.45 | 1024.85–1088.77 | 0.998 | 0.989–0.999 |
| string_split / small | micro | one full document split and result fold | zig-fast | 959.94 | 953.56–969.21 | 0.921 | 0.917–0.928 |
| string_split / large | micro | one full document split and result fold | my-llvm | 217421.57 | 214577.44–221929.67 | 3.263 | 3.258–3.295 |
| string_split / large | micro | one full document split and result fold | my-qbe | 266544.70 | 263378.54–269355.93 | 4.019 | 4.000–4.023 |
| string_split / large | micro | one full document split and result fold | rust | 27847.01 | 27480.37–28498.83 | 0.421 | 0.419–0.425 |
| string_split / large | micro | one full document split and result fold | go | 66274.38 | 65799.09–68678.66 | 1.000 | 1.000–1.000 |
| string_split / large | micro | one full document split and result fold | zig-safe | 62281.81 | 61552.98–65371.67 | 0.940 | 0.937–0.942 |
| string_split / large | micro | one full document split and result fold | zig-fast | 58462.59 | 58194.32–60331.77 | 0.882 | 0.880–0.885 |
| string_join / small | micro | one full fragment join and output fold | my-llvm | 422.32 | 419.78–436.48 | 1.040 | 1.032–1.045 |
| string_join / small | micro | one full fragment join and output fold | my-qbe | 556.33 | 553.53–566.57 | 1.367 | 1.363–1.372 |
| string_join / small | micro | one full fragment join and output fold | rust | 220.15 | 218.38–230.50 | 0.543 | 0.540–0.545 |
| string_join / small | micro | one full fragment join and output fold | go | 407.55 | 402.78–416.69 | 1.000 | 1.000–1.000 |
| string_join / small | micro | one full fragment join and output fold | zig-safe | 313.70 | 309.89–333.32 | 0.773 | 0.766–0.779 |
| string_join / small | micro | one full fragment join and output fold | zig-fast | 270.47 | 267.17–280.16 | 0.664 | 0.659–0.674 |
| string_join / large | micro | one full fragment join and output fold | my-llvm | 23537.18 | 23331.55–23738.13 | 0.917 | 0.912–0.919 |
| string_join / large | micro | one full fragment join and output fold | my-qbe | 28673.11 | 28304.80–29174.27 | 1.115 | 1.109–1.119 |
| string_join / large | micro | one full fragment join and output fold | rust | 13428.39 | 13298.06–13556.59 | 0.521 | 0.518–0.526 |
| string_join / large | micro | one full fragment join and output fold | go | 25722.85 | 25424.16–26095.76 | 1.000 | 1.000–1.000 |
| string_join / large | micro | one full fragment join and output fold | zig-safe | 17940.31 | 17716.94–18315.58 | 0.695 | 0.691–0.699 |
| string_join / large | micro | one full fragment join and output fold | zig-fast | 16667.21 | 16475.51–16982.00 | 0.647 | 0.644–0.652 |
| int_parse / small | micro | one strict signed decimal parse | my-llvm | 10.07 | 10.01–10.44 | 0.419 | 0.417–0.425 |
| int_parse / small | micro | one strict signed decimal parse | my-qbe | 17.95 | 17.73–18.25 | 0.748 | 0.745–0.751 |
| int_parse / small | micro | one strict signed decimal parse | rust | 4.48 | 4.46–4.56 | 0.186 | 0.186–0.187 |
| int_parse / small | micro | one strict signed decimal parse | go | 24.02 | 23.74–24.16 | 1.000 | 1.000–1.000 |
| int_parse / small | micro | one strict signed decimal parse | zig-safe | 5.73 | 5.70–5.82 | 0.239 | 0.238–0.240 |
| int_parse / small | micro | one strict signed decimal parse | zig-fast | 5.72 | 5.68–5.78 | 0.238 | 0.238–0.239 |
| int_parse / large | micro | one strict signed decimal parse | my-llvm | 10.59 | 10.54–10.99 | 0.392 | 0.389–0.394 |
| int_parse / large | micro | one strict signed decimal parse | my-qbe | 18.78 | 18.61–19.66 | 0.694 | 0.691–0.696 |
| int_parse / large | micro | one strict signed decimal parse | rust | 5.06 | 5.04–5.09 | 0.187 | 0.187–0.187 |
| int_parse / large | micro | one strict signed decimal parse | go | 27.07 | 26.97–27.26 | 1.000 | 1.000–1.000 |
| int_parse / large | micro | one strict signed decimal parse | zig-safe | 6.74 | 6.70–6.77 | 0.249 | 0.248–0.249 |
| int_parse / large | micro | one strict signed decimal parse | zig-fast | 6.24 | 6.18–6.35 | 0.230 | 0.229–0.231 |
| int_format / small | micro | one signed decimal formatting and output fold | my-llvm | 63.62 | 63.19–65.41 | 3.901 | 3.882–3.946 |
| int_format / small | micro | one signed decimal formatting and output fold | my-qbe | 88.84 | 88.29–89.30 | 5.458 | 5.446–5.484 |
| int_format / small | micro | one signed decimal formatting and output fold | rust | 14.51 | 14.41–14.94 | 0.893 | 0.889–0.909 |
| int_format / small | micro | one signed decimal formatting and output fold | go | 16.28 | 16.10–16.39 | 1.000 | 1.000–1.000 |
| int_format / small | micro | one signed decimal formatting and output fold | zig-safe | 40.28 | 39.87–41.02 | 2.478 | 2.458–2.494 |
| int_format / small | micro | one signed decimal formatting and output fold | zig-fast | 32.45 | 32.26–32.96 | 1.997 | 1.994–2.004 |
| int_format / large | micro | one signed decimal formatting and output fold | my-llvm | 70.02 | 69.66–70.32 | 3.979 | 3.947–3.991 |
| int_format / large | micro | one signed decimal formatting and output fold | my-qbe | 91.21 | 90.81–91.69 | 5.177 | 5.155–5.211 |
| int_format / large | micro | one signed decimal formatting and output fold | rust | 15.18 | 15.00–15.76 | 0.865 | 0.854–0.892 |
| int_format / large | micro | one signed decimal formatting and output fold | go | 17.59 | 17.37–17.93 | 1.000 | 1.000–1.000 |
| int_format / large | micro | one signed decimal formatting and output fold | zig-safe | 42.83 | 42.26–44.62 | 2.429 | 2.407–2.438 |
| int_format / large | micro | one signed decimal formatting and output fold | zig-fast | 36.05 | 35.87–36.36 | 2.046 | 2.034–2.060 |
| word_count / small | application | one complete tokenize/count/fold job | my-llvm | 2278.09 | 2263.25–2350.58 | 3.540 | 3.530–3.576 |
| word_count / small | application | one complete tokenize/count/fold job | my-qbe | 3037.65 | 3028.52–3065.57 | 4.738 | 4.711–4.747 |
| word_count / small | application | one complete tokenize/count/fold job | rust | 346.40 | 343.40–374.67 | 0.538 | 0.535–0.540 |
| word_count / small | application | one complete tokenize/count/fold job | go | 643.52 | 639.26–660.43 | 1.000 | 1.000–1.000 |
| word_count / small | application | one complete tokenize/count/fold job | zig-safe | 245.15 | 242.59–248.62 | 0.381 | 0.379–0.382 |
| word_count / small | application | one complete tokenize/count/fold job | zig-fast | 190.17 | 188.81–194.55 | 0.295 | 0.294–0.298 |
| word_count / large | application | one complete tokenize/count/fold job | my-llvm | 21140.24 | 20923.47–21799.66 | 2.116 | 2.104–2.125 |
| word_count / large | application | one complete tokenize/count/fold job | my-qbe | 28543.35 | 28348.16–29819.49 | 2.864 | 2.853–2.873 |
| word_count / large | application | one complete tokenize/count/fold job | rust | 3892.37 | 3859.01–3983.23 | 0.391 | 0.389–0.392 |
| word_count / large | application | one complete tokenize/count/fold job | go | 9959.34 | 9914.09–10512.23 | 1.000 | 1.000–1.000 |
| word_count / large | application | one complete tokenize/count/fold job | zig-safe | 3128.60 | 3087.29–3231.16 | 0.314 | 0.313–0.316 |
| word_count / large | application | one complete tokenize/count/fold job | zig-fast | 2469.50 | 2453.29–2547.72 | 0.247 | 0.246–0.248 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | my-llvm | 24019.81 | 23484.36–24230.99 | 4.470 | 4.412–4.486 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | my-qbe | 35183.81 | 34656.58–35904.68 | 6.558 | 6.509–6.589 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | rust | 4204.21 | 4130.65–4372.59 | 0.784 | 0.780–0.787 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | go | 5351.72 | 5239.25–5582.42 | 1.000 | 1.000–1.000 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | zig-safe | 3839.36 | 3757.61–4422.69 | 0.715 | 0.709–0.724 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | zig-fast | 3036.26 | 2979.41–3080.42 | 0.565 | 0.561–0.570 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | my-llvm | 396748.55 | 391280.00–399291.95 | 4.791 | 4.772–4.842 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | my-qbe | 577140.20 | 572226.62–593017.81 | 6.981 | 6.935–7.038 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | rust | 68713.25 | 67705.66–74294.23 | 0.837 | 0.826–0.841 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | go | 82811.63 | 81161.95–88679.55 | 1.000 | 1.000–1.000 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | zig-safe | 66520.10 | 65403.27–77668.63 | 0.806 | 0.795–0.811 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | zig-fast | 53305.73 | 52679.35–59815.16 | 0.645 | 0.641–0.650 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 161419.80 | 160060.45–178912.92 | 5.291 | 5.276–5.332 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 217201.11 | 213343.11–243647.01 | 7.101 | 7.052–7.235 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 7143.20 | 6845.36–7832.95 | 0.231 | 0.226–0.234 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | go | 30515.26 | 30151.00–34690.37 | 1.000 | 1.000–1.000 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 11923.69 | 11615.60–13987.79 | 0.385 | 0.383–0.389 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 8453.00 | 8252.69–9208.67 | 0.274 | 0.273–0.279 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 3091019.63 | 2750473.23–3235734.50 | 5.542 | 5.513–5.684 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 4157303.95 | 3627747.50–4319852.45 | 7.399 | 7.266–7.599 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 124233.98 | 112671.82–135836.06 | 0.231 | 0.229–0.233 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | go | 543441.42 | 479191.05–583816.75 | 1.000 | 1.000–1.000 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 230414.43 | 212943.20–258728.19 | 0.440 | 0.432–0.447 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 187251.47 | 168927.87–204138.00 | 0.347 | 0.339–0.349 |

Calibration limits: record_reads/small (iteration_cap), record_reads/large (iteration_cap), mutate_unique/small (iteration_cap), mutate_unique/large (iteration_cap), integer_math/large (slowest_arm_budget), branch_mixed/small (slowest_arm_budget), record_construct/large (slowest_arm_budget), call_direct/large (slowest_arm_budget), call_indirect/small (slowest_arm_budget), option_handle/small (slowest_arm_budget), option_handle/large (slowest_arm_budget), result_propagate/large (slowest_arm_budget), list_scan/large (slowest_arm_budget), list_filter/small (slowest_arm_budget), dict_lookup/large (slowest_arm_budget), dict_lookup_str/large (slowest_arm_budget), dict_update/small (slowest_arm_budget), dict_update/large (slowest_arm_budget), dict_update_str/small (slowest_arm_budget), dict_update_str/large (slowest_arm_budget), set_dedup/small (slowest_arm_budget), alloc_short/small (slowest_arm_budget), alloc_short/large (slowest_arm_budget), alloc_retained/small (slowest_arm_budget), sort_int/large (slowest_arm_budget), sort_records/large (slowest_arm_budget), bytes_scan/large (slowest_arm_budget), string_equal/small (iteration_cap), string_equal/large (pilot_limit), string_search/large (slowest_arm_budget), string_split/large (slowest_arm_budget), int_parse/small (iteration_cap), int_parse/large (slowest_arm_budget), int_format/small (slowest_arm_budget), int_format/large (slowest_arm_budget), json_transform/small (slowest_arm_budget), json_transform/large (slowest_arm_budget).

Per-core activity: {"2": 99.183996956632, "3": 0.5110819064307437}.
Governor: powersave.
Sibling reservation is operator-managed; busy counters record average load and cannot exclude short interference.

Operation inventory coverage does not establish 80% of everyday CPU time. Separate application profiles are required.
