# D4: Add narrow managed `Cell[T]`

Status: accepted for `bootstrap-v1`; implemented in Wave 2 item 5.

## Rule

`Cell(value=initial)` creates an identity-bearing managed cell. Copying a cell
shares its single slot. `cell.value` reads it and `cell.value = replacement`
replaces it. The element must be copyable, storable and free of result
obligations, resources and capabilities; scalars such as `int` are permitted.
The cell itself is managed, so it is traced by the collector rather than an
owner.

## Rejected alternative

Reject capturing closures and stored references as the mechanism for scanner or
parser state. A cell has no address-taking, pointer arithmetic, implicit
dereference, identity comparison, FFI layout, or wire encoding.

## Compatibility consequence

Existing records retain field-copy value semantics; `Cell` is deliberately the
exception. Shared mutation becomes visible at construction, parameter passing,
and `.value` assignment sites. `Cell` has no equality, JSON/codec, FFI or wire
spelling, and a user declaration named `Cell` still shadows the builtin.
