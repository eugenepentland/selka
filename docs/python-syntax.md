# The language

This is the language guide. There is one syntax: `def`, `record`, indentation and
`#` comments. The compiler checks types before execution and manages ordinary
lists, strings and dictionaries by reference counting with copy-on-write; there is
no garbage collector to tune. There are no allocator arguments
or ownership annotations in ordinary data code.

A file that opens with `module NAME` is a project entry. `mylang run` loads its
reachable imports itself, so one file can use the standard library without
switching commands:

```mylang
# doc: expect 42
module main
import math

def main() -> int:
    return math.clamp(99, 0, 42)
```

Save this as `main.my`, then run `zig-out/bin/mylang run main.my --print-result`.
It prints `42`; without that flag `run` prints only what the program prints
itself. `run-project` remains the explicit alias for a project entry, and a file
with no module header is still one standalone unit.

Here is the same single-file shape with ordinary records and a list:

```mylang
# doc: expect 42
record Node:
    value: int
    children: list[Node]

def main() -> int:
    nodes = [Node(value=40, children=[])]
    nodes.append(Node(value=2, children=[]))
    total = 0
    for node in nodes:
        total = total + node.value
    return total
```

Save it as `main.my` too; `check` type-checks either file without building. The
[named-constraints project](../examples/named-constraints/main.my) is a larger
example: several modules, a generic contract and a test entry
(`fake_tests.my`).

Write `def`, `record`, four-space indentation, `#` comments, `True`, `False`,
`None`, and `and`/`or`/`not`. A statement ends at its newline; a `;` separates two
statements written on one line, as it does in Python. Parenthesized expressions and
collection literals may continue across lines. Tabs in indentation are rejected.
`pass` represents an empty suite. An omitted function return annotation means
`None`; functions may end naturally or use bare `return`.

Fixed-width conversions read like the numeric ones: `i64(x)`, `u8(x)` and their
siblings convert with a runtime range check, as `int(x)` and `float(x)` do between
`int`, `float` and `str`. Explicit type arguments are always square: `f[T](x)`,
`Box[int](value=1)`, `todo[int]()`, `wrap[Metres](n)`.

Assignments create mutable bindings and infer their types. An annotation is
needed when inference is ambiguous: `children: list[Node] = []` or
`counts: dict[str, int] = {}`. Function parameters, record fields, and non-unit
return types are annotated. The compiler remains statically typed; reassigning
an `int` local to a string is an error.

Declared functions accept positional and keyword arguments, including defaults:

```python
def offset(value: int, amount: int = 2) -> int:
    return value + amount

# offset(value=40) returns 42
```

Arguments evaluate once in their written order, even when keywords reorder the
parameters. Defaults must be immutable numeric, boolean, string, or `None`
literals; mutable collection defaults are rejected. Required parameters precede
those with defaults. Intrinsics and callback values require positional arguments.

`int` is a checked signed 64-bit integer. Fixed-width `u8` through `u64` and
`i8` through `i64` remain available for binary formats and host interfaces.
Representable unsuffixed integer literals adopt an expected integer type, in a `const`
initializer as in a typed local. Integer literals take Python's spellings (`0xFF`, `0o17`,
`0b1010`, `1_000`, and a width suffix as in `0xFFu8`), described in
[integer literal spellings](integer-operations.md#integer-literal-spellings).
`float` is binary64 and accepts literals such as `1.5`, `.5`, `5.`, `1_000.5` and `4.2e1`, ordinary
arithmetic and comparisons, and `float(integer)` / `int(float)` conversion.
`/` produces a float; `//` rounds the quotient down and `%` follows that quotient.
`divtrunc(a, b)` and `remtrunc(a, b)` round toward zero instead, for binary formats and
C interfaces that need that rounding. Float-to-int conversion truncates toward zero and
traps outside the signed range. `sqrt`, `floor`, `ceil`, `trunc` and `abs` operate on
`float` values, and `round` is a [prelude builtin](#prelude-builtins); `exp`, `log`
and the trigonometric functions are not provided.

```mylang
# doc: expect 42
def main() -> int:
    spread = -7
    floored = spread // 2
    toward_zero = divtrunc(spread, 2)
    return (toward_zero - floored) * 42
```

### Operators Python has

Comparisons chain: `==`, `!=`, `<`, `<=`, `>` and `>=` share one precedence
level, and `low <= x < high` means `low <= x and x < high`, with each operand
evaluated once, left to right, and the rest skipped once a link is false. `str`
and `bytes` [order lexicographically](text.md#ordering-and-repetition), and `*`
repeats a `str`, `bytes` or list by an integer.

On integers `|`, `^` and `&` are bitwise or, xor and and, ranked as Python ranks
them: below the operands of a comparison and above `+` and `-`, with `|` the
loosest and `&` the tightest, so `1 | 2 ^ 3 & 1` is `1 | (2 ^ (3 & 1))`. On two
[sets](sets.md#set-operators) of one type the same operators and `-` are union, symmetric
difference, intersection and difference.

```mylang
# doc: expect 42
def main() -> int:
    flags = 6 | 1
    mask = 12 & 10
    if 1 | 2 ^ 3 & 1 != 3 or (5 ^ 3) != 6:
        return 1
    return flags * mask - 14
```

```mylang
# doc: expect 42
def main() -> int:
    x = 5
    if not (0 < x < 10 and 1 <= x <= 5 and x == 5 != 6):
        return 1
    if not ("abc" < "abd") or "ab" * 2 != "abab":
        return 3
    return 42
```

`**`, `<<` and `>>` are not operators: write a multiplication loop (or
`math.pow(x, n)` for a `float`) and `shift_left(value, count)` /
`shift_right(value, count)`. Each rejection names that alternative.

Lists infer a homogeneous element type from nonempty literals. They share mutable
storage; assignment does not copy their contents. Use `items.append(value)`,
`len(items)`, `items[index]`, `items[index] = value`, and `items[start:end]`.
Negative indexes count from the end. Slices create independent list storage and
copy the selected elements. Nested indexing and expression receivers work.

Strings use ordinary single or double quotes and represent immutable UTF-8 text.
Indexing and length count Unicode scalar values, rather than bytes or grapheme
clusters. Use concatenation, equality, `split(separator)`, `separator.join(parts)`,
and `str(value)` for scalar conversion. Strings also support slices and iteration. `b"..."` represents bytes for binary APIs.

Strings answer `strip`/`lstrip`/`rstrip`, `upper`/`lower`, `replace(old, new)`,
`startswith`/`endswith`, `find(sub)` (-1 when absent), `count(sub)`, `zfill(width)`,
`splitlines()`, and `isdigit`/`isalpha`/`isspace`. Every one returns a fresh value, so no
alias changes. `ljust` and `rjust` are absent, because intrinsic methods take no defaulted
arguments. `int(text)` and `float(text)` return `Option[int]` and `Option[float]`: the
language has no exceptions, so a string that is not exactly one number answers `None`.

An `f"..."` literal interpolates `{expression}` holes, converting each one exactly as
`str(value)` does and concatenating the result. `{{` and `}}` write single braces. A hole
may end in a CPython [format specification](text.md#format-specifications) —
`f"{price:.2f}"`, `f"{n:05d}"`, `f"{name:>8}"`, `f"{total:,}"` — which renders exactly
as CPython does.

```mylang
# doc: expect 42
def label(count: int, items: list[int]) -> str:
    return f"total {count} of {len(items)}"

def main() -> int:
    if label(7, [1, 2, 3]) == "total 7 of 3":
        return 42
    return 0
```

Dictionaries preserve insertion order and take any
[hashable](sets.md#hashable-keys) key: an integer, `bool`, `str`, `bytes`, or a
tuple, record, union, enum or `Option` built from those. Their values
have a single inferred or annotated type. Updates through an alias are shared.
Use `counts[key]`, `counts[key] = value`, `counts.get(key, fallback)`,
`counts.keys()`, `counts.values()` and `counts.items()`. These return ephemeral typed
views for direct loops and immediate `len`, `in`, `list`, `set` and `sorted`.
Use `kept = list(counts.values())` to store an independent snapshot; storing
a view itself is `E_VIEW_STORED`. View types are also rejected in parameter,
return, field and collection element annotations, including unused generic
declarations; use a list type for a snapshot. Items yield records with `key` and `value`
fields and support `for key, value in counts.items()`.
`key in counts`, `value in items`, and `substring in text` support `not in` too.
Iterating a dictionary visits keys in insertion order; changing its size during
iteration traps. The [word-count example](../examples/python-word-count/main.my)
puts these operations together.

`[value for name in items if condition]` builds a list in one pass, with the filter
optional and the binding confined to the comprehension. The source is a list, string,
dictionary or an integer `range(...)` — `[i for i in range(10)]` and
`[i for i in range(10, 0, -2)]` work the same as they do in a `for` loop. Without a filter, the result reserves the source length (or
the exact nonnegative range length) before filling; filtered results grow with the
values they retain. A comprehension may also take two names, several `for` clauses
and several `if` filters, which nest left to right as Python reads them: each clause
accepts exactly what a `for` loop accepts, `enumerate`, `zip` and
`for k, v in d.items()` included.
The set comprehension `{value for name in items if condition}` builds a
[set](sets.md#set-literals-and-construction) the same way.

```mylang
# doc: expect 42
def main() -> int:
    source = [1, 2, 3, 4]
    kept = [value * 7 for value in source if value > 2]
    grid = [[1, 2], [3, 4]]
    flat = [x for row in grid for x in row if x % 2 == 0]
    return kept[0] + kept[1] - 7 + flat[1] - flat[0] - 2
```

### Dict and set comprehensions

`{key: value for name in source if condition}` builds a dictionary and
`{value for name in source}` a set, through the same clauses a list comprehension
takes. The key is evaluated before the value, and a repeated key keeps its first
position and its last value. An annotated destination gives the key, value or
element type to the literals inside: `small: dict[str, u8] = {k: 0 for k in names}`.

```mylang
# doc: expect 42
def main() -> int:
    prices = {"pear": 3, "fig": 5, "kiwi": 2}
    doubled = {name: price * 2 for name, price in prices.items() if price > 2}
    squares = {x: x * x for x in range(5)}
    paired = {k: v for k, v in zip(["a", "b"], [10, 20])}
    return doubled["fig"] + squares[4] + paired["a"] + len({c for c in "hello"}) + 2
```

### Generator expressions

A generator expression is accepted where Python programs pass one: as the only
argument of `sum`, `any`, `all`, `min`, `max`, `sorted`, `list`, `set`, `dict` or
`str.join` — `sum(x * x for x in xs)` — or in its own parentheses beside other
arguments, `sorted((x for x in xs), reverse=True)`. `sum`, `any`, `all`, `min` and
`max` fold each value as the loop produces it, with no intermediate list; `any` and
`all` stop at the first value that decides them, exactly as Python stops. `sorted`,
`list` and `str.join` receive the list the loop builds, `set` its set, and `dict`
the dictionary of its `(key, value)` tuples. `min` and `max` of no values trap with
CPython's message, and `sum` starts from zero of the value's type.

```mylang
# doc: expect 42
def main() -> int:
    xs = [4, 1, 3]
    if not any(x > 3 for x in xs) or all(x > 1 for x in xs):
        return 1
    ordered = sorted(x * 10 for x in xs)
    text = "-".join(str(x) for x in xs)
    return sum(x * x for x in xs) + max(x for x in xs) + ordered[0] + len(text) - 3
```

A generator anywhere else — stored in a variable, passed to a function you
declared, or given to `len` — is `E_GENERATOR`, whose note names the list
comprehension to write instead; count with `sum(1 for x in xs if p)`.

```mylang
# doc: expect-error E_GENERATOR
def main() -> int:
    squares = (x * x for x in [1, 2, 3])
    return 0
```

`for value in items`, `for index, value in enumerate(items)`, and
`for index in range(end)` / `range(start, end)` / `range(start, end, step)` support
`break` and `continue`. A [stepped range](range-iteration.md#stepped-ranges) counts
down for a negative step.
Iteration over a place reads its current value on every step. Element writes and
`mut` callee updates stay visible even when another variable holds a copy. A live
list accepts growth; a decrease from its last observed length traps
`R_LIST_ITERATION_MUTATION`. Dictionary and set length changes, and length changes
to an indexed ancestor such as `rows` in `for value in rows[0]`, also trap.
Indices are evaluated once at entry. Direct assignment to the root variable in
the loop body selects an independent entry snapshot. A callee's `mut` write-back
remains live, including replacement of the collection with another value.
Fixed-array places also see later element writes; their terminal length is fixed.
Comprehensions and generator expressions follow the same source rule, including
writes by their produced expressions and filters. Immutable string/bytes fields
see same-length replacements; terminal length changes and changes to their
indexed managed ancestors trap. String length counts Unicode scalars.
Copies made before any loop remain independent. Non-place sources retain their
entry value.

```mylang
def main() -> int:
    items = [1, 2]
    saved = items
    total = 0
    for value in items:
        total += value
        items[1] = 9
        if value == 9:
            items.append(3)
    assert total == 13
    assert saved == [1, 2]
    return 0
```

Classes declare **value records**, with annotated fields and named construction:
`Node(value=42, children=[])`. They have no inheritance, methods, or implicit
`self`. Assigning a record copies its fields; managed fields still share their
underlying collections. Ordinary field assignment updates a record local or a
record held in a list slot.

Enums and tagged unions declare closed cases. `Kind.first` constructs a case without a
payload and `Kind.first(value)` constructs one with its declared payload; `match`/`case`
uses the same spelling. A generic variant names only its template, because `Slot[int].some`
cannot be told apart from an index followed by a member, so `Slot.some(v)` takes its type
arguments from the expected type.

```mylang
# doc: expect 42
record Point:
    x: int
    y: int

union Shape:
    empty,
    radius: int,
    point: Point

def score(shape: Shape) -> int:
    match shape:
        case Shape.empty:
            return 0
        case Shape.radius(r):
            return r * r
        case Shape.point(p):
            return p.x + p.y

def main() -> int:
    return score(Shape.point(Point(x=2, y=4))) + score(Shape.radius(6))
```

A fixed array `[N]T` and an enum-indexed table `[Kind]T` have no constructor keyword:
a list literal becomes the array and a dict literal keyed by `Kind.case` becomes the
table whenever the surrounding annotation, parameter, field or result demands one. The
array length is checked statically and the table requires every case exactly once.

A tuple groups two to eight values without declaring a record: `(a, b)` builds one, the
type is written `tuple[str, int]`, and the bare forms `return a, b` and `x, y = a, b`
are accepted, so `a, b = b, a` is the swap. A tuple has no fields, no indexing, no
methods and no `len`; take it apart by destructuring, `x, y = value` or `for x, y in
pairs`, and bind `_` for a value you do not need. It compares structurally, prints as
`(1, 'a')`, and is one structural type everywhere. See [tuples](tuples.md).

```mylang
# doc: expect 42
enum Status:
    ok,
    missing

def codes() -> [Status]int:
    return {Status.missing: 4, Status.ok: 38}

def total(values: [2]int) -> int:
    return values[0] + values[1]

def main() -> int:
    fixed: [2]int = [0, 0]
    table = codes()
    return total(fixed) + table[Status.ok] + table[Status.missing]
```

`assert condition` and `assert condition, "message"` trap `R_ASSERT` when the condition is
false, reporting the message — or the expression's own source text — and the location of the
expression. Assertions are allowed under every effect bound and are not removed in release
builds; use them for invariants a caller cannot violate, and `Result` for errors it can.

`case _` covers every variant no earlier arm named, discarding the payload of each one it
covers. It must be the last arm, must cover at least one variant, and is rejected when it
would drop a payload that carries an unhandled result.

A `while True` loop with no `break` never falls through, so a function whose body ends in
one needs no unreachable trailing `return`.

Checked errors use the following explicit extension to Python syntax:

```mylang
def checked(value: int) -> Result[int, int]:
    if value < 0:
        return Err(1)
    return Ok(value)

def main() -> int:
    match checked(42):
        case Ok(value):
            return value
        case Err(code):
            return code
```

`value = checked(42)?` propagates an error when the enclosing function returns a
compatible `Result`. `Option[T]` represents an optional value: construct it with
`Some(value)` or contextual `None`, then match `case Some(value)` / `case None`.
Prelude `list`, `Result`, and `Option` have one identity across every module;
ordinary procedures use `None`.

Generic functions and records use square brackets, for example
`def identity[T](value: T) -> T:`. Calls infer type arguments when possible, and
`identity[int](2)` supplies them explicitly.
Unconstrained parameters default to copyable values. Additional operations on an
abstract type require the existing explicit generic contracts.

`stream.print(values..., sep=, end=)` writes its arguments separated by spaces
with a trailing newline. The entry point declares the stream it writes to, for
example `def main(out: Stream) -> int`, then calls `out.print(...)`; the runtime
supplies both `out` and `err`. Bare `print(...)` is rejected with
`E_OUTPUT_CAPABILITY`. `mylang run` streams that output as it happens; the entry
point's `int` result becomes the process exit status (truncated to a byte) and is
printed to stdout only with `--print-result`.

Files are Python-shaped over explicit authority. The entry point asks for a
`Filesystem` capability by parameter type and every file call takes that
capability first: `with open(fs, path, "rb") as f:`, `f.read()`, `f.write(data)`,
plus `read_text`, `write_text`, `exists`, `listdir`, `mkdir` and `remove`.
`mylang run` grants the filesystem, clock, entropy and environment by default;
`--restrict` withholds them and turns on the `--allow-*` flags. See
[printing, files and command-line authority](io.md).

## Declaration forms Python spells differently

Four declaration shapes have a different accepted spelling, and each one is
rejected with a message that names it. A bare module-level assignment is a
module constant:

```mylang
# doc: expect-error E_SYNTAX
MAX = 42
```

Declare it with `const MAX: int = 42`; the type is required, the value must be an
immutable scalar literal, and the name is visible to every function in the file.

A method belongs to the record's functions, not to its field list:

```mylang
# doc: expect-error E_SYNTAX
class Point:
    def __init__(self, x: int, y: int):
        self.x = x
```

There are no methods on records (and no `class`); write a top-level function that
takes the record as its first parameter, `def norm1(p: Point) -> int:`, and call
it as `norm1(p)`.

`from module import name` is not a declaration either:

```mylang
# doc: expect-error E_SYNTAX
from dataclasses import dataclass
```

Import the module (`import math`) and name its exports through the module, or
declare a `record` for the data you need. `record` is the language's data
declaration and replaces the decorator class.

Union, enum and result bodies separate their cases with commas. A case written
on its own line without one is rejected at that case:

```mylang
# doc: expect-error E_SYNTAX
union Event:
    heartbeat
    count: int
```

Write `heartbeat,` and `count: int,`. The parser still stops at the first syntax
error; these four messages are targeted at the shapes above rather than general
error recovery.

## Conditional expressions

`value_if_true if condition else value_if_false` is one expression with Python's
precedence, read to the right when it nests. The condition must be `bool`, and
both arms have one type — the expected type where the context supplies one, for
instance a binding annotation, a return type or a call parameter, and otherwise
the then arm's own type, with an integer literal arm adopting the expected width.
Nothing widens between the arms, so arms that disagree are rejected with `E_TYPE`
(`conditional arms must agree: ...`). Only the chosen arm is evaluated, so a
guard on the left genuinely prevents a trap on the right, while both arms are
still checked: each contributes its effects, and a name no path reaching an arm
assigns is still `E_UNBOUND`.

```mylang
# doc: expect 42
def maybe(value: int) -> Option[int]:
    return Some(value) if value > 0 else None


def pick(side: int) -> int:
    return 532 if side == 1 else 42


def main() -> int:
    match maybe(pick(2)):
        case Some(value):
            return value
        case None:
            return 0
```

`Some(value) if value > 0 else None` takes the `Option[int]` its return type
demands, so both arms are constructed contextually. The expression is accepted
in every expression position — an assignment value, a `return` value, a call or
keyword argument, a record-constructor field, a list element and an f-string
hole — and `a if p else b if q else c` nests in the else arm.

## Statement forms Python spells differently

The same targeted messaging covers the everyday statement shapes a Python first
attempt reaches for. Each rejection names the accepted spelling it has instead,
as an `alternative` note on the diagnostic:

| rejected spelling | accepted spelling |
| --- | --- |
| `x = y = 21` | `x = 21` then `y = 21` |
| `del xs[0]` | `_ = xs.pop(index)`; for a dictionary `_ = d.pop(key)` |
| `try:` / `except` | `Result` and `match`: `case Ok(value)` / `case Err(reason)` |
| `r"a\nb"` | an ordinary quoted string with the escape written out |
| `if r is None:` | `r == None`, or `match r:` with `case None` |
| `case 1:` | `if x == 1:` / `elif x == 3:` |
| `v = parse(s).unwrap()` | `match` on the `Result`, or `?` to propagate it |
| `if (n := len(xs)) > 2:` | `n = len(xs)` on its own line, then the test |
| `if __name__ == "__main__":` | nothing: `mylang run` calls `def main()` |

```mylang
# doc: expect-error E_SYNTAX
def main() -> int:
    xs = [1, 2, 3]
    del xs[0]
    return len(xs)
```

A loop `else`, a nested `def`, a `match` used as an expression, `**` and `<<`
keep their own `E_EXPRESSION` code and name the construct to write instead: a
flag tested after the loop, a top-level function, an `if`/`elif` assignment,
a multiplication loop, and `shift_left(value, count)`.

## One command shape

Use `mylang run <entry.my>` for both standalone files and module entries. The
command detects `module`, `import`, and `export` headers and loads the reachable
project; `run-project` remains an explicit alias. An entry point may declare
`args: list[str]` first. Compiler and runtime options belong before a separating
`--`; every value after it is a guest argument, including option-looking values.

`mylang build <entry.my> --run` and an executable produced with `-o` use the same
native runtime and integer exit-status rule. `build --run` auto-detects a module
entry like `run`; a persistent module build still requires `--project`. An
installed executable receives every OS argument after `argv[0]` as guest data,
unchanged, and reads its own runtime controls from `MYLANG_OPTIONS` instead. `mylang test <entry.my>`
also builds native children, but reports the test runner's aggregate status rather
than treating a test function's value as a process exit status. Guest tests
receive no ambient capabilities.

A missing grant under `--restrict` is caught before `main` runs, with the same
message from `run`, `build --run` and a built executable: it names the `--allow-*`
flag to pass, and the process exits 2.

`with` opens a file and closes it when the block ends; see
[files](io.md#files). `with arena():` is retired: it runs as an ordinary block and
warns `W_ARENA_RETIRED`; remove the `with arena():` line and dedent its body.

Ten modules ship inside the compiler and are imported by name: `math`, `strings`,
`sort`, `path`, `hex`, `base64`, `json`, `pool`, `random` and `time`. They are
ordinary Python-style source over the same managed types; see the
[standard library](standard-library.md).

Projects retain explicit `module`, `import`, and `export` declarations. Dotted
names call imported functions and name imported types. Host capabilities and
resource cleanup retain their checked contracts; the
[advanced feature reference](current-language.md) covers those APIs.

This is a Python-style statically checked language, not a Python interpreter.
In particular:

- Locals are function-scoped, like Python: a name assigned anywhere in the body is
  one binding, in scope from its first assignment onward. Reading it on a path that
  may not have assigned it is a static `E_UNBOUND`. Because a `for` or `while` loop
  may execute zero times, an assignment made only in the loop body does not make the
  name definitely assigned after the loop; predeclare it before the loop if it is read
  afterward.
- Integers have fixed width, conditions require booleans, and records are values.
  Records, fixed arrays, unions, `Result` and `Option` compare structurally with
  `==`/`!=`. There are no reference types: `class` is rejected.
- Binary64 arithmetic follows IEEE behavior, including infinities/NaNs on floating
  division by zero. It does not raise Python exceptions.
- Lists are homogeneous; `range` takes one to three arguments and slices have no
  step. A live list place accepts growth and traps a decrease from the last
  observed length; indexed ancestors, dictionaries and sets retain exact length
  checks.
- Formatting validates source and rewrites it into the one canonical layout;
  `fmt --check` is nonzero when the input bytes differ from that layout.

## Prelude builtins

The everyday Python builtins are ordinary prelude names: no import is needed,
and a local binding or declared function of the same name still wins. `sum`,
`min`, `max`, `sorted`, `abs`, `round`, `any`, `all`, `reversed`, `list` and
`zip` cover the scalar folds and list materialization. `sum`, `any`, `all`,
`min` and `max` accept a list of the element type they name; text extrema compare
the stored Unicode scalars without allocating an encoding. `sorted` accepts a
list of integer, `float`, `str` or `bytes` and returns a new stable ascending list without
changing its input. It and `values.sort()` use a stable merge that keeps the runs
a list already has, with one work buffer of at most half the list, so ordered
and reverse-ordered lists sort in linear time and every list in `O(n log n)`. For
floats, NaNs follow ordered values while equal values and signed zeros retain
their input order. `reversed(xs)` copies a list or string from last to first
and, like `zip(a, b)`, is also a `for` source; `zip` stops at the shorter list and the
Boolean folds stop as soon as their answer is known.
`list(range(end))`, `list(range(start, end))` and `list(range(start, end, step))`
materialize their range.
`sorted` and `values.sort()` also take Python's `key=` and `reverse=`; see
[keyed sorting](#keyed-sorting).

`round(value)` answers the nearest integral `float`, with halves away from zero
and NaN or infinities unchanged. `round(value, ndigits)` answers the `float`
nearest the exact binary value rounded to `ndigits` decimals (a negative count
rounds left of the point) with the same rule: `round(3.14159, 2)` is `3.14` and
`round(2.675, 2)` is `2.67`, because 2.675 is stored below the half, both as in
CPython; an exact tie differs, `round(0.125, 2)` being `0.13` where CPython says
`0.12` (declared in `velocity/divergences.json`). `abs` is total for `int` except the signed
minimum, which traps `R_OVERFLOW`; a `float` argument stays the prelude float
operation. An empty `min`/`max` has no answer and traps `R_LIST_BOUNDS`.

```mylang
# doc: expect 15
def main() -> int:
    values = [3, 1, 2]
    if round(3.14159, 2) != 3.14 or round(1234.5, -2) != 1200.0:
        return 0
    return sum(values) + max(values) + abs(0 - 6)
```

Byte-oriented code uses the managed `bytes` type; see
[managed byte strings](bytes.md) for its literals, operations and conversions.

## Keyed sorting

`values.sort(key=f, reverse=b)` sorts a list in place and
`sorted(values, key=f, reverse=b)` returns a sorted copy, spelled as in Python:
both keywords are optional and keyword-only. The key maps one element to the
value it is ordered by — any integer type, `bool`, `float`, `str`, `bytes`, or a tuple of
those, compared field by field.

```mylang
# doc: expect 42
record Player:
    name: str
    team: int
    score: float

def by_name(player: Player) -> str:
    return player.name

def main() -> int:
    players = [Player(name="cy", team=2, score=7.5), Player(name="al", team=1, score=9.0), Player(name="bo", team=2, score=9.0)]
    players.sort(key=lambda p: p.score, reverse=True)
    if players[0].name != "al" or players[1].name != "bo":
        return 1
    by_team = sorted(players, key=lambda p: (p.team, p.name))
    if by_team[0].name != "al" or by_team[2].name != "cy":
        return 2
    alphabetical = sorted(players, key=by_name)
    return len(alphabetical[2].name) * 21
```

The rules, which match Python's wherever Python defines them:

- **The key is called exactly once per element, in list order**, before any
  element moves. A key that traps stops the program with that trap, raised by the
  first element in list order whose key traps, and the list has not changed.
- **The sort is stable, with and without `reverse`.** Elements whose keys are
  equal keep their original order. `reverse=True` orders the keys descending and
  still keeps equal keys in their original order, so it is not the same as
  sorting and then calling `reverse()`: `[(1, "a"), (1, "b")]` stays in that
  order under either direction.
- **Floats** order as `values.sort()` orders them: `-0.0` equals `0.0`, and
  every NaN sorts after every other value, so `reverse=True` puts the NaNs first.
  Python leaves NaN ordering undefined; this is the one total order the language
  uses everywhere.
- **Without a key**, `values.sort(reverse=True)` and `sorted(values, reverse=True)`
  order an integer, `float`, `str` or `bytes` list by its elements, stably.
- **In place means in place**: the list keeps its identity, so every alias of it
  sees the new order, and no second list of the elements is built. The extra
  memory is one key per element plus the sort's scratch. `sorted` builds its
  new list directly in sorted order rather than copying and then sorting.

A lambda key gets its key type from its body when the body is the element itself,
a field path from it (`lambda p: p.score`), arithmetic or a negation of one, `len`
of one, or a tuple of those; for any other body write a named function whose
return type says what the key is. The checker rejects a key that does not take
one element of the list's type, one that declares its argument `mut`, and one
whose result has no order (`E_SORT_KEY`), a `reverse=` that is not a `bool`
(`E_TYPE`), and a positional or unknown argument (`E_CALL_ARGUMENT`). There is
no `cmp=`: map each element to a tuple instead.

`sort.sort_by_key(values, key)` is the same keyed sort on a copy. Because keys
are now computed in list order, a key function that traps on several elements
reports the first of them in list order; the module's earlier recursive merge
asked for keys in a different order.


A brace dialect — `fn`, `let`, `struct`, `new T { … }`, `alias::name`,
`f::<T>(x)`, `cast<T>(x)`, `//` comments — was accepted until 2026-09-13 and is
now rejected. [The removed-features index](legacy/README.md) records what each
spelling became.
