# G14. One spelling for each thing: pinned examples

The `X` examples are exceptions, pinned as they behave today; the `H` examples show the goal holding. The gate test of W8
(`src/advice_tables_test.zig`) also holds the other half of the goal: every replacement a message in the three advice tables
names is code the compiler accepts.

## Holds

**G14-H1 (`try` over an operator expression is the position rule's error, not a type error; was G14-X9, W8; since TRY-2
the operator belongs outside the `try`).**

```selka
# doc: expect-error E_TRY_POSITION
func half(x: int) -> int fails str:
    if x % 2 != 0:
        fail "odd"
    return x // 2

func total(x: int) -> int fails str:
    mut sum = 0
    sum += try (half(x) + 1)
    return sum

func main() -> int:
    match total(4):
        case Ok(v):
            return v
        case Err(_):
            return 1
```

**G14-H2 (a method is refused at every argument count, with its function home as the repair; was G14-X1, W13-S5).**

```selka
# doc: expect-error E_METHOD_REMOVED
func main(out: Stream) -> int:
    const s = "a b"
    const p = s.split()
    print(out, len(p))
    return 0
```

**G14-H3 (the method with an argument is refused as before, and the function forms check; was G14-X2, W13-S5).**

```selka
# doc: expect-error E_METHOD_REMOVED
func main() -> int:
    const s = "a,b"
    const p = s.split(",")
    return len(p)
```

```selka
# doc: expect 2
import strings

func main(out: Stream) -> int:
    const s = "a b"
    print(out, len(strings.words(s)))
    return 0
```

**G14-H4 (a file operation has one spelling, the capability's method; was G14-X3, W13-S5).**

```selka
# doc: expect-error E_REMOVED_SPELLING
func main(fs: Filesystem) -> int:
    const a = fs.exists("p")
    const b = exists(fs, "p")
    if a and b:
        return 1
    return 0
```

## Exceptions

**G14-X4 (the marker words are ordinary names; W21).**

```selka
# doc: expect 6
func main(out: Stream) -> int:
    mut own = 1
    mut mut = 2
    const copy = 3
    print(out, own + mut + copy)
    return 0
```

**G14-X5 (an internal name is reserved, so a capability method cannot be called; W21).**

```selka
# doc: expect-error E_SYNTAX
func main(entropy: Entropy) -> int:
    const n = entropy.random_u64()
    return int(n % 2)
```

**G14-X6 and G14-X7 (an f-string with one hole is the hole).**

```selka
# doc: expect-error E_OWN_MARKER
func main() -> int:
    const a = "abc"
    const s = f"{a}"
    return len(s) + len(a)
```

```selka
# doc: expect 7
func main(out: Stream) -> int:
    const a = "abc"
    const s = f"x{a}"
    print(out, len(s) + len(a))
    return 0
```

**G14-X8 (a literal match on a text field is refused; on a local it is accepted).**

```selka
# doc: expect-error E_LITERAL_ARM
record Entry:
    text: str

func main() -> int:
    const entry = Entry(text="yes")
    match entry.text:
        case "yes":
            return 1
        case _:
            return 0
```

**G14-X10 (`try` in a call's argument or an operand and the same call after a declaration are two spellings of one program;
TRYARG and TRY-2, the user's decisions of 17 November 2026).** Both run left to right and leave at the failing `try`; G14-H1
still holds for a `try` over an operator expression.

```selka
# doc: expect 2
func half(x: int) -> int fails str:
    if x % 2 != 0:
        fail "odd"
    return x // 2

func total(x: int) -> int fails str:
    return abs(try half(x))

func main(out: Stream) -> int:
    match total(4):
        case Ok(v):
            print(out, v)
        case Err(_):
            print(out, 0)
    return 0
```

```selka
# doc: expect 2
func half(x: int) -> int fails str:
    if x % 2 != 0:
        fail "odd"
    return x // 2

func total(x: int) -> int fails str:
    const h = try half(x)
    return abs(h)

func main(out: Stream) -> int:
    match total(4):
        case Ok(v):
            print(out, v)
        case Err(_):
            print(out, 0)
    return 0
```

```selka
# doc: expect 3
func half(x: int) -> int fails str:
    if x % 2 != 0:
        fail "odd"
    return x // 2

func total(x: int) -> int fails str:
    mut sum = 0
    sum += try half(x) + 1
    return sum

func main(out: Stream) -> int:
    match total(4):
        case Ok(v):
            print(out, v)
        case Err(_):
            print(out, 0)
    return 0
```
