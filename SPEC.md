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

- [GENERIC-SYNTAX-1] Generic syntax retains named type parameters, nonempty explicit requirement lists, and explicit `::<...>` call type arguments through owned AST copying and formatting; duplicate parameters/requirements and lists beyond 16 are rejected. Executable specialization remains unsupported and must reject rather than erase these annotations.

- [GENERIC-REQUIREMENTS-1] Builtin generic requirements are copy, equality, and integer, with integer implying equality and equality implying copy. Matching uses concrete equality rules and forbids implicit copying of owners or pending results; nominal integer-backed domains are not integers. Unknown requirement names and builtin type-variable shadowing are diagnosed even in uncalled templates before specialization rejection.

- [GENERIC-BODY-1] The initial abstract generic body checker keeps type parameters distinct and requires declared integer/equality support for the corresponding operations. It checks pure builtin/type-parameter signatures, locals, returns, branches, loops, and casts without substituting representative concrete types. Unsupported forms and 256-depth/100000-work bounds reject explicitly; executable specialization remains unsupported.
