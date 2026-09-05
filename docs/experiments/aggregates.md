# A1: aggregate values and complete conversions

Status: nominal record declarations, complete construction, field access,
preserving updates, and declarative complete conversions are implemented.
Fixed arrays, checked indexing, and additional integer widths remain pending A1
work. The later borrowing/resource/effect tracks remain pending.

## Implemented syntax and checking

```text
struct Point { x: i64, y: i64 }
struct View { horizontal: i64 }

conversion fn to_view(source: Point) -> View {
    discard source.y;
    return new View { horizontal: source.x };
}

fn move(point: Point) -> Point {
    return update(point) { x: point.x + 1 };
}
```

Records are nominal: equal field layouts do not make two declarations the same
type. Field lists and initializer lists use commas without trailing commas.
Empty records are allowed. Field types may refer forward to finite record types;
direct and indirect by-value cycles are rejected. Type/function names share the
top-level namespace and cannot be shadowed by locals or parameters.

`new Type { field: expression, ... }` requires exactly one initializer per
field, with matching types. `update(expression) { field: expression, ... }`
produces a value of the base's nominal type and preserves all omitted fields.
The base evaluates first, followed by replacement expressions in written order.
Construction also evaluates fields in written order before arranging values in
declaration order. Neither operation silently supplies defaults. Field access
uses `.name` and binds more tightly than unary/binary operators. Fields are
immutable; replace a mutable record binding using `update`. Record equality is
not defined; explicitly compare relevant fields.

A `conversion fn` has one record parameter and returns a record. Its initial
body form permits direct named source-field discards followed by one explicit
`return new Destination { ... };`. Arbitrary locals, branches, loops, whole-value
returns, and implicit delegation are not accepted in this declarative form.
Use ordinary helpers to compute transformations from explicitly selected fields.

Each source field must be directly accessed through the resolved source
parameter in a destination expression, or explicitly discarded by name. Nested
access `source.inner.x` accounts for the top-level field `inner`; it is not a
promise to convert every nested subfield. Passing only `source` to a helper
accounts for no fields. Unrelated ordinary functions can inspect a subset of a
record without making a complete-conversion promise.

Accounting is syntactic over checked expressions, including short-circuit
operands; it does not prove that a transformation computes the right value or
that every operand executes. The restricted body prevents an unused local read
from masquerading as accounting. Adding a source field breaks conversions until
it is deliberately used or discarded; adding a destination field breaks
incomplete constructions. Missing-field diagnostics point to the declaration.

## Chosen storage semantics

The first records will be immutable values containing scalars and finite record
values. Nominal type identities are separate from runtime value tags: primitive
IDs are reserved, and aggregate values carry their declared type ID. Frontend schemas retain record and field names/spans. Dumps show schemas,
source names in signatures, and numeric type/field identities in instructions.

A copied aggregate may share immutable backing storage. Each operand or
initialized local owns a reference. Loads retain, stores replace and release the
old local, calls transfer argument references into parameter slots, returns
release callee locals and transfer one result, and discard releases its operand.
A field read retains its result before releasing the containing value. This
produces value behavior without eagerly deep-copying unchanged nested values.

The runtime does not expose these host pointers to guest code. This is not a
reference/borrow model. References will require allocation identity, bounds,
and lifetime information before guest pointers or slices are accepted. Resources
and effects are also separate later work; host reference counting does not prove
those language contracts.

Zero-reference aggregate nodes are released with an intrusive work list, without
allocation or host recursion. Nested immutable sharing cannot introduce guest
cycles through construction. All runtime buffers release remaining values on
traps and host errors. Local slots currently retain a value until overwrite or
function exit; lexical cleanup obligations for resources must be introduced with
the resource model. Loop declarations reuse their assigned slots.

## Implemented evidence

`src/value_test.zig` exercises the new representation and internal VM instructions:

- A value survives local overwrite, argument passing, return, field projection,
  and discard, producing 42.
- Step-limit traps at every instruction boundary release all owned references.
- Allocation-failure sweeps cover aggregate construction and VM ownership paths.
- Repeated nested fields survive destruction of the outer record.
- A 20,000-level immutable chain is released without host recursion.
- Invalid internal field accesses and scalar operations release consumed values.
- 10,000 VM loop constructions/overwrites fit a 4 KiB live-allocation budget,
  including VM/validator storage, and leave zero outstanding bytes.

The storage tests use internal bytecode to isolate lifetime failures.
`src/records_test.zig` additionally runs source programs and checks nominal
mismatches, recursive schemas, incomplete/duplicate/unknown fields, evaluation
order, added fields, conversion accounting, and allocation failures throughout
the complete pipeline. Actual CLI fixtures exercise records/conversions and
verify that every command rejects incomplete conversions before execution.

## Remaining A1 acceptance

Fixed arrays, checked indexing, and additional integer widths from plan A1 are
still pending, including checked conversion and overflow/bounds fixtures.
Record-specific acceptance is covered, but A1 as a whole is not complete.
Examples are in `examples/records.my` and `examples/conversions.my`.
