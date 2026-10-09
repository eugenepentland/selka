# Interfaces, simplicity, and parallel agent development

15 September 2026 · targeted design and implementation audit

Research follow-up: [evidence and adoption decision](interface-research-2026-09-15.md).
It qualifies the design recommendation below: independently checkable contracts
have a strong justification; the additional benefit of a full runtime interface
feature still needs a local comparison with modules and callbacks.

## Verdict

**Small Go-inspired behavior interfaces fit this language.** They would let a
consumer name the operations it needs while implementations keep their own state
and representation. That supports independent implementation, fakes, and testing.
The language already has much of the underlying machinery; its immediate problems
are inconsistent substitution rules and a test workflow that still needs the real
implementation to type-check before using its replacement.

My recommended order is: fix those problems, demonstrate one complete workflow
using existing callbacks, then introduce named interfaces if they materially
reduce the remaining plumbing. Interfaces should make an ordinary API easier to
read. General inheritance, reflection, and a universal dynamic value are not
needed to achieve that.

For the broader simplicity goal, optimize the number of rules a programmer must
remember and the number of repair cycles an agent needs. A smaller implementation
or keyword count alone is not a reliable measure of either.

## Scope and evidence

Reviewed the guide, reference, recent audits and decisions, generic contracts,
callbacks, effect checking, native test substitution, caching, formatting, and
selected standard-library code. Ran **19 focused probes** against a pinned copy of
the installed compiler, including native execution and two native guest-test configurations.
Full sources, arguments, outputs, and compiler identity are in the accompanying
[probe evidence](interfaces-and-agent-development-2026-09-15-probes.json).

- Git HEAD at the start of probing: `b190397`.
- Git HEAD when the pinned probes were repeated: `e366fd5`; concurrent work
  advanced the checkout during this audit.
- Installed compiler identity:
  `620e2427bd6a95dd974a075d651c4d2964a1731222704325254de6547b7bff2a`.
- The working tree contained ongoing uncommitted changes. Runtime observations
  describe that installed binary; source observations describe the inspected tree.
  These are not claims that a fresh build of every ongoing edit passes. The
  executable was reinstalled during the audit, so all probes were repeated against
  one pinned copy; the findings were unchanged.
- No compiler implementation was changed or rebuilt. No Guardian gate was
  exercised. This is not a full compiler correctness audit or an agent speed study.

## Findings in priority order

### 1. Provider substitution is blocked by an unfinished real implementation

**High priority for the requested parallel workflow.**

The native test runner supports replacement dependency sources through a case's
`providers` configuration. I verified that replacing a complete implementation
returning `1` with a fake returning `42` passes its consumer test.

Changing the original implementation to `return todo[int]()` makes the same test
exit 2 with `E_TYPED_HOLE`, although the replacement is complete and valid.
[native_test_command.zig](../../src/native_test_command.zig), line 51, checks the
original project; replacements are first applied at lines 74–78. Test discovery
and schema compatibility currently depend on that initial successful check.

This directly obstructs “agent A implements the service while agent B tests the
consumer against a fake.” Interfaces alone would not fix that ordering.

**Recommendation:** give consumer tests a checked contract independent of the
production body, and select the implementation before checking executable bodies.
Validate the fake against that contract, then compile the consumer's selected
dependency graph. Extend the existing test workflow instead of creating another
runner. Keep production builds rejecting all holes in their selected graph.

Do not simply skip the original check without replacing its schema guarantees.
Public parameter names, types, defaults, nominal data identities, effects, and
ownership obligations still need checking. Invalid declarations must not be
treated as acceptable unfinished bodies.

**Acceptance:** a client test passes with a fake while the unselected production
body contains a typed hole; a wrong fake signature fails before execution; the
production build still fails until its body is complete. Record the selected
provider and contract identity in the test receipt.

### 2. A callback's effect ceiling behaves differently from an operation contract

**High priority; a small, central simplification.**

A function declared `effects()` cannot be passed to a callback accepting
`effects(output)`. Giving the same function the broader explicit annotation makes
it accepted, even when its body has no output. Both behaviors were probed.

[callables.zig](../../src/callables.zig), lines 12–23, requires exact effect masks.
In contrast, [structural_constraints.zig](../../src/structural_constraints.zig),
line 50, already accepts an implementation whose declared effects are a subset of
the operation contract's permitted effects.

**Recommendation:** use one substitution rule: an implementation may do fewer
things than its contract allows. Keep parameter and result identities exact in
the first version; this does not require general type variance.

The call through the abstract value must retain the contract's full ceiling.
Otherwise replacing a fake with a real implementation can unexpectedly change
caller checking. Update assignment compatibility, generic forwarding, and native
target validation together. Exact type identity can remain exact; assignability
is a separate question.

The probe's diagnostic also exposes internal notation:
`expected def@128:i64,i64, found def(i64)->i64 effects(0)`. Render the canonical
source signature and named effects, with the missing or excessive requirement.
That is information an agent can immediately act on.

### 3. Stored callbacks work, but the obvious call syntax fails

**High priority for a minimal abstraction mechanism.**

The language can store a callback in a record, including a generic record carrying
implementation-specific state. However, `store.get(key)` fails with
`E_UNKNOWN_TYPE`. Reading `get = store.get` and then calling `get(key)` works.
The generic state-and-callback probe executed successfully.

**Recommendation:** let a callable-valued field be called directly. This needs no
inheritance, implicit receiver parameter, captured environment, or user-defined
method machinery. Resolve the field normally, validate its callable type, and
evaluate the receiver and arguments once in source order.

For actual methods, the existing structural operation checker only accepts public
domain operations; ordinary records cannot define them
([structural_constraints.zig](../../src/structural_constraints.zig), line 22).
A named interface therefore needs an intentional record-method or explicit
adapter design. It is not just a new name for functionality already complete.

### 4. Familiar Python spellings sometimes have surprising meanings

**Fix `dict.items()` before broader application use.**

The following probe runs successfully:

```text
data = {10: 100, 20: 200}
for key, value in data.items():
    print(key, value)

Actual output:
0 100
1 200
```

The first binding receives a position, not a key. This is deliberate in
[parser.zig](../../src/parser.zig), lines 724–728, and covered by
[python_collections_test.zig](../../src/python_collections_test.zig), line 294.
It is a design defect relative to the intended familiar surface, not an untested
implementation accident. Python's `items()` yields key/value pairs.
([Python dictionary reference](https://docs.python.org/3/library/stdtypes.html#dict.items))

Integer keys make this especially costly: the program can remain type-correct
while computing the wrong answer. Change the operation to expose actual keys and
values. If general tuples remain deferred, a bounded pair-iteration implementation
can solve this immediately; do not retain the positional meaning as a shortcut.

Another confirmed difference: `round(2.5)` returns `3.0`, while Python's one-argument
`round` returns the integer `2` using ties-to-even. Decide whether familiar `round`
should match that behavior, or give the existing operation a descriptive name.
([Python round reference](https://docs.python.org/3/library/functions.html#round))

Maintain a small compatibility matrix: same spelling and meaning; intentionally
different and documented; unsupported and diagnosed. Prioritize silent changes in
meaning over missing syntax. Fixed-width integers, Boolean-only conditions, and
explicit `Result` are coherent differences worth keeping.

### 5. The documentation and formatter impose avoidable coordination costs

**High priority for agent reliability.**

Current reader-facing contradictions include:

- [python-syntax.md](../python-syntax.md), line 89, says `round` is absent;
  line 342 explains its implemented behavior.
- That guide, line 323, says slices have no step; native collection tests cover
  step slicing in [python_collections_test.zig](../../src/python_collections_test.zig).
- [current-language.md](../current-language.md), line 53, says removed raw
  `f64_*` operations remain available.
- [functions.md](../functions.md), line 90, lists four entry-point forms but
  omits the now-working `Result[int, str]` form.
- The provider example in [guest-tests.md](../experiments/guest-tests.md) uses
  removed brace syntax, and [typed-holes.md](../typed-holes.md) calls `todo[T]()`
  angle-bracket syntax.

Executable examples do not detect false prose or obsolete snippets in differently
labelled fences. Use one current guide and compiler-derived API descriptions;
mark historical pages consistently. Check negative feature claims against the
feature manifest and a small set of probes. Give each language change an explicit
documentation update list.

The formatter currently returns the original bytes
([formatter.zig](../../src/formatter.zig), line 13). I verified that
`def main( )` and `return  1+2` survive unchanged. Parsing indentation does not
canonicalize spaces, wrapping, or declaration spacing.

Implement a real, comment-preserving canonical formatter. For independent agents,
it can reduce stylistic disagreements and merge noise. Preserve string contents
and evaluation order; check idempotence and semantic preservation.

### 6. Finish the small features that remove existing workarounds

These have better immediate justification than a broad new object system:

- **`Cell[T]`:** already an accepted pending decision in
  [D4](../adr/D4-managed-cell.md). The standard JSON scanner uses
  `position: list[int]` as shared scalar state
  ([json.my](../../src/stdlib/json.my), line 38). An explicit cell gives that
  existing pattern a direct name. Keep ordinary records as values.
- **Immutable `str`/`bytes` constants:** a `const NAME: str = "example"` probe
  still rejects with `E_CONSTANT_EXPRESSION`. Literal constants do not need
  unrestricted compile-time heap evaluation. Specify initialization, rooting,
  and arena independence once.
- **Record equality:** two identical scalar records still reject `==`. Consider
  derived fieldwise equality when every field supports it, sharing existing
  managed equality behavior where relevant. Do not invent pointer identity or
  equality for callbacks/resources to make every record comparable.
- **Small expression conveniences:** conditional expressions and `is None`
  still reject. They are reasonable later additions. Tuples/destructuring deserve
  one coherent design if they replace multiple special cases around `items`,
  `zip`, `enumerate`, and paired returns; they are not a prerequisite for mocks.

`?` over `Option` and `main -> Result[int, str]` already work in the installed
binary. Do not repeat the earlier audits' recommendations to implement them.

### 7. Improve incremental checking at the same boundary agents collaborate on

The [cache reference](../tooling/caches.md) documents that persistent frontend
reuse stores syntax and complete successful check verdicts, not checked bodies.
After an edit, one-shot invocations still recheck bodies. `check-session` can reuse
some bodies, but generics, constants, and aliases cause conservative fallback.

The [self-hosting plan](self-hosting-implementation-plan-2026-09-14.md) already
proposes stable identities and separate interface/body fingerprints. Prioritize
that work independently of a full compiler rewrite. Agent processes repeatedly
invoking the compiler need cross-process reuse, or a transparently managed
persistent service, to benefit consistently.

Three dependency distinctions matter:

1. A stable public contract can let an unchanged consumer retain its type check.
2. Changed implementation behavior must still invalidate affected runtime tests.
3. Generic specializations, inlining, constant evaluation, and exposed layouts
   may make generated code depend on implementation details as well.

Because calls support keywords and defaults, parameter names and default values
belong in the observable API fingerprint too. Explicit effect ceilings at shared
contracts prevent implementation edits from silently expanding the interface.
Local helpers can continue using inferred effects.

### 8. Make performance escape hatches cross the useful data boundaries

Keep GC, ordinary records, lists, dictionaries, strings, and the native backend as
the default. Keep arenas, fixed arrays, integer widths, and measured foreign
kernels as escape hatches.

The current direct [C FFI](../c-ffi.md) handles scalar signatures, while the typed
tooling [JSON boundary](../typed-json.md) excludes ordinary managed graphs. Those
limits are distinct from the working guest `json` library.

For agent-built applications, a bounded copied bridge for strings, bytes, and
ordinary acyclic data would make existing libraries and performance kernels much
more useful. Add zero-copy borrowed access only for a measured workload, with
explicit lifetime and ownership rules. Avoid making callers learn internal wire
node layouts for an ordinary text or byte request.

Also keep effect names literal. `noio` currently permits `host`, clock, random,
and environment effects; a `noio` helper calling an `extern def` checked in a
probe. It cannot be used as a purity or determinism promise. Prefer exact effects
on contracts, and consider retiring or narrowing this shorthand through an
explicit compatibility decision.

## What works today: one consumer, independent provider state

This is a complete example executed by the audit. Its two providers have different
state types; the consumer does not know either representation. The local `get`
binding is the current workaround for calling a callback field.

```mylang
# doc: skip Historical pre-redesign syntax retained as audit evidence.
# doc: expect 0
record Store[S]:
    state: S
    get: def(S, int) -> int effects()

def dictionary_get(state: dict[int, int], key: int) -> int effects():
    return state.get(key, 0)

def fixed_get(state: int, key: int) -> int effects():
    return state + key

def total[S](store: Store[S], key: int) -> int:
    get = store.get
    return get(store.state, key)

def main() -> int:
    fake = Store[int](state=40, get=fixed_get)
    table = Store[dict[int, int]](state={2: 42}, get=dictionary_get)
    assert total(fake, 2) == 42
    assert total(table, 2) == 42
    table.state[2] = 41
    assert total(table, 2) == 41
    return 0
```

This proves mechanical substitution, not behavioral equivalence of the providers:
they intentionally have different general behavior. A real application must
define what missing keys, updates, and failures mean and test both against it.

For one operation, passing a callback and explicit context directly is simpler
still. For module-sized boundaries, the existing provider fixtures can substitute
a complete checked dependency. No new runtime concurrency feature is needed to
run development agents in parallel.

## How interfaces should fit

Go's useful idea here is structural satisfaction: a type with the required methods
implements the interface without needing to declare a relationship. Python's
protocols offer a related structural typing model.
([Go specification](https://go.dev/ref/spec#Interface_types),
[Python protocol specification](https://typing.python.org/en/latest/spec/protocol.html))

### Recommended semantic scope

- Small consumer-owned contracts, typically one to three operations.
- Exact parameter/result types and explicit effect ceilings. Implementations may
  use a subset of allowed effects.
- Nominal identity stays intact for records, domains, errors, and IDs. Matching
  operation shapes must not make unrelated data types interchangeable.
- One rule for type-owned operations on records and domains, with an explicit
  receiver in implementation declarations. Avoid global free-function searches.
- No inheritance of state, default method bodies, overloaded names, associated
  types, runtime casts, or universal `any` in the first version.
- Optional interfaces use `Option[Interface]`. Avoid Go's typed-nil ambiguity;
  Go's FAQ documents why an interface containing a nil pointer can itself be
  non-nil. ([Go FAQ](https://go.dev/doc/faq#nil_error))

An illustrative end-state API, **not current syntax**, could be:

```text
interface PriceLookup:
    def get(key: int) -> Result[int, str] effects(managed_allocation)

def total(store: PriceLookup, key: int) -> Result[int, str]:
    return Ok(store.get(key)? + 1)
```

The contract also needs written semantics: units, valid keys, missing-key
behavior, mutation, and errors. Method signatures do not encode those facts.

### Static constraints and runtime interface values are different capabilities

A named generic constraint can build on today's `op(...)` requirements and check
the consumer before a concrete provider is available. It does not by itself
create a runtime value that hides an arbitrary implementation's state type.

If first-class interface values are added, **`store: PriceLookup` should be the
easy application spelling**. It hides implementation types and permits runtime
selection. A concrete parameter or an explicit generic bound such as
`S: PriceLookup` can remain the performance escape hatch for specialization and
inlining. Reuse one contract definition for both forms. Do not force generic state
parameters through every application API merely to avoid a possible indirect call.

Start by testing the callback-based version above; named constraints can be an
incremental implementation step. Full runtime values need deliberate decisions
about dispatch tables, GC rooting, allocation effects, equality, and storage.
They are more work than named constraints.

Record receivers should preserve existing value semantics. Persistent mutation
should continue through shared managed fields or `Cell`; interface conversion
must not silently turn scalar record fields into shared mutable state. Any boxed
provider must be traced, and arena-backed data must not escape through it.
Capabilities and resource ownership remain enforced through the abstraction;
an interface never grants authority or makes a move-only resource copyable.

## A workflow to measure before adding more language

1. Agree on a small contracts module containing data types, operations, effects,
   and behavioral examples. Give contract changes a clear owner.
2. One agent implements the production provider in its own module/worktree.
3. Another implements the consumer against a fake with the same contract.
4. A third task can independently build shared contract tests when useful.
5. Run those tests against both providers: present/missing values, failure paths,
   state changes, ordering, and any relevant ownership/cleanup behavior.
6. Test the assembled application with the production provider. A passing fake
   suite does not establish production I/O behavior or correctness.

Use existing test receipts and combined-merge verification. Extend them to record
the selected provider and contract fingerprint wherever that is not yet explicit.
Generated fake scaffolding should require configured results or fail on unexpected
calls; it should not silently manufacture successful defaults.

Measure time to the first passing consumer test, blocked waiting time, number of
compiler-repair cycles, contract edits, merge fixes, final integration failures,
and total agent/tool cost. Compare the current callback/module approach with the
proposed interface approach on the same bounded task, with repeated runs and
held-out acceptance cases. More simultaneous agents is useful only if total
completion time improves without weakening correctness.

## Recommended next sequence

1. Correct `dict.items()` and reconcile the current guide/reference.
2. Accept effect-subset callback substitution, improve its diagnostics, and allow
   direct callback-field calls.
3. Make selected-provider testing work while the unselected implementation has a
   typed hole, preserving contract checks.
4. Complete `Cell` and immutable text/byte constants; add real formatting.
5. Run one representative parallel-development trial. Use its remaining friction
   to decide how soon named methods/interfaces should land.
6. Advance interface-aware incremental checking and practical managed-data FFI.

This keeps the simple managed language as the common path, while making contracts,
implementation substitution, and performance choices explicit and understandable.
