# Memory-management closeout, 12 October 2026

Execution in progress. None of the three release milestones is yet qualified.
The session has one coordinator and ten concurrent workers in independent sibling
worktrees. The original checkout and its unrelated edits are preserved.

C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`, exactly `origin/development`
at kickoff. Both documented ancestor checks passed. Integration branch:
`codex/memory-closeout-20261012`.

| Milestone | Status |
| --- | --- |
| Qualified implementation | Pending integrated candidate and full verification |
| Zero-RC default | Pending implementation qualification |
| Active legacy RC retirement | Pending default qualification and installed component boundary |

The [kickoff record](kickoff.json) pins toolchain, Guardian, worktrees, host,
admission budget and preserved checkout. The [public export census](public-exports-C0.json)
records all 206 public declarations across the current standard-library modules;
A04/A05 supply contracts and executable coverage. [Item ledger](ledger.json).

The freshly rebuilt C0 compiler installation is recorded in A09's installation
manifest; it preserves `bin/`, `libexec/` and `tools/` together. Historical reports
remain immutable and are not new measurements. Each worker publishes its sources,
raw results and handoff under its own A01–A10 directory.

Publication is not authorized by this handoff. Work remains on local branches;
no push or self-hosting branch merge is part of this run.

## Current integration evidence

The fresh C0 census passed all 81 cases and 131 counted executions. Within the
original 30, 23 still allocate and 7 are allocation-free; all migrated cases run
without RC or managed exit-live bytes. This is baseline evidence, not final
candidate qualification. See [the C0 report](A03/C0-release/REPORT.md).

Integrated work includes bounded map scheduling, allocation-overflow guards,
managed-list permutation operations, command and cache mode plumbing, independent
library snapshots, borrowed comprehensions and sorting, repetition, bounded affine
resource lifetimes, and compiler regressions found by the larger survey. Focused
worker results identify their own revisions; they do not certify a later binary.

The user-expanded Result-list implementation is integrated. Support5 passes its
release/ThreadSanitizer Result-map cases at 1/2/8 workers. These results identify
their actual source and binary; they do not qualify a final candidate.

Support5 is source `a1f19edf255c8c0886731d8d7cce450d5f657720`, compiler SHA256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`. The native
object-lifetime bug is fixed and the host loader-cache change was independently
reviewed. Installed components still use the historical RC-seed package, which
remains an explicit package blocker.

The original 30 release sanity run on Support5 passes all 30 cases and 72 counted
executions: 23 allocating, 7 allocation-free, zero RC events and zero managed
exit-live bytes. All 72 source/input matched comparisons have identical allocation
traffic and managed peaks to freshly built C0. Final five-mode qualification is
pending.

Public-library and four-application fixtures have passing intermediate matrices;
Support5 passes 40 cache probes and 52 command/analysis/cost rows. Each worker
report identifies its artifact and refused cases. Later integrated fixes cover
single-item dictionary borrowing, readonly managed dictionary defaults, complete
tuple staging, fresh field receivers, scalar field snapshots, numeric formatter
ABI, slice lifetimes, interior mutable calls and named provider transfers.
These focused results do not qualify a final common compiler.

Support6 is source `5167c588be79dd43d21d5013c36db15110bf239b`, Debug compiler SHA256
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`. It is not C1.
[Its original A06 checks](coordinator/support6/a06-summary.json) record 56/64
guest sources, 21/23 additional sources, and both counted native `ce2_effects`
modes passing. Refusals remain in the denominators. Later explicit-copy migrations
pass five modes for borrowed elements and row snapshots. The scalar-child-write
fix for `v_nested` is integrated and passes its worker's five-mode checks; it still
needs the common compiler rerun.

A10 independently rebuilt a ReleaseFast compiler from that exact source, SHA256
`29cfbd13390692757ce3add9cf61d8398eff283760d16cedb3c5b9addaa03e26`. Both owned
component protocol suites passed 688 counted executions on the Debug and this
ReleaseFast compiler, with zero RC events and managed exit-live bytes. A10's
actual installed owned components also passed 42 pure tests and protocol oracles.
See [the package evidence](A10/packaging-support6-candidate/qualification-state.json).
The original Support6 Debug installation retains its historical libexec; the new
owned installation is separate. Normal component defaults remain unchanged.
Explicit qualified pin options now allow development builds without invoking the
immutable legacy seed's known native-object lifetime defect.

Provider transfer, tuple and borrowed-default implementations are integrated but
still need the next common-artifact library/application matrices. Bounded local
borrowed-provider wrappers, managed selection between distinct input owners,
scalar record-field writes inside lists, independent set children and managed
generator folds are now integrated with focused regressions. Source histories and
failed cases remain visible in the ledger.

Support7 is frozen at `bed11cf3bf3102ffec44487e431a1573fdf02ad5`. Its complete
ReleaseFast installation was built successfully with the independently qualified
owned component compiler pin; compiler SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`. The source, command and installation boundary are recorded
in [the installation identity](coordinator/support7/support7-identity.json). It is a proposed
qualification candidate, not a completed milestone. The verification coordinator
also needs to admit and bind the explicit component pin/archive options before
the complete gate can qualify that same package.

A09 corrected a measured RSS harness defect: outer Python-child rusage included
launcher memory before exec. New RSS-only GNU-time measurements discriminate
small and large native children independently of a 256 MiB launcher allocation.
Old pilot RSS observations are explicitly invalid; no final RSS claim uses them.
The final schedule separates 330 runtime samples, 90 RSS samples, and 30
size-aligned counted configurations from the 435-build/695-run census. Eight
immutable C0 counted builds fail ordinary native linking. Those failures remain
recorded. A separately identified exact-artifact native adapter now passes all 15
C0 configurations, with zero RC events and managed exit-live bytes. The final
candidate must use the matched adapter and normal/manual controls; those results
are still pending.

The exploratory full gate on `245e892f8518943ee44a0cc6009ab4b4fa6bca43` failed
after 45 fresh actions (no reuse). Raw evidence remains in
`coordinator/exploratory-verify-01/`. The dictionary snapshot defect is fixed in
later sources, but complete verification must still pass on frozen final inputs.
Focused tests do not replace that gate.
