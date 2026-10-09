# A2: complete enum-indexed tables

Status: implemented. This completes A2 alongside nominal domains/private
construction, closed enums/tagged unions, and exhaustive matching. Borrowing,
resources, modules, native execution, generated schemas, and the other roadmap
tracks remain pending.

## Syntax and type identity

```mylang
enum Status:
    ok
    missing
    failed


func response_codes() -> [Status]u16:
    mut codes: [Status]u16 = {Status.failed: 500u16, Status.ok: 200u16, Status.missing: 404u16}
    return codes


func main() -> i64:
    mut original = response_codes()
    mut revised = replace(original, Status.failed, 503u16)
    return i64(revised[Status.failed])
```

`[Enum]Value` is a complete table indexed by one closed enum. It is available
wherever a type annotation is accepted. The key must be an enum, not an integer,
domain, record, array, or tagged union (even a union with only empty cases).
A table's structural type includes both the nominal enum identity and the value
type. Tables with different enum keys remain distinct despite equal case counts
or names. `[Status]u16` is also distinct from a numeric `[3]u16` array.

Table values may contain scalars, domains, records, arrays, variants, and other
tables, subject to the finite by-value layout rule. Enums may be declared after
the table type's first use. Nested numeric arrays and enum-indexed tables compose.
Whitespace does not affect type identity.

## Complete named construction and lookup

`new [Enum]Value { case: expression, ... }` requires exactly one correctly typed
initializer for every enum case. Unknown keys, duplicates, missing cases, and
wrong value types are errors. Positional construction with `[value, ...]` is
rejected for enum tables. There are no implicit defaults, wildcard entries, or
trailing commas. Bare case names in the initializer list are resolved against
the declared key enum.

Adding an enum case breaks all old table constructors until the new key is
initialized. `E_INCOMPLETE_TABLE` names the missing key and points to its enum
case declaration. Existing exhaustive match checks independently expose missing
arms. Reordering an enum declaration or a table initializer list does not change
which value belongs to a named key. Initializer expressions still evaluate once
in written order before values are arranged in enum layout order, so reordering
expressions can change which effect/trap occurs first.

`table[key]` requires a value of exactly the key enum type; numeric or foreign-enum
indices are rejected. The base evaluates first, then the key. An existing valid
key always identifies an initialized entry; the VM also checks type and bounds.
`replace(table, key, value)` returns a new table of the same type and preserves
every other entry. Its arguments evaluate left to right. Copies of the old table
remain unchanged. Named record `update` and `.field` access are not table APIs.

`len(table)` returns the enum's case count as `u64`, while retaining evaluation
of the operand. It does not provide numeric access to enum cases or make integer
casts to an enum valid. General enum iteration and schema-derived generators
are separate future features.

## Unknown external codes and conversion boundaries

Enums remain closed; no implicit numeric cast can create an unknown case. An
ordinary decoder can map known protocol numbers to enum values and preserve
other numbers in an explicit `unknown` union variant. The acceptance fixture
uses `Decoded { known: Message, unknown: u8 }`, then exhaustively handles both
cases. This makes the chosen unknown-value policy visible without confusing
internal enum order with an external wire code.

This is an explicit guest decoder example, not generated serialization or I/O.
Shared schemas, serializers, external spellings, and binding generation remain
in F. Table-valued record fields participate in existing complete conversion
accounting: direct access/discard accounts for the field, while construction
separately verifies all table keys.

## Storage, validation, and analysis

Table schemas are interned by key enum identity and value type. Metadata records
one named entry per enum case; numeric array type metadata remains independent
of array length. The compiler collects enum names/cases before interning tables
and resolves union payloads afterward, supporting forward type references.
Cycle checking follows table value types as it does ordinary array elements.

Tables share immutable aggregate storage and the established retain/release
paths. Replacement copies the immediate element buffer and shares immutable
nested values, costing O(number of cases) work/storage. Host memory allocation
is still an implementation detail rather than a completed guest effect model.

Emission validation checks table key kind, enum cardinality, ordered schema names,
value types, and constructor permutation. Runtime lookup/replacement validates
key identity before reading its variant tag. Wrong numeric/foreign-enum keys in
mutated internal bytecode fail cleanly and release operands. Source callers
cannot construct out-of-range enum tags. There is no untrusted bytecode loader.

Exact discovery `exact-v7` retains enum key identity, value type, named mappings,
written initializer order, lookup keys, and replacement expressions. Renamed
bindings still match; a numeric array of the same length does not match a table.
Ordinary named construction and existing lowering are shared with records.

## Evidence and A2 acceptance

- `src/tables_test.zig`: named mapping stability across enum reorder, added-case
  failures and declaration locations, key/type/shape errors, nested types, forward
  enums, record conversions, explicit unknown-protocol handling, evaluation order,
  allocation-failure cleanup, bounded storage, duplicate identity, and VM rejection
  of numeric/foreign-enum keys in mutated internal bytecode.
- A source loop performs 10,000 replacements under a 4 KiB live runtime budget.
  A nested-value fixture releases every runtime allocation on success and at every
  executed instruction-budget trap boundary.
- Actual CLI fixtures run `examples/tables.my` (1407), inspect table dumps, reject
  incomplete mappings across all four commands, and report incorrect key types.
- The full suite passes 123/123 tests in Debug and ReleaseFast (104 core,
  19 actual CLI), with formatting and whitespace checks passing on Guardian's
  exact `0.17.0-dev.1683+5ceec001b` snapshot.

A2's domain acceptance is covered by `domains_test.zig`: Seconds cannot stand in
for Millimeters, explicit checked conversions pass or trap on overflow, and
private factories cannot be bypassed. `variants_test.zig` covers closed variants,
typed payloads, exhaustive matching, and added-case failures. These table fixtures
complete the named mapping requirement. Later roadmap tracks are not complete.
