# Post-MVP experiment sequence

Native execution is outside the active roadmap-completion goal. Preserve the
ability to add a backend later, but do not implement or extend native execution
as part of completing this roadmap. The current goal is to develop the language
on its bytecode VM; a future decision can reopen native work.

The user authorized duplicate discovery and post-MVP experiments on 2026-09-05.
The scalar MVP remains the tested baseline. This is implementation tracking,
not a claim that the full future language has been delivered.

## Current direction — 2026-09-06

Interpreter-first development supersedes the older sequencing below. The custom
Zig VM is the primary runtime while language semantics and usability develop.
See [the current design and acceptance criteria](interpreter-first.md).

| Priority | Work | Completion evidence |
| --- | --- | --- |
| 1 | Interpreter workflow, concrete generic local views and arena/reset lifetimes implemented | `test`/`test-interpreter` retain Guardian, core/CLI and interpreter/tooling coverage; `test-native` is optional and `test-all` combines both. Views and arenas have VM/CLI rejection and cleanup acceptance. Next active priority: diagnostic provenance and repair fixtures. |
| 2 | In progress: whole-value transfer and borrow provenance with executed repair fixtures implemented | Next: partial-field/arena/lifetime provenance and versioned CLI diagnostic output; audit optional-value ergonomics. Agent repair success remains unmeasured. |
| 3 | Typed registered host functions with handwritten wrappers | Exact signatures/effects, ownership and lifetime checks, typed errors, deterministic fake-host tests. |
| 4 | Board-validation or constraint-processing module | Independent behavioral tests and recorded agent repair outcomes; geometry/routing kernels stay in native libraries. |
| 5 | Trial-driven language/tooling refinement | Evidence for generic constraints, source serialization, incremental checking, and useful duplication reports. |
| Deferred | Further native compilation, native ABI expansion, LLVM/direct x86_64 Linux, Wasm/JIT | Revisit only for demonstrated application needs; no current deadline or completion gate. |

The host-function milestone is guest-to-host library calling through the VM.
Previously implemented native embedding and generated native bindings compile
and call guest programs; they do not complete this new host-registration milestone.
`zig build test` now runs interpreter acceptance; `test-interpreter` is an alias.
`test-native` selects native compilation integration and `test-all` combines both.
The ordinary corpus retains independent VM expectations in the default suite;
its C compilation requires `--native --zig`. Shared core/CLI roots are unchanged.

## Track inventory

| Track | Current state | Next concrete acceptance experiment |
| --- | --- | --- |
| T, duplicate discovery | Exact grouping plus opt-in bounded approximate matching implemented for single-file and module programs; reports show canonical edits and truncation | Header-index and banded-comparison scaling acceptance pass; initial invoice/packet application review passes; continue scaling within compatible buckets; never merge automatically. |
| A1, aggregates and complete conversions | Implemented: records, construction, fields, preserving updates, complete conversions, integer widths/casts, fixed arrays, checked indexing | A1 acceptance passes; carry the immutable value semantics into A2. |
| A2, nominal domains and exhaustive mappings | Implemented: domains/private construction, closed enums/tagged unions, exhaustive matching, and complete enum-indexed tables | A2 unit, privacy, added-variant match/table, and explicit unknown-code handling experiments pass. |
| B, borrowing | Implemented: memory/lease registry, scoped references, reference/slice parameters, bounded views, and explicit returned-reference provenance | B acceptance passes; carry borrowing and snapshot rules into resource ownership. |
| C, ownership/capabilities/effects | Owned buffers, queries/mutations, checked views, moves/wrappers, and partial-construction cleanup, and transitive allocation bounds, and explicit allocator capabilities implemented; clock/random capabilities and effects implemented; source filesystem/network resource acquisition/completion, owned error returns, and cleanup effects implemented; bounded environment lookup implemented; fixed-byte-array resource reads/writes implemented; resource permission attenuation implemented; borrowed slice I/O implemented; typed-handle pool and arena-reset backends plus execution-lifetime VM/CLI arena selection implemented; partial field moves implemented; source pools/handles, checked shared region backing, lexical source arenas, and conservative escape checking implemented; explicit source reset results implemented | Allocator and clock/random authority/effects pass acceptance; source resource lifecycle and cleanup effects pass; bounded environment lookup passes; resource reads/writes pass; permission attenuation passes; borrowed slice I/O passes; lexical arena acceptance passes under the documented conservative lifetime rules; explicit reset result acceptance passes. |
| D, errors and abstraction | In progress: typed results, checked handling/transfer, acknowledgement, and propagation implemented; typed-handle pool backend implemented; source handles implemented; generic syntax, builtin requirements, pure symbolic body/call checking and executable specialization implemented; borrowed inputs/slices/lexical reborrows/reference provenance, concrete record/array updates, enum/union construction and exhaustive matching implemented; concrete result transfer/acknowledgement/propagation and path obligations implemented; partial field moves and remaining-field obligations implemented; concrete owned transfer and cleanup-effect inference implemented; buffer/pool acquisition and operations with allocation effects implemented; provider capability/result/effect operations implemented; local array/buffer views and concrete array-input slice results implemented; local arena/reset scopes with monotone origin and escape checks implemented; structural constraints and public generic tooling pending | Use the application trial to prioritize further structural/codec abstractions; diagnostic repair quality is next in the interpreter-first order. |
| M, modules/interfaces | Implemented experimental scope: bounded imports, exports/privacy, source maps, module checking/VM execution, direction policy, default-limit graph/tooling acceptance, and initial ordinary-application corpus review | Shared-domain execution, direction policy, 256-module/4096-import boundaries, and invoice/packet application acceptance pass; production-user corpus evidence remains unmeasured. |
| E, native execution — deferred | C emission, native builder, provider adapters, embedding, value/domain ABIs and generated bindings have historical acceptance evidence. | Retain existing assets. Further coverage, borrowed/capability native calls, native performance, LLVM and direct x86_64 Linux output are outside current milestones. |
| F, compile-time/schema/incremental work | In progress: restricted effect-free project evaluation with step/frame/VM-memory budgets and source/implementation dependency receipts plus request identity before execution and persistent successful VM-result reuse with bounded field-level request comparisons implemented; typed scalar input manifest validation/module generation and fresh in-memory evaluation/cache bindings for multiple bounded manifests implemented; checked public type/function schema derivation and bounded ordinary typed JSON serialization/deserialization with owned failure locations and standalone Python data bindings with checked persistent artifact reuse and unchanged-output preservation implemented; checked full source receipts for schema/binding generation and exported effect-free typed invocation with owned argument copies implemented; explicit domain codec declarations and schema contracts implemented; executed domain JSON with shared operation budgets implemented; schema-pinned public JSON invocation implemented; generated Python callable wrappers and domain wire objects plus fresh manifest inputs for schema generation and calls implemented; automatic content polling through a persistent check session and bounded exact successful-verdict reuse with warning replay implemented; native value/domain ABI bindings implemented; native borrowed/capability bindings deferred; source byte serialization and finer incremental checking remain pending | Prioritize bounded source byte serialization and finer semantic reuse when the interpreter trial needs them; preserve input/schema and budget checks. |
| T, formatter/reference reports/verification | Canonical single-file/module formatter and reachable-project formatting checks, resolved function-call/binding reports including module main/export roots, configurable structural metrics, and separate manifest verification driver implemented | Extend reference/specification identities and entry roots as needed by the trial; evaluate duplication usefulness and diagnostic repair outcomes. |

## Historical implementation checkpoints

The remainder records earlier decisions and validation at their recorded scope.
Dated “next” statements do not override the interpreter-first priorities above.

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


### Readable specialization diagnostics and metadata — 2026-09-06

Checked functions now retain concrete type arguments explicitly. Instance display
names include ordered concrete types and qualified nominal names, remain unchanged
when discovery order changes, and flow into dumps/reports and VM/C traces. Public
module/schema roots use metadata rather than punctuation to exclude internal
instances. This advances the original understandable-diagnostics criterion; it
does not complete direct public generic tooling, broader operations, native
embedding or incremental compilation. See `docs/experiments/generic-diagnostics.md`.

Validation: all 586 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Tests cover discovery-order independence,
qualified nominal names, dump/trace output, schema exclusion and allocation-failure
cleanup. This does not establish completion of direct generic public tooling or
the other unfinished roadmap tracks.


### Native embedding entry and shared-library builds — 2026-09-06

Generated C now offers `mylang_native_run_v1` with explicit providers and budgets,
a scalar entry result, bounded located traps and returning host failures. Every
invocation releases guest storage; repeated calls reset state, and overlapping
calls return Busy. `scripts/native.py --library` builds a shared library while
preserving atomic and unchanged-output publication. See
`docs/experiments/native-embedding.md` for the public C header contract.

Focused acceptance passed 24 host programs across -O0/-O2 with undefined-behavior
sanitization, repeated calls, frame/step budgets, reentry/concurrent rejection,
live-resource trap cleanup and allocation-failure recovery. Independent public-header hosts
linked and ran Debug/ReleaseFast shared libraries and verified unchanged rebuilds.
All 586 ReleaseFast core tests passed; the full Debug regression command also
completed successfully, including 586 core and 60 CLI tests. Arbitrary exported native calls,
aggregate native arguments/results, generated native callable bindings, finer
incremental compilation and the other pending roadmap requirements remain open.


### Exported native scalar invocation — 2026-09-06

Module native emission now retains resolved export roots and exposes
`mylang_native_call_v1`. Hosts call qualified public names with exact typed scalar
bits; integer widths, full u64 results, Booleans, counts and ranges are checked.
Private helpers and internal generic instances remain unavailable. Located traps,
budgets, cleanup and repeated-call recovery share the native entry machinery.
The public C headers work with independently linked shared-library hosts. See
`docs/experiments/native-calls.md` for the contract.

Validation: 587 core tests passed in both Debug and ReleaseFast; all 60 CLI
tests and formatting passed. Native parity
passed 2682 comparisons across 93 single-file and 16 module fixtures, and all 24
embedding host programs passed. Named-call acceptance passed -O0/-O2 sanitizer
runs and Debug/ReleaseFast shared-library host links, covering visibility, every
scalar boundary, invalid inputs, trap locations, allocation failures and recovery.
Guardian passed all 88 checks without baselines. The earlier full Debug embedding
suite also completed successfully before this API extension. Aggregate/domain
native wire values, borrowed/capability signatures, generated native callable
bindings, incremental compilation and the other pending roadmap items remain open.


### Native ordinary aggregate value calls — 2026-09-06

`mylang_native_call_values_v1` now copies checked preorder scalar, record,
fixed-array/table, enum, packed/boxed variant and typed-result values across the
native host boundary. Inputs become guest-owned copies; outputs use caller-owned
nodes and retain no guest allocation. Counts, type names, tags and scalar ranges
are validated; the scalar call API shares that range implementation. Output
capacity failures report the required size without writing output. Domains,
resources and other runtime identities remain opaque. See
`docs/experiments/native-wire.md` for the positional schema and ownership contract.

Acceptance passes address/undefined-behavior sanitizer runs in -O0/-O2 and
independent Debug/ReleaseFast shared-library hosts. Tests cover snapshots,
empty values, nested packed/boxed payloads, enum tables, typed results, malformed
inputs, opaque signatures, output capacity, traps, allocation failures, recovery,
exact 128-level and 100000-node limits, and cross-API Busy rejection. Full core
runs passed 587 tests in Debug/ReleaseFast, all 60 CLI tests passed, and native
parity passed 2682 comparisons. All 24 embedding cases and scalar native-call
acceptance passed. Final shared-range refactoring is checked by both native call
drivers and focused compiler allocation tests. Guardian passed all 88 checks with
baselines disabled. A variant-input regression exposed and corrected use of a
guest-frame-only stack helper before entry-frame creation; this was test-derived
evidence. Native domain codecs, generated schema-pinned native bindings,
borrowed/capability signatures, incremental compilation and other roadmap items
remain unfinished.


### Schema-pinned generated native Python bindings — 2026-09-06

Native module libraries now expose canonical public schema bytes and SHA-256
from the same checked compilation as their code. Shared checked-schema rendering
avoids a project/schema import cycle. Generated Python modules include
`NativeClient` and `NativeLimits`; their existing typed wrappers call ordinary
native scalar/record/array/table/variant/result functions only after validating
the library's schema. Calls preserve host snapshots, report native traps and
budgets, and do not retry output-capacity failures. Both embedded runtime sources
participate in the generator/cache identity. See
`docs/experiments/native-bindings.md` for usage and the synchronous native boundary.

Independent metadata tests pass public field/type/case/export invalidation,
compatible body/private/relocation stability, concurrent queries, both native
optimization modes and absent single-file schemas. Generated Python acceptance
passes typed compiler/native comparisons, schema/ABI/I/O rejection, integer
boundaries, snapshots, traps/recovery, node/depth/frame/step budgets, malformed
results and calls after source removal. Existing Python data/call, binding-cache,
schema and receipt tests pass; cache tests include changes to the native runtime.
All 587 core tests passed in Debug/ReleaseFast, all 60 CLI tests and formatting
passed, and native parity passed 2682 comparisons. Native scalar/aggregate host
acceptance passes, and Guardian passed all 88 checks without baselines. These are
focused and core regression results, not a new full-build-test run.

Native domain codecs, borrowed/capability invocation, source serialization,
finer semantic/native incremental compilation and the other pending roadmap
requirements remain unfinished. Schema identity establishes interface
compatibility; it does not authenticate implementation behavior.


### Internal native codec execution — 2026-09-06

Generated native dispatch now permits internal calls only to functions selected
by checked domain codec declarations. One owned argument and result cross the
internal call boundary while the surrounding operands, frames, instruction/frame
budgets and cleanup destination are preserved. Normal public calls retain their
existing behavior. This is a prerequisite for codec-aware native value traversal;
public wire calls and NativeClient still reject domain signatures. See
`docs/experiments/native-codec-dispatch.md` for the remaining integration.

Four sanitizer hosts pass nontrivial decoder/encoder execution, packed/boxed
rejection ownership, caller operand/frame preservation, shared budgets, exact
trap frames, non-codec private-helper rejection, allocation failures and recovery.
An uninstantiated generic declaration verifies separation from source declaration
ordinals. Compiler codec-dispatch allocation sweeps pass. All 588 core tests
passed in Debug/ReleaseFast, all 60 CLI tests and formatting passed, and native
parity passed 2682 comparisons. Existing 24 embedding cases, ordinary aggregate
wire acceptance and generated native Python tests pass. Guardian passed all 88
checks with baselines disabled; no new full-build-test run is claimed.

Public native codec input/output conversion, typed rejection reporting, shared
codec-call quotas and generated-client domain support remain unfinished. Output
encoding must be staged so each encoder runs once rather than once per sizing
and writing pass. The other pending roadmap requirements also remain open.


### Public native domain codec calls — 2026-09-06

The new `mylang_native_call_codecs_v1` API converts declared domain wire values,
including domains nested in records, arrays and variants. Input decoders, the
public root and output encoders share step/frame limits and a separate bounded
call quota. Encoded output is staged before publication so each encoder runs once
and insufficient buffers or traps leave caller output unchanged. Implicit decoder
rejections carry the domain identity and ordinary typed rejection tree; explicit
public decoder calls retain ordinary language-result semantics. The original
value API keeps its domain opacity. See `docs/experiments/native-codec-wire.md`.

Four sanitizer hosts and four separately linked public-header hosts pass both
optimization modes and packed/boxed rejection representations. Coverage includes
nested conversion, exact call limits, shared step/frame budgets, decoder/encoder
traps, unchanged insufficient output, allocation failures and repeated recovery.
All 588 core tests pass in Debug and ReleaseFast. Existing internal codec, ordinary
wire, scalar call, generated Python native-client and 24 embedding host cases pass,
including cross-API Busy rejection. All 2682 VM/native comparisons pass. The new
driver runs in `zig build test`; a new
full-suite pass is not claimed here. Guardian passes all 88 checks with baselines
disabled. Generated Python domain support, source-level codec operations and all
other outstanding roadmap requirements remain open.


### Generated Python native domain bindings — 2026-09-06

Generated `NativeClient` now supports the codec-capable public function set,
using explicit domain wire wrappers and the native codec API for domain-bearing
signatures. Ordinary signatures retain the original value ABI and work without
the optional codec symbol. Domain calls report `NativeABIUnavailable` when that
symbol is absent. Schema pins still apply before invocation.

`NativeLimits.max_calls` defaults to 4096 and bounds implicit decoders, the public
root and output encoders under the shared native execution. Host traversal counts
explicit domain nodes in its depth and node budgets. Implicit decoder failures
raise `CallError` with domain/call context and a typed scalar or aggregate rejection
value. Insufficient output never triggers a retry, including when only the
rejection flag and required error-tree capacity are available.

Debug and ReleaseFast shared-library acceptance passes VM/native agreement for
ordinary and nested domain values, nontrivial decoding/encoding, scalar/record
rejections, explicit decoder results, decoder/encoder traps, exact call budgets,
malformed output, absent codec APIs, success/rejection capacity failures and calls
after source removal. Existing Python data binding (29 wire comparisons),
compiler-process call and binding-cache suites pass, including runtime digest
invalidation. Python syntax and whitespace checks pass; Guardian passes all 88
checks with baselines disabled. This change does not claim a new full Zig-suite
run. Source-level codec operations, borrowed/capability native invocation,
incremental compilation and all other pending roadmap requirements remain open.


### Source declared domain codec operations — 2026-09-06

Source expressions now support `codec_decode<Domain>(wire)` and
`codec_encode<Domain>(value)`. They select the methods named by an explicit codec
contract and lower to ordinary checked calls, retaining public visibility,
parameter/result typing, result obligations, effect checks and execution budgets.
The decoder returns its declared typed result; encoding cannot accept raw backing
values. Imported domain aliases and formatter round trips are supported.
See `docs/experiments/source-codecs.md`.

Both full core runs passed 591 tests in Debug/ReleaseFast; final focused acceptance
adds a nonstandard method-name/transformation case and generic-constraint rejection.
All 60 CLI tests and 2688 VM/native comparisons across 110 fixtures passed.
Allocation-failure tests cover source execution/formatting and imported codec
resolution. Guardian passes all 88 checks without baselines. New behavior
classification subjects for the lexer, formatter and resolver were labeled
intentional-change against the tagged SOURCE-CODEC-1 contract; uncertain subjects
remain pending. No new full build-test run is claimed.

This completes explicit source domain-to-wire conversion. JSON byte serialization
operations still need bounded buffer/slice contracts, allocation authority and
typed malformed-input handling. Generic codec constraints, borrowed/capability
native invocation, finer incremental compilation and all other outstanding
roadmap work remain open.


### Exact successful project-check reuse — 2026-09-06

Persistent checking sessions now retain one bounded successful verdict alongside
the syntax cache. Every request freshly loads files, module headers and generated
manifest inputs before comparing complete module names, paths and source bytes.
An exact hit replays owned warnings and skips interface/semantic work. Changed
snapshots check afresh; failed checks are never retained. Clearing drops both
caches. Cumulative `semantic` JSON observations distinguish hits, misses, storage,
bypass and retained bytes from actual syntax reuse.

Verdict retention is limited to a separate 16 MiB arena, for up to 32 MiB combined
syntax/verdict entry storage. Oversized entries bypass storage; failed replacement
allocations preserve the prior successful verdict. This is in-process whole-project
reuse, with no hash-only key or persistent disk verdicts. See
`docs/experiments/check-session.md` for the protocol and trust boundary.

Full core suites passed 595 tests in Debug/ReleaseFast; final five-test cache runs
add explicit failed-replacement preservation. All 60 CLI tests pass. Persistent
session and watch acceptance pass exact warm hits, identical warning replay,
source/type/privacy/deleted-file recovery, changed/invalid manifests, clear,
retention bounds and protocol/child cleanup. Guardian passes all 88 checks without
baselines; its complexity finding prompted shared loading/input-validation and
verdict helpers and was labeled useful-review. The cache behavior was labeled
intentional-change; uncertain subjects remain pending. No new full build-test run
is claimed. Finer semantic queries, persistent reuse, incremental native linking,
source JSON byte serialization and all other pending roadmap items remain open.


### Concrete schemas in generic bodies — 2026-09-06

The abstract generic checker now shares the resolved type catalog with concrete
specialization. Fixed copyable records, arrays and nominal values can appear
alongside symbolic parameters in signatures, local annotations, generic calls
and pure concrete helpers. Record/array construction, record projection, array
and enum-table indexing, and length use declared concrete schemas. Imported
aliases retain declaring-module resolution; nominally different records remain
distinct, and symbolic integer parameters still require explicit conversion to
fixed integer fields. Concrete domains can pass through without exposing backing
construction. Complete runtime-identity/result-bearing graphs remain excluded.
See `docs/experiments/generic-concrete.md` and `examples/generic-records.my`.

All 599 core tests pass in Debug/ReleaseFast, all 60 CLI tests pass, and VM/native
parity passes 2706 comparisons across 113 fixtures, including imported record
helpers and an imported generic bounds trap. Final focused tests in both modes
also verify concrete-domain passthrough. Allocation sweeps cover abstract and
concrete checking, VM execution and native emission. Formatting and all 88 Guardian
checks pass with baselines disabled. Its concreteType error-path claim was labeled
false-positive because rejection/allocation tests already covered the catch;
adding the helper name to the test title was the only required edit.

Parameter-dependent composite types, generic type declarations, structural
requirements, aggregate updates, variants/results/ownership abstract rules,
source codec constraints, public generic tooling and the remaining roadmap
requirements stay open. This is not completion of the full generic language or
a claim of a new full build-test run.


### Generic aggregate updates — 2026-09-06

Generic bodies now support partial updates of concrete copyable records and
replacement of fixed-array or enum-table elements. Construction/update field
validation and indexing/replacement index validation share helpers. Updates
preserve untouched fields, require unique known fields with exact types, and
cannot infer a record shape from a symbolic parameter. Table keys retain nominal
enum identity. Ordinary specialization/lowering retains snapshots, evaluation
order and runtime bounds. See `docs/experiments/generic-updates.md` and
`examples/generic-updates.my`, which returns 44 while reading original and updated
record/table values.

All 601 core tests pass in Debug/ReleaseFast; all 60 CLI tests and 2724 VM/native
comparisons across 116 fixtures pass. Allocation sweeps cover record/table snapshot
updates and native emission. Uncalled-template tests reject malformed fields,
indices, elements and enum keys; imported native fixtures cover empty-array and
maximum-u64 replacement traps. Formatting and all 88 Guardian checks pass with
baselines disabled. Uncertain ROI subjects remain pending, and no new full
build-test run is claimed.

Concrete variant construction/matching, result/ownership abstract rules,
parameter-dependent structural types, codec constraints, public generic tooling,
source JSON serialization and all other pending roadmap requirements remain open.


### Concrete generic variants and exhaustive matching — 2026-09-06

Generic bodies now construct concrete copyable enums/unions and match them
exhaustively. Nominal case ownership, exact payload presence/type, arm-local
bindings, duplicate/missing cases and all-arm return flow are checked before
instantiation. Every arm is checked even after a fallthrough arm; bindings do not
escape or conflict across independent arms. Named enum-table construction now
requires every declared key exactly once and shares record field validation.
See `docs/experiments/generic-variants.md` and `examples/generic-variants.my`, which
returns 16 from record/scalar union payloads and a complete enum table.

All 605 core tests pass in Debug/ReleaseFast; all 60 CLI tests and 2742 VM/native
comparisons across 119 fixtures pass. Allocation sweeps cover construction,
matching, enum tables, execution and native emission. Rejection tests cover
payload/case/type errors, scope escape, incomplete return paths and invalid later
arms. Imported fixtures retain aliases and located traps inside generic match
arms. Formatting and all 88 Guardian checks pass with baselines disabled.
Uncertain ROI subjects remain pending; no new full build-test run is claimed.

Result-bearing and runtime-owned variant graphs remain excluded pending abstract
handling/ownership rules. Parameter-dependent structural types, generic codec
constraints, public generic tooling, source JSON serialization and the remaining
roadmap requirements stay open.


### Ownership diagnostic provenance and repairs — 2026-09-06

Whole-value transfer/handling failures, conflicting borrows and suspended parent
references now retain both the causal operation and the original binding's
source location. Ordinary and abstract generic checking share the diagnostic
helpers. Ownership snapshots preserve move witnesses across checked paths;
replacement clears the witness before a later transfer. Active-loan selection
is deterministic, and imported generic diagnostics map every note to the
original module. See [the provenance contract](diagnostic-provenance.md).

Authored repair fixtures assert exact diagnostic codes and source offsets, then
execute corrected result-transfer, borrow-scope, child-reference and moved-buffer
programs. A CLI fixture checks all three imported-module locations and executes
the repaired project. Allocation-failure coverage checks collection and rendering.
These regressions do not measure an agent's repair success rate.

Validation: Debug `zig build test` passes 27/27 steps and ReleaseFast
`test-interpreter` passes 28/28 steps; both pass 721/721 core/CLI tests
(658 core, 63 CLI), the interpreter/tooling drivers and 96 independent corpus
comparisons. Formatting and all 88 Guardian checks pass with baselines disabled;
existing report-only size/line findings remain. A test helper's parameter count
and five hard-limit call lines required one additional gate cycle. No native
execution suite was run.

Partial-field moves, arena/lifetime explanations, versioned machine-readable CLI
diagnostics and optional-value ergonomics remain open in this track. Typed host
registration, the real application/repair trial and remaining interpreter
roadmap items stay active. Native execution remains excluded.
