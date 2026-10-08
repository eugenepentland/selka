LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Current source `7e7773e43c934e67e32db3205a9f867049f9b46a`; latest complete integrated evidence: `B0`. Goal complete: **False**.
Mixed production evidence: True. States: `{"my-llvm": {"O": 71, "P": 3, "S": 6}, "my-qbe": {"O": 77, "S": 3}}`.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| record_reads / small (64) | 4.0033 | **1.0000** | 1.2072 | 1.3713 | 1.2724 | 1.4598 | 3.3636 | O / O | B0 |
| record_reads / large (4096) | 4.5650 | **1.0000** | 1.1234 | 1.3275 | 1.2162 | 1.4129 | 3.6264 | O / O | B0 |
| tagged_stack / small (64) | 6.4408 | **1.0000** | 1.0269 | 1.8674 | 1.9016 | 3.0195 | 4.0123 | O / O | B0 |
| tagged_stack / large (4096) | 7.6010 | **1.0000** | 1.0901 | 1.8459 | 1.8480 | 3.0251 | 3.6091 | O / O | B0 |
| mutate_unique / small (64) | 3.2762 | **1.0000** | 1.1804 | 1.2290 | 1.2094 | 1.5747 | 7.6379 | O / O | B0 |
| mutate_unique / large (1024) | 3.4398 | **1.0000** | 1.1486 | 1.3022 | 1.2176 | 1.4749 | 6.9678 | O / O | B0 |
| mutate_shared / small (64) | 11.8443 | 1.0509 | 5.1436 | 1.6182 | **1.0000** | 11.9037 | 15.1546 | O / O | B0 |
| mutate_shared / large (1024) | 96.3787 | **1.0000** | 8.6954 | 2.2145 | 1.7497 | 3.2446 | 3.9678 | O / O | B0 |
| integer_math / small (64) | 105.7685 | **1.0000** | 1.3640 | 1.3398 | 1.1877 | 1.8197 | 5.0610 | O / O | B0 |
| integer_math / large (4096) | 6392.6711 | **1.0000** | 1.3269 | 1.3768 | 1.2743 | 1.8377 | 5.2206 | O / O | B0 |
| float_math / small (64) | 91.4178 | 1.5745 | 1.5169 | 1.5610 | **1.0000** | 2.5058 | 6.5162 | O / O | B0 |
| float_math / large (4096) | 5916.6681 | 1.5073 | 1.4176 | 1.3404 | **1.0000** | 2.5444 | 6.5156 | O / O | B0 |
| branch_predictable / small (64) | 60.8996 | 1.0064 | 1.9126 | 2.1806 | **1.0000** | 2.1627 | 6.7382 | O / O | B0 |
| branch_predictable / large (4096) | 3857.2533 | **1.0000** | 2.0636 | 2.3532 | 1.0083 | 2.1880 | 6.9528 | O / O | B0 |
| branch_mixed / small (64) | 80.8896 | 1.0122 | 1.4726 | 1.7674 | **1.0000** | 1.4963 | 5.7080 | O / O | B0 |
| branch_mixed / large (4096) | 5392.7967 | **1.0000** | 1.6810 | 1.8025 | 1.0213 | 1.4794 | 5.4820 | O / O | B0 |
| record_construct / small (64) | 117.0071 | **1.0000** | 1.3917 | 1.5113 | 1.3046 | 1.8202 | 9.9000 | O / O | B0 |
| record_construct / large (4096) | 8032.3910 | **1.0000** | 1.4712 | 1.5283 | 1.3087 | 1.8130 | 9.9099 | O / O | B0 |
| record_update / small (64) | 135.6380 | **1.0000** | 1.3243 | 1.6213 | 1.2125 | 1.8238 | 12.6456 | O / O | B0 |
| record_update / large (4096) | 7810.9254 | **1.0000** | 1.4069 | 1.6395 | 1.3422 | 2.0557 | 14.0277 | O / O | B0 |
| call_direct / small (64) | 53.5971 | **1.0000** | 1.4886 | 1.4581 | 1.1261 | 1.6899 | 18.3277 | O / O | B0 |
| call_direct / large (4096) | 2328.1370 | **1.0000** | 1.7183 | 1.5253 | 1.0437 | 2.1965 | 27.0024 | O / O | B0 |
| call_indirect / small (64) | 119.4754 | 1.0756 | 1.3121 | 1.4906 | **1.0000** | 1.3423 | 8.8352 | O / O | B0 |
| call_indirect / large (4096) | 6998.9496 | 1.1581 | 1.3453 | 1.5799 | **1.0000** | 1.3756 | 9.6028 | O / O | B0 |
| option_handle / small (64) | 50.9477 | **1.0000** | 2.2121 | 2.3130 | 1.7541 | 2.2282 | 21.0979 | O / O | B0 |
| option_handle / large (4096) | 2433.8520 | **1.0000** | 2.8414 | 2.6665 | 2.1914 | 2.6353 | 27.9332 | O / O | B0 |
| result_propagate / small (64) | 67.8821 | **1.0000** | 2.2136 | 1.8857 | 1.2119 | 2.4130 | 19.6002 | O / O | B0 |
| result_propagate / large (4096) | 3981.3316 | **1.0000** | 2.4216 | 2.0523 | 1.4753 | 2.4797 | 22.2252 | O / O | B0 |
| binary_search / small (16) | 58.4475 | **1.0000** | 1.9603 | 1.5091 | 1.4379 | 1.9800 | 7.2034 | O / O | B0 |
| binary_search / large (256) | 1580.0181 | **1.0000** | 1.6992 | 3.4432 | 1.3305 | 1.9192 | 10.6123 | O / O | B0 |
| packet_decode / small (16) | 44.4827 | 1.1836 | 2.6728 | 1.8419 | **1.0000** | 2.1621 | 10.4416 | O / O | B0 |
| packet_decode / large (256) | 660.8722 | 1.2066 | 3.0576 | 1.9560 | **1.0000** | 2.2540 | 11.4511 | O / O | B0 |
| list_scan / small (64) | 49.0371 | **1.0000** | 1.2722 | 1.8459 | 1.3498 | 2.0643 | 5.0333 | O / O | B0 |
| list_scan / large (4096) | 3380.0797 | **1.0000** | 1.2127 | 1.6581 | 1.3890 | 1.5361 | 3.6315 | O / O | B0 |
| list_append / small (64) | 115.1849 | 1.3508 | 1.9135 | 2.1715 | **1.0000** | 2.6792 | 4.3123 | O / O | T9 |
| list_append / large (4096) | 5414.5766 | 1.0894 | 1.9588 | 2.1366 | **1.0000** | 2.4072 | 3.9112 | O / O | T9 |
| list_filter / small (64) | 177.9840 | 1.0990 | 1.9368 | 1.5068 | **1.0000** | 2.6375 | 4.7879 | O / O | B0 |
| list_filter / large (4096) | 6892.5245 | **1.0000** | 1.9650 | 1.8369 | 1.2613 | 2.4967 | 5.3200 | O / O | B0 |
| dict_lookup / small (64) | 300.9516 | 2.4699 | 1.7785 | 2.0004 | **1.0000** | 1.9397 | 3.2588 | O / O | B0 |
| dict_lookup / large (4096) | 33803.0743 | 1.3746 | **1.0000** | 1.7895 | 1.3927 | 1.7863 | 2.6548 | O / O | B0 |
| dict_lookup_str / small (64) | 467.1945 | 2.2418 | 1.4048 | 1.2997 | **1.0000** | 1.4698 | 2.2298 | O / O | B0 |
| dict_lookup_str / large (4096) | 48823.4819 | 1.4964 | **1.0000** | 1.5235 | 1.2243 | 1.6699 | 2.3235 | O / O | B0 |
| dict_update / small (64) | 2901.9315 | 2.4568 | 3.3928 | 2.0251 | **1.0000** | 5.0071 | 6.7677 | O / O | B0 |
| dict_update / large (4096) | 517545.3553 | 1.0873 | 1.1729 | 1.3933 | **1.0000** | 2.2007 | 2.7962 | O / O | B0 |
| dict_update_str / small (64) | 5815.2123 | 2.7412 | 1.9978 | 1.3210 | **1.0000** | 2.9788 | 3.8135 | O / O | B0 |
| dict_update_str / large (4096) | 813334.5833 | 1.5250 | **1.0000** | 1.2508 | 1.0737 | 1.7264 | 2.0366 | O / O | B0 |
| set_dedup / small (64) | 315.2532 | 3.2981 | 3.9658 | 2.1143 | **1.0000** | 10.2592 | 13.5868 | O / O | B0 |
| set_dedup / large (4096) | 65854.8194 | 1.1052 | 1.2774 | 1.4120 | **1.0000** | 3.3251 | 4.2926 | O / O | B0 |
| alloc_short / small (64) | 3.9337 | 20.8925 | 38.2879 | 88.5583 | **1.0000** | 1256.0525 | 1706.3399 | O / O | B0 |
| alloc_short / large (1024) | 3.9012 | 327.5994 | 536.1037 | 1374.7989 | **1.0000** | 19711.5691 | 26589.1038 | O / O | B0 |
| alloc_retained / small (64) | 1292.6997 | 1.0697 | 1.4853 | 1.0303 | **1.0000** | 2.3540 | 3.5644 | O / O | B0 |
| alloc_retained / large (1024) | 20710.2684 | 1.0504 | 1.2628 | 1.0366 | **1.0000** | 2.2667 | 3.3646 | O / O | B0 |
| mutate_nested / small (64) | 725.6244 | 1.5319 | 1.5667 | 1.6185 | 1.4389 | **1.0000** | 1.1389 | P / O | T9 |
| mutate_nested / large (1024) | 6984.3321 | 2.7290 | 2.4279 | 2.7002 | 2.5072 | **1.0000** | 1.2342 | P / O | T9 |
| sort_int / small (64) | 161.2429 | 1.3579 | 6.3145 | 1.6313 | **1.0000** | 1.3402 | 2.5690 | O / O | T9 |
| sort_int / large (4096) | 43559.5301 | 1.4501 | 5.2613 | 1.4596 | **1.0000** | 1.0125 | 1.2332 | P / O | T9 |
| sort_records / small (64) | 534.9452 | 1.1915 | 12.9614 | 1.4126 | **1.0000** | 2.2464 | 2.9003 | O / O | T9 |
| sort_records / large (4096) | 51470.2384 | **1.0000** | 23.3619 | 2.1788 | 1.7380 | 1.2257 | 1.4972 | O / O | T9 |
| lox_eval / small (16) | 738.1632 | **1.0000** | 1.1383 | 2.6921 | 2.6291 | 3.6607 | 4.0643 | O / O | B0 |
| lox_eval / large (256) | 10981.4215 | **1.0000** | 1.1776 | 2.7947 | 2.7405 | 3.6183 | 3.9186 | O / O | B0 |
| bytes_scan / small (64) | 3.4936 | 5.0533 | 6.7494 | 7.8731 | 3.4318 | **1.0000** | 2.3316 | S / O | G2 |
| bytes_scan / large (4096) | 75.9983 | 13.9961 | 13.2417 | 18.9235 | 9.1867 | **1.0000** | 1.0389 | S / S | G2 |
| string_equal / small (64) | 2.9688 | **1.0000** | 1.5119 | 1.3398 | 1.2732 | 1.3576 | 7.3130 | O / O | T3 |
| string_equal / large (4096) | 30.0438 | **1.0000** | 1.2331 | 2.1291 | 1.6502 | 1.1718 | 22.8477 | O / O | T3 |
| string_search / small (64) | 19.5710 | 2.1818 | 1.2578 | 4.5687 | 3.7994 | **1.0000** | 1.2554 | S / O | G2 |
| string_search / large (4096) | 87.2513 | 14.8271 | 7.3482 | 34.0815 | 30.1024 | **1.0000** | 1.0635 | S / S | G2 |
| string_split / small (64) | 557.5921 | **1.0000** | 1.8763 | 1.8560 | 1.7269 | 6.2247 | 8.1218 | O / O | B0 |
| string_split / large (4096) | 28435.3492 | **1.0000** | 2.3570 | 2.1980 | 2.0666 | 7.6152 | 9.7548 | O / O | B0 |
| string_join / small (64) | 218.7103 | **1.0000** | 1.8238 | 1.4099 | 1.2128 | 1.0464 | 1.3873 | S / O | G2 |
| string_join / large (4096) | 12572.0989 | 1.0570 | 2.0184 | 1.3990 | 1.3022 | **1.0000** | 1.0738 | S / S | G2 |
| int_parse / small (64) | 4.4765 | **1.0000** | 5.4265 | 1.2862 | 1.2858 | 2.3003 | 4.1124 | O / O | B0 |
| int_parse / large (4096) | 5.1722 | **1.0000** | 5.3121 | 1.3142 | 1.2250 | 2.2325 | 3.8033 | O / O | B0 |
| int_format / small (64) | 14.6652 | **1.0000** | 1.1260 | 2.8091 | 2.2430 | 4.1006 | 5.8296 | O / O | B0 |
| int_format / large (4096) | 15.2605 | **1.0000** | 1.1656 | 2.8462 | 2.4104 | 3.9492 | 5.7315 | O / O | B0 |
| word_count / small (16) | 191.7825 | 1.8371 | 3.3564 | 1.2846 | **1.0000** | 12.1132 | 15.9617 | O / O | B0 |
| word_count / large (256) | 2487.5682 | 1.5222 | 4.0224 | 1.2683 | **1.0000** | 8.7401 | 11.3832 | O / O | B0 |
| csv_aggregate / small (16) | 2944.5439 | 1.3879 | 1.7711 | 1.2608 | **1.0000** | 6.0784 | 9.0282 | O / O | B0 |
| csv_aggregate / large (256) | 52479.7031 | 1.2783 | 1.5519 | 1.2404 | **1.0000** | 5.6377 | 8.3173 | O / O | B0 |
| json_transform / small (16) | 6899.6433 | **1.0000** | 4.3197 | 1.6697 | 1.1923 | 8.0906 | 13.1937 | O / O | B0 |
| json_transform / large (256) | 112741.4467 | **1.0000** | 4.3936 | 1.8951 | 1.4849 | 7.7247 | 12.8006 | O / O | B0 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| B0 | `730a86e62b47c922dc1411d24b5868c3bd2132f3`; `d4378789-427a-4862-8718-52189af6bc96` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| G1 | `730a86e62b47c922dc1411d24b5868c3bd2132f3`; `c463b27d-f6d6-4fd0-84b7-086faff0d341` (15 rounds, 3 warmups), `f58b516a-fc86-49b6-b5fc-49bda2057537` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-b1-730a86e6-20261004-b.json.gz) (`22375b630b78f3fa98e5d6df5f878efa07d2dfb257172b7e52f29e3df6867221`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [confirmation](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-b1-730a86e6-20261004-a.json.gz) (`ec140a53df9f487d8e15cbbe4d1c28972f4263ab20c531ecd2677d2383fe50e1`), [checks](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-b1-730a86e6-20261004-normalized-checks.json) (`961b244c6cf9c1681b9e567d78556e773216c8b79121b96ab4eef190ad2f3c00`) |
| T3 | `5a60ef1039aca32657ef5877a464eb8a81d6c115`; `f247a239-ff91-4677-b1d7-58d18cfb9417` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-text-rf-host-20261004/.mylang-cache/goal110-join/join-screen.json) (`366c33f9783fc0036b32f206f17bc5a4b4c4da3b3cd575c534b468daa270fa4e`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| G2 | `957f97c6d9906ef11cf344ce055dada8be8446ea`; `653a9088-22ea-4938-b01e-8af53a1346fa` (15 rounds, 3 warmups), `0a7c22fa-7d2c-49b4-b64f-ffbb4803a5cf` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-integrated-rf-20261004/confirmation-b.json.gz) (`fdbb4001d3ebbeae82827a300c43c8dcbfc8dc1ad8fb0b9814919d367e1f0edc`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [confirmation](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-integrated-rf-20261004/confirmation-a.json.gz) (`e4cbbd2285fa3db65cf6b3a71d19f231cfe5fc8ad81189976271de0450a377fd`), [checks](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-join-957f97c6-rf-20261004-checks.json) (`b0b01b6cf9b40b32b1453ef510b7700f820bbb2b6edf6f0402e33f02a2ad4eea`) |
| T7 | `8043c4d9e0ad907c8a1b9e8416a1e58815eef0df`; `118e5b2a-23a0-4b29-a630-9906fbbe59af` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-sort-rotation-20261004/.mylang-cache/goal110-rotation-review/six-arm-screen.json) (`2874c15c578fed8df4cbad0cd2d7b4c55f1585ab82d7b1987d8bbf0817f9de88`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| T9 | `63842d3c32ab3079d878cff89224478543f9b7f3`; `693cd1d6-6d63-44cb-bfa2-3b1984e73325` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-presize-ready-20261004/.mylang-cache/goal110-presize-ready-review/six-arm-screen.json) (`20f286774876a955755458e47563c6318bf7913329f319ea04b4a9dd474564b2`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
