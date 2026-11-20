LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `T19-dictionary-probe-screen`; source `64fb7e62732db9cea46414248fd59ba362e31b56`; scope `subset`.
Execution identity SHA256: `86961f9ba1727a841985686470fc349668a96a4e2eaba91ee963c090e87dbb08`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| dict_lookup / small (64) | 241.7641 | 2.4956 | 1.7420 | 1.9272 | **1.0000** | 1.7813 | 2.6263 | O / O | T19-dictionary-probe-screen |
| dict_lookup / large (4096) | 28430.5587 | 1.3881 | **1.0000** | 1.7561 | 1.4127 | 1.7146 | 2.2477 | O / O | T19-dictionary-probe-screen |
| dict_lookup_str / small (64) | 374.8779 | 2.2505 | 1.3826 | 1.2828 | **1.0000** | 1.3993 | 2.1803 | O / O | T19-dictionary-probe-screen |
| dict_lookup_str / large (4096) | 39072.5244 | 1.5065 | **1.0000** | 1.5420 | 1.2337 | 1.6338 | 2.1882 | O / O | T19-dictionary-probe-screen |
| dict_update / small (64) | 2434.7386 | 2.4457 | 3.2559 | 1.9178 | **1.0000** | 4.6740 | 6.2726 | O / O | T19-dictionary-probe-screen |
| dict_update / large (4096) | 424101.6198 | 1.0726 | 1.1643 | 1.3904 | **1.0000** | 2.1332 | 2.7035 | O / O | T19-dictionary-probe-screen |
| dict_update_str / small (64) | 4702.7558 | 2.7543 | 1.9782 | 1.3070 | **1.0000** | 2.9639 | 3.7663 | O / O | T19-dictionary-probe-screen |
| dict_update_str / large (4096) | 656801.4737 | 1.5310 | **1.0000** | 1.2357 | 1.0834 | 1.6897 | 1.9708 | O / O | T19-dictionary-probe-screen |
| set_dedup / small (64) | 282.2402 | 3.3139 | 3.9153 | 2.0368 | **1.0000** | 9.8410 | 12.8880 | O / O | T19-dictionary-probe-screen |
| set_dedup / large (4096) | 54404.1217 | 1.0945 | 1.2397 | 1.4250 | **1.0000** | 3.3013 | 4.2335 | O / O | T19-dictionary-probe-screen |
| mutate_nested / small (64) | 730.4728 | 1.5211 | 1.5509 | 1.5414 | 1.4063 | **1.0000** | 1.1477 | P / O | T19-dictionary-probe-screen |
| mutate_nested / large (1024) | 7050.6528 | 2.6843 | 2.3990 | 2.6761 | 2.4420 | **1.0000** | 1.1218 | P / O | T19-dictionary-probe-screen |
| string_search / small (64) | 19.3667 | 2.1821 | 1.2479 | 4.5541 | 3.7790 | **1.0000** | 1.2490 | P / O | T19-dictionary-probe-screen |
| string_search / large (4096) | 85.9730 | 14.8739 | 7.4079 | 33.7443 | 30.0712 | **1.0000** | 1.0516 | P / P | T19-dictionary-probe-screen |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| T19-dictionary-probe-screen | `64fb7e62732db9cea46414248fd59ba362e31b56`; `020b61e2-171b-4a5a-861a-f8ffffee62aa` (5 rounds, 1 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-dict-read-20261004/.mylang-cache/goal110-dict-probe-debug/screen.json) (`e2d1d6dd46515e7ffb88a9a6afbce6b71038806a919ea3a960cb6045aa4cc785`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
