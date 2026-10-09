# Generic slice parameters
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Generic functions now accept shared `&[]T` and exclusive `&mut []T` parameters.
They query length, read elements, write through exclusive views, and forward views
to checked helpers. `examples/generic-slices.my` fills a selected range and sums
it while retaining the original immutable array snapshot.

## Abstract and concrete rules

The symbolic binding records both reference permission and whether it represents
a slice. A slice cannot substitute for a whole-value reference, even if the
element and referenced value have the same type. Forwarding checks reference
kind as well as the substituted element type, permission and alias rules.

`len_slice` produces `u64`. An index must be a concrete integer or a symbolic type
parameter with the `integer` requirement. Slice reads require copy support for
the element. Writes require an exclusive view and a value with the identical
symbolic element type; equally constrained but distinct parameters do not match.
Invalid operations are rejected in uncalled templates, before specialization.

Concrete instances retain the existing slice ABI and runtime rules. View lengths
are runtime values, not specialization keys. Empty views remain valid; element
access traps if an index is negative, exceeds the view, or is a full-width unsigned
value outside its range. Mutation preserves owner snapshots, and traps keep the
source span of the operation inside the original template. Callers' lexical
borrow scopes continue to control view lifetime.

## Acceptance and remaining work

Tests cover integer and Boolean elements, forwarding, mutation, empty views,
snapshots, wrong reference kinds, permissions, type-variable/index requirements,
exclusive alias rejection, negative/full-width bounds traps, and allocation
failures. An imported generic slice helper executes through a concrete module
wrapper without becoming an internal schema root. Native fixtures exercise slice
mutation and bounds traps in both C optimization modes.

[Lexical borrowing and narrowing](generic-borrows.md) now have acceptance.
[Reference/slice results and provenance](generic-returned-references.md) are
supported too. General move-only requirements and broader abstract effect/ownership
rules remain unfinished. This extension handles slice inputs and operations;
it does not establish completion of the generic or wider language roadmap.

Validation: all 579 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2664 comparisons across 90 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes slice
forwarding and module-backed execution/schema generation. Generic lexical borrow
scopes and returned-reference contracts remain unverified and unfinished.
