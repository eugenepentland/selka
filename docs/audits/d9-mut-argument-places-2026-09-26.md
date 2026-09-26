# Nested mutable argument places

This is an isolated correctness follow-up to checker commit `3b5f54b0`, not a
WP-4 acceptance result. Main and the stage-3 baseline remain unchanged. The
implementation initially runs on ABI2; integrating its history-sensitive fixture
requires the cohesive ABI3 semantic-publication implementation as described below.

## Contract and original failure

`MUTATION-OVERLAP-1` requires a read-only argument to receive an independent value
when a same-call `mut` argument reaches its source. `MUTATION-ENFORCE-1` requires
the mutable argument to write through the caller's slot. Together they require
`change(mut original[0], original)` to return the earlier child value 7 while a
write in `change` updates `original[0]` to 13. `COW-RECEIVER-ARGUMENT-1` additionally
keeps an already selected receiver stable across later argument callbacks.
`COW-MUT-ARGUMENT-1` records the corresponding nested-call preparation explicitly.

The immutable before compiler, built at checker commit 3b5f54b0, prints 13/13 under
GC and 7/7 under ABI2RC on both actual QBE and LLVM backends. The corrected compiler
prints 7/13 in all four combinations. The exact source is unchanged in
`experiments/d9-mut-argument-checker-20260926/change.my`; this experiment retains
commands, source/compiler SHA256 identities, stdout, stderr and RC counts.

## Changes and ownership boundaries

Nonlocal mutable collection arguments now lower through a hidden writing-place
local, following the same place preparation used for nested collection mutations.
The COW plan can therefore make the path unique and publish replacement headers
into its captured field or element. Whole locals retain their existing ABI.
Each field, key and index expression is evaluated once.

GC pending receiver scopes retain and pin the selected ancestor path through
later argument evaluation and the consuming call. A readonly transfer therefore
clones the pinned finite path. A later callback can replace the original entry
without retargeting the already selected mutable argument. RC uses the existing
receiver hold scopes; its normal call completion closes those scopes after result
publication, in reverse bytecode fill order. Named arguments can evaluate in a
different order from local numbering, so numbering is not used for cleanup.

The COW single-store query admits a terminal `drop_local` emitted by reordered
named argument lowering. A drop before the store, any subsequent load, a second
store, a move or an address-taking reference prevents this place classification.
A raw bytecode test exercises the valid cleanup and three refusal cases.

Indirect calls now use their checked callable mutation footprint in the same
argument uniqueness and pin/unpin paths as direct calls. Packing happens after
preparation, so a replacement header is the pointer the callee receives.
Ownership role inference also recognizes these indirect mutable loads. This does
not change C callback ABI, runtime descriptors, count operations or allocator code.

No `fillPlace`, reboxing, read-capture/history, or runtime C implementation was
changed. The small direct/indirect callee view shares preparation without changing
the existing direct inferred/declarative write-footprint behavior.

## Sharing-history dependency, not an old-output waiver

The checker fixture `clone_during` writes `target[1] = target[1]` and returns
`source.copy()`. Its caller attaches a live view to the returned child and then
changes that child to 13. The broken indexed preparation printed `[13]`, 13, 7 in
all four old configurations. Corrected GC prints `[7]`, 13, 7. ABI2RC still prints
`[13]`, 13, 7 because it lacks the pending semantic-history change.

The exact event trace explains why 7 is required by `COW-SHARED-1` and
`COW-UNIQUE-1`, despite the old output:

1. Select original child A as the mutable place; pin its owning parent and A.
2. Publish the readonly parent argument. The pinned path is copied, so this
   argument owns a fresh unpinned child B containing 7, while the mutable argument
   still selects A.
3. The callee writes A. Its `source.copy()` shallow-copies the readonly parent's
   entries. B is unpinned, so this real child-copy event reuses B and marks it
   shared rather than cloning it again.
4. The returned outer dictionary is independent. Its child B remains historically
   shared after the temporary readonly argument dies. A live view retains B.
5. Mutating the returned dictionary's child must copy shared B to a fresh child C,
   leaving the live view on B containing 7. The returned child C contains 13;
   original A still contains 7 in this self-assignment fixture.

Before the fix, the caller did not protect the selected ancestor before readonly
publication. The shallow readonly argument still reached the mutable child A;
inside `source.copy()` A was pinned, so it was cloned at that later event. The
returned fresh child lacked B's real subsequent sharing event. That is an effect
of the broken preparation, not a reason to omit the event after correction.

`history_oracle.my` independently demonstrates the sticky child rule without an
indexed mutable argument: `clone(fresh)` returns `source.copy()`, then a view is
attached before mutating the returned child. Even the immutable before GC compiler
prints `[7]`, 13, 7 on both backends. Performance's independent ABI3 design review
confirms that readonly publication followed by CHILDREN must produce the same
trace. The checker assertion is changed to require all three concrete observations:
`list(live) == [7]`, `copied[0][1] == 13`, and `original[0][1] == 7`.
This is an ABI3-dependent fixture correction justified by the exact documented
events, not an expectation relaxed to pass ABI2. The corresponding ABI2 RC failure
remains explicit until paired execution with the cohesive ABI3 implementation.

## Validation before ABI3 integration

All compilers are Debug builds. QBE commands use the default backend; actual LLVM
commands use `--release` without a later QBE override, selecting O3/full LTO.
`--force` prevents reused guest test verdicts.

- New fixture: 15 assertions in each GC-stress/ABI2RC and QBE/LLVM combination,
  60 successes. Cases cover argument order, named reorder, repeated/distinct
  selected places, key side effects, later callback replacement, arenas,
  indirect calls, fixed arrays and alternating dictionary/list paths.
- The same 15 assertions run in a standalone unaccounted executable in all four
  combinations, with identical success and balanced RC counts.
- Two standalone traps exercise a callee failure and a later argument failure
  while an arena and selected receiver scopes are active. Both return the intended
  located `R_ASSERT` in all four combinations. Every RC run restores owner/hold
  and heap-allocation/retirement totals before teardown.
- New emission/terminal-drop unit filter: 15/15 including 11 unnamed root blocks.
  Existing copy-on-write unit filter: 32/32.
- 14 broader fixtures: 85/86 GC and 86/86 ABI2RC on each backend. These receipts
  precede correcting the precise history expectation above. With the corrected
  expectation GC passes and ABI2RC fails that one fixture. Both expectation eras
  and the original raw receipts remain archived.
- Whole-tree Guardian verification and final formatting/diff checks are recorded
  with the final commit. No rule or size ratchet was increased.

Full combined gates belong to the parent integration. This isolated result closes
the indexed argument preparation defect; final history parity depends on ABI3.


## Paired ABI3 execution supplement

The immutable Debug compiler at
`d9-rc-compiler-astra/.tmp-rc/install-history-joined/bin/mylang` includes this
place correction and the cohesive private semantic-history implementation. Its
SHA256 is `586a983780fa8508a67905b58589be541ec65df5af2e84d305c8c9b0967d4455`.
The compiler owner is committing that implementation separately; these receipts
identify the actual binary and do not substitute for its combined integration gate.

All paired checks pass on actual QBE and LLVM O3/full LTO:

- Both history probes print exactly `[7]`, 13, 7 under GC stress and ABI3 RC,
  eight executions. The corrected permanent checker fixture also passes all four
  runtime/backend combinations.
- The original reproducer prints 7, 13 in all four combinations.
- The standalone driver passes all 15 assertions in all four combinations.
  Each RC backend allocates/retires 233 heap objects, acquires 26 additional
  ordinary owners and releases 259 owners, and acquires/releases 381 holds.
- Callee and later-argument failures preserve their intended located `R_ASSERT`
  on all four combinations. RC callee failure allocates/retires 16 objects,
  acquires/releases owners 1/17 and holds 19/19. RC argument failure
  allocates/retires eight objects, acquires/releases owners 1/9 and holds 22/22.

The paired receipt files retain complete commands, output, compiler/source hashes
and counters. ABI2's historical failure remains recorded rather than overwritten.
No further production change was needed after the documented argument-place fix;
ABI3 supplies the required physical-loan and semantic-sharing behavior. These
results establish this pairing, not whole-corpus WP-4 performance acceptance.
