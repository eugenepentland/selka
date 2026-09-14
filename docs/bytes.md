# Managed byte strings

`bytes` is an immutable, garbage-collected byte string with the same runtime
shape as `str`: a stable identity traced by the nonmoving collector, copied by
reference on assignment, and usable wherever a managed value is allowed. Where
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
shares one traced object. Dictionary keys remain `int` or `str`.

```mylang
# doc: expect 6
class Packet:
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

Byte strings are immutable: there is no `b[i] = value` and no `append`. Building
a new value with `+`, a slice, `split`, `join`, or any conversion allocates, and
those operations carry the transitive `managed_allocation` effect, so a `noalloc`
function cannot construct them.

Like `str`, `bytes` is accepted in exported module signatures but is not an
ordinary data type at wire boundaries. JSON encoding and decoding reject it with
`E_JSON_CODEC` and `host def` signatures reject it with `E_HOST_SIGNATURE`. Every
byte-string operation runs on the QBE native backend as well as the VM, over a
native byte runtime that mirrors the managed text runtime with a one-byte
stride.

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
