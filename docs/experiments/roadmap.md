# Post-MVP experiment sequence

The user authorized duplicate discovery and post-MVP experiments on 2026-09-05.
The scalar MVP remains the tested baseline. This is implementation tracking,
not a claim that the full future language has been delivered.

| Track | Current state | Next concrete acceptance experiment |
| --- | --- | --- |
| T, exact duplicate discovery | Implemented as separate `discover-duplicates` command; review and scaling corpus added | Collect ordinary-program findings before adding approximate matching; never merge automatically. |
| A1, aggregates and complete conversions | Implemented: records, construction, fields, preserving updates, complete conversions, integer widths/casts, fixed arrays, checked indexing | A1 acceptance passes; carry the immutable value semantics into A2. |
| A2, nominal domains and exhaustive mappings | Implemented: domains/private construction, closed enums/tagged unions, exhaustive matching, and complete enum-indexed tables | A2 unit, privacy, added-variant match/table, and explicit unknown-code handling experiments pass. |
| B, borrowing | Implemented: memory/lease registry, scoped references, reference/slice parameters, bounded views, and explicit returned-reference provenance | B acceptance passes; carry borrowing and snapshot rules into resource ownership. |
| C, ownership/capabilities/effects | Typed results and owned-buffer/cleanup backend implemented; source resource ownership/capabilities/effects pending | Acquire A, fail acquiring B, release A once; reject transitive forbidden effects including cleanup. |
| D, errors and abstraction | In progress: typed results, checked handling/transfer, acknowledgement, and propagation implemented; generics/handles pending | Require handling/propagation/explicit acknowledgement without erasing evaluation or ownership obligations. |
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
implemented. Scoped borrowing, reference parameters, and bounded slices are implemented; effects remain pending.

The [A1 experiment record](aggregates.md) describes the implemented storage
foundation, record frontend, integer widths, and completed array work.

[Integer widths and checked casts](integers.md) complete the width portion of A1.

[Fixed arrays and checked indexing](arrays.md) complete A1. A2 now includes
[nominal domains and private construction](domains.md). [Closed variants and exhaustive
matching](variants.md) are also implemented. [Complete enum-indexed tables](tables.md) finish A2.
Borrowing and slices now enforce allocation identity, bounds, and lifetime
checks. Returned-reference contracts now complete [B acceptance](b-audit.md).


[B backend memory and lifetime rules](borrowing.md) now establish allocation,
lease, bounds, and store identity without guest host pointers. Scoped shared/exclusive
references now use this registry through checked source and VM instructions.
Reference parameters now support checked call reborrows. [Bounded slices](slices.md) now support
checked narrowing, element access, and slice parameters. Returned-reference
lifetime contracts are implemented; [the B audit](b-audit.md) records acceptance.


[Typed recoverable results and handling obligations](results.md) establish the
minimal error-value foundation for C/D. They preserve obligations through binding,
wrapping, and helper calls, with exhaustive handling or explicit acknowledgement.
[Propagation](propagation.md) now checks early-return obligations and borrow
cleanup. [Owned-buffer transfers and partial-acquisition cleanup](ownership.md) now have backend acceptance evidence. Source ownership and resource integration are next.
