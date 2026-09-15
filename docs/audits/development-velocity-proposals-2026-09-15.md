# Development velocity: comparison with two proposed languages

Audited 2026-09-15.

- **Proposal A:** the attached, twenty-point design beginning “maximum development velocity over the lifetime of a very large codebase”: Python/Go-like source, static guarantees, GC, controlled allocation, architectural boundaries, incremental compilation and testing.
- **Proposal B:** the seven-point design in the request: explicit boundary contracts, capability effects, immutable values with copy-on-write, an incremental query compiler, integrated tooling, deterministic debugging, and deliberate uniformity.

## Verdict

**mylang is substantially aligned with A's application-language design. It is materially less aligned with B's guarantees about local reasoning. Neither proposal's complete large-codebase development experience is implemented yet.**

The strongest existing pieces are static boundary types, nominal data types, exhaustive matching, checked results, transitive effect ceilings, GC with managed arenas, explicit imports/exports, and selective native test execution. These are implemented mechanisms, rather than only design intentions.

The largest semantic gap is **shared mutation invisible in the effect signature**. The largest iteration gap is **limited reuse of checked code, especially when generics are present**. The most immediate tooling gap is **a formatter that currently preserves every input byte**. Rich runtime debugging, general hot replacement, a language server with checked refactorings, and package API compatibility enforcement remain further away.

My recommendation is to preserve the existing core and prioritize those gaps. Adding more surface syntax would do less to achieve the proposals' shared goal: reducing how much implementation a developer must inspect before changing code safely.

## Evidence and scope

This audit combines current source inspection with **42 recorded command/session observations**, including native execution, deliberately rejected programs, cache transitions, and the named-constraint production/fake examples. Full commands, fixture sources, diagnostics, compiler identities, and results are in [the probe evidence](development-velocity-proposals-2026-09-15-probes.json).

The observations used a pinned copy of the installed compiler, whose reported compiler identity begins `c54d594e5ad60689`. Repository HEAD during the probes was `a9e29d4845ab2f8a700eeb238ed03023d2ac701e`; the working tree already contained unrelated edits. The evidence records executable and inspected-source hashes. This distinguishes observed binary behavior from source inspection without assuming the installed binary incorporates every working-tree edit.

No compiler implementation was changed or rebuilt. No full acceptance suite or Guardian gate was run. The small fixtures establish behavior, not large-project performance or comparative developer productivity. Historical audits and old experiment pages were checked against current source and the installed feature manifest where relevant.

## Where the proposals differ

Both proposals favor explicit contracts and fast feedback. A emphasizes a convenient managed application language and a complete development workflow. B makes a stronger semantic commitment: a caller should understand what a function can change from its boundary alone, with immutable value semantics and declared effects supporting that promise.

A is not indifferent to aliasing: it also says passed references should not mutate unexpectedly. Consequently, mylang's shared lists and dictionaries are a departure from **both** proposals, especially B. GC is compatible with either design; choosing GC does not require choosing shared mutable collection semantics.

## Proposal A: requirement-by-requirement comparison

“Strong” means the central mechanism exists; it does not claim production maturity. “Partial” means useful implementation exists but an important part of the requested behavior is missing. “Gap” means the central behavior is absent or deliberately different.

| A item | Assessment | Current mylang behavior |
| --- | --- | --- |
| 1. Local reasoning | **Partial** | Types and explicit capability values help. Effects are optional ceilings, and even `effects()` permits writes through shared collections. |
| 2. Static typing with local inference | **Strong** | Function parameters are typed; non-unit results are declared; ordinary local types are inferred. Omitting a result annotation declares unit rather than inferring a value result. |
| 3. No null | **Strong** | `Option[T]` distinguishes absence. Direct field access on `Option[User]` rejects. `None` is contextual option absence or unit, not a nullable value accepted everywhere. |
| 4. Lightweight errors as values | **Strong, with qualifications** | `Result[T, E]`, checked handling obligations, and `?` exist. Explicit `_ =` may discard a result. Runtime traps are outside the recoverable error type. No `Config!` abbreviation, but explicit error types are a useful contract. |
| 5. Immutability / restricted shared mutation | **Gap** | Locals are mutable; lists/dictionaries share references; nested managed fields remain shared when records are copied. Mutation need not appear in the signature. |
| 6. GC and allocation escape hatches | **Strong in direction** | Tracing GC is the application default; managed arenas control release time without allocator parameters. `noalloc` restricts managed allocation, not all host/runtime allocation. Arenas are not a general allocator API or a hard real-time guarantee. |
| 7. Cheap distinct domain types | **Strong, different spelling** | `domain` gives distinct identity and controlled construction. `type UserId = int` is a transparent alias and does **not** provide distinct identity. Nominal records are another available option. |
| 8. Algebraic data types | **Strong** | Closed enums/unions and exhaustive matches exist. Adding a variant produces a missing-case diagnostic unless a wildcard already covers it. |
| 9. Composition and interfaces | **Partial** | Records, typed callbacks, structural generic requirements, and named constraints support composition and substitution. There is no general runtime interface-value facility; operation constraints currently target public domain operations. |
| 10. Limited inspectable metaprogramming | **Partial / compatible direction** | Bounded constants, typed schemas, codecs and generation tools exist. No unrestricted compile-time or textual macro system. The proposal's general `derive` plus expansion workflow is not established. |
| 11. Explicit imports | **Strong** | Qualified module imports, aliases, explicit exports and privacy checks expose dependencies. |
| 12. Architecture enforced by packages | **Partial** | Import cycles reject; `check-policy` enforces explicit dependency rules. Ordinary build/check commands do not automatically require that policy. Local package locks pin source contents, rather than implement architectural package layers. |
| 13. Function-level incremental compilation | **Partial** | Native function-object caching and in-process ordinary-body reuse work. Persistent typed-body and generic-specialization reuse remain missing. |
| 14. Dependency-aware test reuse | **Strong within current scope** | Passed native tests reuse semantic dependency receipts. A helper edit reran only its affected test in this audit. Project checking still precedes result reuse. |
| 15. Deterministic builds | **Partial** | Compiler/tool/runtime identities, content hashes, package locks and cache contracts provide substantial input tracking. This audit does not establish portable, byte-identical, fully hermetic builds across environments. |
| 16. One official tool | **Partial** | `mylang` integrates checking, building, running, testing, doctests and inspection. Packages, navigation queries and property-law campaigns still have Python drivers; a unified package/benchmark/coverage/LSP workflow is absent. |
| 17. Exceptional diagnostics | **Partial, useful foundation** | Located diagnostics, stable error codes, related spans, effect origins and JSON output help repairs. Some errors still expose internal type names rather than useful source signatures. |
| 18. Excellent runtime debugging metadata | **Partial / major remaining work** | Native traps have source locations and call stacks. The tested bounds trap lacked index/length values; native record/replay and time-travel debugging are absent. |
| 19. Structured concurrency | **Gap today** | Guest task/spawn facilities are absent. Scoped tasks with isolated data are a proposal; the current manifest describes parallelism as one guest process per task. |
| 20. Make invalid states hard to express | **Strong foundation** | Nominal types, closed variants, complete record construction, options and checked results already provide the main modeling tools. They do not enforce arbitrary business invariants automatically. |

Primary references: [functions](../functions.md), [results and options](../results-and-options.md), [data types](../records-and-unions.md), [aliases](../type-aliases.md), [managed memory](../managed-memory.md), [arenas](../arenas.md), [modules](../modules.md), [effects](../effects.md), [cache behavior](../tooling/caches.md), [packages](../tooling/packages.md), and [current feature manifest](../../src/features.json).

## Proposal B: requirement-by-requirement comparison

| B item | Assessment | Important distinction |
| --- | --- | --- |
| 1. Boundary types, sums, checked errors | **Close** | The central type and error mechanisms exist. A missing unit return annotation still has one fixed meaning. Exhaustiveness gives a change checklist only where matches do not use a catch-all. |
| 2. Effects in signatures | **Partial** | Explicit transitive bounds exist, but are optional; the vocabulary has eight fixed categories. No user-defined `Db`/`Payments` effect rows, general algebraic handlers, or tracked shared-state mutation. Typed provider parameters can distinguish dependencies without introducing those effects. |
| 3. Immutable values, visible mutation | **Substantial mismatch** | Collections use shared references rather than copy-on-write. A copied record can still expose mutable descendants. `effects()` does not mean input immutability. |
| 4. Sub-second queries and hot replacement | **Partial caching; major gap on the complete promise** | Selected caches work. Generic code prevents existing session body reuse; one-shot edits recheck bodies. The default loader permits 256 modules/16 MiB. General live function replacement and preserved-state migration are absent. |
| 5. Tooling is the language | **Partial** | Checked navigation/schema data and a shared CLI exist. Actual canonical formatting, an LSP, checked rename/extract/move, library codemods and publishing-time API-break checks are not present as the proposed workflow. |
| 6. Deterministic debugging and testing | **Partial testing; debugging gap** | Doctests, deterministic test receipts and bounded integer property-law campaigns exist. Native structured trace/replay and time-travel debugging do not. Explicit effects alone do not supply them. |
| 7. Deliberately boring | **Mostly aligned in intent** | No class inheritance or Python dynamic object model; explicit dependencies, nominal data and restricted metaprogramming favor uniformity. Mixed shallow-value/reference semantics, inconsistent callback effect substitution and documentation drift undermine that uniformity. |

The absence of an `async` spelling is not evidence that the proposed single-model concurrency system already exists: mylang currently lacks that guest concurrency system altogether.

## Findings that matter most

### 1. An empty effect set does not make a function pure

This program was compiled and executed natively. It exited successfully because the caller's list was changed:

```mylang
# doc: expect 0
def overwrite(values: list[int]) -> None effects():
    values[0] = 42

def main() -> int:
    values = [1]
    overwrite(values)
    if values[0] != 42:
        return 1
    return 0
```

A second native probe put the list inside a `record`, passed the record by value, and changed the same list through the helper's copied record. The caller observed that change too.

By contrast, appending under `effects()` rejects because append contributes `managed_allocation`. The current distinction is about allocation and authority categories, not whether external aliases observe a write. The eight-effect vocabulary in [effect_set.zig](../../src/effect_set.zig) has no mutation category.

**Consequence:** a signature alone cannot establish that input data stays unchanged. A caller must know the nested sharing structure and inspect the implementation, which is exactly the reasoning cost both proposals seek to reduce.

**Decision to make:** either keep shared mutable collections and introduce checked read-only/mutation contracts, or adopt value semantics consistently through mutable descendants. Adding a `mutation` word without enforcing alias behavior would not resolve the issue. Copy-on-write would also require decisions about nested graphs, cycles, identity and performance; changing only outer-list assignment is insufficient.

### 2. The effects system has a solid foundation, but weak defaults for public boundaries

Fresh probes established all of these:

- An unannotated helper may print.
- The same helper with `effects()` rejects with `E_EFFECT_BOUND`.
- `effects(db)` rejects: applications cannot add arbitrary effect names.
- `noio` accepts a call to an explicitly declared `effects(host)` external function.
- A function declared `effects()` cannot substitute for a callback parameter declared `effects(output)`.

The last point comes from exact effect-mask equality in [callables.zig](../../src/callables.zig). Structural operation contracts already allow an implementation whose effects are a subset of the permitted set in [structural_constraints.zig](../../src/structural_constraints.zig). This inconsistency makes capability substitution harder than the proposal suggests.

**Recommendation:** require explicit effect ceilings at exported/shared contracts, retain inference for local helpers, and make callback substitution accept a smaller effect set where sound. This improves current workflows before introducing a substantially larger algebraic-effect system. Document that `noio` permits clock, random, environment and host effects; it is not a determinism promise.

### 3. Selective tests work; the compiler still repeats important semantic work

These results were reproduced with isolated caches:

| Change | Native tests actually executed | Cached passing results |
| --- | ---: | ---: |
| Initial run | 2 | 0 |
| Unchanged rerun | 0 | 2 |
| Change helper used by test A | 1 | 1 |
| Change unused helper | 0 | 2 |
| Force execution | 2 | 0 |
| Introduce a type error | Setup rejected | No cached success reported |

An unchanged one-shot project check also reused its successful verdict; an edited project missed it; an invalid edit rejected. In a checking session, changing one ordinary function checked one body and reused two. Adding an unused generic function to that same project caused the next edit to reuse **zero** ordinary bodies and check all three again.

This follows [semantic_key.prepare](../../src/semantic_key.zig): generic functions and other unsupported forms disable the ordinary-body reuse path. The specialization key is explicitly documented in source as a primitive for a future reuse engine. [main.zig](../../src/main.zig) passes no body cache on the ordinary one-shot path; [native_test_command.zig](../../src/native_test_command.zig) checks before looking up test results.

The default module count is also a concrete ceiling, not merely a missing benchmark. A 257-module input rejected with `E_MODULE_LIMIT`, consistent with [project.zig](../../src/project.zig)'s 256 modules, 4,096 imports, 4 MiB/file and 16 MiB/project defaults. Those limits can be changed in an implementation, but today's default workflow does not establish suitability for the proposals' millions-of-lines target.

**Recommendation:** prioritize persistent checked-body reuse and generic specialization reuse, then measure end-to-end edit/check/affected-test latency on increasingly large, representative applications. Include generics, managed data and imported types. Cache key matches and invalidation explanations should not be reported as executed work actually skipped.

### 4. The formatter does not deliver uniform source

Both `fmt` and `fmt --check` accepted:

```text
def main() -> int:
    value=  40+2
    return value
```

`fmt` returned those bytes unchanged. [formatter.zig](../../src/formatter.zig) implements formatting by duplicating the original input and ignoring the supplied tokens and type declarations.

This is a direct gap against both proposals' one canonical style. Significant indentation still leaves ample formatting work: spaces around operators, declaration separation, trailing whitespace and other layouts. The language's indentation rules do not themselves normalize those choices.

**Recommendation:** implement a formatter that changes noncanonical valid input, preserves comments, and produces an idempotent result. Have `--check` reject input that differs from that canonical result.

### 5. Navigation is useful, but safe refactoring and rich debugging are separate deliverables

[Source navigation](../tooling/navigation.md) already provides checked symbols, references, types, effect summaries and pinned source snapshots. That directly helps the “read five functions instead of fifty” objective. It does not yet provide an editor service that performs checked rename, extract or move operations.

The native bounds probe reported `R_LIST_BOUNDS`, its original source location, and the two-function call stack. It described the error as `native execution failed`; it did not report the bad index `14` or list length `1`. That is substantially less explanatory than A's runtime diagnostic example.

The installed manifest explicitly lists bounded VM tracing and in-memory host replay as **removed** on 2026-09-14. The surviving [execution-observations experiment](../experiments/execution-observations.md) describes those historical facilities and must not be counted as current native replay support. [Agent tools](../tooling/agent-tools.md) documents this distinction and the surviving property-law driver.

**Recommendation:** first improve native traps with operation-specific values and repair context. Then implement record/replay at explicit provider boundaries if realistic debugging trials justify it. General time travel and production replay require capture completeness, state/scheduling semantics and storage contracts in addition to effect annotations.

### 6. Architectural and abstraction mechanisms exist, but the default workflow does not finish the job

The architecture probe checked successfully with a deny-all policy file beside it; explicitly running `check-policy` rejected its import. Import cycles rejected in ordinary checking. This is useful enforcement, but projects must wire policy into their required workflow. See [dependency policy](../experiments/import-policy.md).

Named constraints deserve credit: the production checkout example ran natively, and its independently selected fake-provider test passed with forced execution. They already provide reusable static contracts without inheritance. Runtime interface values and arbitrary implementations behind one erased type are a separate capability, not prerequisites for every useful interface abstraction.

There is still a coordination limitation: the native provider-replacement test path checks the original project before applying replacement sources. An unfinished production dependency can therefore block that path. A fake-only entry excludes the production dependency and works today; making selected-provider testing contract-driven would remove more waiting between independent implementations.

[Local packages](../tooling/packages.md) provide offline locked snapshots. They do not implement a registry publishing check, semantic version solving, or automatic rejection of minor-version API breaks. A package compatibility checker could reuse exported schemas, but its handling of defaults, effects, constraints and nominal identities would need an explicit compatibility policy.

## What I would prioritize

| Priority | Work | Reviewable acceptance criterion |
| --- | --- | --- |
| 1 | Decide and enforce the shared-mutation contract | A caller can tell whether a nested collection argument may change without reading the callee. Read-only promises are checked through aliases and calls. |
| 2 | Strengthen public effect boundaries and callback substitution | An exported contract cannot silently gain effects; a callback with fewer permitted effects substitutes correctly. |
| 3 | Finish the everyday tools | Formatting changes noncanonical code; current feature docs agree with the executable; native bounds errors report index and length. |
| 4 | Reuse checked generic code across edits | An implementation-only edit preserves unrelated checked bodies/specializations in ordinary workflows, with real reuse counters and cold/warm diagnostic equivalence. |
| 5 | Make contracts support independent development | A consumer can run against a selected fake while the unselected production body is unfinished; project policy participates in required verification. |
| 6 | Prove the workflow at increasing scale | Repeated representative changes measure complete feedback latency, context examined, repair attempts and successful delivery, including API/effect/type changes. |

After those foundations, structured concurrency, native replay, editor refactorings and package evolution checks should be scheduled against application needs. The [scoped-task design](../concurrency-proposal.md) is relevant future work, but remains a proposal; it should not receive implementation credit.

## How much confidence should the velocity claim receive?

The design fit is encouraging, but a productivity advantage is still a hypothesis. The repository's [historical velocity report](../../experiments/velocity-evidence/v1/report.md) records aggregate delivery time increasing by 11.640% across eight main tasks. That experiment changed several variables and explicitly disclaims causal attribution and a language ranking. It is neither proof of a speed advantage nor proof that mylang is intrinsically slower.

The useful next experiment is a set of unfamiliar-code maintenance tasks: add a union case, change an exported contract, find an aliasing bug, swap a provider, and fix a native runtime failure. Measure how much source the developer or agent must examine, time to useful feedback, and time to accepted correct behavior. Tiny compilation fixtures alone cannot answer the lifetime-development-velocity question.

**Overall:** mylang already has much of A's proposed language foundation. B identifies the more important missing promise: checked boundaries that make effects and shared mutation predictable without opening implementations. Delivering that promise, and finishing the existing tooling/cache paths, would move the language closer to both proposals than a broad expansion of language features.
