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
