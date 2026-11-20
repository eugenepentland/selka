LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T9`; source `63842d3c32ab3079d878cff89224478543f9b7f3`; scope `subset`.
Execution identity SHA256: `89ea83158ed21f56dacbf0202582fd88a23033b1bcd8f815d12ca2edca5956c3`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| sort_records / small (64) | 534.9452 | 1.1915 | 12.9614 | 1.4126 | **1.0000** | 2.2464 | 2.9003 | O / O | T9 |
| sort_records / large (4096) | 51470.2384 | **1.0000** | 23.3619 | 2.1788 | 1.7380 | 1.2257 | 1.4972 | O / O | T9 |
| sort_int / small (64) | 161.2429 | 1.3579 | 6.3145 | 1.6313 | **1.0000** | 1.3402 | 2.5690 | O / O | T9 |
| sort_int / large (4096) | 43559.5301 | 1.4501 | 5.2613 | 1.4596 | **1.0000** | 1.0125 | 1.2332 | P / O | T9 |
| mutate_nested / small (64) | 725.6244 | 1.5319 | 1.5667 | 1.6185 | 1.4389 | **1.0000** | 1.1389 | P / O | T9 |
| mutate_nested / large (1024) | 6984.3321 | 2.7290 | 2.4279 | 2.7002 | 2.5072 | **1.0000** | 1.2342 | P / O | T9 |
| list_append / small (64) | 115.1849 | 1.3508 | 1.9135 | 2.1715 | **1.0000** | 2.6792 | 4.3123 | O / O | T9 |
| list_append / large (4096) | 5414.5766 | 1.0894 | 1.9588 | 2.1366 | **1.0000** | 2.4072 | 3.9112 | O / O | T9 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T9 | `63842d3c32ab3079d878cff89224478543f9b7f3`; `693cd1d6-6d63-44cb-bfa2-3b1984e73325` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-presize-ready-20261004/.mylang-cache/goal110-presize-ready-review/six-arm-screen.json) (`20f286774876a955755458e47563c6318bf7913329f319ea04b4a9dd474564b2`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
