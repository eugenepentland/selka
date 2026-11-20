# Immutable scalar constants (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Immutable scalar constants

Checking folds scalar initializers before anything is built, and each read of a
scalar constant is its literal value (`selka dump-ir` shows `42:i64` where
`MAX` was read).

Scalar constants are cached within one evaluation; no generated results persist
across compilation snapshots.

## String and byte literal constants

The compiler folds the join into one
literal when it checks the program, so the constant holds exactly the text it spells,
as if it had been written out.

its
getter returns the one literal (`selka dump-ir` shows `ret str0`)

`check`, `run`, `build --run` and installed programs use the same checked getter.
Function-body semantic caching remains disabled for programs with constants;
native object cache keys include emitted IL, so editing a literal changes its
getter object even when all callers remain unchanged. See SPEC.md `CONSTANT-2`.
