# Modules, imports and exports

A program larger than one file is a project: a set of modules, each a single
source file, joined by `import` declarations and connected to the entry point the
command line names. There is no package manifest in the language itself (a library
shared between applications is a local package: `selka docs packages`) and no
ambient namespace — a module sees exactly what it declares and what its imports
bring in.

## Running a file that imports

`selka run` loads the reachable graph when a file imports modules. Module
identity comes from the file path: `helper.selka` is imported as `helper`, and no
source file declares a `module` header. Standard modules are embedded in the
compiler and use the same import syntax:

```selka
# doc: expect 42
import math

func main() -> int:
    return math.clamp(99, 0, 42)
```

`selka run main.selka --print-result` prints `42`; `selka run-project main.selka`
remains the explicit project command. A file without imports can still be
checked and run as one standalone unit.

A file that imports is the entry of a graph and is named like a module: letters,
digits and `_`, not starting with a digit. `selka check my-prog.selka` with an
`import` in it prints `error[E_ENTRY_NAME]: rename `my-prog.selka` to `my_prog.selka`:
a file that imports must be named like a module`; the same file with no import
checks as it stands.

### Headerless scripts

All source files are headerless, including imported modules. A project import
resolves to a matching file under the project root. A missing file produces a
located module-read diagnostic:

```selka
# doc: expect-error E_MODULE_READ
import helper

func main() -> int:
    return 0
```

Exported declarations use `public`; imported private declarations remain
inaccessible. Generated `.api` metadata retains its module identity header.

This is the canonical everyday command shape:

```console
$ selka run main.selka
$ selka run main.selka --restrict --allow-read=.
```

`run` and `run-project` share stdout, stderr, capability and exit-status
semantics. Both compile to a temporary native executable. A completed `main`
returning `int` exits with that value (truncated to eight bits), `--print-result`
also prints it, diagnostics go to stderr, and a trap outranks the return value.
Every capability is granted by default; `--restrict` denies capabilities except
those named by `--allow-*` options.

The related native routes use the same runtime contract with command-specific
front ends. `selka build main.selka --run -- <guest-arguments>` executes a temporary
binary, while `selka build main.selka -o app` creates an executable that reads the
same runtime options from the `SELKA_OPTIONS` environment variable. `build --run` auto-detects a module entry exactly
like `run`; a persistent `build main.selka -o app` still requires `--project` for a
module project. `selka test main.selka` builds each guest test as a separate native
child with no ambient capabilities and returns an aggregate runner status.

A `main(args: str[], ...)` entry point receives only guest arguments: values
after `--` for `selka run` and `build --run`, and every OS argument after
`argv[0]`, unchanged, for an installed executable. Runtime controls stay before
the delimiter for a command and in `SELKA_OPTIONS` for an installed program. Values are validated
UTF-8; invalid platform bytes fail at the host boundary before guest execution.

Under `--restrict`, all launch paths report the first missing entry capability
with the same stderr line and exit 2 before guest execution. The generated entry
stops after the first failed grant instead of reporting every missing capability.

## Disk modules

Every source file is headerless: it begins with its `import` declarations, then
its top-level declarations. An import resolves to a source file under the project
root by turning the dotted name into a path: `import units` reads `units.selka`, and
`import shared.units` reads `shared/units.selka`. `selka run` and
`selka check-project` take the entry file and load the reachable graph once, in
dependency order; `selka run-project` is the explicit project-entry alias.
Nothing is exported implicitly: a declaration is visible to importers only when
it carries the `public` modifier, and an exported signature that mentions a
private type rejects rather than leaking it. The bare `export NAME` directive is
gone. Exported functions publish their declared signatures, mutation footprints
and return-origin contracts. Capability arguments are explicit; source `noalloc`,
`noio` and `effects(...)` clauses are retired with `E_EFFECTS_REMOVED`.

```selka
# doc: project measure
# doc: file units.selka

public record Distance:
    value: int

public func make(value: int) -> Distance:
    return Distance(value=value)

public func metres(distance: Distance) -> int:
    return distance.value
```

```selka
# doc: project measure
# doc: file main.selka
# doc: expect 42
import units

func main() -> int:
    return units.metres(units.make(42))
```

### The project root and `selka.json`

The project root, where `import units` looks for `units.selka`, is the directory of the nearest
`selka.json`: the search starts at the entry file's directory and goes up, and the first file
found wins. With no `selka.json` the root is the entry file's own directory, so a module that
lives in a parent directory is `E_MODULE_READ` (`there is no units.selka under the import root app
(no selka.json sets it)`). A file under a hidden folder of the project (`.tmp/scratch.selka`, the place for a scratch
program) belongs to the project too: its imports start at the same root, and `selka check DIR` and `selka test DIR`
still leave the hidden folder out. Nothing imports a file of a hidden folder: the compiler names such an entry
`__hidden_tmp.scratch` inside, a test report shows it as `.tmp.scratch_test::test_x`, and a source that writes a module
name with a segment beginning `__hidden_` is `E_INTERNAL_NAME` (`hidden folders cannot be imported`); move the module out
of the hidden folder to import it. The smallest file that makes a directory the root is:

```json
{"version": 1}
```

`{}` is `E_PROJECT_CONFIG` (`selka.json must carry version: 1`), and so is a key that is not in
this list. Every key but `version` is optional:

| Key | What it holds | Guide |
|---|---|---|
| `version` | `1`; `2` is needed for `lint` and `release` | this page |
| `budgets` | `max_modules`, `max_imports`, `max_file_bytes`, `max_total_bytes` | [Limits](#limits) below |
| `limits` | `run` and `test` defaults for `max_steps`, `max_frames`, `max_memory` | [runtime budgets](tooling/runtime-budgets.md#project-defaults-in-selkajson) |
| `import_policy` | a policy file whose import-direction rules every command enforces | [import policy](tooling/import-policy.md) |
| `interface_files` | `true` makes each module's `.api` file part of the check | [interface files](tooling/interface-files.md#enforcing-current-files-with-selkajson) (`selka docs api`) |
| `links` | C source files that `build`, `run` and `test` link | [project links](c-ffi.md#project-links) |
| `allow_links` | packages whose own C sources the build may use | [packages](tooling/packages.md#c-sources-in-a-package) |
| `stores` | where the caches and the temporary folder live | [the caches](tooling/native-build.md#the-caches) |
| `lint` | the lint profile and rule settings (version 2) | [lint](tooling/lint.md) |
| `release` | the entries and excluded paths of the checked project docs (version 2) | [release docs](tooling/release-docs.md#configure-entries-and-paths) |
| `value_semantics` | only `true`, the default, is accepted | [value semantics](value-semantics.md) |

## Dotted qualification

An import is qualified by its full dotted module name or by its local alias — the
name after `as`, or the trailing segment of the dotted name when there is none.
So `import prices` answers `prices.total`, `import catalog.prices` answers both
`catalog.prices.total` and `prices.total`, and `import catalog.prices as p`
answers both `p.total` and `catalog.prices.total`. A dotted path is joined only
while it continues a registered module path, so a bare prefix that does not
continue one (`catalog` on its own) is an ordinary name a local or parameter may
reuse. The same spelling covers functions and types, so
`prices.Price` is a type annotation and a constructor, and `prices.total` is a
call or a function value. Qualification does not relax privacy: a name the other
module did not export is still unreachable, and binding the same alias twice
rejects with `E_IMPORT_ALIAS`.

```selka
# doc: project catalog
# doc: file prices.selka

public record Price:
    cents: int

public func total(first: Price, second: Price) -> Price:
    return Price(cents=first.cents + second.cents)
```

```selka
# doc: project catalog
# doc: file main.selka
# doc: expect 42
import prices

func main() -> int:
    mut sum: prices.Price = prices.total(prices.Price(cents=40), prices.Price(cents=2))
    return sum.cents
```

### A module used without its import

A file reaches another file of the project only through its `import`. When a file writes `util.twice(2)`, `util.Row` or
`shared.calc.f(x)` and `util` is no name in scope, no import binds it and no local holds it, and the import root holds a
module file of that name (`util.selka`, `shared/calc.selka`), the refusal is `E_MODULE_NOT_IMPORTED`, worded as for a standard
module: `` `util` is a module of this project that this file does not import; add `import util` ``. `selka fix` writes
the line in the file's sorted directive block, and the file then checks. A qualifier written by its last segment alone
(`calc.f(x)`) gets the same answer when exactly one file `calc.selka` lies in a directory below the root: `` `calc` is the module
`shared.calc` of this project, which this file does not import; add `import shared.calc` ``. With two such files the
refusal keeps its own message, since a guess between them is no repair, and so does a qualifier that is no module file.

### An enum case written without its enum

A case of an enum is written with its enum: `argparse.Error.MissingValue(name="db")`, not `argparse.MissingValue(name="db")`
and not `MissingValue(name="db")`. The refusal is `E_UNKNOWN_SYMBOL`. When exactly one enum in reach has a case of that name (the
exported enums of the module the call names, or for a bare name the file's own enums and those of the modules it imports) it
says ``did you mean `argparse.Error.MissingValue`?`` and `selka fix` writes the call with its enum. A case that two enums have
keeps the plain message, since a guess between them is no repair.

### A bare name that an imported module declares

An import binds the module's name, not its declarations: after `import bitio`, a function, type or constant of `bitio` is written
`bitio.new_bitout()`, `bitio.BitOut`, `bitio.LIMIT`. The bare `new_bitout()` is refused as `E_UNKNOWN_SYMBOL` ("this module
declares no `new_bitout`"), and when exactly one module the file imports declares that name publicly, as the kind the position needs, the
message goes on ``the imported module `bitio` declares it: write `bitio.new_bitout` `` and `selka fix` writes the qualifier (the import's
alias when it has one). When two or three imported modules declare it the message names them all and `selka fix` leaves the choice to
you. A private declaration and a module the file does not import are not offered.

### A local named like a path root

A bare prefix of an import's dotted path is not a name the import binds, so a local or parameter may take it even
when the path continues past it: with `import eval.deprecations`, a function that has its own `eval` (a parameter,
a `const` or `mut`, a `for` variable, a `with ... as` name or a `match` payload) reads `eval.deprecations.items` as
the field `deprecations` of that local and its field `items`, and calls `eval.deprecations.note(...)` on the
field. This is the ordinary rule that the innermost binding of a name is the one in force. Where no such local
is in force, including after the block that declared it has ended, the same spelling is the module path. An
alias is different: a local cannot take the name of an import alias (`E_SHADOWING`), and `eval_deprecations.total`
always names the module.

```selka
# doc: project walker
# doc: file eval/deprecations.selka

public record Log:
    items: int[]

public const LIMIT: int = 7
```

```selka
# doc: project walker
# doc: file main.selka
# doc: expect 12
import eval.deprecations as eval_deprecations

record Holder:
    deprecations: eval_deprecations.Log

func count(eval: Holder) -> int:
    return len(eval.deprecations.items)

func limit() -> int:
    if True:
        const eval = 5
        if eval == 5:
            return eval
    return eval.deprecations.LIMIT

func main() -> int:
    const eval = Holder(deprecations=eval_deprecations.Log(items=[1, 2, 3]))
    return count(eval) + limit() + len(eval.deprecations.items) + 1
```

## Export placement

A declaration is published by writing `public` in front of it: `public func
name(...)`, `public record Name`, `public enum Name`, `public type Name`, and so
on. The modifier names no other declaration, so a file keeps its public surface
where each declaration is written and a rename can never leave a stale directive
behind.

The bare `export NAME` directive was removed: it now rejects with
`E_EXPORT_REMOVED`, which points at the declaration spelling to use instead. The
only remaining export directive is the dotted re-export `export module.Name`,
which publishes an imported declaration (see below); it may appear anywhere among
the top-level declarations after its imports, and a
duplicate or unknown re-export still reports at the directive that caused it.

```selka
# doc: project report
# doc: file totals.selka

public func base() -> int:
    return 40


public func bonus() -> int:
    return 2
```

```selka
# doc: project report
# doc: file main.selka
# doc: expect 42
import totals

func main() -> int:
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

```selka
# doc: project published
# doc: file units.selka

public record Distance:
    value: int

public func make(value: int) -> Distance:
    return Distance(value=value)

public func metres(distance: Distance) -> int:
    return distance.value
```

```selka
# doc: project published
# doc: file facade.selka
import units
export units.Distance
export units.make
export units.metres
```

```selka
# doc: project published
# doc: file main.selka
# doc: expect 42
import facade

func main() -> int:
    mut distance: facade.Distance = facade.make(42)
    return facade.metres(distance)
```

## Checking every module of a project

`selka check ENTRY.selka` loads the modules `ENTRY` imports and no others, so a module nothing imports can hold any
error and the check still passes. Name the project's directory instead and every module beneath it is checked,
imported or not, test modules included:

```console
$ selka check src
check: ok (319 modules, 0 cached)
```

The directory is the project: module names are the paths beneath the directory holding the nearest `selka.json`
([the project root](#the-project-root-and-selkajson); the directory itself when there is none), the same names
`selka test DIR` and `selka fix DIR` use (a test run keeps a file's own folder as its root where the file loads with
it: [directory runs](tooling/guest-tests.md#directory-runs)). Hidden directories, `build`, `zig-out`, `node_modules` and the
`release.exclude` paths of the configuration are left out of the walk, wherever they lie beneath `DIR`; `DIR` itself is walked
whatever it is called (`selka check build` checks the modules of a folder called `build`, named `build.NAME`). A file whose name is not a module name (`bad-name.selka`) is skipped and named on standard error. The check loads all the modules through
one generated entry, `selka_check_all`, which exists only in memory (a project that has a module of that name is
refused with exit status 2), so the work is shared across the project and a second run is served from the caches as a
second `check ENTRY` is. A test file keeps its access to the private declarations of the module it tests, and the
generated entry reports no warnings. The count in the last line is the number of project modules loaded.

## Limits

- By default a project loads at most 16,384 modules and 262,144 import edges,
  with each file capped at 4 MiB and the whole project at 64 MiB of source —
  room for well over a million lines with no configuration. A `selka.json`
  `budgets` object (`max_modules`, `max_imports`, `max_file_bytes`,
  `max_total_bytes`) raises or lowers each, and `selka test` bounds its source
  snapshot by the same `max_total_bytes`. `max_file_bytes` bounds the project's
  own files: the embedded standard library is outside it, so a project with a
  small `max_file_bytes` can still `import math`. The library still counts toward
  `max_total_bytes`.
- Import cycles reject with `E_IMPORT_CYCLE`, reporting both the importing location and the related
  source location. The message names what each module of the cycle uses from the next (at most three
  names per import, then a count) and the way out: move what the modules share into a module they all
  import, or, when one import of the cycle is unused, remove it. Importing the same module twice in one
  file rejects with `E_DUPLICATE_IMPORT`.
- Standard-library names are reserved and load from embedded source rather than
  from the project root; `--local-stdlib` on `run`, `build`, `check` or `test`
  prefers a file beside the entry while developing a replacement. A standard-named
  file named directly as the `check` entry is checked from its path without the
  switch; the switch is needed when an import should resolve to it. Without the
  switch a project's own `options.selka` is ignored, and `check`, `build`, `run` and
  `test` say so, as the refusal of `options.Options(...)` does. See
  [the standard library](standard-library.md).
- Every source file derives its module identity from its path; module headers
  are rejected with a deletion fix. Standard and project imports use the same
  headerless source form. Configured projects resolve names beneath the project
  root, and unconfigured entries resolve them beneath the entry directory.
