# Narrowed optional field-write refusal

Read-only diagnosis against Support7 source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, compiler SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
No production source was changed and no fix has been qualified.

A03's reduced `owned-option.my` and `copied-option.my` both refuse
`child.value = 20` with `E_SINGLE_OWNER_BORROW`. Their record is
`Node(value: int, left: Node?, right: Node?)`. A scalar-only
`Row(value: int)` control admits the same narrowed optional write.
The original migration remains A03-owned and was not copied or changed.
`a03-source-checks.json` preserves A03's checks; the three typed dumps are
new A01 observations of those exact reduced sources. `identity.json`
records source hashes, commands and the shared admission wait.

## Source cause

The owned case's checked tree is, with irrelevant guards omitted:

```text
initialize %0 child = Some(Node(...))
initialize %3 <collection> = block {
    match %0 { Some bind %2: {}, None: assertion false }
    value %2
}
initialize %3 = [the same refresh]
assign %0 = Some(update(%3, field .0 = 20))
```

`sema_places.zig:520` creates the guarded payload receiver and refresh.
`sema_places.zig:435` wraps the updated payload in its original Some case.
`single_owner.zig:551` recognizes only a top-level update/replace or an
element store. Therefore this assignment calls `expression(.move)`.
The variant arm at line708 passes `.move` to the update; its base then
moves the borrowed synthetic `%3`. `%3` borrows the original optional
through the narrowing match, and is not a whole transferable owner.
`checkLocal` correctly rejects that move. The scalar-only record takes
the untracked path and therefore does not encounter this ownership check.

This is not evidence that `.copy()` failed to produce independent storage:
the fresh-owned case fails identically without any copy or input holder.

## Narrow patch request to A07

Recognize one complete same-owner optional reconstruction in `checkStore`,
without changing ordinary variant-construction move rules:

1. The store is assignment to a mutable optional root. Its variant type is
   exactly the destination type, its tag is that shape's Some tag, and its
   payload type is exactly the optional element type.
2. The payload is an update whose base is a compiler-generated borrowed
   receiver. The receiver's recorded definition is the exact guarded
   narrowing block: match of the destination local, expected Some arm and
   binding, None defensive trap, and final read of that binding. Require
   matching local identities and available/writable ownership state;
   merely sharing a root is insufficient.
3. For that proven wrapper, check destination mutation and check the inner
   update with update access. Keep generic `.variant` payload checking as
   move, including variants assembled from other or arbitrary borrows.
4. Preserve existing refresh and RHS evaluation order. Do not set the
   existing `Store.element` flag on a union: Core currently permits that
   flag only for record/array stores.

Backend qualification is required before shipping source admission.
The refreshed payload currently lowers through `union_payload` and,
for recursive storage, `box_get`; reconstructing Some emits `union_make`
and possibly `box_make`. The old union/box shell must relinquish carried
children exactly once. If existing ownership lowering cannot prove this,
add the corresponding narrowly proven transfer at the final refreshed
payload extraction, using the existing union/box take operations. Do not
turn arbitrary payload reads into owners or fix the symptom with a deep
copy. The earlier receiver read and RHS effects must remain in their
original order.

A02 confirmed its separate list-field `+=` change modifies only that
specific branch and leaves this scalar optional reconstruction unchanged.

## Required regressions

- Fresh owned optional and copied optional: scalar field write succeeds;
  copied input remains unchanged; the rebuilt optional remains usable.
- Recursive nested siblings and independent dynamic text/list fields
  survive scalar and managed-field replacement; ignored siblings, early
  return, repeated replacement and None paths clean up exactly once.
- RHS effects preserve existing refresh semantics. An RHS invalidating
  the narrowed optional must retain its specified refusal or defensive
  trap; it must never reuse an invalid payload.
- A different optional's payload, a different tag/owner, ordinary borrowed
  pattern payload reconstruction and escaping borrowed fields remain
  rejected. Explicit whole copies remain valid independent owners.
- Malformed typed-tree controls exercise mismatched tags, bindings, types
  and destination identity, independently of source spelling.
- Native release, debug, verified release, optimized debug and release
  without facts: results, zero RC events, zero exit-live managed bytes,
  and structural ABI/LLVM/symbol checks. Inspect recursive union/box
  transfer and run an ordinary pre-retirement compatibility control.

Owner: A07 for checker/Core implementation and proof, with A02 coordinating
any `sema_places.zig` producer edits. This diagnosis does not close the
release blocker.
