Candidate **a2dfdfa9-dictionary-word-debug**: focused comparison.

Source `a2dfdfa994e19ac3c80373a443913c7ecdef23d7`; session `d772c021-e811-45d7-b0f4-980e04c0dfb1`.

All 80 frozen targets are retained in JSON. Each backend/case/size remains a separate target.

| Case / size | Backend | ns/iteration | Frozen ratio | Same-session original reference | Paired 95% interval | Current winner | Status |
|---|---|---:|---:|---:|---:|---|---|
| dict_lookup / small | my-llvm | 346.4699 | 1.374 | 1.439 (zig-fast) | 1.424–1.446 | zig-fast | open; slower_in_this_session |
| dict_lookup / small | my-qbe | 585.2750 | 2.322 | 2.431 (zig-fast) | 2.423–2.441 | zig-fast | open; slower_in_this_session |
| dict_lookup / large | my-llvm | 38761.8189 | 1.299 | 1.385 (go) | 1.379–1.425 | go | open; slower_in_this_session |
| dict_lookup / large | my-qbe | 57638.4245 | 1.931 | 2.059 (go) | 2.045–2.129 | go | open; slower_in_this_session |
| dict_lookup_str / small | my-llvm | 545.4963 | 1.396 | 1.458 (zig-fast) | 1.455–1.472 | zig-fast | open; slower_in_this_session |
| dict_lookup_str / small | my-qbe | 814.8083 | 2.086 | 2.178 (zig-fast) | 2.170–2.192 | zig-fast | open; slower_in_this_session |
| dict_lookup_str / large | my-llvm | 64373.2468 | 1.601 | 1.656 (go) | 1.647–1.688 | go | open; slower_in_this_session |
| dict_lookup_str / large | my-qbe | 84318.9421 | 2.097 | 2.169 (go) | 2.146–2.200 | go | open; slower_in_this_session |
| dict_update / small | my-llvm | 11130.9139 | 4.487 | 4.647 (zig-fast) | 4.639–4.661 | zig-fast | open; slower_in_this_session |
| dict_update / small | my-qbe | 15331.5708 | 6.180 | 6.401 (zig-fast) | 6.399–6.431 | zig-fast | open; slower_in_this_session |
| dict_update / large | my-llvm | 897885.8033 | 2.069 | 2.119 (zig-fast) | 2.113–2.158 | zig-fast | open; slower_in_this_session |
| dict_update / large | my-qbe | 1134741.5410 | 2.614 | 2.677 (zig-fast) | 2.672–2.733 | zig-fast | open; slower_in_this_session |
| dict_update_str / small | my-llvm | 13365.2185 | 2.702 | 2.854 (zig-fast) | 2.782–2.871 | zig-fast | open; slower_in_this_session |
| dict_update_str / small | my-qbe | 17432.2253 | 3.524 | 3.723 (zig-fast) | 3.621–3.758 | zig-fast | open; slower_in_this_session |
| dict_update_str / large | my-llvm | 1090938.5200 | 1.603 | 1.668 (go) | 1.667–1.684 | go | open; slower_in_this_session |
| dict_update_str / large | my-qbe | 1281339.1200 | 1.883 | 1.959 (go) | 1.956–1.983 | go | open; slower_in_this_session |
| set_dedup / small | my-llvm | 2781.9393 | 9.629 | 9.867 (zig-fast) | 9.825–9.869 | zig-fast | open; slower_in_this_session |
| set_dedup / small | my-qbe | 3567.9734 | 12.350 | 12.655 (zig-fast) | 12.559–12.680 | zig-fast | open; slower_in_this_session |
| set_dedup / large | my-llvm | 178391.4010 | 3.218 | 3.292 (zig-fast) | 3.282–3.329 | zig-fast | open; slower_in_this_session |
| set_dedup / large | my-qbe | 228214.5267 | 4.116 | 4.212 (zig-fast) | 4.197–4.233 | zig-fast | open; slower_in_this_session |
| mutate_nested / small | my-llvm | 716.2229 | 0.959 | 0.979 (my-llvm) | 0.972–0.983 | my-llvm | at_or_below; faster_in_this_session |
| mutate_nested / small | my-qbe | 842.9436 | 1.129 | 1.153 (my-llvm) | 1.150–1.155 | my-llvm | open; slower_in_this_session |
| mutate_nested / large | my-llvm | 7138.3341 | 1.001 | 1.024 (my-llvm) | 1.009–1.037 | my-llvm | near_target; slower_in_this_session |
| mutate_nested / large | my-qbe | 8307.8030 | 1.165 | 1.192 (my-llvm) | 1.186–1.201 | my-llvm | open; slower_in_this_session |
| string_search / small | my-llvm | 19.3668 | 0.975 | 0.996 (my-llvm) | 0.993–1.004 | my-llvm | at_or_below; inconclusive |
| string_search / small | my-qbe | 24.1725 | 1.217 | 1.243 (my-llvm) | 1.238–1.255 | my-llvm | open; slower_in_this_session |
| string_search / large | my-llvm | 85.8175 | 0.872 | 0.896 (my-qbe) | 0.878–0.898 | my-llvm | at_or_below; faster_in_this_session |
| string_search / large | my-qbe | 90.3777 | 0.919 | 0.943 (my-qbe) | 0.925–0.950 | my-llvm | at_or_below; faster_in_this_session |

Frozen-target ratios condition on historical medians and have no same-session implication by themselves.
Paired intervals resample the same round indices, then divide medians; archived rounds are never paired.
Overlapping intervals are inconclusive. Near target (within 5%) does not meet the numerical goal.
Faster in this exploratory session is not demonstrated faster: independent confirmation is required.
Winner selection, multiple comparisons and repeated tuning are not corrected by these intervals.
Calibration limits and host interference remain material, especially for tiny or eliminated kernels.
