# Aggregate updates in generic bodies

Generic bodies now support `update(record) { field: value }` and
`replace(array_or_table, index, value)` when the aggregate type is concrete and
copyable. `examples/generic-updates.my` updates a record's nested array and an
enum-indexed table while reading their original values afterward; it returns 44.

Record construction and updates share field validation. Construction still needs
every field; an update may name any subset, including none. Unknown or duplicate
fields reject, and each replacement must have the exact declared field type.
Untouched fields remain present. Updating a nominal domain or a symbolic type
parameter is not a way to infer a record shape or access private backing storage.

Indexing and replacement share the same abstract index check. Fixed arrays accept
integer indices; tables require their exact enum key type. The replacement value
must match the declared element type. Equal enum ordinals from distinct nominal
enums do not make the key types interchangeable.

Specialization uses the ordinary update/replacement lowering, preserving snapshots,
evaluation order, and runtime bounds. These operations do not mutate their input
value. Empty-array and full-width unsigned out-of-range replacements still trap
at the original template location in both the VM and native execution.

## Acceptance and remaining work

Allocation-failure tests execute record and table updates, inspect original and
updated values, and emit native code. Uncalled-template tests reject duplicate,
unknown and wrongly typed fields, invalid indices/elements, mismatched enum keys,
and attempted updates of symbolic parameters. Shared VM/native acceptance executes
the example and imported replacement traps with zero and maximum-u64 indices.

Concrete enums/unions still need generic construction/matching rules. Generic
result/ownership operations, parameter-dependent structural types, codec
constraints, public generic tooling and other roadmap requirements remain open.
