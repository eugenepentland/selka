Candidate **milestone-d348026f-debug-20261003**: focused comparison.

Source `d348026f52eb02792e8c0c1d07dae7f6c8e26bd7`; session `27422a64-ac35-47f8-ad6d-481c66b43b2b`.

All 80 frozen targets are retained in JSON. Each backend/case/size remains a separate target.

| Case / size | Backend | ns/iteration | Frozen ratio | Same-session original reference | Paired 95% interval | Current winner | Status |
|---|---|---:|---:|---:|---:|---|---|
| integer_math / small | my-llvm | 257.1323 | 2.820 | 2.435 (rust) | 2.398–2.464 | rust | open; slower_in_this_session |
| integer_math / small | my-qbe | 636.0768 | 6.977 | 6.023 (rust) | 5.909–6.131 | rust | open; slower_in_this_session |
| integer_math / large | my-llvm | 15664.3984 | 2.952 | 2.707 (rust) | 2.574–2.844 | rust | open; slower_in_this_session |
| integer_math / large | my-qbe | 39730.9154 | 7.489 | 6.866 (rust) | 6.523–7.207 | rust | open; slower_in_this_session |
| float_math / small | my-llvm | 223.4969 | 3.158 | 2.710 (zig-fast) | 2.654–2.748 | zig-fast | open; slower_in_this_session |
| float_math / small | my-qbe | 586.3856 | 8.284 | 7.111 (zig-fast) | 7.006–7.636 | zig-fast | open; slower_in_this_session |
| float_math / large | my-llvm | 13955.5551 | 3.383 | 2.853 (zig-fast) | 2.725–2.881 | zig-fast | open; slower_in_this_session |
| float_math / large | my-qbe | 36840.5373 | 8.930 | 7.532 (zig-fast) | 7.494–7.728 | zig-fast | open; slower_in_this_session |
| call_direct / small | my-llvm | 77.4999 | 1.776 | 1.746 (rust) | 1.736–1.751 | rust | open; slower_in_this_session |
| call_direct / small | my-qbe | 1525.3474 | 34.956 | 34.369 (rust) | 34.195–34.567 | rust | open; slower_in_this_session |
| call_direct / large | my-llvm | 5038.5141 | 2.635 | 2.206 (rust) | 1.927–2.471 | zig-fast | open; slower_in_this_session |
| call_direct / large | my-qbe | 115834.0953 | 60.569 | 50.715 (rust) | 46.907–56.838 | zig-fast | open; slower_in_this_session |
| record_construct / small | my-llvm | 246.7520 | 2.292 | 2.240 (rust) | 2.233–2.244 | rust | open; slower_in_this_session |
| record_construct / small | my-qbe | 1751.2545 | 16.269 | 15.899 (rust) | 15.798–16.071 | rust | open; slower_in_this_session |
| record_construct / large | my-llvm | 15100.4134 | 2.353 | 2.312 (rust) | 2.303–2.320 | rust | open; slower_in_this_session |
| record_construct / large | my-qbe | 108935.6490 | 16.973 | 16.680 (rust) | 16.618–16.789 | rust | open; slower_in_this_session |
| record_update / small | my-llvm | 247.6596 | 2.276 | 2.258 (rust) | 2.249–2.266 | rust | open; slower_in_this_session |
| record_update / small | my-qbe | 2116.9360 | 19.455 | 19.297 (rust) | 19.142–19.867 | rust | open; slower_in_this_session |
| record_update / large | my-llvm | 18064.7921 | 2.829 | 2.127 (rust) | 2.027–2.356 | rust | open; slower_in_this_session |
| record_update / large | my-qbe | 162688.2173 | 25.479 | 19.153 (rust) | 16.656–21.633 | rust | open; slower_in_this_session |
| option_handle / small | my-llvm | 115.5768 | 2.463 | 2.245 (rust) | 2.144–2.341 | rust | open; slower_in_this_session |
| option_handle / small | my-qbe | 1962.9862 | 41.829 | 38.130 (rust) | 36.059–38.657 | rust | open; slower_in_this_session |
| option_handle / large | my-llvm | 9470.3781 | 4.152 | 2.550 (rust) | 2.273–2.693 | rust | open; slower_in_this_session |
| option_handle / large | my-qbe | 168701.7835 | 73.969 | 45.430 (rust) | 41.667–48.177 | rust | open; slower_in_this_session |
| result_propagate / small | my-llvm | 206.1539 | 3.372 | 2.258 (rust) | 2.136–2.342 | rust | open; slower_in_this_session |
| result_propagate / small | my-qbe | 2956.3953 | 48.350 | 32.387 (rust) | 29.965–34.150 | rust | open; slower_in_this_session |
| result_propagate / large | my-llvm | 13182.5274 | 3.979 | 2.716 (rust) | 2.631–2.822 | rust | open; slower_in_this_session |
| result_propagate / large | my-qbe | 181553.8416 | 54.802 | 37.404 (rust) | 35.616–38.863 | rust | open; slower_in_this_session |
| binary_search / small | my-llvm | 176.9540 | 3.424 | 1.972 (rust) | 1.881–2.014 | rust | open; slower_in_this_session |
| binary_search / small | my-qbe | 869.0456 | 16.817 | 9.687 (rust) | 9.219–9.924 | rust | open; slower_in_this_session |
| binary_search / large | my-llvm | 5067.3957 | 3.459 | 1.955 (rust) | 1.885–1.993 | rust | open; slower_in_this_session |
| binary_search / large | my-qbe | 29701.3851 | 20.273 | 11.458 (rust) | 11.020–11.698 | rust | open; slower_in_this_session |
| tagged_stack / small | my-llvm | 34.3629 | 6.023 | 3.187 (rust) | 3.106–3.921 | rust | open; slower_in_this_session |
| tagged_stack / small | my-qbe | 38.9369 | 6.824 | 3.612 (rust) | 3.559–4.549 | rust | open; slower_in_this_session |
| tagged_stack / large | my-llvm | 33.6352 | 5.903 | 3.080 (rust) | 2.803–3.503 | rust | open; slower_in_this_session |
| tagged_stack / large | my-qbe | 38.9985 | 6.844 | 3.572 (rust) | 3.473–4.022 | rust | open; slower_in_this_session |
| int_parse / small | my-llvm | 18.8268 | 4.199 | 2.259 (rust) | 2.154–2.285 | rust | open; slower_in_this_session |
| int_parse / small | my-qbe | 32.9153 | 7.341 | 3.949 (rust) | 3.787–4.027 | rust | open; slower_in_this_session |
| int_parse / large | my-llvm | 21.7086 | 4.291 | 2.271 (rust) | 2.213–2.328 | rust | open; slower_in_this_session |
| int_parse / large | my-qbe | 35.9486 | 7.106 | 3.760 (rust) | 3.728–3.822 | rust | open; slower_in_this_session |
| int_format / small | my-llvm | 102.6603 | 7.077 | 3.855 (rust) | 3.783–3.906 | rust | open; slower_in_this_session |
| int_format / small | my-qbe | 150.3996 | 10.368 | 5.648 (rust) | 5.502–5.679 | rust | open; slower_in_this_session |
| int_format / large | my-llvm | 106.3202 | 7.006 | 3.715 (rust) | 3.631–3.780 | rust | open; slower_in_this_session |
| int_format / large | my-qbe | 152.7514 | 10.065 | 5.337 (rust) | 5.251–5.428 | rust | open; slower_in_this_session |
| json_transform / small | my-llvm | 98194.4853 | 13.747 | 7.930 (rust) | 7.802–8.151 | rust | open; slower_in_this_session |
| json_transform / small | my-qbe | 163267.2600 | 22.856 | 13.184 (rust) | 13.001–13.475 | rust | open; slower_in_this_session |
| json_transform / large | my-llvm | 1520525.2122 | 12.239 | 7.523 (rust) | 7.391–7.819 | rust | open; slower_in_this_session |
| json_transform / large | my-qbe | 2593643.0822 | 20.877 | 12.833 (rust) | 12.594–13.392 | rust | open; slower_in_this_session |
| lox_eval / small | my-llvm | 5023.7718 | 7.002 | 3.920 (rust) | 3.821–4.000 | rust | open; slower_in_this_session |
| lox_eval / small | my-qbe | 5231.1496 | 7.291 | 4.082 (rust) | 3.989–4.219 | rust | open; slower_in_this_session |
| lox_eval / large | my-llvm | 74464.1158 | 6.983 | 3.942 (rust) | 3.783–4.031 | rust | open; slower_in_this_session |
| lox_eval / large | my-qbe | 75483.1272 | 7.078 | 3.996 (rust) | 3.846–4.057 | rust | open; slower_in_this_session |

Frozen-target ratios condition on historical medians and have no same-session implication by themselves.
Paired intervals resample the same round indices, then divide medians; archived rounds are never paired.
Overlapping intervals are inconclusive. Near target (within 5%) does not meet the numerical goal.
Faster in this exploratory session is not demonstrated faster: independent confirmation is required.
Winner selection, multiple comparisons and repeated tuning are not corrected by these intervals.
Calibration limits and host interference remain material, especially for tiny or eliminated kernels.
