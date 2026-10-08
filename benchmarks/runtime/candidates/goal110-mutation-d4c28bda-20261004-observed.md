LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T13`; source `d4c28bdace208ee284fe22cc63f074b183990967`; scope `subset`.
Execution identity SHA256: `161266991046ccd6190367e96b1098be171a1f15ed149df2e59e8e8084d901e8`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| mutate_unique / small (64) | 2.9211 | **1.0000** | 1.1442 | 1.2812 | 1.2289 | 1.4440 | 7.2121 | O / O | T13 |
| mutate_unique / large (1024) | 2.9232 | **1.0000** | 1.1449 | 1.2823 | 1.2286 | 1.4551 | 7.2059 | O / O | T13 |
| mutate_shared / small (64) | 9.9771 | 1.0340 | 5.3741 | 1.5700 | **1.0000** | 11.0875 | 15.4259 | O / O | T13 |
| mutate_shared / large (1024) | 65.4858 | **1.0000** | 8.8544 | 2.2447 | 1.7325 | 3.4656 | 4.1223 | O / O | T13 |
| record_reads / small (64) | 3.8008 | **1.0000** | 1.2025 | 1.3853 | 1.2846 | 1.4097 | 3.0617 | O / O | T13 |
| record_reads / large (4096) | 3.8753 | **1.0000** | 1.2089 | 1.4026 | 1.2431 | 1.4464 | 3.6482 | O / O | T13 |
| tagged_stack / small (64) | 5.6965 | **1.0000** | 1.0531 | 1.8438 | 1.8624 | 2.9293 | 3.7731 | O / O | T13 |
| tagged_stack / large (4096) | 5.7073 | **1.0000** | 1.0523 | 1.8383 | 1.8592 | 2.9234 | 3.7499 | O / O | T13 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T13 | `d4c28bdace208ee284fe22cc63f074b183990967`; `3f794887-6658-4d9c-84f3-ec14db91432c` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-unique-capture-20261004/experiments/runtime-goal110-unique-capture-20261004/screen.json) (`d1fd09958f088925d766384a98fdb9b26b42bfb80118e158527d9cbc2cfcca37`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
