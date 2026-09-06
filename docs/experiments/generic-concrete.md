# Concrete value schemas in generic bodies

A generic function can now combine symbolic parameters with fixed concrete types.
For example, `examples/generic-records.my` converts any declared integer input
into a concrete `Sample` record containing a fixed array, then passes that record
through another generic function. It returns 17 in the VM and native execution.

The abstract checker receives the same resolved type catalog used by concrete
specialization. It resolves imported aliases in the declaring module and retains
nominal identities: two records with identical fields are still different types.
Type parameters remain symbolic; an `integer` requirement does not make `T` equal
to `i64`. An explicit `cast<i64>(value)` is needed for an i64 field.

Supported concrete operations include record and fixed-array construction,
record field projection, array/table indexing and length, and passing/returning
concrete values through generic and pure concrete helper calls. Record fields
must appear exactly once; array literals require the declared length and element
types. Integer array indices and enum table keys retain their ordinary type rules.
Index bounds remain checked at runtime with the original template source frames.
Equality remains restricted to types supported by the language; record equality
is not implicitly derived.

Concrete domain values may pass through a template while retaining opacity.
These changes do not permit structural operations on an unconstrained type
parameter or allow direct domain backing construction. Concrete graphs containing
runtime identities or result obligations reject even in uncalled templates.
Complete graph validation is cached by concrete root type during one abstract
checking pass, avoiding repeated validation of the same fixed schema.

## Acceptance and remaining work

Core tests execute nested records and arrays through multiple generic functions,
check declared method opacity, and reject nominal mismatches, missing/duplicate
fields, invalid fields/indices/lengths, and owned/result-bearing signatures before
instantiation. Allocation sweeps cover checking, VM execution and native emission.
VM/native acceptance includes the source example, imported aliases through pure
helpers, and an imported generic bounds trap.

Generic record/type declarations, parameter-dependent composite shapes, structural
requirements, aggregate updates, variant construction/matching, and general
result/ownership operations still need abstract rules. Source codec constraints,
public generic invocation/schema representation and other roadmap items remain
open. Concrete specialization still performs full semantic, ownership, region and
effect checks after abstract acceptance.
