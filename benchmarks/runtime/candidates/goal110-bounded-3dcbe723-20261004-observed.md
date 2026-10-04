LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T15-screen`; source `3dcbe723da4036fb7d69046e77e9f8cd16d7512f`; scope `subset`.
Execution identity SHA256: `9f2773320ddaca3261add25305a8f89238a146bf5d39b4966e6e05b994e168af`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_equal / small (64) | 2.9716 | **1.0000** | 1.5350 | 1.3503 | 1.2762 | 1.3533 | 5.2425 | O / O | T15-screen |
| string_equal / large (4096) | 12.7125 | 2.3949 | 2.8551 | 5.0571 | 3.9182 | **1.0000** | 18.3321 | P / O | T15-screen |
| bytes_scan / small (64) | 3.4605 | 5.0836 | 6.4961 | 8.1367 | 3.5117 | **1.0000** | 2.3598 | P / O | T15-screen |
| bytes_scan / large (4096) | 75.2132 | 13.9240 | 13.7789 | 19.4140 | 9.2528 | **1.0000** | 1.0460 | P / P | T15-screen |
| string_search / small (64) | 19.4907 | 2.1650 | 1.2431 | 4.5620 | 3.7860 | **1.0000** | 1.2551 | P / O | T15-screen |
| string_search / large (4096) | 89.1882 | 14.4187 | 7.1756 | 33.1569 | 29.2903 | **1.0000** | 1.0283 | P / P | T15-screen |
| string_join / small (64) | 168.6640 | 1.2937 | 2.3600 | 1.8307 | 1.5935 | **1.0000** | 1.1156 | P / O | T15-screen |
| string_join / large (4096) | 5781.1512 | 2.3278 | 4.3524 | 3.0621 | 2.8494 | **1.0000** | 1.0253 | P / P | T15-screen |
| int_parse / small (64) | 4.4356 | **1.0000** | 5.3763 | 1.2879 | 1.2795 | 2.2470 | 4.0857 | O / O | T15-screen |
| int_parse / large (4096) | 5.0592 | **1.0000** | 5.3222 | 1.3494 | 1.2402 | 2.2298 | 3.7989 | O / O | T15-screen |
| int_format / small (64) | 14.3856 | **1.0000** | 1.1217 | 2.7539 | 2.2209 | 4.1113 | 5.8676 | O / O | T15-screen |
| int_format / large (4096) | 15.4529 | **1.0000** | 1.1352 | 2.7366 | 2.3175 | 3.8842 | 5.5839 | O / O | T15-screen |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T15-screen | `3dcbe723da4036fb7d69046e77e9f8cd16d7512f`; `a8ccda6c-7cd0-4453-b6af-093639fff2ea` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-equality-bounded-20261004/.mylang-cache/goal110-equality-bounded-rf/bounded-screen.json) (`534dc46872ff9648412893132235f304943dd084f5c2e136c2033353510a56c6`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
