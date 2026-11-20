# Immutable scalar constants

Declare a module constant with an explicit scalar type:

```selka
const SCALE: i64 = 6
public const ANSWER: i64 = SCALE * FACTOR
const FACTOR: i64 = 7
const MASK: u8 = u8(255)
```

- Integer widths, `bool` and `float` ([float constants](#float-constants)), `str` and `bytes`
  ([literal constants](#string-and-byte-literal-constants)) are supported. A table of numbers is a `bytes` constant built
  by a source function ([constants that are tables](source-evaluation.md#constants-that-are-tables)). Any other type, a
  list for one, is `E_CONSTANT_TYPE`.
- An unsuffixed integer literal in any base takes the declared type when its value fits: `const MASK: u32 = 0xFF00_0000`
  and `const LOW: u8 = 255` need no suffix or cast.
- An initializer may hold scalar literals, other visible constants, casts, and unary and binary operators. `ord("=")` of
  a one-byte literal and `b"="[0]` fold to the character's number
  ([character codes by name](bytes.md#character-codes-by-name)). Bounded calls to scalar source functions work, as
  [source-evaluation.md](source-evaluation.md) describes. Allocation, aggregate construction and external effects are
  excluded.
- Forward references work; a dependency cycle is rejected even in a short-circuited operand. Every constant is checked
  even when unused. Overflow, invalid casts and evaluated division by zero are compilation errors.
- Short-circuit operators keep their runtime meaning: `False and (1 / 0 == 0)` is a valid false constant, and its
  unevaluated operand is still checked for syntax, dependencies and types.
- Nesting is bounded at 256 levels and evaluation at 65,536 work units.

Constants follow the module export rules:

```selka
public const ANSWER: i64 = 42
```

Importers read `settings.ANSWER`. Generic functions may read concrete constants; there are no generic constants. A
constant cannot be assigned, and cannot replace `func main`. There is no dynamic initializer, initialization order or
mutable storage.

## Float constants

A `float` constant is folded at check time with the same binary64 operations a running program uses. The initializer may
use:

- float and integer literals (an integer literal takes the float type, so `const HALF: float = 1 / 2` is `0.5`), other
  visible constants, parentheses, unary `-`, `+`, `-`, `*`, `/`, `//`, `%`, and comparisons (which make a `bool`
  constant);
- `float(...)`, `int(...)`, `sqrt`, `floor`, `ceil`, `trunc` and `abs`.

An integer operand beside a float converts to the nearest binary64 first. `-0.0` keeps its sign. An overflowing literal
is `E_FLOAT_RANGE`, and a value of the wrong type is `E_TYPE`. Converting a float constant to an integer type truncates
toward zero, and NaN, an infinity or an out-of-range value is `E_CONSTANT_ARITHMETIC`. Compile-time calls to source
functions take and return integers and `bool`.

```selka
# doc: expect 42
const PI: float = 3.14
const TWO_PI: float = PI * 2.0
const SCALE: int = int(TWO_PI * 100.0)

func main() -> int:
    if TWO_PI != 6.28 or SCALE != 628:
        return 1
    return int(PI * 10.0) + 11
```

## String and byte literal constants

`str` and `bytes` constants hold a literal of the matching type: empty literals, Unicode text and ordinary escapes work,
and so do transparent type aliases.

```selka
# doc: expect 42
import strings

const LABEL: str = "hé🙂"
const HEADER: bytes = b"\x00\x27"
const EMPTY: bytes = b""

func main() -> int:
    return strings.char_count(LABEL) + HEADER[1] + len(EMPTY)
```

The initializer may also join literals and other constants of the same type with `+`, or name one such constant alone:
constants of the same module in either order, and imported ones (`settings.NAME`). A `bytes` constant may be a call of a
source function that builds its octets, which is how a lookup table is written
([constants that are tables](source-evaluation.md#constants-that-are-tables)). A constant a join names must itself be a
literal or such a join; a cycle is `E_CONSTANT_CYCLE`, naming the constants in it. Other calls, format strings, other
operators, casts, indexing, a constant of the other type and an embedded constant are `E_CONSTANT_EXPRESSION` or
`E_TYPE`, even for an unused declaration.

```selka
# doc: expect 42
const SELECTOR: str = "#" + NAME + "-" + ORDER
const NAME: str = "split"
const ORDER: str = "parse,check"
const HEADER: bytes = MAGIC + b"\x01"
const MAGIC: bytes = b"MY"

func main() -> int:
    if SELECTOR != "#split-parse,check":
        return 1
    return len(SELECTOR) + len(HEADER) + 21
```

The one call allowed is `embed_bytes("path")` for a `bytes` constant or `embed_str("path")` for a `str` constant, which
reads a project file at compile time ([embedding a file](bytes.md#embedding-a-file-at-compile-time)). Such a constant is
static data: reading it allocates nothing and is legal under `noalloc`.

A `str` or `bytes` constant reads directly through its module's functions, with no local copy: `bytes.split(TABLE, b"\n")`
and `strings.upper(NAME)` work on a constant, on an embedded one and on one read through an import
(`strings.upper(settings.NAME)`), as do indexing, `len` and slicing. A literal constant allocates when it is read by a
call; an embedded one does not.

```selka
# doc: expect 42
import bytes
import strings

const TABLE: bytes = b"a=1\nb=2\nc=3"
const LABEL: str = "hello"

func main() -> int:
    mut rows = bytes.split(TABLE, b"\n")
    if len(rows) != 3 or not strings.starts_with(LABEL, "he"):
        return 1
    return strings.char_count(strings.upper(LABEL)) + rows[1][2] - 13
```

A `str` or `bytes` constant is static data in the built program: reading it allocates and frees nothing, and a function
that only reads it passes `@noalloc`, a `bytes` table built by a source function included. There is no module
initialization order or shared mutable storage. Ownership checks, cleanup and allocation budgets apply as usual.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/module-constants.md).
