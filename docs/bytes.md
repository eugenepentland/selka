# Managed byte strings

`bytes` is an immutable owned byte string, usable wherever a managed value is
allowed. Checked ownership controls moves and borrows; `copy(value)` makes an
independent owned value. Where
`str` holds Unicode scalar values, `bytes` holds raw octets, so byte-oriented
code no longer needs fixed `[N]u8` arrays or explicit
`u8` literals.

A `b"..."` or `b'...'` literal produces `bytes`. `len` is signed, indexing yields
an `int` in `0..255`, slicing copies a byte range, and `+` concatenates.

An indexed byte is a number, not a one-character string, so name a character with
`ord`: `data[0] == ord("G")` compares the first byte with the code of `G`, and
`ord(text[0])` gives the same code for the first character of a `str`.
`int(text[0])` is `E_NUMERIC_PARSE`: `int` converts numbers, and `ord` converts a
character.

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

Escapes follow the byte-literal rules exactly: `\n`, `\r`, `\t`, `\0`, `\\`,
`\"` and two hexadecimal digits after `\x`. A literal is limited to 65,536
decoded bytes. Source text outside escapes contributes its UTF-8 encoding, so
`b"é"` is two bytes.

## Indexing, slicing and iteration

A constant negative index or slice endpoint is rejected. A dynamically negative
index or endpoint, or an index outside the byte string, traps with `R_LIST_BOUNDS`. Use `data[len(data) - 1]` for the last byte. Slice endpoints
above the length clamp to the length and reversed intervals produce an empty result,
matching list slices. Iteration borrows the byte string and yields `int` octets;
the owner must remain available while the borrow is live.

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

`==` and `!=` compare content, never identity. `in` and `not in` accept either an
`int`, testing for a single byte, or a `bytes` value, testing for a contiguous
subsequence. `bytes.find(data, needle)` returns the first index of a subsequence
or `-1`, and `bytes.starts_with` / `bytes.ends_with` test the ends without copying.

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

`bytes.find_any(b, values, start)` answers where the next octet from a *set* begins.
`values` is a byte set rather than a sequence, so its order and its repeats do not
matter and an empty set finds nothing. The answer is the first index at or after
`start` whose octet occurs anywhere in `values`, or `-1` when the rest of the
receiver holds none. A constant negative `start` reports
`E_NEGATIVE_INDEX_REMOVED`; a computed negative start traps `R_LIST_BOUNDS`.
A nonnegative `start` at or past `len(b)` answers `-1`. This is how a scanner names any
one of several terminators without first copying the bytes that remain.

`bytes.find_any(b, values, start, end)` searches only `[start, end)`, as `bytes.find(b, needle, start, end)` does, so
the next delimiter inside one line of a large buffer is found without reading past the line: an octet at `end - 1`
is found and one at `end` is not, an `end` at or past `len(b)` is `len(b)`, and an `end` at or before `start`
answers `-1`. The offset it answers still counts from the first octet of `b`. A negative `end` is refused or
traps as a negative `start` is.

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

A scanner asks two questions of a byte constantly: is it one of these, and is it between these. Both have a short form.

- **One of a set.** `c in b"+-/%"` is true when the integer `c` is one of the four octets. It reads `c` once and takes
  the set from a byte string, so it replaces `c == 43 or c == 45 or c == 47 or c == 37`. Write a byte that is not
  printable with an escape (`b" \t\r\n"`). An `int` outside `0..255` is in no set, and `not in` is the negation.
- **Between two values.** A comparison chain, `48 <= c <= 57`, is true when both comparisons are, and evaluates the
  middle operand once. It replaces `c >= 48 and c <= 57`, and it chains any run of `<`, `<=`, `>`, `>=` and `==`
  (`low < c <= high`).

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

`selka lint` reports the long spellings as `L_BYTE_SET` and `L_RANGE_CHAIN`, and `selka fix` rewrites them. Both rules
read only the cases where the rewrite cannot change the program: the value is a plain name, field or index whose evaluation
has no effect, and the bytes are integer literals.

## Character codes by name

A scanner compares bytes with character codes, and `61` says nothing until the reader recalls it is `=`. `ord("=")`
is that number, and so is `b"="[0]`, the first octet of a literal. Both fold at compile time where a value is
needed, so a module constant and a literal `match` arm can name the character:

- the argument of `ord` is a text literal of exactly one byte, below `0x80` (`ord("é")` is two bytes and keeps its
  diagnostic, `E_CONSTANT_EXPRESSION` in a constant and `E_LITERAL_ARM` in an arm);
- the second form is a text or bytes literal indexed by an integer literal inside it; an index past the literal
  keeps the diagnostic;
- an arm takes the type of the matched integer, so `case ord("a"):` matches a `u8` as well as an `int`, and refuses a byte
  the type cannot hold; `ord("+") | ord("-")` lists alternatives, and a repeat reports `E_DUPLICATE_ARM` by value;
- a call or an index that is not a literal (`ord(text)`, `data[0]`) is not a constant, as before.

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

Read the file once with `fs.read_file(path)`, which answers `Result[bytes, str]`, and
keep that one buffer. Walk it with offsets rather than splitting it: `find_any(b"\n",
start)` names the end of the current line, the next line starts one byte later, and a
last line with no newline ends at `len(data)`. Pass `data`, `start` and `end` to
helpers that scan in place with `data[i]`. A slice `data[start:end]` that is only read,
bound to a local, passed to a `bytes` parameter or written to a stream is a view of the
file buffer and copies nothing (a walk over three lines, a thousand times, allocates 0);
storing it is what copies, so a line you keep takes `copy(data[start:end])`, which
copies just that line, never the file. The
whole-file `split(b"\n")` builds a list of copies of every line first, which this
loop avoids. A number in a line can be read where it sits with
`bytes.parse_int_range(data, start, end)`, which answers `Option[int]` without a slice.

The loop below skips blank lines and `#` comments, drops a carriage return before the
newline, and counts distinct lines in a `dict[bytes, int]`. The first output line is
for the fixture file `lines.txt` (three lines), the second for a literal with every
case.

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

`bytes.split(data, separator)` returns `list[bytes]` and keeps leading and
trailing empty pieces; an empty separator is rejected at runtime.
`bytes.join(parts, separator)` rebuilds a byte string from a `list[bytes]`.
`bytes.replace(data, old, new)` replaces every non-overlapping occurrence of `old`, scanning from the front,
as `strings.replace` does for `str`: it is `new` joined over the pieces of `data` split at `old`, so an empty `old` is rejected
at runtime like an empty separator, and `data` is unchanged.

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

```selka
# doc: expect 42
import bytes

func main() -> int:
    if bytes.replace(b"a,b,c", b",", b"--") != b"a--b--c":
        return 1
    if bytes.replace(b"aaa", b"aa", b"b") != b"ba":
        return 2
    return 42
```

## Converting between bytes, integers and text

`bytes(values)` builds a byte string from a `list[int]`. A value outside `0..255`
traps with `R_BYTE_RANGE`, so range-check untrusted input before converting.
`bytes.to_list(b)` returns the octets as a `list[int]`.

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

`strings.encode(s)` produces the UTF-8 bytes of a `str` (there is no `s.encode()` method: operations are functions).
`strings.decode(b)` returns
`Result[str, str]` rather than raising, because the language has no exceptions:
the error payload describes the invalid sequence. `str(b)` is deliberately not
provided, so a byte string never turns into its own debug spelling by accident.

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

`b.hex()` renders lowercase hexadecimal text and `bytes.fromhex(s)` parses it
back, returning `Result[bytes, str]` for odd lengths and non-hexadecimal digits.

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

`bytes` is a prelude type name like `str`. It nests in `list[bytes]`,
`dict[str, bytes]`, record fields, and `Option`/`Result` payloads. Move owned
bytes into these values, or use `copy(value)` when the original must remain usable.
Dictionary keys may be `bytes` as well as `int` and `str`: `dict[bytes, int]` is
an ordinary counting table, and any other hashable type works too (see
[hashable keys](sets.md#hashable-keys)).

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

Byte strings are immutable: there is no `b[i] = value` and no `append` on a
`bytes` value, and `+`, a slice, `split`, `join` and every conversion build a
fresh value and carry the transitive `managed_allocation` effect, so a `noalloc`
function cannot construct them. Building octets in place is what the separate
`byte_buffer` type is for.

Like `str`, `bytes` is accepted in exported module signatures but is not an
ordinary data type at wire boundaries. JSON encoding and decoding reject it with
`E_JSON_CODEC`, and an `extern func` signature rejects it with
`E_EXTERN_SIGNATURE`. Every byte-string operation is native code over the C
runtime's byte routines, which mirror its text routines with a one-byte stride.

## Views and owned copies

A slice, `b[start:end]`, is a view of the owner's bytes. `owning.borrow(start,
end)`, `TextView` and `ByteView` were removed: a slice replaces them, spelled
`bytes` (or `str` for text). The view borrows storage without extending the
owner's lifetime, so keep the owner alive and do not move or mutate it while the
slice is in use; the checker rejects an invalidating operation with the
`copy(value)` repair. `len(view)` reads the range length and `copy(view)`
materializes owned bytes that can outlive the owner. A slice bound to a local
borrows, so a read of it allocates nothing. A slice that is stored or returned is
refused until it is written as `copy(value)`, which makes the copy at that point; a
slice that is compared copies at that point.

Endpoints above the length clamp and a reversed interval is empty; negative
endpoints are rejected or trap according to the ordinary slice rules. Use a
narrow slice or `copy(value)` at a storage or return boundary. Numeric parsing of a
slice is not supported; use the explicit range parsers below or materialize its
bytes first.

The function below returns owned bytes. Its caller reads a name from `field`
while `field` remains alive and makes an independent copy when it needs an
owned value.

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

`bytes.read_u16_be(data, offset)` and its siblings read one fixed-width integer or
float from the octets at `offset`. The functions cover `read_u16`, `read_u32` and
`read_u64`, `read_i16`, `read_i32` and `read_i64`, each with a `_be` (most significant
octet first) or `_le` (least significant octet first) form, and `read_f32_le` and
`read_f64_le`. Floats are little-endian only. `read_u8` and `read_i8` read a single
octet, which has no byte order, as an inline load with the same bounds check (the
read that `data[offset]` makes through a runtime call).

The check covers the whole width at once: an offset below zero, or an offset whose
octets do not all lie inside `data`, traps `R_LIST_BOUNDS` with the offset and the
length, the same report an out-of-range index gives. The offset counts from the first
octet of `data`, which may be an owned value, a `bytes` parameter (a view) or a slice,
so a function that receives a view reads it from its own start. A read borrows its
bytes and never copies them.

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

A view and a slice read the same way, from their own first octet:

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

Floats are read from their little-endian octets:

```selka
# doc: expect 42
import bytes

func main() -> int:
    const half: int[] = [0, 0, 192, 63]
    if bytes.read_f32_le(bytes(half), 0) != 1.5:
        return 1
    return 42
```

### A `byte_buffer` does not take these reads

The fixed-width reads (`read_u8`, `read_i8`, and the `read_u16`, `read_u32`, `read_u64`,
`read_i16`, `read_i32` and `read_i64` forms with `_be` and `_le`, `read_f32_le` and
`read_f64_le`) take `bytes` only, and so does `bytes.replace`. A `byte_buffer` given to
one is `E_TYPE`, `expected bytes, found byte_buffer`. The searches, splits, trims and
number parses of the `bytes` module do take a buffer, and read it in place.

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

No fixed-width read lends a buffer's octets. `buf[i]` reads one octet with no copy. For
a wider read, `bytes(buf[i:i + 8])` copies just those eight octets for each call, where
`bytes(buf)`, the repair the message names, copies the whole buffer. Octets that are
read word by word and never written are better held as `bytes`, which every read above
takes without a copy.

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

`embed_bytes("path")` answers a project file's contents as `bytes`, and
`embed_str("path")` answers them as `str` (the file must be valid UTF-8). The
compiler reads the file while it loads the program and stores its bytes in the
executable as static data, so a program that embeds a table, a fixture or a text
library needs no `Filesystem` capability, performs no read at run time and
cannot fail to find its data after it is built. Both calls use the embedded static data and need no runtime filesystem
authority. They are also available in generic bodies. Every byte is kept, including
NUL, and an empty file is an empty value.

The argument must be one plain string literal, because the file is read before
the program runs: a variable, `b"..."`, a second argument or a computed path is
`E_EMBED_ARGUMENT`. The path is relative to the directory of the source file
that spells the call and uses `/`. `selka run`, `build`, `check`, `test` and
every project command read it the same way.

The most useful place for a call is the whole initializer of a module constant,
which reads the file once at load and hands out static data on every access: the
constant's type is `bytes` for `embed_bytes` and `str` for `embed_str`, and
reading it, from the same module or through an import, allocates nothing.

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

The example above counts the words the sibling file `words.txt` holds; its first
lines are the runner's own `# doc:` comments, which the loop skips.

Every failure is reported at the string literal, before the program runs:

| code | when |
| --- | --- |
| `E_EMBED_ARGUMENT` | the call is not exactly one string literal |
| `E_EMBED_PATH` | the path is empty or holds a NUL byte or a backslash |
| `E_EMBED_ABSOLUTE` | the path starts with `/` |
| `E_EMBED_ESCAPE` | the path leaves the project root through `..` or a symbolic link |
| `E_EMBED_MISSING` | there is no such file |
| `E_EMBED_DIRECTORY` | the path names a directory or another non-regular file |
| `E_EMBED_UNREADABLE` | the file exists but cannot be read |
| `E_EMBED_TOO_LARGE` | the file is over 16 MiB |
| `E_EMBED_UTF8` | `embed_str` was given a file that is not valid UTF-8; the message names the offending byte offset |
| `E_EMBED_UNAVAILABLE` | the source was not loaded from a directory, so a relative path has nothing to resolve against |

The project root is the directory of the nearest `selka.json` above the entry
file, or the entry's own directory when there is none. `..` may climb inside the
root, so `embed_bytes("../shared/table.bin")` from `lib/data.selka` is fine when
`shared/` is in the project; a path that would leave it, and a symbolic link that
resolves outside it, are `E_EMBED_ESCAPE`, decided before the target is probed. A
symbolic link that stays inside the root is followed.

```selka
# doc: expect-error E_EMBED_MISSING
func main() -> int:
    return len(embed_bytes("no-such-file.bin"))
```

```selka
# doc: expect-error E_EMBED_ARGUMENT
func main() -> int:
    mut name = "table.bin"
    return len(embed_bytes(name))
```

The file's content is part of the build's inputs. Editing only an embedded file
rechecks and rebuilds exactly the declarations that embed it and the module
objects that hold them; an unchanged file reuses every cached result, and
deleting or replacing it changes the keys too. `selka test` captures embedded
files with the sources, so a test result is reused only while its fixture is
unchanged. The `project-dependencies` receipt lists each embedded file with its
BLAKE3 digest. Navigation and `selka context` snapshots list the same embedded
identities and recheck them before publishing facts, including same-length edits.
An interface file prints an embedded constant as
`embed_bytes("path")`, never as the file's bytes. In the native build each
distinct file is one static object, however many times it is embedded, and the
work to build it is linear in its size.

Project `budgets.max_file_bytes` bounds each source or embedded file, and
`budgets.max_total_bytes` bounds all loaded source bytes plus every successful
embedded identity. Repeated calls in one module naming the same path share one
read and charge; the same physical file named from different modules has separate
module/path identities and charges. Test snapshots deduplicate physical copies
before reading them and use the loaded closure's project allowances. Provider
replacements capture and recheck their own reachable embedded fixtures, including
ones the production graph did not use. The allowances reach the reader before
it allocates; exceeding one reports `E_PROJECT_BYTES` at the embed literal
and names the budget field to raise. The separate 16 MiB embed limit still applies
when the project allows a larger file.

## Counting characters and parsing numbers

`bytes.scalar_count(b)` answers `Result[int, str]`: the number of Unicode scalars in
the octets, validated in the same pass that counts them, so measuring a range
never decodes it. ASCII runs advance a word at a time, and an invalid sequence —
an overlong encoding, a surrogate, a value above U+10FFFF, a truncated sequence
or a stray continuation byte — answers `Err` carrying the decoder's reason.
`len(b)` stays the octet count; only `scalar_count` measures characters.

A slice stored in a local is an owned byte value. When offsets are already
available, use a range parser to avoid constructing that intermediate value.

The explicit `bytes.parse_int_range(b, start, end)` and
`bytes.parse_float_range(b, start, end)` operations expose the same underlying range
parser for code that already stores offsets. `bytes.scalar_count_range(b, start, end)`
also avoids a view. Explicit negative endpoints follow the index/slice rule: constants
report `E_NEGATIVE_INDEX_REMOVED`, and computed negatives trap `R_LIST_BOUNDS`.
Nonnegative upper endpoints clamp; invalid numeric grammar and overflow still
answer `None`, and malformed UTF-8 still answers `Err`. Scalar counting may allocate the error string for invalid UTF-8 and is
therefore not accepted under `noalloc`.

`bytes.parse_int(b)` and `bytes.parse_float(b)` answer `Option[int]` and `Option[float]` by
reading the octets through the same pinned grammar as `parse_int(text)` and
`parse_float(text)`: surrounding ASCII whitespace, one optional sign, decimal digits
with single `_` separators between them, a fraction, an exponent, and the
`inf`/`infinity`/`nan` spellings. An overflowing integer answers `None` rather
than wrapping, and neither parse allocates, so a `noalloc` function may call them.

What `bytes.parse_int` takes is wider than most protocols' integers, so a strict parser checks the octets first
and calls it only for the range. It accepts a leading `+` or `-`, ASCII whitespace on either side (space, tab, line
feed, carriage return, vertical tab and form feed), leading zeros however many (`b"007"` is 7), and a single `_`
between two digits (`b"1_000"` is 1000); `b"-0"` is 0. It answers `None` for empty data, a bare sign, `b"+-5"`, a space
between the sign and the digits or inside the number, a `_` at either end or doubled, `0x10`, `1e3`, `1.0`, a non-ASCII
digit or space, a NUL octet, and a value outside `-9223372036854775808` to `9223372036854775807`.

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

`byte_buffer` is the mutable sibling of `bytes`: the same one-octet elements, the
same length, indexing, iteration, comparison and search, and no `+`. What it adds
is a growable backing with spare capacity beyond its length, and the eight
methods that write into it: `append(data)`, `append_byte(value)`,
`append_range(data, start, end)`, `append_array(array, start, end)`,
`append_utf8(text)`, `append_int(value)`, `append_float(value)` and
`reserve(extra)`. `append(data)` is the whole-argument
form of `append_range`: it appends every octet of `data`. `append_array` is
`append_range` for a `FixedArray[u8, N]`, such as the `bytes` field of a
`network.Read[N]` chunk: it copies `array[start:end]` in one step, whatever `N`
is, instead of one `append_byte` call per octet. Each answers a `bool` that is true exactly when it accepted the
request — a no-op success such as `reserve(0)` answers true and writes nothing —
none allocates a value for the appended fragment, and growth doubles the backing
storage, so appending N octets performs `O(log N)` allocations. `append_utf8`,
`append_int` and `append_float` build no temporary `bytes`, `str` or formatted
text: the integer's digits and the float's canonical spelling are written
straight into the buffer's capacity, and the float spelling is byte for byte what
`str(value)` prints.

The refusals mirror the checked vocabulary: `append_byte` rejects a value outside
`0..255`, `append_range` and `append_array` return `False` for nonnegative
endpoints whose `end` is below `start` or past `len(data)` (or `N`), and `reserve`
rejects a negative count.
A negative range endpoint, a constant or a computed one, traps `R_LIST_BOUNDS`. A refusal writes nothing, so the receiver
is byte-for-byte unchanged, and `reserve` never changes the length. Length, indexing, iteration, comparison and search read the
current content. Mutating operations update the owned buffer; an active read
borrow must end before a mutation.

A buffer's current octets reach a stream through the receiver's own `write`:
`write(out, buffer)` writes exactly what the buffer holds, out of its own storage,
with no snapshot and no copy — the final `bytes(buffer)` is only needed when the
octets must outlive the buffer. It contributes the `output` effect like any other
stream write, and appending afterwards cannot change what was already written.
`buffers.clear(mut buffer)` then empties the buffer and keeps its capacity, so one buffer serves
every chunk of a loop that assembles output, writes it and starts again: the 1,000th fill allocates
nothing (`buffers.empty()` for each chunk allocates a new buffer each time).

A slice of a `byte_buffer`, `buffer[start:end]`, is a new `byte_buffer` holding just those octets: a buffer can grow under a
view, so there is no borrowed slice of one, and the slice expression names the copy. Printing it, a format hole, `len`, a loop,
an index, `hex.encode`, a membership test (`x in buffer[1:3]`) and a comparison read that copy (or, for a comparison with octets,
the range in place) and nothing more. `copy(buffer[1:3])` names that buffer, so it can be written to (`buffers.append(mut piece,
b"x")`), passed to a `byte_buffer` parameter, returned and stored in a record or a list, and the buffer it came from does not
change. A bare name cannot hold the slice: `const piece = buffer[1:3]` and `mut part = buffer[0:1]` are refused at the check with
`E_BUFFER_SLICE_NAME`, whose message says to write `copy(buffer[1:3])` for a buffer of the range or `bytes(buffer[1:3])`, an owned
immutable copy that the buffer can grow beside without changing it, for its octets. A slice is a `byte_buffer`, so a `bytes`
parameter takes `bytes(buffer[1:3])`.

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

Only `byte_buffer` carries those methods, so an immutable byte string can never
be written through: a `b"..."` literal, a slice and a view are all read-only, and
`bytes(buffer)` creates an owned immutable snapshot of the current octets.
The snapshot stays unchanged when the buffer is appended to later. Its copy cost
is explicit; ownership optimization may reuse storage only when the old value
is dead. Build a buffer with
`byte_buffer(values)` from a `list[int]` — the standard library
[`byte_builder`](standard-library.md#byte_builder) module wraps one — and take
its snapshot with `bytes(buffer)`.

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

A `b"..."` literal still reads as a fixed `[N]u8` array exactly where the context
demands one — an array annotation — so array-shaped host and fixture code keeps
compiling. Everywhere else a byte literal is a `bytes` value.

```selka
# doc: expect 131
func checksum(view: bytes) -> int:
    mut total = 0
    for byte in view:
        total += byte
    return total


func main() -> int:
    mut managed = b"AB"
    if len(managed) != 2:
        return 1
    return checksum(b"AB") + managed[0] - 65
```

## Byte literals

`b"..."` and `b'...'` are the two spellings of a byte-string literal and differ
only in the quote character. The recognized escapes are `\n`, `\r`, `\t`, `\0`,
`\\`, `\"` and exactly two hexadecimal digits after `\x`; any other escape, and
an unterminated literal, is a located source error. Text outside an escape
contributes its UTF-8 encoding, so one non-ASCII character can be several bytes,
and an empty literal has length zero. A single literal, of text or of bytes, is
limited to 65,536 decoded bytes, beyond which it reports `E_BYTE_LITERAL_LIMIT`.
A larger text or value is held in one of two ways: a constant that joins shorter
literals and constants with `+` (the join is folded at compile time and may hold up
to 1 MiB, see [module constants](module-constants.md)), or `embed_str("file")` and
`embed_bytes("file")`, which read a project file of any size (see
[Embedding a file at compile time](#embedding-a-file-at-compile-time)).

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

See [Python text surface](python-text-surface.md) for stable bytes sorting, trim sets, ranged search and scalar repr.
