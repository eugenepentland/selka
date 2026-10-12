# Field list augmentation and exact self-extension

The feature patch removes the second record reconstruction after a field list
`+=`. The existing collection operation already writes its result through the
captured receiver path. The duplicate reconstruction attempted to move the
borrowed field and caused `E_SINGLE_OWNER_BORROW`, even without a snapshot.
Other augmented operations retain their existing lowering. Source overlap and
borrow rules are unchanged.

An additional, pre-existing lowering defect affected `record.items.extend(record.items)`:
three equivalent field reads reached an opaque physical-identity call, and later
read merging produced `same_block(x, x)` without eliminating the impossible
distinct-source arm. That arm retained the consumed list and compilation refused.
The list builder now recognizes exact record-projection identity before emitting
the branch and uses its existing self-extension loop. The proof compares resolved
SSA parents, field indices and physical types, walks at most 64 projections, and
stops at every other producer. Explicit copies, different roots, different fields
and unknown index paths keep the existing runtime identity branch. No child copy
or source-owner contract is relaxed.

The production input base is Support7
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`. The final focused compiler is
`.zig-cache/o/aaaad3b7262401a2ac2f9b3ec4382abd/mylang`, SHA256
`929f2f872a5cc8bfa5eee9c21471d53d3d64a7c9a517acee2657ca1f5da29ebb`.
`registered.json` records the exact source hashes, toolchain, commands and logs.
The owned Support6 component pin supplies build helpers; this is separate from
the coordinator's final installed-package qualification.

The registered suite passes 2/2 tests on that compiler:

- Five counted modes: release, unoptimized debug, verified release, optimized
  debug, and release without facts.
- Nested records, list/dictionary parents and a narrowed Optional; flat and
  nested managed self-extension through both `+=` and `.extend`; sibling and
  independent-owner inputs; copied snapshot independence.
- Dynamic negative index and RHS effects exactly once in order; bounds and
  missing-key traps before RHS effects (ten trap runs across five modes).
- Zero counted RC events, zero exit-live managed bytes and clean emitted LLVM.
- Three invalidating RHS calls remain overlap refusals; borrowed field returns
  remain `E_SINGLE_OWNER_BORROW`.

The source-normalization-only intermediate compiler also ran unchanged public
test bodies, with an assertion-only main added by the evidence harness:

| Corpus | Five checked modes | Ordinary release/debug |
| --- | --- | --- |
| `rc_semantic_publication.my` (6 public functions) | 5/5 pass | 2/2 pass |
| `field_augmented.my` (6 public functions) | Debug passes; four optimized modes refused | 2/2 pass |

These intermediate results are **not relabeled as results from the final focused
compiler**. Source pairs and hashes are in `source-identities.json`; exact commands
and outputs are in `interim-results/`. Same-statement parent rebinding, field
replacement and sibling mutation are rejected with `E_MUTATION_OVERLAP` by both
the frozen baseline and the source-fix compiler. The stronger ordinary positive
control (without runtime trap probes) passes release/debug after normalization;
frozen Support7 refused its indexed receiver/RHS form with `E_CORE_UNSUPPORTED`.
The original ordinary public oracles remain unchanged and pass.

The remaining optimized refusal is a separate ownership-pass ordering defect:
after inlining a mutable helper, `takeFields` visits a record projection before
the later-numbered producer marks it owned. Its nested child is never reconsidered.
The explicit `.extend(added)` control fails on frozen Support7 too. The coordinator
owns the proposed worklist repair. Exact reduced sources and raw/facts IR are in
`../field-augmented-prior-mut/`. The original full `field_augmented` matrix must
be rerun against the combined compiler; this item remains a qualification blocker.

Preserved unsuccessful runs are explicit: `initial-optional-fixture/` used an
assertion where the front end requires a terminating branch to narrow Optional;
`before-projection-proof/` records the self-extension refusal; and
`projection-build-error/` records a corrected Zig pointer-argument typo. No old
measurements were replaced or used for runtime/RSS claims. The focused gate used
shared admission ticket 1125; earlier tickets and commands remain in the logs.
