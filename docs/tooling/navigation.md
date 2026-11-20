# Source navigation

`selka index-project` answers "where is this defined and what uses it" from
checked compiler facts rather than from a text search. It runs the ordinary
project frontend, never executes guest code, and pins every answer to the exact
sources and compiler that produced it. The design record is
bounded compiler navigation (`docs/experiments/navigation-client.md`).

## Source navigation

By default the command prints a bounded `navigation-summary-v1` overview (see
[the summary and the filters](#summary-and-filters-for-large-projects)); with
`--full` it prints one `navigation-v1` JSON document: `symbols` for module-
qualified declarations and locals, each with its original source range,
signature, checked type name, the declared `mut`
parameter positions, a declared `return_origin` (`fresh` or `params`), its `borrow.positions` source list, whether the
body performs any managed write (`mutation_writes`), and a bounded snippet; `references` for
resolved call, read, write, field and type edges; and `snapshot` for every loaded
module's path, byte length and SHA-256 alongside the compiler's own identity.
Those relationships are static, so they are not runtime coverage and not proof
that a change is safe. A project that fails body checking still produces a
partial index with `checked: false` and no checked edges, which is useful for
repairing source and is never a successful type-check verdict. The index has
no size cap: it grows with the project and is bounded only by the compiler's
memory ceiling, like `check`. To ask one focused question instead of
reading the whole index, `selka context` returns one declaration's contract,
the types it names, its callers and callees and the tests that reach it
([focused context](agent-context.md)), and `selka tests-for` lists the reaching
tests alone ([below](#which-tests-reach-a-declaration)).

Every symbol also carries the analysis behind its facts, so an unavailable
inference is never an empty fact: see [Fact status](#fact-status-in-interface-and-navigation-output).
Parsed callable declarations publish their mutation and return-source contracts
whether or not their bodies were checked. `borrow` is an object such as
`{"positions":[0,69]}`; positions are sorted and have no 64-parameter limit.
When bodies were not checked, `analysis` identifies that status and
`mutation_writes` is `null`. Lexical-only candidates also have `null` callable
contracts because a signature was not parsed.

```console
$ selka index-project examples/modules/main.selka --full
{"version":"navigation-v1","checked":true,"reference_scope":"resolved concrete bodies and specializations; ...","snapshot_sha256":"65f6f8db...","snapshot":{...},"symbols":[...],"references":[...], ...}
$ selka context examples/modules/main.selka --symbol=shared.units::Distance.make
{"version":"agent-context-v1","status":"ok", ... {"name":"dependencies","records":[{"direction":"outgoing","edge":"call","id":"shared.units::Distance.raw", ...},{"direction":"incoming","edge":"call","id":"main::main","kind":"function","signature":"main() -> int", ...}]}, ...}
```

## Summary and filters for large projects

The complete document grows with every local and every relationship: 36 MB for
a generated 50,000-line project, 145 MB at 200,000 lines and 364 MB at 500,000.
So `index-project`
without a flag prints `navigation-summary-v1` instead — the snapshot digest and
compiler identity, totals, and one row per loaded module with its path, its
exported count and its declaration counts by kind — plus the queries that
drill down, with your entry path filled in. It skips the relationship walk,
and its size follows the module count: 15 KB at 50,000 lines, 58 KB at
200,000 and 144 KB at 500,000.

```console
$ selka index-project examples/modules/main.selka
{"version":"navigation-summary-v1","checked":true,"snapshot_sha256":"4b030dc6...","compiler":{...},"totals":{"modules":2,"symbols":11,"exported":4,"kinds":{"function":4,"type":2,"field":1,"parameter":3,"local":1}},"modules":[{"module":"shared.units","path":"shared/units.selka","exported":3,"kinds":{"function":3,"type":1,"parameter":3}},{"module":"main","path":"main.selka","exported":1,"kinds":{"function":1,"type":1,"field":1,"local":1}}],"queries":{...}}
```

A filter prints `navigation-selection-v1`: the same `navigation-v1` symbol and
reference records, restricted to what the filters select, with the snapshot rows
of the modules those records sit in (`snapshot_sha256` still pins the whole
project). Every filter given must match, and each is also accepted with a
space instead of `=`:

| Filter | Selects |
| --- | --- |
| `--module=NAME` | the declarations of one module |
| `--symbol=NAME` | one declaration and the members it owns: a type's fields and cases, a type's fields, a function's parameters and locals |
| `--kind=KIND` | one kind: `function`, `type`, `constraint`, `field`, `case`, `parameter` or `local` |

References into or out of a selected symbol come with it, so `--symbol` answers
"who calls this and what does it call" in one document. `--symbol` accepts the
spelling code writes at a call site, `module.name`, as well as `module::name` and
a bare name only one declaration carries (see
[call-site spelling](#call-site-spelling)). A filter that names nothing prints
the document with `"status": "missing"` (or `"ambiguous"` with `candidates`) and
exits 2; an unknown `--kind`, or `--full` together with a filter, is a usage
error.

```console
$ selka index-project examples/modules/main.selka --symbol=shared.units.Distance.make
{"version":"navigation-selection-v1","status":"ok","checked":true, ... "selection":{"module":null,"symbol":"shared.units.Distance.make","kind":null,"resolved":"shared.units::Distance.make"}, ... "symbols":[{"id":"shared.units::Distance.make", ...},{"id":"shared.units::Distance.make/local:value@147", ...}], ...}
```

`--full` is the complete `navigation-v1` document, byte for byte what the
command printed by default before; it is streamed rather than built in memory.
The repository's own `navigation-v1` consumers under `scripts/` and `tests/` pass it.

## Call-site spelling

Code names a declaration in another module as `module.name`; the index spells
its identity `module::name`. `selka context --symbol`, `selka tests-for` and
`selka index-project --symbol` accept both. A dotted spelling is tried at every
split into a module path and a member path, because both may contain dots:
`shared.units.Distance.make` is `shared.units::Distance.make`. One match is the
answer; a spelling that matches several declarations is reported with the
candidates and is never silently resolved.

```console
$ selka tests-for examples/modules/main.selka shared.units.Distance.make
tests-for shared.units::Distance.make
  direct (0):
  reached-by (0):
```

## Reading an interface

`selka list-interfaces` is the declaration-only view of a project: it parses
and resolves names but does not require bodies to type-check. Each exported
callable prints its whole signature, capability parameters, mutation and
return-origin contracts, an `analysis(STATUS)` clause, and the number of
discovered tests that reach it. A body that fails to check leaves the declaration
listed without publishing checked body facts.

`analysis(declaration-only)` means bodies were not checked; `analysis(template)`
means a generic declaration was not instantiated. When the test index is
unavailable, the callable prints `tests(unavailable)`. A standard-library
function the compiler supplies (`builtin func`) is listed `export builtin
function`, with no body behind it. Retired source effects and inferred effect
sets are not part of the listing.

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

`selka list-interfaces` and `selka index-project` publish the same vocabulary
of analysis status, so a text line and a JSON field cannot disagree about
whether a fact was checked. The words are defined in
the compiler-derived reference and shared with
`selka reference`: `checked`, `template`, `declaration-only`, `declared` and
`lexical-only`.

| Surface | Unavailable facts | Status field |
| --- | --- | --- |
| `list-interfaces` text | `tests(unavailable)` | `analysis(STATUS)` on the callable line |
| `index-project` JSON | Declared `mutates`, `return_origin` and `borrow`; `mutation_writes` is null without checked bodies; lexical-only callable contracts are null | `"analysis": "STATUS"` on the symbol |
| `list-interfaces --contracts` | Declared mutation and return-origin contract remains in `permissions` | envelope `"analysis": "declaration-only"` when bodies were not checked |

Consumers must distinguish `null` (unavailable) from an empty declared mutation
or return-source list. The compatibility field `permissions` records the declared
`mutates=...;origin=...` contract; it no longer carries an effect ceiling.

```console
$ selka index-project hole.selka --full
{"version":"navigation-v1","checked":false, "symbols":[{"name":"unfinished","analysis":"declaration-only","mutates":[],"return_origin":"fresh","borrow":{"positions":[]},"mutation_writes":null}], ...}
```

## Which tests reach a declaration

`selka tests-for <entry.selka> <qualified-name>` answers the maintainer question
"what breaks if I change this?" It loads and checks the project, then walks the
resolved call graph from every discovered test:

```console
$ selka tests-for src/app/main.selka app::parse
tests-for app::parse
  direct (1): app::test_parse
  reached-by (2): app::test_parse app::test_end_to_end
```

`direct` names the tests whose body calls the declaration itself; `reached-by`
adds every test that reaches it only through another call. The distinction is
what makes the answer actionable: a test that reaches `parse` only through
`main` proves little about `parse`, so extend a `direct` test when one exists.
An unknown qualified name prints a message and exits 2; a declaration no test
reaches prints empty lists and exits 0. The name may be written as a call site
writes it, `app.parse` (see [call-site spelling](#call-site-spelling)).

The answer does not wait for the project to check. When a body does not
type-check — the usual state in the middle of a change — `tests-for` prints the
diagnostics on stderr and still answers on stdout, from a call graph read from
the parsed calls: each call resolves by name through the calling module's own
declarations and its import aliases, the same namespaces the checker uses. A
closing `basis: syntax` line labels that answer, because a name resolved
without checked types is not a checked fact:

```console
$ selka tests-for src/app/main.selka app.parse
src/app/main.selka:12:20: error[E_TYPE]: expected int, found str
...
tests-for app::parse
  direct (1): app::test_parse
  reached-by (2): app::test_parse app::test_end_to_end
  basis: syntax (the project does not type-check; calls were resolved by name, not by checked types)
```

Only a project whose syntax does not parse gets no answer: `tests-for` says so
and exits 1.

The same index backs two other surfaces: `selka lint` attaches the reachable
tests to any finding that names a declaration, and `selka list-interfaces`
prints the count as a `tests(N)` column.

`selka list-interfaces ENTRY.selka --cost` appends the entry's release per-function
[cost report](cost.md) after the public declarations. The cost analysis requires
checked bodies and an executable entry. `--cost` and the JSON `--contracts`
manifest are mutually exclusive.
