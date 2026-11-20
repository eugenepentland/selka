# Standard library

Forty-two modules ship inside the compiler. They are ordinary guest source
built on the managed types described in the [language guide](python-syntax.md),
[managed memory](managed-memory.md) and [managed byte strings](bytes.md): growable arrays (`T[]`),
`dict`, `str`, `bytes`, value records, optional values (`T?`) and checked results. There is no
allocator to thread and no storage tier to choose.

### Functions the compiler supplies

A hundred and twenty-three of the library's functions are declared `builtin func`: a signature
and its documentation comment with no body, because the compiler supplies every call. They
are the list, dictionary, set, text, bytes and buffer operations that were methods once
(`lists.pop`, `dicts.get`, `strings.upper`, `strings.strip`, `lists.exchange`), the function homes of the methods text,
bytes, a byte buffer and a set still answer (`strings.strip_chars`, `bytes.index`,
`sets.update`: each is its method's own operation, so a program that moves from the method
to the function runs the same code), the nine `simd` lane operations, the
`parallel.map` family, the scalar text helpers (`strings.char_count`, `strings.chars`,
`lists.stride`) and two private `testing` counters. A call is the operation however it
is spelled: the module's name, an import alias (`import strings as s`), another module's
re-export (`export strings.upper`), keyword arguments or explicit type arguments. A
`strings`, `bytes` or `buffers` operation is also a function value, which runs the same
operation; a `simd` operation or a scalar text helper is not one
(`E_BUILTIN_FUNCTION_VALUE`): call it directly, or pass a named function that calls it.
`selka list-interfaces` lists each one as `export builtin function`. Only the
library declares a `builtin func`; in a program's own module it is refused
(`E_BUILTIN_DECLARATION`). The library's own sources call these functions as a program
does: they are written in the function forms and are refused a method form or a second spelling
(`E_METHOD_REMOVED`, `E_REMOVED_SPELLING`) like any program, with no waiver: the bounded search that
`strings.find` and `strings.rfind` convert to `int?` is the library's own private home
(`find_offset`, `rfind_offset`), not a method.

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

Import a module by name; projects do not copy these files. While developing a
replacement, `--local-stdlib` on `run`, `build`, `check` or `test` prefers a file
beside the entry over the embedded copy; without it, an imported local
standard-named file is ignored (`check`, `build`, `run` and `test` print a warning that names it, and the refusal of a name
only that file declares, `module `options` declares no `Options``, says that `options` is the standard module and the file is
not used: rename it). A standard-named file
named directly as the `check` entry is always checked from its path, so
`selka check csv.selka` checks the file even without the switch.

| Module | Covers |
| --- | --- |
| [`lists`](#lists) | filling, linear membership and optional last elements |
| [`math`](#math) | binary64 classification, rounding, roots, powers, integer extrema and divisors |
| [`strings`](#strings) | the text operations `str` itself does not provide |
| [`dicts`](#dicts) | the dictionary probes `dict` itself does not provide |
| [`options`](#options) | taking an owned option's payload or a default without a copy |
| [`buffers`](#buffers) | the in-place writes of a `byte_buffer` |
| [`sets`](#sets) | the fourteen operations on `set[T]` |
| [`bytes`](#bytes) | the operations specific to byte strings |
| [`sort`](#sort) | stable ordering, binary search, extrema and duplicate removal |
| [`parallel`](#parallel) | ordered, synchronous mapping with scoped workers |
| [`path`](#path) | pure POSIX-style path text algebra |
| [`hex`](#hex) | hexadecimal text for byte strings |
| [`base64`](#base64) | RFC 4648 standard and URL-safe transcoding |
| [`csv`](#csv) | RFC 4180 parsing and rendering with header tables |
| [`http`](#http) | pure HTTP/1.0 and HTTP/1.1 request and response parsing and rendering |
| [`byte_builder`](#byte_builder) | incremental binary and UTF-8 output assembly |
| [`byte_format`](#byte_format) | Zig's `{d}` and `{d:.N}` float text and a number-and-text template for byte builders |
| [`json`](#json) | strict RFC 8259 parsing, rendering and typed access |
| [`pool`](#pool) | generational handles into a reusable slot store |
| [`spans`](#spans) | text kept in a long-lived table of files, named by file, start and length |
| [`symbols`](#symbols) | names interned once, with an integer key that stands for each |
| [`memo`](#memo) | bounded, process-local reuse of pure computations |
| [`hashes`](#hashes) | block-based SHA-256 in Selka; BLAKE3 digests and the `Digest` value |
| [`binary`](#binary) | little-endian integers, LEB128 varints and length-prefixed fields over the byte builders |
| [`process`](#process) | running a program with the `Process` capability and capturing its output |
| [`argparse`](#argparse) | command-line parsing for Selka tools: flags, options, positionals, generated help, errors as values |
| [`logging`](#logging) | leveled, typed events written one to a line on a stream the program holds, as text or JSON |
| [`flate`](#flate) | decompression of raw DEFLATE, zlib and gzip data, whole or in pieces, with CRC-32 and Adler-32 |
| [`cache_record`](#cache_record) | canonical string-array storage records with integrity checks |
| [`persistent_memo`](#persistent_memo) | verified cross-process byte snapshots of pure computations |
| [`durable`](#durable) | retained chunk progress and recoverable atomic output publication |
| [`network`](#network) | capability-based connections, listeners and byte I/O, a denied stand-in `Network` and an in-memory one |
| [`random`](#random) | seeded SplitMix64 streams, entropy-seeded generators, and a seeded and a failing stand-in `Entropy` |
| [`time`](#time) | wall-clock instants, checked durations, and a simulated and a failing `Clock` |
| [`filesystem`](#filesystem) | an empty in-memory stand-in `Filesystem` |
| [`environment`](#environment) | a stand-in `Environment` holding fixed pairs |
| [`testing`](#testing) | executed blocks and managed allocations, the growth of a test's work |

`time.simulated_clock`, `time.failing_clock`, `random.seeded_entropy`, `random.failing_entropy`, `filesystem.memory`,
`environment.fixed`, `network.denied` and `network.memory` build deterministic stand-ins for the
capabilities a program is otherwise handed by its entry point. Building one needs
no capability, and a stand-in never reaches a host resource,
so code that takes a `Clock` or a `Filesystem` can be tested by passing one; see
[deterministic stand-ins](effects.md#deterministic-stand-ins) and
[capability parameters in tests](tooling/guest-tests.md#capability-parameters).

Managed-value modules report conversion failures using checked results or optional values.
The byte builder's checked append operations return a success flag. The network
module uses the resource-result types documented below.

## buffers

`byte_buffer` is the growable octet sequence; `buffers` holds its writes, each taking
the buffer first with the call-site `mut` marker. `buffers.empty()` creates one.
`buffers.append_byte(mut data, value)` appends one octet and answers whether it did:
`value` must be in `0..255`, and any other value appends nothing and answers `False`.
`buffers.append_range(mut data, piece, start, end)` appends a window of a byte string
and answers whether the range was valid (`start <= end <= len(piece)`; a negative
`start` or `end` traps `R_LIST_BOUNDS`). `buffers.reserve(mut data, extra)` makes room for `extra` more octets
without writing any, and answers `False` for a negative request. Those three answers
are discarded with `_ =` when they are not used. `buffers.append(mut data, piece)`
appends a byte string's octets, `buffers.append_utf8(mut data, text)` appends a text's
UTF-8 octets, and `buffers.append_int`/`buffers.append_float` append the **decimal
text** of a number (`1.5` is three octets), not a binary encoding. These four always
write and answer nothing, so they are plain statements.
`buffers.clear(mut data)` empties the buffer and keeps its storage: the length is 0 and the capacity is what it was,
so the next appends write into room that is already there. A loop that fills one buffer, writes it with
`write(out, data)` and clears it allocates for the first fill only (1,000 fills allocate what 10 do), where a
`buffers.empty()` per fill allocates for each; `clear` answers nothing and is a plain statement. A `byte_builder`
is emptied the same way through its field, `buffers.clear(mut builder.buffer)`.
The prelude's `copy(data)` answers independent storage. Reading a buffer's octets is the
prelude's `bytes(value)`, and `len(data)` is its octet count.

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

Byte strings are immutable octets, and `bytes` holds the operations specific to them,
each taking the byte string first. `starts_with`, `ends_with`, `count`, `find` and
`rfind` search (`find`/`rfind` answer octet offsets and `-1` when absent, the method's
own convention until stage 2b settles one `find`); `split` and `join` partition and
assemble, and `replace(data, old, new)` replaces every non-overlapping occurrence of `old` as `strings.replace` does; `strip`, `lstrip` and `rstrip` trim whitespace; and the window words read a
range without copying: `parse_int_range(data, start, end)` and
`parse_float_range(...)` answer an option, and `scalar_count_range(...)` answers the
Unicode scalar count of a UTF-8 window or `Err` when the window is not valid UTF-8.
The fixed-width reads `read_u16_be(data, offset)`, `read_u16_le`, `read_u32_be`,
`read_u32_le`, `read_u64_be`, `read_u64_le`, `read_i16_be`, `read_i16_le`, `read_i32_be`,
`read_i32_le`, `read_i64_be` and `read_i64_le` answer one integer of that width at
`offset`, `read_u8` and `read_i8` answer the single octet at `offset` as an inline load (what
`data[offset]` makes through a runtime call), and `read_f32_le` and `read_f64_le` answer one
little-endian float; an offset whose octets are not all inside `data` traps
([`bytes`](bytes.md#fixed-width-reads)).
`len(data)` is the octet count, and `bytes(values)` builds a byte string from an
`int[]` or a `byte_buffer`. `fromhex(text)` decodes even-length hexadecimal text, the
type's own `bytes.fromhex(text)`, which a file that imports this module reaches through
it. The writes for a growable buffer live in
[`buffers`](#buffers).

The searches take optional bounds: `find(data, needle, start, end)` and the same `start`
and `end` on `rfind`, `count`, `starts_with`, `ends_with`, `index` and `rindex` read the
octets in `[start, end)` and still answer offsets from the first octet (an `end` past the
length is the length; a negative bound traps `R_TEXT_BOUNDS`). `index` and `rindex` are
`find` and `rfind` that trap `R_SUBSTRING_NOT_FOUND` instead of answering `-1`, and the
empty needle counts `len(data) + 1` times. `words(data)` splits at runs of the six ASCII
whitespace octets; `strip_chars(data, characters)`, `lstrip_chars` and `rstrip_chars` trim
the octets a set holds; `parse_int(data)` and `parse_float(data)` read the whole data as a
number (an option; `parse_int` takes a leading `+`, surrounding whitespace and leading zeros, so a strict parser
checks first: [what it accepts](bytes.md#counting-characters-and-parsing-numbers)); `scalar_count(data)` counts UTF-8 scalars (`Err` for invalid UTF-8);
`to_list(data)` answers the octets as integers; and `find_any(data, octets, start)` answers
the first offset at or after `start` holding any octet of a set, or `-1` (`find_any(data, octets, start, end)` reads
only `[start, end)`, as `find` does).

**A buffer where `bytes` is read.** The searches, splits, trims and number parses of this
module (`find`, `count`, `starts_with`, `split`, `strip`, `words`, `parse_int`, `to_list`,
`find_any`, the `_range` forms and the others), `strings.decode`, `hex.encode`,
`hashes.sha256_bytes` and `hashes.blake3_bytes` also take a `byte_buffer`: the buffer lends
its octets for the call, with no copy, and the call is the buffer's own method
(`bytes.find(buf, x)` is `buf.find(x)`), so it answers what that method answers (a trimmed
or split buffer is a buffer). No write to the buffer can happen during the call: the
operation reads it in place, and no operand of a read is `mut`. Only `bytes` is taken by
`bytes.replace` and by the fixed-width reads (`read_u8` to `read_f64_le`, above): a
`byte_buffer` there is `E_TYPE`. Read one word of a buffer with `bytes(buf[i:i + 8])`, a
copy of those eight octets alone, or hold the octets as `bytes`
([a buffer does not take these reads](bytes.md#a-byte_buffer-does-not-take-these-reads)).

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

```selka
# doc: expect b'a-b'
# doc: expect 1
import bytes

func main(out: Stream) -> int:
    const parts = bytes.split(b"a,b", b",")
    print(out, bytes.join(parts, b"-"))
    print(out, bytes.count(b"a,b", b","))
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

`byte_builder` assembles an immutable byte string in one mutable `byte_buffer`
([in-place octet methods](bytes.md#writing-octets-in-place)) whose backing
storage grows by doubling, so `append`, `append_range`, `append_byte`,
`append_spaces`, `append_text`, `append_int` and `append_float` write each
fragment's octets straight into that capacity and no fragment allocates a value
for itself: `append_text` builds no temporary encoded `bytes`, and `append_int`
and `append_float` no temporary text or byte value at all. `append_float` writes
the canonical spelling `str(value)` prints, built on the runtime's own stack. `finish` publishes the buffer as an immutable snapshot
with `bytes(buffer)`, which copies the current octets into independent owned
storage. `finish` may allocate but does not mutate the builder;
when the assembled octets are only going to a stream,
`write(out, builder.buffer)` writes the buffer's own storage instead and skips
that copy.

The number of octets assembled so far is `len(builder.buffer)`. `len(builder)` is `E_TYPE`
(`operation requires a fixed array value`), because a `Builder` is a record around its buffer and not a sequence;
`len(byte_builder.finish(builder))` gives the same count but copies the octets first.

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

`append_array` and `append_array_range` copy octets out of a fixed `u8` array of
any length `N` in one step. They are how a `network.Read[N]` chunk reaches a
builder: `byte_builder.append_array(mut raw, chunk.bytes, int(chunk.length))`
appends the filled part of the chunk with one copy, where a loop of
`append_byte` calls pays one call per octet. They refuse and trap exactly as
`append_range` does for the range `array[0:count]` or `array[start:end]`.

The checked appends refuse invalid nonnegative requests before writing
anything, so a refused call leaves the builder byte-for-byte unchanged.
`append_range` refuses nonnegative endpoints whose `end` is below `start` or past
`len(data)`; an empty range succeeds and changes nothing. A constant negative
endpoint reports `E_NEGATIVE_INDEX_REMOVED`; a computed negative endpoint traps
`R_LIST_BOUNDS`.

`append_byte` rejects values outside `0..255`, `append_spaces` rejects negative
counts and `reserve` rejects a negative count. A rejection answers `False`; a
no-op success such as `reserve(0)` answers `True` and changes nothing.
`append_int` writes its digits through a small fixed local buffer, so it builds
no managed intermediate value at all. `reserve` grows the buffer's
capacity for a further `extra` octets without changing the finished length.

`finish` returns an immutable snapshot. The builder remains usable, and later
appends — including an append of a snapshot back into its own builder — do not
change earlier results. Mutating operations modify only their builder argument.

```selka
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

Output that Zig writes with `w.print("<rect x=\"{d:.1}\" y=\"{d:.1}\"/>", .{ x, y })` is one call here too, onto a
[`byte_builder`](#byte_builder). `byte_format.shortest(mut builder, x)` is Zig's `{d}` of a float: the shortest digits that
round-trip, never scientific, with no `.0` after a whole number (`100.0` is `100`, `-0.0` is `-0`; `byte_builder.append_float`
keeps the `.0`). `byte_format.decimal(mut builder, x, decimals)` is Zig's `{d:.N}`: `decimals` digits from the shortest digits,
rounded half up, so `6.475` at two decimals is `6.48` (`strings.format_float` and an f-string round the exact binary value and
print `6.47`); it answers `False` and appends nothing for `decimals` outside 0 to 17. Both agree with the pinned Zig toolchain's
output on a captured set of 294 values at 0, 1, 2, 3 and 6 decimals (`tests/lang/byte_format_templates.selka`).

`byte_format.format(mut builder, template, numbers)` writes a template whose placeholders take the numbers in order: `{d}` is
`shortest`, `{d:.N}` is `decimal`, and `{{` and `}}` write a brace. `format1`, `format2` and `format3` add one, two or three texts,
which `{s}` takes in order and writes as they are, with no copy: the texts are ordinary borrowed `bytes` arguments, not list
elements (a list of borrowed `bytes` needs a `copy` for each). An integer travels as `float(n)` and prints whole up to 2^53. A
template that does not fit its arguments (an unknown placeholder, an unclosed or lone brace, too few or too many numbers or texts)
is a mistake in the program, not in its input, and traps `R_ASSERT` naming the octet and the reason. A run of literal and number
appends is a template:

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

The signatures show the float four-lane form; the compiler checks each call against the
`Simd` type its operands and context give, for any float or f32 lanes and 2, 4, 8 or 16 lanes.
`splat` and `load` take their lane count from the expected type. See [SIMD](simd.md).

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

`sqrt`, `trunc`, `floor`, `ceil`, `round`, `min`, `max` and `abs` are bare names of the prelude, listed here
because they are numeric: `math.floor`, `math.round`, `math.sqrt` and the others of the first group are refused
with `E_REMOVED_SPELLING`, and `selka fix` rewrites them. Everything below the second heading needs `import math`
and the `math.` prefix. 
`pi` and `e` are functions, so write `math.pi()` and `math.e()`. `bits` and
`f32_bits` answer the IEEE bit pattern of a value, every NaN as the canonical quiet
NaN, and `from_bits` and `f32_from_bits` build the value a pattern names
([bit patterns](floating-point.md#bit-patterns)). `fma` and `f32_fma` round `a * b + c`
once, and `hypot` and `f32_hypot` answer Zig's `std.math.hypot` bits
([fused multiply-add and hypot](floating-point.md#fused-multiply-add-and-hypot)). `log10`, `exp`, `atan2` and `pow_float`
(float exponent; `pow` takes an integer one) and their `f32_` forms answer the bits of Zig's `std.math.log10`, `exp`,
`atan2` and `pow` ([Zig-exact functions](floating-point.md#zig-exact-log10-exp-atan2-and-pow_float)); `ln`, `atan`, `acos`,
`asin`, `tan`, `expm1`, `sinh`, `cosh`, `tanh`, `cbrt`, `sin` and `cos` answer the bits of Zig's `@log`, `std.math.atan`, `acos`,
`asin`, `@tan`, `std.math.expm1`, `sinh`, `cosh`, `tanh`, `cbrt`, `@sin` and `@cos`
([Zig-exact ln, trigonometry and hyperbolics](floating-point.md#zig-exact-ln-atan-acos-asin-tan-expm1-sinh-cosh-tanh-cbrt-sin-and-cos)). A module constant
of your own may be a `float` as well as an integer or a `bool`
([float constants](module-constants.md#float-constants)). `gcd`, `lcm` and
`isqrt` return a `Result` because `-9223372036854775808` has no positive counterpart and
a least common multiple can leave the signed range; the bare `abs` traps `R_OVERFLOW` on
that value instead.

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

`int(value)` of a float that does not fit traps `R_FLOAT_CONVERSION`, and two functions convert without that trap.
`to_int(value)` answers `Some` of what `int(value)` gives and `None` where it would trap: not-a-number, an infinity, a
value from 2^63 up or below -2^63. `to_int_saturating(value)` always answers an integer: 9223372036854775807 from 2^63 up and
for +infinity, -9223372036854775808 below -2^63 and for -infinity, `0` for not-a-number (as Rust's `as` and Go's saturating
forms do), and `int(value)` for everything else. `int(value)` itself keeps its trap, and `i8` to `u64` keep theirs
([integer conversions](floating-point.md#integer-conversions)).

```selka
# doc: expect 9223372036854775807 -9223372036854775808 0 None Some(41)
import math

func main(out: Stream) -> int:
    print(out, math.to_int_saturating(1e30), math.to_int_saturating(0.0 - 1e30), math.to_int_saturating(math.nan()), math.to_int(1e30), math.to_int(41.9))
    return 0
```

`sqrt` calls the internal binary64 square-root helper on its ordinary `float` argument,
so it is the correctly rounded square root. `pow` takes an integer exponent and
squares repeatedly; magnitudes above 4096 saturate to a same-parity magnitude,
which preserves the sign and the overflow or underflow outcome.

`sin`, `cos` and `tan` take angles in radians and are Zig's own routines (`@sin`, `@cos` and `@tan`),
including range reduction for large finite angles, so a program ported from Zig prints the same bytes. Sine preserves
negative zero; cosine of either zero is one. Infinite angles and not-a-number produce not-a-number. These are pure
operations and require no `Host` capability.

```selka
# doc: expect 0.0 1.0
import math

func main(out: Stream) -> int:
    print(out, math.sin(0.0), math.cos(0.0))
    return 0
```

## lists

`lists.filled(count, value)` creates independent copies, returning an empty list
when `count <= 0`. `lists.contains(values, value)` scans for an equal element;
`lists.index_of(values, value)` answers the position of the first equal element and
`lists.remove(mut values, value)` takes it out, both trapping when no element is
equal (the reading the retired `index`/`remove` methods had); `lists.last(values)`
returns the last element or `None` for an empty list.

The list's own writes take the list first and carry the `mut` marker at the call
site: `lists.exchange(mut values, index, own replacement)` replaces an element and
answers the former value, `lists.extend(mut values, other)` copies another list's
elements to the end and `lists.extend_own(mut values, own other)` moves them there, in
order, copying none and freeing the emptied `other`, `lists.insert(mut values, index, value)` clamps a position past
the end to the length, `lists.pop(mut values)` and `lists.pop_at(mut values, index)`
remove and answer one element, and `lists.clear(mut values)` removes every element.
Neither copies the element it takes out: `lists.pop_at` moves the later elements down
one place. `lists.exchange` copies nothing either: its replacement moves in, so a named
value is given with `own` (a fresh value or `copy(value)` takes no marker). It is the
list's own exchange, so it takes an index of any integer type and any element, a
resource or a `Result` included (`lists.exchange(mut results, 1, Ok(5))`). Before
25 October it took a borrowed replacement and copied it; `selka fix` migrates such a
call to `own` at the value's last use and to `copy(value)` everywhere else.
The prelude's `copy(values)` returns independent storage with each managed child copied too.
The in-place order is the prelude's `sort(mut values)` and the copy in reverse is the
prelude's `reversed(values)`, so no list word repeats those names; `lists.reverse(mut
values)` is the in-place reversal those two do not provide.

```selka
# doc: expect 5
import lists

func main() -> int:
    mut rows = [[1], [2, 3]]
    const more = [[4], [5, 6]]
    lists.extend_own(mut rows, own more)
    return len(rows) + rows[3][1] - 5
```

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

The dictionary probes answer the two questions a caller otherwise spells as a
membership test plus a second index. `dicts.find(mapping, key)` returns the value
stored under `key`, or `None` when the mapping has no entry for it. A managed value
comes back as an independent copy: the generic body must also accept a directly recursive
record (`next: Node?`), and the checker does not lend those, so the copy stays until it does.
`dicts.get` declares `from mapping, fallback`: its result may borrow either input.
`dicts.setdefault` declares `from mapping`: its result borrows the stored entry. `dicts.add(mut mapping, key, delta)` adds
an integer to the entry under `key`, starting from zero. `dicts.append_to(mut
mapping, key, own item)` appends to the list stored under `key`, starting a list
with `item`. Both read the `key` (a name, field or element) and copy it only when the
mapping has no entry for it, so a call that finds its key allocates nothing; `append_to` takes
the `item` `own`, so a named binding the caller owns is given away and a borrowed name is copied at the call, and
`dicts.setdefault(mut mapping, key, fallback)` answers the stored value or
stores the fallback and answers that (it reads a `key` written as a name, field or element and copies it only when
the mapping has no entry for it), and `dicts.update(mut mapping, other)` copies
every entry of another mapping in, replacing the keys it already holds. `dicts.add`
and `dicts.setdefault` probe once, `dicts.append_to` grows the stored list in place
(two probes, linear in the number of appends), and the mapping keeps owning its
storage.

The other dictionary operations are homes too: `dicts.get(mapping, key, fallback)`
answers the stored value or `fallback`; `dicts.pop(mut mapping, key)` removes the entry
and answers its value, trapping when it is absent, and `dicts.pop_default(mut mapping,
key, fallback)` answers `fallback` instead; `dicts.clear(mut mapping)` removes every
entry. The views `dicts.keys(mapping)`, `dicts.values(mapping)` and `dicts.items(mapping)`
are ephemeral: use one in a direct loop or an immediate `len`, `in`, `list`, `set` or
`sorted`, and write `list(dicts.values(mapping))` for an independent snapshot.

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

`value.unwrap_or(default)` reads: it borrows the option and the default, so keeping
the result means a `copy(...)`, except when the option is a call's result that lends
nothing and the default is a value of its own: `maybe().unwrap_or("")` gives an owned
value wherever a value is taken ([R6](ownership-rules.md#r6--borrowed-selections)).
`take_or` consumes both instead (`match own`): the
payload of an owned option, or the owned default when it is `None`, is the result
without a copy, and the other value is dropped. Pass an option of scalars without
`own`; it has no storage to give.

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

`MAX` stands for the largest `int`, 9223372036854775807: an `end` at or past the length
reads to the end of the text. The bounds are the ranged methods' (`text.find(needle,
start, end)`): the searches read the octets in `[start, end)` and answer offsets counted
from the text's start; a negative bound traps `R_TEXT_BOUNDS` and one inside a multi-byte
character traps `R_TEXT_BOUNDARY`. `strings.count` of the empty needle answers
`len(text) + 1`, the boundaries between octets, as Python's `count` does.
`strip_chars(text, characters)` and its `lstrip_chars` and `rstrip_chars` trim the octets
that `characters` holds and answer a new text (`strip` trims whitespace and lends a view);
`zfill(text, width)` pads with `0` after a leading sign, as Python's `zfill` does.

```selka
# doc: expect 2
# doc: expect 5
# doc: expect 4
# doc: expect hi
# doc: expect -0042
# doc: expect ['a', 'b', 'c']
import strings

func main(out: Stream) -> int:
    print(out, strings.count("abcabc", "c", 0, 6) + strings.count("abc", "z"))
    print(out, strings.text_index("abcabc", "c", 3))
    print(out, strings.count("abc", ""))
    print(out, strings.strip_chars("xxhixx", "x"))
    print(out, strings.zfill("-42", 5))
    print(out, strings.words("a\x0bb\x0cc"))
    return 0
```

`strip`, `lstrip` and `rstrip` declare `from text` and return slices of their
input without copying. Bind the result with `const` or read it in place; write
`copy(...)` when independent storage is needed.

`strings.repeat` returns empty text for a nonpositive count. `strings.encode` is the
UTF-8 encoding of a `str`, which cannot fail; `strings.decode` is the other direction
and answers `Err("invalid UTF-8 in byte string")` for bytes that are not valid UTF-8.
`strings.find_any(text, needles)` answers the earliest scalar position any of the
needles occupies, or `None` when none is present, as a byte offset — one position
convention for the module: `strings.find`, `strings.rfind` and `strings.find_any`
answer byte offsets in an `int?`, and the scalar readings are the compiler's
`strings.char_find`, `char_rfind` and `char_index`. When the needle's absence is
an error rather than a branch, `strings.text_index` and `strings.text_rindex`
answer the same byte offsets and trap `R_SUBSTRING_NOT_FOUND`; the names are the
compiler's `text_index` kind, because a bare `index` would be shadowed by the
loop counter every module writes. `strings.split` keeps
every piece of a partitioned text, `strings.replace` replaces every occurrence and
traps on an empty needle (the checked form is `substitute`), and `strings.rfind`
answers the last occurrence with the same option and byte-offset convention as
`find`. `strings.words`
splits on runs of whitespace, as Python's `split()` with no separator does: no
empty piece comes back, and leading or trailing whitespace adds nothing. The whitespace
is the six ASCII octets space, tab, line feed, vertical tab, form feed and carriage return.
`strings.words` and `strings.join` are the native operations of the refused methods `text.split()` and
`separator.join(parts)`. The
matching `str` method is `split(separator)`, which needs its separator; write
`strings.words(text)` when the words are what the program wants.

`strings.Builder` is the text counterpart of `byte_builder`: it owns a
`byte_buffer`, `append` writes a borrowed piece into the buffer's spare
capacity, and `finish` copies the accumulated text once into an independent
`str`. Only text can enter the builder, so `finish` is infallible and a finished
snapshot is always valid UTF-8. The builder remains usable after `finish`, and a
later append does not change an earlier snapshot. The exported record type is
`strings.Builder`; `strings.builder()` returns one, and
`mut field = strings.builder()` infers the type, so no annotation is needed. Use
it when a parser has to assemble a field from pieces; a contiguous field needs
only a slice.

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

`str` provides `+`, `==`, `in`, indexing, slicing and iteration; its operations are this module's functions, such as
`strings.split(text, separator)`, `strings.join(parts, separator)` and `strings.encode(text)`. This module adds what
it lacks. `upper` and `lower` map ASCII only. `substitute` is spelled that way
because `replace` is a reserved word. `ord` reads the Unicode scalar value of a
single-character text and `chr` builds that text from a scalar value; both reject
a length other than one, and `chr` rejects surrogates and code points past
`0x10FFFF`. The fallible builders return `Error`: `Invalid` marks an argument
outside the operation's accepted range, `Overflow` marks a value that does not fit
the rendering, and `message(error)` returns the human-readable reason.

```selka
# doc: expect 42
import strings

func main() -> int:
    if not strings.starts_with("answer=42", "answer"):
        return 1
    if strings.strip("  spaced \t") != "spaced":
        return 2
    match strings.find("answer=42", "="):
        case Some(position):
            return decoded(strings.char_slice("answer=42", position + 1, 9))
        case None:
            return 3

func decoded(body: str) -> int:
    match parse_int(body):
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

`format_decimal` is the other rounding, the one Zig's `{d:.N}` prints: it takes the
shortest digits that round-trip (the ones `str(value)` shows) and rounds them half up at
the Nth decimal, looking only at the first dropped digit. A decimal tie such as `6.475`
therefore rounds up even though the binary value sits just below it. Use it to match output
written by Zig or JavaScript; use `format_float` or an f-string to match Python and C. It
keeps the sign of a result that rounds to zero, as Zig does, and takes the same 0 to 17
decimals.

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

`format_shortest(value)` is the float's shortest text that reads back as the same float, with an
exponent where the plain form would be long. `str(1e300)` is 301 digits and `str(5e-324)` is a point
and 323 zeros; `format_shortest(1e300)` is `"1e+300"` and `format_shortest(5e-324)` is `"5e-324"`. The rule
is Python's `repr`: from 1e-4 up to but not including 1e16 the text is `str(value)` (plain digits, `.0` on a
whole number: `"0.0001"`, `"100000.0"`, `"9999999999999998.0"`); outside that range it is the shortest digits
with a point after the first when there are more, then `e`, a sign and at least two exponent digits
(`"1e+16"`, `"1.5e-05"`, `"1.7976931348623157e+308"`). A program that reads the text back
(`parse_float`) gets the same bits for every finite float, an infinity and a NaN, and negative zero is
`"-0.0"`; infinities and NaN are `str`'s `"inf"`, `"-inf"` and `"nan"`. `str(value)` and f-strings do not
change. The small side agrees with Go's `strconv.FormatFloat(x, 'g', -1, 64)` and with `jq`; the large side
does not: Go writes an exponent from 1e6 up (`1e+06`), and `jq` when the zeros after the digits pass 15
(`jq` prints `15000000000000000` where this prints `"1.5e+16"`). A program that has to match one of them
cuts the digits out of `format_shortest`'s text and lays them out itself.

```selka
# doc: expect 1e+300 5e-324 1e-05 0.0001 1.5e+16 9999999999999998.0 -0.0
import strings

func main(out: Stream) -> int:
    print(out, strings.format_shortest(1e300), strings.format_shortest(5e-324), strings.format_shortest(0.00001), strings.format_shortest(0.0001), strings.format_shortest(1.5e16), strings.format_shortest(9999999999999998.0), strings.format_shortest(-0.0))
    return 0
```

### A prefix at an octet offset

A scanner that walks a text's octets and asks at each one whether a marker starts there cannot slice at every
offset: `text[at:]` traps `R_TEXT_BOUNDARY` when `at` falls inside a multi-byte scalar, and so does the method
`text.startswith(prefix, at)`. `strings.starts_with_at(text, prefix, at)` asks the same question without slicing. It
answers `False` at an offset inside a scalar (no text begins there) and past the end; at the end only the empty prefix
matches, and a negative offset traps `R_TEXT_BOUNDS`, as a negative slice does. On the octets of a `bytes` value, which
have no scalar boundaries, the same question is `bytes.starts_with(data[at:], prefix)`.

Which to use: `strings.starts_with_at(text, prefix, at)` is for an offset the program did not find itself, such as every
octet a scanner walks; it answers `False` inside a multi-byte character and past the end. The bounded
`strings.starts_with(text, prefix, start=at)` is for an offset known to be at a character, such as one a search
answered; it traps `R_TEXT_BOUNDARY` otherwise, as a slice does. Both stay.

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

`text[0:width]` counts octets, so it traps `R_TEXT_BOUNDARY` when the width falls inside a multi-byte scalar, and a
text of ASCII letters never shows it: a cut that passed every test with ASCII texts ended a server on the first long
character. `strings.cut_octets(text, limit)` is the cut that cannot: the longest prefix of at most `limit` octets that
ends where a character ends. It is a view of `text`, like a slice, so nothing is copied (`copy(...)` makes it
independent storage, as the example does before it adds the ellipsis). A limit inside a character backs off to where
that character starts; a limit below the first character's width, or negative, gives the empty text; a limit at or past
the length gives the whole text. `strings.char_slice(text, 0, count)` cuts at a count of scalars instead, which is the
other way to avoid the trap when the width is a count of characters. `selka lint` reports a slice of a `str` whose
bound is a literal, a constant or the other bound plus a literal (`L_TEXT_SLICE_OCTETS`) and names these helpers.

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

`strings.join(parts, separator)` is Python's `separator.join(parts)`: the parts with the separator between each two,
none before the first or after the last, and empty text for an empty list. `str(list)` is the list as `print` shows it,
brackets and quotes included (`[3, 1, 2]`, `['a', 'b']`); `join` is for the other message, a separator of your choosing
and no brackets or quotes, and a list of numbers joins the `str` of each element, collected first. `bytes.join` is
the same for `bytes[]`.

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

`set[T]` holds each value at most once, and `sets` holds its fourteen operations, each
taking its sets as ordinary arguments: `sets.add(mut values, own value)`,
`sets.include(mut values, value)` and `sets.discard(mut values, value)` change one set in
place (`include` borrows its value and copies it only when the set does not hold it yet,
where `add` takes the value it is given), `sets.union`,
`sets.intersection`, `sets.difference` and `sets.symmetric_difference` answer a new
set, and `sets.subset`, `sets.superset` and `sets.disjoint` answer a fact about two
sets. `sets.remove(mut values, value)` removes a value and traps `R_MISSING_KEY` when it
is absent, `sets.pop(mut values)` removes and answers one element, `sets.clear(mut values)`
empties the set, and `sets.update(mut values, other)` adds every element of another set or
of a list of the element type; any other source is refused with a message (the method
`values.update("abc")` adds the three letters, `sets.update` does not take a text). Every
function is generic over an `equality` element type, which is also what a `set[T]` key
requires.

```selka
# doc: expect 3
import sets

func main(out: Stream) -> int:
    mut values: set[int] = {1, 2}
    sets.update(mut values, [5, 6])
    sets.update(mut values, {7})
    sets.remove(mut values, 1)
    const one = sets.pop(mut values)
    _ = one
    const left = len(values)
    sets.clear(mut values)
    print(out, left - len(values))
    return 0
```

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

`import sort` makes `sort` the name of this module in the file, so after it a call of the builtin
`sort(mut values)` is read as a call of the module and refused ("`sort` here names the imported module, which hides the
builtin"). Write the module's function (`sort.sort_ints(values)`), or leave the import out and keep the builtin; `selka fix`
deletes an `import sort` that nothing else in the file uses.

The concrete `sort_ints`, `sort_floats` and `sort_strs` wrappers delegate to the
same stable merge engine as `sorted` and `values.sort()`, returning a new list and
leaving the input untouched. That engine keeps the ascending runs a list already
has, reverses strictly descending ones, extends short runs by insertion and merges
through one scratch buffer of at most half the list, with a comparison compiled
for each element type, so an ordered or reversed list sorts in linear time.
Not-a-number follows every ordered float, equal values and signed zeros retain
their input order, and text compares its stored Unicode scalar values directly.
`compare_strs` and `min_str` therefore allocate no temporary encodings. A generic
sort over an arbitrary element type needs an integer key function or a comparison
function, because the language has no ordering contract: `copy`, `equality`, `integer`,
`codec` and `storable` are the only generic requirements.

`sort_by_key` is a thin forwarder to Python's keyed sort: it returns
`sorted(values, key=key)`, which computes each element's key exactly once, in
list order, and gathers the elements into the new list with the native keyed sort
(see [keyed sorting](python-syntax.md#keyed-sorting) for `key=`, `reverse=` and
the `float`, `str`, `bytes` and recursively ordered record keys the method and `sorted` accept). A key
function that traps on several elements reports the first of them in list order;
before the keyed sort existed, `sort_by_key` asked for keys in the order a
recursive merge first needed them. Sorting NaNs last is a deliberate
regularization: the earlier comparator treated a NaN as tied with every value,
so its position could depend on merge boundaries rather than one ordering
contract.

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

`sort_by_compare(mut values, compare)` sorts a list in place by a comparison of two elements, for an order that no
single `int`, `float` or `str` key gives: jq's order across types of value, or an `ORDER BY` of several keys with a direction
each. `compare` is a top-level function that takes two elements and returns an `int`: negative when the first element goes
before the second, zero when neither does, positive when the second goes first (the answers of `compare_strs` and
`time.compare`). The result is the one order the comparison gives, and the sort is stable: elements that compare equal keep
their input order. The elements are lent to `compare` and never copied; the sort moves each one once. It holds two lists
of positions beside the list, so a list of a million records needs 16 MB more, and it takes about as long as a merge sort
written by hand over a list of indexes. `T` needs `copy` as `sort_by_key` does, which no element type that cannot be lent
to a function (a resource, a result) has.

The language has no closures, so a comparison that needs more than the two elements gets it as a third argument:
`sort_by_compare_with(mut values, compare, context)` calls `compare(first, second, context)` on every comparison, and
`context` is read-only and the same each time. It is one value of any `copy + storable` type, so a record carries
what the comparison needs: the direction of each key, the columns to compare, a table to look values up in. This is
`parallel.map`'s trailing arguments with one context value in their place.
A comparison that is not an order (it answers "before" both ways, or goes around in a cycle) still ends and
does not trap: the sort leaves every element in the list once, in an order the comparison does not determine. An empty
list and a one-element list are returned at once. For a key that is one `int`, `float` or `str` the keyed `sort(mut
values, key=f)` is faster, since it computes each key once instead of calling a comparison.

The first example orders values of several types the way jq does (`null`, then `false` and `true`, then numbers, then
texts), and the second sorts rows by a text key and then an age that falls when its context says so.

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

`map` applies a function to every element and returns a new list in input order.
The input remains available after the call. Checked ownership borrows distinct
input elements for scoped workers and joins all workers before returning their
owned results.
See [scoped parallel work](managed-memory.md#explicit-values-and-scoped-parallel-work).

The callback takes one read-only input and returns a storable value. A callback
returning managed input data must explicitly `copy(value)` it; returning newly
constructed data transfers it to the output. This API has
no closure captures, detached tasks or escaping handles, and does not support
Unit elements. Scheduling and per-element storage have a cost, so a parallel
speedup is not guaranteed for small callbacks.

A callback may take read-only trailing arguments after its item:
`parallel.map(values, callback, a, b)` calls `callback(item, a, b)` for every item,
with one to five arguments. Each argument is the same for every item. Sema selects the
variant of the argument count: `map_with1`, `map_with2`, `map_with3`, `map_with4` or
`map_with5` in `parallel.selka`. An argument is a scalar (`int`, `float`, `bool`, and
the other scalar types) or a managed value (a list, text, bytes, record or dictionary),
which is lent to every item and not copied. A list, text or bytes held in a plain
parameter is refused (`E_SLICE_ESCAPES`): write `copy(...)` around it, or declare the
parameter `own`; a local, an `own` parameter and a record parameter go in as they are.
A `mut` argument is `E_TASK_MUT`, and an `own` marker on an argument and a fallible
callback are `E_PARALLEL_MAP_ARGS`. The same rule governs the list itself: a list in
a local is passed as it is, and one in a plain parameter has to be copied or declared
`own` (both cases, with examples, are in [Limits](concurrency.md#limits)).

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

A fallible callback (`-> R fails E`) makes `parallel.map` a fallible map: write
`try parallel.map(values, callback)`, which gives `R[] fails E`. Every item runs.
The failure returned is the one with the lowest input index, and the map fails only
after every item has finished. A bare `parallel.map` of a fallible callback is a
compile error (`E_PARALLEL_MAP_FALLIBLE`) whose fix renames the call to
`parallel.map_results`. That is the list of results, `Result[R, E][]`, one per input
in input order, which is what `parallel.map` of a fallible callback gave before this
change, so the rename keeps the program's meaning. A fallible map takes `T` with
`copy`, as `map` does, because a parameter with only `storable` counts as holding
results while its body is checked.

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
# doc: expect item-1! item-2!
import lists
import parallel

func transform(value: str) -> str:
    return value + "!"

func main(out: Stream) -> int:
    mut source = ["item-" + str(1), "item-" + str(2)]
    const result = parallel.map(source, transform)
    if source[0] != "item-1":
        return 1
    lists.clear(mut source)
    print(out, result[0], result[1])
    return 0
```

`threads()` is the number of threads in the pool the tasks run on, at least 1: what
`--threads N` or `SELKA_THREADS=N` set, else one per CPU the process may use. The pool
starts once and a program cannot change its size. `cpus()` is the number of CPUs the
process may use (its affinity mask, at least 1), whatever `--threads` says, so
`f"using {parallel.threads()} of {parallel.cpus()}"` says what a run has and what the
machine offers. Neither takes a capability, and a task gets the same answers as the
calling thread. A test child runs one pool thread, so `threads()` answers 1 under
`selka test`. [The pool's size](concurrency.md#the-pools-size) says when the count is
fixed and cuts a list into that many pieces.

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

`basename` and `dirname` declare `from value` and return views of the input.
`relative(base, target)` is `target` as a path from the folder `base`, both normalized first:
`relative("/a/b", "/a/b/c.selka")` is `c.selka`, `relative("/a/b", "/a/x")` is `../x`, and a path from itself is
`.`; when one is absolute and the other is not, `target` comes back normalized and whole.
These operations read and build text only. They open nothing, resolve no symbolic
link and need no capability.

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

`hex.encode(data)` is the operation of `data.hex()` (it also takes a `byte_buffer`, which
lends its octets); this module adds the uppercase rendering and a predicate, and names the
operations the way the other codecs do.

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

Encoding always emits canonical padding. Decoding rejects a length that is not a
multiple of four, a symbol outside the chosen alphabet, padding anywhere but at
the end of the final group, and a final group whose unused bits are not zero, so
exactly one encoding of any byte string decodes.

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

`csv` parses RFC 4180 text into rows and renders rows back. It is pure text
algebra: it does not read or write files, so a caller reads with
`fs.read_text(path)` first and writes with `fs.write_text(path, csv.write(rows))`.
The delimiter is a comma; a field is quoted with `"`; a quote inside a quoted
field is doubled; LF or CRLF ends a row, and a bare CR is accepted as a line
ending too. A blank line is an empty row, not a row with one empty field, so
the writer renders a lone empty field as `""`.
A final newline does not add a row.

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

`parse` accepts ragged rows and does not enforce a field count. `parse_table`
uses the first row as the header; an empty document gives an empty header and no
rows. Failures name the line and column where the document stopped; an
unterminated quoted field reports the end of the document (the position after its
last byte), not the opening quote. `write`
quotes only a field containing a comma, a quote, CR or LF, writes LF line endings
and ends every row with a newline. There are no dialect options, type conversion,
streaming or file access in this module.

`parse` returns text, so `a,,b` and `a,"",b` give the same row. `parse_fields`
reads the same documents, accepts and refuses exactly what `parse` does with the
same messages, and returns for each field its `text` and `quoted`: whether the
document wrote the field inside quotes. A program for which an empty unquoted
field is NULL and `""` is empty text reads `field.quoted` and tests
`field.text == ""`. `quoted` is `True` for a quoted field whatever it holds
(`"a"` too) and `False` for every unquoted one, an empty field and a field
after a trailing comma included. It is a `Field` record rather than a parallel
`bool[][]` so a field and its flag cannot drift apart when a program filters or
reorders rows (the way `Table` keeps a header with its rows). There is no
writer from `Field` values: `write` takes `str[][]` and quotes a field only when
it must, so a quoted field that needed no quotes is written without them.

What `parse` and `parse_fields` accept and return, each case from a run:

| Document | Result |
| --- | --- |
| `a,,b` and `a,"",b` | `["a", "", "b"]` both; `quoted` is `False,False,False` and `False,True,False` |
| `"a""b"` and `""""` | `a"b` and `"`: a doubled quote inside quotes is one quote |
| `"a` and `"""` | refused, `UnterminatedQuote`: `unterminated quoted field at line 1, column 3` and `... line 1, column 4` |
| `"a\nb",c` (LF, CRLF or CR inside quotes) | the field `a\nb`, with the break kept as written; the line count of a later error includes it |
| `a,b\nc,d`, `a,b\r\nc,d`, `a,b\rc,d` | the rows `[a, b]` and `[c, d]`: LF, CRLF and a bare CR each end a row, in any mix |
| `a,b\nc,d` and `a,b\nc,d\n` | the same two rows: a last line needs no ending and a final ending adds no row |
| `a\n\nb\n` | `[a]`, `[]`, `[b]`: an empty line is an empty row, so is a last empty line (`a\n\n` is `[a]`, `[]`) |
| an empty document, `\n`, `""` | no rows; one empty row `[]`; one row `[""]` |
| `a, b ,c` | `a`, ` b `, `c`: spaces belong to the field |
| `a,` and `,a` | `[a, ""]` and `["", a]`: a comma after the last field starts an empty one |
| `a"b`, `ab"c"`, ` "a"` | refused, `UnexpectedQuote`: `quote inside an unquoted field at line 1, column 2`, `... column 3`, `... column 2` |
| `"a"b`, `"a" ,b` | refused, `UnexpectedCharacter`: `unexpected character after a field at line 1, column 4` |
| a UTF-8 byte-order mark, then `a,b` | not removed: the first field is the mark and `a`; the mark then `"a",b` is refused as a quote in an unquoted field at line 1, column 4 |

A position is `at line L, column C`, both counted from 1. The column counts bytes
(`λ"x` is refused at column 3, and the three bytes of a byte-order mark put the
next column at 4). A line is counted at each LF, inside a quoted field too; a
bare CR ends a row but does not start a new line, so a later position keeps
counting columns along the same line. The position of `UnexpectedQuote` and
`UnexpectedCharacter` is the offending byte; the position of `UnterminatedQuote`
is the end of the document. `parse` does not strip a byte-order mark: a program
that reads a file an editor saved with one drops it first, `text[3:]` when
`strings.starts_with` finds it.

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

`http` parses one complete HTTP/1.0 or HTTP/1.1 request or response from bytes
and renders one back. It is a pure codec: it opens no socket, reads no clock and
keeps no connection state. Pair it with `network` for framing on a live
`Connection`.

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

`parse_request` requires a request line with exactly a token method, a request
target of one of the four forms of RFC 9112 ([request targets](#request-targets)) and
an `HTTP/1.0` or `HTTP/1.1` version, then `CRLF`-separated
header fields and an optional `Content-Length` body. It ignores bytes after that
body: `parse_request_prefix` says how many octets the message took, so a server
that keeps a connection open moves on to the next request ([several messages in one
buffer](#several-messages-in-one-buffer)). A header
section is limited to 65,536 bytes and 100 fields, and a body to 1,048,576
bytes; `parse_request_within` takes other limits ([request limits](#request-limits)). Header names use the RFC 9110 token alphabet; values must be UTF-8 with no
control octet other than horizontal tab; obsolete line folding, a repeated
conflicting `Content-Length`, and a chunked request body are refused. The reading is strict where two
readers could disagree about where a message's fields or body end ([strict reading](#strict-reading)).

`parse_response` accepts `Content-Length`, a single `chunked` transfer coding with
trailers, or a body ended by connection close. The last form needs `closed=true`;
while the peer is open and no length is present the result is `Incomplete`. A 1xx,
204 or 304 response has no body. A response that is both chunked and carries
`Content-Length` is refused. The codec does not distinguish a HEAD response, whose
body a caller must not read; pass `closed=false` and treat the result as headers
only.

Both writers validate the method (a token), target (one of the four forms), version (`HTTP/1.0` or
`HTTP/1.1`), status, header names and values, and
reject a declared `Content-Length` that disagrees with `body`; `write_response_head` writes the answer to a HEAD
request ([HEAD answers](#head-answers)). They add
`Content-Length` for a nonempty body that has no declared length. `write_response` also writes `Content-Length: 0` for an
empty body, so a reader always finds where an answer ends, except for a 1xx, 204 or 304 answer (which has no body, and which
is refused when it is given one) and when the caller's fields already carry a `Transfer-Encoding`. A `Transfer-Encoding`
beside a body (which would get a `Content-Length`) or beside a `Content-Length` is refused, in both writers: a message that says
two things about where it ends is the start of request smuggling.
`header` and `headers` match names case-insensitively. `header` declares
`from fields` and borrows the selected value; `headers` returns independent copies. `target` is the target as sent
without its fragment (from the first `#`; a parsed request has none). `path` and `query` answer by the target's form
([request targets](#request-targets)). `query` returns the text after the first `?`, later `?`s included, or the empty
string.

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

A refusal says which limit it hit, so a server answers with the right status from the value, not the text.
`HeaderTooLarge` is a header section past 65,536 bytes or more than 100 fields (`status` 431), `BodyTooLarge` a body, chunk
or declared `Content-Length` past 1,048,576 bytes (413), `UnsupportedVersion` a version spelled `HTTP/` digit `.` digit
other than 1.0 and 1.1 (505), `Unsupported` any other feature the codec lacks, such as a chunked request body or a version
token that is not spelled like one (501), and `Malformed` and `Incomplete` everything else wrong with the bytes (400). `message` returns the same reason text for every case.

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

A request target is one of four forms (RFC 9112 section 3.2), and `parse_request` and `parse_request_within` refuse any
other with `Malformed` (400): an **origin form** (`/`, then a path, then an optional `?query`), an **absolute form** (a scheme,
`://`, a nonempty authority, then an optional path and query), **`*`** (for OPTIONS) and an **authority form**
(`host:port`, for CONNECT: a name, an IPv4 address or a bracketed IP literal, and a port of one to five digits, at most 65535).
A target that is empty or holds a space, a control octet or a `#` is refused (a fragment is never sent), and so is one that
starts with neither `/` nor a scheme (`admin/x`, `?a=b`). The codec does not tie a form to a method: `GET *` is read, and a
server decides whether it answers it. `write_request` refuses the same targets.

`path` and `query` are defined on each form. In origin form the path is the text before the first `?`, so a `://` inside the
path (`/public/x://h/admin`) or inside the query changes nothing. In absolute form it starts at the first `/` after the
authority, and is `/` when there is none (RFC 9110 section 7.1). **`*` and an authority form have no path: `path` answers the
empty string** for them, never `/*` or `/host:port`, which a route table could hold; `query` answers the empty string.
`target` is the target as sent. (A `Request` a program builds by hand with some other target is read as it always was:
`path` gives it a leading `/`.)

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

Two readers that disagree on where a message's fields or body end are how request smuggling works, so the codec refuses
what it used to guess at. A message that is well formed by RFC 9110 and RFC 9112 is read as before.

- **Numbers are digits.** `Content-Length` is one to 18 ASCII digits (`007` is 7) and nothing else: a sign, an underscore, a
  space inside, a list (`4, 4`) and a digit of another script are `Malformed`. Two `Content-Length` fields that agree are one
  length and two that differ are refused. A status code is exactly three digits (100 to 999). A chunk size is `1*HEXDIG`
  (no `0x`, no sign). `Content-Length` beside `Transfer-Encoding` is refused: in a request as an unsupported chunked body
  (501), in a response as `Malformed` (400).
- **Control octets are refused, not trimmed.** Only a space and a horizontal tab are trimmed from the ends of a field value (the
  Unicode spaces that `str.strip` removes are part of the value). A control octet other than a tab (0 to 8, 10 to 31, 127), a
  bare CR and a bare LF are refused in a field value, a reason phrase, a version and a chunk-size line, wherever they stand. A line
  ends at CRLF only: a message whose lines end at a bare LF never completes (`Incomplete`).
- **Chunked bodies.** A chunk-size line is a hexadecimal size, optional blanks and an optional chunk extension, which is
  read for its octets (no control octet) and ignored. A trailer that names `Content-Length` or `Transfer-Encoding` is refused
  (RFC 9110 section 6.5.1), as is one with folding or a bad name. A 1xx, 204 or 304 response ends at its blank line whatever its
  fields say, so one that claims to be chunked is `Malformed`. The chunks are gathered in one builder, so the time is linear.
- **A version token** with a control octet is `Malformed`; one that is spelled `HTTP/1.10` or `http/1.1` is `Unsupported`
  (501), and `HTTP/1.2` is `UnsupportedVersion` (505).

Still read laxly, by choice: a method in lower case is a method of its own (`method` lower-cases it for comparison), one or
more spaces between a status line's version, code and reason are accepted, and a missing or repeated `Host` field is not
refused.

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

`parse_request` and `parse_response` read the one message at the start of `data` and ignore what follows.
`parse_request_prefix(data, limits)` and `parse_response_prefix(data, closed)` also answer how many octets that message took
(`length`): the header section, its blank line and the body, and for a chunked body the trailer section too; for a response whose
body the close of the connection ended, all of `data`. The octets after `length` are the start of the next message, and never
change what the first one says. A message that is not complete yet fails with `Incomplete` as before. A server that keeps a
connection open parses on from `data[length:]`:

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

The answer to a HEAD request is the header section of the GET answer, its `Content-Length` included, and no body, so
`write_response` cannot write it: it refuses a declared length that differs from the body. `write_response_head(response)`
writes the header section `write_response` would write, ending with its blank line, and nothing after it. Give it the
GET answer itself, body and all, and its `Content-Length` is the body's (declared, or added as `write_response` adds
it); or give it an empty body and the `Content-Length` the GET answer carries, which is written as declared. The other
checks of `write_response` hold: a nonempty body must match a declared length, a declared length must be a decimal
integer, and an empty body with no declared length gets no field here, where `write_response` writes `Content-Length: 0`: the body of a
HEAD answer is always empty, so the writer cannot tell the GET answer's empty body from an omitted one.

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

`parse_request` holds a request to a header section of 65,536 bytes and 100 fields and a body of 1,048,576 bytes.
`parse_request_within(data, limits)` parses the same way within the caller's `Limits` (`header_bytes`, `header_fields`
and `body_bytes`), so a server that takes a 5 MiB upload parses the whole request. The defaults of `Limits()` are
`parse_request`'s, so `parse_request_within(data, Limits())` is `parse_request(data)`. A body, or a declared
`Content-Length`, over `body_bytes` is refused with `BodyTooLarge` (`status` 413), and a section or field count past
its limit with `HeaderTooLarge` (431): never `Malformed`, so a server answers with the status the value names.

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

`loads` parses strict RFC 8259: no comments, no trailing commas, no leading zero,
no bare fraction or exponent, no unescaped control character, no lone surrogate,
and no trailing text. Nesting deeper than `max_depth()` is rejected. Objects keep
the order their keys were parsed in, and `dumps` reproduces it. A member that
repeats a key keeps the last value and the place of the first, as Python's
`json.loads` does: `{"a":1,"b":2,"a":3}` reads as `{"a":3,"b":2}`, nested
objects included. A number without a fraction or exponent that fits the signed range
becomes `integer`; anything else becomes `number`. Each error message names the
byte offset where the scanner stopped.

A refusal is an `Error` value whose `Malformed` case carries the human-readable
reason; `message` returns that reason. Match on the case to branch on the
category rather than the text. Because the payload is a plain `str`, a module
that wraps `json.Error` in its own error union converts a propagated failure
with `try` and no hand-written translation.

`get`, `at`, `as_str`, `as_list` and `as_dict` return a borrow of the value they read: the
selected member, element or payload is read in place, and nothing is copied. Their
signatures declare `from value`; `message` declares `from error` and borrows its
error payload too. A borrowed answer is bound with
`const` (or read or passed on), and writing `copy(...)` around the call keeps an independent value. Matching
directly on the call is a store of the borrow, so the example below binds the answer first.

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

`dumps` renders infinities and not-a-number as `null`, because RFC 8259 has no
spelling for them. Rendering a float uses the shortest decimal that reads back as
the same value, written without an exponent.

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

The compiler derives the JSON form of a type from its declaration, so a record
needs no hand-written reader or writer, and a field added to the record is read
and written with no other change. The form is plain JSON:

| Selka type | Written | Read |
| --- | --- | --- |
| `int`, `i8` to `u64` | a number, exact (`18446744073709551615`) | an integer token that fits the width; `1.0`, `1e3` and one past the range are refused |
| `float`, `f32` | the shortest number that reads back the same, spelled as Python's `repr` (`2.5`, `-0.0`, `1e+300`) | any number; one past the type's range is `out_of_range`; NaN and the infinities cannot be written |
| `bool`, `str` | `true`/`false`, a string | the same; `null` is refused |
| `T?` | `null` or the value | `null`, the value, or an absent member (`None`) |
| list, `FixedArray[T, N]` | an array | an array (a fixed array of exactly `N` elements) |
| enum case without fields | its name, `"green"`, also in an enum whose other cases have fields | the name; another name is `unknown_case`, and `{"case": "green"}` is refused |
| enum case with fields | `{"case": "circle", "value": {"r": 3}}` | the same |
| record | an object, its fields in declaration order | the rules below |

A record reads from an object whose members may come in any order. A missing
member takes the field's declared default; a field without a default is required
(`missing`). A member the record has no field for is `unknown_member`, and a
member given twice is `duplicate`. A record with `@invariant` is checked before
the decoded value is returned, as a constructor is: a value that breaks it makes
`decode` fail with kind `invariant`, at the record's path and the offset of its
`{`, and the program handles it like any bad document. A number past 2^53 is read
and written exactly; a JavaScript reader rounds it. A value nests at most 1,000
arrays and objects deep, either way: `decode` refuses a deeper document
(`syntax`), and `encode` a deeper value (`unwritable`, at the path where it
stopped), so `decode` reads everything `encode` writes.

Every refusal is a `CodecError`: its `kind`, the `path` of the field it is about
(`projects[3].tracker.tasks[12].stamp`, empty for the whole document), the byte
`offset` of the value in the document (in the text written so far, for `encode`),
and `message`, the sentence `str(error)` prints. A member name in a path or a
sentence is spelled as JSON writes it (`a\nb`, `ab\u0000cd`); a sentence cuts a
name it echoes at 80 bytes and a long path in the middle, with `...`. A type with a part that has no
JSON form (a function, a capability, a resource, a class) is refused where
`encode` or `decode` is called, with `E_NO_CODEC` naming that part's path; so is
a dictionary, a set, `bytes`, a tuple or a `json.Json` field, which are not built
yet. A generic function passes the promise on with the same bound:
`func load[T: codec](text: str) -> T fails json.CodecError`.

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

A pool is the escape hatch for graphs and entity tables that values cannot
express directly: a stable, copyable name for a slot that stays valid while the
slot lives and reports absence once it does not. Removing a slot bumps its
generation, so every handle to the old occupant stops matching. A stale handle
and an out-of-range handle report `None` or `False`, and no handle ever traps.

A handle carries a slot index and a generation, not the identity of its pool, so
a handle from one pool passed to another is only rejected when that pool has no
matching live slot. Keep a handle with the pool it came from, the way an index
belongs to its list.

**`handle.index` is readable.** A `Handle` has two `int` fields, `index` and `generation`, and a program may read both
(a hand-built `pool.Handle[T](index=0, generation=0)` is an ordinary record too, and `==` compares the two fields).
`index` is the slot number: slots are numbered from 0 in the order they were first allocated, so every `index` of a
live handle is below `pool.capacity(store)`, and `index` can subscript a list kept beside the pool. It does not change
for as long as the entry lives (`pool.set` writes the same slot). `pool.remove` frees the slot, and the next
`pool.insert` takes the slot freed last, so a new handle can carry the `index` of a removed one, with a larger
`generation`: a list kept beside the pool must be written at `handle.index` on every insert, appended when `index`
is `len(list)` and overwritten when it is smaller, or it keeps the removed entry's data.

**`pool.get` returns a copy.** The record comes out whole, with every list, dictionary and text it holds, on each
call, and `pool.set` copies the record in again; the checker does not lend the result. A record that holds a list of
200,000 integers, read 2,000 times, cost about 0.35 ms a
read in a release build, and the same loop over a list kept outside the pool cost 0.17 s in all. Nothing reads or
writes one field of a pooled record in place: the functions above are all there are, and none takes a field. So keep
in the pool the small record that says what the entry is (a name, a kind, a few numbers), and keep the large or
growing data in lists beside it, subscripted by `handle.index`. A field that changes often belongs in such a list
too, since changing it through the pool is a `get`, the change and a `set`, two copies of the whole record.

```selka
# doc: expect True False 2 1
import pool

record Node:
    name: str

# edges[handle.index] is the list of the node `handle` names, kept beside the pool
func add(mut nodes: pool.Pool[Node], mut edges: int[][], name: str, links: int[]) -> pool.Handle[Node]:
    const handle = pool.insert(mut nodes, Node(name=name))
    if handle.index == len(edges):
        append(mut edges, copy(links))
    else:
        edges[handle.index] = copy(links)
    return handle

func degree(edges: int[][], handle: pool.Handle[Node]) -> int:
    return len(edges[handle.index])

func main(out: Stream) -> int:
    mut seed: Node[] = []
    mut nodes = pool.create(seed)
    mut edges: int[][] = []
    const a = add(mut nodes, mut edges, "a", [1, 2, 3])
    const b = add(mut nodes, mut edges, "b", [0, 2])
    _ = pool.remove(mut nodes, a)
    const d = add(mut nodes, mut edges, "d", [1])
    print(out, d.index == a.index, pool.occupied(nodes, a), degree(edges, b), degree(edges, d))
    return 0
```

`Pool` is a value record whose fields are managed lists, so assigning one refers
to the same store rather than to a snapshot. `count()` rather than `len()` reports
the live population, because `len` is a reserved word.

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

Creation takes a seed list, which also supplies the element type. Pass an empty
annotated list for an empty pool.

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

`spans` is for text that lives next to the buffer it was read from, for as long as the program, which a stored `bytes` can only do by
copying and a borrowed view cannot do at all (a record that leaves its function cannot hold a borrow; a local one may hold whole
values and places, never a slice: [Keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer)). A `Sources` table holds the text of every file the
program reads, each under a file number; `add` moves the text in (`own`) and answers the number, and a file is never changed or
removed afterwards, so a position in it never goes stale. A `Span` is a file number, a start and a length: three integers, copied
freely, kept in records, lists and dictionary values, with none of the allocation of a copy of the text. It is
[sealed](records-and-unions.md#sealed-records): `of`, `between`, `empty_at`, `whole`, `sub` and `join` build one, and another
module reads its fields and never writes them. The text is read through the
table: `text(sources, span)` is a view of the file's own octets, borrowed from the table for as long as it is used, and a span
outside the table traps `R_ASSERT` instead of reading the wrong text.

The table is meant to live as long as the data that points into it. A parser that returns tokens or tree nodes holding spans must
not own the table it filled: the evaluator, the design model or the session does, and the parse takes it by `mut`. Read the text
where it is used (a comparison, a message) and keep spans, not views, in the data: the checker holds the whole record a view came
from, so a view of `model.sources` blocks a write to any field of `model` while it is live.

`equals`, `same`, `starts_with` and `compare` read the text in place with no copy; `same` and `compare` take two spans of any files of
one table. `hash` is 32-bit FNV-1a of the span's text and equals `hash_bytes` of the same octets, for a table of your own. Spans
compare by position, not by text: `==` on two spans asks whether they are the same place, and a dictionary keyed by `Span` keys by
place. To key by text, intern the name with [`symbols`](#symbols).

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

`symbols` interns a name once and gives back a key. A `Table` holds each distinct name; `intern(mut table, text)` answers the `Symbol`
of a name, adding it the first time (the text is borrowed and copied only when it is new, so interning a name already in the
table allocates nothing), and `name(table, symbol)` reads it back as a view of the table's own copy. A `Symbol` is one integer:
copy it, store it in records and lists, compare it with `==` and key a dictionary or set by it. Repeated net names, reference
designators and identifiers become symbols, and the program reads the text where it prints or parses it. `find` looks a name up
without adding it, `valid` says whether a symbol belongs to a table, and `intern_span(mut table, sources, span)` interns the text a
[span](#spans) names, so the same word at two places, or in two files, is one symbol. A `Table` is
[sealed](records-and-unions.md#sealed-records): only `symbols` builds or changes one, so its list of names and its index always agree.

Within one table two symbols are equal exactly when their names are equal, and a symbol stays valid for as long as its table does
(names are never removed). A symbol belongs to the table that made it: `name` traps `R_ASSERT` for a number the table does not
have and reads another name for one it does, so keep one table for the names that share a meaning. `pool` handles do not fit this
job: a pool copies a value out on every `get` where `name` lends it, and it cannot look a value up.

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

`memo` reuses completed results within one running application. `create` binds
the computation and accepts an entry limit from zero through 65,536. An invalid
limit returns `Error.InvalidCapacity`; `message` supplies its explanatory text.
Zero disables retention, so every `call` computes and returns `reused=False`.
For positive limits, a hit returns the stored snapshot and `reused=True`.
Misses fill the cache, then replace entries in insertion order. Hits do not
refresh that order. `count` reports retained entries, `capacity` reports the
configured limit, and `clear` releases the cache's entries and resets its order.

The callback takes the complete `Key` argument. It should compute a deterministic
result from that key: this in-process cache reuses completed values and does not
validate external state or enforce a source effect ceiling. Captures remain
unavailable. Tagged keys compare exactly: integer `1`, text `"1"` and
bytes `b"1"` are separate arguments. Arbitrary floating-point and collection
keys are not accepted. Each `Entry` also records the actual callable; replacing
`cache.compute` cannot serve an earlier callback's result for the same key.

Results are copyable, storable values with equality support. Lists and records
containing lists are permitted: results, keys and copied caches keep independent
value snapshots when callers later mutate their copies. Capabilities, owned
resources and function values are excluded from results. A trap propagates
normally; insertion happens only after the computation returns. This library
does not recover a trapped process.

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

`connect` acquires a `Connection` through a `Network` that has already been
narrowed with `net.host(name)`; the narrowed capability pins the endpoint, so
`connect` takes no request string. `read` returns a `Chunk[N]` of `N` bytes and
`write` sends a fixed `[N]u8` array, both reporting their progress; `close`
completes the handle. A resource parameter reads, `mut` borrows and `own` takes,
and a plain parameter of a resource type is refused (`E_OWN_PARAMETER`), so
`read`, `write` and `close` take the `Connection` `own`: each consumes the handle
it receives, and the call writes `read[4](own connection)`. A `mut` parameter
borrows the handle instead, so a helper can use one connection across calls, and
the handle it keeps must be declared `own`. Use the raw
`read_resource`/`write_resource`/`complete_resource` builtins when one
connection needs several operations. `write_resource` accepts a managed `bytes`
value as well as a fixed `u8` array, which is the usual path for a response whose
length is known only at run time.

`listen` binds a `Listener` through the same narrowed `net.host(name)` value. The
endpoint must appear in a separate `--allow-listen=IP:PORT` grant; a grant for an
outbound `--allow-endpoint` does not permit listening. The listener stays live
across accepts. `accept_resource[Accepted](listener)` is the raw builtin used by a
server loop: it borrows the listener, returns a fresh `Connection` on success, and
leaves the same binding ready for the next accept. Accepted connections have
read, write and complete rights but no accept right, and a `Listener` has the
accept right but no read or write right: `read_resource` on a listener, or
`accept_resource` on a connection, answers `err(2)` at once. A failed accept carries only
its error code and does not consume the listener binding, so a server may retry or
stop; `examples/http-server/main.selka` stops.

```text
# doc: not-selka
selka run examples/http-server/main.selka --restrict --allow-listen=127.0.0.1:8080
```

`examples/http-server/main.selka` is a complete single-threaded server. It reads one
request at a time from a 64 KiB chunk, assembles it with `byte_builder`, parses it
with `http.parse_request`, and writes the encoded response with
`write_resource[network.Written](connection, wire)`.

A resource is move-only, and passing it by value transfers it. A `mut` parameter
is an exclusive borrow for every type, resources included (FR-203), so a server
loop can hand its listener to a helper: `accept_one(mut listener)` reads the
listener, accepts one connection and leaves the caller's binding ready for the
next call. A helper that keeps the resource — storing it in a record or returning
it as the resource itself — declares the parameter `own` and every call site
passes `own listener`. The same holds for a connection that several helpers serve
in turn, and projecting any field of a record that holds a resource consumes the
whole record. A helper that reads more input takes the connection `own` and
returns it, passing the bytes out through a `mut` argument, and the caller
reassigns its one local. The connection is `own`: each call gives the binding away
and takes the returned one back. Return the bare connection, not a record that wraps it:
a loop that carries a record holding a resource checks but cannot be built.

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

`denied` builds a stand-in `Network` that reaches nothing: every acquisition
through it, or through a `net.host(...)` narrowing of it, fails with the
`Connected.err` code `denied_here()`. `describe` spells any `Connected.err` code
as a reason; for that one it reads `network access is denied in this context:
this Network is a deterministic stand-in`.

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

The same denied Network also refuses a listener, so a capability test can cover
the server path without opening a socket.

```selka
# doc: expect 6 network access is denied in this context: this Network is a deterministic stand-in
import network

func main(out: Stream) -> int:
    mut net = network.denied()
    with net.host("127.0.0.1:8081") as scoped:
        match network.listen(scoped):
            case ok(_):
                print(out, "listening")
            case err(code):
                print(out, code, network.describe(code))
    return 0
```

### Time limits on a connection

`connect` and the reads and writes of the `Connection` it returns wait as long as the peer takes, so a peer that accepts
and then never answers stalls the program. `connect_within(net, limits)` connects the same way within the time limits of
a `Timeouts` record, all in milliseconds: `connect_ms` bounds the connect, and `read_ms` and `write_ms` bound each later
`read_resource` that waits that long for a byte and each `write_resource` that waits that long to send one. A limit that
runs out is an ordinary failure with the error code `timed_out()` (7): `Connected.err` for the connect, `Read.err` or
`Written.err` for a transfer, which leaves the connection open, so a caller may wait again or close it. It is not the
code of a refused or unreachable endpoint (3), which fails at once, and a peer that closed is a read's end of stream, as
before; `describe(timed_out())` reads `timed out: the endpoint did not answer within the time limit`. A field left at
0 (the default) or below has no limit, so `connect_within(net, Timeouts())` is `connect(net)`, and a limit above one
day is one day. The runtime keeps the limits on the socket (a nonblocking connect waited on with `poll`, then
`SO_RCVTIMEO` and `SO_SNDTIMEO`): no thread, no signal, and no `Clock` of the program's. On a stand-in Network nothing
blocks, so the limits have nothing to bound and `connect_within` answers as `connect` does.

A client that asks a service on loopback for every request bounds the whole exchange:

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

The time-out code is a value of its own, so a caller tells it from the other failures:

```selka
# doc: expect 7 True timed out: the endpoint did not answer within the time limit
import network

func main(out: Stream) -> int:
    const limits = network.Timeouts(read_ms=5000)
    print(out, network.timed_out(), limits.connect_ms == 0 and limits.write_ms == 0, network.describe(network.timed_out()))
    return 0
```

`receive_buffer_bytes` asks the kernel for a receive buffer of that size (`SO_RCVBUF`, set before the connect, since
the window a connection advertises is fixed then); 0, the default, keeps the system's. Linux doubles the number for its
own bookkeeping, keeps at least about 2 KiB and at most `net.core.rmem_max`, and stops growing the buffer by itself. It
bounds what can wait unread at this end: a peer that writes to a reader that never reads has its sends stop being
taken after this buffer and the writer's own send buffer are full. The writer's buffer is the writer's kernel's
(`net.ipv4.tcp_wmem`, up to 4 MiB by default), so on loopback a writer to a 4 KiB reader stops after about 2.9 MB
instead of 4.2 MB: fewer bytes, not a few kilobytes. A test that checks how a server treats a stalled reader sets the
reader's buffer small and counts what the server queues itself. An older spelling such as
`network.Timeouts(read_ms=1500)` keeps the system's buffer.

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

`network.memory()` is a `Network` stand-in whose endpoints are names, so a test can drive both halves of a socket
program without a socket. The name of `net.host(name)` is the endpoint: `listen` registers it, `connect` to a name that
is listened on makes a pair of connected ends and queues the server end on the listener, and
`accept_resource[Accepted](listener)` hands the next end out, in the order the clients connected. Bytes written on one
end queue on the other (a megabyte at most per direction), and a read returns what is queued, up to the size it asks
for. Nothing blocks, because a test has one thread: a read with nothing queued while the peer is open, an accept with
nothing waiting, a `connect` to a name nobody listens on, a second `listen` on a name that is taken and a write after the
peer closed all fail at once with the code 3, where a real socket would wait or reset. A closed end gives its peer the
bytes still queued and then end of stream, as a socket does, with a read of no bytes. The stand-in offers no `Poller`,
and `network.denied()` is unchanged. A narrowed capability lives in a `with` scope, so the listener and the ends live
inside it.

A name is taken only while a live listener holds it, and a listener is a resource, so it ends at its last use, as every
resource does: a second `listen` on the name is refused with the code 3 (the real network's address in use) while the first
listener is still used later, and succeeds once the first has been used for the last time or its scope has ended. A listener
that is bound and never used again holds nothing, on the real network as here.

That holds for a discard too: `_ = own listener` as the last line is not a use that keeps the listener open, so the listener
below is closed after its binding, before the `connect` written under it, and the `connect` is refused with the code 3.

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

To hold a listener or a connection open on purpose, use it where it must still be alive: here the `accept_resource` under the
`connect` is a use of the listener, so it is open at the `connect`, and `network.close(own client)` ends the client where the
program says. (A function that waits on a poller holds it the same way: the `wait` in the example of the next section is a use.)

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

```selka
# doc: expect 4 pong
import network

func main(out: Stream) -> int:
    mut net = network.memory()
    with net.host("memory:80") as scoped:
        match network.listen(scoped):
            case ok(owned):
                mut listener = own owned
                match network.connect(scoped):
                    case ok(made):
                        mut client = own made
                        match accept_resource[network.Accepted](listener):
                            case Ok(accepted):
                                mut server = own accepted
                                match write_resource[network.Written](client, b"ping"):
                                    case Ok(_):
                                        pass
                                    case Err(_):
                                        return 1
                                match read_resource[network.Read[16]](server):
                                    case Ok(chunk):
                                        print(out, chunk.length, "pong")
                                    case Err(_):
                                        return 2
                            case Err(_):
                                return 3
                    case err(_):
                        return 4
            case err(_):
                return 5
    return 0
```

### Addresses given at run time

`net.host("IP:PORT")` takes only a literal, so a reader sees in the source where a function's Network reaches. A server
that is told where to listen and what to reach when it is deployed takes the address as a value instead, as `fs` takes a
path: `connect_to(net, address)`, `connect_within_to(net, address, limits)`, `listen_at(net, address)`,
`open_poller_at(net, address)` and, in the event loop, `dial_to` and `dial_within_to`. Each is its literal sibling
(`connect`, `connect_within`, `listen`, `open_poller`, `dial`, `dial_within`) with the address as a `str`, read from the
environment, an argument or a file. What the source then shows is where the address comes from; the address itself is
in the launch.

- **The address** is `IP:PORT`: a dotted IPv4 address, a colon and a port of decimal digits alone, as `--allow-endpoint`
  and `net.host` read it. A host name, an IPv6 address, a sign, a space before or after, or anything after the port is
  malformed. Port 0 asks the kernel for a port and only a poller can report it, so only `open_poller_at` takes it.
- **The grant** is checked when the operation runs, exactly as for a `net.host` literal: under `--restrict` the address
  must be one an `--allow-endpoint=IP:PORT` (to connect or dial) or `--allow-listen=IP:PORT` (to listen) names
  verbatim, or the result is `err(2)` ("denied: outside the granted endpoints"); a launch with no grant of that kind at
  all answers 1. Without `--restrict` every address is granted, as every path is for `fs`, and a malformed one fails with
  3, as an endpoint nobody answers on.
- **A narrowed Network stays narrow.** Through `net.host("127.0.0.1:9000")` only `"127.0.0.1:9000"` itself is
  reachable; any other address is `err(2)`, never sent to the narrowing's address. A function handed a narrowed Network
  is as bounded as before.
- **The stand-ins**: `network.memory()` takes any text as an endpoint name, so a test passes the address it wants and a
  name `listen_at` registers is the one a `net.host` literal of the same text names; it offers no poller, so
  `open_poller_at` and `dial_to` are refused there (2) as `open_poller` is. `network.denied()` refuses them all with
  `denied_here()`.

`acquire_resource` on a Network, which these operations are written with, is the standard library's own: in a program it
is `E_INTERNAL_NAME`, because its requests are the module's internal encoding and one built at run time would reach any
address the launch grants past the literal rule.

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

Under `--restrict` its unit file grants that one address: `SELKA_OPTIONS=--restrict --allow-env=APP_LISTEN
--allow-listen=127.0.0.1:30150`, with `APP_LISTEN=127.0.0.1:30150`.

### Event loop

One thread can serve many connections with a `Poller`: `open_poller(net)` binds
the listening endpoint a `net.host("IP:PORT")` narrowing names (the same
`--allow-listen` grant as `listen`), and the runtime keeps the listener and every
accepted connection inside that one resource. A program names a connection by the
small integer id `accept` returns, so connections live in a `dict[int, State]`
instead of as resources, and the loop function holds exactly one resource local.
Nothing blocks except `wait`, which waits at most `timeout_ms` milliseconds. The
design is in the event loop note (`docs/design/event-loop-2026-10-18.md`).

**Memory goes back to the system when the loop idles.** A program keeps the memory it frees while it works, so
that a request that frees and allocates a few tens of kilobytes does not fault the same pages in again; after a
burst of deletes its resident size stays at the peak. `wait` hands that memory back when it is about to block with
nothing ready and either its limit is a second or more (or none) or the waits before it found nothing for a second;
it does so once after at least 256 values of about a kilobyte or more were freed and the free memory is 1 MiB or more,
and a busy loop never does. A server that stored and deleted 12 MB of values holds about 3 MB a second later.
Values of about a kilobyte or less are kept in 64 KiB chunks that are only reused, never returned.

**A `Poller` holds as many connections as the process may open descriptors**
(accepted and dialled together), less 64 kept for the rest of the program, and at
most 1,048,576: plan for that number, not for a count of your own.
`network.connection_limit(own poller, mut outcome)` reports it: `outcome.value` is the
limit and `outcome.extra` the number open. Where the hard descriptor limit is 524,288
the limit is 524,224, and `ulimit -n 2000` makes it 1,936. The poller raises the soft
descriptor limit to the hard one when it opens (a program this one starts, with
`process`, gets back the soft limit this one started with), and its table starts at 1,024 slots
(what an idle poller has always held) and doubles as connections arrive, at about 50
bytes a slot besides the kernel's own socket. At the limit `accept` answers
`OUTCOME_FULL` (so does an `accept` that the process has no descriptor for) and the
poller stops reporting the listener, so a further client still connects, in the
kernel's backlog, and waits unanswered until a slot frees. A second poller on the same
address fails to open (`err(3)`), and the blocking `Listener` cannot be added to a
poller. What a program can do at the limit is free slots: close the connections that
have gone quiet (`set_idle_timeout`, then `close_connection` on each `EVENT_IDLE`), or
close the least recently active client itself when `connection_limit` shows the table
nearly full. Either makes room, and the poller reports the listener again so that the
waiting client is accepted.

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

Open the poller in the function that holds the narrowed `Network` and pass it by
value to the loop function: a resource cannot be returned from the function that
called `net.host(...)` (`E_RESOURCE_ESCAPE`). The poller, and the listener inside it, stay open for as long as the loop uses
them; a loop that never waits would close them at once, as any resource is closed after its last use
([when a value is destroyed](managed-memory.md#releasing-memory)).

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

Every operation except the `dial` family takes the `Poller` `own` and returns it, so the loop gives the
binding away on each line and takes the new one back: write
`live = network.wait(own live, 100, mut ready)` after `mut live = own poller`. A helper that calls any of them
does the same: it takes the poller `own` and returns it, and its caller writes `live = helper(own live, ...)`, once
or twice in a row. A `mut` poller parameter does not do this: calling `network.close_connection(own poller, ...)`
or any other `own` operation from one is `E_SINGLE_OWNER_BORROW` (declare the parameter `own`). `mut poller` is the
form of the `dial` family alone ([below](#dialling-from-the-event-loop)), which borrows the poller and returns nothing.
Results other than the poller come back through `mut`
arguments: `Ready` holds the events of one `wait` (`ids` and `flags` side by side),
`Outcome` holds the result of one operation (`code`, `value` and `extra`), and
`recv` appends to a `byte_builder.Builder`. Keep the decisions of a server in plain
functions of ids and bytes; only the thin shell touches the poller. The helpers of the shell have this shape:

```selka
# doc: check
import network

func close_quiet(own held: network.Poller, id: int, mut outcome: network.Outcome) -> network.Poller:
    return network.close_connection(own held, id, mut outcome)

func sweep(own held: network.Poller, mut ready: network.Ready) -> network.Poller:
    mut poller = own held
    mut outcome = network.new_outcome()
    poller = network.wait(own poller, 100, mut ready)
    for index in range(ready.count):
        if network.has(ready.flags[index], network.EVENT_IDLE):
            poller = close_quiet(own poller, ready.ids[index], mut outcome)
    return poller

func serve(own poller: network.Poller) -> int:
    mut live = own poller
    mut ready = network.new_ready()
    live = sweep(own live, mut ready)
    live = sweep(own live, mut ready)
    return ready.count

func main(net: Network) -> int:
    with net.host("127.0.0.1:0") as scoped:
        match network.open_poller(scoped):
            case ok(poller):
                return serve(own poller)
            case err(code):
                return code
```

An event's flags combine `EVENT_READABLE` (1), `EVENT_WRITABLE` (2), `EVENT_HANGUP`
(4), `EVENT_ERROR` (8) and `EVENT_IDLE` (16); the listener is `LISTENER`, id 0.
Readiness is level-triggered: an event repeats until the socket is drained, so a
loop that stops early loses nothing. A hangup or error also reads as readable, so
the next `recv` reports it. A new connection is watched for readable only; ask for
`EVENT_WRITABLE` with `set_interest` while a `send` is unfinished, and drop
`EVENT_READABLE` to stop reading from a client whose response is still queued.

Every operation fills an `Outcome` whose `code` is one of `OUTCOME_OK` (0),
`OUTCOME_WOULD_BLOCK` (1: nothing now), `OUTCOME_CLOSED` (2: the peer finished
sending), `OUTCOME_FAILED` (3: `value` is the errno), `OUTCOME_UNKNOWN` (4: the id is
not open), `OUTCOME_FULL` (5: the table is full), `OUTCOME_BAD` (6) or, for `dial` alone, `OUTCOME_DENIED` (7:
the Network refused the dial). `recv` appends
at most `RECV_LIMIT` (16,384) bytes per call and counts them in `value`. `send`
offers `data[offset:]` (at most `TRANSFER_LIMIT`, 65,536 bytes, per call) and reports
in `value` how many bytes the kernel took, so a large response is written over
several wake-ups with the guest advancing its own `offset`; nothing is sliced, so
the rest of `data` is never copied. Ids are never reused for another connection, so
a stale id answers `OUTCOME_UNKNOWN`.

At the limit (above) clients wait in the kernel's
backlog instead of spinning the loop. That backlog is the system maximum
(`SOMAXCONN`, which the kernel clamps to `net.core.somaxconn`, 4,096 by default on
current kernels) for a `Poller` and for a blocking `Listener` alike, so a burst of
clients that connect faster than the program accepts them is queued rather than
having its SYNs dropped and retried a second later.

An idle keep-alive client needs no clock: `set_idle_timeout(poller, 5000, ...)`
makes `wait` report `EVENT_IDLE` for a connection that has moved no bytes for five
seconds (the timer restarts on `accept` and on every `recv` or `send` that moves
bytes, and after each report), and the loop closes it. The runtime keeps the time;
the program learns none of it, and a program that wants its own deadlines still
reads the `Clock` it was given.

`--allow-listen=127.0.0.1:0` grants a kernel-assigned port: `net.host("127.0.0.1:0")`
binds a free port and `port(poller, LISTENER, ...)` reports it, so a test needs no
fixed port. The grant is matched verbatim like every other (a `:0` grant does not
permit `127.0.0.1:8080` and the reverse), and `--allow-endpoint=IP:0` is still a
usage error. A blocking `listen` refuses a port-0 narrowing with `err(2)` because a
`Listener` cannot report its port. `peer` reports an accepted connection's IPv4
address and port (`format_address` spells them), for an access log.

This skeleton checks without a network; `examples/event-loop-echo/main.selka` is the
complete echo server.

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

`set_idle_timeout` is the poller's, so it applies to every connection. A server that holds some connections open on
purpose, such as an event stream that is quiet between its writes, wants a short timeout for ordinary requests and a long
one, or none, for those. `set_connection_idle_timeout(poller, id, millis, ...)` gives connection `id` its own idle
timeout, which replaces the poller's for that connection alone: `millis` milliseconds, 0 never to report it idle, or a
negative value to return it to the poller's. Every connection that sets nothing keeps the poller's value, so a server
that never calls it behaves as before. Setting it restarts the connection's timer, which then runs as the poller's does
(it restarts on every `recv` or `send` that moves bytes and after each `EVENT_IDLE` report), and closing the connection
forgets it. A connection's own timeout works with none set on the poller. An id that is not open answers
`OUTCOME_UNKNOWN`, and `LISTENER` answers `OUTCOME_BAD`.

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

A `Poller` also opens connections: `dial(mut poller, net, mut outcome)` connects to the endpoint a `net.host("IP:PORT")`
narrowing names and adds the connection to the poller's table, as `accept` adds an accepted one, so one loop can be a
service and a client, and a client holds many connections by their ids instead of in a list (a resource cannot be a
list or dictionary element). `outcome.value` is the new id. Nothing blocks: the connection starts connecting, and a
later `wait` reports it with `EVENT_CONNECTED` (32) once it is open, or with `EVENT_ERROR` when the connect was refused,
the host unreachable or the connect not finished within `connect_ms`. The next `recv` of a failed one answers
`OUTCOME_FAILED` with the errno (111 refused, 110 timed out, 113 no route); close it then. While a connection is still
connecting, `recv` and `send` answer `OUTCOME_WOULD_BLOCK` and `set_interest` takes effect once it is open. `dial`
itself answers `OUTCOME_FAILED` for a failure known at once (on this host a refused port often is), `OUTCOME_FULL`
for a full table and `OUTCOME_DENIED` (7) when the Network refused the dial before any socket was made, with its
`Connected.err` code in `value` (2 outside the granted endpoints, 6 a stand-in).

`dial_within(mut poller, net, limits, mut outcome)` takes the `Timeouts` of `connect_within`: `connect_ms` bounds the
connect and `receive_buffer_bytes` sets the receive buffer. Nothing of a Poller waits, so `read_ms` and `write_ms` bound
nothing here; the idle timeouts (`set_idle_timeout`, `set_connection_idle_timeout`) play their part and apply to a
dialled connection as to an accepted one, its timer starting when it is open. The dial needs exactly the grant a
blocking `connect` needs: the literal of `net.host` and `--allow-endpoint=IP:PORT` under `--restrict` (a listen grant
is not enough), so nothing is reached that a blocking connect could not reach. A stand-in Network refuses a dial
(`OUTCOME_DENIED`: 6 from `network.denied()`, 2 from `network.memory()`, which offers no poller).

`dial_to(mut poller, net, address, mut outcome)` and `dial_within_to(mut poller, net, address, limits, mut outcome)`
dial an address the program has at run time, under the grants of `connect_to` ([addresses given at run
time](#addresses-given-at-run-time)): a launch that does not grant it, or a narrowed Network that names another, answers
`OUTCOME_DENIED` with 2, and a malformed address that is granted `OUTCOME_FAILED` with 22, the errno of an invalid
argument.

The poller is a `mut` borrow here, not `own` as in the other operations, because the dial also takes the Network. A
step of your own may still take the poller `own`, the Network and a `Filesystem` or a `Clock` beside it and return the
poller (`func dial_slot(own live: network.Poller, net: Network) -> network.Poller`): an `own` input of the result's type
is its origin, and the providers beside it are not counted (rule P3 in `docs/ownership-rules.md`). Write
`network.dial(mut live, scoped, mut outcome)` inside it. Each connection is the poller's, so dropping the poller closes it.

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

A program that only connects out needs no listener, and `open_poller` would make it bind one and be granted
`--allow-listen`. `network.open_client_poller(net)` returns a `Poller` that listens on nothing: `dial`, `dial_to` and their
`_within` forms add connections to it, and `wait`, `recv`, `send`, `set_interest`, the idle timeouts, `close_connection`,
`peer` and `connection_limit` work on them as on the connections of `open_poller`, with the same limit (the descriptor
limit less 64, so a load tester holds thousands) and the same table. It takes the `Network` as it is, or one narrowed with
`net.host("IP:PORT")`.

It adds no authority. Under `--restrict` it needs no `--allow-listen`, and each dial still needs the `--allow-endpoint=IP:PORT`
of the address it names, exactly as `connect_to` does (`OUTCOME_DENIED` with 2 when it is not granted). A launch that grants
no `--allow-endpoint` at all refuses the open with 1 (`network.describe(1)`, "no network authority is available"), and a
narrowing of an endpoint that is not granted refuses it with 2. `network.memory()` offers no poller of either kind (2) and
`network.denied()` refuses it (`denied_here()`).

Nothing listens, so `accept` answers `OUTCOME_WOULD_BLOCK` for ever (a server's accept loop ends at once if it is run on a
client poller), `wait` never reports `LISTENER`, and `port` and `set_interest` of `LISTENER` answer `OUTCOME_BAD`. Open the
poller in the function that holds the `Network`, as `open_poller` is, and keep the connections in a `dict[int, State]` by
id. This client dials one address, waits for the connect to finish and reports a refusal; nothing listens on
`127.0.0.1:1`, so it reports the errno of a refused connection (111). A load tester dials in batches and then `send`s and
`recv`s on every id the same way:

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

The stream is SplitMix64: deterministic simulation state, not a cryptographic
generator. Equal seeds give equal streams, and seed zero's first word is
`16294208416658607535`. Copying a `Random` snapshots its current position;
each copy advances independently through the same remaining sequence. Pass
`mut generator` to advance the caller's stream.

`random` returns one of the 2^53 multiples of 2^-53 in `[0, 1)`. `randint` is
inclusive at both ends, covers the entire signed range without overflowing, and
removes modulo bias by rejecting the unusable tail of the word space. `shuffle`
is an in-place Fisher-Yates pass. Reading entropy requires the explicit
`Entropy`; importing the module grants nothing. `seeded_entropy` builds a
stand-in `Entropy` whose words are the SplitMix64 stream of its seed, so
`from_entropy` on it is reproducible, and each read advances it.

`failing_entropy(after)` is the stand-in for fault-injection tests: it answers its first `after` reads with the words
of `seeded_entropy(0)` and then fails every read the way a provider that has stopped working does, so `from_entropy`
returns `Err("entropy capability failed")`. A count below one fails the first read. It grants nothing and is
deterministic, so a test that uses it stays cached.

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

`registers` reads and writes hardware registers through a `Registers` capability: `registers.read8`,
`registers.read16` and `registers.read32` answer the value at an address (`u32`), and `registers.write8`,
`registers.write16` and `registers.write32` store one. On a device (`--target thumbv6m-none`) `main(reg: Registers)`
receives the hardware's registers and each read or write is one volatile access; a Linux build refuses that `main`
(`E_TARGET_CAPABILITY`), and `registers.simulated()` makes a simulated bank, so a driver written against `Registers` is
tested on Linux. A bank is one little-endian memory of bytes: a 32-bit write at `A` reads back through `read8` at `A` to
`A+3`, and an address never written reads 0. `registers.poke32` sets what a read answers without logging a write,
as the hardware would. Every write is logged, oldest first: `registers.write_count`, `registers.write_address`,
`registers.write_value` and `registers.write_width` (8, 16 or 32) read the log by index (an index outside it traps
`R_LIST_BOUNDS`), `registers.writes` answers it as a list of `RegisterWrite` records and `registers.last_write` the
newest value written at an address, or `None`. `simulated()` allocates the whole bank, 4,096 distinct words and
16,384 log entries, so the reads, writes, `poke32` and `pin32` allocate nothing and are allowed in a `@noalloc`
function; a full bank or log traps `R_REGISTER_BANK`. A bank models hardware that changes under the code:
`registers.script32(reg, address, values)` makes the next reads of the word that holds `address` answer `values` in
order (one per read of any width), then the stored word again; a new script replaces the old and an empty list ends it;
the values are copied when they are given, so `script32` allocates and the reads do not. `registers.pin32(reg,
address, mask, value)` makes the bits of `mask` read as `value`'s whatever is written or poked there, over a script's
values too; writes are still logged as written, and a mask of 0 unpins. A `parallel` task may make its own bank. A
device build refuses `simulated`, `poke32`, `script32`, `pin32` and the log readers (`E_TARGET_SIMULATED_REGISTERS`).
`registers.start_core1(reg, entry)` exists only on a device: it starts the second core (an RP2040's core 1) running
`entry`, a top-level `func(Registers) -> int`, with its own stack, heap and `Registers`, and answers `True`, or `False`
when the platform has one core (QEMU's) or core 1 was started already; a host build that calls it is refused
(`E_TARGET_DEVICE_REGISTERS`). See [register access](io.md#register-access) and
[the second core](tooling/native-build.md#the-second-core-registersstart_core1).

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

`cpu` is the processor's own instructions that firmware needs and no expression names, each taking the `Registers`
capability first as the authority over the machine: `cpu.wait_for_event(reg)`, `cpu.wait_for_interrupt(reg)`,
`cpu.send_event(reg)`, `cpu.barrier(reg)` (a data and an instruction synchronisation barrier: what must follow a write
that changes how memory or interrupts behave) and `cpu.breakpoint(reg)`. `cpu.interrupts_off(reg)` holds interrupts off
and answers an `InterruptState`, the state before the call; `cpu.interrupts_restore(reg, own state)` puts it back. The
state is a sealed `@linear` record, so a path that never restores does not compile (`E_LINEAR_UNCONSUMED`), restoring
twice is `E_LINEAR_CONSUMED`, and only `cpu` makes or ends one (`E_SEALED_RECORD` for a forged state or an
`own state.primask` elsewhere). Holds nest: `state.primask` is 1 when interrupts were off already, and the inner restore
leaves them off. On a device (`--target thumbv6m-none`) each call is the instruction itself, inline, with no call:
`wfe`, `wfi`, `sev`, `dsb sy` and `isb sy`, `bkpt #0`, `mrs` of PRIMASK with `cpsid i`, and `msr` of PRIMASK. These seven
functions may be called from `@freestanding` and `@freestanding(ram)` code, a flash routine that holds interrupts off
itself among them; the simulated bank's readers below may not.

On a simulated bank (`registers.simulated()`) each call does nothing to the machine and returns at once, a wait too,
and is recorded in the bank's event log beside its write log, so library code that holds interrupts off or waits is
tested on Linux. `cpu.event_count`, `cpu.event_operation` (the function's name, `"send_event"`) and
`cpu.event_writes_before` (how many register writes came before it) read one entry, `cpu.events` answers the log as
`CpuEvent` records and `cpu.count_of(reg, "barrier")` how many of one ran; `cpu.interrupts_are_off(reg)` says whether
they are off now and `cpu.write_with_interrupts_off(reg, index)` whether logged register write `index` happened while
they were. The log is allocated with the bank (16,384 operations; a full one traps `R_REGISTER_BANK`), so every call is
allowed in a `@noalloc` function. A device build refuses the log readers (`E_TARGET_SIMULATED_REGISTERS`, naming the
function).

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

Both records count signed nanoseconds, which spans roughly 292 years either side
of the Unix epoch. Every constructor and every arithmetic operation that can leave
that range returns `Result`. `now` reads the host's wall clock through an explicit
`Clock` and keeps the provider's unavailable, denied and failed categories
apart in its message. A `Clock` needs no grant; its wall time does: under `--restrict` without `--allow-clock`, `now`
fails with "the wall clock is not granted: pass `--allow-clock`" while `monotonic` and `sleep` keep working.

These are wall-clock instants: a host clock may move backward, so `elapsed`
rejects a reversed pair rather than inventing a negative span. The capability
module offers `monotonic` for elapsed time: a clock's reading that never decreases,
and `sleep` to wait on a clock (a simulated clock advances instead of waiting). It
offers calendar conversion in UTC only and no time zones.

Both count nanoseconds, like `Duration` and `Instant`: `monotonic(clock)` is a reading in nanoseconds (from an
arbitrary start, so only a difference of two readings means anything), and `sleep(clock, count)` waits `count`
nanoseconds, so `sleep(clock, 1000)` is a microsecond and a millisecond is `sleep(clock, 1000000)`. A count of zero or
less waits for nothing. A host clock really waits (the call may return later than asked, never sooner); a simulated
clock moves its wall and monotonic readings by `count` and returns at once, so the example below prints exactly a
million.

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

`to_civil` and `from_civil` convert between an `Instant` and the proleptic Gregorian date and time of day in
UTC (no leap seconds), for the instants a nanosecond count holds: 1677-09-21T00:12:43.145224192Z through
2262-04-11T23:47:16.854775807Z. `from_civil` refuses a field out of range (`2023-02-29`, hour 24, second 60) and an
instant outside that span, with a message naming the field. `format_rfc3339` writes `YYYY-MM-DDThh:mm:ss[.fraction]Z`, the
fraction only when it is not zero and without trailing zeros; `parse_rfc3339` reads `T` or `t`, one to nine fraction
digits, and `Z`, `z` or a `+hh:mm` / `-hh:mm` offset, and refuses a leap second and anything after the offset.
`format_http_date` writes the IMF-fixdate of RFC 9110 (`Sun, 06 Nov 1994 08:49:37 GMT`, whole seconds);
`parse_http_date` accepts the three forms a recipient must: IMF-fixdate, the obsolete RFC 850 form
(`Sunday, 06-Nov-94 08:49:37 GMT`, two-digit years 70 to 99 read as 19xx and 00 to 69 as 20xx) and asctime
(`Sun Nov  6 08:49:37 1994`). Names are case-sensitive, and the weekday name is read but not checked against the date.

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

`simulated_clock` builds a stand-in `Clock` that reads `start` until `advance`
moves it (backward for a negative duration, the way a wall clock may step).
Copies of it share one reading. A host-granted clock cannot be moved, and
`advance` answers it with `Err("only a simulated clock can be advanced")`.

`failing_clock(start, reads)` is the stand-in for fault-injection tests: it reads `start` like `simulated_clock`,
answers its first `reads` calls of `now` and then fails every one the way a provider that has stopped working does,
with `Err("clock capability failed")`. A count below one fails the first read. `advance`, `sleep` and `monotonic`
keep working, and it is deterministic, so a test that uses it stays cached.

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

`memory` builds an empty in-memory stand-in `Filesystem`. It serves every
whole-path helper (`read_file`, `read_text`, `write_file`, `write_text`,
`exists`, `listdir`, `mkdir`, `remove`), `fs.open(path, mode)` in the `r`, `w`
and `a` modes with every handle method, and the narrowings `fs.dir(path)` and
`fs.read_only()`, which stay in memory. It follows the rules of a `--restrict`
root: paths are relative, `.` alone names the root, a path with an empty or `..`
component (or a nested `.` such as `./a`) is denied, a file's parent directory
must exist, `remove` takes a file or an empty directory, and error texts match
the host surface. A test's injected `fs` is this same filesystem, so `listdir(".")`
lists the empty root it starts with. `listdir` sorts by name. It never touches the disk,
and it answers the durable calls too (see below), with times from a logical clock of its own, so
nothing it reports depends on when a test runs.

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

Three helpers do what a build program does to files. `filesystem.mkdir_all(fs, path)` is `mkdir -p`: it makes
`path` and every folder on the way that is missing, and a part of the way that is a file fails. `filesystem.copy_file(fs,
source, target)` is `cp`: the octets of one file written to another, which gets a new file's mode.
`filesystem.walk(fs, root, suffix, skip)` answers every regular file below `root` whose name ends in `suffix` (`""` for
all), as a path from `root`, sorted; a folder whose name or path from `root` is in `skip` is not entered, and the entry
`".*"` skips every folder whose name starts with a dot. Symbolic links are neither followed nor listed.

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

The module also wraps the native durable calls of [rename, stat and file locks](io.md#rename-stat-and-file-locks).
`filesystem.stat(fs, path)` returns a `Stat` (`kind: PathKind`, `size`, `modified` in nanoseconds since the Unix
epoch, `inode`, `mode`, the permission bits, `changed`, the status-change time in the same nanoseconds, which the
kernel moves for any change to the entry, `set_modified` included, and `device`, the number `stat(2)` gives for the device
the entry is on, and `owner`, `group` and `links`, the numeric user and group that own the entry and its number of hard links, as
`stat(2)` gives them; a constructor may leave `mode`, `changed`, `device`, `owner`, `group` and `links` out and they then default to `0`;
every entry of a `memory()` filesystem is owned by `filesystem.MEMORY_OWNER` and `filesystem.MEMORY_GROUP`, `1000`) and fails with a `StatError`, so a caller can match `Missing` (nothing at the path) apart from `Failed(message)` (any other
refusal). `PathKind` is `Regular`, `Directory`, `Symlink` or `Other`; the final component is not followed, and
`filesystem.stat_follow(fs, path)` is the same call following a symbolic link at the end. `filesystem.is_lock_busy(message)`
says whether the failure text of `try_lock_file` reports a lock held by another holder.

An inode names a file only together with its device, which is how `/proc/locks` writes a lock's file (`MAJ:MIN:INODE`, major and
minor in hexadecimal): `filesystem.device_major(stat.device)` and `filesystem.device_minor(stat.device)` take the number apart as
`major(3)` and `minor(3)` do, and every entry of a `memory()` filesystem is on the one device `filesystem.MEMORY_DEVICE` (major 0,
minor 1). `filesystem.statfs(fs, path)` answers a `filesystem.Space` (`size_bytes`, `free_bytes` and `available_bytes`, the bytes an
ordinary process may still use) for the filesystem that holds `path`, failing as `stat` does; a `memory()` filesystem answers the
fixed numbers 1073741824, 536870912 and 402653184. `filesystem.read_at(fs, path, offset, max_bytes)` reads at most `max_bytes` octets
of a regular file from byte `offset`: fewer at the end of the file and none past it, so a reader of a file that only grows
asks from where its last answer ended. See [device, free space and reads from an
offset](io.md#device-free-space-and-reads-from-an-offset).

A `memory()` filesystem also honours the permission bits it keeps: it acts as an ordinary user who owns every entry, so a write to
a file without the write bit, a creation, removal or rename in a directory without it, a read of a file without the read bit and
a path through a directory without the search bit are refused with the words the real filesystem gives (`permission denied`). See
[permission bits on the in-memory filesystem](io.md#permission-bits-on-the-in-memory-filesystem) for which call checks which bit.

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

`filesystem.list_entries(fs, path)` lists a directory with the kind of every entry, from the directory itself and with no
`stat` of the entries: it returns `Entry[]` (`Entry` has `name: str` and `kind: PathKind`) and fails with the message text.
A real directory lists in the system's order and `memory()` sorted by name; see
[listings with entry kinds](io.md#listings-with-entry-kinds).

Nine more typed functions wrap the [real-path and metadata operations](io.md#real-paths-permissions-and-times), each
failing with the message text: `filesystem.realpath(fs, path)` (the absolute link-free path, with or without a restriction, and
the path relative to the narrowing on an `fs.dir` handle) and `filesystem.cwd(fs)` (the `realpath` of `.`) return a `str`;
`filesystem.chmod(fs, path, mode)`, `filesystem.touch(fs, path)`, `filesystem.set_modified(fs, path, nanoseconds)` and
`filesystem.symlink(fs, target, path)` (a symbolic link at `path` holding the text `target`, with the grant every write
has), `filesystem.link(fs, target, path)` (a hard link: `path` becomes a second name for the regular file `target`, the two
sharing one inode so that `Stat.links` reads 2 for both; both names must fall inside write grants or inside a narrowed handle's
folder, and no link is followed, so the call cannot reach a file the program may not write) and `filesystem.mkdir_mode(fs, path, mode)`
(a folder made with the permission bits `mode` from the moment it exists, which `fs.mkdir` then `chmod` is not; the umask narrows
`mode` as it does a file's) return `Unit`; `filesystem.create_mode(fs, path, mode)` returns the `File` that `fs.open(path, "wb")`
would, a new file made with the permission bits `mode` in the one `open(2)` that creates it and an existing one truncated with its
own mode kept; see [hard links and folders with a mode](io.md#real-paths-permissions-and-times); `filesystem.dir_at(fs, path)` returns `fs` narrowed to the folder `path`, a value known only at run time,
as `fs.dir("literal")` narrows it ([a folder named at run time](io.md#a-folder-named-at-run-time-filesystemdir_at)): the path
is read as `fs` reads one, the folder must exist and be reached without a symbolic link, and the handle refuses `..`, absolute
paths and links as a `fs.dir` handle does (a backslash is a byte of a name there, as everywhere on Linux); `filesystem.read_link(fs, path)` returns the `str` stored in the symbolic link at `path`, as `readlink(2)`
does, without following it: relative or absolute, naming something or nothing, and under the rules `filesystem.stat` has for the same
path on every kind of root (see [real paths, permissions and times](io.md#real-paths-permissions-and-times)). `fs.atomic_write_file_mode(path, data, mode)` is the builtin that publishes with chosen permissions
where `atomic_write_file` keeps `0600`. A `memory()` filesystem, and so a test's `fs`, answers all of these, and the rest
of the durable family (`atomic_write_file`, `replace_file`, `replace_file_synced`, `rename_path`, `read_regular_file`, `list_directory`,
`sync_directory` and the three locks), from its own entries: `Stat.modified` reads a logical clock that starts at the test clock's epoch and
moves one second for each call that changes it, inodes count up from 2, a file is `0644` and a directory `0755`, a
symbolic link is an entry of its own that only `realpath` and `stat_follow` follow and only inside the filesystem, a hard link is
a second entry for one shared file, and a lock is held until its `File` is released. `lock_file` on a held path fails at once, since a
stand-in cannot wait. The details are in [the durable calls on a test's filesystem](io.md#the-durable-calls-on-a-tests-filesystem).

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

`fixed` builds a stand-in `Environment` holding exactly `values`: `env.get`
answers from them, `env.names()` lists them sorted, and `env.only(...)` narrows
them, trapping `R_CAPABILITY` on a name outside the narrowed set as a host
`Environment` does. It never reads the process environment. A name must be
nonempty, at most 128 bytes and free of `=`, and a value at most 16384 bytes
(`R_ENVIRONMENT` otherwise); neither may contain NUL.

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

A test prints to a capturing stream and reads back what it printed. `memory()`
returns a `Stream` that keeps every write; `text(stream)` returns the text printed
to it so far as one `str`. Neither needs a grant, and the text never reaches the
process's output. Each stream keeps only its own text, and any number of them may
exist at once. `text` on a stream the process owns (its `out` or `err`) fails with
`InvalidCapability`, because only a capturing stream has text to read.

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

`input_from(data: bytes) -> Input` is the same idea for standard input: an in-memory
[`Input`](io.md#standard-input) that answers `read`, `read_exact`, `read_line` and `read_into` from the octets of
`data` in order and then reports the end of the input. Two inputs keep separate positions.

```selka
# doc: expect b'ab' b'c' b''
import streams

func main(out: Stream) -> int:
    const stdin = streams.input_from(b"abc")
    print(out, stdin.read(2), stdin.read(9), stdin.read(9))
    return 0
```

## Focused references

- Time and randomness (`docs/standard-time-random.md`) specifies the capability
  contracts, the pinned SplitMix64 vectors and the arithmetic limits.
- [Binary64 floating point](floating-point.md) specifies what `float` itself
  does, which is what `math` builds on.
- Time and random example (`examples/standard-time-random/main.selka`) exercises
  reproducible streams and rejected bounds without ambient authority.
- Managed word counts (`examples/python-word-count/main.selka`) shows the builtin
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

`try` converts automatically at such a boundary: when the propagated result's
error type is the payload type of a case of the enclosing function's error
union, the error wraps in that case with no hand-written translation helper.

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

- `sort` has no ordering contract to generalize over, so a generic sort needs an
  integer key function or a comparison function (`sort_by_compare`).
- `pool.create` takes a seed list instead of an explicit type argument, and
  `json`'s union variants are built through the module's constructor functions.
- No module reads or writes a file; `path` is text algebra only.

## hashes

`hashes.sha256(data: bytes) -> str` returns 64 lowercase hexadecimal digits.
The runtime hashes the octets of `data` in place (a `bytes` parameter or a slice is read
without a copy, and the padding is built in two 64-byte blocks of its own). It uses the
x86 SHA extensions when the CPU has them, chosen when the first hash runs, and portable C
otherwise; both give the same digest. Until 8 November 2026 this was a Selka
implementation at about 250 MB/s; the runtime's SHA-NI path runs at about 2 GB/s and its
portable path at about 340 MB/s (1 KB, 64 KB and 16 MB inputs, release build,
`experiments/native-sha256-20261108/REPORT.md`). The 32 raw octets of the digest, as `bytes`,
are `hashes.sha256_bytes(data)` and `hashes.sha256_text_bytes(text)` (once the methods `data.sha256()` and
`text.sha256()`), and
`hashes.blake3_bytes(data)` and `hashes.blake3_text_bytes(text)` answer the raw BLAKE3 octets
(`hashes.blake3` answers a `Digest`). Each hashes in place, a text's UTF-8 octets with no
encoded copy, and the `bytes` ones also take a `byte_buffer`.

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

func main() -> int:
    if hashes.sha256(b"abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad":
        return 42
    return 1
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

`hashes.blake3(data: bytes) -> Digest` and `hashes.blake3_text(text: str) -> Digest` return the 32-byte
[BLAKE3](https://github.com/BLAKE3-team/BLAKE3) digest of the octets of `data` (or of the UTF-8 octets of `text`,
with no encoded copy). The hash runs in the runtime, over the octets in place (a `bytes` parameter or a slice is
hashed without a copy), at the speed of Zig's `std.crypto.hash.Blake3`: within 2% of it at 1 KiB, 64 KiB and 16 MiB
on this machine's AVX2 CPU (`experiments/incremental-engine-20261030/L1/REPORT.md`). The 32 raw octets, as `bytes`,
are `hashes.blake3_bytes(data)` and `hashes.blake3_text_bytes(text)`.

A `hashes.Digest` is a record of four `u64` words (`w0` to `w3`, each the little-endian reading of eight
consecutive digest octets), so it is a plain value: it compares with `==`, keys a dictionary or a set, sits in a
record field and copies freely. It is [sealed](records-and-unions.md#sealed-records): only `hashes` builds one (the
functions below), and its words are read, never written. There are no methods, so a digest is read through functions:

| Function | Result |
| --- | --- |
| `hashes.hex(digest)` | the 64 lowercase hexadecimal digits, the spelling `sha256` answers |
| `hashes.to_bytes(digest)` | the 32 octets as `bytes` |
| `hashes.from_bytes(data)` | the digest of those 32 octets; fails with a `str` unless `len(data) == 32` |
| `hashes.from_hex(text)` | the digest of 64 hexadecimal digits in either case; fails with a `str` otherwise |

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

`hashes.sha1(data: bytes) -> str` returns the 40 lowercase hexadecimal digits of the SHA-1 digest of `data`, and
`hashes.sha1_bytes(data: bytes) -> bytes` its 20 octets, the form a protocol encodes. SHA-1 is broken for collisions:
use it only where a protocol names it, such as the WebSocket handshake of RFC 6455 or Git's object names, and never to
protect anything; `sha256` and `blake3` are the hashes to choose. It is written in Selka and reads whole blocks of `data`
in place, at about 1,100 executed blocks per 64 octets, which suits a handshake's few dozen octets and not bulk data.

A WebSocket client checks the server's `Sec-WebSocket-Accept`: the base64 of the SHA-1 of the key it sent and a fixed
GUID. With the sample of RFC 6455 section 1.3:

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

A compact binary record format over `byte_builder`: fixed-width little-endian integers, LEB128 varints and
length-prefixed bytes and text. Writing appends to a `byte_builder.Builder`; reading takes the `bytes` and an
`int` position the caller keeps, and a read that cannot finish fails instead of trapping.

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

`put_uvarint` writes seven bits per octet, least significant group first, with the high bit set on every octet but the
last (`300` is `ac 02`); `put_varint` zigzag-maps a signed value (`0, -1, 1, -2` become `0, 1, 2, 3`) first, so small
magnitudes of either sign are short. `put_bytes` and `put_text` write the octet count as an unsigned varint, then the
octets. Every `get_*` takes the data and a `mut position`, advances the position past what it read, and fails with
`Truncated` when the input ends first (a length prefix that promises more octets than remain included), `Overlong`
when a varint needs more than ten octets or sets bits past the 64th, and `Text` when length-prefixed text is not UTF-8.
A failed read leaves the position where it was.

`get_bytes` and `get_text` return independent copies. `get_length` reads only the count that precedes a field and
checks that many octets remain, leaving the position just past the prefix; the payload is then
`data[at:at + count]` and the caller steps over it with `at += count`, so a decoder that only needs to look at a
field reads it without copying. `bytes.read_u8(data, at)` is the inline single-octet read for such a field's first
or last octet.

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

`process.command(argv)` is a request to run `argv` in the caller's directory and environment with no input, keeping up to
`DEFAULT_LIMIT` (one mebibyte) of each output stream; set `directory`, `input`, `environment` (`Some(["NAME=VALUE"])`
is exactly the child's environment, `None` inherits) or `limit` on it before the call. `process.run(proc, request)` needs
the [`Process` capability](io.md#processes) and runs the program to completion. `message(error)` spells an `Error`. The
`Output` says how the child ended (`exited` with its status in `code`, or a signal number in `code`), what it wrote, and
whether `truncated` cut either stream. A program that is missing fails `NotFound`; one the system will not start, a
request without a program fail `Failed`. A started program runs with the caller's own
authority; `--restrict` does not contain it.

`process.executable_path(proc)` is the absolute path of the running program, or fails with the system's reason.

`process.start(proc, request, stdout_path, stderr_path)` starts a program without waiting for it, its output in the
named files or `/dev/null`, and returns a `Child`: a sealed linear record that only `start` makes and that ends exactly
once, by `wait` (as long as it takes) or `stop` (`SIGTERM`, a grace in milliseconds, then `SIGKILL`). `signal` sends a
signal (1 to 64, named by `SIGTERM` and the other constants) and `wait_within` waits up to a limit (`None`: still
running). A started program is killed if the Selka program ends first. See
[starting a program without waiting](io.md#starting-a-program-without-waiting).

`process.run_within(proc, request, millis, log_path, grace_millis)` is `run` with a time limit: it starts the program
with both output streams in the file `log_path`, in the order written (as `>LOG 2>&1`), waits up to `millis`
milliseconds, and answers `Some` with how it ended (read its output from the file), or `None` when the limit passed
and `stop` ended it (`SIGTERM`, the grace, then `SIGKILL`). On a scripted Process the rule's `Output`, output included,
answers and no file is written.

`process.start_to(proc, request, stdout, stderr)` is `start` with a `Destination` for each output stream: `Discard`
(`/dev/null`), `File(path)` (emptied when the program starts) or `Caller`, which lets the program write straight to this
program's own standard output (for `stdout`) or standard error (for `stderr`) while it runs, as a shell's default does, so a
compiler's or `git`'s output shows live. What this program printed first is flushed before the program starts. See
[letting a started program write to the caller's streams](io.md#letting-a-started-program-write-to-the-callers-streams).

`process.group()` makes a `Group`: a sealed linear owner of any number of started programs, which a `Child` cannot be kept
in. `group_start` and `group_start_to` start a program into it as `start` and `start_to` do and answer its key (0, 1, 2,
...); `group_wait_any_within` and `group_wait_any` answer the key and the exit status or signal of the first program to end
(a program that ended unseen is not lost; the wait sleeps until one ends); `group_signal` and `group_signal_all` signal one
program or all, each in a process group of its own, so what it started gets the signal too; `group_stop` ends them all
(`SIGTERM`, a grace, `SIGKILL`); `group_size` counts the programs no wait has answered; and `group_close(proc, own g, grace)`
stops what is still running and ends the group. See [running several programs at
once](io.md#running-several-programs-at-once-a-group), with a runnable example.

A test's `proc: Process` parameter and `process.scripted(rules)` are **scripted Processes**: they start nothing, and
`process.run` on one logs the request and answers from the first `Rule` that covers it (its `program`, an optional
`args` prefix, a `Reply` and an optional `times` count), or fails `Failed("scripted Process has no rule for [argv]")`.
`process.expect(proc, rule)` adds a rule, `process.calls(proc)` returns the logged requests, oldest first, and
`process.exited(code, stdout, stderr)` builds the `Output` of a program that exited. A scripted Process answers
`executable_path` with `SCRIPTED_EXECUTABLE_PATH`. See
[testing code that runs programs](io.md#testing-code-that-runs-programs) for the matching rules.

`process.stop_requested(stop)` reads a `Stop`, the capability a `main` declares to hear SIGTERM and SIGINT instead of
dying of them: it turns true at the first stop and stays true, and a second signal ends the program.
`process.simulated_stop()` is a stand-in no signal reaches, which a test also gets for a `Stop` parameter, and
`process.request_stop(stop)` delivers the notice to it and to every copy (on the real `Stop`, the program asks itself to
stop). Needs no grant. See [hearing a stop](io.md#hearing-a-stop) for what each wait does when a stop arrives.

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

`buildkit` is for build programs: the `build.selka` of a project, which [`selka do STEP`](tooling/native-build.md#build-programs-selka-do)
finds and runs. It is not named `build` because a project's own `build/` folder and `build.selka` would hide a standard
module of that name. Every function takes the capabilities it uses as parameters, so a test hands it a scripted
`Process`, an in-memory `Filesystem` and `streams.memory()`, and nothing starts.

`buildkit.locate(env)` answers the `Tools` that `selka do` set in the environment: the compiler that started the
program, the Zig it uses and the project's root (the folder of `build.selka`). A program started another way has none of
them, and `locate` fails naming the first one missing and saying to start it with `selka do STEP`.

A `Command` is an argument list, the folder it runs in (`""` keeps the caller's), a time limit in milliseconds (0 waits
as long as it takes), the file its output goes to under a limit (a limit needs one), and a root that the printed line
leaves off its paths. `buildkit.run(proc, fs, out, command)` prints `$ ` and the command's line (`shown`), runs it, and
answers a `Ran` (the exit status, `128` plus the signal for a signal, as a shell says, what it wrote, and whether the
limit stopped it); unless it exited with 0 in time it fails with `failure_text`: `FAILED:` and the line, the status or
the limit, and the last `TAIL_LINES` lines of each stream. `buildkit.execute` is the same without the judgement, for a
tool whose nonzero status the caller reads. Under a limit the command runs through
[`process.run_within`](#process), and its output is the log's. The files a build walks, copies and makes are
[`filesystem.walk`, `copy_file` and `mkdir_all`](#filesystem), and [`path.relative`](#path) shortens a path for the
reader.

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

`buildkit.run_steps(context, names, step, clock)` runs the named steps in order, each as `step(context, name)`, timing
each with `clock`; the first failure stops the run and the steps after it are `Skipped`. A function cannot capture, so
`context` carries what the steps share (a record of `Tools` and capabilities). `buildkit.summary(out, outcomes)` prints
one line a step (`ok      check             6.8 s`, `FAILED  images ...`, `skipped verify`), then a failed step's
message, and answers whether every step was done, so a build's `all` is a list of names:

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

The compiler's own commands that a build runs have their argument lists built in one tested place: `check_argv`
(`selka check TARGET OPTIONS`), `tests_argv`, `fmt_check_argv` (`selka fmt FILE --check`), `build_argv` (`selka build
SOURCE -o OUTPUT OPTIONS`), `packages_lock_argv` (`selka packages lock MANIFEST --output LOCK`) and `packages_build_argv`
(`selka packages build ENTRY --lock LOCK --command COMMAND -- OPTIONS`), each starting with `tools.compiler`.

## argparse

`argparse` parses a command line for a Selka tool against a spec the tool declares. It is pure: it reads no
environment and exits nothing, so `main(args: str[], ...)` hands it the arguments and decides what a mistake
costs. Declare the spec with `argparse.new(program, summary)` and the `add_*` functions, each taking the spec with the
call-site `mut` marker; `argparse.parse(spec, items)` returns a `Parsed` or fails with an `argparse.Error`.

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

A flag is `--name` (and `-s` when it has a one-character short name); an option takes a value as
`--name VALUE`, `--name=VALUE`, `-s VALUE`, `-s=VALUE` or `-sVALUE`, and takes the next word whatever it looks like. Short flags
cluster (`-jv`), and an option ends a cluster by taking the rest of it. `--` ends the options and a lone `-` is a
positional. The last value of a repeated option wins in `get`, and `get_all` keeps them all in order. `-h` and
`--help` are always declared: they set `Parsed.help` and skip the missing-positional check, and
`help_text` prints the usage line, the summary, the positional arguments and the options, each aligned and ending in a
newline. A mistake is the `Err` value, named by the `message` text (`unknown option --nope`); the tool prints it with the
usage line and chooses its exit status. Long options are not abbreviated. A program with commands (`tasks --db F add TITLE
--prio 2`) is the next subsection.

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

A program of the form `tasks [--db PATH] COMMAND [ARGS]` has a `Commands` value: the options that come before the
command word live in `program.global` (declare them with the same `add_flag` and `add_option` functions, on
`mut program.global`; a positional declared there is not used), and each command has a spec of its own, added with
`add_command`, which copies it and renames its program to `tasks add`. The spec's summary is the command's line in the
program's help. `parse_command` reads the words before the first positional word as the program's options, takes that
word (or the one after a `--`) as the command, and reads everything after it against the command's spec. The
program's options do not follow the word. The result names the command and holds both sets.

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

A mistake carries the command it was found in: `command_message` says `unknown option --prio for command done` for an
option another command has (and for the program's own option written after the word), and `command_of(error)` is that
command, or "" when the mistake came before the word or there was no valid word. `command_usage(program, command)` and
`command_help(program, command)` give that command's usage line and help text, and the program's for "". Help is a parsed
fact as in `parse`: `-h` before the word sets `invocation.global.help` (the command is ""), after it
`invocation.local.help`, and neither checks for a missing positional. A tool prints
`command_help(program, invocation.command)` for either.

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

`logging` writes a program's own messages: an event is a level, a message and typed fields, written as one line on a
`Stream` the program already holds (`logging.new(err)`). It reads no environment, opens no file and prints a time only
when it is given a `Clock` whose wall time is granted (`--allow-clock` under `--restrict`); the level comes from text the program passes (`logging.parse_level`). The whole guide, with
the line format, the quoting and escapes, the JSON form and the rules for tasks, is [logging](logging.md)
(`selka docs logging`).

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

Each setting answers a changed copy and leaves its logger as it was. A level function does nothing when the logger does
not show that level, but its arguments are built before the call, so `enabled` is the way to skip an expensive message.
A line is `TIME LEVEL NAME: message key=value ...` in text (the time only with a clock, the name only when set) or one
JSON object with `time`, `level`, `logger` and `message` first. A value is quoted when it is empty or holds a space, an
`=`, a `"` or a control byte; inside quotes and in the message, a newline, a return, a tab, a `"`, a `\` and any other
control byte are written as escapes, so one event is always one line. An event is built whole and flushed: a failed
write to standard error is ignored and a failed write to standard output traps `R_OUTPUT`, as `print` does; a reader that
has gone from either ends the program quietly with status 141 ([stream](io.md#stream)). A task
cannot log, since it holds no capability: it returns an `Event` from `logging.event`, and the caller writes it after the
group with `logging.write`.

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

`flate` decompresses the DEFLATE family: `flate.inflate(data, limit)` reads a raw stream (RFC 1951),
`flate.zlib_decode(data, limit)` a zlib stream (RFC 1950) and `flate.gunzip(data, limit)` gzip data (RFC 1952). Each
returns the decompressed `bytes` or fails with a message that says what is wrong: a truncated stream, a reserved block
type, a stored block whose length and complement disagree, a Huffman code that is over-subscribed or incomplete, a
distance that reaches back before the start of the output, a checksum or size that does not match, or a result past
`limit`. The limit is a byte count the result may not exceed, so a few bytes of input cannot claim gigabytes of
output; pass what the caller can afford. The module only decompresses: there is no compressor in the standard library.

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

`zlib_decode` checks the header (the deflate method, the check bits) and the Adler-32 of the result and refuses a stream
that asks for a preset dictionary. `gunzip` skips the optional name, comment, extra field and header check of each
member, checks its CRC-32 and size, decompresses several members one after another to their concatenation and ignores
zero bytes after the last one; any other trailing data is refused. `crc32` and `adler32` return the checksums as
non-negative integers below 2^32, the same values zlib gives. A 34 MB gzip file (an edit-check coverage map) decompresses in
about two seconds in a debug build.

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

The one-shot functions take all the compressed bytes and return all the plain ones, so a `.tgz` costs its decompressed size
in memory. An inflater takes the compressed bytes a piece at a time and holds the 32 KiB window of the last output and
what one piece needs, never the whole result: a gzip file of 1 GiB of zeros inflates in about 6 MB. `flate.inflater(limit)`
starts a raw stream, `flate.zlib_inflater(limit)` a zlib stream and `flate.gzip_inflater(limit)` gzip data, one member or
several, each member's CRC-32 and size checked. The `Inflater` is a value: pass it with `mut`. `limit` is the most plain bytes
the whole stream may produce, and `9223372036854775807` says no limit.

`flate.feed(mut stream, piece)` takes the next piece and returns the plain bytes the stream could produce so far, which may be
none. A piece may end anywhere (inside a header, a code, a checksum), and the pieces may be of any size, a byte at a time or
whatever the caller read. A call returns about a mebibyte at most: when it returns something, call `feed` again with `b""`
until it returns nothing, to get the rest of what the piece held, and only then read the next piece. A stream that has
failed fails again with the same message at every later call. Malformed input fails with the message the one-shot function
gives, and so does a result past `limit`.

`feed` cannot know that no more input is coming. When the caller has fed all of it, `flate.ended(stream)` says whether the
stream ended cleanly (a raw or zlib stream through its last block and, for zlib, its Adler-32; a gzip stream at the end of a
member, or empty, as `gunzip` takes empty data) and `flate.finish(stream)` fails with the message that says where a stream
that did not end stopped: `unexpected end of the compressed data` inside a block, `the gzip header is cut short`, `the gzip
member is cut short` inside the trailer, `the zlib stream has the wrong length`. The streaming form refuses trailing data
where it sees it: after a raw or zlib stream, or after a gzip member when what follows zero bytes is not zero. The one-shot
functions are this inflater fed one piece, and keep their behaviour and limits.

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

`flate.crc32_update(value, data)` and `flate.adler32_update(value, data)` take the checksum of the bytes so far and give the
checksum with `data` after them, so a program that inflates in pieces itself can check a trailer: `crc32(a + b)` is
`crc32_update(crc32(a), b)` and `adler32(a + b)` is `adler32_update(adler32(a), b)`, whatever the cut. The value for no
bytes is 0 for the CRC-32 and 1 for the Adler-32.

## cache_record

`cache_record.encode(fields: str[]) -> bytes` writes canonical string-array JSON
inside a versioned SHA-256 envelope. `decode(data)` returns `Result[str[], Error]`;
`message(error)` explains a rejected record. Truncated, altered, noncanonical
and nonstring records are rejected. The checksum detects damage; it does not
authenticate an untrusted writer. Bound storage reads before decoding.

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

`persistent_memo.call(fs, options, compute, key)` returns
`Result[Lookup, Error]`, where `Lookup` holds `value: bytes` and `reused: bool`.
The callback takes `memo.Key` and permits only managed allocation. It returns
an immutable byte snapshot. Use `message(error)` to describe a failure.

Pass a filesystem capability narrowed to an existing dedicated cache directory.
`Options(max_entries, max_bytes)` accepts 0–256 entries and 0–1,048,576 raw bytes
of key plus value per entry. Zero entries forces execution without storage.
Oversized values and callbacks without a qualified `function_digest` execute
without retaining a receipt. Tags distinguish text, bytes and integer keys.

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

For native persistence, replace the stand-in and zero limit with a real narrowed
`Filesystem` and positive entry limit. Directory ownership serializes readers,
writers and eviction. Each record binds the actual callable's reachable code,
source schemas and execution context, exact tagged input, canonical byte encoding
and checksum. A malformed record is a miss; provider failures remain errors.
Lowered entry limits trim the directory deterministically. Entry count and
per-entry size bound retention; there is no TTL or ambient file freshness rule.

## durable

`durable.run(fs, request, compute)` returns `Result[Report, Error]`. A pure
`func(bytes, bytes) -> durable.Step` receives one
captured chunk and the last state snapshot; `Step(output, state)` returns bytes.
`Request(input, chunks, initial_state, output_path, max_bytes)` captures the
workflow inputs. `Report(fresh, reused, output_digest, state)` counts newly
computed and previously committed steps separately. `message(error)` describes
invalid, corrupt, incompatible, uncacheable and provider failures.

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
`test/fixtures/application-cache/application.selka`.
Its developer qualification driver runs cold, warm, edit, corruption and crash
cases against independently calculated output.


## testing

`testing` measures the work a test performs instead of its duration.
`testing.steps(work, n)` runs `work(n)`, a `func(int) -> int`, and answers the
blocks it executed — the count the test's step ceiling charges;
`testing.allocations(work, n)` answers the managed blocks the runtime allocated
for it, the event `--counters` reports as `allocs`, so a block recycled on a
thread's list free list in the inline fast path is not a new allocation.
`testing.allocations_writing(work, out, n)` does the same for a workload that
needs a `Stream` to print what it builds, such as the f-string print idiom.

`testing.growth(work, small, large)` runs both sizes and answers the larger of
the two counts' growth ratios without judging it. `testing.linear(work, small,
large)` fails when either count grows by more than 1.5× the step from `small` to
`large`: at 1,000 → 4,000 the ratio limit is 6×, so an `n log n` workload (about
4.8×) passes and a quadratic one (16×) fails; a count that is zero at both sizes
passes. `testing.constant(work, small, large)` allows 1.5× plus two counts of
slack. A failure is an assertion naming the counter, both values and the ratio.

Both sizes run inside the test's budget, so a large quadratic shape needs
`limits.test.max_steps` in `selka.json`
([work per test](tooling/guest-tests.md#work-per-test)). A program that carries
no executed-block accounting — a built binary, or `selka run` without
`--max-steps` — traps `R_NO_STEP_ACCOUNTING` when a check reads the counters;
`selka test` always counts its blocks, even under `--max-steps 0`.

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
