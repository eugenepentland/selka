# Source navigation

`mylang index-project` answers "where is this defined and what uses it" from
checked compiler facts rather than from a text search. It runs the ordinary
project frontend, never executes guest code, and pins every answer to the exact
sources and compiler that produced it. The design record is
[bounded compiler navigation](../experiments/navigation-client.md).

## Source navigation

The command prints one `navigation-v1` JSON document: `symbols` for module-
qualified declarations and locals, each with its original source range,
signature, checked type name, the published effect ceiling, the declared `mut`
parameter positions, a `return_origin` bound (`fresh`, `params` or `unknown`), whether the
body performs any managed write (`mutation_writes`), and a bounded snippet; `references` for
resolved call, read, write, field and type edges; and `snapshot` for every loaded
module's path, byte length and SHA-256 alongside the compiler's own identity.
Those relationships are static, so they are not runtime coverage and not proof
that a change is safe. A project that fails body checking still produces a
partial index with `checked: false` and no checked edges, which is useful for
repairing source and is never a successful type-check verdict. Defaults cap
symbols and relationship rows at 20 each and combined snippets at 8 KiB, and
omitted counts are reported explicitly. `scripts/navigate.py` asks one focused
question over the same index — `definition`, `references`, `callers`, `callees`,
`impact` or `context` — and `tests/navigation_client.py --compiler BINARY`
exercises the whole surface.

Every symbol also carries the analysis behind its facts, so an unavailable
inference is never an empty fact: see [Fact status](#fact-status-in-interface-and-navigation-output).
A symbol whose bodies were checked keeps exactly the field set and values it
published before — for a private helper the inferred summary, and for an exported
function the ceiling its signature implies narrowed by any clause it wrote, which
E2 has always reported in `effects` with `return_origin` as the bound `unknown`. A symbol whose bodies were
not checked publishes `analysis` and `null` for those four fields instead, and a
consumer must read `null` as "not known here" rather than as "none".

```console
$ mylang index-project examples/modules/main.my > /tmp/index.json
$ python3 -c "import json; d=json.load(open('/tmp/index.json')); print(d['version'], d['checked'], len(d['symbols']), len(d['references']))"
navigation-v1 True 11 25
$ python3 scripts/navigate.py --compiler zig-out/bin/mylang --entry examples/modules/main.my \
    --symbol 'shared.units::Distance.make' --relation callers --limit 5
{"version": "navigation-query-v1", "checked": true, ... "references": [{"from": "main::main", "to": "shared.units::Distance.make", "kind": "call", "location": {"path": "main.my", "start": 263, "end": 287, "line": 10, "column": 19}}], ...}
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
$ mylang index-project hole.my > /tmp/index.json
$ python3 -c "import json; d=json.load(open('/tmp/index.json')); print(d['checked']); print([(s['name'], s.get('analysis'), s['effects']) for s in d['symbols'] if s['kind'] == 'function'])"
False
[('double', 'declaration-only', None), ('unfinished', 'declaration-only', None), ('main', 'declaration-only', None)]
$ mylang index-project main.my > /tmp/index.json
$ python3 -c "import json; d=json.load(open('/tmp/index.json')); print([(s['name'], s.get('analysis'), s['effects']) for s in d['symbols'] if s['name'] == 'parse'])"
[('parse', None, [])]
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
reaches prints empty lists and exits 0.

The same index backs two other surfaces: `mylang lint` attaches the reachable
tests to any finding that names a declaration, and `mylang list-interfaces`
prints the count as a `tests(N)` column.
