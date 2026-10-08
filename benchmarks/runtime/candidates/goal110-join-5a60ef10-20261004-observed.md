LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T3`; source `5a60ef1039aca32657ef5877a464eb8a81d6c115`; scope `subset`.
Execution identity SHA256: `a6d89854d618bf06aca615f184d5ff38d15751f2c21bc67d710266e371adbbee`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_join / small (64) | 216.4277 | **1.0000** | 1.8303 | 1.4205 | 1.2220 | 1.0520 | 1.3984 | P / O | T3 |
| string_join / large (4096) | 12641.8773 | 1.0560 | 2.0088 | 1.3856 | 1.2960 | **1.0000** | 1.0594 | P / P | T3 |
| string_equal / small (64) | 2.9688 | **1.0000** | 1.5119 | 1.3398 | 1.2732 | 1.3576 | 7.3130 | O / O | T3 |
| string_equal / large (4096) | 30.0438 | **1.0000** | 1.2331 | 2.1291 | 1.6502 | 1.1718 | 22.8477 | O / O | T3 |
| string_search / small (64) | 19.4227 | 2.1785 | 1.2610 | 4.5741 | 3.8087 | **1.0000** | 1.2565 | P / O | T3 |
| string_search / large (4096) | 87.0177 | 14.7777 | 7.3699 | 33.8576 | 29.9673 | **1.0000** | 1.0584 | P / P | T3 |
| bytes_scan / small (64) | 3.4672 | 5.0991 | 6.8245 | 8.1435 | 3.4708 | **1.0000** | 2.3453 | P / O | T3 |
| bytes_scan / large (4096) | 75.6007 | 14.0428 | 13.4011 | 18.8035 | 9.2021 | **1.0000** | 1.0412 | P / P | T3 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T3 | `5a60ef1039aca32657ef5877a464eb8a81d6c115`; `f247a239-ff91-4677-b1d7-58d18cfb9417` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-text-rf-host-20261004/.mylang-cache/goal110-join/join-screen.json) (`366c33f9783fc0036b32f206f17bc5a4b4c4da3b3cd575c534b468daa270fa4e`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
