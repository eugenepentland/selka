# RC boxed collection write-back, 2026-09-26

Mutating a collection field narrowed from a recursive `Option` updated a
materialized body but left the owning `Option` pointing at its earlier box.
For example, after saving a snapshot, assigning `original.mapping[1] = 13`
left both `original` and the snapshot reading 7 under counted RC.

The RC place fill now republishes the updated body through the existing
guarded rebox bridge before exposing its receiver. Reboxing keeps the original
allocation region, commits the replacement before releasing an owned old box,
and leaves a caller-borrowed old box alive. It retains the body's ordinary and
held child edges physically. Pin-aware copying at this boundary is wrong:
it can publish a cloned child while the pending receiver still names the old
child. The ABI3 physical-retain primitive fixes that boundary without introducing
another semantic sharing event.

Five permanent language regressions cover heap and arena snapshots, an old
live view, repeated writes and an older-region owner mutated inside an arena.
All five fail on the frozen pre-fix RC compiler `7998e84c`; all five pass on
both actual backends after the fix. Accounted GC controls pass all five before
and after. Twelve RC guest files pass 83 uncached assertions per backend.

Ordinary, unaccounted execution also returns all five expected results under
RC on QBE and LLVM O3/full LTO. Both report 55 heap allocations/retirements,
42 owner acquisitions plus 97 releases, and 16 hold acquisitions/releases.
The corresponding GC runs expose a separate repeated-write failure, returning
four true values and one false value despite all five passing under the test
runner. That failure is preserved and assigned to a separate correction; this
report does not claim complete GC/RC parity.

The C bridge suite passes 25 cases under ASan and UBSan, including new pinned
heap and arena child-identity assertions and the existing borrowed/owned guard
and late-count-refusal rollback cases. A saved negative control restoring the
old pin-aware body copy fails the new identity assertion. Debug install passes
19/19 steps, the focused Zig suite passes 16 tests, and formatting passes.

The initial resource-bearing probe was admitted but crashed before this change;
the first rebox draft reached the bridge's finalized-body invariant sooner.
The existing `RECURSIVE-VALUES-1` contract forbids owned resources in recursive
boxes. Checker correction `75802ff9` enforces that rule while preserving valid
acyclic file-owning records and `Result` values. It must accompany final
integration; this slice does not implement resource relocation through shared
immutable boxes.

This branch has private ABI3 ancestry and must join the complete semantic-history
compiler changes before entering the integration branch. Those changes must also
audit any frame-private loan reaching the owning box slot: the rebox bridge's
existing guard describes ordinary ownership, not a loan role. No default-runtime
flip, full combined gate or WP-4 instruction/RSS acceptance is claimed here.

The final Debug compiler SHA256 is
`b3a99d2e0a9af39450080fdffb484d007ef94c304bf922e539ab943273d5e66b`.
Raw before/after receipts, negative controls, diagnostic sources and drivers are
in [`experiments/d9-rc-box-writeback-20260926`](../../experiments/d9-rc-box-writeback-20260926).
