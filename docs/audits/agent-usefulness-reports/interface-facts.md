# F1(a) — honest interface facts: report

Package: **F1(a)**, "Make compiler facts unambiguous and current" — the half that
separates declared ceilings, inferred summaries and analysis status on the older
fact surfaces (`list-interfaces`, `index-project`, `list-interfaces --contracts`).

| Fact | Value |
| --- | --- |
| Status | **complete and gate-green**; the one deliberate behaviour change beyond the unavailable/declaration-only rendering is the lead-approved template case (below) |
| Gate | `zig build` 88/88 guardian checks passed; `zig build test --summary all` = `64/64 steps succeeded; 1452/16165 tests passed (14713 skipped)`, exit 0 (the pass count moves as concurrent packages land tests; it read 1421/16134 mid-session) |
| Focused tests | `interfaces` 79/79, `navigation` 24/24 (`scripts/focused_test.py units`) |
| Other gates | `zig build fmt-check` exit 0; `zig build test-docs` 0 failed/0 mis-tagged; `mylang doc-coverage .` 164 features, 0 failures |
| Pre-change binary used for every "before" measurement | copy of `zig-out/bin/mylang` taken before the first edit (sha256 `5f4ef7de30ef7313e1bf47000921c04754057bc36ef29ddc90b0e7a8c061c2bb`) |

## The defect, reproduced and fixed

`/tmp/w0probe/hole.my` (the W0 baseline fixture, unchanged):

```mylang
# doc: expect-error E_TYPED_HOLE
module hole

public def double(x: int) -> int effects(managed_allocation):
    return x * 2

public def unfinished(x: int) -> int:
    return todo[int]()

def main() -> int:
    return double(2)
```

`mylang check hole.my` exits 1; its stderr is **byte-identical before and after**
(`cmp` on the two captures), so `E_TYPED_HOLE` and its spans are untouched:

```
hole.my:7:12: error[E_TYPED_HOLE]: unresolved implementation obligation; fill this hole before checking or execution
      return todo[int]()
             ^
  note: hole.my:7:17: required result type declared here
```

`mylang list-interfaces hole.my` (exit 0 both times):

before — the complete and the incomplete function are indistinguishable, and the
checker's conservative internal mask is published as if it were inferred:

```
# doc: not-mylang
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module hole
  export function double def(x:i64)->i64 effects(filesystem,network,clock,random,environment,host,managed_allocation,output,mutation) ceiling(managed_allocation)
  export function unfinished def(x:i64)->i64 effects(filesystem,network,clock,random,environment,host,managed_allocation,output,mutation)
```

after — the declared ceiling stays visible, the inferred set is unavailable, the
status says why, and the test relationship is unavailable rather than silently
absent:

```
# doc: not-mylang
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module hole
  export function double def(x:i64)->i64 effects(unavailable) analysis(declaration-only) ceiling(managed_allocation) tests(unavailable)
  export function unfinished def(x:i64)->i64 effects(unavailable) analysis(declaration-only) tests(unavailable)
```

A completely checked module (`/tmp/f1probe/complete.my`) renders exactly as before:

```
# doc: not-mylang
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module complete
  export function double def(x:i64)->i64 effects() ceiling(managed_allocation) tests(0)
  export function pure def(x:i64)->i64 effects() tests(0)
```

`mylang index-project hole.my`, before → after, per symbol:

```
before  {"id":"hole::double",     "effects":[], "mutates":[], "return_origin":"unknown", "mutation_writes":false}
        {"id":"hole::unfinished", "effects":[], "mutates":[], "return_origin":"unknown", "mutation_writes":false}
        {"id":"hole::main",       "effects":[], "mutates":[], "return_origin":"unknown", "mutation_writes":false}
after   {"id":"hole::double",     "analysis":"declaration-only", "effects":null, "mutates":null, "return_origin":null, "mutation_writes":null}
        {"id":"hole::unfinished", "analysis":"declaration-only", "effects":null, "mutates":null, "return_origin":null, "mutation_writes":null}
        {"id":"hole::main",       "analysis":"declaration-only", "effects":null, "mutates":null, "return_origin":null, "mutation_writes":null}
```

`mylang list-interfaces --contracts hole.my` gained one envelope field and changed
nothing else:

```json
{"version":"interface-contracts-v2","analysis":"declaration-only","modules":[{"name":"hole","declarations":[
 {"name":"double","kind":"function","signature":"def(x:i64)->i64","generics":"","permissions":"effects=managed_allocation;mutates=;origin=unknown","shape":""},
 {"name":"unfinished","kind":"function","signature":"def(x:i64)->i64","generics":"","permissions":"effects=filesystem,network,clock,random,environment,host,managed_allocation,output,mutation;mutates=;origin=unknown","shape":""}]}]}
```

## The vocabulary, and why it is spelled this way

`src/fact_status.zig` (new, 44 lines) is the single definition the compiler's own
surfaces share:

| Status | Meaning | Where it appears |
| --- | --- | --- |
| `checked` | bodies were checked and this declaration has a checked summary | never printed; the absence of the field/key on a checked fact |
| `template` | bodies were checked, but no call instantiated this generic declaration | `analysis(template)` / `"analysis":"template"` |
| `declaration-only` | declarations and exported signatures were checked; bodies were not | `analysis(declaration-only)` / `"analysis":"declaration-only"` |
| `declared` | a type, resource, constraint or field declaration, which has no body | `"analysis":"declared"` on non-callable symbols of an unchecked index |
| `lexical-only` | only top-level lexical candidates survived a syntax failure | `"analysis":"lexical-only"` from the partial renderer |

The names are the ones `src/reference.zig` already publishes as
`analysis: checked | template | declaration-only | declared` and
`docs/reference.md` §Fact status defines. **`src/reference.zig` mirrors them
deliberately rather than importing them**: that file belongs to the executable's
root module (it takes the compiler as a `comptime language: type` parameter), so a
Zig file may not be shared with the `mylang` module, and the package brief marks it
off-limits. Between the two surfaces that *can* share — `interfaces.zig` and
`navigation.zig` — the vocabulary is one shared module, and `FACT-STATUS-1` pins
the spellings next to the reference's own tests. `unavailable` is
`reference.zig`'s envelope status for a standard library that could not be loaded
at all; neither interface surface can be in that state (the index either builds, or
the command exits 1 with diagnostics), so no producer here would ever emit it and
it is not invented.

`checked` is a real value, not a default: a surface prints nothing for it because a
checked fact is exactly the payload a consumer already reads, which is what keeps
every previously checked answer byte-identical.

## How checked output was proved unchanged

Method: the pre-change binary was copied before the first edit; both binaries were
then run over every `.my` file under `examples/`, `experiments/`, `selfhost/`,
`src/schematic/guest/` and `tests/lang/` (2615 candidates); files where the
pre-change binary's `check` failed were skipped, leaving **569 checked programs**.
For each, `list-interfaces`, `list-interfaces --contracts` and `index-project` were
run with both binaries and compared byte for byte (`index-project` with
`compiler_sha256` and `snapshot_sha256` normalised, since those identify the build,
not the source).

| Surface | Differs | Composition of every difference |
| --- | --- | --- |
| `list-interfaces` | 4 of 569 (8 lines) | all 8 lines are generic declarations no call instantiated — `random::choice`, `random::shuffle` (twice, two applications use the same module), `generic_arrays_case_1::contains`, `math::min`, `math::max`, `math::clamp`; each old line was the full conservative mask and each new line is `effects(unavailable) analysis(template)` with the declared `ceiling(...)` (including an explicitly empty `ceiling()`) and `mutates(...)` preserved |
| `index-project` | 5 of 569 (11 symbols) | the 8 template symbols above plus three listing-invisible unexported templates in `tests/lang/migrated/structural_constraints.my` (`structural_constraints_case_1::forward`, `_2::use`, `_3::f`, `_4::unused`, `_4::concrete`); each gets `"analysis":"template"` plus `null` inferred fields; no non-generic function and no type declaration changed |
| `list-interfaces --contracts` | 480 | all 480 differ by exactly one inserted key, `"analysis":"declaration-only",`, verified programmatically by deleting that key and re-comparing (`non-key: 0`) |

Independent checks:

- **Every status-changed symbol in the whole sweep is generic**: all 11 carry type
  parameters in their own published signature — `choice[T: copy + storable](…)`,
  `shuffle[T: copy + storable](…)`, `contains[T: equality](…)`,
  `min[T: integer](…)`, `max[T: integer](…)`, `clamp[T: integer](…)`,
  `forward[T: Id + op(identity(x: T) -> T effects())](…)`, `use[T: A + B](…)`,
  `f[T: A + B](…)`, `unused[T: A + B + op(…)](…)`, `concrete[T: C + D](…)`. Zero
  ordinary functions and zero type declarations were relabelled.
- **No exit status moved**: for all 57 checked programs of the narrower sweep,
  `list-interfaces --contracts` exit codes and stdout bytes were compared; the
  only stdout change is the added key.
- **`check` diagnostics are byte-identical** on the hole fixture (above).
- **Unit tests pin the checked rendering**: `INTERFACE-FACTS-1` (second case)
  asserts the exact checked lines `effects() ceiling(managed_allocation) tests(0)`
  and the absence of `analysis(`/`unavailable`; `NAVIGATION-FACTS-1` (second case)
  asserts a checked symbol keeps `effects: []`, `mutates: []` and a real
  `return_origin` with **no** `analysis` key; `INTERFACE-CONTRACT-STATUS-1`
  asserts the checked manifest contains no `"analysis"` key at all.

### The one approved exception: an uninstantiated template in a checked project

A generic declaration that no call instantiated has no inferred summary *even when
the project checks completely* — the pre-change rendering published the checker's
conservative `all` mask for it. The lead confirmed this is the same defect and that
byte-identity protects known facts, not fallbacks, so it now renders
`effects(unavailable) analysis(template)` (text) and
`"analysis":"template"` with `null` fields (JSON). The only repo programs this
touches are the ones listed above; `tests/lang/standard_strings.my`'s listing is
the one checked-program listing in the tree whose bytes differ, in exactly those
three `math` template lines. All other checked contracts are unchanged.

## Files changed

| File | Change |
| --- | --- |
| `src/fact_status.zig` | **new**: the shared analysis-status vocabulary (`Status`, `name`), mirroring `src/reference.zig`'s spellings with the reason recorded |
| `src/interfaces.zig` | `publishedEffects` returns `?effect_set.Mask` (null = no checked instantiation) instead of falling back to `effect_set.all`; `renderFunctionLine` prints `effects(unavailable)`, `analysis(STATUS)` and `tests(unavailable)`, and keeps the declared ceiling/`mutates`/docstring clauses; `ContractManifest` gains an optional envelope `analysis` (omitted when checked); `contractFunction` keeps the declared-bound meaning of `permissions` with the reason on the field |
| `src/navigation.zig` | `Symbol.Details.analysis` (default `lexical-only`); `jsonStringify` publishes the checked field set unchanged or `analysis` + `null` inferred fields; `declarationAnalysis`/`functionAnalysis` classify declarations, and `functionFacts` promotes typed entries to `checked` |
| `src/interfaces_test.zig` | 5 new tests (`INTERFACE-FACTS-1`, `-2`, `INTERFACE-CONTRACT-STATUS-1`, `FACT-STATUS-1`) |
| `src/navigation_test.zig` | 4 new tests (`NAVIGATION-FACTS-1`, `-2`, `-3`) and one existing fixture updated to state `analysis = .checked` because it pins the checked wire shape |
| `SPEC.md` | 7 appended bullets (append-only; the `spec` guardian check is green) |
| `src/features.json` | new `interface-fact-status` tooling slug anchored at the new doc section |
| `docs/tooling/navigation.md` | new section *Fact status in interface and navigation output* with runnable `console` examples, plus the reading/an interface and source-navigation prose brought up to date |

`src/schema_report.zig` and `src/schema.zig` are **unchanged, deliberately**:
`schema_report.render` and `schema.render` both begin with `compilation.check()`,
and `schema-project` on the hole fixture exits 1 with the `E_TYPED_HOLE`
diagnostic and **empty stdout** (verified for both the plain and `--schema-report`
forms). A schema can only exist for a successfully checked project, so there is no
unchecked state for it to label; inventing a status field there would have been a
field with no producer.

## Remaining limits (honest)

1. **`index-project` still has one mixed-provenance field.** For an *exported*
   function with a declared ceiling, E2 publishes that ceiling in `effects` and the
   bound `unknown` in `return_origin` (a private helper publishes the inferred
   summary). The values are declared facts, but JSON has no separate `ceiling`
   field, so a reader cannot see the provenance. Adding one is a byte change to
   every checked symbol of that kind, which the package's byte-identity rule
   forbids; it needs a navigation-v2 envelope or an explicit exception.
2. **Re-export facade symbols keep today's empty arrays.** I deliberately left a
   symbol whose declaration is not a function in the merged syntax (a facade
   entry) at `checked`, so no checked answer moves. Its inferred facts were already
   an empty set and remain one; the honest fix costs bytes for facade projects.
3. **The contract manifest has no per-declaration status.** `ContractDeclaration`
   is at the 7-field cap and its `permissions` string is compared by
   `native_test_contracts.zig`'s frozen set-subset relation, which cannot carry an
   unknown token (a production `effects=unknown` would reject every provider that
   declares a real effect). The new envelope-level `analysis` covers the only
   production path (`list-interfaces --contracts` never attaches a program); a
   template inside a *unit-test-attached* checked manifest still publishes its
   bound without a per-declaration caveat.
4. **No diagnostic-code reason for unavailability.** The surfaces can say
   `declaration-only`, not `E_TYPED_HOLE`: `main.zig`'s `listInterfaces` discards
   the body diagnostic and restores the pre-check project problem before
   `Index.render` runs, so the reason is gone by render time. Carrying it would
   need an `Index` field set from `main.zig` (off-limits here).
5. **Lexical-only symbols still publish empty `signature`/`type_name` strings.**
   The partial renderer has no source text for them. I bounded the change to the
   inferred fields the plan names (`effects`, `mutates`, `return_origin`,
   `mutation_writes`); making the text fields `null` as well is a further step.
6. **`tests-for` and `lint` need no status field**: both run only after a
   successful check (an unchecked project exits 1 with diagnostics), and no JSON
   surface reports a test count for an unchecked project, so there is no "zero
   tests" claim to correct. The listing's `tests(N)` column was the one place a
   test relationship could be read as zero-by-omission, and it now says
   `tests(unavailable)`.

## Cross-package findings

1. **`scripts/navigate.py:152` breaks on the new null** (I may not edit `scripts/`).
   `--effect` filters with `effect in item['effects']`; on an unchecked project
   `effects` is now `null`, so
   `python3 scripts/navigate.py --compiler zig-out/bin/mylang --entry /tmp/w0probe/hole.my --effect managed_allocation`
   prints `navigate: argument of type 'NoneType' is not a container or iterable`.
   One-line fix: `(effect is None or effect in (item['effects'] or []))`. The
   already-checked path is unaffected.
2. **`main.zig` discards the body diagnostic before the interface gate renders**
   (`listInterfaces` saves/restores `project.problem`). If a future package wants
   the exact diagnostic code as the unavailability reason, `Index` needs a field
   that `main.zig` sets on the failed check — a small, contained change in files
   this package does not own.
3. **Any golden artifact that pins the old fallback lines must be regenerated**:
   only `tests/lang/standard_strings.my`'s listing is affected in-tree, and no
   gated golden test pins it (`test/golden_parity.zig` does not run
   `list-interfaces`). The gate is green with the new lines.
4. **`src/reference.zig` needs no change**: it reads inferred effects from the
   checked program itself (with its own `template` detection) and only parses
   declared clauses out of the listing, so the new `analysis(...)` and
   `effects(unavailable)` tokens pass through its parser untouched. This was
   verified by `zig build test` (`test-agent-usefulness` green) and by
   `mylang reference --query …` on the installed binary.
