# Standard library

Ten modules ship inside the compiler. They are ordinary Python-style guest source
built on the managed types described in the [Python-style guide](python-syntax.md),
[managed memory](managed-memory.md) and [managed byte strings](bytes.md): `list`,
`dict`, `str`, `bytes`, value `record` records, `Option` and `Result`. There is no
allocator to thread and no storage tier to choose.

Import a module by name; projects do not copy these files.

| Module | Covers |
| --- | --- |
| [`math`](#math) | binary64 classification, rounding, roots, powers, integer extrema and divisors |
| [`strings`](#strings) | the text operations `str` itself does not provide |
| [`sort`](#sort) | stable ordering, binary search, extrema and duplicate removal |
| [`path`](#path) | pure POSIX-style path text algebra |
| [`hex`](#hex) | hexadecimal text for byte strings |
| [`base64`](#base64) | RFC 4648 standard and URL-safe transcoding |
| [`json`](#json) | strict RFC 8259 parsing, rendering and typed access |
| [`pool`](#pool) | generational handles into a reusable slot store |
| [`random`](#random) | seeded SplitMix64 streams and entropy-seeded generators |
| [`time`](#time) | wall-clock instants and checked durations |

Every fallible operation returns `Result[T, str]` with a readable message, or
`Option[T]` when absence is not an error. No function returns an integer code and
none of them traps on ordinary bad input.

## math

```text
# doc: not-mylang
pi() -> float                        e() -> float
nan() -> float                       infinity() -> float
is_nan(value: float) -> bool         is_inf(value: float) -> bool
is_finite(value: float) -> bool      fabs(value: float) -> float
sign(value: float) -> int            sqrt(value: float) -> float
trunc(value: float) -> float         floor(value: float) -> float
ceil(value: float) -> float          round(value: float) -> float
pow(base: float, exponent: int) -> float
fmin(a: float, b: float) -> float    fmax(a: float, b: float) -> float
min[T: integer](a: T, b: T) -> T     max[T: integer](a: T, b: T) -> T
clamp[T: integer](value: T, low: T, high: T) -> T
abs(value: int) -> Result[int, str]  isqrt(value: int) -> Result[int, str]
gcd(a: int, b: int) -> Result[int, str]
lcm(a: int, b: int) -> Result[int, str]
```

`pi` and `e` are functions because module constants currently accept only integers
and booleans. `abs`, `gcd`, `lcm` and `isqrt` are checked because
`-9223372036854775808` has no positive counterpart and a least common multiple can
leave the signed range.

```mylang
# doc: expect 42
module main
import math

def main() -> int:
    if math.sqrt(1764.0) != 42.0:
        return 1
    if math.floor(0.0 - 1.5) != 0.0 - 2.0 or math.ceil(0.0 - 1.5) != 0.0 - 1.0:
        return 2
    if math.pow(2.0, 10) != 1024.0 or math.clamp(99, 0, 42) != 42:
        return 3
    match math.gcd(0 - 12, 18):
        case Ok(divisor):
            return int(math.sqrt(49.0)) * divisor
        case Err(message):
            return 0 - len(message)
```

`sqrt` calls the binary64 `f64_sqrt` intrinsic on its ordinary `float` argument,
so it is the correctly rounded square root. `pow` takes an integer exponent and
squares repeatedly; magnitudes above 4096 saturate to a same-parity magnitude,
which preserves the sign and the overflow or underflow outcome.

## strings

```text
# doc: not-mylang
digits() -> str                      letters() -> str
whitespace() -> str
union Error:
    Invalid: str, Overflow: str
message(error: Error) -> str
is_digit(text: str) -> bool          is_alpha(text: str) -> bool
is_alnum(text: str) -> bool          is_space(text: str) -> bool
starts_with(text: str, prefix: str) -> bool
ends_with(text: str, suffix: str) -> bool
find(text: str, needle: str) -> Option[int]
count(text: str, needle: str) -> int
strip(text: str) -> str              lstrip(text: str) -> str
rstrip(text: str) -> str             lines(text: str) -> list[str]
upper(text: str) -> str              lower(text: str) -> str
repeat(text: str, times: int) -> Result[str, Error]
pad_left(text: str, width: int, fill: str) -> Result[str, Error]
pad_right(text: str, width: int, fill: str) -> Result[str, Error]
substitute(text: str, needle: str, insertion: str) -> Result[str, Error]
to_int(text: str) -> Option[int]     to_float(text: str) -> Option[float]
format_int(value: int, base: int) -> Result[str, Error]
format_float(value: float, decimals: int) -> Result[str, Error]
```

`str` already provides `+`, `==`, `in`, indexing, slicing, iteration,
`split(separator)`, `separator.join(parts)` and `encode()`. This module adds what
it lacks. `upper` and `lower` map ASCII only. `substitute` is spelled that way
because `replace` is a reserved word. The fallible builders return `Error`:
`Invalid` marks an argument outside the operation's accepted range, `Overflow`
marks a value that does not fit the rendering, and `message(error)` returns the
human-readable reason.

```mylang
# doc: expect 42
module main
import strings

def main() -> int:
    if not strings.starts_with("answer=42", "answer"):
        return 1
    if strings.strip("  spaced \t") != "spaced":
        return 2
    match strings.find("answer=42", "="):
        case Some(position):
            return decoded("answer=42"[position + 1:9])
        case None:
            return 3

def decoded(body: str) -> int:
    match strings.to_int(body):
        case Some(value):
            return value
        case None:
            return 4
```

`to_int` rejects anything the signed range cannot hold, including
`9223372036854775808`. `to_float` accumulates an exact integer mantissa and
applies one power-of-ten scaling, so short decimals convert exactly; long or
extreme literals are accurate to a few units in the last place rather than
correctly rounded. `format_float` rounds halves away from zero and rejects values
too large for fixed decimals.

## sort

```text
# doc: not-mylang
compare_strs(a: str, b: str) -> int
sort_ints(values: list[int]) -> list[int]
sort_floats(values: list[float]) -> list[float]
sort_strs(values: list[str]) -> list[str]
sort_by_key[T: copy + storable](values: list[T], key: def(T) -> int effects()) -> list[T]
is_sorted_ints(values: list[int]) -> bool
binary_search(values: list[int], target: int) -> Option[int]
min_int(values: list[int]) -> Option[int]
max_int(values: list[int]) -> Option[int]
min_str(values: list[str]) -> Option[str]
unique_ints(values: list[int]) -> list[int]
unique_strs(values: list[str]) -> list[str]
```

Every ordering is a stable merge sort that returns a new list and leaves its input
untouched. Text compares in Unicode code point order. A generic sort over an
arbitrary element type needs an integer key function, because the language has no
ordering contract: `copy`, `equality`, `integer`, `codec` and `storable` are the
only generic requirements.

```mylang
# doc: expect 42
module main
import sort

record Entry:
    name: str
    score: int

def by_score(entry: Entry) -> int effects():
    return entry.score

def main() -> int:
    ranked = sort.sort_by_key([Entry(name="c", score=30), Entry(name="a", score=12)], by_score)
    if ranked[0].name != "a":
        return 1
    ordered = sort.sort_ints([9, 1, 4])
    match sort.binary_search(ordered, 9):
        case Some(position):
            return ranked[0].score + ranked[1].score * position // 2
        case None:
            return 2
```

## path

```text
# doc: not-mylang
record Split:
    root: str
    extension: str

separator() -> str                   is_absolute(value: str) -> bool
join(left: str, right: str) -> str   join_all(parts: list[str]) -> str
basename(value: str) -> str          dirname(value: str) -> str
splitext(value: str) -> Split        stem(value: str) -> str
extension(value: str) -> str         components(value: str) -> list[str]
normalize(value: str) -> str
```

These operations read and build text only. They open nothing, resolve no symbolic
link and need no capability, so they are usable inside a `noio` function.

```mylang
# doc: expect 42
module main
import path

def main() -> int:
    full = path.join("/usr/local", "lib/mylang/../answer.txt")
    if path.normalize(full) != "/usr/local/lib/answer.txt":
        return 1
    if path.extension(full) != ".txt" or path.stem(full) != "answer":
        return 2
    if path.basename("/a/b/") != "" or path.dirname("/a") != "/":
        return 3
    return len(path.normalize(full)) + 17
```

## hex

```text
# doc: not-mylang
encode(data: bytes) -> str           encode_upper(data: bytes) -> str
decode(text: str) -> Result[bytes, str]
is_hex(text: str) -> bool
```

`bytes` already carries `b.hex()` and `bytes.fromhex(s)`; this module adds the
uppercase rendering and a predicate, and names the operations the way the other
codecs do.

```mylang
# doc: expect 42
module main
import hex

def main() -> int:
    text = hex.encode(b"\x0f\xa0")
    if text != "0fa0" or hex.encode_upper(b"\x0f\xa0") != "0FA0":
        return 1
    if not hex.is_hex(text) or hex.is_hex("0fg0"):
        return 2
    match hex.decode(text):
        case Ok(raw):
            if raw != b"\x0f\xa0":
                return 3
            return len(raw) * 21
        case Err(message):
            return 0 - len(message)
```

## base64

```text
# doc: not-mylang
standard_alphabet() -> bytes         urlsafe_alphabet() -> bytes
b64encode(data: bytes) -> bytes
b64decode(data: bytes) -> Result[bytes, str]
urlsafe_b64encode(data: bytes) -> bytes
urlsafe_b64decode(data: bytes) -> Result[bytes, str]
```

Encoding always emits canonical padding. Decoding rejects a length that is not a
multiple of four, a symbol outside the chosen alphabet, padding anywhere but at
the end of the final group, and a final group whose unused bits are not zero, so
exactly one encoding of any byte string decodes.

```mylang
# doc: expect 42
module main
import base64
import hex

def main() -> int:
    encoded = base64.b64encode(b"foobar")
    if encoded != b"Zm9vYmFy" or base64.b64encode(b"f") != b"Zg==":
        return 1
    match base64.b64decode(encoded):
        case Ok(raw):
            if hex.encode(raw) != "666f6f626172":
                return 2
            return refused() + len(raw) * 7
        case Err(message):
            return 0 - len(message)

def refused() -> int:
    match base64.b64decode(b"Zh=="):
        case Ok(_):
            return 1
        case Err(_):
            return 0
```

## json

```text
# doc: not-mylang
union Json:
    null, boolean: bool, integer: int, number: float,
    text: str, array: list[Json], object: dict[str, Json]

union Error:
    Malformed: str

loads(source: str) -> Result[Json, Error]
message(error: Error) -> str
dumps(value: Json) -> str
max_depth() -> int                   type_name(value: Json) -> str
null_value() -> Json                 boolean(value: bool) -> Json
integer(value: int) -> Json          number(value: float) -> Json
text(value: str) -> Json             array(items: list[Json]) -> Json
object(fields: dict[str, Json]) -> Json
is_null(value: Json) -> bool         as_bool(value: Json) -> Option[bool]
as_int(value: Json) -> Option[int]   as_float(value: Json) -> Option[float]
as_str(value: Json) -> Option[str]   as_list(value: Json) -> Option[list[Json]]
as_dict(value: Json) -> Option[dict[str, Json]]
get(value: Json, key: str) -> Option[Json]
at(value: Json, index: int) -> Option[Json]
```

`loads` parses strict RFC 8259: no comments, no trailing commas, no leading zero,
no bare fraction or exponent, no unescaped control character, no lone surrogate,
no trailing text, and no duplicate object key. Nesting deeper than `max_depth()`
is rejected. Objects keep the order their keys were parsed in, and `dumps`
reproduces it. A number without a fraction or exponent that fits the signed range
becomes `integer`; anything else becomes `number`. Each error message names the
byte offset where the scanner stopped.

A refusal is an `Error` value whose `Malformed` case carries the human-readable
reason; `message` returns that reason. Match on the case to branch on the
category rather than the text. Because the payload is a plain `str`, a module
that wraps `json.Error` in its own error union converts a propagated failure
with `?` and no hand-written translation.

```mylang
# doc: expect 42
module main
import json

def main() -> int:
    match json.loads("{\"rows\":[{\"n\":40},{\"n\":2}]}"):
        case Ok(document):
            return total(document)
        case Err(error):
            return 0 - len(json.message(error))

def total(document: json.Json) -> int:
    match json.get(document, "rows"):
        case Some(rows):
            return summed(rows)
        case None:
            return 1

def summed(rows: json.Json) -> int:
    sum = 0
    index = 0
    while index < 2:
        match json.at(rows, index):
            case Some(row):
                sum += field(row)
            case None:
                return 2
        index += 1
    return sum

def field(row: json.Json) -> int:
    match json.get(row, "n"):
        case Some(value):
            match json.as_int(value):
                case Some(count):
                    return count
                case None:
                    return 0
        case None:
            return 0
```

`dumps` renders infinities and not-a-number as `null`, because RFC 8259 has no
spelling for them. Rendering a float uses the shortest decimal that reads back as
the same value, written without an exponent.

## pool

```text
# doc: not-mylang
record Pool[T: copy + storable]: ...  record Handle[T: copy + storable]: ...

create[T: copy + storable](values: list[T]) -> Pool[T]
insert[T: copy + storable](store: Pool[T], value: T) -> Handle[T]
get[T: copy + storable](store: Pool[T], handle: Handle[T]) -> Option[T]
set[T: copy + storable](store: Pool[T], handle: Handle[T], value: T) -> bool
remove[T: copy + storable](store: Pool[T], handle: Handle[T]) -> bool
occupied[T: copy + storable](store: Pool[T], handle: Handle[T]) -> bool
count[T: copy + storable](store: Pool[T]) -> int
capacity[T: copy + storable](store: Pool[T]) -> int
handles[T: copy + storable](store: Pool[T]) -> list[Handle[T]]
```

A pool is the escape hatch for graphs and entity tables that a tracing collector
handles awkwardly: a stable, copyable name for a slot that stays valid while the
slot lives and reports absence once it does not. Removing a slot bumps its
generation, so every handle to the old occupant stops matching. A stale handle
and an out-of-range handle report `None` or `False`, and no handle ever traps.

A handle carries a slot index and a generation, not the identity of its pool, so
a handle from one pool passed to another is only rejected when that pool has no
matching live slot. Keep a handle with the pool it came from, the way an index
belongs to its list.

`Pool` is a value record whose fields are managed lists, so assigning one refers
to the same store rather than to a snapshot. `count()` rather than `len()` reports
the live population, because `len` is a reserved word.

```mylang
# doc: expect 42
module main
import pool

def main() -> int:
    seed: list[int] = []
    store = pool.create(seed)
    first = pool.insert(store, 10)
    second = pool.insert(store, 32)
    if not pool.remove(store, first) or pool.remove(store, first):
        return 1
    third = pool.insert(store, 10)
    if pool.capacity(store) != 2 or pool.count(store) != 2:
        return 2
    match pool.get(store, first):
        case Some(_):
            return 3
        case None:
            return live(store, second) + live(store, third)

def live(store: pool.Pool[int], handle: pool.Handle[int]) -> int:
    match pool.get(store, handle):
        case Some(value):
            return value
        case None:
            return 0
```

Creation takes a list rather than an explicit type argument, because a call cannot
yet spell `create[int]()`. Pass an empty annotated list for an empty pool.

## network

```text
# doc: not-mylang
resource Connection: network

class Chunk[const N: u64]:       result Connected:
    bytes: [N]u8                     ok: Connection,
    length: u64                      err: int
    eof: bool

result Read[const N: u64]:       result Written:
    ok: Chunk[N],                    ok: u64,
    err: int                         err: int

class Failure:                   result Closed:
    resource: Connection             ok: bool,
    code: int                        err: Failure

connect(net: Network) -> Connected effects(network)
read[const N: u64](connection: Connection) -> Read[N] effects(network)
write[const N: u64](connection: Connection, data: [N]u8) -> Written effects(network)
close(connection: Connection) -> Closed effects(network)
```

`connect` acquires a `Connection` through a `Network` that has already been
narrowed with `net.host(name)`; the narrowed capability pins the endpoint, so
`connect` takes no request string. `read` returns a `Chunk[N]` of `N` bytes and
`write` sends a fixed `[N]u8` array, both reporting their progress; `close`
completes the handle. Because a resource passed to a function is transferred, each
of `read`, `write` and `close` consumes the `Connection` it receives, so use the
raw `read_resource`/`write_resource`/`complete_resource` builtins when one
connection needs several operations.

```mylang
# doc: expect 0
module main
import network

def main() -> int:
    return 0
```

## random

```text
# doc: not-mylang
record Random: ...

seeded(seed: int) -> Random          from_word(word: u64) -> Random
from_entropy(capability: random_cap) -> Result[Random, str] effects(random, managed_allocation)
next_word(generator: Random) -> u64  random(generator: Random) -> float
randint(generator: Random, low: int, high: int) -> Result[int, str]
choice[T: copy + storable](generator: Random, items: list[T]) -> Option[T]
shuffle[T: copy + storable](generator: Random, items: list[T])
```

The stream is SplitMix64: deterministic simulation state, not a cryptographic
generator. Equal seeds give equal streams, and seed zero's first word is
`16294208416658607535`. A `Random` value keeps its state in a managed cell, so
copies of the value advance one shared stream rather than forking it.

`random` returns one of the 2^53 multiples of 2^-53 in `[0, 1)`. `randint` is
inclusive at both ends, covers the entire signed range without overflowing, and
removes modulo bias by rejecting the unusable tail of the word space. `shuffle`
is an in-place Fisher-Yates pass. Reading entropy requires the explicit
`random_cap`; importing the module grants nothing.

```mylang
# doc: expect 42
module main
import random

def main() -> int:
    generator = random.seeded(7)
    index = 0
    while index < 100:
        match random.randint(generator, 0 - 5, 5):
            case Ok(value):
                if value < 0 - 5 or value > 5:
                    return 1
            case Err(message):
                return 0 - len(message)
        index += 1
    items = [1, 2, 3, 4, 5]
    random.shuffle(generator, items)
    total = 0
    for value in items:
        total += value
    if random.random(generator) >= 1.0:
        return 2
    return total + 27
```

## time

```text
# doc: not-mylang
record Duration:                      record Instant:
    nanoseconds: int                     unix_nanoseconds: int

nanoseconds(count: int) -> Duration
microseconds(count: int) -> Result[Duration, str]
milliseconds(count: int) -> Result[Duration, str]
seconds(count: int) -> Result[Duration, str]
sum(first: Duration, second: Duration) -> Result[Duration, str]
difference(first: Duration, second: Duration) -> Result[Duration, str]
compare(first: Duration, second: Duration) -> int
to_seconds(value: Duration) -> float to_milliseconds(value: Duration) -> int
now(clock: clock_cap) -> Result[Instant, str] effects(clock, managed_allocation)
from_unix_nanoseconds(count: int) -> Instant
after(start: Instant, duration: Duration) -> Result[Instant, str]
elapsed(start: Instant, end: Instant) -> Result[Duration, str]
expired(deadline: Instant, current: Instant) -> bool
```

Both records count signed nanoseconds, which spans roughly 292 years either side
of the Unix epoch. Every constructor and every arithmetic operation that can leave
that range returns `Result`. `now` reads the host's wall clock through an explicit
`clock_cap` and keeps the provider's unavailable, denied and failed categories
apart in its message.

These are wall-clock instants: a host clock may move backward, so `elapsed`
rejects a reversed pair rather than inventing a negative span. The capability
surface exposes no monotonic counter, so this module offers no monotonic clock,
no sleep, and no calendar or time-zone conversion.

```mylang
# doc: expect 42
module main
import time

def main() -> int:
    start = time.from_unix_nanoseconds(1000000000)
    match time.milliseconds(1500):
        case Ok(step):
            return advanced(start, step)
        case Err(message):
            return 0 - len(message)

def advanced(start: time.Instant, step: time.Duration) -> int:
    match time.after(start, step):
        case Ok(deadline):
            if not time.expired(deadline, deadline) or time.expired(deadline, start):
                return 1
            return measured(start, deadline)
        case Err(message):
            return 0 - len(message)

def measured(start: time.Instant, deadline: time.Instant) -> int:
    match time.elapsed(start, deadline):
        case Ok(span):
            if time.to_milliseconds(span) != 1500 or time.to_seconds(span) != 1.5:
                return 2
            return int(time.to_seconds(span) * 28.0)
        case Err(message):
            return 0 - len(message)
```

## Focused references

- [Time and randomness](standard-time-random.md) specifies the capability
  contracts, the pinned SplitMix64 vectors and the arithmetic limits.
- [Binary64 floating point](floating-point.md) specifies what `float` itself
  does, which is what `math` builds on.
- [Time and random example](../examples/standard-time-random/main.my) exercises
  reproducible streams and rejected bounds without ambient authority.
- [Managed word counts](../examples/python-word-count/main.my) shows the builtin
  collections these modules are written against.

## Contracts these modules share

Managed collections grow automatically; see [managed memory](managed-memory.md),
and [managed arenas](arenas.md) for releasing a phase of work in one step. A
module import grants no authority: clock and entropy functions take capability
parameters the host supplies, and every other module is pure. Runtime byte budgets
bound backing and bookkeeping allocation. Text indexes count Unicode scalar
values, there is no Unicode normalization, and case mapping is ASCII only.

Error messages are ordinary text meant for a human reader; a module that can fail
carries them in an error union so the category is matchable and the text is only
printed. See [Error unions](#error-unions).

## Error unions

A standard module whose operations can fail exports an error union named `Error`
and returns `Result[T, Module.Error]` from every exported fallible operation
instead of `Result[T, str]`. Each case carries a `str` payload, and the exported
`message(error)` helper returns the human-readable reason a caller would
otherwise have matched as bare text. Match on the case to branch on the
category; the text is for people and may change between releases. Adding a case
to a published error union is a breaking interface change, because a caller that
matches exhaustively stops compiling.

The `json` and `strings` modules follow this contract today; `math`, `time`,
`random`, `base64` and `hex` still return `Result[T, str]`.

`?` converts automatically at such a boundary: when the propagated result's
error type is the payload type of a case of the enclosing function's error
union, the error wraps in that case with no hand-written translation helper.

```mylang
# doc: expect 42
module main
import json

union AppError:
    Json: json.Error


def size(source: str) -> Result[int, AppError]:
    document = json.loads(source)?
    return Ok(len(json.dumps(document)))


def main() -> int:
    match size("{bad}"):
        case Ok(_):
            return 1
        case Err(error):
            match error:
                case AppError.Json(detail):
                    if len(json.message(detail)) > 0:
                        return 42
                    return 2
```

## Limits

- Decimal-to-float conversion is accurate rather than correctly rounded; `sqrt`
  uses the correctly rounded binary64 instruction.
- There are no transcendental functions: no `exp`, `log`, `sin` or `pow` with a
  floating exponent.
- `sort` has no ordering contract to generalize over, so a generic sort needs an
  integer key function.
- `pool.create` takes a seed list instead of an explicit type argument, and
  `json`'s union variants are built through the module's constructor functions.
- No module reads or writes a file; `path` is text algebra only.
