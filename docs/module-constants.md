# Immutable scalar constants

Declare a module constant with an explicit scalar type:

```selka
const SCALE: i64 = 6
public const ANSWER: i64 = SCALE * FACTOR
const FACTOR: i64 = 7
const MASK: u8 = u8(255)
```

Integer widths, `bool` and `float` are supported (see [float constants](#float-constants)), as are `str` and `bytes`
([literal constants](#string-and-byte-literal-constants)); a table of numbers is a `bytes` constant built by a source function
(see [constants that are tables](source-evaluation.md#constants-that-are-tables)). Any other type, a list for one, is `E_CONSTANT_TYPE`. An unsuffixed integer literal in any base takes
the declared type when its value fits, so `const MASK: u32 = 0xFF00_0000` and
`const LOW: u8 = 255` need no suffix or cast (`u8(255)` still works). Initializers may contain scalar
literals, other visible constants, casts, and unary/binary operators; `ord("=")` of a one-byte literal and `b"="[0]` fold to the character's
number ([character codes by name](bytes.md#character-codes-by-name)). Forward
references work; dependency cycles reject even in a short-circuited operand.
Bounded calls to scalar source functions are supported as described in
[source-evaluation.md](source-evaluation.md). Allocation, aggregate construction
and external effects are excluded throughout a scalar initializer. Every constant is checked even when unused. Overflow, invalid
casts, and evaluated division by zero are compilation errors.

Short-circuit operators retain their normal runtime semantics: `False and
(1 / 0 == 0)` is a valid false constant. Its unevaluated operand is still checked
for legal syntax, dependencies, and type correctness.

Constants use the existing module export/privacy rules:

```selka
public const ANSWER: i64 = 42
```

Importers read `settings.ANSWER`. Generic functions may read concrete constants;
there are no generic constants yet. Constants cannot be assigned or mutably
reassigned, and they cannot replace the required `func main` entry point.

Checking folds scalar initializers before anything is built, and each read of a
scalar constant is its literal value (`selka dump-ir` shows `42:i64` where
`MAX` was read). There is no dynamic initializer, initialization order, or mutable
storage.

Dependency/expression nesting is bounded at 256 and validation/evaluation work
at 65,536 expression, statement and name-lookup work units per evaluation.
Scalar constants are cached within one evaluation; no generated results persist
across compilation snapshots.

## Float constants

A `float` constant folds its initializer at check time with the same binary64
operations a running program uses, so the constant and the same expression computed
at run time are the same number, and every read is the literal the constant folded
to. The initializer may use float and integer literals (an integer literal takes the
float type from the declaration, so `const HALF: float = 1 / 2` is `0.5`), other
visible constants, parentheses, unary `-`, `+`, `-`, `*`, `/`, `//`, `%`, comparisons
(which make a `bool` constant), `float(...)`, `int(...)`, `sqrt`, `floor`, `ceil`,
`trunc` and `abs`. An integer operand beside a float converts to the nearest binary64
first. `-0.0` keeps its sign, an overflowing literal is `E_FLOAT_RANGE`, and a value of
the wrong type for its declaration is `E_TYPE`. Converting a float constant to an
integer type truncates toward zero and rejects NaN, an infinity or an out-of-range
value with `E_CONSTANT_ARITHMETIC`. Compile-time calls to source functions still take
and return integers and `bool`.

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

`str` and `bytes` constants hold a literal of the matching type. Empty literals,
Unicode text and ordinary literal escapes work. Transparent type aliases also work.

```selka
# doc: expect 42
import strings

const LABEL: str = "hé🙂"
const HEADER: bytes = b"\x00\x27"
const EMPTY: bytes = b""

func main() -> int:
    return strings.char_count(LABEL) + HEADER[1] + len(EMPTY)
```

The initializer may also join literals and other constants of the same type with
`+`, or name one such constant alone: constants of the same module in either order of
declaration, and imported ones (`settings.NAME`). A `bytes` constant may also be a call of a source function that builds its
octets, which is how a lookup table is written
([constants that are tables](source-evaluation.md#constants-that-are-tables)). The compiler folds the join into one
literal when it checks the program, so the constant holds exactly the text it spells,
as if it had been written out. A constant the join names must itself be a literal or
such a join; a cycle is `E_CONSTANT_CYCLE`, which names the constants in it. Other calls,
format strings, other operators, casts, indexing, a constant of the other type and
an embedded constant are rejected with `E_CONSTANT_EXPRESSION` or `E_TYPE`, even for
an unused declaration. Scalar constants retain their existing rules.

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

The one call allowed is `embed_bytes("path")` for a `bytes` constant or
`embed_str("path")` for a `str` constant, which reads a project file at compile
time; see
[embedding a file](bytes.md#embedding-a-file-at-compile-time). Such a constant is
static data: reading it allocates nothing and contributes no effect, so it is
legal under `noalloc`.

A `str` or `bytes` constant reads directly through its module's functions: there
is no need to copy it into a local first. `bytes.split(TABLE, b"\n")`,
`strings.upper(NAME)` and `strings.starts_with(NAME, "he")` work on a constant, on
an embedded one (`const DATA: bytes = embed_bytes("x.txt")` then
`bytes.split(DATA, b"\n")`) and on one read through an import
(`strings.upper(settings.NAME)`). Indexing, `len` and slicing already did. The
receiver is read once, so the call has the same effect as the same call on a
local: a constant literal allocates, an embedded constant does not.

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

These constants use the same export/privacy rules and can be read by generic
functions. A `str` or `bytes` constant is static data in the built program: its
getter returns the one literal (`selka dump-ir` shows `ret str0`), reading it
allocates nothing and frees nothing, and a function that only reads it passes
`@noalloc`. That holds for a `bytes` table a source function built as well. There
is no module initialization order or shared mutable storage. Checked ownership,
deterministic cleanup and allocation budgets apply.

`check`, `run`, `build --run` and installed programs use the same checked getter.
Function-body semantic caching remains disabled for programs with constants;
native object cache keys include emitted IL, so editing a literal changes its
getter object even when all callers remain unchanged. See SPEC.md `CONSTANT-2`.
