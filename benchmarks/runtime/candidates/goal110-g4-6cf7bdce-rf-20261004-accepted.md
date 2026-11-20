LLVM ≤1.10; 80 required cells. QBE: tracked, 0 required cells.

Evidence `G4`; source `6cf7bdce11bc205862bf75b9d9ce72e46caad0a2`; scope `subset`.
Execution identity SHA256: `30aa59264a699dcabf430dbe8a681040bbd3c039789b76702adb6a08e5e2c2a3`. Goal complete: **False**.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| string_join / small (64) | 162.8626 | 1.3451 | 2.4317 | 1.8955 | 1.6336 | **1.0000** | 1.1664 | C / O | G4 |
| string_join / large (4096) | 5763.9243 | 2.3079 | 4.3569 | 3.0551 | 2.8575 | **1.0000** | 1.0115 | C / C | G4 |
| bytes_scan / small (64) | 3.4649 | 5.0849 | 6.8839 | 7.9880 | 3.4720 | **1.0000** | 2.3692 | C / O | G4 |
| bytes_scan / large (4096) | 75.3386 | 14.1340 | 13.3834 | 18.8670 | 9.2750 | **1.0000** | 1.0494 | C / C | G4 |
| string_search / small (64) | 19.5696 | 2.1785 | 1.2547 | 4.5712 | 3.7904 | **1.0000** | 1.2549 | C / O | G4 |
| string_search / large (4096) | 87.5278 | 14.7733 | 7.3155 | 33.9751 | 30.0027 | **1.0000** | 1.0550 | C / C | G4 |
| string_equal / small (64) | 2.9979 | **1.0000** | 1.4842 | 1.3563 | 1.2735 | 1.3898 | 7.2728 | O / O | G4 |
| string_equal / large (4096) | 12.7438 | 2.4308 | 2.9087 | 5.0839 | 3.9540 | **1.0000** | 18.7675 | C / O | G4 |
| sort_int / small (64) | 165.2368 | 1.3727 | 6.4191 | 1.6209 | **1.0000** | 1.3925 | 2.5638 | O / O | G4 |
| sort_int / large (4096) | 44151.3168 | 1.4312 | 5.2569 | 1.4696 | 1.0165 | **1.0000** | 1.2146 | C / O | G4 |
| mutate_nested / small (64) | 743.1072 | 1.5630 | 1.5550 | 1.5835 | 1.4494 | **1.0000** | 1.1819 | C / O | G4 |
| mutate_nested / large (1024) | 7194.4692 | 2.7668 | 2.4057 | 2.7373 | 2.5132 | **1.0000** | 1.1046 | C / O | G4 |
<!-- DASHBOARD-END -->

| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |
|---|---|---|
| G4 | `6cf7bdce11bc205862bf75b9d9ce72e46caad0a2`; `bcc5273b-e669-4cf3-9682-5580ed530ff0` (15 rounds, 3 warmups), `620102fe-f182-439c-a8ff-2bbc42b25152` (15 rounds, 3 warmups) | [report](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-g4-rf-20261004/confirmation-b.json.gz) (`59aaa8b1316cb882925ef3b9bb72ae1e7934a3554725a0e1efbb97da39aff3bb`), [anchor](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz) (`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`), [confirmation](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/experiments/runtime-goal110-g4-rf-20261004/confirmation-a.json.gz) (`804fb8a355c4c49ac6ec5c49015e4208d49ddd58947809bdc28f80e78ef7fcfb`), [checks](/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003/benchmarks/runtime/candidates/goal110-g4-6cf7bdce-rf-20261004-checks.json) (`9d66395ac1fe01f4fa9fef8d080f726b15ed6c0fb8ebcabab4f8caa628d85f64`) |

C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.
P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.
The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.
