# Source navigation

`mylang index-project` answers "where is this defined and what uses it" from
checked compiler facts rather than from a text search. It runs the ordinary
project frontend, never executes guest code, and pins every answer to the exact
sources and compiler that produced it. The design record is
[bounded compiler navigation](../experiments/navigation-client.md).

## Source navigation

The command prints one `navigation-v1` JSON document: `symbols` for module-
qualified declarations and locals, each with its original source range,
signature, checked type name, named effects, the normalized `mutates` input
positions, a `return_origin` bound (`fresh`, `params` or `unknown`), whether the
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
spelling, the inferred `effects(...)` set when the bodies check, any
`mutates(...)` parameters by name, and a declared ceiling when the source wrote
one. A body that fails to check leaves the declaration listed and reports no
body diagnostic.

```console
$ mylang list-interfaces program.my
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module main
  export function main def(fs:Filesystem,clock:Clock)->i64 effects()
```
