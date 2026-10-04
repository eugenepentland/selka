LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T17-annotation-screen`; source `0311796e84e192e3ac1e4fd0bb9d5824b55be1e2`; scope `subset`.
Execution identity SHA256: `d60cbb44169b906819c63e906f95d853e1c4180d217493a8bcacf0ea4cd81422`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_equal / small (64) | 2.9260 | **1.0000** | 1.5396 | 1.3461 | 1.2752 | 1.2506 | 7.1534 | O / O | T17-annotation-screen |
| string_equal / large (4096) | 12.1337 | 2.4516 | 2.9693 | 5.2247 | 4.0049 | **1.0000** | 19.0478 | P / O | T17-annotation-screen |
| string_search / small (64) | 19.2254 | 2.1867 | 1.2559 | 4.5499 | 3.8035 | **1.0000** | 1.2611 | P / O | T17-annotation-screen |
| string_search / large (4096) | 91.0562 | 13.9338 | 7.0549 | 31.5890 | 28.1621 | 1.0956 | **1.0000** | I / P | T17-annotation-screen |
| bytes_scan / small (64) | 3.4719 | 5.0623 | 6.2426 | 8.0071 | 3.4686 | **1.0000** | 2.3114 | P / O | T17-annotation-screen |
| bytes_scan / large (4096) | 74.9411 | 13.8121 | 13.9300 | 19.3924 | 9.2278 | **1.0000** | 1.0443 | P / P | T17-annotation-screen |
| string_join / small (64) | 162.9776 | 1.3400 | 2.4180 | 1.8864 | 1.6240 | **1.0000** | 1.1627 | P / O | T17-annotation-screen |
| string_join / large (4096) | 5790.1878 | 2.2897 | 4.3306 | 3.0366 | 2.8376 | **1.0000** | 1.0122 | P / P | T17-annotation-screen |
| int_parse / small (64) | 4.3751 | **1.0000** | 5.3589 | 1.3016 | 1.2841 | 2.2510 | 4.1325 | O / O | T17-annotation-screen |
| int_parse / large (4096) | 5.0678 | **1.0000** | 5.2446 | 1.3263 | 1.2283 | 2.2012 | 3.7728 | O / O | T17-annotation-screen |
| int_format / small (64) | 14.5126 | **1.0000** | 1.1040 | 2.7287 | 2.1580 | 3.9426 | 5.7778 | O / O | T17-annotation-screen |
| int_format / large (4096) | 15.0825 | **1.0000** | 1.1410 | 2.7857 | 2.3270 | 3.8594 | 5.6754 | O / O | T17-annotation-screen |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T17-annotation-screen | `0311796e84e192e3ac1e4fd0bb9d5824b55be1e2`; `809fbbda-8625-4f0d-a601-bd2b143975cb` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-floor-result-range-20261004/.mylang-cache/goal110-floor-result-range-debug/annotation-screen.json) (`8bebbb3c42cb6149989301eb151be8fb6dd2a6b52876fabee743ef11355478fd`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
