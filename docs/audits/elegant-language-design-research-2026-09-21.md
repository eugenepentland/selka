# Language design that makes correct changes cheaper

2026-09-21 · Research and experiment proposals; no language changes or agent trials performed.

**Recommendation:** explore language mechanisms that preserve useful facts across
boundaries. A checked fact should reduce what an agent must inspect, what a caller
must handle, and, where sound, what the compiler must recompute or the runtime must
check. Start with **opaque aggregate domains** and **bounded flow-sensitive
reasoning**. Keep **immutable collections built through local mutation** as the
larger follow-up. Treat stable public contracts and contextual type inference as
separate, narrower experiments.

This is a research shortlist, not a claim that five additions maximize velocity.
The mechanisms have different strengths; none is expected to improve every metric.
The smallest successful intervention might be a library change using today's
language. That is a useful result too.

## What the existing work tells us

| Evidence | Finding to carry forward | Limit |
| --- | --- | --- |
| [Cascade redesign trial](cascade-experiment-results-2026-09-19.md) | Neither redesign recovered its upfront cost on the independent task pack. Reading and verification were substantial costs, including when a requested behavior already existed. | Three repetitions per cell and one chain per arm do not settle whether a design helps longer maintenance sequences. |
| [Elegance metrics](../../experiments/elegance-metrics/findings-2026-09-19.md) | Dependency propagation scores did not predict agent change cost within the tested tasks; extra leaf declarations could improve the score without improving work. | This rejects the proposed proxy on this corpus, not modularity itself. |
| [M1b diagnostic trial](m1b-diagnostic-feedback-readout-2026-09-19.md) | Suggestions missed the practical target; hidden acceptance was already 111/112. More explanatory text alone is not an established velocity improvement. | Treatment delivery, duplicate cases and development/test contamination limit generalization; do not conclude that good diagnostics are useless. |
| [Surface SSA audit](language-level-ssa-2026-09-19.md) | The backend already derives scalar SSA. Surface reassignment restrictions would leave the observed aggregate/helper costs and shared mutation hazards largely untouched. | Internal flow analysis remains useful without changing the assignment model. |
| [Parser performance audit](language-performance-ergonomics-2026-09-20.md) | Avoidable materialization, representation choices and aggregate traffic supplied concrete performance hypotheses. | Its configuration-specific timings are historical. Several recommendations have since been implemented. |
| [M3 readiness](m3-project-invocation-runbook-2026-09-20.md) | An incompatible planner snapshot prevented the proposed cohort from starting. | An experiment cannot establish language productivity if its baseline does not work with its frozen compiler. |

Reading and verification belong in the main productivity outcome. Unlike one
interpretation in the cascade readout, I would not assume design can only reduce
editing: a good boundary should reduce investigation and uncertainty too. Phase
measurements can explain a result, but cannot replace total delivery cost.

## Establish the actual starting point

This checkout already contains substantial uncommitted work. The accompanying
[inspection evidence](elegant-language-design-research-2026-09-21-evidence.json)
records selected source hashes and the installed compiler's feature report.
Inspection began on 2026-09-20 and the report was finalized on 2026-09-21.
Git HEAD alone does not identify the baseline. Feature declarations and inspected
source are evidence of the implementation surface, not a fresh acceptance run.

Already present in source and advertised by the installed compiler:

- Distinct value `record` and reference `class` types, functional record update,
  nominal scalar domains, checked `Result`, `Option`, and named constraints.
- Effects and mutation footprints, including return-origin analysis. Public
  unannotated effects can still depend on inferred implementation facts; class
  mutation has an advisory-footprint exception.
- `bytes.view`, nonallocating numeric parsing and scalar counting, immutable
  `bytes`, mutable `byte_buffer`, and aggregate copy elimination.
- Persistent checked-body and specialization caches, selective native testing,
  focused context, interface fact status and structured typed-hole obligations.

See [records](../records-and-unions.md), [effects](../effects.md),
[bytes](../bytes.md), [caches](../tooling/caches.md), and the
[implementation ledger](agent-usefulness-reports/ledger.md).

Two concrete remaining seams are especially useful for research:

1. The port's [View](../../experiments/sexpr-port/sexpr/view.my) exposes
   `source`, `start`, and `end` as freely constructible fields. Its bounds invariant
   is a comment. `matches` still decodes text and `equal` still copies ranges,
   despite the newer native byte operations. Better library adoption is therefore
   a necessary control before attributing improvement to new syntax.
2. Native `bytes.view` avoids copying payload bytes but allocates a small header
   per view. The application record is an inline owner/range value. These are
   different cost models; replacing every application span with a native view is
   not automatically a performance win. See
   [native_bytes.c](../../src/native_bytes.c) and [view semantics](../bytes.md#views-and-owned-copies).

## Shortlist

Ranks reflect research priority and implementation scope, not measured scores.

| Candidate | Fact preserved | Likely agent benefit | Runtime opportunity | Compilation expectation |
| --- | --- | --- | --- | --- |
| A. Aggregate domains | A value can only be constructed through its defining API | Fewer scattered validation assumptions; representation changes stay local | Validated range/text operations and better representations become safer to expose | Neutral initially; abstraction alone does not improve caching |
| B. Flow-sensitive facts | A guard established a property on a particular value/path | Familiar early returns, fewer unpacking helpers, precise failure explanations | Remove redundant checks only where the backend consumes a valid proof | Extra bounded analysis; may cost more than it saves |
| C. Build then freeze | Published data has no mutable reachable state | Stable snapshots, simpler invariants and transformations | Compact sequences, stable iteration, potentially fewer copies/checks | Extra type/lifetime rules; no initial speedup claim |
| D. Stable public contracts | What clients may rely on survives body changes | Smaller read surface; implementation can be developed independently | Usually neutral; stronger contracts sometimes help optimization | Most direct candidate for less downstream rechecking |
| E. Expected-type inference | The surrounding declaration already determines a type | Less redundant syntax and fewer constructor/type-argument guesses | Normally identical code | Neutral or a small checker cost; bounded local work |

These are related but independently testable. Do not introduce all five in one
compiler and then credit the package to an unspecified property called elegance.

## A. Generalize scalar domains to opaque aggregate representations

Today a scalar `domain` can hide its representation and construction. Extend that
same rule to a value record or immutable managed representation. Avoid introducing
a second privacy model or a general theorem prover.

Illustrative proposed syntax, **not accepted syntax today**:

```text
record SpanRepresentation:
    source: bytes
    start: int
    end: int

domain ByteSpan: SpanRepresentation:
    def checked(source: bytes, start: int, end: int) -> Result[ByteSpan, SpanError]:
        # Check 0 <= start <= end <= len(source), then wrap privately.
        ...

    def length(span: ByteSpan) -> int:
        ...

    def subspan(span: ByteSpan, start: int, end: int) -> Result[ByteSpan, SpanError]:
        ...
```

The important rule is that external code cannot fabricate a span, write its
fields, or use `replace` to bypass construction. The defining operations preserve
the invariant. Start with scalars, immutable `bytes`/`str`, and value records
composed of those; exclude shared mutable descendants from the first experiment.
Current domain tests already reject external representation access, so this
extends an established mechanism. See [domains](../domains.md) and
[domain opacity tests](../../src/domain_equality_test.zig).

Useful applications of one mechanism:

- A byte span keeps its source and bounds together; parser clients cannot create
  mismatched range/source triples accidentally.
- Validated UTF-8 data can expose text operations without repeatedly turning
  failure into an ordinary result at every consumer. Arbitrary byte slicing must
  drop that guarantee or revalidate character boundaries.
- A nonempty immutable sequence gives a total `first` operation. A normalized
  path or parsed configuration keeps boundary validation out of its consumers.
- Representations can change without exposing field edits throughout the program.
  Layout remains a code-generation dependency even when it is hidden from source.

**Why this can compound:** the same construction boundary removes invalid states
from client code, centralizes useful diagnostics, and creates a place to provide
specialized operations. It can make a representation optimization an API-internal
change instead of a project-wide migration.

**What it does not prove:** opacity verifies who can construct a value; it does
not prove that an arbitrary constructor implements its intended mathematical
predicate. The defining code still needs tests. Nor does a type called `Sorted`
authorize the optimizer to assume sortedness. Any eliminated runtime check needs
a compiler-known operation contract or a separately established proof.

**Smallest experiment:** compare an exposed record with an opaque domain behind
the *same* small operation API and identical implementation. Add tasks changing a
range convention, diagnosing a bad subspan, and extending an operation. Separately
compare both against the existing ad hoc implementation. That distinguishes the
benefit of library cleanup from enforcement by the language.

**Reject or narrow it if:** clients gain casts, forwarding wrappers or long APIs
without reading less or making fewer invariant mistakes. Do not introduce a
general `Validated[T, predicate]` solver to rescue a small null result.

This follows the information-preserving approach in
[Alexis King's article](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
and Parnas's argument for hiding changeable representation decisions behind
operations ([original paper](https://prl.khoury.northeastern.edu/img/p-tr-1971.pdf)).
Their application to mylang agent productivity is a hypothesis, not a result of
those sources.

## B. Let ordinary control flow establish reusable local facts

The narrow first change is `Option` narrowing after a guard:

```text
# Proposed: ordinary early-return shape, with flow-sensitive Option typing.
def width(candidate: Option[Widget]) -> int:
    if candidate is None:
        return 0
    return candidate.width
```

The [velocity audit](agent-velocity-2026-09-17.md) and
[SSA audit](language-level-ssa-2026-09-19.md) already proposed this. The additional
research hypothesis is that one small fact representation can support type
checking, diagnostic explanations and selected optimization proofs.

Phase 1 should track `Some`/`None` facts on local value bindings, assignments and
control-flow joins. It should retain the current rule that a binding has one
declared type. A use has a refined view of that type along a checked path.
`Result` handling remains explicit through existing `match` and `?` rules.

A separate phase can track simple integer intervals and bounds over immutable
bytes, fixed arrays, or frozen collections. For example, a known `0 <= i < len(b)`
can justify a checked projection without repeating an equivalent check when
neither `i` nor the relevant storage has changed. Propagating that proof into
lowering is additional work, not an automatic consequence of accepting the guard.

**Benefits from the same facts:** less branching boilerplate; more familiar code;
diagnostics explaining the missing condition; typed-hole/context reports showing
the facts at a site; and, later, fewer redundant checks. The explainability comes
from a bounded justification such as “the None branch returned here,” rather than
new heuristic advice.

**Soundness boundary:** a fact about a local value differs from a fact about a
field of a shared object. Calls that can mutate an alias invalidate affected heap
facts. Reassignment kills facts about the previous value; joins keep only common
facts. Do not preserve a list-length or dictionary-membership fact across unknown
mutation. For the first release, decline heap refinements rather than silently
trust them. Existing mutation analysis is useful input, not a reason to skip this
distinction.

**Compilation boundary:** cap interval/union complexity and widen to unknown in
loops. Start with no arbitrary predicate calls, SMT solver, or interprocedural
proof search. Ordinary safety checks remain whenever proof is unavailable.
Preserve trap, effect-order and execution-budget semantics when optimizing.

**Smallest experiment:** paired repair and feature tasks involving optional
lookups, early returns and reassignment. Include negative controls where a shared
field changes through a call. Evaluate guard syntax first, then range optimization
as a distinct intervention. Option narrowing alone has no promised runtime gain.

**Reject or narrow it if:** the accepted syntax expands substantially, but repair
effort stays unchanged or invalidation rules surprise agents. Also reject an
optimization that saves runtime by changing observable failure behavior.

[TypeScript's control-flow analysis](https://www.typescriptlang.org/docs/handbook/2/narrowing)
is a concrete precedent for this surface shape. It is not a soundness specification
for mylang's aliasing rules or evidence of faster agent maintenance.

## C. Construct with mutation, publish immutable collections

Extend the distinction already made between `byte_buffer` and `bytes` to an opt-in
sequence of immutable values. Keep existing shared mutable lists available.

```text
# Proposed library/type sketch; spelling is not settled.
def make_index(input: bytes) -> FrozenList[Entry]:
    entries: list[Entry] = []
    # Existing ordinary loops append immutable Entry values.
    ...
    return freeze(entries)
```

Define `freeze` as an immutable snapshot first. It must copy or safely detach the
outer storage when mutable aliases survive. For the first version, `Entry` must
contain only immutable leaves, value records of those leaves, or already-frozen
collections. Reject `FrozenList[MutableClass]` rather than pretending an immutable
outer sequence makes a mutable graph immutable. A general deep freeze of cyclic
graphs is a different, much larger feature.

The compiler can later elide the snapshot copy for a proven fresh, nonescaping
builder. That optimization must establish the absence of surviving mutable aliases;
neither GC nor a readonly parameter provides that fact. Explicitly consuming a
builder is another option, but would add a source-level lifetime obligation and
should be evaluated separately.

**What this unlocks:** an AST or configuration can be passed around without
rechecking whether another helper changed it; snapshots have stable contents;
validated aggregate invariants survive calls; length/content facts remain valid;
and compact storage or cheap reads become possible. Local mutation can remain an
efficient implementation technique.

There is already a foundation: mylang permits mutation of definitely fresh local
storage without claiming caller-visible mutation. The new fact is that the
*returned graph* cannot subsequently be mutated. See [fresh local mutation](../effects.md#fresh-local-mutation).

**Costs:** freezing can add a whole copy and retain memory; persistent path updates
can be expensive; immutable types introduce another collection vocabulary. Do not
assume a generic frozen sequence outperforms today's list, or switch the collector
as part of this experiment.

**Smallest experiment:** freeze an AST's child lists after parsing, and an
independent small configuration/index structure. Measure construction and repeated
traversal separately, plus peak memory and feature work involving snapshots. Keep
the copying version as the semantic baseline before evaluating copy elision.

**Reject or narrow it if:** most real tasks immediately thaw or copy data, or
snapshot construction costs exceed the read-side benefit with no agent gain.

[Koka's effect research](https://arxiv.org/abs/1406.2061) establishes a disciplined
way to encapsulate local state. [Perceus](https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse)
demonstrates that functional interfaces can coexist with storage reuse under a
different memory model. These are feasibility precedents; their performance does
not transfer to mylang's tracing GC.

## D. Make a public contract sufficient to check its clients

Mylang already has explicit types, named requirements, effect ceilings, mutation
summaries, contract manifests and caches. The remaining research direction is to
make their separation complete: clients checked against a stable contract should
not need a successful production body merely to establish their own validity.

Start with an opt-in strict public-boundary policy, not annotations on every
helper. Reuse existing `effects(...)` and `mutates(...)`. Where clients need alias
information, expose a checked return-origin promise, or conservatively use
`unknown`. Do not infer a more permissive public promise silently after a body edit.
Retain inference inside the implementation.

Three dependencies must remain distinct:

| Consumer | Depends on |
| --- | --- |
| Client type checking | Relevant public signature, effects, mutation/alias guarantees, nominal identities and generic requirements |
| Code generation | Representation/ABI plus any bodies used for inlining, specialization or constants |
| Behavioral tests | Actual selected implementation, transitive behavior dependencies, fixtures and execution policy |

An unchanged signature never justifies reusing a test result after a behavior
change. A declaration-only contract can support client checking, but cannot certify
the implementation, linking, or a release. This extends the existing
[interface research](interface-research-2026-09-15.md) rather than proposing a new
runtime interface system.

**Benefits:** agents can read a short boundary; consumers and implementations can
be worked on independently; a body-only change can stop propagating through type
checking; and diagnostics can identify a violated public promise locally.

**Costs:** annotations and inferred-summary maintenance can exceed saved work on
small programs. Stronger separation can reduce cross-boundary optimization unless
its implementation dependencies are tracked explicitly.

**Smallest experiment:** modify private helpers beneath a stable export and use
existing work reports to count bodies actually rechecked. Include a deliberate
contract change, a body-only behavioral bug, and a generic specialization. Then
test a client feature against a declared contract while production has a typed
hole. Compare against the current cache, not the older pre-cache implementation.

**Reject or narrow it if:** global passes still dominate elapsed time, or annotation
work increases agent cost without reducing investigation or checking latency.

[Rust's incremental compiler documentation](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html)
explains why changed inputs need not invalidate consumers when a queried result
is unchanged. The mylang-specific proposal is to align that dependency boundary
with what source-level clients are entitled to assume.

## E. Use expected types consistently at construction sites

Keep function signatures explicit while allowing their types to flow inward.
The current [generic inference rule](../generic-inference.md) uses argument types
but explicitly excludes return context. `Some` already has contextual rules;
different constructor families need not require different guessing strategies.

```text
# Proposed: a return-only type parameter can be solved from this local annotation.
items: list[Entry] = empty()

# Proposed: the enclosing return type supplies the expected collection element.
def no_entries() -> list[Entry]:
    return empty()
```

Unify arguments and an available expected result against the callee's declared
signature. Reject conflicting constraints; never use coercion, implementation
body search, or global overload search to invent an answer. Explicit type
arguments remain available. Missing context still requires an annotation.

**Benefits:** fewer repeated names and temporary annotated variables, more direct
composition, and errors at the conflicting input rather than at a distant use.
This is a small syntax/checker improvement with several usability consequences,
but no credible direct runtime speedup claim.

**Smallest experiment:** first count actual inference-related repairs in current
idiom and friction evidence, then test a bounded set of collection factories,
options and generic result constructors. Require equivalent specializations and
generated code for explicit and inferred forms.

**Reject or defer it if:** current agents rarely hit this problem. A feature that
saves a few characters without eliminating repair work is lower priority than an
invariant or dependency boundary.

## The experiment I would run next

**First choice: A, opaque aggregate domains, with a library-only control.** It tests
a language-level mechanism with several applications while keeping runtime,
parsing rules and algorithm choices constant. B is the smaller fallback if we
want a short checker prototype before any new aggregate type support.

1. **Preflight without agents.** Freeze a working compiler and two compatible
   small applications. One should use source ranges; another should use a
   validated configuration/path value. Do not reuse a stale planner just because
   it appeared in an earlier experiment. Verify the starting programs and their
   independent behavior oracles before allocating sessions.
2. **Use three arms.** A0 is current application code. A1 provides a compact
   operation API around an ordinary exposed record. A2 provides the identical API
   around an opaque aggregate domain. A1 and A2 receive the same documentation,
   algorithms, diagnostics where applicable, and tool access. A2 necessarily has
   an extra rejection when a task attempts to violate opacity; that is treatment.
   Use the same experimental compiler for all arms.
3. **Pilot for headroom.** Use separate development tasks to check that agents
   actually encounter the intended invariants, and that the brief/oracle agree.
   If neither investigation nor mistakes involve the boundary, change the
   research question before freezing the main cohort. Do not manufacture bad
   baseline documentation or seed exclusively treatment-specific mistakes.
4. **Freeze a diverse task pack.** Include feature additions, a bug whose cause
   crosses a helper boundary, a representation change, and legitimate needs that
   may reveal an overly restrictive API. Add short chained tasks to measure
   amortization, with equal state carried forward in every arm. Separate chains
   from independent repetitions in analysis. Use genuinely new test instances.
5. **Measure the complete attempt.** Record independent hidden acceptance, total
   wall time to public acceptance/final submission, generated/input/cache-read
   tokens separately, actual compiler invocations, and read/edit/verification
   phases. Show success-versus-budget and capped time across all assigned runs;
   do not report only successful sessions. Hidden checks grade the sealed final
   candidate, rather than guiding candidate selection.
6. **Measure mechanism and cost separately.** Count attempts to construct invalid
   state, files/definitions read, and repeated validation logic. These explain
   outcomes, not an elegance score. Report implementation/migration cost apart
   from per-task savings. Break-even only exists if savings are positive.
7. **Control performance independently.** Record cold and warm edit/check/test
   times. Benchmark runtime and allocations on equal accepted behavior in
   randomized interleaved runs with pinned safety settings. An opaque-type trial
   need not improve runtime; a later representation experiment must supply that
   evidence. Keep raw sample order and executable/source identities.
8. **Predeclare the decision after the pilot, before main results.** Select one
   primary efficiency outcome and a practical threshold, such as 15% lower capped
   delivery time, conditional on a predeclared correctness noninferiority rule.
   That percentage is a product choice, not a scientific constant. Determine
   sample size from pilot variability and the minimum effect worth shipping.
   Use task-level uncertainty estimates retaining within-task repetitions; do
   not treat repeated sessions of one task as new independent applications.

A1 beating A0 while A2 adds no benefit means the library is sufficient. A2 beating
A1 would support the new language rule. A2 helping correctness while costing more
time is a tradeoff to report, not a universal win. A wide interval is inconclusive.
One-task success would not justify a general feature.

## Changes I would leave out of this round

- Surface SSA, mandatory immutable local names, or a global replacement of shared
  collections: the relevant measured hazards lie elsewhere, and migration would
  contaminate a small test.
- A new effect-handler runtime, general dependent types, unrestricted macros, or
  a memory-management replacement: much larger mechanisms than these hypotheses
  require.
- More architecture scoring or a source-code compression target: the local
  experiments did not validate those as agent-cost proxies.
- Additional byte-view/buffer syntax: those foundations now exist. First measure
  adoption and the allocation/layout tradeoffs already available.

The design criterion is concrete: **one enforceable rule should remove several
recurring obligations from real programs, while costing less to learn, check and
maintain than those obligations did.** The proposed experiment tests that claim
without requiring a universal numerical definition of elegance.
