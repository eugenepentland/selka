# Statements and bindings

A function body is a suite of statements over block-scoped locals, checked before
anything runs. This page covers the four things a statement can assume: how a name
comes into existence, where one statement ends and the next begins, how an
invariant is stated, and what a condition is allowed to be.
[Python-style application code](python-syntax.md) is the wider tour of the
surface, and [functions and calls](functions.md) covers the declarations these
statements live in.

## Assignments and value records

`const name = value` introduces an immutable local. `mut name = value`
introduces a writable local. Both infer the type from the initializer; add an
annotation when needed, such as `mut points: Point[] = []`. A local `const`
initializer runs normally at runtime.

`name = value` updates an existing `mut` binding. It never creates a name, and
writing through a `const` binding, including its nested fields or arrays, is an
error. Ordinary data parameters are read-only unless declared `mut`.

Locals belong to their enclosing block. A declaration may not shadow an active
local or parameter. Loop variables and pattern bindings are read-only and
belong to the loop body or case body. A name declared inside a branch is not
available after the branch, even when every branch declares the same spelling.
Declare a writable value in the surrounding block when several branches or
iterations must update it, or use a conditional or match expression to choose
one immutable value. Reading a name outside its scope reports a name error;
reading an existing binding before it is definitely initialized is also rejected.

A `record` declares a value record with annotated fields and named
construction, and assigning a record copies its fields, so the copy's scalar
fields move independently of the original. Managed fields are independent
values too; the runtime can share their backing storage until a write, as
[managed collections](managed-memory.md) explains.

```mylang
# doc: expect 42
record Tally:
    count: int
    seen: int[]

func main() -> int:
    mut first = Tally(count=2, seen=[])
    mut second = first
    second.count = 40
    second.seen.append(7)
    if len(first.seen) != 0 or len(second.seen) != 1:
        return 1
    return second.count + first.count
```

`second.count = 40` leaves `first.count` at 2, and
`second.seen.append(7)` leaves `first.seen` empty. Both records preserve
independent values.

## The discard name

`_` is the discard name. `_ = value` drops a value, `a, _ = pair` skips a tuple
element, and a `for` target or comprehension element that the body never reads is
written `_`. Because `_` names nothing worth keeping it never shadows: nested loops
may each bind it, `for _, _ in ...` binds nothing, and the outer `_` is visible
again once an inner scope that bound it ends. Every other loop variable is still
block-scoped and may not reuse the name of an active local, which the checker
reports as `E_SHADOWING`.

```mylang
# doc: expect 42
func main() -> int:
    mut total = 0
    for _ in range(2):
        for _ in range(3):
            total += 7
    return total
```

## Statement endings

A statement ends at its newline. Semicolon-separated statements are rejected;
write each statement on its own line. An expression continues across a
line break only inside brackets — parentheses, a list or dictionary literal, a
call's argument list, a subscript — because the Python surface takes its structure
from indentation. A binary operator left dangling at the end of an unbracketed
line does not continue the expression, and the indented line that follows reports
`E_INDENTATION`. Module, import, export and unbraced type declarations end at a
newline under the same rule, and the formatter preserves the boundaries it finds.

```mylang
# doc: expect 42
func main() -> int:
    mut width = 6
    mut height = 7
    mut area = (width
        * height)
    return area
```

## Assert statements

`assert condition` checks a Boolean expression and traps with `R_ASSERT` when it
is false, reporting the expression's own source text as the message and the
location of that expression. `assert condition, "message"` reports the string
literal instead; the native backend carries it into the located `R_ASSERT`
diagnostic. The message may also be any `str` expression, including an f-string:
it is evaluated only when the condition is false, and its rendered text is
written to standard error immediately before the trap, so a passing assertion
pays nothing and a failed one names the values it saw. Assertions themselves
are permitted under every effect bound, including `noalloc` and `noio`, and
inside generic function bodies, because checking a condition contributes no
effect of its own. A literal message stays free of effects; an allocating
message is an ordinary expression, so under `noalloc` or `effects()` it is
rejected with `E_EFFECT_BOUND`. Use assertions for invariants a caller cannot
violate and a `Result` for errors it can.

```mylang
# doc: expect 42
func scaled(value: int, factor: int) -> int noalloc:
    assert factor > 0
    assert value <= 100, "value must fit the table"
    return value * factor

func main() -> int:
    return scaled(21, 2)
```

An f-string message renders through the same formatter `print` uses:

```mylang
# doc: expect 42
func half(value: int) -> int:
    assert value % 2 == 0, f"half needs an even value, got {value}"
    return value // 2

func main() -> int:
    return half(84)
```

A failing assertion prints the message, the offending line and the call stack,
and stops the program; it is a trap, not a catchable error.

## Booleans and conditions

`bool` is a distinct type with the two literals `True` and `False`, and it is the
only type a condition accepts. `if`, `elif`, `while`, a comprehension filter and
the operands of `and`, `or` and `not` all require it; an integer, a string or a
list in that position is rejected with `E_TYPE` and the message
`expected bool, found i64`, because there is no truthiness rule behind it. Write
the test out: `len(values) == 0` rather than `not values`, `value != 0` rather
than `if value`. `and` and `or` evaluate their right operand only when the left
one has not already decided the answer, so a guard written to the left of a call
genuinely prevents that call.

```mylang
# doc: expect 42
func divides(value: int, divisor: int) -> bool:
    return value % divisor == 0

func main() -> int:
    mut total = 0
    mut ready = True
    if ready and not divides(7, 2):
        total += 40
    mut empty: int[] = []
    if len(empty) == 0 or divides(7, 0):
        total += 2
    return total
```

`divides(7, 0)` would trap on the zero divisor, and `or` never reaches it.
`print` renders the two values as `True` and `False`; see
[printing, files and command-line authority](io.md).
