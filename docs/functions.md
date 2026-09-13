# Functions and calls

`def` declares every callable in the language. There are no methods, no
inheritance, no nested definitions and no closures, so a call's meaning follows
entirely from the declaration its name resolves to. This page covers how a call
supplies its arguments, what a function may return, and the one form — a function
value — that lets the target of a call be decided while the program runs.
[Statements and bindings](statements.md) covers what goes inside a body, and
[Python-style application code](python-syntax.md) is the wider tour of the
surface.

## Keyword arguments and defaults

A call passes arguments positionally, by keyword, or both, with every positional
argument before the first keyword. Keywords may name the parameters in any order,
and the arguments are evaluated exactly once in the order they are *written*,
not in parameter order, so a call whose arguments have effects behaves the way it
reads. A parameter may carry a default, which must be an immutable scalar
literal — a number, `True` or `False`, a string, or `None` — so no two calls can
ever share a mutable default; required parameters must precede every parameter
that has one, and the other order reports `E_DEFAULT_ARGUMENT`. Unknown,
duplicate, missing, excess and misplaced arguments are all rejected, and a
default's declared type is checked even in a function nothing calls. Intrinsics
such as `len` and calls made through a callback value take positional arguments
only.

```mylang
# doc: expect 42
def offset(value: int, amount: int = 2, scale: int = 1) -> int:
    return value * scale + amount

def main() -> int:
    plain = offset(38)
    keyword = offset(amount=2, value=38)
    if plain != keyword:
        return 1
    return plain + offset(0, scale=2)
```

Record construction reads the same way — `Point(x=1, y=2)` binds fields by name
through the same rules — and generic calls infer their type arguments from the
values they are given unless the [explicit
list](#explicit-call-type-arguments) is written out.

## Unit procedures

A function that produces no value is a procedure. Write `-> None` or omit the
return annotation entirely; both declare the same unit result. The body may end
by falling off the bottom or with a bare `return`, and both paths release the
frame's owned values through the ordinary cleanup. Unit is a real type rather
than an absence, which has one consequence worth remembering: an expression used
as a standalone statement must have it, so a call whose result you mean to throw
away needs `_ = work(...)` and a bare non-unit value reports
`E_EXPLICIT_DISCARD_REQUIRED`. Unit appears in a module's public schema as
`kind: unit` and stays callable from other language modules, but it is rejected
at the data, wire and host ABI boundaries, so a procedure is not callable across
the C ABI.

```mylang
# doc: expect 42
def bump(values: list[int]):
    values.append(0)

def add(values: list[int], value: int) -> None:
    if value < 0:
        return
    values.append(value)

def main() -> int:
    values: list[int] = []
    add(values, 40)
    add(values, -1)
    add(values, 2)
    bump(values)
    total = 0
    for value in values:
        total += value
    return total
```

`add` returns early for the negative value, `bump` falls off the end, and neither
needs a return annotation to say so.

## Entry point signatures

`main` is the entry point and may be written four ways: `-> int`, `-> None`,
`-> Result[int, int]` or `-> Result[None, int]`. All four adapt to one status
convention. An `int` result, or the `int` carried by `Ok` or by `Err`, is the
status value that `mylang run --print-result` prints after the program's own
output; the two `None` forms have no value of their own and report `0`. The
`Result` forms exist so the entry point can end a failure with `?` instead of
matching it at the top level. `main` may also declare capability parameters,
which is how a program asks for the filesystem, the clock, entropy or the
environment — see [printing, files and command-line
authority](io.md) — and it may not be generic.

```mylang
# doc: expect 42
def parse(value: int) -> Result[int, int]:
    if value < 0:
        return Err(2)
    return Ok(value)

def main() -> Result[int, int]:
    first = parse(40)?
    second = parse(2)?
    return Ok(first + second)
```

## Explicit call type arguments

A generic call may state its type arguments in square brackets between the
function name and the argument list: `identity[int](2)` is the Python spelling of
the legacy `identity::<int>(2)`. Explicit arguments and [inferred
ones](generic-inference.md) reach the same instance, so the choice is about
readability rather than behaviour — except where inference has nothing to work
from, such as a type parameter no value argument mentions, where the explicit
list is required. The list is all or nothing: a partial list is not completed by
inference, the return context never supplies a missing argument, and the wrong
count or an undeclared base name is rejected. In call position a square-bracket
application names a function when the base is a declared function and a generic
record otherwise, so `Box[int](item=0)` remains record construction.

```mylang
# doc: expect 42
def identity[T](value: T) -> T:
    return value

class Box[T]:
    item: T

def main() -> int:
    explicit = identity[int](2)
    inferred = identity(40)
    boxed = Box[int](item=0)
    return explicit + inferred + boxed.item
```

## Function values

The name of a declared function, written without a call, is a function value. Its
type is spelled `fn(parameters) -> result effects(...)`, with the parameter
types, the result type and the effect ceiling all written out, and a value of
that type can be stored in a local, passed as an argument and returned. A
function value captures nothing. There are no closures and no nested `def`, so
the value is an immediate function identity and everything it needs arrives
through its parameters; an attempt to capture the enclosing environment is
rejected rather than boxed. Function values are ordinary copied values with no
ownership of their own, and a call through one validates the target and keeps the
ordinary result and ownership obligations. They have no rendering, so passing one
to `print` is rejected with `E_IO_ARGUMENT`.

```mylang
# doc: expect 42
def double(value: int) -> int effects():
    return value * 2

def chosen() -> fn(int) -> int effects():
    return double

def apply(callback: fn(int) -> int effects(), value: int) -> int:
    return callback(value)

def main() -> int:
    op = chosen()
    return apply(op, 18) + op(3)
```

## Bounded callbacks

A parameter that accepts a function value declares the exact signature and the
exact effect ceiling it will take, and the match is exact in both directions: a
callback declared `effects()` rejects a function that prints, and a callback
declared `effects(output)` equally rejects a pure one, reporting `E_TYPE` with
the two signatures side by side. There is no widening or narrowing at the
boundary, so the ceiling is a statement about what invoking the callback may
cause, and a helper that calls an `effects(output)` callback must admit `output`
in its own bound. Generic helpers may declare parameter-dependent callback
signatures, which is how [`sort.sort_by_key`](standard-library.md) takes an
integer key function over an arbitrary element type. Captured environments stay
rejected here too, so a callback that needs context takes it as another
parameter.

```mylang
# doc: expect 40
# doc: expect 2
# doc: expect 42
def announce(value: int) -> int effects(output):
    print(value)
    return value

def sum_announced(values: list[int], report: fn(int) -> int effects(output)) -> int effects(output):
    total = 0
    for value in values:
        total += report(value)
    return total

def main() -> int:
    print(sum_announced([40, 2], announce))
    return 0
```

`sum_announced` carries `effects(output)` because calling `report` can print. Had
it been written `noio`, or with an empty `effects()`, the declaration would be
rejected before the program ran.
