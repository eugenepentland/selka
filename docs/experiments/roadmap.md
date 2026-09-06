# Post-MVP experiment sequence

The user authorized duplicate discovery and post-MVP experiments on 2026-09-05.
The scalar MVP remains the tested baseline. This is implementation tracking,
not a claim that the full future language has been delivered.

| Track | Current state | Next concrete acceptance experiment |
| --- | --- | --- |
| T, duplicate discovery | Exact grouping plus opt-in bounded approximate matching implemented for single-file and module programs; reports show canonical edits and truncation | Header-index and banded-comparison scaling acceptance pass; initial invoice/packet application review passes; continue scaling within compatible buckets; never merge automatically. |
| A1, aggregates and complete conversions | Implemented: records, construction, fields, preserving updates, complete conversions, integer widths/casts, fixed arrays, checked indexing | A1 acceptance passes; carry the immutable value semantics into A2. |
| A2, nominal domains and exhaustive mappings | Implemented: domains/private construction, closed enums/tagged unions, exhaustive matching, and complete enum-indexed tables | A2 unit, privacy, added-variant match/table, and explicit unknown-code handling experiments pass. |
| B, borrowing | Implemented: memory/lease registry, scoped references, reference/slice parameters, bounded views, and explicit returned-reference provenance | B acceptance passes; carry borrowing and snapshot rules into resource ownership. |
| C, ownership/capabilities/effects | Owned buffers, queries/mutations, checked views, moves/wrappers, and partial-construction cleanup, and transitive allocation bounds, and explicit allocator capabilities implemented; clock/random capabilities and effects implemented; source filesystem/network resource acquisition/completion, owned error returns, and cleanup effects implemented; bounded environment lookup implemented; fixed-byte-array resource reads/writes implemented; resource permission attenuation implemented; borrowed slice I/O implemented; typed-handle pool and arena-reset backends plus execution-lifetime VM/CLI arena selection implemented; partial field moves implemented; source pools/handles, checked shared region backing, lexical source arenas, and conservative escape checking implemented; explicit source reset results implemented | Allocator and clock/random authority/effects pass acceptance; source resource lifecycle and cleanup effects pass; bounded environment lookup passes; resource reads/writes pass; permission attenuation passes; borrowed slice I/O passes; lexical arena acceptance passes under the documented conservative lifetime rules; explicit reset result acceptance passes. |
| D, errors and abstraction | In progress: typed results, checked handling/transfer, acknowledgement, and propagation implemented; typed-handle pool backend implemented; source handles implemented; generic syntax, builtin requirement resolution, and initial pure symbolic body/call checking and executable specialization implemented; broader generic contracts and tooling pending | Require handling/propagation/explicit acknowledgement without erasing evaluation or ownership obligations. |
| M, modules/interfaces | Implemented experimental scope: bounded imports, exports/privacy, source maps, module checking/VM execution, direction policy, default-limit graph/tooling acceptance, and initial ordinary-application corpus review | Shared-domain execution, direction policy, 256-module/4096-import boundaries, and invoice/packet application acceptance pass; production-user corpus evidence remains unmeasured. |
| E, native execution | Scalar, domain, enum, record/array/table, conversion/update, packed/boxed union/result, and ordinary-value borrowing/slice and root-allocator owned-buffer/lexical-arena/pool C emission, explicit clock/random/environment provider adapters, and pinned-Zig native builder implemented for single-file and module projects; scalar semantic/trap/path/trace parity passes | Ordinary value acceptance and native allocation-failure cleanup implemented; All current bytecode operations have native emission; explicit resource ABI v4 and lifecycle/I/O/generation/quota acceptance pass. Native embedding/bindings and broader compilation performance remain open. |
| F, compile-time/schema/incremental work | In progress: restricted effect-free project evaluation with step/frame/VM-memory budgets and source/implementation dependency receipts plus request identity before execution and persistent successful VM-result reuse with bounded field-level request comparisons implemented; typed scalar input manifest validation/module generation and fresh in-memory evaluation/cache bindings for multiple bounded manifests implemented; checked public type/function schema derivation and bounded ordinary typed JSON serialization/deserialization with owned failure locations and standalone Python data bindings with checked persistent artifact reuse and unchanged-output preservation implemented; checked full source receipts for schema/binding generation and exported effect-free typed invocation with owned argument copies implemented; explicit domain codec declarations and schema contracts implemented; executed domain JSON with shared operation budgets implemented; schema-pinned public JSON invocation implemented; generated Python callable wrappers and domain wire objects plus fresh manifest inputs for schema generation and calls implemented; automatic content polling through a persistent check session implemented; native ABI bindings and finer incremental compilation pending | Reject duplicate schema keys and undeclared inputs; explain invalidation and evaluation budgets. |
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
Module scaling and an initial ordinary-application corpus review are now implemented; duplicate, quality,
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
declared domain codecs, executed JSON, and generation receipt/cache integration are
implemented below; Python callable wrappers are described at the end of this record.

[Typed JSON codecs](typed-json.md) now validate and materialize ordinary checked
values and serialize them canonically under byte/node/token/depth limits, rejecting
opaque dependencies and private root types. Executed domain codecs are implemented
below; source operations, native ABI bindings, and richer input/generation
integration remain pending.

[Generated Python data bindings](python-bindings.md) now provide standalone nominal
classes and compatible typed JSON codecs from fresh checked schemas, with generation
limits, explicit unsupported-type reporting, and compiler/Python acceptance.
Python domain-codec integration and callable wrappers are implemented below; binding artifact reuse
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
plus allocation-failure cleanup and bounded-live-storage acceptance. [Native ordinary-value references](native-references.md) now support scoped loans,
parameters, returned views, and checked slices. [Native owned buffers](native-buffers.md)
add root allocator entry parameters, ownership transfer, growth, mutation, and buffer
slices with VM/native and allocation-failure acceptance. Native pools and external resource operations remain pending.

[Initial ordinary-application corpus review](../../examples/corpus/README.md) adds
an invoice calculator and borrowed packet decoder: 13 modules, independent-oracle
execution, exact/near duplicate decisions, quality/policy review, change-impact
rejection, schema/binding round trips, and declared-input evaluation. This is an
authored bounded corpus, not production deployment or independent-user evidence.

[Typed invocation](typed-invocation.md) supplies the checked factory execution
foundation for explicit domain codecs and callable wrappers. Codec declarations, schema contracts, and executed JSON with shared operation
budgets and Python callable generation are implemented below;
representation-only domain decoding stays disabled.

[Explicit domain codec contracts](domain-codecs.md) now bind ordinary wire types to
public effect-free decoder/encoder methods, require a typed decoder result for the
exact domain, and emit checked schema metadata without exposing backing values.
Executed JSON and shared budgets are implemented below. Source operations and native ABI bindings remain pending.

[Executed domain JSON codecs](domain-json.md) now traverse declared domain wire
representations, execute checked factories/accessors, retain located typed errors
and source traps, and share memory/step/call/work budgets across each operation.
The CLI round trip and generated Python calls use this path; source serialization
operations and richer input integration remain pending.

[Schema-pinned public JSON calls](checked-calls.md) now execute exported functions
from named wire arguments, verify the complete checked public schema before any
argument codec executes, and share budgets across decoding, target execution, and
encoding. This supplies the executable request boundary for the generated Python
wrappers and domain wire representations described below.

[Generated Python calls](python-calls.md) complete the initial callable-wrapper and
Python domain-wire work mentioned above. They invoke the schema-pinned compiler
protocol with explicit limits, preserve typed result errors, and validate domains
through declared language decoders. Native ABI bindings, source operations, and
richer input integration remain pending.

[Declared inputs for schemas and calls](call-inputs.md) now extend manifest-backed
in-memory modules to schema/codec/invocation CLI paths, binding generation, and
generated Python clients. Fresh values and source receipts coexist with compatible
artifact reuse; schema changes invalidate old calls. Source serialization and
finer frontend incremental work remain pending.

[Bounded incremental module syntax](incremental-syntax.md) now reuses exact parse
tables across fresh embedding projects, with owned copies, retention limits,
invalidation/eviction observations, and fresh semantic checks. Persistent and
semantic query caching, automatic watching, and the rest of F remain pending.

[Persistent checking sessions](check-session.md) now expose syntax reuse through
a serial check/clear/quit CLI protocol, with fresh source/manifests, status and
cache observations, error recovery, and bounded request framing. Semantic query
reuse and persistent storage remain pending.

[Native lexical arenas](native-arenas.md) are implemented with chunk backing,
reset, allocator identity, and frame cleanup; Debug/ReleaseFast parity and sanitizer
acceptance pass.
Native external resources remain pending.

[Native pools](native-pools.md) now implement handles, operations, quotas, and
root/arena cleanup; full Debug/ReleaseFast acceptance and sanitizer cleanup checks pass.

[Native clock/random providers](native-providers.md) now use explicit C adapters
with typed results and missing-grant checks; full Debug/ReleaseFast acceptance passes.

[Native environment lookup](native-environment.md) now preserves bounded bytes,
missing/empty values, padding, snapshots, and explicit grants through provider ABI v2.
Complete Debug/ReleaseFast acceptance passes.

[Native resource implementation](native-resources.md) now has a normal-cleanup
ordering correction, counted emergency ownership unwind, and an executable
destruction-order harness. Full Debug/ReleaseFast unwind acceptance passes; native
filesystem/network operations remain pending. Propagation now boxes outgoing
errors before clearing operands; full Debug/ReleaseFast regression acceptance passes.

Native resource lifecycle providers now implement acquisition, completion, reduced
permissions, and failure cleanup through ABI v3. Focused VM trace comparisons and
allocation-failure checks and full Debug/ReleaseFast regression acceptance pass. Native
resource byte I/O and broader stress acceptance remain pending.

Native array/slice resource I/O is implemented through ABI v4, completing emission
for the currently defined bytecode operations. Focused VM trace, allocation-failure,
quota/reuse, and mixed-store checks and full Debug/ReleaseFast acceptance pass.
Generation-exhaustion stress, native embedding, and wider roadmap work remain open.


### Native resource registry stress — 2026-09-06

Completed generation-exhaustion, stale-owner, registry-growth, and simultaneous
per-kind quota stress in the native runtime acceptance harness. Six O0/O2
sanitizer runs pass with zero retained allocations; mutation checks reject
unchecked generation wrap and stale-token release. Mirrored source quota fixtures
pass four exact VM/native trace comparisons, including acquisition from the other
provider family while one is full and reuse after cleanup. Mixed-store acceptance
passes two outcomes and 30 allocation failures. Guardian passes all 88 checks with
baselines disabled. This follow-up used focused acceptance; the prior full-suite
baseline remains 31 steps and 595 core/CLI tests. Native embedding/performance,
generics, source serialization, and finer incremental compilation remain open.


### Automatic project checking — 2026-09-06

Implemented `scripts/watch.py`: one persistent compiler session checks initially
and after content changes to module sources or declared manifests. Bounded polling
handles atomic replacement, deletion/recreation, nested imports, same-size edits
with preserved timestamps, and changes during an active check. Source/input
errors remain recoverable. Reply limits, timeout, SIGINT/SIGTERM, and child reaping
are explicit. The standard test build includes end-to-end watch acceptance.
See [watch behavior and acceptance](watch.md) for conservative
whole-source-tree invalidation and polling limits. Semantic query reuse,
persistent query storage, native incremental compilation/embedding, generics,
source serialization, and other unfinished roadmap requirements remain open.

Validation: the full ReleaseFast build passed all 32 steps (unchanged core/CLI test
steps reused cached results). Final focused watch acceptance passed with Debug
and ReleaseFast compiler builds. Guardian passed all 88 checks with baselines
disabled. Native resource acceptance passed 116 outcomes, 106 VM trace comparisons,
392 allocation failures, and six registry sanitizer cases.


### Native build publication and measurement — 2026-09-06

The native builder now stages guest C, trusted adapter compilation, and linking,
then atomically publishes complete executables. Identical executable bytes preserve
inode/timestamp; failures preserve the last successful output. `--report` records
generated-C identity, frontend/native elapsed time, and publication status while
explicitly stating that the driver does not reuse compilation. Fresh trusted
adapter cache storage prevents stale assembly `.incbin` inputs observed in the
regression fixture. Adapter compilation retains the caller's working directory.
Native compilation/query reuse, incremental linking, embedding/bindings, generics,
source serialization, and the remaining roadmap requirements stay open.

Validation: focused native-builder acceptance passes, including a failing-before
partial-output simulation and the changed `.incbin` regression. Scalar/module
parity passes all 2,616 comparisons; clock/random and environment acceptance pass
32/38 comparisons and 14/56 allocation failures. Final fixed-I/O resource selection
passes two VM/native traces, 28 allocation failures, and six registry sanitizer
runs. The build gate passes all 88 Guardian checks without baselines. This was
focused validation; no new full-suite result is claimed for this milestone.


### Declared-requirement generics: frontend stage — 2026-09-06

Added explicit type parameters with nonempty requirement lists and `::<...>` call
arguments to the AST/parser. Owned copies, mapped source spans, syntax-cache reuse,
formatter round trips, exported-signature privacy, and 16/17 list boundaries are
covered. Semantic preflight rejects these forms with `E_GENERIC_UNSUPPORTED`;
requirements are not yet resolved and templates cannot execute. Generics remains
open: requirement checking, bounded specialization, module/ownership/effect
integration, VM/native execution, and tooling acceptance are the next work.

Validation: the full core suite passed 540 tests in Debug and ReleaseFast, all 60
CLI tests passed, and the final generic-focused run passed seven tests including
the additional qualified-module formatting fixture. All Zig tests compiled and
the build gate passed all 88 Guardian checks without baselines. No executable
generic or native-specialization acceptance is claimed.


### Generic builtin requirement resolution — 2026-09-06

Added normalized `copy`, `equality`, and `integer` requirements, implication checks,
and concrete type matching using existing ownership/result contracts. Equality
uses the same predicate as ordinary expressions. Unknown requirements are rejected
in all templates, including uncalled private module declarations; malformed AST
inputs and allocation-failure cleanup are covered. Template-body checking and
executable specialization remain unsupported. General move-only/user-defined
requirements, bounded instance interning, substitution, backend/tooling integration,
and the rest of the roadmap remain open.

Validation: full core runs passed 546 tests in Debug and ReleaseFast; all 60 CLI
tests passed. The focused requirement run passed seven tests, including the added
module/private-template diagnostic case. The build passed all 88 Guardian checks
without baselines. These results validate requirement resolution/matching and
ordinary language regressions, not executable generics or template-body checking.


### Initial abstract generic body checking — 2026-09-06

Added symbolic checking of the pure builtin/type-parameter subset: locals,
assignment, returns, branches/loops, casts, arithmetic, and equality. Type-variable
identities remain distinct and operations require declared guarantees; no concrete
representative type is substituted. Literal validation is shared with the concrete
checker. Module scope, original diagnostics, allocation cleanup, and explicit
256-depth/100000-visit limits have acceptance coverage. Calls, nominal/composite
signatures, references, ownership/effects, and executable specialization remain
explicitly unsupported. Generics and the broader roadmap remain open.

Validation: all 554 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the focused abstract-body run passed eight tests. The Guardian build
gate passed all 88 checks without baselines. These runs cover the implemented
symbolic subset and ordinary-language regressions; they do not establish executable
generics or completion of the full template-body contract.


### Abstract generic calls and requirement forwarding — 2026-09-06

Added indexed generic declaration lookup, explicit type/value argument arity,
requirement implication, and symbolic parameter/result substitution. Calls retain
module/domain privacy and cross-file diagnostic links; same-named declarations
remain distinct. Recursive calls check signatures without expanding bodies.
Allocation-failure acceptance covers local and module-backed checking. Concrete
helper summaries, broader abstract body forms, instance interning/substitution,
executable specialization, and the remaining roadmap stay open.

Validation: the full core suites passed 559 tests in Debug and ReleaseFast, all 60
CLI tests passed, and final generic-focused acceptance passed 25 tests. The build
gate passed all 88 Guardian checks without baselines. This validates abstract
calls and ordinary-language regressions; executable generic specialization and
completion of the broader roadmap remain unproven and unfinished.


### Pure concrete helpers in generic call graphs — 2026-09-06

Abstract generic checking now follows ordinary helper calls and validates all
transitively reachable bodies using the supported pure builtin rules. A worklist
bounded by declaration count visits each body once, including recursive cycles;
uncalled ordinary functions are left to concrete checking. Original module/domain
privacy and source locations survive traversal. Hidden clock operations reject
even behind constant-false branches. General effect/reference contracts, nominal
substitution, executable specialization, and other roadmap requirements remain open.

Validation: all 563 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the build passed all 88 Guardian checks with baselines disabled.
Coverage includes helper cycles, shared callees, module/domain privacy, hidden
clock effects, invalid signatures/bodies, and allocation-failure cleanup. No
executable specialization or full native-suite result is claimed for this change.


### Bounded concrete specialization identities — 2026-09-06

Added an independently tested compilation-local instance registry keyed by
resolved declaration ordinal and ordered concrete type identities. Owned argument
copies, stable discovery IDs, existing-key reuse at capacity, nominal identity,
4096-entry/16-argument bounds, and allocation-failure recovery are covered.
The registry is not yet wired into executable lowering: call discovery,
per-instance type substitution, semantic/function-index migration, VM/native and
tooling integration remain unfinished. See [the instance-table experiment](generic-instances.md)
under docs/experiments. Generics and the broader roadmap remain open.

Validation: all 568 core tests passed in Debug; focused instance-table acceptance
passed six tests in Debug and ReleaseFast, including allocation-failure sweeps
and recovery. The build passed all 88 Guardian checks with baselines disabled.
This is registry and ordinary regression evidence; no new executable generic,
CLI, or full native-suite result is claimed.


### Executable pure generic specialization — 2026-09-06

Concrete semantic checking now separates source declarations from executable
instances, resolves callee signatures through concrete type arguments, and clears
touched expression cache entries between bodies. Recursive/repeated calls reuse
bounded specialization IDs; ordinary functions do not consume the 4096 generic
instance budget. The supported pure templates execute through VM/C lowering,
including integer widths, nominal copy values, and imported calls. Ordinary
public wrappers remain schema roots while internal instances are excluded.
General reference/effect/ownership contracts, direct generic schema/invocation,
user-defined requirements, and other roadmap tracks remain unfinished.
See `docs/experiments/generic-execution.md` for the current scope and boundaries.

Validation: full core runs passed 573 tests in Debug and ReleaseFast; all 60 CLI
tests passed. Final generic-focused acceptance passed 40 tests, including the
additional returned-reference identity regression. Native parity passed 2640
comparisons across 86 single-file and 16 module fixtures with -O0/-O2 and undefined
behavior sanitization; 50 final targeted codec comparisons passed after inserting
an uninstantiated template before codec functions. Guardian passed all 88 checks
with baselines disabled. No new full resource/provider-suite result is claimed.


### Generic borrowed input parameters — 2026-09-06

Abstract checking now distinguishes value, shared-reference and exclusive-reference
bindings. Supported templates read, write and forward reference inputs while
preserving symbolic types, access permissions, and ordinary alias rules. Duplicate
exclusive inputs reject even when forwarded to shared callee parameters; repeated
shared inputs remain valid. Calls use a temporary name table and count reference
arguments toward the work budget. Concrete instances retain ordinary borrow
validation and VM/C execution. Generic slices, lexical borrow scopes, returned
reference provenance, broader ownership/effects, and other roadmap work remain open.
See `docs/experiments/generic-references.md` for scope and acceptance.

Validation: all 576 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2646 comparisons across 87 single-file and 16
module fixtures using -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes local
reference forwarding and imported setter execution/schema generation. These
results do not establish the unfinished slice or returned-reference contracts.


### Generic slice input operations — 2026-09-06

Generic shared/exclusive slice inputs now support length, element reads/writes,
and forwarding. Abstract checks retain reference kind, symbolic element identity,
integer-index requirements, access permission, and alias rules. Concrete VM/C
instances retain runtime view lengths, bounds traps and immutable snapshots.
Imported slice helpers execute through ordinary public wrappers. Lexical generic
borrow scopes/narrowing, reference-result provenance, wider effect/ownership
contracts, and other roadmap tracks remain unfinished. See
`docs/experiments/generic-slices.md` for current scope and acceptance.

Validation: all 579 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2664 comparisons across 90 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes slice
forwarding and module-backed execution/schema generation. Generic lexical borrow
scopes and returned-reference contracts remain unverified and unfinished.


### Generic lexical borrowing and narrowing — 2026-09-06

Generic bodies now borrow copyable local values, reborrow references, and narrow
known slice inputs. Root identities, loan counts and parent child counts enforce
owner access and exclusive-parent suspension without scanning every local. Scope
exit restores access and removes names on returns and failures. Recursive generic
slice helpers execute through VM/C with runtime subrange bounds checks. Generic
reference-result provenance, abstract whole-value range shape, broader ownership
and effects, and other roadmap requirements remain unfinished. See
`docs/experiments/generic-borrows.md` for current scope and acceptance.

Validation: all 582 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2676 comparisons across 92 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure tests cover recursive
borrows and imported narrowing helpers. These results do not establish generic
reference-result provenance or completion of the broader roadmap.


### Generic reference-result provenance — 2026-09-06

Generic whole-reference and slice results now validate explicit input provenance,
kind, permission and symbolic type before specialization. Borrow-call scopes and
forwarding preserve roots and parent suspension, including results borrowed from
later parameters. Concrete return contracts resolve types in the callee instance.
Imported result helpers execute through ordinary wrappers with internal instances
excluded from public schema roots. Abstract whole-value-to-slice shape, broader
nominal/composite operations, move-only/external-effect contracts, direct generic
public invocation, and other roadmap requirements remain unfinished. See
`docs/experiments/generic-returned-references.md` for scope and acceptance.

Validation: all 584 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes
forwarded references, later-input provenance and imported result helpers/schema
rendering. These results validate the supported reference contracts, not the
remaining generic operations or broader roadmap requirements.
