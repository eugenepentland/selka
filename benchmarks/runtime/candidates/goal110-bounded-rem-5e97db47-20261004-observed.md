LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T18-bounded-bias-screen`; source `5e97db47f08f667d97419abafd098df263a2aec3`; scope `subset`.
Execution identity SHA256: `5b5c3f59fb743640f28e17beb19c9ff66b3fd8ffca93fe997844c363fc826749`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| list_append / small (64) | 113.3803 | 1.3419 | 1.9003 | 2.1764 | **1.0000** | 2.3764 | 3.9083 | O / O | T18-bounded-bias-screen |
| list_append / large (4096) | 5300.6918 | 1.0872 | 1.9977 | 2.1281 | **1.0000** | 1.8540 | 3.7688 | O / O | T18-bounded-bias-screen |
| list_filter / small (64) | 139.1230 | 1.0762 | 1.9527 | 1.4660 | **1.0000** | 2.3819 | 4.5908 | O / O | T18-bounded-bias-screen |
| list_filter / large (4096) | 5407.0530 | **1.0000** | 1.9447 | 1.7754 | 1.2987 | 2.1649 | 5.1430 | O / O | T18-bounded-bias-screen |
| sort_int / small (64) | 162.3799 | 1.3376 | 6.2304 | 1.6136 | **1.0000** | 1.3169 | 2.5358 | O / O | T18-bounded-bias-screen |
| sort_int / large (4096) | 43074.1262 | 1.4620 | 5.2921 | 1.4617 | 1.0032 | **1.0000** | 1.2375 | P / O | T18-bounded-bias-screen |
| mutate_nested / small (64) | 722.3879 | 1.5264 | 1.5576 | 1.5512 | 1.4125 | **1.0000** | 1.1752 | P / O | T18-bounded-bias-screen |
| mutate_nested / large (1024) | 7022.9228 | 2.6785 | 2.4036 | 2.6759 | 2.4480 | **1.0000** | 1.2310 | P / O | T18-bounded-bias-screen |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T18-bounded-bias-screen | `5e97db47f08f667d97419abafd098df263a2aec3`; `296b1b31-17fd-495e-906f-be325ac66f02` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-bounded-rem-20261004/.mylang-cache/goal110-bounded-rem-debug/screen.json) (`561e2ad455c0a0e8843070b993d59fbdae3dbbb212d5d2f10a25dd6a03873887`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
