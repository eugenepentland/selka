# Compiler behavior specification

This document records implemented behavior with executable Zig regression evidence.
Each stable ID has one primary `// spec:` test. Additional tests and Python
acceptance drivers exercise further cases; these links are not a claim of exhaustive
coverage or proof of memory safety. The language remains experimental. The QBE
native backend is the only runtime: every behavior below is native behavior, and
bytecode names the internal IR it consumes rather than anything that is executed.
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
- [CORE-10] Rejects silent result abandonment and permits `_ = value` to release the result obligation explicitly. A diagnostic about a binding that cannot be assigned or modified names that rule rather than a declaration keyword.
- [CORE-11] Unwraps successful results and propagates compatible error payloads by case name across nominal result types. Native propagation constructs the outgoing result before releasing unfinished operands; failed construction releases the propagated payload before those operands.
## Ownership and capabilities

- [OWN-9] Releases previously acquired resources exactly once when a later acquisition propagates an error.
- [OWN-10] Delegates environment access through explicit grants and distinguishes missing, empty, and present values.
- [OWN-11] Rejects direct and transitive allocation that violates declared effect bounds and reports a call witness.
## Projects and native output

- [QBE-1] Emits deterministic independent QBE native function units with stable symbols and body-local instructions; unrelated body edits and declaration reordering preserve unchanged units. Unsupported native features fail before publishing output.
- [QBE-2] Builds Linux x86-64 executables and shared libraries directly through the Zig CLI without Python or a compiler source checkout; bundled runtime inputs, verified object reuse, source diagnostics, and native API adapters preserve native build behavior. The generated entry adapter and each guest function are separately cached objects, the fixed runtime translation units are archived once per build environment and linked after every object that can reference them, and section-level collection drops runtime a program never reaches. A stored object or archive is reused only when a fingerprint over its length and contents matches, so damaged bytes or a damaged fingerprint rebuild that one entry; an unchanged executable is republished by comparing length and then bytes, retaining its inode and modification time. `--run` executes a temporary native binary with inherited I/O and propagated status, then removes it while retaining cached objects. Shared-library links also bind the library's own data-descriptor symbols internally, so a guest object's non-PIC references resolve within the library instead of failing as preemptible relocations.
- [NATIVE-BUILD-RECLAIM-1] A native build owns its filesystem and process scratch in a reclaiming arena freed when the build ends, over the general allocator rather than the process arena, so a long-lived host that rebuilds its guest on every reload does not accumulate build memory.
- [QBE-HOST-COMPILER-1] A native build emits its guest's QBE units through its own executable by default (`/proc/self/exe emit-project-qbe`); `MYLANG_HOST_COMPILER` overrides that frontend with an explicit compiler, which a host application driven from a binary that is not itself a compiler supplies. `MYLANG_QBE` and `MYLANG_ZIG` likewise name the native tools when neither a flag, a tool beside the compiler, nor `PATH` locates them.
- [QBE-3] The compiler bundles only the native runtime build inputs — its runtime C sources and headers and the Zig runtime units it compiles, with their reference closure — never compiler tests or guest fixtures. A build materializes that tree once per build-time content hash under `<cache-dir>/runtime/<hash>`, staging into a private directory and renaming so concurrent builds sharing a cache never observe a partial tree, and reuses it on every later build.
- [QBE-4] Native builds identify their inputs without rereading them: the compiler's own identity is a build-time digest of its sources, the Zig toolchain and the optimize mode, and external tools are identified by path, size and modification time. Object-cache keys still change when the compiler, runtime, tools, target or mode change. Build tools resolve from an explicit option, then beside the compiler's own executable, then `PATH`; the working directory never selects one.

- [EXPORT-PLACEMENT-1] Explicit `export Name;` directives may appear anywhere among top-level declarations after the module/import header. Discovery collects them in source order with original locations; duplicate and unknown exports and private interface leaks still reject. Exports inside function or type bodies reject, and formatting preserves directive order and comments.

- [PROJ-1] Loads shared module dependencies once in dependency order and releases state on allocation failure.
- [PROJ-2] Reports module cycles with both the importing location and the related source location.
- [PROJ-3] Rejects duplicate exports, missing exported symbols, and private types exposed through public interfaces.
- [PROJ-4] Reports related declarations in their original source files after project source mapping.
## Discovery and formatting

- [TOOL-1] Groups exact duplicate bodies after binding renaming while preserving resolved binding identity.
- [TOOL-2] Reports literal differences once per exact-group representative when discovering near duplicates.
- [TOOL-3] Reports incomplete near-duplicate discovery when work budgets are exhausted and rejects invalid budgets.
- [TOOL-5] `fmt` permits semantically incomplete drafts but rejects syntactically invalid input, and returns an accepted program byte for byte, because its indentation already is its canonical layout.
- [TOOL-6] Includes calls in untaken paths and cycles when calculating static function reachability.
## Evaluation and wire boundaries

- [WIRE-2] Rejects duplicate input names, keywords, unsupported input types, and noncanonical or out-of-range values.
- [WIRE-3] Encodes independently constructed typed values without consuming them and enforces byte, value, and depth limits.
- [WIRE-4] Rejects duplicate, missing, unknown, and private function entries in domain codec declarations.
## Command line

- [DECLARATION-LIST-1] `list-declarations` prints one parse-only `declarations-v1` JSON document with the declared module name or null for a single-file program, its import names and explicit aliases, its export directives, and every top-level declaration's kind, name, export flag, byte range and attached comment start. The kinds are exactly the top-level constructs the parser accepts: alias, const, struct, enum, union, result, domain, resource, fn and host_fn. An export directive sets the named declaration's flag; unknown and duplicate export directives reject with the existing located diagnostics. Listing requires only parsing, so modules with type or ownership errors still list, and no name resolution, checking or execution is claimed.

- [DECLARATION-LIST-2] Listed byte ranges are zero-based, half-open, disjoint and ordered by start. A declaration runs from its first token through its terminating semicolon or final token before an implicit newline/EOF terminator, and its comment start covers contiguous leading `#` lines with no blank line before the declaration. The module header, import statements, export directives and comment-and-declaration ranges account for every byte of the file except whitespace and line comments between them.

- [DEPENDENCIES-1] `project-dependencies` emits a versioned checked module graph with resolved imports, source byte hashes, implementation identity and exact consumed generated-input manifest hashes. It does not execute guest code; invalid projects emit no complete receipt.

- [DISK-PROJECT-1] Interpreter application hosts load `main.my` and imported modules from an explicit disk directory, with bounded reads and no embedded-source fallback. Failed loads and compilation release owned storage and preserve located source errors; a later invocation reads repaired source. Existing typed host registrations remain mandatory. The standalone acceptance driver also changes guest source and project roots using the same executable without Zig or Guardian on PATH.

- [CLI-1] Distinguishes source errors, runtime traps, and invalid command usage through actual process results.
- [CLI-2] Reports missing arguments and missing source files as usage or host failures.
- [CLI-3] Executes the plan acceptance programs and recursive functions through the command-line executable.
- [CLI-4] Schema generation reads declared input manifests into generated modules on every invocation and rejects malformed or duplicate inputs. A generated module is ordinary source — a `#` provenance comment, a `module` line, `export` directives and one `def` per value — and spells a boolean `True`/`False` even though its manifest spells it the way JSON does.

- [CACHE-1] Reusing unchanged module syntax preserves fresh semantic checks and changed results, with independent returned storage and bounded cache retention.
- [CLI-5] Persistent checking sessions reuse unchanged parses and allow clearing retained cache storage between requests.








- [NOMINAL-TYPE-SYNTAX-1] Nominal declarations retain explicit type parameters and requirements; nested named applications retain base and argument spans through parsing, formatting, syntax caching and module relocation. Lists are bounded at 16 and nesting at 256; module interfaces check exported type privacy, constructor kind, application arity and parameter shadowing. Malformed nominal declarations follow NOMINAL-TEMPLATE-CHECK-1; concrete specialization follows NOMINAL-INSTANCE-1.
- [GENERIC-SYNTAX-1] Generic syntax retains named type parameters, nonempty explicit requirement lists, and explicit `[...]` call type arguments through owned AST copying and formatting; duplicate parameters/requirements and lists beyond 16 are rejected. A specialized instance is named `f[i64]` after the arguments it was given, so a diagnostic and a disassembly name it the way its call site is written. Executable specialization must preserve these annotations through contract validation before lowering.

- [NOMINAL-INSTANCE-1] Concrete nominal records, unions, results and enums specialize by declaration and ordered semantic argument identities into complete runtime schemas. Construction, assignment, matching, result handling and owned-field flow use the ordinary checked IR/VM rules; concrete types compose with existing generic functions and numeric arrays. Unused templates and unexpanded phantom arguments do not become empty runtime records. Public type lookup requires exported bases and visible arguments, including phantom arguments. Symbolic nominal uses in generic function bodies follow NOMINAL-BODY-1. Canonical type display names have a 1 MiB compilation budget, and schema export of a generic type constructor remains explicitly unsupported pending generic tooling.
- [NOMINAL-LAYOUT-1] Nominal declarations, including unused templates, have bounded finite storage graphs before executable specialization. Canonical symbolic identities preserve declaration, parameter scope and ordered arguments. Only stored fields/payloads and array elements expand; phantom arguments do not create storage edges. Even zero-length arrays retain the existing finite-type rule. Cycles reject with E_RECURSIVE_RECORD and original closing-edge/related locations; growing families reject with E_GENERIC_LIMIT at 4096 nominal instances, 4096 array shapes or 100000 expansion operations. Graph IDs are not runtime type IDs and do not authorize execution.
- [NOMINAL-TEMPLATE-CHECK-1] Nominal declaration metadata resolves field and payload expressions to declaration identities and local parameters even in unused templates. It rejects unknown types, shadowing, duplicate members, malformed result schemas, application arity/kind errors and insufficient argument requirements. Copy guarantees propagate through ordinary and generic records/unions without copying owners or pending results; scalar domains and enums retain equality without integer operations. Expression checking is bounded at 256 levels and 100000 visits. Metadata is not an executable layout: finite storage dependencies follow NOMINAL-LAYOUT-1; concrete instances follow NOMINAL-INSTANCE-1; symbolic nominal operations in generic function bodies follow NOMINAL-BODY-1.
- [GENERIC-REQUIREMENTS-1] Builtin generic requirements are copy, equality, and integer, with integer implying equality and equality implying copy. Matching uses concrete equality rules and forbids implicit copying of owners or pending results; nominal integer-backed domains are not integers. Unknown requirement names and builtin type-variable shadowing are diagnosed even in uncalled templates before specialization.

- [GENERIC-BODY-1] The initial abstract generic body checker keeps type parameters distinct and requires declared integer/equality support for the corresponding operations. It checks pure builtin/type-parameter signatures, locals, returns, branches, loops, and casts without substituting representative concrete types. Unsupported forms and 256-depth/100000-work bounds reject explicitly; concrete specialization must retain these universal checks.

- [GENERIC-ARRAY-1] Fixed numeric arrays may contain generic type parameters in signatures, constructors, annotations, nested arrays and explicit type arguments. Universal checking retains element requirements, exact lengths, nominal identities, copy/result obligations and source-located traps before specialization. Concrete shapes are interned by element identity and length, with bounded specialization; symbolic enum-keyed tables and parameterized lengths remain explicitly unsupported.
- [GENERIC-CALL-1] Abstract calls between pure generic templates resolve declaration identities and domain/module privacy, require complete explicit or uniquely inferred type arguments and value-argument arity, enforce requirement implication, and substitute parameter/result identities without merging distinct type variables. Recursive calls check signatures without expanding bodies; reachable concrete helpers must also pass the abstract pure-body rules.

- [GENERIC-HELPER-1] Abstract generic checking validates every transitively called ordinary helper against the supported pure builtin body rules. A bounded declaration worklist checks each reachable body once, including recursive cycles; uncalled ordinary bodies are left to concrete checking. Helper signatures alone cannot authorize hidden effects. Broader effect and ownership contracts remain unfinished.

- [GENERIC-INSTANCE-1] The compilation-local specialization registry interns resolved declaration identities and ordered concrete type identities, owns argument storage, preserves IDs across growth and allocation failure, and reuses recursive requests. It bounds discovery at 4096 entries and each argument list at 16. Nominal types remain distinct regardless of representation. Executable checking uses these identities without conflating them with source declaration ordinals.

- [GENERIC-EXECUTION-1] Pure generic templates specialize on explicit or uniquely inferred concrete type arguments after universal body validation. Repeated and recursive calls reuse instances; per-instance bindings, expression resolution, widths and nominal types remain distinct. Ordinary entry/export wrappers execute instances through the checked native backend. Internal instances are excluded from direct module export/schema roots. Main cannot be generic; unsupported abstract forms still reject.





- [GENERIC-DIAGNOSTIC-1] Checked specializations retain explicit ordered concrete type arguments. Human-readable function names include those types, preserve qualified nominal names, and do not depend on discovery ordinals. Traces and reports use these names, while public-root selection uses specialization metadata rather than spelling.








- [SOURCE-CODEC-1] `codec_decode[Domain](wire)` returns the declared decoder's typed result and `codec_encode[Domain](value)` returns its declared wire value. Both resolve through explicit domain codec contracts and preserve ordinary call typing, ownership, effects, runtime budgets and source diagnostics. They do not expose backing construction or provide JSON byte serialization.

- [CHECK-CACHE-1] A persistent checking session may reuse a successful verdict only after fresh project and manifest loading and exact comparison of every loaded module name, path and source byte. Hits replay owned warnings and skip interface/semantic work; failures are never retained. Retention is bounded and clear drops syntax and verdict caches while preserving cumulative observations.

- [GENERIC-CONCRETE-1] Abstract generic checking resolves concrete copyable nominal and fixed-array schemas without conflating them with type parameters. Concrete record/array construction and projection obey declared field, element and index types; malformed uncalled templates reject. Concrete owned flow follows GENERIC-OWNED-1; individual runtime operations require their own abstract rules. Concrete result obligations follow GENERIC-RESULT-1.

- [GENERIC-UPDATE-1] Generic bodies may update concrete copyable records and replace fixed-array/table elements. Field uniqueness and field/element/index types are checked before instantiation; normal specialization preserves immutable snapshots, evaluation order and runtime bounds. These operations do not infer structural capabilities for symbolic parameters.

- [GENERIC-VARIANT-1] Abstract generic checking supports construction and exhaustive matching of concrete copyable enums/unions. Cases retain nominal identities and exact payload types; each arm scopes its payload independently, duplicate/missing cases reject, and a match terminates only when every arm terminates. Named enum-table construction requires every key exactly once. Result-bearing variants follow GENERIC-RESULT-1; runtime-owned value flow follows GENERIC-OWNED-1.

- [GENERIC-RESULT-1] Abstract checking of concrete result-bearing generic values enforces single transfer, explicit handling, scope/return obligations, and agreement across continuing branches, match arms, loops and short-circuit paths before instantiation. Nested payloads retain obligations and aggregate operations cannot erase siblings or replaced results. Propagation requires compatible concrete result errors and rejects live result bindings or previously evaluated result temporaries on its early-return path. An explicit `_ =` release evaluates its operand. Symbolic result type constructors remain pending.



- [GENERIC-CLEANUP-1] Concrete resource ownership passed through generic functions retains its provider lifecycle. Explicit partial extraction/drop and implicit scope cleanup release each live resource exactly once, including allocation failures and traps; forwarding does not complete or duplicate an external resource.


- [GENERIC-PROVIDER-1] Abstract generic provider operations enforce concrete or symbolic nominal result contracts, exact capability kinds and fixed byte-array inputs before instantiation. Resource I/O requires a mutable unconsumed owner after argument evaluation. Acquisition/completion preserve resource ownership and permission attenuation cannot create authority. Direct clock/random/environment/filesystem/network effects propagate through helper calls and enforce bounds even in uncalled or unreachable source paths.

- [GENERIC-PROVIDER-EXEC-1] Generic provider execution preserves ordinary callback values/counts, bounded output bytes, typed failures, retry ownership and cleanup under allocation failure. Short-circuit paths remain unevaluated at runtime while their possible effects remain statically checked.






- [DIAGNOSTIC-JSON-1] CLI --diagnostics=json selects diagnostic-v1 JSON Lines on stderr without changing command results or exit statuses. Source and VM diagnostics preserve stable codes, severity, original-file byte ranges and byte-based line/columns, related/origin/requirement notes, bounded frames and omitted-frame counts. Project-loader related sites retain their own module coordinates. Auxiliary CLI messages are separate message records. Successful check-session warning replay uses the selected format, and cache identity prevents cross-format replay. Default text remains available; invalid command-line syntax and emergency output failures may use text.


- [HOST-SOURCE-1] Contextual host fn declarations have no guest body and require an explicit effects(host, ...) contract. Only ordinary top-level, non-generic copied data signatures are supported; capabilities, managed collections and runtime-owned graphs reject. Main retains a guest body. Host and additional declared effects propagate through ordinary and abstract generic calls, including uncalled templates. Effect-free evaluation/invocation cannot execute these calls. Modules, formatting and disassembly preserve declarations; duplicate discovery excludes external implementations.


- [BOARD-TRIAL-1] The bounded board-validation experiment runs its guest as a native executable with a trusted geometry provider linked into it, compares deterministic reports and callback counts with an independent fixed oracle and standalone Zig implementation, and releases snapshot and callback graphs on allocation failure.

- [NOMINAL-BODY-1] Generic bodies retain nominal declaration identity and ordered symbolic arguments, check fields and payloads before calls, and preserve construction, assignment, exhaustive matches, named result propagation, partial ownership and cleanup effects. Substitution and late VM catalog materialization retain stable type IDs and reuse existing numeric array shapes. Phantom arguments retain identity without contributing stored-value contracts. Shape traversal uses an explicit stack and the generic checking work budget; argument-growing runtime specialization remains bounded by the nominal graph/name limits. Ordinary unconstrained type parameters still require structural constraints for member operations. Provider-specific symbolic shapes follow NOMINAL-PROVIDER-1; public generic schema tooling remains pending.

- [NOMINAL-PROVIDER-1] Generic resource/environment operations accept symbolic nominal result and payload records only when their exact named fields satisfy the ordinary provider contract for every permitted substitution. Declaration order does not affect meaning. Byte inputs and output arrays must have known u8 elements and numeric lengths; a general integer parameter is insufficient. Concrete and symbolic checking share named contract definitions. Resource identity, authority, mutable access, handling, cleanup and effect checks remain enforced before calls. VM specialization preserves bounded bytes, absent environment values, partial I/O, failed-completion ownership and cleanup under allocation failure or instruction traps.

- [GENERIC-CODEC-1] Generic bodies may invoke codec_encode/codec_decode for explicitly concrete domains, resolving the declared method and checking exact value types, arity, result obligations and transitive effects. Reachable factories/accessors are checked with their declaring domain's representation privacy, including module relocation. wrap/unwrap require that exact declaring domain; private methods remain inaccessible outside it. A codec operation on a type parameter rejects until a codec constraint is declared by a future language extension.

- [BOARD-ABSTRACTION-1] The board trial uses a shared Slot<T:copy> for optional IDs, regions, features and first violations, and one equality-constrained membership helper for component/net IDs. Typed snapshots preserve each instantiated slot's exact payload identity; a NetId payload cannot enter a component slot. Consolidation preserves the fixed board contract, oracle results, callback counts and repair fixture failure/restoration behavior.

## Interpreted schematic pilot

- [SCHEMATIC-1] The guest S-expression parser, circuit model, interface expansion and SVG renderer execute in the bytecode VM. A typed scalar host boundary exposes only bounded UTF-8 source bytes and unpublished output. Invalid inputs, unsupported forms, incomplete or duplicate pads and invalid ports reject without publishing partial SVG. The pilot supports one parameterless module with one 41-pad IC and supported two-terminal primitives; its documented limits and metadata exclusions are not a general Netlisp evaluator or electrical sign-off.


- [NAVIGATION-1] Compiler navigation indexes module-qualified declaration identities, original source ranges, signatures, effects, concrete call/read/write/field/type relationships and bounded source excerpts without VM execution. Every result carries compiler and loaded-source identities. Static relationships do not establish runtime coverage. Failed body checking emits declarations without checked relationships; lexical recovery after body syntax errors emits explicitly unchecked candidates.
- [GENERIC-API-1] Checked public schemas expose generic templates separately from concrete callable functions and data types, preserving parameter requirements, symbolic signatures, fields/cases, module import scope, effect contracts and source identity. Templates require explicit specialization and cannot be invoked as concrete values through the JSON API.
- [STRUCTURAL-FIELD-1] Copy-constrained function parameters may require named fields with exact named types, including another declared type parameter. Concrete satisfaction and symbolic forwarding preserve nominal identity and checked field reads/updates. Structural fields do not expose opaque domain backing or permit incomplete construction of an unknown record.
- [STRUCTURAL-OP-1] Function parameters may require public nongeneric domain operations with explicit parameter/result types and an effect ceiling. Type-owned generic calls check declared contracts before specialization; concrete operations must satisfy signature, visibility and effects.
- [STRUCTURAL-LIMIT-1] Structural requirements currently apply to function templates with copy guarantees and named type expressions. Nominal type declarations and unknown complete constructors reject explicitly.
- [INCREMENTAL-CAPACITY-1] The syntax cache retains at most 256 modules within its unchanged byte budget; edits can reuse exact unchanged module syntax while complete semantic checking and diagnostic equivalence remain required.


### Disk application raw byte host

- [BYTE-IO-1] The raw byte host preserves arbitrary input, enforces bounds and publishes output only on successful guest exit. Its operations are a trusted native provider compiled into the guest's own executable, which buffers output where only the driver can publish it.

The `mylang-io --project DIRECTORY` host compiles `main.my` and its imports from
disk into bytecode. It supplies only `io::length() -> i64`,
`io::byte(index: i64) -> u8`, and `io::put(value: u8) -> i64`, each with host effects.
Input bytes are passed untouched, including invalid UTF-8 and NUL. The guest owns
parsing, validation, algorithms, and serialization. Input is bounded at 2 MiB;
output at 128 MiB; a put returns zero on success. Negative/out-of-range reads and
output exhaustion fail the host call. Output is published only after guest main
returns zero, never after traps or nonzero exits. The host supplies no external
filesystem, network, environment or process authority to the guest. Host calls/work
are bounded at 300 million each and guest execution at 2 billion steps; the coordinator
also enforces wall/CPU/memory limits. The executable is built outside application
sessions; editing guest files requires no Zig rebuild or language Guardian run.

- [STANDARD-MODULES-1] Reserved standard sources load identically through all project providers and participate in source budgets, dependency graphs and digests. They are ordinary Python-syntax guest modules over managed types and may import one another.

- [PLAIN-JSON-1] The strict document parser produces a checked i64 tape for a JSON text. It rejects duplicate decoded keys, invalid Unicode, integers outside i64, nonfinite numbers, trailing data and container depth over 64. Its byte budget is at most 1 MiB; scratch and output allocation remain bounded.
- [PLAIN-JSON-2] Ordinary JSON validation applies to every subtree, including unused fields: decoded duplicate keys, malformed UTF-8, out-of-range integers, nonfinite floats, trailing bytes and excessive nesting reject.
- [PLAIN-JSON-3] Failed document parsing releases partially allocated DOM, tape and text storage.
- [STANDARD-MODULES-2] Embedded standard source bytes count against the same per-file and total project source budgets as user modules.

## Guest application test tool

- [NATIVE-TEST-1] `mylang test` checks the project, discovers exported `test_` functions, validates named typed JSON inputs, and compares native results structurally. Boolean results default to true; other types require expectations. Filters and reasoned skips never turn an empty or all-skipped selection into success. Each execution uses a fresh bounded native process without implicit host grants.
- [NATIVE-TEST-2] Successful deterministic tests may reuse verified receipts keyed by semantic dependency closure, call signature, relevant layouts, case settings, execution limits, and tool/runtime identity. That identity follows QBE-4: the compiler's embedded build-time digest, and path, size and modification time for external tools, rather than rereading executables on every run. Whitespace and unrelated body edits preserve valid results; affected helper edits invalidate consumers. Corrupt receipts are misses; failed or externally effectful executions are not reused. `--force` executes selected unskipped tests.
- [NATIVE-TEST-3] Provider fixtures replace only existing dependency sources in private bounded snapshots, preserve the selected test signature and exported types, and never edit originals. Source/compiler changes invalidate the run before result publication. Native reports distinguish passed, cached, failed, and skipped cases; setup failures exit 2 and empty/all-skipped selections exit 3.
- [NATIVE-TEST-4] A directory argument selects every `.my` program beneath it in sorted order, skipping generated trees, and runs one bounded child command per program across the machine's cores. Child reports merge into one case listing, one count summary and the most severe exit status, and children share the object cache and receipt directory so an unchanged program reuses its results instead of rebuilding. A filter carrying no `*`, `?` or `[` matches any substring of a qualified test name; one carrying them keeps shell-style wildcard semantics. A per-case configuration file is rejected for a directory run, because its keys name the tests of one project.

## Guest memory ceilings

- [MEMORY-CEILING-1] Every process that runs guest code runs under a byte ceiling. The soft ceiling is the managed heap's own budget: an allocation that would exceed it after a collection traps with `R_MEMORY_BUDGET`, "memory budget exhausted", and exit status 1, rather than growing. The ceiling travels in `MYLANG_MEMORY_LIMIT` as bytes with an optional `K`, `M` or `G` suffix, so no spawner needs a new argument ABI and a program started by hand under an exported variable is bounded the same way; malformed text refuses the run instead of leaving it unbounded, and zero removes the ceiling. `--max-memory=BYTES` on `run`, `build --run` and `test` outranks the variable, which outranks the built-in default: 512 MiB for one test child, 4 GiB for `run` and `build --run`. A resolved test ceiling is part of a receipt key, so changing it re-executes rather than reuses.
- [MEMORY-CEILING-2] Behind the soft ceiling the runtime caps its own address space with `RLIMIT_AS` at the budget plus fixed headroom, before its first allocation, so a runtime defect cannot outgrow the budget. It never loosens a tighter ceiling already in force and installs none under a sanitizer, whose shadow mapping reserves more address space than any budget allows. The compiler bounds itself the same way at start-up, at 8 GiB unless `MYLANG_HOST_MEMORY_LIMIT` says otherwise, and the tools a native build spawns complete under the inherited ceiling. Every host that runs a guest in its own process — the byte runner, the board trial and the schematic renderer — installs that same ceiling before it runs anything, because there a runaway guest is a runaway host.
- [MEMORY-CEILING-3] A directory test run fans out over the cores the machine has, further limited by how many per-child ceilings its reported free memory holds, so a cold run on a loaded machine waits instead of oversubscribing. `--jobs N` outranks `MYLANG_JOBS`, which outranks that derived width; zero and non-numeric widths are rejected, the width never exceeds the programs there are to run, and it is never less than one.

See `docs/experiments/guest-tests.md` and `tests/native_test_cli.py`.

## Installed feature identity

- [FEATURE-REPORT-1] `mylang --features` reports `language-features-v1`, the compiler
identity, pinned Zig version and embedded feature/restriction manifest, without reading
its own executable. `compiler_sha256` is that identity: a build-time SHA-256 over the
compiler's source inputs, Zig version and optimize mode, embedded when the compiler is
built. The same identity appears in every receipt's `implementation`, so a receipt and a
feature report from one compiler always agree. The current reference is
`docs/current-language.md`; historical checkpoint prose does not supersede it. The
manifest records implementation coverage, not a test certificate.
- [FEATURE-REPORT-2] The manifest's `implemented` section is a JSON object keyed by feature
slug. Every entry carries `kind`, either `language` or `tooling`, a one-line `summary`, and a
`doc` pointer of the form `<page>.md#<heading-anchor>` naming the documentation section that
demonstrates the feature. A slug that stops describing a real form moves to `removed` with a
date and a note rather than disappearing.
- [DOCCOV-1] `mylang doc-coverage [<repo-root>]` resolves every implemented feature's `doc`
pointer against that checkout. A pointer without an anchor, a page that does not exist, a page
reached through a `..` component, a page under `docs/legacy/` whose examples the runner never
executes, and an anchor matching no heading are all reported failures.
A heading's anchor is its text lowercased with punctuation dropped, spaces turned into hyphens,
and hyphens and underscores kept; its section runs to the next heading of the same or higher
level, and headings inside fenced blocks are not headings. A `language` section must contain a
fence tagged `mylang` or `my` that the documentation runner executes — one tagged
`# doc: skip` or `# doc: not-mylang` does not count. A `tooling` section must contain a fence
tagged `bash`, `sh`, `console` or `text`, or an executable program fence.
- [DOCCOV-2] Every `export` of every `src/stdlib/*.my` module must be named as a whole word in
that module's `## <module>` section of `docs/standard-library.md`, every such section must
carry an executed example, and every exported definition must have a `#` comment line directly
above it in the module source.
- [DOCCOV-3] The command prints per-page feature counts, the standard-module and export totals,
and one line per failure, then a failure count. It exits 0 only when nothing failed, 1 when
anything is undocumented, and 2 for an unusable command line. A missing or malformed
`features.json`, an unreadable page and an unlistable `src/stdlib` are reported as failures
rather than host errors. `zig build test-doc-coverage` runs it, and the default `test` step
depends on it.
- [DIAGNOSTIC-RECOVERY-1] Semantic checking recovers at ordinary and symbolic function boundaries after a source error, reports independent function faults in source order, and deduplicates repeated errors at the same source range and code. It stops within the failed function and skips whole-program verification when any body is incomplete; syntax, type-catalog, and namespace construction remain prerequisites. A failed check never publishes typed code or permits execution. Repeating a failed compilation check preserves diagnostics rather than appending duplicates.

## Proven parameter return regions

- [STANDARD-MODULES-7] Standard generic Result values retain the language's must-handle obligation; an ignored fallible result is a source error.

- [BYTE-IO-BULK-1] The byte application host optionally registers io::read_block(i64)->Block and io::write_block(Block)->i64 for a copied plain Block with bytes:[256]u8 followed by count:i64. Reads return up to 256 useful bytes with zero padding, count zero at EOF, and reject offsets outside [0,input length]. Writes reject counts outside [0,256], append up to remaining unpublished output capacity, and return the accepted count. Each call charges one work unit plus transferred bytes before mutation; a work failure never appends a partial block. The block's record and array shapes are validated against the emitted native host metadata before any callback is linked, and declaring only one of the pair rejects. Existing scalar declarations remain compatible. Output is published only after successful guest exit.
- [BYTE-IO-LIMITS-1] mylang-io accepts unique decimal --max-input, --max-output, --max-steps, --max-calls and --max-work values using = syntax after --project DIRECTORY. It also accepts unique --qbe=, --zig= and --cache-dir= paths for the native build, preferring an explicit path, then the environment, then the tools this build produced. Input/output limits may be zero; execution budgets must be positive. Unknown flags, duplicate limits, non-decimal values and overflow reject before invocation. The configured input limit, output publication capacity and guest call/work budgets are enforced without changing default limits.

- [SCOPED-PROVIDERS-1] Packaged resource adapters accept only relative normal path components under an open directory and exact configured numeric TCP endpoints. Read-only acquisition rejects write/create/truncate modes before effects; network adapters do not resolve DNS or follow redirects.
- [SCOPED-PROVIDERS-2] Directory adapters reject symlink path components, create exclusively, truncate only opened regular files, report actual partial I/O and close all provider handles when their stores end. The host keeps directory and endpoint grants alive until provider stores close.
- [SCOPED-PROVIDERS-3] The packaged synchronous TCP adapter connects only after an exact endpoint grant match, transfers bounded byte chunks with reported progress, and closes the connection on completion or cleanup.

- [SCOPED-PROVIDERS-4] mylang-io provisions directory and numeric endpoint capabilities only with explicit --allow-dir=PATH and --allow-endpoint=IP:PORT arguments; directories default to read-only and --allow-write requires a directory grant. Unknown, duplicate directory, invalid endpoint and unscoped write grants reject before invocation.

- [LOOP-EXIT-1] break and continue are terminating statements targeting the nearest enclosing while loop. They reject outside loops, retain must-handle obligations, conservatively preserve ownership of outer locals, and release exited owned values and nested managed arenas before jumping. Generic bodies enforce the same contracts. Loops remain conservatively fallthrough-capable for return checking.

- [CONSTANT-1] Module-level const NAME: TYPE = EXPR declarations define immutable builtin integer or bool values. Initializers use literals, scalar casts/operators and visible constants with acyclic forward dependencies; allocation and external effects are excluded even in untaken operands; SOURCE-EVAL-1 adds bounded scalar source-function calls. Checking evaluates with width/overflow/division validation and bounded depth/work before emitting literal getters. Normal short-circuit evaluation applies after syntax/dependency validation. Exports and imported names use ordinary privacy checks; generic functions may read constants.

- [FOR-RANGE-1] for NAME in START..END iterates a half-open ascending range of matching integer types with an immutable scoped binding. Bounds evaluate once left-to-right; empty/reversed ranges execute no body. Continue performs the hidden checked increment before the next condition; break skips it. Generic ranges retain integer requirements and the same ownership cleanup rules as while.


- [TYPE-ALIAS-1] type NAME = TYPE declares a transparent non-parameterized alias for an existing scalar, aggregate, fixed array or concrete nominal application. Alias chains support forward references and reject cycles or declaration conflicts. They preserve target nominal identity, ownership and result obligations; they never unwrap domains. Exported aliases obey interface visibility checks and private aliases cannot be named across modules. Constants accept aliases of supported scalar types.



## Runtime requested-byte accounting

- [RUNTIME-BYTES-1] Embedded allocation budgets support child quotas clamped to the parent limit. Child allocations and resize/remap operations charge both live-byte limits; failed acquisitions do not charge storage; release restores live accounting and retains peak statistics. Accounting objects must outlive every allocation made through them.
- [INTEGER-EXTENDED-1] Named integer bitwise operations, shifts, wrapping and saturating arithmetic use declared widths; invalid shift counts trap identically across optimization modes.

## Explicit implementation obligations

- [TYPED-HOLES-1] `todo[T]()` declares an unresolved implementation obligation with a checked required type and a located `E_TYPED_HOLE` diagnostic plus related type span. Ordinary and uncalled generic function bodies report independent holes at safe recovery boundaries. Formatting retains them. No checked program, bytecode or executable is published until every hole is replaced. This is an explicit declared type, not inferred expected-type completion.

## Bounded host replay

## Bounded VM explanations


- [FLOAT-DOMAIN-1] Builtin float is IEEE binary64: separate arithmetic operations with canonical arithmetic NaNs, numeric comparisons in which signed zeros compare equal and every NaN comparison is false, and checked conversion to and from signed integers. The raw f64_* intrinsics over u64 representations remain available for code that owns a bit pattern; the f64 spelling is not a type name.

- [STRUCTURAL-COMPOSITE-1] Structural field and operation signatures substitute fixed arrays and nominal applications. Result obligations remain transferred by value. Invalid unused templates still reject.



- [CONST-LENGTH-1] Generic functions and nominal declarations accept explicit const N:u64 parameters, used as array lengths, forwarded constant arguments and u64 values in function bodies. Literal lengths are bounded to 1048576 and participate in specialization identity separately from type arguments. Symbolic checking preserves unknown lengths and rejects invalid unused templates, including type/value confusion and array literals whose length cannot be proved.
- [SEMANTIC-CACHE-1] Supported changed-source checks reuse independently owned checked function bodies with relocated spans, nodes, statements and locals; failed checks or snapshot allocation failures do not replace the last complete snapshot.
- [SEMANTIC-CACHE-2] Declaration/type/import identities invalidate body reuse, generic/constant/alias configurations conservatively check fresh, and complete region/effect/codec passes rerun after every body edit.
- [SEMANTIC-CACHE-3] Cached source spans and node/statement identities must belong to unchanged mapped intervals and their function's tables; invalid relocation falls back instead of trusting stale references.

- [SEMANTIC-CACHE-4] Reusing a caller body never reuses transitive effect verdicts; a callee's new effect rejects an unchanged effect-bounded caller.
- [SEMANTIC-CACHE-5] Failed cache publication releases only its pending snapshot; the previous successful function queries remain reusable after OutOfMemory.
- [SEMANTIC-CACHE-6] Project queries include module paths, import/export text, signatures and type catalogs, preserving fresh/cached diagnostics and execution through source relocation and changed module interfaces.
- [CALLBACK-1] Noncapturing function values have exact parameter/result signatures and declared effect ceilings, including parameter-dependent signatures in generic helpers. Creation stores an immediate function identity; invocation validates the target and preserves ordinary ownership/result obligations. Callback parameters and results are ordinary copied values; captured environments are rejected.

- [SEMANTIC-CALLBACK-1] Function-name values may infer callback schemas while checking bodies, so semantic body reuse stays disabled for these programs until snapshots can safely remap their inferred types. Fresh and changed-source callback execution retain identical signatures and outcomes.

- [STANDARD-TIME-RANDOM-1] Standard durations and Unix nanosecond instants use checked signed arithmetic that reports overflow, reversal and unrepresentable spans as Result failures instead of wrapping or trapping; seeded SplitMix64 has stable word sequences, a shared stream across copies of a generator, and inclusive integer sampling that covers the whole signed range without modulo bias.
- [STANDARD-TIME-RANDOM-2] Standard clock and entropy calls require explicit capabilities and keep the unavailable, denied and failed provider categories apart in their reported messages; a later failed read leaves earlier results intact and host allocation failure aborts normally.
- [STANDARD-TIME-RANDOM-3] Standard provider wrappers preserve source effect ceilings, so a caller declaring a narrower ceiling than clock or random plus managed allocation is rejected while checking; one entropy-seeded generator performs exactly one provider read and replays identically from its state word.

- [TYPE-ALIAS-SCHEMA-1] Exported transparent aliases retain their checked canonical target in public schemas and native interfaces, including scalar, array, chained and concrete generic targets.



- [SCOPED-DIRECTORY-1] Read-authorized `m:path` metadata and `l:path` directory listing acquisitions publish bounded immutable byte snapshots under the existing directory grant. Empty paths denote that root only for these modes; intermediate/final directory traversal never follows symlinks, while final metadata reports a symlink itself.
- [SCOPED-DIRECTORY-2] Failed directory snapshot construction releases partial bytes and open directories before returning; allocation failures never publish a live snapshot handle.


## Standard library over managed types

- [STANDARD-MATH-1] Standard math classifies, rounds and roots binary64 values with IEEE behaviour preserved at zeros, infinities and not-a-number; sqrt reduces by exact powers of four and refines by Newton iteration, pow takes an integer exponent whose magnitude saturates by parity, and abs, gcd, lcm and isqrt report the values the signed range cannot hold as Result failures.
- [STANDARD-STRINGS-1] Standard strings add the classification, search, trimming, padding, case mapping and numeric conversion that builtin str lacks. to_int accepts exactly the signed range and rejects every other text; to_float accumulates an exact integer mantissa with one power-of-ten scaling; format_int covers bases 2 to 36 including the most negative integer, and format_float rounds halves away from zero and rejects magnitudes it cannot render.
- [STANDARD-SORT-1] Standard ordering is a stable merge over a copy that leaves its input unchanged, for integers, binary64 values, Unicode code point order on text, and any element type through an integer key callback. Binary search, extrema and duplicate removal report absence through Option and keep first-occurrence order.
- [STANDARD-PATH-1] Standard path operations are pure text algebra with no filesystem authority: joining honours an absolute right side, basename and dirname agree with the trailing-separator convention, splitext ignores a leading dot, and normalize removes duplicate separators, single dots and resolvable parents while keeping unresolvable ones.
- [STANDARD-CODECS-1] Standard base64 emits canonical padding for both RFC 4648 alphabets and decodes only canonical input, rejecting a length that is not a multiple of four, a symbol outside the alphabet, padding before the final group and a final group with nonzero unused bits. Hexadecimal transcoding accepts either letter case and rejects odd lengths.
- [STANDARD-JSON-1] Standard JSON parses strict RFC 8259 text into a recursive union, rejecting comments, trailing commas, leading zeros, bare fractions and exponents, unescaped control characters, lone surrogates, duplicate object keys, trailing text and nesting past a fixed limit, and naming the byte offset in every message. Objects keep parsed key order, a number without fraction or exponent that fits the signed range stays exact, and rendering round-trips a parsed document without added whitespace.
- [STANDARD-POOL-1] A standard pool hands out copyable generational handles into a reusable slot store. Removing a slot advances its generation so every earlier handle stops matching; a stale or out-of-range handle reports absence and no handle traps, released slots are reused before the store grows, and copies of a pool value refer to one shared store. A handle names a slot and a generation rather than a pool, so it must be used with the pool that issued it.

## Application library parity

- [STANDARD-INTEGER-EXTREMA-1] Standard math integer min, max and clamp compare exact values at every supported integer width without arithmetic overflow, including both ends of each signed and unsigned range.

## Ordinary JSON schema helpers




## Bytecode execution

- [VM-AUDIT-1] Scalar-loop execution preserves results, exact instruction budgets and located traps across runtime representation optimizations.

- [NATIVE-TIMING-1] `run --timings` reports native execution nanoseconds on stderr, covering the guest process and the native build it needed but excluding source compilation. Timing preserves guest results, quotas and runtime diagnostics; duplicate options and unsupported commands reject it.

- [PHASE-TIMING-1] One-shot compiler commands and the raw byte I/O host accept opt-in `--timings=json`, emitting versioned phase-timings-v1 JSON Lines on stderr. Records use nonnegative duration_ns, explicit inclusive scope, available work counts and the command exit_code; total includes cleanup and excludes timing serialization. Attempted failing phases remain observable, stdout and default behavior are preserved, and legacy `--timings` remains compatible.

- [ERGONOMIC-INTEGRATION-1] Late exports, inferred generic calls and unit procedures compose across module boundaries, preserving cross-module effect and result obligations.
- [GENERIC-INFERENCE-1] Generic function calls may omit their entire type-argument list when checked call arguments uniquely determine every type and const length parameter. Matching follows direct variables, fixed arrays, nominal applications, and callback signatures; repeated occurrences must agree. Abstract callers retain distinct symbolic identities and declared requirements. Argument expressions are checked and evaluated once in their original order; ordinary type, effect, ownership, and structural checks remain in force. Return context, constraints alone, defaults, and partial explicit lists do not infer missing arguments; ambiguity and conflicting inference report E_GENERIC_INFERENCE. Unmaterialized phantom type arguments require explicit specialization.
## Unit procedures

- [UNIT-1] The builtin `unit` is a distinct no-value type. Unit functions accept `return;` and implicit fallthrough; `main` still returns `i64`.
- [UNIT-2] Ordinary standalone expressions must have type `unit`; all other values require `_ =` or result handling, including generic bodies. VM calls preserve unit identity and ownership cleanup.
- [UNIT-3] Unit is described explicitly in public schemas and is rejected by data/wire and host ABI boundaries.
- [UNIT-4] Unit fallthrough and early return release owned parameters through the ordinary cleanup paths.
- [UNIT-5] Fallible values with unit success payloads retain all result obligations; a successful `try` yielding unit may appear as a standalone statement.
- [UNIT-6] Public unit-returning functions remain callable within language modules. Their schema uses `kind: unit`; copied VM/host/native ABI invocation rejects unit-containing signatures explicitly instead of interpreting unit as a scalar or capability.

## Managed tracing heap

- [GC-ROOTS-1] Managed list aliases share stable identity and mutations. Retained values, including intermediate call arguments and ordinary aggregate snapshots, root managed objects across allocation and stress collection.
- [GC-CYCLES-1] Nonmoving tracing collection reclaims unreachable cycles, including cycles through ordinary aggregate fields and cycles whose last root left a block, and preserves reachable cycles.
- [GC-BOUNDARY-1] Managed list operations enforce element types, and an out-of-range read or write raises a located list-bounds trap.
- [GC-SOURCE-1] Managed list aliases in immutable local bindings and helper parameters share mutation without explicit allocator authority.
- [GC-SOURCE-2] Source programs can construct list/record cycles; a later managed allocation collects an unreachable cycle before execution shutdown.
- [GC-SOURCE-3] Managed results held as intermediate call arguments or inside ordinary record snapshots survive collection triggered by later arguments and callee allocations.
- [GC-SOURCE-4] Out-of-bounds managed reads and writes produce located R_LIST_BOUNDS traps and release execution roots and backing.
- [GC-SOURCE-6] `noalloc` rejects transitive managed allocation and list growth; fixed-slot mutation and reads remain permitted.
- [GC-SOURCE-7] Managed element declarations reject owned resources and unchecked results, including such values nested in ordinary aggregates.
- [GC-SOURCE-9] Bytecode validation rejects managed metadata on record shapes that are not managed containers.
- [GC-GENERIC-1] Generic managed list creation, mutation, and identity helpers preserve shared aliases without explicit allocator authority.
- [GC-GENERIC-2] Recursive generic list and record declarations form managed reference graphs without recursive value layout.
- [GC-GENERIC-3] Ordinary directly recursive value declarations remain rejected even when managed lists are available.
- [GC-GENERIC-4] Source formatting preserves generic list declarations and contextual uses of list as a variant name.

## Managed standard library

- [GC-GENERIC-5] Managed list elements cannot contain allocator or provider capabilities, including nested records, arrays, and instantiated generic elements; declarations reject with E_LIST_CAPABILITY.
- [GC-CAPABILITY-1] Managed element declarations reject capability values and capabilities nested in aggregates, preserving the source authority boundary.

- [GC-SOURCE-11] Lexical block, break, and continue exits release managed local roots, including roots nested in copyable records, so unreachable cycles can be reclaimed at the next allocation before the enclosing function returns.

## Managed arenas

- [ARENA-MANAGED-1] Python-style `with arena() as name:` and `with arena():` open a region over ordinary managed objects. Every managed allocation performed in the block's dynamic extent, including allocations inside called helpers, is tagged with that arena's nesting depth; arenas nest and the innermost one wins. Normal block exit releases every object allocated at that depth in bulk, dropping their outgoing edges before any header is freed, and reports the release separately from tracing reclamation in `memory.gc.statistics`.
- [ARENA-MANAGED-2] `name.escape(value)` deep-copies the part of the managed graph reachable from `value` that lives in the innermost arena into the enclosing region, preserving sharing and cycles inside the copy and sharing objects that already live in an older region. Escape carries the `managed_allocation` effect. The arena binding itself is opaque: it cannot be stored, passed, returned, or compared, only used as the receiver of `escape`, and `escape` must name the innermost active arena.
- [ARENA-MANAGED-3] Every managed object header records its arena depth and every store of a managed reference into a heap object is checked: list append, list slot writes, dictionary key/value writes, and values nested in record snapshots. Storing a reference of a younger arena into an older container traps with a located `R_ARENA_ESCAPE`, including stores performed inside helpers called from the block.
- [ARENA-MANAGED-4] Inside a `with arena()` block the checker rejects, with `E_ARENA_ESCAPE`, assigning a managed-bearing value to a binding declared before the block, returning a managed-bearing value, and direct stores into an outer-declared collection or record (`append`, indexed writes, dictionary writes, and field assignment). A managed-bearing type is any type whose values may hold a garbage-collected reference; scalars, enums, domains and records with only scalar fields are free to escape. `name.escape(value)` is the exception and may also be returned from the outermost arena scope of a function. Diagnostics name the escaping expression, the arena scope, and the outer binding, and render complete JSON provenance.
- [ARENA-MANAGED-5] Normal exit, `return`, `?` propagation, `break`/`continue` out of the block, and traps or host allocation failure unwinding through it all release the arena exactly once. Frame-owned values are released before the bulk free, and at an explicit block exit any binding declared before the block that still reaches arena storage traps with `R_ARENA_ESCAPE` as a defence in depth. An arena scope is always closed by the frame that opened it; a mismatched close is an internal-error rejection.
- [ARENA-MANAGED-6] Tracing collection continues to run at managed allocation safepoints inside an arena, including under `--gc-stress`; arena objects are traced normally and a swept arena object leaves its arena. Collection is suspended only for the duration of one `escape` copy, whose partly built clones are not yet rooted. Allocation inside an arena still contributes the `managed_allocation` effect, so `noalloc` rejects it; entering a scope itself contributes no effect.
- [ARENA-MANAGED-7] Arena scopes, bulk release, and escape copies unwind cleanly on every host allocation failure, leaving no live managed objects at execution teardown.
- [ARENA-MANAGED-8] Managed arena scopes lower on the QBE native backend. Every native managed object header records its arena depth, collection backing grows in its owner's region, the store barrier is emitted before each managed reference store whose element type can hold a collected reference, `escape` deep-copies into the enclosing region with collection suspended, `end_arena` scans the frame's outer bindings and clears the block's own before the bulk release, and every native frame restores its entry depth on return and while a trap, `?` propagation, `break`/`continue` or host allocation failure unwinds through it. An arena-free program emits neither barrier nor depth bookkeeping. Generic function bodies reject arena scopes with `E_GENERIC_BODY_UNSUPPORTED`.

- [SURFACE-STMT-1] A statement ends at its newline, at the dedent that closes its suite, or at EOF; two statements written on one line are separated by `;`.
- [SURFACE-STMT-2] Postfix `?` propagates result errors and unwraps success with postfix precedence.
- [SURFACE-STMT-3] `None` and `()` both spell the unit type and unit value; a bare `return` before a newline or a dedent returns unit.
- [SURFACE-STMT-4] Calls and function parameters permit trailing commas; a delimiter continues an expression across newlines.
- [SURFACE-STMT-5] Parse-only declaration listing and module formatting preserve newline-terminated module, import, export, and type directives.
- [SURFACE-STMT-6] Project discovery recognizes newline-terminated directives and declarations while allowing multiline function signatures.

## Command-line authority

- [CAPABILITY-1] `Filesystem`, `Network`, `Clock`, `Entropy` and `Environment` are Python spellings of the existing `filesystem_cap`, `network_cap`, `clock_cap`, `random_cap` and `environment_cap` entry capabilities, and name the same checked types. They resolve only when no declared or imported type claims the name, so an ordinary `class Clock` still wins in its own module, and inside a project the spellings resolve exactly where the module graph resolves no declaration of that name. Authority stays explicit: an entry point declares what it needs by parameter type, helpers receive grants as ordinary arguments, and no numeric cast or copy mints one.
- [CAPABILITY-2] `mylang run` and `run-project` grant every capability by default: filesystem reading and writing with no directory restriction, the clock, entropy and the whole process environment. `--restrict` switches the command to deny-by-default, and only then do `--allow-read=DIR` and `--allow-write=DIR` (each repeatable, up to eight directories), `--allow-clock`, `--allow-random`, `--allow-env` and `--allow-all` narrow anything; without `--restrict` they are accepted and narrow nothing. `--allow-random=SEED` pins the entropy seed in either mode, because it selects a stream rather than withholding one; an unseeded stream is seeded from the wall clock. `--allow-all` grants the clock, entropy, every environment name and read/write access to the working directory, and cannot be combined with another grant. A repeated flag, an empty-valued flag, and any of these options on a command that does not execute a program are usage errors.
- [CAPABILITY-3] Under `--restrict`, an entry point that names a capability the command line did not grant is rejected after checking and lowering but before the first guest instruction, with a message that says `--restrict` is active, names the flag that would grant the capability, and offers to drop `--restrict`; the status is 2. Without `--restrict` that refusal cannot happen. Grants for capabilities the entry point does not request provision providers that are never read.
- [CAPABILITY-4] The default filesystem grant is one direct root over the process working directory: a relative guest path resolves against it and an absolute path names itself, each operation applies the whole path at once and follows symlinks, and write authority is always present, so the default can never be narrower than a read grant. Under `--restrict`, directory grants are an ordered search path of scoped roots instead: a guest path must be relative with no empty, `.`, `..`, NUL or backslash component, it is tried against each granted root in order and the first success wins, traversal opens each component with symlink following disabled and final opens reject symlinks. Modes that change the tree — write, exclusive create, truncate, create directory and remove — consider only roots granted with `--allow-write`, which also grants reading that root, and a read-only grant rejects them before opening anything. Neither mode is a sandbox: the providers run inside the compiler process, the host filesystem tree is trusted, directory handles retain authority across renames, and directory scoping does not distinguish hard links to shared inodes.
- [CAPABILITY-5] The clock reports Unix-epoch nanoseconds from the host wall clock, with no monotonicity guarantee. Entropy is a reproducible pseudorandom stream, seeded by `--allow-random=SEED` when given and otherwise from the wall clock; it is not a cryptographic entropy source, and a program needing one must be embedded with its own provider. The environment exposes the host process environment, restricted to the `--allow-env=NAME,...` allowlist when one is given, reporting absent names as absent and denying names outside the list.

## Ordinary output

- [IO-1] `print(values...)` writes each argument's Python rendering to standard output, separated by single spaces and followed by one newline. `int` and the fixed-width integers render in decimal, `bool` as `True`/`False`, `None` as `None`, `float` with a `.0` suffix when it has no fractional digits and `nan`/`inf`/`-inf` for the nonfinite values, `str` raw at the top level and `repr`-quoted inside a container, and `bytes` as a Python `b'...'` literal with `\n`, `\r`, `\t`, `\'`, `\\` and `\xNN` escapes. Lists render as `[a, b]`, insertion-ordered dictionaries as `{k: v}` and fixed arrays as `[a, b]`. Nesting deeper than 24 levels renders as `...`, so a cyclic managed graph still terminates. `print()` writes only the newline.
- [IO-2] Records render as `Name(field=value, ...)` in declaration order, enum cases as `Name.case`, union cases as `Name.case(payload)` or `Name.case`, checked results as `Ok(value)`/`Err(value)` and optionals as `Some(value)`/`None`. Module qualification is stripped from the printed name. A record with a moved field prints `<moved>` for that field rather than reading it.
- [IO-3] `print` accepts the keyword arguments `sep=` and `end=`, each an ordinary `str` expression that replaces the separator or the trailing newline. Positional arguments must precede both keywords, neither may be repeated, and any other keyword is rejected with `E_IO_ARGUMENT`. Printed values evaluate in source order, then `sep=`, then `end=`. Both keywords materialize the prelude `str` type on demand, so a program whose only text is a separator still checks, and a `print` call without keywords needs no text schema at all.
- [IO-4] `print` contributes the `output` effect. `noio` withholds `filesystem`, `network` and `output` together, so a direct or transitive `print` under `noio` is rejected with `E_EFFECT_BOUND` and a call witness; `effects(output)` permits it and `noalloc` does not constrain it. Bytecode validation independently recomputes the effect from the emitted instruction.
- [IO-5] `print` is a reserved call spelling only while no local binding, declared function or imported top-level name shadows it; a program that declares its own `print` calls that function instead. Capabilities, files, owned resources and callback values have no rendering and are rejected with `E_IO_ARGUMENT`. A host that supplies no output writer discards program output rather than failing, and a writer that refuses bytes traps with `R_OUTPUT`.
- [IO-6] The QBE native backend lowers `print`. The compiler emits one C renderer per type a program actually prints, so every value shape renders byte-identically to `src/io_render.zig`, including `sep=`/`end=` raw text, the 24-level depth cap and the float spelling. A call buffers its whole line before any byte reaches standard output and flushes once; a refused write traps `R_OUTPUT`. Generic function bodies reject `print` and the whole-path file builtins with `E_GENERIC_BODY_UNSUPPORTED` rather than reporting them as unknown functions.
- [IO-7] `with` is one statement form with two resource kinds. `with arena() as name:` opens a managed region; any other expression must produce an open file handle and must name its binding. `open(fs, path, mode)` takes a `Filesystem` capability, a relative `str` path and a literal mode — `"r"`, `"w"`, `"a"` with an optional `"b"` or `"t"` — and returns `Result[File, str]` for binary modes or `Result[TextFile, str]` for text modes. Directly as the head of a `with` statement the call yields the handle itself and a failure traps with a located `R_FILE`, the way Python's `open` raises; `with open(...)? as f:` propagates the result instead, and every other position yields the ordinary result. A binary handle's `read`, `readline` and `readlines` produce `bytes`; a text handle's produce `str`, decoded as UTF-8. `f.read()` reads to end of file, `f.read(n)` reads at most `n` bytes, `f.readline()` keeps its terminator, and `f.readlines()` returns the lines with their terminators kept.
- [IO-8] `f.write(data)` accepts the handle's own element type, writes every byte by looping over the provider's partial progress, and returns the count. `f.flush()` exists for familiarity and is a no-op because writes are unbuffered. Mode `"w"` creates the file or truncates an existing one, `"a"` appends at the current end, and `"r"` neither creates nor truncates. Whole-file reads and writes are capped at 64 MiB.
- [IO-9] `read_file`, `read_text`, `write_file`, `write_text`, `listdir`, `mkdir` and `remove` each take the capability first and return `Result[T, str]`, whose error text names the operation, the path and a readable reason. `exists(fs, path)` returns `bool` rather than a result. A helper opens, uses and closes its resource within the call, so a failure leaves no handle behind.
- [IO-10] A directory granted without write authority rejects every writing mode — `w`, `a`, create, truncate, `mkdir` and `remove` — before opening anything, and the returned error says the mode needs a write grant.
- [IO-11] A file `with` scope closes its handle exactly once at every exit: falling off the end, `return`, `?` propagation, `break`, `continue`, an explicit `f.close()`, and a trap or host allocation failure unwinding through it. A method on a closed or stale handle traps with `R_FILE`; so does any provider failure during a method, since `f.read()` yields bytes rather than a result. The trap message carries the same readable reason as the `Result` error text.
- [IO-12] File operations contribute the `filesystem` effect, so `noio` rejects them with `E_EFFECT_BOUND`. `with` on a value that is not an arena or an open file is rejected with `E_WITH_RESOURCE`, which tells a `Result` operand to propagate with `open(...)?` or match first. A non-literal mode, an unsupported mode and an unknown handle method are rejected with `E_FILE_ARGUMENT`. Generic function bodies reject file operations. The QBE native backend runs the whole file surface too, over a native scoped-directory provider with the same request grammar, `Result` error text and located `R_FILE` traps; an open handle is one owned resource word that the ordinary local drop closes at every scope exit. A native executable grants every capability by default and `--restrict` switches it to deny-by-default with the same `--allow-*` flags, which `mylang build --run` forwards after `--`.

## Collection and statement surface

- [SURFACE-COLLECTIONS-1] Managed list push(value), len(), indexing, and indexed assignment preserve shared aliases across bindings.
- [SURFACE-COLLECTIONS-2] Record construction names its type and fields — `Box[i64](value=42)`, `Empty()` — covering generic records, empty records declared with `pass`, and trailing argument commas.
- [SURFACE-COLLECTIONS-3] Generic managed list methods and indexing preserve abstract element type checking.

- [SURFACE-STMT-7] Condition expressions admit record constructors inside nested call arguments; record and field names remain case-sensitive identifiers.
- [SURFACE-STMT-8] Record constructor syntax accepts nested generic type arguments, including List fields initialized with contextually typed empty lists.
- [SURFACE-STMT-9] A newline separates postfix call suffixes from completed expressions outside parentheses, while parentheses permit multiline calls and suffixes.

- [SURFACE-COLLECTIONS-4] Managed list methods reject invalid argument counts, unknown methods, mismatched element types, and noninteger indices.

## Prelude types and contextual constructors

- [BUILTIN-CONTEXT-1] List<T> and Result<T,E> are available without imports or explicit declarations and use existing managed-list and fallible-result semantics.
- [BUILTIN-CONTEXT-2] Empty lists and Ok/Err payload constructors use expected binding, return, and concrete call-argument types.
- [BUILTIN-CONTEXT-3] Record fields and managed list elements propagate their expected types into nested empty list expressions.
- [BUILTIN-CONTEXT-4] Ok(()) constructs successful Result<unit,E> values with normal handling obligations.
- [BUILTIN-CONTEXT-5] Generic List and Result expressions preserve symbolic type parameters through empty list creation, mutation, and Ok construction.
- [BUILTIN-CONTEXT-6] Contextual constructors reject missing or incompatible expected types, invalid generic arity, and forbidden managed capability elements.
- [BUILTIN-CONTEXT-7] Explicitly declared List and Result types retain their own nominal identities and contextual constructors.
- [BUILTIN-CONTEXT-8] Builtin List and Result types share canonical identity across imported module signatures without imports of a prelude module.
- [BUILTIN-CONTEXT-9] A module-local List declaration shadows the prelude in that module while unrelated modules continue to resolve the builtin List.
- [BUILTIN-CONTEXT-10] Module-local functions named Ok or Err take precedence over contextual constructors in both ordinary and generic bodies, without spurious constructor diagnostics.
- [SCHEMATIC-INPUTS-1] The schematic host provides named circuit, pinout, and interface document handles through io.inputs; nominal Document values preserve the existing scalar byte I/O ABI, and older guests declaring only four byte callbacks remain supported.
- [SCHEMATIC-INPUTS-2] Named input providers reject absent host documents instead of issuing unusable handles.

- [MODULE-DOT-1] Direct import aliases accept dot-qualified function and type references, including generic records and imported domain methods; local list methods retain their meanings.
- [MODULE-DOT-2] Dot-qualified imported functions can be passed as values, and generic function bodies resolve dotted module type references through their declaring module.
- [MODULE-DOT-3] Dotted qualification preserves private-symbol, private-domain-function, and import-alias-shadowing checks.
- [MODULE-DOT-4] Dotted module parsing, namespace normalization, checking, and execution release all allocations on allocation failure.

- [SCHEMATIC-MODEL-1] The schematic entry parses named document handles, builds one validated schematic value, and passes it to rendering; normal and collection-stress execution produce identical SVG and release all managed roots.
- [MODULE-DOT-5] Semantic caching recognizes dotted imported function values and keeps callback type catalogs fresh across repeated requests and imported function edits.

## Python-oriented core values

- [PYTHON-CORE-1] Prelude List, Result and Option have one nominal identity shared across modules; unrelated user nominal declarations remain distinct.
- [PYTHON-CORE-2] Unit and Result<unit/int,int> entry functions adapt to the scalar runner status convention while retaining their ordinary guest signatures. The synthesized wrapper is not a source declaration, so no public interface names it and a project with such an entry emits native units like any other.
- [PYTHON-CORE-3] Representable unsuffixed integer constants inherit numeric contexts; explicit suffixes retain their types and out-of-range constants are rejected.
- [PYTHON-CORE-4] Decimal float literals and ordinary arithmetic/comparisons use binary64 numeric semantics, including equal signed zeros and unordered NaNs.

## Surface syntax

- [PYTHON-1] Sources use `def`/`class` heads, colon and space-indented blocks, `#` comments, implicit continuation inside delimiters, and source-preserving virtual block delimiters. A suite opens at the `:` that ends its line and closes at its dedent; `{` and `}` are only a dictionary literal, so a brace-bodied declaration is rejected. A suite's reported bytes end at the last token it wrote, so the blank lines and comments before the next declaration belong to neither, and a function's measured length and navigation excerpt cover only the function. Missing blocks, inconsistent dedents, and indentation tabs are diagnosed. Indentation is the only block syntax, so `fmt` returns the text a program already has.
- [PYTHON-2] Functions support ordinary mutable assignment, annotated bindings, `True`/`False`/`None`, `and`/`or`/`not`, `pass`, `elif`, omitted unit return annotations, `int` as i64, and square type parameters whose omitted requirement defaults to copy. `pass` spells an empty suite wherever one is written, including a record with no fields and a domain with no members. A `;` separates two statements written on one line, as it does in Python.
- [PYTHON-3] Value records use `class` with annotated fields and named construction; square-bracket type applications and `match`/`case` preserve contextual variant names and underscore payload discards for semantic resolution. Every explicit type argument uses square brackets, including `todo[T]()`, `wrap[D](v)`, `codec_encode[D](v)` and the capability and resource operations.

- [PY-VARIANT-1] `Type.case(value)` constructs an enum or tagged-union variant carrying its declared payload; `Type.case` without parentheses stays the payload-free construction and contextual `Ok`/`Err`/`Some`/`None` are unchanged. The payload evaluates once and `match`/`case` patterns keep the same spelling.
- [PY-GENERIC-1] `f[T](x)` applies explicit type arguments to a generic function, constant lengths included (`first[i64, 2](values)`), and a member call takes them the same way: `D.hidden[U](x)` on a domain method, `m.D.make[U](x)` on an imported one, and `m.make[i64, 2](v)` on an imported free function. An argument may name any type the lexer spells as a keyword, capabilities included: `hold[clock_cap]()`. A square-bracket application in call position names a function when the base is a declared function and a generic record otherwise, so `Box[T](field=v)` construction is unchanged and the nominal type catalog never resolves a function application as a type.
- [PY-GENERIC-2] Explicit call type arguments reach the same instance as inference, and the wrong number of arguments or an undeclared base name is rejected.
- [PY-FLOAT-1] `sqrt`, `floor`, `ceil`, `trunc` and `abs` are prelude operations on `float`, so guest code needs no `u64` bit pattern. Each takes one float and answers a float; a non-float argument is rejected, and a local binding or declared function of the same name shadows the operation.
- [PY-WILDCARD-1] `case _` in a `match` statement covers every variant no earlier arm named, discarding the payload of each one it covers.
- [PY-WILDCARD-2] A wildcard arm must be the last arm, must cover at least one variant, and is rejected when it would drop a result-bearing payload; that variant needs its own arm.
- [PY-SUBSCRIPT-1] A subscript index may begin with a parenthesis: `values[(n - 1) % 3]` is an index, because a square-bracket type application never contains a parenthesized group.
- [PY-RESERVED-1] `len` and `replace` are intrinsics only at the head of a call. Both name ordinary declarations, record fields, keyword arguments, members, exports and imported module members, so `strings.replace(...)`, `pool.len(p)`, `text.replace(old, new)` and a field named `len` are all spellable.
- [PY-LOOP-1] A `while True` loop with no `break` targeting it never falls through, so a function whose body ends in one needs no unreachable trailing return.
- [PY-PRELUDE-1] The `bytes` and `float` prelude types are registered wherever their names are written in source, including a variant payload, a record field and a bare annotation, rather than only where a literal or conversion appears.
- [PY-COMPREHENSION-1] `[value for name in iterable if condition]` builds a fresh list through one checked loop over a list, string, byte string or dictionary, under the same fixed iteration bound and mutation check as `for`. The filter runs before the value, the binding lives only inside the comprehension, and the source collection is unchanged.
- [PY-COMPREHENSION-2] A comprehension takes exactly one generator and at most one filter. A binding that shadows an active name, a non-Boolean filter, a source that is not a managed collection, and a produced value that is not a copyable storable list element are all rejected. Generator expressions and multiple generators are not provided.
- [PY-FSTRING-1] `f"..."` interpolates `{expression}` holes and concatenates the pieces into one `str`. A hole takes any value `print` can render — lists, dictionaries, records, variants, results, options and byte strings as well as scalars — and renders it through the same renderer, so one value has one spelling wherever it is written. A hole holds one ordinary expression, including calls, operators, indexing and a nested format string, and is checked in its own source position. `f` before a quote is the prefix; anywhere else it is an ordinary identifier.
- [PY-FSTRING-2] `{{` and `}}` stand for single braces, ordinary string escapes apply to the literal pieces, and an empty format string is empty text. An empty hole, an unmatched or unterminated brace, more than one expression in a hole, a format specification after `:`, and a value with no rendering — a capability, an open file or a callback — are all rejected. Rendering releases its partial buffer on allocation failure and reports it as `OutOfMemory`, the way every other allocating writer in the compiler does.
- [PY-STR-1] `str` values answer `strip`, `lstrip`, `rstrip`, `upper`, `lower` and `zfill(width)` with a fresh string, leaving the receiver and every alias unchanged. Case mapping covers ASCII letters and leaves every other scalar alone; `zfill` keeps a leading sign in front of the padding.
- [PY-STR-2] `replace(old, new)`, `find(sub)` (-1 when absent), `count(sub)`, `startswith`, `endswith`, `isdigit`, `isalpha` and `isspace` follow Python's answers, including `False` for every classification of empty text. An empty needle traps `R_EMPTY_SEPARATOR`, and these methods are rejected on lists and dictionaries.
- [PY-STR-3] `splitlines()` splits on `\n`, `\r` and `\r\n` without keeping the terminators and yields no line for empty text. `int(text)` returns `Option[int]` and `float(text)` returns `Option[float]`, answering `None` rather than raising when the whole string is not exactly one number.
- [PY-STR-4] Every `str` method, scalar-value iteration and both number intrinsics lower to the QBE native backend over the immutable native text runtime, so no `str` operation reports `E_QBE_UNSUPPORTED`. A native `find`, `count` or `replace` with an empty needle raises `R_EMPTY_SEPARATOR`, and every method answers the value its documented semantics require.
- [PY-NUM-1] `int(text)` and `float(text)` accept one pinned base-10 grammar: optional surrounding ASCII whitespace, an optional `+` or `-` sign, then decimal ASCII digits separated by single `_` characters that must sit between two digits. `float` additionally accepts a `.` fraction, an `e`/`E` exponent with its own optional sign and digit run, and the case-insensitive spellings `inf`, `infinity` and `nan`. An alternate base such as `0x10`, a non-ASCII digit, an interior space, a trailing character and empty text are all `None`, and one shared vector table drives the checker and the native runtime so they cannot drift.
- [PY-NUM-3] A native program that parses numbers links the shared text runtime unit that holds the grammar, and `int(text)`/`float(text)` lower to an `Option` whose `Some` payload the runtime publishes and whose `None` carries no payload. A program that only measures or slices text links no such unit.
- [PY-NUM-2] `int(text)` answers `None` for a value the signed 64-bit range cannot hold rather than wrapping. `float(text)` is correctly rounded: a value beyond binary64 answers an infinity and one below it a signed zero, an absurd exponent saturates instead of wrapping, and digits past the rounding horizon are folded into a sticky digit that keeps the rounding the full text would have produced.
- [PY-ASSERT-1] `assert condition` checks a Boolean expression under any effect bound, in ordinary and generic function bodies, and traps `R_ASSERT` when it is false. The trap's source span is the checked expression and its default message is that expression's source text.
- [PY-ASSERT-2] `assert condition, "message"` reports the string literal instead of the expression text. Native lowering raises the same `R_ASSERT` code without the message, matching every other native trap.
- [PY-DIV-1] `divtrunc(a, b)` and `remtrunc(a, b)` are prelude helpers for integer division and remainder that round toward zero, the rounding `//` and `%` deliberately do not provide. They take two operands of one integer type, trap on a zero divisor and on the signed minimum divided by -1, and a local binding or declared function of the same name shadows them.
- [PY-CONVERSION-1] A `conversion` function body constructs its destination record as `T(a=v)`, under complete source-field accounting.
- [PY-VARIANT-3] A generic variant names only its template, because `Slot[T].some(v)` cannot be told apart from an index followed by a call. `Slot.some(v)` and the pattern `case Slot.some(v)` take their type arguments from the expected type — a binding annotation, parameter, field or result — in ordinary and generic function bodies alike, and report `E_GENERIC_INFERENCE` when no context supplies them. A project resolves the template through its own module names, so a declared or imported `m.Slot.some(v)` infers its arguments the same way.
- [PY-ARRAY-1] A list literal whose expected type is a fixed array `[N]T` — from an annotation, a parameter, a record field or a return type — constructs that array rather than a managed list, and a list literal in every other context still builds a managed list.
- [PY-ARRAY-2] Fixed-array literals check their length statically against the expected array, reporting `E_ARRAY_LENGTH`, and each element against the declared element type.
- [PY-TABLE-1] A dict literal whose expected type is an enum-indexed table `[Kind]T` constructs that table, its keys spelled `Kind.case` and its values arranged in enum layout order independently of source order.
- [PY-TABLE-2] Table literals require exactly one entry per case of their own key enum; missing cases, duplicates, non-case keys and cases of a different enum are rejected.
- [PY-VARIANT-2] Variant construction resolves through the declared type identity, so a local binding shadowing the type name keeps ordinary member resolution and a name that is not a declared case stays an ordinary call. Supplying no payload, more than one payload, a payload to an empty case, or a payload of the wrong type is rejected.


- [PY-COLLECTIONS-1] Managed list literals infer homogeneous element types or use contextual list types; append, nested indexes, receiver expressions, and indexed writes evaluate operands once. Legacy writes retain receiver-first order; Python function writes evaluate the assigned value before the target. Signed negative indexes count from the end.
- [PY-COLLECTIONS-2] List slices copy the selected elements into a fresh managed list, normalize negative endpoints and clamp to bounds. `len(list)` returns signed i64.
- [PY-COLLECTIONS-3] For-each and enumerate evaluate a list once and retain its initial iteration bound, rejecting structural mutation through aliases before the next body or step; range accepts end or start/end. Break and continue retain correct step semantics.

- [PY-COLLECTIONS-4] Contextual nested literals preserve list types across fields and nested indexes.
- [PY-COLLECTIONS-5] Field assignment reconstructs mutable local records or list-slot records with receiver/index operands evaluated once, retaining value semantics for previous copies.
- [PY-COLLECTIONS-6] Generic list literals, iteration, slicing and writes preserve symbolic element types and allocation effects.
- [PY-COLLECTIONS-7] Receiver calls, computed indexes and assignment values run exactly once in source order and survive collection at every allocation.
- [PY-COLLECTIONS-8] Structural list mutation through an alias traps during continued iteration, including continue and the final step; break exits without another iteration check.
- [PY-COLLECTIONS-9] Generic record field updates preserve managed alias copying and concrete value semantics.
- [PY-COLLECTIONS-10] Slicing clamps negative and oversized endpoints, produces empty reversed intervals and copies list storage while retaining shallow element values.

- [PY-COLLECTIONS-11] Contextual types attach to complete expressions so an annotated postfix expression does not incorrectly constrain its receiver literal.
- [PY-COLLECTIONS-12] End-only range syntax starts at signed zero in runtime and compile-time scalar functions.

- [PY-COLLECTIONS-13] Record field writeback retains unrelated fields changed through managed aliases during evaluation of the assigned value.


- [PY-TEXT-1] Managed immutable text validates UTF-8, indexes Unicode scalar values (including negative indices), compares exact codepoints, concatenates, and splits/joins literal separators. Strings cannot be mutated through list operations. Scalar str conversions use Python Boolean/None spellings and numeric text. Python strings support Unicode escapes, codepoint slices, membership, and iteration; generic bodies preserve these types.
- [PY-DICT-1] Managed dictionaries preserve insertion order and shared alias updates, compare integer/string keys by value, distinguish missing keys from defaults, trace key/value cycles, and fail allocation or capacity growth atomically. Managed data equality compares contents with cycle detection; dictionary equality ignores insertion order. Membership searches dictionary keys, list values, or a text substring. Python in/not in evaluate the needle before the container exactly once. Dictionary iteration returns keys in insertion order and traps if aliases change its size; generic dictionary literals preserve symbolic key/value types.
- [PY-BYTES-1] `b"..."` and `b'...'` produce managed immutable `bytes` with the `[BYTE-LITERAL-1]` escapes and decoded-size limit; a literal keeps the fixed `[N]u8` array reading only where the context demands one, including readonly `&[]u8` slice parameters. `len(b)` is signed, `b[i]` yields an `int` in 0..255 with negative indices from the end and an `R_LIST_BOUNDS` trap outside them, `b[i:j]` copies a clamped byte range, `a + b` concatenates, `==`/`!=` compare content, `in`/`not in` search a byte scalar or a contiguous subsequence, and `for x in b` yields `int` under the list iteration-bound rules. Byte strings are immutable, are traced and rooted like `str`, and construction, concatenation, slicing and conversion contribute `managed_allocation`.
- [PY-BYTES-2] `bytes(values)` builds a byte string from a `list[int]` and traps with `R_BYTE_RANGE` outside 0..255; `b.to_list()` returns `list[int]`. `s.encode()` produces the UTF-8 bytes of a `str` and `b.decode()` returns `Result[str, str]` whose error reports invalid UTF-8 rather than raising. `b.hex()` formats lowercase hexadecimal text and `bytes.fromhex(s)` returns `Result[bytes, str]`, rejecting odd lengths and non-hexadecimal digits. `str(b)` is not provided.
- [PY-BYTES-3] `b.split(sep)` returns `list[bytes]` and rejects an empty separator, `sep.join(parts)` rebuilds a byte string, and `b.startswith(x)`, `b.endswith(x)` and `b.find(x)` (returning -1 when absent) mirror the text operations. `bytes` is a prelude type usable in `list[bytes]`, `dict[str, bytes]`, record fields and `Option`/`Result` payloads; dictionary keys remain `int` or `str`. Like `str`, `bytes` is accepted in exported module signatures and rejected at JSON, host-function and native-embedding boundaries with those boundaries' existing diagnostics.
- [PY-BYTES-4] Byte strings are ordinary managed objects under `with arena()`: byte strings built inside the block are region-allocated, `escape` copies them into the enclosing region alone or inside lists, storing an arena byte string into an outer list directly is rejected with `E_ARENA_ESCAPE`, and doing so through a helper traps `R_ARENA_ESCAPE` at run time.
- [PY-BYTES-5] The QBE native backend lowers every byte-string operation, not only construction, `len`, indexing, iteration and equality: concatenation, clamped slicing, `in`/`not in` over a byte scalar or a subsequence, `split`/`join`, `startswith`/`endswith`/`find`, `to_list`, `bytes(values)` with its `R_BYTE_RANGE` trap, `hex`/`fromhex` and `encode`/`decode` all run natively over a byte runtime that mirrors the managed text runtime with a one-byte stride, and report the traps and `Result` error text the language specifies.

- [SCHEMATIC-PYTHON-1] The Python-syntax schematic uses GC collections and unit output helpers; decimal output preserves negative values including the minimum signed integer under Python floor division and modulo semantics.
- [PYTHON-CALL-1] Declared functions accept positional and keyword arguments with trailing scalar-literal defaults; argument effects run once in source order even when parameter order differs, including inferred generic calls.
- [PYTHON-CALL-2] Calls reject unknown, duplicate, missing, excess, and misplaced arguments. Defaults require immutable scalar literals, their declared types are checked even in unused functions, and required parameters cannot follow defaults.
- [PYTHON-CALL-3] Python constructor calls resolve records by declaration identity, support positional and named fields, generic records, and empty `class` declarations using `pass`.
- [PYTHON-CALL-4] Keyword/default binding, source-order lowering, execution, and native emission release partial allocations on allocator failure.
- [PYTHON-CALL-5] Editing a default value invalidates checked caller reuse and produces fresh call behavior.

- [C-FFI-1] Explicit `extern def` declarations use fixed-arity C scalar signatures on QBE: signed/unsigned 8/16/32/64-bit integers, bool, float as C double, and unit results as C void. They require effects(host), bypass provider registration, retain transitive external effects, and reject borrowed/aggregate/generic signatures. Trusted host-provider registration rejects direct imports. Declaration listing and module discovery treat `extern` as a declaration head, so a newline-terminated declaration ends where the next one begins.

