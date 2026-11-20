# Typed holes

A typed hole is a place where an implementation is missing and the author has
said so in the source. Everything around it is checked normally, so the rest of a
half-written module still reports its real errors, and the hole itself is a
located diagnostic rather than a value that compiles and fails later.

## Typed holes

Write `todo[T]()` in expression position, where `T` is the type the missing code
has to produce. The type is declared, not inferred from context: the checker
validates it, then reports `E_TYPED_HOLE` at the `todo` with a related span on
the declared type. Ordinary bodies and uncalled generic bodies each report their
own holes in one check, at safe recovery boundaries, so a file with several
gaps names all of them instead of stopping at the first.

`selka check` refuses a hole: nothing is published while a hole remains, so the
construct stays an obligation rather than a panic hidden behind a passing check. A
release build refuses a hole that `main` can reach; see
[Release builds](#release-builds). A debug build (`selka build`, `selka run` and
`selka test`) does not refuse it; see [Running with holes](#running-with-holes).

```selka
# doc: expect-error E_TYPED_HOLE
record Invoice:
    subtotal: int
    tax: int

func total(invoice: Invoice) -> int:
    return invoice.subtotal + invoice.tax

func discount(invoice: Invoice) -> int:
    return todo[int]()

func main() -> int:
    mut invoice = Invoice(subtotal=40, tax=2)
    return total(invoice) - discount(invoice)
```

## Running with holes

A debug build keeps each hole as an expression of its declared type. Evaluating
it traps with `R_TYPED_HOLE`, and the trap names the hole's location and the
call frames that reached it. A program whose tests avoid the hole therefore
runs and passes before the rest of the program is finished:

```selka
# doc: expect-error E_TYPED_HOLE
func unfinished() -> int:
    return todo[int]()

func double(x: int) -> int:
    return x * 2

public func test_double() -> bool:
    return double(21) == 42

public func test_reaches_hole() -> bool:
    return unfinished() == 1

func main() -> int:
    return double(1)
```

`selka test` runs `test_double` and reports `test_reaches_hole` as failed with
`R_TYPED_HOLE`. The check of the same file still reports `E_TYPED_HOLE`.

A skeleton function that takes a capability can be written before its body: the parameters
it will read are not reported while the hole stands.

```selka
# doc: expect 7
func read_all(fs: Filesystem, path: str) -> bytes:
    return todo[bytes]()

func main() -> int:
    return 7
```

The debug and release rules are these:

- `selka check`, `check-module` and `check-project` report every hole with
  `E_TYPED_HOLE`, as before.
- `selka build --release` (and `run --release`) refuses a hole `main` can reach with
  `E_TYPED_HOLE` and writes no executable; a hole in a function `main` cannot reach is
  built as a trap, as in a debug build.
- `selka build`, `selka run` and `selka test` (the debug modes) accept the
  hole and trap at `R_TYPED_HOLE` when it is reached.
- No cache hides a hole from `check`. A debug build, `run` or `test` publishes check summaries too, and a function that holds a
  hole is left out of what they let a later check stand in, so `check` reports `E_TYPED_HOLE` after a debug build, in the same
  work directory or a new one beside a shared store. Nor does a refused check stop the next build from keeping the hole as a trap.
- A hole never hides an ownership error. When a check fails only because of
  holes, the ownership errors of the same program are reported beside them, as
  if each hole were a value of its declared type.
- A function whose body still holds a hole is not refused or warned about for a
  parameter it does not read: the code that fills the hole may read it. A
  skeleton such as `func read_all(fs: Filesystem, path: str) -> bytes:` with a
  `todo[bytes]()` body therefore builds and runs, with no `_fs` rename
  to remove later. Once the hole is filled, an unread capability parameter is
  `E_UNUSED_CAPABILITY` again and an unread parameter `W_UNUSED_BINDING`. The
  allowance covers parameters only, and only the function that holds the hole.

## Release builds

A release build keeps each hole as a trap while it checks, as a debug build does, and builds only the functions
`main` can reach. A hole left in one of those functions is one the program can run into, so the build refuses it
with `E_TYPED_HOLE`, naming the function that holds it, and writes no executable. A hole in a function nothing
reaches never reaches the binary, so a skeleton whose finished part is all that `main` uses ships while its stubs
wait: the modules a program imports no longer have to be hole-free.

A function value counts as a call. A function that `main` hands on as a callback (`apply(unfinished, False)`)
is reachable whether or not the code ever calls it, and a hole in it refuses the build. A function reached only
from a function `main` cannot reach is not built, and a function value taken there does not count.

The arguments of a `debug(...)` line are evaluated in every build, a release build included, so a hole reached only through
one refuses `selka build --release`, as `check` and `run --release` already did.

`selka check` is unchanged: it reports every hole of every module it reads.

## Checking one file of a skeleton

A file that imports skeleton modules inherits their holes: every `todo[T]()` of every module it reaches is an
`E_TYPED_HOLE` of the check, and a real error of the file is one block among hundreds. `selka check-module FILE`
therefore reports the holes of FILE in full, with its other errors, and the holes of the other modules it reached on
one line after them:

```console
$ selka check-module src/erc.selka
src/erc.selka:7:12: error[E_TYPED_HOLE]: unresolved implementation obligation; fill this hole before checking or execution
...
note: 473 typed holes in 41 other modules (check DIR lists them)
```

The check still fails while any module holds a hole (the exit status is 1, as before), the note is text only
(`--diagnostics=json` lists every hole), and `selka check DIR` and `selka check FILE` print every hole of every
module, as they did.

A hole never hides another error of its module. A check that a hole refuses runs the remaining checks of the module
once more with the holes kept as traps, and prints what they find beside the holes: an unread capability parameter
(`E_UNUSED_CAPABILITY`), the module's ownership errors and its warnings (`W_UNUSED_IMPORT`, `W_UNUSED_BINDING`).

## Structured obligations

`check --diagnostics=json` attaches a versioned `typed-hole-obligation` record to each
`E_TYPED_HOLE` diagnostic, so an agent can read the hole's local context instead of
guessing it. The record carries the checked snapshot's identity and the hole's exact
source range, the declared result type, the enclosing callable, every in-scope
initialized binding with its type, the generic requirements in force, the permitted
`mutates(...)` footprint, plus the contextual expected type when the checker knows
one. Facts the unresolved hole cannot establish are named in an `unavailable`
list rather than guessed. Uninitialized and consumed
bindings never appear as inputs; they are counted in `unusable_bindings`. The text
diagnostic stays as short as before.

```bash
$ selka check --diagnostics=json hole.selka
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_TYPED_HOLE", …
"obligation":{"kind":"typed-hole-obligation","version":1,"identity":{…},
"declared":{"text":"int",…},"bindings":[{"name":"x","type":"int",…}],…}}
```

An obligation is identified by its snapshot digest — the source path, the checked text
and the hole's range — together with that range, so a query made against an older
snapshot answers "no such hole" instead of pointing at whatever now sits at the same
offset. Replacing the hole removes its obligation, and the program checks and runs
normally again.

## Limits

- `todo[T]()` takes exactly one type argument and no value arguments. It is the
  one construct that keeps angle-bracket type arguments in the Python surface;
  ordinary generic calls are written `f[T](x)`.
- A release build (`selka build --release`, `selka run --release`) refuses a hole `main` can reach, so
  it cannot ship one. A debug build, `run` and `test` trap at it instead. `check` always reports it.
- Source formatting preserves a hole, so running the formatter over an unfinished
  file does not quietly erase the obligation.
- This is an explicit declared type, not expected-type completion: the compiler
  does not propose an implementation or rank candidates. Pair the diagnostic with
  the navigation queries to find the types and functions a filling would need.
- A snapshot is retained per check, beside the diagnostic that carries it: there is no
  durable hole database and no `context --at` query yet, so the structured JSON record
  is the only route to it. One snapshot keeps at most 32 bindings and 32 requirements
  and counts the surplus in `omitted`.
- Checker recovery still stops at its existing safe boundaries: a function whose body
  fails earlier than its hole reports only the earlier failure, and additional holes in
  one body are reported only where the checker already recovers.

## Related pages

- Typed implementation obligations (`docs/experiments/typed-holes.md`) — the experiment record behind this feature
