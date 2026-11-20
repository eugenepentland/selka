# D9 indexed-transfer and scoped-receiver review — 2026-09-26

The indexed payload-return proof remains conservative when combined with the
scoped receiver fix. No additional compiler change was needed.

`qbe_cow.retainPlaces` preserves implicit parent/key uses. `qbe_liveness.extend`
only grows liveness, and the emitter reruns ownership and COW planning until
those uses settle before planning moves and GC roots. The indexed proof's
post-commit lifetime checks therefore see the retained uses. Its structural
first-parent-use, unchanged-index, closed-control-flow and no-observer checks
remain intact.

The caller's direct `mut list` path still makes the argument unique after all
argument evaluation and pins it before the call. A preexisting outer snapshot
therefore shares children before the callee can omit an extraction transfer.
The scoped receiver changes retain their own parent/key roots and pins; they do
not relax the mut-list call contract. An earlier match or iteration borrow is
still rejected by the indexed proof's first-use boundary.

The final combined IL retains zero `myl_qbe_cow_transfer` calls in both
`heap::set_object_field` and its `heap::set_instance_field` wrapper. The wrapper
retains the list's pin/unpin operations. Thus the replan preserves this specific
optimization as well as the lifetime guards.

## Frozen validation

The joined Debug compiler is `91d1311e`, SHA-256
`d733b14aca8b25b0d4fb2d1becda50c98c2ab0f8cfac342e22a204bc58c9d82c`.
Its compiler and sibling QBE were copied to isolated scratch before validation.

Sixty guest probes passed on both QBE and LLVM with value semantics and native
GC stress: 20 indexed-return tests, 37 nested-array/callback tests, and
[three combined receiver/commit probes](evidence/d9-index-scope-interaction.my).
The combined probes preserve a caller's pending payload receiver, an outer
snapshot, and a callback's captured nested array across the indexed commit.
The final recorded invocation reports three fresh passes and 57 cached passes
per backend; those 57 had passed freshly in the preceding invocation using the
same compiler and unchanged sources. [Raw results and source hashes](evidence/d9-indexed-joined-validation.json)
retain the exact identities and outcomes.

[All 44 switch-off IL comparisons](evidence/d9-indexed-joined-off-il.json) compiled
and matched exact `60b668cf` byte for byte. This review supplies focused combined
correctness evidence; the root integration runs its separate full gate and final
43-workload performance comparison.
