# Guarded immutable-byte scan loops

Status: reviewed and implemented as a bounded compiler slice. Base is root-created
`45b4b62970d23d4724458bd1f0b86dead4b17a0c`. The completed managed-helper
compiler and evidence remain fixed in the other worktree.

## Observed cost and existing machinery

The exact unchanged `bench/parity/micro/bytes_scan.my` builds an 8 MiB immutable
bytes value, then scans it sixteen times. Root's matched diagnostic ratios are
3.554239× accepted GC on QBE and 12.666139× on LLVM. Its saved emission uses the
immutable 49c compiler, SHA
`49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.
Commands, compiler/source hashes and full IL are in `.tmp-bytes/emission-identity.json`
and `.tmp-bytes/{rc,gc}-main.ssa`.

The inner loop is PC118..137. LOAD_LOCAL data7 and the scalar index precede
GET_INDEX PC124. The body has no loan/acquire or semantic SHARE. It loads the
immutable header, normalizes the signed index, checks bounds, reads one byte,
then calls `values.finish`. That emits a guarded operand-zero drop through
`%rcguards + 40`. The slot can own elsewhere in this function, but this raw bytes
load does not publish an owner. The branch is therefore false on valid ordinary
execution and blocks the generated no-call/vectorizable loop.

The existing language-level loop plan already supports immutable byte storage,
checked fallback, stable storage addresses, signed normalization and overflow
facts. GC uses its guarded fast copy. RC's supplementary read-loop certificate
currently admits scalar list buffer operations only, and requires every operand
type to be scalar; bytes GET_INDEX cannot pass. Its final `quietCopy` rejects the
remaining drop call even though that particular guard is clear.

## Narrow proposed admission

Extend the existing RC read-loop certificate, without changing loop range facts,
normal indexing, generic drop behavior or runtime helpers. Retain existing limits:
4096 function instructions, 256 locals, 200 body instructions, eight concrete
owners, and the shared 262144 analysis-charge allowance. Add at most eight exact
byte-read triples, each storing GET_INDEX PC, source local and operand position.
Charge their suffix-entry/metadata scans against the same allowance. Before
`holds.mayHold`, charge the full local scan plus one whole instruction scan for
every same-type local (including named locals that iterationOwner would skip).
This upper bound prevents nested hidden-iterator scans from escaping the budget.
Use shared `ownership_sources.targetsSatisfy` for all explicit successors, with
variant-arm visits charged separately. Fixed-size
membership checks are bounded independently by eight.

A byte read must be exactly these three adjacent instructions within the loop:

1. LOAD_LOCAL of one concrete immutable bytes home.
2. LOAD_LOCAL of one ordinary i64 index local.
3. GET_INDEX of the same bytes type, returning u8.

The incoming stack at the first instruction contains only scalars. The next two
states contain exactly that bytes value at the recorded receiver position and
otherwise scalars. The successor is scalar-only. No branch may enter either
suffix instruction; the existing loop proof separately rejects external body
entries and unexpected backedges. Initial scope can reject constants or more
complex index expressions even when otherwise safe; this exact triple admits
the measured bytes_scan site.

The owner is a private concrete local: no by-reference/caller-storage, place,
move alias or semantic alias representation. Its type must satisfy
`typed.isByteString(record)` and `shape.buffer == u8`; mutable byte_buffer, str,
dictionary, boxes and arbitrary managed output remain excluded. The source must
have a retained local journal slot. Refuse function-wide `holds.mayHold` for this
bytes type, because it would make LOAD_LOCAL emit conditional H publication.
This deliberately leaves such bodies on their existing path. All other local
loads/stores stay scalar, so no bytes home can be rebound within the loop.

Reuse the existing quiet planner checks at every instruction: no COW/share,
capture, mutable plan interception, early local release, arena action, callback,
allocation or implicit ownership effect. The complete generated fast body must
still pass unchanged `quietCopy`: only cold failure calls may remain. Existing
scalar list admissions and their O/H guard remain unchanged.

## Entry guard and empty-token induction

Before any fast-copy payload/range read, test each byte home is live with its
ordinary typed-owner journal role. Reject LOAN/H, borrowed or empty roles to the
original loop. The ordinary token can name heap, arena or immortal bytes; the
loop cannot retire or rebind it. Its header owns canonical backing, so interior
byte storage remains live for the complete loop.

Also load the actual retained operand guard for each receiver position and
require zero before entering the fast copy. A nonzero guard branches to the
original loop without dropping, clearing or changing anything. Guard access
uses the journal's logical-to-physical mapping, never a hardcoded offset. A
missing slot refuses certification rather than aliasing another guard.

This runtime zero check establishes the base case independently of an optimistic
semantic-liveness inference. The exact raw bytes LOAD publishes no token; the
index load and all other admitted scalar instructions publish none. GET_INDEX
returns a scalar and drops only the recorded bytes operand. Thus the receiver
guard remains zero on every path and backedge. No other managed producer, call,
MOVE, store, variant payload or hidden H publication is admitted. External head
reentry reevaluates both anchor and empty-operand guards.

Keep the proof only in the active fast-copy emission context, for example an
optional read certificate in `qbe_loop_version.Active` (currently four fields).
The narrow `values.drop` query may omit a drop only when both its current PC and
operand index match a saved byte-read entry in that active certificate. It must
not trigger while emitting the original copy or an independently admitted
scalar/hoisted loop. All other drops retain their current behavior.

No token or drain is removed: the suppressed branch's guard is proven zero.
There is consequently no changed finalizer boundary, ownership traffic,
uniqueness, PIN/SHARED state or arena retention. If bounds/range/overflow or
ownership entry guards fail, the original code retains the original trap PC,
message, cleanup and negative-index semantics. Finite step accounting already
disables versioning; preserve that behavior.

## Proposed source ownership and controls

Expected edits are limited to `qbe_rc_read_version`, its tests, a small optional
field/setter in `qbe_loop_version.Active`, and the exact fast-copy query in
`qbe_rc_values.drop`. A separate helper can hold byte-specific triple analysis
if needed to keep the existing module cohesive. No `qbe.zig`, RC State, journal
layout, runtime, normal bytes emission or record-read hook change is planned.
Core confirmed these sections are disjoint from its named-record field reads;
`quietCopy`'s public API and semantics remain unchanged.

Before measurement, verify actual PC124 admission and a fast copy with no RC
cleanup call, retaining a real ordinary fallback. Focused proof tests cover
wrong type/result, H-capable source, alias/byref home, branch entry into the
triple, unexpected producer/call and exhausted bounded storage. Check the exact
operand guard in emitted IL and a rejected/synthetic guard fallback, not just
presence of a fast label.

Actual backend controls cover nonempty and empty immutable values; short loops
that use fallback; signed negative indices, upper/lower bounds failures and
finite step traps; aliases/snapshots and bytes backed by caller arenas; source
replacement before a loop/reentry; and a mutable-buffer/callback negative.
Ownership counts should be identical, not merely balanced. Keep the control
matrix bounded to the changed lifetime/check boundaries.

After root and compiler peer review, source freeze and those controls, run the
unchanged full bytes_scan on reserved CPU10: interleaved before/after median-three
instructions on actual QBE and LLVM with 100% event running, exact output and
separate counted variants. Preserve accepted GC denominators and binaries.
No full-corpus/default or acceptance claim follows from this isolated slice.
