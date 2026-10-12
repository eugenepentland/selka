# A03 handoff

- Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Branch: `codex/memory-closeout-20261012-A03`.
- Original scope: this directory only. The coordinator subsequently transferred
  A01's 36 guest fixture reservations and reserved
  `src/core/a03_migration_boundaries_test.zig`; the coordinator supplied its
  `src/core/root_test.zig` registration. The exact guest file list is in
  `guest-migrations/review-identities.json`.
- Harness commit: `d23f84d0c`; the following evidence/admission commit is the
  current branch head when this handoff is delivered.
- Implemented: isolated failure-preserving census adapter; 81-case pinned
  manifest preserving the original 30 IDs and all historical 48 matrix cases.
- Completed tests: all 81 C0 release cases / 131 executions; zero RC, no managed
  exit leaks, matching outputs/exits and 81 clean LLVM/symbol audits. Original 30
  freshly measure 23 allocating / 7 allocation-free at inputs 4 and 11. No
  migrated workload refuses; original unmigrated source checks admit 21/refuse 9.
- Fresh controls: JSON hits add 3 allocations/320 bytes at 1/16/128 siblings;
  misses add 0. Record explicit copies use 27,000 blocks versus field transfers
  at 21,000 for 1,000 unpacks; both managed peaks are 1,536 bytes. These are
  source-variant comparisons on C0, not a compiler-only before/after saving.
- Baseline compiler: A09 full C0 Debug installation, SHA-256
  `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
- Tooling checks: Python AST parse and manifest uniqueness/coverage assertions;
  first commit's Guardian hook passed all 88 checks. No Guardian feedback write.
- Final dependency: coordinator-frozen integrated compiler and exact SHA.
- Evidence paths: `manifest.json`, `C0-release/{REPORT.md,results.json.gz,
  raw-json.tar.gz,controls.json,sha256.json}` and `C0-smoke/`. Full scratch raw
  outputs/binaries/LLVM: `.tmp/memory-closeout/A03/C0-batched/`; earlier `C0/`
  and `C0-smoke/` remain intact. `C0-batched.log` reports every release lane.
- Scheduling: coordinator-approved leases of at most ten compiler invocations,
  reacquired after 60 seconds at safe boundaries; separate queue-wait receipts.
  SIGUSR1 saves a checkpoint after the active lane. No nested admission.
- Shared-file request completed: coordinator added the new boundary-test root.
- Known limitations: managed counters do not measure RSS/native overhead;
  source checks of the original unmigrated corpus are reported separately.
  LLVM/symbol audit does not replace A07's runtime ABI layout proof.

The final compiler must run all five modes (405 builds / 655 executions) on the
same 81-case manifest. Per coordinator direction, C0 was measured release-first;
its result correctly marks `complete_matrix: false`. The pinned census found no
production defect; the expanded guest migration work below found additional
compiler blockers. The integrated candidate dependency remains open.
A baseline-only success does not qualify default promotion or legacy retirement.

The transferred migration preserves 356 public test signatures. Explicit source
copy calls increase from 7 to 250; the migration changes 331 added/286 removed
lines including comments. This is source migration, not a compiler-only win.
Nine negative borrow/write cases preserve rejection of former implicit-snapshot
call windows and mutable iteration; the positive snapshot case executes in
debug and verified release. Five focused registered tests pass.

Interim support2 (`245e892f8518943ee44a0cc6009ab4b4fa6bca43`, compiler SHA-256
`3e9f7f2cd7e1ff7dc13b342dc812cb64b340cddc02b8b2b4b1ae8008cb203c7c`) source checks
admitted 22/36 files, with all 14 failures retained. A later native release subset
ran 21/24 files /118 Boolean tests successfully with RC0, no managed leaks and
clean LLVM/symbols. Exact tested sources and receipts are archived in
`guest-migrations/`; these results do not claim final C1 qualification.

Open production reproducers include nested writes, distinct mutable collection
places, dictionary-item iteration, fresh-value projections, optional narrowing,
interior dictionary mutable lowering, and a managed-string destructuring swap
(A07 and coordinator); aggregate render-helper ownership is assigned to A04.
The snapshot scalar panic is fixed by the coordinator and awaits fresh recheck.
See `guest-migrations/README.md` and `qualification.json` for source paths and
limits. The smallest valid local copy/staging migrations are already applied;
legitimate in-place operations remain intact for their compiler owners to fix.
