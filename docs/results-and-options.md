# Results and options

The language has no exceptions. A call that can fail returns `Result[T, E]`, and a call
that can find nothing returns `Option[T]`. The two are deliberately different: a
`Result` carries a handling obligation the checker enforces, while an `Option` is
ordinary data that may be ignored. Both are prelude types with one identity everywhere,
so no module declares or imports them, and both are taken apart with the `match`
statement described in [records, unions and enums](records-and-unions.md#tagged-unions).

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
def divide(numerator: int, denominator: int) -> Result[int, str]:
    if denominator == 0:
        return Err("division by zero")
    return Ok(numerator // denominator)

def main(out: Stream) -> int:
    match divide(21, 3):
        case Ok(value):
            out.print(value)
        case Err(message):
            out.print(message)
    ignored = divide(1, 0)
    return 0
```

The `match` above discharges the first result. The program is still rejected, because
`ignored` reaches the end of `main` unhandled; writing `_ = divide(1, 0)` instead accepts
the failure explicitly and checks cleanly. Results describe errors a caller can recover
from. A violated invariant is not one: `assert` traps, and so do arithmetic overflow and
host failures, none of which turn into an `Err`.

## Postfix error propagation

`expression?` unwraps a successful `Result` into its payload and, on failure, returns the
error from the enclosing function immediately. The enclosing function must itself return
a compatible `Result` — the error payloads are matched by case, and an error of an
unrelated type is rejected, so a function whose errors are `int` cannot propagate a `str`
error. The one implicit conversion is the wrapping case: when the enclosing error union
carries the propagated error type as a case payload, the error converts into that case
and no hand-written translation helper is needed. `?` on a value that is not a
result is rejected, as is `?` in a function that returns a plain value. The early return
releases the scope it leaves the way an ordinary `return` does, including closing an open
file or ending an arena block.

```mylang
# doc: expect 37
def divide(n: int, d: int) -> Result[int, str]:
    if d == 0:
        return Err("division by zero")
    return Ok(n // d)

def average(total: int, parts: int) -> Result[int, str]:
    share = divide(total, parts)?
    return Ok(share + 1)

def report(total: int, parts: int) -> int:
    match average(total, parts):
        case Ok(value):
            return value
        case Err(message):
            return len(message)

def main() -> int:
    return report(40, 2) + report(40, 0)
```

This returns `37`: `21` from the successful path, and `16` — the length of the propagated
message — from the failing one. `average` never mentions the error case, which is the
point of the form. `with open(fs, path, mode)? as f:` is the same operator at a `with`
head; see [printing, files and command-line authority](io.md).

When the enclosing error union has a case whose payload is exactly the propagated error
type, that case is the conversion. The wrapped error keeps its own identity inside the
payload, so a caller can recover the category and the detail:

```mylang
# doc: expect 20
result Inner:
    ok: int,
    err: str


union AppError:
    Detail: str,
    Missing: int


def load(flag: bool) -> Inner:
    if flag:
        return Err("no value")
    return Ok(20)


def convert(flag: bool) -> Result[int, AppError]:
    value = load(flag)?
    return Ok(value)


def rate(flag: bool) -> int:
    match convert(flag):
        case Ok(value):
            return value - 8
        case Err(error):
            match error:
                case AppError.Detail(text):
                    return len(text)
                case AppError.Missing(code):
                    return code


def main() -> int:
    return rate(False) + rate(True)
```

`convert(True)` propagates `Err("no value")` without a translation helper: the `str`
becomes the payload of `AppError.Detail`, so `rate(True)` returns `8` and the program
prints `20`. A propagated error type that is not a case payload of the enclosing union
still fails with `E_TYPE`.

## Option constructors

`Option[T]` represents a value that may be absent. `Some(value)` builds the present case
and a bare `None` builds the absent one, and both take their `Option[T]` type from the
surrounding context: a binding annotation, a parameter, a record field or the enclosing
function's return type. `Some(value)` with no such context is rejected with
`E_OPTION_INFERENCE`, and outside an `Option` context `None` is the ordinary unit value a
procedure returns, not an empty option. Take an option apart with `case Some(value)` and
`case None`. An option carrying only ordinary data has no handling obligation, so it may
be ignored or discarded; that is the difference from a `Result`, and the reason the
standard library returns `Option[T]` for a lookup that found nothing and `Result[T, E]`
for an operation that failed.

```mylang
# doc: expect 47
def lookup(values: list[int], index: int) -> Option[int]:
    if index < 0 or index >= len(values):
        return None
    return Some(values[index])

def main() -> int:
    values = [10, 20, 30]
    total = 0
    match lookup(values, 1):
        case Some(value):
            total = total + value
        case None:
            total = total - 1
    missing: Option[int] = lookup(values, 9)
    match missing:
        case Some(value):
            total = total + value
        case None:
            total = total + 5
    parsed = int("22")
    match parsed:
        case Some(value):
            total = total + value
        case None:
            total = total - 1
    return total
```

This returns `47`. `int(text)` and `float(text)` return options for the same reason: text
that is not exactly one number answers `None` instead of raising.

## Contextual empty constructors

An empty `[]`, an empty `{}`, `Ok(...)` and `Err(...)` carry no type of their own. Each
takes the type it needs from the place it is written: an annotated binding, a record
field, a list element, a concrete call argument, or the enclosing function's declared
result. This is what lets `Batch(names=[], counts={})` construct a record whose fields
are a `list[str]` and a `dict[str, int]`, and lets `return Err("empty")` name no types at
all. Where no expected type reaches the expression the compiler says so rather than
guessing: a contextless empty list is rejected with `E_LIST_INFERENCE` and a contextless
`Ok` or `Err` with `E_RESULT_INFERENCE`. Nesting works, so an expected `list[list[int]]`
pushes its element type into an inner `[]`.

```mylang
# doc: expect 9
record Batch:
    names: list[str]
    counts: dict[str, int]

def empty_batch() -> Batch:
    return Batch(names=[], counts={})

def first(values: list[int]) -> Result[int, str]:
    if len(values) == 0:
        return Err("empty")
    return Ok(values[0])

def main() -> int:
    batch = empty_batch()
    batch.names.append("alpha")
    batch.counts["alpha"] = 3
    pending: list[int] = []
    total = 0
    match first(pending):
        case Ok(value):
            total = total + value
        case Err(message):
            total = total + len(message)
    return total + len(batch.names) + batch.counts["alpha"]
```

This returns `9`. A module that declares its own function named `Ok` or `Err` calls that
function instead; the contextual constructors never shadow a declaration you wrote.

## Builtin list and result types

`list[T]` and `Result[T, E]` are part of the prelude. They need no `record` declaration
and no import, they are spellable in annotations, record fields, parameters, return types
and exported module signatures, and they use the same managed-list and checked-result
semantics as everything else on this page. Both work under generic type parameters, so a
generic function can build a `list[T]` or an `Ok(value)` whose payload type is still
symbolic. A module that declares its own `List` or `Result` type keeps its own nominal
identity inside that module, and unrelated modules continue to resolve the prelude one.

```mylang
# doc: expect 12
def head[T](values: list[T]) -> Result[T, str]:
    if len(values) == 0:
        return Err("empty")
    return Ok(values[0])

def main() -> int:
    numbers: list[int] = [7, 8, 9]
    words: list[str] = ["alpha"]
    total = 0
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
module main
import strings

def summarise(counts: dict[str, int]) -> Result[str, str]:
    if len(counts) == 0:
        return Err("no counts")
    names: list[str] = counts.keys()
    return Ok(names[0])

def main() -> int:
    counts: dict[str, int] = {"lang": 4}
    total = 0
    match strings.find("mylang", "lang"):
        case Some(index):
            total = total + index
        case None:
            total = total - 1
    match summarise(counts):
        case Ok(name):
            raw: bytes = name.encode()
            total = total + len(raw)
        case Err(message):
            total = total - len(message)
    return total
```

This returns `6`. `strings.find` returns the prelude `Option[int]` and `summarise`
returns the prelude `Result[str, str]`, and neither declaration nor import mentions a
prelude module.

## Related pages

- [Records, unions and enums](records-and-unions.md) — the declared types these wrap
- [Python-style application code](python-syntax.md) — the surrounding syntax
- [Standard library](standard-library.md) — which module functions return `Option` and which return `Result`
- [Printing, files and command-line authority](io.md) — file helpers returning `Result[T, str]`
- [Managed byte strings](bytes.md) — `decode` and `fromhex` as checked results
