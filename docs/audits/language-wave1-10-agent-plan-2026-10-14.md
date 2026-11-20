# Language wave 1: coordinator plus ten workers (2026-10-14)

Prepared 14 October 2026 as the execution handoff for one coordinator and ten
workers, L01 to L10. Wave 1 carries out the two outstanding decisions of 13
October (scalar domains removed, the inferred effect system deleted) and the
seven removals among the
[surface proposals](../design/surface-simplification-2026-10-13.md): proposals 5
(comprehensions and generator arguments), 10 (lambdas), 11 (conditional and
`match` expressions), 12 (negative indexes), 13 (tuples), 14 (sequence
repetition) and 15 (`in` on a list). Every removal lands with its `mylang fix`
migration, as `CLAUDE.md` requires. Wave 2 (methods on built-in types, punning,
unqualified cases, scalar `match`, the lints) and wave 3 (`str` as bytes, slices
as views) are out of scope.

Why now: every feature removed here is one the ownership migration, the parity
work and the self-hosted compiler no longer have to carry. Proposal 12 is also a
performance change: the negative-index wrap is the check shape that keeps LLVM
from eliminating bounds and overflow checks in the VM dispatch loop
([parity plan](lox-eda-zig-parity-plan-2026-10-13.md), cause C4).

## Base and constraints

Plan base, local `main`:

```text
0a9288890 docs: plan the caching follow-up and the fast-forward of main
```

`C0` is the tip of `claude/language-wave1-plan-20261014` (that commit plus this
plan and the design text). Recheck before starting; if `main` has moved, build
`C0` from current `main` plus this branch's documentation commits.

**The caching follow-up is running at the same time**
([its plan](caching-followup-10-agent-plan-2026-10-14.md), branch
`codex/caching-followup-20261014-integration`). Its timing samples only qualify
while the host's one-minute load average is below 4. Until its R2 round has
recorded qualified K1 samples (read
`experiments/caching-followup-20261014/status.md` on its integration branch, or
ask the user), run **at most four** wave 1 workers with builds, in this order:
L01, L02, L03, L09. Start the other six once R2 is recorded. Never use timing
admission; ordinary builds and gates go through `scripts/build-slot.sh`.

Files both programs touch: `SPEC.md` (the `spec-bullets` merge driver merges
appended bullets), `CLAUDE.md` (the caching run edits the caches and gate
sections; this wave edits "Where the language differs from Python"),
`build.zig` (new test registrations only), and
`src/core/test_runner_portable.zig` (L04 changes how a test's host use is
decided; tell the caching coordinator, because that decision affects which
receipts are shared).

## What a removal means in this wave

The old forms cannot simply be deleted from the parser, because almost every fix
needs types: a comprehension's accumulator needs its element type
(`mut out: int[] = []`), `s * n` repeats only when `s` is a `str`, `in` changes
only on a list, and `d[-1]` on a `dict[int, V]` is a key, not an index. So each
feature lands in two steps:

1. **Reject with a fix.** The checker still types the old form, then reports
   `E_<FEATURE>_REMOVED` with `sink.appendFix` (non-fatal, so every site in a
   function gets its fix in one round, like `E_MUTATION_MARKER` at
   `sema_calls.zig:786,799`), using `typed.surfaceTypeName` (`typed.zig:469`) to
   spell types. The fix is attached only where the edit is certain; elsewhere the
   diagnostic explains the rewrite. Lowering of the old form to Core is deleted
   in this step, because a rejected program never lowers.
2. **Delete what only the old form used** once the corpus is migrated: Core
   machinery, runtime helpers, caches' format entries, docs. The typed
   recognition that produces the fix stays until wave 2 completes, so a user
   upgrading across the wave gets the fix; a later cleanup removes it.

Name every new code `E_<FEATURE>_REMOVED`: `scripts/migrate_embedded.py` already
excludes `# doc: expect-error E_*_REMOVED` examples from rewriting.

**Templates to copy.** A checker-level certain fix: `src/dictionary_views.zig:285-311`
(`E_VIEW_STORED`, `snapshotFixCertain`), its fixture
`test/fixtures/fix-migration/dictionary-views.my` and test
`test/fix_cli_test.zig:481-505`. A parser-level multi-edit fix:
`rejectMutatesClauseOf` (`src/parser.zig:1317-1360`). A whole-block fix:
`src/arena_fix.zig` with `src/retired_features_test.zig`. `diagnostic.Fix`/`Edit`
are at `src/diagnostic.zig:51-66`. Every migration test follows FIX-MIGRATION-1:
`fix --check` exits 1 and leaves the file unchanged, `fix` exits 0, the content
matches, `check` exits 0, a second `fix --check` exits 0. Each worker puts its
migration tests in its own new file, `test/fix_wave1_<feature>_test.zig`, not in
`test/fix_cli_test.zig`, whose FIX-MIGRATION-2 asserts exact edit counts
(`:316-317`) that the coordinator updates once per round.

**The corpus is regenerated, never merged.** Worker branches commit the compiler
change, its tests and docs, and then a separate last commit titled
`migration (generated): <feature>` produced by `mylang fix` and
`scripts/migrate_embedded.py` over the tree. The coordinator integrates the
compiler commits only, then L10 regenerates the migration on the integrated tree
with every integrated fix at once and the coordinator commits that. Files touched
by several features (most of `tests/lang`) therefore never conflict.

**What migrates and what does not.**

| Path | Treatment |
| --- | --- |
| `tests/lang` (350 files), `test/core` (183), `examples`, `bench`, `benchmarks`, `velocity`, live `docs/**` fences, Zig `\\` guest strings, golden JSON | Regenerated by `mylang fix` and `migrate_embedded.py`; IR, counter and LLVM expectations in `test/core` updated by hand where the generated code changes |
| `src/stdlib/*.my` | Edited by hand (`fix` drops `@stdlib/` edits, `fix_command.zig:275`) |
| `selfhost/components/**` | Built by the pinned seed, which speaks the old language, but checked by the live `fmt --check`: rewrite the few uses (comprehensions in `cache_plan/incremental.my` and `tests.my`, bytes repetition in `cache_plan/tests.my`) to plain loops both compilers accept; no `lists.*` there |
| `test/core/conformance.pins` (35 pinned files, 12 affected) | Migrate the bodies; keep every pinned test name |
| `experiments/`, `test/fixtures/fix-migration/`, diagnostic tests that contain old syntax on purpose, `docs/audits`, `docs/design`, `docs/adr`, legacy trees | Not rewritten |

## Decisions this plan takes

The user approves these by approving the plan:

- **A declaration without an initializer.** `mut name: T` with no value,
  definitely assigned on every path before its first read, checked by the
  definite-initialization analysis that already exists
  (`sema_operators.zig:307-323`). It is the only way to turn
  `const x = a if p else b` and a `match` expression into statements that keep
  both branches on their own lines without evaluating a placeholder.
- **Repetition replacements match today's `*`.** `strings.repeat(s, n)` and
  `lists.filled(n, v)` return an empty value for `n <= 0` and do not fail, so the
  migration is exact. The existing fallible `strings.repeat` (`strings.my:133`)
  changes to that signature, and its seven callers migrate by fix.
- **Negative indexes trap with the existing codes.** A negative index or slice
  bound raises `R_LIST_BOUNDS` / `R_TEXT_BOUNDS` (one unsigned comparison catches
  it); an upper slice bound beyond the length still clamps; the trap message
  names the wave so a runtime-computed negative is easy to recognise.
- **Records as sort keys.** A record whose fields are all orderable orders field
  by field in declaration order when it is a `sorted`/`sort` key, so a tuple sort
  key migrates to a record key exactly. Records with hashable fields are dict and
  set keys if they are not already.
- **Domain JSON.** A former domain becomes an ordinary record and serializes as a
  JSON object; no special case for one-field records. L03 reports every persisted
  shape that changes. (The design text leans the other way; this keeps one rule
  for all records.)

## Ownership and operating rules

**Coordinator only:** `build.zig`, `build_test_inputs.zig`, `SPEC.md`,
`CLAUDE.md`, `guardian.toml`, `src/features.json` (through L10's patch queue),
`test/fix_cli_test.zig`, the frontend cache, semantic summary and module
interface format versions (`frontend_cache.zig:25`, `semantic_summary.zig:24`,
`module_interface.zig:31`, bumped once per round), and the ledger.

**Shared compiler files are claimed by function.** `src/parser.zig`,
`src/ast.zig`, `src/typed.zig`, `src/sema.zig`, `src/sema_expressions.zig`,
`src/sema_statements.zig`, `src/sema_operators.zig`, `src/sema_collections.zig`,
`src/sema_builtins.zig`, `src/generic_bodies.zig` and
`src/frontend_migration*.zig` are edited by several workers; each worker edits
only the functions listed in its assignment and sends a patch request for any
other. The coordinator merges in round order and resolves conflicts.

**Operational rules** as in `CLAUDE.md`: `source ~/.config/mylang/dev-env.sh` in
every worktree; private `ZIG_LOCAL_CACHE_DIR` and on-disk `TMPDIR`; builds and
focused tests through `scripts/build-slot.sh build`; complete verification
through `scripts/verify_cache.py` (it owns admission), once per integration
round by the coordinator; every new behavioural line under `src/` gets a test
tagged `// spec: TAG` and a `SPEC.md` bullet (send bullets to the coordinator);
Guardian's struct, parameter and doc-comment rules apply. Workers commit fixed
SHAs and a `handoff.md` under `experiments/language-wave1-20261014/LNN/`; only the
coordinator integrates; nobody pushes. Fast-forwarding `main` to the final
integration commit is authorized when R5 passes its complete verification and
nothing on `main` has moved; otherwise present the commit to the user.

## Ten workers

| Worker | Removes or adds | First deliverable |
| --- | --- | --- |
| L01 | Shared migration machinery; declarations without an initializer | Helpers and the new declaration, with tests |
| L02 | `lists` module, `strings.repeat`; proposals 14 and 15 | The library words with docs and fixtures |
| L03 | Scalar domains (decision) | Rejection and fix for `domain`, `wrap`, `unwrap`, `X.f` |
| L04 | The inferred effect system (decision) | The mutation pass moved out of `effects.zig` |
| L05 | Lambdas (proposal 10) | Checker-level fix that writes the named function |
| L06 | Conditional and `match` expressions (proposal 11) | Statement-level fixes using L01's declaration |
| L07 | Comprehensions and generator arguments (proposal 5) | Statement-level fixes with typed accumulators |
| L08 | Tuples (proposal 13); records as sort and dict keys | Record keys, then tuple-return fixes |
| L09 | Negative indexes (proposal 12) | Trap semantics in lowering, emission and runtime |
| L10 | Corpus regeneration, docs, features, conformance, audits | Exact site counts on `C0` and the regeneration script |

### L01 — Shared migration machinery and declarations without an initializer

**Own:** a new `src/migration_support.zig` (fresh names that collide with no
active binding or declaration, indentation-preserving statement insertion,
"hoist before the enclosing statement", a purity predicate for operands, and the
evaluation-order certainty check), the declaration change in `src/parser.zig`
(binding statement parse, `:1554-1555`) and its checking in
`sema_statements.zig`/`sema_operators.zig` (definite initialization), tests in
`src/migration_support_test.zig`, and the declaration's section in
`docs/statements.md`.

`mut name: T` with no initializer is legal when every path assigns it before any
read; `const` still requires a value. Publish the helper API in `handoff.md` on
day one; L05 to L08 build on it.

**Accept:** definite-assignment errors for a read before assignment on any
path, including loops, `match` arms, early `return` and `try`; helpers unit
tested on nested blocks and comments; SPEC bullet and docs example.

### L02 — Library words; sequence repetition and list membership

**Own:** new `src/stdlib/lists.my` (`filled[T](n, v)`, `contains[T: equality](xs,
x)`, `last[T](xs) -> T?`), its registration in `src/standard_library.zig:4-25`, a
fixture under `src/stdlib/fixtures/`, `strings.repeat` in `src/stdlib/strings.my`,
a bytes repetition function in the module that owns bytes operations, the
`## lists` section of `docs/standard-library.md` (every export named with a `#`
comment above it, as doc-coverage requires); the repetition checker
(`sema_idioms.zig:55-61,100-107,182-195`, `repetition.zig`,
`sema_statements.zig:615`, `sema.zig:1064-1075`), its Core
(`build.zig:1934,1995`, `build_values.zig:100-136`) and runtime
(`core_values.c:9-26`, `zero_rc.zig:167`); the membership checker list arms
(`sema_operators.zig:380-434`) and Core (`build.zig:2464-2468`,
`build_values.zig:65-69`; keep `firstIndex`, which `list.index` shares).

Check whether `tests/guest/lists.my` collides with the new module name. `in` on
`str`, `bytes`, dictionaries and sets stays; `x in d.values()` is a list scan and
is removed with lists. The membership fix to `lists.contains(xs, x)` reverses
evaluation order (today the needle is evaluated first), so it is certain only
for pure operands; it inserts `import lists` (identical insertions apply once,
`fix_plan.zig:31-36`).

**Accept:** `E_REPETITION_REMOVED` and `E_LIST_MEMBERSHIP_REMOVED` with fixes;
`"-" * n` and `[0] * n` give the same values as `strings.repeat` and
`lists.filled` for every `n`, including negatives; the stdlib fixtures pass;
doc-coverage green.

### L03 — Scalar domains

**Own:** the domain surface in `lexer.zig:27-33,244-250`; parser domain
declaration (`:928-949`), `domainMember` (`:747`), `codec` (`:654-674`),
`parseWrap` (`:2537`), `unwrap` (`:1946`, `:2595`), `op(...)` (`:1229-1230`,
`:1296-1311`), `E_PRIVATE_SCOPE` (`:1028-1029`); `nominal_catalog.zig:288-299`,
`type_catalog.zig:159`; the wrap/unwrap checks (`sema_expressions.zig:827-841`);
owner-qualified `X.f` resolution and domain privacy (`sema.zig:700-747`,
`interfaces.zig:183`); `structural_constraints.zig`, the named-constraint
machinery, `domain_codecs.zig`, `source_codec.zig`, the domain arms of
`source_json.zig:23` and `data_type.zig:46-60`, `sema_contracts.zig:199,504`;
`generic_bodies.zig:569,673,1943-1980,2034,2077-2083`; property-test support
(`property_types.zig:108`); Core `build.zig:351-366,1550-1557,2248-2263`; tests
`domains_test.zig`, `domain_codecs_test.zig`, `domain_equality_test.zig`, the `op`
part of `structural_constraints_test.zig`, `named_constraints_namespace_test.zig`,
`test/named_constraints_probes.zig`; docs `docs/domains.md` and the domain parts
of `generics.md`, `contracts.md`, `typed-json.md`, `functions.md`,
`floating-point.md`.

Remove the source surface only. `shape.domain` and the typed `.wrap`/`.unwrap`
nodes also represent `float` (`nominal_catalog.zig:290`, `numeric_surface.zig:84`,
`sema_idioms.zig:212`, `prelude_builtins.zig:938`) and callback types
(`nominal_catalog.zig:323`, `callables.zig:145`); keep them. `ast.Domain` is shared
with `resource` (`parser.zig:839`); keep what `resource` needs.

The fix: a `domain` becomes a one-field record with its invariant, `wrap[X](v)`
becomes `X(value=v)`, `unwrap(x)` becomes `x.value`, `X.f(a)` becomes `f(a)`.
When two former domains in one module define the same member name, the fix
renames to `<domain>_<name>` rather than withholding (FIX-MIGRATION-CAPTURE-1,
`SPEC.md:314`). Generic code under `op()` takes the operation as a function value.

**Accept:** `E_DOMAIN_REMOVED` with fixes for every example under `examples/`
(`domains.my`, `domain-codecs/`, `structural-constraints.my`, `generic-arrays.my`,
`named-constraints/`, `corpus/invoice/`, `modules/shared/units.my`,
`interface-files/shop/money`, which `test/integration.zig:4733` API-FILE-3 checks);
generated property tests over the replacement records; a list of every JSON shape
that changes; L04 unblocked (codecs and `op()` no longer require effect bounds).

### L04 — The inferred effect system

**Own:** `src/effects.zig` (1,128 lines) and `src/effect_set.zig`; the effect
clause in `parser.zig` (`effectBound` `:1370-1397`, callback ceilings `:587`,
`op()` bound `:1309`, `E_HOST_EFFECTS` `:1042-1046`, constants' implicit bound
`:886-888`); `ast.zig:258,280,447`; `typed.zig:253,754-755`; effect sites in
`sema_calls.zig:128-175`, `callables.zig:49-96`, `generic_bodies.zig` (`checkAbstract`
callers and the mask sites), `lint.zig:2244-2265`; every consumer of effect facts
in interfaces, hashes and caches (`incremental.zig:600-710`, `semantic_key.zig:160-210,455`,
`semantic_summary.zig:47`, `generic_cache.zig:193-205`, `module_interface.zig:314`,
`interfaces.zig:694-1009,1105,1349`, `interface_files.zig:181-191`,
`generic_api.zig:231,268`, `context.zig:1051-1072`, `reference.zig:309-541`,
`navigation.zig:327`, `schema_graph.zig:194`, `core/build_host.zig:43`);
`effects_test.zig` and the effect parts of `external_capabilities_test`,
`callbacks_test`, `interfaces_test`; `docs/effects.md`, the bounded-callback
section of `docs/functions.md`, `c-ffi.md`, `contracts.md:157`.

1. Move the mutation pass (`effects.zig:865-886`, `mutationPass` →
   `origins.check`) and `E_UNUSED_CAPABILITY` (`effects.zig:16`) out first; both
   stay.
2. Replace the textual `noalloc` clause with an `@noalloc` attribute
   (`parser.zig:763-800`, `ast.zig:342`) feeding the Core check that already exists
   (`core/allocation_contract.zig`, `W_NOALLOC_ALLOCATES`).
3. Extend the contract rule `rejectInContract` (`sema_expressions.zig:613-629`) to
   reject a mention of a capability parameter.
4. `extern func` needs only its `host: Host` parameter; callback types lose their
   ceilings.
5. Replace the inferred `host` fact in `test_runner_portable.zig:59,73` with one
   computed from capability parameters and reachable `extern` calls; agree the
   replacement with the caching coordinator before it lands.
6. Delete inference, `E_EFFECT_BOUND`, `E/W_DERIVED_EFFECTS`, `E_UNKNOWN_EFFECT`,
   `E_DUPLICATE_EFFECT`, `E_HOST_EFFECTS`, `E_CODEC_EFFECT`; the fix deletes every
   `effects(...)` and `noio` clause and turns `noalloc` into `@noalloc`. Do not
   touch `src/core/effects.zig` or `ce2_effects_test.zig` (unrelated CE2 summaries).

**Accept:** about 380 annotation sites migrated by fix (72 in the stdlib by hand);
interface files and fingerprints no longer carry effect fields; a capability
misuse is reported at the operation; `@noalloc` still fails an allocating
function; the stdlib, examples and integration tests pass; about 2,500 compiler
lines removed. Starts implementation after L03's R1 integration.

### L05 — Lambdas

**Own:** `parser.zig:1894-1896,2160-2178`; `ast.zig:317,419`; `sema.zig:369-450,1784-1843`;
`sema_expressions.zig:939-971`; `sema_calls.zig:285-290`; the lambda form of sort-key
inference in `sema_builtins.zig:485-610`; `generic_bodies.zig:46-49,445-451`;
`lambda@` naming in `core/emit_units.zig:99`, `lowering_cache.zig:617`,
`project_compile.zig:183-198`, `lint.zig:954`; lambda entries in
`frontend_cache.zig:240,602,628`, `ast_copy.zig:68`, `project_syntax.zig:101-113`;
tests `tests/lang/lambda_sort_keys.my`, `keyed_sorting.my`, `sorted_keys.my`,
`callbacks.my` and the lambda parts of the listed Zig tests; `docs/lambdas.md`;
mark decision record D5 superseded (`docs/adr/`).

The fix is checker-level: it writes a top-level `func` with a fresh name, the
parameter and result types spelled (including an inferred sort-key type), and
passes it by name. **Accept:** `E_LAMBDA_REMOVED` with fixes for all 40 sites;
the named functions are callable by `mylang test`; about 450 lines removed.

### L06 — Conditional and `match` expressions

**Own:** `if p then a else b` (`parser.zig:1906,2047-2058`), the Python form
(`:2026-2027,2091-2101`), `conditionalDiscard` (`:1600,2059`), `ast.zig:127,130,143`,
`sema_operators.zig:302-374`, match expressions (`parser.zig:1907,2077-2090`,
`sema_statements.zig:310-357,669`), their `generic_bodies.zig` sites
(`105,503-510,2171,2178-2184,2198,2895`), the rewrite in
`frontend_migration.zig:54-61` (today it turns the Python form into the
`then` form; retarget it to statements), `frontend_migration_variants.zig:19`,
`arena_fix.zig:136`. The `yield` statement shares its parse with `fail`
(`parser.zig:1561-1566`): remove `yield`, keep `fail`. Comprehension `yield`
belongs to L07. Tests
`tests/lang/conditional_expression.my`, the four FRONTEND-MATCH-1 tests in
`tests/lang/frontend_types.my:89-230` (convert, keep the names), the
`then`-output assertions in `test/fix_cli_test.zig:175,346,557-559` (patch
request), `docs/python-syntax.md:483-520,548-549`, `docs/statements.md:27`.

Fixes: in a binding, assignment or `return`, the expression becomes an `if` or
`match` statement assigning a declaration without an initializer (L01) or
returning from each arm. In an argument, f-string hole or operand, hoist it into
a fresh declaration before the enclosing statement when L01's check says the
order of evaluation is preserved; otherwise no fix.

**Accept:** `E_CONDITIONAL_EXPRESSION_REMOVED` and `E_MATCH_EXPRESSION_REMOVED`
with fixes for every statement-level site (58 conditional, about 224 `yield`
arms); FRONTEND-MATCH-1 still passes with statement forms; the stdlib's two uses
(`strings.my:271-272`, `json.my:528`) rewritten.

### L07 — Comprehensions and generator arguments

**Own:** list, dict and set comprehensions and generators in `parser.zig`
(`listLiteral` `:2035-2046`, `parseComprehension` `:2274-2284`, `gather`
`:2286-2309`, `comprehensionClauses` `:2252-2269`, `generatorExpression`
`:2313-2318` with `:2111-2116,2734-2740`, `len(generator)` `:2589-2592`, brace forms
`:2388,2394,2405-2415`); `ast.zig:75,78,155,182-205`; `sema_collections.zig:339-371,422-451,455-487`
(keep `comprehensionLoop` `:503-530`, which `set(iterable)` uses); all of
`sema_gathers.zig`; the hooks in `sema_expressions.zig:94,712-713,1007,1100`,
`sema_statements.zig:676`, `sema.zig:1069,1220-1221`, `sema_builtins.zig:317,350,428`,
`sema_collections.zig:928`, `sema_sets.zig:119-120`, `generic_bodies.zig:83-121,937-1020,2123-2124,2887`,
`frontend_binding_migration.zig:135-139,194`, `dictionary_views.zig:252`,
`arena_fix.zig:131,134`, `nominal_type_syntax.zig:6`, and the Python-order rewrite
in `frontend_migration_expressions.zig:12-20,49-130`; tests
`python_comprehension_test.zig`, `collections_fidelity_test.zig`,
`tests/lang/python_comprehension.my`, `dict_comprehensions.my`,
`generator_arguments.my`; docs `managed-memory.md:508`, `python-syntax.md:222,240`.

Fixes: a comprehension at statement level becomes a typed `mut` accumulator
(fresh name, `typed.surfaceTypeName` element type), a `for` loop, an optional
`if` and an `append`; `sum`/`any`/`all`/`min`/`max` become accumulator loops
(`0` or `0.0` by type, `False`/`True`, an optional for `min`/`max` of a possibly
empty input); the fill shape `[for i in range(n) yield v]` with `v` pure and not
using `i` becomes `lists.filled(n, v)` (about 135 sites). Inside a larger
expression, hoist under L01's evaluation-order check, otherwise no fix.

**Accept:** `E_COMPREHENSION_REMOVED` and `E_GENERATOR_REMOVED` with fixes for
the 239 sites; the stdlib use (`hashes.my:24`) and the component uses rewritten
to plain loops; about 1,000 lines removed.

### L08 — Tuples

**Own:** `tupleType` (`parser.zig:498,533-550`), `Node.tuple` (`ast.zig:124`),
`parenthesizedTuple`/`bareTuple` (`:2105-2159`, used at `:1653,1774,1799`),
destructuring (`:1550,1656-1659,1765-1839`); `sema_places.zig:176-340`;
`sema_operators.zig:36-38,467`; `sema_expressions.zig:880,927,1032`;
`sema_collections.zig:268`; the tuple branch of the two-name `for`
(`sema_loops.zig:112-116`; the `enumerate`, `zip` and `.items()` paths already
materialise nothing and stay); `sema_gathers.zig:239-254` (coordinate with L07);
sort keys in `sema_builtins.zig:584-608` and `prelude_builtins.zig:590-616`;
`type_catalog.zig:189`; `Store.unpack` (`typed.zig:646-648`,
`core/tuple_unpack.zig`, `build.zig:782,813-830`, `single_owner.zig:505,585-600`,
`semantic_store.zig:835-870`, `semantic_copy.zig:264`); tests `tuples_test.zig`,
`a01_tuple_origins_test.zig`, `core/a01_tuple_unpack_test.zig`,
`tests/lang/tuples.my`; `docs/tuples.md`.

Keep the internal record shape (`shape.tuple`) wherever Core uses it for
record-like values; remove the surface. First add records as sort keys and as
dictionary and set keys (the decision above). Fixes: a swap becomes
temporaries; a function returning `a, b` gets a synthesized record named after
the function in PascalCase (checked for collisions), fields named from
consistent bare-name returns or call-site destructuring, every return written
`Name(field=value, …)` in full (punning is wave 2), and every project call site
rewritten to a binding plus one binding per field; a tuple sort key becomes a
record key; no fix for tuples that are stored, passed, compared, printed, used as
enum payloads, property parameters or generic arguments, where the diagnostic
explains the rewrite and the corpus is migrated by hand.

**Accept:** `E_TUPLE_REMOVED` with fixes for the certain shapes; the 14
tuple-returning functions and every other live use migrated; printing,
hashing and sorting tests updated; `docs/tuples.md` moved to the removed
features.

### L09 — Negative indexes

**Own:** the list wrap in `collection_lower.zig:274-298` (`index()`, called from
`access()` `:312`, `slice()` `:388-389`, `sema_places.zig:552`) and `sliceStep`
(`:343-356`); fixed arrays (`sema_places.zig:713-728`, `typed.zig:96-100`,
`core/build.zig:1630-1709`); the emitter (`facts.zig:298-330` `normalizedRaw`,
`emit_llvm.zig:1324-1328`, `checkedIndex` `:2618-2651`, `boundsCheck`
`:2681-2701`, `countsFromEnd` `:2718`, `originalIndex` `:2734`, `emit_fn.zig:32`,
`index_checks.zig:160`, `stores.zig:27,204,310`); text and bytes
(`emit_bytes.zig:20-36`, `emit_text.zig:117-135,190`, `build_text.zig:109-121`,
`build_text_more.zig:99`, `build_list_methods.zig:161`); runtime
(`core_text.c:384-400,648,667-707,1259-1275`, `core_bytes.c:186-191`); tests
`tests/lang/array_negative_index.my`, `test/core/negative_index.my`,
`array_places_test.zig`, `core/f2_index_test.zig`, `emit_llvm_test.zig`,
`e2e_test.zig`, `native_execute.zig:839-846`; docs `records-and-unions.md:431`,
`managed-memory.md:201,272`, `text.md:87`, `bytes.md:35`.

A negative index or slice bound traps with `R_LIST_BOUNDS`/`R_TEXT_BOUNDS`; the
upper slice bound still clamps. The fix is certain only for constant negatives
on a pure base: `xs[-k]` → `xs[len(xs) - k]`, `xs[-k:]` → `xs[max(len(xs) - k, 0):]`
(keeping today's clamp). A runtime-computed negative becomes a trap with no
compile-time diagnostic, so audit every `tests/lang` and `test/core` use (about
165 in 31 files) and every stdlib index for a computed negative before landing.

**Accept:** `E_NEGATIVE_INDEX_REMOVED` with fixes for the constant sites; the
wrap compare and select are gone from emitted LLVM for list, text and bytes
indexing (show the before and after IR for a list read and a text slice); the
`--verify-facts` gate passes; record the instruction count of a list-read loop
before and after with `perf stat -e instructions:u`, labelled diagnostic.

### L10 — Corpus regeneration, docs, features and audits

**Own:** `scripts/migrate_embedded.py` and its exclusions, the regeneration script
the coordinator runs each round, the hand migration of `src/stdlib/*.my` sites
that the feature workers do not own, `selfhost/components` rewrites, conformance
pins, `test/core` expectation updates that follow from regeneration, the
`src/features.json` patch queue (every removed slug moved to `removed`,
summaries that mention removed forms rewritten: `list-comprehensions`,
`dict-and-set-comprehensions`, `generator-arguments`, `tuples`,
`destructuring-element-targets`, `expression-bodied-lambdas`,
`conditional-expression`, `fixed-array-negative-indices`, `derived-effect-ceilings`,
`capability-effects`, `bounded-guest-callbacks`, `named-constraints`,
`structural-contracts`, and the summaries of `text-ordering-and-repetition`,
`collection-membership-and-value-equality`, `list-methods-and-indexing`,
`inferred-list-literals-and-slices`, `managed-bytes`, `text-search-ranges`,
`fixed-array-iteration`, `stepped-range`, `discard-name`, `managed-sets`,
`hashable-keys`, `keyed-sorting`, `bytes-sorting`, `limits`), the shared docs
(`docs/python-syntax.md`, `docs/statements.md`, `docs/managed-memory.md`, the
`CLAUDE.md` language section through the coordinator), and the audits.

1. On `C0`, publish exact site counts per feature with the query that produced
   each (they replace this plan's estimates), and the front-end line count.
2. Each round, regenerate the migration on the integrated tree, run `doctest .`,
   `doc-coverage .` and `fmt-check`, and hand the coordinator the generated
   commit.
3. At the end, an audit that finds zero remaining uses outside the exempt paths,
   and the lines removed per feature.

**Accept:** every round's regenerated tree passes the doc gate; the final audit
shows zero uses; `docs/python-syntax.md` describes only the surviving forms.

## Rounds

1. **R0 (day 0).** Coordinator pins `C0` and the ledger. L10 publishes exact
   counts. L01, L02, L03 and L09 start; the rest wait for the caching run's R2.
2. **R1 (days 1–2).** Integrate L01, L02, L03 and L09, regenerate, complete
   verification. Start L04 to L08 once the caching run allows.
3. **R2 (days 2–3).** Integrate L05, L06 and L07, regenerate, verify.
4. **R3 (days 3–4).** Integrate L08 and L04, regenerate, verify.
5. **R4 (day 4).** Step 2 for every feature: delete what only the old forms used,
   bump the cache formats once, verify.
6. **R5 (day 5).** Freeze, L10's zero-use audit, full verification and
   formatting, the parity VM micro-measurement from L09, and the acceptance
   report. Fast-forward `main` if it has not moved.

## Done criteria

| # | Criterion |
| --- | --- |
| W1 | Each removed form is rejected with its `E_<FEATURE>_REMOVED` diagnostic, with a certain fix wherever the plan says one exists, and a FIX-MIGRATION-1-style test |
| W2 | Zero uses of a removed form outside the exempt paths (L10's audit, with its queries) |
| W3 | The complete verification gate, formatting, `doctest .` and `doc-coverage .` pass on the final commit |
| W4 | The stdlib, examples, components and conformance pins pass with their test names unchanged |
| W5 | Emitted LLVM has no negative-index wrap; the list-read instruction count is recorded |
| W6 | The front end is smaller by the lines each worker reports, with the effect system's about 2,500 lines gone |
| W7 | `CLAUDE.md`, `docs/python-syntax.md` and `src/features.json` describe only the surviving language |

## Handoff format

Each worker's `handoff.md` gives `C0`, its fixed SHAs (compiler commits and the
separate generated migration commit), owned files and patch requests, the
diagnostic codes and fixes added, which sites have no certain fix and why,
before and after site counts, tests with commands and exit statuses, lines
removed, and open items.

## Copy-and-paste instruction for the coordinator

```text
Use docs/audits/language-wave1-10-agent-plan-2026-10-14.md as the execution
plan and docs/design/surface-simplification-2026-10-13.md as the language
design it implements. Both are on branch claude/language-wave1-plan-20261014
(local main 0a9288890 plus these documents), checked out at
/home/epentland/ai/canopy/mylang-language-wave1-plan-20261014; read them there
but do not work in that worktree. Pin C0 at that branch's tip; if main has
moved, build C0 from current main plus the branch's documentation commits.

Run one coordinator and workers L01–L10, each in its own worktree and branch
from C0 (codex/language-wave1-20261014-lNN), integrating on
codex/language-wave1-20261014-integration. The caching follow-up is running at
the same time: run at most four workers with builds (L01, L02, L03, L09) until
its R2 round has recorded qualified K1 samples, then start the rest. Never use
timing admission.

Every removal is rejected with an E_<FEATURE>_REMOVED diagnostic and a certain
fix, tested in the worker's own test/fix_wave1_<feature>_test.zig. Integrate
compiler commits only; L10 regenerates the corpus migration on each integrated
tree with mylang fix and scripts/migrate_embedded.py, never merging worker
migration commits. Enforce the ownership rules: the coordinator alone edits
build.zig, build_test_inputs.zig, SPEC.md, CLAUDE.md, guardian.toml,
test/fix_cli_test.zig, src/features.json (through L10) and the cache format
versions; shared compiler files are claimed by function as listed. Do not
rewrite experiments/, the fix-migration fixtures or intentional old-syntax
diagnostic tests.

Integrate in rounds R0–R5 with one complete verification per round. Agree L04's
change to test portability in src/core/test_runner_portable.zig with the
caching coordinator before it lands. At R5, fast-forward main to the
integration commit if its complete verification passes and main has not moved.
Report each done criterion W1–W7 as passed or failed with evidence. Do not push,
do not clear shared caches, and do not edit other sessions' worktrees.
```

For a manually opened worker session, give it this plan, `C0`, its worktree and
the instruction: "Execute LNN only; follow its ownership and acceptance
contract; commit fixed SHAs and return the handoff."
