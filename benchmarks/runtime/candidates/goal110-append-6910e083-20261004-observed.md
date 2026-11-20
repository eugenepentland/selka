LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T12`; source `6910e08351a50ce8524a5e37d3f6c23feb4d3383`; scope `subset`.
Execution identity SHA256: `28478bcfc04e59b8581f4391d9a53761381c09611f4882d9bbad1659802d855f`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| list_append / small (64) | 112.7540 | 1.3635 | 1.9205 | 2.1700 | **1.0000** | 2.3878 | 4.0291 | O / O | T12 |
| list_append / large (4096) | 5316.1692 | 1.0883 | 1.9989 | 2.1341 | **1.0000** | 1.8502 | 3.7854 | O / O | T12 |
| list_filter / small (64) | 139.3599 | 1.0775 | 1.9520 | 1.4605 | **1.0000** | 2.5734 | 4.5527 | O / O | T12 |
| list_filter / large (4096) | 5380.9056 | **1.0000** | 1.9535 | 1.8042 | 1.3147 | 2.3925 | 5.2128 | O / O | T12 |
| sort_int / small (64) | 162.8525 | 1.3413 | 6.2696 | 1.6145 | **1.0000** | 1.3460 | 2.6245 | O / O | T12 |
| sort_int / large (4096) | 43807.5292 | 1.4408 | 5.2225 | 1.4501 | **1.0000** | 1.0108 | 1.2168 | P / O | T12 |
| mutate_nested / small (64) | 719.5282 | 1.5519 | 1.5747 | 1.5739 | 1.4659 | **1.0000** | 1.1730 | P / O | T12 |
| mutate_nested / large (1024) | 6938.5819 | 2.7463 | 2.4531 | 2.7418 | 2.5262 | **1.0000** | 1.1791 | P / O | T12 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T12 | `6910e08351a50ce8524a5e37d3f6c23feb4d3383`; `def9ac1d-2d1e-4914-8b41-fab6208c5474` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-collections-hot-20261004/.mylang-cache/goal110-append-range-review/six-arm-screen.json) (`4a65e858b932c803e59a13a787137622f6ad35392490c2f09d91ae40d22ae40b`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
