# A01 prepared retirement handoff

Base: `44947e6967d8eb0deeaa86b25ca2bb44bc58803d`.
Worker checkpoint: `01c00de44951162daeb14c36eac41b020ee633d0`.
Proposed commits: none; patches are unapplied review artifacts, pending C2/C3 authorization.

Owned primary paths: `src/core/build_parallel.zig` (audited unchanged),
`src/core/runtime/core_tasks.c`, `src/stdlib/parallel.my`.
Owned dependent fixtures: `a01_owned_scheduler_fixture.c`, `task_scheduler_fixture.c`,
`task_scheduler_test.zig`, `task_ir_program.zig`, `task_ir_test.zig` under `src/core`.
Shared request: one Core buildFunction selector change to A07/coordinator.

Files: `owned-runtime.patch`, `fixture-migration.patch`,
`shared-selector-request.patch`; exact hashes in `manifest.json`. Historical input
snapshots are under `originals/`. `patch-applicability.json` records all three
successful dry-runs in disposable exact-base snapshots. `static-review.json`
records identical pending/atomic/futex lines, seven unchanged queue/join/map bodies,
zero remaining RC/share helper references in the proposed task runtime, and removal
of legacy exported task aliases. No production files were edited.

A10 reviewed the ownership/ABI declaration boundary. Required native/TSan/structural,
source/census/cache, paired performance and full gate reruns are in README.md.
Unresolved owners: coordinator C2 qualification/C3 authorization; A07 shared Core
and emission retirement; A02/root block ABI and RC/COW removal; A10 package/CLI;
A03/A08/A09 final frozen-artifact evidence. A prepared patch is not a shipped or
qualified retirement implementation.
