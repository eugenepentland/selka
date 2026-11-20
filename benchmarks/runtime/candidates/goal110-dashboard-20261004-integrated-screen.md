LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Current source `1a3980631e79bc65f048acd063d7250800f01901`; latest complete integrated evidence: `B0`. Goal complete: **False**.
Mixed production evidence: True. States: `{"my-llvm": {"O": 70, "P": 3, "S": 7}, "my-qbe": {"O": 77, "S": 3}}`.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| record_reads / small (64) | 3.7877 | **1.0000** | 1.2019 | 1.3863 | 1.2845 | 1.4058 | 3.0336 | O / O | T23 |
| record_reads / large (4096) | 3.8772 | **1.0000** | 1.2158 | 1.3819 | 1.2270 | 1.4536 | 5.3357 | O / O | T23 |
| tagged_stack / small (64) | 5.6853 | **1.0000** | 1.0509 | 1.8421 | 1.8684 | 2.5140 | 3.7534 | O / O | T23 |
| tagged_stack / large (4096) | 5.6855 | **1.0000** | 1.0550 | 1.8432 | 1.8596 | 2.5225 | 3.7416 | O / O | T23 |
| mutate_unique / small (64) | 2.9043 | **1.0000** | 1.1559 | 1.2861 | 1.2303 | 1.3552 | 6.9106 | O / O | T23 |
| mutate_unique / large (1024) | 2.9338 | **1.0000** | 1.1361 | 1.2706 | 1.2207 | 1.3425 | 6.8547 | O / O | T23 |
| mutate_shared / small (64) | 9.9566 | 1.0419 | 5.4084 | 1.5597 | **1.0000** | 11.0573 | 15.9027 | O / O | T23 |
| mutate_shared / large (1024) | 65.8456 | **1.0000** | 8.7702 | 2.2172 | 1.7165 | 3.3511 | 4.1241 | O / O | T23 |
| integer_math / small (64) | 87.6222 | **1.0000** | 1.3475 | 1.3396 | 1.1951 | 1.8522 | 4.7356 | O / O | T23 |
| integer_math / large (4096) | 5116.3262 | **1.0000** | 1.3754 | 1.3663 | 1.2326 | 1.9323 | 5.0436 | O / O | T23 |
| float_math / small (64) | 69.5057 | 1.5220 | 1.4749 | 1.4627 | **1.0000** | 2.6101 | 6.6248 | O / O | T23 |
| float_math / large (4096) | 4032.8056 | 1.5643 | 1.5243 | 1.4760 | **1.0000** | 2.7541 | 7.1190 | O / O | T23 |
| branch_predictable / small (64) | 60.8996 | 1.0064 | 1.9126 | 2.1806 | **1.0000** | 2.1627 | 6.7382 | O / O | B0 |
| branch_predictable / large (4096) | 3857.2533 | **1.0000** | 2.0636 | 2.3532 | 1.0083 | 2.1880 | 6.9528 | O / O | B0 |
| branch_mixed / small (64) | 80.8896 | 1.0122 | 1.4726 | 1.7674 | **1.0000** | 1.4963 | 5.7080 | O / O | B0 |
| branch_mixed / large (4096) | 5392.7967 | **1.0000** | 1.6810 | 1.8025 | 1.0213 | 1.4794 | 5.4820 | O / O | B0 |
| record_construct / small (64) | 117.0071 | **1.0000** | 1.3917 | 1.5113 | 1.3046 | 1.8202 | 9.9000 | O / O | B0 |
| record_construct / large (4096) | 8032.3910 | **1.0000** | 1.4712 | 1.5283 | 1.3087 | 1.8130 | 9.9099 | O / O | B0 |
| record_update / small (64) | 135.6380 | **1.0000** | 1.3243 | 1.6213 | 1.2125 | 1.8238 | 12.6456 | O / O | B0 |
| record_update / large (4096) | 7810.9254 | **1.0000** | 1.4069 | 1.6395 | 1.3422 | 2.0557 | 14.0277 | O / O | B0 |
| call_direct / small (64) | 43.0422 | **1.0000** | 1.4509 | 1.4092 | 1.0792 | 1.7664 | 17.8754 | O / O | T23 |
| call_direct / large (4096) | 1872.4606 | 1.0029 | 1.6970 | 1.5042 | **1.0000** | 2.2573 | 25.9222 | O / O | T23 |
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
| list_append / small (64) | 112.2182 | 1.3628 | 1.9333 | 2.1863 | **1.0000** | 2.3995 | 4.0635 | O / O | T23 |
| list_append / large (4096) | 5345.9445 | 1.0907 | 1.9814 | 2.1433 | **1.0000** | 1.8588 | 3.7341 | O / O | T23 |
| list_filter / small (64) | 139.1761 | 1.0770 | 1.9613 | 1.4703 | **1.0000** | 2.3556 | 4.5698 | O / O | T23 |
| list_filter / large (4096) | 5397.4366 | **1.0000** | 1.9264 | 1.8166 | 1.3058 | 2.1953 | 5.1807 | O / O | T23 |
| dict_lookup / small (64) | 242.2439 | 2.5270 | 1.7406 | 1.9302 | **1.0000** | 1.8093 | 2.6274 | O / O | T23 |
| dict_lookup / large (4096) | 28710.4867 | 1.3829 | **1.0000** | 1.7417 | 1.3986 | 1.7195 | 2.2188 | O / O | T23 |
| dict_lookup_str / small (64) | 376.3802 | 2.2426 | 1.3774 | 1.2809 | **1.0000** | 1.4061 | 2.1836 | O / O | T23 |
| dict_lookup_str / large (4096) | 39638.9637 | 1.4502 | **1.0000** | 1.5207 | 1.2190 | 1.6267 | 2.1550 | O / O | T23 |
| dict_update / small (64) | 2901.9315 | 2.4568 | 3.3928 | 2.0251 | **1.0000** | 5.0071 | 6.7677 | O / O | B0 |
| dict_update / large (4096) | 517545.3553 | 1.0873 | 1.1729 | 1.3933 | **1.0000** | 2.2007 | 2.7962 | O / O | B0 |
| dict_update_str / small (64) | 4722.3498 | 2.8825 | 1.9687 | 1.3140 | **1.0000** | 2.9540 | 3.7561 | O / O | T23 |
| dict_update_str / large (4096) | 656304.5789 | 1.4081 | **1.0000** | 1.2331 | 1.0832 | 1.6795 | 1.9685 | O / O | T23 |
| set_dedup / small (64) | 315.2532 | 3.2981 | 3.9658 | 2.1143 | **1.0000** | 10.2592 | 13.5868 | O / O | B0 |
| set_dedup / large (4096) | 65854.8194 | 1.1052 | 1.2774 | 1.4120 | **1.0000** | 3.3251 | 4.2926 | O / O | B0 |
| alloc_short / small (64) | 3.9337 | 20.8925 | 38.2879 | 88.5583 | **1.0000** | 1256.0525 | 1706.3399 | O / O | B0 |
| alloc_short / large (1024) | 3.9012 | 327.5994 | 536.1037 | 1374.7989 | **1.0000** | 19711.5691 | 26589.1038 | O / O | B0 |
| alloc_retained / small (64) | 1292.6997 | 1.0697 | 1.4853 | 1.0303 | **1.0000** | 2.3540 | 3.5644 | O / O | B0 |
| alloc_retained / large (1024) | 20710.2684 | 1.0504 | 1.2628 | 1.0366 | **1.0000** | 2.2667 | 3.3646 | O / O | B0 |
| mutate_nested / small (64) | 722.3398 | 1.5287 | 1.5612 | 1.5608 | 1.4159 | **1.0000** | 1.1565 | P / O | T23 |
| mutate_nested / large (1024) | 6964.8301 | 2.7224 | 2.4334 | 2.6850 | 2.4637 | **1.0000** | 1.1309 | P / O | T23 |
| sort_int / small (64) | 163.0341 | 1.3315 | 6.2027 | 1.6060 | **1.0000** | 1.3095 | 2.5459 | O / O | T23 |
| sort_int / large (4096) | 43055.9702 | 1.4655 | 5.2876 | 1.4752 | 1.0073 | **1.0000** | 1.2402 | P / O | T23 |
| sort_records / small (64) | 534.9452 | 1.1915 | 12.9614 | 1.4126 | **1.0000** | 2.2464 | 2.9003 | O / O | T9 |
| sort_records / large (4096) | 51470.2384 | **1.0000** | 23.3619 | 2.1788 | 1.7380 | 1.2257 | 1.4972 | O / O | T9 |
| lox_eval / small (16) | 738.1632 | **1.0000** | 1.1383 | 2.6921 | 2.6291 | 3.6607 | 4.0643 | O / O | B0 |
| lox_eval / large (256) | 10981.4215 | **1.0000** | 1.1776 | 2.7947 | 2.7405 | 3.6183 | 3.9186 | O / O | B0 |
| bytes_scan / small (64) | 3.4649 | 5.0849 | 6.8839 | 7.9880 | 3.4720 | **1.0000** | 2.3692 | S / O | G4 |
| bytes_scan / large (4096) | 75.3386 | 14.1340 | 13.3834 | 18.8670 | 9.2750 | **1.0000** | 1.0494 | S / S | G4 |
| string_equal / small (64) | 2.9979 | **1.0000** | 1.4842 | 1.3563 | 1.2735 | 1.3898 | 7.2728 | O / O | G4 |
| string_equal / large (4096) | 12.7438 | 2.4308 | 2.9087 | 5.0839 | 3.9540 | **1.0000** | 18.7675 | S / O | G4 |
| string_search / small (64) | 19.5696 | 2.1785 | 1.2547 | 4.5712 | 3.7904 | **1.0000** | 1.2549 | S / O | G4 |
| string_search / large (4096) | 87.5278 | 14.7733 | 7.3155 | 33.9751 | 30.0027 | **1.0000** | 1.0550 | S / S | G4 |
| string_split / small (64) | 557.5921 | **1.0000** | 1.8763 | 1.8560 | 1.7269 | 6.2247 | 8.1218 | O / O | B0 |
| string_split / large (4096) | 28435.3492 | **1.0000** | 2.3570 | 2.1980 | 2.0666 | 7.6152 | 9.7548 | O / O | B0 |
| string_join / small (64) | 162.8626 | 1.3451 | 2.4317 | 1.8955 | 1.6336 | **1.0000** | 1.1664 | S / O | G4 |
| string_join / large (4096) | 5763.9243 | 2.3079 | 4.3569 | 3.0551 | 2.8575 | **1.0000** | 1.0115 | S / S | G4 |
| int_parse / small (64) | 4.4652 | **1.0000** | 5.4083 | 1.2816 | 1.2776 | 2.2302 | 4.0938 | O / O | T14 |
| int_parse / large (4096) | 5.0104 | **1.0000** | 5.3917 | 1.3551 | 1.2539 | 2.2453 | 3.8461 | O / O | T14 |
| int_format / small (64) | 14.7507 | **1.0000** | 1.1094 | 2.7537 | 2.1862 | 3.9779 | 5.8586 | O / O | T14 |
| int_format / large (4096) | 15.0874 | **1.0000** | 1.1681 | 2.8252 | 2.3938 | 3.9588 | 5.8056 | O / O | T14 |
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
| T11 | `d9d6362f0914df21078070288959fea3b73603e7`; `9945beb4-2ca0-47fe-b6ef-50f7363aea38` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-text-combined-20261004/.mylang-cache/goal110-text-combined/combined-screen.json) (`e8a73bf10eb4fd87ce41155a5497945eb61338e3ac793a835cca8d147fa15790`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| T12 | `6910e08351a50ce8524a5e37d3f6c23feb4d3383`; `def9ac1d-2d1e-4914-8b41-fab6208c5474` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-collections-hot-20261004/.mylang-cache/goal110-append-range-review/six-arm-screen.json) (`4a65e858b932c803e59a13a787137622f6ad35392490c2f09d91ae40d22ae40b`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| T13 | `d4c28bdace208ee284fe22cc63f074b183990967`; `3f794887-6658-4d9c-84f3-ec14db91432c` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-unique-capture-20261004/experiments/runtime-goal110-unique-capture-20261004/screen.json) (`d1fd09958f088925d766384a98fdb9b26b42bfb80118e158527d9cbc2cfcca37`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| T14 | `448ee20c66eafaad72a6d3ba024fbeb1f6f599df`; `d4cdb9de-8914-401b-ba4c-6c4fc4f56f8d` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-join-short-20261004/.mylang-cache/goal110-join-short/short-screen.json) (`3072006fbf8f17a71b15dddfc689ad667b9831afa47eb45bda497d9461fb9278`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| G4 | `6cf7bdce11bc205862bf75b9d9ce72e46caad0a2`; `bcc5273b-e669-4cf3-9682-5580ed530ff0` (15 rounds, 3 warmups), `620102fe-f182-439c-a8ff-2bbc42b25152` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-g4-rf-20261004/confirmation-b.json.gz) (`59aaa8b1316cb882925ef3b9bb72ae1e7934a3554725a0e1efbb97da39aff3bb`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [confirmation](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-g4-rf-20261004/confirmation-a.json.gz) (`804fb8a355c4c49ac6ec5c49015e4208d49ddd58947809bdc28f80e78ef7fcfb`), [checks](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-g4-6cf7bdce-rf-20261004-checks.json) (`9d66395ac1fe01f4fa9fef8d080f726b15ed6c0fb8ebcabab4f8caa628d85f64`) |
| T16-index-screen | `14ffa2c0f385a11e5216bbdec5bdff429f9f981b`; `a98d5b40-fcd9-4ba5-9b36-e66b39b79396` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-rf-20261004/.mylang-cache/goal110-index-forward-rf/screen.json) (`ef9df3eaa44a8f64585104e2a781d1f62b2c671f889dc81212d1ea284a9251b4`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |
| T23 | `1a3980631e79bc65f048acd063d7250800f01901`; `3a8d0bc2-e996-40d7-a049-0d1250097d63` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-integrated-20261004/.mylang-cache/goal110-integrated-debug/integrated-screen.json) (`fac94b55563f8755b8c359c32909ab5af3924c6a853b105974a2c27b2fded11c`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
