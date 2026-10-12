# Pending ownership contract reviews

These are source reviews of proposals under implementation. They are not guest
qualification or approval to promote the default. Support6 component execution
remains independent of both proposals.

## Borrowed dictionary selection

A07's draft uses the compiler-only call
`myl_core_borrow_select_v1_<dictionary physical type>_<value physical type>`.
Its three explicit operands are the selected value, dictionary, and evaluated
fallback. The exact signature borrows all three and returns the selected value;
the emitter removes the marker. The selected phi's incoming edges must borrow,
and both input roots must remain live through every use of the result.

The existing cache representation supports this ordinary call without adding a
field to every instruction:

- Stage-store keys include the compiler identity, so changed production code
  creates a separate namespace.
- Lowering discovery hashes ordered physical compounds and exact helper names and
  signatures. Physical type ordinals must not be relocated as string ordinals.
- IR snapshots retain the full physical catalog and helper signatures. The
  canonical call digest retains this versioned marker name; its special renderer
  normalization does not apply.
- No wire layout change occurs solely from using an existing call instruction.
  Reusing an existing marker version with different semantics would require a new
  version, and any later wire-field change requires its normal schema bump.

The review requires source loans for **both** possible roots, including temporary
fallback storage; rejection of escaping, consuming, or invalidating uses; strict
declaration/call/phi validation before ownership; and bounded graph traversals.
The draft's deduplicated `sharedLiveUses` and `selectionOwners` address repeated
ancestry. The remaining recursive `viewBelow` walk was reported to A07 because
shared child diamonds also require deduplication there.

Required evidence includes fresh and cached hit/miss paths, invalidation of either
root, exact malformed-marker refusal, earlier physical-type discovery edits,
consuming-use refusal, and nested selection scaling. These tests have not yet
been run by A08.

## Complete tuple unpack metadata

A01 proposed `typed.Store.unpack: ?[]const ?LocalId`, valid only for a generated
initialization that evaluates and consumes the whole tuple once. Null children
mean explicitly discarded fields. There is no surviving partial tuple owner.

The generic persisted codec, AST deep copier, semantic copier, and lowering tree
hash already recurse through this optional slice. Each slice is independently
copied. `LocalId` remains unchanged because a cached body carries its complete
`Function.scope`; it must not be relocated like a global node or function ID.
The existing typed walk visits `Store.value` once, and this metadata adds no
expressions to traverse.

Adding the field changes serialized checked trees and therefore requires
`semantic_store.format_version` to move from `semantic-cache-v7` to a new version.
The file explicitly requires a bump for layout, tag, or validation changes. A
default initializer on the new Zig field does not make old byte layouts valid.

Current durable-body checks do not establish the proposed contract. Before a
decoded unpack reaches lowering, validation must establish initialization-only
placement, `element == false`, an unavailable original tuple slot, exact tuple
arity, unique in-range non-null destination slots, and exact field types. Unpack
metadata on assignment or range-loop start/end stores must be refused. Structural
checks possible before catalog relocation should run while loading; exact type
checks require the restored catalog or equivalent recorded recipes.

Required evidence includes malformed metadata, independent copied slice storage,
relocated source and earlier declaration edits, specialization reuse, and
rejection of prior-format stored bodies. The shared declaration and implementation
are not yet present in A08, and no schema bump has been applied here.
