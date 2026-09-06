# Borrowed input parameters in generic functions

Generic functions now accept shared `&T` and exclusive `&mut T` input parameters.
They can copy the referenced value with `read_ref`, replace it with `write_ref`
when the input is exclusive, and forward references to checked generic or ordinary
helpers. `examples/generic-references.my` executes the same setter for `i8` and
`i64`, then forwards a shared reference twice for a read-only calculation.

## Abstract guarantees and concrete enforcement

The symbolic environment distinguishes value bindings from references and retains
the access permission of each reference parameter. Referenced `T` remains the
same symbolic identity as value `T`; distinct type parameters do not become equal
because their requirements match. Reading requires copy support. Writing requires
an exclusive reference and a value of the same type. A reference cannot implicitly
become a value through return, binding, or a value argument.

At calls, abstract checking validates reference kind, required permission, and
substituted parameter type. Reference arguments must name active references.
A per-call name table detects duplicate reference arguments without pairwise
comparison. Repeating a shared reference is allowed. Repeating an exclusive input
is rejected even when both callee parameters are shared, matching the existing
concrete checker's conservative reborrow rule. Distinct exclusive input parameters
are separated by the caller's ordinary alias checking. Reference arguments count
toward the abstract body work budget.

These rules apply to uncalled templates, so invalid reference code does not become
acceptable merely because one concrete instantiation avoids it. Supported instances
then pass ordinary semantic borrow checks and use existing VM/C reference handling.
Borrowed mutation is observable to the caller; this extension is not a claim of
mathematical purity or of general abstract effect inference.

## Boundaries and acceptance

Generic slice parameters now have [separate acceptance](generic-slices.md).
[Lexical borrow scopes](generic-borrows.md) are supported too. [Reference results](generic-returned-references.md) now have acceptance.
Conversions and owned/resource operations remain unsupported. This
stage does not infer reference result provenance or lifetime contracts. Ordinary
callers can create lexical borrows and pass them into supported generic helpers.
General move-only requirements and broader effect contracts remain open.

Fixtures cover shared reads, exclusive writes, generic forwarding, multiple
concrete widths and booleans, repeated shared references, invalid permissions,
value/reference confusion, symbolic type mismatches, alias rejection in uncalled
templates, allocation failures, and imported generic setters through concrete
module wrappers. Native parity includes the new reference example and an imported
setter fixture. The broader roadmap remains unfinished.

Validation: all 576 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2646 comparisons across 87 single-file and 16
module fixtures using -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes local
reference forwarding and imported setter execution/schema generation. These
results do not establish the unfinished slice or returned-reference contracts.
