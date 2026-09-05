# Post-MVP experiment sequence

The user authorized duplicate discovery and post-MVP experiments on 2026-09-05.
The scalar MVP remains the tested baseline. This is implementation tracking,
not a claim that the full future language has been delivered.

| Track | Current state | Next concrete acceptance experiment |
| --- | --- | --- |
| T, duplicate discovery | Exact grouping plus opt-in bounded approximate matching implemented; reports show canonical edits and truncation | Continue ordinary-program review and candidate-index scaling; never merge automatically. |
| A1, aggregates and complete conversions | Implemented: records, construction, fields, preserving updates, complete conversions, integer widths/casts, fixed arrays, checked indexing | A1 acceptance passes; carry the immutable value semantics into A2. |
| A2, nominal domains and exhaustive mappings | Implemented: domains/private construction, closed enums/tagged unions, exhaustive matching, and complete enum-indexed tables | A2 unit, privacy, added-variant match/table, and explicit unknown-code handling experiments pass. |
| B, borrowing | Implemented: memory/lease registry, scoped references, reference/slice parameters, bounded views, and explicit returned-reference provenance | B acceptance passes; carry borrowing and snapshot rules into resource ownership. |
| C, ownership/capabilities/effects | Owned buffers, queries/mutations, checked views, moves/wrappers, and partial-construction cleanup, and transitive allocation bounds, and explicit allocator capabilities implemented; clock/random capabilities and effects implemented; source filesystem/network resource acquisition/completion, owned error returns, and cleanup effects implemented; bounded environment lookup implemented; fixed-byte-array resource reads/writes implemented; resource permission attenuation implemented; borrowed slice I/O implemented; typed-handle pool and arena-reset backends plus execution-lifetime VM/CLI arena selection implemented; partial field moves implemented; source pools/handles implemented; source arena scopes pending | Allocator and clock/random authority/effects pass acceptance; source resource lifecycle and cleanup effects pass; bounded environment lookup passes; resource reads/writes pass; permission attenuation passes; borrowed slice I/O passes; continue source arena integration. |
| D, errors and abstraction | In progress: typed results, checked handling/transfer, acknowledgement, and propagation implemented; typed-handle pool backend implemented; source handles implemented; generics pending | Require handling/propagation/explicit acknowledgement without erasing evaluation or ownership obligations. |
| M, modules/interfaces | Pending a multi-file domain program | Resolve imports/exports and private boundaries; distinguish optional direction policy from type validity. |
| E, native execution | Scalar C emission and pinned-Zig native builder implemented; scalar semantic/trap parity passes | Scalar acceptance complete; broader native support requires explicit operations and corresponding executable parity fixtures. |
| F, compile-time/schema/incremental work | Pending aggregates/variants/modules | Reject duplicate schema keys and undeclared inputs; explain invalidation and evaluation budgets. |
| T, formatter/reference reports/verification | Canonical formatter, resolved function-call/binding reports, configurable structural metrics, and separate manifest verification driver implemented | Extend reference/specification identities and entry roots with modules/schemas, and parity fixtures with native execution. |

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
implemented. Scoped borrowing, reference parameters, and bounded slices are implemented; transitive allocation bounds now pass, while allocator and clock/random capabilities now pass; further external operations remain pending.

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
cleanup. [Owned-buffer transfers and partial-acquisition cleanup](ownership.md) now have backend acceptance evidence. [Source ownership and recoverable acquisition](owned-buffers.md) now integrate that cleanup into the VM; [buffer operations/views](buffer-operations.md) now pass acceptance. [Transitive allocation bounds](effects.md) now pass acceptance. [Explicit allocator capabilities](allocator-capabilities.md) now pass acceptance. [Clock/random capability operations](external-capabilities.md) now pass acceptance. [Source filesystem/network resource lifecycle and cleanup effects](source-resources.md) now pass; [bounded environment lookup](environment.md) now passes; [resource reads/writes](resource-io.md) now pass; [permission attenuation](attenuation.md) now passes; [borrowed slice I/O](resource-slices.md) now passes; [partial field moves](partial-fields.md) and [source pools/handles](source-pools.md) now pass; nested arena scopes remain next.

[External resource backend acceptance](external-resources.md) now covers explicit
fallible completion, fallback release, scoped transfers, and reverse cleanup.
[Source and VM integration with cleanup-effect inference](source-resources.md) now
pass acceptance. [Non-consuming copyable field inspection](owned-field-reads.md) now supports
code-dependent retry; [partial field moves](partial-fields.md) now pass.

[Environment capability acceptance](environment.md) now covers bounded read-only
lookup, provider identity, missing/empty distinctions, and transitive effects.

[Typed-handle pools](typed-pools.md) now provide backend graph, stale-ID, snapshot,
slot-reuse, and bulk-clear acceptance. [Source pool/handle integration](source-pools.md) now passes; nested arena scopes remain pending.

[Arena backing and region reset](arenas.md) now have backend borrow, lifetime,
snapshot, and storage-reuse acceptance. Source arena scopes and escape checks
remain pending.

[Execution-lifetime arenas](arena-execution.md) now run source programs through
the VM and CLI; nested source arena scopes and escape checking remain pending.

[Approximate discovery](approximate-discovery.md) now reports bounded near matches
separately from exact groups, with changed facts and explicit incomplete-search status.

[Static quality reports](quality-reports.md) now separate resolved call reachability
and binding counts from unmeasured runtime coverage, with configurable structural
review thresholds.

[Canonical formatting](formatter.md) now preserves tokens/comments and supports
stdout output plus a syntax-only check mode. The [verification driver](verification-driver.md) is implemented.

[Project verification](verification-driver.md) now runs explicit steps with truthful
filtered/dependency reporting, executed parity, rejection sentinels, specification
markers, and timing observations separate from performance gates.

[Scalar native execution](native-execution.md) now uses direct C branches and
explicit frames, with executed VM/native parity and explicit unsupported-feature
diagnostics.

[Partial field moves](partial-fields.md) now preserve remaining record fields,
resource cleanup, and per-field result obligations across checked control flow.

[Source pools and nominal handles](source-pools.md) now integrate graph operations,
allocator authority, execution quotas, snapshots, and ownership cleanup.
