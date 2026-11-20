# Standard library

Forty-two modules ship inside the compiler: ordinary guest source on the managed types of the [language guide](python-syntax.md), [managed memory](managed-memory.md) and [managed byte strings](bytes.md). Import one by name. An import grants no authority; only a capability parameter does.

### Functions the compiler supplies

123 of the library's functions are `builtin func`: a signature and comment with no body, because the compiler supplies the call. They are the list, dict, set, text, bytes and buffer operations that are methods in Python (`lists.pop`, `dicts.get`, `strings.upper`), the `simd` lane operations, the `parallel.map` family and a few text helpers (`strings.char_count`, `strings.chars`, `lists.stride`).

- A call is the operation however it is spelled: module name, import alias (`import strings as s`), re-export (`export strings.upper`), keyword or explicit type arguments.
- A `strings`, `bytes` or `buffers` operation is also a function value. A `simd` operation or scalar text helper is not (`E_BUILTIN_FUNCTION_VALUE`): call it directly.
- `selka list-interfaces` lists each as `export builtin function`. Declaring one in your own module is `E_BUILTIN_DECLARATION`.

```selka
# doc: expect 42
import strings as s
import simd as v

func apply(f: func(str) -> str, text: str) -> str:
    return f(text)

func main() -> int:
    const lanes = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    if s.upper(text="ab") != "AB" or apply(s.lower, "AB") != "ab" or v.sum(lanes) != 10.0:
        return 1
    return 42
```

### The modules

`--local-stdlib` on `run`, `build`, `check` or `test` prefers a file beside the entry over the embedded copy. Without it, an imported local file with a standard name is ignored: the command warns and names it, so rename the file. A standard-named file given directly as the `check` entry is always checked from its path.

- **Values:** [`lists`](#lists), [`dicts`](#dicts), [`sets`](#sets), [`options`](#options), [`sort`](#sort), [`strings`](#strings), [`bytes`](#bytes), [`buffers`](#buffers), [`byte_builder`](#byte_builder), [`byte_format`](#byte_format), [`math`](#math), [`simd`](#simd), [`parallel`](#parallel).
- **Formats:** [`csv`](#csv), [`http`](#http), [`json`](#json), [`hex`](#hex), [`base64`](#base64), [`path`](#path), [`binary`](#binary), [`flate`](#flate), [`hashes`](#hashes), [`argparse`](#argparse), [`logging`](#logging).
- **Stores:** [`pool`](#pool), [`spans`](#spans), [`symbols`](#symbols), [`memo`](#memo), [`cache_record`](#cache_record), [`persistent_memo`](#persistent_memo), [`durable`](#durable).
- **Capabilities:** [`network`](#network), [`filesystem`](#filesystem), [`environment`](#environment), [`streams`](#streams), [`time`](#time), [`random`](#random), [`process`](#process), [`registers`](#registers), [`cpu`](#cpu), [`buildkit`](#buildkit), [`testing`](#testing).

`time.simulated_clock`, `time.failing_clock`, `random.seeded_entropy`, `random.failing_entropy`, `filesystem.memory`, `environment.fixed`, `network.denied` and `network.memory` build deterministic stand-ins for the capabilities the entry point hands a program. They need no capability and never reach a host resource, so code that takes a `Clock` or `Filesystem` is tested by passing one ([deterministic stand-ins](effects.md#deterministic-stand-ins), [capability parameters in tests](tooling/guest-tests.md#capability-parameters)).

## buffers

`buffers` holds the in-place writes of a `byte_buffer`. Each takes the buffer first with `mut`; `buffers.empty()` creates one.

- `append_byte(mut data, value)`: one octet; `False` unless `value` is in `0..255`.
- `append_range(mut data, piece, start, end)`: a window of a byte string; `False` unless `start <= end <= len(piece)`; a negative bound traps `R_LIST_BOUNDS`.
- `reserve(mut data, extra)`: room for `extra` more octets; `False` for a negative request.
- `append(mut data, piece)` and `append_utf8(mut data, text)`: a byte string's or a text's octets.
- `append_int` and `append_float`: the decimal text of a number (`1.5` is three octets), not a binary encoding.
- `clear(mut data)`: empties the buffer and keeps its storage, so a fill-write-clear loop allocates for the first fill only. Empty a builder's with `buffers.clear(mut builder.buffer)`.

Discard the `False` of the first three with `_ =`; the rest answer nothing. The prelude gives `copy(data)`, `bytes(value)` and `len(data)`.

```selka
# doc: expect 42
import buffers

func main() -> int:
    mut data = buffers.empty()
    _ = buffers.append_byte(mut data, 65)
    buffers.append(mut data, b"BC")
    buffers.append_int(mut data, 1)
    buffers.append_utf8(mut data, "é")
    const text = bytes(data)
    if text != b"ABC1\xc3\xa9":
        return 0
    if len(copy(data)) != len(data):
        return 0
    buffers.clear(mut data)
    if len(data) != 0:
        return 0
    buffers.append(mut data, b"again")
    if bytes(data) != b"again":
        return 0
    return 42
```

## bytes

Byte strings are immutable octets. `bytes` holds their specific operations, each taking the byte string first; writes to a growable buffer are in [`buffers`](#buffers).

- **Search:** `starts_with`, `ends_with`, `count`, `find`, `rfind` (octet offsets, `-1` when absent), `index` and `rindex` (trap `R_SUBSTRING_NOT_FOUND` instead), `find_any(data, octets, start)`. All take optional `start` and `end` bounds over `[start, end)` and still answer offsets from the first octet: an `end` past the length is the length, a negative bound traps `R_TEXT_BOUNDS`. The empty needle counts `len(data) + 1` times.
- **Split, join, trim:** `split`, `join`, `words` (runs of the six ASCII whitespace octets), `replace(data, old, new)` (every non-overlapping occurrence), `strip`, `lstrip`, `rstrip`, and `strip_chars`, `lstrip_chars`, `rstrip_chars` (the octets a set holds).
- **Numbers:** `parse_int` and `parse_float` read the whole data into an option. `parse_int` takes a leading `+`, whitespace and leading zeros ([what it accepts](bytes.md#counting-characters-and-parsing-numbers)). `parse_int_range` and `parse_float_range` read a window without copying. `scalar_count` counts UTF-8 scalars (`Err` for invalid UTF-8); `scalar_count_range` does a window.
- **Fixed-width reads** take `(data, offset)` and trap when the octets are not all inside `data` ([fixed-width reads](bytes.md#fixed-width-reads)): `read_u8`, `read_i8` (inline loads), `read_u16_be`, `read_u16_le`, `read_u32_be`, `read_u32_le`, `read_u64_be`, `read_u64_le`, `read_i16_be`, `read_i16_le`, `read_i32_be`, `read_i32_le`, `read_i64_be`, `read_i64_le`, `read_f32_le`, `read_f64_le`.
- **Other:** `len(data)`, `bytes(values)` from an `int[]` or `byte_buffer`, `to_list(data)`, `fromhex(text)` (even-length hexadecimal).

A `byte_buffer` is accepted where `bytes` is read: the searches, splits, trims and parses above, `strings.decode`, `hex.encode`, `hashes.sha256_bytes` and `hashes.blake3_bytes` borrow its octets with no copy, as the buffer's own method (`bytes.find(buf, x)` is `buf.find(x)`), so a trimmed or split buffer answers a buffer. `bytes.replace` and the fixed-width reads take only `bytes` (`E_TYPE`): read a word with `bytes(buf[i:i + 8])` ([a buffer does not take these reads](bytes.md#a-byte_buffer-does-not-take-these-reads)).

```selka
# doc: expect 3
# doc: expect 1
# doc: expect [b'a', b'b']
# doc: expect b'a'
# doc: expect Some(12)
# doc: expect True
import buffers
import bytes

func main(out: Stream) -> int:
    print(out, bytes.find(b"abcabc", b"a", 1))
    print(out, bytes.rindex(b"abab", b"b", 0, 3))
    print(out, bytes.words(b" a\tb "))
    print(out, bytes.strip_chars(b"xax", b"x"))
    print(out, bytes.parse_int(b"12"))
    mut buf = buffers.empty()
    buffers.append(mut buf, b"a,b")
    print(out, bytes.find(buf, b",") == 1 and bytes.find_any(buf, b",", 0) == 1)
    return 0
```

## byte_builder

```text
# doc: not-selka
record Builder: ...
create() -> Builder
append(mut builder: Builder, data: bytes) -> Unit
append_range(mut builder: Builder, data: bytes, start: int, end: int) -> bool
append_array(mut builder: Builder, array: FixedArray[u8, N], count: int) -> bool
append_array_range(mut builder: Builder, array: FixedArray[u8, N], start: int, end: int) -> bool
append_text(mut builder: Builder, text: str) -> Unit
append_int(mut builder: Builder, value: int) -> Unit
append_byte(mut builder: Builder, value: int) -> bool
append_float(mut builder: Builder, value: float) -> bool
append_spaces(mut builder: Builder, count: int) -> bool
reserve(mut builder: Builder, extra: int) -> bool
finish(builder: Builder) -> bytes
repeat(data: bytes, count: int) -> bytes
```

`byte_builder` assembles an immutable byte string in one growing `byte_buffer` ([in-place octet methods](bytes.md#writing-octets-in-place)); no append allocates a value of its own.

- `finish` copies the octets into an independent `bytes`. The builder stays usable and later appends never change earlier snapshots. To send the octets to a stream without the copy, `write(out, builder.buffer)`.
- `len(builder.buffer)` is the octet count; `len(builder)` is `E_TYPE`, since a `Builder` is a record, not a sequence.
- The checked appends answer `False` and change nothing for an invalid request: `append_byte` outside `0..255`, `append_spaces` or `reserve` below 0, `append_range` with `end` below `start` or past `len(data)`. A no-op success (`reserve(0)`, an empty range) answers `True`. A constant negative `append_range` endpoint is `E_NEGATIVE_INDEX_REMOVED`; a computed one traps `R_LIST_BOUNDS`.
- `append_array` and `append_array_range` copy octets out of a fixed `u8` array of any length in one step, as a `network.Read[N]` chunk reaches a builder: `byte_builder.append_array(mut raw, chunk.bytes, int(chunk.length))`. They refuse and trap as `append_range` does.
- `append_float` writes the spelling `str(value)` prints.

```selka
# doc: expect 5
import byte_builder

func main(out: Stream) -> int:
    mut builder = byte_builder.create()
    byte_builder.append_text(mut builder, "abc")
    byte_builder.append_int(mut builder, 42)
    print(out, len(builder.buffer))
    return 0
```

## byte_format

```text
# doc: not-selka
shortest(mut builder: byte_builder.Builder, value: float) -> Unit
decimal(mut builder: byte_builder.Builder, value: float, decimals: int) -> bool
format(mut builder: byte_builder.Builder, template: bytes, numbers: float[]) -> Unit
format1(mut builder: byte_builder.Builder, template: bytes, numbers: float[], a: bytes) -> Unit
format2(mut builder: byte_builder.Builder, template: bytes, numbers: float[], a: bytes, b: bytes) -> Unit
format3(mut builder: byte_builder.Builder, template: bytes, numbers: float[], a: bytes, b: bytes, c: bytes) -> Unit
```

Output that Zig writes with `w.print("<rect x=\"{d:.1}\"/>", .{ x })` is one call here, onto a [`byte_builder`](#byte_builder).

- `shortest(mut builder, x)` is Zig's `{d}`: the shortest round-trip digits, never scientific, no `.0` after a whole number (`100.0` is `100`; `byte_builder.append_float` keeps the `.0`).
- `decimal(mut builder, x, decimals)` is Zig's `{d:.N}`: the shortest digits rounded half up, so `6.475` at two decimals is `6.48` (`strings.format_float` and an f-string print `6.47`). It answers `False` and appends nothing outside 0 to 17 decimals.
- `format(mut builder, template, numbers)` fills a template: `{d}` is `shortest`, `{d:.N}` is `decimal`, `{{` and `}}` write a brace. An integer travels as `float(n)` and prints whole up to 2^53.
- `format1`, `format2` and `format3` add one to three texts for `{s}`, written as they are with no copy; they are borrowed `bytes` arguments, not list elements.
- A template that does not fit its arguments (unknown placeholder, unclosed or lone brace, too few or too many arguments) traps `R_ASSERT` naming the octet and reason.

```selka
# doc: expect b'<rect x="1.3" y="2" width="30.46" label="U&1"/>'
# doc: expect b'100 -0 0.1'
import byte_builder
import byte_format

func rect(x: float, y: float, width: float, label: bytes) -> bytes:
    mut out = byte_builder.create()
    byte_format.format1(mut out, b'<rect x="{d:.1}" y="{d}" width="{d:.2}" label="{s}"/>', [x, y, width], label)
    return byte_builder.finish(out)

func main(out: Stream) -> int:
    print(out, rect(1.25, 2.0, 30.456, b"U&1"))
    mut numbers = byte_builder.create()
    byte_format.format(mut numbers, b"{d} {d} {d}", [100.0, -0.0, 0.1])
    print(out, byte_builder.finish(numbers))
    return 0
```

## simd

```text
# doc: not-selka
splat(value: float) -> Simd[float, 4]            load(values: float[], index: int) -> Simd[float, 4]
store(mut values: float[], index: int, value: Simd[float, 4])
select(mask: Simd[bool, 4], a: Simd[float, 4], b: Simd[float, 4]) -> Simd[float, 4]
sum(value: Simd[float, 4]) -> float              min(value: Simd[float, 4]) -> float
max(value: Simd[float, 4]) -> float              fma(a: Simd[float, 4], b: Simd[float, 4], c: Simd[float, 4]) -> Simd[float, 4]
sqrt(value: Simd[float, 4]) -> Simd[float, 4]
```

The signatures show the float four-lane form; the compiler checks each call against the `Simd` type its operands and context give (float or f32, 2, 4, 8 or 16 lanes). `splat` and `load` take their lane count from the expected type. See [SIMD](simd.md).

```selka
# doc: expect 42
import simd

func main() -> int:
    const v: Simd[float, 4] = simd.splat(2.0)
    if simd.sum(v) != 8.0 or simd.max(simd.fma(v, v, v)) != 6.0:
        return 1
    return 42
```

## math

```text
# doc: not-selka
# Bare names: no import and no `math.` prefix (`math.floor(x)` is E_REMOVED_SPELLING)
sqrt(value: float) -> float          trunc(value: float) -> float
floor(value: float) -> float         ceil(value: float) -> float
round(value: float, ndigits: int = 0) -> float
min(a: T, b: T) -> T                 max(a: T, b: T) -> T
abs(value: T) -> T

# Functions of the math module: write math.NAME(...)
pi() -> float                        e() -> float
nan() -> float                       infinity() -> float
is_nan(value: float) -> bool         is_inf(value: float) -> bool
is_finite(value: float) -> bool      fabs(value: float) -> float
sign(value: float) -> int
sin(value: float) -> float           cos(value: float) -> float
pow(base: float, exponent: int) -> float
fmin(a: float, b: float) -> float    fmax(a: float, b: float) -> float
clamp[T: integer](value: T, low: T, high: T) -> T
isqrt(value: int) -> Result[int, str]
gcd(a: int, b: int) -> Result[int, str]
lcm(a: int, b: int) -> Result[int, str]
bits(value: float) -> u64            from_bits(pattern: u64) -> float
f32_bits(value: f32) -> u32          f32_from_bits(pattern: u32) -> f32
fma(a: float, b: float, c: float) -> float   f32_fma(a: f32, b: f32, c: f32) -> f32
hypot(x: float, y: float) -> float   f32_hypot(x: f32, y: f32) -> f32
log10(x: float) -> float             f32_log10(x: f32) -> f32
exp(x: float) -> float               f32_exp(x: f32) -> f32
atan2(y: float, x: float) -> float   f32_atan2(y: f32, x: f32) -> f32
pow_float(x: float, y: float) -> float   f32_pow_float(x: f32, y: f32) -> f32
ln(x: float) -> float                atan(x: float) -> float
acos(x: float) -> float              asin(x: float) -> float
tan(x: float) -> float               expm1(x: float) -> float
sinh(x: float) -> float              cosh(x: float) -> float
tanh(x: float) -> float              cbrt(x: float) -> float
to_int(value: float) -> int?         to_int_saturating(value: float) -> int
```

The first group (`sqrt`, `trunc`, `floor`, `ceil`, `round`, `min`, `max`, `abs`) is bare prelude names: `math.floor(x)` and the other `math.` spellings of it are `E_REMOVED_SPELLING`, which `selka fix` rewrites. The rest needs `import math` and the `math.` prefix. All of it is pure and needs no capability.

- `pi` and `e` are functions: `math.pi()`.
- `bits`, `f32_bits` answer the IEEE bit pattern (every NaN as the canonical quiet NaN); `from_bits`, `f32_from_bits` build the value ([bit patterns](floating-point.md#bit-patterns)).
- `fma`, `f32_fma` round `a * b + c` once; `hypot`, `f32_hypot` answer Zig's bits ([fused multiply-add and hypot](floating-point.md#fused-multiply-add-and-hypot)).
- `log10`, `exp`, `atan2`, `pow_float` (float exponent; `pow` takes an integer one) and their `f32_` forms, and `ln`, `atan`, `acos`, `asin`, `tan`, `expm1`, `sinh`, `cosh`, `tanh`, `cbrt`, `sin`, `cos`, answer Zig's bits, so a ported program prints the same bytes ([Zig-exact functions](floating-point.md#zig-exact-log10-exp-atan2-and-pow_float), [ln, trigonometry and hyperbolics](floating-point.md#zig-exact-ln-atan-acos-asin-tan-expm1-sinh-cosh-tanh-cbrt-sin-and-cos)). Angles are radians; an infinite angle or NaN gives NaN.
- `pow` takes an integer exponent; a magnitude above 4096 saturates to a same-parity magnitude, keeping the sign and the overflow or underflow outcome.
- `gcd`, `lcm`, `isqrt` return a `Result` (`-9223372036854775808` has no positive counterpart; an lcm can leave the signed range). The bare `abs` traps `R_OVERFLOW` on that value.

```selka
# doc: expect 42
import math
import strings

func main() -> int:
    if sqrt(1764.0) != 42.0:
        return 1
    if floor(0.0 - 1.5) != 0.0 - 2.0 or ceil(0.0 - 1.5) != 0.0 - 1.0:
        return 2
    if math.pow(2.0, 10) != 1024.0 or math.clamp(99, 0, 42) != 42:
        return 3
    match math.gcd(0 - 12, 18):
        case Ok(divisor):
            return int(sqrt(49.0)) * divisor
        case Err(message):
            return 0 - strings.char_count(message)
```

`int(value)` of a float that does not fit traps `R_FLOAT_CONVERSION` ([integer conversions](floating-point.md#integer-conversions)). Two functions convert without the trap:

- `to_int(value)` answers `Some(int(value))`, or `None` for NaN, an infinity, or a value from 2^63 up or below -2^63.
- `to_int_saturating(value)` always answers an integer: 9223372036854775807 from 2^63 up and for +infinity, -9223372036854775808 below -2^63 and for -infinity, `0` for NaN, `int(value)` otherwise.

```selka
# doc: expect 9223372036854775807 -9223372036854775808 0 None Some(41)
import math

func main(out: Stream) -> int:
    print(out, math.to_int_saturating(1e30), math.to_int_saturating(0.0 - 1e30), math.to_int_saturating(math.nan()), math.to_int(1e30), math.to_int(41.9))
    return 0
```

## lists

`lists` holds the Python list methods as functions. Writes take the list first with `mut`.

- `filled(count, value)`: `count` independent copies, empty when `count <= 0`.
- `contains(values, value)`; `last(values)`: the last element or `None`.
- `index_of(values, value)`, `remove(mut values, value)`: position of / removal of the first equal element; trap when none is equal.
- `exchange(mut values, index, own replacement)`: replaces an element and answers the former value, for any integer index type and any element (a resource or `Result` too). Nothing is copied: give a named value with `own` (a fresh value or `copy(value)` takes no marker).
- `extend(mut values, other)` copies another list's elements to the end; `extend_own(mut values, own other)` moves them, copying none and freeing the emptied `other`.
- `insert(mut values, index, value)` clamps an index past the end to the length. `pop(mut values)` and `pop_at(mut values, index)` remove and answer one element. `clear(mut values)` removes all. `reverse(mut values)` reverses in place.

The prelude supplies `copy(values)` (independent storage, managed children copied too), `sort(mut values)` and `reversed(values)`.

```selka
# doc: expect 42
import lists

func main() -> int:
    const values = lists.filled(3, 14)
    if lists.contains(values, 14) and lists.last(values) == Some(14):
        return 42
    return 0
```

## dicts

`dicts` holds the dictionary probes `dict` lacks, and the Python methods as functions.

- `find(mapping, key)`: the stored value or `None`; a managed value comes back as an independent copy.
- `get(mapping, key, fallback)`: the stored value or `fallback`; the result may borrow either input.
- `setdefault(mut mapping, key, fallback)`: the stored value, or stores `fallback` and answers it; the result borrows the stored entry.
- `add(mut mapping, key, delta)`: adds an integer to the entry, starting from zero.
- `append_to(mut mapping, key, own item)`: appends to the list under `key`, starting one with `item`; a named binding is given away, a borrowed name is copied.
- `update(mut mapping, other)`: copies every entry in, replacing keys it holds.
- `pop(mut mapping, key)`: removes the entry and answers its value; traps when absent. `pop_default(mut mapping, key, fallback)` answers `fallback` instead. `clear(mut mapping)` removes all.
- `keys`, `values`, `items` are ephemeral views: use one in a direct loop or an immediate `len`, `in`, `list`, `set` or `sorted`; `list(dicts.values(mapping))` is an independent snapshot.

`add`, `append_to` and `setdefault` copy the `key` only when the mapping has no entry for it, so a call that finds its key allocates nothing.

```selka
# doc: expect 42
import dicts

func main() -> int:
    mut counts: dict[str, int] = {}
    dicts.add(mut counts, "a", 40)
    dicts.add(mut counts, "a", 1)
    dicts.add(mut counts, "b", 7)
    mut groups: dict[str, int[]] = {}
    dicts.append_to(mut groups, "x", 3)
    dicts.append_to(mut groups, "x", 4)
    match dicts.find(counts, "a"):
        case Some(value):
            if value == 41 and dicts.find(counts, "z") is None and len(groups["x"]) == 2:
                return value + groups["x"][1] - 3
        case None:
            return 0
    return 0
```

## options

```text
# doc: not-selka
take_or[T](own value: T?, own default: T) -> T
```

`value.unwrap_or(default)` borrows both, so keeping the result needs `copy(...)`, except for a call's result that lends nothing with a default of its own: `maybe().unwrap_or("")` is owned ([R6](ownership-rules.md#r6--borrowed-selections)). `take_or` consumes both (`match own`): the payload of an owned option, or the owned default when `None`, is the result with no copy. Pass an option of scalars without `own`.

```selka
# doc: expect 4 7
import options


record Decl:
    name: str
    pins: int[]


func main(out: Stream) -> int:
    const found: Decl? = Some(Decl(name="ab", pins=[1, 2]))
    const kept = options.take_or(own found, Decl(name="", pins=[]))
    const missing: int? = None
    print(out, len(kept.name) + len(kept.pins), options.take_or(missing, 7))
    return 0
```

## strings

```text
# doc: not-selka
digits() -> str                      letters() -> str
whitespace() -> str
union Error:
    Invalid: str, Overflow: str
message(error: Error) -> str
record Builder:
    buffer: byte_buffer
builder() -> Builder
append(mut builder: Builder, text: str) -> Unit
finish(builder: Builder) -> str
join(parts: str[], separator: str) -> str
is_digit(text: str) -> bool          is_alpha(text: str) -> bool
is_alnum(text: str) -> bool          is_space(text: str) -> bool
starts_with(text: str, prefix: str, start: int = 0, end: int = MAX) -> bool
starts_with_at(text: str, prefix: str, at: int) -> bool
cut_octets(text: str, limit: int) -> str from text
ends_with(text: str, suffix: str, start: int = 0, end: int = MAX) -> bool
find(text: str, needle: str, start: int = 0, end: int = MAX) -> int?
count(text: str, needle: str, start: int = 0, end: int = MAX) -> int
strip(text: str) -> str from text
lstrip(text: str) -> str from text
rstrip(text: str) -> str from text
strip_chars(text: str, characters: str) -> str
lstrip_chars(text: str, characters: str) -> str
rstrip_chars(text: str, characters: str) -> str
zfill(text: str, width: int) -> str
lines(text: str) -> str[]
words(text: str) -> str[]
upper(text: str) -> str              lower(text: str) -> str
repeat(text: str, times: int) -> str
pad_left(text: str, width: int, fill: str) -> Result[str, Error]
pad_right(text: str, width: int, fill: str) -> Result[str, Error]
substitute(text: str, needle: str, insertion: str) -> Result[str, Error]
to_int(text: str) -> int?     to_float(text: str) -> float?
format_int(value: int, base: int) -> Result[str, Error]
format_float(value: float, decimals: int) -> Result[str, Error]
format_decimal(value: float, decimals: int) -> Result[str, Error]
format_shortest(value: float) -> str
ord(text: str) -> Result[int, Error]
chr(code: int) -> Result[str, Error]
encode(text: str) -> bytes
decode(data: bytes) -> Result[str, str]
find_any(text: str, needles: str[]) -> int?
split(text: str, separator: str) -> str[]
replace(text: str, needle: str, insertion: str) -> str
rfind(text: str, needle: str, start: int = 0, end: int = MAX) -> int?
text_index(text: str, needle: str, start: int = 0, end: int = MAX) -> int
text_rindex(text: str, needle: str, start: int = 0, end: int = MAX) -> int
```

`str` provides `+`, `==`, `in`, indexing, slicing and iteration; its other operations are these functions. `MAX` above is 9223372036854775807.

- **Bounds:** searches read `[start, end)` and answer offsets from the start of the text. An `end` at or past the length reads to the end; a negative bound traps `R_TEXT_BOUNDS`; one inside a multi-byte character traps `R_TEXT_BOUNDARY`. `count` of the empty needle is `len(text) + 1`.
- **Positions:** `find`, `rfind`, `find_any` answer byte offsets in an `int?`; `char_find`, `char_rfind`, `char_index` are the scalar readings. `text_index` and `text_rindex` answer the same offsets and trap `R_SUBSTRING_NOT_FOUND`.
- **Python habit → Selka:** `s.split()` is `strings.words(s)` (runs of the six ASCII whitespace octets, no empty piece); `sep.join(parts)` is `strings.join(parts, sep)`; `replace` is a reserved word, so the checked form is `substitute`. `split` keeps every piece, and `replace` replaces every occurrence and traps on an empty needle.
- **Trim:** `strip`, `lstrip`, `rstrip` return views without copying (bind with `const`; `copy(...)` for independent storage). `strip_chars`, `lstrip_chars`, `rstrip_chars` trim the octets of `characters` and answer a new text. `zfill(text, width)` pads with `0` after a sign.
- **Other:** `repeat` is empty for a count below 1. `upper` and `lower` map ASCII only. `encode` cannot fail; `decode` answers `Err("invalid UTF-8 in byte string")`. `ord` and `chr` convert a one-character text and a scalar value; any other length is rejected, and `chr` rejects surrogates and values past `0x10FFFF`.
- **Errors:** fallible builders return `Error`: `Invalid` (argument outside the accepted range) or `Overflow` (does not fit the rendering); `message(error)` gives the reason.
- **`strings.Builder`** is the text counterpart of `byte_builder`: `append` writes a borrowed piece, `finish` copies the text once into an independent `str` (infallible, valid UTF-8) and the builder stays usable. `strings.builder()` returns one; `mut field = strings.builder()` infers the type.

```selka
# doc: expect 42
import strings

func main() -> int:
    mut field = strings.builder()
    strings.append(mut field, "a")
    strings.append(mut field, "λ")
    mut first = strings.finish(field)
    strings.append(mut field, "b")
    if first != "aλ" or strings.finish(field) != "aλb":
        return 1
    return 42
```

- `to_int` rejects anything the signed range cannot hold, `9223372036854775808` included. `to_float` is `parse_float(text)`: surrounding ASCII whitespace, single underscores between digits, `inf`, `infinity` and `nan` are accepted.
- `format_float(x, n)` rounds the exact binary value, as C and Python do: `format_float(2.675, 2)` is `"2.67"`. An exact tie rounds away from zero (`format_float(0.125, 2)` is `"0.13"`, Python prints `0.12`); a result that rounds to zero loses its sign (`"0.00"`); a value too large for fixed decimals is rejected. It agrees with `round(x, n)`. An [f-string](text.md#format-specifications) `f"{x:.2f}"` rounds an exact tie to even (`"0.12"`) and keeps a negative zero's sign (`"-0.00"`).
- `format_decimal(x, n)` is Zig's `{d:.N}`: it rounds the shortest round-trip digits half up, so `6.475` rounds up, and keeps the sign of a zero result. It takes 0 to 17 decimals. Use it to match Zig or JavaScript, `format_float` to match Python and C.
- `format_shortest(value)` is Python's `repr` rule: `str(value)` from 1e-4 up to but not including 1e16 (`"0.0001"`, `"100000.0"`), else the shortest digits with `e`, a sign and two or more exponent digits (`"1e+16"`, `"1.5e-05"`). Negative zero is `"-0.0"`; `"inf"`, `"-inf"`, `"nan"` as `str`. It reads back to the same bits. Go writes an exponent from 1e6 up and `jq` prints `15000000000000000` where this prints `"1.5e+16"`; to match either, lay out the digits yourself.

```selka
# doc: expect 6.47 6.48 -0.00 10.00
import strings

func shown(result: Result[str, strings.Error]) -> str:
    match result:
        case Ok(text):
            return copy(text)
        case Err(error):
            return strings.message(error)

func main(out: Stream) -> int:
    print(out, shown(strings.format_float(6.475, 2)), shown(strings.format_decimal(6.475, 2)), shown(strings.format_decimal(-0.001, 2)), shown(strings.format_decimal(9.995, 2)))
    return 0
```

```selka
# doc: expect 1e+300 5e-324 1e-05 0.0001 1.5e+16 9999999999999998.0 -0.0
import strings

func main(out: Stream) -> int:
    print(out, strings.format_shortest(1e300), strings.format_shortest(5e-324), strings.format_shortest(0.00001), strings.format_shortest(0.0001), strings.format_shortest(1.5e16), strings.format_shortest(9999999999999998.0), strings.format_shortest(-0.0))
    return 0
```

### A prefix at an octet offset

`text[at:]` and `text.startswith(prefix, at)` trap `R_TEXT_BOUNDARY` when `at` is inside a multi-byte scalar. `strings.starts_with_at(text, prefix, at)` asks without slicing: `False` inside a scalar and past the end, only the empty prefix matches at the end, a negative offset traps `R_TEXT_BOUNDS`. Use it for an offset you did not find yourself (every octet a scanner walks); `strings.starts_with(text, prefix, start=at)` is for an offset known to be at a character and traps `R_TEXT_BOUNDARY` otherwise. On `bytes`: `bytes.starts_with(data[at:], prefix)`.

```selka
# doc: expect 2 False
import strings

func comments(text: str) -> int:
    mut count = 0
    mut at = 0
    while at < len(text):
        if strings.starts_with_at(text, "<!--", at):
            count += 1
        at += 1
    return count

func main(out: Stream) -> int:
    print(out, comments("a \u2014 b <!-- c --> <!-- d -->"), strings.starts_with_at("\u2014", "", 1))
    return 0
```

### A text cut at a width

`text[0:width]` counts octets and traps `R_TEXT_BOUNDARY` inside a multi-byte scalar, which ASCII tests never show. `strings.cut_octets(text, limit)` is the longest prefix of at most `limit` octets that ends where a character ends: a view (`copy(...)` makes it independent). A limit inside a character backs off to its start; below the first character's width or negative gives `""`; at or past the length gives the whole text. `strings.char_slice(text, 0, count)` cuts at a count of scalars. `selka lint` reports a `str` slice with a literal, constant or other-bound-plus-literal bound (`L_TEXT_SLICE_OCTETS`).

```selka
# doc: expect abcdef… abcdefg…
import strings

func short(text: str, width: int) -> str:
    if len(text) > width:
        return copy(strings.cut_octets(text, width - 1)) + "\u2026"
    return copy(text)

func main(out: Stream) -> int:
    print(out, short("abcdef\u00e9hij", 8), short("abcdefghij", 8))
    return 0
```

### Joining text

`strings.join(parts, separator)` is Python's `separator.join(parts)`: empty text for an empty list, no separator before the first or after the last part. `str(list)` is the list as `print` shows it, brackets and quotes included; a list of numbers joins the `str` of each element. `bytes.join` is the same for `bytes[]`.

```selka
# doc: expect positions 3, 1, 2
import strings

func main(out: Stream) -> int:
    const order = [3, 1, 2]
    mut parts: str[] = []
    for position in order:
        append(mut parts, str(position))
    print(out, "positions " + strings.join(parts, ", "))
    return 0
```

## sets

`sets` holds the fourteen operations on `set[T]`, generic over an `equality` element type (also what a `set[T]` key requires).

- `add(mut values, own value)` takes the value; `include(mut values, value)` borrows it and copies only when the set lacks it. `discard(mut values, value)` removes if present; `remove` traps `R_MISSING_KEY` when absent.
- `pop(mut values)` removes and answers one element; `clear(mut values)` empties the set.
- `update(mut values, other)` adds every element of a set or a list of the element type; any other source is refused (the method `values.update("abc")` adds three letters, `sets.update` takes no text).
- `union`, `intersection`, `difference`, `symmetric_difference` answer a new set; `subset`, `superset`, `disjoint` answer a fact about two sets.

```selka
# doc: expect 42
import sets

func main() -> int:
    mut values: set[int] = set()
    sets.add(mut values, 3)
    sets.add(mut values, 4)
    sets.include(mut values, 4)
    const other = set([4, 9])
    if sets.union(values, other) != set([3, 4, 9]):
        return 0
    if sets.intersection(values, other) != set([4]):
        return 0
    if not sets.subset(set([4]), values) or not sets.disjoint(values, set([7])):
        return 0
    sets.discard(mut values, 3)
    if values != set([4]):
        return 0
    return 42
```

## sort

```text
# doc: not-selka
compare_strs(a: str, b: str) -> int
sort_ints(values: int[]) -> int[]
sort_floats(values: float[]) -> float[]
sort_strs(values: str[]) -> str[]
sort_by_key[T: copy + storable](values: T[], key: func(T) -> int) -> T[]
sort_by_compare[T: copy + storable](mut values: T[], compare: func(T, T) -> int)
sort_by_compare_with[T: copy + storable, C: copy + storable](mut values: T[], compare: func(T, T, C) -> int, context: C)
is_sorted_ints(values: int[]) -> bool
binary_search(values: int[], target: int) -> int?
min_int(values: int[]) -> int?
max_int(values: int[]) -> int?
min_str(values: str[]) -> str?
unique_ints(values: int[]) -> int[]
unique_strs(values: str[]) -> str[]
```

`import sort` makes `sort` this module's name in the file, so a later builtin `sort(mut values)` is refused ("`sort` here names the imported module, which hides the builtin"). Write `sort.sort_ints(values)` or drop the import; `selka fix` deletes an `import sort` nothing else uses.

- `sort_ints`, `sort_floats`, `sort_strs` return a new list and leave the input alone, with the stable sort of `sorted` and `values.sort()`: NaN follows every ordered float, equal values and signed zeros keep input order, text compares Unicode scalar values. An ordered or reversed list sorts in linear time.
- A generic sort needs an integer key function or a comparison function: the language has no ordering contract, and `copy`, `equality`, `integer`, `codec` and `storable` are the only generic requirements.
- `sort_by_key(values, key)` is `sorted(values, key=key)`: each key computed once, in list order; a key function that traps on several elements reports the first ([keyed sorting](python-syntax.md#keyed-sorting)).
- `sort_by_compare(mut values, compare)` sorts in place by a comparison for an order no single key gives. `compare` is a top-level function of two elements returning an `int`: negative when the first goes first, zero when neither, positive when the second goes first (as `compare_strs` and `time.compare` answer). The sort is stable, elements are lent not copied, and `T` needs `copy` (no resource or result elements).
- `sort_by_compare_with(mut values, compare, context)` calls `compare(first, second, context)`; with no closures, `context` is one read-only `copy + storable` value, usually a record, the same on every call. A comparison that is not an order still ends and does not trap; the result order is unspecified.
- For one `int`, `float` or `str` key, `sort(mut values, key=f)` is faster than a comparison.

```selka
# doc: expect 42
import sort

record Entry:
    name: str
    score: int

func by_score(entry: Entry) -> int:
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

The first example orders values of several types as jq does (`null`, booleans, numbers, texts); the second sorts rows by a text key, then by an age that falls when its context says so.

```selka
# doc: expect null false true 3 12 "a" "b"
import sort
import strings

enum Value:
    nothing
    flag(on: bool)
    number(n: int)
    text(s: str)

func rank(value: Value) -> int:
    match value:
        case nothing:
            return 0
        case flag(on):
            if on:
                return 2
            return 1
        case number(n=_):
            return 3
        case text(s=_):
            return 4

func compare(first: Value, second: Value) -> int:
    if rank(first) != rank(second):
        return rank(first) - rank(second)
    match first:
        case number(n=left):
            match second:
                case number(n=right):
                    return left - right
                case _:
                    return 0
        case text(s=left):
            match second:
                case text(s=right):
                    return sort.compare_strs(left, right)
                case _:
                    return 0
        case _:
            return 0

func show(value: Value) -> str:
    match value:
        case nothing:
            return "null"
        case flag(on):
            if on:
                return "true"
            return "false"
        case number(n):
            return f"{n}"
        case text(s):
            return f'"{s}"'

func main(out: Stream) -> int:
    mut values = [Value.text(s="b"), Value.number(n=12), Value.flag(on=True), Value.nothing, Value.text(s="a"), Value.number(n=3), Value.flag(on=False)]
    sort.sort_by_compare(mut values, compare)
    mut shown: str[] = []
    for value in values:
        append(mut shown, show(value))
    print(out, strings.join(shown, " "))
    return 0
```

```selka
# doc: expect Ada:41 Ada:30 Bo:52 Bo:19
import sort
import strings

record Person:
    name: str
    age: int

# What the comparison reads besides the two people: whether the age key falls.
record Order:
    age_falls: bool

func by_name_then_age(first: Person, second: Person, order: Order) -> int:
    const by_name = sort.compare_strs(first.name, second.name)
    if by_name != 0:
        return by_name
    if order.age_falls:
        return second.age - first.age
    return first.age - second.age

func main(out: Stream) -> int:
    mut people = [Person(name="Bo", age=19), Person(name="Ada", age=30), Person(name="Bo", age=52), Person(name="Ada", age=41)]
    sort.sort_by_compare_with(mut people, by_name_then_age, Order(age_falls=True))
    mut shown: str[] = []
    for person in people:
        append(mut shown, f"{person.name}:{person.age}")
    print(out, strings.join(shown, " "))
    return 0
```

## parallel

```text
# doc: not-selka
map[T: copy + storable, R: copy + storable](values: T[], function: func(T) -> R) -> R[]
map_fallible[T: copy + storable, R: copy + storable, E: copy + storable](values: T[], function: func(T) -> Result[R, E]) -> R[] fails E
map_results[T: storable, R: storable](values: T[], function: func(T) -> R) -> R[]
threads() -> int
cpus() -> int
```

`map` applies a function to every element and returns a new list in input order; the input stays available. Checked ownership lends distinct elements to scoped workers and joins them before returning ([scoped parallel work](managed-memory.md#explicit-values-and-scoped-parallel-work)).

- The callback takes one read-only input and returns a storable value. Returning managed input data needs `copy(value)`. There are no closure captures, detached tasks or escaping handles, and `Unit` elements are unsupported. A small callback may not speed up.
- **Trailing arguments:** `parallel.map(values, callback, a, b)` calls `callback(item, a, b)` with one to five read-only arguments, lent and the same for every item. A list, text or bytes in a plain parameter is `E_SLICE_ESCAPES` (wrap in `copy(...)` or declare the parameter `own`); a `mut` argument is `E_TASK_MUT`; an `own` marker on an argument, or a fallible callback, is `E_PARALLEL_MAP_ARGS` ([Limits](concurrency.md#limits), [ownership rules](ownership-rules.md)).
- **Fallible callback** (`-> R fails E`): `try parallel.map(values, callback)` gives `R[] fails E`. Every item runs; the failure returned has the lowest input index. A bare `parallel.map` of a fallible callback is `E_PARALLEL_MAP_FALLIBLE`; its fix renames the call to `parallel.map_results`, the `Result[R, E][]` list, one per input. A fallible map needs `T: copy`.
- `threads()` is the pool size, at least 1: `--threads N` or `SELKA_THREADS=N`, else one per CPU the process may use. The pool starts once and its size cannot change; under `selka test` it is 1. `cpus()` is the CPUs the process may use (at least 1), whatever `--threads` says. Neither takes a capability ([the pool's size](concurrency.md#the-pools-size)).

```selka
# doc: expect 30 -4
import parallel

func scale_by(value: int, factor: int) -> int:
    return value * factor

func shift(value: int, bias: int, flip: bool) -> int:
    if flip:
        return value - bias
    return value + bias

func main(out: Stream) -> int:
    const doubled = parallel.map([1, 2, 3], scale_by, 10)
    const moved = parallel.map([1, 2, 3], shift, 5, True)
    print(out, doubled[2], moved[0])
    return 0
```

```selka
# doc: expect ok-0 ok-2
# doc: expect bad-1
import parallel

func attempt(value: int) -> str fails str:
    if value % 2 == 0:
        return "ok-" + str(value)
    fail "bad-" + str(value)

func attempt_all(values: int[]) -> str[] fails str:
    return try parallel.map(values, attempt)

func main(out: Stream) -> int:
    match attempt_all([0, 2]):
        case Ok(texts):
            print(out, texts[0], texts[1])
        case Err(text):
            print(out, text)
    match attempt_all([0, 1, 3]):
        case Ok(texts):
            print(out, len(texts))
        case Err(text):
            print(out, text)
    return 0
```

```selka
# doc: expect True True
import parallel

func main(out: Stream) -> int:
    print(out, parallel.threads() >= 1, parallel.cpus() >= 1)
    return 0
```

## path

```text
# doc: not-selka
record Split:
    root: str
    extension: str

separator() -> str                   is_absolute(value: str) -> bool
join(left: str, right: str) -> str   join_all(parts: str[]) -> str
basename(value: str) -> str from value
dirname(value: str) -> str from value
splitext(value: str) -> Split        stem(value: str) -> str
extension(value: str) -> str         components(value: str) -> str[]
normalize(value: str) -> str         relative(base: str, target: str) -> str
```

`basename` and `dirname` return views of the input. `relative(base, target)` is `target` as a path from the folder `base`, both normalized: `relative("/a/b", "/a/b/c.selka")` is `c.selka`, `relative("/a/b", "/a/x")` is `../x`, a path from itself is `.`; when exactly one is absolute, `target` comes back normalized and whole. These read and build text only: no file, no symbolic link, no capability.

```selka
# doc: expect 42
import path
import strings

func main() -> int:
    mut full = path.join("/usr/local", "lib/selka/../answer.txt")
    if path.normalize(full) != "/usr/local/lib/answer.txt":
        return 1
    if path.extension(full) != ".txt" or path.stem(full) != "answer":
        return 2
    if path.basename("/a/b/") != "" or path.dirname("/a") != "/":
        return 3
    if path.relative("/usr/local/lib", "/usr/share/doc") != "../../share/doc":
        return 4
    return strings.char_count(path.normalize(full)) + 17
```

## hex

```text
# doc: not-selka
encode(data: bytes) -> str           encode_upper(data: bytes) -> str
decode(text: str) -> Result[bytes, str]
is_hex(text: str) -> bool
```

`hex.encode(data)` is `data.hex()` (it also takes a `byte_buffer`); this module adds the uppercase rendering and a predicate.

```selka
# doc: expect 42
import hex
import strings

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
            return 0 - strings.char_count(message)
```

## base64

```text
# doc: not-selka
standard_alphabet() -> bytes         urlsafe_alphabet() -> bytes
b64encode(data: bytes) -> bytes
b64decode(data: bytes) -> Result[bytes, str]
urlsafe_b64encode(data: bytes) -> bytes
urlsafe_b64decode(data: bytes) -> Result[bytes, str]
```

Encoding always emits canonical padding. Decoding rejects a length that is not a multiple of four, a symbol outside the alphabet, padding anywhere but the end of the final group, and a final group with nonzero unused bits, so exactly one encoding decodes.

```selka
# doc: expect 42
import base64
import hex
import strings

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
            return 0 - strings.char_count(message)

func refused() -> int:
    match base64.b64decode(b"Zh=="):
        case Ok(_):
            return 1
        case Err(_):
            return 0
```

## csv

`csv` parses RFC 4180 text into rows and renders rows back. It is pure and opens no file: read with `fs.read_text(path)`, write with `fs.write_text(path, csv.write(rows))`. There are no dialect options, type conversion or streaming.

```text
# doc: not-selka
enum Error:
    UnterminatedQuote(value: str)
    UnexpectedQuote(value: str)
    UnexpectedCharacter(value: str)
message(error: Error) -> str
record Table:
    header: str[]
    rows: str[][]
record Field:
    text: str
    quoted: bool
parse(text: str) -> Result[str[][], Error]
parse_fields(text: str) -> Result[Field[][], Error]
parse_table(text: str) -> Result[Table, Error]
write(rows: str[][]) -> str
write_table(table: Table) -> str
```

- The delimiter is a comma; a field is quoted with `"`, a quote inside is doubled. LF, CRLF or a bare CR ends a row; a final newline adds no row; a blank line is an empty row, so the writer renders a lone empty field as `""`.
- `parse` accepts ragged rows. `parse_table` takes the first row as the header (an empty document gives an empty header and no rows).
- `write` takes `str[][]`, quotes only a field containing a comma, quote, CR or LF, and ends every row with LF. There is no writer from `Field` values.
- `parse` returns text, so `a,,b` and `a,"",b` give one row. `parse_fields` accepts and refuses exactly as `parse` does and returns each field's `text` and `quoted` (`True` for a field written in quotes, whatever it holds). To read an unquoted empty field as NULL and `""` as empty text, test `field.quoted` and `field.text == ""`.
- A UTF-8 byte-order mark is kept: drop it first (`text[3:]` when `strings.starts_with` finds it).
- A failure names `at line L, column C`, from 1. The column counts bytes; a line counts at each LF (quoted fields too), a bare CR ends a row but not a line. `UnexpectedQuote` and `UnexpectedCharacter` name the offending byte, `UnterminatedQuote` the end of the document.

| Document | Result |
| --- | --- |
| `"a""b"` | `a"b` |
| `"a\nb",c` (LF, CRLF or CR inside quotes) | field `a\nb`, break kept |
| `a\n\nb\n` | `[a]`, `[]`, `[b]` |
| empty document, `\n`, `""` | no rows; `[]`; `[""]` |
| `a, b ,c` | `a`, ` b `, `c` |
| `a,` and `,a` | `[a, ""]` and `["", a]` |
| `"a` | `UnterminatedQuote`: `unterminated quoted field at line 1, column 3` |
| `a"b` | `UnexpectedQuote`: `quote inside an unquoted field at line 1, column 2` |
| `"a"b` | `UnexpectedCharacter`: `unexpected character after a field at line 1, column 4` |

```selka
# doc: expect 42
import csv

func field_kinds(text: str) -> str:
    mut kinds = ""
    match csv.parse_fields(text):
        case Ok(rows):
            for row in rows:
                for field in row:
                    if field.quoted:
                        kinds += "quoted "
                    elif field.text == "":
                        kinds += "null "
                    else:
                        kinds += "text "
        case Err(error):
            kinds = csv.message(error)
    return kinds


func rows_of(text: str) -> str[][]:
    match csv.parse(text):
        case Ok(rows):
            return rows
        case Err(_):
            return []


func main() -> int:
    if field_kinds("a,,b\n") != "text null text ":
        return 1
    if field_kinds("a,\"\",b\n") != "text quoted text ":
        return 2
    if rows_of("a,,b\n") != rows_of("a,\"\",b\n"):
        return 3
    if field_kinds("a\"b") != "quote inside an unquoted field at line 1, column 2":
        return 4
    if rows_of("a\n\nb") != [["a"], [], ["b"]]:
        return 5
    match csv.parse_table("name,score\nada,41\n"):
        case Ok(table):
            if table.header != ["name", "score"]:
                return 6
            if table.rows != [["ada", "41"]]:
                return 7
            if csv.write_table(table) != "name,score\nada,41\n":
                return 8
            return 42
        case Err(_):
            return 9
```

## http

`http` parses one complete HTTP/1.0 or HTTP/1.1 request or response from bytes and renders one back. It is a pure codec: no socket, clock or connection state. Pair it with `network` for a live `Connection`.

```text
# doc: not-selka
record Header:
    name: str
    value: str
record Request:
    method: str
    target: str
    version: str
    headers: Header[]
    body: bytes
record Response:
    version: str
    status: int
    reason: str
    headers: Header[]
    body: bytes
enum Error:
    Incomplete
    Malformed(value: str)
    Unsupported(value: str)
    HeaderTooLarge(value: str)
    BodyTooLarge(value: str)
    UnsupportedVersion(value: str)
message(error: Error) -> str
status(error: Error) -> int
record Limits:
    header_bytes: int = 65536
    header_fields: int = 100
    body_bytes: int = 1048576
record ParsedRequest:
    request: Request
    length: int
record ParsedResponse:
    response: Response
    length: int
parse_request(data: bytes) -> Result[Request, Error]
parse_request_within(data: bytes, limits: Limits) -> Result[Request, Error]
parse_request_prefix(data: bytes, limits: Limits) -> Result[ParsedRequest, Error]
parse_response(data: bytes, closed: bool) -> Result[Response, Error]
parse_response_prefix(data: bytes, closed: bool) -> Result[ParsedResponse, Error]
write_request(request: Request) -> Result[bytes, Error]
write_response(response: Response) -> Result[bytes, Error]
write_response_head(response: Response) -> Result[bytes, Error]
header(fields: Header[], name: str) -> str? from fields
headers(fields: Header[], name: str) -> str[]
method(request: Request) -> str
target(request: Request) -> str
path(request: Request) -> str
query(request: Request) -> str
```

- **`parse_request`:** a token method, a [request target](#request-targets), `HTTP/1.0` or `HTTP/1.1`, `CRLF`-separated header fields, an optional `Content-Length` body. Names use the RFC 9110 token alphabet; values are UTF-8 with no control octet but tab. Refused: obsolete line folding, a repeated conflicting `Content-Length`, a chunked request body. Bytes after the body are ignored; `parse_request_prefix` also answers how many octets the message took ([several messages](#several-messages-in-one-buffer)). Defaults: a header section of 65,536 bytes and 100 fields, a body of 1,048,576 bytes; `parse_request_within` takes others ([request limits](#request-limits)). Reading is [strict](#strict-reading) where two readers could disagree about where a message ends.
- **`parse_response`:** `Content-Length`, a single `chunked` coding with trailers, or a body ended by connection close (needs `closed=true`; with the peer open and no length the result is `Incomplete`). 1xx, 204 and 304 have no body; chunked plus `Content-Length` is refused. A HEAD response is not told apart: pass `closed=false` and read headers only.
- **Writers** (`write_request`, `write_response`, `write_response_head`) validate method, target, version, status and header names and values, reject a declared `Content-Length` that disagrees with `body`, and add `Content-Length` for a nonempty body without one. `write_response` also writes `Content-Length: 0` for an empty body, except for 1xx, 204, 304 (no body; refused when given one) and when the fields carry `Transfer-Encoding`. `Transfer-Encoding` beside a body or `Content-Length` is refused in both writers (request smuggling).
- **Accessors:** `header` (borrows, `from fields`) and `headers` (copies) match names case-insensitively. `target` is the target as sent, without a fragment. `path` and `query` answer by the target's form; `query` is the text after the first `?` (later `?`s included) or `""`.

```selka
# doc: expect /view file=https://example.test/x.html /a/b c=d
import http

func show(wire: bytes) -> str:
    match http.parse_request(wire):
        case Ok(request):
            return http.path(request) + " " + http.query(request)
        case Err(error):
            return http.message(error)


func main(out: Stream) -> int:
    print(out, show(b"GET /view?file=https://example.test/x.html HTTP/1.1\r\n\r\n"), show(b"GET http://example.test/a/b?c=d HTTP/1.1\r\n\r\n"))
    return 0
```

A refusal says which limit it hit, so a server picks the status from the value:

| Error | Meaning | `status` |
| --- | --- | --- |
| `HeaderTooLarge` | header section past 65,536 bytes or 100 fields | 431 |
| `BodyTooLarge` | body, chunk or declared `Content-Length` past 1,048,576 bytes | 413 |
| `UnsupportedVersion` | `HTTP/` digit `.` digit other than 1.0, 1.1 | 505 |
| `Unsupported` | another missing feature, such as a chunked request body or a malformed version token | 501 |
| `Malformed`, `Incomplete` | everything else wrong with the bytes | 400 |

`message` returns the reason text for every case.

```selka
# doc: expect 431 413 505
import byte_builder
import http

func status_of(wire: bytes) -> int:
    match http.parse_request(wire):
        case Ok(_):
            return 200
        case Err(error):
            return http.status(error)


func main(out: Stream) -> int:
    const wide = b"GET / HTTP/1.1\r\nX: " + byte_builder.repeat(b"y", 70000) + b"\r\n\r\n"
    print(out, status_of(wide), status_of(b"POST / HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n"), status_of(b"GET / HTTP/2.0\r\n\r\n"))
    return 0
```

```selka
# doc: expect GET /hello name=ada
import http

func main(out: Stream) -> int:
    match http.parse_request(b"GET /hello?name=ada HTTP/1.1\r\nHost: example.test\r\n\r\n"):
        case Ok(request):
            print(out, request.method, http.path(request), http.query(request))
        case Err(error):
            print(out, http.message(error))
    return 0
```

### Request targets

`parse_request`, `parse_request_within` and `write_request` accept four forms (RFC 9112 section 3.2) and refuse any other with `Malformed` (400):

- **Origin form:** `/`, a path, an optional `?query`.
- **Absolute form:** a scheme, `://`, a nonempty authority, an optional path and query.
- **`*`**, for OPTIONS.
- **Authority form** `host:port`, for CONNECT: a name, IPv4 address or bracketed IP literal, and a port of one to five digits, at most 65535.

A target that is empty or holds a space, control octet or `#` is refused, as is one starting with neither `/` nor a scheme (`admin/x`, `?a=b`). A form is not tied to a method (`GET *` is read). `path` is the text before the first `?` in origin form (a `://` inside the path or query changes nothing); in absolute form it starts at the first `/` after the authority, or is `/`. `*` and the authority form have no path: `path` and `query` answer `""`, never `/*` or `/host:port`.

```selka
# doc: expect /a/b|c=d /| | | refused
import http
import strings

func shown(target: str) -> str:
    const raw = "GET " + target + " HTTP/1.1\r\n\r\n"
    match http.parse_request(strings.encode(raw)):
        case Ok(request):
            return http.path(request) + "|" + http.query(request)
        case Err(_):
            return "refused"


func main(out: Stream) -> int:
    print(out, shown("http://h.test/a/b?c=d"), shown("https://h.test"), shown("*"), shown("h.test:443"), shown("/a#b"))
    return 0
```

### Strict reading

Two readers that disagree on where a message's fields or body end are how request smuggling works, so the codec refuses what it would guess at. A message that is well formed by RFC 9110 and 9112 is read as written.

- **Numbers are digits.** `Content-Length` is one to 18 ASCII digits (`007` is 7); a sign, underscore, inner space, list (`4, 4`) or another script's digit is `Malformed`. Equal duplicate `Content-Length` fields are one length, differing ones are refused. A status code is exactly three digits (100 to 999); a chunk size is `1*HEXDIG` (no `0x`, no sign). `Content-Length` beside `Transfer-Encoding` is refused (a request: 501 unsupported chunked body; a response: `Malformed`).
- **Control octets are refused, not trimmed.** Only space and tab are trimmed from a field value's ends. Any other control octet (0 to 8, 10 to 31, 127), a bare CR and a bare LF are refused in a field value, reason phrase, version and chunk-size line. A line ends at CRLF only: lines ending at a bare LF never complete (`Incomplete`).
- **Chunked bodies:** a chunk-size line is a hexadecimal size, optional blanks and an optional extension (read, ignored). A trailer naming `Content-Length` or `Transfer-Encoding`, or with folding or a bad name, is refused. A 1xx, 204 or 304 response ends at its blank line, so one claiming to be chunked is `Malformed`.
- **Version token:** a control octet is `Malformed`; `HTTP/1.10` or `http/1.1` is `Unsupported` (501); `HTTP/1.2` is `UnsupportedVersion` (505).

Read laxly, by choice: a lower-case method is a method of its own, extra spaces between a status line's version, code and reason are accepted, and a missing or repeated `Host` is not refused.

```selka
# doc: expect refused refused refused 4
import http
import strings

func framed(value: str) -> str:
    const raw = "POST / HTTP/1.1\r\nContent-Length: " + value + "\r\n\r\nBODYBODY"
    match http.parse_request(strings.encode(raw)):
        case Ok(request):
            return str(len(request.body))
        case Err(_):
            return "refused"


func main(out: Stream) -> int:
    print(out, framed("+4"), framed("0_4"), framed("-0"), framed("4"))
    return 0
```

### Several messages in one buffer

`parse_request` and `parse_response` read the one message at the start of `data` and ignore the rest. `parse_request_prefix(data, limits)` and `parse_response_prefix(data, closed)` also answer `length`, the octets that message took (header section, blank line, body, and a chunked trailer; all of `data` for a response ended by close). What follows `length` starts the next message; an incomplete one is `Incomplete`. A server that keeps a connection open parses on from `data[length:]`:

```selka
# doc: expect /one:4
# doc: expect /two:0
# doc: expect 45 21
import http

func main(out: Stream) -> int:
    const buffer = b"POST /one HTTP/1.1\r\nContent-Length: 4\r\n\r\nBODYGET /two HTTP/1.1\r\n\r\n"
    mut offset = 0
    mut lengths: int[] = []
    while offset < len(buffer):
        match http.parse_request_prefix(buffer[offset:], http.Limits()):
            case Ok(parsed):
                print(out, parsed.request.target + ":" + str(len(parsed.request.body)))
                append(mut lengths, parsed.length)
                offset += parsed.length
            case Err(error):
                print(out, http.message(error))
                return 1
    print(out, lengths[0], lengths[1])
    return 0
```

### HEAD answers

A HEAD answer is the GET answer's header section, its `Content-Length` included, and no body, so `write_response` cannot write it. `write_response_head(response)` writes the header section `write_response` would, ending at the blank line. Give it the GET answer itself (its `Content-Length` is the body's) or an empty body with the `Content-Length` the GET answer carries (written as declared). An empty body with no declared length gets no field, where `write_response` writes `Content-Length: 0`.

```selka
# doc: expect 38 True
import http

func main(out: Stream) -> int:
    const fields = [http.Header(name="Content-Length", value="5")]
    const head = http.Response(version="HTTP/1.1", status=200, reason="OK", headers=fields, body=b"")
    match http.write_response_head(head):
        case Ok(data):
            print(out, len(data), data == b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n")
        case Err(error):
            print(out, http.message(error))
    return 0
```

### Request limits

`parse_request_within(data, limits)` parses within the caller's `Limits` (`header_bytes`, `header_fields`, `body_bytes`); the defaults of `Limits()` are `parse_request`'s (65,536 bytes, 100 fields, 1,048,576 bytes), so a server taking a 5 MiB upload sets `body_bytes`. A body or declared `Content-Length` over `body_bytes` is `BodyTooLarge` (413); a section or field count over its limit is `HeaderTooLarge` (431), never `Malformed`.

```selka
# doc: expect parsed 2097152 413
import byte_builder
import http
import strings

func upload(size: int) -> bytes:
    const head = "PUT /f HTTP/1.1\r\nHost: x\r\nContent-Length: " + str(size) + "\r\n\r\n"
    return strings.encode(head) + byte_builder.repeat(b"x", size)


# The body length a request parses to, or the status its refusal answers with.
func outcome(data: bytes, limits: http.Limits) -> str:
    match http.parse_request_within(data, limits):
        case Ok(request):
            return "parsed " + str(len(request.body))
        case Err(error):
            return str(http.status(error))


func main(out: Stream) -> int:
    const limits = http.Limits(body_bytes=5 * 1048576)
    print(out, outcome(upload(2097152), limits), outcome(upload(5 * 1048576 + 1), limits))
    return 0
```

## json

```text
# doc: not-selka
union Json:
    null, boolean: bool, integer: int, number: float,
    text: str, array: Json[], object: dict[str, Json]

union Error:
    Malformed: str

loads(source: str) -> Result[Json, Error]
message(error: Error) -> str from error
dumps(value: Json) -> str
max_depth() -> int                   type_name(value: Json) -> str
null_value() -> Json                 boolean(value: bool) -> Json
integer(value: int) -> Json          number(value: float) -> Json
text(value: str) -> Json             array(items: Json[]) -> Json
object(fields: dict[str, Json]) -> Json
is_null(value: Json) -> bool         as_bool(value: Json) -> bool?
as_int(value: Json) -> int?   as_float(value: Json) -> float?
as_str(value: Json) -> str? from value
as_list(value: Json) -> Json[]? from value
as_dict(value: Json) -> dict[str, Json]? from value
get(value: Json, key: str) -> Json? from value
at(value: Json, index: int) -> Json? from value
```

- `loads` is strict RFC 8259: no comments, trailing commas, leading zeros, bare fractions or exponents, raw control characters, lone surrogates or trailing text. Nesting past `max_depth()` is rejected; each error names the byte offset where the scanner stopped.
- Objects keep their parse order and `dumps` reproduces it. A repeated key keeps the last value in the first one's place, as Python's `json.loads` does: `{"a":1,"b":2,"a":3}` reads as `{"a":3,"b":2}`.
- A number with no fraction or exponent that fits the signed range is `integer`, anything else `number`. `dumps` writes infinities and NaN as `null` and a float as its shortest decimal without an exponent.
- A refusal is an `Error` whose `Malformed` case carries the reason; `message` returns it. Match on the case, not the text. A module that wraps `json.Error` in its own error union converts it with `try`.
- `get`, `at`, `as_str`, `as_list`, `as_dict` return a borrow (`from value`; `message` is `from error`). Bind the answer with `const`, or `copy(...)` it; matching directly on the call stores the borrow.

```selka
# doc: expect 42
import json
import strings

func main() -> int:
    match json.loads("{\"rows\":[{\"n\":40},{\"n\":2}]}"):
        case Ok(document):
            return total(document)
        case Err(error):
            return 0 - strings.char_count(json.message(error))

func total(document: json.Json) -> int:
    const rows = json.get(document, "rows")
    match rows:
        case Some(found):
            return summed(found)
        case None:
            return 1

func summed(rows: json.Json) -> int:
    mut sum = 0
    mut index = 0
    while index < 2:
        const row = json.at(rows, index)
        match row:
            case Some(item):
                sum += field(item)
            case None:
                return 2
        index += 1
    return sum

func field(row: json.Json) -> int:
    const member = json.get(row, "n")
    match member:
        case Some(value):
            match json.as_int(value):
                case Some(count):
                    return count
                case None:
                    return 0
        case None:
            return 0
```

### Deriving JSON for your own types

```text
# doc: not-selka
encode[T: codec](value: T) -> Result[str, CodecError]
decode[T: codec](source: str) -> Result[T, CodecError]

enum CodecErrorKind:
    syntax, missing, unexpected, out_of_range, unknown_member, unknown_case, duplicate, unwritable, invariant
record CodecError:
    kind: CodecErrorKind, path: str, offset: int, message: str
```

The compiler derives the JSON form of a type from its declaration: a record needs no reader or writer, and an added field is read and written with no other change.

| Selka type | Written | Read |
| --- | --- | --- |
| `int`, `i8` to `u64` | exact number (`18446744073709551615`) | an integer token that fits; `1.0`, `1e3`, out of range refused |
| `float`, `f32` | shortest round-trip, Python `repr` (`2.5`, `-0.0`, `1e+300`) | any number; past the range `out_of_range`; NaN and infinities cannot be written |
| `bool`, `str` | `true`/`false`, a string | the same; `null` refused |
| `T?` | `null` or the value | `null`, the value, or an absent member (`None`) |
| list, `FixedArray[T, N]` | an array | an array (exactly `N` elements for a fixed array) |
| enum case without fields | its name, `"green"` (also in an enum whose other cases have fields) | the name; another is `unknown_case`; `{"case": "green"}` refused |
| enum case with fields | `{"case": "circle", "value": {"r": 3}}` | the same |
| record | an object, fields in declaration order | below |

- A record reads from an object with members in any order. A missing member takes the field's default, or is `missing` when it has none; an unknown member is `unknown_member`; a repeated one is `duplicate`.
- An `@invariant` is checked before `decode` returns: a breach fails with kind `invariant`, at the record's path and the offset of its `{`.
- A number past 2^53 is read and written exactly (a JavaScript reader rounds it). Nesting is at most 1,000 arrays and objects: `decode` refuses a deeper document (`syntax`), `encode` a deeper value (`unwritable`).
- Every refusal is a `CodecError`: `kind`, `path` (`projects[3].tracker.tasks[12].stamp`, empty for the whole document), byte `offset` (in the text written so far, for `encode`) and `message` (what `str(error)` prints). Names in a path or sentence are spelled as JSON writes them; echoed names are cut at 80 bytes and long paths in the middle with `...`.
- A part with no JSON form (function, capability, resource, class) is `E_NO_CODEC` naming its path, where `encode` or `decode` is called; so are a dictionary, set, `bytes`, tuple and `json.Json` field. A generic function passes the promise on: `func load[T: codec](text: str) -> T fails json.CodecError`.

```selka
# doc: expect {"name":"site","port":8080,"tags":["a"],"owner":null}
# doc: expect Server(name='site', port=8080, tags=['a'], owner=None) True
# doc: expect Server(name='edge', port=80, tags=[], owner=Some('ops'))
# doc: expect `port` at byte 22 is 70000, outside the range 0 to 65535
# doc: expect out_of_range port
import json

record Server:
    name: str
    port: u16 = 80
    tags: str[] = []
    owner: str?

func main(out: Stream) -> int:
    const server = Server(name="site", port=8080u16, tags=["a"], owner=None)
    const text = json.encode(server) else Err(problem):
        print(out, problem)
        return 1
    print(out, text)
    const back = json.decode[Server](text) else Err(problem):
        print(out, problem)
        return 1
    print(out, back, back == server)
    const edge = json.decode[Server]("{\"owner\": \"ops\", \"name\": \"edge\"}") else Err(problem):
        print(out, problem)
        return 1
    print(out, edge)
    const wrong = json.decode[Server]("{\"name\": \"x\", \"port\": 70000}")
    match wrong:
        case Ok(_):
            return 1
        case Err(problem):
            print(out, problem)
            print(out, case_name(problem.kind), problem.path)
    return 0
```

## pool

```text
# doc: not-selka
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

A pool is the escape hatch for graphs and entity tables: a stable, copyable name for a slot, valid while the slot lives. Removing a slot bumps its generation, so every handle to the old occupant stops matching. A stale or out-of-range handle reports `None` or `False`; no handle traps.

- A handle holds a slot index and a generation, not its pool's identity: a handle given to another pool is rejected only if that pool has no matching live slot. Keep a handle with its pool.
- **`handle.index` is readable.** `Handle` has two `int` fields, `index` and `generation` (a hand-built `pool.Handle[T](index=0, generation=0)` is an ordinary record; `==` compares both). `index` counts from 0 in first-allocation order, is always below `pool.capacity(store)`, and can subscript a list kept beside the pool. It is stable while the entry lives (`pool.set` writes the same slot).
- `pool.remove` frees the slot and the next `pool.insert` reuses the slot freed last, so a new handle can carry a removed one's `index` with a larger `generation`. Write the beside list at `handle.index` on every insert (append when `index` is `len(list)`, else overwrite) or it keeps the removed entry's data.
- **`pool.get` returns a copy** of the whole record, every list, dictionary and text in it, and `pool.set` copies it back; no field is read or written in place. Keep the small record that says what the entry is in the pool and large or growing data in lists beside it, subscripted by `handle.index`. A field that changes often belongs in such a list: through the pool it is a `get`, a change and a `set`, two copies of the record.
- `Pool` is a value record of managed lists, so assigning one shares the store. `count()` is the live population (`len` is reserved). `pool.create` takes a seed list, which supplies the element type; pass an empty annotated list for an empty pool.

```selka
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

## spans

```text
# doc: not-selka
@sealed record Span: file: int, start: int, length: int
record Sources: texts: bytes[], names: str[]
create() -> Sources
add(mut sources: Sources, name: str, own data: bytes) -> int
count(sources: Sources) -> int
has_file(sources: Sources, file: int) -> bool
file_text(sources: Sources, file: int) -> bytes from sources
file_name(sources: Sources, file: int) -> str from sources
text(sources: Sources, span: Span) -> bytes from sources
whole(sources: Sources, file: int) -> Span
of(file: int, start: int, length: int) -> Span
between(file: int, start: int, stop: int) -> Span
empty_at(file: int, start: int) -> Span
end_of(span: Span) -> int
is_empty(span: Span) -> bool
fits(sources: Sources, span: Span) -> bool
sub(span: Span, offset: int, length: int) -> Span
join(a: Span, b: Span) -> Span
equals(sources: Sources, span: Span, other: bytes) -> bool
same(sources: Sources, a: Span, b: Span) -> bool
starts_with(sources: Sources, span: Span, prefix: bytes) -> bool
compare(sources: Sources, a: Span, b: Span) -> int
hash_bytes(data: bytes) -> int
hash(sources: Sources, span: Span) -> int
```

`spans` keeps text next to the buffer it was read from for the whole program, which a stored `bytes` can do only by copying and a borrowed view cannot do at all ([keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer)).

- A `Sources` table holds the text of every file read, each under a file number. `add` moves the text in (`own`) and answers the number; a file never changes or goes, so a position never goes stale.
- A `Span` is a file number, a start and a length: three integers, copied freely, kept in records, lists and dictionary values. It is [sealed](records-and-unions.md#sealed-records): `of`, `between`, `empty_at`, `whole`, `sub` and `join` build one; other modules only read its fields.
- `text(sources, span)` is a view of the file's own octets, borrowed from the table; a span outside the table traps `R_ASSERT`.
- The table lives as long as the data pointing into it. A parser returning spans must not own the table it filled: the session does, and the parse takes it by `mut`. Keep spans, not views, in the data: a view of `model.sources` blocks a write to any field of `model` while live.
- `equals`, `same`, `starts_with`, `compare` read the text in place (`same` and `compare` take two spans of one table); `hash` is the 32-bit FNV-1a of the text and equals `hash_bytes` of the same octets.
- Spans compare by position, not text: `==` asks for the same place, and a dictionary keyed by `Span` keys by place. To key by text, intern with [`symbols`](#symbols).

```selka
# doc: expect 6 words, 'alpha' twice: True
# doc: expect b'beta' at file 0 start 12
import spans

# A token keeps where its word is, where a copy would keep the word.
record Token:
    word: spans.Span

func split(sources: spans.Sources, file: int) -> Token[]:
    const data = spans.file_text(sources, file)
    mut found: Token[] = []
    mut start = -1
    for position in range(len(data) + 1):
        mut octet = 32
        if position < len(data):
            octet = int(data[position])
        if octet == 32:
            if start >= 0:
                append(mut found, Token(word=spans.between(file, start, position)))
            start = -1
        elif start < 0:
            start = position
    return found

func main(out: Stream) -> int:
    mut sources = spans.create()
    mut text = b"let alpha = beta + alpha"
    const file = spans.add(mut sources, "design.sexp", own text)
    const tokens = split(sources, file)
    print(out, len(tokens), "words, 'alpha' twice:", spans.same(sources, tokens[1].word, tokens[5].word))
    print(out, spans.text(sources, tokens[3].word), "at file", tokens[3].word.file, "start", tokens[3].word.start)
    return 0
```

## symbols

```text
# doc: not-selka
record Symbol: id: int
@sealed record Table: names: bytes[], index: dict[bytes, int]
create() -> Table
intern(mut table: Table, text: bytes) -> Symbol
intern_span(mut table: Table, sources: spans.Sources, span: spans.Span) -> Symbol
find(table: Table, text: bytes) -> Symbol?
name(table: Table, symbol: Symbol) -> bytes from table
valid(table: Table, symbol: Symbol) -> bool
count(table: Table) -> int
```

`symbols` interns a name once and gives back a key; a `Table` holds each distinct name.

- `intern(mut table, text)` answers the `Symbol` of a name, adding it the first time (the text is copied only when new). `name(table, symbol)` is a view of the table's copy. `find` looks a name up without adding; `valid` says whether a symbol belongs to a table; `intern_span(mut table, sources, span)` interns the text a [span](#spans) names.
- A `Symbol` is one integer: copy it, store it, compare with `==`, key a dictionary or set by it. Within a table two symbols are equal exactly when their names are, and a symbol lives as long as its table (names are never removed).
- A `Table` is [sealed](records-and-unions.md#sealed-records): only `symbols` builds or changes one.
- A symbol belongs to the table that made it: `name` traps `R_ASSERT` for a number the table lacks and reads another name for one it has, so keep one table per set of names that share a meaning.
- A `pool` does not fit: it copies on every `get` where `name` lends, and cannot look a value up.

```selka
# doc: expect 2 True False b'VCC'
# doc: expect 3 1
import dicts
import symbols

func main(out: Stream) -> int:
    mut table = symbols.create()
    const gnd = symbols.intern(mut table, b"GND")
    const vcc = symbols.intern(mut table, b"VCC")
    print(out, symbols.count(table), gnd == symbols.intern(mut table, b"GND"), gnd == vcc, symbols.name(table, vcc))
    mut uses: dict[symbols.Symbol, int] = {}
    for word in [b"GND", b"VCC", b"GND", b"GND"]:
        const sym = symbols.intern(mut table, word)
        uses[sym] = dicts.get(uses, sym, 0) + 1
    print(out, uses[gnd], uses[vcc])
    return 0
```

## memo

```text
# doc: not-selka
Key.Number(value: int) | Key.Text(value: str) | Key.Data(value: bytes)
Error.InvalidCapacity(value: str)
message(error: Error) -> str
Cache[V: equality + storable]
Entry[V: equality + storable]
Lookup[V: equality + storable] { value: V, reused: bool }
create(max_entries: int, compute: func(Key) -> V) -> Result[Cache[V], Error]
call(mut cache: Cache[V], key: Key) -> Lookup[V]
clear(mut cache: Cache[V]) -> Unit
count(cache: Cache[V]) -> int
capacity(cache: Cache[V]) -> int
```

`memo` reuses completed results within one running application. `create` binds the computation and takes an entry limit from 0 to 65,536; an invalid limit returns `Error.InvalidCapacity` (`message` explains).

- Limit 0 disables retention: every `call` computes and answers `reused=False`. Otherwise a hit answers the stored snapshot with `reused=True`; misses fill the cache, then replace entries in insertion order (hits do not refresh it). `count`, `capacity` and `clear` report and reset.
- The callback takes the whole `Key` and should be deterministic in it. The cache does not validate external state or enforce a source effect ceiling; captures are unavailable. Tagged keys compare exactly: integer `1`, text `"1"` and bytes `b"1"` differ. Floating-point and collection keys are not accepted.
- Results are copyable, storable values with equality (lists, and records holding lists, are fine; results, keys and copied caches stay independent snapshots). Capabilities, owned resources and function values are excluded. A trap propagates; an entry is inserted only after the computation returns.
- Retention is bounded by entry count and a lookup scans that many entries, so keep the working set small. `Entry` and its storage are not a serialization format. No filesystem, expiry or cross-process reuse (`persistent_memo` and `durable` add them).

```selka
# doc: expect 42
import memo
import strings

func square(key: memo.Key) -> int:
    match key:
        case Number(value=value):
            return value * value
        case Text(value=value):
            return strings.char_count(value)
        case Data(value=value):
            return len(value)

func main() -> int:
    match memo.create(2, square):
        case Ok(created):
            mut cache = own created
            const first = memo.call(mut cache, memo.Key.Number(value=6))
            const second = memo.call(mut cache, memo.Key.Number(value=6))
            if first.reused or not second.reused or second.value != 36:
                return 1
            if memo.count(cache) != 1 or memo.capacity(cache) != 2:
                return 2
            memo.clear(mut cache)
            return second.value + 6
        case Err(error):
            return strings.char_count(memo.message(error))
```

## network

```text
# doc: not-selka
resource Connection: network           resource Listener: network

record Chunk[const N: u64]:      result Connected:
    bytes: [N]u8                     ok: Connection,
    length: u64                      err: int
    eof: bool

result Read[const N: u64]:       result Listening:
    ok: Chunk[N],                    ok: Listener,
    err: int                         err: int

result Written:                  result Accepted:
    ok: u64,                         ok: Connection,
    err: int                         err: int

record Failure:                  result Closed:
    resource: Connection             ok: bool,
    code: int                        err: Failure

connect(net: Network) -> Connected
connect_within(net: Network, limits: Timeouts) -> Connected
connect_to(net: Network, address: str) -> Connected                  # the address given at run time
connect_within_to(net: Network, address: str, limits: Timeouts) -> Connected
record Timeouts: connect_ms: int = 0, read_ms: int = 0, write_ms: int = 0, receive_buffer_bytes: int = 0
timed_out() -> int                   # 7: a limit of connect_within ran out
listen(net: Network) -> Listening
listen_at(net: Network, address: str) -> Listening
accept_resource[Accepted](listener: Listener) -> Accepted
read[const N: u64](own connection: Connection) -> Read[N]
write[const N: u64](own connection: Connection, data: [N]u8) -> Written
close(own connection: Connection) -> Closed
denied() -> Network                  denied_here() -> int
describe(code: int) -> str

resource Poller: network             open_poller(net: Network) -> Polling
result Polling: ok: Poller, err: int
open_poller_at(net: Network, address: str) -> Polling
open_client_poller(net: Network) -> Polling
```

- **Connect:** `connect` acquires a `Connection` through a `Network` narrowed with `net.host(name)`, which pins the endpoint (no request string). `read` returns a `Chunk[N]`, `write` sends a fixed `[N]u8` array, both reporting progress; `close` completes the handle.
- **Resources:** a plain parameter of a resource type is `E_OWN_PARAMETER`. `read`, `write` and `close` take the `Connection` `own` and consume it (`read[4](own connection)`); a `mut` parameter lets a helper use one connection across calls. A helper that keeps a resource (in a record, or returned) takes it `own` and callers pass `own listener`; one that reads more input takes the connection `own`, returns it and passes bytes out through `mut`. Projecting a field of a record holding a resource consumes the record, so return the bare connection: a loop carrying such a record checks but cannot be built.
- **Raw builtins:** `read_resource`, `write_resource` (also takes managed `bytes`, the path for a response of run-time length) and `complete_resource` serve several operations on one connection.
- **Listen:** `listen` binds a `Listener` through the narrowed `net.host(name)`; the endpoint needs its own `--allow-listen=IP:PORT` grant (`--allow-endpoint` does not permit listening). `accept_resource[Accepted](listener)` borrows it and returns a fresh `Connection`; a failed accept carries only its code and keeps the listener.
- **Rights:** an accepted connection can read, write and complete but not accept; a `Listener` can only accept. `read_resource` on a listener or `accept_resource` on a connection answers `err(2)`.

A complete single-threaded server is [`examples/http-server/main.selka`](https://github.com/eugenepentland/selka/blob/main/examples/http-server/main.selka):

```text
# doc: not-selka
selka run examples/http-server/main.selka --restrict --allow-listen=127.0.0.1:8080
```

```selka
# doc: check
import byte_builder
import network


func pump(own connection: network.Connection, mut raw: byte_builder.Builder) -> network.Connection:
    mut live = own connection
    match read_resource[network.Read[16]](live):
        case Ok(chunk):
            mut index = 0
            while index < int(chunk.length):
                _ = byte_builder.append_byte(mut raw, int(chunk.bytes[index]))
                index += 1
        case Err(code):
            _ = code
    return live


func serve(own connection: network.Connection) -> int:
    mut raw = byte_builder.create()
    mut live = own connection
    mut reads = 0
    while reads < 2:
        live = pump(own live, mut raw)
        reads += 1
    return len(byte_builder.finish(raw))


func main(net: Network) -> int:
    with net.host("127.0.0.1:8080") as scoped:
        match network.connect(scoped):
            case ok(connection):
                return serve(own connection)
            case err(code):
                return code
```

`denied` builds a stand-in `Network` that reaches nothing: every acquisition through it (or a `net.host(...)` narrowing of it), a listener included, fails with the `Connected.err` code `denied_here()`. `describe` spells any code; for that one: `network access is denied in this context: this Network is a deterministic stand-in`.

```selka
# doc: expect 6 network access is denied in this context: this Network is a deterministic stand-in
import network

func main(out: Stream) -> int:
    mut net = network.denied()
    with net.host("127.0.0.1:8000") as scoped:
        match network.connect(scoped):
            case ok(_):
                print(out, "connected")
            case err(code):
                print(out, code, network.describe(code))
    return 0
```

### Time limits on a connection

`connect` and a `Connection`'s reads and writes wait as long as the peer takes. `connect_within(net, limits)` connects within a `Timeouts` record, in milliseconds:

| Field | Bounds |
| --- | --- |
| `connect_ms` | the connect |
| `read_ms`, `write_ms` | each later `read_resource` waiting for a byte, each `write_resource` waiting to send one |
| `receive_buffer_bytes` | the kernel receive buffer (`SO_RCVBUF`, set before the connect); 0 keeps the system's |

A limit that runs out fails with code `timed_out()` (7): `Connected.err` for the connect, `Read.err` or `Written.err` for a transfer, which leaves the connection open. A refused or unreachable endpoint is code 3 and fails at once; a peer that closed is a read's end of stream. `describe(timed_out())` reads `timed out: the endpoint did not answer within the time limit`. A field at 0 (the default) or below has no limit, so `connect_within(net, Timeouts())` is `connect(net)`; a limit above one day is one day; on a stand-in nothing blocks. A test of a stalled reader sets `receive_buffer_bytes` small and counts what the server queues.

A client that bounds a whole exchange with a loopback service:

```selka
# doc: check
import byte_builder
import network


# Send `request` and read the answer to its end, failing with the code of the first transfer that fails.
func ask(own connection: network.Connection, request: bytes) -> bytes fails int:
    mut live = own connection
    match write_resource[network.Written](live, request):
        case Ok(_):
            pass
        case Err(code):
            fail code
    mut raw = byte_builder.create()
    while True:
        match read_resource[network.Read[4096]](live):
            case Ok(chunk):
                _ = byte_builder.append_array(mut raw, chunk.bytes, int(chunk.length))
                if chunk.eof:
                    return byte_builder.finish(raw)
            case Err(code):
                fail code
    fail 0


func main(net: Network, err: Stream) -> int:
    with net.host("127.0.0.1:9000") as scoped:
        match network.connect_within(scoped, network.Timeouts(connect_ms=5000, read_ms=5000, write_ms=5000)):
            case ok(connection):
                match ask(own connection, b"GET /verify HTTP/1.1\r\nConnection: close\r\n\r\n"):
                    case Ok(answer):
                        return len(answer)
                    case Err(code):
                        print(err, "the service did not answer:", network.describe(code))
                        return 1
            case err(code):
                print(err, "cannot reach the service:", network.describe(code))
                return 1
```

```selka
# doc: expect 7 True timed out: the endpoint did not answer within the time limit
import network

func main(out: Stream) -> int:
    const limits = network.Timeouts(read_ms=5000)
    print(out, network.timed_out(), limits.connect_ms == 0 and limits.write_ms == 0, network.describe(network.timed_out()))
    return 0
```

```selka
# doc: check
import network

# A reader that holds a stream open without reading it, with a small receive buffer.
func main(net: Network, err: Stream) -> int:
    with net.host("127.0.0.1:8080") as scoped:
        match network.connect_within(scoped, network.Timeouts(read_ms=1500, receive_buffer_bytes=4096)):
            case ok(stream):
                _ = network.close(own stream)
                return 0
            case err(code):
                print(err, network.describe(code))
                return 1
```

### In-memory network

`network.memory()` is a `Network` stand-in whose endpoints are names, so a test drives both halves of a socket program without a socket. `listen` registers the name of `net.host(name)`, `connect` to a listened name makes a connected pair and queues the server end, `accept_resource[Accepted](listener)` hands out ends in connect order. Bytes written on one end queue on the other (1 MB per direction); a read returns what is queued.

Nothing blocks, so these fail at once with code 3: a read with nothing queued while the peer is open, an accept with nothing waiting, a `connect` to a name nobody listens on, a second `listen` on a taken name, a write after the peer closed. A closed end gives its peer the queued bytes, then end of stream. There is no `Poller`; `network.denied()` is unchanged. A narrowed capability lives in a `with` scope, so the listener and ends live inside it.

A name is taken only while a live listener holds it, and a listener ends at its last use like any resource: a second `listen` on the name is refused (3) while the first is still used later and succeeds after its last use. `_ = own listener` as the last line is not a use that keeps it open, so the `connect` under it is refused:

```selka
# doc: expect refused with 3
import network

func main(out: Stream) -> int:
    mut net = network.memory()
    with net.host("memory:81") as scoped:
        match network.listen(scoped):
            case ok(owned):
                mut listener = own owned
                match network.connect(scoped):
                    case ok(made):
                        _ = network.close(own made)
                        print(out, "connected")
                    case err(code):
                        print(out, "refused with", code)
                _ = own listener
            case err(_):
                return 5
    return 0
```

To hold a listener or connection open on purpose, use it where it must be alive: the `accept_resource` under the `connect` is a use of the listener, and `network.close(own client)` ends the client where the program says (a function that waits on a poller holds it the same way).

```selka
# doc: expect connected and accepted
import network

func main(out: Stream) -> int:
    mut net = network.memory()
    with net.host("memory:81") as scoped:
        match network.listen(scoped):
            case ok(owned):
                mut listener = own owned
                match network.connect(scoped):
                    case ok(made):
                        mut client = own made
                        match accept_resource[network.Accepted](listener):
                            case Ok(accepted):
                                _ = own accepted
                                print(out, "connected and accepted")
                            case Err(code):
                                print(out, "no connection to accept", code)
                        _ = network.close(own client)
                    case err(code):
                        print(out, "refused with", code)
            case err(_):
                return 5
    return 0
```

### Addresses given at run time

`net.host("IP:PORT")` takes only a literal, so a reader sees where a Network reaches. A server told its addresses at deployment passes them as a `str`: `connect_to`, `connect_within_to`, `listen_at`, `open_poller_at`, `dial_to`, `dial_within_to` are the siblings of `connect`, `connect_within`, `listen`, `open_poller`, `dial`, `dial_within`.

- **The address** is `IP:PORT`, as `--allow-endpoint` and `net.host` read it: a dotted IPv4 address, a colon, a decimal port. A host name, IPv6 address, sign, space or trailing text is malformed. Port 0 asks the kernel for a port and only a poller reports it, so only `open_poller_at` takes it.
- **The grant** is checked when the operation runs, as for a literal. Under `--restrict` the address must be named verbatim by `--allow-endpoint=IP:PORT` (connect, dial) or `--allow-listen=IP:PORT` (listen), else `err(2)` ("denied: outside the granted endpoints"), or 1 with no grant of that kind at all. Without `--restrict` every address is granted and a malformed one fails with 3.
- **A narrowed Network stays narrow:** through `net.host("127.0.0.1:9000")` only that address is reachable; any other is `err(2)`.
- **Stand-ins:** `network.memory()` takes any text as a name (what `listen_at` registers is what a `net.host` literal of that text names); it has no poller, so `open_poller_at` and `dial_to` are refused (2). `network.denied()` refuses all with `denied_here()`.
- `acquire_resource` is the library's own: in a program it is `E_INTERNAL_NAME`.

```selka
# doc: expect 0 0 2
import network

# The code `connect_to` answers, 0 when it connected.
func connect_code(net: Network, address: str) -> int:
    match network.connect_to(net, address):
        case ok(made):
            _ = network.close(own made)
            return 0
        case err(code):
            return code


func main(out: Stream) -> int:
    mut net = network.memory()
    const address = "127.0.0.1:" + str(9000)
    match network.listen_at(net, address):
        case ok(owned):
            mut listener = own owned
            const reached = connect_code(net, address)
            with net.host("127.0.0.1:9000") as scoped:
                print(out, reached, connect_code(scoped, address), connect_code(scoped, "127.0.0.1:9001"))
            match accept_resource[network.Accepted](listener):
                case Ok(accepted):
                    _ = network.close(own accepted)
                case Err(_):
                    pass
        case err(code):
            print(out, "listen failed", code)
    return 0
```

A server that listens where its deployment says, with a default for development:

```selka
# doc: check
import network


func main(net: Network, env: Environment, err: Stream) -> int:
    mut address = "127.0.0.1:8080"
    match env.get("APP_LISTEN"):
        case Some(value):
            address = copy(value)
        case None:
            pass
    match network.open_poller_at(net, address):
        case ok(poller):
            _ = own poller
            return 0
        case err(code):
            print(err, "cannot listen on " + address + ":", network.describe(code))
            return 1
```

Under `--restrict` its unit file grants that one address: `SELKA_OPTIONS=--restrict --allow-env=APP_LISTEN --allow-listen=127.0.0.1:30150`, with `APP_LISTEN=127.0.0.1:30150`.

### Event loop

One thread serves many connections with a `Poller`. `open_poller(net)` binds the endpoint a `net.host("IP:PORT")` narrowing names (the `--allow-listen` grant of `listen`); the runtime keeps the listener and every accepted connection inside that one resource. A connection is the small integer id `accept` returns, so connections live in a `dict[int, State]`. Nothing blocks except `wait`, for at most `timeout_ms`. A complete echo server is [`examples/event-loop-echo/main.selka`](https://github.com/eugenepentland/selka/blob/main/examples/event-loop-echo/main.selka).

```text
# doc: not-selka
open_poller(net: Network) -> Polling
open_poller_at(net: Network, address: str) -> Polling               # the address given at run time
open_client_poller(net: Network) -> Polling                         # listens on nothing: only dial and dial_to add connections
wait(own poller, timeout_ms, mut ready: Ready) -> Poller            # fills ready.ids and ready.flags
accept(own poller, mut outcome: Outcome) -> Poller                  # outcome.value = the new id
recv(own poller, id, mut raw: byte_builder.Builder, mut outcome) -> Poller   # the Builder itself, not raw.buffer
send(own poller, id, data: bytes, offset: int, mut outcome) -> Poller   # outcome.value = bytes taken
shutdown_send(own poller, id, mut outcome) -> Poller                # half-close
close_connection(own poller, id, mut outcome) -> Poller
port(own poller, id, mut outcome) -> Poller                         # LISTENER or a connection id
peer(own poller, id, mut outcome) -> Poller                         # value = IPv4 address, extra = port
set_interest(own poller, id, mask, mut outcome) -> Poller           # EVENT_READABLE, EVENT_WRITABLE
set_idle_timeout(own poller, millis, mut outcome) -> Poller         # EVENT_IDLE after that long quiet
set_connection_idle_timeout(own poller, id, millis, mut outcome) -> Poller   # one connection's own
dial(mut poller, net: Network, mut outcome)                         # outcome.value = the new id
dial_within(mut poller, net: Network, limits: Timeouts, mut outcome)
dial_to(mut poller, net: Network, address: str, mut outcome)        # the address given at run time
dial_within_to(mut poller, net: Network, address: str, limits: Timeouts, mut outcome)
connection_limit(own poller, mut outcome) -> Poller                 # value = limit, extra = open
format_address(address: int, number: int) -> str                # "a.b.c.d:port"
new_ready() -> Ready      new_outcome() -> Outcome      has(flags, flag) -> bool
```

Open the poller where the narrowed `Network` is held and pass it by value to the loop function: a resource cannot be returned from the function that called `net.host(...)` (`E_RESOURCE_ESCAPE`). The poller and its listener stay open while the loop uses them; a loop that never waits closes them at once ([when a value is destroyed](managed-memory.md#releasing-memory)).

```selka
# doc: allow-listen 127.0.0.1:0
# doc: expect 0
import network

# The poller is open for the whole call, because the `wait` is a use of it.
func wait_once(own poller: network.Poller) -> int:
    mut live = own poller
    mut ready = network.new_ready()
    live = network.wait(own live, 0, mut ready)
    return ready.count


func main(net: Network) -> int:
    with net.host("127.0.0.1:0") as scoped:
        match network.open_poller(scoped):
            case ok(poller):
                return wait_once(own poller)
            case err(code):
                return 100 + code
```

**Ownership.** Every operation except the `dial` family takes the `Poller` `own` and returns it: `live = network.wait(own live, 100, mut ready)` after `mut live = own poller`. A helper does the same (`live = helper(own live, ...)`). An `own` operation called from a `mut` poller parameter is `E_SINGLE_OWNER_BORROW`: declare it `own`. `mut poller` is the `dial` family's form alone ([below](#dialling-from-the-event-loop)). Other results come back through `mut` arguments: `Ready` (the events of one `wait`: `ids`, `flags`) and `Outcome` (`code`, `value`, `extra`); `recv` appends to a `byte_builder.Builder`. Keep decisions in plain functions of ids and bytes and let a thin shell touch the poller.

**Events.** Flags combine; the listener is `LISTENER`, id 0. Readiness is level-triggered: an event repeats until the socket is drained.

| Flag | Value | Means |
| --- | --- | --- |
| `EVENT_READABLE` | 1 | data to `recv` (a hangup or error also reads as readable) |
| `EVENT_WRITABLE` | 2 | the send buffer has room (reported only while `set_interest` asks for it) |
| `EVENT_HANGUP` | 4 | the peer closed or reset the connection |
| `EVENT_ERROR` | 8 | the socket has a pending error, which the next `recv` or `send` reports |
| `EVENT_IDLE` | 16 | no bytes moved for the idle timeout |
| `EVENT_CONNECTED` | 32 | a dialled connection is open |

A new connection is watched for readable only: ask for `EVENT_WRITABLE` with `set_interest` while a `send` is unfinished, and drop `EVENT_READABLE` to stop reading from a client whose response is queued.

**Outcomes.** Every operation fills an `Outcome` whose `code` is:

| Code | Value | Means |
| --- | --- | --- |
| `OUTCOME_OK` | 0 | done |
| `OUTCOME_WOULD_BLOCK` | 1 | nothing now |
| `OUTCOME_CLOSED` | 2 | peer finished sending |
| `OUTCOME_FAILED` | 3 | `value` is the errno |
| `OUTCOME_UNKNOWN` | 4 | id not open |
| `OUTCOME_FULL` | 5 | table full |
| `OUTCOME_BAD` | 6 | a malformed command or an argument the operation does not take (such as `LISTENER` for `peer`) |
| `OUTCOME_DENIED` | 7 | `dial` only: the Network refused |

`recv` appends at most `RECV_LIMIT` (16,384) bytes per call and counts them in `value`. `send` offers `data[offset:]` (at most `TRANSFER_LIMIT`, 65,536 bytes) and reports in `value` how many the kernel took: write a large response over several wake-ups, advancing `offset` yourself. Ids are never reused, so a stale id answers `OUTCOME_UNKNOWN`.

**Connection limit.** A `Poller` holds as many connections (accepted and dialled) as the process may open descriptors, less 64, at most 1,048,576. `connection_limit(own poller, mut outcome)` answers the limit in `outcome.value` and the number open in `outcome.extra` (a hard limit of 524,288 gives 524,224; `ulimit -n 2000` gives 1,936). The poller raises the soft descriptor limit to the hard one when it opens.

- At the limit `accept` answers `OUTCOME_FULL` and the listener is no longer reported; further clients wait in the kernel's backlog (`SOMAXCONN`, clamped to `net.core.somaxconn`, 4,096 by default) until a slot frees.
- To free slots, close quiet connections (`set_idle_timeout`, then `close_connection` on each `EVENT_IDLE`) or the least recently active client when `connection_limit` shows the table nearly full.
- A second poller on the same address fails to open (`err(3)`); a blocking `Listener` cannot join a poller.

**Idle clients.** `set_idle_timeout(poller, 5000, ...)` makes `wait` report `EVENT_IDLE` for a connection that has moved no bytes for five seconds (the timer restarts on `accept`, on each `recv` or `send` that moves bytes, and after each report); the loop closes it. The runtime keeps the time; for your own deadlines read the `Clock` you were given.

**Port 0.** `--allow-listen=127.0.0.1:0` grants a kernel-assigned port: `net.host("127.0.0.1:0")` binds a free one and `port(poller, LISTENER, ...)` reports it, so a test needs no fixed port. Grants match verbatim (`:0` does not permit `127.0.0.1:8080`, nor the reverse); `--allow-endpoint=IP:0` is a usage error; a blocking `listen` refuses a port-0 narrowing with `err(2)`. `peer` reports an accepted connection's IPv4 address and port (`format_address` spells them).

This skeleton checks without a network:

```selka
# doc: check
import byte_builder
import network

func serve(own poller: network.Poller, err: Stream) -> int:
    mut live = own poller
    mut outcome = network.new_outcome()
    mut ready = network.new_ready()
    live = network.port(own live, network.LISTENER, mut outcome)
    print(err, "listening on port", outcome.value)
    while True:
        live = network.wait(own live, 100, mut ready)
        for index in range(ready.count):
            if ready.ids[index] == network.LISTENER:
                live = network.accept(own live, mut outcome)
                if outcome.code == network.OUTCOME_OK:
                    print(err, "accepted connection", outcome.value)
            elif network.has(ready.flags[index], network.EVENT_READABLE):
                mut raw = byte_builder.create()
                # `recv` takes the Builder (`mut raw`), not its `buffer` (`mut raw.buffer` is `E_TYPE`).
                live = network.recv(own live, ready.ids[index], mut raw, mut outcome)
                if outcome.code == network.OUTCOME_CLOSED:
                    live = network.close_connection(own live, ready.ids[index], mut outcome)
                elif outcome.code == network.OUTCOME_OK:
                    live = network.send(own live, ready.ids[index], byte_builder.finish(raw), 0, mut outcome)
    return 0


func main(net: Network, err: Stream) -> int:
    with net.host("127.0.0.1:0") as scoped:
        match network.open_poller(scoped):
            case ok(poller):
                return serve(own poller, err)
            case err(code):
                return code
```

### A connection's own idle timeout

`set_connection_idle_timeout(poller, id, millis, ...)` gives one connection its own timeout, replacing the poller's for it: `millis` ms, 0 never to report it idle, negative to return to the poller's. Other connections keep the poller's value, and it works with none set on the poller. Setting restarts the timer; closing forgets it. An id not open answers `OUTCOME_UNKNOWN`; `LISTENER` answers `OUTCOME_BAD`.

```selka
# doc: check
import network

# Ordinary requests go idle after 15 seconds; a connection that became an event stream never does.
func promote_to_stream(own poller: network.Poller, id: int, mut outcome: network.Outcome) -> network.Poller:
    mut live = own poller
    live = network.set_connection_idle_timeout(own live, id, 0, mut outcome)
    return live


func main(net: Network, err: Stream) -> int:
    with net.host("127.0.0.1:0") as scoped:
        match network.open_poller(scoped):
            case ok(poller):
                mut live = own poller
                mut outcome = network.new_outcome()
                live = network.set_idle_timeout(own live, 15000, mut outcome)
                live = network.accept(own live, mut outcome)
                if outcome.code == network.OUTCOME_OK:
                    live = promote_to_stream(own live, outcome.value, mut outcome)
                print(err, "own timeout", outcome.code)
                return 0
            case err(code):
                return code
```

### Dialling from the event loop

A `Poller` also opens connections, so one loop can be service and client and hold many connections by id (a resource cannot be a list or dictionary element).

- `dial(mut poller, net, mut outcome)` connects to the endpoint a `net.host("IP:PORT")` narrowing names and adds it to the table; `outcome.value` is the new id. Nothing blocks: a later `wait` reports `EVENT_CONNECTED`, or `EVENT_ERROR` when refused, unreachable or not finished within `connect_ms`. The next `recv` of a failed one answers `OUTCOME_FAILED` with the errno (111 refused, 110 timed out, 113 no route); close it. While connecting, `recv` and `send` answer `OUTCOME_WOULD_BLOCK` and `set_interest` takes effect once open.
- `dial` answers `OUTCOME_FAILED` for a failure known at once, `OUTCOME_FULL` for a full table, and `OUTCOME_DENIED` when the Network refused before any socket was made, with its `Connected.err` code in `value` (2 outside the granted endpoints, 6 a stand-in).
- `dial_within` takes the `Timeouts` of `connect_within`: `connect_ms` and `receive_buffer_bytes` apply, `read_ms` and `write_ms` bound nothing; idle timeouts apply, the timer starting when open.
- `dial_to` and `dial_within_to` take an address known at run time under the grants of `connect_to` ([addresses given at run time](#addresses-given-at-run-time)): not granted, or other than the narrowed one, is `OUTCOME_DENIED` with 2; a malformed granted address is `OUTCOME_FAILED` with 22.
- A dial needs exactly a blocking `connect`'s grant: the `net.host` literal and, under `--restrict`, `--allow-endpoint=IP:PORT` (a listen grant is not enough). A stand-in refuses (`OUTCOME_DENIED`: 6 from `network.denied()`, 2 from `network.memory()`).
- The poller is a `mut` borrow here because the dial also takes the Network. A step of your own may take the poller `own` with the Network and a `Filesystem` or `Clock` beside it and return the poller (`func dial_slot(own live: network.Poller, net: Network) -> network.Poller`): an `own` input of the result's type is its origin, the providers are not counted (rule P3, [ownership rules](ownership-rules.md)). Dropping the poller closes its connections.

```selka
# doc: check
import byte_builder
import network


# Ask the service on 127.0.0.1:9000 from the loop that serves 127.0.0.1:8080, and read its answer when it comes.
func serve(own poller: network.Poller, service: Network, err: Stream) -> int:
    mut live = own poller
    mut outcome = network.new_outcome()
    mut ready = network.new_ready()
    network.dial_within(mut live, service, network.Timeouts(connect_ms=5000), mut outcome)
    if outcome.code != network.OUTCOME_OK:
        print(err, "cannot dial the service", outcome.code, outcome.value)
        return 1
    const asked = outcome.value
    while True:
        live = network.wait(own live, 1000, mut ready)
        for index in range(ready.count):
            const id = ready.ids[index]
            if id == network.LISTENER:
                live = network.accept(own live, mut outcome)
            elif id == asked and network.has(ready.flags[index], network.EVENT_CONNECTED):
                live = network.send(own live, asked, b"GET /verify HTTP/1.1\r\nConnection: close\r\n\r\n", 0, mut outcome)
            elif network.has(ready.flags[index], network.EVENT_READABLE):
                mut raw = byte_builder.create()
                live = network.recv(own live, id, mut raw, mut outcome)
                if outcome.code != network.OUTCOME_OK:
                    live = network.close_connection(own live, id, mut outcome)
    return 0


func main(net: Network, err: Stream) -> int:
    with net.host("127.0.0.1:8080") as listening:
        with net.host("127.0.0.1:9000") as service:
            match network.open_poller(listening):
                case ok(poller):
                    return serve(own poller, service, err)
                case err(code):
                    return code
```

### A client with no listener

A program that only connects out should not bind a listener or need `--allow-listen`. `network.open_client_poller(net)` returns a `Poller` that listens on nothing: `dial`, `dial_to` and their `_within` forms add connections, and `wait`, `recv`, `send`, `set_interest`, the idle timeouts, `close_connection`, `peer` and `connection_limit` work as on `open_poller`, with the same limit and table. It takes the `Network` as is or narrowed with `net.host("IP:PORT")`.

- Under `--restrict` it needs no `--allow-listen`; each dial still needs the `--allow-endpoint=IP:PORT` of its address (`OUTCOME_DENIED` with 2 otherwise).
- A launch with no `--allow-endpoint` at all refuses the open with 1 (`network.describe(1)`: "no network authority is available"); a narrowing to an endpoint not granted refuses it with 2. `network.memory()` offers no poller (2); `network.denied()` refuses it (`denied_here()`).
- Nothing listens: `accept` answers `OUTCOME_WOULD_BLOCK` for ever, `wait` never reports `LISTENER`, and `port` and `set_interest` of `LISTENER` answer `OUTCOME_BAD`. Keep connections in a `dict[int, State]` by id.

This client dials one address, waits for the connect and reports a refusal (nothing listens on `127.0.0.1:1`, so errno 111); a load tester dials in batches, then `send`s and `recv`s per id:

```selka
# doc: allow-endpoint 127.0.0.1:1
# doc: expect refused 111
import byte_builder
import network


# Wait for connection `id` to finish connecting. A refusal ends as `OUTCOME_FAILED` with the errno in `outcome.value`:
# `wait` reports `EVENT_ERROR` and the first `recv` after it answers the errno.
func settle(own poller: network.Poller, id: int, mut outcome: network.Outcome) -> network.Poller:
    mut live = own poller
    mut ready = network.new_ready()
    live = network.wait(own live, 1000, mut ready)
    if ready.count > 0 and network.has(ready.flags[0], network.EVENT_ERROR):
        mut raw = byte_builder.create()
        live = network.recv(own live, id, mut raw, mut outcome)
    return live


# A poller and a `Network` are two inputs, so the dial is written where both are held.
func main(net: Network, out: Stream) -> int:
    match network.open_client_poller(net):
        case ok(poller):
            mut live = own poller
            mut outcome = network.new_outcome()
            network.dial_to(mut live, net, "127.0.0.1:1", mut outcome)
            if outcome.code == network.OUTCOME_OK:
                const id = outcome.value
                live = settle(own live, id, mut outcome)
            _ = own live
            if outcome.code == network.OUTCOME_FAILED:
                print(out, "refused", outcome.value)
            else:
                print(out, "connected")
            return 0
        case err(code):
            print(out, "no poller", code)
            return 1
```

## random

```text
# doc: not-selka
record Random: ...

seeded(seed: int) -> Random          from_word(word: u64) -> Random
from_entropy(capability: Entropy) -> Result[Random, str]
seeded_entropy(seed: int) -> Entropy
failing_entropy(after: int) -> Entropy
next_word(mut generator: Random) -> u64  random(mut generator: Random) -> float
randint(mut generator: Random, low: int, high: int) -> Result[int, str]
choice[T: copy + storable](mut generator: Random, items: T[]) -> T?
shuffle[T: copy + storable](mut generator: Random, mut items: T[])
```

- The stream is SplitMix64: deterministic simulation state, not a cryptographic generator. Equal seeds give equal streams (seed zero starts with `16294208416658607535`). Copying a `Random` snapshots its position; each copy advances alone. Pass `mut generator` to advance the caller's stream.
- `random` answers one of the 2^53 multiples of 2^-53 in `[0, 1)`. `randint` is inclusive at both ends, covers the whole signed range without overflow and removes modulo bias. `shuffle` is an in-place Fisher-Yates pass.
- Entropy needs the explicit `Entropy` capability; importing grants nothing. `seeded_entropy` is a stand-in whose words are the SplitMix64 stream of its seed, so `from_entropy` on it is reproducible.
- `failing_entropy(after)` answers its first `after` reads like `seeded_entropy(0)`, then fails every read, so `from_entropy` returns `Err("entropy capability failed")` (a count below one fails the first read). It is deterministic, so a test using it stays cached.

```selka
# doc: expect ok ok entropy capability failed
import random

func draw(entropy: Entropy) -> str:
    match random.from_entropy(entropy):
        case Ok(_):
            return "ok"
        case Err(message):
            return copy(message)

func main(out: Stream) -> int:
    const entropy = random.failing_entropy(2)
    print(out, draw(entropy), draw(entropy), draw(entropy))
    return 0
```

```selka
# doc: expect 42
import random
import strings

func main() -> int:
    mut generator = random.seeded(7)
    mut index = 0
    while index < 100:
        match random.randint(mut generator, 0 - 5, 5):
            case Ok(value):
                if value < 0 - 5 or value > 5:
                    return 1
            case Err(message):
                return 0 - strings.char_count(message)
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
            mut generator = own sampled
            return int(random.next_word(mut generator) % 1000u64)
        case Err(_):
            return 500
```

## registers

`registers` reads and writes hardware registers through a `Registers` capability, on a device or on a simulated bank. [Register access](io.md#register-access) has the rules, `script32`, `pin32`, `start_core1`, the bank sizes and the refusal codes (`E_TARGET_CAPABILITY`, `E_TARGET_SIMULATED_REGISTERS`, `E_TARGET_DEVICE_REGISTERS`, `R_REGISTER_BANK`).

- A bank is one little-endian memory: a 32-bit write at `A` reads back through `read8` at `A` to `A+3`. `poke32` sets what a read answers without logging a write.
- Every write is logged, oldest first: `write_count`, `write_address`, `write_value`, `write_width` (8, 16 or 32) read it by index (outside it traps `R_LIST_BOUNDS`); `writes` answers `RegisterWrite` records; `last_write` the newest value written at an address, or `None`.
- `simulated()` allocates the whole bank, so reads, writes, `poke32` and `pin32` are allowed in `@noalloc`; `script32` copies its values and allocates. A `parallel` task may make its own bank.

```selka
# doc: expect 1 2 [32, 8] Some(5)
import registers

# Turn on bit 0 of the control register at `base`, keeping the other bits.
func enable(reg: Registers, base: u32):
    registers.write32(reg, base, bit_or(registers.read32(reg, base), 1))


func main(out: Stream) -> int:
    const reg = registers.simulated()
    registers.poke32(reg, 0x40000000, 0x4)
    enable(reg, 0x40000000)
    registers.write8(reg, 0x40000004, 5)
    mut widths: int[] = []
    for entry in registers.writes(reg):
        append(mut widths, entry.width)
    print(out, bit_and(registers.read8(reg, 0x40000000), 1), registers.write_count(reg), widths, registers.last_write(reg, 0x40000004))
    return 0
```

```selka
# doc: expect 7 9 0 1 True
import registers

func main(out: Stream) -> int:
    const reg = registers.simulated()
    registers.script32(reg, 0x40000020, [7, 9])
    registers.pin32(reg, 0x40000024, 0x1, 0x1)
    registers.write32(reg, 0x40000024, 0)
    const ticks = [registers.read32(reg, 0x40000020), registers.read32(reg, 0x40000020), registers.read32(reg, 0x40000020)]
    print(out, ticks[0], ticks[1], ticks[2], registers.read32(reg, 0x40000024), registers.last_write(reg, 0x40000024) == Some(0))
    return 0
```

A device program that runs a second loop on core 1 (it checks everywhere; only a `--target thumbv6m-none` build makes it):

```selka
# doc: check
import registers

# Core 1: push one word to core 0 through the SIO FIFO (FIFO_WR at 0xD0000054).
func second(reg: Registers) -> int:
    registers.write32(reg, 0xD0000054, 7)
    return 0


func main(reg: Registers) -> int:
    if not registers.start_core1(reg, second):
        return 1
    # The word core 1 pushed, once FIFO_ST (0xD0000050) says one waits.
    mut polls = 0
    while bit_and(registers.read32(reg, 0xD0000050), 1) == 0:
        polls += 1
    return int(registers.read32(reg, 0xD0000058))
```

## cpu

`cpu` holds the processor instructions firmware needs and no expression names, each taking the `Registers` capability first.

- `wait_for_event`, `wait_for_interrupt`, `send_event`, `barrier` (data and instruction synchronisation, needed after a write that changes how memory or interrupts behave) and `breakpoint`. On a device each is the instruction, inline, and may be called from `@freestanding` and `@freestanding(ram)` code together with the two below.
- `interrupts_off(reg)` answers an `InterruptState`, the state before the call; `interrupts_restore(reg, own state)` puts it back. The state is a sealed `@linear` record: never restoring is `E_LINEAR_UNCONSUMED`, restoring twice `E_LINEAR_CONSUMED`, a forged state or an `own state.primask` outside `cpu` `E_SEALED_RECORD`. Holds nest: `state.primask` is 1 when interrupts were already off, so the inner restore leaves them off.
- On a simulated bank each call does nothing to the machine, a wait included, and is logged beside the write log: `event_count`, `event_operation` (the function's name, `"send_event"`) and `event_writes_before` read an entry; `events` answers `CpuEvent` records; `count_of(reg, "barrier")` counts one kind; `interrupts_are_off(reg)` says whether they are off now; `write_with_interrupts_off(reg, index)` whether logged write `index` happened while they were. The log holds 16,384 operations (full traps `R_REGISTER_BANK`), so every call is allowed in `@noalloc`. A device build refuses the log readers (`E_TARGET_SIMULATED_REGISTERS`) and `@freestanding` code may not call them.

```selka
# doc: expect False True False 1 2
import cpu
import registers

# Drive a flash chip's select line low and send one command with interrupts held off, then wake the other core.
func select_and_send(reg: Registers, command: u32):
    const held = cpu.interrupts_off(reg)
    registers.write32(reg, 0x4001800c, 0)
    registers.write32(reg, 0x40018008, command)
    cpu.interrupts_restore(reg, own held)
    cpu.send_event(reg)


func main(out: Stream) -> int:
    const reg = registers.simulated()
    registers.write32(reg, 0x4001800c, 1)
    select_and_send(reg, 0x9f)
    const writes = [cpu.write_with_interrupts_off(reg, 0), cpu.write_with_interrupts_off(reg, 2)]
    print(out, writes[0], writes[1], cpu.interrupts_are_off(reg), cpu.count_of(reg, "send_event"), cpu.event_writes_before(reg, 0) + cpu.event_writes_before(reg, 1) - 2)
    return 0
```

## time

```text
# doc: not-selka
record Duration:                      record Instant:
    nanoseconds: int                     unix_nanoseconds: int

nanoseconds(count: int) -> Duration                    # each takes a count of the unit it names
microseconds(count: int) -> Result[Duration, str]
milliseconds(count: int) -> Result[Duration, str]
seconds(count: int) -> Result[Duration, str]
sum(first: Duration, second: Duration) -> Result[Duration, str]
difference(first: Duration, second: Duration) -> Result[Duration, str]
compare(first: Duration, second: Duration) -> int
to_seconds(value: Duration) -> float to_milliseconds(value: Duration) -> int
now(clock: Clock) -> Result[Instant, str]
from_unix_nanoseconds(count: int) -> Instant
after(start: Instant, duration: Duration) -> Result[Instant, str]
elapsed(start: Instant, end: Instant) -> Result[Duration, str]
expired(deadline: Instant, current: Instant) -> bool
simulated_clock(start: Instant) -> Clock
failing_clock(start: Instant, reads: int) -> Clock     # `reads`: the calls of `now` it answers
advance(clock: Clock, duration: Duration) -> Result[Unit, str]
monotonic(clock: Clock) -> int                         # nanoseconds
sleep(clock: Clock, count: int) -> Unit                # waits `count` nanoseconds

record Civil:                         # a UTC date and time of day
    year: int       month: int      day: int
    hour: int       minute: int     second: int      nanosecond: int
is_leap_year(year: int) -> bool
days_in_month(year: int, month: int) -> int            # 0 for a month outside 1 to 12
to_civil(instant: Instant) -> Civil
from_civil(civil: Civil) -> Result[Instant, str]
weekday(civil: Civil) -> int                            # ISO 8601: Monday 1 to Sunday 7
format_rfc3339(instant: Instant) -> str
parse_rfc3339(text: str) -> Result[Instant, str]
format_http_date(instant: Instant) -> str
parse_http_date(text: str) -> Result[Instant, str]
```

- Both records count signed nanoseconds, about 292 years either side of the Unix epoch; every constructor and arithmetic operation that can leave that range returns `Result`.
- `now` reads the wall clock through an explicit `Clock` and keeps the provider's unavailable, denied and failed categories apart in its message. A `Clock` needs no grant but its wall time does: under `--restrict` without `--allow-clock`, `now` fails with "the wall clock is not granted: pass `--allow-clock`", while `monotonic` and `sleep` keep working.
- A host clock may move backward, so `elapsed` rejects a reversed pair. `monotonic(clock)` never decreases and counts nanoseconds from an arbitrary start: only differences mean anything. `sleep(clock, count)` waits `count` nanoseconds (zero or less: no wait; a host clock never returns sooner, a simulated one moves its readings by `count` at once).
- Calendar conversion is UTC only; there are no time zones.

```selka
# doc: expect 1000000
import time

func main(out: Stream) -> int:
    const clock = time.simulated_clock(time.from_unix_nanoseconds(0))
    const before = time.monotonic(clock)
    time.sleep(clock, 1000000)
    print(out, time.monotonic(clock) - before)
    return 0
```

- `to_civil` and `from_civil` convert an `Instant` to and from the proleptic Gregorian date and time of day in UTC (no leap seconds) for the span a nanosecond count holds, 1677-09-21T00:12:43.145224192Z to 2262-04-11T23:47:16.854775807Z. `from_civil` refuses a field out of range (`2023-02-29`, hour 24, second 60) and an instant outside the span, naming the field.
- `format_rfc3339` writes `YYYY-MM-DDThh:mm:ss[.fraction]Z`, the fraction only when not zero and without trailing zeros. `parse_rfc3339` reads `T` or `t`, one to nine fraction digits and `Z`, `z` or a `+hh:mm` / `-hh:mm` offset; it refuses a leap second and anything after the offset.
- `format_http_date` writes the IMF-fixdate of RFC 9110 (`Sun, 06 Nov 1994 08:49:37 GMT`). `parse_http_date` also accepts the obsolete RFC 850 form (`Sunday, 06-Nov-94 08:49:37 GMT`; years 70 to 99 read as 19xx, 00 to 69 as 20xx) and asctime (`Sun Nov  6 08:49:37 1994`). Names are case-sensitive; the weekday is read, not checked.

```selka
# doc: expect 784111777
import time

func main() -> int:
    match time.parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT"):
        case Ok(instant):
            const civil = time.to_civil(instant)
            if civil.year != 1994 or civil.month != 11 or civil.day != 6 or time.weekday(civil) != 7:
                return 1
            if time.format_rfc3339(instant) != "1994-11-06T08:49:37Z":
                return 2
            return instant.unix_nanoseconds // 1000000000
        case Err(_):
            return 3
```

- `simulated_clock` is a stand-in `Clock` that reads `start` until `advance` moves it (backward for a negative duration); copies share one reading. A host-granted clock cannot be moved: `advance` answers `Err("only a simulated clock can be advanced")`.
- `failing_clock(start, reads)` reads like `simulated_clock` for its first `reads` calls of `now`, then fails each with `Err("clock capability failed")` (a count below one fails the first). `advance`, `sleep` and `monotonic` keep working; it is deterministic, so a test using it stays cached.

```selka
# doc: expect 1000 clock capability failed
import time

func stamp(clock: Clock) -> str:
    match time.now(clock):
        case Ok(instant):
            return f"{instant.unix_nanoseconds}"
        case Err(message):
            return copy(message)

func main(out: Stream) -> int:
    const clock = time.failing_clock(time.from_unix_nanoseconds(1000), 1)
    print(out, stamp(clock), stamp(clock))
    return 0
```

```selka
# doc: expect 42
import time
import strings

func main() -> int:
    mut start = time.from_unix_nanoseconds(1000000000)
    match time.milliseconds(1500):
        case Ok(step):
            return advanced(start, step)
        case Err(message):
            return 0 - strings.char_count(message)

func advanced(start: time.Instant, step: time.Duration) -> int:
    match time.after(start, step):
        case Ok(deadline):
            if not time.expired(deadline, deadline) or time.expired(deadline, start):
                return 1
            return measured(start, deadline)
        case Err(message):
            return 0 - strings.char_count(message)

func measured(start: time.Instant, deadline: time.Instant) -> int:
    match time.elapsed(start, deadline):
        case Ok(span):
            if time.to_milliseconds(span) != 1500 or time.to_seconds(span) != 1.5:
                return 2
            return int(time.to_seconds(span) * 28.0)
        case Err(message):
            return 0 - strings.char_count(message)
```

## filesystem

```text
# doc: not-selka
memory() -> Filesystem
mkdir_all(fs: Filesystem, path: str) -> Unit fails str
copy_file(fs: Filesystem, source: str, target: str) -> Unit fails str
walk(fs: Filesystem, root: str, suffix: str, skip: str[]) -> str[] fails str
```

`filesystem.memory()` is an empty in-memory stand-in `Filesystem` that follows the rules of a `--restrict` root and never touches the disk; a test's injected `fs` is this filesystem. Every entry belongs to `filesystem.MEMORY_OWNER` and `filesystem.MEMORY_GROUP` (1000) on the device `filesystem.MEMORY_DEVICE`. Its paths, permission bits, logical clock, inodes and locks are in [the durable calls on a test's filesystem](io.md#the-durable-calls-on-a-tests-filesystem) and [permission bits on the in-memory filesystem](io.md#permission-bits-on-the-in-memory-filesystem).

```selka
# doc: expect Ok(['data', 'notes.txt']) Ok('hello')
import filesystem

func save(fs: Filesystem, text: str) -> Unit fails str:
    return try fs.write_text("notes.txt", text)

func main(out: Stream) -> int:
    mut fs = filesystem.memory()
    _ = save(fs, "hello")
    _ = fs.mkdir("data")
    print(out, fs.listdir("."), fs.read_text("notes.txt"))
    return 0
```

Three helpers do what a build program does to files, and fail with the message text:

- `mkdir_all(fs, path)` is `mkdir -p`; a part of the way that is a file fails.
- `copy_file(fs, source, target)` is `cp`; the target gets a new file's mode.
- `walk(fs, root, suffix, skip)` answers every regular file below `root` whose name ends in `suffix` (`""` for all), sorted, as paths from `root`; a folder whose name or path is in `skip` is not entered (`".*"` skips dot folders); links are neither followed nor listed.

```selka
# doc: expect Ok(['a.selka', 'src/b.selka']) Ok(b'x')
import filesystem

func main(out: Stream) -> int:
    mut fs = filesystem.memory()
    _ = filesystem.mkdir_all(fs, "proj/src/deep")
    _ = filesystem.mkdir_all(fs, "proj/.git")
    _ = fs.write_file("proj/a.selka", b"x")
    _ = fs.write_file("proj/src/b.selka", b"")
    _ = fs.write_file("proj/.git/c.selka", b"")
    _ = filesystem.copy_file(fs, "proj/a.selka", "proj/src/deep/a.txt")
    print(out, filesystem.walk(fs, "proj", ".selka", [".*"]), fs.read_file("proj/src/deep/a.txt"))
    return 0
```

The other typed functions, and the types `Stat`, `StatError`, `PathKind`, `Space` and `Entry`, are in [rename, stat and file locks](io.md#rename-stat-and-file-locks) (`stat`, `stat_follow`, `is_lock_busy`), [device, free space and reads from an offset](io.md#device-free-space-and-reads-from-an-offset) (`statfs`, `read_at`, `device_major`, `device_minor`), [listings with entry kinds](io.md#listings-with-entry-kinds) (`list_entries`), [real paths, permissions and times](io.md#real-paths-permissions-and-times) (`realpath`, `cwd`, `chmod`, `touch`, `set_modified`, `symlink`, `read_link`, `link`, `mkdir_mode`, `create_mode`, `fs.atomic_write_file_mode`) and [a folder named at run time](io.md#a-folder-named-at-run-time-filesystemdir_at) (`dir_at`). A `Stat` constructor may leave `mode`, `changed`, `device`, `owner`, `group` and `links` out (they default to `0`).

```selka
# doc: expect 0 1 True
# doc: expect 1073741824 536870912 402653184
# doc: expect b'6789' b'' replace refused: replace 'lib/app': permission denied
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("lib")
    _ = fs.write_file("lib/app", b"0123456789")
    match filesystem.stat(fs, "lib/app"):
        case Ok(found):
            print(out, filesystem.device_major(found.device), filesystem.device_minor(found.device), found.device == filesystem.MEMORY_DEVICE)
        case Err(_):
            return 1
    match filesystem.statfs(fs, "lib"):
        case Ok(space):
            print(out, space.size_bytes, space.free_bytes, space.available_bytes)
        case Err(_):
            return 2
    mut rest = b"?"
    match filesystem.read_at(fs, "lib/app", 6, 100):
        case Ok(data):
            rest = copy(data)
        case Err(_):
            return 3
    mut past = b"?"
    match filesystem.read_at(fs, "lib/app", 10, 100):
        case Ok(data):
            past = copy(data)
        case Err(_):
            return 4
    _ = filesystem.chmod(fs, "lib", 0o555)
    mut refusal = "replaced"
    match fs.replace_file_synced_mode("lib/app", b"new", 0o755):
        case Ok(_):
            pass
        case Err(message):
            refusal = "replace refused: " + message
    print(out, rest, past, refusal)
    return 0
```

```selka
# doc: expect Missing
# doc: expect Regular 3 420
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    match filesystem.stat(fs, "x"):
        case Ok(_):
            print(out, "unexpected")
        case Err(error):
            match error:
                case Missing:
                    print(out, "Missing")
                case Failed(message=text):
                    print(out, "Failed:", text)
    _ = fs.write_text("x", "abc")
    match filesystem.stat(fs, "x"):
        case Ok(info):
            match info.kind:
                case Regular:
                    print(out, "Regular", info.size, info.mode)
                case Directory:
                    print(out, "Directory")
                case Symlink:
                    print(out, "Symlink")
                case Other:
                    print(out, "Other")
        case Err(_):
            print(out, "unexpected")
    return 0
```

## environment

```text
# doc: not-selka
fixed(values: dict[str, str]) -> Environment
```

`fixed` builds a stand-in `Environment` holding exactly `values`: `env.get` answers from them, `env.names()` lists them sorted, `env.only(...)` narrows them (a name outside the narrowed set traps `R_CAPABILITY`, as on a host `Environment`). It never reads the process environment. A name is nonempty, at most 128 bytes, without `=`; a value at most 16384 bytes; neither contains NUL (`R_ENVIRONMENT` otherwise).

```selka
# doc: expect /home/test ['HOME', 'LANG']
import environment

func home(env: Environment) -> str:
    match env.get("HOME"):
        case Some(value):
            return copy(value)
        case None:
            return "/"

func main(out: Stream) -> int:
    mut env = environment.fixed({"HOME": "/home/test", "LANG": "C"})
    print(out, home(env), env.names())
    return 0
```

## streams

A test prints to a capturing stream and reads back what it printed. `memory()` returns a `Stream` that keeps every write; `text(stream)` returns the text so far as one `str`. Neither needs a grant, nothing reaches the process's output, and each stream keeps only its own text. `text` on a stream the process owns (`out` or `err`) fails with `InvalidCapability`.

```selka
# doc: expect True
import streams

func report(out: Stream, label: str, count: int) -> int:
    print(out, label, count)
    return count

func main(out: Stream) -> int:
    const capture = streams.memory()
    _ = report(capture, "count:", 7)
    print(out, streams.text(capture) == "count: 7\n")
    return 0
```

`input_from(data: bytes) -> Input` is the same for standard input: an in-memory [`Input`](io.md#standard-input) that answers `read`, `read_exact`, `read_line` and `read_into` from `data` in order, then reports the end. Two inputs keep separate positions.

```selka
# doc: expect b'ab' b'c' b''
import streams

func main(out: Stream) -> int:
    const stdin = streams.input_from(b"abc")
    print(out, stdin.read(2), stdin.read(9), stdin.read(9))
    return 0
```

## Focused references

[Binary64 floating point](floating-point.md) specifies what `float` does, which `math` builds on. [Time and randomness](https://github.com/eugenepentland/selka/blob/main/docs/standard-time-random.md) specifies the capability contracts, the pinned SplitMix64 vectors and the arithmetic limits.

## Contracts these modules share

Managed collections grow automatically and are released with their last owner ([managed memory](managed-memory.md)). A `str` is bytes: `len(text)`, `text[i]` and `text[a:b]` count octets, and the `strings.char_*` functions count characters ([text](text.md#text-is-bytes-scalars-have-helpers)). There is no Unicode normalization, and case mapping is ASCII only. Managed-value modules report conversion failures with checked results or optional values; the byte builder's checked appends return a success flag; `network` uses resource-result types. A module that can fail carries its messages in an [error union](#error-unions).

## Error unions

A standard module whose operations can fail exports an error union named `Error` and returns `Result[T, Module.Error]` from every exported fallible operation, not `Result[T, str]`. Each case carries a `str` payload and `message(error)` returns the human-readable reason. Match on the case; the text is for people and may change between releases. Adding a case to a published error union is a breaking interface change: a caller that matches exhaustively stops compiling.

`json` and `strings` follow this contract; `math`, `time`, `random`, `base64` and `hex` still return `Result[T, str]`. `try` converts automatically at such a boundary: when the propagated error type is the payload type of a case of the enclosing function's error union, it wraps in that case with no translation helper.

```selka
# doc: expect 42
import json
import strings

enum AppError:
    Json(value: json.Error)


func size(source: str) -> int fails AppError:
    mut document = try json.loads(source)
    return strings.char_count(json.dumps(document))


func main() -> int:
    match size("{bad}"):
        case Ok(_):
            return 1
        case Err(error):
            match error:
                case Json(value=detail):
                    if strings.char_count(json.message(detail)) > 0:
                        return 42
                    return 2
```

## Limits

- `json`'s union variants are built through the module's constructor functions.
- No module reads or writes a file; `path` is text algebra only.

## hashes

`hashes.sha256(data: bytes) -> str` answers 64 lowercase hexadecimal digits. The 32 raw octets, as `bytes`, are `hashes.sha256_bytes(data)` and `hashes.sha256_text_bytes(text)`; `hashes.blake3_bytes(data)` and `hashes.blake3_text_bytes(text)` answer the raw BLAKE3 octets (`hashes.blake3` answers a `Digest`). Each hashes in place, a text's UTF-8 octets with no encoded copy, and the `bytes` ones also take a `byte_buffer`.

```selka
# doc: expect True
# doc: expect 32
import hashes

func main(out: Stream) -> int:
    print(out, hashes.sha256_bytes(b"abc") == hashes.sha256_text_bytes("abc"))
    print(out, len(hashes.blake3_text_bytes("abc")))
    return 0
```

```selka
# doc: expect 42
import hashes
import hex

func main() -> int:
    const raw = hashes.sha256_bytes(b"abc")
    if len(raw) == 32 and hex.encode(raw) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad":
        return 42
    return 1
```

### BLAKE3 digests

`hashes.blake3(data: bytes) -> Digest` and `hashes.blake3_text(text: str) -> Digest` answer the 32-byte [BLAKE3](https://github.com/BLAKE3-team/BLAKE3) digest of `data` (or of `text`'s UTF-8 octets), hashed in place. The raw octets are `blake3_bytes(data)` and `blake3_text_bytes(text)`.

A `hashes.Digest` is four `u64` words (`w0` to `w3`, each the little-endian reading of eight digest octets): a plain value that compares with `==`, keys a dictionary or set and copies freely. It is [sealed](records-and-unions.md#sealed-records): only `hashes` builds one, and its words are read, never written. It has no methods:

| Function | Result |
| --- | --- |
| `hashes.hex(digest)` | the 64 lowercase hexadecimal digits, as `sha256` answers |
| `hashes.to_bytes(digest)` | the 32 octets as `bytes` |
| `hashes.from_bytes(data)` | the digest of 32 octets; fails with a `str` unless `len(data) == 32` |
| `hashes.from_hex(text)` | the digest of 64 hexadecimal digits, either case; fails with a `str` otherwise |

```selka
# doc: expect 42
import hashes

func main() -> int:
    const digest = hashes.blake3(b"abc")
    if hashes.hex(digest) != "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85":
        return 1
    if digest != hashes.blake3_text("abc") or digest == hashes.blake3(b"abd"):
        return 2
    match hashes.from_hex(hashes.hex(digest)):
        case Ok(again):
            if again != digest:
                return 3
        case Err(_):
            return 4
    mut seen: dict[hashes.Digest, int] = {}
    seen[digest] = 7
    if seen[hashes.blake3(b"abc")] != 7:
        return 5
    return 42
```

### SHA-1 for protocols that require it

`hashes.sha1(data: bytes) -> str` answers 40 lowercase hexadecimal digits and `hashes.sha1_bytes(data: bytes) -> bytes` the 20 octets a protocol encodes. SHA-1 is broken for collisions: use it only where a protocol names it (the WebSocket handshake of RFC 6455, Git's object names), never to protect anything; choose `sha256` or `blake3`. It suits a handshake's few dozen octets, not bulk data. A WebSocket client checks the server's `Sec-WebSocket-Accept`, the base64 of the SHA-1 of its key and a fixed GUID. With the sample of RFC 6455 section 1.3:

```selka
# doc: expect s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
import base64
import hashes
import strings

# The `Sec-WebSocket-Accept` value a server answers the `Sec-WebSocket-Key` `key` with.
func accept_value(key: str) -> str:
    const digest = hashes.sha1_bytes(strings.encode((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))
    match strings.decode(base64.b64encode(digest)):
        case Ok(text):
            return text
        case Err(_):
            return ""


func main(out: Stream) -> int:
    print(out, accept_value("dGhlIHNhbXBsZSBub25jZQ=="))
    return 0
```

## binary

A compact binary record format over `byte_builder`: fixed-width little-endian integers, LEB128 varints, length-prefixed bytes and text. Writing appends to a `byte_builder.Builder`; reading takes the `bytes` and an `int` position the caller keeps, and a read that cannot finish fails instead of trapping.

```text
# doc: not-selka
put_u8(mut b, u8)  put_u16_le(mut b, u16)  put_u32_le(mut b, u32)  put_u64_le(mut b, u64)
put_i8(mut b, i8)  put_i16_le(mut b, i16)  put_i32_le(mut b, i32)  put_i64_le(mut b, i64)
put_uvarint(mut b, u64)  put_varint(mut b, i64)  put_bytes(mut b, bytes)  put_text(mut b, str)

get_u8(data, mut at) -> u8 fails Error   get_u16_le  get_u32_le  get_u64_le
get_i8(data, mut at) -> i8 fails Error   get_i16_le  get_i32_le  get_i64_le
get_uvarint(data, mut at) -> u64 fails Error   get_varint(data, mut at) -> i64 fails Error
get_length(data, mut at) -> int fails Error
get_bytes(data, mut at) -> bytes fails Error   get_text(data, mut at) -> str fails Error
remaining(data, at) -> int   at_end(data, at) -> bool   message(error) -> str
enum Error: Truncated | Overlong | Text
```

- `put_uvarint` writes seven bits per octet, low group first, the high bit set on all but the last octet (`300` is `ac 02`). `put_varint` zigzag-maps a signed value first (`0, -1, 1, -2` become `0, 1, 2, 3`). `put_bytes` and `put_text` write the octet count as an unsigned varint, then the octets.
- Every `get_*` takes the data and a `mut position`, advances it past what it read, and fails with `Truncated` (input ends first, a length prefix promising too many octets included), `Overlong` (a varint over ten octets or past the 64th bit) or `Text` (length-prefixed text not UTF-8). A failed read leaves the position where it was.
- `get_bytes` and `get_text` return independent copies. `get_length` reads only the count before a field and checks that many octets remain, leaving the position past the prefix: the payload is `data[at:at + count]` and the caller steps over it with `at += count`, so looking at a field copies nothing. `bytes.read_u8(data, at)` is the inline single-octet read for its first or last octet.

```selka
# doc: expect 42
import binary
import byte_builder
import hex

func decode(data: bytes) -> int fails binary.Error:
    mut at = 0
    const id = try binary.get_uvarint(data, mut at)
    const delta = try binary.get_varint(data, mut at)
    const name = try binary.get_text(data, mut at)
    const stamp = try binary.get_u32_le(data, mut at)
    if id != 300u64 or delta != -2 or name != "λ" or stamp != 7u32 or not binary.at_end(data, at):
        return 0
    return 42

func main() -> int:
    mut builder = byte_builder.create()
    binary.put_uvarint(mut builder, 300u64)
    binary.put_varint(mut builder, -2)
    binary.put_text(mut builder, "λ")
    binary.put_u32_le(mut builder, 7u32)
    const data = byte_builder.finish(builder)
    if hex.encode(data) != "ac0203" + "02cebb" + "07000000":
        return 1
    match decode(data):
        case Ok(value):
            return value
        case Err(error):
            return 2
```

## process

```text
# doc: not-selka
record Request:                      record Output:
    argv: str[]                          exited: bool
    directory: str                       code: int
    input: bytes                         stdout: bytes
    environment: str[]?                  stderr: bytes
    limit: int                           truncated: bool

enum Error: NotFound(program: str) | Failed(message: str)

command(argv: str[]) -> Request     run(proc: Process, request: Request) -> Output fails Error
message(error: Error) -> str        DEFAULT_LIMIT: int

record Rule:                        enum Reply: Exit(output: Output) | Missing | Refused(message: str)
    program: str
    reply: Reply                    scripted(own rules: Rule[]) -> Process
    args: str[]? = None             expect(proc: Process, rule: Rule)
    times: int? = None              calls(proc: Process) -> Request[]
                                    exited(code, stdout, stderr) -> Output
executable_path(proc: Process) -> str fails str       SCRIPTED_EXECUTABLE_PATH: str

@sealed @linear record Child:       start(proc, request, stdout_path: str?, stderr_path: str?) -> Child fails Error
    pid: int                        start_to(proc, request, stdout: Destination, stderr: Destination) -> Child fails Error
    ended: Output?                  pid(mut child: Child) -> int
                                    signal(proc, mut child, number: int) -> Unit fails Error
SIGHUP SIGINT SIGQUIT SIGKILL       wait_within(proc, mut child, millis: int) -> Output? fails Error
SIGUSR1 SIGUSR2 SIGTERM SIGCONT     wait(proc, own child) -> Output fails Error
SIGSTOP  SCRIPTED_PID: int          stop(proc, own child, grace_millis: int) -> Output fails Error
run_within(proc, request, millis: int, log_path: str, grace_millis: int) -> Output? fails Error

enum Destination: Discard | File(path: str) | Caller

@sealed @linear record Group      group() -> Group          group_size(mut g) -> int         group_pid(mut g, key) -> int?
record Finished: key: int, output: Output          @sealed record Member    # a Group's own bookkeeping; only `group_start` makes one
group_start(proc, mut g, request, stdout_path: str?, stderr_path: str?) -> int fails Error     # the key
group_start_to(proc, mut g, request, stdout: Destination, stderr: Destination) -> int fails Error
group_wait_any_within(proc, mut g, millis: int) -> Finished? fails Error     group_wait_any(proc, mut g) -> Finished fails Error
group_signal(proc, mut g, key: int, number: int) -> Unit fails Error         group_signal_all(proc, mut g, number: int) -> Unit fails Error
group_stop(proc, mut g, grace_millis: int) -> Finished[] fails Error         group_close(proc, own g, grace_millis: int) -> Finished[] fails Error

stop_requested(notice: Stop) -> bool     simulated_stop() -> Stop     request_stop(notice: Stop)
```

[Running a program](io.md#processes), [starting one without waiting](io.md#starting-a-program-without-waiting), [writing to the caller's streams](io.md#letting-a-started-program-write-to-the-callers-streams), [groups](io.md#running-several-programs-at-once-a-group), [scripted Processes](io.md#testing-code-that-runs-programs) and [hearing a stop](io.md#hearing-a-stop) are in io.md, with the `Process` capability, `NotFound` and `Failed`, `Child`, `Destination`, `Group`, `Rule`, `Stop` and the `SIG*` constants. Not there:

- `command(argv)` keeps up to `DEFAULT_LIMIT` (one mebibyte) of each output stream; set `directory`, `input`, `environment` (`Some(["NAME=VALUE"])` is exactly the child's, `None` inherits) or `limit` before the call. `message(error)` spells an `Error`.
- `run_within(proc, request, millis, log_path, grace_millis)` is `run` with a time limit: both streams go to `log_path` in the order written (`>LOG 2>&1`), and it answers `Some` with how the program ended, or `None` when the limit passed and `stop` ended it (`SIGTERM`, the grace, `SIGKILL`). A scripted Process answers the rule's `Output` and writes no file.

```selka
# doc: expect False True True
import process

func main(out: Stream) -> int:
    const stop = process.simulated_stop()
    const copy_of_it = stop
    const before = process.stop_requested(stop)
    process.request_stop(copy_of_it)
    print(out, before, process.stop_requested(stop), process.stop_requested(copy_of_it))
    return 0
```

```selka
# doc: expect 42
import process

func main(proc: Process) -> int:
    mut request = process.command(["/bin/cat"])
    request.input = b"piped\n"
    match process.run(proc, request):
        case Ok(result):
            if result.exited and result.code == 0 and result.stdout == b"piped\n" and not result.truncated:
                return 42
            return 1
        case Err(error):
            return 2
```

## buildkit

```text
# doc: not-selka
record Tools: compiler: str, zig: str, root: str          locate(env: Environment) -> Tools fails str
COMPILER_VARIABLE ("SELKA")  ZIG_VARIABLE ("SELKA_ZIG")  ROOT_VARIABLE ("SELKA_PROJECT_ROOT")

record Command:                  record Ran:                  shown(command: Command) -> str
    argv: str[]                      code: int                execute(proc, fs, out: Stream, command) -> Ran fails str
    directory: str = ""              stdout: str              run(proc, fs, out: Stream, command) -> Ran fails str
    limit_millis: int = 0            stderr: str              failure_text(command, ran: Ran) -> str
    log: str = ""                    timed_out: bool          tail(text: str, count: int) -> str
    root: str = ""                                            last_line(text: str) -> str
TAIL_LINES: int (12)  GRACE_MILLIS: int (2000)

enum State: Done | Failed | Skipped        record Outcome: name: str, state: State, nanoseconds: int, message: str
run_steps[C](context: C, names: str[], step: func(C, str) -> Unit fails str, clock: Clock) -> Outcome[]
summary(out: Stream, outcomes: Outcome[]) -> bool        summary_line(outcome: Outcome) -> str

check_argv(tools, target, options: str[]) -> str[]       tests_argv(tools, target, options: str[]) -> str[]
fmt_check_argv(tools, file) -> str[]                     build_argv(tools, source, output, options: str[]) -> str[]
packages_lock_argv(tools, manifest, output) -> str[]     packages_build_argv(tools, entry, lock, command, options: str[]) -> str[]
```

`buildkit` is for build programs, the `build.selka` that [`selka do STEP`](tooling/native-build.md#build-programs-selka-do) finds and runs. It is not named `build`, which a project's own `build/` folder and `build.selka` would hide. Every function takes the capabilities it uses, so a test hands it a scripted `Process`, an in-memory `Filesystem` and `streams.memory()` and nothing starts.

- `locate(env)` answers the `Tools` that `selka do` set in the environment: the compiler that started the program, the Zig it uses and the project root (the folder of `build.selka`). Started another way, `locate` fails naming the first missing one and saying to use `selka do STEP`.
- A `Command` is an argument list, its folder (`""` keeps the caller's), a time limit in milliseconds (0 waits as long as it takes), the file its output goes to under a limit (a limit needs one), and a root the printed line leaves off its paths. `run(proc, fs, out, command)` prints `$ ` and the line (`shown`), runs it, and answers a `Ran` (exit status, `128` plus the signal for a signal, as a shell says; what it wrote; whether the limit stopped it). Unless it exited with 0 in time it fails with `failure_text`: `FAILED:`, the line, the status or limit, and the last `TAIL_LINES` lines of each stream. `execute` is the same without the judgement. Under a limit the command runs through [`process.run_within`](#process).
- A build walks, copies and makes files with [`filesystem.walk`, `copy_file` and `mkdir_all`](#filesystem); [`path.relative`](#path) shortens a path for the reader.

```selka
# doc: expect $ cd packages && /opt/selka test rp2040
# doc: expect FAILED: cd packages && /opt/selka test rp2040
# doc: expect exit status 1
# doc: expect stdout, last lines:
# doc: expect | 1 failed
import buildkit
import process
import streams
import strings

func main(fs: Filesystem, out: Stream) -> int:
    const failing = process.exited(1, strings.encode("1 failed\n"), b"")
    const proc = process.scripted([process.Rule(program="/opt/selka", reply=process.Reply.Exit(output=own failing))])
    const tools = buildkit.Tools(compiler="/opt/selka", zig="zig", root="/work")
    const command = buildkit.Command(argv=buildkit.tests_argv(tools, "rp2040", []), directory="/work/packages", root="/work")
    const said = streams.memory()
    match buildkit.run(proc, fs, said, command):
        case Ok(_):
            return 1
        case Err(message):
            print(out, strings.rstrip(streams.text(said)))
            # The failure's later lines are indented; printed trimmed here.
            for line in strings.lines(message):
                print(out, strings.strip(line))
            return 0
```

`run_steps(context, names, step, clock)` runs the named steps in order as `step(context, name)`, timing each; the first failure stops the run and later steps are `Skipped`. A function cannot capture, so `context` carries what the steps share. `summary(out, outcomes)` prints one line a step (`ok      check             6.8 s`, `FAILED  images ...`, `skipped verify`), then a failed step's message, and answers whether every step was done:

```selka
# doc: expect skipped verify
# doc: expect images: nothing to build
# doc: expect False ['check', 'images']
import buildkit
import process
import streams
import strings

record Context:
    proc: Process

func step(context: Context, name: str) -> Unit fails str:
    _ = process.run(context.proc, process.command(["step", copy(name)])) else Err(error):
        fail process.message(error)
    if name == "images":
        fail "images: nothing to build"

func main(clock: Clock, out: Stream) -> int:
    const proc = process.scripted([process.Rule(program="step", reply=process.Reply.Exit(output=process.exited(0, b"", b"")))])
    const outcomes = buildkit.run_steps(Context(proc=proc), ["check", "images", "verify"], step, clock)
    const said = streams.memory()
    const passed = buildkit.summary(said, outcomes)
    const lines = strings.lines(streams.text(said))
    print(out, lines[2])
    print(out, lines[3])
    mut ran: str[] = []
    for call in process.calls(proc):
        append(mut ran, copy(call.argv[1]))
    print(out, passed, ran)
    return 0
```

The compiler commands a build runs have their argument lists built in one place: `check_argv` (`selka check TARGET OPTIONS`), `tests_argv`, `fmt_check_argv` (`selka fmt FILE --check`), `build_argv` (`selka build SOURCE -o OUTPUT OPTIONS`), `packages_lock_argv` (`selka packages lock MANIFEST --output LOCK`) and `packages_build_argv` (`selka packages build ENTRY --lock LOCK --command COMMAND -- OPTIONS`), each starting with `tools.compiler`.

## argparse

`argparse` parses a command line against a spec the tool declares. It is pure: it reads no environment and exits nothing, so `main(args: str[], ...)` hands it the arguments and decides what a mistake costs. Declare with `argparse.new(program, summary)` and the `add_*` functions (each takes the spec with `mut`); `argparse.parse(spec, items)` returns a `Parsed` or fails with an `argparse.Error`.

```text
# doc: not-selka
record Flag:                        # one declaration of each kind, kept in the Spec
    name: str
    short: str
    help: str
record Option:
    name: str
    short: str
    value_name: str
    help: str
    fallback: str?
record Positional:
    name: str
    help: str
    required: bool
    repeated: bool
record Spec:                        # built with new and the add_ functions
    program: str
    summary: str
    flags: Flag[]
    options: Option[]
    positionals: Positional[]
record Parsed:
    help: bool                      # -h or --help was given
    positionals: str[]
enum Error:
    UnknownOption(name: str)        # --nope, -q
    MissingValue(name: str)         # an option as the last word
    UnexpectedValue(name: str)      # --flag=1
    MissingPositional(name: str)
    UnexpectedPositional(value: str)
    NotAnInteger(name: str, value: str)
new(program: str, summary: str) -> Spec
add_flag(mut spec: Spec, name: str, short: str, help: str)
add_option(mut spec: Spec, name: str, short: str, value_name: str, help: str)
add_option_default(mut spec: Spec, name: str, short: str, value_name: str, help: str, fallback: str)
add_positional(mut spec: Spec, name: str, help: str)
add_optional_positional(mut spec: Spec, name: str, help: str)
add_rest(mut spec: Spec, name: str, help: str)
parse(spec: Spec, items: str[]) -> Parsed fails Error
has(parsed: Parsed, name: str) -> bool
get(parsed: Parsed, name: str) -> str?
get_all(parsed: Parsed, name: str) -> str[]
get_int(parsed: Parsed, name: str) -> int fails Error
message(error: Error) -> str
usage(spec: Spec) -> str
help_text(spec: Spec) -> str
```

- A flag is `--name` (and `-s` with a one-character short name). An option takes `--name VALUE`, `--name=VALUE`, `-s VALUE`, `-s=VALUE` or `-sVALUE`, and takes the next word whatever it looks like. Short flags cluster (`-jv`); an option ends a cluster by taking the rest. `--` ends the options; a lone `-` is a positional. Long options are not abbreviated.
- The last value of a repeated option wins in `get`; `get_all` keeps them all in order.
- `-h` and `--help` are always declared: they set `Parsed.help` and skip the missing-positional check. `help_text` prints the usage line, summary, positionals and options, aligned, ending in a newline.
- A mistake is the `Err` value, named by `message` (`unknown option --nope`); the tool prints it with the usage line and picks its exit status.

```selka
# doc: expect 53
import argparse

func main() -> int:
    mut spec = argparse.new("count", "Count things.")
    argparse.add_flag(mut spec, "loud", "l", "shout")
    argparse.add_option_default(mut spec, "times", "n", "N", "repeat", "2")
    argparse.add_positional(mut spec, "WORD", "what to count")
    match argparse.parse(spec, ["--loud", "-n", "5", "word"]):
        case Ok(parsed):
            match argparse.get_int(parsed, "times"):
                case Ok(times):
                    if argparse.has(parsed, "loud") and parsed.positionals[0] == "word":
                        return times * 10 + 3
                    return 1
                case Err(_):
                    return 2
        case Err(_):
            return 3
```

### Commands

A program like `tasks [--db PATH] COMMAND [ARGS]` has a `Commands` value. Options before the command word live in `program.global` (declare them with `add_flag` and `add_option` on `mut program.global`; a positional there is unused). Each command has a spec of its own, added with `add_command`, which copies it and renames its program to `tasks add`; the summary is the command's line in the help. `parse_command` reads the words before the first positional word (or the one after `--`) as the program's options, takes that word as the command, and reads the rest against its spec; the program's options may not follow it.

```text
# doc: not-selka
record Commands:                    # built with new_commands and add_command
    global: Spec                    # the options before the command word
    commands: Command[]
record Command:
    name: str
    spec: Spec                      # its program name reads "tasks add"
record Invocation:
    command: str                    # the command word; "" when the program's own help was asked for
    global: Parsed                  # the options before the word: has, get, get_all, get_int read it
    local: Parsed                   # the flags, options and positionals after it
enum CommandError:
    MissingCommand(known: str)      # no word; `known` lists the commands
    UnknownCommand(name: str, known: str)
    Failed(command: str, error: Error)   # the mistake of the command's arguments, or of the options before the word ("")
new_commands(program: str, summary: str) -> Commands
add_command(mut program: Commands, name: str, spec: Spec)
parse_command(program: Commands, items: str[]) -> Invocation fails CommandError
command_message(error: CommandError) -> str
command_of(error: CommandError) -> str
command_usage(program: Commands, command: str) -> str
command_help(program: Commands, command: str) -> str
```

A mistake carries its command: `command_message` says `unknown option --prio for command done` for an option another command has (or the program's own option after the word), and `command_of(error)` is that command, or "" when the mistake came before the word or no valid word came. `command_usage(program, command)` and `command_help(program, command)` give a command's usage line and help text (the program's for ""). `-h` before the word sets `invocation.global.help` (command ""), after it `invocation.local.help`; neither checks for a missing positional. A tool prints `command_help(program, invocation.command)` for either.

```selka
# doc: expect 23
import argparse

func main() -> int:
    mut program = argparse.new_commands("tasks", "A task tracker.")
    argparse.add_option_default(mut program.global, "db", "", "PATH", "the database file", "tasks.db")
    mut add = argparse.new("add", "Add a task.")
    argparse.add_option(mut add, "prio", "", "N", "priority 1 to 5")
    argparse.add_positional(mut add, "TITLE", "the title")
    argparse.add_command(mut program, "add", add)
    mut done = argparse.new("done", "Mark tasks done.")
    argparse.add_rest(mut done, "ID", "the tasks")
    argparse.add_command(mut program, "done", done)
    match argparse.parse_command(program, ["done", "--prio", "2"]):
        case Err(error):
            if argparse.command_message(error) != "unknown option --prio for command done":
                return 1
            if argparse.command_usage(program, argparse.command_of(error)) != "usage: tasks done [-h] [ID ...]":
                return 2
        case Ok(_):
            return 3
    match argparse.parse_command(program, ["--db", "t.db", "add", "Buy milk", "--prio", "2"]):
        case Ok(invocation):
            match argparse.get_int(invocation.local, "prio"):
                case Ok(prio):
                    if invocation.command == "add" and argparse.get(invocation.global, "db") == Some("t.db"):
                        return prio * 10 + 3
                    return 4
                case Err(_):
                    return 5
        case Err(_):
            return 6
```

## logging

`logging` writes a program's own messages: an event is a level, a message and typed fields, written as one line on a `Stream` the program holds (`logging.new(err)`). It reads no environment, opens no file and prints a time only when given a `Clock` whose wall time is granted (`--allow-clock` under `--restrict`); the level comes from text the program passes (`logging.parse_level`). The line format, quoting and escapes, JSON form and task rules are in [logging](logging.md) (`selka docs logging`).

```text
# doc: not-selka
enum Level:                     # in this order; a new logger shows info and above
    debug
    info
    warn
    error
record Field:                   # made by text, number, real and flag
    key: str
    value: json.Json
record Logger:                  # an ordinary record: copied, stored and passed like a Stream
    stream: Stream
    clock: Clock?
    level: Level
    name: str
    fields: Field[]
    json_lines: bool
record Event:                   # a plain value, which a task can build and return
    level: Level
    message: str
    fields: Field[]
new(stream: Stream) -> Logger
with_level(log: Logger, level: Level) -> Logger
with_clock(log: Logger, clock: Clock) -> Logger
named(log: Logger, name: str) -> Logger
with_field(log: Logger, field: Field) -> Logger
as_json(log: Logger) -> Logger
enabled(log: Logger, level: Level) -> bool
parse_level(wanted: str) -> Level?
text(key: str, value: str) -> Field
number(key: str, value: int) -> Field
real(key: str, value: float) -> Field
flag(key: str, value: bool) -> Field
debug(log: Logger, message: str, fields: Field[]? = None)      # info, warn and error are the same
event(level: Level, message: str, fields: Field[]? = None) -> Event
write(log: Logger, entry: Event)
```

- Each setting answers a changed copy. A level function does nothing when the logger does not show that level, but its arguments are built first, so `enabled` skips an expensive message.
- A line is `TIME LEVEL NAME: message key=value ...` (time only with a clock, name only when set), or one JSON object with `time`, `level`, `logger` and `message` first. An event is always one line: values and messages are quoted and escaped as needed.
- A failed write to standard error is ignored, one to standard output traps `R_OUTPUT` as `print` does, and a reader that has gone from either ends the program quietly with status 141 ([stream](io.md#stream)).
- A task cannot log (no capability): it returns an `Event` from `logging.event` and the caller writes it after the group with `logging.write`.

```selka
# doc: expect 2026-11-17T09:35:14Z WARN scan: slow ms=31 note="two words"
# doc: expect {"level":"error","message":"stop","code":3}
# doc: expect WARN checked path=/a
# doc: expect True False
import logging
import parallel
import time

func check(path: str) -> logging.Event:
    return logging.event(logging.Level.warn, "checked", [logging.text("path", path)])


func main(out: Stream) -> int:
    const clock = time.simulated_clock(time.from_unix_nanoseconds(1794908114000000000))
    const log = logging.named(logging.with_clock(logging.new(out), clock), "scan")
    logging.warn(log, "slow", [logging.number("ms", 31), logging.text("note", "two words")])
    const lines = logging.as_json(logging.new(out))
    logging.error(lines, "stop", [logging.number("code", 3)])
    const plain = logging.new(out)
    for entry in parallel.map(["/a"], check):
        logging.write(plain, entry)
    logging.debug(plain, "dropped")
    const wanted = logging.parse_level("warn") else:
        return 1
    print(out, logging.enabled(plain, logging.Level.info), logging.enabled(logging.with_level(plain, wanted), logging.Level.info))
    return 0
```

## flate

```text
# doc: not-selka
inflate(data: bytes, limit: int) -> Result[bytes, str]
zlib_decode(data: bytes, limit: int) -> Result[bytes, str]
gunzip(data: bytes, limit: int) -> Result[bytes, str]
inflater(limit: int) -> Inflater
zlib_inflater(limit: int) -> Inflater
gzip_inflater(limit: int) -> Inflater
feed(mut stream: Inflater, piece: bytes) -> Result[bytes, str]
ended(stream: Inflater) -> bool
finish(stream: Inflater) -> Result[Unit, str]
crc32(data: bytes) -> int
crc32_update(value: int, data: bytes) -> int
adler32(data: bytes) -> int
adler32_update(value: int, data: bytes) -> int
```

`flate` decompresses the DEFLATE family: `inflate(data, limit)` a raw stream (RFC 1951), `zlib_decode(data, limit)` zlib (RFC 1950), `gunzip(data, limit)` gzip (RFC 1952). Each returns the decompressed `bytes` or fails with a message saying what is wrong: truncation, a reserved block type, a stored block whose length and complement disagree, an over-subscribed or incomplete Huffman code, a distance before the start of the output, a checksum or size mismatch, or a result past `limit`. `limit` is the most bytes the result may reach, so a few bytes cannot claim gigabytes: pass what you can afford. There is no compressor.

- `zlib_decode` checks the header and the Adler-32 and refuses a preset dictionary.
- `gunzip` skips each member's optional name, comment, extra field and header check, checks its CRC-32 and size, joins several members and ignores zero bytes after the last; other trailing data is refused.
- `crc32` and `adler32` answer the zlib checksums as integers from 0 below 2^32.

```selka
# doc: expect 23 2369606115 b'hello hello hello hello'
import flate

func main(out: Stream) -> int:
    const packed = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\xcbH\xcd\xc9\xc9W\xc8@'\x01\xe3Q=\x8d\x17\x00\x00\x00"
    match flate.gunzip(packed, 1048576):
        case Ok(plain):
            print(out, len(plain), flate.crc32(plain), plain)
        case Err(message):
            print(out, message)
    return 0
```

### Inflating in pieces

The one-shot functions hold the whole result in memory. An inflater takes compressed bytes a piece at a time and keeps only the 32 KiB window of the last output and what one piece needs.

- `inflater(limit)` starts a raw stream, `zlib_inflater(limit)` zlib, `gzip_inflater(limit)` gzip (one member or several, each CRC-32 and size checked). The `Inflater` is a value: pass it with `mut`. `limit` is the most plain bytes the stream may produce; `9223372036854775807` means none.
- `feed(mut stream, piece)` answers the plain bytes ready so far, possibly none. A piece may end anywhere and be any size. A call answers about a mebibyte at most: when it answers something, `feed` again with `b""` until it answers nothing, then read the next piece. A failed stream fails again with the same message; malformed input or a result past `limit` fails with the one-shot message.
- When all input is fed, `ended(stream)` says whether the stream ended cleanly (raw or zlib through its last block and, for zlib, its Adler-32; gzip at the end of a member, or empty) and `finish(stream)` fails saying where it stopped: `unexpected end of the compressed data`, `the gzip header is cut short`, `the gzip member is cut short`, `the zlib stream has the wrong length`. Trailing data is refused: after a raw or zlib stream, or after a gzip member when what follows zero bytes is not zero.
- `crc32_update(value, data)` and `adler32_update(value, data)` extend a checksum: `crc32(a + b)` is `crc32_update(crc32(a), b)`, whatever the cut. The value for no bytes is 0 (CRC-32) and 1 (Adler-32).

```selka
# doc: expect 23 2369606115 b'hello hello hello hello'
import buffers
import filesystem
import flate

# The plain bytes of the gzip file at `path`, read 8 bytes at a time.
func inflate_file(fs: Filesystem, path: str) -> bytes fails str:
    mut stream = flate.gzip_inflater(1048576)
    mut plain = buffers.empty()
    with try fs.open(path, "rb") as f:
        mut piece = f.read(8)
        while len(piece) > 0:
            mut out = try flate.feed(mut stream, piece)
            while len(out) > 0:
                buffers.append(mut plain, out)
                out = try flate.feed(mut stream, b"")
            piece = f.read(8)
    try flate.finish(stream)
    return bytes(plain)


func main(out: Stream) -> int:
    mut fs = filesystem.memory()
    const packed = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\xcbH\xcd\xc9\xc9W\xc8@'\x01\xe3Q=\x8d\x17\x00\x00\x00"
    _ = fs.write_file("hello.gz", packed)
    match inflate_file(fs, "hello.gz"):
        case Ok(plain):
            print(out, len(plain), flate.crc32(plain), plain)
        case Err(message):
            print(out, message)
    return 0
```

## cache_record

`cache_record.encode(fields: str[]) -> bytes` writes canonical string-array JSON in a versioned SHA-256 envelope. `decode(data)` answers `Result[str[], Error]`; `message(error)` explains a rejected record. Truncated, altered, noncanonical and nonstring records are rejected. The checksum detects damage; it does not authenticate an untrusted writer, so bound storage reads before decoding.

```selka
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

`persistent_memo.call(fs, options, compute, key)` answers `Result[Lookup, Error]`; `Lookup` holds `value: bytes` and `reused: bool`. The callback takes `memo.Key`, permits only managed allocation and returns an immutable byte snapshot. `message(error)` describes a failure.

- Pass a filesystem narrowed to an existing dedicated cache directory (a real narrowed `Filesystem` and a positive entry limit persist; a stand-in with a zero limit does not).
- `Options(max_entries, max_bytes)` takes 0 to 256 entries and 0 to 1,048,576 raw bytes of key plus value per entry. Zero entries executes without storage. An oversized value, or a callback without a qualified `function_digest`, executes without retaining a receipt. Tags distinguish text, bytes and integer keys.
- A malformed record is a miss; provider failures remain errors. Lowered entry limits trim the directory deterministically. Retention is bounded by entry count and per-entry size; there is no TTL or file-freshness rule.

```selka
# doc: expect 42
import filesystem
import memo
import persistent_memo
import strings

func encoded(key: memo.Key) -> bytes:
    match key:
        case Number(value=value):
            return strings.encode(str(value))
        case Text(value=value):
            return strings.encode(value)
        case Data(value=value):
            return copy(value)

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

## durable

`durable.run(fs, request, compute)` answers `Result[Report, Error]`. A pure `func(bytes, bytes) -> durable.Step` receives one captured chunk and the last state snapshot; `Step(output, state)` returns bytes. `Request(input, chunks, initial_state, output_path, max_bytes)` captures the inputs; `Report(fresh, reused, output_digest, state)` counts newly computed and already committed steps separately; `message(error)` describes invalid, corrupt, incompatible, uncacheable and provider failures.

```selka
# doc: expect 42
import durable
import filesystem

func copy_chunk(chunk: bytes, state: bytes) -> durable.Step:
    return durable.Step(output=copy(chunk), state=copy(state))

func main() -> int:
    # Reserved output names are rejected before any storage operation.
    const request = durable.Request(input=b"a\n", chunks=[b"a\n"], initial_state=b"", output_path="run.json", max_bytes=1024)
    if durable.run(filesystem.memory(), request, copy_chunk) == Err(durable.Error.Invalid):
        return 42
    return 1
```

- A real run needs an existing dedicated native directory (`fs.dir("durable")`) and an ordinary output filename (`final.csv`). To make creating the directory survive a crash, create it and synchronize its parent first.
- Limits: at most 1,024 chunks, and a chosen 1 to 8 MiB for input, total chunk bytes, total output and each state snapshot. The output filename cannot escape the directory or collide with `run.json`, `chunk-` artifacts or `.myl-durable-` temporary files.
- Changed input, implementation, schemas, output name or limits rejects the old journal. Corrupt committed evidence fails closed: keep it for diagnosis or start a new directory. Committed progress is kept; uncommitted artifacts and abandoned temporary files are collected.
- Final output is published atomically from committed bytes. A failed directory sync may mean it was published: the call errors, and retrying the same request checks or republishes the intended bytes. A second recoverer gets a busy error while the first owns the directory (released on exit or process death).
- Process-crash recovery is qualified by real termination at publication boundaries; power-loss behavior is not established. Network requests, external database transactions and arbitrary effects are not replayed.

## testing

`testing` measures the work a test does, not its duration.

- `steps(work, n)` runs `work(n)`, a `func(int) -> int`, and answers the blocks executed (what the step ceiling charges).
- `allocations(work, n)` answers the managed blocks allocated, the `allocs` of `--counters`; `allocations_writing(work, out, n)` does the same for a workload that needs a `Stream`.
- `growth(work, small, large)` runs both sizes and answers the larger of the two counts' growth ratios, unjudged.
- `linear(work, small, large)` fails when a count grows by more than 1.5 times the step from `small` to `large` (1,000 to 4,000: limit 6, so `n log n`, about 4.8, passes and a quadratic one, 16, fails; a count that is zero at both sizes passes). `constant(work, small, large)` allows 1.5 times plus two counts. A failure names the counter, both values and the ratio.

Both sizes run inside the test's budget, so a large quadratic shape needs `limits.test.max_steps` in `selka.json` ([work per test](tooling/guest-tests.md#work-per-test)). With no step accounting (a built binary, or `selka run` without `--max-steps`) a check that reads the counters traps `R_NO_STEP_ACCOUNTING`; `selka test` always counts, even under `--max-steps 0`.

```selka
# doc: expect 42
import testing


# Builds a list of n values and answers its length.
func build(n: int) -> int:
    mut values: int[] = []
    for i in range(n):
        append(mut values, i)
    return len(values)


# The append loop's work grows with n, so it passes at a 4x step.
@test
func build_grows_linearly() -> bool:
    return testing.linear(build, 1000, 4000)


func main() -> int:
    return 42
```

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/standard-library.md).
