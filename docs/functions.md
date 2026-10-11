# Functions and calls

`func` declares every callable in the language. There are no methods, no
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
default's declared type is checked even in a function nothing calls. Intrinsics such as `len` have their own argument rules. A callable type may
include `named` labels; calls through the value honor those labels and its exact
`mut` parameter positions.

```mylang
# doc: expect 42
func offset(value: int, amount: int = 2, scale: int = 1) -> int:
    return value * scale + amount

func main() -> int:
    mut plain = offset(38)
    mut keyword = offset(amount=2, value=38)
    if plain != keyword:
        return 1
    return plain + offset(0, scale=2)
```

Record construction reads the same way — `Point(x=1, y=2)` binds fields by name
through the same rules — and generic calls infer their type arguments from the
values they are given unless the [explicit
list](#explicit-call-type-arguments) is written out.

### Keyword-only parameters

Mark each parameter that requires a label with `named`: `named amount: int`.
Positional parameters come first, then named parameters. Repeat the modifier for
each named parameter; a bare `*` separator is not part of the canonical grammar.
Named parameters may be supplied in any order. Required and defaulted named
parameters may appear in either order, while positional parameters retain the
required-before-defaulted rule. Arguments evaluate once in their written order.
A missing label reports `E_KEYWORD_ONLY` with the labelled call.

Combine permissions as `named mut points: Point[]` and call it with
`points=mut points`. The name and mutation permission are both part of the contract.

```mylang
# doc: expect 1204
func issue(host: int, named code: int, named file: int = 0, named position: int = 4) -> int:
    return host * 1000 + code * 100 + file * 10 + position


func main() -> int:
    mut written = issue(1, position=4, code=2)
    mut defaulted = issue(1, code=2)
    if written != defaulted:
        return 0
    return written
```

So `io.issue(host, 13, 0, span.start)` reports
`` `code` is keyword-only; write `io.issue(host, code=13, file=0, position=span.start)` ``.
Rendered interfaces repeat `named` and prefix `mut` so a reader can see the
same call contract as in the source declaration.

### Wide signatures

A function may take any number of scalar parameters (`int`, `float`, `bool` and the
other fixed-width numbers). A list, string, record or other aggregate parameter must be
one of its first 64 parameters, because the checker tracks which inputs a written or
returned value may come from by position; a later one is `E_PARAMETER_POSITION`. Move
it earlier, or group related parameters into a record and pass that.

## Unit procedures

A procedure produces `Unit`. Write `-> Unit` or omit the return annotation.
`Unit` is a builtin scalar type name, like `int` and `bool`; choose a different
name for an application record, because a nominal declaration cannot override
its meaning in type annotations.
The unit value is `()`. Falling off the body or a bare `return` succeeds with
unit, and ordinary cleanup runs on both paths. A fallible procedure writes
`func save(...) fails SaveError:` and uses `fail error` for failure.

A standalone call statement must produce unit. Use `_ = work(...)` to explicitly
discard an ordinary non-unit result; checked results still require handling.
Unit flows through generic functions, callbacks, bindings and result payloads.
`try save(...)` propagates a fallible procedure's error at a statement boundary.
Unit remains unsuitable for ordinary wire data and has its existing C ABI rules.

```mylang
# doc: expect 42
func bump(mut values: int[]):
    values.append(0)

func add(mut values: int[], value: int) -> Unit:
    if value < 0:
        return
    values.append(value)

func main() -> int:
    mut values: int[] = []
    add(mut values, 40)
    add(mut values, -1)
    add(mut values, 2)
    bump(mut values)
    mut total = 0
    for value in values:
        total += value
    return total
```

`add` returns early for the negative value, `bump` falls off the end, and neither
needs a return annotation to say so. Both write through `values`, so both declare
`mut values: int[]` and every caller marks the argument.

## Entry point signatures

`main` may return `int`, `Unit`, `int fails E`, or unit with `fails E`.
A successful integer becomes the process exit status, truncated to its low eight
bits; successful unit exits zero. An integer error supplies its status, and
another error exits one. Errors are printed to standard error with their
[error return trace](results-and-options.md#error-return-traces).
`mylang run --print-result` additionally prints a successful integer.
Capability parameters remain available on the entry point; runtime arguments
use the existing command conventions.

```mylang
# doc: expect 42
func parse(value: int) -> int fails int:
    if value < 0:
        fail 2
    return value

func main() -> int fails int:
    mut first = try parse(40)
    mut second = try parse(2)
    return first + second
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
func identity[T](value: T) -> T:
    return value

record Box[T]:
    item: T

func main() -> int:
    mut explicit = identity[int](2)
    mut inferred = identity(40)
    mut boxed = Box[int](item=0)
    return explicit + inferred + boxed.item
```

## Function values

The name of a declared function, written without a call, is a function value. Its
type is spelled `func(parameters) -> result effects(...)`, with the parameter
types, the result type and the effect ceiling all written out, and a value of
that type can be stored in a local, passed as an argument and returned. A
function value captures nothing. There are no closures and no nested `func`, so
the value is an immediate function identity and everything it needs arrives
through its parameters; an attempt to capture the enclosing environment is
rejected rather than boxed. Function values are ordinary copied values with no
ownership of their own, and a call through one validates the target and keeps the
ordinary result and ownership obligations. They have no rendering, so passing one
to `print` is rejected with `E_IO_ARGUMENT`.

```mylang
# doc: expect 42
func double(value: int) -> int effects():
    return value * 2

func chosen() -> func(int) -> int effects():
    return double

func apply(callback: func(int) -> int effects(), value: int) -> int:
    return callback(value)

func main() -> int:
    mut op = chosen()
    return apply(op, 18) + op(3)
```

## Function identity

`same_function(left, right)` compares two compatible function values without
calling them. It returns `True` for the same callable and `False` for different
callables. Passing values with different call signatures, or a non-function,
is a type error. The comparison itself contributes no effects.

This identity lasts only within the running program. It is useful for separating
entries in an application memo cache. It supplies no persistent code digest:
after recompilation or process restart, persistent reuse needs validated
implementation, dependency, argument and result-schema identities.

```mylang
# doc: expect 42
func increment(value: int) -> int effects():
    return value + 1

func decrement(value: int) -> int effects():
    return value - 1

func main() -> int:
    const chosen = increment
    if not same_function(chosen, increment):
        return 1
    if same_function(chosen, decrement):
        return 2
    return 42
```

## Bounded callbacks

A parameter that accepts a function value declares the destination signature
and effect ceiling. Parameter and result types stay invariant, but the
implementation's declared effect ceiling may be a subset of the destination's:
a pure callback may fill an `effects(output)` slot, while a callback that may
print may not fill an `effects()` slot. Rejected substitutions report `E_TYPE`
with both canonical source contracts and named effects; a rejected substitution
reads `expected func(int) -> int effects(), found func(int) -> int effects(output)`.
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
func announce(value: int, out: Stream) -> int effects(output):
    out.print(value)
    return value

func sum_announced(values: int[], report: func(int, Stream) -> int effects(output), out: Stream) -> int effects(output):
    mut total = 0
    for value in values:
        total += report(value, out)
    return total

func main(out: Stream) -> int:
    out.print(sum_announced([40, 2], announce, out))
    return 0
```

`sum_announced` carries `effects(output)` because calling `report` can print. Had
it been written `noio`, or with an empty `effects()`, the declaration would be
rejected before the program ran.

A function declared without an effect clause takes the ceiling of whatever slot
it fills — a direct call's parameter, a generic call's parameter such as
`sort.sort_by_key`'s key, or a sort key — so it needs no `effects()` of its own to
be passed where one is expected. Its body is then held to that ceiling: an
unannotated function whose body can print, touch the filesystem or reach any other
effect the slot forbids — including allocation for an `effects()` slot — is rejected
with `E_EFFECT_BOUND` at the place the value is passed. A sort key may allocate: its
slot is `func(T) -> K effects(managed_allocation)`.

```mylang
# doc: expect 3
import sort

func negate(value: int) -> int:
    return 0 - value

func main() -> int:
    mut ordered = sort.sort_by_key([1, 3, 2], negate)
    return ordered[0]
```

## Mutating callbacks

A callable signature declares the `mut` parameters it writes just as a declared
function does, and a call through the value substitutes the actual argument
origin, so the caller still needs permission for the mutation:

```mylang
# doc: expect 7
func apply(mut values: int[], f: func(mut values: int[]) -> Unit effects(mutation)) -> Unit effects(mutation):
    f(mut values)


func set_first(mut values: int[]) -> Unit effects(mutation):
    values[0] = 7


func main(out: Stream) -> int effects(managed_allocation, output):
    mut values = [1]
    apply(mut values, set_first)
    out.print(values[0])
    return 0
```

A positional binder name is a documentation label. A `named` binder requires
that call label, and its name participates in callable identity. An implementation may write fewer inputs than the
destination footprint permits, and a call through a stored or returned callback
uses the destination's footprint just as it uses the destination's effect ceiling.
A call through a function value follows the same exclusivity rule as a direct
call: its `mut` arguments must name disjoint places, so `f(mut xs, mut xs)` is
`E_MUTATION_OVERLAP` there too
([value semantics](value-semantics.md#the-rules)).

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
func square(x: int) -> int effects():
    return x * x


@test
func square_of_three() -> bool effects():
    return square(3) == 9


@allow("dead-private", reason="kept for the doctest example")
func helper() -> int effects():
    return 1


func main(out: Stream) -> int:
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
func area(width: int, height: int) -> int effects():
    """The rectangle's area in square units.

    A docstring is inert, so this text never reaches the program.
    """
    return width * height


func main() -> int effects():
    return area(2, 7)
```

## Persistent function identity

`function_digest(callback) -> str` returns a compiler-issued identity for the
actual callable, its reachable implementation and source schemas, and relevant
compiler, runtime, toolchain, target and build settings. It contributes managed
allocation. It does not invoke the callback. A same-name function or a manually
chosen version string cannot substitute for this identity.

```mylang
# doc: expect 42
func next(value: int) -> int effects():
    return value + 1

func main() -> int:
    const identity = function_digest(next)
    if len(identity) != 64:
        return 1
    if identity != function_digest(next):
        return 2
    return 42
```

An empty string means the compiler cannot establish complete persistent
authority, including unsupported external linking or an unqualified tool.
Consumers must execute without persistent reuse or reject the durable request.
Unknown indirect targets conservatively widen dependencies. Compiler and
execution-context changes can invalidate all identities; this favors correctness
over retaining results across an unqualified migration. Pure callback signatures
remain a separate requirement: an identity alone does not make effects replayable.

Tests that reach `function_digest` execute fresh rather than reuse an individual
test receipt. The query can observe broader compilation dependencies than the
ordinary rooted test key represents. Ordinary tests retain their existing reuse;
application `persistent_memo` and `durable` still use the qualified identities.
