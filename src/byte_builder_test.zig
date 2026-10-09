//! The byte builder assembles mixed binary and UTF-8 output under collection.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-BYTE-BUILDER-1
test "standard byte builder preserves snapshots and handles binary text and indentation" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/byte_builder.selka"), 42);
}

// spec-case: STANDARD-BYTE-BUILDER-1
test "standard byte builder remains rooted when every managed allocation collects" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/byte_builder.selka"), 42);
}

// spec-case: STANDARD-BYTE-BUILDER-1
test "standard byte builder keeps its published call surface unchanged" {
    try fixture.run(t.allocator,
        \\import byte_builder
        \\
        \\func build() -> bool:
        \\    mut out = byte_builder.create()
        \\    byte_builder.append(mut out, b"ab")
        \\    byte_builder.append_text(mut out, "cd")
        \\    if not byte_builder.append_byte(mut out, 101):
        \\        return False
        \\    if not byte_builder.append_spaces(mut out, 2):
        \\        return False
        \\    return byte_builder.finish(out) == b"abcde  "
        \\
        \\func main() -> int:
        \\    if not build():
        \\        return 1
        \\    return 42
        \\
    , 42);
}

// spec-case: STANDARD-BYTE-BUILDER-1
test "standard byte builder freezes a snapshot that is appended back into its builder" {
    try fixture.run(t.allocator,
        \\import byte_builder
        \\
        \\func main() -> int:
        \\    mut out = byte_builder.create()
        \\    byte_builder.append_text(mut out, "λ")
        \\    mut first = byte_builder.finish(out)
        \\    byte_builder.append(mut out, first)
        \\    if not byte_builder.append_range(mut out, first, 1, 2):
        \\        return 1
        \\    mut smallest = -9223372036854775808
        \\    byte_builder.append_int(mut out, smallest)
        \\    mut expected = b"\xce\xbb\xce\xbb\xbb-9223372036854775808"
        \\    if first != b"\xce\xbb":
        \\        return 2
        \\    if byte_builder.finish(out) != expected:
        \\        return 3
        \\    if not byte_builder.reserve(mut out, 64):
        \\        return 4
        \\    if byte_builder.finish(out) != expected:
        \\        return 5
        \\    return 42
        \\
    , 42);
}

// spec-case: PY-BYTES-6
test "a byte buffer appended to itself copies its earlier range across growth" {
    try fixture.run(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut small = byte_buffer(empty)
        \\    if not small.append_range(b"ab", 0, 2):
        \\        return 1
        \\    if not small.append_range(small, 0, len(small)):
        \\        return 2
        \\    if small != b"abab":
        \\        return 3
        \\    mut long = byte_buffer(empty)
        \\    mut index = 0
        \\    while index < 200:
        \\        _ = long.append_byte(index % 256)
        \\        index += 1
        \\    mut before = bytes(long)
        \\    if not long.append_range(long, 0, len(long)):
        \\        return 4
        \\    if len(long) != 400:
        \\        return 5
        \\    if bytes(long[0:200]) != before or bytes(long[200:400]) != before:
        \\        return 6
        \\    return 42
        \\
    , 42);
}

// spec-case: PY-BYTES-6
test "byte buffer methods are rejected on receivers that are not byte buffers" {
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut text = "abc"
        \\    _ = text.append_byte(65)
        \\    return 0
        \\
    );
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut values: int[] = []
        \\    _ = values.append_utf8("x")
        \\    return 0
        \\
    );
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut table: dict[str, int] = {}
        \\    _ = table.reserve(3)
        \\    return 0
        \\
    );
    // A `bytes` value is immutable, so the in-place methods are not even
    // declared for it: the checker names the mutable receiver to use instead.
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut literal = b"abc"
        \\    _ = literal.append_byte(65)
        \\    return 0
        \\
    );
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = bytes(empty)
        \\    _ = data.append_range(b"abc", 0, 3)
        \\    return 0
        \\
    );
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = bytes(empty)
        \\    _ = data.reserve(3)
        \\    return 0
        \\
    );
    // The mutable buffer takes only the matching operand types.
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = byte_buffer(empty)
        \\    _ = data.append_range(b"abc", 0)
        \\    return 0
        \\
    );
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = byte_buffer(empty)
        \\    _ = data.append_utf8(b"x")
        \\    return 0
        \\
    );
    try fixture.reject(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = byte_buffer(empty)
        \\    _ = data.append_range(12, 0, 1)
        \\    return 0
        \\
    );
}

// spec-case: PY-BYTES-6
test "byte buffer methods compile and run in discard position" {
    try fixture.run(t.allocator,
        \\import byte_builder
        \\
        \\func main() -> int:
        \\    mut out = byte_builder.create()
        \\    byte_builder.append(mut out, b"seed")
        \\    mut empty: int[] = []
        \\    mut data = byte_buffer(empty)
        \\    _ = data.append_range(b"hello", 1, 3)
        \\    _ = data.append_utf8("λ")
        \\    _ = data.append_int(0 - 42)
        \\    _ = data.append_byte(65)
        \\    _ = data.reserve(64)
        \\    if data != b"el\xce\xbb-42A":
        \\        return 1
        \\    _ = byte_builder.append_range(mut out, b"tail", 0, 4)
        \\    if byte_builder.finish(out) != b"seedtail":
        \\        return 2
        \\    return 42
        \\
    , 42);
}

// spec: PY-BYTES-6
test "byte buffer methods write in place and every snapshot stays immutable" {
    try fixture.run(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut buffer = byte_buffer(empty)
        \\    if not buffer.append_byte(65):
        \\        return 7
        \\    if not buffer.append_range(b"0123456789", 1, 4):
        \\        return 8
        \\    if buffer.append_range(b"0123456789", 4, 3):
        \\        return 9
        \\    if buffer.append_range(b"0123456789", 0, 99):
        \\        return 10
        \\    if buffer.append_range(b"0123456789", 0 - 1, 3):
        \\        return 11
        \\    if not buffer.append_utf8("λ"):
        \\        return 12
        \\    mut smallest = -9223372036854775808
        \\    if not buffer.append_int(smallest):
        \\        return 13
        \\    if not buffer.append_int(0):
        \\        return 14
        \\    mut spelling = b"A123\xce\xbb-92233720368547758080"
        \\    if buffer != spelling:
        \\        return 15
        \\    if buffer.append_byte(256):
        \\        return 16
        \\    if buffer.append_byte(0 - 1):
        \\        return 17
        \\    if buffer.reserve(0 - 1):
        \\        return 18
        \\    # Reserving and appending change neither an earlier snapshot nor a literal.
        \\    mut snapshot = bytes(buffer)
        \\    if not buffer.reserve(1024):
        \\        return 19
        \\    if bytes(buffer) != snapshot or len(snapshot) != len(spelling) or snapshot != spelling:
        \\        return 20
        \\    if not buffer.append_byte(33):
        \\        return 21
        \\    if snapshot != spelling or bytes(buffer) != snapshot + b"!":
        \\        return 22
        \\    if buffer[0] != 65 or len(buffer) != len(snapshot) + 1:
        \\        return 23
        \\    if len(b"abc") != 3 or spelling[0:3] != b"A12":
        \\        return 24
        \\    return 42
        \\
    , 42);
}

// spec-case: PY-BYTES-6
test "byte buffer growth keeps every earlier copy intact under collection" {
    try fixture.run(t.allocator,
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut buffer = byte_buffer(empty)
        \\    if not buffer.reserve(5000):
        \\        return 1
        \\    mut index = 0
        \\    while index < 5000:
        \\        if not buffer.append_byte(index % 256):
        \\            return 2
        \\        index += 1
        \\    if len(buffer) != 5000:
        \\        return 3
        \\    mut early = bytes(buffer)
        \\    if not buffer.append_utf8("😀"):
        \\        return 4
        \\    if not buffer.append_int(0 - 5):
        \\        return 5
        \\    if len(early) != 5000 or early[4999] != 4999 % 256 or early[0] != 0:
        \\        return 6
        \\    if bytes(buffer) != early + b"\xf0\x9f\x98\x80-5":
        \\        return 7
        \\    return 42
        \\
    , 42);
}

// spec: PY-BYTES-SNAPSHOT-1
test "PY-BYTES-SNAPSHOT-1 a published snapshot survives the builder's later writes" {
    try fixture.run(t.allocator,
        \\import byte_builder
        \\
        \\func main() -> int:
        \\    mut out = byte_builder.create()
        \\    byte_builder.append_text(mut out, "abc")
        \\    mut first = byte_builder.finish(out)
        \\    # The snapshot reads the buffer's own octets; the append that follows
        \\    # moves them into a private block, so `first` cannot change.
        \\    byte_builder.append_text(mut out, "def")
        \\    mut second = byte_builder.finish(out)
        \\    if first != b"abc" or len(first) != 3:
        \\        return 1
        \\    if second != b"abcdef":
        \\        return 2
        \\    # Appending an earlier snapshot back into its own builder reads the
        \\    # detached block, which the snapshot retains.
        \\    byte_builder.append(mut out, first)
        \\    mut third = byte_builder.finish(out)
        \\    if third != b"abcdefabc":
        \\        return 3
        \\    if second != b"abcdef" or first != b"abc":
        \\        return 4
        \\    if third[0] != 97 or third[8] != 99:
        \\        return 5
        \\    # A snapshot of an empty buffer, then a reserve and one append.
        \\    mut other = byte_builder.create()
        \\    mut blank = byte_builder.finish(other)
        \\    if len(blank) != 0:
        \\        return 6
        \\    if not byte_builder.reserve(mut other, 32):
        \\        return 7
        \\    if not byte_builder.append_byte(mut other, 90):
        \\        return 8
        \\    if blank != b"" or byte_builder.finish(other) != b"Z":
        \\        return 9
        \\    return 42
        \\
    , 42);
}

// spec-case: PY-BYTES-SNAPSHOT-1
test "a snapshot taken under collection keeps its octets across later appends" {
    try fixture.run(t.allocator,
        \\import byte_builder
        \\
        \\func main() -> int:
        \\    mut out = byte_builder.create()
        \\    mut index = 0
        \\    while index < 64:
        \\        byte_builder.append_text(mut out, "piece")
        \\        index += 1
        \\    mut published = byte_builder.finish(out)
        \\    if len(published) != 320:
        \\        return 1
        \\    index = 0
        \\    while index < 8:
        \\        byte_builder.append_text(mut out, "tail")
        \\        index += 1
        \\    if len(published) != 320 or published[0] != 112 or published[319] != 101:
        \\        return 2
        \\    if byte_builder.finish(out) != published + b"tailtailtailtailtailtailtailtail":
        \\        return 3
        \\    return 42
        \\
    , 42);
}
