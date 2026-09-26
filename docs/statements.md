# Statements and bindings

A function body is a suite of statements over function-scoped locals, checked before
anything runs. This page covers the four things a statement can assume: how a name
comes into existence, where one statement ends and the next begins, how an
invariant is stated, and what a condition is allowed to be.
[Python-style application code](python-syntax.md) is the wider tour of the
surface, and [functions and calls](functions.md) covers the declarations these
statements live in.

## Assignments and value records

`name = value` declares a mutable local and infers its type from the right-hand
side; `name: T = value` annotates it when the value supplies nothing to infer
from, as an empty list or dictionary literal does. Locals are function-scoped,
like Python: an assignment to a name anywhere in the body is one binding, in scope
from its first assignment to the end of the function, and a nested block
reassigns the same binding rather than shadowing it. Its type is fixed at the
first assignment. Reading a name on a control-flow path that may not have assigned
it — the branch of an `if` with no matching `else`, for instance — is rejected
with `E_UNBOUND`; a name never assigned before the read is still `E_UNKNOWN_NAME`.
Because every `for` or `while` loop may execute zero times, an assignment made only
in the loop body does not bind the name after the loop; predeclare it before the
loop when it is read afterward. An assignment in every continuing `if`/`elif`/`else`
branch does bind the name afterwards. The `for` loop variable itself, a `match`
payload binding, and a move-only resource stay scoped to their own block; the
loop rebinds its variable at the top of every iteration, so assigning it in the
body never changes which iteration comes next. A `record` declares a value record with annotated fields and named
construction, and assigning a record copies its fields, so the copy's scalar
fields move independently of the original. Managed fields are independent
values too; the runtime can share their backing storage until a write, as
[managed collections](managed-memory.md) explains.

```mylang
# doc: expect 42
record Tally:
    count: int
    seen: list[int]

def main() -> int:
    first = Tally(count=2, seen=[])
    second = first
    second.count = 40
    second.seen.append(7)
    if len(first.seen) != 0 or len(second.seen) != 1:
        return 1
    return second.count + first.count
```

`second.count = 40` leaves `first.count` at 2, and
`second.seen.append(7)` leaves `first.seen` empty. Both records preserve
independent values.

## Statement endings

A statement ends at the end of its line. Semicolons are never required and new
code should omit them, but a semicolon still separates two statements written on
one line, which is the only place one is needed. An expression continues across a
line break only inside brackets — parentheses, a list or dictionary literal, a
call's argument list, a subscript — because the Python surface takes its structure
from indentation. A binary operator left dangling at the end of an unbracketed
line does not continue the expression, and the indented line that follows reports
`E_INDENTATION`. Module, import, export and unbraced type declarations end at a
newline under the same rule, and the formatter preserves the boundaries it finds.

```mylang
# doc: expect 42
def main() -> int:
    width = 6; height = 7
    area = (width
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
def scaled(value: int, factor: int) -> int noalloc:
    assert factor > 0
    assert value <= 100, "value must fit the table"
    return value * factor

def main() -> int:
    return scaled(21, 2)
```

An f-string message renders through the same formatter `print` uses:

```mylang
# doc: expect 42
def half(value: int) -> int:
    assert value % 2 == 0, f"half needs an even value, got {value}"
    return value // 2

def main() -> int:
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
def divides(value: int, divisor: int) -> bool:
    return value % divisor == 0

def main() -> int:
    total = 0
    ready = True
    if ready and not divides(7, 2):
        total += 40
    empty: list[int] = []
    if len(empty) == 0 or divides(7, 0):
        total += 2
    return total
```

`divides(7, 0)` would trap on the zero divisor, and `or` never reaches it.
`print` renders the two values as `True` and `False`; see
[printing, files and command-line authority](io.md).
