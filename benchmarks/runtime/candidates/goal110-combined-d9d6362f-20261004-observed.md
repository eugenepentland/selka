LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T11`; source `d9d6362f0914df21078070288959fea3b73603e7`; scope `subset`.
Execution identity SHA256: `a29baba04d1cc6da3a31cf86b87cd149335b30f892db5273942dbaf24694da85`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_search / small (64) | 19.4215 | 2.1720 | 1.2458 | 4.5307 | 3.7704 | **1.0000** | 1.2502 | P / O | T11 |
| string_search / large (4096) | 85.5741 | 14.9053 | 7.4736 | 33.8903 | 30.1528 | **1.0000** | 1.0630 | P / P | T11 |
| string_join / small (64) | 218.6612 | **1.0000** | 1.8139 | 1.4096 | 1.2211 | 1.1183 | 1.3325 | O / O | T11 |
| string_join / large (4096) | 12482.5074 | 1.0642 | 2.0129 | 1.4109 | 1.3177 | **1.0000** | 1.0166 | P / P | T11 |
| bytes_scan / small (64) | 3.4674 | 5.0638 | 6.8480 | 8.1634 | 3.4806 | **1.0000** | 2.3441 | P / O | T11 |
| bytes_scan / large (4096) | 75.0280 | 14.0212 | 13.4565 | 19.3559 | 9.2655 | **1.0000** | 1.0680 | P / P | T11 |
| string_equal / small (64) | 2.9690 | **1.0000** | 1.5477 | 1.3496 | 1.2814 | 1.3908 | 7.3887 | O / O | T11 |
| string_equal / large (4096) | 12.6775 | 2.4161 | 2.8856 | 5.0955 | 3.9546 | **1.0000** | 18.6251 | P / O | T11 |
| int_parse / small (64) | 4.4112 | **1.0000** | 5.3807 | 1.2932 | 1.2842 | 2.2517 | 4.1101 | O / O | T11 |
| int_parse / large (4096) | 5.0952 | **1.0000** | 5.2690 | 1.3155 | 1.2200 | 2.1978 | 3.7639 | O / O | T11 |
| int_format / small (64) | 14.3986 | **1.0000** | 1.1222 | 2.7571 | 2.2048 | 4.0116 | 5.8660 | O / O | T11 |
| int_format / large (4096) | 15.1253 | **1.0000** | 1.1487 | 2.7855 | 2.3320 | 3.8757 | 5.6559 | O / O | T11 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T11 | `d9d6362f0914df21078070288959fea3b73603e7`; `9945beb4-2ca0-47fe-b6ef-50f7363aea38` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-text-combined-20261004/.mylang-cache/goal110-text-combined/combined-screen.json) (`e8a73bf10eb4fd87ce41155a5497945eb61338e3ac793a835cca8d147fa15790`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
