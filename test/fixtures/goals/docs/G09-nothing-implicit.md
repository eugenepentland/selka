# G9. Nothing implicit: pinned examples

## Holds

**G9-H1.** No closures.

```selka
# doc: expect-error E_LAMBDA_REMOVED
func main() -> int:
    const f = lambda x: x + 1
    return 0
```

**G9-H2.** No comprehensions or generators.

```selka
# doc: expect-error E_COMPREHENSION_REMOVED
func main() -> int:
    const ys = [x * 2 for x in [1, 2]]
    return len(ys)
```

**G9-H3.** No mutable state in a module.

```selka
# doc: expect-error E_SYNTAX
mut counter = 0

func main() -> int:
    return counter
```

**G9-H4.** No cycle between modules.

```selka
# doc: project cycle
# doc: file b.selka
# doc: expect-error E_IMPORT_CYCLE
import main

public func fb(n: int) -> int:
    return n
```

```selka
# doc: project cycle
# doc: file main.selka
import b

public func fa(n: int) -> int:
    return b.fb(n)

func main() -> int:
    return fa(3)
```

**G9-H5.** A value cannot be dropped silently.

```selka
# doc: expect-error E_EXPLICIT_DISCARD_REQUIRED
func three() -> int:
    return 3

func main() -> int:
    three()
    return 0
```

**G9-H6.** A collection cannot change while it is iterated.

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    mut xs = [1, 2]
    for x in xs:
        append(mut xs, x)
    return len(xs)
```

**G9-H7.** A name cannot change meaning inside a function.

```selka
# doc: expect-error E_SHADOWING
func main() -> int:
    const n = 1
    if n > 0:
        const n = 2
        return n
    return n
```

**G9-H8.** A catch-all after a complete match is refused.

```selka
# doc: expect-error E_WILDCARD_ARM
enum Layer:
    copper
    silk

func f(l: Layer) -> int:
    match l:
        case copper:
            return 1
        case silk:
            return 2
        case _:
            return 3

func main() -> int:
    return f(Layer.silk)
```

**G9-H9.** An index and the middle of a chained comparison are evaluated once.

```selka
# doc: expect [0, 5, 0, 0] 2 True
func tick(mut n: int) -> int:
    n += 1
    return n

func main(out: Stream) -> int:
    mut calls = 0
    mut xs = [0, 0, 0, 0]
    xs[tick(mut calls)] += 5
    const inside = 0 < tick(mut calls) < 10
    print(out, xs, calls, inside)
    return 0
```

**G9-H10.** `try` converts an error into a case of the enclosing enum only when exactly one case can
carry it. With two `str` cases the order of the cases would choose the error, so the conversion is refused.

```selka
# doc: expect-error E_ERROR_CASE_AMBIGUOUS
enum AppErr:
    Io(message: str)
    Parse(value: str)
    Other(code: int)

func parse(s: str) -> int fails str:
    if len(s) == 0:
        fail "empty"
    return len(s)

func run(s: str) -> int fails AppErr:
    const n = try parse(s)
    return n + 1

func main(out: Stream) -> int:
    match run(""):
        case Ok(v):
            print(out, v)
        case Err(e):
            print(out, e)
    return 0
```

**G9-H11.** With one case that can carry a `str`, `try` converts into it.

```selka
# doc: expect AppErr.Parse(value='empty')
enum AppErr:
    Parse(value: str)
    Other(code: int)

func parse(s: str) -> int fails str:
    if len(s) == 0:
        fail "empty"
    return len(s)

func run(s: str) -> int fails AppErr:
    const n = try parse(s)
    return n + 1

func main(out: Stream) -> int:
    match run(""):
        case Ok(v):
            print(out, v)
        case Err(e):
            print(out, e)
    return 0
```

**G9-H12.** `old(x)` of a managed place copies it at every call, so the copy is written: a bare `old(items)` is
refused (W4, the user's decision of 12 November 2026), and `selka fix` writes `old(copy(items))`.

```selka
# doc: expect-error E_CONTRACT_OLD_COPY
@ensures(len(items) == len(old(items)) + 1)
func grow(mut items: int[], x: int):
    append(mut items, x)

func main(out: Stream) -> int:
    mut xs = [1, 2, 3]
    grow(mut xs, 9)
    print(out, len(xs))
    return 0
```

**G9-H13.** With the copy written, the capture is accepted, and `selka cost FILE --sites` labels its row "written".

```selka
# doc: expect 4
@ensures(len(items) == len(old(copy(items))) + 1)
func grow(mut items: int[], x: int):
    append(mut items, x)

func main(out: Stream) -> int:
    mut xs = [1, 2, 3]
    grow(mut xs, 9)
    print(out, len(xs))
    return 0
```

**G9-H14.** A standard-library function the compiler supplies is declared `builtin func`, with no body that a call could
run instead of the operation: a call is the operation however it is spelled, so an alias gives the sum of the lanes, as
`simd.sum(...)` does (before W10, `v.sum(...)` ran a placeholder body and printed `1.0`).

```selka
# doc: expect 10.0 AB
import simd as v
import strings as s

func main(out: Stream) -> int:
    print(out, v.sum(Simd[float, 4]([1.0, 2.0, 3.0, 4.0])), s.upper(text="ab"))
    return 0
```

## Exceptions

**G9-X3 (a dictionary key is copied with no `copy(` written; by decision of 12 November 2026: the one documented
implicit copy, labelled by the tools).** The value beside it needs `copy(...)`. `selka cost FILE --sites` labels the
key copy "implicit (dictionary key)".

```selka
# doc: expect 1
record Entry:
    key: str
    n: int

func index(entries: Entry[]) -> dict[str, int]:
    mut out: dict[str, int] = {}
    for e in entries:
        out[e.key] = e.n
    return out

func main(out: Stream) -> int:
    mut es: Entry[] = []
    append(mut es, Entry(key="a", n=1))
    const d = index(es)
    print(out, d["a"])
    return 0
```

**G9-X5 (a frame block: the callee copies its parameter when the caller passes a slice; W4, W18, decision Q8).** The
build accepts it today. `selka cost FILE --sites` reports "hidden copies: 1 (1 frame block)" and labels the row
"implicit (frame block)"; the hidden-copy check counts it and does not refuse it (decision Q8 is open).

```selka
# doc: expect 36
# doc: expect 6
record Line:
    text: str
    n: int

func line_len(l: Line) -> int:
    return len(l.text) + l.n

func total(text: str) -> int:
    mut sum = 0
    for i in range(3):
        sum += line_len(Line(text=text, n=i))
    return sum

func main(out: Stream) -> int:
    const words = "hello world"
    print(out, total(words))
    print(out, total(words[0:1]))
    return 0
```

**G9-X6 (an update made on a copy is lost with no diagnostic; W7).**

```selka
# doc: expect 1
record Item:
    name: str
    count: int

func bump(mut items: Item[]):
    mut first = copy(items[0])
    first.count = first.count + 1

func main(out: Stream) -> int:
    mut items: Item[] = []
    append(mut items, Item(name="a", count=1))
    bump(mut items)
    print(out, items[0].count)
    return 0
```

**G9-X7 (an integer above 2^53 changes value in mixed arithmetic; decision Q7).**

```selka
# doc: expect 9007199254740992.0 9007199254740992.0
func main(out: Stream) -> int:
    const big = 9007199254740993
    print(out, big / 1, big + 0.0)
    return 0
```

Not pinnable here: the labels of `selka cost --sites` (written, named operation, implicit; W4) are a tool's output,
tested in `src/core/written_copy_test.zig`; and a written `copy(x)` removed when `x` is dead, which leaves no row. See `docs/audits/implicit-code-audit-2026-11-11.md`,
sections 3.1 and 3.6.
