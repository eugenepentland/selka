LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `G2`; source `957f97c6d9906ef11cf344ce055dada8be8446ea`; scope `subset`.
Execution identity SHA256: `eae9e7de7b53c2773937229a73bcb1e022235656c1bed259901c18baa2724bb5`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_join / small (64) | 217.2226 | **1.0000** | 1.8177 | 1.4080 | 1.2193 | 1.0475 | 1.3872 | P / O | G2 |
| string_join / large (4096) | 12530.1218 | 1.0556 | 2.0045 | 1.3952 | 1.3080 | **1.0000** | 1.0682 | P / P | G2 |
| bytes_scan / small (64) | 3.4556 | 5.0817 | 6.6686 | 8.0647 | 3.4873 | **1.0000** | 2.3206 | P / O | G2 |
| bytes_scan / large (4096) | 76.0261 | 13.9676 | 13.2306 | 18.9033 | 9.1576 | **1.0000** | 1.0405 | P / P | G2 |
| string_search / small (64) | 19.5291 | 2.1834 | 1.2573 | 4.5773 | 3.7956 | **1.0000** | 1.2548 | P / O | G2 |
| string_search / large (4096) | 87.3147 | 14.8173 | 7.3499 | 34.0843 | 30.0839 | **1.0000** | 1.0650 | P / P | G2 |
| mutate_nested / small (64) | 737.2862 | 1.5953 | 1.5728 | 1.6042 | 1.4692 | **1.0000** | 1.1394 | P / O | G2 |
| mutate_nested / large (1024) | 7239.7713 | 2.7829 | 2.4066 | 2.7569 | 2.5421 | **1.0000** | 1.0993 | P / I | G2 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| G2 | `957f97c6d9906ef11cf344ce055dada8be8446ea`; `0a7c22fa-7d2c-49b4-b64f-ffbb4803a5cf` (15 rounds, 3 warmups), `653a9088-22ea-4938-b01e-8af53a1346fa` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/goal110-join-rf-20261004/.mylang-cache/goal110-integrated-rf-20261004/confirmation-a.json) (`e4cbbd2285fa3db65cf6b3a71d19f231cfe5fc8ad81189976271de0450a377fd`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [confirmation](/home/epentland/ai/canopy/mylang-worktrees/goal110-join-rf-20261004/.mylang-cache/goal110-integrated-rf-20261004/confirmation-b.json) (`fdbb4001d3ebbeae82827a300c43c8dcbfc8dc1ad8fb0b9814919d367e1f0edc`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
