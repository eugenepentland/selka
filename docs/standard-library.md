# Standard library

Nineteen modules ship inside the compiler. They are ordinary guest source
built on the managed types described in the [language guide](python-syntax.md),
[managed memory](managed-memory.md) and [managed byte strings](bytes.md): growable arrays (`T[]`),
`dict`, `str`, `bytes`, value records, optional values (`T?`) and checked results. There is no
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
| [`byte_builder`](#byte_builder) | incremental binary and UTF-8 output assembly |
| [`json`](#json) | strict RFC 8259 parsing, rendering and typed access |
| [`parallel`](#parallel) | ordered mapping with scoped workers in experimental zero-RC builds |
| [`pool`](#pool) | generational handles into a reusable slot store |
| [`memo`](#memo) | bounded, process-local reuse of pure computations |
| [`hashes`](#hashes) | block-based SHA-256 in Selka |
| [`cache_record`](#cache_record) | canonical string-array storage records with integrity checks |
| [`persistent_memo`](#persistent_memo) | verified cross-process byte snapshots of pure computations |
| [`durable`](#durable) | retained chunk progress and recoverable atomic output publication |
| [`network`](#network) | capability-based connections and byte I/O, and a denied stand-in `Network` |
| [`random`](#random) | seeded SplitMix64 streams, entropy-seeded generators and a seeded stand-in `Entropy` |
| [`time`](#time) | wall-clock instants, checked durations and a simulated `Clock` |
| [`filesystem`](#filesystem) | an empty in-memory stand-in `Filesystem` |
| [`environment`](#environment) | a stand-in `Environment` holding fixed pairs |

`time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`,
`environment.fixed` and `network.denied` build deterministic stand-ins for the
capabilities a program is otherwise handed by its entry point. Building one needs
no capability and is not an effect, and a stand-in never reaches a host resource,
so code that takes a `Clock` or a `Filesystem` can be tested by passing one; see
[deterministic stand-ins](effects.md#deterministic-stand-ins) and
[capability parameters in tests](tooling/guest-tests.md#capability-parameters).

Managed-value modules report conversion failures using checked results or optional values.
The byte builder's checked append operations return a success flag. The network
module uses the resource-result types documented below.

## byte_builder

```text
# doc: not-mylang
record Builder: ...
create() -> Builder
append(mut builder: Builder, data: bytes) -> Unit
append_range(mut builder: Builder, data: bytes, start: int, end: int) -> bool
append_text(mut builder: Builder, text: str) -> Unit
append_int(mut builder: Builder, value: int) -> Unit
append_byte(mut builder: Builder, value: int) -> bool
append_float(mut builder: Builder, value: float) -> bool
append_spaces(mut builder: Builder, count: int) -> bool
reserve(mut builder: Builder, extra: int) -> bool
finish(builder: Builder) -> bytes
```

`byte_builder` assembles an immutable byte string in one mutable `byte_buffer`
([in-place octet methods](bytes.md#writing-octets-in-place)) whose backing
storage grows by doubling, so `append`, `append_range`, `append_byte`,
`append_spaces`, `append_text`, `append_int` and `append_float` write each
fragment's octets straight into that capacity and no fragment allocates a value
for itself: `append_text` builds no temporary encoded `bytes`, and `append_int`
and `append_float` no temporary text or byte value at all. `append_float` writes
the canonical spelling `str(value)` prints, built on the runtime's own stack. `finish` publishes the buffer as an immutable snapshot
with `bytes(buffer)`, which copies no octet: the snapshot reads the buffer's own
storage and the buffer's next write moves its octets into a private block first,
so `finish` contributes `managed_allocation` but does not mutate the builder;
when the assembled octets are only going to a stream,
`stream.write(builder.buffer)` writes the buffer's own storage instead and skips
that copy.

The checked appends reject rather than trap, and they reject before writing
anything, so a refused call leaves the builder byte-for-byte unchanged:
`append_range` rejects a negative `start`, an `end` below `start` or an `end`
past `len(data)` — an empty range succeeds and changes nothing — while
`append_byte` rejects values outside `0..255`, `append_spaces` rejects negative
counts and `reserve` rejects a negative count. A rejection answers `False`; a
no-op success such as `reserve(0)` answers `True` and changes nothing.
`append_int` writes its digits through a small fixed local buffer, so it builds
no managed intermediate value at all. `reserve` grows the buffer's
capacity for a further `extra` octets without changing the finished length.

`finish` returns an immutable snapshot. The builder remains usable, and later
appends — including an append of a snapshot back into its own builder — do not
change earlier results. All mutating operations carry `mutation` and
`managed_allocation` effects and mutate only their builder argument.

```mylang
# doc: expect 42
import byte_builder

func main() -> int:
    mut output = byte_builder.create()
    byte_builder.append_text(mut output, "λ")
    if not byte_builder.append_byte(mut output, 0):
        return 1
    if not byte_builder.append_spaces(mut output, 3):
        return 2
    mut smallest = -9223372036854775808
    byte_builder.append_int(mut output, smallest)
    if not byte_builder.append_range(mut output, b"0123456789", 4, 6):
        return 3
    mut snapshot = byte_builder.finish(output)
    if byte_builder.append_range(mut output, b"0123456789", 6, 99):
        return 4
    if not byte_builder.reserve(mut output, 128):
        return 5
    if byte_builder.finish(output) != snapshot:
        return 6
    return len(snapshot) + 14
```

## math

```text
# doc: not-mylang
pi() -> float                        e() -> float
nan() -> float                       infinity() -> float
is_nan(value: float) -> bool         is_inf(value: float) -> bool
is_finite(value: float) -> bool      fabs(value: float) -> float
sign(value: float) -> int            sqrt(value: float) -> float
sin(value: float) -> float           cos(value: float) -> float
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
import math

func main() -> int:
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

`sqrt` calls the internal binary64 square-root helper on its ordinary `float` argument,
so it is the correctly rounded square root. `pow` takes an integer exponent and
squares repeatedly; magnitudes above 4096 saturate to a same-parity magnitude,
which preserves the sign and the overflow or underflow outcome.

`sin` and `cos` take angles in radians and use the native binary64 operations,
including range reduction for large finite angles. Sine preserves negative zero;
cosine of either zero is one. Infinite angles and not-a-number produce
not-a-number. These are pure operations and require no `Host` capability.

```mylang
# doc: expect 0.0 1.0
import math

func main(out: Stream) -> int:
    out.print(math.sin(0.0), math.cos(0.0))
    return 0
```

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
find(text: str, needle: str) -> int?
count(text: str, needle: str) -> int
strip(text: str) -> str              lstrip(text: str) -> str
rstrip(text: str) -> str             lines(text: str) -> str[]
upper(text: str) -> str              lower(text: str) -> str
repeat(text: str, times: int) -> Result[str, Error]
pad_left(text: str, width: int, fill: str) -> Result[str, Error]
pad_right(text: str, width: int, fill: str) -> Result[str, Error]
substitute(text: str, needle: str, insertion: str) -> Result[str, Error]
to_int(text: str) -> int?     to_float(text: str) -> float?
format_int(value: int, base: int) -> Result[str, Error]
format_float(value: float, decimals: int) -> Result[str, Error]
ord(text: str) -> Result[int, Error]
chr(code: int) -> Result[str, Error]
```

`str` already provides `+`, `==`, `in`, indexing, slicing, iteration,
`split(separator)`, `separator.join(parts)` and `encode()`. This module adds what
it lacks. `upper` and `lower` map ASCII only. `substitute` is spelled that way
because `replace` is a reserved word. `ord` reads the Unicode scalar value of a
single-character text and `chr` builds that text from a scalar value; both reject
a length other than one, and `chr` rejects surrogates and code points past
`0x10FFFF`. The fallible builders return `Error`: `Invalid` marks an argument
outside the operation's accepted range, `Overflow` marks a value that does not fit
the rendering, and `message(error)` returns the human-readable reason.

```mylang
# doc: expect 42
import strings

func main() -> int:
    if not strings.starts_with("answer=42", "answer"):
        return 1
    if strings.strip("  spaced \t") != "spaced":
        return 2
    match strings.find("answer=42", "="):
        case Some(position):
            return decoded("answer=42"[position + 1:9])
        case None:
            return 3

func decoded(body: str) -> int:
    match strings.to_int(body):
        case Some(value):
            return value
        case None:
            return 4
```

`to_int` rejects anything the signed range cannot hold, including
`9223372036854775808`. `to_float` delegates to `parse_float(text)`, so both spellings
use the pinned numeric grammar and parser. This includes surrounding ASCII
whitespace, single underscores between digits, and `inf`, `infinity`, and `nan`;
these forms were rejected by the older `strings.to_float` implementation.
`format_float` rounds the exact binary value, so `format_float(2.675, 2)` is
`"2.67"` as in C and Python (2.675 is stored as 2.67499999…). A value that is
exactly halfway rounds away from zero — `format_float(0.125, 2)` is `"0.13"`
where Python prints `0.12` — and a result that rounds to zero is printed without a
sign (`"0.00"` for `-0.001`). Values too large for fixed decimals are rejected.
`format_float` agrees with `round(x, n)`, which rounds the same way; an
[f-string format specification](text.md#format-specifications) such as
`f"{x:.2f}"` rounds an exact tie to even as CPython does (`"0.12"`), and keeps the
sign of a negative zero (`"-0.00"`).

## sort

```text
# doc: not-mylang
compare_strs(a: str, b: str) -> int
sort_ints(values: int[]) -> int[]
sort_floats(values: float[]) -> float[]
sort_strs(values: str[]) -> str[]
sort_by_key[T: copy + storable](values: T[], key: func(T) -> int effects()) -> T[]
is_sorted_ints(values: int[]) -> bool
binary_search(values: int[], target: int) -> int?
min_int(values: int[]) -> int?
max_int(values: int[]) -> int?
min_str(values: str[]) -> str?
unique_ints(values: int[]) -> int[]
unique_strs(values: str[]) -> str[]
```

The concrete `sort_ints`, `sort_floats` and `sort_strs` wrappers delegate to the
same stable merge engine as `sorted` and `values.sort()`, returning a new list and
leaving the input untouched. That engine keeps the ascending runs a list already
has, reverses strictly descending ones, extends short runs by insertion and merges
through one scratch buffer of at most half the list, with a comparison compiled
for each element type, so an ordered or reversed list sorts in linear time.
Not-a-number follows every ordered float, equal values and signed zeros retain
their input order, and text compares its stored Unicode scalar values directly.
`compare_strs` and `min_str` therefore allocate no temporary encodings. A generic
sort over an arbitrary element type needs an integer key function, because the
language has no ordering contract: `copy`, `equality`, `integer`, `codec` and
`storable` are the only generic requirements.

`sort_by_key` is a thin forwarder to Python's keyed sort: it returns
`sorted(values, key=key)`, which computes each element's key exactly once, in
list order, and gathers the elements into the new list with the native keyed sort
(see [keyed sorting](python-syntax.md#keyed-sorting) for `key=`, `reverse=` and
the `float`, `str`, `bytes` and tuple keys the method and `sorted` accept). A key
function that traps on several elements reports the first of them in list order;
before the keyed sort existed, `sort_by_key` asked for keys in the order a
recursive merge first needed them. Sorting NaNs last is a deliberate
regularization: the earlier comparator treated a NaN as tied with every value,
so its position could depend on merge boundaries rather than one ordering
contract.

```mylang
# doc: expect 42
import sort

record Entry:
    name: str
    score: int

func by_score(entry: Entry) -> int effects():
    return entry.score

func main() -> int:
    mut ranked = sort.sort_by_key([Entry(name="c", score=30), Entry(name="a", score=12)], by_score)
    if ranked[0].name != "a":
        return 1
    mut ordered = sort.sort_ints([9, 1, 4])
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
join(left: str, right: str) -> str   join_all(parts: str[]) -> str
basename(value: str) -> str          dirname(value: str) -> str
splitext(value: str) -> Split        stem(value: str) -> str
extension(value: str) -> str         components(value: str) -> str[]
normalize(value: str) -> str
```

These operations read and build text only. They open nothing, resolve no symbolic
link and need no capability, so they are usable inside a `noio` function.

```mylang
# doc: expect 42
import path

func main() -> int:
    mut full = path.join("/usr/local", "lib/mylang/../answer.txt")
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
import hex

func main() -> int:
    mut text = hex.encode(b"\x0f\xa0")
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
import base64
import hex

func main() -> int:
    mut encoded = base64.b64encode(b"foobar")
    if encoded != b"Zm9vYmFy" or base64.b64encode(b"f") != b"Zg==":
        return 1
    match base64.b64decode(encoded):
        case Ok(raw):
            if hex.encode(raw) != "666f6f626172":
                return 2
            return refused() + len(raw) * 7
        case Err(message):
            return 0 - len(message)

func refused() -> int:
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
    text: str, array: Json[], object: dict[str, Json]

union Error:
    Malformed: str

loads(source: str) -> Result[Json, Error]
message(error: Error) -> str
dumps(value: Json) -> str
max_depth() -> int                   type_name(value: Json) -> str
null_value() -> Json                 boolean(value: bool) -> Json
integer(value: int) -> Json          number(value: float) -> Json
text(value: str) -> Json             array(items: Json[]) -> Json
object(fields: dict[str, Json]) -> Json
is_null(value: Json) -> bool         as_bool(value: Json) -> bool?
as_int(value: Json) -> int?   as_float(value: Json) -> float?
as_str(value: Json) -> str?   as_list(value: Json) -> Json[]?
as_dict(value: Json) -> dict[str, Json]?
get(value: Json, key: str) -> Json?
at(value: Json, index: int) -> Json?
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
import json

func main() -> int:
    match json.loads("{\"rows\":[{\"n\":40},{\"n\":2}]}"):
        case Ok(document):
            return total(document)
        case Err(error):
            return 0 - len(json.message(error))

func total(document: json.Json) -> int:
    match json.get(document, "rows"):
        case Some(rows):
            return summed(rows)
        case None:
            return 1

func summed(rows: json.Json) -> int:
    mut sum = 0
    mut index = 0
    while index < 2:
        match json.at(rows, index):
            case Some(row):
                sum += field(row)
            case None:
                return 2
        index += 1
    return sum

func field(row: json.Json) -> int:
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

## parallel

```text
# doc: not-mylang
map[T: copy + storable, R: copy + storable](values: T[], function: func(T) -> R) -> R[]
```

`map` applies a read-only function to each input and returns results in input
order. Ordinary builds execute it sequentially. Experimental zero-RC builds
borrow input elements for scoped parallel work and join every task before
returning. A callback returning managed input data must explicitly copy it;
newly created results transfer to the output. The initial API takes one
read-only parameter and has no closure captures or detached tasks. See
[scoped parallel work](managed-memory.md#explicit-values-and-scoped-parallel-work-experimental-closeout).

```mylang
# doc: expect 0
import parallel

func square(value: int) -> int:
    return value * value


func main() -> int:
    const input = [1, 2, 3]
    const output = parallel.map(input, square)
    assert output == [1, 4, 9]
    assert input == [1, 2, 3]
    return 0
```

## pool

```text
# doc: not-mylang
record Pool[T: copy + storable]: ...  record Handle[T: copy + storable]: ...

create[T: copy + storable](values: T[]) -> Pool[T]
insert[T: copy + storable](mut store: Pool[T], value: T) -> Handle[T]
get[T: copy + storable](store: Pool[T], handle: Handle[T]) -> T?
set[T: copy + storable](mut store: Pool[T], handle: Handle[T], value: T) -> bool
remove[T: copy + storable](mut store: Pool[T], handle: Handle[T]) -> bool
occupied[T: copy + storable](store: Pool[T], handle: Handle[T]) -> bool
count[T: copy + storable](store: Pool[T]) -> int
capacity[T: copy + storable](store: Pool[T]) -> int
handles[T: copy + storable](store: Pool[T]) -> Handle[T][]
```

A pool is the escape hatch for graphs and entity tables that values cannot
express directly: a stable, copyable name for a slot that stays valid while the
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
import pool

func main() -> int:
    mut seed: int[] = []
    mut store = pool.create(seed)
    mut first = pool.insert(mut store, 10)
    mut second = pool.insert(mut store, 32)
    if not pool.remove(mut store, first) or pool.remove(mut store, first):
        return 1
    mut third = pool.insert(mut store, 10)
    if pool.capacity(store) != 2 or pool.count(store) != 2:
        return 2
    match pool.get(store, first):
        case Some(_):
            return 3
        case None:
            return live(store, second) + live(store, third)

func live(store: pool.Pool[int], handle: pool.Handle[int]) -> int:
    match pool.get(store, handle):
        case Some(value):
            return value
        case None:
            return 0
```

Creation takes a seed list, which also supplies the element type. Pass an empty
annotated list for an empty pool.

## memo

```text
# doc: not-mylang
Key.Number(value: int) | Key.Text(value: str) | Key.Data(value: bytes)
Error.InvalidCapacity(value: str)
message(error: Error) -> str
Cache[V: equality + storable]
Entry[V: equality + storable]
Lookup[V: equality + storable] { value: V, reused: bool }
create(max_entries: int, compute: func(Key) -> V effects(managed_allocation)) -> Result[Cache[V], Error]
call(mut cache: Cache[V], key: Key) -> Lookup[V]
clear(mut cache: Cache[V]) -> Unit
count(cache: Cache[V]) -> int
capacity(cache: Cache[V]) -> int
```

`memo` reuses completed results within one running application. `create` binds
the computation and accepts an entry limit from zero through 65,536. An invalid
limit returns `Error.InvalidCapacity`; `message` supplies its explanatory text.
Zero disables retention, so every `call` computes and returns `reused=False`.
For positive limits, a hit returns the stored snapshot and `reused=True`.
Misses fill the cache, then replace entries in insertion order. Hits do not
refresh that order. `count` reports retained entries, `capacity` reports the
configured limit, and `clear` releases the cache's entries and resets its order.

The callback takes the complete `Key` argument and permits only managed
allocation. External I/O, host calls, clock, randomness, environment access,
caller mutation and captured local state are ineligible. `noio` alone is not
a purity contract. Tagged keys compare exactly: integer `1`, text `"1"` and
bytes `b"1"` are separate arguments. Arbitrary floating-point and collection
keys are not accepted. Each `Entry` also records the actual callable; replacing
`cache.compute` cannot serve an earlier callback's result for the same key.

Results are copyable, storable values with equality support. Lists and records
containing lists are permitted: results, keys and copied caches keep independent
value snapshots when callers later mutate their copies. Capabilities, owned
resources and function values are excluded from results. A trap propagates
normally; insertion happens only after the computation returns. This library
does not recover a trapped process.

```mylang
# doc: expect 42
import memo

func square(key: memo.Key) -> int:
    match key:
        case memo.Key.Number(value=value):
            return value * value
        case memo.Key.Text(value=value):
            return len(value)
        case memo.Key.Data(value=value):
            return len(value)

func main() -> int:
    match memo.create(2, square):
        case Ok(created):
            mut cache = created
            const first = memo.call(mut cache, memo.Key.Number(value=6))
            const second = memo.call(mut cache, memo.Key.Number(value=6))
            if first.reused or not second.reused or second.value != 36:
                return 1
            if memo.count(cache) != 1 or memo.capacity(cache) != 2:
                return 2
            memo.clear(mut cache)
            return second.value + 6
        case Err(error):
            return len(memo.message(error))
```

Retention is bounded by entry count. Lookup scans at most that many entries;
arbitrary key/result payload sizes remain subject to the application's runtime
memory limit. The cache is intended for small, explicit working sets. Use the
constructor and operations to maintain its representation; `Entry` and the
storage fields are implementation details, not a format for serialization.
There is no filesystem access, expiration policy or cross-process reuse.
The separate `persistent_memo` and `durable` modules add compiler-issued
implementation identities and a qualified native storage provider.

## network

```text
# doc: not-mylang
resource Connection: network

record Chunk[const N: u64]:      result Connected:
    bytes: [N]u8                     ok: Connection,
    length: u64                      err: int
    eof: bool

result Read[const N: u64]:       result Written:
    ok: Chunk[N],                    ok: u64,
    err: int                         err: int

record Failure:                  result Closed:
    resource: Connection             ok: bool,
    code: int                        err: Failure

connect(net: Network) -> Connected effects(network)
read[const N: u64](connection: Connection) -> Read[N] effects(network)
write[const N: u64](connection: Connection, data: [N]u8) -> Written effects(network)
close(connection: Connection) -> Closed effects(network)
denied() -> Network                  denied_here() -> int
describe(code: int) -> str
```

`connect` acquires a `Connection` through a `Network` that has already been
narrowed with `net.host(name)`; the narrowed capability pins the endpoint, so
`connect` takes no request string. `read` returns a `Chunk[N]` of `N` bytes and
`write` sends a fixed `[N]u8` array, both reporting their progress; `close`
completes the handle. Because a resource passed to a function is transferred, each
of `read`, `write` and `close` consumes the `Connection` it receives, so use the
raw `read_resource`/`write_resource`/`complete_resource` builtins when one
connection needs several operations.

`denied` builds a stand-in `Network` that reaches nothing: every acquisition
through it, or through a `net.host(...)` narrowing of it, fails with the
`Connected.err` code `denied_here()`. `describe` spells any `Connected.err` code
as a reason; for that one it reads `network access is denied in this context:
this Network is a deterministic stand-in`.

```mylang
# doc: expect 6 network access is denied in this context: this Network is a deterministic stand-in
import network

func main(out: Stream) -> int:
    mut net = network.denied()
    match network.connect(net.host("127.0.0.1:8000")):
        case network.Connected.ok(_):
            out.print("connected")
        case network.Connected.err(code):
            out.print(code, network.describe(code))
    return 0
```

## random

```text
# doc: not-mylang
record Random: ...

seeded(seed: int) -> Random          from_word(word: u64) -> Random
from_entropy(capability: random_cap) -> Result[Random, str] effects(random, managed_allocation)
seeded_entropy(seed: int) -> Entropy
next_word(mut generator: Random) -> u64  random(mut generator: Random) -> float
randint(mut generator: Random, low: int, high: int) -> Result[int, str]
choice[T: copy + storable](mut generator: Random, items: T[]) -> T?
shuffle[T: copy + storable](mut generator: Random, mut items: T[])
```

The stream is SplitMix64: deterministic simulation state, not a cryptographic
generator. Equal seeds give equal streams, and seed zero's first word is
`16294208416658607535`. Copying a `Random` snapshots its current position;
each copy advances independently through the same remaining sequence. Pass
`mut generator` to advance the caller's stream.

`random` returns one of the 2^53 multiples of 2^-53 in `[0, 1)`. `randint` is
inclusive at both ends, covers the entire signed range without overflowing, and
removes modulo bias by rejecting the unusable tail of the word space. `shuffle`
is an in-place Fisher-Yates pass. Reading entropy requires the explicit
`random_cap`; importing the module grants nothing. `seeded_entropy` builds a
stand-in `Entropy` whose words are the SplitMix64 stream of its seed, so
`from_entropy` on it is reproducible, and each read advances it.

```mylang
# doc: expect 42
import random

func main() -> int:
    mut generator = random.seeded(7)
    mut index = 0
    while index < 100:
        match random.randint(mut generator, 0 - 5, 5):
            case Ok(value):
                if value < 0 - 5 or value > 5:
                    return 1
            case Err(message):
                return 0 - len(message)
        index += 1
    mut items = [1, 2, 3, 4, 5]
    random.shuffle(mut generator, mut items)
    mut total = 0
    for value in items:
        total += value
    if random.random(mut generator) >= 1.0:
        return 2
    return total + 27 - drawn(random.seeded_entropy(3)) + drawn(random.seeded_entropy(3))

func drawn(entropy: Entropy) -> int:
    match random.from_entropy(entropy):
        case Ok(sampled):
            mut generator = sampled
            return int(random.next_word(mut generator) % 1000u64)
        case Err(_):
            return 500
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
simulated_clock(start: Instant) -> Clock
advance(clock: Clock, duration: Duration) -> Result[Unit, str]
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

`simulated_clock` builds a stand-in `Clock` that reads `start` until `advance`
moves it (backward for a negative duration, the way a wall clock may step).
Copies of it share one reading. A host-granted clock cannot be moved, and
`advance` answers it with `Err("only a simulated clock can be advanced")`.

```mylang
# doc: expect 90
import time

func since(clock: Clock, start: time.Instant) -> int:
    match time.now(clock):
        case Ok(current):
            match time.elapsed(start, current):
                case Ok(span):
                    return time.to_milliseconds(span) // 1000
                case Err(_):
                    return -1
        case Err(_):
            return -1

func main() -> int:
    mut start = time.from_unix_nanoseconds(0)
    mut clock = time.simulated_clock(start)
    match time.seconds(90):
        case Ok(step):
            _ = time.advance(clock, step)
        case Err(_):
            return -1
    return since(clock, start)
```

```mylang
# doc: expect 42
import time

func main() -> int:
    mut start = time.from_unix_nanoseconds(1000000000)
    match time.milliseconds(1500):
        case Ok(step):
            return advanced(start, step)
        case Err(message):
            return 0 - len(message)

func advanced(start: time.Instant, step: time.Duration) -> int:
    match time.after(start, step):
        case Ok(deadline):
            if not time.expired(deadline, deadline) or time.expired(deadline, start):
                return 1
            return measured(start, deadline)
        case Err(message):
            return 0 - len(message)

func measured(start: time.Instant, deadline: time.Instant) -> int:
    match time.elapsed(start, deadline):
        case Ok(span):
            if time.to_milliseconds(span) != 1500 or time.to_seconds(span) != 1.5:
                return 2
            return int(time.to_seconds(span) * 28.0)
        case Err(message):
            return 0 - len(message)
```

## filesystem

```text
# doc: not-mylang
memory() -> Filesystem
```

`memory` builds an empty in-memory stand-in `Filesystem`. It serves every
whole-path helper (`read_file`, `read_text`, `write_file`, `write_text`,
`exists`, `listdir`, `mkdir`, `remove`), `fs.open(path, mode)` in the `r`, `w`
and `a` modes with every handle method, and the narrowings `fs.dir(path)` and
`fs.read_only()`, which stay in memory. It follows the rules of a `--restrict`
root: paths are relative, a path with an empty, `.` or `..` component is denied,
a file's parent directory must exist, `remove` takes a file or an empty
directory, and error texts match the host surface. `listdir` sorts by name, and
the surface exposes no timestamps, so nothing it reports depends on when or in
which order it was written. It never touches the disk.

```mylang
# doc: expect Ok(['data', 'notes.txt']) Ok('hello')
import filesystem

func save(fs: Filesystem, text: str) -> Result[Unit, str]:
    return fs.write_text("notes.txt", text)

func main(out: Stream) -> int:
    mut fs = filesystem.memory()
    _ = save(fs, "hello")
    _ = fs.mkdir("data")
    out.print(fs.listdir(""), fs.read_text("notes.txt"))
    return 0
```

## environment

```text
# doc: not-mylang
fixed(values: dict[str, str]) -> Environment
```

`fixed` builds a stand-in `Environment` holding exactly `values`: `env.get`
answers from them, `env.names()` lists them sorted, and `env.only(...)` narrows
them, trapping `R_CAPABILITY` on a name outside the narrowed set as a host
`Environment` does. It never reads the process environment. A name must be
nonempty, at most 128 bytes and free of `=`, and a value at most 16384 bytes
(`R_ENVIRONMENT` otherwise); neither may contain NUL.

```mylang
# doc: expect /home/test ['HOME', 'LANG']
import environment

func home(env: Environment) -> str:
    match env.get("HOME"):
        case Some(value):
            return value
        case None:
            return "/"

func main(out: Stream) -> int:
    mut env = environment.fixed({"HOME": "/home/test", "LANG": "C"})
    out.print(home(env), env.names())
    return 0
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

Managed collections grow automatically and are released when their last owner
goes away; see [managed memory](managed-memory.md). A
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
import json

enum AppError:
    Json(value: json.Error)


func size(source: str) -> Result[int, AppError]:
    mut document = try json.loads(source)
    return Ok(len(json.dumps(document)))


func main() -> int:
    match size("{bad}"):
        case Ok(_):
            return 1
        case Err(error):
            match error:
                case AppError.Json(value=detail):
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

## hashes

`hashes.sha256(data: bytes) -> str` returns 64 lowercase hexadecimal digits.
The implementation is Selka, reads 64-byte blocks, and uses bounded working
arrays without making a padded copy of the whole input.

```mylang
# doc: expect 42
import hashes

func main() -> int:
    if hashes.sha256(b"abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad":
        return 42
    return 1
```

## cache_record

`cache_record.encode(fields: str[]) -> bytes` writes canonical string-array JSON
inside a versioned SHA-256 envelope. `decode(data)` returns `Result[str[], Error]`;
`message(error)` explains a rejected record. Truncated, altered, noncanonical
and nonstring records are rejected. The checksum detects damage; it does not
authenticate an untrusted writer. Bound storage reads before decoding.

```mylang
# doc: expect 42
import cache_record

func main() -> int:
    match cache_record.decode(cache_record.encode(["schema-v1", "00ff"])):
        case Ok(fields):
            if fields == ["schema-v1", "00ff"]:
                return 42
            return 1
        case Err(_):
            return 2
```

## persistent_memo

`persistent_memo.call(fs, options, compute, key)` returns
`Result[Lookup, Error]`, where `Lookup` holds `value: bytes` and `reused: bool`.
The callback takes `memo.Key` and permits only managed allocation. It returns
an immutable byte snapshot. Use `message(error)` to describe a failure.

Pass a filesystem capability narrowed to an existing dedicated cache directory.
`Options(max_entries, max_bytes)` accepts 0–256 entries and 0–1,048,576 raw bytes
of key plus value per entry. Zero entries forces execution without storage.
Oversized values and callbacks without a qualified `function_digest` execute
without retaining a receipt. Tags distinguish text, bytes and integer keys.

```mylang
# doc: expect 42
import filesystem
import memo
import persistent_memo

func encoded(key: memo.Key) -> bytes:
    match key:
        case memo.Key.Number(value=value):
            return str(value).encode()
        case memo.Key.Text(value=value):
            return value.encode()
        case memo.Key.Data(value=value):
            return value

func main() -> int:
    const options = persistent_memo.Options(max_entries=0, max_bytes=1024)
    match persistent_memo.call(filesystem.memory(), options, encoded, memo.Key.Number(value=42)):
        case Ok(found):
            if not found.reused and found.value == b"42":
                return 42
            return 1
        case Err(_):
            return 2
```

For native persistence, replace the stand-in and zero limit with a real narrowed
`Filesystem` and positive entry limit. Directory ownership serializes readers,
writers and eviction. Each record binds the actual callable's reachable code,
source schemas and execution context, exact tagged input, canonical byte encoding
and checksum. A malformed record is a miss; provider failures remain errors.
Lowered entry limits trim the directory deterministically. Entry count and
per-entry size bound retention; there is no TTL or ambient file freshness rule.

## durable

`durable.run(fs, request, compute)` returns `Result[Report, Error]`. A pure
`func(bytes, bytes) -> durable.Step effects(managed_allocation)` receives one
captured chunk and the last state snapshot; `Step(output, state)` returns bytes.
`Request(input, chunks, initial_state, output_path, max_bytes)` captures the
workflow inputs. `Report(fresh, reused, output_digest, state)` counts newly
computed and previously committed steps separately. `message(error)` describes
invalid, corrupt, incompatible, uncacheable and provider failures.

```mylang
# doc: expect 42
import durable
import filesystem

func copy_chunk(chunk: bytes, state: bytes) -> durable.Step:
    return durable.Step(output=chunk, state=state)

func main() -> int:
    # Reserved output names are rejected before any storage operation.
    const request = durable.Request(input=b"a\n", chunks=[b"a\n"], initial_state=b"", output_path="run.json", max_bytes=1024)
    if durable.run(filesystem.memory(), request, copy_chunk) == Err(durable.Error.Invalid):
        return 42
    return 1
```

A real run needs an existing dedicated native directory, such as
`fs.dir("durable")`, and an ordinary output filename such as `final.csv`.
The caller creates the directory and synchronizes its parent before beginning
if it needs directory creation to survive a crash. Limits permit at most 1,024
chunks and a selected 1–8 MiB of input, total chunk bytes, total output and each
state snapshot. The output filename cannot escape the directory or collide with
`run.json`, `chunk-` artifacts or `.myl-durable-` temporary files.

Each completed artifact is synchronized before its digest enters a synchronized
journal replacement. Recovery validates the request, callable identity, every
committed artifact and the chain of state snapshots before skipping work.
Changed input, implementation, schemas, output name or limits rejects the old
journal. Corrupt committed evidence fails closed; preserve it for diagnosis or
start a new directory. Uncommitted artifacts and abandoned temporary files are
collected while holding the directory lease. Committed progress is retained.

Final output is atomically published from committed bytes. A failed directory
sync may mean publication occurred: the operation returns an error, and retrying
the same request safely checks or republishes the intended bytes. A second
recoverer receives a busy error while the first owns the directory; ownership
is released on normal exit or process death. Process-crash recovery is qualified
with actual termination at publication boundaries. Power-loss behavior has not
been experimentally established. These APIs do not replay network requests,
external database transactions or arbitrary effects.

The complete CSV application is in
[`test/fixtures/application-cache/application.my`](../test/fixtures/application-cache/application.my).
Its developer qualification driver runs cold, warm, edit, corruption and crash
cases against independently calculated output.
