# Compiler behavior specification

This document records implemented behavior with executable Zig regression evidence.
Each stable ID has one primary `// spec:` test. Additional tests and Python
acceptance drivers exercise further cases; these links are not a claim of exhaustive
coverage or proof of memory safety. The language remains experimental. Ownership
and resource behaviors below describe the VM unless native output is named.
The roadmap in `docs/experiments/roadmap.md` tracks unsupported and planned features.

## Core semantics

- [BYTE-LITERAL-1] Quoted byte literals produce ordinary fixed `[N]u8` arrays without terminators. UTF-8 source contributes its encoded bytes; escapes are `\n`, `\r`, `\t`, `\0`, `\\`, `\"` and exactly two hexadecimal digits after `\x`. Empty literals have length zero; each literal is limited to 65,536 decoded bytes (`E_BYTE_LITERAL_LIMIT`). Checking, generic bodies, module relocation, cached syntax and formatting preserve ordinary array identity and behavior. Invalid escapes and unterminated literals are located source errors.

- [CORE-1] Evaluates multiplication before addition, honors parentheses, and associates subtraction from the left.
- [CORE-2] Reports checked arithmetic overflow at the responsible operator without evaluating arithmetic during checking.
- [CORE-3] Returns located source diagnostics for empty input, malformed syntax, and out-of-range integer literals.
- [CORE-4] Accepts the signed and unsigned integer width limits and rejects literals above each maximum.
- [CORE-5] Constructs records by field name and preserves original values when producing updated record copies.
- [CORE-6] Preserves fixed-array copies and accepts each integer index width, including zero-length arrays.
- [CORE-7] Rejects interchange between distinct nominal domains and requires their declared construction operations.
- [DOMAIN-EQUALITY-1] Values of the same scalar domain support == and != by their integer or boolean backing values, including generic equality requirements. Declaration identity must match across module aliases; equality exposes no backing value, permits no implicit arithmetic or ordering, evaluates operands left to right, and preserves VM cleanup and execution limits.
- [CORE-8] Rejects nonexhaustive matches after a variant is added, including matches on statically known values.
- [CORE-9] Uses enum case names for table construction and indexing regardless of declaration or initializer order.
- [CORE-10] Rejects silent result abandonment and permits an explicit acknowledgement of the result obligation.
- [CORE-11] Unwraps successful results and propagates compatible error payloads by case name across nominal result types. Native propagation constructs the outgoing result before releasing unfinished operands; failed construction releases the propagated payload before those operands.
## Ownership and capabilities

- [OWN-1] Rejects conflicting borrows, mutation through shared references, and writes with incompatible value types.
- [OWN-2] Suspends exclusive parent references while child reborrows exist and restores access after their scope.
- [OWN-3] Rejects negative, reversed, and out-of-bounds slice ranges and indices without unsigned truncation.
- [OWN-4] Allows returned scalar references to mutate caller storage and restores parents after the returned borrow scope.
- [OWN-5] Returns nominal owned buffers on successful acquisition and typed errors for invalid or denied capacities.
- [OWN-6] Rejects returns and assignments that allow arena capabilities or their owned storage to escape.
- [OWN-7] Rejects arena reset with live buffers, borrows, or children while preserving copied allocator authority.
- [OWN-8] Rejects forged pool handles, incompatible handle categories, and pool declarations with owning elements.
- [OWN-9] Releases previously acquired resources exactly once when a later acquisition propagates an error.
- [OWN-10] Delegates environment access through explicit grants and distinguishes missing, empty, and present values.
- [OWN-11] Rejects direct and transitive allocation that violates declared effect bounds and reports a call witness.
- [OWN-12] Releases arena backing and owners across every injected host allocation failure in the execution scenario.
## Projects and native output

- [EXPORT-PLACEMENT-1] An export after a type or function declaration rejects with located E_EXPORT_PLACEMENT and instructs moving it after imports and before declarations. Header export semantics and privacy checks are unchanged.

- [PROJ-1] Loads shared module dependencies once in dependency order and releases state on allocation failure.
- [PROJ-2] Reports module cycles with both the importing location and the related source location.
- [PROJ-3] Rejects duplicate exports, missing exported symbols, and private types exposed through public interfaces.
- [PROJ-4] Reports related declarations in their original source files after project source mapping.
- [PROJ-5] Emits deterministic native C for scalar programs and releases compiler allocations on injected failure.
- [PROJ-6] Validates every function before native emission, including uncalled functions, and rejects invalid source without partial output.
- [PROJ-7] Retains static lifetime and exclusivity checks when compiling supported references to native C.
## Discovery and formatting

- [TOOL-1] Groups exact duplicate bodies after binding renaming while preserving resolved binding identity.
- [TOOL-2] Reports literal differences once per exact-group representative when discovering near duplicates.
- [TOOL-3] Reports incomplete near-duplicate discovery when work budgets are exhausted and rejects invalid budgets.
- [TOOL-4] Formats canonical indentation while preserving inline, standalone, and trailing source comments.
- [TOOL-5] Permits semantically incomplete drafts during formatting but rejects syntactically invalid input.
- [TOOL-6] Includes calls in untaken paths and cycles when calculating static function reachability.
## Evaluation and wire boundaries

- [WIRE-1] Preserves aggregate evaluation results and enforces instruction, frame, and memory limits.
- [WIRE-2] Rejects duplicate input names, keywords, unsupported input types, and noncanonical or out-of-range values.
- [WIRE-3] Encodes independently constructed typed values without consuming them and enforces byte, value, and depth limits.
- [WIRE-4] Rejects duplicate, missing, unknown, and private function entries in domain codec declarations.
- [WIRE-5] Shares instruction, invocation, traversal, and memory budgets across nested domain codec values.
- [WIRE-6] Rejects stale schemas, private targets, effects, reference boundaries, and malformed call arguments before execution.
## Command line

- [DEPENDENCIES-1] `project-dependencies` emits a versioned checked module graph with resolved imports, source byte hashes, implementation identity and exact consumed generated-input manifest hashes. It does not execute guest code; invalid projects emit no complete receipt.

- [DISK-PROJECT-1] Interpreter application hosts load `main.my` and imported modules from an explicit disk directory, with bounded reads and no embedded-source fallback. Failed loads and compilation release owned storage and preserve located source errors; a later invocation reads repaired source. Existing typed host registrations remain mandatory. The standalone acceptance driver also changes guest source and project roots using the same executable without Zig or Guardian on PATH.

- [CLI-1] Distinguishes source errors, runtime traps, and invalid command usage through actual process results.
- [CLI-2] Reports missing arguments and missing source files as usage or host failures.
- [CLI-3] Executes the plan acceptance programs and recursive functions through the command-line executable.
- [CLI-4] Schema generation reads declared input manifests into generated modules on every invocation and rejects malformed or duplicate inputs.

- [CACHE-1] Reusing unchanged module syntax preserves fresh semantic checks and changed results, with independent returned storage and bounded cache retention.
- [CLI-5] Persistent checking sessions reuse unchanged parses and allow clearing retained cache storage between requests.

- [NATIVE-BUFFER-1] Native emission supports root allocator parameters and owned buffer results while cleaning failed compiler allocations.

- [NATIVE-ARENA-1] Native arena scopes preserve allocator lifetime, reset rejection, and cleanup on returns and failures.

- [NATIVE-POOL-1] Native pools preserve generation-checked handles, shared quotas, immutable snapshots, and root/arena ownership cleanup.

- [NATIVE-PROVIDER-1] Native clock/random reads require explicit host providers, preserve full-width results and recoverable errors, and reject missing grants before guest execution.

- [NATIVE-ENVIRONMENT-1] Native environment lookup preserves bounded output, missing/empty distinctions, zero padding, typed failures, and explicit provider grants.

- [NATIVE-RESOURCE-1] Native resource lifecycle emission preserves nominal owners, explicit grants, permission intersection, retryable completion errors, and pending-handle cleanup before older guest values.

- [NATIVE-RESOURCE-IO-1] Native resource reads/writes preserve permissions, bounded partial counts, EOF, fixed-array zero padding, slice snapshots, and unchanged guest bytes on provider failure.

- [NOMINAL-TYPE-SYNTAX-1] Nominal declarations retain explicit type parameters and requirements; nested named applications retain base and argument spans through parsing, formatting, syntax caching and module relocation. Lists are bounded at 16 and nesting at 256; module interfaces check exported type privacy, constructor kind, application arity and parameter shadowing. Malformed nominal declarations follow NOMINAL-TEMPLATE-CHECK-1; concrete specialization follows NOMINAL-INSTANCE-1.
- [GENERIC-SYNTAX-1] Generic syntax retains named type parameters, nonempty explicit requirement lists, and explicit `::<...>` call type arguments through owned AST copying and formatting; duplicate parameters/requirements and lists beyond 16 are rejected. Executable specialization must preserve these annotations through contract validation before lowering.

- [NOMINAL-INSTANCE-1] Concrete nominal records, unions, results and enums specialize by declaration and ordered semantic argument identities into complete runtime schemas. Construction, updates, matching, result handling, borrowing and owned-field flow use the ordinary checked IR/VM rules; concrete types compose with existing generic functions and numeric arrays. Unused templates and unexpanded phantom arguments do not become empty runtime records. Public type lookup requires exported bases and visible arguments, including phantom arguments. Symbolic nominal uses in generic function bodies follow NOMINAL-BODY-1. Canonical type display names have a 1 MiB compilation budget, and schema export of a generic type constructor remains explicitly unsupported pending generic tooling.
- [NOMINAL-LAYOUT-1] Nominal declarations, including unused templates, have bounded finite storage graphs before executable specialization. Canonical symbolic identities preserve declaration, parameter scope and ordered arguments. Only stored fields/payloads, array elements and buffer/pool elements expand; phantom arguments do not create storage edges, and pool handles do not point back to pool storage. Even zero-length arrays retain the existing finite-type rule. Cycles reject with E_RECURSIVE_RECORD and original closing-edge/related locations; growing families reject with E_GENERIC_LIMIT at 4096 nominal instances, 4096 array shapes or 100000 expansion operations. Graph IDs are not runtime type IDs and do not authorize execution.
- [NOMINAL-TEMPLATE-CHECK-1] Nominal declaration metadata resolves field and payload expressions to declaration identities and local parameters even in unused templates. It rejects unknown types, shadowing, duplicate members, malformed result schemas, application arity/kind errors and insufficient argument requirements. Copy guarantees propagate through ordinary and generic records/unions without copying owners or pending results; scalar domains, enums and pool handles retain equality without integer operations. Expression checking is bounded at 256 levels and 100000 visits. Metadata is not an executable layout: finite storage dependencies follow NOMINAL-LAYOUT-1; concrete instances follow NOMINAL-INSTANCE-1; symbolic nominal operations in generic function bodies follow NOMINAL-BODY-1.
- [GENERIC-REQUIREMENTS-1] Builtin generic requirements are copy, equality, and integer, with integer implying equality and equality implying copy. Matching uses concrete equality rules and forbids implicit copying of owners or pending results; nominal integer-backed domains are not integers. Unknown requirement names and builtin type-variable shadowing are diagnosed even in uncalled templates before specialization.

- [GENERIC-BODY-1] The initial abstract generic body checker keeps type parameters distinct and requires declared integer/equality support for the corresponding operations. It checks pure builtin/type-parameter signatures, locals, returns, branches, loops, and casts without substituting representative concrete types. Unsupported forms and 256-depth/100000-work bounds reject explicitly; concrete specialization must retain these universal checks.

- [GENERIC-ARRAY-1] Fixed numeric arrays may contain generic type parameters in signatures, constructors, annotations, nested arrays, references and explicit type arguments. Universal checking retains element requirements, exact lengths, nominal identities, copy/result obligations, borrowing, arena origins and source-located traps before specialization. Concrete shapes are interned by element identity and length, with bounded specialization; symbolic enum-keyed tables and parameterized lengths remain explicitly unsupported.
- [GENERIC-CALL-1] Abstract calls between pure generic templates resolve declaration identities and domain/module privacy, require explicit type-argument arity and value-argument arity, enforce requirement implication, and substitute parameter/result identities without merging distinct type variables. Recursive calls check signatures without expanding bodies; reachable concrete helpers must also pass the abstract pure-body rules.

- [GENERIC-HELPER-1] Abstract generic checking validates every transitively called ordinary helper against the supported pure builtin body rules. A bounded declaration worklist checks each reachable body once, including recursive cycles; uncalled ordinary bodies are left to concrete checking. Helper signatures alone cannot authorize hidden effects. Broader effect and ownership contracts remain unfinished.

- [GENERIC-INSTANCE-1] The compilation-local specialization registry interns resolved declaration identities and ordered concrete type identities, owns argument storage, preserves IDs across growth and allocation failure, and reuses recursive requests. It bounds discovery at 4096 entries and each argument list at 16. Nominal types remain distinct regardless of representation. Executable checking uses these identities without conflating them with source declaration ordinals.

- [GENERIC-EXECUTION-1] Pure generic templates specialize on explicit concrete type arguments after universal body validation. Repeated and recursive calls reuse instances; per-instance bindings, expression resolution, widths and nominal types remain distinct. Ordinary entry/export wrappers execute instances through checked VM/C backends. Internal instances are excluded from direct module export/schema roots. Main cannot be generic; unsupported abstract forms still reject.

- [GENERIC-REFERENCE-1] Abstract generic checking distinguishes values, shared references and exclusive references. Reads copy only permitted values; writes and exclusive forwarding require exclusive access. Calls preserve substituted reference types and reject simultaneous aliasing of an exclusive reference, even in uncalled templates. Concrete instances retain ordinary borrow checking.

- [GENERIC-SLICE-1] Shared/exclusive generic slice parameters preserve symbolic element identity and reference kind. Length has type u64; indices require integer support, reads require copy support, and writes require exclusive access and matching elements. Forwarding retains permission and alias checks. Concrete instances retain bounds traps and snapshot semantics.

- [GENERIC-BORROW-1] Generic lexical borrows preserve symbolic value/element identities and copy guarantees, access permissions, root ownership and parent suspension. Range narrowing requires a known slice and integer bounds. Scopes restore access on exit and reject escaping names, conflicting owner access and aliasing exclusive roots, including in uncalled templates. Narrowing an abstract whole value remains unsupported.

- [GENERIC-RETURN-1] Generic reference results validate declared input provenance, symbolic result type, kind and permission even in uncalled templates. Returned roots cannot originate from local values or another input. Borrow-call scopes substitute callee types and preserve root identity, suspension and cleanup. Implicit conversion of references to ordinary values remains forbidden; abstract whole-value-to-slice results remain unsupported.

- [GENERIC-DIAGNOSTIC-1] Checked specializations retain explicit ordered concrete type arguments. Human-readable function names include those types, preserve qualified nominal names, and do not depend on discovery ordinals. Traces and reports use these names, while public-root selection uses specialization metadata rather than spelling.

- [NATIVE-EMBED-1] Generated C can expose a versioned embedding entry instead of main, returning scalar entry results, bounded located traps and host failures without printing or exiting. Providers and budgets are explicit; repeated calls reset guest state and release storage. Overlapping calls to one generated program return Busy. Arbitrary exported-function and aggregate ABI invocation remain unfinished.

- [NATIVE-CALL-1] Native named calls expose only resolved module exports, excluding private functions and internal generic instances. The initial scalar ABI validates exact builtin type names, argument counts and integer/Boolean ranges; unsupported public signatures fail explicitly. Calls return located traps, release storage and permit subsequent invocations.

- [NATIVE-WIRE-1] Native public value calls copy bounded preorder scalar/record/array/variant trees into guest storage and copy results into caller-owned output. Exact schema identities, counts, tags and ranges are validated. Insufficient output reports required capacity without writing output or retaining guest storage. Domain and resource identities remain opaque.

- [NATIVE-SCHEMA-1] Native module libraries expose immutable canonical public schema bytes and their SHA-256 from the same checked compilation as the emitted code. Queries execute no guest code. Single-file libraries without a public schema report absence. Field, case, type and public-function contract changes alter compatibility identity; source location and compatible implementation-only changes need not.

- [NATIVE-BINDINGS-1] Generated Python bindings may call an explicitly selected native shared library only after verifying its canonical public schema hash. Ordinary typed wrappers retain value validation and snapshots, report bounded native traps and host failures, and never retry capacity failures implicitly. Declared domain codecs use the opt-in native codec API with typed rejection errors and shared call limits; ordinary calls retain their original ABI. Reference/capability signatures remain unavailable through this client.

- [NATIVE-CODEC-1] Native embedding can internally invoke compiler-selected declared codec functions while preserving surrounding operands, frames, cleanup ownership and shared instruction/frame budgets. This internal path does not expose arbitrary private functions or accept unvalidated raw domain values through the public wire API.

- [NATIVE-CODEC-WIRE-1] Opt-in native domain calls run declared decoders before public invocation and each output encoder once, with shared instruction/frame/call quotas. Typed decoder rejection values and domain context survive cleanup; prepared output prevents partial publication and duplicate encoding. The ordinary value ABI retains its domain opacity.

- [SOURCE-CODEC-1] `codec_decode<Domain>(wire)` returns the declared decoder's typed result and `codec_encode<Domain>(value)` returns its declared wire value. Both resolve through explicit domain codec contracts and preserve ordinary call typing, ownership, effects, runtime budgets and source diagnostics. They do not expose backing construction or provide JSON byte serialization.

- [CHECK-CACHE-1] A persistent checking session may reuse a successful verdict only after fresh project and manifest loading and exact comparison of every loaded module name, path and source byte. Hits replay owned warnings and skip interface/semantic work; failures are never retained. Retention is bounded and clear drops syntax and verdict caches while preserving cumulative observations.

- [GENERIC-CONCRETE-1] Abstract generic checking resolves concrete copyable nominal and fixed-array schemas without conflating them with type parameters. Concrete record/array construction and projection obey declared field, element and index types; malformed uncalled templates reject. Concrete owned flow follows GENERIC-OWNED-1; individual runtime operations require their own abstract rules. Concrete result obligations follow GENERIC-RESULT-1.

- [GENERIC-UPDATE-1] Generic bodies may update concrete copyable records and replace fixed-array/table elements. Field uniqueness and field/element/index types are checked before instantiation; normal specialization preserves immutable snapshots, evaluation order and runtime bounds. These operations do not infer structural capabilities for symbolic parameters.

- [GENERIC-VARIANT-1] Abstract generic checking supports construction and exhaustive matching of concrete copyable enums/unions. Cases retain nominal identities and exact payload types; each arm scopes its payload independently, duplicate/missing cases reject, and a match terminates only when every arm terminates. Named enum-table construction requires every key exactly once. Result-bearing variants follow GENERIC-RESULT-1; runtime-owned value flow follows GENERIC-OWNED-1.

- [GENERIC-RESULT-1] Abstract checking of concrete result-bearing generic values enforces single transfer, explicit handling, scope/return obligations, and agreement across continuing branches, match arms, loops and short-circuit paths before instantiation. Nested payloads retain obligations and aggregate operations cannot erase siblings or replaced results. Propagation requires compatible concrete result errors and rejects live result bindings or previously evaluated result temporaries on its early-return path. Acknowledgement evaluates its operand. Partial field moves follow GENERIC-FIELD-1; symbolic result type constructors remain pending and concrete owned flow follows GENERIC-OWNED-1.

- [GENERIC-FIELD-1] Generic bodies may read concrete record fields without copying result obligations and take individual fields from concrete result-bearing records. Immutable field-availability snapshots distinguish partial moves across branches, matches, loops and short-circuit paths. Remaining result fields require handling at scope exit, overwrite and early propagation; moved fields reject access and incomplete records reject whole-value use. Replacing a handled partial binding restores all fields. Concrete owned graphs follow GENERIC-OWNED-1; symbolic structural field constraints remain pending.

- [GENERIC-OWNED-1] Abstract generic bodies enforce whole/partial transfer and continuing-path agreement for concrete owned values. Ordinary owned values may be dropped implicitly or explicitly; result-bearing values retain handling obligations. Replacement releases the old ordinary owned value and restores availability. Owned input/return/local type cleanup effects propagate through resolved helper calls, including recursive cycles, and enforce declared bounds before instantiation. Buffer/pool acquisition and operations follow GENERIC-RUNTIME-1; provider operations follow GENERIC-PROVIDER-1 and local regions require their own abstract rules. Copy constraints do not admit owned type arguments.

- [GENERIC-CLEANUP-1] Concrete resource ownership passed through generic functions retains its provider lifecycle. Explicit partial extraction/drop and implicit scope cleanup release each live resource exactly once, including allocation failures and traps; forwarding does not complete or duplicate an external resource.

- [GENERIC-RUNTIME-1] Generic buffer/pool acquisition requires explicit allocator authority, integer capacity and the matching concrete owned-success/i64-error result shape. Buffer/pool operations enforce element/handle/result types, mutable owners and availability after argument evaluation. Acquisition and buffer reserve seed allocation effects through helper calls; in-capacity mutations retain their ordinary noalloc behavior. Result propagation and failure cleanup retain existing owned-value semantics. Provider operations follow GENERIC-PROVIDER-1; local regions and views require their own abstract checks.

- [GENERIC-PROVIDER-1] Abstract generic provider operations enforce concrete or symbolic nominal result contracts, exact capability kinds and byte/slice inputs before instantiation. Resource I/O requires a mutable unconsumed owner after argument evaluation; read slices require exclusive u8 views. Acquisition/completion preserve resource ownership and permission attenuation cannot create authority. Direct clock/random/environment/filesystem/network effects propagate through helper calls and enforce bounds even in uncalled or unreachable source paths.

- [GENERIC-PROVIDER-EXEC-1] Generic provider execution preserves ordinary callback values/counts, bounded output bytes, typed failures, retry ownership and cleanup under allocation failure. Short-circuit paths remain unevaluated at runtime while their possible effects remain statically checked.

- [GENERIC-LOCAL-VIEW-1] Generic bodies may borrow numeric fixed-array and buffer ranges with concrete copyable element types. Bounds evaluate before owner availability/access checks; active views prevent conflicting mutation, transfer or growth, and nested views preserve parent suspension and scope restoration. Array snapshots retain value semantics. A returned slice may originate in its declared concrete whole-array reference input, but local array/buffer storage cannot escape through an input lifetime. Uncalled invalid templates reject, bounds trap at source locations, and VM execution/cleanup survives host allocation failures. Enum tables and undeclared symbolic shapes cannot be sliced; local arena/reset origins remain pending.

- [GENERIC-REGION-1] Generic arena scopes require allocator authority and seed allocation effects through calls. Reset requires bool-success/i64-error results and preserves checked handling; the VM rejects reset while live storage/children remain. Abstract arena dependencies propagate monotonically through values, aggregate fields, match payloads, branches/loops, references and conservative helper effects. Returns, propagated errors, outer bindings and longer-lived container storage reject shorter-lived origins before instantiation. Plain snapshots, independent heap allocations and inert handles may leave. Allocation failures and VM traps release live owners before closing regions; symbolic structural/codec requirements remain separate work.

- [DIAGNOSTIC-PROVENANCE-1] Whole-value transfer/handling errors and conflicting/suspended borrows retain separate causal-operation and value-declaration locations alongside the primary invalid use. Move witnesses follow restored branch/loop ownership state and clear after replacement; a witness describes a checked preceding path. Borrow witnesses select the earliest relevant source declaration deterministically. Ordinary and abstract generic checks expose this evidence in structured diagnostics and readable notes. Repair fixtures assert exact locations and independently execute repaired programs; they do not establish agent repair success rates. Partial-field moves follow DIAGNOSTIC-PARTIAL-MOVE-1; general machine-readable CLI diagnostics remain separate acceptance work.

- [DIAGNOSTIC-PARTIAL-MOVE-1] Reuse of a moved record field reports E_FIELD_MOVED with the earlier field extraction and original binding declaration; invalid whole-record use reports E_PARTIAL_MOVE with a missing-field witness. Ordinary and abstract generic checking preserve witnesses through branch snapshots and clear them on whole-binding replacement. Continuing-path equality compares availability, not source locations. Witnesses identify checked paths, not a predicted runtime branch.

- [DIAGNOSTIC-LIFETIME-1] Arena escape errors retain the deepest dependent arena declaration through conservative calls, aggregate storage and loop fixed points; equal-depth witnesses use the earliest source declaration deterministically. An invalid reference return identifies the returned borrow, its actual owner and the input required by the signature. Ordinary and abstract generic checks retain their existing acceptance rules. Executed repairs and exact-location regressions validate these notes, which explain static dependencies rather than claiming a particular runtime path.

- [DIAGNOSTIC-JSON-1] CLI --diagnostics=json selects diagnostic-v1 JSON Lines on stderr without changing command results or exit statuses. Source and VM diagnostics preserve stable codes, severity, original-file byte ranges and byte-based line/columns, related/origin/requirement notes, bounded frames and omitted-frame counts. Project-loader related sites retain their own module coordinates. Auxiliary CLI messages are separate message records. Successful check-session warning replay uses the selected format, and cache identity prevents cross-format replay. Default text remains available; invalid command-line syntax and emergency output failures may use text.

- [HOST-REGISTRY-1] The trusted host registry snapshots exact names and ordinary nominal signatures, rejects missing/duplicate/mismatched registrations and insufficient effect grants before callback execution, and rejects borrowed/authority-bearing signatures. Synchronous sessions deep-copy inputs and outputs, preserve typed result values, enforce call/value/cooperative-work budgets and reject reentrancy/stale sessions. Callbacks own returned values in the provided allocator and must not retain borrowed call data. Guest declarations and VM dispatch follow HOST-SOURCE-1 and HOST-VM-1.


- [HOST-SOURCE-1] Contextual host fn declarations have no guest body and require an explicit effects(host, ...) contract. Only ordinary top-level, non-generic copied data signatures are supported; references, capabilities and runtime-owned graphs reject. Main retains a guest body. Host and additional declared effects propagate through ordinary and abstract generic calls, including uncalled templates. Effect-free evaluation/invocation cannot execute these calls. Modules, formatting and disassembly preserve declarations; duplicate discovery excludes external implementations.

- [HOST-VM-1] VM host registrations derive only explicit declarations from independently validated bytecode and bind to the same immutable compiled program/catalog. Preflight checks all bindings and grants before guest operations; ordinary functions cannot be overridden. Calls use one synchronous session per execution with copied values, declared result handling, instruction/frame and callback budgets, located failure/contract/limit traps and allocation-failure cleanup. Malformed host bodies, signatures or effect metadata reject. Guest-native compilation of host declarations is unsupported.


- [HOST-INVOKE-1] Host-enabled typed invocation accepts only ordinary copied-value guest signatures and returns a caller-owned typed value or a located trap. Program-bound registrations preflight before guest effects; missing bindings, invalid arguments and hidden public entry names cannot execute callbacks. Pure invocation retains effect-free restrictions. Direct external declarations are not guest entry points. Per-invocation instruction/frame and callback budgets reset, and arguments/results clean up under allocation failures.

- [BOARD-TRIAL-1] The bounded board-validation experiment runs guest bytecode through typed Zig geometry callbacks, compares deterministic reports and callback counts with an independent fixed oracle and standalone Zig implementation, and releases snapshot and callback graphs on allocation failure.

- [NOMINAL-BODY-1] Generic bodies retain nominal declaration identity and ordered symbolic arguments, check fields and payloads before calls, and preserve construction, updates, exhaustive matches, named result propagation, partial ownership, cleanup effects and borrow/arena contracts. Substitution and late VM catalog materialization retain stable type IDs and reuse existing numeric array shapes. Phantom arguments retain identity without contributing stored-value contracts. Shape traversal uses an explicit stack and the generic checking work budget; argument-growing runtime specialization remains bounded by the nominal graph/name limits. Ordinary unconstrained type parameters still require structural constraints for member operations. Provider-specific symbolic shapes follow NOMINAL-PROVIDER-1; public generic schema tooling remains pending.

- [NOMINAL-PROVIDER-1] Generic resource/environment operations accept symbolic nominal result and payload records only when their exact named fields satisfy the ordinary provider contract for every permitted substitution. Declaration order does not affect meaning. Byte inputs and output arrays must have known u8 elements and numeric lengths; a general integer parameter is insufficient. Concrete and symbolic checking share named contract definitions. Resource identity, authority, mutable access, handling, cleanup and effect checks remain enforced before calls. VM specialization preserves bounded bytes, absent environment values, partial I/O, failed-completion ownership and cleanup under allocation failure or instruction traps.

- [GENERIC-CODEC-1] Generic bodies may invoke codec_encode/codec_decode for explicitly concrete domains, resolving the declared method and checking exact value types, arity, result obligations and transitive effects. Reachable factories/accessors are checked with their declaring domain's representation privacy, including module relocation. wrap/unwrap require that exact declaring domain; private methods remain inaccessible outside it. A codec operation on a type parameter rejects until a codec constraint is declared by a future language extension.

- [BOARD-ABSTRACTION-1] The VM board trial uses a shared Slot<T:copy> for optional IDs, regions, features and first violations, and one equality-constrained membership helper for component/net IDs. Typed snapshots preserve each instantiated slot's exact payload identity; a NetId payload cannot enter a component slot. Consolidation preserves the fixed board contract, oracle results, callback counts and repair fixture failure/restoration behavior.

## Interpreted schematic pilot

- [SCHEMATIC-1] The guest S-expression parser, circuit model, interface expansion and SVG renderer execute in the bytecode VM. A typed scalar host boundary exposes only bounded UTF-8 source bytes and unpublished output. Invalid inputs, unsupported forms, incomplete or duplicate pads and invalid ports reject without publishing partial SVG. The pilot supports one parameterless module with one 41-pad IC and supported two-terminal primitives; its documented limits and metadata exclusions are not a general Netlisp evaluator or electrical sign-off.


- [NAVIGATION-1] Compiler navigation indexes module-qualified declaration identities, original source ranges, signatures, effects, concrete call/read/write/field/type relationships and bounded source excerpts without VM execution. Every result carries compiler and loaded-source identities. Static relationships do not establish runtime coverage. Failed body checking emits declarations without checked relationships; lexical recovery after body syntax errors emits explicitly unchecked candidates.
- [GENERIC-API-1] Checked public schemas expose generic templates separately from concrete callable functions and data types, preserving parameter requirements, symbolic signatures, fields/cases, module import scope, effect/reference contracts and source identity. Templates require explicit specialization and cannot be invoked as concrete values through the JSON API.
- [STRUCTURAL-FIELD-1] Copy-constrained function parameters may require named fields with exact named types, including another declared type parameter. Concrete satisfaction and symbolic forwarding preserve nominal identity and checked field reads/updates. Structural fields do not expose opaque domain backing or permit incomplete construction of an unknown record.
- [STRUCTURAL-OP-1] Function parameters may require public nongeneric domain operations with explicit parameter/result types, reference permissions and an effect ceiling. Type-owned generic calls check declared contracts before specialization; concrete operations must satisfy signature, visibility and effects, and borrowed calls retain alias and lifetime rules.
- [STRUCTURAL-LIMIT-1] Structural requirements currently apply to function templates with copy guarantees and named type expressions. Nominal type declarations, unknown complete constructors and operation reference results reject explicitly.
- [SOURCE-JSON-1] Source JSON encoding/decoding uses the versioned typed-json-v1 wire representation, an explicit allocator and owned u8 buffers with checked results; successful values and failed operations release storage correctly under allocation failure.
- [SOURCE-JSON-2] Malformed data and byte quotas return defined checked errors; source limits are bounded by one MiB and invalid requested limits return an invalid-budget error.
- [SOURCE-JSON-3] Domain serialization uses declared, checked, effect-free codec operations and preserves factory rejection without exposing private backing values.
- [SOURCE-JSON-4] Source JSON calls enforce result shapes, allocator authority, serializable data eligibility, allocation effects and ownership transfer before execution.
- [SOURCE-JSON-5] Source JSON byte/value work and codec execution consume the caller's VM step budget, and owned output storage respects buffer capacity constraints.
- [SOURCE-JSON-6] Source JSON decoding rejects wrong versions/types, duplicate or unknown fields, trailing data and malformed values. Reserved codec calls and consumed input buffers retain ordinary call and ownership checks.
- [SOURCE-JSON-7] Nested domain codec execution shares the remaining frame budget with active parent guest frames; nested quota exhaustion cannot exceed the outer VM limits.
- [SOURCE-JSON-8] Bytecode validation rejects forged source JSON operand/result types and invalid domain codec function identities/signatures before execution.
- [GENERIC-JSON-1] The codec requirement proves ordinary serializable data or explicit domain codec eligibility. Uncalled generic bodies and forwarded requirements are checked symbolically, including possible result-handling obligations, without substituting a representative concrete type.
- [INCREMENTAL-CAPACITY-1] The syntax cache retains at most 256 modules within its unchanged byte budget; edits can reuse exact unchanged module syntax while complete semantic checking and diagnostic equivalence remain required.


### Disk application raw byte host

- [BYTE-IO-1] The raw byte host preserves arbitrary input, enforces bounds and publishes output only on successful guest exit.

The `mylang-io --project DIRECTORY` host compiles `main.my` and its imports from
disk into bytecode. It supplies only `io::length() -> i64`,
`io::byte(index: i64) -> u8`, and `io::put(value: u8) -> i64`, each with host effects.
Input bytes are passed untouched, including invalid UTF-8 and NUL. The guest owns
parsing, validation, algorithms, and serialization. Input is bounded at 2 MiB;
output at 128 MiB; a put returns zero on success. Negative/out-of-range reads and
output exhaustion fail the host call. Output is published only after guest main
returns zero, never after traps or nonzero exits. The host supplies no external
filesystem, network, environment or process authority to the guest. Host calls/work
are bounded at 300 million each and VM execution at 2 billion steps; the coordinator
also enforces wall/CPU/memory limits. The executable is built outside application
sessions; editing guest files requires no Zig rebuild or language Guardian run.

- [LITERAL-SLICE-1] A byte-string literal may be passed directly to a readonly u8 slice parameter. Its temporary is borrowed only for that call, then released. Mutable references, other element types and reference-returning calls reject this shorthand.
- [PLAIN-JSON-1] json_parse consumes an owned u8 buffer under explicit allocator authority and returns a checked owned i64 document tape. Plain JSON rejects duplicate decoded keys, invalid Unicode, integers outside i64, nonfinite numbers, trailing data and container depth over 64. Its byte budget is at most 1 MiB; scratch, VM work and output allocation remain bounded.
- [STANDARD-MODULES-1] Reserved std_json and std_text sources load identically through all project providers and participate in source budgets, dependency graphs and digests. std_text requires explicit io host registration.

- [PLAIN-JSON-2] Ordinary JSON validation applies to every subtree, including unused fields: decoded duplicate keys, malformed UTF-8, out-of-range integers, nonfinite floats, trailing bytes and excessive nesting reject.
- [PLAIN-JSON-3] Failed document parsing releases partially allocated DOM, tape and text storage.
- [PLAIN-JSON-4] The VM document operation returns quota errors for output capacity exhaustion and releases consumed input and partial output on all exits.
- [STANDARD-MODULES-2] Embedded standard source bytes count against the same per-file and total project source budgets as user modules.
- [LITERAL-SLICE-2] Concrete and abstract generic checking reject literal arguments to mutable or non-byte references and any reference-returning call.
- [LITERAL-SLICE-3] Literal-backed call references release their backing before the next call, including loops, allocation failures and frame unwinding.
- [STANDARD-TEXT-1] The raw-byte text library emits byte strings and decimal signed integers including i64 minimum and maximum without intermediate signed overflow.
- [PLAIN-JSON-5] Plain document parsing works in generic bodies with a concrete document result, rejects non-document results, and revalidates its decode-only operation at the bytecode boundary.

## Guest application test tool

The `scripts/test_project.py` runner discovers checked exported `test_` functions,
invokes them with schema-pinned typed JSON, and compares structured expectations.
It distinguishes skips, empty selections, traps, assertion failures and setup
failures. It grants no host capabilities. Source/compiler changes invalidate
results. See `docs/experiments/guest-tests.md` and `tests/guest_tests.py`.

## Installed feature identity

- [FEATURE-REPORT-1] `mylang --features` reports `language-features-v1`, the running executable's
SHA-256, pinned Zig version and embedded feature/restriction manifest. The current
reference is `docs/current-language.md`; historical checkpoint prose does not
supersede it. The manifest records implementation coverage, not a test certificate.
- [DIAGNOSTIC-RECOVERY-1] Semantic checking recovers at ordinary and symbolic function boundaries after a source error, reports independent function faults in source order, and deduplicates repeated errors at the same source range and code. It stops within the failed function and skips whole-program verification when any body is incomplete; syntax, type-catalog, and namespace construction remain prerequisites. A failed check never publishes typed code or permits execution. Repeating a failed compilation check preserves diagnostics rather than appending duplicates.

## Proven parameter return regions

- [REGION-PROVENANCE-1] A helper whose every explicit return directly names the same immutable value parameter carries only that parameter's region dependency in its result. Reference parameters, early result propagation, host functions and unrecognized return expressions retain conservative all-argument result dependencies. Mutable reference argument effects always retain conservative dependency checks; actual scratch returns remain rejected escapes.
- [STANDARD-MODULES-3] Reserved std_result, std_bytes and std_json_view provide explicit named errors and optional values, checked document-local JSON access, byte ordering/search, strict UTF-8 validation, checked decimal i64 parsing, and capacity-bounded escaped JSON strings. Raw JSON tape APIs remain compatible; typed queries require an unmodified parser-produced document. Owned error context is moved without discarding its cause.
- [STANDARD-MODULES-4] Escaped ordinary JSON strings quote and escape control bytes, reject invalid UTF-8 distinctly and return a named capacity failure before publishing output.
- [STANDARD-MODULES-5] Typed JSON fields return optional nodes; absent members, present null, wrong types and invalid node indices remain distinct. Object and array access uses member indices without exposing tape offsets.
- [STANDARD-MODULES-6] Standard context errors preserve category, original numeric code and owned byte payload across explicit try propagation. Provider-specific denied codes use an explicit adapter parameter rather than a universal assumed numeric code.
- [STANDARD-MODULES-7] Standard generic Result values retain the language's must-handle obligation; an ignored fallible result is a source error.
- [GENERIC-CONTAINER-1] `buffer Vec<T:copy>:T` and `pool Store<T:copy>(Id):T`
  declare element-generic owners. Pool handles use the same explicit arguments
  (`Id<T>`) and remain distinct across specializations. Element expressions must
  guarantee copy even in uncalled templates; owned and must-handle elements stay
  excluded. Generic operation checking preserves explicit allocator growth,
  move-only ownership, arena provenance, and typed pool failure boundaries.

- [STANDARD-COLLECTIONS-1] The reserved std_collections module supplies generic
  vectors under explicit allocator/capacity authority and allocation-free slice
  find, contains, reversal, integer insertion sort and lower-bound search. Sorting
  is stable, ascending and quadratic; lower_bound requires ascending input and
  returns an insertion index. Vector elements retain the copy requirement.
- [BYTE-IO-BULK-1] The byte application host optionally registers io::read_block(i64)->Block and io::write_block(Block)->i64 for a copied plain Block with bytes:[256]u8 followed by count:i64. Reads return up to 256 useful bytes with zero padding, count zero at EOF, and reject offsets outside [0,input length]. Writes reject counts outside [0,256], append up to remaining unpublished output capacity, and return the accepted count. Each call charges one work unit plus transferred bytes before mutation; allocation/work failure never appends a partial block. Existing scalar declarations remain compatible. Output is published only after successful guest exit.
- [BYTE-IO-LIMITS-1] mylang-io accepts unique decimal --max-input, --max-output, --max-steps, --max-calls and --max-work values using = syntax after --project DIRECTORY. Input/output limits may be zero; execution budgets must be positive. Unknown flags, duplicate limits, non-decimal values and overflow reject before invocation. The configured input limit, output publication capacity and VM/host budgets are enforced without changing default limits.

- [BOUNDED-COLLECTIONS-1] std_map, std_set and std_queue provide capacity-bounded,
  element-generic collections. Operations return their owner on both accepted and
  rejected mutations. Existing map keys replace, set insertion deduplicates, queue
  removal is FIFO, full insertion preserves content, and removal frees capacity.
  Operations never grow implicitly and preserve cleanup on every branch.
- [UNIT-CONVENTION-1] Reserved std_unit exports the empty ordinary record Unit and noalloc unit()->Unit constructor. Unit is a copyable normal value accepted by generic functions and result payloads; successful operations with no useful payload need no dummy integer. Fallible Result<Unit,E> keeps its must-handle obligation.
- [SCOPED-PROVIDERS-1] Packaged resource adapters accept only relative normal path components under an open directory and exact configured numeric TCP endpoints. Read-only acquisition rejects write/create/truncate modes before effects; network adapters do not resolve DNS or follow redirects.
- [SCOPED-PROVIDERS-2] Directory adapters reject symlink path components, create exclusively, truncate only opened regular files, report actual partial I/O and close all provider handles when their stores end. The host keeps directory and endpoint grants alive until provider stores close.
- [SCOPED-PROVIDERS-3] The packaged synchronous TCP adapter connects only after an exact endpoint grant match, transfers bounded byte chunks with reported progress, and closes the connection on completion or cleanup.

- [SCOPED-PROVIDERS-4] mylang-io provisions directory and numeric endpoint capabilities only with explicit --allow-dir=PATH and --allow-endpoint=IP:PORT arguments; directories default to read-only and --allow-write requires a directory grant. Unknown, duplicate directory, invalid endpoint and unscoped write grants reject before invocation.

- [LOOP-EXIT-1] break and continue are terminating statements targeting the nearest enclosing while loop. They reject outside loops, retain must-handle obligations, conservatively preserve ownership of outer locals, and clean up exited borrows, owned values and nested arenas before jumping. Generic bodies enforce the same contracts. Loops remain conservatively fallthrough-capable for return checking.

- [CONSTANT-1] Module-level const NAME: TYPE = EXPR declarations define immutable builtin integer or bool values. Initializers use literals, scalar casts/operators and visible constants with acyclic forward dependencies; allocation and external effects are excluded even in untaken operands; SOURCE-EVAL-1 adds bounded scalar source-function calls. Checking evaluates with width/overflow/division validation and bounded depth/work before emitting literal getters. Normal short-circuit evaluation applies after syntax/dependency validation. Exports and imported names use ordinary privacy checks; generic functions may read constants.

- [FOR-RANGE-1] for NAME in START..END iterates a half-open ascending range of matching integer types with an immutable scoped binding. Bounds evaluate once left-to-right; empty/reversed ranges execute no body. Continue performs the hidden checked increment before the next condition; break skips it. Generic ranges retain integer requirements and the same ownership/borrow/arena cleanup rules as while.

- [MATCH-VALUE-1] match expressions select one expression from an exhaustive set of variant arms, evaluate the scrutinee once, and require every arm to yield the same type. Payload bindings and owned/result values preserve existing move and must-handle rules. Match expressions retain outer temporary obligations during try propagation, keep branch ownership states compatible, and propagate arena dependencies through the selected result. Ordinary and generic bodies share these checks.

- [TYPE-ALIAS-1] type NAME = TYPE declares a transparent non-parameterized alias for an existing scalar, aggregate, fixed array or concrete nominal application. Alias chains support forward references and reject cycles or declaration conflicts. They preserve target nominal identity, ownership and result obligations; they never unwrap domains. Exported aliases obey interface visibility checks and private aliases cannot be named across modules. Constants accept aliases of supported scalar types.

- [OWNER-REFERENCE-1] Whole-value shared/exclusive references may borrow owners
  without result-handling obligations. read_field copies an ordinary field through
  a shared reference; buffer/pool operations use shared inspection or exclusive
  mutation. read_ref and take_field cannot copy or move a borrowed owner. Whole
  partial owners reject borrowing. Element slices are borrowed from owners in
  separate lexical scopes, so growth cannot invalidate an outstanding view.
- [NATIVE-HOST-1] Native C host declarations use a checked copied preorder-value ABI with exact qualified function/type names, effect bounds and explicit grants. All host registrations preflight before guest instructions; calls and sticky callback work charges share execution budgets, input/output copies share node/depth limits, and malformed results fail with cleanup. Provider ABI version 5 adds the host registry without exposing guest pointers.
- [NATIVE-HOST-2] Native copied host values preserve nominal domains, records, arrays and fallible variants across generic calls; scalar domain equality compares the same checked backing values as the VM. Invalid host result structures trap before a guest result is published.
- [NATIVE-JSON-1] Native ordinary json_parse links the same strict parser used by the VM through a versioned support-object ABI. It preserves malformed/limit/budget errors, UTF-8 and duplicate-key rejection, tape layout, instruction charges and allocator-region ownership, and frees parser output on native failures. Typed source domain codecs invoke isolated compiled methods with copied data.
- [NATIVE-JSON-2] Native typed source JSON for ordinary integers, booleans, records, arrays, enums and result/union variants uses the normative typed-json-v1 encoder/decoder, preserving byte/traversal quotas, canonical output and named nominal identities.
- [NATIVE-JSON-3] Native source JSON invokes checked domain methods as compiled code in isolated operand/frame/object registries, copies input and result values, preserves remaining frame/step and 256-call budgets, and restores caller state after domain rejection or traps.

- [NATIVE-JSON-4] Typed native JSON releases temporary metadata, copied values and codec output at every parent allocator failure position.

## Runtime requested-byte accounting

- [RUNTIME-BYTES-1] Embedded allocation budgets support child quotas clamped to the parent limit. Child allocations and resize/remap operations charge both live-byte limits; failed acquisitions do not charge storage; release restores live accounting and retains peak statistics. Accounting objects must outlive every allocation made through them.
- [RUNTIME-BYTES-2] The byte application runner accepts unique nonnegative `--max-runtime-bytes`, `--max-vm-bytes`, `--max-host-bytes` limits and `--memory-report`. VM and host requested live bytes share the total cap. Source compilation/input storage, underlying allocator overhead, operating-system and provider-internal allocations outside the supplied allocator are excluded. Exhaustion terminates execution with cleanup; it is not a guest-recoverable numeric error. Reports distinguish VM allocations (including retained arena chunks) and host allocations.
- [INTEGER-EXTENDED-1] Named integer bitwise operations, shifts, wrapping and saturating arithmetic use declared widths; invalid shift counts trap identically across optimization modes.

## Explicit implementation obligations

- [TYPED-HOLES-1] `todo<T>()` declares an unresolved implementation obligation with a checked required type and a located `E_TYPED_HOLE` diagnostic plus related type span. Ordinary and uncalled generic function bodies report independent holes at safe recovery boundaries. Formatting retains them. No checked program, bytecode or executable is published until every hole is replaced. This is an explicit declared type, not inferred expected-type completion.

## Bounded host replay

- [HOST-REPLAY-1] In-memory host transcripts wrap explicit copied-value registrations without adding authority. They record bounded calls, argument fingerprints, copied outcomes and cooperative work; replay checks exact sequence/schema identity and never reinvokes providers. Missing/extra/changed calls invalidate replay. Recording exhaustion or allocation failure leaves an incomplete transcript. Transcripts borrow the checked schema and own their copies; all registrations close before transcript destruction. They are single-threaded debugging artifacts, not portable or secret-free logs.

## Bounded VM explanations

- [VM-TRACE-1] Optional `memory.trace` observations record instruction/source identity and the top operand before execution into a caller-owned bounded buffer. Scalar values can explain branch conditions; aggregates record only type identity. Full buffers count omitted events without changing guest work/steps or retaining guest owners. Traces are debugging samples, not complete causal proofs or portable replay logs.

- [SPLIT-LEASE-1] An explicit checked exclusive split creates disjoint siblings
  atomically and suspends its parent until both descendants end. Physical buffer
  extents and projected array-member extents retain independent bounds; projected
  leases cannot authorize whole-array access. Empty/nested partitions preserve
  bounds, snapshot semantics, ownership exclusion and allocation-failure cleanup.

- [SPLIT-SOURCE-1] `split view at midpoint as left, right { ... }` creates checked disjoint exclusive slices. Siblings may be supplied to the same call, including generic calls. Parent access is suspended for their lexical scope.
- [FLOAT-DOMAIN-1] std_math::F64 supplies explicit IEEE binary64 operations over a nominal u64 representation, canonical arithmetic NaNs, numeric comparisons, checked integer conversion and exact bit serialization; builtin f64 syntax is not introduced.

- [STRUCTURAL-COMPOSITE-1] Structural field and operation signatures substitute fixed arrays and nominal applications. Slice and whole-owner reference parameters preserve their declared permissions and effect ceiling; result obligations remain transferred by value. Invalid unused templates still reject.

- [REGION-PROJECTION-1] Proven immutable aliases and record field selections retain only the selected input authority. Generic specializations use the same field identities. Unknown, mutable, ambiguous, host, borrowed-parameter and early-propagation return flows retain conservative all-input provenance.
- [SOURCE-EVAL-1] Scalar module constants may invoke nongeneric source functions with scalar arguments, locals, branches, loops and recursion. Static validation rejects external effects and unsupported memory/aggregate operations even in untaken paths. Evaluation is limited to 256 nesting levels and 65536 expression, statement and lookup work units, with located errors and no executable publication on failure. Every compilation reevaluates from its complete source/input snapshot with fixed-width target-independent scalar semantics.

- [SPLIT-CONTEXTUAL-1] `split` introduces a partition only at statement start followed by its view identifier; it remains available as a function, local, field or reference identifier elsewhere.

- [RUNTIME-CATEGORIES-1] VM guest backing may use a separately budgeted allocator from metadata and independent snapshots. Reports distinguish requested backing bytes (including retained arena chunks) from logical live/peak buffer and pool slots; nested regions use the supplied backing budget and failed acquisitions do not increase logical accounting.

- [CONST-LENGTH-1] Generic functions and nominal declarations accept explicit const N:u64 parameters, used as array lengths, forwarded constant arguments and u64 values in function bodies. Literal lengths are bounded to 1048576 and participate in specialization identity separately from type arguments. Symbolic checking preserves unknown lengths and rejects invalid unused templates, including type/value confusion and array literals whose length cannot be proved.
- [SEMANTIC-CACHE-1] Supported changed-source checks reuse independently owned checked function bodies with relocated spans, nodes, statements, locals and borrow metadata; failed checks or snapshot allocation failures do not replace the last complete snapshot.
- [SEMANTIC-CACHE-2] Declaration/type/import identities invalidate body reuse, generic/constant/alias configurations conservatively check fresh, and complete region/effect/codec passes rerun after every body edit.
- [SEMANTIC-CACHE-3] Cached source spans and node/statement identities must belong to unchanged mapped intervals and their function's tables; invalid relocation falls back instead of trusting stale references.

- [SEMANTIC-CACHE-4] Reusing a caller body never reuses transitive effect verdicts; a callee's new allocation rejects an unchanged noalloc caller.
- [SEMANTIC-CACHE-5] Failed cache publication releases only its pending snapshot; the previous successful function queries remain reusable after OutOfMemory.
- [SEMANTIC-CACHE-6] Project queries include module paths, import/export text, signatures and type catalogs, preserving fresh/cached diagnostics and execution through source relocation and changed module interfaces.
- [CALLBACK-1] Noncapturing function values have exact parameter/result signatures and declared effect ceilings, including parameter-dependent signatures in generic helpers. Creation stores an immediate function identity; invocation validates the target and preserves ordinary ownership/result obligations. Explicit readonly whole-value and slice context parameters borrow synchronously with existing alias and region checks; contexts cannot escape or be captured, and mutable parameters and reference results are rejected.

- [SEMANTIC-CALLBACK-1] Function-name values may infer callback schemas while checking bodies, so semantic body reuse stays disabled for these programs until snapshots can safely remap their inferred types. Fresh and changed-source callback execution retain identical signatures and outcomes.

- [STANDARD-TIME-RANDOM-1] Standard durations and Unix nanosecond instants use checked full-width arithmetic; SplitMix64 seeded state has stable word sequences and bounded rejection sampling with retained state on exhaustion.
- [STANDARD-TIME-RANDOM-2] Standard clock and entropy calls require explicit capabilities, retain typed provider failures, and report initialized byte prefixes on partial entropy failure; host allocation failure aborts normally.
- [STANDARD-TIME-RANDOM-3] Standard provider wrappers preserve source effect ceilings; rejection sampling honors the caller's maximum draw count and empty entropy fills perform no reads.

- [TYPE-ALIAS-SCHEMA-1] Exported transparent aliases retain their checked canonical target in public schemas and native interfaces, including scalar, array, chained and concrete generic targets.
- [STANDARD-MODULES-8] Borrowed map operations preserve the map owner; bounded vector append-many is unchanged on insufficient capacity, deduplication and filtering retain input order, and clear accepts empty vectors.
- [STANDARD-MODULES-9] Bounded hash tables handle collisions, tombstone reuse, replacement in full tables, and byte keys by content; full insertion preserves existing values and physical slot iteration is deterministic.
- [STDLIB-TEXT-DATA-1] Reserved text and data modules provide bounded byte builders, range-based splitting, ASCII whitespace trimming, base formatting, finite decimal conversion, endian codecs, canonical padded base64, hex, JSON construction and explicit argument token parsing. Builder failure consumes owned intermediate output and returns a typed error.
- [STDLIB-COMPOSITION-1] Text range splitting, borrowed byte-key hash tables and owned JSON builders compose in one checked module while retaining capacity errors and scoped borrows.
- [STANDARD-IO-1] `std_path` exposes strict relative byte-path validation, component/name/extension spans and bounded joining. Invalid paths never normalize into authority-bearing requests.
- [STANDARD-IO-2] `std_io` buffered readers and writers retain owned file state on success and recoverable failures, report partial progress, distinguish EOF from stalled providers, and preserve buffered bytes for retry. Bounded collection retains partial output and the first byte beyond its limit.
- [STANDARD-IO-3] `std_fs.open` translates typed modes to scoped provider requests and rejects invalid paths before acquisition. Supplied filesystem authority remains mandatory.

- [STANDARD-IO-4] Resource acquisition accepts fixed byte arrays or consumes an owned u8 buffer on either outcome. The provider receives a copied, call-bounded byte request; invalid value schemas reject before access.

- [STANDARD-IO-5] Invalid acquisition request schemas reject before reading or invoking provider memory.

- [OWNED-BUFFER-1] Storable buffer elements may own nested buffers but contain no must-handle results or external resources. Append/write consume input even on failure; take moves the selected value out using swap-removal; truncate only shrinks and releases each removed value. Owned elements cannot be copied through read, resize fill, or slices.
- [STANDARD-OWNED-COLLECTIONS-1] Owned vectors and linear maps move storable values through insertion, replacement, removal and destruction. Bounded insertion/replacement failure consumes the offered value, preserves existing values, and reports capacity/bounds errors; missing map keys return error 4.
- [OWNED-BUFFER-2] Owned element read, resize-fill, and slices are rejected in ordinary and generic code. Buffer elements cannot hide fallible results or filesystem/network owners inside arrays/records/unions.
- [OWNED-BUFFER-3] Owned insertions, helper mutation and take results retain allocator-origin restrictions; child arena owners cannot enter parent storage or escape through extraction.
- [OWNED-BUFFER-4] Bytecode buffer graphs recompute finite storage contracts rather than trusting supplied copy/storable flags; forged external-resource storage, cyclic ownership and owned-element slice instructions are invalid.
- [SCOPED-DIRECTORY-1] Read-authorized `m:path` metadata and `l:path` directory listing acquisitions publish bounded immutable byte snapshots under the existing directory grant. Empty paths denote that root only for these modes; intermediate/final directory traversal never follows symlinks, while final metadata reports a symlink itself.
- [SCOPED-DIRECTORY-2] Failed directory snapshot construction releases partial bytes and open directories before returning; allocation failures never publish a live snapshot handle.

- [STANDARD-DIRECTORY-1] Standard metadata and listing APIs decode versioned bounded copied streams into typed kinds, u64 size, entry counts and name spans, validating framing. Opaque backslash names remain enumerable even though strict path APIs will not open them; byte offsets never borrow provider memory.

## Application library parity

- [STANDARD-PARITY-1] std_order provides bounded lexicographic range-key heapsort, binary search, equal-run counts and min-priority heap operations over caller-owned Item slices; invalid sort ranges and full pushes leave storage unchanged; byte-key counters preserve their prior value on full or overflow.
- [STANDARD-PARITY-2] std_ascii matches explicit ASCII identifier classes and length bounds over integer slices; std_iter visits each distinct index pair once in lexicographic order without allocation.
- [STANDARD-PARITY-3] std_graph prepares caller-owned indegrees from bounded directed edges, reserves ready vertices, completes each once, and distinguishes finished and cyclically stalled graphs; state and edges must retain their prepared correspondence.
- [STANDARD-INTEGER-EXTREMA-1] std_math integer min/max compare exact values at every supported integer width without arithmetic overflow; min_or/max_or use an explicit fallback only for an empty slice and ignore it for nonempty slices. Existing F64 operations remain available.

## Ordinary JSON schema helpers

- [STANDARD-JSON-SCHEMA-1] Checked document-local JSON cursors iterate immediate array elements or object members in source order, skipping nested subtrees; empty cursors terminate and advancing an exhausted cursor is idempotent. Required fields distinguish absence from null. Integer and boolean defaults apply only to absent fields; present wrong kinds remain errors. Inclusive integer/count bounds and descriptor-based allowed object field checks preserve named type and bounds failures without changing parser strictness or application validation precedence.
- [STANDARD-CORPUS-TEXT-1] Bounded byte right-padding and span joining validate output limits and descriptor bounds before allocation; decoded JSON string materialization preserves full UTF-8 and embedded NUL with explicit absent, wrong-kind and bounds errors. Separately named absolute lexical path validation, component-prefix matching and bounded relative-suffix joining preserve all existing relative path contracts.
- [STANDARD-CORPUS-TEXT-2] Text materialization, padding, joining and absolute path builders release owned partial outputs when runtime allocation fails.

- [BORROW-SYNTAX-1] `borrow owner[..] as view` borrows all initialized elements of a buffer, fixed array or existing slice with existing slice safety rules. Comma-separated borrow clauses use independent per-clause mutability and lower left-to-right to lexical nested scopes; all aliases remain checked, later clauses observe earlier loans, and return/try/break/continue release loans in reverse order. Whole-value borrowing without brackets retains its existing meaning. Generic bodies enforce the same rules. Grouped scopes count toward the existing parser nesting bound.

- [CALLBACK-CONTEXT-1] Readonly callback contexts support whole values and slices, enforce synchronous lexical borrowing, preserve allocation-region provenance, and participate in generic checking and noalloc effect ceilings.
- [CALLBACK-ALGORITHMS-1] Generic context-aware sort_by uses bounded in-place heapsort; lower_bound_by searches under the same ordering and filter_by preserves retained order and capacity. JSON document contexts can compare node IDs directly.

## Bytecode execution

- [VM-AUDIT-1] Scalar-loop execution preserves results, exact instruction budgets and located traps across runtime representation optimizations.

- [VM-FUSION-1] Execution-local fused scalar and array-read sequences preserve original logical instruction counts, located traps, trace events and borrowed-local behavior; generic dispatch remains selectable for differential verification.
- [VM-FUSION-2] Fused dispatch falls back for locals whose active storage has moved into the borrowing store.
- [VM-FUSION-3] Requested bounded traces preserve original operation names, PCs, logical step counts and source spans under both dispatch settings.
- [VM-FUSION-4] Fusion metadata uses a fixed-size execution-local cache; every injected execution allocation failure releases all owned storage.

- [VM-FUSION-5] Scalar-only calls and returns preserve frame limits and results across frame-array growth; fusion cache collisions preserve original instruction identity.

- [VM-FUSION-6] Scalar fast paths reuse checked local bindings; invocation argument copies canonicalize integer representations and reject mismatched types before execution.

- [VM-TIMING-1] `run --timings` reports VM execution nanoseconds on stderr, including VM validation, setup and cleanup but excluding source compilation and result output. Timing preserves guest results, dispatch selection, quotas and runtime diagnostics; duplicate options and unsupported commands reject it.

- [VM-FUSION-7] Fused arithmetic chains preserve evaluation order, intermediate overflow/division traps, original source spans and every logical instruction-budget cutoff.

- [PHASE-TIMING-1] One-shot compiler commands and the raw byte I/O host accept opt-in `--timings=json`, emitting versioned phase-timings-v1 JSON Lines on stderr. Records use nonnegative duration_ns, explicit inclusive scope, available work counts and the command exit_code; total includes cleanup and excludes timing serialization. Attempted failing phases remain observable, stdout and default behavior are preserved, and legacy `--timings` remains compatible.
