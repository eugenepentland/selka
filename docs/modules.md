# Modules, imports and exports

A program larger than one file is a project: modules, each a single source file, joined by `import` declarations to the
entry the command line names. A module sees what it declares and what its imports bring in (a library shared between
applications is a local package: `selka docs packages`).

## Running a file that imports

`selka run` loads the reachable graph when a file imports modules. A module is its file path: `helper.selka` is
`helper`, and a `module` header is rejected with a deletion fix. Standard modules use the same import syntax:

```selka
# doc: expect 42
import math

func main() -> int:
    return math.clamp(99, 0, 42)
```

`--print-result` prints `42`. A file that imports is named like a module (letters, digits and `_`, not starting with a
digit): `selka check my-prog.selka` with an `import` in it is `E_ENTRY_NAME` (rename it `my_prog.selka`).

### Headerless scripts

A project import resolves to a matching file under the project root; a missing file is `E_MODULE_READ`:

```selka
# doc: expect-error E_MODULE_READ
import helper

func main() -> int:
    return 0
```

Exported declarations use `public`; imported private declarations stay inaccessible.

```console
$ selka run main.selka
$ selka run main.selka --restrict --allow-read=.
```

- `run` compiles to a temporary native executable; `main` returning `int` exits with that value (eight bits), and a trap
  outranks it. `run-project` is the explicit alias.
- `build main.selka --run -- ARGS` runs a temporary binary; `build main.selka -o app` needs `--project` for a module
  project, and the binary reads runtime options from `SELKA_OPTIONS`.
- `test main.selka` builds each guest test as a separate native child with no ambient capabilities.
- Every capability is granted by default; `--restrict` denies all but those named by `--allow-*`, and reports the first
  missing entry capability with one stderr line and exit 2 before guest execution.
- `main(args: str[], ...)` receives only guest arguments: the values after `--` for `run` and `build --run`, every OS
  argument after `argv[0]` for an installed executable. Runtime controls go before the delimiter, or in `SELKA_OPTIONS`.
  Arguments must be valid UTF-8.

## Disk modules

A source file begins with its `import` declarations, then its top-level declarations. A dotted import name is a path under
the project root: `import units` reads `units.selka`, `import shared.units` reads `shared/units.selka`. `selka run` and
`selka check-project` load the reachable graph once, in dependency order.

- Nothing is exported implicitly: a declaration is visible to importers only with `public`, and an exported signature that
  mentions a private type is rejected.
- Capability arguments are explicit; source `noalloc`, `noio` and `effects(...)` clauses are `E_EFFECTS_REMOVED`.

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

The project root, where `import units` looks for `units.selka`, is the directory of the nearest `selka.json`, searching
up from the entry file's directory. With none, the root is the entry file's directory, so a module in a parent directory
is `E_MODULE_READ`. A file under a hidden folder (`.tmp/scratch.selka`) belongs to the project and imports from the same
root, but `selka check DIR` and `selka test DIR` skip the folder, and nothing imports from it (`E_INTERNAL_NAME`): move
the module out. The smallest `selka.json`:

```json
{"version": 1}
```

`{}` and an unknown key are `E_PROJECT_CONFIG`. Every key but `version` is optional:

| Key | What it holds | Guide |
|---|---|---|
| `version` | `1`; `2` is needed for `lint` and `release` | |
| `budgets` | `max_modules`, `max_imports`, `max_file_bytes`, `max_total_bytes` | [Limits](#limits) |
| `limits` | `max_steps`, `max_frames`, `max_memory` defaults for `run` and `test` | [runtime budgets](tooling/runtime-budgets.md#project-defaults-in-selkajson) |
| `import_policy` | a policy file of import-direction rules | [import policy](tooling/import-policy.md) |
| `interface_files` | `true`: each module's `.api` file is part of the check | [interface files](tooling/interface-files.md#enforcing-current-files-with-selkajson) |
| `links` | C source files that `build`, `run` and `test` link | [project links](c-ffi.md#project-links) |
| `allow_links` | packages whose C sources the build may use | [packages](tooling/packages.md#c-sources-in-a-package) |
| `stores` | where the caches and temporary folder live | [the caches](tooling/native-build.md#the-caches) |
| `lint` | lint profile and rule settings (version 2) | [lint](tooling/lint.md) |
| `release` | entries and excluded paths of the project docs (version 2) | [release docs](tooling/release-docs.md#configure-entries-and-paths) |
| `value_semantics` | only `true`, the default | [value semantics](value-semantics.md) |

## Dotted qualification

An import is qualified by its full dotted name or its local alias (the name after `as`, else the trailing segment):
`import prices` answers `prices.total`; `import catalog.prices` answers `catalog.prices.total` and `prices.total`;
`import catalog.prices as p` answers `p.total` and `catalog.prices.total`. It covers functions and types
(`prices.Price` annotates and constructs). A bare prefix that continues no module path is an ordinary name. Qualification
does not relax privacy; binding the same alias twice is `E_IMPORT_ALIAS`.

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

`util.twice(2)` or `shared.calc.f(x)` with no import binding `util`, and a module file of that name under the root, is
`E_MODULE_NOT_IMPORTED`; `selka fix` writes the import. A last segment alone (`calc.f(x)`) gets the same answer when
exactly one `calc.selka` lies below the root.

### An enum case written without its enum

A case is written with its enum: `argparse.Error.MissingValue(name="db")`, not `argparse.MissingValue(name="db")` or
`MissingValue(name="db")` (`E_UNKNOWN_SYMBOL`). When exactly one enum in reach has that case, the message names it and
`selka fix` writes it.

### A bare name that an imported module declares

An import binds the module's name, not its declarations: after `import bitio`, write `bitio.new_bitout()`, `bitio.BitOut`,
`bitio.LIMIT`. The bare `new_bitout()` is `E_UNKNOWN_SYMBOL`; when exactly one imported module declares that name
publicly, the message names it and `selka fix` writes the qualifier; with several, the message lists them and the choice is
yours.

### A local named like a path root

A bare prefix of an import's dotted path is not bound by the import, so a local or parameter may take it: with
`import eval.deprecations`, a function with its own `eval` reads `eval.deprecations.items` as fields of that local. The
innermost binding wins; where no such local is in force, the same spelling is the module path. A local cannot take an
import alias's name (`E_SHADOWING`).

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

A declaration is published by writing `public` in front of it: `public func name(...)`, `public record Name`,
`public enum Name`, `public type Name`. The bare `export NAME` directive is `E_EXPORT_REMOVED`. The one directive left is
the dotted re-export `export module.Name` (below), which may appear anywhere after the imports; a duplicate or unknown
one is reported at the directive.

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

`export units.Distance` names the import qualifier and the declaration inside it; the facade module publishes it under the
final name, so one module can be the public surface of a package whose declarations live in a submodule. The target must
already be exported by its module, and a qualifier that is not imported is `E_UNKNOWN_EXPORT`.

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

`selka check ENTRY.selka` loads only the modules `ENTRY` imports, so an unimported module can hold any error. Name the
project's directory and every module beneath it is checked, test modules included:

```console
$ selka check src
check: ok (319 modules, 0 cached)
```

- Module names are the paths beneath the directory of the nearest `selka.json` ([the project
  root](#the-project-root-and-selkajson)), the names `selka test DIR` and `selka fix DIR` use
  ([directory runs](tooling/guest-tests.md#directory-runs)).
- Hidden directories, `build`, `zig-out`, `node_modules` and the `release.exclude` paths are left out. A file whose name is
  not a module name (`bad-name.selka`) is skipped and named on standard error.
- A project with a module named `selka_check_all` is refused with exit status 2. A test file keeps access to the private
  declarations of the module it tests. The count in the last line is the number of modules loaded.

## Limits

| Limit | Default |
| --- | --- |
| modules in a project | 16,384 |
| import edges | 262,144 |
| one source file | 4 MiB |
| the whole project's source | 64 MiB |

The `selka.json` `budgets` keys (`max_modules`, `max_imports`, `max_file_bytes`, `max_total_bytes`) change each; `selka test`
uses `max_total_bytes` too. `max_file_bytes` covers the project's own files only, so `import math` still works.

- An import cycle is `E_IMPORT_CYCLE`; the message names what each module uses from the next and the way out (move the
  shared part into a module they all import, or remove an unused import). The same module imported twice in one file is
  `E_DUPLICATE_IMPORT`.
- Standard-library names are reserved and load from embedded source; `--local-stdlib` on `run`, `build`, `check` or `test`
  prefers a file beside the entry while you develop a replacement. Without it a project's own `options.selka` is ignored,
  and the command says so. See [the standard library](standard-library.md).

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/modules.md).
