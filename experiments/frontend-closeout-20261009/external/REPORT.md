# Final frozen external qualification — 2026-10-09

All 450 mode commands and 1,008 native oracle cases pass against the final
immutable compiler `artifacts/mylang-final`, SHA256
`aca89445a3f2d4f2dddbf68b6441c3473374cd37b2e6cde68929e0690def737f`.
`final-source-guard.json` rechecks all 612 candidate source files and the compiler
hash after qualification: no changes. Implementation is committed as fb868aace.

The existing migrated Lox and EDA snapshots under
`experiments/frontend-followthrough-20261009/external/sources/` were reused
unchanged. `prepared-commands.json` binds the exact 84 Lox and 366 EDA mode
commands to previous receipts. All six property-bearing EDA commands retain
seed **8679566789041942096**. Timed mode logs, command receipts, reports and input
inventories remain in `lox-modes/` and `eda-modes/`; the prior snapshots and
qualification evidence were not overwritten.

`compare_first_batch.py` directly compares the final reports with the qualified
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

Release guest builds succeeded (`native-builds.json`). Lox binary SHA256 is
`8b03465716b3b71bdf5f1ff0e60dde9387f3ef8f743b2261366454c35a127f33`;
EDA binary SHA256 is
`efdc5b13b93d6cf6976d754f1e9cf5bd8b0fbb298ef816e3824207690dc05ee2`.
The unchanged external oracle compared final captures directly against prior
`lox-native-final/answers.json` and `eda-native-final/answers.json`: **974 Lox**
and **34 EDA** cases, no failures or mismatches, both binaries unchanged during
capture. Native elapsed times were 4.008s and 2.860s. Raw receipts and all 34 EDA
output sets remain under `lox-native/` and `eda-native/`; build caches and
binaries alone are excluded by the scoped `.gitignore`.

This qualifies the frozen external corpus; it does not repair the pre-existing
custom range release CFG rejection documented separately in `../range/REPORT.md`.
Final enforcement preserves guest effect scopes and reverts attempted generalized
allocation ceilings; no guest wrapper effect contracts were widened. Integrated
full-gate execution and Guardian feedback belong to the coordinator.
