# Typed implementation obligations

Write `todo[T]()` where an implementation is missing. The checker validates the
explicit type and emits `E_TYPED_HOLE` with a related span naming that type.
Ordinary and uncalled generic function bodies report independent holes in the
same check. Formatting retains the construct. Unresolved holes never produce a
checked program or bytecode, and cannot execute through VM/native commands.

The type is declared by the author, not inferred from context. Use existing
navigation context queries alongside the diagnostic to find types and functions.
This first experiment does not yet rank candidate implementations or establish
that holes reduce agent turns. That needs matched maintenance trials. The feature
is an implementation obligation, not a runtime panic hidden behind a valid check.
