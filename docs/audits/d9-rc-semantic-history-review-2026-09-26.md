# Independent review of semantic history and physical loans

This is a read-only review of the contract committed as `795c7f6e`, after the
small-allocation runtime change `16ecdc50`. It records implementation obligations,
not a claim that the proposed runtime or compiler wiring has passed validation.
The motivating GC/RC discrepancies remain correctness work until the cohesive
implementation reproduces the accepted observable behavior.

## Representation

The existing ownership shape plus a distinct LOAN16 journal role is a reasonable
minimal general representation. Private inline bytes avoid retaining addresses
into a parent that can resize. One H per direct managed leaf protects projected
children when a parent later replaces or drops them. Holding only the parent
cannot provide that guarantee. Ordinary O acquisition would alter uniqueness;
a per-object fresh-clone flag cannot identify the origin of each physical value.
Existing proved callback-free read loans can keep their cheaper representation.

There is no existing nonmutating native-type unique-content validator. The
iterative unique-drop walk is a useful model, but shape NONE does not imply
copyability: raw resources deliberately have no counted edge. Inline raw unique
fields must be rejected, and an ordinary box pointer can hide a body with a unique
finalizer. Admission therefore needs whole-value compiler copyability and any
corresponding runtime invariant, rather than only the counted shape. Native
collection kind 4 also covers mutable byte buffers; the immutable-bytes exclusion
must retain the source type distinction.

## Lifetime, cleanup and refusal

H acquisition on an arena allocation is a no-op. A physical loan does not extend
the arena's chunks. Arena watermark cleanup, surviving-slot checks, trap unwind
and frame cleanup must recognize LOAN16 before chunks are reclaimed. Loans must
not cross an ordinary owned provider/heap ABI without conversion.

Semantic pinned clones must preserve the source region, bounded by the legal
destination, including each child clone job. Using the current destination depth
blindly would recreate the corrected older-heap-to-inner-arena false escape.
Explicit escape remains the separate operation that migrates younger objects.

Acquisition must count duplicate leaves and existing H leaves independently.
A late H-limit refusal must restore every earlier acquired hold and leave source
bytes intact. Drop must release H rather than reinterpret the shape as ordinary
O ownership, clear the guard and visited slot before callbacks, and retain the
pre-reserved, allocation-free iterative walk. Raw resource close remains separate.
Useful tests include duplicate aliases at the hold limit, inactive variant arms,
overlapping storage refusal, an ownerless H receiver, arena cleanup and a
reentrant finalizer that registers metadata.

## History transaction boundaries

Pending SHARED changes must commit after all fallible preparation and before
releasing source anchors or draining callbacks. Rollback must discard pending
marks before aborting fresh clones, since abort can run finalizers. Preserve
preexisting marks and all unrelated header bits. Any objects named by the mark
journal must stay live until commit or rollback completes.

The history transaction must match each physical helper's atomicity promise.
For example, dictionary key/value/output batches cannot commit a key mark and
then refuse the value's count increment. Conversely, a real language SHARE that
completed before evaluating a later trapping expression must stay committed.
The semantic event inventory needs to distinguish these boundaries explicitly.

Shallow producers that invoke comparators or other guest callbacks cannot defer
the original capture/share event until after that callback. Their original
pointers must remain available without publishing a different snapshot first.
Audit existing eager arena SHARED writes in physical COPY, flat transfer and
memo reuse: adding a semantic mark journal alone does not make those writes
transactional or distinguish physical traffic from semantic history.

## Clone reuse and optimization proofs

The current staged clone memo is keyed by source pointer and target region.
The semantic implementation must prove that this key still identifies one child
publication policy, or include the necessary policy distinction. Repeated pinned
diamonds and mixed O/H references should test shell reuse, subsequent child-view
observations and refusal rollback. Fresh shell identity alone does not explain
whether a later semantic reuse of that shell needs a mark.

All uniqueness shortcuts must consult the new history contract. Inline TAKE
remains pure physical relocation of an already published owner, and LOAN16 must
be excluded even where the producer was previously classified as owned. Borrowed
body and readonly scalar-result certificates need the stated semantic-event
audit; scalar output does not prove that internal unboxing/sharing was inert.

No frame offsets need to change, but the new role and semantic behavior require
the coordinated version-3 ownership identity before emission. Isolated C tests
should precede activation, followed by actual QBE/LLVM history, arena, trap and
collection probes with balanced physical counters. The full matched corpus is
still required after correctness; these review conclusions grant no performance
exception.
