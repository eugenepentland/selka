# D2: Use `record` for value records

Status: accepted for `bootstrap-v1`; canonical `record` head implemented and repository example/stdlib sources migrated. `class` remains accepted during the compatibility window.

## Rule

`record Name:` is the canonical declaration for a value with named fields.
Records have value semantics, no inheritance, no methods, and no implicit
`self`.

## Rejected alternative

Reject retaining `class` as the permanent spelling. That name suggests identity,
inheritance, and methods that this type deliberately does not provide. Also reject
adding class behavior merely to justify the old keyword.

## Compatibility consequence

The parser now accepts `record Name:` as a contextual declaration head while
leaving `record` usable as an ordinary identifier outside declaration position.
The repository examples and standard library have migrated to `record`; the
remaining inline fixtures use the compatibility spelling. `class` remains
accepted for one compatibility window. A structured replacement diagnostic and
the final `class` removal still depend on the planned agent-idiom check and the
one-version delay.
