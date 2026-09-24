# Modules, imports and exports

A program larger than one file is a project: a set of modules, each a single
source file, joined by `import` declarations and connected to the entry point the
command line names. There is no package manifest in the language itself and no
ambient namespace — a module sees exactly what it declares and what its imports
bring in.

## Running a file that imports

`mylang run` detects a project entry itself. When the file the command names
opens with a `module` header — or a module-only `import`/`export` directive — it
loads the reachable graph exactly as a project command does, so a single file
that imports a standard module needs no separate command:

```mylang
# doc: expect 42
module main
import math

def main() -> int:
    return math.clamp(99, 0, 42)
```

`mylang run main.my --print-result` prints `42`; `mylang run-project main.my`
remains the explicit alias for the same entry. A file with no module header is
still checked and run as one standalone unit; see
[headerless scripts](#headerless-scripts) for the one import it may carry.

### Headerless scripts

A file with no `module` header is one standalone unit, and it may import the
compiler-embedded standard modules directly. The first line is the import; there
is no module name to declare because nothing imports the file back:

```mylang
# doc: expect 42
import math

def main() -> int:
    return math.clamp(99, 0, 42)
```

Save it as `probe4.my` and `mylang run probe4.my --print-result` prints `42`.
The imports resolve from the embedded standard library exactly as they do for a
project entry — the same ten modules, the same exports — and the rest of the file
is an ordinary program body. Anything other than standard-module imports still
needs the header, because a project module has to declare the name its importers
request:

```mylang
# doc: expect-error E_MODULE_HEADER
import helper

def main() -> int:
    return 0
```

That rejection is reported at the file's first token and names the accepted
form: begin the file with `module NAME` when it imports a module of its own.
A file that begins with a declaration, with an `export` directive or with a
dotted import path is rejected the same way, and a headerless file that another
module imports is rejected too — only the entry the command names may be
headerless.

This is the canonical everyday command shape:

```console
$ mylang run main.my
$ mylang run main.my --restrict --allow-read=.
```

`run` and `run-project` share stdout, stderr, capability and exit-status
semantics. Both compile to a temporary native executable. A completed `main`
returning `int` exits with that value (truncated to eight bits), `--print-result`
also prints it, diagnostics go to stderr, and a trap outranks the return value.
Every capability is granted by default; `--restrict` denies capabilities except
those named by `--allow-*` options.

The related native routes use the same runtime contract with command-specific
front ends. `mylang build main.my --run -- <guest-arguments>` executes a temporary
binary, while `mylang build main.my -o app` creates an executable that reads the
same runtime options from the `MYLANG_OPTIONS` environment variable. `build --run` auto-detects a module entry exactly
like `run`; a persistent `build main.my -o app` still requires `--project` for a
module project. `mylang test main.my` builds each guest test as a separate native
child with no ambient capabilities and returns an aggregate runner status.

A `main(args: list[str], ...)` entry point receives only guest arguments: values
after `--` for `mylang run` and `build --run`, and every OS argument after
`argv[0]`, unchanged, for an installed executable. Runtime controls stay before
the delimiter for a command and in `MYLANG_OPTIONS` for an installed program. Values are validated
UTF-8; invalid platform bytes fail at the host boundary before guest execution.

Under `--restrict`, all launch paths report the first missing entry capability
with the same stderr line and exit 2 before guest execution. The generated entry
stops after the first failed grant instead of reporting every missing capability.

## Disk modules

A file opens with `module NAME`, then its `import` declarations, then its
top-level declarations. An import resolves to a source file under the project
root by turning the dotted name into a path: `import units` reads `units.my`, and
`import shared.units` reads `shared/units.my`. `mylang run` and
`mylang check-project` take the entry file and load the reachable graph once, in
dependency order; `mylang run-project` is the explicit project-entry alias.
Nothing is exported implicitly: a declaration is visible to importers only when
it carries the `public` modifier, and an exported signature that mentions a
private type rejects rather than leaking it. The bare `export NAME` directive is
gone. Exported functions do not need to spell an effect ceiling: the checker
freezes each body's inferred effect set as the published interface contract, and
an explicit `noalloc`, `noio` or `effects(...)` is an opt-in narrowing enforced
as an upper bound.

```mylang
# doc: project measure
# doc: file units.my
module units

public record Distance:
    value: int

public def make(value: int) -> Distance effects():
    return Distance(value=value)

public def metres(distance: Distance) -> int effects():
    return distance.value
```

```mylang
# doc: project measure
# doc: file main.my
# doc: expect 42
module main
import units

def main() -> int:
    return units.metres(units.make(42))
```

## Dotted qualification

An import is qualified by its full dotted module name or by its local alias — the
name after `as`, or the trailing segment of the dotted name when there is none.
So `import prices` answers `prices.total`, `import catalog.prices` answers both
`catalog.prices.total` and `prices.total`, and `import catalog.prices as p`
answers both `p.total` and `catalog.prices.total`. A dotted path is joined only
while it continues a registered module path, so a bare prefix that does not
continue one (`catalog` on its own) is an ordinary name a local or parameter may
reuse. The same spelling covers functions, types and domain methods, so
`prices.Price` is a type annotation and a constructor, and `prices.total` is a
call or a function value. Qualification does not relax privacy: a name the other
module did not export is still unreachable, and binding the same alias twice
rejects with `E_IMPORT_ALIAS`.

```mylang
# doc: project catalog
# doc: file prices.my
module prices

public record Price:
    cents: int

public def total(first: Price, second: Price) -> Price effects():
    return Price(cents=first.cents + second.cents)
```

```mylang
# doc: project catalog
# doc: file main.my
# doc: expect 42
module main
import prices

def main() -> int:
    sum: prices.Price = prices.total(prices.Price(cents=40), prices.Price(cents=2))
    return sum.cents
```

## Export placement

A declaration is published by writing `public` in front of it: `public def
name(...)`, `public record Name`, `public enum Name`, `public type Name`, and so
on. The modifier names no other declaration, so a file keeps its public surface
where each declaration is written and a rename can never leave a stale directive
behind.

The bare `export NAME` directive was removed: it now rejects with
`E_EXPORT_REMOVED`, which points at the declaration spelling to use instead. The
only remaining export directive is the dotted re-export `export module.Name`,
which publishes an imported declaration (see below); it may appear anywhere among
the top-level declarations after the module header and its imports, and a
duplicate or unknown re-export still reports at the directive that caused it.

```mylang
# doc: project report
# doc: file totals.my
module totals

public def base() -> int effects():
    return 40


public def bonus() -> int effects():
    return 2
```

```mylang
# doc: project report
# doc: file main.my
# doc: expect 42
module main
import totals

def main() -> int:
    return totals.base() + totals.bonus()
```

## Re-exports

A directive may also publish an imported declaration: `export units.Distance`
names the import qualifier and the declaration inside it, and the facade module
publishes that declaration under the final name. Importers then name it exactly
as if the facade had declared it, which lets one module be the public surface of
a package whose real declarations live in a submodule. The target must already
be exported by the module that declares it, and a qualifier that is not imported
rejects with the located `E_UNKNOWN_EXPORT`.

The facade adds only a public name. A reference through it resolves to the
declaring module's identity, so the declaration keeps one implementation, one
contract and one schema entry, and the project fingerprint reports the facade
name.

```mylang
# doc: project published
# doc: file units.my
module units

public record Distance:
    value: int

public def make(value: int) -> Distance effects():
    return Distance(value=value)

public def metres(distance: Distance) -> int effects():
    return distance.value
```

```mylang
# doc: project published
# doc: file facade.my
module facade
import units
export units.Distance
export units.make
export units.metres
```

```mylang
# doc: project published
# doc: file main.my
# doc: expect 42
module main
import facade

def main() -> int:
    distance: facade.Distance = facade.make(42)
    return facade.metres(distance)
```

## Limits

- By default a project loads at most 16,384 modules and 262,144 import edges,
  with each file capped at 4 MiB and the whole project at 64 MiB of source —
  room for well over a million lines with no configuration. A `mylang.json`
  `budgets` object (`max_modules`, `max_imports`, `max_file_bytes`,
  `max_total_bytes`) raises or lowers each, and `mylang test` bounds its source
  snapshot by the same `max_total_bytes`.
- Import cycles reject, reporting both the importing location and the related
  source location. Importing the same module twice in one file rejects with
  `E_DUPLICATE_IMPORT`.
- Standard-library names are reserved and load from embedded source rather than
  from the project root; see [the standard library](standard-library.md).
- A single-file program needs no `module` header at all, and it may import the
  embedded standard modules directly. Only an import of a project module needs
  the header: it is the project commands, not the language, that turn a file
  into a graph.
