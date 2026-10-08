# Managed byte strings

`bytes` is an immutable, reference-counted byte string with the same runtime
shape as `str`: assignment shares its storage, which is invisible because it never
changes, and it is usable wherever a managed value is allowed. Where
`str` holds Unicode scalar values, `bytes` holds raw octets, so byte-oriented
code no longer needs fixed `[N]u8` arrays or explicit
`u8` literals.

A `b"..."` or `b'...'` literal produces `bytes`. `len` is signed, indexing yields
an `int` in `0..255`, slicing copies a byte range, and `+` concatenates.

```mylang
# doc: expect 42
def main() -> int:
    header = b"my"
    body = b"lang"
    whole = header + body
    if len(whole) != 6:
        return 1
    if whole[0] != 109:
        return 2
    if whole[-1] != 103:
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

Negative indexes count from the end. An index outside the byte string traps with
`R_LIST_BOUNDS`; slices instead clamp both endpoints and produce an empty result
when the interval is reversed, matching list slices. Iteration yields `int` and
retains its initial bound, so the loop cannot run past a byte string that an
alias replaced.

```mylang
# doc: expect 30
def main() -> int:
    frame = b"\x01\x02\x03\x04"
    if len(frame[2:99]) != 2:
        return 1
    if len(frame[-1:0]) != 0:
        return 2
    if frame[-2] != 3:
        return 3
    total = 0
    for value in frame:
        total += value
    for index, value in enumerate(frame):
        total += index * value
    return total
```

## Membership and equality

`==` and `!=` compare content, never identity. `in` and `not in` accept either an
`int`, testing for a single byte, or a `bytes` value, testing for a contiguous
subsequence. `b.find(x)` returns the first index of a subsequence or `-1`, and
`b.startswith(x)` / `b.endswith(x)` test the ends without copying.

```mylang
# doc: expect 15
def main() -> int:
    record = b"GET /index.html"
    if not record.startswith(b"GET "):
        return 1
    if record.endswith(b".css"):
        return 2
    if record.find(b"/index") != 4:
        return 3
    if record.find(b"?query") != -1:
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

`b.find_any(values, start)` answers where the next octet from a *set* begins.
`values` is a byte set rather than a sequence, so its order and its repeats do not
matter and an empty set finds nothing. The answer is the first index at or after
`start` whose octet occurs anywhere in `values`, or `-1` when the rest of the
receiver holds none. It is a search, so `start` clamps the way a slice endpoint
does rather than trapping the way an index does: a negative `start` begins at 0,
and a `start` at or past `len(b)` answers `-1`. This is how a scanner names any
one of several terminators without first copying the bytes that remain.

```mylang
# doc: expect 24
def main() -> int:
    record = b"GET /index.html HTTP/1.1"
    if record.find_any(b" \r\n", 4) != 15:
        return 1
    if record.find_any(b"/", 5) != 20:
        return 2
    if record.find_any(b"?", 0) != -1:
        return 3
    if record.find_any(b"", 0) != -1:
        return 4
    if record.find_any(b"G", -1) != 0:
        return 5
    return len(record)
```

## Splitting and joining

`b.split(sep)` returns `list[bytes]` and keeps leading and trailing empty pieces;
an empty separator is rejected at runtime. `sep.join(parts)` rebuilds a byte
string from a `list[bytes]`.

```mylang
# doc: expect 11
def main() -> int:
    line = b"name,age,city"
    fields = line.split(b",")
    if len(fields) != 3:
        return 1
    if fields[1] != b"age":
        return 2
    if b",".join(fields) != line:
        return 3
    widths = 0
    for field in fields:
        widths += len(field)
    return widths
```

## Converting between bytes, integers and text

`bytes(values)` builds a byte string from a `list[int]`. A value outside `0..255`
traps with `R_BYTE_RANGE`, so range-check untrusted input before converting.
`b.to_list()` returns the octets as a `list[int]`.

```mylang
# doc: expect 177
def main() -> int:
    values: list[int] = [72, 105]
    greeting = bytes(values)
    if greeting != b"Hi":
        return 1
    octets = greeting.to_list()
    if len(octets) != 2:
        return 2
    if octets[1] != 105:
        return 3
    return octets[0] + octets[1]
```

`s.encode()` produces the UTF-8 bytes of a `str`. `b.decode()` returns
`Result[str, str]` rather than raising, because the language has no exceptions:
the error payload describes the invalid sequence. `str(b)` is deliberately not
provided, so a byte string never turns into its own debug spelling by accident.

```mylang
# doc: expect 6
def text_of(raw: bytes) -> Result[str, str]:
    return raw.decode()


def main() -> int:
    encoded = "héllo".encode()
    if len(encoded) != 6:
        return 1
    match text_of(encoded):
        case Ok(value):
            if value != "héllo":
                return 2
        case Err(message):
            return 0 - len(message)
    match text_of(b"\xff"):
        case Ok(other):
            return 0 - len(other)
        case Err(message):
            return len(encoded)
```

`b.hex()` renders lowercase hexadecimal text and `bytes.fromhex(s)` parses it
back, returning `Result[bytes, str]` for odd lengths and non-hexadecimal digits.

```mylang
# doc: expect 54
def parse(digits: str) -> Result[bytes, str]:
    return bytes.fromhex(digits)


def main() -> int:
    raw = b"\x0f\xa0"
    if raw.hex() != "0fa0":
        return 1
    match parse("0fa0"):
        case Ok(value):
            if value != raw:
                return 2
        case Err(message):
            return 0 - len(message)
    match parse("0f0"):
        case Ok(value):
            return 0 - len(value)
        case Err(message):
            return len(message)
```

## Storing byte strings

`bytes` is a prelude type name like `str`. It nests in `list[bytes]`,
`dict[str, bytes]`, record fields, and `Option`/`Result` payloads, and every copy
shares one reference-counted storage block. Dictionary keys remain `int` or `str`.

```mylang
# doc: expect 6
record Packet:
    kind: str
    payload: bytes


def main() -> int:
    packets: list[Packet] = [Packet(kind="hello", payload=b"\x01"), Packet(kind="data", payload=b"\x02\x03")]
    index: dict[str, bytes] = {}
    for packet in packets:
        index[packet.kind] = packet.payload
    if len(index) != 2:
        return 1
    if index["data"] != b"\x02\x03":
        return 2
    alias = packets[1]
    if alias.payload != packets[1].payload:
        return 3
    total = 0
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
`E_JSON_CODEC`, and an `extern def` signature rejects it with
`E_EXTERN_SIGNATURE`. Every byte-string operation is native code over the C
runtime's byte routines, which mirror its text routines with a one-byte stride.

## Views and owned copies

`b.view(start, end)` answers a byte string that *reads* the range `b[start:end]`
instead of copying it. The endpoints clamp exactly like the slice that would have
copied them, so a negative start counts from the end, an end past the length
clamps, and a reversed or empty interval is the empty byte string. Every read —
length, indexing, iteration, comparison, membership, search, slicing, `decode`,
`scalar_count` and numeric parsing — applies to a view exactly as it does to a
byte string, so a tokenizer can keep an atom's spelling as a range of the document
rather than materializing it.

A view retains the source's backing storage: the octets stay readable after the
byte string that first owned them is unreachable, and a view of a view reads the
same storage one range further in. Constructing one allocates the view's own small
header, and that is the only allocation involved — comparing, searching, counting,
parsing and re-emitting a view never allocate. `b.copy()` is the explicit owned
copy: it materializes the octets into a byte string that shares no storage with
the receiver, which is what a value that must outlive its document needs. Slicing
a view (`v[a:b]`) copies too, exactly like slicing a byte string.

```mylang
# doc: expect 42
def strip_quotes(line: bytes) -> bytes:
    if len(line) < 2 or line[0] != 34:
        return line
    return line.view(1, len(line) - 1)


def main() -> int:
    line = b'"content-length: 42"'
    field = strip_quotes(line)
    if field != b"content-length: 42":
        return 1
    name = field.view(0, 14)
    if name != b"content-length" or len(name) != 14:
        return 2
    if field.view(16, 18) != b"42":
        return 3
    # Clamping matches a slice: negative endpoints count from the end.
    if field.view(0 - 2, 99) != b"42":
        return 4
    owned = name.copy()
    if owned != b"content-length" or owned == b"content-lengt":
        return 5
    if line == field or len(line) != 20:
        return 6
    return len(name) + len(owned) + len(field.view(16, 18)) + 12
```

## Embedding a file at compile time

`embed_bytes("path")` answers a project file's contents as `bytes`, and
`embed_str("path")` answers them as `str` (the file must be valid UTF-8). The
compiler reads the file while it loads the program and stores its bytes in the
executable as static data, so a program that embeds a table, a fixture or a text
library needs no `Filesystem` capability, performs no read at run time and
cannot fail to find its data after it is built. Both calls are pure: they have no
effect, not even `managed_allocation`, so they are legal in `noio`, `noalloc`
and `effects()` functions and in generic bodies. Every byte is kept, including
NUL, and an empty file is an empty value.

The argument must be one plain string literal, because the file is read before
the program runs: a variable, `b"..."`, a second argument or a computed path is
`E_EMBED_ARGUMENT`. The path is relative to the directory of the source file
that spells the call and uses `/`. `mylang run`, `build`, `check`, `test` and
every project command read it the same way.

The most useful place for a call is the whole initializer of a module constant,
which reads the file once at load and hands out static data on every access: the
constant's type is `bytes` for `embed_bytes` and `str` for `embed_str`, and
reading it, from the same module or through an import, allocates nothing.

```mylang
# doc: project embedding
# doc: file words.txt
alpha
beta
gamma
```

```mylang
# doc: project embedding
# doc: file main.my
# doc: expect 3
module main

const WORDS: str = embed_str("words.txt")


def main() -> int:
    text = WORDS
    total = 0
    for line in text.split("\n"):
        if len(line) != 0 and line[0] != "#":
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

The project root is the directory of the nearest `mylang.json` above the entry
file, or the entry's own directory when there is none. `..` may climb inside the
root, so `embed_bytes("../shared/table.bin")` from `lib/data.my` is fine when
`shared/` is in the project; a path that would leave it, and a symbolic link that
resolves outside it, are `E_EMBED_ESCAPE`, decided before the target is probed. A
symbolic link that stays inside the root is followed.

```mylang
# doc: expect-error E_EMBED_MISSING
def main() -> int:
    return len(embed_bytes("no-such-file.bin"))
```

```mylang
# doc: expect-error E_EMBED_ARGUMENT
def main() -> int:
    name = "table.bin"
    return len(embed_bytes(name))
```

The file's content is part of the build's inputs. Editing only an embedded file
rechecks and rebuilds exactly the declarations that embed it and the module
objects that hold them; an unchanged file reuses every cached result, and
deleting or replacing it changes the keys too. `mylang test` captures embedded
files with the sources, so a test result is reused only while its fixture is
unchanged. The `project-dependencies` receipt lists each embedded file with its
BLAKE3 digest. Navigation and `mylang context` snapshots list the same embedded
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

`b.scalar_count()` answers `Result[int, str]`: the number of Unicode scalars in
the octets, validated in the same pass that counts them, so measuring a range
never decodes it. ASCII runs advance a word at a time, and an invalid sequence —
an overlong encoding, a surrogate, a value above U+10FFFF, a truncated sequence
or a stray continuation byte — answers `Err` carrying the decoder's reason.
`len(b)` stays the octet count; only `scalar_count` measures characters.

An immediately parsed slice or view is lowered directly to the existing range
parser. Both `b[start:end].parse_int()` and
`b.view(start, end).parse_float()` avoid constructing the intermediate byte
value and are accepted under `noalloc`. The receiver and bounds are evaluated
once in source order; omitted endpoints, negative offsets, clamping, and
reversed ranges keep the ordinary slice/view behavior. Assigning the slice or
view to a binding still constructs that value, as does slicing a mutable
`byte_buffer`.

The explicit `b.parse_int_range(start, end)` and
`b.parse_float_range(start, end)` operations expose the same underlying range
parser for code that already stores offsets. `b.scalar_count_range(start, end)`
also avoids a view, but may allocate the error string for invalid UTF-8 and is
therefore not accepted under `noalloc`.

`b.parse_int()` and `b.parse_float()` answer `Option[int]` and `Option[float]` by
reading the octets through the same pinned grammar as `int(text)` and
`float(text)`: surrounding ASCII whitespace, one optional sign, decimal digits
with single `_` separators between them, a fraction, an exponent, and the
`inf`/`infinity`/`nan` spellings. An overflowing integer answers `None` rather
than wrapping, and neither parse allocates, so a `noalloc` function may call them.

```mylang
# doc: expect 42
def measure(raw: bytes) -> int:
    match raw.scalar_count():
        case Ok(width):
            return width
        case Err(_):
            return 0 - 1


def main() -> int:
    ascii = b"hello"
    if measure(ascii) != 5:
        return 1
    mixed = b"a\xce\xbbb\xf0\x9f\x98\x80c"
    if measure(mixed) != 5:
        return 2
    if measure(b"\xff") != 0 - 1:
        return 3
    if measure(b"\xc0\xaf") != 0 - 1 or measure(b"\xce") != 0 - 1:
        return 4
    match b"  -12  ".parse_int():
        case Some(value):
            if value != 0 - 12:
                return 5
        case None:
            return 6
    match b"2.5e1".parse_float():
        case Some(value):
            if value != 25.0:
                return 7
        case None:
            return 8
    match b"12a".parse_int():
        case Some(_):
            return 9
        case None:
            pass
    token = b"size=2.5mm".view(5, 8)
    match token.parse_float():
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
is a growable backing with spare capacity beyond its length, and the six methods
that write into it: `append_byte(value)`, `append_range(data, start, end)`,
`append_utf8(text)`, `append_int(value)`, `append_float(value)` and
`reserve(extra)`. Each answers a `bool` that is true exactly when it accepted the
request — a no-op success such as `reserve(0)` answers true and writes nothing —
none allocates a value for the appended fragment, and growth doubles the backing
storage, so appending N octets performs `O(log N)` allocations. `append_utf8`,
`append_int` and `append_float` build no temporary `bytes`, `str` or formatted
text: the integer's digits and the float's canonical spelling are written
straight into the buffer's capacity, and the float spelling is byte for byte what
`str(value)` prints.

The refusals mirror the checked vocabulary: `append_byte` rejects a value outside
`0..255`, `append_range` rejects a negative `start`, an `end` below `start` or an
`end` past `len(data)`, and `reserve` rejects a negative count. A rejection
writes nothing, so the receiver is byte-for-byte unchanged, and `reserve` never
changes the length. Length, indexing, iteration, comparison and search read the
current content, and identity survives growth, so aliases see every append.

A buffer's current octets reach a stream through the receiver's own `write`:
`out.write(buffer)` writes exactly what the buffer holds, out of its own storage,
with no snapshot and no copy — the final `bytes(buffer)` is only needed when the
octets must outlive the buffer. It contributes the `output` effect like any other
stream write, and appending afterwards cannot change what was already written.

Only `byte_buffer` carries those methods, so an immutable byte string can never
be written through: a `b"..."` literal, a slice and a view are all read-only, and
`bytes(buffer)` publishes the buffer's current octets as an immutable snapshot
without copying them — the snapshot reads the buffer's own storage and retains
it, and the buffer's next write moves its octets into a private block first, so
a snapshot never changes under a later append. Build a buffer with
`byte_buffer(values)` from a `list[int]` — the standard library
[`byte_builder`](standard-library.md#byte_builder) module wraps one — and take
its snapshot with `bytes(buffer)`.

```mylang
# doc: expect 42
def main() -> int:
    empty: list[int] = []
    buffer = byte_buffer(empty)
    if not buffer.append_range(b"hello world", 0, 5):
        return 1
    if not buffer.append_byte(44):
        return 2
    if not buffer.append_utf8(" λ"):
        return 3
    if not buffer.append_int(0 - 7):
        return 4
    if not buffer.append_float(2.5):
        return 9
    snapshot = bytes(buffer)
    if not buffer.reserve(64):
        return 5
    if not buffer.append_byte(33):
        return 6
    if snapshot != b"hello, \xce\xbb-72.5" or bytes(buffer) != snapshot + b"!":
        return 7
    return len(snapshot) + 28
```

A `b"..."` literal still reads as a fixed `[N]u8` array exactly where the context
demands one — an array annotation — so array-shaped host and fixture code keeps
compiling. Everywhere else a byte literal is a `bytes` value.

```mylang
# doc: expect 131
def checksum(view: bytes) -> int:
    total = 0
    for byte in view:
        total += byte
    return total


def main() -> int:
    managed = b"AB"
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
and an empty literal has length zero. A single literal is limited to 65,536
decoded bytes, beyond which it reports `E_BYTE_LITERAL_LIMIT`.

```mylang
# doc: expect 42
def main() -> int:
    if b'ok' != b"ok":
        return 1
    escapes = b"\x2a\t\n\r\0\\\""
    if len(escapes) != 7:
        return 2
    if escapes[4] != 0 or escapes[6] != 34:
        return 3
    if len(b"") != 0 or len(b"é") != 2:
        return 4
    return escapes[0]
```

See [Python text surface](python-text-surface.md) for stable bytes sorting, trim sets, ranged search and scalar repr.
