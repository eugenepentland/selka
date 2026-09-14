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
still checked and run as one standalone unit, unchanged.

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
front ends. `mylang build main.my --run -- <runtime-options>` executes a temporary
binary, while `mylang build main.my -o app` creates an executable that accepts the
same runtime options directly. Today `build` requires `--project` for a module
entry even though `run` auto-detects it. `mylang test main.my` builds each guest
test as a separate native child with no ambient capabilities and returns an
aggregate runner status. Wave 1 has no guest `argv` parameter: these arguments
configure execution and are not application data.

One observable gap remains in this baseline: under `--restrict`, `run` reports a
missing entry capability with a command-line preflight diagnostic, while
`build --run` and an installed executable report `CapabilityUnavailable: QBE
runtime failure`. All three exit 2 and deny execution, but their stderr text is
not yet identical.

## Disk modules

A file opens with `module NAME`, then its `import` declarations, then its
top-level declarations. An import resolves to a source file under the project
root by turning the dotted name into a path: `import units` reads `units.my`, and
`import shared.units` reads `shared/units.my`. `mylang run` and
`mylang check-project` take the entry file and load the reachable graph once, in
dependency order; `mylang run-project` is the explicit project-entry alias.
Nothing is exported implicitly: a declaration is visible to importers only when
an `export` directive names it, and an exported signature that mentions a
private type rejects rather than leaking it.

```mylang
# doc: project measure
# doc: file units.my
module units
export Distance
export make
export metres

class Distance:
    value: int

def make(value: int) -> Distance:
    return Distance(value=value)

def metres(distance: Distance) -> int:
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

An import binds one alias — the last segment of the dotted name, or the name
after `as` — and every use of that module's exports is written `alias.name`. The
same spelling covers functions, types and domain methods, so `prices.Price` is a
type annotation and a constructor, and `prices.total` is a call or a function
value. Qualification does not relax privacy: a name the other module did not
export is still unreachable, and binding the same alias twice rejects with
`E_IMPORT_ALIAS`.

```mylang
# doc: project catalog
# doc: file prices.my
module prices
export Price
export total

class Price:
    cents: int

def total(first: Price, second: Price) -> Price:
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

`export NAME` may appear anywhere among the top-level declarations, after the
module header and its imports. It may precede the declaration it names, follow
it, or sit in a group of directives away from all of them, which lets a file
either keep its public surface together at the top or annotate each declaration
where it is written. Directives are collected in source order and keep their own
locations, so a duplicate or unknown export still reports at the directive that
caused it. An `export` inside a function or type body rejects.

```mylang
# doc: project report
# doc: file totals.my
module totals

def base() -> int:
    return 40

export base
export bonus

def bonus() -> int:
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

## Limits

- A project loads at most 256 modules and 4,096 import edges, with each file
  capped at 4 MiB and the whole project at 16 MiB of source.
- Import cycles reject, reporting both the importing location and the related
  source location. Importing the same module twice in one file rejects with
  `E_DUPLICATE_IMPORT`.
- Standard-library names are reserved and load from embedded source rather than
  from the project root; see [the standard library](standard-library.md).
- A single-file program needs no `module` header at all. It is the project
  commands, not the language, that turn a file into a graph.
