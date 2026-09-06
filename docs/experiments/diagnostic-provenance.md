# Ownership diagnostic provenance and repair fixtures

Whole-value and partial-field transfer errors, conflicting borrows and suspended
parent references report the invalid use, the earlier operation and the value
declaration. Arena escapes and invalid returned references now explain their
lifetime origins and contracts as described below.
This applies to ordinary checking and to abstract generic bodies, including
uncalled templates. Existing error codes remain unchanged.

The structured `Diagnostic` keeps the immediate cause in `related` and an optional
binding-declaration note in `provenance.origin`. Returned-reference mismatches
also keep the required input in `provenance.requirement`. Notes are stored by value;
the bounded runtime trace remains separate. Text rendering prints the causal note
before the creation/declaration note and maps each span through the original source map.
The CLI regression checks exact lines and columns in an imported generic module.
The [versioned CLI protocol](json-diagnostics.md) exposes this evidence through
`--diagnostics=json`, alongside structured compiler API data.

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

## Arena and returned-reference lifetimes

Arena dependencies now carry both depth and the arena allocator's declaration.
Ordinary checking and abstract generic graph propagation share the same dependency
ordering and E_ARENA_ESCAPE helper. Deeper dependencies take precedence; when depths
are equal, the earliest declaration wins. A changed witness propagates even when
the depth stays the same, so cycles and traversal order cannot leave a stale later
origin. These finite monotone updates preserve termination of the existing fixed
point analyses. The graph still queues each node at most once at a time.

The note identifies the arena supplying the limiting dependency. Origins survive
assignments, aggregate construction and extraction, conservative helper calls and
mutable reference writes through the existing data flow. This does not make the
analysis path-sensitive: an assignment inside `while false` can still contribute a
static dependency. The explanation reports that dependency, not a prediction of
which branch executes. Host checker storage increases from a depth to a depth and
optional span per tracked node/local; no VM execution or memory policy changes.

When a returned reference comes from a different root than the signature allows,
E_RETURN_LIFETIME identifies the returned loan, the actual owner's declaration and
the required input parameter. Reborrows retain their root identity. Text rendering
prints the causal loan, owner, and contract notes in that order. Both ordinary and
abstract generic checks use this contract, and imported-module CLI tests assert
all original lines and columns before executing corrected projects.

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
- Allocating an escaping buffer from the caller's heap instead of a local arena.
- Returning the declared input reference instead of borrowing a local value.
- Retaining arena origins through loop fixed points and mutable helper writes;
  selecting the deepest nested arena and propagating equal-depth witnesses through
  cycles under allocation failure.

These are authored regression repairs, not measurements of an agent's repair
success rate. They do not prescribe blind text replacement or prove that every
suggested edit preserves application intent. The real board/constraint trial
still needs matched tasks, recorded attempts and independent behavioral tests.

## Remaining diagnostic work

[Versioned machine-readable CLI output](json-diagnostics.md) is implemented.
Current lifetime notes show the origin and contract; they do not enumerate every intermediate
assignment or helper in a dependency path. The initial
[optional-value audit](optional-values.md) retains named unions/results; application
usability and broader repair evidence remain pending. Typed host registration and
the application trial remain active roadmap work; native execution remains excluded.
