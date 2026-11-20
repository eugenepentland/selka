LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T16-index-screen`; source `14ffa2c0f385a11e5216bbdec5bdff429f9f981b`; scope `subset`.
Execution identity SHA256: `a24c5535105700bc843a523f172b40cef000bc5086e4b76c895a7ba0bb2cb4e1`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| mutate_unique / small (64) | 2.9026 | **1.0000** | 1.1507 | 1.2895 | 1.2372 | 1.3576 | 6.7536 | O / O | T16-index-screen |
| mutate_unique / large (1024) | 2.9017 | **1.0000** | 1.1506 | 1.2876 | 1.2364 | 1.4381 | 6.7739 | O / O | T16-index-screen |
| mutate_shared / small (64) | 9.7464 | 1.0487 | 5.5117 | 1.5753 | **1.0000** | 10.7449 | 16.0660 | O / O | T16-index-screen |
| mutate_shared / large (1024) | 65.1761 | **1.0000** | 8.9154 | 2.2502 | 1.7374 | 3.3703 | 4.1422 | O / O | T16-index-screen |
| record_reads / small (64) | 3.8071 | **1.0000** | 1.2034 | 1.3815 | 1.2844 | 1.4038 | 2.9913 | O / O | T16-index-screen |
| record_reads / large (4096) | 3.8857 | **1.0000** | 1.2041 | 1.4121 | 1.2350 | 1.4356 | 4.0160 | O / O | T16-index-screen |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T16-index-screen | `14ffa2c0f385a11e5216bbdec5bdff429f9f981b`; `a98d5b40-fcd9-4ba5-9b36-e66b39b79396` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-rf-20261004/.mylang-cache/goal110-index-forward-rf/screen.json) (`ef9df3eaa44a8f64585104e2a781d1f62b2c671f889dc81212d1ea284a9251b4`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
