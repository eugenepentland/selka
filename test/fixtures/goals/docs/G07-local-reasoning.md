# G7. Local reasoning: pinned examples

A caller is judged from the signatures it names. `H` examples show the property holding. `X` examples pin a known
exception to today's behaviour: when one starts failing, the exception has changed, and `docs/goals.md` must be updated
with it.

## Holds

**G7-H1.** A result that borrows from a parameter without saying so is refused, so a signature never hides a loan.

```selka
# doc: expect-error E_BORROW_UNDECLARED
func first(xs: str[]) -> str:
    return xs[0]

func main() -> int:
    return len(first(["a"]))
```

**G7-H2.** A plain parameter cannot be written.

```selka
# doc: expect-error E_MUTATION_MARKER
func grow(xs: int[]):
    append(mut xs, 1)

func main() -> int:
    mut xs = [1]
    grow(xs)
    return len(xs)
```

**G7-H3.** A call that lets the callee write says so at the call.

```selka
# doc: expect-error E_MUTATION_MARKER
func grow(mut xs: int[]):
    append(mut xs, 1)

func main() -> int:
    mut xs = [1]
    grow(xs)
    return len(xs)
```

**G7-H4.** A bare call of a prelude name is always the builtin, so a module function that would replace it for a bare
call is refused at its declaration (W6; this was the exception G7-X7, which exited with 101 and 7).

```selka
# doc: expect-error E_BUILTIN_FUNCTION_NAME
func len(n: int) -> int:
    return n + 100

func abs(n: int) -> int:
    return 7

func main(out: Stream) -> int:
    print(out, len(1), abs(0 - 3))
    return 0
```

**G7-H5.** A module function with a prelude name that its own module never calls bare is accepted, and other modules
reach it by its qualified name, so `zipfile.write(...)` and the bare `len(...)` beside it each say what they call.

```selka
# doc: project zipfile-write
# doc: file zipfile.selka
public func write(count: int) -> int:
    return count * 10
```

```selka
# doc: project zipfile-write
# doc: file main.selka
# doc: expect 23
import zipfile

func main() -> int:
    return zipfile.write(2) + len([1, 2, 3])
```

**G7-H6.** A re-export that would make a bare prelude name call the re-exported function is refused the same way; before
W6 this `abs(-3)` called the standard library's `math.abs`.

```selka
# doc: expect-error E_BUILTIN_FUNCTION_NAME
import math
export math.abs

func main() -> int:
    return abs(0 - 3)
```

**G7-H7 and G7-H8 (a generic body is judged at its declaration; W3).** A body that some kind of type argument its bounds
admit would refuse is refused at its declaration, whatever its callers pass: this program calls `first` and `keep` with
`int` only. Before W3 it was accepted, and the same bodies were refused inside the template only when a program passed
`str`. The repaired bodies, ` from xs` on the result and `copy(x)` on the stored value (the fixes `selka fix` writes), are
accepted for every kind.

```selka
# doc: expect-error E_BORROW_UNDECLARED
func first[T](xs: T[]) -> T:
    const head = xs[0]
    return head

func keep[T](x: T) -> T[]:
    mut out: T[] = []
    append(mut out, x)
    return out

func main() -> int:
    const a = first([1, 2, 3])
    const b = keep(5)
    return a + len(b)
```

```selka
# doc: check
func first[T](xs: T[]) -> T from xs:
    const head = xs[0]
    return head

func keep[T](x: T) -> T[]:
    mut out: T[] = []
    append(mut out, copy(x))
    return out

func main() -> int:
    const a = first([1, 2, 3])
    const b = keep(5)
    return a + len(first(["a", "b"])) + len(keep("c")) + len(b)
```

**G7-H9 (an arm's binding keeps its place for every payload type; FX9, decision HOLD).** Inside a `match mut` arm, the
matched value cannot be replaced while a payload binding is still used afterwards, so a reader of the arm knows the
binding names the case it matched. Until 13 November this held only when the payloads held text or lists; with plain
numbers the program below built, read the empty case's payload and wrote the old case back (it printed 8). Now it is
refused with `E_SINGLE_OWNER_OVERLAP` at the replacing write.

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
enum Sh:
    empty
    rad(value: int)


func main() -> int:
    mut s = Sh.rad(value=1)
    match mut s:
        case rad(value=v):
            s = Sh.empty
            v = v + 8
        case empty:
            return 1
    return 0
```

## Exceptions

**G7-X3 and G7-X4 (a borrowing list; W2, decision Q2).** A list that only ever receives borrowed rows borrows them.
One fresh row appended later makes the earlier `append` an error.

```selka
# doc: expect 1
record Row:
    name: str
    tags: str[]

func count(rows: Row[]) -> int:
    return len(rows)

func main(out: Stream) -> int:
    mut all: Row[] = []
    append(mut all, Row(name="a", tags=["x"]))
    append(mut all, Row(name="b", tags=["y"]))
    mut hits: Row[] = []
    for r in all:
        if r.name == "a":
            append(mut hits, r)
    print(out, count(hits))
    return 0
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Row:
    name: str
    tags: str[]

func main() -> int:
    mut all: Row[] = []
    append(mut all, Row(name="a", tags=["x"]))
    mut hits: Row[] = []
    for r in all:
        if r.name == "a":
            append(mut hits, r)
    append(mut hits, Row(name="z", tags=[]))
    return len(hits)
```

**G7-X5 and G7-X6 (a field default decides whether a record borrows; W2).**

```selka
# doc: check
record R:
    s: str
    n: int = 0

func size(r: R) -> int:
    return len(r.s) + r.n

func main() -> int:
    const names = ["ab", "cd"]
    const r = R(s=names[1])
    return size(r)
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
record R:
    s: str
    tags: str[] = []

func size(r: R) -> int:
    return len(r.s) + len(r.tags)

func main() -> int:
    const names = ["ab", "cd"]
    const r = R(s=names[1])
    return size(r)
```

**G7-X8 (an import hides a builtin; W6).**

```selka
# doc: expect-error E_UNKNOWN_SYMBOL
import sort

func main() -> int:
    mut xs = [3, 1]
    sort(mut xs)
    return xs[0]
```
