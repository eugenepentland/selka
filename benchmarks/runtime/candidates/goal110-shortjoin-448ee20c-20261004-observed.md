LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T14`; source `448ee20c66eafaad72a6d3ba024fbeb1f6f599df`; scope `subset`.
Execution identity SHA256: `681065cd885933fc805585bf15de578d2e3a8f47c726dfdf0802ce6c2d05a7f6`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_join / small (64) | 168.0490 | 1.3244 | 2.4341 | 1.8809 | 1.6189 | **1.0000** | 1.1604 | P / O | T14 |
| string_join / large (4096) | 5827.4985 | 2.3080 | 4.3977 | 3.1101 | 2.8703 | **1.0000** | 1.0278 | P / P | T14 |
| string_equal / small (64) | 3.0268 | **1.0000** | 1.5012 | 1.3484 | 1.2632 | 1.3790 | 7.2135 | O / O | T14 |
| string_equal / large (4096) | 12.7685 | 2.4246 | 2.9102 | 5.0731 | 3.9523 | **1.0000** | 18.6942 | P / O | T14 |
| string_search / small (64) | 19.5866 | 2.1848 | 1.2476 | 4.5764 | 3.7969 | **1.0000** | 1.2625 | P / O | T14 |
| string_search / large (4096) | 87.8658 | 14.7209 | 7.3040 | 33.8651 | 29.8837 | **1.0000** | 1.0492 | P / P | T14 |
| bytes_scan / small (64) | 3.4983 | 5.0640 | 6.7663 | 7.9616 | 3.4936 | **1.0000** | 2.3752 | P / O | T14 |
| bytes_scan / large (4096) | 75.1857 | 14.1884 | 13.5256 | 19.0731 | 9.3108 | **1.0000** | 1.0470 | P / P | T14 |
| int_parse / small (64) | 4.4652 | **1.0000** | 5.4083 | 1.2816 | 1.2776 | 2.2302 | 4.0938 | O / O | T14 |
| int_parse / large (4096) | 5.0104 | **1.0000** | 5.3917 | 1.3551 | 1.2539 | 2.2453 | 3.8461 | O / O | T14 |
| int_format / small (64) | 14.7507 | **1.0000** | 1.1094 | 2.7537 | 2.1862 | 3.9779 | 5.8586 | O / O | T14 |
| int_format / large (4096) | 15.0874 | **1.0000** | 1.1681 | 2.8252 | 2.3938 | 3.9588 | 5.8056 | O / O | T14 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T14 | `448ee20c66eafaad72a6d3ba024fbeb1f6f599df`; `d4cdb9de-8914-401b-ba4c-6c4fc4f56f8d` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-join-short-20261004/.mylang-cache/goal110-join-short/short-screen.json) (`3072006fbf8f17a71b15dddfc689ad667b9831afa47eb45bda497d9461fb9278`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
