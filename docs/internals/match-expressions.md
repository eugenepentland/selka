# Matching a variant: how it works

Implementation detail moved out of `docs/match-expressions.md`. The guide keeps the user-visible rule.

## Variant matches

Ordinary and generic functions share these rules. Lowering uses exhaustive
variant dispatch, owned payload cleanup included.

## Literal arms

The matched value is read once. A plain name or parameter is compared in place, and a call
result or a slice is bound to a hidden local that the comparisons only read, so neither is
copied. A `str` or `bytes` element or field is refused with `E_LITERAL_ARM`, because
binding it would copy it: bind it first with `const value = copy(...)`. The arms lower to
the same `if`/`elif` chain a hand-written match would, and a release build turns that
chain into a lookup table.
