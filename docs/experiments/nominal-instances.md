# Concrete nominal instances on the VM

Concrete applications of record, union, result and enum templates now materialize
complete runtime schemas and execute through the existing typed IR and bytecode
VM. For example, `Box<i64>`, `Slot<Box<i64>>` and `Answer<Box<i64>>` retain their
own nominal identities. `examples/nominal-instances.my` returns `16`.

## Identity and storage

The catalog uses the [finite layout graph](nominal-layouts.md) after declaration
checking. Declaration identity and ordered argument identities determine an
instance. Different declarations, reordered arguments, different scalar/domain
arguments, and different enum-key applications remain distinct. Repeated
applications share a schema. Numeric arrays include their length and element;
enum-key arrays also retain their key identity.

Only concrete identities with demanded, complete storage become runtime schemas.
Symbolic roots validate unused templates without allocating executable records.
Phantom arguments retain semantic identity without fabricated empty runtime
records. Growing phantom families remain executable when actual storage is finite.
Enum array keys demand their own runtime metadata without becoming storage edges.

Names use qualified declarations and canonical argument names. Display names
share a 1 MiB compilation budget, diagnosed with `E_GENERIC_LIMIT` before
exponential argument-name expansion exhausts memory. The graph's existing
identity, traversal and nesting bounds also apply.

## Operations and boundaries

Concrete instances use the existing construction, field projection/update,
exhaustive matching, result propagation, ownership, partial moves, borrowing and
snapshot rules. Owned concrete fields make their containers move-only; pending
results preserve handling obligations. Nominal parameters still use the declared
`copy`, `equality` or `integer` requirements. An owned field in a template does
not imply that owned type arguments satisfy `copy`.

Existing generic functions can receive a concrete instance as `T`, including
fixed arrays of that instance. Concrete nominal types inside generic function
bodies are checked before specialization. Parameter-dependent applications such
as `Box<T>` in signatures or bodies now follow the [symbolic body contract](nominal-bodies.md).
The catalog retains its arena-owned semantic identities until function
specialization finishes, appending complete schemas without renumbering existing
types. Field indexes grow with amortized capacity; dynamically created numeric
arrays reuse their existing runtime identity.

Imported instances retain declaration identity across aliases. Public value-type
lookup requires an exported base and public type arguments, including phantom
arguments. Private argument types cannot be exposed simply because they occupy
no storage. Typed host registrations receive the complete concrete signatures
and retain the existing copied-input, typed-result and effect contracts.

Public schema export of a nominal type constructor remains pending. The schema
entry reports `E_SCHEMA_GENERIC_TYPE` at an exported template declaration; the
lower-level checked graph API returns `UnsupportedGenericTypeExport`. It does
not silently omit a public constructor or invent an arbitrary instance. Ordinary
schema exports keep their existing behavior.

## Evidence and remaining work

Tests execute nested records/unions, updated snapshots, results, partial owned
field moves, borrowed updates, arena escape checks, generic function/array composition, enum tables,
imported instances, domain factories, pool handles and typed host calls. Rejection
tests cover argument/declaration identity, arity, result obligations, requirement
violations, duplicate moves, conflicting borrows, private phantom arguments and
bounded name expansion. Allocation-failure sweeps cover catalog construction,
owned execution, imported programs and host result transport. CLI tests execute
instances with both memory backings and check structured identity diagnostics.

Validation: 829/829 Zig tests and all 21 Python interpreter/tooling drivers pass;
72 nominal-focused tests also pass in ReleaseFast. Formatting, the gated install
and all 88 Guardian checks pass with baselines disabled. The board trial retains
147 oracle comparisons, and the ordinary VM corpus retains 96 independent checks.
Actual agent repair attempts remain pending.

Symbolic nominal operations, provider-specific symbolic shapes and the board
trial's shared `Slot<T>` declarations are now implemented. Public generic tooling
remains pending.
The measured repair study, source serialization and incremental tooling remain
open. Guest-native compilation is excluded from the active goal.
