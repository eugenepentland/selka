# Initial abstract generic body checking

Track D now checks a pure subset of generic bodies before the existing executable
specialization rejection. Parameters remain symbolic identities; no example
concrete type stands in for an unknown type. Thus equal requirements on `T` and
`U` do not make them the same type, and `copy` does not permit arithmetic merely
because a future caller might supply an integer.

Supported signatures contain type parameters, builtin scalar/capability values,
and [concrete copyable value schemas](generic-concrete.md).
Supported bodies include local bindings and annotations, mutable assignment,
returns, discard of copyable values, blocks, branches, loops, arithmetic/comparison,
Boolean operations, and checked integer casts. Arithmetic and ordered comparison
require `integer`; equality requires `equality`. Boolean conditions require `bool`.
No implicit conversion equates a generic integer parameter with an `i64` literal;
`T(1)` states the conversion explicitly. Cast success is not guaranteed for
every value or width; ordinary runtime bounds remain necessary at specialization.

The checker enforces local scopes, type-variable identity, mutability, and
no-shadowing rules. Module-aware checking uses the declaring module's exports and
import aliases rather than flattening names across modules. Both branches are
checked, even when a condition is a literal. Both must return to establish an
unconditional branch return. Loops are conservatively treated as potentially falling through: a later return
is required even after `while true`.

Integer literal suffix/range checking is shared with the concrete checker,
including directly negated signed minima. Diagnostics preserve original source
spans and module paths. Temporary checking maps, normalized requirements, and
locals are released on failure; diagnostic strings belong to the diagnostic sink.

## Explicit limits and unsupported forms

Every body has a maximum checking depth of 256 and 100,000 expression/statement
visits. These bound compiler work, not guest execution. Left-deep expressions and
wide statement sequences exercise the limits without executing a template.

[Generic calls and pure concrete helpers](generic-calls.md) are now supported.
Concrete record/fixed-array construction and projection are now supported.
[Parameter-dependent fixed arrays](generic-arrays.md) now support recursive
shape checking and substitution. Parameterized records/unions and conversions
still need additional abstract rules and reject explicitly. They are not
silently skipped. Valid bodies in the supported subset now execute through
[concrete specialization](generic-execution.md).

[Borrowed input parameters](../legacy/experiments/generic-references.md) now permit explicit mutation
through exclusive references. External effectful operations remain unsupported. This does not implement abstract
call-effect inference, general move-only/result handling, reference provenance,
region escape checking, or complete generic body validation. Those remain required
before broad executable generic support. Existing concrete checks must still run
for generated instances; abstract acceptance alone is not authorization to bypass
them or emit an executable.

## Acceptance and next work

Fixtures verify symbolic integer/equality requirements, distinct equally constrained
parameters, casts, scope/return rules, immutable assignments, signed literal minima,
module-local visibility/shadowing, original diagnostic locations, allocation-failure
cleanup, deep expressions, and the 100,000/100,002 visit boundary.

Generic call/signature resolution and requirement forwarding now have acceptance.
The remaining work includes abstract ownership/reference/effect rules and
broader schema/tooling integration; pure specialization now has VM/C acceptance.
Generics and the full roadmap remain open.

Validation: all 554 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the focused abstract-body run passed eight tests. The Guardian build
gate passed all 88 checks without baselines. These runs cover the implemented
symbolic subset and ordinary-language regressions; they do not establish executable
generics or completion of the full template-body contract.


[Concrete result handling](generic-results.md) now adds transfer, acknowledgement,
propagation and control-flow obligations. [Partial field state](../legacy/experiments/generic-fields.md) now preserves remaining obligations;
[concrete owned flow](../legacy/experiments/generic-owned.md) now retains transfer and cleanup effects.
Runtime operations and region scopes remain pending.
