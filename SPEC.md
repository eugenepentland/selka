# Compiler behavior specification

This document records implemented behavior with executable Zig regression evidence.
Each stable ID has one primary `// spec:` test. Additional tests and Python
acceptance drivers exercise further cases; these links are not a claim of exhaustive
coverage or proof of memory safety. The language remains experimental. Ownership
and resource behaviors below describe the VM unless native output is named.
The roadmap in `docs/experiments/roadmap.md` tracks unsupported and planned features.

## Core semantics

- [CORE-1] Evaluates multiplication before addition, honors parentheses, and associates subtraction from the left.
- [CORE-2] Reports checked arithmetic overflow at the responsible operator without evaluating arithmetic during checking.
- [CORE-3] Returns located source diagnostics for empty input, malformed syntax, and out-of-range integer literals.
- [CORE-4] Accepts the signed and unsigned integer width limits and rejects literals above each maximum.
- [CORE-5] Constructs records by field name and preserves original values when producing updated record copies.
- [CORE-6] Preserves fixed-array copies and accepts each integer index width, including zero-length arrays.
- [CORE-7] Rejects interchange between distinct nominal domains and requires their declared construction operations.
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

- [GENERIC-SYNTAX-1] Generic syntax retains named type parameters, nonempty explicit requirement lists, and explicit `::<...>` call type arguments through owned AST copying and formatting; duplicate parameters/requirements and lists beyond 16 are rejected. Executable specialization must preserve these annotations through contract validation before lowering.

- [GENERIC-REQUIREMENTS-1] Builtin generic requirements are copy, equality, and integer, with integer implying equality and equality implying copy. Matching uses concrete equality rules and forbids implicit copying of owners or pending results; nominal integer-backed domains are not integers. Unknown requirement names and builtin type-variable shadowing are diagnosed even in uncalled templates before specialization.

- [GENERIC-BODY-1] The initial abstract generic body checker keeps type parameters distinct and requires declared integer/equality support for the corresponding operations. It checks pure builtin/type-parameter signatures, locals, returns, branches, loops, and casts without substituting representative concrete types. Unsupported forms and 256-depth/100000-work bounds reject explicitly; concrete specialization must retain these universal checks.

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

- [GENERIC-PROVIDER-1] Abstract generic provider operations enforce concrete result contracts, exact capability kinds and byte/slice inputs before instantiation. Resource I/O requires a mutable unconsumed owner after argument evaluation; read slices require exclusive u8 views. Acquisition/completion preserve resource ownership and permission attenuation cannot create authority. Direct clock/random/environment/filesystem/network effects propagate through helper calls and enforce bounds even in uncalled or unreachable source paths.

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
