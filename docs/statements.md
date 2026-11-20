# Statements and bindings

A function body is a suite of statements over block-scoped locals. This page covers how a name comes into existence,
where a statement ends, `assert`, and what a condition may be. See also [Python-style application code](python-syntax.md)
and [functions and calls](functions.md).

## Assignments and value records

`const name = value` introduces an immutable local and `mut name = value` a writable one. Both infer the type from the
initializer; annotate when needed: `mut points: Point[] = []`.

An annotated local may omit its initializer: `mut name: Type` or `const name: Type`.

- Every path that reaches a read must assign it first. A loop may run zero times, so assigning only inside a loop does not
  count; a path that returns or fails does not contribute.
- A `const` is assigned exactly once on every path that reaches a read.
- An unannotated binding needs an initializer. There are no conditional or match expressions: assign a named result in
  an `if` or `match` statement, or return in each arm.

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

`name = value` initializes a definitely unassigned annotated binding or updates a `mut` one; it never creates a name.
Writing through a `const`, including its nested fields, is an error. Data parameters are read-only unless `mut`.

Locals belong to their enclosing block:

- A declaration may not shadow an active local or parameter.
- Loop variables and pattern bindings are read-only and live in their body.
- A name declared inside a branch is not available after it. Declare a writable value in the surrounding block when
  several branches or iterations must update it.

A `record` is a value record with annotated fields and named construction. Scalar-only records copy by value; a record
with owned values can move. `copy(value)` keeps an independent original ([managed collections](managed-memory.md)).

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

## Bind or else

`const source = read(path) else Err(message):` unwraps an Option or a Result and, on the failing case, runs a block that
has to leave: for the exits `try` cannot spell (print and return a status, `continue`, `break`).
Write the failing case after `else`: `Err(e)` or `Err(_)` for a Result, `None` or a bare `else:` for an Option.
`_ = check(path) else Err(e):` binds nothing, for a payload of `Unit`.

`source` is visible from the next statement on, not in the `else` block; `e` exists only in the `else` block. A call
result moves its payload into `source`; a named place stays borrowed until the last use of `source`.
`mut items = read(path) else Err(_):` needs an owned source (a call result or `copy(place)`). Use `try` when the failure
leaves unchanged: `const nodes = try parse(text)`.

| You write | The compiler says |
| --- | --- |
| bare `else:` or `else None:` over a Result | `E_PATTERN_PAYLOAD`; `selka fix` writes `else Err(_):` |
| `check(path) else Err(e):` as a bare call statement | syntax error; write `if check(path) is Err(e):` (`selka fix` does) |
| `x = read(path) else Err(e):`, or an assignment to a field | syntax error; declare a new `const` with the `else`, then assign it |
| anything else after `else` | `E_ELSE_PATTERN` |
| a value that is neither Option nor Result | `E_ELSE_OPERAND` |
| an `else` block that can run off its end | `E_ELSE_FALLTHROUGH`; end it with `return`, `fail`, `break` or `continue` |
| an `else` block that is only `fail e` (or `return None`) | `W_ELSE_IS_TRY`; `selka fix` writes `try` ([idiom rewrites](tooling/lint.md#idiom-rewrites)) |
| a two-arm `match` whose `None` or `Err` arm leaves | `W_MATCH_ELSE`; `selka fix` writes the declaration |

To handle a failure and go on, write `if CALL is Err(e):` (`is None` for an Option) or a `match`.

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

## The discard name

`_ = value` evaluates `value` and throws its result away; an unwanted result (a `Result`, a count) must say so with
`_ =`. `_ = own value` also gives a local away. Neither keeps a value alive: a value is destroyed after its last real use
([when a value is destroyed](managed-memory.md#releasing-memory); [holding a listener open](standard-library.md#in-memory-network)).

An unread `for` target is written `_`. It never shadows: nested loops may each bind it, and `for _, _ in ...` binds
nothing. Every other loop variable may not reuse an active name (`E_SHADOWING`).

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

A statement ends at its newline; semicolons are rejected. An expression continues across a line break only inside
brackets (parentheses, a list or dictionary literal, a call's arguments, a subscript).

- A dangling binary operator at the end of an unbracketed line reports `E_INDENTATION`: write `(a +` ... `b)`.
- A backslash at the end of a line reports `E_TOKEN` with the same advice.
- `selka fix` adds the parentheses and removes the backslashes for one expression after `return`, `if`, `elif`, `while`
  or an assignment.

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

`assert condition` traps with `R_ASSERT` when false, reporting the expression's source text and location.
`assert condition, "message"` reports the message instead. The message may be any `str` expression, including an f-string;
it is evaluated only when the condition is false. A comma after the message is `E_SYNTAX`; a message of another type is
`E_TYPE` (use a format string to show a number).

An allocation in the condition or message fails `@noalloc` code with `E_NOALLOC_ALLOCATES`. A failing assertion prints
the message, the line and the call stack and stops the program: a trap, not a catchable error. Use assertions for
invariants a caller cannot violate and a `Result` for errors it can.

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

## Booleans and conditions

`bool` is a distinct type with the literals `True` and `False`, and the only type a condition accepts. `if`, `elif`,
`while` and the operands of `and`, `or` and `not` require it; an integer, string or list there is `E_TYPE`
(`expected bool, found i64`). Write `len(values) == 0` rather than `not values`. `and` and `or` evaluate their right
operand only when the left has not decided the answer, so a guard on the left prevents the call on the right.

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

`print` renders the values as `True` and `False` ([printing](io.md)).
