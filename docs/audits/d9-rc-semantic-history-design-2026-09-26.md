# RC semantic sharing history: proposed correctness baseline

Status: approved contract, API declarations only; implementation follows isolated
runtime tests. Base `8dccb3e1`, including the
snapshot correction `540560ee`, arena lifetime correction and completed aggregate
publication. The exact motivating outputs are in
[d9-live-view-snapshots-2026-09-26.md](d9-live-view-snapshots-2026-09-26.md).

## Observable contract

Preserve the tracing runtime's semantic COW history independently of physical O/H
counts. A real semantic SHARE sets the existing SHARED mark on each ordinary
mutable payload it reuses. Releasing a physical owner does not clear that mark.
An ordinary mutation detaches a marked payload even at O=1/H=0; the new shell is
unmarked, and its reused mutable children receive their own semantic marks.
This deliberately starts with the conservative GC behavior. Skipping a no-view
clone later requires a proof preserving its child-history effects too.

Whole views and H edges preserve identity and never trigger SHARE. Scalar,
immutable bytes/text, raw resources and immutable box pointers are not mutable
payload marks. A pinned semantic transfer clones the finite protected path and
keeps the new outer shell unmarked; it does not mark the original pinned object.
Unboxing a mutable-bearing immutable body remains a separate semantic event,
matching the GC emitter's existing needsCopy and scoped-projection exclusions.
Actual payload region preservation remains the joined arena contract.

## Why a marker-only patch is insufficient

`qbe_rc_ops.after` currently gives every ordinary borrowed managed result an
owned snapshot immediately. That physical copy can clone a pinned source before
its later `value_copy` executes. Marking the resulting fresh shell would mark the
wrong object and lose the distinction between reuse and an already-completed
pinned snapshot. Aggregate projections can cross several such operations.

The initial implementation therefore needs a physical loan state, rather than
trying to reconstruct origin from O counts, H presence or a global clone bit.
A per-object "fresh clone" bit cannot stand for the different obligations of
multiple values referring to that object.

## Physical loans before publication

For copyable borrowed results, copy the inline bytes into private operand storage
and acquire H, not O, for each physical managed edge. This operation never clones,
marks or changes a container's logical child edges. Existing H leaves acquire H
as well. The private bytes avoid retaining addresses into a parent that cleanup
may clear or resize. Immutable boxes are terminal held allocations; their bodies
continue to own their ordinary children.

Use a distinct `MYL_QBE_RC_LOAN = 16` journal role, without changing any frame
or slot offsets. Its drop visitor releases one H per managed leaf. It is mutually
exclusive with ordinary counted/unique/construction roles; it is not the existing
single-pointer held receiver role. No raw unique resource may enter this path.
Existing linear resource transfers retain their guarded move/close protocol;
tests must establish that every borrowed-result site carrying unique cleanup is
handled by that protocol before enabling the general loan path.

`qbe_rc_values.finish` uses a loan for ordinary borrowed copyable results. Local
load/store and hidden temporary hooks preserve the role until an actual ownership
publication. A loan can never enter the inline TAKE path. Explicit semantic copy
sites, canonical owned call/return boundaries and owning collection/aggregate
stores convert loans transactionally to their required O/H representation, then
drop the old loan. Existing proved guard-free receiver/read loans remain intact.
This work uses logical journal indices and the compact journal's address helper;
no new raw entry or guard arithmetic is required.

## Semantic operation and emission boundary

Add a small `qbe_rc_history` planner/emitter that classifies the GC-equivalent
semantic event before physical ownership lowering. Its inputs are the bytecode
operation, finalized ownership copy decision and existing COW plan. The event is
not inferred from whichever physical helper happens to run.

The event inventory includes:

* Real `value_copy` assign/store/return/payload/argument sites, including the
  dedicated children and source-children modes used by shallow/bulk operations.
* Read-capture shares before later callback evaluation, which have no explicit
  `value_copy` instruction. GC-only capture sharing must have an RC counterpart.
* Mutable-bearing box-body materialization that GC lowers through cow_unbox;
  pure boxes and already-protected receiver projections keep their exclusions.
* Child publication during a semantic uniqueness clone. Physical lifetime
  acquisition, view creation, holds and journal moves do not create history.

Freeze typed native entry points for semantic COPY and TAKE into empty pending
storage, with six or fewer parameters: heap, native type, destination, source,
target region and a semantic mode (direct/children/source-children). A loan always
uses COPY; an ordinary owned token may use TAKE. Physical relocate/adoption stays
separate. The compiler publishes the existing pending guard only on success.

Extend the iterative transfer/clone transaction with a semantic policy. Reused
mutable leaves enqueue SHARED updates; pinned leaves produce fresh unmarked
shells and apply child policy while filling them. H leaves are identity copies.
Commit mark changes only after all fallible work succeeds. Count, metadata,
region or allocation refusal must leave source pointers, guards, counts and
observable history unchanged; already-prepared clones are aborted through the
existing construction journal. Retained marks on failure could themselves alter
a later live view, so rollback cannot treat them as harmless metadata.

Shallow collection producers must initially acquire physical child edges without
premature pinned snapshots. Their following semantic children operation performs
the one required snapshot/mark transaction using those original pointers. The
same separation applies to aggregate initialization and native collection stores:
compiler-marked publication must not be repeated by an ordinary physical acquire.

`myl_rc_unique`, unique_owned/borrow/held and bulk element preparation all consult
SHARED in addition to physical ownership. A semantically marked detach always
executes the child-history policy. No inline uniqueness shortcut may bypass it.
Inline TAKE remains a physical relocation after publication and preserves header
marks; it never clears history. Counter builds keep counting actual O/H traffic
and allocations at their existing physical sites.

## Borrowed entries and optimization admission

Initially decline optional borrowed-body certificates when they would remove a
GC semantic event. A mutable-bearing return copy cannot simply disappear into a
borrowed ABI. A later extension may attach a complete return publication recipe
and execute it in the caller before releasing the anchor. The canonical owned
ABI remains the fallback, so this restriction does not reject legal programs.
Pure immutable accessors, including the accepted schematic accessor when its
physical result has no mutable payloads, can retain their certificate.

Apply the same audit to whole-body readonly scalar-result elision: scalar return
alone does not excuse a skipped mutable-bearing unbox or internal semantic copy.
Retain the certificate only when the body has no such event. Existing static
receiver/loop proofs remain valid only when their closed interval cannot create a
new semantic mark; history events must participate in that interference check.

## Frozen interface and sequencing

`native_rc.h` advances `MYL_RC_ABI_VERSION` to 3; `qbe_runtime.h` reserves
LOAN16 with no offset changes. `native_rc_values.h` declares
`myl_rc_native_loan(heap,type,dst,src)`, `myl_rc_native_unloan(heap,type,value)`
and `myl_rc_native_publish(heap,type,dst,src,region,semantic_mode)`. Modes are
DIRECT=0, CHILDREN=1, SOURCE_CHILDREN=2 and independent TAKE=4; the two children
modes cannot be combined. Header declarations alone emit no new loan role.
The parent owns the coordinated rc-v3/rc-v3-counting selector/cache/stats change,
which must join before the compiler emits loans.

Loans remain private to a guest frame and cannot escape through an ordinary
heap/provider ABI. The semantic event is applied at the original GC evaluation
point before later callbacks, never deferred merely until an eventual store.
Lifetime-only O>1 clones are distinct from semantic detaches: the former must
not manufacture child history. Fresh semantic clone shells remain unmarked;
only reused ordinary mutable leaves/children receive committed marks.

## Implementation split and validation

1. Freeze the physical-loan and semantic-publication API, frame role and versioned
   ownership tag with the runtime/header and compact-journal owners. No layout
   offsets change. Add C refusal/pin/history tests before connecting guest code.
2. Add transactional runtime loan/share/drop and marked uniqueness, preserving
   iterative traversal, region rules, H views and unique finalization.
3. Wire compiler loans and semantic events as one cohesive correctness slice,
   including collection children, matches, box reads and conservative certificate
   admission. Do not enable a marker-only subset as a completed implementation.
4. Execute exact QBE/LLVM GC-vs-RC history probes, then the full guest, golden,
   trap, arena and accepted performance corpus. Optimize only after parity.

High-value tests include both mutation orders from the motivating example;
share/drop/mutate before creating a view; nested list/dict child views; whole-view
copy as a negative marker control; callback snapshots of pinned nested payloads;
H-only receivers; shallow copy/slice/extend/update; repeated variant/match and
boxed projections; canonical and borrowed calls; nested arena escape; count and
metadata refusal followed by a successful retry; and million-deep boxed paths.
Every probe reports the exact view/snapshot/original values and actual balanced
O/H/allocation counts on both real backends.
