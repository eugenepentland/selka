# Managed byte strings

`bytes` is an immutable owned byte string: raw octets where `str` holds Unicode scalars. A `b"..."` or `b'...'` literal produces it; `len` is signed, indexing yields an `int` in `0..255`, a slice is a [view](#views-and-owned-copies), `+` concatenates, and `copy(value)` makes an independent value. An indexed byte is a number, not a one-character string: compare it with `ord("G")`. `int(text[0])` is `E_NUMERIC_PARSE`: `int` converts numbers, `ord` a character.

```selka
# doc: expect 42
func main() -> int:
    mut header = b"my"
    mut body = b"lang"
    mut whole = header + body
    if len(whole) != 6:
        return 1
    if whole[0] != ord("m"):
        return 2
    if whole[len(whole) - 1] != 103:
        return 3
    if whole[2:6] != body:
        return 4
    return whole[0] - 67
```

## Indexing, slicing and iteration

A constant negative index or endpoint is rejected; a computed negative one, or an index outside the byte string, traps `R_LIST_BOUNDS`. Endpoints above the length clamp and a reversed interval is empty, as for lists. Iteration yields `int` octets.

```selka
# doc: expect 30
func main() -> int:
    mut frame = b"\x01\x02\x03\x04"
    if len(frame[2:99]) != 2:
        return 1
    if len(frame[max(len(frame) - 1, 0):0]) != 0:
        return 2
    if frame[len(frame) - 2] != 3:
        return 3
    mut total = 0
    for value in frame:
        total += value
    for index, value in enumerate(frame):
        total += index * value
    return total
```

## Membership and equality

`==` and `!=` compare content. `in` and `not in` take an `int` (one byte) or a `bytes` (a subsequence). `bytes.find(data, needle)` returns the first index or `-1`; `bytes.starts_with` and `bytes.ends_with` test the ends without copying.

```selka
# doc: expect 15
import bytes

func main() -> int:
    mut record = b"GET /index.html"
    if not bytes.starts_with(record, b"GET "):
        return 1
    if bytes.ends_with(record, b".css"):
        return 2
    if bytes.find(record, b"/index") != 4:
        return 3
    if bytes.find(record, b"?query") != -1:
        return 4
    if 47 not in record:
        return 5
    if b"html" not in record:
        return 6
    if record == b"GET /":
        return 7
    return len(record)
```

## Searching a byte set

`bytes.find_any(b, values, start)` answers the first index at or after `start` whose octet is in the set `values`, or `-1` (an empty set finds nothing, and a `start` at or past `len(b)` answers `-1`). A negative `start` is `E_NEGATIVE_INDEX_REMOVED` as a constant and traps `R_LIST_BOUNDS` computed.

`find_any(b, values, start, end)` searches `[start, end)` as `bytes.find` does: an octet at `end - 1` is found, one at `end` is not, an `end` past `len(b)` is `len(b)`, an `end` at or before `start` answers `-1`, and a negative `end` is treated like a negative `start`. Offsets count from the first octet of `b`.

```selka
# doc: expect 24
import bytes

func main() -> int:
    mut record = b"GET /index.html HTTP/1.1"
    if bytes.find_any(record, b" \r\n", 4) != 15:
        return 1
    if bytes.find_any(record, b"/", 5) != 20:
        return 2
    if bytes.find_any(record, b"?", 0) != -1:
        return 3
    if bytes.find_any(record, b"", 0) != -1:
        return 4
    if bytes.find_any(record, b"G", 0) != 0:
        return 5
    if bytes.find_any(record, b" ", 0, 3) != -1 or bytes.find_any(record, b" ", 0, 4) != 3:
        return 6
    return len(record)
```

## Testing a byte against a set or a range

- **One of a set.** `c in b"+-/%"` is true when `c` is one of the four octets and reads `c` once. An `int` outside `0..255` is in no set; `not in` negates.
- **Between two values.** `48 <= c <= 57` evaluates the middle operand once; any run of `<`, `<=`, `>`, `>=` and `==` chains (`low < c <= high`).

```selka
# doc: expect 3 2 1
func is_sign(c: int) -> bool:
    return c in b"+-"


func is_digit(c: int) -> bool:
    return 48 <= c <= 57


func main(out: Stream) -> int:
    mut text = b"-12+a"
    mut signs = 0
    mut digits = 0
    mut other = 0
    for c in text:
        if is_sign(c):
            signs += 1
        elif is_digit(c):
            digits += 1
        else:
            other += 1
    print(out, signs + other, digits, other)
    return 0
```

`selka lint` reports the long spellings (`c == 43 or c == 45`, `c >= 48 and c <= 57`) as `L_BYTE_SET` and `L_RANGE_CHAIN`, and `selka fix` rewrites them where the value is a plain name, field or index and the bytes are integer literals.

## Character codes by name

`ord("=")` and `b"="[0]` name a character code and fold at compile time, so a constant and a `match` arm can use them:

- `ord` takes a text literal of exactly one byte below `0x80` (`ord("é")` is `E_CONSTANT_EXPRESSION` in a constant and `E_LITERAL_ARM` in an arm); the second form is a text or bytes literal indexed by an integer literal inside it. `ord(text)` and `data[0]` are not constants.
- An arm takes the type of the matched integer, so `case ord("a"):` matches a `u8` and refuses a byte the type cannot hold; `ord("+") | ord("-")` lists alternatives, and a repeat is `E_DUPLICATE_ARM`.

```selka
# doc: expect 3 2 1
const EQUALS: int = ord("=")
const QUOTE: int = ord('"')


func kind(ch: int) -> int:
    match ch:
        case ord("+") | ord("-"):
            return 1
        case ord("*"):
            return 2
        case EQUALS:
            return 3
        case _:
            return 0


func main(out: Stream) -> int:
    print(out, kind(EQUALS), kind(ord("*")), kind(b"-"[0]))
    return 0
```

## Walking the lines of a file

Read the file once with `fs.read_file(path)` (`Result[bytes, str]`) and walk the buffer with offsets, not `split`: `find_any(b"\n", start)` ends the current line, the next starts one byte later, and a last line without a newline ends at `len(data)`. A slice `data[start:end]` that is only read (bound to a local, passed to a `bytes` parameter, written to a stream) copies nothing; a line you keep takes `copy(data[start:end])`. `split(b"\n")` copies every line first; `bytes.parse_int_range(data, start, end)` reads a number in place.

The loop skips blank lines and `#` comments, drops a carriage return and counts distinct lines.

```selka
# doc: allow-read notes
# doc: expect 3 5 3
# doc: expect 4 5 3
import bytes
import dicts

record Summary:
    lines: int
    longest: int
    distinct: int


func summarize(data: bytes) -> Summary:
    mut lines = 0
    mut longest = 0
    mut counts: dict[bytes, int] = {}
    mut start = 0
    while start < len(data):
        mut end = bytes.find_any(data, b"\n", start)
        mut after = end + 1
        if end < 0:
            end = len(data)
            after = len(data)
        if end > start and data[end - 1] == ord("\r"):
            end -= 1
        if end > start and data[start] != ord("#"):
            const line = data[start:end]
            lines += 1
            longest = max(longest, len(line))
            counts[line] = dicts.get(counts, line, 0) + 1
        start = after
    return Summary(lines=lines, longest=longest, distinct=len(counts))


func main(fs: Filesystem, out: Stream) -> int:
    match fs.read_file("lines.txt"):
        case Ok(data):
            const file = summarize(data)
            print(out, file.lines, file.longest, file.distinct)
        case Err(message):
            print(out, message)
            return 1
    const cases = summarize(b"alpha\nbeta\n\n# note\ngamma\r\nalpha")
    print(out, cases.lines, cases.longest, cases.distinct)
    return 0
```

## Splitting and joining

`bytes.split(data, separator)` returns `list[bytes]`, keeping leading and trailing empty pieces; `bytes.join(parts, separator)` rebuilds a byte string. `bytes.replace(data, old, new)` replaces every non-overlapping occurrence of `old` from the front, as `strings.replace` does, leaving `data` unchanged. An empty separator or `old` is rejected at runtime.

```selka
# doc: expect 11
import bytes

func main() -> int:
    mut line = b"name,age,city"
    mut fields = bytes.split(line, b",")
    if len(fields) != 3:
        return 1
    if fields[1] != b"age":
        return 2
    if bytes.join(fields, b",") != line:
        return 3
    mut widths = 0
    for field in fields:
        widths += len(field)
    return widths
```

## Converting between bytes, integers and text

`bytes(values)` builds a byte string from a `list[int]`; a value outside `0..255` traps `R_BYTE_RANGE`. `bytes.to_list(b)` returns the octets as a `list[int]`.

```selka
# doc: expect 177
import bytes

func main() -> int:
    mut values: int[] = [72, 105]
    mut greeting = bytes(values)
    if greeting != b"Hi":
        return 1
    mut octets = bytes.to_list(greeting)
    if len(octets) != 2:
        return 2
    if octets[1] != 105:
        return 3
    return octets[0] + octets[1]
```

`strings.encode(s)` produces the UTF-8 bytes of a `str` (there is no `s.encode()`). `strings.decode(b)` answers `Result[str, str]`, the error describing the invalid sequence. `str(b)` is not provided, so a byte string never turns into its debug spelling by accident.

```selka
# doc: expect 6
import strings

func text_of(raw: bytes) -> str fails str:
    return try strings.decode(raw)


func main() -> int:
    mut encoded = strings.encode("héllo")
    if len(encoded) != 6:
        return 1
    match text_of(encoded):
        case Ok(value):
            if value != "héllo":
                return 2
        case Err(message):
            return 0 - strings.char_count(message)
    match text_of(b"\xff"):
        case Ok(other):
            return 0 - strings.char_count(other)
        case Err(message):
            return len(encoded)
```

`hex.encode(b)` renders lowercase hexadecimal text (the method `b.hex()` is `E_METHOD_REMOVED`); `bytes.fromhex(s)` parses it back as `Result[bytes, str]`, failing on odd lengths and non-hexadecimal digits.

```selka
# doc: expect 54
import hex
import strings

func parse(digits: str) -> bytes fails str:
    return try bytes.fromhex(digits)


func main() -> int:
    mut raw = b"\x0f\xa0"
    if hex.encode(raw) != "0fa0":
        return 1
    match parse("0fa0"):
        case Ok(value):
            if value != raw:
                return 2
        case Err(message):
            return 0 - strings.char_count(message)
    match parse("0f0"):
        case Ok(value):
            return 0 - len(value)
        case Err(message):
            return strings.char_count(message)
```

## Storing byte strings

`bytes` nests in `list[bytes]`, `dict[str, bytes]`, record fields and `Option` and `Result` payloads. Move owned bytes in, or `copy(value)` when the original must remain usable. Dictionary keys may be `bytes` as well as `int` and `str`: `dict[bytes, int]` is an ordinary counting table (see [hashable keys](sets.md#hashable-keys)).

```selka
# doc: expect 6
record Packet:
    kind: str
    payload: bytes


func main() -> int:
    mut packets: Packet[] = [Packet(kind="hello", payload=b"\x01"), Packet(kind="data", payload=b"\x02\x03")]
    mut index: dict[str, bytes] = {}
    for packet in packets:
        index[packet.kind] = copy(packet.payload)
    if len(index) != 2:
        return 1
    if index["data"] != b"\x02\x03":
        return 2
    mut alias = copy(packets[1])
    if alias.payload != packets[1].payload:
        return 3
    mut total = 0
    for value in index["data"]:
        total += value
    return total + len(index["hello"])
```

## Contracts and boundaries

Byte strings are immutable: no `b[i] = value`, no `append`. `+`, a slice, `split`, `join` and every conversion build a fresh value with the transitive `managed_allocation` effect, so a `noalloc` function cannot construct them; build octets in place with `byte_buffer`. `bytes` is accepted in exported signatures but not at wire boundaries: JSON encoding and decoding reject it (`E_JSON_CODEC`), and so does an `extern func` signature (`E_EXTERN_SIGNATURE`).

## Views and owned copies

A slice `b[start:end]` is a view of the owner's bytes: it borrows without extending the owner's lifetime, so keep the owner alive and do not move or mutate it while the slice is in use (the checker rejects that and offers the `copy(value)` repair). `copy(view)` makes owned bytes that outlive the owner. A slice bound to a local allocates nothing to read; a stored or returned slice is refused until written `copy(value)`; a compared slice copies at that point. Parse numbers with the range parsers below, or copy the slice first.

```selka
# doc: expect 42
func strip_quotes(line: bytes) -> bytes:
    if len(line) < 2 or line[0] != 34:
        return copy(line)
    return copy(line[1:len(line) - 1])


func main() -> int:
    mut line = b'"content-length: 42"'
    mut field = strip_quotes(line)
    if field != b"content-length: 42":
        return 1
    const name = field[0:14]
    mut owned = copy(name)
    if owned != b"content-length" or len(name) != 14:
        return 2
    if field[16:18] != b"42":
        return 3
    # Clamping matches a slice; an explicit offset selects the final bytes.
    if field[len(field) - 2:99] != b"42":
        return 4
    if owned != b"content-length" or owned == b"content-lengt":
        return 5
    if line == field or len(line) != 20:
        return 6
    return len(name) + len(owned) + len(field[16:18]) + 12
```

## Fixed-width reads

`bytes.read_u16_be(data, offset)` and its siblings read one fixed-width integer or float at `offset`:

| Functions | Reads |
|---|---|
| `read_u16`, `read_u32`, `read_u64`, `read_i16`, `read_i32`, `read_i64` | each with `_be` (most significant octet first) or `_le` |
| `read_f32_le`, `read_f64_le` | floats, little-endian only |
| `read_u8`, `read_i8` | one octet, no byte order, with the same bounds check |

An offset below zero, or whose octets do not all lie inside `data`, traps `R_LIST_BOUNDS`. The offset counts from the first octet of `data` (an owned value, a `bytes` parameter or a slice), so a function that receives a view reads it from its own start. Reads never copy.

```selka
# doc: expect 42
import bytes
import strings

func main() -> int:
    const data = strings.encode("ABCD")
    if bytes.read_u32_be(data, 0) != 1094861636u32:
        return 1
    if bytes.read_u16_be(data, 2) != 17220u16:
        return 2
    if bytes.read_u16_le(data, 2) != 17475u16:
        return 3
    const signed = bytes([255, 254])
    if bytes.read_i16_be(signed, 0) != i16(-2):
        return 4
    if bytes.read_u8(data, 3) != 68u8 or bytes.read_i8(signed, 0) != i8(-1):
        return 5
    return 42
```

```selka
# doc: expect 42
import bytes
import strings

func third_word(data: bytes) -> u16:
    return bytes.read_u16_be(data, 2)

func main() -> int:
    const data = strings.encode("ABCDEFGH")
    if third_word(data) != 17220u16:
        return 1
    if bytes.read_u16_be(data[2:], 0) != 17220u16:
        return 2
    return 42
```

### A `byte_buffer` does not take these reads

The fixed-width reads and `bytes.replace` take `bytes` only: a `byte_buffer` given to one is `E_TYPE`, `expected bytes, found byte_buffer`. The searches, splits, trims and number parses of the `bytes` module take a buffer and read it in place.

```selka
# doc: expect-error E_TYPE
import buffers
import bytes

func main(out: Stream) -> int:
    mut buf = buffers.empty()
    buffers.append(mut buf, b"abcdefgh")
    print(out, bytes.read_u64_le(buf, 0))
    return 0
```

For a wider read of a buffer, `bytes(buf[i:i + 8])` copies just those octets, where `bytes(buf)`, the repair the message names, copies the whole buffer; `buf[i]` reads one octet with no copy. Octets read word by word and never written are better held as `bytes`.

```selka
# doc: expect 7523094288207667809
import buffers
import bytes

func main(out: Stream) -> int:
    mut buf = buffers.empty()
    buffers.append(mut buf, b"abcdefgh")
    print(out, bytes.read_u64_le(bytes(buf[0:8]), 0))
    return 0
```

## Embedding a file at compile time

`embed_bytes("path")` answers a project file's contents as `bytes` and `embed_str("path")` as `str` (valid UTF-8). The compiler reads the file while it loads the program and stores it in the executable as static data, so the program needs no `Filesystem` capability and cannot fail to find its data. Every byte is kept, NUL included.

The argument must be one plain string literal (a variable, `b"..."`, a second argument or a computed path is `E_EMBED_ARGUMENT`); the path uses `/` and is relative to the source file that spells the call. Embed as the whole initializer of a module constant: the file is read once and reading the constant allocates nothing.

```selka
# doc: project embedding
# doc: file words.txt
alpha
beta
gamma
```

```selka
# doc: project embedding
# doc: file main.selka
# doc: expect 3
import strings

const WORDS: str = embed_str("words.txt")


func main() -> int:
    mut text = WORDS
    mut total = 0
    for line in strings.split(text, "\n"):
        if strings.char_count(line) != 0 and strings.char_at(line, 0) != "#":
            total += 1
    return total
```

Every failure is reported at the string literal, before the program runs:

| Code | When |
|---|---|
| `E_EMBED_ARGUMENT` | not exactly one string literal |
| `E_EMBED_PATH` | the path is empty or holds a NUL byte or backslash |
| `E_EMBED_ABSOLUTE` | the path starts with `/` |
| `E_EMBED_ESCAPE` | the path leaves the project root through `..` or a symlink |
| `E_EMBED_MISSING` | there is no such file |
| `E_EMBED_DIRECTORY` | a directory or other non-regular file |
| `E_EMBED_UNREADABLE` | the file cannot be read |
| `E_EMBED_TOO_LARGE` | the file is over 16 MiB |
| `E_EMBED_UTF8` | `embed_str` of a file that is not UTF-8 (names the byte offset) |
| `E_EMBED_UNAVAILABLE` | the source was not loaded from a directory |

The project root is the directory of the nearest `selka.json` above the entry file, else the entry's directory. `..` may climb inside the root (`embed_bytes("../shared/table.bin")` from `lib/data.selka`); a path or symbolic link that leaves it is `E_EMBED_ESCAPE`. A link that stays inside is followed.

```selka
# doc: expect-error E_EMBED_MISSING
func main() -> int:
    return len(embed_bytes("no-such-file.bin"))
```

Editing an embedded file rebuilds only what embeds it. Project `budgets.max_file_bytes` bounds each source or embedded file and `budgets.max_total_bytes` all loaded source bytes plus every embedded file; exceeding one is `E_PROJECT_BYTES` at the embed literal, naming the budget field to raise. The 16 MiB embed limit still applies when the project allows a larger file.

## Counting characters and parsing numbers

`bytes.scalar_count(b)` answers `Result[int, str]`, the number of Unicode scalars, validated in the same pass. An invalid sequence (overlong, surrogate, above U+10FFFF, truncated, stray continuation byte) answers `Err` with the decoder's reason. It may allocate the error string, so `noalloc` does not accept it.

`bytes.parse_int_range(b, start, end)`, `bytes.parse_float_range(b, start, end)` and `bytes.scalar_count_range(b, start, end)` work on offsets you hold, without a slice. Negative endpoints follow the index rule (`E_NEGATIVE_INDEX_REMOVED` constant, `R_LIST_BOUNDS` computed); upper endpoints clamp; invalid grammar and overflow answer `None`, malformed UTF-8 `Err`.

`bytes.parse_int(b)` and `bytes.parse_float(b)` answer `Option[int]` and `Option[float]` through the pinned grammar of `parse_int(text)` and `parse_float(text)` (see [text](text.md#parsing-numbers-from-text)); an overflowing integer is `None`. Neither allocates, so `noalloc` may call them. That grammar is wider than most protocol integers, so a strict parser checks the octets first:

| `bytes.parse_int` accepts | It answers `None` for |
|---|---|
| a leading `+` or `-`; ASCII whitespace either side (space, tab, line feed, carriage return, vertical tab, form feed); leading zeros (`b"007"` is 7); one `_` between two digits (`b"1_000"`); `b"-0"` | empty data, a bare sign, `b"+-5"`, a space between sign and digits or inside the number, a `_` at either end or doubled, `0x10`, `1e3`, `1.0`, a non-ASCII digit or space, a NUL octet, a value outside `-9223372036854775808` to `9223372036854775807` |

```selka
# doc: expect Some(5) Some(5) Some(7) Some(1000) Some(0)
# doc: expect None None None None
import bytes

func main(out: Stream) -> int:
    print(out, bytes.parse_int(b"+5"), bytes.parse_int(b" 5\n"), bytes.parse_int(b"007"), bytes.parse_int(b"1_000"), bytes.parse_int(b"-0"))
    print(out, bytes.parse_int(b"1e3"), bytes.parse_int(b"5 6"), bytes.parse_int(b"9223372036854775808"), bytes.parse_int(b""))
    return 0
```

```selka
# doc: expect 42
import bytes

func measure(raw: bytes) -> int:
    match bytes.scalar_count(raw):
        case Ok(width):
            return width
        case Err(_):
            return 0 - 1


func main() -> int:
    mut ascii = b"hello"
    if measure(ascii) != 5:
        return 1
    mut mixed = b"a\xce\xbbb\xf0\x9f\x98\x80c"
    if measure(mixed) != 5:
        return 2
    if measure(b"\xff") != 0 - 1:
        return 3
    if measure(b"\xc0\xaf") != 0 - 1 or measure(b"\xce") != 0 - 1:
        return 4
    match bytes.parse_int(b"  -12  "):
        case Some(value):
            if value != 0 - 12:
                return 5
        case None:
            return 6
    match bytes.parse_float(b"2.5e1"):
        case Some(value):
            if value != 25.0:
                return 7
        case None:
            return 8
    match bytes.parse_int(b"12a"):
        case Some(_):
            return 9
        case None:
            pass
    const token_source = b"size=2.5mm"
    const token = token_source[5:8]
    match bytes.parse_float(token):
        case Some(value):
            if value != 2.5:
                return 10
        case None:
            return 11
    return measure(ascii) + 37
```

## Writing octets in place

`byte_buffer` is the mutable sibling of `bytes`: the same elements, length, indexing, iteration, comparison and search, no `+`, and a growable backing. Eight methods write into it:

| Method | Appends |
|---|---|
| `append(data)` | every octet of `data` |
| `append_byte(value)` | one octet |
| `append_range(data, start, end)` | `data[start:end]` |
| `append_array(array, start, end)` | `array[start:end]` of a `FixedArray[u8, N]`, such as a `network.Read[N]` chunk's `bytes` |
| `append_utf8(text)` | the UTF-8 octets of a `str` |
| `append_int(value)`, `append_float(value)` | the integer's digits, the float's spelling (byte for byte what `str(value)` prints) |
| `reserve(extra)` | nothing: spare capacity |

Each answers a `bool`: true when it accepted the request. `append_byte` rejects a value outside `0..255`; `append_range` and `append_array` return `False` for nonnegative endpoints whose `end` is below `start` or past `len(data)` (or `N`); `reserve` rejects a negative count; a negative range endpoint traps `R_LIST_BOUNDS`. A refusal writes nothing, and an active read borrow must end before a mutation.

`write(out, buffer)` writes what the buffer holds with no copy and contributes the `output` effect. `buffers.clear(mut buffer)` empties it and keeps its capacity, so one buffer serves every chunk of a loop.

A slice `buffer[start:end]` is a new `byte_buffer` of just those octets (a buffer can grow under a view, so it has no borrowed slice); printing, a format hole, `len`, a loop, an index, `hex.encode`, a membership test and a comparison read that copy. `copy(buffer[1:3])` names it as a buffer you can write to, pass, return and store. `const piece = buffer[1:3]` is `E_BUFFER_SLICE_NAME`: write `copy(buffer[1:3])` or `bytes(buffer[1:3])`, an owned immutable copy that a `bytes` parameter takes.

```selka
# doc: expect 7861 2 b'xa'
import hex


func main(out: Stream) -> int:
    const buffer = byte_buffer([120, 97, 122])
    print(out, hex.encode(buffer[0:2]), len(buffer[1:3]), buffer[0:2])
    return 0
```

```selka
# doc: expect b'bc!' 3 b'abcd'
import buffers


func main(out: Stream) -> int:
    mut buffer = byte_buffer([97, 98, 99, 100])
    mut piece = copy(buffer[1:3])
    buffers.append(mut piece, b"!")
    print(out, bytes(piece), len(piece), bytes(buffer))
    return 0
```

A `b"..."` literal, a slice and a view are read-only, and `bytes(buffer)` makes an owned immutable snapshot that stays unchanged when the buffer grows later. Build a buffer with `byte_buffer(values)` from a `list[int]` (the [`byte_builder`](standard-library.md#byte_builder) module wraps one).

```selka
# doc: expect 42
import buffers

func main() -> int:
    mut empty: int[] = []
    mut buffer = byte_buffer(empty)
    if not buffers.append_range(mut buffer, b"hello world", 0, 5):
        return 1
    if not buffers.append_byte(mut buffer, 44):
        return 2
    buffers.append_utf8(mut buffer, " λ")
    buffers.append_int(mut buffer, 0 - 7)
    buffers.append_float(mut buffer, 2.5)
    mut snapshot = bytes(buffer)
    if not buffers.reserve(mut buffer, 64):
        return 5
    if not buffers.append_byte(mut buffer, 33):
        return 6
    if snapshot != b"hello, \xce\xbb-72.5" or bytes(buffer) != snapshot + b"!":
        return 7
    return len(snapshot) + 28
```

```selka
# doc: expect 11
func main() -> int:
    mut empty: int[] = []
    mut buffer = byte_buffer(empty)
    mut chunk = FixedArray[u8, 40]([72u8, 105u8, 33u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8])
    if not buffer.append_array(chunk, 0, 3):
        return 1
    if buffer.append_array(chunk, 3, 41):
        return 2
    if buffer != b"Hi!":
        return 3
    return len(buffer) + 8
```

A `b"..."` literal is a fixed `[N]u8` array where an array annotation demands one, and `bytes` elsewhere.

## Byte literals

`b"..."` and `b'...'` differ only in the quote character. The escapes are `\n`, `\r`, `\t`, `\0`, `\\`, `\"` and exactly two hexadecimal digits after `\x`; any other escape, and an unterminated literal, is an error. Text outside an escape contributes its UTF-8 encoding, so `b"é"` is two bytes.

A text or bytes literal is limited to 65,536 decoded bytes (`E_BYTE_LITERAL_LIMIT`). Hold more in a constant that joins shorter ones with `+` (folded at compile time, up to 1 MiB; see [module constants](module-constants.md)), or [embed a file](#embedding-a-file-at-compile-time).

```selka
# doc: expect 42
func main() -> int:
    if b'ok' != b"ok":
        return 1
    mut escapes = b"\x2a\t\n\r\0\\\""
    if len(escapes) != 7:
        return 2
    if escapes[4] != 0 or escapes[6] != 34:
        return 3
    if len(b"") != 0 or len(b"é") != 2:
        return 4
    return escapes[0]
```

See the [Python text surface](python-text-surface.md) for stable bytes sorting, trim sets, ranged search and scalar repr.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/bytes.md).
