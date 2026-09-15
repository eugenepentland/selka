# Named constraints: implementation review

Reviewed 2026-09-15. Target: `da3aabf` (named constraints), compared with its
parent `9c016df` and with current checkout `3c0b41f` on `wave3/base`.

**Conclusion: the basic examples work, but the implementation is not complete
against the brief. Three high-priority correctness bugs and five additional
issues need fixes.** No compiler implementation was modified during this review.

The [implementation brief](../named-constraints-proposal.md) requires preserved
nominal identity, declaration-scoped type resolution, consistent expanded bounds,
independent declaration validation, and public tooling integration. The handoff
explicitly defers schema integration and acknowledges inconsistent limit checking;
both were required by that brief.

## Findings

### 1. P1: exported imported constraints can crash the compiler

Location: [interfaces.zig](../../src/interfaces.zig#L319), especially line 320.

`checkSignatures` reads `unit.symbols.items[bound.identity.symbol]`, where `unit`
is the consuming module. The symbol index belongs to `bound.identity.module`.
These are separate symbol tables. A valid public constraint can consequently
appear private, or its index can exceed the consumer's symbol count and panic.

Repro `export_wrong_module_index`: `contracts.my` declares three records and
then exports `constraint C[T] = copy`. A two-function consumer exports
`f[T: contracts.C](x: T) -> T`. `check-project` aborts with index 3, length 2 at
`interfaces.zig:320`. The smaller `export_false_private` variation rejects the
same public bound as `E_PRIVATE_INTERFACE` because it reads the consumer's
private `main` symbol instead.

This was reproduced with both the target commit's compiler and the current
checkout's compiler. Index the defining module's table, including when resolving
the related declaration span. Add imported-export tests with different symbol
counts and export layouts; the one-symbol acceptance fixture hides this bug.

### 2. P1: consumer type parameters capture concrete types in imported contracts

Locations: [generic_bodies.zig](../../src/generic_bodies.zig#L112) (`ty`,
`substituted`) and [generic_substitution.zig](../../src/generic_substitution.zig#L35).

Subject aliases are checked by declaration scope, but resolution then falls
through to matching every consumer type parameter by spelling. A concrete type
name inside a named declaration can therefore become an unrelated consumer
parameter with the same name.

Repro `capture_imported_nominal`: the contracts module declares nominal
`record Token` and `Use[S] = copy + op(use(s: S, token: Token) -> int effects())`.
The consumer declares `call[Token, P: contracts.Use]`. A provider accepting
`token: int` is accepted when the caller instantiates its own `Token` as `int`,
despite failing the contract's actual `contracts.Token` requirement. The program
also compiles and runs natively.

Renaming only the consumer parameter to `U` makes the program reject correctly
(`capture_control_renamed`). This is a semantic change caused by an otherwise
irrelevant binder rename. Preserve the defining scope for every non-subject leaf;
only the named declaration's subject may substitute into a consumer parameter.
Cover both universal checking and concrete conformance, including nested types.

### 3. P1: requirement merging uses source spelling instead of type identity

Location: [generic_requirements.zig](../../src/generic_requirements.zig#L329),
especially `sameCanonical` at lines 369–377.

`sameCanonical` recognizes a whole-span subject or compares raw source text.
It does not resolve nominal identities, aliases, or composite type expressions.
This both discards distinct obligations and rejects equivalent ones.

- `nominal_distinct_coalesce`: modules `a` and `b` each declare a different
  nominal `ID`, and each exports `Has[T] = copy + field(value: ID)`. The bound
  `T: a.Has + b.Has` accepts a record containing only `a.ID`: the `b.ID`
  requirement was discarded because both type spans spell `ID`. It runs
  natively. Reversing the bound order rejects that same argument.
- `inline_subject_overlap`: an inline `op(identity(x: T) -> T effects())`
  conflicts with the equivalent named `Id[P]` operation after binding it to `T`.
- `composite_subject_overlap`: equivalent `list[P]` and `list[Q]` operation
  contracts conflict because their subject spellings differ.

Merge resolved, recursively normalized requirement types using nominal identities
and subject parameter positions. Do not patch this with more string replacement.
Test same-spelled types from different modules, different aliases for the same
type, named-plus-inline subject overlap, and alpha-renamed composite signatures.

### 4. P2: module preflight loses implied and named `copy` guarantees

Locations: [generic_requirements.zig](../../src/generic_requirements.zig#L204)
and [interfaces.zig](../../src/interfaces.zig#L34).

`validateOneBound` computes an expanded builtin `Set` into `ignored` but checks
only the explicit `copy` bit. Existing `equality` and `integer` bounds imply
`copy`, so this changes behavior for existing module programs that do not use
named constraints. Also, interface-time `ConstraintLookup.find` never fills
`Definition.copyable`, so named bundles fail to supply it.

- `implied_copy_single` checks successfully with
  `T: equality + field(value: int)`; adding only `module main` rejects it with
  the error that field contracts require `copy` (`implied_copy_module`).
- `named_copy_plus_field` declares `C[T] = copy`, but a module's
  `T: C + field(value: int)` rejects with the same error.

Use the resolved builtin implication set, and pass equivalent guarantees through
both lookup paths. Existing builtin semantics and named-bound composition must
agree between standalone and module checking.

### 5. P2: valid overlapping bounds exceed the limit only in module projects

Location: [generic_requirements.zig](../../src/generic_requirements.zig#L228).

Interface-time validation sums each bundle's raw member count without coalescing
overlap. It runs before semantic normalization, so the semantic path cannot
rescue a valid module program.

Repro `overlap_limit_single`: two distinct bundles each contain `copy` and the
same eight fields. `T: A + B` checks successfully as a standalone program: nine
unique requirements. Adding only a module header rejects with `E_GENERIC_LIMIT`
because preflight counts eighteen (`overlap_limit_module`).

The handoff acknowledges this but incorrectly limits its practical impact by
calling the semantic path authoritative. Module compilation already stops at
preflight. Normalize consistently across modules, or defer the expanded limit
until a phase with correct identities. Preserve the bounded-work checks.

### 6. P2: checked public schemas erase named contracts

Location: [generic_api.zig](../../src/generic_api.zig#L49) and the public tooling
integration omitted from the change.

`schema-project examples/named-constraints/main.my --schema-report` succeeds,
but `checkout::total` reports its `P` with all three requirement arrays empty:

```json
{
  "name": "P",
  "requirements": [],
  "field_requirements": [],
  "operation_requirements": []
}
```

Neither the named bound nor its required `price` operation appears there.
An agent inspecting the checked API cannot discover how to implement a provider.
This directly undermines the intended independent-development workflow.

The handoff lists this as deferred “polish”; sections 6–7 of the brief require
it. Expose exported constraint definitions, bound references and resolved promises
with a versioned schema representation. Cover navigation separately; the pre-body
text inventory's constraint name alone does not replace a checked contract.

### 7. P2: standalone files accept duplicate and colliding constraint declarations

Locations: [constraint_lookup.zig](../../src/constraint_lookup.zig#L39) and
[nominal_sources.zig](../../src/nominal_sources.zig#L35).

Constraint names enter the module index, but the standalone path does not enforce
the same declaration namespace. `findLocal` simply selects the first matching
definition.

`single_duplicate_used` declares `C[T] = copy` followed by `C[T] = integer`,
then passes `True` to a function bounded by `C`. The program checks successfully
using the first declaration. `single_name_collision` also accepts a record and
a constraint both named `C`.

Reject these declarations before resolving uses, including when neither is used.
Add standalone coverage alongside the existing module collision tests. A file
should not acquire different namespace rules by adding a module header.

### 8. P2: an unused constraint can contain an invalid result-bearing field

Location: [nominal_sources.zig](../../src/nominal_sources.zig#L60).

The new definition-validation path resolves signature types and checks nominal
arguments but does not apply the full structural-field validity checks. Those
checks currently happen when a function consumes the constraint.

`unused_result_field` declares
`Bad[T] = copy + field(value: Result[int, int])` and successfully checks.
Adding an otherwise unused function bounded by `Bad` makes the same declaration
reject with `E_GENERIC_REQUIREMENT`: structural fields cannot carry pending
result obligations (`used_result_field`).

Validate the complete structural declaration when checking its definition, even
before a consumer exists. Test result-bearing and move-only fields and supported
composite field types, not just unknown type names and missing `copy`.

## Evidence and verification

The [reproduction evidence](named-constraints-review-2026-09-15-probes.json)
contains complete sources, commands, exit statuses, diagnostics, binary hashes,
current-checkout confirmations, native execution results and the checked schema
excerpt. Repro names above match entries in its `target.results` array.

- Reviewed the implementation commit and the required behavior in the brief.
- Ran 18 focused checking probes, including controls that change only bound
  order, binder spelling, module presence, or whether a definition is used.
- Ran the two incorrectly accepted contract programs as native executables;
  both exited successfully. These are contract-checking failures, not merely
  misleading diagnostics.
- Reproduced the three P1 cases and the module `copy`/limit failures using the
  current checkout's compiler as well as the implementation worktree's compiler.
- The existing production example ran successfully. The fake example passed
  with `--force` (one test executed, no result receipt reused).
- `zig build test-units -Dtest-filter='named constraints'` on the implementation
  worktree and `zig build test-units --summary all` on the current checkout
  succeeded using cached test results. These are not fresh executions of the
  entire suites. Guardian's attached 88-check runs passed with their reported
  diff scopes; they do not establish correctness of these additional cases.
- The previously reported managed-metadata test fixture is corrected by the
  later commit `3c0b41f`. It is not a remaining named-constraints blocker.

The review did not rerun every full repository gate, benchmark compilation speed,
or establish new incremental reuse guarantees. The problems above are directly
reproduced correctness failures and missing required integration.

## Recommended repair order

1. Fix the imported export lookup panic and both type-identity failures.
2. Make interface and semantic constraint validation use consistent normalized
   contracts, including `copy` implications, overlap and limits.
3. Complete declaration validation, standalone namespace checks and checked
   public tooling.
4. Add the repros as permanent regressions, then run the required native, module,
   generic, cache and documentation gates from the original brief.

Keep the public V1 syntax while fixing these internals. The findings do not
justify adding runtime interfaces or expanding the language's feature scope.
