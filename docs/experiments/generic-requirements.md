# Generic requirement resolution

Track D now resolves three builtin requirements during semantic preflight and
module interface checking. It checks every declaration, including uncalled and
private templates. Unknown names get a located `E_GENERIC_REQUIREMENT` diagnostic.
This is requirement resolution, **not template-body checking or specialization**;
otherwise-valid generic declarations still produce `E_GENERIC_UNSUPPORTED` before
execution.

| Requirement | Concrete promise |
| --- | --- |
| `copy` | The checked type carries neither move-only ownership nor pending result-handling obligations. |
| `equality` | The type supports ordinary language equality: integers, booleans, closed enums, and nominal pool handles. Also implies `copy`. |
| `integer` | The type is one of the eight signed/unsigned integer widths. Also implies `equality` and `copy`. |

Requirements normalize into a closed set. An explicit `copy + integer` declaration
is valid and has the same guarantees as `integer`; exact duplicate requirements
remain rejected. Implication compares the guaranteed operation sets and is ready
for validating type-parameter forwarding during later template checking. It does
not itself validate any generic call or body today.

Nominal domains retain their boundary: an integer-backed domain does not satisfy
`integer` and has no implicit equality unless the concrete language defines it.
Ordinary records may satisfy `copy`, but do not acquire implicit structural
equality. Results and records containing pending results fail `copy`, even when
their scalar payloads could otherwise be copied. Buffers, resource owners, pools,
and containing records also fail `copy`; pool handles remain copyable/equatable
values. Capability values follow their existing explicit value-passing rules;
`copy` does not grant new authority or erase effects.

The equality predicate is shared by concrete semantic checking and requirement
matching. Requirement matching consumes checked type identities/contracts rather
than guessing from names or backing representations. Reference modes, lifetimes,
result transfer, cleanup, and effects still need enforcement by template-body
checking and concrete specialization. User-defined requirements and requirements
for general move-only parameters are not implemented by these three builtins.

## Ownership and diagnostics

The resolver returns caller-owned parameter metadata, frees partially allocated
results on error, and retains source spans for diagnostics. It validates malformed
caller-supplied AST lists as well as parsed declarations. Builtin type names cannot
be type-variable names; source syntax rejects reserved names, and the resolver
also rejects them in supplied ASTs. Module diagnostics retain the declaring file
and requirement span. Syntax-only formatting continues to accept unresolved names;
interface and semantic checking establish requirement validity.

## Acceptance and next work

Tests cover the implication lattice, every integer width, booleans, allocator
values, nominal domains/enums/records/handles, ownership and result wrappers,
unknown requirements in uncalled templates, module-private declarations, malformed
AST input, and allocation failures. Ordinary expression equality remains covered
by the complete core suites.

Next: abstract template-body validation using these contracts, bounded instance
interning by declaration and nominal type identity, substitution with preserved
module/source context, and VM/native/tooling integration. Generics and the broader
roadmap remain open.

Validation: full core runs passed 546 tests in Debug and ReleaseFast; all 60 CLI
tests passed. The focused requirement run passed seven tests, including the added
module/private-template diagnostic case. The build passed all 88 Guardian checks
without baselines. These results validate requirement resolution/matching and
ordinary language regressions, not executable generics or template-body checking.
