# Corrected frozen external qualification — 2026-10-09

All 450 mode commands and 1,008 native oracle cases pass against the final
immutable compiler `artifacts/mylang-qualified`, SHA256
`21319448ba51241f917c040004d1a3c7123e5516d5f0a766d7cff557294793f2`.
`0bbfeb740:experiments/frontend-closeout-20261009/external-final2/final-source-guard.json` rechecks all 614 qualified candidate source files and the compiler
hash after qualification: no changes. This records the corrected frozen source after the integrated gate findings; the prior 612-file checkpoint is retained separately in `0bbfeb740:experiments/frontend-closeout-20261009/external`.

The existing migrated Lox and EDA snapshots under
`experiments/frontend-followthrough-20261009/external/sources/` were reused
unchanged. `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/prepared-commands.json` binds the exact 84 Lox and 366 EDA mode
commands to previous receipts. All six property-bearing EDA commands retain
seed **8679566789041942096**. Timed mode logs, command receipts, reports and input
inventories remain in `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/lox-modes` and `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/eda-modes`; the prior snapshots and
qualification evidence were not overwritten.

`0bbfeb740:experiments/frontend-closeout-20261009/external-final2/compare_first_batch.py` directly compares the final reports with the qualified
first-batch `lox-modes-successor` and `eda-modes-successor` reports from compiler
SHA256 `5e072ee17b825cfbd40ed5533c3bce9f166ce4ae576395020cd5e435cc45ed11`.
Both migrated source inventories are identical. Every case membership, contract
hash, provider hash and verdict is unchanged. EDA has **366/366 byte-identical
reports**. Lox has **81/84 byte-identical reports**; only configured
`driver_tests` source fingerprints differ in debug, release and verify modes.
No other case fields differ. Equivalence of those fingerprint preimages remains
**unproved**; this report does not assign an inferred cause to the difference.
The complete comparisons are retained in `*-first-batch-comparison.json`.

The separate `*-modes-difference-audit.json` files retain comparison with the
older S5 reference, with zero unreviewed differences and preserved verdicts.
Their historical source-migration explanation describes that older transition;
no new source migration occurred during this closeout.

Release guest builds succeeded (`0bbfeb740:experiments/frontend-closeout-20261009/external-final2/native-builds.json`). Lox binary SHA256 is
`8b03465716b3b71bdf5f1ff0e60dde9387f3ef8f743b2261366454c35a127f33`;
EDA binary SHA256 is
`6efb2bce730050c8a78cf4db26536ac3cdec9e602dcb9ace5f472242f2f2d4b6`.
The unchanged external oracle compared final captures directly against prior
`lox-native-final/answers.json` and `eda-native-final/answers.json`: **974 Lox**
and **34 EDA** cases, no failures or mismatches, both binaries unchanged during
capture. Native elapsed times were 4.510s and 7.669s. Raw receipts and all 34 EDA
output sets remain under `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/lox-native` and `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/eda-native`; build caches and
binaries alone are excluded by the scoped `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/.gitignore`.

This qualifies the frozen external corpus; it does not repair the pre-existing
custom range release CFG rejection documented separately in `../range/REPORT.md`.
Final enforcement preserves guest effect scopes and reverts attempted generalized
allocation ceilings; no guest wrapper effect contracts were widened. Integrated
full-gate execution and Guardian feedback belong to the coordinator.

The corrected compiler pools the UTF-8 scalar-count cold error diagnostic instead
of allocating it; resource fixtures/examples now accurately permit filesystem
effects. Those corrections required a fresh immutable compiler and this separate
replay. The frozen external snapshots and tests/lang range inputs did not change.
`0bbfeb740:experiments/frontend-closeout-20261009/external-final2/final-source-guard.json` additionally verifies all 450 recorded argv exactly
match `0bbfeb740:experiments/frontend-closeout-20261009/external-final2/prepared-commands.json`. Native executables and mode cache products alone
are ignored; raw outputs and all 34 EDA output sets remain preserved.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
