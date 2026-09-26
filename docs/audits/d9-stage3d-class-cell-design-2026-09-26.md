# D9 stage 3d: class and Cell retirement decision

Stage 3a's value-semantics switch is opt-in, while stage 3c makes finite
recursive records and unions legal. Stage 3d will retire shared mutable
objects under that switch. This branch starts from the validated 3c branch
and integrates the validated 3a branch while both are still pending on
`main`; that is a scheduling change, not a change to D9's value model.

## Decision

Under `--value-semantics`, a `class` declaration is a compile error with a
replacement diagnostic. A finite tree or aggregate should become a `record`
or recursive `union`; an object whose identity matters, especially a cyclic
graph, should become a `pool.Pool[T]` entry named by a `pool.Handle[T]` or a
similar explicit id. The diagnostic names both routes because the checker
cannot infer whether the source observes identity. There is no silent
`class`→`record` rewrite: it would compile many programs while changing their
answers. The opt-out mode continues to accept `class` during the migration
window. This is a compile error under the switch, rather than a warning,
because the switch promises independent values and a surviving shared class
would silently violate that promise.

The builtin `Cell[T]` also becomes a compile error under the switch. It is a
managed, identity-bearing shared slot by D4, so simply making its contents
copyable would leave shared mutation. A local mutable value should use a value
`record` and a `mut` parameter, with a store-back where it was loaded from an
aggregate. A true shared slot should live in a pool and be named by a handle.
An ordinary user declaration named `Cell` remains a normal type. The opt-out
mode keeps the builtin for compatibility until the default flips in 3f; D4's
runtime support can be removed only after that window.

The replacement diagnostic must fire for a class declaration even when unused,
and for a builtin Cell in a signature or expression even when no constructor
is called. It must not reject a user-defined `Cell` or a type name merely
containing `Cell`. The checker and CLI tests will pin those boundaries. The
`class` and Cell migrations do not remove arenas: the existing `with arena()`
and `escape` rules remain the bulk-release path for value trees.

## Inventory and migration rule

The P1 census
(`experiments/value-semantics-20260924/p1/classes.jsonl` on
`exp/e2-value-semantics`) has 80 canonical declarations: 53 in `tests/lang`,
16 in the external Lox port, three in `experiments/sexpr-port`, three in
`bench/parity`, two in the standard library, two in trial T2, and one in the
schematic guest. Stage 3c already migrated `binary_trees_arena.my`'s class
tree to a recursive record, leaving 79. The census counts 24 graph-shaped
classes and 10 type-recursive ones; 20 have observed sharing. The external
Lox and trial sources will be kept as reviewable, reproducible patches plus
scripts to apply them to their pinned source trees, and the 13 Lox scripts
will be checked on the migrated port.

The stage 3d source scan found one omission in P1: generic
`network::Chunk[N]` was also a class. The tracked inventory includes this
extra declaration, so its working total is 81; all three standard-library
classes have become value records. `network::Failure` contains an owned
resource, whose ownership and completion rules still apply.

For each declaration, migration requires a behavior check:

- Pure data carriers: use a record and preserve the output. A `mut` helper
  receives changes to the caller's value; a value read from a collection is
  stored back after modification.
- Finite trees and ASTs: use recursive records or unions from stage 3c, keeping
  the same traversal and output. A box is immutable and path copying preserves
  earlier values.
- Graphs, cycles, and shared VM state: assign stable pool handles or explicit
  integer ids. Re-fetch and store a changed record through the handle so two
  references observe the same logical object without sharing mutable memory.
- Legacy aliasing tests: replace them with value or handle assertions. Keep
  only checker tests that explicitly verify the opt-out compatibility mode;
  do not let their old answers define the new mode.

Every rewritten program will be checked under the switch; the full default
gate must also stay green. Any corpus excluded from the 80-declaration census
because it is an immutable historical snapshot or duplicate will be listed
separately rather than silently counted as migrated.
