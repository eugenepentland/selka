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

An annotated local may omit its initializer: `mut name: Type` or `const name: Type`.
Every path that reaches a read must first assign it; a loop may run zero times,
so assigning only inside a loop does not initialize it after the loop. A path
that returns or fails does not contribute to the assignment requirement.
A `const` is assigned exactly once on every path that reaches a read; assigning
a possibly assigned binding again, including on a repeating loop path, is rejected.
An unannotated binding still requires an initializer. Conditional and match
expressions are retired: use these statement forms to assign a named result,
or return directly in each arm. A migration may extract a selection from an
operand only when it preserves evaluation order; repeated loop conditions and
short-circuit branches require an explicit statement rewrite.

```selka
# doc: expect 42
func choose(flag: bool) -> int:
    const result: int
    if flag:
        result = 42
    else:
        result = 0
    return result

func main() -> int:
    return choose(True)
```

`name = value` initializes a definitely unassigned annotated binding or updates an
existing `mut` binding. It never creates a name, and
writing through a `const` binding, including its nested fields or arrays, is an
error. Ordinary data parameters are read-only unless declared `mut`.

Locals belong to their enclosing block. A declaration may not shadow an active
local or parameter. Loop variables and pattern bindings are read-only and
belong to the loop body or case body. A name declared inside a branch is not
available after the branch, even when every branch declares the same spelling.
Declare a writable value in the surrounding block when several branches or
iterations must update it. Reading a name outside its scope reports a name error;
reading an existing binding before it is definitely initialized is also rejected.

A `record` declares a value record with annotated fields and named
construction. Scalar-only records copy by value; a record containing owned
values can move. Use `copy(value)` to retain an independent original before changing
the new record or its managed fields, as [managed collections](managed-memory.md)
explains.

```selka
# doc: expect 42
record Tally:
    count: int
    seen: int[]

func main() -> int:
    mut first = Tally(count=2, seen=[])
    mut second = copy(first)
    second.count = 40
    append(mut second.seen, 7)
    if len(first.seen) != 0 or len(second.seen) != 1:
        return 1
    return second.count + first.count
```

`second.count = 40` leaves `first.count` at 2, and
`second.seen.append(7)` leaves `first.seen` empty. Both records preserve
independent values.

## Bind or else

`const source = read(path) else Err(message):` unwraps an Option or a Result and, when the value is the failing case, runs a
block that has to leave. It is for the exits `try` cannot spell: printing a diagnostic and returning a status, `continue`,
`break`, or returning a different value. The failing case is written after `else`: `Err(e)` or `Err(_)` for a Result,
`None` for an Option, and a bare `else:` for an Option's `None` (a Result spells `Err(_)`, so discarding an error stays visible).
A bare `else:` or `else None:` over a Result reports `E_PATTERN_PAYLOAD`, which says that the call can fail and names
both patterns, with a note at the called function; `selka fix` writes `else Err(_):`, which drops the failure as the
block already did.
`_ = check(path) else Err(e):` binds nothing, for a call whose payload is `Unit`. A statement that is only a call has no value
to bind, so `check(path) else Err(e):` is a syntax error that says what to write: `if check(path) is Err(e):` for a call that
gives nothing back (or `is None` for an Option), and `selka fix` makes that rewrite when the pattern is `Err(name)`, `Err(_)` or
`None`. The `else` unwraps the value into a new name, so an assignment to a name that already exists takes none:
`x = read(path) else Err(e):` is a syntax error that says to declare a new `const` with the `else` and assign it, or to write a
`match`. An assignment to a field or an element, `pax.size = read(path) else Err(e):`, gets the same refusal with the forms that do its job:
`const value = read(path) else Err(e):` and then `pax.size = value`, `pax.size = try read(path)` in a function that can fail (that
returns an Option, for an Option), or `if read(path) is Ok(value):` (`Some(value)`) with the assignment inside. Anything else after `else` reports
`E_ELSE_PATTERN`, a value that is neither an Option nor a Result `E_ELSE_OPERAND`, and an `else` block that can run
off its end `E_ELSE_FALLTHROUGH`: end it with `return`, `fail`, `break` or `continue`. To handle a failure and go on, which the block cannot do,
write `if CALL is Err(e):` (`is None` for an Option), or a `match` with an arm for each case; the message says so.

The declaration is a `match` underneath: the statements after it, to the end of the enclosing block, are the arm that
holds the payload, so the names and the ownership are a match's. `source` is visible from the next statement on, not in the
`else` block or in the expression, and the failure name `e` exists only in the `else` block. A call result moves its payload into
`source`; a named place stays borrowed until the last use of `source`, as `const alias = place` would, so a write to the place
after that use is accepted. `mut items = read(path) else Err(_):` (or a type annotation, `const items: int[] = ...`) takes
the payload over as a writable owner, which needs an owned source: a call result, or `copy(place)`. A `mut` over a borrowed
place is refused as `mut x = alias` is. Use `try` when the failure leaves unchanged: `const nodes = try parse(text)`. A bind-or-else whose `else` block is only `fail e` (or `return None`, in a function that returns an Option) draws the
warning `W_ELSE_IS_TRY`, and `selka fix` rewrites it to `try` ([idiom rewrites](tooling/lint.md#idiom-rewrites)). A two-arm
`match` over an Option or a Result whose `None` or `Err` arm leaves is this declaration written the long way: it draws
`W_MATCH_ELSE`, and `selka fix` writes the declaration with that arm's block, followed by the other arm's statements.

```selka
# doc: expect 9 -1 3
import filesystem


func read_size(fs: Filesystem, path: str) -> int:
    const body = fs.read_text(path) else Err(_):
        return -1
    return len(body)


func nonzero(n: int) -> int:
    const value = check(n) else:
        return 0
    return value + 1


func check(n: int) -> int?:
    if n == 0:
        return None
    return Some(n)


func main(out: Stream) -> int:
    mut fs = filesystem.memory()
    _ = fs.write_text("a.txt", "123456789")
    print(out, read_size(fs, "a.txt"), read_size(fs, "none.txt"), nonzero(2))
    return 0
```

```selka
# doc: expect-error E_ELSE_FALLTHROUGH
func first(n: int) -> int:
    const value = lookup(n) else:
        pass
    return value


func lookup(n: int) -> int?:
    if n == 0:
        return None
    return Some(n)


func main() -> int:
    return 0
```

## The discard name

`_` is the discard name. `_ = value` evaluates `value` and throws its result away, which a
result the program does not want (a `Result`, a count) must say with `_ =`; `_ = own value` also
gives a local away. Neither is a use that keeps a value alive: a value is destroyed after its
last real use, not at the end of its block, so a closing `_ = own value` does not hold it open.
A resource (a poller, a listener, a connection) that is only discarded at the end of a function
is closed after its last other use, which can be above a call that needs it
([when a value is destroyed](managed-memory.md#releasing-memory), and
[how to hold a listener open](standard-library.md#in-memory-network)). An unread `for` target
is written `_`. Because `_` names nothing worth keeping it never shadows: nested loops
may each bind it, `for _, _ in ...` binds nothing, and the outer `_` is visible
again once an inner scope that bound it ends. Every other loop variable is still
block-scoped and may not reuse the name of an active local, which the checker
reports as `E_SHADOWING`.

```selka
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
`E_INDENTATION`: "an expression continues on the next line only inside parentheses,
so a line ending in `+` ends there: write `(a +` ... `b)`". A backslash at the end
of a line does not continue it either; it reports `E_TOKEN` with the same advice.
`selka fix` writes the parentheses and removes the backslashes when the statement
is one expression after `return`, `if`, `elif`, `while` or an assignment. Module,
import, export and unbraced type declarations end at a newline under the same
rule, and the formatter preserves the boundaries it finds.

```selka
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
pays nothing and a failed one names the values it saw. Assertions are also available inside generic function bodies. The condition
and a failing message are ordinary expressions; any allocations they perform
are included in the Core `@noalloc` build assertion and lint checks. A possible
allocation fails `build`, `run` or `test` with `E_NOALLOC_ALLOCATES`. Use assertions for invariants a caller cannot
violate and a `Result` for errors it can.

```selka
# doc: expect 42
@noalloc
func scaled(value: int, factor: int) -> int:
    assert factor > 0
    assert value <= 100, "value must fit the table"
    return value * factor

func main() -> int:
    return scaled(21, 2)
```

An f-string message renders through the same formatter `print` uses:

```selka
# doc: expect 42
func half(value: int) -> int:
    assert value % 2 == 0, f"half needs an even value, got {value}"
    return value // 2

func main() -> int:
    return half(84)
```

Two texts joined with `+` are one text, so a message may say which value failed without a format string. The
message is one expression: the commas of a call's arguments stay inside the call, and a comma after the message is
`E_SYNTAX`, because an `assert` has a condition and a message and no third operand. A message of another type is
`E_TYPE`: write a format string to show a number.

```selka
# doc: expect 42
func place(slot: str, width: int) -> int:
    assert len(slot) <= width, "slot " + slot + " is wider than " + str(width)
    return len(slot) * 21

func main() -> int:
    return place("ab", 2)
```

A failing assertion prints the message, the offending line and the call stack,
and stops the program; it is a trap, not a catchable error.

## Booleans and conditions

`bool` is a distinct type with the two literals `True` and `False`, and it is the
only type a condition accepts. `if`, `elif`, `while` and
the operands of `and`, `or` and `not` all require it; an integer, a string or a
list in that position is rejected with `E_TYPE` and the message
`expected bool, found i64`, because there is no truthiness rule behind it. Write
the test out: `len(values) == 0` rather than `not values`, `value != 0` rather
than `if value`. `and` and `or` evaluate their right operand only when the left
one has not already decided the answer, so a guard written to the left of a call
genuinely prevents that call.

```selka
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
