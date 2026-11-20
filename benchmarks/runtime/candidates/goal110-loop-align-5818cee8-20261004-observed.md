LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T24`; source `5818cee8e679c1f30fd5966963210511fcf69919`; scope `subset`.
Execution identity SHA256: `62fe3844ffe850a4bd92416f9c2bb2770445a52b073511d281d462cebc926151`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_equal / small (64) | 2.8980 | **1.0000** | 1.4554 | 1.3512 | 1.2730 | 1.2548 | 7.2811 | O / O | T24 |
| string_equal / large (4096) | 11.9156 | 2.4683 | 3.0167 | 5.2747 | 4.0295 | **1.0000** | 19.3745 | P / O | T24 |
| string_search / small (64) | 19.2122 | 2.1854 | 1.2561 | 4.5289 | 3.8007 | **1.0000** | 1.2547 | P / O | T24 |
| string_search / large (4096) | 85.0163 | 14.9639 | 7.4921 | 33.4920 | 29.6707 | **1.0000** | 1.0685 | P / P | T24 |
| bytes_scan / small (64) | 3.4469 | 5.0289 | 6.1756 | 8.0831 | 3.4440 | **1.0000** | 2.3204 | P / O | T24 |
| bytes_scan / large (4096) | 74.9177 | 13.7139 | 13.8983 | 19.2355 | 9.1912 | **1.0000** | 1.0577 | P / P | T24 |
| string_join / small (64) | 158.7379 | 1.3727 | 2.4770 | 1.9397 | 1.6649 | **1.0000** | 1.1875 | P / O | T24 |
| string_join / large (4096) | 5701.8121 | 2.3363 | 4.3922 | 3.0542 | 2.9049 | **1.0000** | 1.0266 | P / P | T24 |
| int_parse / small (64) | 4.3267 | **1.0000** | 5.3982 | 1.3086 | 1.2969 | 2.2767 | 4.1793 | O / O | T24 |
| int_parse / large (4096) | 4.9709 | **1.0000** | 5.3107 | 1.3630 | 1.2415 | 2.2351 | 3.8469 | O / O | T24 |
| int_format / small (64) | 14.6538 | **1.0000** | 1.0806 | 2.6349 | 2.1078 | 3.7536 | 5.6717 | O / O | T24 |
| int_format / large (4096) | 14.9637 | **1.0000** | 1.1467 | 2.7362 | 2.2887 | 3.7450 | 5.6202 | O / O | T24 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T24 | `5818cee8e679c1f30fd5966963210511fcf69919`; `9456e694-5282-477b-ad5f-80a7da4a3826` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-natural-loop-align-20261004/.mylang-cache/goal110-natural-loop-align/alignment-screen.json) (`547d1fecc4d2a2f1a9006705e2d1aa032ca8252bb05249d3c467f9aa3c4814d0`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
