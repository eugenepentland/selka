# The language

This is the language guide. There is one syntax: `func`, `record`, indentation and `#` comments. The compiler checks types before execution and manages lists, strings and dictionaries through checked ownership and deterministic cleanup, with no allocator arguments and no garbage collector. Ordinary parameters borrow for reading, `own` marks a transfer, `copy(value)` makes an independent value and `mut` an exclusive writable argument.

A file imports modules directly; its module name comes from its path and needs no module header. Save this as `main.selka` and run `selka run main.selka --print-result`, which prints `42` (without the flag, `run` prints only what the program prints):

```selka
# doc: expect 42
import math

func main() -> int:
    return math.clamp(99, 0, 42)
```

Write four-space indentation, `True`, `False`, `None` and `and`/`or`/`not`. Each statement ends at its newline; semicolons and tabs in indentation are rejected. Only parenthesized expressions and collection literals continue across lines, not a binary operator or a trailing backslash (`E_INDENTATION` and `E_TOKEN` say to write parentheses; `selka fix` writes them). `pass` is an empty suite, and an omitted return annotation means `Unit`.

`const name = value` is immutable and `mut name = value` writable. Annotate when inference is ambiguous (`mut counts: dict[str, int] = {}`). Parameters, record fields and non-unit return types are annotated, and reassigning an `int` local to a string is an error. Explicit type arguments are square: `f[T](x)`, `Box[int](value=1)`. Fixed-width conversions `i64(x)` and `u8(x)` range-check at run time, as `int(x)` and `float(x)` do.

For managed values, `const alias = owner` borrows read-only until `alias`'s last use; `const next = own owner` and `mut next = own owner` transfer. A named value also needs `own` when stored or passed to an owning parameter (`rows[i] = own row`, `Row(items=own items)`, `Some(own items)`, `take(own items)`). A bare `return items` is exempt, and calls, literals, operators, `copy(...)` and scalars never take `own`. A missing or misplaced marker is `E_OWN_MARKER`. `own record.items` consumes the whole record; `copy(record.items)` keeps it. `-> T from source` declares a read-only result borrowed from a parameter ([ownership rules](ownership-rules.md)).

Functions take positional and keyword arguments with defaults ([functions](functions.md)):

```selka
# doc: check
func offset(value: int, amount: int = 2) -> int:
    return value + amount

# offset(value=40) returns 42
```

Arguments evaluate once, in written order, even when keywords reorder them. Defaults are immutable numeric, boolean, string or `None` literals, and required parameters come first. Intrinsics need positional arguments. A callback parameter declared `named` requires its label; `named` before `:` is a name, `named named: int` the modifier and then the name.

`int` is a checked signed 64-bit integer; `u8` to `u64` and `i8` to `i64` serve binary formats and host interfaces. An unsuffixed literal adopts an expected integer type, also in a `const`; literals take Python's spellings and a width suffix such as `0xFFu8` ([integer literal spellings](integer-operations.md#integer-literal-spellings)). `float` is binary64 (`1.5`, `.5`, `5.`, `4.2e1`). `/` produces a float; `//` rounds down and `%` follows it; `divtrunc(a, b)` and `remtrunc(a, b)` round toward zero. Float-to-int conversion truncates toward zero and traps outside the signed range. `sqrt`, `floor`, `ceil`, `trunc` and `abs` take a `float`, `round` is a [prelude builtin](#prelude-builtins), and `exp`, `log` and the trigonometric functions are not provided.

```selka
# doc: expect 42
func main() -> int:
    mut spread = -7
    mut floored = spread // 2
    mut toward_zero = divtrunc(spread, 2)
    return (toward_zero - floored) * 42
```

### Operators Python has

Comparisons chain: `low <= x < high` means `low <= x and x < high`, each operand evaluated once and the rest skipped once a link is false. `str` and `bytes` [order lexicographically](text.md#ordering-and-repetition). Repeat with `strings.repeat(text, count)`, `byte_builder.repeat(data, count)` and `lists.filled(count, value)`.

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

Integers have no bit operators: `&`, `|` and `^` are refused (`selka fix` rewrites each to its call). Use `bit_and`, `bit_or`, `bit_xor`, `bit_not(value)`, `shift_left(value, count)` and `shift_right(value, count)` ([combine bits](integer-operations.md#bitwise-and-shift-helpers)). On two [sets](sets.md#set-operators) of one type `|`, `&`, `-` and `^` are union, intersection, difference and symmetric difference.

```selka
# doc: expect 42
func main() -> int:
    mut flags = bit_or(6, 1)
    mut mask = bit_and(12, 10)
    if bit_or(1, bit_xor(2, bit_and(3, 1))) != 3 or bit_xor(5, 3) != 6:
        return 1
    return flags * mask - 14
```

Other C operators are refused at the token, with no `selka fix` edit:

- `**`, `<<`, `>>` and their `=` forms: write a multiplication loop (`math.pow(x, n)` for a `float`) and `shift_left` / `shift_right`;
- `x++`, `x--`: write `x += 1`, `x -= 1`;
- `&=`, `|=`, `^=`: rebind a set with its operator, or write `x = bit_or(x, y)` (`bit_and`, `bit_xor`) for an integer;
- `~x`: write `bit_not(x)`;
- `a ? b : c`: declare the result first and assign it in an `if`/`else` (`?` after a value only passes a failure on).

Lists infer a homogeneous element type from nonempty literals: `append(mut items, value)`, `len(items)`, `items[index]`, `items[index] = value`, `items[start:end]`. Indexes and slice bounds must be nonnegative (`len(items) - k` counts from the end); a computed negative position traps and upper bounds clamp. A slice copies its elements.

Strings are immutable UTF-8 text in single or double quotes; indexing and length count octets ([text](text.md)). Text operations are `strings` functions, a set's writes are `sets.add`, `remove`, `update`, `pop` and `clear`, and the Python method spellings (`text.encode()`, `", ".join(parts)`) are `E_METHOD_REMOVED` (`selka fix` writes the function and its import). `parse_int(text)` and `parse_float(text)` return `int?` and `float?`, `None` for a string that is not exactly one number. An `f"..."` literal interpolates `{expression}` holes as `str(value)` does, with an optional CPython [format specification](text.md#format-specifications) (`f"{price:.2f}"`, `f"{n:05d}"`):

```selka
# doc: expect 42
func label(count: int, items: int[]) -> str:
    return f"total {count} of {len(items)}"

func main() -> int:
    if label(7, [1, 2, 3]) == "total 7 of 3":
        return 42
    return 0
```

Dictionaries keep insertion order and take any [hashable](sets.md#hashable-keys) key: `counts[key]`, `counts[key] = value`, `dicts.get(counts, key, fallback)`, `dicts.keys(counts)`, `dicts.values(counts)`, `dicts.items(counts)`. The last three are ephemeral views for direct loops and immediate `len`, `in`, `list`, `set` and `sorted`; `list(dicts.values(counts))` stores a snapshot, and storing a view or naming a view type in an annotation is `E_VIEW_STORED`. `key in counts` and `substring in text` support `not in`; lists use `lists.contains(items, value)`.

Build collections with a typed accumulator and explicit `for` and `if` statements. Comprehensions are `E_COMPREHENSION_REMOVED`, generator expressions `E_GENERATOR_REMOVED`; `selka fix` rewrites certain list comprehensions.

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

`for value in items`, `for index, value in enumerate(items)` and `for index in range(end)` / `range(start, end)` / `range(start, end, step)` support `break` and `continue` (a [stepped range](range-iteration.md#stepped-ranges) counts down for a negative step). `x in range(a, b)` is refused: write `a <= x < b`. Iteration borrows its source for reading and it cannot be mutated meanwhile: `copy(value)` an element to store it, or use an index loop:

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

A `record` is a value with annotated fields and named construction, `Node(value=42, children=[])`: no inheritance, methods or implicit `self`. An `enum` declares closed cases with named payload fields: `Kind.first`, `Kind.some(value=x)`, matched as `case some(value=x)`; a generic variant names its template, `Slot.some(value=x)` ([records, unions and enums](records-and-unions.md), [case names](records-and-unions.md#case-names)).

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

`FixedArray[T, N]([elements])` builds a fixed array, checked statically; the enum-indexed table `[Kind]T` is a dict literal keyed by `Kind.case` and needs every case exactly once.

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

There are no tuples, destructuring or parallel assignment (`E_TUPLE_REMOVED`; see [record replacements](tuples.md)); the two-name loops over `enumerate`, `zip` and `dicts.items()` stay.

`assert condition` and `assert condition, "message"` trap `R_ASSERT` when false, in release builds too: use them for invariants a caller cannot violate, and `Result` for errors it can. `case _` covers every variant no earlier arm named; it must be last, cover at least one variant, and not drop a payload that carries an unhandled result. A `while True` loop with no `break` never falls through, so no trailing `return` is needed after it.

Checked errors are the one extension to Python syntax; `const value = try checked(42)` propagates an error when the enclosing function declares a compatible `fails` type ([results and options](results-and-options.md)):

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

`T?` is an optional value, `Some(value)` or contextual `None`. Procedures use `Unit` and the value `()`. Generics use square brackets, `func identity[T](value: T) -> T:`; calls infer type arguments or take them explicitly, `identity[int](2)`.

`print(out, values..., sep=, end=)` writes its arguments separated by spaces with a trailing newline. The entry point declares its stream, `func main(out: Stream) -> int`; bare `print(...)` is `E_OUTPUT_CAPABILITY`. The `int` result is the exit status. The entry point asks for a `Filesystem` by parameter type, and every file call takes it first: `with open(fs, path, "rb") as f:`. `selka run` grants the filesystem, clock, entropy and environment by default; `--restrict` withholds them and turns on the `--allow-*` flags ([printing, files and command-line authority](io.md)).

## Declaration forms Python spells differently

Each is rejected with a message that names the accepted spelling:

- **A module constant** needs `const` and a type: a bare `MAX = 42` and an untyped `const MAX = 42` are `E_SYNTAX`; write `const MAX: int = 42` (an immutable scalar literal, visible to every function in the file). `selka fix` inserts the type for a plain literal.
- **A method**: `class Point:` with `__init__` is `E_SYNTAX`. Write a top-level function taking the record first, `func norm1(p: Point) -> int:`, and call `norm1(p)`.
- **`from module import name`** is `E_SYNTAX`: `import math` and name its exports through the module, or declare a `record`.
- **Enum cases** occupy separate lines with named payload fields: `Event.count(value=3)`, bound by `case count(value=count)`.

Two of them as the compiler reports them:

```selka
# doc: expect-error E_SYNTAX
MAX = 42
```

```selka
# doc: expect-error E_SYNTAX
from dataclasses import dataclass
```

## Selecting a value

Assign a named result in an `if` or `match` statement: declare it with its type before the branches, and every continuing branch must initialize it. A function can also return directly from each branch.

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

Conditional expressions (`a if condition else b`, `if condition then a else b`) are `E_CONDITIONAL_EXPRESSION_REMOVED`, and match expressions with `yield` arms `E_MATCH_EXPRESSION_REMOVED`. `selka fix` rewrites only where evaluation order is preserved; at a short-circuit operand or another uncertain site, write the statement form by hand.

## Statement forms Python spells differently

Each rejection names the accepted spelling:

| Python habit | Selka |
| --- | --- |
| `x = y = 21` | `const x = 21` then `const y = 21` |
| `del xs[0]` | `_ = lists.pop_at(mut xs, index)`; `_ = dicts.pop(mut d, key)` for a dictionary |
| `try:` / `except` | `-> T fails E` and a `match` on the call: `case Ok(value)` / `case Err(reason)` |
| `r"a\nb"` | an ordinary string with the escape written out |
| Optional presence | `if r is None:` or `match r:` with `case None` |
| `case Some(3):` | `case 3:` in a match on an `int`, `str`, `bytes` or `bool` |
| `parse(s).unwrap()` | `const v = try parse(s)` or a result `match` |
| `if (n := len(xs)) > 2:` | `const n = len(xs)` on its own line, then the test |
| `if __name__ == "__main__":` | nothing: `selka run` calls `func main()` |
| a loop `else`, a nested `func` | a flag declared outside the loop, a top-level function |

```selka
# doc: expect-error E_SYNTAX
func main() -> int:
    mut xs = [1, 2, 3]
    del xs[0]
    return len(xs)
```

## One command shape

`selka run <entry.selka>` runs standalone files and module entries alike (`run-project` is an alias): it detects `import` and `export` and loads the reachable project. An entry point may declare `args: str[]` first. Compiler and runtime options go before a separating `--`; every value after it is a guest argument, option-looking values included.

`selka build <entry.selka> --run` and an executable built with `-o` share the native runtime and exit-status rule; `build --run` detects a module entry like `run`, while a persistent module build still needs `--project`. An installed executable passes every OS argument after `argv[0]` to the guest unchanged and reads its runtime controls from `SELKA_OPTIONS`. `selka test` reports the test runner's aggregate status, and guest tests receive no ambient capabilities.

A missing grant under `--restrict` is caught before `main` runs, with the same message from `run`, `build --run` and a built executable: it names the `--allow-*` flag to pass, and the process exits 2. `with` opens a file and closes it at the block's end ([files](io.md#files)); `with arena():` is `E_ARENA_REMOVED`: remove the line and dedent its body.

The standard modules ship inside the compiler and are imported by name (`math`, `strings`, `sort`, `path`, `json`, `csv`, `http`, `time`); the [standard library](standard-library.md) lists them.

This is a statically checked Python-style language, not a Python interpreter:

- Names belong to their block, and active locals and parameters cannot be shadowed.
- Integers have fixed width, conditions require booleans, and records are values that compare structurally (with fixed arrays, unions, `Result` and `Option`) by `==`/`!=`. There are no reference types: `class` is rejected.
- Float division by zero gives an infinity or NaN, not an exception.
- A slice is contiguous, so stepped slices are refused in favour of `strings.char_stride` and `lists.stride`; a text slice is a view, copied into a record, list or dictionary with `copy(value)`.
- `fmt --check` is nonzero when the input differs from the canonical layout; text the formatter cannot reproduce faithfully is `E_FORMAT_VERIFY` (exit 2) and nothing is written ([the formatter](tooling/formatter.md)).

## Prelude builtins

The everyday Python builtins are prelude names (no import; a local binding of the same name wins): `sum`, `min`, `max`, `sorted`, `abs`, `round`, `any`, `all`, `reversed`, `list` and `zip`.

- `sum`, `any`, `all`, `min` and `max` take a list; an empty `min`/`max` traps `R_LIST_BOUNDS`, and the Boolean folds stop as soon as the answer is known.
- `sorted` takes a list of integer, `float`, `str` or `bytes` and returns a new stable ascending list; `sort(mut values)` sorts in place. Floats: NaNs follow ordered values, and equal values and signed zeros keep input order. Both take `key=` and `reverse=` ([keyed sorting](#keyed-sorting)).
- `reversed(xs)` copies a list or string last to first and, like `zip(a, b)`, is a `for` source; `zip` stops at the shorter list. `list(range(...))` materializes a range.

`round(value)` answers the nearest integral `float`, halves away from zero. `round(value, ndigits)` rounds the exact binary value to `ndigits` decimals (a negative count rounds left of the point): `round(2.675, 2)` is `2.67` as in CPython, but an exact tie differs: `round(0.125, 2)` is `0.13` where CPython says `0.12`. `abs` is total for `int` except the signed minimum, which traps `R_OVERFLOW`.

```selka
# doc: expect 15
func main() -> int:
    mut values = [3, 1, 2]
    if round(3.14159, 2) != 3.14 or round(1234.5, -2) != 1200.0:
        return 0
    return sum(values) + max(values) + abs(0 - 6)
```

A bare call of a prelude name is always the prelude function, so a module function with that name is `E_BUILTIN_FUNCTION_NAME` when its own module uses the name bare, as a call or a function value; `selka fix` renames it with every use (`shapes_sum` in `shapes.selka`), and a re-export `export helpers.sum` is repaired to `helpers.sum(...)`. A function its module never uses bare is accepted: a public `write` called as `zipfile.write(...)` misleads nobody.

```selka
# doc: expect-error E_BUILTIN_FUNCTION_NAME
func sum(values: int[]) -> int:
    _ = values
    return 100

func main() -> int:
    return sum([1, 2, 3])
```

## Keyed sorting

`values.sort(key=f, reverse=b)` sorts in place and `sorted(values, key=f, reverse=b)` returns a sorted copy; both keywords are optional and keyword-only. The key maps an element to an integer type, `bool`, `float`, `str`, `bytes`, or a record of ordered fields, compared in declaration order.

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

- The key is called once per element, in list order, before any element moves; a key that traps stops the program with the first trap in list order and leaves the list unchanged.
- The sort is stable, with and without `reverse`: equal keys keep their original order, so `reverse=True` is not sorting and then reversing.
- Floats: `-0.0` equals `0.0` and every NaN sorts after every other value, so `reverse=True` puts the NaNs first.
- Without a key, `sort(reverse=True)` and `sorted(values, reverse=True)` order an integer, `float`, `str` or `bytes` list by its elements.
- Sorting in place needs a writable receiver; `sorted` returns an independent list.

The key is a named function with an explicit parameter and return type; lambdas are `E_LAMBDA_REMOVED`. `E_SORT_KEY` is a key that does not take one element of the list's type, declares its argument `mut`, or returns a type with no order; a `reverse=` that is not a `bool` is `E_TYPE`, and a positional or unknown argument `E_CALL_ARGUMENT`. There is no `cmp=`: map each element to an ordered record, or use [`sort.sort_by_compare`](standard-library.md#sort), which takes a context value. `sort.sort_by_key(values, key)` is the same keyed sort on a copy.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/python-syntax.md).
