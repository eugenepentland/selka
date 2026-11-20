# Typed holes

A typed hole marks code you have not written yet. Everything around it is checked normally, so a half-written module
still reports its real errors, and the hole is a located diagnostic rather than a value that compiles and fails later.

## Typed holes

Write `todo[T]()` in expression position, where `T` is the type the missing code must produce. The type is declared, not
inferred: the checker validates it, then reports `E_TYPED_HOLE` at the `todo`, with a related span on the declared type.
One check names every hole, in ordinary bodies and in uncalled generic bodies, instead of stopping at the first.

`selka check` refuses a hole. A release build refuses a hole that `main` can reach (see
[Release builds](#release-builds)). A debug build (`selka build`, `selka run`, `selka test`) accepts it (see
[Running with holes](#running-with-holes)).

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

A debug build keeps each hole as an expression of its declared type. Evaluating it traps with `R_TYPED_HOLE`, naming the
hole's location and the call frames that reached it. A program whose tests avoid the hole runs and passes before the
rest is finished:

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

`selka test` runs `test_double` and reports `test_reaches_hole` as failed with `R_TYPED_HOLE`. The check of the same file
still reports `E_TYPED_HOLE`.

A skeleton function that takes a capability can be written before its body: the parameters it will read are not
reported while the hole stands.

```selka
# doc: expect 7
func read_all(fs: Filesystem, path: str) -> bytes:
    return todo[bytes]()

func main() -> int:
    return 7
```

The rules:

- `selka check`, `check-module` and `check-project` report every hole with `E_TYPED_HOLE`.
- `selka build --release` and `run --release` refuse a hole `main` can reach with `E_TYPED_HOLE` and write no
  executable. A hole in a function `main` cannot reach is built as a trap.
- `selka build`, `run` and `test` accept the hole and trap at `R_TYPED_HOLE` when it is reached.
- No cache hides a hole from `check`: it reports `E_TYPED_HOLE` after a debug build too.
- A hole never hides another error of its module. When holes alone fail a check, the module's ownership errors,
  `E_UNUSED_CAPABILITY` and warnings (`W_UNUSED_IMPORT`, `W_UNUSED_BINDING`) are reported beside them, as if each hole
  were a value of its declared type.
- A function that holds a hole is not refused or warned about for a parameter it does not read, because the code that
  fills the hole may read it. Once the hole is filled, an unread capability parameter is `E_UNUSED_CAPABILITY` and an
  unread parameter `W_UNUSED_BINDING`. The allowance covers parameters of the function that holds the hole only.

## Release builds

A release build builds only the functions `main` can reach, with each hole kept as a trap. A hole left in one of them
is refused with `E_TYPED_HOLE`, naming the function that holds it, and no executable is written. A hole in a function
nothing reaches never reaches the binary, so a skeleton whose finished part is all `main` uses ships while its stubs
wait.

A function value counts as a call: a function `main` hands on as a callback (`apply(unfinished, False)`) is reachable
whether or not it is ever called, and a hole in it refuses the build. A function value taken in a function `main`
cannot reach does not count. The arguments of a `debug(...)` line are evaluated in every build, so a hole reached only
through one refuses `selka build --release`.

## Checking one file of a skeleton

A file that imports skeleton modules inherits their holes, so a real error of the file can be one block among hundreds.
`selka check-module FILE` reports the holes of FILE in full, with its other errors, and the holes of the other modules it
reached on one line after them:

```console
$ selka check-module src/erc.selka
src/erc.selka:7:12: error[E_TYPED_HOLE]: unresolved implementation obligation; fill this hole before checking or execution
...
note: 473 typed holes in 41 other modules (check DIR lists them)
```

The check still fails while any module holds a hole (exit 1). The note is text only: `--diagnostics=json` lists every
hole, and `selka check DIR` and `selka check FILE` print every hole of every module.

## Structured obligations

`check --diagnostics=json` attaches a versioned `typed-hole-obligation` record to each `E_TYPED_HOLE` diagnostic, so an
agent can read the hole's local context instead of guessing it. The record carries:

- the checked snapshot's identity and the hole's exact source range;
- the declared result type, the enclosing callable, and the contextual expected type when the checker knows one;
- every in-scope initialized binding with its type, the generic requirements in force, and the permitted `mutates(...)`
  footprint;
- an `unavailable` list naming the facts the hole cannot establish, and `unusable_bindings`, a count of uninitialized and
  consumed bindings, which never appear as inputs.

```bash
$ selka check --diagnostics=json hole.selka
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_TYPED_HOLE", …
"obligation":{"kind":"typed-hole-obligation","version":1,"identity":{…},
"declared":{"text":"int",…},"bindings":[{"name":"x","type":"int",…}],…}}
```

An obligation is identified by its snapshot digest and its range, so a query made against an older snapshot answers "no
such hole" instead of pointing at whatever now sits at that offset. Replacing the hole removes its obligation.

## Limits

- `todo[T]()` takes exactly one type argument and no value arguments. It is the one construct that keeps angle-bracket
  type arguments in the Python surface; ordinary generic calls are written `f[T](x)`.
- A release build cannot ship a reachable hole. A debug build, `run` and `test` trap at it. `check` always reports it.
- The formatter preserves a hole.
- The type is declared, not completed from context: the compiler does not propose an implementation. Pair the
  diagnostic with the [navigation](tooling/navigation.md) queries to find the types and functions a filling needs.
- A snapshot lives with the diagnostic that carries it: there is no durable hole database, and the JSON record is the
  only route to it. One snapshot keeps at most 32 bindings and 32 requirements and counts the surplus in `omitted`.
- Recovery stops at the checker's safe boundaries: a function whose body fails earlier than its hole reports only the
  earlier failure, and further holes in one body are reported only where the checker already recovers.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/typed-holes.md).
