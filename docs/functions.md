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
the C ABI. There is no unit literal: a bare `return`, falling off the end, or a
unit-returning call produces it, and `type Name = None` may name it. Unit is an
ordinary value of one shape rather than an absence, so it flows through generic
functions, callbacks, bindings and result payloads, and `fallible()?` propagates
a failed result whose success payload is unit.

```mylang
# doc: expect 42
def bump(values: mut list[int]):
    values.append(0)

def add(values: mut list[int], value: int) -> None:
    if value < 0:
        return
    values.append(value)

def main() -> int:
    values: list[int] = []
    add(mut values, 40)
    add(mut values, -1)
    add(mut values, 2)
    bump(mut values)
    total = 0
    for value in values:
        total += value
    return total
```

`add` returns early for the negative value, `bump` falls off the end, and neither
needs a return annotation to say so. Both write through `values`, so both declare
`values: mut list[int]` and every caller marks the argument.

## Entry point signatures

`main` is the entry point and may be written four ways: `-> int`, `-> None`,
`-> Result[int, int]` or `-> Result[None, int]`. All four adapt to one status
convention. An `int` result, or the `int` carried by `Ok` or by `Err`, becomes
the process exit status (truncated to the low 8 bits) and is also what `mylang
run --print-result` prints after the program's own output; the two `None` forms
have no value of their own and report `0`. The
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
function name and the argument list: `identity[int](2)`. Explicit arguments and [inferred
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

record Box[T]:
    item: T

def main() -> int:
    explicit = identity[int](2)
    inferred = identity(40)
    boxed = Box[int](item=0)
    return explicit + inferred + boxed.item
```

## Function values

The name of a declared function, written without a call, is a function value. Its
type is spelled `def(parameters) -> result effects(...)`, with the parameter
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

def chosen() -> def(int) -> int effects():
    return double

def apply(callback: def(int) -> int effects(), value: int) -> int:
    return callback(value)

def main() -> int:
    op = chosen()
    return apply(op, 18) + op(3)
```

## Bounded callbacks

A parameter that accepts a function value declares the destination signature
and effect ceiling. Parameter and result types stay invariant, but the
implementation's declared effect ceiling may be a subset of the destination's:
a pure callback may fill an `effects(output)` slot, while a callback that may
print may not fill an `effects()` slot. Rejected substitutions report `E_TYPE`
with both canonical source contracts and named effects; a rejected substitution
reads `expected def(int) -> int effects(), found def(int) -> int effects(output)`.
Calls through stored or returned callbacks still use the destination
contract's ceiling, so a helper that calls an `effects(output)` callback must
admit `output` in its own bound even when the concrete target passed in is pure.
Generic helpers may declare parameter-dependent callback signatures, which is how
[`sort.sort_by_key`](standard-library.md) takes an integer key function over an
arbitrary element type. Captured environments stay rejected here too, so a
callback that needs context takes it as another parameter.

```mylang
# doc: expect 40
# doc: expect 2
# doc: expect 42
def announce(value: int, out: Stream) -> int effects(output):
    out.print(value)
    return value

def sum_announced(values: list[int], report: def(int, Stream) -> int effects(output), out: Stream) -> int effects(output):
    total = 0
    for value in values:
        total += report(value, out)
    return total

def main(out: Stream) -> int:
    out.print(sum_announced([40, 2], announce, out))
    return 0
```

`sum_announced` carries `effects(output)` because calling `report` can print. Had
it been written `noio`, or with an empty `effects()`, the declaration would be
rejected before the program ran.

## Mutating callbacks

A callable signature declares the `mut` parameters it writes just as a declared
function does, and a call through the value substitutes the actual argument
origin, so the caller still needs permission for the mutation:

```mylang
# doc: expect 7
def apply(values: mut list[int], f: def(values: mut list[int]) -> None effects(mutation)) -> None effects(mutation):
    f(mut values)


def set_first(values: mut list[int]) -> None effects(mutation):
    values[0] = 7


def main(out: Stream) -> int effects(managed_allocation, output):
    values = [1]
    apply(mut values, set_first)
    out.print(values[0])
    return 0
```

The binder name is only a label: it does not become a keyword argument and it is
excluded from callable identity. An implementation may write fewer inputs than the
destination footprint permits, and a call through a stored or returned callback
uses the destination's footprint just as it uses the destination's effect ceiling.

## Attributes

A declaration may carry a fixed-vocabulary attribute on the line directly above
it. `@deprecated("reason")` marks a callable that callers should stop using:
a call from another module reports `W_DEPRECATED` with the reason, and the
attribute is part of the declaration's interface fingerprint. `@test` makes a
function a discovered test regardless of its name or `export` flag, so
`mylang test` and the `mylang lint` test rules see the same set. `@allow("rule",
reason="...")` waives one lint rule for findings on that declaration, replacing
the `# lint: allow` comment; a missing `reason=` is still `L_WAIVER_REASON` and
always blocks. The vocabulary is fixed: any other `@name` is
`E_UNKNOWN_ATTRIBUTE`, and repeating one kind on a declaration is
`E_DUPLICATE_ATTRIBUTE`. Attributes attach to function declarations and
round-trip through `fmt`.

```mylang
# doc: expect 9
@deprecated("use square_v2; removed after api_version 3")
def square(x: int) -> int effects():
    return x * x


@test
def square_of_three() -> bool effects():
    return square(3) == 9


@allow("dead-private", reason="kept for the doctest example")
def helper() -> int effects():
    return 1


def main(out: Stream) -> int:
    out.print(square(3))
    return 0
```

The call inside `square_of_three` and `main` is same-module, so `@deprecated`
reports nothing here; a caller in another module would see the warning.

## Docstrings

A string literal that is the first statement of a module or of a function body is
that declaration's docstring. Write it with the ordinary `"..."` or `'...'`
spelling, or with a triple-quoted `"""..."""` that spans lines; either way it is
inert, so it contributes no value, no binding and no effect, and the statements
after it behave exactly as they would without it. A string later in a body is not
a docstring and stays an ordinary standalone expression. A record, union, enum or
domain may document itself the same way, with the string as the first line of its
body.

`list-interfaces` prints a declaration's first docstring line after its
signature. `mylang lint`'s `undocumented-export` rule reports an exported
function, record, union or domain whose docstring is missing, is shorter than
`min_chars` non-whitespace characters (12 by default, configurable as the
top-level `lint.min_chars` key in `mylang.json`), or merely restates the
declaration's own name; it reports under the `agent` profile and blocks under
`strict` and `safety`.

```mylang
# doc: expect 14
def area(width: int, height: int) -> int effects():
    """The rectangle's area in square units.

    A docstring is inert, so this text never reaches the program.
    """
    return width * height


def main() -> int effects():
    return area(2, 7)
```

