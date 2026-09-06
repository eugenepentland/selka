# Post-MVP experiment sequence

The user authorized duplicate discovery and post-MVP experiments on 2026-09-05.
The scalar MVP remains the tested baseline. This is implementation tracking,
not a claim that the full future language has been delivered.

| Track | Current state | Next concrete acceptance experiment |
| --- | --- | --- |
| T, duplicate discovery | Exact grouping plus opt-in bounded approximate matching implemented for single-file and module programs; reports show canonical edits and truncation | Header-index and banded-comparison scaling acceptance pass; continue ordinary-program review and scaling within compatible buckets; never merge automatically. |
| A1, aggregates and complete conversions | Implemented: records, construction, fields, preserving updates, complete conversions, integer widths/casts, fixed arrays, checked indexing | A1 acceptance passes; carry the immutable value semantics into A2. |
| A2, nominal domains and exhaustive mappings | Implemented: domains/private construction, closed enums/tagged unions, exhaustive matching, and complete enum-indexed tables | A2 unit, privacy, added-variant match/table, and explicit unknown-code handling experiments pass. |
| B, borrowing | Implemented: memory/lease registry, scoped references, reference/slice parameters, bounded views, and explicit returned-reference provenance | B acceptance passes; carry borrowing and snapshot rules into resource ownership. |
| C, ownership/capabilities/effects | Owned buffers, queries/mutations, checked views, moves/wrappers, and partial-construction cleanup, and transitive allocation bounds, and explicit allocator capabilities implemented; clock/random capabilities and effects implemented; source filesystem/network resource acquisition/completion, owned error returns, and cleanup effects implemented; bounded environment lookup implemented; fixed-byte-array resource reads/writes implemented; resource permission attenuation implemented; borrowed slice I/O implemented; typed-handle pool and arena-reset backends plus execution-lifetime VM/CLI arena selection implemented; partial field moves implemented; source pools/handles, checked shared region backing, lexical source arenas, and conservative escape checking implemented; explicit source reset results implemented | Allocator and clock/random authority/effects pass acceptance; source resource lifecycle and cleanup effects pass; bounded environment lookup passes; resource reads/writes pass; permission attenuation passes; borrowed slice I/O passes; lexical arena acceptance passes under the documented conservative lifetime rules; explicit reset result acceptance passes. |
| D, errors and abstraction | In progress: typed results, checked handling/transfer, acknowledgement, and propagation implemented; typed-handle pool backend implemented; source handles implemented; generics pending | Require handling/propagation/explicit acknowledgement without erasing evaluation or ownership obligations. |
| M, modules/interfaces | In progress: bounded import discovery, explicit exports/privacy, source maps, module-aware type checking, and VM execution implemented; optional direction policy and default-limit graph/tooling acceptance implemented; ordinary-program corpus review pending | Shared-domain execution, direction policy, and integrated 256-module/4096-import acceptance pass; extend ordinary-program corpus review. |
| E, native execution | Scalar, domain, enum, record/array/table, conversion/update, and packed/boxed union/result C emission plus pinned-Zig native builder implemented for single-file and module projects; scalar semantic/trap/path/trace parity passes | Ordinary value acceptance and native allocation-failure cleanup implemented; native borrowing/resources and other operations requires explicit operations and corresponding executable parity fixtures. |
| F, compile-time/schema/incremental work | In progress: restricted effect-free project evaluation with step/frame/VM-memory budgets and source/implementation dependency receipts plus request identity before execution and persistent successful VM-result reuse with bounded field-level request comparisons implemented; typed scalar input manifest validation/module generation and fresh in-memory evaluation/cache bindings for multiple bounded manifests implemented; checked public type/function schema derivation and bounded ordinary typed JSON serialization/deserialization with owned failure locations and standalone Python data bindings with checked persistent artifact reuse and unchanged-output preservation implemented; checked full source receipts for schema/binding generation implemented; domain codecs, callable foreign wrappers, and finer incremental compilation pending | Reject duplicate schema keys and undeclared inputs; explain invalidation and evaluation budgets. |
| T, formatter/reference reports/verification | Canonical single-file/module formatter and reachable-project formatting checks, resolved function-call/binding reports including module main/export roots, configurable structural metrics, and separate manifest verification driver implemented | Extend reference/specification identities and entry roots with modules/schemas, and parity fixtures with native execution. |

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
implemented. Scoped borrowing, reference parameters, and bounded slices are implemented; transitive allocation bounds now pass, while allocator, external capabilities, and the resource operations described below now pass.

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
cleanup. [Owned-buffer transfers and partial-acquisition cleanup](ownership.md) now have backend acceptance evidence. [Source ownership and recoverable acquisition](owned-buffers.md) now integrate that cleanup into the VM; [buffer operations/views](buffer-operations.md) now pass acceptance. [Transitive allocation bounds](effects.md) now pass acceptance. [Explicit allocator capabilities](allocator-capabilities.md) now pass acceptance. [Clock/random capability operations](external-capabilities.md) now pass acceptance. [Source filesystem/network resource lifecycle and cleanup effects](source-resources.md) now pass; [bounded environment lookup](environment.md) now passes; [resource reads/writes](resource-io.md) now pass; [permission attenuation](attenuation.md) now passes; [borrowed slice I/O](resource-slices.md) now passes; [partial field moves](partial-fields.md) and [source pools/handles](source-pools.md) now pass; [source arena scopes](source-arenas.md) now pass.

[External resource backend acceptance](external-resources.md) now covers explicit
fallible completion, fallback release, scoped transfers, and reverse cleanup.
[Source and VM integration with cleanup-effect inference](source-resources.md) now
pass acceptance. [Non-consuming copyable field inspection](owned-field-reads.md) now supports
code-dependent retry; [partial field moves](partial-fields.md) now pass.

[Environment capability acceptance](environment.md) now covers bounded read-only
lookup, provider identity, missing/empty distinctions, and transitive effects.

[Typed-handle pools](typed-pools.md) now provide backend graph, stale-ID, snapshot,
slot-reuse, and bulk-clear acceptance. [Source pool/handle integration](source-pools.md) now passes; [source arena scopes](source-arenas.md) now pass.

[Arena backing and region reset](arenas.md) now have backend borrow, lifetime,
snapshot, and storage-reuse acceptance. [Source arena scopes and escape checks](source-arenas.md) now pass.

[Execution-lifetime arenas](arena-execution.md) now run source programs through
the VM and CLI; [nested source arena scopes and escape checking](source-arenas.md) now pass.

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

[Checked region backing](region-backing.md) now shares allocator authority and
lifetime guards between buffers and pools, with independent retained snapshots.
[Lexical source arena scopes and conservative escape checking](source-arenas.md) now pass.

[Explicit source arena reset](arena-reset.md) now reclaims unused chunks with typed
results, stable allocator authority, and live-owner/child guards.

[Module header discovery](module-discovery.md) now loads shared dependencies once,
reports cycles across files, and emits deterministic content fingerprints. Export,
privacy, and cross-file type resolution were added in the subsequent milestones below.

[Module interface indexing](module-interfaces.md) now parses module bodies and checks
explicit exports and signature visibility. Body resolution/type checking and
shared-domain execution are covered by the subsequent execution milestone below.

[Module source maps and AST relocation](module-source-mapping.md) now preserve
original locations through diagnostics/VM/native traces and prepare combined AST
tables with explicit module ownership for semantic integration.

[Cross-file type checking and VM execution](module-execution.md) now run the shared
domain example with private boundaries, nominal identities, borrowing, result
obligations, and transitive effects. Optional direction policy and module tooling
were added in the subsequent milestones below.

[Optional import-direction policy](import-policy.md) now evaluates ordered, explained
rules against resolved imports with a verdict separate from language validity.
Broader module corpus/scaling acceptance remains pending; duplicate, quality,
and formatting integrations are recorded below.

[Module duplicate discovery](module-duplicates.md) now reports exact and approximate
candidates across checked imports while preserving qualified nominal/callee
identities and original source paths.

[Module quality reports](module-quality.md) now distinguish main reachability from
exported interface roots and retain qualified calls and original file locations.
Module formatting is now available as described below. Schema/generated-root
integration remains pending.

[Module formatting](module-formatting.md) now preserves headers, qualified names, and
comment gaps, with syntax-only per-file output and reachable-project check mode.

[Scalar module native execution](module-native.md) now emits/builds module programs
with executed VM/native path/trace parity; broader native operations remain pending.

[Native nominal scalar domains](native-domains.md) now retain frontend privacy/type
checks and VM instruction-budget parity with scalar backing representation.

[Native closed enums](native-enums.md) now support construction, equality, calls,
mutation, and exhaustive dispatch with executed VM/native parity.

[Module graph boundary acceptance](module-scaling.md) now checks execution, reports,
formatting, source edits, diagnostics, cycles, and default module/import limits
through the actual CLI.

[Restricted project evaluation](restricted-evaluation.md) now establishes effect-free,
parameter-free execution with explicit VM budgets as the first F foundation.

[Evaluation dependency reports](evaluation-reports.md) now record source snapshots,
imports, budgets, compiler identity, and a deterministic request digest.

[Persistent evaluation caching](evaluation-cache.md) now reuses matching successful
results after fresh request checks and reports actual VM execution/skips.

[Typed input manifest generation](input-manifests.md) now validates named scalar
inputs and emits deterministic typed modules with manifest provenance hashes.

[Checked public schema derivation](schemas.md) now emits deterministic exported type
graphs and function contracts while preserving nominal identities and opaque boundaries.
Ordinary serialization and Python data bindings are now implemented as described below;
domain codecs, callable foreign wrappers, and generation receipt/cache integration remain pending.

[Typed JSON codecs](typed-json.md) now validate and materialize ordinary checked
values and serialize them canonically under byte/node/token/depth limits, rejecting
opaque dependencies and private root types. Source operations, domain codecs, callable
foreign wrappers, and richer input/generation integration remain pending.

[Generated Python data bindings](python-bindings.md) now provide standalone nominal
classes and compatible typed JSON codecs from fresh checked schemas, with generation
limits, explicit unsupported-type reporting, and compiler/Python acceptance.
Domain codecs and foreign function wrappers remain pending; binding artifact reuse
and loaded-source receipts are implemented below.

[Incremental binding artifact reuse](binding-cache.md) now skips generation on a
verified request hit after fresh compiler checks and preserves identical output
timestamps. Loaded-source generation receipts are now implemented below; frontend
incremental compilation remains pending.

[Checked schema source receipts](schema-receipts.md) now identify every loaded module
and the actual compiler image behind a checked schema. Binding cache hits retain
fresh source provenance independently of reusable public-schema/artifact identity.

[Typed JSON failure locations](codec-diagnostics.md) now identify nested values with
bounded, owned JSON pointers in compiler diagnostics and embedding APIs, preserving
allocation-error classification and explicitly marking truncated paths.

[Native packed variants and results](native-variants.md) extend construction, matching,
transfers, acknowledgement, and propagation. [Native aggregates](native-aggregates.md)
add records, arrays, tables, conversions/updates, boxed payloads and wider layouts,
plus allocation-failure cleanup and bounded-live-storage acceptance. Native
borrowing and resource operations remain pending.
