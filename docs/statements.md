# Statements and bindings

A function body is a suite of statements over block-scoped locals, checked before
anything runs. This page covers the four things a statement can assume: how a name
comes into existence, where one statement ends and the next begins, how an
invariant is stated, and what a condition is allowed to be.
[Python-style application code](python-syntax.md) is the wider tour of the
surface, and [functions and calls](functions.md) covers the declarations these
statements live in.

## Assignments and value records

`name = value` declares a mutable local and infers its type from the right-hand
side; `name: T = value` annotates it when the value supplies nothing to infer
from, as an empty list or dictionary literal does. A local belongs to the block
that introduced it, so a name first assigned inside an `if` or a loop is gone at
the dedent and reading it afterwards reports `E_UNKNOWN_NAME`. Declare it before
the block when it has to survive; a nested block can reassign a local that
already exists. A `class` declares a value record with annotated fields and named
construction, and assigning a record copies its fields, so the copy's scalar
fields move independently of the original. That copy is shallow: a managed field
— a list, dictionary, string or record holding one — still refers to the same
object in both records, exactly as [managed collections](managed-memory.md)
behave everywhere else.

```mylang
# doc: expect 42
class Tally:
    count: int
    seen: list[int]

def main() -> int:
    first = Tally(count=2, seen=[])
    second = first
    second.count = 40
    second.seen.append(7)
    if len(first.seen) != 1:
        return 1
    return second.count + first.count
```

`second.count = 40` leaves `first.count` at 2, because the two records are
separate values. `second.seen.append(7)` is visible through `first.seen`, because
the two records point at one list.

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
literal instead; the message is a literal rather than an expression, and the
native backend raises the same `R_ASSERT` code without carrying it. Assertions
are permitted under every effect bound, including `noalloc` and `noio`, and
inside generic function bodies, because checking a condition contributes no
effect of its own. They are not removed in any build, so use them for invariants
a caller cannot violate and a `Result` for errors it can. `assert` is a keyword
only in the Python surface; legacy brace sources keep it as an ordinary
identifier.

```mylang
# doc: expect 42
def scaled(value: int, factor: int) -> int noalloc:
    assert factor > 0
    assert value <= 100, "value must fit the table"
    return value * factor

def main() -> int:
    return scaled(21, 2)
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
