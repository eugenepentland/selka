# Research: do interfaces justify their cost for parallel agent development?

15 September 2026 · research addendum to the
[implementation audit](interfaces-and-agent-development-2026-09-15.md)

## Decision

**Independently checkable contracts are justified. A full Go-style runtime
interface feature is a plausible next step, with an unproven incremental benefit
over this language's existing modules and callbacks.**

The research supports a more qualified recommendation than the earlier design
endorsement. Interfaces can make application code easier to understand, but they
add language and compiler rules. Whether they reduce total development complexity
depends on how much repeated state plumbing, coupling, and coordination they
remove. Zero added complexity is not a credible promise.

Interfaces are compatible with incremental compilation and testing. Getting the
benefit requires separating contract dependencies, implementation dependencies,
and test dependencies; adding syntax does not provide that separation by itself.

## Evidence and its limits

This review uses original research papers, compiler documentation, language-team
guidance, and firsthand engineering reports. Sources were checked on 15 September
2026. These evidence types answer different questions:

| Source | Finding relevant to this decision | Evidence limit |
| --- | --- | --- |
| [Parnas: criteria for decomposing systems into modules](https://prl.khoury.northeastern.edu/img/p-tr-1971.pdf), especially the independent-development discussion | Hiding representation decisions behind relatively simple operation contracts lets independent development begin earlier and reduces the knowledge needed to understand a module. | Foundational design argument with examples; it does not compare language interface features or AI agents. |
| [Go Code Review Comments: Interfaces](https://go.dev/wiki/CodeReviewComments#interfaces) | Define interfaces around actual consumer requirements. Avoid speculative interfaces and producer-side interfaces introduced merely for mocking. | Experienced engineering guidance, not a controlled productivity study. It still explicitly demonstrates a consumer using a fake. |
| [Google Go best practices: Interfaces](https://google.github.io/styleguide/go/best-practices.html#interfaces) | Small interfaces can narrow a large API; unnecessary interfaces and layers increase the burden of understanding code. | Guidance for a language already possessing interfaces, not proof that adding them to mylang is worthwhile. |
| [Towards a Science of Scaling Agent Systems, v3](https://arxiv.org/html/2512.08296v3), revised 8 April 2026 | Examines 260 configurations across six benchmarks, including SWE-bench Verified and Terminal-Bench. Benefits depend on task structure and coordination. SWE-bench results show aggregate degradation across the tested multi-agent architectures. | The coding benchmark uses only 20 selected instances per configuration, with wide intervals and variation by model. It tests agent architectures, not language interface support, and does not establish mylang development speed. |
| [Why Do Multi-Agent LLM Systems Fail?, v3](https://arxiv.org/html/2503.13657v3), revised 26 October 2025 | Its 1,600+ traces across seven frameworks identify failures involving system design, agent alignment, and verification. | Diagnostic evidence across several task types, not a causal test of interfaces as a remedy. |
| [Anthropic's parallel C-compiler project](https://www.anthropic.com/engineering/building-c-compiler), 5 February 2026 | Agents progressed on distinct failing cases; a shared blocking kernel failure caused duplicated work. A harness using GCC for other files made separate failures independently actionable. | Firsthand coding example. No controlled comparison of interface features or a matched single-agent baseline. |
| [OCaml modules and separate compilation](https://ocaml.org/manual/5.4/moduleexamples.html) | Module signatures and implementations are separate compilation artifacts. | Demonstrates an established mechanism for independent compilation; no claim that adopting OCaml's whole module system would simplify mylang. |
| [TypeScript project references](https://www.typescriptlang.org/docs/handbook/project-references.html) | Consumers load declaration outputs from referenced projects; build mode checks which projects need rebuilding. | Demonstrates declaration-based build separation, not language-interface-specific speed. |
| [sbt/Zinc incremental recompilation](https://www.scala-sbt.org/1.x/docs/Understanding-Recompilation.html) | Implementation-only edits can preserve client compilation, while public inferred-type changes can invalidate clients. API fingerprints and dependency tracking drive reuse. | Compiler-specific rules; mylang must implement its own correct dependencies. |
| [Go compiler export data](https://go.dev/src/cmd/compile/README) | Downstream compiler inputs include exported types, inlineable bodies, generic bodies, and escape-analysis summaries. | Shows why unchanged signatures alone do not guarantee unchanged optimized code. |
| [Ekstazi: Practical Regression Test Selection with Dynamic File Dependencies](https://users.ece.utexas.edu/~gligoric/papers/GligoricETAL15Ekstazi.pdf), ISSTA 2015 | Evaluated dependency-based test selection over 615 revisions of 32 Java projects. Tracking files used by tests made selective execution practical. | Supports implementation-dependency tracking in an interface-using language; its measured speedups do not transfer directly to mylang. |
| [Software Engineering at Google: Test Doubles](https://abseil.io/resources/swe-book/html/ch13.html) | Fakes need validation; shared contract tests can exercise both the fake and real implementation. | Tests cover chosen behavior and cannot prove complete equivalence. |

I did not find a controlled study isolating the effect of adding a language-level
interface feature on parallel coding-agent completion time, comprehension, and
incremental build/test cost together. The published evidence supports useful
mechanisms and cautions; the final adoption decision still needs a local trial.

The scaling study's current revision matters: its earlier four-benchmark,
180-configuration results should not be presented as its complete current coverage.
Neither its positive financial-reasoning result nor its negative aggregate coding
result is a transferable percentage prediction for this project.

## Three meanings of “interface”

1. **A module's public contract:** exported names, parameter/result types, effects,
   ownership rules, and shared data. Clients can check against this before the
   implementation is ready.
2. **A named structural constraint:** a reusable requirement such as “this type
   supplies these operations.” Generic code can be checked under those promises.
3. **A runtime interface value:** a value such as `store: Store` that can contain
   providers with different hidden concrete state types and dispatch operations
   to the selected provider.

The requested parallel workflow needs the first capability and a way to select a
fake. The other capabilities may make that workflow more convenient, especially
for several related operations or providers selected at runtime.

**Inference for mylang:** module signatures and existing callback injection can
deliver much of the benefit before adding runtime interface values. A named
constraint alone must not be advertised as supporting arbitrary hidden state;
that requires an additional runtime representation or explicit generic state.

## Does it reduce complexity?

The relevant comparison is the complete program and workflow, including generated
adapters, repeated type parameters, fake setup, compiler diagnostics, and state
ownership. Counting keywords or lines in the interface declaration misses most of
the cost.

| Approach | What it solves | Cost in this language | Appropriate first use |
| --- | --- | --- | --- |
| Existing module contract plus provider selection | A consumer works against a chosen production or fake module | Requires the checker/test-runner separation already identified; replacement and nominal identity rules must stay explicit | A whole dependency selected per test or application |
| Callback plus explicit context, optionally bundled in a record | Substitutable behavior with state; already demonstrated in the audit | State and callback types can spread through signatures; callable-field syntax currently needs a workaround | One operation or a small local dependency |
| Named structural constraint over existing operations | Reusable promises and independently checked generic bodies | Needs naming, record-operation/adaptation rules, and diagnostics; specialization still depends on concrete types | Repeated generic requirements |
| Small runtime interface value | A short public type hides provider state and supports runtime selection | Requires dispatch representation, conversion rules, GC/arena safety, and a coherent receiver model | Several operations over shared state, or heterogeneous providers |

These cost assessments are design inferences from the inspected implementation,
not externally measured rankings.

There is also a risk in making everything generic for presumed performance. Go's
language-team guidance recommends ordinary interface parameters when code only
needs their methods, and callbacks for configurable operations such as comparison.
Its historical implementation-specific performance claims should not be transferred
to mylang. [When To Use Generics](https://go.dev/blog/when-generics)

If a runtime interface is eventually added, keep the easy application spelling
`store: Store`. Make concrete or specialized paths available when measurements
justify them. Determine costs in mylang's backend rather than assuming generics
are automatically faster.

## Incremental compilation: compatible, with explicit dependency rules

The compiler needs a checked contract artifact that can exist independently of a
successful implementation body. It should be derived from canonical declarations,
with one authoritative source for the shared contract; avoid requiring agents to
manually synchronize several header/schema representations.

For this language, that artifact needs observable parameter names and defaults,
types, nominal identities, generic requirements, explicit effect ceilings, and
relevant ownership/representation promises. Private helper bodies and source
coordinates should not determine public contract identity.

An explicit effect ceiling keeps implementation edits from changing a consumer's
promise. The analogy to sbt's explicit return-type recommendation is a design
inference: both keep an implementation detail from silently altering the API.

The following is a proposed invalidation policy, not a description of current
mylang cache behavior:

| Change | Consumer type checking | Code generation | Tests |
| --- | --- | --- | --- |
| Production body changes; observable contract unchanged | Reuse eligible | Rebuild changed implementation; rebuild callers that used its body for optimization | Rerun affected production/integration tests; fake-only tests may be reusable |
| Fake body changes; observable contract unchanged | Reuse eligible | Rebuild fake and any code specialized from it | Rerun affected fake-based tests |
| Required operation, argument, result, effect, or ownership contract changes | Recheck affected clients and provider conformance | Rebuild affected code and adapters | Invalidate affected test receipts |
| Add an unrelated operation to a provider | Existing consumer checks can remain eligible under local, explicit resolution rules | Rebuild affected provider artifacts | Select by implementation/test dependencies |
| Compiler, runtime ABI, relevant build options, or provider selection changes | Reuse only where the corresponding keys permit it | Invalidate affected artifacts | Invalidate affected receipts |

Ordinary indirect calls provide a useful separation: callers need a call contract,
while the provider supplies code. Inlining and specialization deliberately cross
that separation. Track those dependencies instead of promising that all body-only
edits avoid downstream work. Go's export-data design provides a concrete example.

Additional operations on an interface itself are different from additional
operations on a provider: a new required method can invalidate provider
conformance even when no caller invokes it. The sbt documentation illustrates this
kind of dependency with abstract methods. Member-name usage alone is insufficient.

## Incremental testing: preserve the selected implementation dependency

**An unchanged type contract does not establish unchanged behavior.** A provider
can return the wrong price without changing a single type.

Cache successful tests against the selected provider, its relevant implementation
dependencies, test input/fixtures, compiler/runtime, and execution policy. Indirect
calls need sound target dependencies. When targets cannot be established, broaden
invalidation conservatively; do not key tests solely by the interface signature.

The [Ekstazi research](https://users.ece.utexas.edu/~gligoric/papers/GligoricETAL15Ekstazi.pdf)
is useful evidence that selective testing works through implementation dependencies.
Its relatively coarse dependency tracking also cautions against assuming that the
finest possible analysis produces the fastest complete test cycle.

Use reusable in-memory fakes with specified behavior. Run the same public contract
tests against the fake and the production implementation, then retain production
integration tests for real effects. This is the approach described in Google's
[Test Doubles chapter](https://abseil.io/resources/swe-book/html/ch13.html).

Interfaces cannot establish agreements about units, ordering, missing-key behavior,
idempotence, or cleanup from signatures alone. Contract documentation and test
cases need to state those agreements before independent implementation begins.

## Small interface design, if the trial justifies it

My proposed restrictions follow the language's simplicity goal:

- Consumer-owned contracts based on actual call sites.
- One operation-contract model shared with generics and callbacks where applicable.
- Exact parameter/result identity initially; implementations may use a subset of
  permitted effects, while callers retain the complete contract ceiling.
- Local and predictable operation lookup; no implicit global extension search.
- Existing record value semantics and explicit shared state. Define interface
  conversion/copying precisely, including any allocation and arena restrictions.
- Required operations only initially; postpone default implementations,
  inheritance, runtime casts, universal dynamic values, and method-level generics.
- Strong navigation: show the contract, possible providers, selected test provider,
  and the first unsatisfied requirement.

The Go team's August 2026 explanation of generic methods is particularly relevant:
generic interface methods create difficult instantiation problems across separately
compiled packages. It supports keeping that interaction out of an initial design,
rather than treating it as an automatic consequence of adding ordinary methods.
[Generic Methods](https://go.dev/blog/generic-methods)

These are proposed design choices. They are not conclusions experimentally proven
to maximize AI development speed.

## Adoption test for this repository

First fix the common baseline so it supports the intended workflow:

1. Check shared declarations without requiring the real provider's body to pass.
2. Select the fake before checking executable implementation bodies.
3. Preserve nominal type identities and check the selected provider's full contract.
4. Permit safe effect-subset substitution and direct calls through callback fields.
5. Record contract and selected-provider identities in receipts.

The [existing audit](interfaces-and-agent-development-2026-09-15.md) supplies direct
evidence for these needs. A source recheck during this research confirmed that
`native_test_command.zig` still checks the original program first and that callback
effect compatibility remains exact. No new compiler builds or Guardian gates were
run for this research.

Then compare that improved baseline with a minimal named-interface prototype on
representative tasks: a pure transformation pipeline, a stateful store with a fake,
and an effectful external dependency. Use both single-agent and parallel-agent
conditions so the effect of the interface can be distinguished from simply
changing the work decomposition. Keep contracts, tools, models, acceptance tests,
and budgets comparable; repeat runs and vary the order.

Measure:

- Wall time to a correctly integrated result, including planning and merge repair.
- Time blocked waiting for another implementation.
- Total agent cost and compiler-repair turns.
- Contract changes, adapter/state plumbing, and accidental shared-file edits.
- Ability of a fresh reader to identify the implementation, state owner, and effects.
- Cold, unchanged, body-edit, and contract-edit compile/test timings.
- Equivalence of clean and incremental outcomes, including deliberately injected
  wrong signatures, changed effects, wrong behavior, and provider changes.

Adopt interfaces if they remove recurring application complexity and improve the
complete workflow without compromising those correctness checks. If module
contracts and callbacks suffice, keep them as the simpler implementation.

## Recommendation

Proceed with independently checkable contracts and correct provider selection.
Prototype a small named interface only where multiple operations or hidden provider
state create demonstrated friction. Keep full runtime interface support conditional
on that evidence. This preserves the option of a simple `store: Store` application
API while avoiding a language expansion justified only by an unmeasured expectation
about agent parallelism.
