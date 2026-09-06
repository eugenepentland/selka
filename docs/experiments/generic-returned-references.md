# Generic reference-result provenance

Generic functions now return whole-value references and slices whose provenance
is declared with `from input`. The input must be a reference of the corresponding
kind and symbolic type. Results can be reborrowed in a call scope and forwarded
through other generics. `examples/generic-returned-references.my` returns and
forwards a mutable tail view, then restores caller access to its parent.

## Universal contracts and specialized types

Abstract checking resolves the declared input parameter, validates its permission
and kind, and matches its symbolic type to the result. Every return must name an
active reference whose root is that input. A reference to a local copy or another
parameter cannot satisfy the contract, even if the concrete types happen to match.
A shared input cannot supply an exclusive result, and an exclusive result cannot
be produced from a shared child. These checks apply to uncalled templates too.

Reference-returning calls require explicit borrow-call scopes. The call checks
ordinary argument requirements, substituted types and aliases before creating the
result loan. That loan uses the selected input's root identity, holds its parent
suspended where required, and is removed on scope exit. Forwarding through another
reference-returning helper preserves the root, not the helper's local spelling.
A result may borrow from a later parameter; parameter ordinal and type-argument
ordinal are independent.

Concrete return-contract validation now resolves both input and result types in
the callee instance. It does not use the caller's type-variable environment.
This matters when a caller's `U` is passed to a callee's `T`, or when a nongeneric
caller consumes `tail::<i8>`. Original source/module context remains intact.

## Acceptance and boundaries

Tests cover mutable narrowed slices, whole-value shared references, renamed type
variables, reordered type arguments, later input provenance, restored caller
access, immutable snapshots, invalid roots, local escape, shared/exclusive
mismatches, wrong reference kinds, implicit reference-to-value use, parent
suspension and allocation failures. Imported reference-returning templates execute
through ordinary module wrappers; their internal instances stay out of schema
roots. Native fixtures exercise the returned views through the existing C backend.

An abstract whole value does not imply array shape, so a result cannot turn `&T`
into `&[]Element` using only `copy`. Broader concrete nominal/composite operations,
move-only and external-effect generic contracts, direct public generic invocation,
and other roadmap requirements remain unfinished. This stage completes the
implemented subset's explicit reference-result contracts, not all generic design.

Validation: all 584 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes
forwarded references, later-input provenance and imported result helpers/schema
rendering. These results validate the supported reference contracts, not the
remaining generic operations or broader roadmap requirements.
