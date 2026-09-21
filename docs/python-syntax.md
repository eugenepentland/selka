# The language

This is the language guide. There is one syntax: `def`, `record`, indentation and
`#` comments. The compiler checks types before execution and manages ordinary
lists, strings and dictionaries with tracing GC. There are no allocator arguments
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
[schematic application](../src/schematic/guest/main.my) is a larger example; its
[instructions](../experiments/schematic/README.md) describe rendering and GC
stress testing.

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
`counts.keys()`, `counts.values()` and `counts.items()`. These return live typed
views; `list(view)` creates an explicit snapshot. Items yield records with `key`
and `value` fields and also support `for key, value in view`.
`key in counts`, `value in items`, and `substring in text` support `not in` too.
Iterating a dictionary visits keys in insertion order; changing its size during
iteration traps. The [word-count example](../examples/python-word-count/main.my)
puts these operations together.

`[value for name in items if condition]` builds a list in one pass, with the filter
optional and the binding confined to the comprehension. The source is a list, string,
dictionary or an integer `range(...)` — `[i for i in range(10)]` works the same as it
does in a `for` loop. Without a filter, the result reserves the source length (or
the exact nonnegative range length) before filling; filtered results grow with the
values they retain. It takes one generator; nested generators and generator
expressions are not provided, and neither are dict or set comprehensions.

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

Generic functions and classes use square brackets, for example
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

There are no methods on `class` or `record`; write a top-level function that
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

## One command shape

Use `mylang run <entry.my>` for both standalone files and module entries. The
command detects `module`, `import`, and `export` headers and loads the reachable
project; `run-project` remains an explicit alias. An entry point may declare
`args: list[str]` first. Compiler and runtime options belong before a separating
`--`; every value after it is a guest argument, including option-looking values.

`mylang build <entry.my> --run` and an executable produced with `-o` use the same
native runtime and integer exit-status rule. `build --run` auto-detects a module
entry like `run`; a persistent module build still requires `--project`. An
installed executable receives OS arguments after `argv[0]` as guest data, with a
`--` separating its own runtime controls from the list. `mylang test <entry.my>`
also builds native children, but reports the test runner's aggregate status rather
than treating a test function's value as a process exit status. Guest tests
receive no ambient capabilities.

Capability denial currently has two diagnostic renderings: `run` catches a
missing restricted grant before execution, while `build --run` and installed
executables report the native runtime's `CapabilityUnavailable` failure. They
all deny the capability and exit 2; unifying the stderr wording is pending.

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

- Locals are function-scoped, like Python: a name assigned anywhere in the body is
  one binding, in scope from its first assignment onward. Reading it on a path that
  may not have assigned it is a static `E_UNBOUND`. Because a `for` or `while` loop
  may execute zero times, an assignment made only in the loop body does not make the
  name definitely assigned after the loop; predeclare it before the loop if it is read
  afterward.
- Integers have fixed width, conditions require booleans, and records are values.
  Records, fixed arrays, unions, `Result` and `Option` compare structurally with
  `==`/`!=`; a `class` compares by reference identity.
- Binary64 arithmetic follows IEEE behavior, including infinities/NaNs on floating
  division by zero. It does not raise Python exceptions.
- Lists are homogeneous; ranges currently accept one or two arguments and slices
  have no step. Changing a list's length during iteration traps.
- GC roots and collection transport across host/JSON boundaries are not
  implemented.
- Formatting validates source and rewrites it into the one canonical layout;
  `fmt --check` is nonzero when the input bytes differ from that layout.

## Prelude builtins

The everyday Python builtins are ordinary prelude names: no import is needed,
and a local binding or declared function of the same name still wins. `sum`,
`min`, `max`, `sorted`, `abs`, `round`, `any`, `all`, `reversed`, `list` and
`zip` cover the scalar folds and list materialization. `sum`, `any`, `all`,
`min` and `max` accept a list of the element type they name; text extrema compare
the stored Unicode scalars without allocating an encoding. `sorted` accepts a
list of `int`, `float` or `str` and returns a new stable ascending list without
changing its input. It and `values.sort()` use a stable merge with one reusable
work buffer, so reverse-ordered large lists retain `O(n log n)` behavior. For
floats, NaNs follow ordered values while equal values and signed zeros retain
their input order. `reversed(xs)` copies a list or string from last to first
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
