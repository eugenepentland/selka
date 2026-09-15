# Public generic API inspection

`mylang schema-project main.my --schema-report` now checks all bodies and reports
exported generic functions and nominal constructors in a separate
`schema.generic_templates` array. Ordinary concrete exports, functions, and their
reachable type graphs remain in the existing schema fields. The inventory is versioned `generic-templates-v2`. Its `contract` is marked
`callable: false` and `requires_explicit_instantiation: true`: discovering a generic
API does not make it a concrete typed-call endpoint. Export a concrete wrapper to
use `invoke-project` with a particular instantiation.

Each template groups declaration identity/location, a symbolic `contract`, and
nominal `shape` separately. It includes its qualified declaration identity, declaration kind,
ordered type parameters and explicit requirements, symbolic value parameters and
result, reference/slice passing modes, returned-reference provenance, and explicitly
declared effect bounds. Generic structs list symbolic fields; generic unions and
results list cases and payloads. A missing effect-bound field means no explicit
bound, while an empty array means an explicit pure bound.

Structural `field(...)` and `op(...)` constraints are separate typed descriptions
on each `contract.type_parameters` entry. Function values/provenance/effects appear
in `contract.signature`; nominal members appear in `shape.fields` or `shape.cases`. Operation constraints retain their parameter/result spellings
and explicit effects. The `codec` requirement appears alongside builtin `copy`,
`equality`, and `integer`; it promises checked codec eligibility, not access to a
private representation. Requirements are conjunctive. Existing implication rules
still apply (`integer` implies `equality`, which implies `copy`); `codec` does not
implicitly promise `copy`.

Named constraints are published two ways: an exported constraint has its own
non-callable `constraint` template carrying its subject and expanded promises, and
an exported generic parameter lists each named bound under `named_requirements`
with the bound spelling, its declaring module, and the expanded
builtin/field/operation promises it contributes. Expanded signatures substitute
the declaration's subject for the consuming parameter.

Symbolic type spellings resolve in the declaration module. The module and direct
import-alias identities are included, so consumers need not interpret an imported
alias in the caller's scope. Qualified IDs stay stable across whitespace changes.
Source locations are exact half-open name byte ranges plus one-based line/column,
path, and full containing-module SHA-256. The outer schema report pins all loaded
sources and the compiler identity; its schema digest includes template metadata.

Private templates are omitted. Public signatures and structural requirements must
respect public type visibility. Invalid uncalled generic bodies prevent checked
schema publication. `list-interfaces` remains the explicitly pre-body-check textual
index; use the checked schema report for an API contract.

Validation includes uncalled-body rejection, private constraint rejection,
structural/codec metadata, concrete-call separation, stable IDs with changing
source receipts, and allocation-failure cleanup.
