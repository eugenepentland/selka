# The language

This is the language guide. There is one syntax: `func`, `record`, indentation and
`#` comments. The compiler checks types before execution and manages ordinary
lists, strings and dictionaries through checked ownership and deterministic
cleanup. Ordinary parameters borrow values for reading; `own` marks transfers
from named managed bindings. Use `copy(value)` when both independent values must remain usable and
`mut` for an exclusive writable argument. There are no allocator arguments or
garbage collector to tune.

A file can import standard or project modules directly. Its module name comes
from its path beneath the project root; no module header is needed. `selka run`
loads reachable imports itself:

```selka
# doc: expect 42
import math

func main() -> int:
    return math.clamp(99, 0, 42)
```

Save this as `main.selka`, then run `zig-out/bin/selka run main.selka --print-result`.
It prints `42`; without that flag `run` prints only what the program prints
itself. `run-project` remains the explicit alias for a project entry, and a file
without imports stays one standalone unit.

Here is the same single-file shape with ordinary records and a list:

```selka
# doc: expect 42
record Node:
    value: int
    children: Node[]

func main() -> int:
    mut nodes = [Node(value=40, children=[])]
    append(mut nodes, Node(value=2, children=[]))
    mut total = 0
    for node in nodes:
        total = total + node.value
    return total
```

Save it as `main.selka` too; `check` type-checks either file without building. The
named-constraints project (`examples/named-constraints/main.selka`) is a larger
example: several modules, a generic contract and a test entry
(`fake_tests.selka`).

Write `func`, `record`, four-space indentation, `#` comments, `True`, `False`,
`None`, and `and`/`or`/`not`. Each statement ends at its newline; semicolon-separated
statements are rejected. Parenthesized expressions and
collection literals may continue across lines; nothing else does, neither a binary operator nor a backslash at the end of a
line (`E_INDENTATION` and `E_TOKEN` say to write parentheses, and `selka fix` writes them). Tabs in indentation are rejected.
`pass` represents an empty suite. An omitted function return annotation means
`Unit`; functions may end naturally or use bare `return`.

Fixed-width conversions read like the numeric ones: `i64(x)`, `u8(x)` and their
siblings convert with a runtime range check, as `int(x)` and `float(x)` do between
numeric types. Parse text explicitly with `parse_int(text)` or `parse_float(text)`. Explicit type arguments are always square: `f[T](x)`,
`Box[int](value=1)`, `todo[int]()`, `wrap[Metres](n)`.

Declarations introduce names: `const name = value` is immutable and
`mut name = value` is writable. Add an annotation when inference is ambiguous:
`mut children: Node[] = []` or `mut counts: dict[str, int] = {}`.
Assignment updates an existing writable binding. Function parameters, record fields, and non-unit
return types are annotated. The compiler remains statically typed; reassigning
an `int` local to a string is an error.

For managed values, `const alias = owner` borrows the place read-only until
`alias`'s last use in its block, even when `owner` is a local or an `own` parameter.
Write `const next = own owner` or `mut next = own owner` to transfer ownership.
Named values also need `own` when stored or passed to an owning parameter:
`rows[i] = own row`, `Row(items=own items)`, `Some(own items)` and `take(own items)`.
A bare `return items` is exempt; `return own items` is refused. Calls, literals,
operators and `copy(...)` produce fresh values that never take `own`, and scalars
never take it either. Missing or misplaced markers are `E_OWN_MARKER`.

`own record.items` transfers the field by consuming its whole record: the record
becomes unavailable and its other fields are destroyed. Use `copy(record.items)`
when the record must stay usable. These moves do not change borrowing signatures:
`-> T from source` still declares a read-only result borrowed from a plain or
`mut` parameter.

Declared functions accept positional and keyword arguments, including defaults:

```selka
# doc: check
func offset(value: int, amount: int = 2) -> int:
    return value + amount

# offset(value=40) returns 42
```

Arguments evaluate once in their written order, even when keywords reorder the
parameters. Defaults must be immutable numeric, boolean, string, or `None`
literals; mutable collection defaults are rejected. Required parameters precede
those with defaults. Intrinsics require positional arguments. A callback parameter declared `named`
requires its label; callback types preserve those labels.

`named` (like `own` and `mut`) is a modifier only where a name follows it. A parameter, or a callback label, can itself
be called `named`: `named` before `:` is the name, and `named named: int` is the modifier and then the name.

```selka
# doc: check
func count(named: int[]) -> int:
    return len(named)

func scaled(named named: int) -> int:
    return named * 2
```

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

```selka
# doc: expect 42
func main() -> int:
    mut spread = -7
    mut floored = spread // 2
    mut toward_zero = divtrunc(spread, 2)
    return (toward_zero - floored) * 42
```

### Operators Python has

Comparisons chain: `==`, `!=`, `<`, `<=`, `>` and `>=` share one precedence
level, and `low <= x < high` means `low <= x and x < high`, with each operand
evaluated once, left to right, and the rest skipped once a link is false. `str`
and `bytes` [order lexicographically](text.md#ordering-and-repetition). Repeat
text with `strings.repeat(text, count)`, bytes with
`byte_builder.repeat(data, count)`, and one list element with
`lists.filled(count, value)`; each returns an empty value for a nonpositive count.

Integers have no bit operators: `&`, `|` and `^` are refused, and the prelude
operations [combine bits](integer-operations.md#bitwise-and-shift-helpers):
`bit_and(a, b)`, `bit_or(a, b)` and `bit_xor(a, b)`, with `bit_not(value)` for
the complement and `shift_left(value, count)` / `shift_right(value, count)` for
shifts. On two [sets](sets.md#set-operators) of one type `|`, `&`, `-` and `^`
are union, intersection, difference and symmetric difference.

```selka
# doc: expect 42
func main() -> int:
    mut flags = bit_or(6, 1)
    mut mask = bit_and(12, 10)
    if bit_or(1, bit_xor(2, bit_and(3, 1))) != 3 or bit_xor(5, 3) != 6:
        return 1
    return flags * mask - 14
```

`selka fix` rewrites a removed operator to its call, keeping both operands.

```selka
# doc: expect-error E_BIT_OPERATOR_REMOVED
func main() -> int:
    return 6 | 1
```

```selka
import strings
# doc: expect 42
func main() -> int:
    mut x = 5
    if not (0 < x < 10 and 1 <= x <= 5 and x == 5 != 6):
        return 1
    if not ("abc" < "abd") or strings.repeat("ab", 2) != "abab":
        return 3
    return 42
```

`**`, `<<` and `>>` are not operators: write a multiplication loop (or
`math.pow(x, n)` for a `float`) and `shift_left(value, count)` /
`shift_right(value, count)`. Each rejection names that alternative, and the
augmented spellings `**=`, `<<=` and `>>=` get the same answer. The other
operators of C are answered at the token where they fail: `x++` and `x--` say to
write `x += 1` and `x -= 1`; `&=`, `|=` and `^=` say to rebind a set with its
operator and to write `x = bit_or(x, y)` (`bit_and`, `bit_xor`) for an integer;
`~x` says to write `bit_not(x)`; `a ? b : c` says that `?` after a value only
passes its failure on and that the result is declared first and assigned in an
`if`/`else`, as a statement and inside the arguments of a call, a parenthesis,
a list, an index or a dictionary value. None of these has a `selka fix` edit.

Lists infer a homogeneous element type from nonempty literals. Write
`mut next = own items` to transfer a list, or `copy(items)` to keep two independent values.
Use `append(mut items, value)`,
`len(items)`, `items[index]`, `items[index] = value`, and `items[start:end]`.
Indexes and explicit slice bounds must be nonnegative. Use `len(items) - k`
for a position counted from the end; runtime-computed negative positions trap.
Upper slice bounds clamp to the length. Slices create independent list storage
and copy the selected elements. Nested indexing and expression receivers work.

Strings use ordinary single or double quotes and represent immutable UTF-8 text.
Indexing and length count octets, not Unicode scalars or grapheme clusters; the
`strings.char_*` helpers read scalars. Use concatenation, equality,
`strings.split(text, separator)`, `strings.join(parts, separator)`, and `str(value)` for scalar conversion. Strings also support slices and iteration. `b"..."` represents bytes for binary APIs.

Text operations are the `strings` module's functions: `starts_with`, `ends_with`,
`find` (an `int?`), `count`, `zfill`, `split`, `words`, `join(parts, separator)`,
`encode`, `strip`, `lstrip`, `rstrip`, `replace`, `lines`, `upper`, `lower`,
`is_digit`, `is_alpha` and `is_space`; bytes have the `bytes` module's, and a set's
writes are `sets.add`, `remove`, `update`, `pop` and `clear`. The Python method
spellings, such as `text.encode()` or `", ".join(parts)`, are refused
(`E_METHOD_REMOVED`), and `selka fix` writes the function with the import it needs. These
operations leave their receiver unchanged. `ljust` and `rjust` are absent, because intrinsic methods take no defaulted
arguments. `parse_int(text)` and `parse_float(text)` return `int?` and `float?`: the
language has no exceptions, so a string that is not exactly one number answers `None`.

An `f"..."` literal interpolates `{expression}` holes, converting each one exactly as
`str(value)` does and concatenating the result. `{{` and `}}` write single braces. A hole
may end in a CPython [format specification](text.md#format-specifications) —
`f"{price:.2f}"`, `f"{n:05d}"`, `f"{name:>8}"`, `f"{total:,}"` — which renders exactly
as CPython does. `f"""..."""` and `f'''...'''` write a format string that spans lines: its text is the
[triple-quoted text](text.md#triple-quoted-text) of the same source, nothing stripped or dedented, and each hole closes on the line
it opens ([triple-quoted format strings](text.md#triple-quoted-format-strings)).

```selka
# doc: expect 42
func label(count: int, items: int[]) -> str:
    return f"total {count} of {len(items)}"

func main() -> int:
    if label(7, [1, 2, 3]) == "total 7 of 3":
        return 42
    return 0
```

Dictionaries preserve insertion order and take any
[hashable](sets.md#hashable-keys) key: an integer, `bool`, `str`, `bytes`, or a
record, union, enum, fixed array or `Option` built from those. Their values
have a single inferred or annotated type. Assignment can move a collection;
`copy(value)` creates an independent value that later writes to the original cannot change.
Use `counts[key]`, `counts[key] = value`, `dicts.get(counts, key, fallback)`,
`dicts.keys(counts)`, `dicts.values(counts)` and `dicts.items(counts)`. These return ephemeral typed
views for direct loops and immediate `len`, `in`, `list`, `set` and `sorted`.
Use `kept = list(dicts.values(counts))` to store an independent snapshot; storing
a view itself is `E_VIEW_STORED`. View types are also rejected in parameter,
return, field and collection element annotations, including unused generic
declarations; use a list type for a snapshot. Items yield records with `key` and `value`
fields and support `for key, value in dicts.items(counts)`.
`key in counts` and `substring in text` support `not in` too. Lists use
`lists.contains(items, value)`; scan dictionary values with an explicit loop.
Iterating a dictionary visits keys in insertion order. The checker rejects
mutation that overlaps the iteration's read borrow. The word-count example (`examples/python-word-count/main.selka`)
puts these operations together.

Build lists with a typed accumulator and explicit `for` and `if` statements.
Comprehensions receive `E_COMPREHENSION_REMOVED`; `selka fix` rewrites certain
cases to loops while preserving source and filter evaluation order.

```selka
# doc: expect 42
func main() -> int:
    mut source = [1, 2, 3, 4]
    mut kept: int[] = []
    for value in source:
        if value > 2:
            append(mut kept, value * 7)
    mut grid = [[1, 2], [3, 4]]
    mut flat: int[] = []
    for row in grid:
        for x in row:
            if x % 2 == 0:
                append(mut flat, x)
    return kept[0] + kept[1] - 7 + flat[1] - flat[0] - 2
```

### Dict and set comprehensions

Build dictionaries and sets with explicit loops, dictionary assignment and
`set.add`. Evaluate each key before its value; repeated keys keep their first
position and last value. Use a typed accumulator when literals need an element type.

```selka
# doc: expect 42
import dicts
import sets
import strings

func main() -> int:
    mut prices = {"pear": 3, "fig": 5, "kiwi": 2}
    mut doubled: dict[str, int] = {}
    for name, price in dicts.items(prices):
        if price > 2:
            doubled[name] = price * 2
    mut squares: dict[int, int] = {}
    for x in range(5):
        squares[x] = x * x
    mut paired: dict[str, int] = {}
    for k, v in zip(["a", "b"], [10, 20]):
        paired[k] = v
    mut letters: set[str] = set()
    for c in strings.chars("hello"):
        sets.add(mut letters, own c)
    return doubled["fig"] + squares[4] + paired["a"] + len(letters) + 2
```

### Generator expressions

Generator arguments receive `E_GENERATOR_REMOVED`. Use an explicit loop for
reductions and a typed accumulator for materialized collections. Preserve the
early exit of `any` and `all` with `break` at the deciding element.

```selka
# doc: expect 42
import strings

func main() -> int:
    mut xs = [4, 1, 3]
    mut has_large = False
    for x in xs:
        if x > 3:
            has_large = True
            break
    if not has_large:
        return 1
    mut all_large = True
    for x in xs:
        if x <= 1:
            all_large = False
            break
    if all_large:
        return 1
    mut scaled: int[] = []
    for x in xs:
        append(mut scaled, x * 10)
    mut ordered = sorted(scaled)
    mut labels: str[] = []
    for x in xs:
        append(mut labels, str(x))
    mut text = strings.join(labels, "-")
    mut squares = 0
    for x in xs:
        squares += x * x
    mut largest = xs[0]
    for x in xs:
        if x > largest:
            largest = x
    return squares + largest + ordered[0] + strings.char_count(text) - 3
```

Stored generator expressions are also rejected. Build a list with an explicit loop.

```selka
# doc: expect-error E_GENERATOR_REMOVED
func main() -> int:
    mut squares = (x * x for x in [1, 2, 3])
    return 0
```

`for value in items`, `for index, value in enumerate(items)`, and
`for index in range(end)` / `range(start, end)` / `range(start, end, step)` support
`break` and `continue`. A [stepped range](range-iteration.md#stepped-ranges) counts
down for a negative step. `range` is a loop source, not a collection, so `x in range(a, b)`
is refused; the comparison is `a <= x < b` (`x < a or b <= x` for `not in`), which the
message writes with the bounds as written and `selka fix` writes when the needle and the
bounds are names or numbers and there is no step.
Iteration borrows its source for reading. The source cannot be moved or mutated
while that borrow remains live. Pass an element to a read-only helper, or use
`copy(value)` when an owned element must be stored independently. Copies made before
the loop remain independent and can be changed separately. String iteration
visits Unicode scalar values; byte iteration visits octets.

Use an index loop when checked ownership must permit mutation between element
reads. The scalar local below finishes its read before the collection changes.

```selka
func main() -> int:
    mut items = [1, 2]
    mut saved = copy(items)
    mut total = 0
    mut index = 0
    while index < len(items):
        const value = items[index]
        index += 1
        total += value
        items[1] = 9
        if value == 9:
            append(mut items, 3)
    assert total == 13
    assert saved == [1, 2]
    return 0
```

Records declare **value records**, with annotated fields and named construction:
`Node(value=42, children=[])`. They have no inheritance, methods, or implicit
`self`. Scalar-only records copy by value; records with owned contents can move.
An explicit `copy(value)` preserves an independent value, including managed fields.
Field assignment updates a writable record
local or a record held in a writable array slot.

Enums declare closed cases with named payload fields. `Kind.first` constructs
a case without a payload; `Kind.some(value=x)` constructs a case whose field is
`value`. A pattern uses the same labels and names the case alone, such as
`case some(value=x)`; the matched value's type says which enum it belongs to.
A generic variant names its template, such as `Slot.some(value=x)`, and takes
its type arguments from the expected type.

```selka
# doc: expect 42
record Point:
    x: int
    y: int

enum Shape:
    empty
    radius(value: int)
    point(value: Point)

func score(shape: Shape) -> int:
    match shape:
        case empty:
            return 0
        case radius(value=r):
            return r * r
        case point(value=p):
            return p.x + p.y

func main() -> int:
    return score(Shape.point(value=Point(x=2, y=4))) + score(Shape.radius(value=6))
```

`case_name(value)` is the declared name of the case a value holds, `Kind.cases()` lists the cases of an enum without payloads and
`Kind.from_name(text)` parses one from its name; see [case names](records-and-unions.md#case-names).

Construct a fixed array with `FixedArray[T, N]([elements])`. The separate
enum-indexed table spelling remains `[Kind]T`:
a list literal becomes the array and a dict literal keyed by `Kind.case` becomes the
table whenever the surrounding annotation, parameter, field or result demands one. The
array length is checked statically and the table requires every case exactly once.

Use a nominal record with named fields to group values. Tuple types, tuple
values, general destructuring and parallel assignments are retired with
`E_TUPLE_REMOVED`; see [record replacements](tuples.md). The two-name loop forms
for `enumerate`, `zip` and dictionary `items()` remain supported.

```selka
# doc: expect 42
enum Status:
    ok
    missing

func codes() -> [Status]int:
    return {Status.missing: 4, Status.ok: 38}

func total(values: FixedArray[int, 2]) -> int:
    return values[0] + values[1]

func main() -> int:
    mut fixed: FixedArray[int, 2] = FixedArray[int, 2]([0, 0])
    mut table = codes()
    return total(fixed) + table[Status.ok] + table[Status.missing]
```

`assert condition` and `assert condition, "message"` trap `R_ASSERT` when the condition is
false, reporting the message — or the expression's own source text — and the location of the
expression. Assertions are also available in generic bodies and are not removed in release
builds; use them for invariants a caller cannot violate, and `Result` for errors it can.

`case _` covers every variant no earlier arm named, discarding the payload of each one it
covers. It must be the last arm, must cover at least one variant, and is rejected when it
would drop a payload that carries an unhandled result.

A `while True` loop with no `break` never falls through, so a function whose body ends in
one needs no unreachable trailing `return`.

Checked errors use the following explicit extension to Python syntax:

```selka
func checked(value: int) -> int fails int:
    if value < 0:
        fail 1
    return value

func main() -> int:
    match checked(42):
        case Ok(value):
            return value
        case Err(code):
            return code
```

`const value = try checked(42)` propagates an error when the enclosing function
declares a compatible `fails` type. `T?` represents an optional value: construct it with
`Some(value)` or contextual `None`, then match `case Some(value)` / `case None`.
Prelude `list`, `Result`, and `Option` have one identity across every module;
ordinary procedures use `Unit` and the value `()`.

Generic functions and records use square brackets, for example
`func identity[T](value: T) -> T:`. Calls infer type arguments when possible, and
`identity[int](2)` supplies them explicitly.
Unconstrained parameters default to copyable values. Additional operations on an
abstract type require the existing explicit generic contracts.

`print(out, values..., sep=, end=)` writes its arguments separated by spaces
with a trailing newline. The entry point declares the stream it writes to, for
example `func main(out: Stream) -> int`, then calls `print(out, ...)`; the runtime
supplies both `out` and `err`. Bare `print(...)` is rejected with
`E_OUTPUT_CAPABILITY`. `selka run` streams that output as it happens; the entry
point's `int` result becomes the process exit status (truncated to a byte) and is
printed to stdout only with `--print-result`.

Files are Python-shaped over explicit authority. The entry point asks for a
`Filesystem` capability by parameter type and every file call takes that
capability first: `with open(fs, path, "rb") as f:`, `f.read()`, `f.write(data)`,
plus `read_text`, `write_text`, `exists`, `listdir`, `mkdir` and `remove`.
`selka run` grants the filesystem, clock, entropy and environment by default;
`--restrict` withholds them and turns on the `--allow-*` flags. See
[printing, files and command-line authority](io.md).

## Declaration forms Python spells differently

Four declaration shapes have a different accepted spelling, and each one is
rejected with a message that names it. A module constant requires an explicit
`const` declaration; a bare module-level assignment is rejected:

```selka
# doc: expect-error E_SYNTAX
MAX = 42
```

Declare it with `const MAX: int = 42`; the type is required, the value must be an
immutable scalar literal, and the name is visible to every function in the file.
Inside a function `const limit = 42` infers its type, so the same line at the top
level is a common slip; it is refused as well:

```selka
# doc: expect-error E_SYNTAX
const MAX = 42
```

The message writes the line as it should be (`const MAX: int = 42`), and `selka fix`
inserts the type after the name when the value is one literal whose type is plain: an
integer, a decimal float, a text or `True` and `False`. For any other value the message
asks for `const MAX: TYPE = ...` and the author names the type.

A method belongs to the record's functions, not to its field list:

```selka
# doc: expect-error E_SYNTAX
class Point:
    func __init__(self, x: int, y: int):
        self.x = x
```

There are no methods on records (and no `class`); write a top-level function that
takes the record as its first parameter, `func norm1(p: Point) -> int:`, and call
it as `norm1(p)`.

`from module import name` is not a declaration either:

```selka
# doc: expect-error E_SYNTAX
from dataclasses import dataclass
```

Import the module (`import math`) and name its exports through the module, or
declare a `record` for the data you need. `record` is the language's data
declaration and replaces the decorator class.

Enum cases occupy separate lines and payload fields have names:

```selka
# doc: check
enum Event:
    heartbeat
    count(value: int)
```

Construct the payload as `Event.count(value=3)` and bind it with
`case count(value=count)`. Nominal `result` declarations retain their
special handling rules. Removed spellings receive structured migration repairs.

## Selecting a value

Use an `if` or `match` statement to assign a named result. Declare the result
with its type before the branches; every continuing branch must initialize it.
A function can also return directly from each branch.

```selka
# doc: expect 42
func maybe(value: int) -> int?:
    if value > 0:
        return Some(value)
    else:
        return None


func pick(side: int) -> int:
    const result: int
    if side == 1:
        result = 532
    else:
        result = 42
    return result


func main() -> int:
    match maybe(pick(2)):
        case Some(value):
            return value
        case None:
            return 0
```

Conditional expressions (`a if condition else b` and `if condition then a else b`)
receive `E_CONDITIONAL_EXPRESSION_REMOVED`. Match expressions with `yield` arms
receive `E_MATCH_EXPRESSION_REMOVED`. `selka fix` replaces certain statement
sites and extracts expressions only when evaluation order is preserved. For a
short-circuit operand, a repeated loop condition, or another uncertain site,
write the statement form manually at the point where the expression runs.

## Statement forms Python spells differently

The same targeted messaging covers the everyday statement shapes a Python first
attempt reaches for. Each rejection names the accepted spelling it has instead,
as an `alternative` note on the diagnostic:

| rejected spelling | accepted spelling |
| --- | --- |
| `x = y = 21` | `const x = 21` then `const y = 21` |
| `del xs[0]` | `_ = lists.pop_at(mut xs, index)`; for a dictionary `_ = dicts.pop(mut d, key)` |
| `try:` / `except` | a function declared `-> T fails E` and a `match` on its call: `case Ok(value)` / `case Err(reason)` |
| `r"a\nb"` | an ordinary quoted string with the escape written out |
| Optional presence | `if r is None:` or `match r:` with `case None` |
| `case Some(3):` | `case 3:` as an arm of its own, in a match on an `int`, `str`, `bytes` or `bool` |
| `v = parse(s).unwrap()` | `const v = try parse(s)` or an explicit result `match` |
| `if (n := len(xs)) > 2:` | `const n = len(xs)` on its own line, then the test |
| `if __name__ == "__main__":` | nothing: `selka run` calls `func main()` |

```selka
# doc: expect-error E_SYNTAX
func main() -> int:
    mut xs = [1, 2, 3]
    del xs[0]
    return len(xs)
```

A loop `else`, a nested `func`, `**` and `<<` retain their diagnostic guidance:
use a flag declared outside the loop, a top-level function, a multiplication loop,
or `shift_left(value, count)`. Use a match statement with ordinary statements
in each arm to select and assign a result.

## One command shape

Use `selka run <entry.selka>` for both standalone files and module entries. The
command detects `import` and `export` directives and loads the reachable
project; `run-project` remains an explicit alias. An entry point may declare
`args: str[]` first. Compiler and runtime options belong before a separating
`--`; every value after it is a guest argument, including option-looking values.

`selka build <entry.selka> --run` and an executable produced with `-o` use the same
native runtime and integer exit-status rule. `build --run` auto-detects a module
entry like `run`; a persistent module build still requires `--project`. An
installed executable receives every OS argument after `argv[0]` as guest data,
unchanged, and reads its own runtime controls from `SELKA_OPTIONS` instead. `selka test <entry.selka>`
also builds native children, but reports the test runner's aggregate status rather
than treating a test function's value as a process exit status. Guest tests
receive no ambient capabilities.

A missing grant under `--restrict` is caught before `main` runs, with the same
message from `run`, `build --run` and a built executable: it names the `--allow-*`
flag to pass, and the process exits 2.

`with` opens a file and closes it when the block ends; see
[files](io.md#files). `with arena():` is retired: it is rejected with
`E_ARENA_REMOVED`; remove the `with arena():` line and dedent its body.

The standard modules ship inside the compiler and are imported by name, for
example `math`, `strings`, `sort`, `path`, `json`, `csv`, `http` and `time`. They
are ordinary Python-style source over the same managed types; the
[standard library](standard-library.md) lists every module and its signatures.

Projects retain explicit `module`, `import`, and `export` declarations. Dotted
names call imported functions and name imported types. Host capabilities and
resource cleanup retain their checked contracts; `selka docs io`, `selka docs effects` and `selka docs stdlib` cover those APIs.

This is a Python-style statically checked language, not a Python interpreter.
In particular:

- Declare immutable locals with `const` and writable locals with `mut`. Names
  belong to their enclosing block; active locals and parameters cannot be shadowed.
  Assignment updates an existing writable binding. Declare a changing value outside
  a loop or branch when it must be read afterward.
- Integers have fixed width, conditions require booleans, and records are values.
  Records, fixed arrays, unions, `Result` and `Option` compare structurally with
  `==`/`!=`. There are no reference types: `class` is rejected.
- Binary64 arithmetic follows IEEE behavior, including infinities/NaNs on floating
  division by zero. It does not raise Python exceptions.
- Lists are homogeneous; `range` takes one to three arguments. A slice is
  contiguous, so stepped slices are refused in favour of `strings.char_stride`
  and `lists.stride`. `str` is bytes: `len(text)`, `text[i]` and `text[a:b]`
  read octets, and `strings.char_count`, `char_at`, `char_slice` and
  `char_stride` read scalars. A text slice is a view of its source: read it or
  bind it, and copy it into a record, a list or a dictionary with `copy(value)`.
  Collection iteration borrows
  its owner for reading. A write that overlaps that borrow is rejected; copy the
  collection before iterating when a separate owner must change.
- Formatting validates source and rewrites it into the one canonical layout;
  `fmt --check` is nonzero when the input bytes differ from that layout. The
  formatter parses its own output before it writes anything: text that does not
  parse, or parses to other syntax than the input had, is refused with
  `E_FORMAT_VERIFY` (exit 2) and nothing is written; see [the formatter](tooling/formatter.md).

## Prelude builtins

The everyday Python builtins are ordinary prelude names: no import is needed,
and a local binding of the same name still wins. `sum`,
`min`, `max`, `sorted`, `abs`, `round`, `any`, `all`, `reversed`, `list` and
`zip` cover the scalar folds and list materialization. `sum`, `any`, `all`,
`min` and `max` accept a list of the element type they name; text extrema compare
the stored Unicode scalars without allocating an encoding. `sorted` accepts a
list of integer, `float`, `str` or `bytes` and returns a new stable ascending list without
changing its input. It and `sort(mut values)` use a stable merge that keeps the runs
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

```selka
# doc: expect 15
func main() -> int:
    mut values = [3, 1, 2]
    if round(3.14159, 2) != 3.14 or round(1234.5, -2) != 1200.0:
        return 0
    return sum(values) + max(values) + abs(0 - 6)
```

A bare call of a prelude name is always the prelude function, so a reader of
`len(xs)` or `sum(values)` never has to search the module for another meaning. A
module function with a prelude function's name is refused at its declaration when
its own module uses the name bare, as a call or as a function value
(`E_BUILTIN_FUNCTION_NAME`, with a note at the first such use); `selka fix`
renames it with every use, to the module's name and the old one (`shapes_sum` in
`shapes.selka`). The same holds for a re-export,
`export helpers.sum`, whose repair writes the uses `helpers.sum(...)`. A function
that its module never uses bare is accepted: a public `write` that other modules
call as `zipfile.write(...)` misleads nobody.

```selka
# doc: expect-error E_BUILTIN_FUNCTION_NAME
func sum(values: int[]) -> int:
    _ = values
    return 100

func main() -> int:
    return sum([1, 2, 3])
```

Byte-oriented code uses the managed `bytes` type; see
[managed byte strings](bytes.md) for its literals, operations and conversions.

## Keyed sorting

`values.sort(key=f, reverse=b)` sorts a list in place and
`sorted(values, key=f, reverse=b)` returns a sorted copy, spelled as in Python:
both keywords are optional and keyword-only. The key maps one element to the
value it is ordered by — any integer type, `bool`, `float`, `str`, `bytes`, or a record recursively composed of
ordered fields, compared in declaration order.

```selka
# doc: expect 42
import strings

record Player:
    name: str
    team: int
    score: float

func by_name(player: Player) -> str:
    return copy(player.name)

func by_score(player: Player) -> float:
    return player.score

public record ByTeamName:
    field_1: int
    field_2: str


func by_team_name(player: Player) -> ByTeamName:
    return ByTeamName(field_1=player.team, field_2=copy(player.name))

func main() -> int:
    mut players = [Player(name="cy", team=2, score=7.5), Player(name="al", team=1, score=9.0), Player(name="bo", team=2, score=9.0)]
    sort(mut players, key=by_score, reverse=True)
    if players[0].name != "al" or players[1].name != "bo":
        return 1
    mut by_team = sorted(players, key=by_team_name)
    if by_team[0].name != "al" or by_team[2].name != "cy":
        return 2
    mut alphabetical = sorted(players, key=by_name)
    return strings.char_count(alphabetical[2].name) * 21
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
- **Mutation requires a writable receiver**. Sorting changes that array's order;
  independently copied arrays retain their own values and order. Sorting uses
  key storage and scratch space. `sorted` returns an independent array in the
  requested order.


Pass a named function with an explicit parameter and return type as the key.
Lambda expressions receive `E_LAMBDA_REMOVED`. The checker rejects a key that does not take
one element of the list's type, one that declares its argument `mut`, and one
whose result has no order (`E_SORT_KEY`), a `reverse=` that is not a `bool`
(`E_TYPE`), and a positional or unknown argument (`E_CALL_ARGUMENT`). There is
no `cmp=`: map each element to an ordered record instead, or, for an order that no key gives (one order across types of
value, or several keys with a direction each), sort by a comparison of two elements with
[`sort.sort_by_compare`](standard-library.md#sort), which also takes a context value for the comparison.

`sort.sort_by_key(values, key)` is the same keyed sort on a copy. Because keys
are now computed in list order, a key function that traps on several elements
reports the first of them in list order; the module's earlier recursive merge
asked for keys in a different order.


A brace dialect — `fn`, `let`, `struct`, `new T { … }`, `alias::name`,
`f::<T>(x)`, `cast<T>(x)`, `//` comments — was accepted until 2026-09-13 and is
now rejected. The removed-features index (`docs/legacy/README.md`) records what each
spelling became.
