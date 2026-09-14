# D2: Use `record` for value records

Status: accepted for `bootstrap-v1`; not yet implemented.

## Rule

`record Name:` is the canonical declaration for a value with named fields.
Records have value semantics, no inheritance, no methods, and no implicit
`self`.

## Rejected alternative

Reject retaining `class` as the permanent spelling. That name suggests identity,
inheritance, and methods that this type deliberately does not provide. Also reject
adding class behavior merely to justify the old keyword.

## Compatibility consequence

The parser and formatter must learn `record`, the repository must migrate, and
`class` may be accepted for one compatibility window with a structured
replacement diagnostic. Formatter output switches immediately; after the window,
`class` is rejected. The rename remains subject to the planned agent-idiom check.
