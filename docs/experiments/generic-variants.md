# Concrete variants in generic bodies

Generic bodies now construct concrete enums and copyable tagged unions and match
them exhaustively. `examples/generic-variants.selka` combines a record-payload union,
a scalar-payload union and a complete enum-indexed table; it returns 16.

Construction selects a case from the exact nominal type and checks payload
presence and type. A case with no payload accepts none; a payload case requires
exactly its declared value. Symbolic arguments are not implicitly converted to a
fixed payload type: use an explicit integer cast when needed.

Every match checks every arm, including arms after one that can fall through.
Case names retain their declaring type, duplicates reject, and every declared
case must be covered. Payload cases require a binding or explicit `(_)`;
empty cases take neither. Payload bindings exist only in their own arm, so the
same binding name may be reused in another arm. A match establishes return flow
only if every arm returns. These checks also apply to uncalled templates.

Generic bodies can also construct enum-indexed tables with named keys. Every
key must appear exactly once and each value must have the declared element type.
Table construction shares field validation with concrete record construction;
table replacement retains the previously implemented nominal key check.

## Acceptance and remaining work

Allocation sweeps execute and emit native code for generic enum/union construction,
scoped matching and table construction. Tests reject missing/duplicate cases,
wrong nominal case owners, payload arity/type errors, incomplete/duplicate table
keys, escaping payload bindings and missing return paths. A fallthrough case
verifies that a later invalid arm is still checked.

VM/native comparisons cover the source example, imported alias-qualified union
construction/matching and a located trap inside an imported generic match arm.
Both scalar and record payload representations are exercised.

[Concrete result-bearing variants](generic-results.md) now retain handling
obligations across matches and propagation. [Partial field state](../legacy/experiments/generic-fields.md) now supports extracting concrete
result-bearing record payloads. [Concrete owned flow](../legacy/experiments/generic-owned.md) now retains cleanup effects.
Runtime operations/regions, parameter-dependent structural types, codec
constraints, public generic tooling and the remaining roadmap still need work.
Concrete specialization continues to apply full semantic, ownership, region and
effect checking after abstract acceptance.
