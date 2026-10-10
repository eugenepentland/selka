# mylang in one page — for Python programmers

mylang is statically typed, Python-shaped, and compiles to a native executable.
Write it like typed Python; the differences that matter are on this page, and
every example on it runs under `mylang doctest`. The compiler carries the longer
guides with it: `mylang docs` lists them and `mylang docs syntax` (or `io`,
`errors`, `tests`, `stdlib`, ...) prints one, from any directory.

## Commands

```bash
mylang check prog.my                  # type-check a program, or a library that has no main (fast)
mylang run prog.my -- ARG1 ARG2       # build and run; the program's arguments go after --
mylang build prog.my -o prog          # native executable (optimized debug build)
mylang build prog.my -o prog --release  # optimized whole program, for shipping or timing
mylang test prog.my                   # run the public test_* functions; `mylang test DIR` runs every file
mylang fmt prog.my --check            # formatter (drop --check to print the formatted file)
mylang docs primer                    # this page; `mylang --help` lists every command
```

`run`, `build` and `test` make an optimized debug build by default: one unit
per module, so an edit recompiles only what changed. Use `--unoptimized` for an optimizer-off diagnostic build. `--release` optimizes the
whole program as one unit and recompiles all of it after any change. Both keep
every overflow, cast and bounds check.
A file argument that is missing, unreadable or a directory is refused by every
command with `mylang COMMAND: cannot read 'PATH': REASON` and exit status 2.
`run` takes its budgets as `--max-steps N`, `--max-frames N`, `--timeout N` and
`--max-memory SIZE`, or as `--flag=N`; `test` takes `--max-steps`, `--max-frames` and
`--max-memory` the same way. Each frame a
`--max-frames` budget allows reserves 32 KiB of `--max-memory`, and a budget the
memory cannot hold is refused up front with the memory it needs.
When `fmt --check` fails, `path:line:column` identifies the first formatting
difference; `fmt FILE` prints the complete corrected source.

## File layout

- Files need no module header. Their paths determine module names: `calc.my`
  is `calc`, and `shared/calc.my` is `shared.calc` beneath the project root.
  `func main` marks an executable entry.
- `import util` loads `util.my` beside the entry; call `util.f(x)`. Only the
  declarations `util` marks `public` are visible. `check`, `run`, `build` and
  `test` follow the imports from a module entry by themselves.
  `check name.my` also accepts a library without `main`: it checks bodies,
  effects and public signatures as well as imports, and a file that does declare
  `main` keeps every check on it. `run` and `build` still need a `main`.
  `check-module name.my` does the same but always checks as a library and
  accepts the same headerless module source.
- Tests are `public func test_name() -> bool` (return `True` to pass), in the same
  file as the code or in `name_test.my` that does `import name` (then only
  `name`'s `public` declarations are visible). A test may take `out: Stream`
  and the capabilities `fs: Filesystem`, `clock: Clock`, `entropy: Entropy`,
  `env: Environment` and `net: Network`; the runner hands each a deterministic
  stand-in (an empty in-memory filesystem, a simulated clock, ...), never real
  authority, so I/O code is testable without host files. `mylang docs tests`
  has the table.
  A `*_test.my` entry imports its sibling directly; both `test` and `fmt`
  accept the same headerless form as other modules.
  Run `mylang test name_test.my` to select sibling tests directly. If
  `mylang test name.my` selects none, it points out an existing sibling test
  file; testing the containing directory also discovers it.

## Program shape and I/O

```mylang
# doc: check
func main(args: str[], fs: Filesystem, out: Stream, err: Stream) -> int:
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

- There is no bare `print`: take `out: Stream` / `err: Stream` parameters (only
  `main` receives them from the runtime; pass them down). `debug(x)` prints to
  stderr from anywhere, for debugging only.
- Capabilities (`fs: Filesystem`, `clock: Clock`, `env: Environment`, ...) are
  parameters of `main`; pass them to the helpers that need them. There is no
  `import sys`, `os`, `re`, `heapq` or `collections`.

## Types and declarations

```mylang
record Item:              # independent value; fields by keyword
    name: str
    count: int

record Node:              # recursive tree value
    value: int
    next: Node?

enum Color:
    red
    green

enum Shape:              # tagged union; variants carry a payload or named fields
    circle(value: float)
    rect(w: float, h: float)

func area(s: Shape) -> float:
    match s:
        case Shape.circle(value=r):
            return 3.0 * r * r
        case Shape.rect(w=w, h=h):
            return w * h
```

Construct with keywords: `Item(name="a", count=1)`, `Shape.rect(w=2.0, h=3.0)`,
`Node(value=1, next=None)`. Recursive trees and ASTs use records and unions;
graphs with identity use pool handles. Writing a field of a `record`
copy (`for it in items: it.count = 0`) is a compile error: update the owning
collection or rebuild the record. Builtin types: `int`, `float`, `bool`, `str`, `bytes`,
`T[]`, `dict[K, V]` (keys `int` or `str` only), `tuple[A, B]`, `T?`
(`Some(x)` / `None`) and `Result[T, E]` (`Ok(x)` / `Err(e)`).

A public declaration can expose only public types. `E_PRIVATE_INTERFACE` on
a `public record` means one of its fields exposes a private type: mark that
type `public` too, or keep the enclosing record private. The same rule applies
through containers and to public function signatures.

```mylang
# doc: expect 2
public record Count:
    value: int

public record ItemCount:
    count: Count

func main(out: Stream) -> int:
    mut item = ItemCount(count=Count(value=2))
    out.print(item.count.value)
    return 0
```

## Errors: Result, Option and `?`

```mylang
# doc: expect 3
func parse_pair(s: str) -> tuple[int, int] fails str:
    mut parts = s.split(",")
    if len(parts) != 2:
        fail f"bad pair: {s}"
    mut a = parse_int(parts[0].strip())          # int(str) -> int?; float(str) likewise
    mut b = parse_int(parts[1].strip())
    if a is None or b is None:         # `is None` narrows: a and b are int below
        fail "not a number"
    return (a, b)

func total(s: str) -> int fails str:
    const left, right = try parse_pair(s) # failure returns from this function
    return left + right

func main(out: Stream) -> int:
    match total("1, 2"):
        case Ok(n):
            out.print(n)
        case Err(message):
            out.print(message)
    return 0
```

There are no exception handlers. Declare expected errors with `fails`, return
success with `return`, fail with `fail`, and propagate with boundary `try`.
To retain a result for explicit comparison, use a typed declaration such as
`const expected: Result[int, str] = Ok(3)`.


A call used as a statement must return unit (`-> Unit`, or no return
annotation). `E_EXPLICIT_DISCARD_REQUIRED` means a non-unit result was ignored:
use the value, handle it, or write `_ = expression` to discard it explicitly.
For a checked result, use `match` or boundary `try` to handle failure.

```mylang
# doc: expect 1
func main(out: Stream) -> int:
    mut values = [10, 20]
    _ = values.pop()                  # pop returns the removed element
    out.print(len(values))
    return 0
```

## Collections

```mylang
# doc: expect 2 1 [[], [7]] 1
func main(out: Stream) -> int:
    mut counts: dict[str, int] = {}          # an empty literal needs a declared type
    for word in "a b a".split():
        counts[word] = counts.get(word, 0) + 1
    mut rows: int[][] = []
    rows.append([])                      # `[]` passed to a method takes its type from it
    rows.append([for n in range(1, 2) yield n * 7])
    out.print(counts["a"], counts["b"], rows, len(rows[1]))
    return 0
```

```mylang
# doc: expect {3, 1, 2} {'a': 1, 'bb': 2} 14 True
func main(out: Stream) -> int:
    mut seen = {3, 1, 2, 3}                  # a set[int]; keeps first-insertion order
    mut lengths = {w: len(w) for w in ["a", "bb"]}
    out.print(seen, lengths, sum(x * x for x in [1, 2, 3]), any(x > 2 for x in seen))
    return 0
```

- list: `append`, `pop`, `insert`, `sort(key=...)`, `len`, slices `xs[a:b]`,
  negative indexes, `x in xs`, comprehensions `[f(x) for x in xs if p(x)]`
  (two names and several `for`/`if` clauses work).
- dict: `d[k]`, `d.get(k, default)`, `k in d`, `for k, v in d.items()`
  (insertion order), `{k: v for k, v in pairs}`.
- set: `{1, 2}`, `seen: set[int] = set()`, `add`, `remove`, `discard`, `in`,
  `|` `&` `-` `^`, `issubset`, `{x for x in xs}`. Iteration and printing are in
  first-insertion order (`set()` when empty); compare `sorted(s)` when the
  order matters. See [Sets](sets.md).
- Generator arguments: `sum(x * x for x in xs)`, `any(...)`, `all(...)`,
  `min(...)`, `max(...)`, `sorted(...)`, `set(...)`, `"".join(...)`; a generator
  stored in a variable is rejected, so write a list comprehension there.
- Sorting: `sorted(xs)`, `xs.sort(key=lambda it: (-it.count, it.name))` (tuple
  keys work; a lambda cannot capture locals, so use a top-level function then).
- `min(a, b)`, `max(xs)`, `abs(n)`, `sum(xs)`, `round(x, n)`, `range(n)`,
  `range(a, b)` and `range(a, b, step)`;
  `for i, x in enumerate(xs)` and `for a, b in zip(xs, ys)` unpack in `for`
  loops and comprehensions.

## Mutating a parameter: `mut` on both sides

```mylang
# doc: expect 1
func bump(mut counts: dict[str, int], key: str):
    counts[key] = counts.get(key, 0) + 1

func main(out: Stream) -> int:
    mut counts: dict[str, int] = {}
    bump(mut counts, "x")                # the call site repeats `mut`
    out.print(counts["x"])
    return 0
```

A function that writes a list, dict or record parameter declares it `mut`, its
callers write `mut arg`, and a `mut` that is never written is an error. Mutating
locals needs nothing. The compiler's message quotes the exact fix. Two `mut`
arguments of one call must name disjoint places: `f(mut a, mut a)`,
`f(mut a, mut a[0])` and `f(mut xs[i], mut xs[j])` are `E_MUTATION_OVERLAP`,
while `f(mut s.a, mut s.b)` and `f(mut xs[0], mut xs[1])` are fine.

## Numbers, strings and bytes

```mylang
# doc: expect 3.5 -4 2 -3 2.67 b
func main(out: Stream) -> int:
    mut fixed = f"{2.675:.2f}"
    mut word = "abc"
    out.print(7 / 2, -7 // 2, -7 % 3, divtrunc(-7, 2), fixed, word[1])
    return 0
```

- `int` is 64-bit and overflow traps; `float` is binary64. Conditions must be
  `bool`: write `if len(xs) > 0:`, not `if xs:`.
- Number literals are Python's: `0xFF`, `0o17`, `0b1010`, `1_000`, `.5`, `5.`,
  `1e-3`, plus an optional width suffix (`0xFFu8`). An unsuffixed integer that
  fits the declared type needs no suffix, even in `const MASK: u32 = 0xFF00_0000`.
  A decimal integer takes no leading zero (`0755` is an error, as in Python 3),
  so write an octal mode `0o755`; there are no imaginary literals (`1j`).
- `/` is float division even on ints; `//` and `%` are Python's floor forms;
  `divtrunc` and `remtrunc` truncate like C. There is no `**`: use
  `math.pow(2.0, 10)` (`import math`, integer exponent). Comparisons chain:
  `0 < x < 10`.
- `str(n)`; `int(s)` and `float(s)` return an `Option`; `ord("a")`, `chr(98)`.
- Strings: `split`, `splitlines`, `strip`, `join`, `replace`, `find`, `count`,
  `startswith`, `lower`, `upper`, `isdigit`, `zfill`, `encode`, ... `s[i]` is a
  one-character `str`. `<` orders strings by code point, and `"ab" * 3`
  repeats. f-strings take CPython's format specs (`{x:.2f}`, `{n:>5}`,
  `{n:,}`, `{n:05d}`, `{x:.1%}`) and print exactly what CPython prints.
- `round(x, n)` rounds the exact binary value, like C and Python
  (`round(2.675, 2)` → `2.67`), except that an exact tie rounds away from zero
  (`round(0.125, 2)` → `0.13`, Python `0.12`; `f"{0.125:.2f}"` is `0.12` in both).
- Build a large string by collecting pieces in a `str[]` and
  `"".join(pieces)`. For byte-level scanning read with `fs.read_file`: `data[i]`
  is an `int`, `data[a:b]` a `bytes` slice, `.decode()` a `Result[str, ...]`.

## Not available — do this instead

| Python | mylang |
| --- | --- |
| `x ** n` | `math.pow(x, n)` (`import math`, integer exponent) |
| `gen = (x for x in xs)` kept in a variable | a list comprehension `[x for x in xs]`; generators are call arguments |
| `try:` / `except` | `fails`, prefix `try`, or an explicit result `match` |
| methods on classes, closures | top-level functions that take the object or state |
| `heapq`, `re`, `collections` | write the small helper (a binary heap over `int[]`) |
| `if x:` on a list, str or int | an explicit `bool` expression |

## Scoping

Use `const` for an immutable local and `mut` for a writable local. Declarations
belong to their enclosing block, and shadowing an active local or parameter is
rejected. Ordinary assignment updates a declared writable binding. Declare a
changing accumulator before a loop or branch if it must remain available afterward.

## Where to read more

`mylang docs TOPIC` prints each of these from the compiler itself: `syntax` (the
language guide), `io` (files, streams, capabilities), `text`, `bytes`,
`modules`, `errors` (Result and Option), `effects`, `stdlib`, `tests` and
`build`. In a large project, `mylang context ENTRY.my --symbol=module::name`
answers one bounded question about a declaration, and `mylang tests-for` and
`mylang test --affected` find the tests an edit reaches.
