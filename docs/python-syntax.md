# The language

This is the language guide. There is one syntax: `def`, `class`, indentation and
`#` comments. The compiler checks types before execution and manages ordinary
lists, strings and dictionaries with tracing GC. There are no allocator arguments
or ownership annotations in ordinary data code.

```mylang
# doc: expect 42
class Node:
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

Save this as `main.my`, then run `zig-out/bin/mylang run main.my --print-result`.
It prints `42`; without that flag `run` prints only what the program prints
itself. Use `check` instead of `run` for type checking, or `run-project` for a
project with imports. The [schematic application](../src/schematic/guest/main.my) is a
larger example; its [instructions](../experiments/schematic/README.md) describe
rendering and GC stress testing.

Write `def`, `class`, four-space indentation, `#` comments, `True`, `False`,
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
Representable unsuffixed integer literals adopt an expected integer type.
`float` is binary64 and accepts literals such as `1.5` and `4.2e1`, ordinary
arithmetic and comparisons, and `float(integer)` / `int(float)` conversion.
`/` produces a float; `//` rounds the quotient down and `%` follows that quotient.
`divtrunc(a, b)` and `remtrunc(a, b)` round toward zero instead, for binary formats and
C interfaces that need that rounding. Float-to-int conversion truncates toward zero and
traps outside the signed range. `sqrt`, `floor`, `ceil`, `trunc` and `abs` operate on
`float` values; `round`, `exp`, `log`, `pow` and the trigonometric functions are not
provided.

```mylang
# doc: expect 42
def main() -> int:
    spread = -7
    floored = spread // 2
    toward_zero = divtrunc(spread, 2)
    return (toward_zero - floored) * 42
```

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
`str(value)` does and concatenating the result. `{{` and `}}` write single braces. Holes take
any expression but no format specification, so round a float or pad a number before
interpolating it.

```mylang
# doc: expect 42
def label(count: int, items: list[int]) -> str:
    return f"total {count} of {len(items)}"

def main() -> int:
    if label(7, [1, 2, 3]) == "total 7 of 3":
        return 42
    return 0
```

Dictionaries preserve insertion order and use `int` or `str` keys. Their values
have a single inferred or annotated type. Updates through an alias are shared.
Use `counts[key]`, `counts[key] = value`, `counts.get(key, fallback)`,
`counts.keys()` and `counts.values()`. The latter two return snapshot lists.
`key in counts`, `value in items`, and `substring in text` support `not in` too.
Iterating a dictionary visits keys in insertion order; changing its size during
iteration traps. The [word-count example](../examples/python-word-count/main.my)
puts these operations together.

`[value for name in items if condition]` builds a list in one pass, with the filter
optional and the binding confined to the comprehension. It takes one generator; nested
generators and generator expressions are not provided, and neither are dict or set
comprehensions.

```mylang
# doc: expect 42
def main() -> int:
    source = [1, 2, 3, 4]
    kept = [value * 7 for value in source if value > 2]
    return kept[0] + kept[1] - 7
```

`for value in items`, `for index, value in enumerate(items)`, and
`for index in range(end)` / `range(start, end)` support `break` and `continue`.
List iteration fixes its initial bound and rejects length changes through aliases.

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
class Point:
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
Prelude `list`, `List`, `Result`, and `Option` have one identity across every
module and both spellings; ordinary procedures use `None`.

Generic functions and classes use square brackets, for example
`def identity[T](value: T) -> T:`. Calls infer type arguments when possible, and
`identity[int](2)` supplies them explicitly.
Unconstrained parameters default to copyable values. Additional operations on an
abstract type require the existing explicit generic contracts.

`print(values...)` writes its arguments separated by spaces with a trailing
newline, and accepts `sep=` and `end=`. `mylang run` streams that output as it
happens and reports the entry point's `int` result only with `--print-result`.

Files are Python-shaped over explicit authority. The entry point asks for a
`Filesystem` capability by parameter type and every file call takes that
capability first: `with open(fs, path, "rb") as f:`, `f.read()`, `f.write(data)`,
plus `read_text`, `write_text`, `exists`, `listdir`, `mkdir` and `remove`.
`mylang run` grants the filesystem, clock, entropy and environment by default;
`--restrict` withholds them and turns on the `--allow-*` flags. See
[printing, files and command-line authority](io.md).

`with` is one statement form with two resource kinds. Wrap a phase of work in
`with arena() as scratch:` to free everything it allocates in one step and copy
the result out with `scratch.escape(value)`; see [managed arenas](arenas.md).

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

- New locals are block-scoped. Initialize a local before an `if` or loop if it is
  needed afterward; nested blocks can reassign that existing local.
- Integers have fixed width, conditions require booleans, and records are values.
- Binary64 arithmetic follows IEEE behavior, including infinities/NaNs on floating
  division by zero. It does not raise Python exceptions.
- Lists are homogeneous; ranges currently accept one or two arguments and slices
  have no step. Changing a list's length during iteration traps.
- GC roots and collection transport across host/JSON boundaries are not
  implemented.
- Formatting validates source and returns it unchanged: indentation already is
  the canonical layout, so `fmt --check` accepts everything that parses.

## Prelude builtins

The everyday Python builtins are ordinary prelude names: no import is needed,
and a local binding or declared function of the same name still wins. `sum`,
`min`, `max`, `sorted`, `abs`, `round`, `any`, `all`, `reversed`, `list` and
`zip` cover the scalar folds and list materialization. `sum`, `any`, `all`,
`min` and `max` accept a list of the element type they name; `sorted` accepts a
list of `int`, `float` or `str` and returns a new stable ascending list without
changing its input. `reversed(xs)` copies a list or string from last to first
and, like `zip(a, b)`, is also a `for` source; `zip` stops at the shorter list and the
Boolean folds stop as soon as their answer is known.
`list(range(end))` and `list(range(start, end))` materialize their range.

`round(value)` answers the nearest integral `float`, with halves away from zero
and NaN or infinities unchanged. `abs` is total for `int` except the signed
minimum, which traps `R_OVERFLOW`; a `float` argument stays the prelude float
operation. An empty `min`/`max` has no answer and traps `R_LIST_BOUNDS`.

```mylang
# doc: expect 15
def main() -> int:
    values = [3, 1, 2]
    return sum(values) + max(values) + abs(0 - 6)
```

Byte-oriented code uses the managed `bytes` type; see
[managed byte strings](bytes.md) for its literals, operations and conversions.

A brace dialect — `fn`, `let`, `struct`, `new T { … }`, `alias::name`,
`f::<T>(x)`, `cast<T>(x)`, `//` comments — was accepted until 2026-09-13 and is
now rejected. [The removed-features index](legacy/README.md) records what each
spelling became.
