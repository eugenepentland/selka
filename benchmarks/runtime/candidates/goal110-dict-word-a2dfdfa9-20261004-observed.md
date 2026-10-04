LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T25`; source `a2dfdfa994e19ac3c80373a443913c7ecdef23d7`; scope `subset`.
Execution identity SHA256: `bec16fdf007a54d3a1898a8057720a96ebad8690f519a64da11a30eb121d4b7d`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| dict_lookup / small (64) | 240.7723 | 2.5146 | 1.7713 | 1.9280 | **1.0000** | 1.4390 | 2.4308 | O / O | T25 |
| dict_lookup / large (4096) | 27996.2446 | 1.4024 | **1.0000** | 1.7739 | 1.4217 | 1.3845 | 2.0588 | O / O | T25 |
| dict_lookup_str / small (64) | 374.1758 | 2.1976 | 1.3878 | 1.2761 | **1.0000** | 1.4579 | 2.1776 | O / O | T25 |
| dict_lookup_str / large (4096) | 38883.4035 | 1.4622 | **1.0000** | 1.5381 | 1.2122 | 1.6555 | 2.1685 | O / O | T25 |
| dict_update / small (64) | 2395.1689 | 2.4805 | 3.2915 | 1.9504 | **1.0000** | 4.6472 | 6.4010 | O / O | T25 |
| dict_update / large (4096) | 423825.9426 | 1.0635 | 1.1452 | 1.3788 | **1.0000** | 2.1185 | 2.6774 | O / O | T25 |
| dict_update_str / small (64) | 4682.9075 | 2.8773 | 1.9747 | 1.3055 | **1.0000** | 2.8540 | 3.7225 | O / O | T25 |
| dict_update_str / large (4096) | 654053.3467 | 1.4365 | **1.0000** | 1.2339 | 1.0770 | 1.6680 | 1.9591 | O / O | T25 |
| set_dedup / small (64) | 281.9458 | 3.3477 | 3.9211 | 2.0300 | **1.0000** | 9.8669 | 12.6548 | O / O | T25 |
| set_dedup / large (4096) | 54181.9759 | 1.0957 | 1.2368 | 1.4261 | **1.0000** | 3.2924 | 4.2120 | O / O | T25 |
| mutate_nested / small (64) | 716.2229 | 1.5427 | 1.5777 | 1.5743 | 1.4358 | **1.0000** | 1.1769 | P / O | T25 |
| mutate_nested / large (1024) | 7138.3341 | 2.6520 | 2.3764 | 2.6454 | 2.4124 | **1.0000** | 1.1638 | P / O | T25 |
| string_search / small (64) | 19.3668 | 2.1912 | 1.2429 | 4.5551 | 3.7951 | **1.0000** | 1.2481 | P / O | T25 |
| string_search / large (4096) | 85.8175 | 14.8868 | 7.4274 | 33.6671 | 30.0514 | **1.0000** | 1.0531 | P / P | T25 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T25 | `a2dfdfa994e19ac3c80373a443913c7ecdef23d7`; `d772c021-e811-45d7-b0f4-980e04c0dfb1` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-dict-word-integrated-20261004/.mylang-cache/goal110-dict-word-debug/screen.json) (`1a51a229d97e0eec9e1a862cccc9ea5825b67f78df85509750e2c04c585368df`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
