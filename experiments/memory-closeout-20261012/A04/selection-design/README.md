# Distinct-parent selection: bounded implementation proposal

Status: **unimplemented public-contract blockers**, not a qualification result.
This follows the list-only fix `cd05d9627f5c492cfa332552b939362ee6ef59a8`.
The scalar-index list fix does not establish a safe join between unrelated
owners. A09's pinned Support6 reproducers and ordinary typed/Core dumps remain
in `A09/repros/managed-selection/`; no original diagnostic is overwritten.

The minimal public failures are `min(a: str, b: str).copy()`, the matching `max`,
and `value: str?; value.unwrap_or(".").copy()`. Support6 refuses their generated
`<collection>` result before the requested copy. `min`/`max` overwrite a hidden
alias initially rooted in `a` with one rooted in `b`; `unwrap_or` joins a borrowed
Some payload with its already evaluated fallback. Treating this result as an
owner or weakening generic `single_owner.merge` would lose one possible parent.

## Proposed source representation

Prefer an explicit compiler-only typed expression:

```text
borrow_selection {
    kind: min_text | max_text | optional_default,
    first: NodeId,
    second: NodeId
}
```

The enum and operand types validate the exact generated operation. The first two
kinds require `str` inputs and output; the optional kind requires the established
Option shape with the second operand and output matching its payload. The frontend
keeps scalar extrema and scalar optional lowering unchanged. The new representation
has the same ordinary semantics and no source syntax. Resource/affine payload
boundaries require A07 review; they must not be made copyable by a selection marker.

For managed results, the ownership checker evaluates the first operand once as a
read, loans all of its possible roots while checking the second operand, then
preserves both roots in the result's provenance. Optional defaults remain eager.
Borrowed result moves/stores/returns require explicit copies, and ambiguous stored
views remain refused as in readonly dictionary `get`. A compiler receiver can hold
this read-only selection even if both operands are fresh temporaries and there is
no source-local origin; it must not accidentally become an owning receiver merely
because `origin()` returns null. Reads of both evaluated owners remain valid until
the selected value's last read/copy. Normal `.copy()` produces an independent owner
and terminates those provenance dependencies.

A07's existing `ambiguous_borrow`, bounded `loanExpression` parent worklist and
receiver-loan path provide the source machinery. Extend only the new expression's
exact parent edges; do not visit arbitrary function arguments as return provenance.
Do not change generic branch/loop merge. In particular, marking the final hidden
slot ambiguous after checking the old block is insufficient: mutation during the
second argument or eager default would already have invalidated the first input.

A block descriptor alternative would need exact first/second initialization slots,
order and result, plus special evaluation of those initializations. It also risks
being dropped by existing block rewriting (`collection_lower.fuseImmediateByteRange`,
`dictionary_views`) and makes the common expression identity less direct. The
explicit expression avoids those issues at the cost of the enumerated walkers.

## Proposed Core contract

Extend A07's exact compiler marker proof rather than admitting a native runtime
helper. A separate versioned kind/name distinguishes dictionary lookup, text
selection and optional payload selection; the physical signature remains three
borrowed operands `(selected, first_owner, fallback)` and a borrowed selected
result. For text, both owners have the selected type. For optional selection,
first_owner is the physical union and fallback has the selected payload type.

The lowerer evaluates each input once in order. Text comparison remains strict
and returns the first input on equality. Optional Some reads the payload without
transfer; None selects the eagerly evaluated fallback. Marker validation proves:

- Compiler runtime linkage, exact canonical numeric type identities, signature,
  no ownership/consumption/view bits, and no executable marker body.
- The selected value resolves to one proved parent choice, or exactly a two-input
  phi over those choices with valid CFG predecessor association and dominance.
- Text choices are the exact evaluated first/second SSA values.
- Optional choice is the exact non-transferring payload read of the first union
  owner at its validated Some tag (including a validated box projection when
  needed), or the exact fallback. Arbitrary aggregate projections do not qualify.
- Borrowed marker/phi results cannot feed consuming instructions, escaping stores
  or owning returns. Bounded copy resolution rejects malformed cycles.

Reuse the existing two-parent liveness and child edges in `own.zig`, exact marker
handling in emission and allocation contracts, and A07's current dominance/corrupt
marker validation. The emitter substitutes the selected value; no native helper,
RC operation, allocation or implicit deep copy is introduced by the marker itself.
The unused fresh operand must be destroyed once after its last use. The selected
parent must survive the borrow. Ordinary controls use ordinary lowering and must
preserve output/effects/noalloc behavior.

## File ownership request

A04 already owns `src/prelude_builtins.zig`. Request `src/option_flow.zig` for the
second producer and a unique `src/core/build_borrow_selection.zig` lowering helper.
Coordinator owns the typed schema (`src/typed.zig`). Additional exact reservations
are needed for `src/typed_walk.zig`, `src/core/typed_dump.zig`,
`src/sema_expressions.zig` child accounting, `src/value_semantics.zig`,
`src/effects.zig`, and `src/origins.zig`. These consumers must visit both operands
and classify the result as borrowed/existing storage, never fresh by default.
Compiler errors from exhaustive switches identify further consumers; reserve any
additional file before editing. A scalar default's own effects remain unchanged.

A07 owns `src/core/single_owner.zig`, `build.zig`, `own.zig`, `emit_llvm.zig`,
`verify_ir.zig` and the existing `borrow_selection.zig` contract; use authored
patches/reservations. Marker allocation/cost dispatch must continue recognizing
only validated exact declarations, including source-extern rejection.

A08 owns `semantic_copy.zig`, `semantic_store.zig` and relevant cache identities.
Reflection already traverses typed struct/union fields in semantic copy/store,
but the new tag changes persisted layout and requires a format/contract bump,
valid/corrupt relocation tests and eager ownership checks on replay. Core source
identities and optimizer validation must reject old/invalid marker artifacts.
The coordinator registers unique tests and updates public contracts only with the
implemented behavior. This document makes no pending change authoritative.

## Required evidence before integration

Keep all four A09 managed cases plus optional iteration and scalar controls.
Add dynamic Unicode/tie values, both runtime optional branches, empty strings,
fresh and borrowed inputs, nested selections, nested managed optional payloads,
explicit copies surviving replacement of either input, and discarded results.
Verify both eager evaluation and receiver-before-default order with counters.

Negative cases must cover mutation/move of either possible parent by a later call
argument; invalidation of the first parent while evaluating the second input;
`unwrap_or` default mutating its optional receiver; stored/returned selected
owners without copies; stored/escaping selected views; and affine/resource
copy boundaries. A copy completed before subsequent owner mutation is positive.

Run five checked native modes, ordinary scalar/text/noalloc controls, RC/live
counters and LLVM/symbol audits, including early exits and fresh unselected input
cleanup. Exercise malformed kind/type/signature/phi/CFG/transfer marker cases,
source-extern spoofing, normal and nested cached replay, valid/invalid ownership
edits, relocation, and retired-marker rejection. Include bounded increasing
nested-selection checks; no general whole-program lifetime inference is proposed.

Owners until implementation: A04 frontend/design; A07 source/Core safety; A08
cache qualification; coordinator shared schema/reservations and integration.
