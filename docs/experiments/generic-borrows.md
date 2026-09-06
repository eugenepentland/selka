# Lexical borrowing inside generic bodies

Generic bodies now create scoped borrows of copyable values and reborrow existing
references. Known slice inputs can be narrowed with integer start/end bounds.
`examples/generic-borrows.my` recursively fills and sums a slice, restoring access
to the parent after each exclusive child scope ends.

## Abstract ownership and access

Each reference retains its underlying root binding. Shared and exclusive loan
counts protect value owners, while direct child counts suspend exclusive parent
references. These counts avoid scanning the complete local environment for each
access. Calls compare root identities, so changing a reference name cannot hide
aliasing. Shared sibling references may coexist and be passed together; any
exclusive alias remains forbidden under the ordinary checker’s conservative rules.

An exclusive borrow of a value requires a mutable binding. A shared reference
cannot be reborrowed exclusively. Access to an exclusive parent is suspended until
its child leaves scope. Owner reads conflict with exclusive loans, and owner writes
conflict with either kind. The body checker validates these rules even in uncalled
templates and branches that a particular execution may never take.

Scope exit restores counts and removes the reference name, including during
checking failures and returns. Returning a copied value through a borrow is
supported; returning a reference still requires the separate, unfinished generic
provenance contract. Immutable copied values keep their ordinary snapshot semantics.

## Slice narrowing and boundaries

Range expressions require integer support. Narrowing a known slice preserves its
element identity and permission. Runtime bounds checks remain in the ordinary
VM/C backends, so an invalid subrange traps at the original template borrow span.
A whole abstract `T` does not imply array shape: range borrowing from such a value
still rejects rather than assuming one caller's concrete type establishes that
operation universally.

Tests cover recursive shared/exclusive narrowing, parent and owner restoration,
shared siblings, owner conflicts, suspended parent access, scope escape,
permission escalation, invalid range types, shadowing, bounds traps, allocation
failures and imported helpers. Generic returned-reference contracts, broader
abstract type/effect/ownership operations, and other roadmap tracks remain open.

Validation: all 582 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2676 comparisons across 92 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure tests cover recursive
borrows and imported narrowing helpers. These results do not establish generic
reference-result provenance or completion of the broader roadmap.
