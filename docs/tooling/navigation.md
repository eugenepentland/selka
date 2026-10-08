# Source navigation

`mylang index-project` answers "where is this defined and what uses it" from
checked compiler facts rather than from a text search. It runs the ordinary
project frontend, never executes guest code, and pins every answer to the exact
sources and compiler that produced it. The design record is
[bounded compiler navigation](../experiments/navigation-client.md).

## Source navigation

By default the command prints a bounded `navigation-summary-v1` overview (see
[the summary and the filters](#summary-and-filters-for-large-projects)); with
`--full` it prints one `navigation-v1` JSON document: `symbols` for module-
qualified declarations and locals, each with its original source range,
signature, checked type name, the published effect ceiling, the declared `mut`
parameter positions, a `return_origin` bound (`fresh`, `params` or `unknown`), whether the
body performs any managed write (`mutation_writes`), and a bounded snippet; `references` for
resolved call, read, write, field and type edges; and `snapshot` for every loaded
module's path, byte length and SHA-256 alongside the compiler's own identity.
Those relationships are static, so they are not runtime coverage and not proof
that a change is safe. A project that fails body checking still produces a
partial index with `checked: false` and no checked edges, which is useful for
repairing source and is never a successful type-check verdict. The index has
no size cap: it grows with the project and is bounded only by the compiler's
memory ceiling, like `check`. To ask one focused question instead of
reading the whole index, `mylang context` returns one declaration's contract,
the types it names, its callers and callees and the tests that reach it
([focused context](agent-context.md)), and `mylang tests-for` lists the reaching
tests alone ([below](#which-tests-reach-a-declaration)).

Every symbol also carries the analysis behind its facts, so an unavailable
inference is never an empty fact: see [Fact status](#fact-status-in-interface-and-navigation-output).
A symbol whose bodies were checked keeps exactly the field set and values it
published before — for a private helper the inferred summary, and for an exported
function the ceiling its signature implies narrowed by any clause it wrote, which
E2 has always reported in `effects` with `return_origin` as the bound `unknown`. A symbol whose bodies were
not checked publishes `analysis` and `null` for those four fields instead, and a
consumer must read `null` as "not known here" rather than as "none".

```console
$ mylang index-project examples/modules/main.my --full
{"version":"navigation-v1","checked":true,"reference_scope":"resolved concrete bodies and specializations; ...","snapshot_sha256":"65f6f8db...","snapshot":{...},"symbols":[...],"references":[...], ...}
$ mylang context examples/modules/main.my --symbol=shared.units::Distance.make
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
$ mylang index-project examples/modules/main.my
{"version":"navigation-summary-v1","checked":true,"snapshot_sha256":"4b030dc6...","compiler":{...},"totals":{"modules":2,"symbols":11,"exported":4,"kinds":{"function":4,"type":2,"field":1,"parameter":3,"local":1}},"modules":[{"module":"shared.units","path":"shared/units.my","exported":3,"kinds":{"function":3,"type":1,"parameter":3}},{"module":"main","path":"main.my","exported":1,"kinds":{"function":1,"type":1,"field":1,"local":1}}],"queries":{...}}
```

A filter prints `navigation-selection-v1`: the same `navigation-v1` symbol and
reference records, restricted to what the filters select, with the snapshot rows
of the modules those records sit in (`snapshot_sha256` still pins the whole
project). Every filter given must match, and each is also accepted with a
space instead of `=`:

| Filter | Selects |
| --- | --- |
| `--module=NAME` | the declarations of one module |
| `--symbol=NAME` | one declaration and the members it owns: a type's fields and cases, a domain's functions, a function's parameters and locals |
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
$ mylang index-project examples/modules/main.my --symbol=shared.units.Distance.make
{"version":"navigation-selection-v1","status":"ok","checked":true, ... "selection":{"module":null,"symbol":"shared.units.Distance.make","kind":null,"resolved":"shared.units::Distance.make"}, ... "symbols":[{"id":"shared.units::Distance.make", ...},{"id":"shared.units::Distance.make/local:value@147", ...}], ...}
```

`--full` is the complete `navigation-v1` document, byte for byte what the
command printed by default before; it is streamed rather than built in memory.
The repository's own `navigation-v1` consumers under `scripts/` and `tests/` pass it.

## Call-site spelling

Code names a declaration in another module as `module.name`; the index spells
its identity `module::name`. `mylang context --symbol`, `mylang tests-for` and
`mylang index-project --symbol` accept both. A dotted spelling is tried at every
split into a module path and a member path, because both may contain dots:
`shared.units.Distance.make` is `shared.units::Distance.make`. One match is the
answer; a spelling that matches several declarations is reported with the
candidates and is never silently resolved.

```console
$ mylang tests-for examples/modules/main.my shared.units.Distance.make
tests-for shared.units::Distance.make
  direct (0):
  reached-by (0):
```

## Reading an interface

`mylang list-interfaces` is the declaration-only view of a project: it parses
and resolves names but does not require bodies to type-check. Each exported
callable prints its whole signature, with capability parameters in their Python
spelling, the inferred `effects(...)` set when the bodies check, its `mut`
parameters by name, the `ceiling(...)` its signature implies (narrowed by a
clause when the source wrote one), and a `tests(N)` column: the number of discovered tests that reach the
callable, directly or transitively, from the same index `tests-for` reads. A
body that fails to check leaves the declaration listed and reports no body
diagnostic.

An inferred summary exists only when checking produced one. When it did not, the
line prints the literal `effects(unavailable)` with an `analysis(STATUS)` clause
instead of the conservative full mask, so a bound the checker keeps internally is
never published as a fact, and the `ceiling(...)` — including an explicitly empty
`ceiling()` — stays visible either way, because it follows from the parameters
alone. `analysis(declaration-only)` means the
bodies were not checked; `analysis(template)` means the project checked but no
call instantiated this generic declaration; the `tests` column becomes
`tests(unavailable)` for the whole-listing case. A declaration with a checked
summary prints exactly what it always printed.

```console
$ mylang list-interfaces main.my
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module main
  export function double def(x:i64)->i64 effects() ceiling(managed_allocation) tests(0)
  export function parse def(value:i64)->i64 effects() tests(1)
$ mylang list-interfaces hole.my
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module hole
  export function double def(x:i64)->i64 effects(unavailable) analysis(declaration-only) ceiling(managed_allocation) tests(unavailable)
  export function unfinished def(x:i64)->i64 effects(unavailable) analysis(declaration-only) tests(unavailable)
```

## Fact status in interface and navigation output

`mylang list-interfaces` and `mylang index-project` publish the same vocabulary
of analysis status, so a text line and a JSON field cannot disagree about
whether a fact was checked. The words are defined in
[the compiler-derived reference](../reference.md#fact-status) and shared with
`mylang reference`: `checked`, `template`, `declaration-only`, `declared` and
`lexical-only`.

| Surface | Unavailable inference | Status field |
| --- | --- | --- |
| `list-interfaces` text | `effects(unavailable)`, `tests(unavailable)` | `analysis(STATUS)` clause on the callable line |
| `index-project` JSON | `null` for `effects`, `mutates`, `return_origin`, `mutation_writes` | `"analysis": "STATUS"` on the symbol |
| `list-interfaces --contracts` | `permissions` keeps the declared directional bound (an omitted ceiling promises the full mask) | envelope `"analysis": "declaration-only"`; omitted when a checked program supplied inferred effects |

A checked symbol or line keeps its previous bytes exactly, so a consumer that
only ever saw checked answers reads the same values; a consumer that may see an
unchecked one must distinguish `null` (unknown) from `[]` (inferred: none) and
from an absent `analysis` key (checked). The `interface-contracts-v2` manifest is
the declared replacement contract rather than an inferred summary, which is why
its per-declaration `permissions` value stays the directional bound its frozen
set-subset consumer compares.

```console
$ mylang index-project hole.my
{"version":"navigation-v1","checked":false, ... "symbols":[{"id":"hole::double","name":"double","kind":"function", ... "analysis":"declaration-only","effects":null,"mutates":null,"return_origin":null,"mutation_writes":null, ...}, ...
$ mylang index-project main.my
{"version":"navigation-v1","checked":true, ... {"id":"main::parse","name":"parse","kind":"function", ... "signature":"parse(value: int) -> int","type_name":"i64","effects":["managed_allocation"],"mutates":[],"return_origin":"fresh","mutation_writes":false, ...}, ...
```

## Which tests reach a declaration

`mylang tests-for <entry.my> <qualified-name>` answers the maintainer question
"what breaks if I change this?" It loads and checks the project, then walks the
resolved call graph from every discovered test:

```console
$ mylang tests-for src/app/main.my app::parse
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
$ mylang tests-for src/app/main.my app.parse
src/app/main.my:12:20: error[E_TYPE]: expected int, found str
...
tests-for app::parse
  direct (1): app::test_parse
  reached-by (2): app::test_parse app::test_end_to_end
  basis: syntax (the project does not type-check; calls were resolved by name, not by checked types)
```

Only a project whose syntax does not parse gets no answer: `tests-for` says so
and exits 1.

The same index backs two other surfaces: `mylang lint` attaches the reachable
tests to any finding that names a declaration, and `mylang list-interfaces`
prints the count as a `tests(N)` column.

`mylang list-interfaces ENTRY.my --cost` appends the entry's release per-function
[cost report](cost.md) after the public declarations. The cost analysis requires
checked bodies and an executable entry. `--cost` and the JSON `--contracts`
manifest are mutually exclusive.
