LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T23`; source `1a3980631e79bc65f048acd063d7250800f01901`; scope `subset`.
Execution identity SHA256: `41e04335cc27012f9877db3f6cbb5d0a41b87645603abfe4869cf15c0a5b7326`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| list_append / small (64) | 112.2182 | 1.3628 | 1.9333 | 2.1863 | **1.0000** | 2.3995 | 4.0635 | O / O | T23 |
| list_append / large (4096) | 5345.9445 | 1.0907 | 1.9814 | 2.1433 | **1.0000** | 1.8588 | 3.7341 | O / O | T23 |
| list_filter / small (64) | 139.1761 | 1.0770 | 1.9613 | 1.4703 | **1.0000** | 2.3556 | 4.5698 | O / O | T23 |
| list_filter / large (4096) | 5397.4366 | **1.0000** | 1.9264 | 1.8166 | 1.3058 | 2.1953 | 5.1807 | O / O | T23 |
| sort_int / small (64) | 163.0341 | 1.3315 | 6.2027 | 1.6060 | **1.0000** | 1.3095 | 2.5459 | O / O | T23 |
| sort_int / large (4096) | 43055.9702 | 1.4655 | 5.2876 | 1.4752 | 1.0073 | **1.0000** | 1.2402 | P / O | T23 |
| mutate_nested / small (64) | 722.3398 | 1.5287 | 1.5612 | 1.5608 | 1.4159 | **1.0000** | 1.1565 | P / O | T23 |
| mutate_nested / large (1024) | 6964.8301 | 2.7224 | 2.4334 | 2.6850 | 2.4637 | **1.0000** | 1.1309 | P / O | T23 |
| dict_lookup / small (64) | 242.2439 | 2.5270 | 1.7406 | 1.9302 | **1.0000** | 1.8093 | 2.6274 | O / O | T23 |
| dict_lookup / large (4096) | 28710.4867 | 1.3829 | **1.0000** | 1.7417 | 1.3986 | 1.7195 | 2.2188 | O / O | T23 |
| dict_lookup_str / small (64) | 376.3802 | 2.2426 | 1.3774 | 1.2809 | **1.0000** | 1.4061 | 2.1836 | O / O | T23 |
| dict_lookup_str / large (4096) | 39638.9637 | 1.4502 | **1.0000** | 1.5207 | 1.2190 | 1.6267 | 2.1550 | O / O | T23 |
| dict_update_str / small (64) | 4722.3498 | 2.8825 | 1.9687 | 1.3140 | **1.0000** | 2.9540 | 3.7561 | O / O | T23 |
| dict_update_str / large (4096) | 656304.5789 | 1.4081 | **1.0000** | 1.2331 | 1.0832 | 1.6795 | 1.9685 | O / O | T23 |
| integer_math / small (64) | 87.6222 | **1.0000** | 1.3475 | 1.3396 | 1.1951 | 1.8522 | 4.7356 | O / O | T23 |
| integer_math / large (4096) | 5116.3262 | **1.0000** | 1.3754 | 1.3663 | 1.2326 | 1.9323 | 5.0436 | O / O | T23 |
| float_math / small (64) | 69.5057 | 1.5220 | 1.4749 | 1.4627 | **1.0000** | 2.6101 | 6.6248 | O / O | T23 |
| float_math / large (4096) | 4032.8056 | 1.5643 | 1.5243 | 1.4760 | **1.0000** | 2.7541 | 7.1190 | O / O | T23 |
| call_direct / small (64) | 43.0422 | **1.0000** | 1.4509 | 1.4092 | 1.0792 | 1.7664 | 17.8754 | O / O | T23 |
| call_direct / large (4096) | 1872.4606 | 1.0029 | 1.6970 | 1.5042 | **1.0000** | 2.2573 | 25.9222 | O / O | T23 |
| record_reads / small (64) | 3.7877 | **1.0000** | 1.2019 | 1.3863 | 1.2845 | 1.4058 | 3.0336 | O / O | T23 |
| record_reads / large (4096) | 3.8772 | **1.0000** | 1.2158 | 1.3819 | 1.2270 | 1.4536 | 5.3357 | O / O | T23 |
| tagged_stack / small (64) | 5.6853 | **1.0000** | 1.0509 | 1.8421 | 1.8684 | 2.5140 | 3.7534 | O / O | T23 |
| tagged_stack / large (4096) | 5.6855 | **1.0000** | 1.0550 | 1.8432 | 1.8596 | 2.5225 | 3.7416 | O / O | T23 |
| mutate_unique / small (64) | 2.9043 | **1.0000** | 1.1559 | 1.2861 | 1.2303 | 1.3552 | 6.9106 | O / O | T23 |
| mutate_unique / large (1024) | 2.9338 | **1.0000** | 1.1361 | 1.2706 | 1.2207 | 1.3425 | 6.8547 | O / O | T23 |
| mutate_shared / small (64) | 9.9566 | 1.0419 | 5.4084 | 1.5597 | **1.0000** | 11.0573 | 15.9027 | O / O | T23 |
| mutate_shared / large (1024) | 65.8456 | **1.0000** | 8.7702 | 2.2172 | 1.7165 | 3.3511 | 4.1241 | O / O | T23 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T23 | `1a3980631e79bc65f048acd063d7250800f01901`; `3a8d0bc2-e996-40d7-a049-0d1250097d63` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-integrated-20261004/.mylang-cache/goal110-integrated-debug/integrated-screen.json) (`fac94b55563f8755b8c359c32909ab5af3924c6a853b105974a2c27b2fded11c`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
