# Complete tuple consumption proposal

Design agreed in coordinator/A01/A07/A08 review. The frontend producer and its
provenance/duplicate-analysis consumers are implemented and pass focused checks.
The full feature is not yet qualified: A07 Core transfer handling and A08 semantic
v8 validation must be integrated before native/provider/Result qualification. The
separate fresh-field receiver repair is committed as `2d471045543d74ea49014062c226b583d2963f5a`.

## Representation

Append `unpack: ?[]const ?LocalId = null` to `typed.Store`. It is valid only on a
compiler-generated `initialize`, with `element=false`. `slot` is a fresh hidden
whole-result temporary (`usage.temporary=true`, `ownership.transfer_available=false`),
not a source variable or any staged field slot. `value` is evaluated once and has
exactly the same tuple type as that hidden slot. The vector has exactly one entry
per logical tuple field. Every non-null entry names a distinct fresh hidden local
with the exact field type. Null means a source `_` explicitly ignores that field.

The source frontend stages all fields before checking/emitting any destination
receiver/index effect. Destination assignments then consume the staged locals in
source order, including duplicate destinations. The hidden whole tuple is
unavailable after checked splitting; it cannot remain a second owner.

## Ownership and modes

Checked ownership consumes the whole RHS. A named borrowed tuple requires an
explicit whole `.copy()`; partial-field move rules stay unchanged. Existing Core
`unpackPayload` splits every physical field, transfers named owners and destroys
ignored managed children. Ordinary RC compilation uses non-destructive `fieldGet`
projections into the staging locals; ownership insertion preserves the existing
borrowed-input/value-snapshot behavior. In particular the ordinary path must not
`box_take` a borrowed tuple. No source mode selector or fallback is introduced.

Named pending Result fields keep their individual handling obligations. An explicit
`_` acknowledges and destroys that field. Overwriting an unhandled existing Result
binding still rejects. Pending aggregate obligations cannot be silently dropped.

The required A05 provider tuple is supported: independent owning provider fields
become independent new roots with no dependency on the now-dead whole tuple. Whole
owner transfer must reject outstanding dependent loans. Provider-dependent resource
fields inherit the tuple's existing single unambiguous provider dependency. An
ambiguous relationship or an owner embedded together with a resource borrowing that
same embedded owner needs an explicit provenance mapping; it must refuse without
inventing one. A05's positive creates its dependent scopes only after unpacking.

## Persistence

A08 confirmed generic persistence and semantic copying handle the optional slice,
deep-copy it, and hash its presence, length and slot values. Local IDs stay local to
the copied Function.scope; they are not relocated as global Node IDs. `Store.value`
remains the only expression traversed. Semantic format v8 is required. Load-time
validation checks placement, element=false, slot bounds, unique bindings, hidden
original-slot exclusion and original-slot/RHS type identity in O(locals+fields).
Restored-tree/Core validation additionally checks exact tuple arity and per-field
logical types against the remapped catalog. Assign/range-counter Stores refuse
this marker. Old v7 private/shared artifacts cannot be adopted as v8.

## Required evidence

- Managed local and collection-slot swaps, duplicate destinations, and unchanged
  scalar tuple behavior.
- RHS evaluated exactly once and all fields staged before destination side effects;
  target receiver/index effects remain left-to-right.
- Returned/named owned tuples, copied borrowed tuples, ignored managed fields, and
  early/error exits with exact cleanup.
- Borrowed unpack without copying, partial moves, use after whole transfer and
  invalidation with live dependent resources remain refusals.
- Result fields: named handling, explicit ignored acknowledgement, independent
  copies, unhandled exits and overwrite refusal.
- Required A05 provider_tuple fixture and provider-dependent resource negatives.
- RC borrowed-input control and five checked native modes with counters/LLVM/symbols.
- Malformed persisted markers, source relocation, earlier-declaration edits and
  generic-specialization warm reuse.

A01 owns `sema_places.zig` and unique tests; root owns `typed.Store` and registrations;
A07 owns Core checking/lowering; A08 owns semantic v8 validation and cache tests.

## Frontend checkpoint

The structural producer test passes (1/1). The frontend consumer suite passes
10/10 (three named tests plus seven always-run blocks): it preserves staged
provenance, preserves named-copy independence, traces staged writes to the whole
RHS, and distinguishes extraction of the first versus second same-type field in
exact duplicate discovery. Guardian passes all 88 checks. Native tests and seven
source refusal controls are prepared but have not run against the combined Core
implementation. These results do not qualify the native tuple feature.

Shared `typed.Store` is a validation overlay matching A08 prerequisite commit
`3bbff3a61db91c4f8105749cefc1652159a2d162` (integrated by the coordinator as
`8f5206e4e`). The A01 feature commit intentionally excludes that shared declaration.
`dictionary_views.zig` is an unrelated authorized validation overlay, also excluded.
The exact root-authored frontend/Core test imports belong to this checkpoint.

The follow-up fixture correction renames only the evaluation-order helper to
`evaluated_pair`, avoiding shadowing the unchanged provider fixture local `pair`.
`frontend-followup.json` records updated source hashes, the preserved original
E_SHADOWING, and successful combined frontend admission. All four pending-Result
frontend refusal controls also pass. `generic-manifest.json` pins the additional
three-instantiation cache probe. Native and integrated cache qualification remain
pending. Initial `manifest.json` hashes describe the original checkpoint revision.

The registered native oracle now requires `tuple-providers 56`, computed from the
lengths of the actual independent provider file contents after complete tuple
unpack. The unchanged standalone A05 fixture remains preserved separately. The
extended combined source passes ordinary frontend checking; its native three-line
output is still an expected oracle, not an observed native result.
