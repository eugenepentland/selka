# selka in one page — for Python programmers

selka is statically typed, Python-shaped, and compiles to a native executable.
Write it like typed Python; the differences that matter are on this page, and
every example on it runs under `selka doctest`. Read `selka docs card` first: the rules writers
trip on, one line each, in 6,000 characters. The compiler carries the longer
guides with it: `selka docs` lists them and `selka docs syntax` (or `io`,
`errors`, `tests`, `stdlib`, ...) prints one, from any directory.

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

`run` and `build` make a lean debug build by default: one unit per module, Core's passes, then code generation at
`-O2` with LLVM's IR passes off (on for a unit of at most 50,000 bytes), so an edit recompiles only what changed. `test` builds the same way at LLVM `-O0`.
`--debug-o0` gives `run` and `build` the `-O0` build (the cheapest cold build), `--optimize-debug` LLVM `-O2` and
`--unoptimized` a build with no Core pass. `--release` optimizes the
whole program as one unit and recompiles all of it after any change. Both keep
every overflow, cast and bounds check.
A file argument that is missing, unreadable or a directory is refused by every
command with `selka COMMAND: cannot read 'PATH': REASON` and exit status 2.
`run` takes its budgets as `--max-steps N`, `--max-frames N`, `--timeout N` and
`--max-memory SIZE`, or as `--flag=N`; `test` takes `--max-steps`, `--max-frames` and
`--max-memory` the same way. Each frame a
`--max-frames` budget allows reserves 32 KiB of `--max-memory`, and a budget the
memory cannot hold is refused up front with the memory it needs.
When `fmt --check` fails, `path:line:column` identifies the first formatting
difference and the same line says what the formatter wants there (for example
`line 1 is followed by one blank line, and the formatter wants two blank lines
between top-level declarations`) and names `selka fmt --write FILE` as the
repair; `fmt FILE` prints the complete corrected source.

## File layout

- Files need no module header. Their paths determine module names: `calc.selka`
  is `calc`, and `shared/calc.selka` is `shared.calc` beneath the project root.
  `func main` marks an executable entry.
- `import util` loads `util.selka` beside the entry; call `util.f(x)`. Only the
  declarations `util` marks `public` are visible. `check`, `run`, `build` and
  `test` follow the imports from a module entry by themselves.
  `check name.selka` also accepts a library without `main`: it checks bodies,
  effects and public signatures as well as imports, and a file that does declare
  `main` keeps every check on it. `run` and `build` still need a `main`.
  `check-module name.selka` does the same but always checks as a library and
  accepts the same headerless module source.
- Tests are `public func test_name() -> bool` (return `True` to pass), in the same
  file as the code or in `name_test.selka` that does `import name` (then only
  `name`'s `public` declarations are visible). A test may take `out: Stream`
  and the capabilities `fs: Filesystem`, `clock: Clock`, `entropy: Entropy`,
  `env: Environment` and `net: Network`; the runner hands each a deterministic
  stand-in (an empty in-memory filesystem, a simulated clock, ...), never real
  authority, so I/O code is testable without host files. `selka docs tests`
  has the table.
  A `*_test.selka` entry imports its sibling directly; both `test` and `fmt`
  accept the same headerless form as other modules.
  Run `selka test name_test.selka` to select sibling tests directly. If
  `selka test name.selka` selects none, it points out an existing sibling test
  file; testing the containing directory also discovers it.

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

- There is no bare `print`: take `out: Stream` / `err: Stream` parameters (only
  `main` receives them from the runtime; pass them down). `debug(x)` prints to
  stderr from anywhere, for debugging only.
- Capabilities (`fs: Filesystem`, `clock: Clock`, `env: Environment`, ...) are
  parameters of `main`; pass them to the helpers that need them. There is no
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

Construct with keywords: `Item(name="a", count=1)`, `Shape.rect(w=2.0, h=3.0)`,
`Node(value=1, next=None)`. Recursive trees and ASTs use records and unions;
graphs with identity use pool handles. Loop bindings borrow elements for reading.
Writing through one (`for it in items: it.count = 0`) is a compile error: update
the owning collection outside that borrow, or explicitly copy and rebuild the record. Builtin types: `int`, `float`, `bool`, `str`, `bytes`,
`T[]`, `dict[K, V]` and `set[K]` (structural hashable keys), `T?`
(`Some(x)` / `None`) and `Result[T, E]` (`Ok(x)` / `Err(e)`).

A public declaration can expose only public types. `E_PRIVATE_INTERFACE` on
a `public record` means one of its fields exposes a private type: mark that
type `public` too, or keep the enclosing record private. The same rule applies
through containers and to public function signatures.

```selka
# doc: expect 2
public record Count:
    value: int

public record ItemCount:
    count: Count

func main(out: Stream) -> int:
    mut item = ItemCount(count=Count(value=2))
    print(out, item.count.value)
    return 0
```

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

There are no exception handlers. Declare expected errors with `fails`, return
success with `return`, fail with `fail`, and propagate with `try`: a statement's whole
value, or a call's argument (`print(out, try total(s))`), never an operand.
To retain a result for explicit comparison, use a typed declaration such as
`const expected: Result[int, str] = Ok(3)`.


A call used as a statement must return unit (`-> Unit`, or no return
annotation). `E_EXPLICIT_DISCARD_REQUIRED` means a non-unit result was ignored:
use the value, handle it, or write `_ = expression` to discard it explicitly.
For a checked result, use `match` or boundary `try` to handle failure.

```selka
# doc: expect 1
import lists

func main(out: Stream) -> int:
    mut values = [10, 20]
    _ = lists.pop(mut values)                  # pop returns the removed element
    print(out, len(values))
    return 0
```

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

A function that keeps its argument takes it as an `own` parameter and moves it on; the
caller writes `own x` for a name it is finished with, or passes a fresh value bare. A
function that only reads takes a plain parameter, and one that returns part of it says
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

```selka
# doc: expect {3, 1, 2} {'a': 1, 'bb': 2} 14 True
import strings

func main(out: Stream) -> int:
    mut seen = {3, 1, 2, 3}                  # a set[int]; keeps first-insertion order
    mut lengths: dict[str, int] = {}
    for w in ["a", "bb"]:
        lengths[w] = strings.char_count(w)
    mut squares = 0
    for x in [1, 2, 3]:
        squares += x * x
    mut has_large = False
    for x in seen:
        if x > 2:
            has_large = True
            break
    print(out, seen, lengths, squares, has_large)
    return 0
```

- list: bare `append(mut xs, own x)`, `sort(mut xs, key=...)` and `len(xs)`; `lists.pop(mut xs)`,
  `lists.insert(mut xs, i, own x)` and `lists.contains(xs, x)` need `import lists` (a bare `pop` or `insert` is
  `E_UNKNOWN_SYMBOL`); slices `xs[a:b]` and nonnegative indexes. Build collected results with
  typed empty lists and explicit `for` / `if` statements.
- dict: `d[k]`, `dicts.get(d, k, default)`, `k in d`, `for k, v in dicts.items(d)`
  (insertion order). Populate dictionaries with assignments inside a loop.
- set: `{1, 2}`, `seen: set[int] = set()`, `add`, `remove`, `discard`, `in`,
  `|` `&` `-` `^`, `issubset`. Iteration and printing are in first-insertion
  order (`set()` when empty); compare `sorted(s)` when the order matters.
  See [Sets](sets.md).
- Sorting: `sorted(xs)` and `sort(mut xs, key=key_function)`. Declare a named key
  function with explicit parameter and return types.
- `min(a, b)`, `max(xs)`, `abs(n)`, `sum(xs)`, `round(x, n)`, `range(n)`,
  `range(a, b)` and `range(a, b, step)`;
  `for i, x in enumerate(xs)` and `for a, b in zip(xs, ys)` unpack in loops.
- Lambdas, comprehensions and generator arguments are retired. Use named
  functions, typed accumulators and explicit loops; preserve early exit when
  replacing an `any` or `all` generator.

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

A function that writes a list, dict or record parameter declares it `mut`, and
its callers write `mut arg`. An unused `mut` parameter is accepted. Mutating
locals needs no marker. A missing or extra call-site marker carries its exact
fix. Core checks that two `mut` arguments of one call name disjoint places:
`f(mut a, mut a)` and `f(mut a, mut a[0])` are `E_SINGLE_OWNER_OVERLAP` (M5),
while different fields of one local or parameter such as `f(mut s.a, mut s.b)` and
distinct literal list indices such as `f(mut xs[0], mut xs[1])` can be proven
disjoint. Two fields of one `match mut` payload are disjoint too, as
`f(mut keys, mut vals)` in `case pairs(keys, vals)`, when the matched place is
not inside a list element; so are bindings of two nested `match mut` arms. When Core cannot prove dynamic indices or dictionary selections
disjoint, it refuses the call conservatively with the same code. Fields inside
one list element are not proven disjoint today: a lent text, list or record field
beside a `mut` sibling of the same element, `f(xs[0].name, mut xs[0].n)`, is
`E_SINGLE_OWNER_OVERLAP` (the rule names the element, not the field; the same
two fields of a local `s` pass, and so does a lent `int`, `bool` or `float`
field, which is read before the call). Pass the element, `f(mut xs[0])`, and
let `f` read one field and write the other, or copy the lent field into a local
first.

A call in an index can also conflict with its receiver's active borrow (R2):
`items[selected(mut items)] = 9` is `E_SINGLE_OWNER_OVERLAP`. A simple case can
carry a [split repair](tooling/fix.md#structured-fixes-in-diagnostics) that saves
the scalar call result before the update. If the split would reorder another
effect or an earlier observation, the compiler leaves it for a manual rewrite.
Ordinary indexed assignment evaluates its assigned value before borrowing the
target, so `items[0] = selected(mut items)` does not alone create this conflict.

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

- `@requires` is a condition on the arguments, `@ensures` a promise about the result and about `mut` parameters as they
  stand at return, `@invariant` something always true of a `record` (checked wherever a value is built or changed), and
  `assert` a fact true at one point in a body. An error the caller cannot be blamed for, such as a missing file, is a `Result`.
- A broken clause is a trap, exit status 1, in `run`, `test` and `--release` alike: `R_ASSERT`, `R_REQUIRES`, `R_ENSURES`
  or `R_INVARIANT`. A broken `@requires` names the caller (`broken by the caller main at prog.selka:9:12`).
- A clause is part of the declaration's interface: `selka list-interfaces` and `selka context` show it, and
  `selka api-diff` reports a changed one as breaking. A property test (a `test_` function with data parameters) discards a
  generated input that breaks its own `@requires` or an `@invariant` of a record it takes, instead of failing
  ([property tests](tooling/guest-tests.md#property-tests)).
- A condition only observes: it reads the parameters (and `result`, `old(...)`, `self`) and may allocate, but cannot use a
  capability such as `out` or `fs`, assign, or write through a `mut` marker (`E_CONTRACT_EFFECT`). `old(len(items))` is
  cheap; a managed value is captured by a written copy, `old(copy(items))`, made at every call.
- An `@invariant` is checked after every write to a field, `append(mut r.items, x)`, `take(mut r.f)` and
  `exchange(mut r.f, v)` included, on records with text, bytes or list fields as on any other. So two writes in a row can
  trap between them: `exchange(mut r.items, new)` swaps a field in one step where `take` and then a store would not, and
  `r = replace(r, low=low, high=high)` changes two fields at once.
- `old(...)` may read a field (`old(cursor.pos)`), and a clause may call a function of the module
  (`@requires(ordered(items))`).
- A clause is checked at run time unless the compiler proves it can never fail; `selka cost prog.selka --clauses` lists
  each one as proved, refuted or kept. A function a clause calls runs at every check, so a loop in it is paid per call.
- There is no loop invariant (write `assert` in or after the loop) and no quantifier (write a function with a loop and
  call it), and `@ensures` speaks of a successful return only, not of the `fail` path.

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
- `str(n)`; `parse_int(s)` and `parse_float(s)` return an `Option` (`int(s)` and
  `float(s)` convert numbers only; on text they are `E_NUMERIC_PARSE`);
  `ord("a")`, `chr(98)`.
- Strings: `split`, `splitlines`, `strip`, `join`, `replace`, `find`, `count`,
  `startswith`, `lower`, `upper`, `isdigit`, `zfill`, `encode`, ... `s[i]` is the
  octet at byte offset `i`, an `int` (`str` is bytes underneath; see
  [text](text.md)), and `strings.char_at(s, i)` is the one-scalar `str` at a scalar
  position. `<` orders strings by code point, and
  `strings.repeat("ab", 3)` repeats (`"ab" * 3` is `E_REPETITION_REMOVED`, as is
  `[0] * n`; use `byte_builder.repeat` for bytes and `lists.filled(n, 0)` for a
  list). f-strings take CPython's format specs (`{x:.2f}`, `{n:>5}`,
  `{n:,}`, `{n:05d}`, `{x:.1%}`) and print exactly what CPython prints.
- `round(x, n)` rounds the exact binary value, like C and Python
  (`round(2.675, 2)` → `2.67`), except that an exact tie rounds away from zero
  (`round(0.125, 2)` → `0.13`, Python `0.12`; `f"{0.125:.2f}"` is `0.12` in both).
- Build a large string by collecting pieces in a `str[]` and
  `strings.join(pieces, "")` (`"".join(pieces)` is `E_METHOD_REMOVED`). For byte-level scanning read with `fs.read_file`: `data[i]`
  is an `int`, and so is `text[i]` on a `str`: compare either one with `ord` of a
  one-character literal, as in `data[i] == ord("G")` and `text[i] == ord("G")`.
  `ord(text[i])` is refused (`ord` takes a `str`). `data[a:b]`
  is a `bytes` slice, `strings.decode(data)` a `Result[str, ...]`. For a file read line by
  line see [walking the lines of a file](bytes.md#walking-the-lines-of-a-file).

```selka
# doc: expect 71 True True a
import strings

func main(out: Stream) -> int:
    const text = "Gab"
    const data = b"Gab"
    print(out, text[0], text[0] == ord("G"), data[0] == ord("G"), strings.char_at(text, 1))
    return 0
```

## Not available — do this instead

| Python | selka |
| --- | --- |
| `x ** n` | `math.pow(x, n)` (`import math`, integer exponent) |
| `"ab" * 3`, `[0] * n` | `strings.repeat("ab", 3)`, `lists.filled(n, 0)` (`E_REPETITION_REMOVED`) |
| `x in xs` on a list | `lists.contains(xs, x)` (`E_LIST_MEMBERSHIP_REMOVED`); `in` still works on `str`, `dict`, `set` and `bytes` |
| `xs[-1]` | `xs[len(xs) - 1]` (`E_NEGATIVE_INDEX_REMOVED`) |
| `a if c else b` | an `if` / `else` statement assigning or returning the value (`E_CONDITIONAL_EXPRESSION_REMOVED`) |
| `[f(x) for x in xs]`, `lambda x: ...` | a typed accumulator with a `for` loop; a named top-level `func` |
| `(a, b)`, `a, b = b, a` | a `record` with named fields (`E_TUPLE_REMOVED`) |
| `gen = (x for x in xs)` | build a typed list with an explicit `for` loop |
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

`selka docs TOPIC` prints each of these from the compiler itself: `syntax` (the
language guide), `io` (files, streams, capabilities), `text`, `bytes`,
`modules`, `errors` (Result and Option), `effects`, `contracts` (`@requires`,
`@ensures`, `@invariant`), `stdlib`, `tests` and `build`. In a large project, `selka context ENTRY.selka --symbol=module::name`
answers one bounded question about a declaration, and `selka tests-for` and
`selka test --affected` find the tests an edit reaches.
