Candidate **dictionary-probe-64fb7e62-debug**: focused comparison.

Source `64fb7e62732db9cea46414248fd59ba362e31b56`; session `020b61e2-171b-4a5a-861a-f8ffffee62aa`.

All 80 frozen targets are retained in JSON. Each backend/case/size remains a separate target.

| Case / size | Backend | ns/iteration | Frozen ratio | Same-session original reference | Paired 95% interval | Current winner | Status |
|---|---|---:|---:|---:|---:|---|---|
| dict_lookup / small | my-llvm | 430.6658 | 1.708 | 1.781 (zig-fast) | 1.766–1.788 | zig-fast | open; slower_in_this_session |
| dict_lookup / small | my-qbe | 634.9440 | 2.519 | 2.626 (zig-fast) | 2.613–2.632 | zig-fast | open; slower_in_this_session |
| dict_lookup / large | my-llvm | 48747.9067 | 1.633 | 1.715 (go) | 1.663–1.735 | go | open; slower_in_this_session |
| dict_lookup / large | my-qbe | 63904.4278 | 2.141 | 2.248 (go) | 2.171–2.274 | go | open; slower_in_this_session |
| dict_lookup_str / small | my-llvm | 524.5794 | 1.343 | 1.399 (zig-fast) | 1.389–1.405 | zig-fast | open; slower_in_this_session |
| dict_lookup_str / small | my-qbe | 817.3322 | 2.092 | 2.180 (zig-fast) | 2.167–2.196 | zig-fast | open; slower_in_this_session |
| dict_lookup_str / large | my-llvm | 63837.2277 | 1.587 | 1.634 (go) | 1.620–1.650 | go | open; slower_in_this_session |
| dict_lookup_str / large | my-qbe | 85497.3300 | 2.126 | 2.188 (go) | 2.180–2.210 | go | open; slower_in_this_session |
| dict_update / small | my-llvm | 11379.9931 | 4.587 | 4.674 (zig-fast) | 4.361–4.763 | zig-fast | open; slower_in_this_session |
| dict_update / small | my-qbe | 15272.0484 | 6.156 | 6.273 (zig-fast) | 5.828–6.370 | zig-fast | open; slower_in_this_session |
| dict_update / large | my-llvm | 904678.9174 | 2.084 | 2.133 (zig-fast) | 2.088–2.152 | zig-fast | open; slower_in_this_session |
| dict_update / large | my-qbe | 1146545.3306 | 2.641 | 2.703 (zig-fast) | 2.605–2.718 | zig-fast | open; slower_in_this_session |
| dict_update_str / small | my-llvm | 13938.3661 | 2.818 | 2.964 (zig-fast) | 2.940–2.978 | zig-fast | open; slower_in_this_session |
| dict_update_str / small | my-qbe | 17712.0301 | 3.580 | 3.766 (zig-fast) | 3.731–3.808 | zig-fast | open; slower_in_this_session |
| dict_update_str / large | my-llvm | 1109828.0658 | 1.631 | 1.690 (go) | 1.689–1.699 | go | open; slower_in_this_session |
| dict_update_str / large | my-qbe | 1294451.8158 | 1.902 | 1.971 (go) | 1.969–1.981 | go | open; slower_in_this_session |
| set_dedup / small | my-llvm | 2777.5281 | 9.614 | 9.841 (zig-fast) | 9.791–9.944 | zig-fast | open; slower_in_this_session |
| set_dedup / small | my-qbe | 3637.4993 | 12.591 | 12.888 (zig-fast) | 12.833–12.964 | zig-fast | open; slower_in_this_session |
| set_dedup / large | my-llvm | 179603.0688 | 3.239 | 3.301 (zig-fast) | 3.290–3.317 | zig-fast | open; slower_in_this_session |
| set_dedup / large | my-qbe | 230320.7979 | 4.154 | 4.234 (zig-fast) | 4.218–4.294 | zig-fast | open; slower_in_this_session |
| mutate_nested / small | my-llvm | 730.4728 | 0.978 | 0.993 (my-llvm) | 0.987–0.995 | my-llvm | at_or_below; faster_in_this_session |
| mutate_nested / small | my-qbe | 838.3523 | 1.122 | 1.139 (my-llvm) | 1.126–1.140 | my-llvm | open; slower_in_this_session |
| mutate_nested / large | my-llvm | 7050.6528 | 0.989 | 1.017 (my-llvm) | 1.002–1.030 | my-llvm | at_or_below; slower_in_this_session |
| mutate_nested / large | my-qbe | 7909.6906 | 1.109 | 1.141 (my-llvm) | 1.123–1.153 | my-llvm | open; slower_in_this_session |
| string_search / small | my-llvm | 19.3667 | 0.975 | 1.002 (my-llvm) | 0.987–1.004 | my-llvm | at_or_below; inconclusive |
| string_search / small | my-qbe | 24.1897 | 1.217 | 1.251 (my-llvm) | 1.234–1.259 | my-llvm | open; slower_in_this_session |
| string_search / large | my-llvm | 85.9730 | 0.874 | 0.890 (my-qbe) | 0.867–0.897 | my-llvm | at_or_below; faster_in_this_session |
| string_search / large | my-qbe | 90.4082 | 0.919 | 0.936 (my-qbe) | 0.931–0.949 | my-llvm | at_or_below; faster_in_this_session |

Frozen-target ratios condition on historical medians and have no same-session implication by themselves.
Paired intervals resample the same round indices, then divide medians; archived rounds are never paired.
Overlapping intervals are inconclusive. Near target (within 5%) does not meet the numerical goal.
Faster in this exploratory session is not demonstrated faster: independent confirmation is required.
Winner selection, multiple comparisons and repeated tuning are not corrected by these intervals.
Calibration limits and host interference remain material, especially for tiny or eliminated kernels.
