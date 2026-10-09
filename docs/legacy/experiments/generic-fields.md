# Partial fields in generic bodies
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Generic bodies now support `read_field(owner, field)` on concrete records and
`take_field(owner, field)` on concrete result-bearing records. The owner must be
an active value binding. Field names resolve against its concrete nominal schema;
no field shape is inferred for a symbolic parameter.

Taking a field transfers it immediately. The owner retains a bitmap of moved
fields, and subsequent access to a moved field rejects. A partial record cannot
be read, passed, projected, returned or acknowledged as a whole. Remaining
ordinary fields can be read and remaining result fields can be taken and handled.
Reading a result field with `read_field` rejects because it would copy an
obligation. Plain copyable records use `read_field`; `take_field` requires a
result-bearing owner in the currently supported generic data graphs.

Scope exit, return, overwrite and early propagation inspect only remaining
result-bearing fields. After those fields have been handled, leftover ordinary
metadata does not create a handling obligation. Replacing a mutable partial
binding restores a complete value after checking its remaining obligations.
Individual field reinitialization is not introduced.

Each take creates an immutable field bitmap in a checker-owned arena. Branch,
match, loop and short-circuit snapshots contain both whole-value availability and
the field bitmap. Comparisons use bitmap contents, so equivalent moves in a
different order agree. The arena is freed after checking the function, including
on allocation failure, and no bitmap escapes into compiled IR.

## Acceptance

`src/generic_fields_test.zig` checks uncalled templates for repeated moves,
copying result fields, incomplete whole-value use, consumed owners, unhandled
remaining fields, wrong owner shapes, reference owners and undeclared fields.
Branch/match mismatches and loop/short-circuit changes reject. Propagation rejects
both remaining local fields and previously evaluated result temporaries.

Valid cases cover differently ordered moves, nested records, returning versus
continuing match arms, result-replenishing loops, remaining metadata reads, and
success/error propagation. Allocation sweeps include semantic checking, execution
and native emission. `examples/generic-fields.my` returns 17; native parity
fixtures also cover imported schemas/helpers and a located trap after extraction.

[Concrete owned graphs](generic-owned.md) now use the same field transfer state
and retain cleanup effects. Individual runtime operations, views and region scopes
still need abstract authority and lifetime checks. Generic type constructors,
symbolic structural constraints, codecs and public tooling remain pending.
