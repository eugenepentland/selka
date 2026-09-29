# mylang in one page — for Python programmers

mylang is statically typed, Python-shaped, and compiles to a native executable. Write
it like typed Python; the differences that matter are all on this page. Every snippet
below compiles on the installed compiler. The full docs (`docs/`) are the reference
if you need more.

## Commands

```bash
mylang check prog.my                 # type-check only (fast)
mylang run prog.my -- ARG1 ARG2      # build natively and run; args after --
mylang build prog.my -o prog         # native executable (multi-file: add --project)
mylang test prog.my                  # run public test_* functions (see layout below)
mylang fmt-module prog.my --check    # formatter for a file with a `module` header
```

## File layout — read this first

- A file may start with `module NAME`. **NAME must equal the file name** without `.my`
  (`calc.my` → `module calc`). `def main` is unrelated to the module name.
- `check`/`run`/`build` accept a file with no header. **`mylang test` needs the header**
  (or a file named `*_test.my`). Simplest: always write `module <filename>` on line 1.
- Tests are `public def test_name() -> bool` (return `True` to pass), in the same file
  as the code or in `name_test.my` that does `import name` (then only `public`
  declarations of `name` are visible). A test may take `out: Stream`; it can **not**
  receive `Filesystem`, `Clock`, etc., so test pure functions and keep I/O in `main`.
- Other files: `import util` loads `util.my` next to the entry; call `util.f(x)`;
  `util` must mark shared declarations `public`. Build with `--project`.

## Program shape and I/O

```mylang
module prog

def main(args: list[str], fs: Filesystem, out: Stream, err: Stream) -> int:
    if len(args) != 1: # args are the arguments only (no program name)
        err.print("usage: prog FILE")
        return 2 # main's return value is the exit status
    match fs.read_text(args[0]): # Result[str, ...]; fs.read_file gives bytes
        case Ok(text):
            out.print(len(text.splitlines()), "lines") # print(a, b) joins with spaces
        case Err(_):
            err.print(f"error: cannot read {args[0]}")
            return 1
    return 0
```

- There is no bare `print`: take `out: Stream` / `err: Stream` parameters (only `main`
  receives them from the runtime; pass them down). `debug(x)` prints to stderr from
  anywhere without a parameter — for debugging only.
- Capabilities (`fs: Filesystem`, `clock: Clock`, …) are parameters of `main`; pass
  them to helpers that need them. No `import sys`/`os`/`re`/`heapq`/`collections`.

## Types and declarations

```mylang
record Item:              # value type: copied on assignment; fields by keyword
    name: str
    count: int

class Node:               # reference type: use for shared/mutable or recursive data
    value: int
    next: Option[Node]

enum Color:
    red,
    green

union Shape:              # tagged union; variants carry a payload or named fields
    circle: float,
    rect(w: float, h: float)

def area(s: Shape) -> float:
    match s:
        case Shape.circle(r):
            return 3.0 * r * r
        case Shape.rect(w, h):
            return w * h
```

Construct with keywords: `Item(name="a", count=1)`, `Shape.rect(w=2.0, h=3.0)`,
`Node(value=1, next=None)`. Recursive data (trees, ASTs) must go through a `class`
(a `union` may name a class declared above it). Writing a field of a `record` copy
(`for it in items: it.count = 0`) is a compile error — use `class` or rebuild the record.

Builtins: `int`, `float`, `bool`, `str`, `bytes`, `list[T]`, `dict[K, V]` (keys `int` or
`str` only), `tuple[A, B]`, `Option[T]` (`Some(x)` / `None`), `Result[T, E]` (`Ok(x)` /
`Err(e)`).

## Errors: Result, Option and `?`

```mylang
def parse_pair(s: str) -> Result[tuple[int, int], str]:
    parts = s.split(",")
    if len(parts) != 2:
        return Err(f"bad pair: {s}")
    a = int(parts[0].strip())          # int(str) -> Option[int]; float(str) likewise
    b = int(parts[1].strip())
    if a is None or b is None:         # `is None` narrows: a and b are int below
        return Err("not a number")
    return Ok((a, b))

def total(s: str) -> Result[int, str]:
    a, b = parse_pair(s)?              # `?` returns the Err early; tuples unpack
    return Ok(a + b)
```

No exceptions or `try`. Comparing with a literal `Ok(...)` needs a typed binding:
`expected: Result[int, str] = Ok(3)` then `total("1,2") == expected`.

## Collections

- Empty literals need a declared type: `xs: list[int] = []`, `d: dict[str, int] = {}`.
  `[]` passed straight into a call (`rows.append([])`, `byte_buffer([])`) is rejected
  (`E_LIST_INFERENCE`): bind an annotated local first and pass that.
- list: `append`, `pop`, `insert`, `sort(key=...)`, `len`, slicing `xs[a:b]`, negative
  indexes, `x in xs`, list comprehensions `[f(x) for x in xs if p(x)]`.
- dict: `d[k]`, `d.get(k, default)`, `k in d`, `for k, v in d.items()` (insertion order).
- Sorting: `sorted(xs)`, `xs.sort(key=lambda it: (-it.count, it.name))` (tuple keys
  work; a lambda cannot capture locals — use a top-level function for that).
- `min(a, b)`, `max(xs)`, `abs(n)`, `sum(xs)`, `range(n)` / `range(a, b)`;
  `for i, x in enumerate(xs)` and `for a, b in zip(xs, ys)` unpack in `for` loops
  (a comprehension takes a single name).

## Mutating a parameter: `mut` on both sides

```mylang
def bump(counts: mut dict[str, int], key: str):
    counts[key] = counts.get(key, 0) + 1

def use_it() -> int:
    counts: dict[str, int] = {}
    bump(mut counts, "x")              # the call site repeats `mut`
    return counts["x"]
```

A function that writes a list/dict/class parameter must declare it `mut`, callers
write `mut arg`, and a `mut` that is never written is an error. Mutating locals needs
nothing. The compiler's message always quotes the exact fix.

## Numbers

- `int` is 64-bit (overflow traps), `float` is binary64. Conditions must be `bool`:
  write `if len(xs) > 0:`, not `if xs:`.
- `/` is float division even on ints (`7 / 2 == 3.5`). `//` and `%` are Python's
  floor forms (`-7 // 2 == -4`, `-7 % 3 == 2`). C-style truncation:
  `divtrunc(-7, 2) == -3`, `remtrunc(-7, 3) == -1`.
- No `**`: `math.pow(2.0, 10) == 1024.0` (`import math`; integer exponent).
- `str(n)`, `int(s)` / `float(s)` (both return `Option`), `ord("a")`, `chr(98)`.

## Strings and bytes

- Methods: `split()`/`split(",")`, `splitlines`, `strip`/`lstrip`/`rstrip`, `join`,
  `replace`, `find`, `count`, `startswith`/`endswith`, `lower`/`upper`, `isdigit`,
  `isalpha`, `isspace`, `zfill`, `encode`. f-strings interpolate expressions
  (`f"{a + 1} {name}"`) but take **no format spec** (`{x:.2f}` is rejected).
- `s[i]` is a one-character `str`; `==` works on strings but `<`/`>` do not (sorting
  lists of strings with `sorted` does).
- Fixed decimals: `strings.format_float(x, 2)` returns `Result[str, ...]`
  (`import strings`). Caution: it rounds the shortest decimal text half away from zero
  (`2.675 → "2.68"`, `0.125 → "0.13"`, `-0.001 → "0.00"`), unlike C/Python `%.2f`.
- Building a large string: collect pieces in a `list[str]` and `"".join(pieces)`;
  `+` in a loop copies every time. For byte-level scanning of big inputs, read with
  `fs.read_file` (bytes): `data[i]` is an `int`, `data[a:b]` a `bytes` slice,
  `.decode()` returns `Result[str, ...]`.

## Not available — do this instead

| Python | mylang |
| --- | --- |
| `set()` | `dict[str, bool]` |
| dict/set comprehension, generator expression | a loop, or a list comprehension |
| `range(a, b, step)` | `while` loop |
| `x ** n`, `round(x, n)` | `math.pow(x, n)`; `strings.format_float` for display |
| `"ab" * 3`, `"a" < "b"` | a loop; compare via `sorted`, `ord`, or char by char |
| `try/except` | `Result` + `?` |
| methods on classes, closures | top-level functions taking the object/state |
| `heapq`, `re`, `collections` | write the small helper (e.g. a binary heap over `list[int]`) |
| `if x:` on a list/str/int | an explicit `bool` expression |

## Scoping

Locals are function-scoped like Python, but reading a name on a path where it might
not be assigned yet is a compile error (`E_UNBOUND`): assign a default before a loop
or `if` that sets it (`best = 0` before the loop).
