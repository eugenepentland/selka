# Source navigation

`selka index-project` answers "where is this defined and what uses it" from checked compiler facts, not a text search. It
never executes guest code, and it pins every answer to the exact sources and compiler that produced it.

## Source navigation

By default the command prints a bounded `navigation-summary-v1` overview (see
[the summary and the filters](#summary-and-filters-for-large-projects)). With `--full` it prints one `navigation-v1`
JSON document:

- `symbols`: module-qualified declarations and locals, each with its source range, signature, checked type name, declared
  `mut` parameter positions, declared `return_origin` (`fresh` or `params`), `borrow.positions`, whether the body
  performs any managed write (`mutation_writes`), and a bounded snippet.
- `references`: resolved call, read, write, field and type edges.
- `snapshot`: every loaded module's path, byte length and SHA-256, with the compiler's identity.

The relationships are static: not runtime coverage, and not proof that a change is safe. A project that fails body
checking still produces a partial index with `checked: false` and no checked edges. The index has no size cap beyond the
compiler's memory ceiling.

Every symbol carries the `analysis` behind its facts (see [Fact status](#fact-status-in-interface-and-navigation-output)).
When bodies were not checked, `mutation_writes` is `null`, and lexical-only candidates have `null` callable contracts.
`borrow` is an object such as `{"positions":[0,69]}`, sorted, with no 64-parameter limit.

```console
$ selka index-project examples/modules/main.selka --full
{"version":"navigation-v1","checked":true,"reference_scope":"resolved concrete bodies and specializations; ...","snapshot_sha256":"65f6f8db...","snapshot":{...},"symbols":[...],"references":[...], ...}
$ selka context examples/modules/main.selka --symbol=shared.units::Distance.make
{"version":"agent-context-v1","status":"ok", ... {"name":"dependencies","records":[{"direction":"outgoing","edge":"call","id":"shared.units::Distance.raw", ...},{"direction":"incoming","edge":"call","id":"main::main","kind":"function","signature":"main() -> int", ...}]}, ...}
```

For one focused question, `selka context` returns a declaration's contract, callers, callees and reaching tests
([focused context](agent-context.md)); `selka tests-for` lists the tests alone ([below](#which-tests-reach-a-declaration)).

## Summary and filters for large projects

The complete document grows with every local and relationship, so `index-project` without a flag prints
`navigation-summary-v1`: the snapshot digest and compiler identity, totals, one row per loaded module (path, exported
count, declaration counts by kind), and the drill-down queries with your entry path filled in.

```console
$ selka index-project examples/modules/main.selka
{"version":"navigation-summary-v1","checked":true,"snapshot_sha256":"4b030dc6...","compiler":{...},"totals":{"modules":2,"symbols":11,"exported":4,"kinds":{"function":4,"type":2,"field":1,"parameter":3,"local":1}},"modules":[{"module":"shared.units","path":"shared/units.selka","exported":3,"kinds":{"function":3,"type":1,"parameter":3}},{"module":"main","path":"main.selka","exported":1,"kinds":{"function":1,"type":1,"field":1,"local":1}}],"queries":{...}}
```

A filter prints `navigation-selection-v1`: the same records, restricted to what the filters select, with the snapshot rows
of their modules (`snapshot_sha256` still pins the whole project). Every filter given must match. Each also accepts a
space instead of `=`:

| Filter | Selects |
| --- | --- |
| `--module=NAME` | the declarations of one module |
| `--symbol=NAME` | one declaration and the members it owns: a type's fields and cases, a function's parameters and locals |
| `--kind=KIND` | one kind: `function`, `type`, `constraint`, `field`, `case`, `parameter` or `local` |

References into or out of a selected symbol come with it, so `--symbol` answers "who calls this and what does it call".
`--symbol` accepts `module.name`, `module::name`, and a bare name only one declaration carries (see
[call-site spelling](#call-site-spelling)). A filter that names nothing prints `"status": "missing"` (or `"ambiguous"`
with `candidates`) and exits 2. An unknown `--kind`, or `--full` with a filter, is a usage error.

```console
$ selka index-project examples/modules/main.selka --symbol=shared.units.Distance.make
{"version":"navigation-selection-v1","status":"ok","checked":true, ... "selection":{"module":null,"symbol":"shared.units.Distance.make","kind":null,"resolved":"shared.units::Distance.make"}, ... "symbols":[{"id":"shared.units::Distance.make", ...},{"id":"shared.units::Distance.make/local:value@147", ...}], ...}
```

`--full` prints the complete `navigation-v1` document.

## Call-site spelling

Code names a declaration in another module as `module.name`; the index spells it `module::name`. `selka context --symbol`,
`selka tests-for` and `selka index-project --symbol` accept both. A dotted spelling is tried at every split into a
module path and a member path, so `shared.units.Distance.make` is `shared.units::Distance.make`. A spelling that matches
several declarations is reported with the candidates, never silently resolved.

```console
$ selka tests-for examples/modules/main.selka shared.units.Distance.make
tests-for shared.units::Distance.make
  direct (0):
  reached-by (0):
```

## Reading an interface

`selka list-interfaces` is the declaration-only view of a project: it resolves names but does not require bodies to
type-check. Each exported callable prints its signature, capability parameters, mutation and return-origin contracts, an
`analysis(STATUS)` clause, and the number of tests that reach it. A body that fails to check leaves the declaration
listed without checked body facts.

`analysis(declaration-only)` means bodies were not checked; `analysis(template)` means a generic declaration was not
instantiated. When the test index is unavailable, the callable prints `tests(unavailable)`. A standard-library function
the compiler supplies (`builtin func`) is listed `export builtin function`, with no body behind it.

```console
$ selka list-interfaces main.selka
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module main
  export function double func(x:i64)->i64 analysis(checked) tests(0)
$ selka list-interfaces hole.selka
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module hole
  export function unfinished func(x:i64)->i64 analysis(declaration-only) tests(unavailable)
```

## Fact status in interface and navigation output

`selka list-interfaces` and `selka index-project` share one vocabulary of analysis status, so a text line and a JSON
field cannot disagree about whether a fact was checked: `checked`, `template`, `declaration-only`, `declared` and
`lexical-only` (the same words as `selka reference`).

| Surface | Unavailable facts | Status field |
| --- | --- | --- |
| `list-interfaces` text | `tests(unavailable)` | `analysis(STATUS)` on the callable line |
| `index-project` JSON | Declared `mutates`, `return_origin` and `borrow`; `mutation_writes` is null without checked bodies; lexical-only callable contracts are null | `"analysis": "STATUS"` on the symbol |
| `list-interfaces --contracts` | Declared mutation and return-origin contract remains in `permissions` | envelope `"analysis": "declaration-only"` when bodies were not checked |

Tell `null` (unavailable) from an empty declared mutation or return-source list. `permissions` records the declared
`mutates=...;origin=...` contract.

```console
$ selka index-project hole.selka --full
{"version":"navigation-v1","checked":false, "symbols":[{"name":"unfinished","analysis":"declaration-only","mutates":[],"return_origin":"fresh","borrow":{"positions":[]},"mutation_writes":null}], ...}
```

## Which tests reach a declaration

`selka tests-for <entry.selka> <qualified-name>` answers "what breaks if I change this?" by walking the call graph from
every test:

```console
$ selka tests-for src/app/main.selka app::parse
tests-for app::parse
  direct (1): app::test_parse
  reached-by (2): app::test_parse app::test_end_to_end
```

`direct` names the tests whose body calls the declaration itself; `reached-by` adds every test that reaches it only
through another call. Extend a `direct` test when one exists. An unknown qualified name exits 2; a declaration no test
reaches prints empty lists and exits 0. The name may be written as a call site writes it, `app.parse`.

The answer does not wait for the project to check. When a body does not type-check, `tests-for` prints the diagnostics
on stderr and still answers on stdout, from the parsed calls resolved by name. A closing `basis: syntax` line labels
that answer, since a name resolved without checked types is not a checked fact:

```console
$ selka tests-for src/app/main.selka app.parse
src/app/main.selka:12:20: error[E_TYPE]: expected int, found str
...
tests-for app::parse
  direct (1): app::test_parse
  reached-by (2): app::test_parse app::test_end_to_end
  basis: syntax (the project does not type-check; calls were resolved by name, not by checked types)
```

Only a project whose syntax does not parse gets no answer: `tests-for` says so and exits 1.

`selka lint` attaches the reachable tests to any finding that names a declaration, and `selka list-interfaces` prints the
count as a `tests(N)` column. `selka list-interfaces ENTRY.selka --cost` appends the entry's release per-function
[cost report](cost.md) after the public declarations; it needs checked bodies and an executable entry, and cannot be
combined with `--contracts`.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/navigation.md).
