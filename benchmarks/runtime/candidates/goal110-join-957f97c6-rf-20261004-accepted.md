LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `G2`; source `957f97c6d9906ef11cf344ce055dada8be8446ea`; scope `subset`.
Execution identity SHA256: `eae9e7de7b53c2773937229a73bcb1e022235656c1bed259901c18baa2724bb5`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_join / small (64) | 218.7103 | **1.0000** | 1.8238 | 1.4099 | 1.2128 | 1.0464 | 1.3873 | C / O | G2 |
| string_join / large (4096) | 12572.0989 | 1.0570 | 2.0184 | 1.3990 | 1.3022 | **1.0000** | 1.0738 | C / C | G2 |
| bytes_scan / small (64) | 3.4936 | 5.0533 | 6.7494 | 7.8731 | 3.4318 | **1.0000** | 2.3316 | C / O | G2 |
| bytes_scan / large (4096) | 75.9983 | 13.9961 | 13.2417 | 18.9235 | 9.1867 | **1.0000** | 1.0389 | C / C | G2 |
| string_search / small (64) | 19.5710 | 2.1818 | 1.2578 | 4.5687 | 3.7994 | **1.0000** | 1.2554 | C / O | G2 |
| string_search / large (4096) | 87.2513 | 14.8271 | 7.3482 | 34.0815 | 30.1024 | **1.0000** | 1.0635 | C / C | G2 |
| mutate_nested / small (64) | 737.5527 | 1.6006 | 1.5794 | 1.6219 | 1.4777 | **1.0000** | 1.1408 | C / O | G2 |
| mutate_nested / large (1024) | 7197.6200 | 2.8005 | 2.4226 | 2.7753 | 2.5558 | **1.0000** | 1.1193 | C / O | G2 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| G2 | `957f97c6d9906ef11cf344ce055dada8be8446ea`; `653a9088-22ea-4938-b01e-8af53a1346fa` (15 rounds, 3 warmups), `0a7c22fa-7d2c-49b4-b64f-ffbb4803a5cf` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-integrated-rf-20261004/confirmation-b.json.gz) (`fdbb4001d3ebbeae82827a300c43c8dcbfc8dc1ad8fb0b9814919d367e1f0edc`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [confirmation](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-integrated-rf-20261004/confirmation-a.json.gz) (`e4cbbd2285fa3db65cf6b3a71d19f231cfe5fc8ad81189976271de0450a377fd`), [checks](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-join-957f97c6-rf-20261004-checks.json) (`b0b01b6cf9b40b32b1453ef510b7700f820bbb2b6edf6f0402e33f02a2ad4eea`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
