# selka in one page — for Python programmers

selka is statically typed, Python-shaped, and compiles to a native executable. Write it like typed Python. Read
`selka docs card` first: the rules writers trip on, one line each. `selka docs` lists the longer guides.

## Commands

```bash
selka check prog.selka                  # type-check a program, or a library that has no main (fast)
selka run prog.selka -- ARG1 ARG2       # build and run; the program's arguments go after --
selka build prog.selka -o prog          # native executable (lean debug build)
selka build prog.selka -o prog --release  # optimized whole program, for shipping or timing
selka test prog.selka                   # run the public test_* functions; `selka test DIR` runs every file
selka fmt prog.selka --check            # formatter (--write edits in place; --diff shows changes)
selka docs primer                    # this page; `selka --help` lists every command
```

`run`, `build` and `test` make a lean debug build, so an edit recompiles only what changed. Every build keeps every
overflow, cast and bounds check.

| Flag | Effect |
| --- | --- |
| `--debug-o0` | `run`/`build`: the cheapest cold build |
| `--optimize-debug` | `run`/`build`: LLVM `-O2` |
| `--unoptimized` | `run`/`build`: no Core pass |
| `--release` | optimize the whole program as one unit; any change recompiles all of it |
| `--max-steps N`, `--max-frames N`, `--max-memory SIZE` | budgets for `run` and `test`; `run` also takes `--timeout N`; `--flag=N` works too |

Each frame a `--max-frames` budget allows reserves 32 KiB of `--max-memory`; a budget the memory cannot hold is refused up
front. A missing, unreadable or directory file argument is refused with `selka COMMAND: cannot read 'PATH': REASON`, exit
status 2. A failed `fmt --check` prints `path:line:column`, what the formatter wants and `selka fmt --write FILE`.

## File layout

- The path is the module name: `calc.selka` is `calc`, `shared/calc.selka` is `shared.calc`. No header is needed.
  `func main` marks an executable entry.
- `import util` loads `util.selka` beside the entry; call `util.f(x)`. Only what `util` marks `public` is visible.
- `check` also accepts a library without `main`; `run` and `build` need one. `check-module` always checks as a library.
- Tests are `public func test_name() -> bool` (return `True` to pass), in the same file or in `name_test.selka` that does
  `import name`. A test may take `out: Stream`, `fs: Filesystem`, `clock: Clock`, `entropy: Entropy`, `env: Environment`
  and `net: Network`, each a deterministic stand-in. `selka docs tests` has the table. `selka test name.selka` that
  selects none points at the sibling test file.

## Program shape and I/O

```selka
# doc: check
import strings

func main(args: str[], fs: Filesystem, out: Stream, err: Stream) -> int:
    if len(args) != 1: # args are the arguments only (no program name)
        print(err, "usage: prog FILE")
        return 2 # main's return value is the exit status
    match fs.read_text(args[0]): # Result[str, ...]; fs.read_file gives bytes
        case Ok(text):
            print(out, len(strings.lines(text)), "lines") # print(a, b) joins with spaces
        case Err(_):
            print(err, f"error: cannot read {args[0]}")
            return 1
    return 0
```

- There is no bare `print`: take `out: Stream` / `err: Stream` parameters (only `main` receives them; pass them down).
  `debug(x)` prints to stderr from anywhere, for debugging only.
- Capabilities (`fs`, `clock`, `env`, ...) are parameters of `main`; pass them to the helpers that need them. There is no
  `import sys`, `os`, `re`, `heapq` or `collections`.

## Types and declarations

```selka
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
        case circle(value=r):
            return 3.0 * r * r
        case rect(w=w, h=h):
            return w * h
```

Construct with keywords: `Item(name="a", count=1)`, `Shape.rect(w=2.0, h=3.0)`, `Node(value=1, next=None)`. Builtin
types: `int`, `float`, `bool`, `str`, `bytes`, `T[]`, `dict[K, V]` and `set[K]` (structural hashable keys), `T?`
(`Some(x)` / `None`) and `Result[T, E]` (`Ok(x)` / `Err(e)`). Graphs with identity use pool handles.

A loop binding borrows its element for reading: `for it in items: it.count = 0` is a compile error. Update the owning
collection outside the loop.

A public declaration can expose only public types: `E_PRIVATE_INTERFACE` on a `public record` means a field exposes a
private type, also through containers and in function signatures. Mark that type `public`.

## Errors: Result, Option and `try`

```selka
# doc: expect 3
import strings

record ParsedPair:
    left: int
    right: int

func parse_pair(s: str) -> ParsedPair fails str:
    mut parts = strings.split(s, ",")
    if len(parts) != 2:
        fail f"bad pair: {s}"
    mut a = parse_int(strings.strip(parts[0]))    # parse_int(str) -> int?; parse_float(str) likewise
    mut b = parse_int(strings.strip(parts[1]))
    if a is None or b is None:         # `is None` narrows: a and b are int below
        fail "not a number"
    return ParsedPair(left=a, right=b)

func total(s: str) -> int fails str:
    const pair = try parse_pair(s) # failure returns from this function
    return pair.left + pair.right

func main(out: Stream) -> int:
    match total("1, 2"):
        case Ok(n):
            print(out, n)
        case Err(message):
            print(out, message)
    return 0
```

There are no exception handlers. Declare expected errors with `fails`, succeed with `return`, fail with `fail`, and
propagate with `try`: a statement's whole value, or a call's argument (`print(out, try total(s))`), never an operand.

A call used as a statement must return unit. `E_EXPLICIT_DISCARD_REQUIRED` means a non-unit result was ignored: use it,
handle it, or write `_ = expression`.

## Collections

```selka
# doc: expect 2 1 [[], [7]] 1
import dicts
import strings

func main(out: Stream) -> int:
    mut counts: dict[str, int] = {}          # an empty literal needs a declared type
    for word in strings.words("a b a"):
        counts[word] = dicts.get(counts, word, 0) + 1
    mut rows: int[][] = []
    mut seed: int[] = []
    append(mut rows, own seed)           # an empty list needs its declared type first
    mut collected: int[] = []
    for n in range(1, 2):
        append(mut collected, n * 7)
    append(mut rows, own collected)
    print(out, counts["a"], counts["b"], rows, len(rows[1]))
    return 0
```

A function that keeps its argument takes it as an `own` parameter; the caller writes `own x` for a name it is finished
with, or passes a fresh value bare. A function that only reads takes a plain parameter; one that returns part of it says
`-> T from p`. Write `copy(x)` only when caller and callee must both keep the value.

```selka
# doc: expect 1 a 1
record Row:
    name: str

func add(mut rows: Row[], own row: Row):     # keeps its argument: `own`
    append(mut rows, own row)

func name_of(row: Row) -> str from row:      # lends part of its argument
    return row.name

func main(out: Stream) -> int:
    mut rows: Row[] = []
    const row = Row(name="a")
    add(mut rows, own row)                   # `row` is finished: it moves
    mut backup: Row[] = []
    add(mut backup, copy(rows[0]))           # both lists keep a row: a copy
    print(out, len(rows), name_of(rows[0]), len(backup))
    return 0
```

- list: `append(mut xs, own x)`, `sort(mut xs, key=...)` and `len(xs)` are bare; `lists.pop`, `lists.insert` and
  `lists.contains` need `import lists` (a bare `pop` is `E_UNKNOWN_SYMBOL`). Indexes are nonnegative.
- dict: `d[k]`, `dicts.get(d, k, default)`, `k in d`, `for k, v in dicts.items(d)` (insertion order).
- set: `{1, 2}`, `set()`, `add`, `remove`, `discard`, `in`, `|` `&` `-` `^`, `issubset`; iteration follows
  first-insertion order. See [Sets](sets.md).
- `sorted(xs)`, `min(a, b)`, `max(xs)`, `abs(n)`, `sum(xs)`, `round(x, n)`, `range(a, b, step)`, `enumerate(xs)` and
  `zip(xs, ys)`; a `sort` key is a named function with typed parameters.

## Mutating a parameter: `mut` on both sides

```selka
# doc: expect 1
import dicts

func bump(mut counts: dict[str, int], key: str):
    counts[key] = dicts.get(counts, key, 0) + 1

func main(out: Stream) -> int:
    mut counts: dict[str, int] = {}
    bump(mut counts, "x")                # the call site repeats `mut`
    print(out, counts["x"])
    return 0
```

A function that writes a list, dict or record parameter declares it `mut`, and its callers write `mut arg`. Mutating
locals needs no marker. A missing or extra call-site marker carries its exact fix.

Two `mut` arguments of one call must name disjoint places, or the call is `E_SINGLE_OWNER_OVERLAP`:

- Refused: `f(mut a, mut a)`, `f(mut a, mut a[0])`, indices Core cannot prove disjoint, and a lent text, list or record
  field beside a `mut` sibling of one list element, `f(xs[0].name, mut xs[0].n)` (pass `f(mut xs[0])` instead).
- Accepted: different fields of one local, `f(mut s.a, mut s.b)`; distinct literal indices, `f(mut xs[0], mut xs[1])`.

A call in an index can conflict with its receiver's borrow too: `items[selected(mut items)] = 9` is refused (a simple case
carries a [split repair](tooling/fix.md#structured-fixes-in-diagnostics)).

## Stating what code expects and promises

```selka
# doc: expect 71
import lists

@requires(len(items) > 0, "nothing to take")    # what a caller must supply
@ensures(result == old(items[len(items) - 1]))  # `result` is the return value; `old(...)` is the value at entry
@ensures(len(items) == old(len(items)) - 1)
func take_last(mut items: int[]) -> int:
    return lists.pop(mut items)

@invariant(self.low <= self.high, "a range never runs backwards")  # true of every Range
record Range:
    low: int
    high: int

func middle(r: Range) -> int:
    const mid = (r.low + r.high) // 2
    assert r.low <= mid and mid <= r.high   # a fact at this point; `assert cond, "message"` names it
    return mid

func main() -> int:
    mut items = [5, 7]
    return take_last(mut items) * 10 + len(items) + middle(Range(low=0, high=0))
```

- `@requires` constrains the arguments, `@ensures` promises the result and the `mut` parameters at return, `@invariant`
  holds for every `record` value, `assert` states a fact at one point. A failure the caller is not to blame for is a
  `Result`.
- A broken clause traps with exit status 1: `R_ASSERT`, `R_REQUIRES`, `R_ENSURES` or `R_INVARIANT`. A condition only
  observes (`E_CONTRACT_EFFECT`). [Contracts](contracts.md) has the rest.

## Numbers, strings and bytes

```selka
# doc: expect 3.5 -4 2 -3 2.67 b
import strings

func main(out: Stream) -> int:
    mut fixed = f"{2.675:.2f}"
    mut word = "abc"
    print(out, 7 / 2, -7 // 2, -7 % 3, divtrunc(-7, 2), fixed, strings.char_at(word, 1))
    return 0
```

- `int` is 64-bit and overflow traps; `float` is binary64. Conditions must be `bool`: `if len(xs) > 0:`, not `if xs:`.
- Literals are Python's (`0xFF`, `0o17`, `0b1010`, `1_000`, `.5`, `1e-3`) plus an optional width suffix (`0xFFu8`). An
  unsuffixed integer that fits the declared type needs no suffix. `0755` is an error: write `0o755`. There are no
  imaginary literals.
- `/` is float division even on ints; `//` and `%` are Python's floor forms; `divtrunc` and `remtrunc` truncate like C.
  Comparisons chain: `0 < x < 10`.
- `str(n)`; `parse_int(s)` and `parse_float(s)` return an `Option` (`int(s)` and `float(s)` on text are
  `E_NUMERIC_PARSE`); `ord("a")`, `chr(98)`.
- `s[i]` is the octet at byte offset `i`, an `int` (see [text](text.md)); `strings.char_at(s, i)` is the one-scalar `str`
  at a scalar position. Compare an octet with `ord` of a one-character literal: `data[i] == ord("G")`. `<` orders strings
  by code point. f-strings take CPython's format specs (`{x:.2f}`, `{n:>5}`, `{n:,}`, `{n:05d}`, `{x:.1%}`).
- `round(x, n)` rounds the exact binary value; an exact tie rounds away from zero (`round(0.125, 2)` is `0.13`, Python
  `0.12`). `data[a:b]` is a `bytes` slice, `strings.decode(data)` a `Result[str, ...]`; see
  [walking the lines of a file](bytes.md#walking-the-lines-of-a-file).

## Not available — do this instead

| Python | selka |
| --- | --- |
| `x ** n` | `math.pow(x, n)` (`import math`, integer exponent) |
| `"ab" * 3`, `[0] * n` | `strings.repeat("ab", 3)`, `lists.filled(n, 0)`, `byte_builder.repeat` (`E_REPETITION_REMOVED`) |
| `"".join(pieces)` | `strings.join(pieces, "")` (`E_METHOD_REMOVED`) |
| `x in xs` on a list | `lists.contains(xs, x)` (`E_LIST_MEMBERSHIP_REMOVED`); `in` works on `str`, `dict`, `set`, `bytes` |
| `xs[-1]` | `xs[len(xs) - 1]` (`E_NEGATIVE_INDEX_REMOVED`) |
| `a if c else b` | an `if` / `else` statement (`E_CONDITIONAL_EXPRESSION_REMOVED`) |
| `[f(x) for x in xs]`, `lambda`, generators | a typed accumulator with a `for` loop (keep early exit for `any`/`all`); a named `func` |
| `(a, b)`, `a, b = b, a` | a `record` with named fields (`E_TUPLE_REMOVED`) |
| `try:` / `except` | `fails`, prefix `try`, or a result `match` |
| classes with methods, closures | top-level functions that take the object or state |
| `heapq`, `re`, `collections` | write the helper |
| `if x:` on a list, str or int | an explicit `bool` expression |

## Scoping

`const` is an immutable local, `mut` a writable one. Declarations belong to their enclosing block; shadowing an active
local or parameter is rejected. Declare an accumulator before the loop or branch that fills it.

## Where to read more

`selka docs TOPIC` prints `syntax`, `io`, `text`, `bytes`, `modules`, `errors`, `effects`, `contracts`, `stdlib`, `tests`
or `build`. In a large project, `selka context ENTRY.selka --symbol=module::name` answers one question about a
declaration; `selka test --affected` finds the tests an edit reaches.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/primer.md).
