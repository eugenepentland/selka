# Results and options

A fallible function declares its successful type and error separately:
`func parse(text: str) -> Point fails ParseError`. `return point` succeeds;
`fail error` returns a declared failure. Calling it produces a checked result
that must be handled, stored or transferred according to the result rules.
`try parse(text)` extracts success and propagates compatible failure from the
enclosing fallible function.

An optional value is written `T?` and represents a value or `None`.
Absence is ordinary data; it carries no result handling obligation. Return or
assign a `T` directly where `T?` is expected. Presence guards narrow locals,
and explicit matching remains available for both optional and result values.
Stored results may still be typed as `Result[T, E]`, and rare nominal `result`
declarations preserve their existing identities.

## Flow-sensitive Option guards

`value is None` and `value is not None` test an Option's tag. When a branch establishes
that a local Option is present, reads of that binding use its payload type. An early
return from the absent branch leaves the payload available on the continuing path.

```mylang
# doc: expect 42
record Node:
    width: int

func width(node: Node?) -> int:
    if node is None:
        return 0
    return node.width

func positive(value: int?) -> bool:
    return value is not None and value > 0

func main() -> int:
    if positive(Some(42)):
        return width(Some(Node(width=42)))
    return 0
```

Facts follow `if`/`else`, `not`, and short-circuit `and`/`or`, in ordinary and generic
functions. A `while value is not None` guard establishes presence inside its body.
After a join, a fact survives only if every continuing branch preserves it. Reassigning
the binding invalidates its fact; loop bodies are checked with assignments from later
iterations in mind, and a loop that might never run establishes no new fact afterwards.

The declared binding remains an Option. Assign `None` or a payload value to replace a writable optional local;
an annotated destination or parameter expecting that same Option type receives the
original wrapper. Repeated `is None` tests and explicit `match` also see the wrapper.
Narrowed record field and collection updates preserve the wrapper.

Only local bindings are refined. A test of `box.item` evaluates that expression once,
but does not establish a fact about future reads through a mutable alias. Assign the
Option to a local first when a stable snapshot is wanted. Presence tests on wrappers
carrying an owned value or a checked `Result` are rejected; use `match` to preserve
their handling obligations.

This initial implementation lowers guards and payload reads through existing variant
dispatch, including a defensive trap for an invalidated payload projection. It does
not promise redundant-check elimination or prove integer bounds.

## Option methods

`T?` answers three intrinsic methods and nothing else: `unwrap_or(default: T) -> T`
returns the payload or the default, `is_none() -> bool` answers whether the value is
absent, and `is_some() -> bool` answers whether it is present. All three are pure and
allocate nothing, so a `noalloc` ceiling accepts them, and all three work in a generic
body whose parameter is an `T?`. `unwrap_or`'s default is checked against the
payload type, and an integer literal adopts that type exactly as it does in a binding,
so a `u8` payload makes `unwrap_or(7)` a `u8` default.

```mylang
# doc: expect 47
func parse(text: str) -> int?:
    return parse_int(text)

func head[T: copy + storable](values: T[]) -> T?:
    if len(values) == 0:
        return None
    return Some(values[0])

func width(text: str) -> int noalloc:
    return parse(text).unwrap_or(0)

func main() -> int:
    mut total = parse("nope").unwrap_or(7)
    total = total + head([40, 1]).unwrap_or(0)
    if parse("2").is_none():
        total = total + 100
    if head([1]).is_some():
        total = total + width("0")
    return total
```

This returns `47`: the absent parse takes the literal default `7`, the present list head
takes `40`, and the presence tests leave `total` alone. The receiver may be a named
binding or any expression, and a binding already narrowed by `is None` answers
`unwrap_or` with its payload and the two presence tests with constants. An `Option`
carrying an owned value or a checked `Result` still needs explicit `match`; a mismatched
default is `E_TYPE` and names the payload type it expected. The `sentinel-int` lint
reports the older convention — a function returning `-1` on one path whose result a
caller tests against a negative literal — and names this rewrite.

## Checked results

`Result[T, E]` is a two-case value: `Ok(value)` carries the success payload and
`Err(payload)` carries the failure payload, which may be any value type — a `str`, an
`int`, an enum or a record. A result-bearing value may not simply be dropped. Every path
out of a scope must have matched it exhaustively, returned it, passed it on, or released
it explicitly with `_ = value`; anything else is rejected with `E_RESULT_UNHANDLED`,
which names both the binding and the scope exit that abandoned it. The obligation
travels with the value, so reading a result-bearing binding transfers the obligation
rather than duplicating it, and a record or union field holding a result keeps the
obligation for the whole wrapper.

```mylang
# doc: expect-error E_RESULT_UNHANDLED
func divide(numerator: int, denominator: int) -> int fails str:
    if denominator == 0:
        fail "division by zero"
    return numerator // denominator

func main(out: Stream) -> int:
    match divide(21, 3):
        case Ok(value):
            out.print(value)
        case Err(message):
            out.print(message)
    mut ignored = divide(1, 0)
    return 0
```

The `match` above discharges the first result. The program is still rejected, because
`ignored` reaches the end of `main` unhandled; writing `_ = divide(1, 0)` instead accepts
the failure explicitly and checks cleanly. Results describe errors a caller can recover
from. A violated invariant is not one: `assert` traps, and so do arithmetic overflow and
host failures, none of which turn into an `Err`.

## Postfix error propagation

Use `try operation()` at a statement value boundary: a declaration initializer,
an assignment value, a `return` value, a standalone operation, or a resource
head such as `with try open(...) as file:`. Nested propagation inside arguments
or arithmetic is rejected; first extract the fallible operation into a local.
`return try other()` forwards the successful value and compatible failure.

The enclosing function must declare a compatible failure type. Existing error
case conversions remain available, including wrapping an error in a declared
error case whose payload has that type. Unrelated errors do not widen
implicitly. Propagation releases the scopes it exits, including open files,
just as `return` and `fail` do. The `?` suffix belongs to optional types.

```mylang
# doc: expect 37
func divide(n: int, d: int) -> int fails str:
    if d == 0:
        fail "division by zero"
    return n // d

func average(total: int, parts: int) -> int fails str:
    mut share = try divide(total, parts)
    return share + 1

func report(total: int, parts: int) -> int:
    match average(total, parts):
        case Ok(value):
            return value
        case Err(message):
            return len(message)

func main() -> int:
    return report(40, 2) + report(40, 0)
```

This returns `37`: `21` from the successful path, and `16` — the length of the propagated
message — from the failing one. `average` never mentions the error case, which is the
point of the form. `with try open(fs, path, mode) as f:` is propagation at a `with`
head; see [printing, files and command-line authority](io.md).

When the enclosing error union has a case whose payload is exactly the propagated error
type, that case is the conversion. The wrapped error keeps its own identity inside the
payload, so a caller can recover the category and the detail:

```mylang
# doc: expect 20
result Inner:
    ok: int,
    err: str


enum AppError:
    Detail(value: str)
    Missing(value: int)


func load(flag: bool) -> Inner:
    if flag:
        return Err("no value")
    return Ok(20)


func convert(flag: bool) -> int fails AppError:
    mut value = try load(flag)
    return value


func rate(flag: bool) -> int:
    match convert(flag):
        case Ok(value):
            return value - 8
        case Err(error):
            match error:
                case AppError.Detail(value=text):
                    return len(text)
                case AppError.Missing(value=code):
                    return code


func main() -> int:
    return rate(False) + rate(True)
```

`convert(True)` propagates `Err("no value")` without a translation helper: the `str`
becomes the payload of `AppError.Detail`, so `rate(True)` returns `8` and the program
prints `20`. A propagated error type that is not a case payload of the enclosing union
still fails with `E_TYPE`.

Optional absence is handled with a presence guard or `match`. A local known to
be present exposes its payload type; return `None` explicitly for the absent path.

```mylang
# doc: expect 4
record Node:
    value: int
    left: Node?


func left_value(node: Node) -> int?:
    const child = node.left
    if child is None:
        return None
    return child.value


func main() -> int:
    mut leaf = Node(value=4, left=None)
    mut root = Node(value=1, left=Some(leaf))
    return left_value(root).unwrap_or(0) + left_value(leaf).unwrap_or(0)
```

## Error return traces

An `Err` that reaches the end of `main`, or fails a test, says where it came from.
Every program keeps one error return trace, in every build mode and on both
backends: constructing an `Err(...)` value starts a fresh trace at that construction,
and a runtime operation that answers `Err` — reading a missing file, say — starts one
at its call. After that, each `try` that passes the error on adds its site, and says
which union case it converted the error into when it wrapped it; a `return` of an
`Err` the statement did not construct itself — a variable, a call's result, a
conditional expression — adds the `return`. Handling an error with `match` or `_ =`
adds nothing, so the trace always describes the most recent `Err` the program made.

```mylang
# doc: expect reading the configuration
enum AppError:
    Config(value: str)
    Usage(value: int)


func parse_port(text: str) -> int fails str:
    if len(text) == 0:
        fail "empty port"
    return len(text)


func read_config(text: str) -> int fails str:
    mut port = try parse_port(text)
    return port + 1


func load(text: str) -> int fails AppError:
    return try read_config(text)


func main(out: Stream) -> int fails AppError:
    out.print("reading the configuration")
    mut port = try load("")
    return port
```

When `main` returns the `Err`, the program writes `error:` and the error, rendered as
`print` renders it, then one line per site, the origin first:

```console
$ mylang run app.my
reading the configuration
error: AppError.Config('empty port')
  app.my:9:16   parse_port   Err(...) created
  app.my:14:12  read_config  ? propagated
  app.my:19:15  load         ? converted to AppError.Config
  app.my:24:12  main         ? propagated
$ echo $?
1
```

`main` may fail with any error type `print` can render. An `int` error is still the
exit status; any other error exits 1. `mylang test` prints the same trace under a
test whose value is an `Err`, and a test declared `-> Result[bool, E]` expects
`Ok(True)`, so it can use `try` and fail with the trace of the error it propagated.
A trap is reported as before, with its call stack instead.

The trace keeps the origin and the last 32 sites after it. A deeper chain, such as
a recursive descent, reports how many sites in between were dropped:
`... 9 more entries dropped ...`. Each site is a function's position table and an
instruction index the compiler already emits, so no text is built while the
program runs. Recording a site is one call to a small runtime recorder, on the
error path only: an `Ok` passing through `try`, and a
`return Ok(...)`, execute nothing extra. A `return` whose value could be either
case tests the returned case once. In an LLVM build the recorder keeps every
register but one intact, so a recording does not make an optimized loop spill
and reload the values it holds in registers.

## Option constructors

`T?` represents a value that may be absent. `Some(value)` builds the present case
and a bare `None` builds the absent one, and both take their `T?` type from the
surrounding context: a binding annotation, a parameter, a record field or the enclosing
function's return type. `Some(value)` with no such context is rejected with
`E_OPTION_INFERENCE`, and outside an `Option` context `None` is the ordinary unit value a
procedure returns, not an empty option. Take an option apart with `case Some(value)` and
`case None`. An option carrying only ordinary data has no handling obligation, so it may
be ignored or discarded; that is the difference from a `Result`, and the reason the
standard library returns `T?` for a lookup that found nothing and `Result[T, E]`
for an operation that failed.

```mylang
# doc: expect 47
func lookup(values: int[], index: int) -> int?:
    if index < 0 or index >= len(values):
        return None
    return Some(values[index])

func main() -> int:
    mut values = [10, 20, 30]
    mut total = 0
    match lookup(values, 1):
        case Some(value):
            total = total + value
        case None:
            total = total - 1
    mut missing: int? = lookup(values, 9)
    match missing:
        case Some(value):
            total = total + value
        case None:
            total = total + 5
    mut parsed = parse_int("22")
    match parsed:
        case Some(value):
            total = total + value
        case None:
            total = total - 1
    return total
```

This returns `47`. `parse_int(text)` and `parse_float(text)` return options for the same reason: text
that is not exactly one number answers `None` instead of raising.

## Contextual empty constructors

An empty `[]`, an empty `{}`, `Ok(...)` and `Err(...)` carry no type of their own. Each
takes the type it needs from the place it is written: an annotated binding, a record
field, a list element, a concrete call argument, or the enclosing function's declared
result. This is what lets `Batch(names=[], counts={})` construct a record whose fields
are a `str[]` and a `dict[str, int]`, and lets `return Err("empty")` name no types at
all. Where no expected type reaches the expression the compiler says so rather than
guessing: a contextless empty list is rejected with `E_LIST_INFERENCE` and a contextless
`Ok` or `Err` with `E_RESULT_INFERENCE`. Nesting works, so an expected `int[][]`
pushes its element type into an inner `[]`.

```mylang
# doc: expect 9
record Batch:
    names: str[]
    counts: dict[str, int]

func empty_batch() -> Batch:
    return Batch(names=[], counts={})

func first(values: int[]) -> int fails str:
    if len(values) == 0:
        fail "empty"
    return values[0]

func main() -> int:
    mut batch = empty_batch()
    batch.names.append("alpha")
    batch.counts["alpha"] = 3
    mut pending: int[] = []
    mut total = 0
    match first(pending):
        case Ok(value):
            total = total + value
        case Err(message):
            total = total + len(message)
    return total + len(batch.names) + batch.counts["alpha"]
```

This returns `9`. A module that declares its own function named `Ok` or `Err` calls that
function instead; the contextual constructors never shadow a declaration you wrote.

## Comparing with a constructor

The operand beside `==` or `!=` is a place that supplies a type too. `Some(...)`,
`None`, `Ok(...)` and `Err(...)` take the type of the other operand, in either order,
whatever that operand is: a local, a field, a call, a method call or an `parse_int(text)`
conversion. The other operand is checked first, so `lookup(values, 1) == Some(20)` and
`None != lookup(values, 9)` need no temporary binding. Two operands that both wait for
a type, such as `Some(1) == Some(1)`, still have nothing to infer from and are rejected
with `E_OPTION_INFERENCE`. Each equality link in a comparison chain uses the same inference, including in generic bodies. Shared operands evaluate once, left to right, and a false link skips the remaining operands.

```mylang
# doc: expect 4
func lookup(values: int[], index: int) -> int?:
    if index < 0 or index >= len(values):
        return None
    return Some(values[index])

func main() -> int:
    mut values = [10, 20, 30]
    mut score = 0
    if lookup(values, 1) == Some(20):
        score += 1
    if None != lookup(values, 2):
        score += 1
    if lookup(values, 9) == None and parse_int("5") == Some(5):
        score += 1
    if Some(20) == lookup(values, 1) == Some(20):
        score += 1
    return score
```

## Builtin list and result types

`T[]` and `Result[T, E]` are part of the prelude. They need no `record` declaration
and no import, they are spellable in annotations, record fields, parameters, return types
and exported module signatures, and they use the same managed-list and checked-result
semantics as everything else on this page. Both work under generic type parameters, so a
generic function can build a `T[]` or an `Ok(value)` whose payload type is still
symbolic. A module that declares its own `List` or `Result` type keeps its own nominal
identity inside that module, and unrelated modules continue to resolve the prelude one.

```mylang
# doc: expect 12
func head[T](values: T[]) -> T fails str:
    if len(values) == 0:
        fail "empty"
    return values[0]

func main() -> int:
    mut numbers: int[] = [7, 8, 9]
    mut words: str[] = ["alpha"]
    mut total = 0
    match head[int](numbers):
        case Ok(value):
            total = total + value
        case Err(message):
            total = total - len(message)
    match head(words):
        case Ok(word):
            total = total + len(word)
        case Err(message):
            total = total - len(message)
    return total
```

This returns `12`. `head[int](numbers)` supplies the type argument explicitly and
`head(words)` infers it; both reach the same instance.

## Canonical prelude types

`list`, `dict`, `str`, `bytes`, `Option` and `Result` have exactly one nominal identity
across every module of a project. A `Result[str, str]` returned by an imported module is the same type as one
built locally, so no project imports a prelude module to make its signatures line up, and
`case Ok(...)` reads a standard-library result the same way it reads yours. The identity
is shared, not ambient: `bytes` and `float` are registered wherever their names appear in
source, so a program that calls `text.encode()` without ever writing `bytes` is rejected
with `E_COLLECTION_METHOD` until an annotation or signature names the type. A module-local
declaration of one of these names shadows the prelude inside that module alone.

```mylang
# doc: expect 6
import strings

func summarise(counts: dict[str, int]) -> str fails str:
    if len(counts) == 0:
        fail "no counts"
    mut names: str[] = list(counts.keys())
    return names[0]

func main() -> int:
    mut counts: dict[str, int] = {"lang": 4}
    mut total = 0
    match strings.find("mylang", "lang"):
        case Some(index):
            total = total + index
        case None:
            total = total - 1
    match summarise(counts):
        case Ok(name):
            mut raw: bytes = name.encode()
            total = total + len(raw)
        case Err(message):
            total = total - len(message)
    return total
```

This returns `6`. `strings.find` returns the prelude `int?` and `summarise`
returns the prelude `Result[str, str]`, and neither declaration nor import mentions a
prelude module.

## Related pages

- [Records, unions and enums](records-and-unions.md) — the declared types these wrap
- [Python-style application code](python-syntax.md) — the surrounding syntax
- [Standard library](standard-library.md) — which module functions return `Option` and which return `Result`
- [Printing, files and command-line authority](io.md) — file helpers returning `Result[T, str]`
- [Managed byte strings](bytes.md) — `decode` and `fromhex` as checked results
