# D4: Add narrow managed `Cell[T]`

Status: accepted for `bootstrap-v1`; implementation pending.

## Rule

`Cell(value=initial)` creates an identity-bearing managed cell. Copying a cell
shares its single slot. `cell.value` reads it and `cell.value = replacement`
replaces it. The element must be managed and storable.

## Rejected alternative

Reject capturing closures and stored references as the mechanism for scanner or
parser state. A cell has no address-taking, pointer arithmetic, implicit
dereference, identity comparison, FFI layout, or wire encoding.

## Compatibility consequence

Existing records retain field-copy value semantics; `Cell` is deliberately the
exception. Shared mutation becomes visible at construction, parameter passing,
and `.value` assignment sites. Until `Cell` lands, compiler prototypes must use
explicit state threading rather than an undocumented substitute.
