# Ownership diagnostic provenance and repair fixtures

Whole-value and partial-field transfer errors, conflicting borrows and suspended parent references
now report the invalid use, the earlier operation and the value declaration.
This applies to ordinary checking and to abstract generic bodies, including
uncalled templates. Existing error codes remain unchanged.

The structured `Diagnostic` keeps the immediate cause in `related` and an optional
binding-declaration note in `origin`. Both are stored by value; the bounded runtime
trace remains separate. Text rendering prints the causal note before the
creation/declaration note and maps each span through the original source map.
The CLI regression checks exact lines and columns in an imported generic module.
This is structured data in the compiler API; a versioned general JSON diagnostic
mode for CLI consumers is still pending.

## Move and borrow evidence

A whole-value move or result handling records the source use that consumed that
binding. Ownership snapshots preserve this witness across branch/loop checking,
and replacement clears it before a later transfer. When paths merge, a witness
identifies a preceding checked path; it is not a claim that execution selected
that path. Consumed buffer/pool/resource queries, field operations and whole-value
uses share the transfer diagnostic helper where they reject consumed owners.

Partial record moves retain one optional source span per schema field, shared by
ordinary and abstract checking. A missing-field access reports that field's earlier
extraction; an invalid whole-record use reports the earliest recorded missing-field
witness. The causal span identifies the field token in `take_field`. Immutable
snapshots preserve witnesses when branches restore, and complete replacement clears
them. Joins compare field availability independently of source positions, so two
branches may extract the same fields at different sites or in different orders.
This replaces boolean checker bookkeeping with optional spans; it increases host
memory per partially moved record snapshot, without changing the VM's move bitmap.

Conflicting loans identify the active borrow and original owner declaration.
Suspended exclusive references identify the child borrow that prevents access.
Ordinary checking chooses the earliest applicable declaration by source span;
generic checking walks lexical loan order and records explicit parent identity.
This avoids exposing hash-map iteration order as the choice of reported borrow.

## Repair acceptance

The fixtures assert diagnostic codes and exact primary, cause and declaration
spans, then independently check and execute repaired programs. They cover:

- Handling the surviving result owner after a transfer.
- Shortening a shared borrow scope before mutating its owner.
- Reading through the child reference while an exclusive parent is suspended.
- Querying the surviving buffer owner after a move.
- Clearing an old move witness when a binding is replaced after branch handling.
- Locating repeated field extraction and incomplete whole-record use, then handling
  the remaining fields in an executed repair.
- Restoring the continuing branch's field witness after another branch returns,
  and clearing earlier extraction witnesses when a record is replenished.
- Mapping all locations to an imported module and executing its repaired version.
- Preserving allocation failures while collecting and rendering provenance.

These are authored regression repairs, not measurements of an agent's repair
success rate. They do not prescribe blind text replacement or prove that every
suggested edit preserves application intent. The real board/constraint trial
still needs matched tasks, recorded attempts and independent behavioral tests.

## Remaining diagnostic work

Arena-origin explanations, richer returned-lifetime paths, and general
machine-readable CLI output remain pending. The initial
[optional-value audit](optional-values.md) retains named unions/results; application
usability and broader repair evidence remain pending. Typed host registration and
the application trial remain active roadmap work; native execution remains excluded.
