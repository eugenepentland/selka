# Named constraints: implementation brief

Status: implemented and shipped as the `named-constraints` feature (see the SPEC
section for `NAMED-CONSTRAINT-*` and `src/features.json`); the historical brief
below records the design as requested on 2026-09-15 and is kept for context. It
was reviewed against checkout `06454cf`, which predates the implementation;
verify each claim against the current compiler before relying on it.

## Objective

Add names for existing structural generic requirements so a consumer, a fake,
and a production implementation can be developed against one shared contract.
Reuse compile-time checking and concrete specialization. Keep the language's
existing operation, effect, ownership, and module rules.

The first release should make repeated contracts shorter without introducing
runtime interface values. It does not promise faster compilation: specialization
can generate more code, and finer incremental checking is separate compiler work.

This brief chooses a deliberately small initial design. The implementation agent
should complete the language, module, tooling, documentation, and regression-test
integration described here. Broader features listed under “Deferred work” are
separate tasks.

## 1. Surface syntax

### Today: repeat the requirements

This is existing, executable syntax:

```mylang
# doc: check
func checkout[P: copy + op(price(policy: P, subtotal: int) -> int effects())](policy: P, subtotal: int) -> int effects():
    return P.price(policy, subtotal) + 500
```

Every helper that forwards `P` must currently repeat the relevant requirements.

### Proposed: declare the requirements once

```mylang
# doc: skip proposed named-constraint syntax
constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())

func checkout[P: Prices](policy: P, subtotal: int) -> int effects():
    return P.price(policy, subtotal) + 500

func place_order[P: Prices](policy: P, subtotal: int) -> int effects():
    return checkout(policy, subtotal)
```

`Prices[P]` declares a contract about one subject type, locally called `P`.
In a bound such as `T: Prices`, the subject is the function's `T`. The binder's
spelling is local to the declaration; using `P`, `T`, or `Provider` means the
same thing. It introduces no special `Self` keyword.

The operation call remains **`P.price(policy, subtotal)`**. Existing structural
operations belong to domains and take explicit arguments. This feature does
not add record methods or the proposed `policy.price(subtotal)` receiver syntax
from the earlier interface discussion.

Fields use the same naming mechanism:

```mylang
# doc: skip proposed named-constraint syntax
constraint HasValue[T] = copy + field(value: int)

func value_of[T: HasValue](item: T) -> int:
    return item.value
```

### Grammar and limits

- Add a top-level declaration: `constraint NAME[SUBJECT] = REQUIREMENTS`.
  Treat `constraint` as a contextual declaration word if the parser can do so
  cleanly; preserve existing uses of the identifier elsewhere.
- Require exactly one subject binder, including for contracts that do not mention
  it in their member signatures. No subject bounds, defaults, or const parameters.
- Reuse the existing `+` requirement grammar on the right-hand side. V1 accepts
  the existing builtin requirements and `field(...)` / `op(...)` forms there.
- A definition's right-hand side cannot refer to another named constraint in V1.
  This keeps expansion one level deep, without inheritance or recursive aliases.
  Reject such references with a located diagnostic, including self references.
- Function bounds may combine names, builtins, and inline requirements:
  `T: Prices + codec` or `T: HasValue + field(tag: bool)`.
- A bound uses the bare name, or `module_alias.Name`. Do not accept `Prices[int]`
  as a bound application or as a value type in V1.
- Named bounds apply to **function type parameters only**. Diagnose their use on
  records, unions, domains, and constant-length parameters. Preserve existing
  builtin bounds on nominal declarations.
- Preserve current composite signature support, including fixed arrays, nominal
  applications, callback types, and concrete imported types wherever inline
  requirements already accept them. A definition may mention its subject and
  names visible in its declaration module; it cannot capture a consumer's other
  type parameters or constant-length parameters.
- Keep existing inline cross-parameter contracts available as the escape hatch
  for contracts V1 cannot name. Do not add multi-parameter constraint declarations.
- Keep the existing limits of 16 requirements per parameter, 16 operation
  arguments, and the existing generic work/specialization budgets. Check the
  expanded contract as well as source lists; expansion must not bypass limits.
  Count unique explicitly required members/builtins after expansion, before
  adding implied builtin guarantees. Bound intermediate normalization work too.

## 2. Complete provider example

Amounts are integer cents. The production policy subtracts a fixed discount;
the fake returns a configured price. Checkout adds 500 cents for shipping.
For the demonstrated fixture, subtotal 2000 and discount 250 produce price 1750.
The fake models that fixture; it does not implement a general discount policy.

```mylang
# doc: check
constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())

domain DiscountPrices: int:
    func make(discount: int) -> DiscountPrices:
        return wrap[DiscountPrices](discount)

    func price(policy: DiscountPrices, subtotal: int) -> int effects():
        return subtotal - unwrap(policy)

domain FixedPrices: int:
    func make(amount: int) -> FixedPrices:
        return wrap[FixedPrices](amount)

    func price(policy: FixedPrices, subtotal: int) -> int effects():
        _ = subtotal
        return unwrap(policy)

func checkout[P: Prices](policy: P, subtotal: int) -> int effects():
    return P.price(policy, subtotal) + 500

func main() -> int:
    mut real = DiscountPrices.make(250)
    mut fake = FixedPrices.make(1750)
    assert checkout(real, 2000) == 2250
    assert checkout(fake, 2000) == 2250
    return 0
```

Neither provider declares `implements Prices`. Satisfaction is structural:
the compiler checks the existing domain operation against the expanded bound.
Provider types retain their distinct nominal identities and representations.
The provider bodies above were run successfully with the existing inline bound;
the named declaration and its uses remain proposed syntax.

## 3. Required semantics

### One requirement model

Normalize named bounds into the same semantic requirements used by inline bounds.
Do not implement a second satisfaction checker or infer requirements from a
consumer's body. Named and equivalent inline bounds must accept and reject the
same operations, including when one form forwards to the other.

Check every constraint declaration for valid names, signatures, and existing
structural rules even when unused. Check generic bodies universally, before any
concrete provider is supplied. An uncalled generic function that uses an
undeclared field or operation must still fail.

Substitute the declaration's subject by **type-parameter identity**, recursively
through signature types. Other names retain the defining module's identity.
Do not expand contracts by rewriting source strings or resolving their names in
the caller's scope. Alpha-renaming a subject must not change the contract.

### Composition and implication

- A name is a transparent bundle of requirements, not a nominal marker. Two
  independently declared names with equivalent expanded requirements can satisfy
  the same forwarding obligations.
- Preserve existing errors for duplicates written directly in one requirement
  list. Repeating the same resolved named declaration in one bound is also an
  error, even through two import aliases.
- When distinct named bundles or a bundle and an inline requirement overlap,
  coalesce identical requirements. Builtin promises combine using the existing
  implication lattice, so `Prices + copy` is valid when `Prices` includes `copy`.
- Same-name field requirements must have the same resolved type. Same-name
  operation requirements must have the same existing signature contract and
  effect ceiling after subject substitution; otherwise reject the composition.
  Do not introduce overloads, unions, or an effect-intersection rule.
- Equivalent operation contracts use the existing parameter-matching rules;
  retain parameter names for diagnostics and existing supported call syntax.
  This feature does not add keyword-operation-call semantics.
- Forwarding uses the existing implication rules over expanded requirements.
  A stronger contract can satisfy a weaker callee; the reverse must fail.
  Do not inspect a particular implementation to justify an otherwise invalid
  universally checked forwarding function.

### Effects, state, and representation

- Required operations have explicit effect ceilings. A concrete method's declared
  effects may be a subset of the required ceiling. The generic caller is checked
  against the full required ceiling, including when the selected fake is pure.
- Keep exact parameter/result type matching, nominal identity, domain privacy,
  public/nongeneric/non-conversion operation restrictions, and current passing
  modes. No global free-function or extension-method search.
- Keep field contracts' `copy` requirement and all existing result-handling,
  storable, ownership, and arena checks. `copy` retains its current meaning; it
  does not mean deep copying managed collections or imply immutability.
- An explicit named bound contributes only its declared and implied guarantees.
  Do not silently add `copy` to every named bound. Unbounded `[T]` keeps its
  existing default behavior.
- A constraint is not a runtime type: reject parameter/field/return annotations
  such as `policy: Prices`, constructors, casts, and `list[Prices]`.
- Keep concrete specialization keyed by the existing function declaration and
  concrete argument identities. Names do not create extra specializations,
  runtime dictionaries, interface tables, or allocation requirements.
- Static operation calls retain the existing direct lowering. A callback written
  inside a generic function remains a runtime function value; this feature does
  not promise that callback calls become direct or that all generic work runs
  at compile time.

## 4. Modules and the parallel development workflow

Constraints participate in the existing module declaration namespace and explicit
exports, with a distinct declaration kind. Diagnose collisions with existing
declarations/import aliases and illegal subject shadowing using current rules.
Do not turn constraints into nominal type-catalog entries to obtain name lookup.

```mylang
# doc: skip proposed named-constraint syntax; contracts.my

public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
```

```mylang
# doc: skip proposed named-constraint syntax; checkout.my
import contracts

public func total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
    return P.price(policy, subtotal) + 500
```

All modules are indexed before resolving named references, so same-module
declaration order does not determine validity. Use ordinary direct imports and
aliases. A private constraint cannot be imported. An exported generic signature
must not expose an unexported constraint; an exported constraint must not expose
private types in any nested requirement signature. Preserve current module
cycle and re-export rules.

Use this fixture layout for implementation acceptance:

| File | Contents and imports |
| --- | --- |
| `contracts.my` | Exports `Prices`; imports no implementation. |
| `checkout.my` | Exports generic `total`; imports only `contracts`. |
| `fakes.my` | Exports `FixedPrices` from the complete example. |
| `fake_tests.my` | Imports `checkout` and `fakes`; has `main` and an exported parameter-free `test_checkout() -> bool` calling `checkout.total(fakes.FixedPrices.make(1750), 2000) == 2250`. |
| `production.my` | Exports `DiscountPrices`; developed independently. |
| `main.my` | Imports `checkout` and `production`; selects the real provider. |

The concrete wrapper makes a generic test reachable through the existing native
test runner; do not try to invoke an unspecialized template through its JSON API.

**Acceptance:** checking and testing the `fake_tests.my` entry must succeed with
`production.my` absent, or with an invalid unfinished body in that unimported
file. Check the explicit entry, rather than directory discovery of every file.
Production checking must reject its invalid body once its own entry imports it.

This gives agents independent work through the import graph. Named constraints
do not make an invalid imported implementation acceptable. The current runner's
source-replacement fixtures initially check the original graph; changing that
ordering or introducing signature-only stub modules is separate work. Do not
bypass body validation or typed-hole rejection to make this feature pass.

Write behavioral contract tests as ordinary generic helpers with concrete test
wrappers for each provider. Document fixture configuration, units, valid inputs,
missing-data behavior, effects, and other observable promises for actual services.
Type conformance alone cannot establish behavioral equivalence.

## 5. Incremental compilation and testing

The required baseline is **correct reuse with the existing caches**. Preserve
their supported reuse and conservative fallbacks; no new persistent checked-body
cache or timing guarantee is required by this feature.

The current persistent frontend caches syntax and successful exact-source
verdicts. Checked-body reuse lives in the in-process session and currently falls
back for generics. Named constraints do not remove that limitation. See
[compiler caches](tooling/caches.md).

Carry named definitions, references, subject identities, and source origins
through AST copies, project relocation, and syntax serialization. Update the
relevant format versions and fingerprints when their contents change. No cache
may retain a successful check after a referenced contract becomes invalid.

Use a normalized semantic description for requirements: resolved nominal type
identities, subject positions, builtin guarantees, members, passing modes, and
effect sets. Keep declaration identity and exact source receipts separately.
Whitespace, a local subject rename, and equivalent requirement ordering should
not change the semantic description, although current exact-source caches may
still miss. Keep diagnostic spans current after reuse.

| Edit | Required behavior |
| --- | --- |
| Whitespace or subject rename | Same meaning and conformance; fresh source locations. Existing conservative cache misses are acceptable. |
| Contract member/type/effect changes | Recheck affected generic obligations and concrete conformance before publication. Adding an unused required operation can invalidate a provider. |
| Provider body changes, same declared contract | Invalidate affected implementation code and test receipts. Do not treat type conformance as proof of unchanged behavior. |
| Generic body changes | Invalidate its affected specializations and dependent test results. |
| Unimported production file changes | The explicit fake-only entry remains valid and its dependency graph is unchanged. |
| Contract export/import removed or renamed | A warm check rejects wherever a fresh check rejects. |

Keep dependencies on bodies used for specialization or optimization. Required
test results must agree for warm, forced, and clean runs; exact cache-hit counts
are acceptance criteria only for paths the current implementation supports.
Report measured counters/timings separately from correctness.

## 6. Compiler integration map

These are starting points, not a requirement to place all changes in these files.
Follow current ownership and module layering; avoid import cycles and global
mutable registries.

| Area | Existing entry points | Work |
| --- | --- | --- |
| Syntax | `src/parser.zig`, `src/ast.zig`, token/lexer definitions | Parse declarations and qualified bound references; share requirement parsing. |
| Names and exports | `src/interfaces.zig`, `src/module_names.zig`, `src/module_syntax.zig` | Index the new kind, resolve references, validate visibility and declaration scope. |
| Copies and project assembly | `src/ast_copy.zig`, `src/project_syntax.zig`, `src/syntax_cache.zig`, `src/frontend_cache.zig` | Retain and relocate the new syntax; review serialization and format keys. |
| Requirement resolution | `src/generic_requirements.zig`, `src/structural_declarations.zig` | Resolve/normalize names, validate definitions, combine bundles with provenance. |
| Universal checking and conformance | `src/generic_bodies.zig`, `src/structural_constraints.zig`, `src/symbolic_types.zig`, `src/generic_substitution.zig`, `src/sema.zig` | Feed both named and inline forms through existing implication, substitution, and satisfaction logic. |
| Specialization | `src/generic_instances.zig`, `src/lower.zig`, `src/qbe.zig` | Verify existing concrete identity and direct operation lowering remain sufficient. |
| Public tooling | `src/generic_api.zig`, `src/declarations.zig`, navigation and schema producers | Expose named contracts and their expanded promises without making them callable endpoints. |
| Reuse and tests | `src/semantic_key.zig`, `src/semantic_cache.zig`, native test receipts/session code | Audit new dependencies and retain sound fallback behavior. |

The existing requirement resolver accepts only source spans and builtin names;
named imports need a declaration-aware resolution context. Choose a shared
normalized representation so interface checking and semantic checking cannot
resolve the same name differently. Retain the named use site and member's
declaration origin for diagnostics; plain copied spans do not substitute types.

Public inspection must show exported constraint declarations and the names used
by exported generic parameters, with the expanded requirements available to an
agent. Follow existing versioning conventions for schema changes. Preserve the
distinction between the pre-body `list-interfaces` inventory and fully checked
schema publication. Formatting must preserve named spelling; it must not expand
every use back into a long inline bound.

Diagnostics should identify the failing named bound, the first missing or
mismatched member, expected and actual types/effects, and the related declaration
in its original file. Prefer existing codes such as `E_GENERIC_REQUIREMENT`,
`E_GENERIC_ARGUMENT`, and `E_GENERIC_LIMIT` where their meaning fits. Avoid
numeric effect masks, pointer-like type spellings, and raw internal IDs in new
messages. An undeclared operation in an uncalled generic should be diagnosed at
that use, not deferred to some later provider instantiation.

## 7. Acceptance checklist

- [ ] Named and equivalent inline bounds work with explicit and inferred generic
  calls, repeated specialization, forwarding, and recursion.
- [ ] The full provider example runs natively and produces the expected results;
  a field constraint accepts distinct matching records without erasing identity.
- [ ] A stronger bound forwards to a weaker one; a weaker bound cannot forward
  to a stronger one, including in an uncalled function.
- [ ] Unused invalid definitions and invalid uncalled generic bodies reject.
- [ ] Missing/private/generic operations, wrong nominal parameter/result types,
  and excessive declared effects reject; permitted effect subsets succeed.
- [ ] Generic callers retain the full required effect ceiling even with a pure
  fake. Existing ownership, result-handling, privacy, and field-copy failures
  also reject through named bounds.
- [ ] Expansion substitutes the subject inside supported composite signatures;
  unrelated same-spelled names in the consumer cannot capture declaration names.
- [ ] Duplicate/conflicting requirements, expansion budgets, wrong declaration
  kinds, and unsupported constraint syntax produce located diagnostics.
- [ ] Local forward references, imported aliases, private visibility, exported
  signature exposure, and module name collisions behave as specified.
- [ ] Fake-only entry checking/testing succeeds independently of an absent or
  unfinished production module; the production entry still validates its body.
- [ ] Warm and clean checking agree after contract, provider, generic-body,
  export, and import edits. A same-signature behavioral bug invalidates the
  affected previously passing test result.
- [ ] AST cloning, serialization, relocation, formatting round trips, schema
  output, navigation, and allocation-failure cleanup cover the new declarations.
- [ ] Existing programs using only inline or builtin requirements retain their
  behavior. No runtime interface representation is emitted for named bounds.

### Validation workflow for the implementation agent

Use the Zig version pinned by `.zigversion`. Follow current repository build
instructions and run focused suites during iteration, for example:

```sh
zig build test-units -Dtest-filter='named constraints'
zig build test-units -Dtest-filter='structural'
zig build test-units -Dtest-filter='generic'
```

Name new tests consistently with the first filter; a filter matching no tests
must fail. Add module/CLI, native execution, and cache regressions at their
existing test layers rather than relying solely on parser tests.

Before reporting implementation complete, rebuild/install the compiler and run
the repository's required gates with the pinned toolchain:

```sh
zig build
zig build test --summary all
zig build fmt-check
```

Update `SPEC.md` with matching test spec tags, `src/features.json`, the current
generic language guide, and runnable examples. Replace relevant proposal skips
with tested examples when the feature ships. Include the supported boundary and
actual validation results in the implementation handoff. If Guardian is exercised,
follow the user's global instruction to append and commit a feedback entry in
the Guardian repository; do not overwrite existing feedback.

## 8. Deferred work

- Runtime interface values, heterogeneous provider containers, runtime casts,
  dynamic dispatch tables, and associated allocation/lifetime rules.
- Record methods, implicit receivers, automatic adapters, free-function lookup,
  `implements` declarations, and generated mocks.
- Constraint inheritance, references between constraint definitions, associated
  types, defaults, generic required operations, and multi-parameter constraints.
- Changing callback effect compatibility or callback-field invocation behavior.
- Signature-only implementation stubs, accepting typed holes for executable
  publication, and reordering provider replacement in the native test runner.
- Fine-grained persistent generic-body caching or new optimization policies.

These may deserve their own proposals after measuring repeated usage. The
deliverable here is an importable name for an existing compile-time contract,
with complete checking and tooling integration.

## Background and verification of this brief

- [Generic functions and structural contracts](generics.md)
- [Generic call inference](generic-inference.md)
- [Modules](modules.md) and [guest tests](tooling/guest-tests.md)
- [Interface and agent-development audit](audits/interfaces-and-agent-development-2026-09-15.md)
- [Online research and its limitations](audits/interface-research-2026-09-15.md)

While preparing this brief, the provider example's inline equivalent executed
successfully with the installed native compiler. No compiler sources were changed
and no Guardian gate was exercised. Named-constraint acceptance remains work for
the implementation agent.
