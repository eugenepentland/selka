Expanded runtime benchmark: **complete**.

40 cases; 15 measured rounds; 3 warmups; 7200 measured samples across all six configurations.

Optimized default build policies; instruction sets are not matched across arms. No forced target tuning or disabled MyLang checks.

Times below are **ns per CLI iteration**, not necessarily per element. See the unit column and contracts. Application and native-library workloads include their documented algorithms. Ratios are medians of paired rounds against Go; 95% intervals use 2,000 bootstrap resamples. No aggregate ranking pools different workloads.

| Case / profile | Level | Unit | Arm | Median ns/iteration | Min–max | Ratio to Go | 95% interval |
|---|---|---|---|---:|---:|---:|---:|
| record_reads / small | micro | one contract operation | my-llvm | 5.84 | 5.48–6.18 | 1.204 | 1.177–1.224 |
| record_reads / small | micro | one contract operation | my-qbe | 13.47 | 13.24–13.74 | 2.785 | 2.700–2.827 |
| record_reads / small | micro | one contract operation | rust | 4.00 | 3.91–4.30 | 0.829 | 0.802–0.872 |
| record_reads / small | micro | one contract operation | go | 4.83 | 4.61–5.15 | 1.000 | 1.000–1.000 |
| record_reads / small | micro | one contract operation | zig-safe | 5.49 | 5.38–6.04 | 1.143 | 1.117–1.168 |
| record_reads / small | micro | one contract operation | zig-fast | 5.09 | 4.92–5.47 | 1.045 | 1.026–1.083 |
| record_reads / large | micro | one contract operation | my-llvm | 6.45 | 6.18–8.17 | 1.252 | 1.201–1.291 |
| record_reads / large | micro | one contract operation | my-qbe | 16.55 | 15.65–18.81 | 3.160 | 2.991–3.245 |
| record_reads / large | micro | one contract operation | rust | 4.57 | 3.99–5.61 | 0.851 | 0.834–0.905 |
| record_reads / large | micro | one contract operation | go | 5.13 | 4.86–6.70 | 1.000 | 1.000–1.000 |
| record_reads / large | micro | one contract operation | zig-safe | 6.06 | 5.54–7.92 | 1.156 | 1.138–1.188 |
| record_reads / large | micro | one contract operation | zig-fast | 5.55 | 5.06–7.01 | 1.052 | 1.029–1.095 |
| tagged_stack / small | micro | one contract operation | my-llvm | 19.45 | 18.93–29.05 | 2.924 | 2.791–2.998 |
| tagged_stack / small | micro | one contract operation | my-qbe | 25.84 | 25.18–28.65 | 3.947 | 3.648–4.040 |
| tagged_stack / small | micro | one contract operation | rust | 6.44 | 5.78–7.17 | 0.971 | 0.899–1.011 |
| tagged_stack / small | micro | one contract operation | go | 6.61 | 6.24–7.39 | 1.000 | 1.000–1.000 |
| tagged_stack / small | micro | one contract operation | zig-safe | 12.03 | 11.32–12.80 | 1.791 | 1.769–1.872 |
| tagged_stack / small | micro | one contract operation | zig-fast | 12.25 | 11.38–17.68 | 1.808 | 1.721–1.963 |
| tagged_stack / large | micro | one contract operation | my-llvm | 22.99 | 18.31–28.77 | 2.783 | 2.752–2.909 |
| tagged_stack / large | micro | one contract operation | my-qbe | 27.43 | 24.67–29.93 | 3.431 | 3.384–3.805 |
| tagged_stack / large | micro | one contract operation | rust | 7.60 | 5.96–8.43 | 0.940 | 0.914–0.972 |
| tagged_stack / large | micro | one contract operation | go | 8.29 | 6.39–9.04 | 1.000 | 1.000–1.000 |
| tagged_stack / large | micro | one contract operation | zig-safe | 14.03 | 11.19–17.11 | 1.755 | 1.731–1.830 |
| tagged_stack / large | micro | one contract operation | zig-fast | 14.05 | 12.28–15.64 | 1.752 | 1.679–1.773 |
| mutate_unique / small | micro | one contract operation | my-llvm | 5.16 | 4.87–6.27 | 1.342 | 1.273–1.388 |
| mutate_unique / small | micro | one contract operation | my-qbe | 25.02 | 24.52–29.86 | 6.429 | 6.288–6.882 |
| mutate_unique / small | micro | one contract operation | rust | 3.28 | 3.03–4.28 | 0.856 | 0.814–0.863 |
| mutate_unique / small | micro | one contract operation | go | 3.87 | 3.57–4.69 | 1.000 | 1.000–1.000 |
| mutate_unique / small | micro | one contract operation | zig-safe | 4.03 | 3.82–5.27 | 1.075 | 1.049–1.117 |
| mutate_unique / small | micro | one contract operation | zig-fast | 3.96 | 3.61–4.98 | 1.033 | 1.008–1.064 |
| mutate_unique / large | micro | one contract operation | my-llvm | 5.07 | 4.93–6.36 | 1.295 | 1.291–1.351 |
| mutate_unique / large | micro | one contract operation | my-qbe | 23.97 | 23.48–28.10 | 6.083 | 5.954–6.327 |
| mutate_unique / large | micro | one contract operation | rust | 3.44 | 3.13–4.16 | 0.849 | 0.825–0.896 |
| mutate_unique / large | micro | one contract operation | go | 3.95 | 3.74–4.76 | 1.000 | 1.000–1.000 |
| mutate_unique / large | micro | one contract operation | zig-safe | 4.48 | 4.12–5.11 | 1.111 | 1.069–1.131 |
| mutate_unique / large | micro | one contract operation | zig-fast | 4.19 | 3.99–4.87 | 1.056 | 1.044–1.082 |
| mutate_shared / small | micro | one contract operation | my-llvm | 140.99 | 132.64–165.05 | 2.268 | 2.174–2.284 |
| mutate_shared / small | micro | one contract operation | my-qbe | 179.50 | 175.71–229.87 | 2.960 | 2.928–3.004 |
| mutate_shared / small | micro | one contract operation | rust | 12.45 | 11.74–15.54 | 0.204 | 0.201–0.209 |
| mutate_shared / small | micro | one contract operation | go | 60.92 | 58.06–78.96 | 1.000 | 1.000–1.000 |
| mutate_shared / small | micro | one contract operation | zig-safe | 19.17 | 17.93–27.87 | 0.308 | 0.303–0.311 |
| mutate_shared / small | micro | one contract operation | zig-fast | 11.84 | 11.30–15.72 | 0.199 | 0.190–0.200 |
| mutate_shared / large | micro | one contract operation | my-llvm | 312.71 | 288.54–383.29 | 0.372 | 0.364–0.395 |
| mutate_shared / large | micro | one contract operation | my-qbe | 382.41 | 346.56–433.74 | 0.455 | 0.427–0.461 |
| mutate_shared / large | micro | one contract operation | rust | 96.38 | 80.09–113.74 | 0.116 | 0.112–0.121 |
| mutate_shared / large | micro | one contract operation | go | 838.05 | 763.78–922.92 | 1.000 | 1.000–1.000 |
| mutate_shared / large | micro | one contract operation | zig-safe | 213.43 | 189.46–253.68 | 0.250 | 0.243–0.275 |
| mutate_shared / large | micro | one contract operation | zig-fast | 168.63 | 138.79–195.32 | 0.197 | 0.184–0.218 |
| integer_math / small | micro | one complete pass over SIZE fixtures | my-llvm | 192.47 | 185.17–251.12 | 1.344 | 1.295–1.374 |
| integer_math / small | micro | one complete pass over SIZE fixtures | my-qbe | 535.29 | 525.34–646.83 | 3.726 | 3.620–3.800 |
| integer_math / small | micro | one complete pass over SIZE fixtures | rust | 105.77 | 100.95–133.57 | 0.732 | 0.705–0.817 |
| integer_math / small | micro | one complete pass over SIZE fixtures | go | 144.27 | 137.62–168.12 | 1.000 | 1.000–1.000 |
| integer_math / small | micro | one complete pass over SIZE fixtures | zig-safe | 141.71 | 135.20–189.98 | 0.975 | 0.947–0.993 |
| integer_math / small | micro | one complete pass over SIZE fixtures | zig-fast | 125.63 | 118.93–164.86 | 0.869 | 0.842–0.961 |
| integer_math / large | micro | one complete pass over SIZE fixtures | my-llvm | 11747.87 | 10786.98–14477.88 | 1.378 | 1.304–1.421 |
| integer_math / large | micro | one complete pass over SIZE fixtures | my-qbe | 33373.77 | 32272.70–36459.25 | 3.933 | 3.492–4.030 |
| integer_math / large | micro | one complete pass over SIZE fixtures | rust | 6392.67 | 5673.95–8356.91 | 0.716 | 0.686–0.788 |
| integer_math / large | micro | one complete pass over SIZE fixtures | go | 8482.47 | 8250.99–10366.17 | 1.000 | 1.000–1.000 |
| integer_math / large | micro | one complete pass over SIZE fixtures | zig-safe | 8801.53 | 7627.99–10607.49 | 1.037 | 0.934–1.095 |
| integer_math / large | micro | one complete pass over SIZE fixtures | zig-fast | 8146.40 | 6891.23–9520.44 | 0.918 | 0.837–0.986 |
| float_math / small | micro | one complete pass over SIZE fixtures | my-llvm | 229.07 | 202.35–274.98 | 1.703 | 1.674–1.759 |
| float_math / small | micro | one complete pass over SIZE fixtures | my-qbe | 595.70 | 547.05–670.43 | 4.324 | 4.254–4.495 |
| float_math / small | micro | one complete pass over SIZE fixtures | rust | 143.94 | 123.30–165.36 | 1.030 | 1.015–1.093 |
| float_math / small | micro | one complete pass over SIZE fixtures | go | 138.67 | 120.56–159.73 | 1.000 | 1.000–1.000 |
| float_math / small | micro | one complete pass over SIZE fixtures | zig-safe | 142.70 | 124.91–163.59 | 1.022 | 1.002–1.108 |
| float_math / small | micro | one complete pass over SIZE fixtures | zig-fast | 91.42 | 80.64–106.65 | 0.680 | 0.650–0.689 |
| float_math / large | micro | one complete pass over SIZE fixtures | my-llvm | 15054.22 | 12485.66–18142.12 | 1.798 | 1.678–1.906 |
| float_math / large | micro | one complete pass over SIZE fixtures | my-qbe | 38550.35 | 33989.05–44537.66 | 4.745 | 4.266–5.018 |
| float_math / large | micro | one complete pass over SIZE fixtures | rust | 8918.08 | 7358.46–10581.26 | 1.101 | 1.042–1.133 |
| float_math / large | micro | one complete pass over SIZE fixtures | go | 8387.23 | 7169.27–9035.80 | 1.000 | 1.000–1.000 |
| float_math / large | micro | one complete pass over SIZE fixtures | zig-safe | 7930.41 | 7016.27–9863.26 | 0.955 | 0.907–1.016 |
| float_math / large | micro | one complete pass over SIZE fixtures | zig-fast | 5916.67 | 4903.80–6520.39 | 0.714 | 0.676–0.750 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | my-llvm | 131.71 | 125.44–141.57 | 1.138 | 1.076–1.166 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | my-qbe | 410.36 | 401.73–452.93 | 3.537 | 3.448–3.574 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | rust | 61.29 | 60.31–72.73 | 0.535 | 0.516–0.541 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | go | 116.48 | 111.26–131.50 | 1.000 | 1.000–1.000 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | zig-safe | 132.80 | 126.15–143.86 | 1.131 | 1.114–1.141 |
| branch_predictable / small | micro | one complete pass over SIZE fixtures | zig-fast | 60.90 | 59.41–65.17 | 0.528 | 0.500–0.535 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | my-llvm | 8439.82 | 6699.02–10747.09 | 1.060 | 0.975–1.142 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | my-qbe | 26818.56 | 25516.70–29870.14 | 3.370 | 3.232–3.465 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | rust | 3857.25 | 3757.25–4660.34 | 0.493 | 0.480–0.510 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | go | 7960.02 | 7369.82–9432.85 | 1.000 | 1.000–1.000 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | zig-safe | 9076.78 | 8154.24–10652.49 | 1.125 | 1.103–1.186 |
| branch_predictable / large | micro | one complete pass over SIZE fixtures | zig-fast | 3889.39 | 3736.29–4388.20 | 0.489 | 0.479–0.498 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | my-llvm | 121.03 | 118.11–155.59 | 1.011 | 1.006–1.031 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | my-qbe | 461.72 | 455.06–510.17 | 3.853 | 3.829–3.914 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | rust | 81.88 | 79.41–108.33 | 0.686 | 0.681–0.699 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | go | 119.12 | 116.75–139.35 | 1.000 | 1.000–1.000 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | zig-safe | 142.97 | 139.08–181.94 | 1.201 | 1.184–1.203 |
| branch_mixed / small | micro | one complete pass over SIZE fixtures | zig-fast | 80.89 | 78.20–103.44 | 0.682 | 0.678–0.689 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | my-llvm | 7978.35 | 7685.91–9123.97 | 0.884 | 0.855–0.903 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | my-qbe | 29563.08 | 28176.66–33861.41 | 3.261 | 3.165–3.324 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | rust | 5392.80 | 5183.40–5714.97 | 0.589 | 0.565–0.612 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | go | 9065.08 | 8584.37–10947.01 | 1.000 | 1.000–1.000 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | zig-safe | 9720.51 | 9323.25–12282.61 | 1.072 | 1.038–1.103 |
| branch_mixed / large | micro | one complete pass over SIZE fixtures | zig-fast | 5507.66 | 5153.76–6207.66 | 0.587 | 0.576–0.620 |
| record_construct / small | micro | one complete pass over SIZE fixtures | my-llvm | 212.98 | 200.89–256.78 | 1.286 | 1.257–1.340 |
| record_construct / small | micro | one complete pass over SIZE fixtures | my-qbe | 1158.37 | 1135.53–1289.92 | 7.111 | 6.559–7.203 |
| record_construct / small | micro | one complete pass over SIZE fixtures | rust | 117.01 | 113.23–175.22 | 0.722 | 0.706–0.762 |
| record_construct / small | micro | one complete pass over SIZE fixtures | go | 162.84 | 157.50–204.88 | 1.000 | 1.000–1.000 |
| record_construct / small | micro | one complete pass over SIZE fixtures | zig-safe | 176.83 | 167.04–243.47 | 1.055 | 1.008–1.096 |
| record_construct / small | micro | one complete pass over SIZE fixtures | zig-fast | 152.65 | 147.97–168.39 | 0.930 | 0.848–0.942 |
| record_construct / large | micro | one complete pass over SIZE fixtures | my-llvm | 14562.99 | 12424.79–16610.80 | 1.282 | 1.141–1.328 |
| record_construct / large | micro | one complete pass over SIZE fixtures | my-qbe | 79600.27 | 74682.18–89825.10 | 7.074 | 6.522–7.522 |
| record_construct / large | micro | one complete pass over SIZE fixtures | rust | 8032.39 | 6938.06–9897.63 | 0.708 | 0.625–0.748 |
| record_construct / large | micro | one complete pass over SIZE fixtures | go | 11817.46 | 9765.52–13640.43 | 1.000 | 1.000–1.000 |
| record_construct / large | micro | one complete pass over SIZE fixtures | zig-safe | 12275.60 | 10458.28–15093.03 | 1.047 | 1.028–1.141 |
| record_construct / large | micro | one complete pass over SIZE fixtures | zig-fast | 10512.36 | 9929.08–13033.87 | 0.953 | 0.935–0.982 |
| record_update / small | micro | one complete pass over SIZE fixtures | my-llvm | 247.37 | 226.88–291.27 | 1.367 | 1.320–1.430 |
| record_update / small | micro | one complete pass over SIZE fixtures | my-qbe | 1715.22 | 1644.78–1809.79 | 9.307 | 8.909–9.599 |
| record_update / small | micro | one complete pass over SIZE fixtures | rust | 135.64 | 117.66–145.58 | 0.713 | 0.668–0.787 |
| record_update / small | micro | one complete pass over SIZE fixtures | go | 179.63 | 170.88–220.74 | 1.000 | 1.000–1.000 |
| record_update / small | micro | one complete pass over SIZE fixtures | zig-safe | 219.91 | 197.05–230.96 | 1.151 | 1.132–1.245 |
| record_update / small | micro | one complete pass over SIZE fixtures | zig-fast | 164.46 | 157.57–186.72 | 0.912 | 0.888–0.940 |
| record_update / large | micro | one complete pass over SIZE fixtures | my-llvm | 16056.68 | 13401.95–19468.90 | 1.337 | 1.275–1.395 |
| record_update / large | micro | one complete pass over SIZE fixtures | my-qbe | 109569.55 | 102993.75–119799.50 | 9.609 | 9.417–10.283 |
| record_update / large | micro | one complete pass over SIZE fixtures | rust | 7810.93 | 7001.48–9539.01 | 0.696 | 0.669–0.732 |
| record_update / large | micro | one complete pass over SIZE fixtures | go | 10989.29 | 9962.23–14644.40 | 1.000 | 1.000–1.000 |
| record_update / large | micro | one complete pass over SIZE fixtures | zig-safe | 12805.73 | 11090.20–16358.85 | 1.104 | 1.091–1.165 |
| record_update / large | micro | one complete pass over SIZE fixtures | zig-fast | 10483.99 | 9938.89–12276.67 | 0.946 | 0.887–0.982 |
| call_direct / small | micro | one complete pass over SIZE fixtures | my-llvm | 90.57 | 85.06–110.48 | 1.189 | 1.132–1.231 |
| call_direct / small | micro | one complete pass over SIZE fixtures | my-qbe | 982.31 | 948.79–1048.37 | 12.679 | 12.096–13.198 |
| call_direct / small | micro | one complete pass over SIZE fixtures | rust | 53.60 | 47.63–64.51 | 0.701 | 0.674–0.730 |
| call_direct / small | micro | one complete pass over SIZE fixtures | go | 79.79 | 70.68–92.58 | 1.000 | 1.000–1.000 |
| call_direct / small | micro | one complete pass over SIZE fixtures | zig-safe | 78.15 | 69.51–89.57 | 0.961 | 0.896–1.040 |
| call_direct / small | micro | one complete pass over SIZE fixtures | zig-fast | 60.35 | 51.10–71.06 | 0.758 | 0.697–0.794 |
| call_direct / large | micro | one complete pass over SIZE fixtures | my-llvm | 5113.80 | 4560.56–6436.76 | 1.283 | 1.230–1.333 |
| call_direct / large | micro | one complete pass over SIZE fixtures | my-qbe | 62865.26 | 60416.70–69237.71 | 15.715 | 14.981–17.057 |
| call_direct / large | micro | one complete pass over SIZE fixtures | rust | 2328.14 | 2095.11–2819.34 | 0.606 | 0.589–0.619 |
| call_direct / large | micro | one complete pass over SIZE fixtures | go | 4000.41 | 3554.78–4844.24 | 1.000 | 1.000–1.000 |
| call_direct / large | micro | one complete pass over SIZE fixtures | zig-safe | 3551.15 | 3200.24–4074.33 | 0.889 | 0.870–0.944 |
| call_direct / large | micro | one complete pass over SIZE fixtures | zig-fast | 2429.83 | 2066.85–2976.19 | 0.598 | 0.584–0.634 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | my-llvm | 160.37 | 152.01–181.41 | 1.013 | 0.992–1.030 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | my-qbe | 1055.59 | 1023.34–1115.83 | 6.661 | 6.617–6.758 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | rust | 128.51 | 125.19–158.85 | 0.829 | 0.818–0.840 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | go | 156.77 | 150.78–188.98 | 1.000 | 1.000–1.000 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | zig-safe | 178.09 | 175.62–186.78 | 1.146 | 1.102–1.166 |
| call_indirect / small | micro | one complete pass over SIZE fixtures | zig-fast | 119.48 | 115.22–126.81 | 0.758 | 0.751–0.766 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | my-llvm | 9627.65 | 8964.54–10249.73 | 1.004 | 0.984–1.027 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | my-qbe | 67209.77 | 66008.04–68851.46 | 7.082 | 6.930–7.183 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | rust | 8105.22 | 7642.73–8596.25 | 0.849 | 0.828–0.881 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | go | 9415.84 | 9174.69–9974.93 | 1.000 | 1.000–1.000 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | zig-safe | 11057.94 | 10601.12–12003.97 | 1.174 | 1.153–1.196 |
| call_indirect / large | micro | one complete pass over SIZE fixtures | zig-fast | 6998.95 | 6590.65–7420.22 | 0.729 | 0.722–0.748 |
| option_handle / small | micro | one complete pass over SIZE fixtures | my-llvm | 113.52 | 108.27–122.94 | 1.001 | 0.971–1.016 |
| option_handle / small | micro | one complete pass over SIZE fixtures | my-qbe | 1074.89 | 1032.57–1168.65 | 9.367 | 9.333–9.586 |
| option_handle / small | micro | one complete pass over SIZE fixtures | rust | 50.95 | 49.91–59.98 | 0.454 | 0.450–0.487 |
| option_handle / small | micro | one complete pass over SIZE fixtures | go | 112.70 | 109.80–122.12 | 1.000 | 1.000–1.000 |
| option_handle / small | micro | one complete pass over SIZE fixtures | zig-safe | 117.84 | 112.77–146.99 | 1.030 | 1.015–1.091 |
| option_handle / small | micro | one complete pass over SIZE fixtures | zig-fast | 89.37 | 86.47–101.42 | 0.795 | 0.788–0.833 |
| option_handle / large | micro | one complete pass over SIZE fixtures | my-llvm | 6414.03 | 6120.77–7781.66 | 0.939 | 0.931–0.946 |
| option_handle / large | micro | one complete pass over SIZE fixtures | my-qbe | 67985.30 | 64756.28–76854.91 | 9.844 | 9.298–10.144 |
| option_handle / large | micro | one complete pass over SIZE fixtures | rust | 2433.85 | 2323.61–3117.53 | 0.359 | 0.355–0.362 |
| option_handle / large | micro | one complete pass over SIZE fixtures | go | 6915.49 | 6356.06–8158.41 | 1.000 | 1.000–1.000 |
| option_handle / large | micro | one complete pass over SIZE fixtures | zig-safe | 6489.85 | 6388.09–7866.67 | 0.996 | 0.974–1.011 |
| option_handle / large | micro | one complete pass over SIZE fixtures | zig-fast | 5333.48 | 5106.31–6852.69 | 0.786 | 0.780–0.817 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | my-llvm | 163.80 | 159.86–174.92 | 1.099 | 1.072–1.113 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | my-qbe | 1330.50 | 1302.02–1472.61 | 8.932 | 8.842–9.091 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | rust | 67.88 | 65.81–77.50 | 0.452 | 0.451–0.464 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | go | 150.27 | 144.04–167.67 | 1.000 | 1.000–1.000 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | zig-safe | 128.01 | 121.69–144.95 | 0.861 | 0.835–0.884 |
| result_propagate / small | micro | one complete pass over SIZE fixtures | zig-fast | 82.27 | 79.89–95.73 | 0.552 | 0.536–0.560 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | my-llvm | 9872.42 | 9607.10–11539.04 | 1.045 | 1.004–1.057 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | my-qbe | 88485.73 | 83990.91–93739.82 | 9.327 | 9.097–9.422 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | rust | 3981.33 | 3591.81–4884.82 | 0.414 | 0.392–0.436 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | go | 9641.36 | 9094.04–10982.32 | 1.000 | 1.000–1.000 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | zig-safe | 8170.89 | 7843.20–8973.91 | 0.869 | 0.813–0.917 |
| result_propagate / large | micro | one complete pass over SIZE fixtures | zig-fast | 5873.54 | 5586.45–6906.63 | 0.615 | 0.606–0.652 |
| binary_search / small | micro | one complete pass over SIZE fixtures | my-llvm | 115.72 | 111.32–121.68 | 1.012 | 0.983–1.020 |
| binary_search / small | micro | one complete pass over SIZE fixtures | my-qbe | 421.02 | 405.47–431.44 | 3.658 | 3.577–3.749 |
| binary_search / small | micro | one complete pass over SIZE fixtures | rust | 58.45 | 56.38–62.41 | 0.510 | 0.504–0.514 |
| binary_search / small | micro | one complete pass over SIZE fixtures | go | 114.57 | 110.20–122.23 | 1.000 | 1.000–1.000 |
| binary_search / small | micro | one complete pass over SIZE fixtures | zig-safe | 88.20 | 85.61–94.75 | 0.764 | 0.751–0.789 |
| binary_search / small | micro | one complete pass over SIZE fixtures | zig-fast | 84.04 | 78.73–90.82 | 0.730 | 0.702–0.748 |
| binary_search / large | micro | one complete pass over SIZE fixtures | my-llvm | 3032.41 | 2934.35–3732.45 | 1.131 | 1.125–1.152 |
| binary_search / large | micro | one complete pass over SIZE fixtures | my-qbe | 16767.62 | 16409.09–18022.30 | 6.242 | 6.184–6.337 |
| binary_search / large | micro | one complete pass over SIZE fixtures | rust | 1580.02 | 1557.25–1709.50 | 0.589 | 0.582–0.597 |
| binary_search / large | micro | one complete pass over SIZE fixtures | go | 2684.83 | 2609.16–2822.52 | 1.000 | 1.000–1.000 |
| binary_search / large | micro | one complete pass over SIZE fixtures | zig-safe | 5440.39 | 5360.48–6649.63 | 2.042 | 2.010–2.093 |
| binary_search / large | micro | one complete pass over SIZE fixtures | zig-fast | 2102.18 | 2079.48–2552.19 | 0.785 | 0.775–0.801 |
| packet_decode / small | application | one complete pass over SIZE fixtures | my-llvm | 96.18 | 92.85–101.38 | 0.796 | 0.766–0.812 |
| packet_decode / small | application | one complete pass over SIZE fixtures | my-qbe | 464.47 | 448.04–491.77 | 3.891 | 3.615–3.991 |
| packet_decode / small | application | one complete pass over SIZE fixtures | rust | 52.65 | 49.79–57.11 | 0.432 | 0.420–0.450 |
| packet_decode / small | application | one complete pass over SIZE fixtures | go | 118.89 | 116.72–130.03 | 1.000 | 1.000–1.000 |
| packet_decode / small | application | one complete pass over SIZE fixtures | zig-safe | 81.93 | 79.18–103.92 | 0.691 | 0.673–0.740 |
| packet_decode / small | application | one complete pass over SIZE fixtures | zig-fast | 44.48 | 41.48–46.48 | 0.362 | 0.354–0.370 |
| packet_decode / large | application | one complete pass over SIZE fixtures | my-llvm | 1489.63 | 1412.03–1608.24 | 0.740 | 0.721–0.777 |
| packet_decode / large | application | one complete pass over SIZE fixtures | my-qbe | 7567.68 | 7064.81–8174.45 | 3.758 | 3.632–3.966 |
| packet_decode / large | application | one complete pass over SIZE fixtures | rust | 797.41 | 753.99–887.08 | 0.409 | 0.390–0.421 |
| packet_decode / large | application | one complete pass over SIZE fixtures | go | 2020.71 | 1860.52–2121.37 | 1.000 | 1.000–1.000 |
| packet_decode / large | application | one complete pass over SIZE fixtures | zig-safe | 1292.66 | 1256.70–1584.53 | 0.672 | 0.664–0.701 |
| packet_decode / large | application | one complete pass over SIZE fixtures | zig-fast | 660.87 | 632.38–750.00 | 0.335 | 0.320–0.357 |
| list_scan / small | micro | one complete SIZE-element dataset operation | my-llvm | 101.23 | 89.20–128.20 | 1.560 | 1.483–1.607 |
| list_scan / small | micro | one complete SIZE-element dataset operation | my-qbe | 246.82 | 215.38–263.62 | 3.681 | 3.425–3.888 |
| list_scan / small | micro | one complete SIZE-element dataset operation | rust | 49.04 | 45.48–67.27 | 0.804 | 0.771–0.843 |
| list_scan / small | micro | one complete SIZE-element dataset operation | go | 62.39 | 57.88–80.18 | 1.000 | 1.000–1.000 |
| list_scan / small | micro | one complete SIZE-element dataset operation | zig-safe | 90.52 | 77.27–108.11 | 1.364 | 1.328–1.451 |
| list_scan / small | micro | one complete SIZE-element dataset operation | zig-fast | 66.19 | 59.31–79.80 | 1.045 | 1.007–1.099 |
| list_scan / large | micro | one complete SIZE-element dataset operation | my-llvm | 5192.20 | 4121.04–6289.13 | 1.323 | 1.293–1.386 |
| list_scan / large | micro | one complete SIZE-element dataset operation | my-qbe | 12274.86 | 10680.98–13720.73 | 2.901 | 2.850–3.195 |
| list_scan / large | micro | one complete SIZE-element dataset operation | rust | 3380.08 | 2964.59–4015.55 | 0.838 | 0.822–0.863 |
| list_scan / large | micro | one complete SIZE-element dataset operation | go | 4098.88 | 3532.36–4514.95 | 1.000 | 1.000–1.000 |
| list_scan / large | micro | one complete SIZE-element dataset operation | zig-safe | 5604.39 | 5081.18–6635.46 | 1.380 | 1.303–1.505 |
| list_scan / large | micro | one complete SIZE-element dataset operation | zig-fast | 4694.86 | 3691.01–5415.29 | 1.146 | 1.093–1.209 |
| list_append / small | micro | one complete SIZE-element dataset operation | my-llvm | 403.79 | 384.48–471.38 | 1.383 | 1.334–1.453 |
| list_append / small | micro | one complete SIZE-element dataset operation | my-qbe | 665.61 | 631.60–783.33 | 2.307 | 2.219–2.369 |
| list_append / small | micro | one complete SIZE-element dataset operation | rust | 206.97 | 197.01–245.93 | 0.706 | 0.692–0.731 |
| list_append / small | micro | one complete SIZE-element dataset operation | go | 299.95 | 268.28–358.50 | 1.000 | 1.000–1.000 |
| list_append / small | micro | one complete SIZE-element dataset operation | zig-safe | 329.38 | 308.27–395.56 | 1.121 | 1.065–1.156 |
| list_append / small | micro | one complete SIZE-element dataset operation | zig-fast | 148.60 | 144.68–176.50 | 0.512 | 0.485–0.533 |
| list_append / large | micro | one complete SIZE-element dataset operation | my-llvm | 16923.24 | 15230.11–20214.05 | 1.231 | 1.156–1.290 |
| list_append / large | micro | one complete SIZE-element dataset operation | my-qbe | 26593.35 | 25066.38–30534.98 | 1.924 | 1.755–2.062 |
| list_append / large | micro | one complete SIZE-element dataset operation | rust | 7461.32 | 6991.86–8776.37 | 0.558 | 0.535–0.583 |
| list_append / large | micro | one complete SIZE-element dataset operation | go | 13560.08 | 12071.22–17318.06 | 1.000 | 1.000–1.000 |
| list_append / large | micro | one complete SIZE-element dataset operation | zig-safe | 15157.89 | 13537.01–17317.77 | 1.080 | 1.040–1.180 |
| list_append / large | micro | one complete SIZE-element dataset operation | zig-fast | 6910.97 | 6527.14–8462.16 | 0.519 | 0.470–0.547 |
| list_filter / small | micro | one complete SIZE-element dataset operation | my-llvm | 469.43 | 453.89–527.21 | 1.343 | 1.310–1.371 |
| list_filter / small | micro | one complete SIZE-element dataset operation | my-qbe | 852.16 | 823.94–954.66 | 2.449 | 2.407–2.501 |
| list_filter / small | micro | one complete SIZE-element dataset operation | rust | 195.61 | 187.77–221.85 | 0.560 | 0.527–0.583 |
| list_filter / small | micro | one complete SIZE-element dataset operation | go | 344.71 | 336.01–429.00 | 1.000 | 1.000–1.000 |
| list_filter / small | micro | one complete SIZE-element dataset operation | zig-safe | 268.19 | 246.44–307.67 | 0.758 | 0.733–0.816 |
| list_filter / small | micro | one complete SIZE-element dataset operation | zig-fast | 177.98 | 173.67–196.44 | 0.516 | 0.498–0.534 |
| list_filter / large | micro | one complete SIZE-element dataset operation | my-llvm | 17208.62 | 15018.12–22237.63 | 1.179 | 1.164–1.301 |
| list_filter / large | micro | one complete SIZE-element dataset operation | my-qbe | 36667.93 | 33686.92–42149.01 | 2.645 | 2.576–2.858 |
| list_filter / large | micro | one complete SIZE-element dataset operation | rust | 6892.52 | 6415.79–9072.21 | 0.518 | 0.500–0.551 |
| list_filter / large | micro | one complete SIZE-element dataset operation | go | 13544.13 | 12578.13–17384.05 | 1.000 | 1.000–1.000 |
| list_filter / large | micro | one complete SIZE-element dataset operation | zig-safe | 12660.63 | 11307.93–15251.41 | 0.904 | 0.875–0.939 |
| list_filter / large | micro | one complete SIZE-element dataset operation | zig-fast | 8693.49 | 8340.48–11064.97 | 0.652 | 0.621–0.672 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | my-llvm | 583.75 | 561.98–657.14 | 1.076 | 1.058–1.140 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | my-qbe | 980.75 | 955.34–1245.81 | 1.859 | 1.821–1.972 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | rust | 743.31 | 709.39–932.26 | 1.400 | 1.361–1.478 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | go | 535.24 | 475.80–621.26 | 1.000 | 1.000–1.000 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | zig-safe | 602.02 | 565.19–701.11 | 1.105 | 1.096–1.129 |
| dict_lookup / small | micro | one complete SIZE-element dataset operation | zig-fast | 300.95 | 291.86–387.74 | 0.573 | 0.553–0.617 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | my-llvm | 60382.13 | 59756.79–62267.94 | 1.780 | 1.708–1.814 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | my-qbe | 89738.93 | 88172.20–95186.57 | 2.654 | 2.535–2.694 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | rust | 46465.23 | 45465.27–49790.78 | 1.377 | 1.323–1.384 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | go | 33803.07 | 32515.24–41259.99 | 1.000 | 1.000–1.000 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | zig-safe | 60491.79 | 59639.30–68906.23 | 1.778 | 1.693–1.831 |
| dict_lookup / large | micro | one complete SIZE-element dataset operation | zig-fast | 47076.51 | 46472.93–59876.37 | 1.391 | 1.357–1.422 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | my-llvm | 686.68 | 673.01–703.37 | 1.046 | 1.035–1.081 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | my-qbe | 1041.77 | 1030.66–1084.04 | 1.593 | 1.581–1.608 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | rust | 1047.38 | 1000.27–1144.64 | 1.592 | 1.550–1.677 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | go | 656.31 | 627.23–684.04 | 1.000 | 1.000–1.000 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | zig-safe | 607.20 | 598.70–686.80 | 0.933 | 0.914–0.948 |
| dict_lookup_str / small | micro | one complete SIZE-element dataset operation | zig-fast | 467.19 | 452.74–530.73 | 0.713 | 0.696–0.739 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | my-llvm | 81532.55 | 80830.50–86211.90 | 1.685 | 1.657–1.710 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | my-qbe | 113443.09 | 111365.34–121737.91 | 2.338 | 2.289–2.379 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | rust | 73061.13 | 66454.66–77946.98 | 1.485 | 1.407–1.502 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | go | 48823.48 | 47174.77–49932.12 | 1.000 | 1.000–1.000 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | zig-safe | 74380.68 | 72435.49–76305.18 | 1.523 | 1.506–1.527 |
| dict_lookup_str / large | micro | one complete SIZE-element dataset operation | zig-fast | 59776.45 | 57344.30–67628.49 | 1.213 | 1.196–1.246 |
| dict_update / small | micro | one complete SIZE-element dataset operation | my-llvm | 14530.38 | 14213.18–16240.40 | 1.473 | 1.445–1.481 |
| dict_update / small | micro | one complete SIZE-element dataset operation | my-qbe | 19639.36 | 19076.40–22160.07 | 1.980 | 1.968–2.013 |
| dict_update / small | micro | one complete SIZE-element dataset operation | rust | 7129.43 | 6960.31–7729.72 | 0.719 | 0.713–0.750 |
| dict_update / small | micro | one complete SIZE-element dataset operation | go | 9845.79 | 9605.01–11539.13 | 1.000 | 1.000–1.000 |
| dict_update / small | micro | one complete SIZE-element dataset operation | zig-safe | 5876.56 | 5724.49–6358.69 | 0.595 | 0.588–0.600 |
| dict_update / small | micro | one complete SIZE-element dataset operation | zig-fast | 2901.93 | 2844.19–3719.76 | 0.297 | 0.290–0.309 |
| dict_update / large | micro | one complete SIZE-element dataset operation | my-llvm | 1138978.95 | 1126026.14–1166111.29 | 1.866 | 1.855–1.925 |
| dict_update / large | micro | one complete SIZE-element dataset operation | my-qbe | 1447140.45 | 1428129.83–1504377.11 | 2.383 | 2.343–2.447 |
| dict_update / large | micro | one complete SIZE-element dataset operation | rust | 562747.30 | 532697.64–612769.59 | 0.921 | 0.894–0.946 |
| dict_update / large | micro | one complete SIZE-element dataset operation | go | 607048.72 | 578404.49–640062.16 | 1.000 | 1.000–1.000 |
| dict_update / large | micro | one complete SIZE-element dataset operation | zig-safe | 721116.03 | 692924.21–758572.58 | 1.183 | 1.173–1.209 |
| dict_update / large | micro | one complete SIZE-element dataset operation | zig-fast | 517545.36 | 494836.64–556998.67 | 0.853 | 0.831–0.884 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | my-llvm | 17322.07 | 16420.09–20248.01 | 1.480 | 1.464–1.508 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | my-qbe | 22176.16 | 21302.41–24631.69 | 1.918 | 1.890–1.943 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | rust | 15940.53 | 15124.76–20014.89 | 1.381 | 1.372–1.404 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | go | 11617.71 | 10833.70–14128.06 | 1.000 | 1.000–1.000 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | zig-safe | 7682.08 | 7294.33–8127.12 | 0.661 | 0.644–0.674 |
| dict_update_str / small | micro | one complete SIZE-element dataset operation | zig-fast | 5815.21 | 5521.73–7187.00 | 0.503 | 0.499–0.511 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | my-llvm | 1404171.44 | 1331337.81–1456503.94 | 1.660 | 1.638–1.707 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | my-qbe | 1656433.79 | 1576557.52–1857776.00 | 1.972 | 1.943–2.037 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | rust | 1240319.42 | 1161817.88–1357977.25 | 1.488 | 1.454–1.541 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | go | 813334.58 | 779426.25–907321.15 | 1.000 | 1.000–1.000 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | zig-safe | 1017295.62 | 949110.25–1064784.19 | 1.203 | 1.178–1.227 |
| dict_update_str / large | micro | one complete SIZE-element dataset operation | zig-fast | 873250.40 | 805734.35–941841.71 | 1.043 | 1.014–1.054 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | my-llvm | 3234.25 | 3176.00–3430.97 | 2.593 | 2.561–2.609 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | my-qbe | 4283.30 | 4189.21–4570.20 | 3.446 | 3.427–3.497 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | rust | 1039.73 | 1005.43–1138.17 | 0.837 | 0.826–0.849 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | go | 1250.24 | 1220.28–1323.78 | 1.000 | 1.000–1.000 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | zig-safe | 666.52 | 647.87–724.59 | 0.543 | 0.531–0.546 |
| set_dedup / small | micro | one complete SIZE-element dataset operation | zig-fast | 315.25 | 298.56–341.22 | 0.249 | 0.246–0.258 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | my-llvm | 218976.70 | 210228.77–229747.37 | 2.623 | 2.586–2.765 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | my-qbe | 282689.12 | 272180.55–292487.84 | 3.370 | 3.315–3.631 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | rust | 72781.19 | 65822.09–84690.87 | 0.882 | 0.857–0.893 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | go | 84120.47 | 74073.91–97128.85 | 1.000 | 1.000–1.000 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | zig-safe | 92983.71 | 86488.32–97844.63 | 1.114 | 1.087–1.169 |
| set_dedup / large | micro | one complete SIZE-element dataset operation | zig-fast | 65854.82 | 59586.91–67943.10 | 0.789 | 0.781–0.798 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | my-llvm | 4940.97 | 4900.13–4967.37 | 32.537 | 31.379–33.242 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | my-qbe | 6712.28 | 6593.08–6744.60 | 44.672 | 42.686–45.211 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | rust | 82.19 | 77.49–94.30 | 0.530 | 0.524–0.594 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | go | 150.61 | 147.87–160.88 | 1.000 | 1.000–1.000 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | zig-safe | 348.36 | 338.27–363.50 | 2.300 | 2.199–2.358 |
| alloc_short / small | micro | one complete SIZE-element dataset operation | zig-fast | 3.93 | 3.56–4.55 | 0.025 | 0.025–0.027 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | my-llvm | 76897.90 | 75541.55–77371.75 | 36.682 | 36.089–38.520 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | my-qbe | 103728.24 | 102475.06–104930.07 | 49.604 | 49.198–51.816 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | rust | 1278.02 | 1176.46–1379.20 | 0.604 | 0.576–0.630 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | go | 2091.42 | 1954.79–2393.59 | 1.000 | 1.000–1.000 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | zig-safe | 5363.31 | 5272.07–5518.36 | 2.571 | 2.559–2.694 |
| alloc_short / large | micro | one complete SIZE-element dataset operation | zig-fast | 3.90 | 3.71–4.71 | 0.002 | 0.002–0.002 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | my-llvm | 3043.01 | 2968.68–3269.39 | 1.589 | 1.575–1.612 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | my-qbe | 4607.70 | 4523.77–4941.10 | 2.409 | 2.395–2.426 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | rust | 1382.84 | 1344.03–1468.46 | 0.717 | 0.716–0.732 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | go | 1920.01 | 1883.59–2002.02 | 1.000 | 1.000–1.000 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | zig-safe | 1331.81 | 1308.76–1382.21 | 0.695 | 0.688–0.700 |
| alloc_retained / small | micro | one complete SIZE-element dataset operation | zig-fast | 1292.70 | 1277.88–1429.40 | 0.676 | 0.672–0.681 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | my-llvm | 46944.01 | 46472.86–49048.20 | 1.797 | 1.786–1.800 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | my-qbe | 69682.05 | 69164.72–70625.43 | 2.665 | 2.649–2.679 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | rust | 21754.49 | 21434.11–22328.47 | 0.829 | 0.827–0.838 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | go | 26152.85 | 25931.39–26528.88 | 1.000 | 1.000–1.000 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | zig-safe | 21467.94 | 21120.09–21853.27 | 0.816 | 0.812–0.823 |
| alloc_retained / large | micro | one complete SIZE-element dataset operation | zig-fast | 20710.27 | 20445.57–21517.56 | 0.793 | 0.789–0.797 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | my-llvm | 753.01 | 741.34–775.93 | 0.624 | 0.621–0.632 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | my-qbe | 859.83 | 850.75–894.47 | 0.714 | 0.712–0.718 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | rust | 1221.95 | 1202.03–1239.16 | 1.016 | 1.007–1.024 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | go | 1198.19 | 1184.32–1270.02 | 1.000 | 1.000–1.000 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | zig-safe | 1241.31 | 1223.53–1287.57 | 1.032 | 1.022–1.047 |
| mutate_nested / small | micro | one complete SIZE-element dataset operation | zig-fast | 1131.32 | 1114.35–1186.71 | 0.943 | 0.934–0.950 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | my-llvm | 7343.12 | 7120.71–7420.94 | 0.410 | 0.403–0.411 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | my-qbe | 8229.86 | 8004.55–8342.64 | 0.456 | 0.450–0.458 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | rust | 20791.90 | 20553.97–21022.12 | 1.156 | 1.151–1.162 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | go | 17989.30 | 17664.32–18329.41 | 1.000 | 1.000–1.000 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | zig-safe | 20712.06 | 20553.53–21304.01 | 1.150 | 1.148–1.161 |
| mutate_nested / large | micro | one complete SIZE-element dataset operation | zig-fast | 19005.68 | 18840.22–19428.03 | 1.054 | 1.049–1.069 |
| sort_int / small | micro | one complete SIZE-element dataset operation | my-llvm | 276.46 | 274.70–278.53 | 0.253 | 0.252–0.254 |
| sort_int / small | micro | one complete SIZE-element dataset operation | my-qbe | 484.28 | 483.24–496.62 | 0.445 | 0.442–0.446 |
| sort_int / small | micro | one complete SIZE-element dataset operation | rust | 228.80 | 226.37–230.55 | 0.209 | 0.209–0.210 |
| sort_int / small | micro | one complete SIZE-element dataset operation | go | 1092.48 | 1083.94–1100.92 | 1.000 | 1.000–1.000 |
| sort_int / small | micro | one complete SIZE-element dataset operation | zig-safe | 275.40 | 271.52–278.39 | 0.252 | 0.250–0.253 |
| sort_int / small | micro | one complete SIZE-element dataset operation | zig-fast | 171.43 | 168.12–175.65 | 0.157 | 0.156–0.158 |
| sort_int / large | micro | one complete SIZE-element dataset operation | my-llvm | 44258.73 | 44064.81–45863.04 | 0.186 | 0.185–0.187 |
| sort_int / large | micro | one complete SIZE-element dataset operation | my-qbe | 53726.33 | 53520.81–55529.70 | 0.226 | 0.225–0.228 |
| sort_int / large | micro | one complete SIZE-element dataset operation | rust | 63316.00 | 63060.74–63936.65 | 0.267 | 0.266–0.268 |
| sort_int / large | micro | one complete SIZE-element dataset operation | go | 237720.36 | 236482.49–238970.01 | 1.000 | 1.000–1.000 |
| sort_int / large | micro | one complete SIZE-element dataset operation | zig-safe | 65448.90 | 64742.60–66132.96 | 0.275 | 0.275–0.277 |
| sort_int / large | micro | one complete SIZE-element dataset operation | zig-fast | 45442.38 | 45063.44–46120.29 | 0.191 | 0.191–0.192 |
| sort_records / small | micro | one complete SIZE-element dataset operation | my-llvm | 1223.82 | 1217.46–1336.18 | 0.166 | 0.165–0.166 |
| sort_records / small | micro | one complete SIZE-element dataset operation | my-qbe | 1620.16 | 1609.77–1741.68 | 0.219 | 0.218–0.220 |
| sort_records / small | micro | one complete SIZE-element dataset operation | rust | 669.19 | 662.46–735.70 | 0.090 | 0.090–0.091 |
| sort_records / small | micro | one complete SIZE-element dataset operation | go | 7404.39 | 7374.96–7538.69 | 1.000 | 1.000–1.000 |
| sort_records / small | micro | one complete SIZE-element dataset operation | zig-safe | 803.68 | 793.36–813.48 | 0.108 | 0.108–0.109 |
| sort_records / small | micro | one complete SIZE-element dataset operation | zig-fast | 571.18 | 566.56–581.49 | 0.077 | 0.077–0.078 |
| sort_records / large | micro | one complete SIZE-element dataset operation | my-llvm | 62361.52 | 61849.46–63111.41 | 0.049 | 0.048–0.049 |
| sort_records / large | micro | one complete SIZE-element dataset operation | my-qbe | 79820.09 | 79218.36–81538.37 | 0.062 | 0.062–0.063 |
| sort_records / large | micro | one complete SIZE-element dataset operation | rust | 52264.42 | 50394.18–53931.36 | 0.041 | 0.040–0.041 |
| sort_records / large | micro | one complete SIZE-element dataset operation | go | 1283804.77 | 1276003.21–1290553.84 | 1.000 | 1.000–1.000 |
| sort_records / large | micro | one complete SIZE-element dataset operation | zig-safe | 116902.80 | 115459.13–118512.46 | 0.091 | 0.090–0.092 |
| sort_records / large | micro | one complete SIZE-element dataset operation | zig-fast | 93047.95 | 92371.54–109994.89 | 0.073 | 0.072–0.073 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 2702.21 | 2695.78–3505.17 | 3.219 | 3.191–3.243 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 3000.09 | 2982.04–3035.47 | 3.588 | 3.544–3.614 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | rust | 738.16 | 723.40–748.31 | 0.881 | 0.861–0.886 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | go | 840.26 | 819.17–853.79 | 1.000 | 1.000–1.000 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 1987.19 | 1970.10–2005.97 | 2.361 | 2.356–2.389 |
| lox_eval / small | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 1940.69 | 1918.88–1951.43 | 2.307 | 2.290–2.334 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | my-llvm | 39734.12 | 39598.54–52245.02 | 3.075 | 3.042–3.089 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | my-qbe | 43031.42 | 42881.36–44547.21 | 3.332 | 3.301–3.341 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | rust | 10981.42 | 10756.68–11371.33 | 0.848 | 0.837–0.865 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | go | 12931.81 | 12835.47–13274.44 | 1.000 | 1.000–1.000 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | zig-safe | 30689.66 | 30553.06–30786.19 | 2.370 | 2.353–2.383 |
| lox_eval / large | application | one complete bytecode program execution with SIZE loop iterations | zig-fast | 30094.61 | 29895.17–30923.24 | 2.326 | 2.310–2.332 |
| bytes_scan / small | micro | one full byte-buffer scan | my-llvm | 3.56 | 3.53–3.75 | 0.147 | 0.145–0.149 |
| bytes_scan / small | micro | one full byte-buffer scan | my-qbe | 8.35 | 8.21–8.55 | 0.345 | 0.343–0.351 |
| bytes_scan / small | micro | one full byte-buffer scan | rust | 17.86 | 17.74–17.89 | 0.736 | 0.722–0.752 |
| bytes_scan / small | micro | one full byte-buffer scan | go | 24.27 | 22.38–25.87 | 1.000 | 1.000–1.000 |
| bytes_scan / small | micro | one full byte-buffer scan | zig-safe | 27.29 | 26.56–28.07 | 1.128 | 1.107–1.153 |
| bytes_scan / small | micro | one full byte-buffer scan | zig-fast | 12.16 | 12.04–12.48 | 0.507 | 0.494–0.512 |
| bytes_scan / large | micro | one full byte-buffer scan | my-llvm | 76.12 | 75.16–102.77 | 0.074 | 0.074–0.075 |
| bytes_scan / large | micro | one full byte-buffer scan | my-qbe | 80.54 | 79.57–81.61 | 0.078 | 0.077–0.080 |
| bytes_scan / large | micro | one full byte-buffer scan | rust | 1074.42 | 1072.72–1076.74 | 1.041 | 1.030–1.052 |
| bytes_scan / large | micro | one full byte-buffer scan | go | 1031.04 | 998.37–1083.92 | 1.000 | 1.000–1.000 |
| bytes_scan / large | micro | one full byte-buffer scan | zig-safe | 1395.26 | 1351.07–2013.77 | 1.360 | 1.340–1.372 |
| bytes_scan / large | micro | one full byte-buffer scan | zig-fast | 703.33 | 700.11–731.85 | 0.683 | 0.673–0.691 |
| string_equal / small | micro | one string equality comparison | my-llvm | 4.17 | 4.13–4.22 | 0.893 | 0.877–0.898 |
| string_equal / small | micro | one string equality comparison | my-qbe | 22.28 | 22.17–22.37 | 4.749 | 4.719–4.813 |
| string_equal / small | micro | one string equality comparison | rust | 3.06 | 3.02–3.09 | 0.650 | 0.642–0.659 |
| string_equal / small | micro | one string equality comparison | go | 4.68 | 4.60–4.82 | 1.000 | 1.000–1.000 |
| string_equal / small | micro | one string equality comparison | zig-safe | 4.20 | 4.13–4.22 | 0.889 | 0.886–0.899 |
| string_equal / small | micro | one string equality comparison | zig-fast | 3.86 | 3.84–3.88 | 0.824 | 0.813–0.834 |
| string_equal / large | micro | one string equality comparison | my-llvm | 36.06 | 35.46–36.76 | 0.943 | 0.936–0.954 |
| string_equal / large | micro | one string equality comparison | my-qbe | 714.82 | 713.54–718.64 | 18.786 | 18.634–18.825 |
| string_equal / large | micro | one string equality comparison | rust | 30.98 | 30.59–31.78 | 0.814 | 0.802–0.821 |
| string_equal / large | micro | one string equality comparison | go | 38.08 | 37.53–39.43 | 1.000 | 1.000–1.000 |
| string_equal / large | micro | one string equality comparison | zig-safe | 65.08 | 64.86–65.67 | 1.707 | 1.705–1.725 |
| string_equal / large | micro | one string equality comparison | zig-fast | 50.63 | 50.30–50.98 | 1.333 | 1.322–1.339 |
| string_search / small | micro | one substring search | my-llvm | 19.77 | 19.67–19.88 | 0.789 | 0.786–0.798 |
| string_search / small | micro | one substring search | my-qbe | 25.12 | 24.81–25.48 | 1.005 | 0.999–1.009 |
| string_search / small | micro | one substring search | rust | 43.20 | 42.68–43.57 | 1.730 | 1.713–1.744 |
| string_search / small | micro | one substring search | go | 24.99 | 24.67–25.37 | 1.000 | 1.000–1.000 |
| string_search / small | micro | one substring search | zig-safe | 90.06 | 89.74–90.51 | 3.605 | 3.578–3.620 |
| string_search / small | micro | one substring search | zig-fast | 74.85 | 73.71–75.29 | 2.995 | 2.974–3.007 |
| string_search / large | micro | one substring search | my-llvm | 88.22 | 86.82–103.21 | 0.136 | 0.135–0.137 |
| string_search / large | micro | one substring search | my-qbe | 93.93 | 91.96–103.95 | 0.145 | 0.143–0.146 |
| string_search / large | micro | one substring search | rust | 1300.83 | 1297.83–1314.40 | 2.011 | 2.004–2.014 |
| string_search / large | micro | one substring search | go | 647.35 | 644.97–672.30 | 1.000 | 1.000–1.000 |
| string_search / large | micro | one substring search | zig-safe | 2995.74 | 2992.00–3258.66 | 4.630 | 4.613–4.638 |
| string_search / large | micro | one substring search | zig-fast | 2642.08 | 2637.69–2802.90 | 4.084 | 4.069–4.094 |
| string_split / small | micro | one full document split and result fold | my-llvm | 3470.86 | 3440.45–3506.16 | 3.322 | 3.302–3.331 |
| string_split / small | micro | one full document split and result fold | my-qbe | 4528.66 | 4490.87–4693.20 | 4.335 | 4.304–4.371 |
| string_split / small | micro | one full document split and result fold | rust | 557.59 | 550.62–569.09 | 0.533 | 0.531–0.539 |
| string_split / small | micro | one full document split and result fold | go | 1046.24 | 1037.80–1057.59 | 1.000 | 1.000–1.000 |
| string_split / small | micro | one full document split and result fold | zig-safe | 1034.89 | 1026.84–1084.10 | 0.989 | 0.985–0.995 |
| string_split / small | micro | one full document split and result fold | zig-fast | 962.93 | 952.50–971.44 | 0.920 | 0.917–0.926 |
| string_split / large | micro | one full document split and result fold | my-llvm | 216541.03 | 215764.16–224713.20 | 3.235 | 3.224–3.243 |
| string_split / large | micro | one full document split and result fold | my-qbe | 277379.79 | 275840.48–281817.38 | 4.129 | 4.116–4.158 |
| string_split / large | micro | one full document split and result fold | rust | 28435.35 | 27898.27–29086.21 | 0.424 | 0.421–0.426 |
| string_split / large | micro | one full document split and result fold | go | 67021.48 | 66672.19–72773.17 | 1.000 | 1.000–1.000 |
| string_split / large | micro | one full document split and result fold | zig-safe | 62501.20 | 62178.66–63254.30 | 0.933 | 0.924–0.936 |
| string_split / large | micro | one full document split and result fold | zig-fast | 58763.71 | 58498.06–59080.42 | 0.877 | 0.874–0.878 |
| string_join / small | micro | one full fragment join and output fold | my-llvm | 413.60 | 408.64–419.06 | 1.008 | 1.003–1.013 |
| string_join / small | micro | one full fragment join and output fold | my-qbe | 342.69 | 337.57–346.65 | 0.833 | 0.830–0.837 |
| string_join / small | micro | one full fragment join and output fold | rust | 220.91 | 218.11–228.56 | 0.535 | 0.534–0.539 |
| string_join / small | micro | one full fragment join and output fold | go | 411.02 | 406.81–415.59 | 1.000 | 1.000–1.000 |
| string_join / small | micro | one full fragment join and output fold | zig-safe | 318.12 | 315.30–323.59 | 0.773 | 0.770–0.775 |
| string_join / small | micro | one full fragment join and output fold | zig-fast | 273.20 | 269.25–277.40 | 0.666 | 0.660–0.670 |
| string_join / large | micro | one full fragment join and output fold | my-llvm | 22704.67 | 22477.16–23071.40 | 0.870 | 0.868–0.877 |
| string_join / large | micro | one full fragment join and output fold | my-qbe | 15385.38 | 15122.56–15852.69 | 0.588 | 0.587–0.597 |
| string_join / large | micro | one full fragment join and output fold | rust | 13591.03 | 13346.29–14166.16 | 0.519 | 0.517–0.523 |
| string_join / large | micro | one full fragment join and output fold | go | 26016.97 | 25754.59–26754.29 | 1.000 | 1.000–1.000 |
| string_join / large | micro | one full fragment join and output fold | zig-safe | 18266.90 | 18013.95–18523.00 | 0.700 | 0.698–0.704 |
| string_join / large | micro | one full fragment join and output fold | zig-fast | 16733.33 | 16474.53–16956.40 | 0.642 | 0.638–0.646 |
| int_parse / small | micro | one strict signed decimal parse | my-llvm | 10.30 | 10.23–10.45 | 0.424 | 0.423–0.428 |
| int_parse / small | micro | one strict signed decimal parse | my-qbe | 18.41 | 18.31–19.02 | 0.758 | 0.755–0.767 |
| int_parse / small | micro | one strict signed decimal parse | rust | 4.48 | 4.44–4.49 | 0.184 | 0.184–0.185 |
| int_parse / small | micro | one strict signed decimal parse | go | 24.29 | 24.01–24.53 | 1.000 | 1.000–1.000 |
| int_parse / small | micro | one strict signed decimal parse | zig-safe | 5.76 | 5.71–5.82 | 0.238 | 0.236–0.239 |
| int_parse / small | micro | one strict signed decimal parse | zig-fast | 5.76 | 5.70–5.84 | 0.237 | 0.237–0.238 |
| int_parse / large | micro | one strict signed decimal parse | my-llvm | 11.55 | 11.41–11.59 | 0.420 | 0.418–0.421 |
| int_parse / large | micro | one strict signed decimal parse | my-qbe | 19.67 | 19.53–19.81 | 0.717 | 0.714–0.719 |
| int_parse / large | micro | one strict signed decimal parse | rust | 5.17 | 5.09–5.34 | 0.189 | 0.187–0.190 |
| int_parse / large | micro | one strict signed decimal parse | go | 27.48 | 27.29–27.57 | 1.000 | 1.000–1.000 |
| int_parse / large | micro | one strict signed decimal parse | zig-safe | 6.80 | 6.75–6.95 | 0.248 | 0.246–0.249 |
| int_parse / large | micro | one strict signed decimal parse | zig-fast | 6.34 | 6.24–6.47 | 0.231 | 0.230–0.233 |
| int_format / small | micro | one signed decimal formatting and output fold | my-llvm | 60.14 | 59.79–60.43 | 3.627 | 3.620–3.658 |
| int_format / small | micro | one signed decimal formatting and output fold | my-qbe | 85.49 | 85.24–86.03 | 5.171 | 5.154–5.203 |
| int_format / small | micro | one signed decimal formatting and output fold | rust | 14.67 | 14.59–15.79 | 0.890 | 0.886–0.899 |
| int_format / small | micro | one signed decimal formatting and output fold | go | 16.51 | 16.41–16.71 | 1.000 | 1.000–1.000 |
| int_format / small | micro | one signed decimal formatting and output fold | zig-safe | 41.20 | 40.65–45.69 | 2.499 | 2.475–2.513 |
| int_format / small | micro | one signed decimal formatting and output fold | zig-fast | 32.89 | 32.58–33.18 | 1.989 | 1.983–2.009 |
| int_format / large | micro | one signed decimal formatting and output fold | my-llvm | 60.27 | 59.86–60.58 | 3.384 | 3.373–3.391 |
| int_format / large | micro | one signed decimal formatting and output fold | my-qbe | 87.47 | 86.86–91.09 | 4.906 | 4.878–4.930 |
| int_format / large | micro | one signed decimal formatting and output fold | rust | 15.26 | 15.11–15.94 | 0.858 | 0.854–0.871 |
| int_format / large | micro | one signed decimal formatting and output fold | go | 17.79 | 17.65–17.97 | 1.000 | 1.000–1.000 |
| int_format / large | micro | one signed decimal formatting and output fold | zig-safe | 43.43 | 43.15–43.77 | 2.441 | 2.426–2.448 |
| int_format / large | micro | one signed decimal formatting and output fold | zig-fast | 36.78 | 36.55–37.08 | 2.064 | 2.055–2.080 |
| word_count / small | application | one complete tokenize/count/fold job | my-llvm | 2323.10 | 2309.40–2345.17 | 3.614 | 3.591–3.621 |
| word_count / small | application | one complete tokenize/count/fold job | my-qbe | 3061.17 | 3047.86–3115.19 | 4.752 | 4.733–4.783 |
| word_count / small | application | one complete tokenize/count/fold job | rust | 352.32 | 348.20–354.68 | 0.548 | 0.542–0.549 |
| word_count / small | application | one complete tokenize/count/fold job | go | 643.70 | 638.80–655.93 | 1.000 | 1.000–1.000 |
| word_count / small | application | one complete tokenize/count/fold job | zig-safe | 246.36 | 244.81–250.02 | 0.382 | 0.381–0.385 |
| word_count / small | application | one complete tokenize/count/fold job | zig-fast | 191.78 | 189.92–195.04 | 0.298 | 0.297–0.300 |
| word_count / large | application | one complete tokenize/count/fold job | my-llvm | 21741.65 | 21595.25–22287.67 | 2.175 | 2.163–2.180 |
| word_count / large | application | one complete tokenize/count/fold job | my-qbe | 28316.55 | 28084.56–28441.03 | 2.831 | 2.820–2.838 |
| word_count / large | application | one complete tokenize/count/fold job | rust | 3786.69 | 3756.12–3876.17 | 0.379 | 0.377–0.380 |
| word_count / large | application | one complete tokenize/count/fold job | go | 10005.95 | 9933.69–10093.92 | 1.000 | 1.000–1.000 |
| word_count / large | application | one complete tokenize/count/fold job | zig-safe | 3154.97 | 3120.93–3239.37 | 0.316 | 0.314–0.317 |
| word_count / large | application | one complete tokenize/count/fold job | zig-fast | 2487.57 | 2456.14–2528.95 | 0.249 | 0.247–0.251 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | my-llvm | 17898.22 | 17776.20–18075.29 | 3.436 | 3.416–3.461 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | my-qbe | 26583.95 | 26400.18–26829.84 | 5.112 | 5.062–5.140 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | rust | 4086.70 | 4057.46–4717.51 | 0.784 | 0.778–0.793 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | go | 5214.98 | 5154.49–5306.91 | 1.000 | 1.000–1.000 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | zig-safe | 3712.57 | 3681.85–3872.61 | 0.713 | 0.708–0.717 |
| csv_aggregate / small | application | one complete CSV parse/validate/group/fold job | zig-fast | 2944.54 | 2900.63–2991.36 | 0.567 | 0.562–0.569 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | my-llvm | 295864.50 | 294595.02–297252.73 | 3.633 | 3.608–3.642 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | my-qbe | 436489.78 | 433078.53–440124.65 | 5.362 | 5.336–5.369 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | rust | 67086.68 | 66249.38–76713.15 | 0.825 | 0.819–0.827 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | go | 81441.63 | 80960.97–82990.09 | 1.000 | 1.000–1.000 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | zig-safe | 65095.55 | 64490.90–65551.53 | 0.798 | 0.795–0.801 |
| csv_aggregate / large | application | one complete CSV parse/validate/group/fold job | zig-fast | 52479.70 | 51890.96–53684.62 | 0.643 | 0.640–0.648 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 55822.24 | 55374.74–56315.57 | 1.874 | 1.869–1.881 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 91031.92 | 90494.03–93171.52 | 3.045 | 3.036–3.067 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 6899.64 | 6829.88–7097.68 | 0.232 | 0.229–0.235 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | go | 29804.34 | 29693.88–30163.19 | 1.000 | 1.000–1.000 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 11520.53 | 11448.04–11691.64 | 0.386 | 0.385–0.387 |
| json_transform / small | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 8226.23 | 8077.54–8411.67 | 0.276 | 0.274–0.277 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | my-llvm | 870893.52 | 866571.62–881931.34 | 1.758 | 1.745–1.775 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | my-qbe | 1443162.71 | 1438664.29–1466335.31 | 2.919 | 2.886–2.942 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | rust | 112741.45 | 112046.81–118547.66 | 0.228 | 0.227–0.230 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | go | 495336.70 | 487190.88–506954.43 | 1.000 | 1.000–1.000 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | zig-safe | 213653.48 | 212419.35–217169.64 | 0.431 | 0.427–0.437 |
| json_transform / large | application | one complete JSON parse/filter/transform/serialize/fold job | zig-fast | 167409.19 | 165923.97–171533.48 | 0.341 | 0.336–0.343 |

Calibration limits: record_reads/large (iteration_cap), tagged_stack/large (slowest_arm_budget), mutate_unique/small (iteration_cap), mutate_unique/large (iteration_cap), integer_math/small (slowest_arm_budget), integer_math/large (slowest_arm_budget), float_math/large (slowest_arm_budget), branch_predictable/large (slowest_arm_budget), call_direct/small (slowest_arm_budget), call_direct/large (slowest_arm_budget), call_indirect/large (slowest_arm_budget), option_handle/small (slowest_arm_budget), option_handle/large (slowest_arm_budget), result_propagate/small (slowest_arm_budget), result_propagate/large (slowest_arm_budget), binary_search/small (slowest_arm_budget), list_append/small (slowest_arm_budget), list_append/large (slowest_arm_budget), list_filter/small (slowest_arm_budget), dict_lookup_str/large (slowest_arm_budget), dict_update/small (slowest_arm_budget), dict_update_str/small (slowest_arm_budget), alloc_short/small (slowest_arm_budget), alloc_short/large (slowest_arm_budget), alloc_retained/small (slowest_arm_budget), mutate_nested/small (slowest_arm_budget), mutate_nested/large (slowest_arm_budget), sort_records/large (slowest_arm_budget), lox_eval/small (slowest_arm_budget), bytes_scan/small (iteration_cap), bytes_scan/large (slowest_arm_budget), string_equal/small (iteration_cap), string_equal/large (pilot_limit), string_search/large (slowest_arm_budget), string_split/large (slowest_arm_budget), string_join/large (slowest_arm_budget), int_format/small (slowest_arm_budget), word_count/large (slowest_arm_budget).

Per-core activity: {"2": 98.99008474706143, "3": 1.0707427605806898}.
Governor: powersave.
Sibling reservation is operator-managed; busy counters record average load and cannot exclude short interference.

Operation inventory coverage does not establish 80% of everyday CPU time. Separate application profiles are required.
