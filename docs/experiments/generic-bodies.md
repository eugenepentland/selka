# Initial abstract generic body checking

Track D now checks a pure subset of generic bodies before the existing executable
specialization rejection. Parameters remain symbolic identities; no example
concrete type stands in for an unknown type. Thus equal requirements on `T` and
`U` do not make them the same type, and `copy` does not permit arithmetic merely
because a future caller might supply an integer.

Supported signatures contain type parameters or builtin scalar/capability values.
Supported bodies include local bindings and annotations, mutable assignment,
returns, discard of copyable values, blocks, branches, loops, arithmetic/comparison,
Boolean operations, and checked integer casts. Arithmetic and ordered comparison
require `integer`; equality requires `equality`. Boolean conditions require `bool`.
No implicit conversion equates a generic integer parameter with an `i64` literal;
`cast<T>(1)` states the conversion explicitly. Cast success is not guaranteed for
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

Calls, concrete nominal/composite signature types, aggregate construction,
references/slices, owned/resource operations, conversions, and other forms that
need additional abstract rules return `E_GENERIC_BODY_UNSUPPORTED`. They are not
silently skipped. Valid bodies in the supported subset still return
`E_GENERIC_UNSUPPORTED` from overall semantic checking because instance interning,
substitution, and executable specialization are not implemented.

The supported subset has no effectful operations. This does not implement abstract
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

Next work is generic call/signature resolution and requirement forwarding, bounded
specialization identities, substitution with source/module provenance, remaining
abstract ownership/reference/effect rules, and VM/C/schema/tooling integration.
Generics and the full roadmap remain open.

Validation: all 554 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the focused abstract-body run passed eight tests. The Guardian build
gate passed all 88 checks without baselines. These runs cover the implemented
symbolic subset and ordinary-language regressions; they do not establish executable
generics or completion of the full template-body contract.
