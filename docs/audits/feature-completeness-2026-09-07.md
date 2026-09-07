# Language feature-completeness audit — 2026-09-07

The language has a substantial working core for bounded, single-threaded applications. Its most immediate gaps are reusable libraries, non-consuming access to owned containers, complete diagnostic feedback, and documented application interfaces. Threads and a new machine-code backend are separate expansion decisions; neither is a prerequisite for making ordinary VM applications easier to build.

This audit proposes 24 work items. They are a backlog for review, not authorization to implement every feature or a claim that every general-purpose language needs the same features.

## Scope and evidence

Baseline: working tree based on commit `226e4d5`, including existing modified and untracked files. The complete HEAD, initial status, 542 file hashes, binary hashes, probe source, commands, stdout, stderr, and diagnostics are retained in [the evidence file](feature-completeness-2026-09-07-evidence.json). The inventory was hashed; targeted implementation, documentation, examples, tests, and application evidence were reviewed. This was not a line-by-line review of all 542 files.

The review used the lexer/AST, parser, semantic and generic checkers, runtime types, ownership/region rules, host interfaces, standard modules, CLI, native emitter, and their acceptance records. Old milestone statements were checked against newer source and records before being classified as gaps.

There were 31 installed-tool invocations: 30 feature/control probes and one retained audit-fixture setup failure. The setup failure declared `module main` in `plain_json.my`; using the matching module name made the plain JSON control return 42. This is not an implementation defect. Negative probes test a specific spelling or construct; source inspection supplies the broader absence/restriction evidence.

The tools were the installed `zig-out/bin/mylang` and `zig-out/bin/mylang-io`. No rebuild, full regression suite, native compilation, or Guardian gate was run. The probes therefore characterize those binary hashes; inspection characterizes the recorded source. Successful controls do not prove the binaries were built from every current source byte. No compiler or application implementation was changed for this audit.

Priority meanings:

- **P1:** recommended next work for maintainable, agent-authored CLI/data applications, or necessary evidence for the project's productivity objective.
- **P2:** useful extension after the affected workload demonstrates friction.
- **P3:** conditional expansion requiring a specific deployment or performance need.

Effort is relative: **S** localized, **M** several components or library APIs, **L** semantic/runtime changes across many components, **XL** a new execution model or backend. These are estimates of scope, not delivery dates.

## Already implemented: preserve and build on these

| Area | Current implementation and evidence |
| --- | --- |
| Types and data | Fixed-width integers, booleans, nominal domains, records, complete construction/conversion, fixed arrays, enum tables, tagged unions, checked results, and byte-string literals. See [AST](../../src/ast.zig), [runtime types](../../src/runtime_values.zig), and [SPEC](../../SPEC.md). |
| Generics | Generic functions and nominal records/unions/results/enums; concrete lengths in generic arrays; symbolic checking; declared structural field/domain-operation contracts; codec requirements. Generic record and structural-contract probes returned 7 and 12. |
| Ownership | Move-only buffers/pools/resources, partial record moves, lexical borrows, input-origin reference returns, arena escape checks, checked handles, and deterministic owned cleanup. The arena example returned 50. |
| Authority | Explicit allocator/filesystem/network/clock/random/environment capabilities, transitive effects, resource read/write/complete attenuation, and host registrations. The `noalloc` rejection and missing-filesystem-provider behavior reproduced. |
| Modules | Disk import graphs, explicit exports/privacy, schemas and typed invocation, source mapping, and module formatting. The module control returned 12. |
| Serialization and text | Byte-string literal-to-slice calls, typed JSON encode/decode, ordinary JSON document parsing, `std_json`, `std_text`, and the `mylang-io` raw-byte host. Controls returned 3, 42, 42, and `ok`. This is a small standard library, not an absent one. |
| Tooling | Versioned JSON diagnostics, ownership provenance, formatting, compiler navigation and impact/context queries, partial declaration indexes, exact verdict and syntax caches, incremental verification, and request-boundary VM reload. |
| Native experiments | C emission and documented native execution/embedding fixtures exist. Current host declarations and source JSON operations reject native emission with `E_NATIVE_FEATURE`. This is partial native coverage, not a complete current-language backend. |
| Application evidence | Three exploratory blocks/nine participant sessions are documented: planner priorities, clearance repair, and pin-role contract changes. These demonstrate feasibility, not a comparative reliability/productivity advantage. The scored pilot remains uncompleted in those records. |

## P1: practical completion and evidence

### F01 — Publish an authoritative current language specification

**Status:** inconsistent documentation. **Layer:** specification/tooling. **Effort:** S–M.

[semantics.md](../semantics.md) still says there are no modules, generics, compile-time execution, standard library, or native backend, then appends implemented extensions. Its entry/signature and literal descriptions also retain scalar-MVP restrictions. Older optional/generic documents are similarly superseded. New trial records contradict broad older statements that no agent attempts exist.

Implement a current feature matrix with supported syntax, explicit restrictions, backend coverage, compiler identity, and linked executable examples. Mark historical checkpoints as historical. Separate “implemented,” “tested at this revision,” and “planned.” Include a machine-readable feature/version report so agents can inspect the installed executable.

**Acceptance:** the documented supported examples execute against a pinned release; the unsupported examples reject as documented. No top-level current reference says an implemented feature is absent. Preserve historical measurements without relabeling them as current runs.

### F02 — Report independent errors in one checking pass

**Status:** incomplete recovery. **Layer:** checker/diagnostics. **Effort:** L.

The `multiple_errors` probe has unrelated undefined names in two functions but receives one error. After fixing the first function, the second error appears. [Diagnostic failure methods](../../src/diagnostic.zig) return `SourceError`, and the checking pipeline propagates failures. Structured JSON already exists; collecting it in a different format will not solve sequential discovery.

Recover at safe declaration/function boundaries, group downstream cascades under their root error, and expose incomplete checking explicitly. Never publish a successful checked program from recovered placeholders.

**Acceptance:** one invocation reports both independent faults with stable source ranges; dependent errors are bounded rather than multiplied; fixing either fault preserves the other's diagnostic. Execution remains forbidden until the program fully checks.

### F03 — Add reusable generic containers and collection algorithms

**Status:** partial primitives; general library missing. **Layer:** language/library. **Effort:** L, staged.

Buffers and typed pools exist, but [their AST declarations](../../src/ast.zig) have no type parameters. `buffer Vec<T:copy>:T` rejects. The embedded [standard-module registry](../../src/standard_library.zig) supplies only `std_json` and `std_text`. A generic record wrapping a concrete buffer does not supply an element-generic buffer.

First implement generic buffers/pools with explicit ownership and effect contracts for copyable elements. Build reusable vector, map/set, queue, sorting, and searching APIs as application demand warrants. Treat containers of owned elements as a later explicit extension: current buffer/pool element restrictions intentionally exclude them.

**Acceptance:** the same library implementation serves two unrelated nominal element/key types without per-type source duplication; growth remains explicit; deletion and failure paths preserve ownership. Begin with the collections actually needed by planner/EDA workloads, not every container at once. Coordinate with F04 and F14.

### F04 — Borrow whole owned containers and owner-bearing records

**Status:** explicitly unsupported. **Layer:** ownership checker/runtime. **Effort:** L.

`fn inspect(x:&B)` for an owned buffer rejects with `E_RESULT_BORROW`. [sema.zig](../../src/sema.zig) explicitly requires owned/result-bearing parameters to transfer by value. Element slices already work, but cannot represent every operation on a collection owner or a record containing several owners.

Add shared/exclusive references to selected owned types, starting with read-only container inspection and mutation through a container owner. Specify growth versus outstanding element views, partial moves, cleanup effects, and returned references. Keep result-handling obligations separate; borrowing a result must not silently discharge it.

**Acceptance:** a helper inspects a buffer-bearing record without moving it; another edits one owned container without returning the entire owner. Moving/destroying the borrowed owner and invalidating live element views still reject. Ordinary and generic bodies obey the same rules.

### F05 — Provide typed text and ordinary-JSON APIs

**Status:** low-level foundation implemented. **Layer:** standard library. **Effort:** M–L.

[std_json](../../src/stdlib/std_json.my) exposes a mutable `i64` document tape, numeric node/slot arguments, and zero as the missing-node convention. [std_text](../../src/stdlib/std_text.my) provides read/emit/decimal-number helpers. Plain JSON parses correctly in the control; missing text literals or missing JSON are not the problem. The [pin-role trial](../experiments/direct-agent-pin-roles-20260907.md) also records application parser-encoding maintenance, although it is not an evaluation of these new standard modules.

Add checked node accessors, named node kinds, optional field results, array/object iteration, escaped ordinary-JSON writing, text comparison/search, parsing, and a bounded builder. Define bytes versus validated UTF-8 explicitly. Consider typed conversion from ordinary JSON separately from the existing `typed-json-v1` protocol.

**Acceptance:** a new optional JSON field can be parsed, validated, and emitted without application code knowing tape offsets or parser key encodings. Missing/null/wrong-type/invalid-UTF-8 cases remain distinct; output escaping and numeric boundaries pass independent tests.

### F06 — Standardize reusable option/result/error APIs

**Status:** language support exists; library contracts are fragmented. **Layer:** library/builtin adapters. **Effort:** M.

Named unions/results, `try`, must-handle obligations, generic nominal wrappers, and partial moves already work. Many [buffer operations](../experiments/buffer-operations.md), [resource operations](../experiments/source-resources.md), and standard modules still use provisional `i64` codes and separately declared status types.

Publish reusable option/result conventions and named error categories, with explicit adapters where builtins currently require numeric error payloads. Add context-preserving error conversion helpers without implicit loss of owned error resources. Dedicated nullable syntax is not required.

**Acceptance:** application code handles allocation-capacity, I/O-denied, parsing, and absent-value cases without magic numeric comparisons. Wrapping/propagating an error preserves its category and owned payload; ignored fallible values still reject.

### F07 — Fill small value and control-flow usability gaps

**Status:** absent constructs, some with workarounds. **Layer:** syntax/checker/lowering. **Effort:** M per staged subset.

Probes reject builtin `void`, module constants, type aliases, `break`, `continue`, and `for`; the [AST](../../src/ast.zig) exposes only while-style loops and statement matches. Empty records can model unit, helpers can return constants, and loops can use explicit flags, so these are usability costs rather than inability to express basic computation.

Prioritize a unit result convention, immutable module constants, and structured loop exits. Then evaluate iteration syntax and value-producing matches. Introduce transparent aliases only with clear nominal-domain distinctions. Each addition needs generic, formatting, source-map, and cleanup support.

**Acceptance:** representative loops no longer require artificial completion flags or dummy success integers. `break`/`continue` nested inside borrow/arena/result scopes perform correct cleanup and cannot abandon must-handle obligations. Constants have defined initialization and dependency rules.

### F08 — Add bounded bulk I/O to the application host

**Status:** byte-at-a-time application host. **Layer:** host/library. **Effort:** M.

[mylang-io](../../src/byte_io/host.zig) exposes `length`, `byte`, and `put`; standard text emission invokes one host call per byte. This is adequate for the current bounded applications but puts transport machinery into common program paths. Generic host declarations accept copied ordinary values; [borrowed host signatures](../experiments/host-functions.md) are currently excluded.

Start with bounded copied blocks and explicit short-read/write results, retaining capability grants, callback/work budgets, and publication rules. A borrowed buffer host ABI is a separate, more demanding step. Expose useful runner limits rather than assuming the current large constants fit every deployment.

**Acceptance:** stream a multi-block binary payload including NUL/invalid UTF-8 with O(blocks) callbacks, exact byte preservation, bounded memory, and specified behavior on partial failure. Benchmark the boundary; no speedup is presumed from source inspection alone.

### F09 — Package scoped filesystem/network providers for real applications

**Status:** capabilities/resource operations implemented; general application integration incomplete. **Layer:** trusted host/library. **Effort:** M–L.

The filesystem-entry probe fails with `CapabilityUnavailable` in the ordinary CLI. [Resource requests](../experiments/source-resources.md) are provider-defined byte protocols. [Attenuation](../experiments/attenuation.md) narrows read/write/complete operations but does not derive directory or endpoint scopes. Existing native provider experiments do not make the current VM CLI a general file/network application runner.

Provide documented host adapters, grant configuration, directory/endpoint policies, and predictable errors. Keep process launching a separately granted future operation. Broad HTTP/TLS/async support should follow an actual application need.

**Acceptance:** an application can use a configured directory and endpoint; attempts outside the scope reject before effects. Test write restrictions during acquisition (including create/truncate), path resolution, resource cleanup, partial I/O, and provider lifetime. These are trusted host contracts, not proof against a malicious host callback.

### F10 — Make application tests convenient in the language workflow

**Status:** strong external harness foundation; no dedicated guest test/assert facility in the inspected syntax/CLI. **Layer:** tooling/library. **Effort:** M.

Tests currently rely heavily on Zig roots, Python drivers, and external application oracles. Add a standard way to discover and run ordinary `.my` test functions, assert structured expected values, filter cases, and inject deterministic providers. This can begin as a tool/library feature; it need not change ordinary language validity or move Guardian policy into guest semantics.

**Acceptance:** an agent adds an application regression without writing a custom Zig host or hardcoding a trial path. Failures identify expected/actual values and source locations. Empty selections, skipped tests, traps, and infrastructure failures are reported distinctly.

### F11 — Extend safety validation across feature interactions

**Status:** substantial targeted tests; broader assurance remains work. **Layer:** validation. **Effort:** ongoing M–L.

Existing ownership, arena, generic, JSON, and host tests include allocation-failure and trap-boundary coverage. The [borrowing audit](../experiments/b-audit.md) explicitly scopes its guarantees; it is not a full-language soundness proof. This audit found restrictions and coverage needs, not a demonstrated memory-corruption exploit.

Add generated valid/invalid programs combining ownership, partial moves, generic specialization, arena escape, JSON, host failure, and control flow. Compare generic and concrete behavior; exercise Debug/optimized host builds and allocator failures. Fuzz parsing/checking and typed runtime boundaries with independent invariants and retained minimized failures. Existing bytecode validation is not an advertised hostile-bytecode sandbox.

**Acceptance:** reproducible campaigns retain seeds, source/tool hashes, coverage and minimized regressions; invalid source produces bounded diagnostics rather than crashes; cleanup/accounting invariants hold. New F04/F12/F13 features require explicit adversarial cases before broad use. [libFuzzer](https://llvm.org/docs/LibFuzzer.html) is one established coverage-guided mechanism, not a required project dependency.

## P2: expressiveness and larger applications

### F12 — Checked splitting of disjoint borrows

**Status:** whole-allocation conflicts. **Layer:** borrow checker/VM leases. **Effort:** L.

The disjoint-slice probe rejects with `E_BORROW_CONFLICT`; [borrowing rules](../experiments/borrowing.md) lock whole allocations. Add an explicit checked split operation before attempting arbitrary index-range proofs. Runtime checks establish the partition; static and runtime loan identities preserve sibling independence and suspend the original parent.

**Acceptance:** write one half while reading/writing the other; reject overlap, parent reuse, buffer growth, owner destruction, and invalid split bounds. Cover empty partitions, nested splits, returned views, and cleanup. Rust's [checked mutable splitting API](https://doc.rust-lang.org/std/primitive.slice.html#method.split_at_mut_checked) supplies a useful precedent. This feature does not itself introduce threads.

### F13 — More precise lifetimes and stored views

**Status:** deliberate restriction. **Layer:** type/region system. **Effort:** L–XL.

[Reference returns](../experiments/returned-references.md) have one declared input origin; reference fields reject in the probe. [Arena analysis](../experiments/source-arenas.md) conservatively merges dependencies and can retain dependencies from unrelated helper inputs.

First improve owner-return provenance and field-sensitive region summaries where real helpers are blocked. Then consider lifetime-parameterized stored references and returns selecting between multiple inputs. Do not weaken checks simply to accept examples.

**Acceptance:** a helper can safely return the intended outer-lifetime value despite an unrelated scratch argument, while true scratch escapes reject. Any stored view becomes unusable before its backing dies. Generic substitutions preserve the same relationships.

### F14 — Complete the useful generic contract surface

**Status:** substantial but bounded generics. **Layer:** checker/type system. **Effort:** L.

[Generic arrays](../experiments/generic-arrays.md) use explicit lengths and exclude length parameters and parameter-dependent enum keys. [Structural contracts](../experiments/structural-constraints.md) restrict composite signatures, returned references, nominal-type constraints, and method shapes. Explicit call type arguments are required (`E_GENERIC_ARITY` in the inference probe).

Prioritize const length parameters, ownership-aware container contracts, and the structural signatures demanded by reusable libraries. Add safe local type-argument inference only if it reduces friction without ambiguous overload/search behavior. Generic records/results themselves are already implemented.

**Acceptance:** one tested helper/library works across lengths and nominal types, and invalid uncalled templates still reject. Bound specialization growth and maintain concrete/generic diagnostic agreement. Coordinate with F03/F04 before designing a universal trait system.

### F15 — Function values and bounded callbacks

**Status:** absent in expression/type/bytecode models; function-value probe rejects. **Layer:** language/runtime/effects. **Effort:** L.

Introduce typed function references first for sorting, visitors, and reusable algorithms. Define the callable's effect ceiling and ownership modes. Capturing closures require an additional capture/lifetime/allocation design; they are not a necessary first step. Existing registered host callbacks are a different facility.

**Acceptance:** a guest sorting/visitor routine accepts a typed guest callback; calling an effectful callback under a smaller effect bound rejects; captured owners, if later supported, cannot be duplicated or outlive backing storage. Update navigation and dependency analysis for indirect calls.

### F16 — Numeric operations beyond the current integer subset

**Status:** bitwise syntax and floats absent. **Layer:** types/operations/runtime. **Effort:** M for integer extensions; L for floats.

[AST operators](../../src/ast.zig) contain arithmetic/logical/comparison operations, and [runtime types](../../src/runtime_values.zig) have integer/Boolean/capability primitives. The bitwise and `f64` probes reject. The JSON parser recognizing numeric syntax does not provide guest floating-point arithmetic.

Add bitwise operations, shifts, and explicit wrapping/saturating integer operations when binary/device workloads need them. Treat floats/math as a separate application-driven decision with specified NaN, infinity, rounding, conversions, equality, serialization and backend behavior.

**Acceptance:** width-boundary and invalid-shift cases behave identically across host optimization modes. Floating-point behavior, if introduced, has independently specified edge cases rather than accidental host semantics.

### F17 — Reusable packages and versioned interfaces

**Status:** modules exist; package distribution/version resolution is not implemented in the inspected loader/CLI. **Layer:** tooling/module identity. **Effort:** M–L.

Start with explicit local dependency roots and immutable version/hash manifests; add package transport only when useful. Define how package identity affects nominal types, reserved standard modules, schemas and compiler/navigation caches. Review re-exports and transparent aliases separately from import resolution.

**Acceptance:** two applications consume the same library without copying files; locked builds resolve identical inputs offline; incompatible versions and nominal identities do not silently merge. Source inventory and verification receipts include dependency and standard-module bytes.

### F18 — Clearer memory budgets and narrower allocator authority

**Status:** logical quotas and host budgets exist; no general total-byte promise. **Layer:** allocator/runtime/embedding. **Effort:** M–L.

[Buffer quotas](../experiments/ownership.md) count slots/live allocations, while immutable values and VM bookkeeping allocate separately. Execution arenas may retain backing after logical owner release. The root allocator capability shares authority and quotas; independent child budget attenuation is not provided by source arenas.

Expose named accounting categories and high-water statistics, configurable application budgets, and optional child quotas that cannot amplify authority. Define whether and which exhaustion paths are guest-recoverable; actual host `OutOfMemory` currently terminates execution with cleanup. Keep `noalloc` explicitly scoped to guest backing operations.

**Acceptance:** nested allocation cannot evade parent quotas; reports distinguish logical live capacity, retained arena backing and host bookkeeping. Allocation churn, growth peaks, snapshots, and failed acquisitions have predictable accounting. A byte cap must name exactly which allocations it includes.

## Conditional experiments and expansion

### F19 — Typed holes, execution explanations, and executable contracts

**Priority:** P2 experiment. **Status:** proposals, with useful foundations. **Layer:** frontend/debug tooling/VM. **Effort:** L, separate experiments.

The hole probe rejects; JSON errors, ownership provenance and [navigation context](../experiments/navigation-client.md) already exist. Extend them with typed implementation obligations, bounded value/branch explanations, replayable test-provider inputs, and named executable laws. Whole-program differential change contracts are a further experiment, not an existing guarantee.

**Acceptance:** in matched tasks, these features improve correct next attempts or total completion effort without leaking hidden expectations or accepting unresolved holes. Replay must detect incompatible host-call sequences. Keep sampled counterexamples distinct from proofs. [Typed-hole contextualization research](https://arxiv.org/abs/2409.00921) provides relevant prior art; benefit to this language remains to be measured.

### F20 — Semantic incremental compilation when measurements justify it

**Priority:** P3 performance trigger. **Status:** exact verdict and syntax reuse implemented; changed projects recheck semantics. **Layer:** compiler/tooling. **Effort:** L–XL.

[Recorded larger-project checks](../experiments/large-project-checking.md) observed edited checks around 5–15 ms; they are historical synthetic measurements, not new audit timings. The persistent development host reloads between requests with fresh guest state; it does not preserve arbitrary mutable state.

When rich real workloads make checking expensive, cache semantic queries using declaration/interface, generic, effect, ownership/cleanup and source dependencies. Benchmark navigation and serialization costs separately. Persistent-state migration and incremental native linking are distinct projects.

**Acceptance:** cached and fresh results/diagnostics agree across body/signature/type/effect/import changes, including negative results and interrupted work. Record p50/p95 edit-to-test latency; do not justify the cache solely by an unchanged-source hit.

### F21 — A current-language native backend

**Priority:** P3 execution-performance/deployment trigger. **Status:** partial C backend; direct LLVM/custom machine-code paths absent from the reviewed compiler. **Layer:** backend/runtime. **Effort:** XL.

The installed emitter rejects both host declarations and source JSON. Extend coverage through the existing C route or choose an LLVM/custom backend against a measured workload. Preserve a shared semantic representation, runtime contracts, source diagnostics, cleanup, host ABI, and a specified treatment of step/frame budgets.

**Acceptance:** a representative application runs with matching results and observable effects on VM and native paths, including failures, with measured compile/run/memory costs. Unsupported features reject before partial output. JIT compilation is optional; a new backend should not be a hidden prerequisite for VM language features.

### F22 — Concurrency, starting with a bounded model

**Priority:** P3 application requirement. **Status:** no guest threading/async memory model. **Layer:** language/runtime/host. **Effort:** XL for shared-memory threads.

[The memory store](../experiments/borrowing.md) is single-thread-owned; host callbacks are synchronous and require lifetime/serialization discipline. An arena does not make concurrent allocation/reset safe. Improve neither claim by merely allowing more borrow syntax.

Choose isolated workers/message passing, scoped parallel work with disjoint ownership, or shared-memory threads deliberately. Define transfer/share rules, synchronized bookkeeping/refcounts/allocators, host provider behavior, cancellation, joining, and arena lifetime/reset coordination. Async I/O also needs a scheduling and suspended-borrow design.

**Acceptance:** workers cannot retain storage after its arena ends; overlapping unsynchronized read/write rejects or is unavailable; cancellation releases resources; provider/reentry rules remain enforceable. Isolated workers can be explored without first implementing arbitrary stored references or Rust's entire lifetime system.

### F23 — Source-level compile-time evaluation

**Priority:** P3 concrete generation/constant need. **Status:** restricted evaluator and result cache exist; general source compile-time expressions are absent. **Layer:** frontend/evaluator. **Effort:** L.

[Restricted evaluation](../experiments/restricted-evaluation.md) already supports bounded effect-free execution as a tool. Integrate only the source forms needed for constants, tables or schema generation, with explicit inputs, source mapping, limits and target semantics. Avoid an unrestricted macro system as the initial implementation.

**Acceptance:** changing any declared source/input/target dependency invalidates generated results; forbidden effects and evaluation-budget failures yield located errors; host/target layout differences cannot silently alter output. F07 module constants can start without unrestricted computation.

### F24 — Measure realistic agent maintenance outcomes

**Priority:** P1 supporting evidence. **Status:** exploratory results exist; comparative effectiveness unsettled. **Layer:** evaluation/tooling. **Effort:** M and repeated trials.

Read [priority calibration](../experiments/direct-agent-calibration-20260907.md), [clearance repair](../experiments/direct-agent-clearance-20260907.md), and [pin-role maintenance](../experiments/direct-agent-pin-roles-20260907.md) together. They document nine sessions and successful private checks, but different early build policies, limited task sizes, unavailable model/token details, and no demonstrated language advantage. This is more evidence than “no actual attempts,” and less than a general performance claim.

Repeat repair, feature, and cross-module contract tasks with comparable fresh contexts and frozen budgets. Add owner-heavy/generic changes and longer maintenance sequences. Fix portable test paths and onboarding independently of language changes. Preserve independent behavioral grading and failed/abandoned outcomes.

**Acceptance:** reports distinguish edited submissions, failed submissions, tool round trips, compiler/check time, reasoning-inclusive wall time, and available token/cost data. Evaluate one language/tooling change at a time where possible. Gate/style friction must not be counted as detected application bugs.

## Suggested implementation sequence

1. **Establish a reliable reference:** F01 and F24; preserve current safety and behavioral tests.
2. **Reduce immediate application friction:** F02, F05, F06, F08 and F10. Most library/host work can proceed before broadening the type system.
3. **Enable reusable libraries:** F04 and F03, followed by the specific F14 contracts those libraries need. Stage F07 into small language changes with complete cleanup coverage.
4. **Broaden safe memory access:** F12 first, then targeted F13 precision. Run F11 continuously; introduce F18 where deployments need tighter limits.
5. **Add application reach:** F09, F15–F17 as real programs require them.
6. **Choose expansion by evidence:** F19 experiments; F20 when checking is a bottleneck; F21 when guest execution/deployment needs native code; F22 when actual parallelism is required; F23 for concrete compile-time tasks.

The first useful milestone is a new disk-loaded application that can parse ordinary input, use reusable collections, report structured errors, and add local regression tests without changing the Zig host or copying application-specific infrastructure. The next is a multi-file maintenance task using ownership/generics and receiving all independent diagnostic obligations together.

No immediate requirement was established for inheritance, arbitrary unsafe pointers, unrestricted operator overloading, macros, a tracing garbage collector, self-hosting, or three permanently maintained execution engines. Their absence alone does not make this language incomplete for its chosen purpose.

## Probe results and review limits

The nine successful controls exercised scalar execution, byte-literal slices, generic records, arenas, structural contracts, typed JSON, modules, standard text output, and ordinary JSON parsing. Other probes reproduced documented exclusions or enforcement. In particular:

| Probe | Observed result | Audit use |
| --- | --- | --- |
| Two unrelated invalid functions | One `E_UNKNOWN_NAME`; fixing it exposed the second | F02 |
| Typed hole | `E_TOKEN` | F19 |
| `f64`, builtin `void` | `E_UNKNOWN_TYPE` | F16, F07 |
| Bitwise expression | `E_SYNTAX` | F16 |
| `break`, `continue`, `for` | `E_EXPLICIT_DISCARD_REQUIRED` | F07; these spellings are parsed as ordinary names, not supported control flow |
| Function as a value | `E_UNKNOWN_NAME` | F15 |
| Type alias, module constant, generic buffer | `E_SYNTAX` | F07, F03 |
| Omitted generic type argument | `E_GENERIC_ARITY` | F14; an intentional explicitness rule |
| Reference to an owned buffer | `E_RESULT_BORROW` | F04 |
| Disjoint simultaneous buffer-like views | `E_BORROW_CONFLICT` on a fixed array | F12 |
| Stored reference field | `E_TYPE` | F13 |
| Allocation under `noalloc` | `E_EFFECT_BOUND` | Positive safety enforcement control |
| Filesystem capability requested through ordinary CLI | Host `CapabilityUnavailable`, exit 2 | F09; no provider was supplied |
| Native host call / source JSON emission | `E_NATIVE_FEATURE`, no emitted source | F21 |

No full compiler-regression, concurrency, hostile-input security, production networking, or native-performance certification is implied. Historical test counts and timings remain attributed to their own records. Before implementing an item, check whether ongoing working-tree changes have already addressed it.
