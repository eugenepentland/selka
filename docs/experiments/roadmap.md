# Post-MVP experiment sequence

The user authorized duplicate discovery and post-MVP experiments on 2026-09-05.
The scalar MVP remains the tested baseline. This is implementation tracking,
not a claim that the full future language has been delivered.

| Track | Current state | Next concrete acceptance experiment |
| --- | --- | --- |
| T, exact duplicate discovery | Implemented as separate `discover-duplicates` command; review and scaling corpus added | Collect ordinary-program findings before adding approximate matching; never merge automatically. |
| A1, aggregates and complete conversions | Implemented: records, construction, fields, preserving updates, complete conversions, integer widths/casts, fixed arrays, checked indexing | A1 acceptance passes; carry the immutable value semantics into A2. |
| A2, nominal domains and exhaustive mappings | In progress: domains/private construction, closed enums/tagged unions, and exhaustive matching implemented | Unit, privacy, and added-variant match experiments pass; implement complete enum-indexed tables. |
| B, borrowing | Pending guest memory representation | Reject shared/exclusive conflicts and expired references with allocation/bounds/lifetime identity. |
| C, ownership/capabilities/effects | Pending B and minimal recoverable errors | Acquire A, fail acquiring B, release A once; reject transitive forbidden effects including cleanup. |
| D, errors and abstraction | Minimal recoverable errors needed with C; broader work pending | Require handling/propagation/explicit acknowledgement without erasing evaluation or ownership obligations. |
| M, modules/interfaces | Pending a multi-file domain program | Resolve imports/exports and private boundaries; distinguish optional direction policy from type validity. |
| E, native execution | Pending one concrete backend choice | Run the same scalar semantic/trap fixtures through the VM and native route. |
| F, compile-time/schema/incremental work | Pending aggregates/variants/modules | Reject duplicate schema keys and undeclared inputs; explain invalidation and evaluation budgets. |
| T, formatter/reference reports/verification | Exact discovery establishes the first command only | Preserve semantics/comments with one formatter; report resolved references separately from runtime test coverage. |

## A1 completed decisions

Records now have nominal type identities, explicit field lists, field access,
and complete literals. The VM uses immutable aggregate storage. The first restriction is immutable record values
containing scalars or finite record/array values; exclude recursive by-value
types and resources. Updating creates a value of the same nominal type. This
must not imply any policy for later owned records or references.

The VM representation follows operand/local/frame ownership.
A request-wide allocation arena for every runtime record expression could grow
without bound inside loops; acceptance must include repeated construction and
update under bounded live storage. Host pointers alone are insufficient for the
later reference model.

Complete conversion needs a checked source-record identity and one explicit
accounting decision per source field, plus complete destination initialization.
A helper receiving an entire record must not automatically count all fields as
handled. Added fields must break old conversions until explicitly preserved,
transformed, or discarded by name. The check establishes accounting, not the
correctness of the conversion's arithmetic.

Record construction, update, declarative conversions, and fixed arrays are
implemented. Borrowing and effect syntax remain pending.

The [A1 experiment record](aggregates.md) describes the implemented storage
foundation, record frontend, integer widths, and completed array work.

[Integer widths and checked casts](integers.md) complete the width portion of A1.

[Fixed arrays and checked indexing](arrays.md) complete A1. A2 now includes
[nominal domains and private construction](domains.md). [Closed variants and exhaustive
matching](variants.md) are also implemented. Complete enum-indexed tables are
the remaining A2 item.
