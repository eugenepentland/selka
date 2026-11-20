LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T7`; source `8043c4d9e0ad907c8a1b9e8416a1e58815eef0df`; scope `subset`.
Execution identity SHA256: `c3ede1b845bcc0fbc55d60e791914b494e84083a1c9149f9b76b963c095d96f6`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| sort_records / small (64) | 542.3958 | 1.1991 | 12.8080 | 1.4046 | **1.0000** | 2.2466 | 2.8732 | O / O | T7 |
| sort_records / large (4096) | 49756.5747 | **1.0000** | 24.2944 | 2.2739 | 1.8195 | 1.2157 | 1.5656 | O / O | T7 |
| sort_int / small (64) | 162.9593 | 1.3593 | 6.3105 | 1.6248 | **1.0000** | 1.3607 | 2.5518 | O / O | T7 |
| sort_int / large (4096) | 44161.2680 | 1.4352 | 5.2027 | 1.4470 | 1.0013 | **1.0000** | 1.2097 | P / O | T7 |
| mutate_nested / small (64) | 719.2670 | 1.5723 | 1.5873 | 1.6002 | 1.4487 | **1.0000** | 1.1548 | P / O | T7 |
| mutate_nested / large (1024) | 7131.9083 | 2.6814 | 2.3925 | 2.6951 | 2.4699 | **1.0000** | 1.2309 | P / O | T7 |
| list_append / small (64) | 116.6963 | 1.3316 | 1.8960 | 2.1422 | **1.0000** | 2.6790 | 4.2871 | O / O | T7 |
| list_append / large (4096) | 5492.3848 | 1.0786 | 1.9315 | 2.1213 | **1.0000** | 2.3875 | 3.8839 | O / O | T7 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T7 | `8043c4d9e0ad907c8a1b9e8416a1e58815eef0df`; `118e5b2a-23a0-4b29-a630-9906fbbe59af` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-sort-rotation-20261004/.mylang-cache/goal110-rotation-review/six-arm-screen.json) (`2874c15c578fed8df4cbad0cd2d7b4c55f1585ab82d7b1987d8bbf0817f9de88`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
