# Fresh dictionary loop-entry uniqueness

Reviewed design after the committed key slice `a8f852b9`; parent authorized
the bounded prototype after runtime review. The previous immutable compilers
and receipts remain unchanged. New implementation/results are reported
separately when validated.

## Actual remaining site and plausible cost

The unchanged `dict_count` ownership report already proposes the root check at
PC64, local5 (`counts`), at loop header34, backedge74. It also proposes the
separate key-list setup check at header10. This is not a missing semantic
hoist: RC first resets all semantic placements, then `qbe_rc_hoist.proven`
requires `listElement(root)`, and `qbe_rc_fresh_root.fresh` only accepts lists
with plain elements. Managed string operands would also fail its scalar
interval grammar. Finally, dictionary tail/key authority is finalized after
that physical-hoist pass. Simply admitting dictionary types there is unsound
and would not compose the required lifetime proof.

The actual root definition is PC28 `MAKE_RECORD dict<str,int> fields=0`, PC29
canonical named `STORE_LOCAL 5`. The loop is PC34..74, with the already proved
key/capture interval PC38..68. The dictionary is never rebound, copied or
referenced in that loop. The current emitted main retains one runtime unique
site for list setup and one at PC64. Full counted runs have 2,001,000 checks:
1000 setup appends plus two million dictionary updates, with zero clones.

At most 1,999,999 checks are targeted: preserve one real dictionary check on
loop entry. O/H/alloc/retire/clone totals should stay at 2001/2001/2029/2029/0;
uniqueness should become 1001. These are predictions to validate independently.
The post-key totals are 1,429,539,240 QBE and 884,367,218 LLVM instructions,
2.161694 and 2.005210 times GC. Reaching 1.3 requires saving 569,842,697 and
311,022,207 instructions, approximately 285 and 156 instructions per removed
check. Descriptor/shape lookup, bridge and generated guard/role work make this
plausible, but no timing attribution establishes that saving yet. Hashing,
dictionary lookup/write, scalar arithmetic and true key insertion remain.

## Initial admission

Reuse an existing semantic COW proposal and one already finalized anchored-key
dictionary-tail certificate. Require a natural loop with empty operand stack
at its header, one admitted dictionary write tail for this root, no interior
entry, and no loop-body reentry bypassing the header. Keep the existing finite
function limit4096 and loop-span limit1024; explicitly charge candidate scans
and refuse exhaustion. Do not widen the existing list proof or admit arbitrary
dictionary operations.

The root must be its own retained canonical named O home: nonparameter,
nonreference, non-H/non-LOAN, no caller/place/box/alias binding or alternate
entry. Initially accept only an immediately preceding empty dictionary
`MAKE_RECORD fields=0` at its single static store. Native lowering calls
`myl_native_dictionary_new`; it does not wrap an existing payload. Do not
infer freshness from result type, an ordinary local name or absence of SHARE.
Exclude transfers through other locals in this first slice.

The direct constructor produces an owned operand. The canonical named store
uses transactional TAKE, clears that operand guard, copies pending bytes to
the named slot, clears the pending guard and publishes the O local. There is
no retained constructor local in this exact path. Dead bytes in unguarded
operand/pending scratch are not physical owners. This handoff must stay part
of the admission argument; a future store interceptor or local handoff requires
its own proof and is refused here.

Audit the root's complete allocation lifetime through the loop backedge, not
only the body. The store must dominate the header. Every explicit and implicit
writer, read, reference, move, drop, pattern binding, projected receiver,
snapshot/publication, field-transfer hook, history event, scope and planned
release is checked. Root loads are allowed only for the exact certified tail;
root receiver operations are limited to its plain-result get and terminal
write. No call, alias escape, retained view, arena transition, extra owner or
semantic mark may occur between construction and the last backedge. A previous
enclosing-loop iteration cannot return to the loop after a later publication
without recreating the fresh root. Post-loop publication itself remains legal
when it cannot feed such a backedge.

Inside the loop, accept the existing anchored key/capture interval by its
explicit tagged authority, with the original key/root/value journals and
terminal runtime write. Outside that interval require the existing bounded
plain scalar grammar plus exact CFG edges. No additional managed operation is
accepted on the basis of its type. The key certificate still proves complete
empty-token capture/key lifetimes, actual source O authority and real iterator
fallback independently. It does not establish dictionary exclusivity itself.

## Entry placement without weakening existing certificates

Run this optional dictionary refinement after dictionary-tail/key finalization
and before journal/frame finalization. A narrow new helper can append a
deduplicated root entry to the existing `cow_plan.Loops.entries` at the semantic
header, preserving the current aliases, places, COW sites and checked flags.
The existing `@ce` entry routing then performs a real check for every external
header entry, while `qbe_rc_hoist.covers` suppresses the covered runtime call in
the body. The first implementation should not alter loop-version admission,
cached backing pointers, scalar lowering or the terminal native write.

Keeping the original body site metadata lets the old tail proof retain its
exact first-check premise: that check is now discharged by a separately
certified entry. The new entry is outside the key interval, and no certificate
is partially recomputed against a changed place graph. If this composition
cannot be established explicitly, retain the original per-iteration path.

## Runtime and failure obligations

Fresh construction plus the complete no-publication lifetime must imply one
physical heap O edge and clear semantic SHARED/immortal state (or the analogous
unshared inherited-arena allocation). `myl_qbe_rc_unique_local` uses already
registered descriptor/shape lookup; `myl_rc_unique_owned` returns immediately
when `myl_rc_unique` succeeds. That successful path allocates nothing, retires
nothing, invokes no finalizer and cannot report a count/region refusal. Runtime
peer review must confirm this before implementation. This is what permits the
one real check to precede a zero-iteration loop condition without introducing
a new failure; shared or uncertain entry roots must refuse the certificate.

Builtin immutable string keys and plain values cannot acquire an owner or
SHARED mark on the containing dictionary header. The native write may grow or
replace backing storage, acquire real inserted-key owners and fail at its
existing location, but keeps the header identity/ordinary root obligation.
All generation, size, memory-budget, region and publication checks remain.
No storage pointer is cached across growth. No arena boundary crosses the
interval. Inherited arena controls are required; general arena elision is not
proposed. Ordinary guest/finalizer-reentry queue behavior remains the existing
terminal write's responsibility.

Runtime peer review confirmed this premise against the current bridge,
slot/shape lookup, unique predicate and dictionary write. Compiler peer review
also found no blocker, contingent on the direct owned-operand handoff and
complete root lifetime. The prototype conservatively refuses every scheduled
nonempty release, even when the current release emitter could omit it. Only
the already certified empty key/list/dictionary capture guards are exempt.
Metadata/CFG scan rows and switch successors are charged explicitly; inherited
type/shape inspection is separately bounded and is not described as one
primitive operation per charged row.

Keep logical step/bounds/overflow/frame checks and caller cleanup. A trap before
the original first write observes the same contents because the fresh entry
check cannot detach. Disappearing internal successful check counts are the
intended optimization; native allocation/refusal behavior must remain exact.

## Controls before full measurement

Structural: actual dict_count has one `@ce34` root check and no body unique
call; first list setup remains. Admitted direct fresh constructor, inherited
arena, zero iteration and post-loop owned return should retain real journals.
Refuse preexisting/surviving snapshots, snapshot creation during the loop,
reference/callback mutation, H views, root rebinding, pattern/parameter roots,
interior entry, unknown managed body operations, unproved key authority and an
enclosing iteration that publishes then reenters without fresh construction.

Guest/trap: existing key/tail controls, exact zero-iteration shared-snapshot
negative, later observable snapshot, bounds/overflow and a few logical step
budgets before the first write; low-budget dictionary growth must fail at the
same original write, including inherited arena. Preserve finalizer reentry.
Do not repeat the known GC-stress physical-floor timeout or a broad stress
matrix without a new unresolved concern.

Only after exact emitted admission and reduced counters match predictions,
request a timing CPU for unchanged full2M median3 QBE/actualLLVM comparisons
against the immutable post-key compiler and accepted GC. No default change,
runtime uniqueness relaxation, eager capacity reservation or RSS acceptance
claim is part of this proposal.
