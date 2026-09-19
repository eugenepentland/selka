//! Integrated Python byte-string syntax, conversions, storage and rejections.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "bytes.my", source);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{ .gc_stress = true }) catch |err| {
        for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-trap.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
}

fn rejected(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-reject.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    for (c.diagnostics.items) |d| if (std.mem.eql(u8, d.code, code)) return;
    for (c.diagnostics.items) |d| debug.print("{s}: {s}\n", .{ d.code, d.message });
    return t.expect(false);
}

/// Run one guest program under GC stress and return its exit value. A trap is
/// reported and turned into an assertion failure so a decoding failure cannot
/// look like an ordinary nonzero result a test forgot to check.
fn value(source: []const u8) !i64 {
    var c = try language.Compilation.init(t.allocator, "utf8-decode.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    return result.value;
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 out-of-range indexes ranges and separators trap with located codes" {
    try trapped("def main() -> int:\n    raw = b\"ab\"\n    return raw[2]\n", "R_LIST_BOUNDS");
    try trapped("def main() -> int:\n    raw = b\"ab\"\n    return raw[-3]\n", "R_LIST_BOUNDS");
    try trapped("def main() -> int:\n    return len(b\"ab\".split(b\"\"))\n", "R_EMPTY_SEPARATOR");
    try trapped("def main() -> int:\n    values: list[int] = [256]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
    try trapped("def main() -> int:\n    values: list[int] = [0 - 1]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 byte strings are immutable and never convert through str" {
    try rejected("def main() -> int:\n    raw = b\"ab\"\n    raw[0] = 1\n    return 0\n", "E_COLLECTION_METHOD");
    try rejected("def main() -> int:\n    raw = b\"ab\"\n    raw.append(1)\n    return 0\n", "E_COLLECTION_METHOD");
    try rejected("def main() -> int:\n    return len(str(b\"ab\"))\n", "E_TEXT_CONVERSION");
    try rejected("def main() -> int:\n    raw = b\"ab\"\n    return len(raw - raw)\n", "E_TEXT_OPERATOR");
    try rejected("def main() -> int:\n    values: dict[bytes, int] = {}\n    return len(values)\n", "E_DICT_KEY");
    try rejected("def main() -> int:\n    return len(bytes(\"ab\"))\n", "E_BYTES_CONVERSION");
    try rejected("def main() -> int:\n    return len(b\"ab\".encode())\n", "E_COLLECTION_METHOD");
    try rejected(
        "def build() -> int noalloc:\n    raw = b\"ab\"\n    return len(raw)\ndef main() -> int:\n    return build()\n",
        "E_EFFECT_BOUND",
    );
    try rejected(
        "def grow(a: bytes, b: bytes) -> int noalloc:\n    return len(a + b)\ndef main() -> int:\n    return grow(b\"a\", b\"b\")\n",
        "E_EFFECT_BOUND",
    );
    try rejected(
        "def cut(a: bytes) -> int noalloc:\n    return len(a[0:1])\ndef main() -> int:\n    return cut(b\"ab\")\n",
        "E_EFFECT_BOUND",
    );
}

// spec: PY-BYTES-4
test "PY-BYTES-4 byte strings are region allocated escaped and barrier checked under with arena" {
    try run(
        \\def main() -> int:
        \\    kept: bytes = b""
        \\    names: list[bytes] = []
        \\    with arena() as scratch:
        \\        parts = b"a,bb,ccc".split(b",")
        \\        kept = scratch.escape(parts[2] + b"!")
        \\        names = scratch.escape([parts[0], parts[1]])
        \\    return len(kept) * 10 + len(names[1])
    , 42);
    try rejected(
        \\def main() -> int:
        \\    outer: list[bytes] = []
        \\    with arena():
        \\        outer.append(b"x" + b"y")
        \\    return len(outer)
    , "E_ARENA_ESCAPE");
    try trapped(
        \\def stash(target: list[bytes], value: bytes):
        \\    target.append(value)
        \\
        \\def main() -> int:
        \\    outer: list[bytes] = []
        \\    with arena():
        \\        stash(outer, b"x" + b"y")
        \\    return len(outer)
    , "R_ARENA_ESCAPE");
}

// spec: PY-BYTES-5
test "PY-BYTES-5 the native backend lowers every byte-string operation" {
    const source =
        \\def parsed(digits: str) -> Result[bytes, str]:
        \\    return bytes.fromhex(digits)
        \\
        \\def main() -> int:
        \\    raw = b"a,b" + b",c"
        \\    parts = raw.split(b",")
        \\    if b",".join(parts) != raw or raw[0:1] != b"a":
        \\        return 1
        \\    if not raw.startswith(b"a") or raw.endswith(b"z") or raw.find(b"b") != 2:
        \\        return 2
        \\    if 97 not in raw or b"b," not in raw:
        \\        return 3
        \\    if bytes(raw.to_list()) != raw or raw.hex() != "612c622c63":
        \\        return 4
        \\    match raw.decode():
        \\        case Ok(text):
        \\            if text.encode() != raw:
        \\                return 5
        \\        case Err(message):
        \\            return 0 - len(message)
        \\    match parsed("612c"):
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(message):
        \\            return 0 - len(message)
    ;
    var compilation = try language.Compilation.init(t.allocator, "bytes-native.my", source);
    defer compilation.deinit();
    const manifest = compilation.emitQbe(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |d| debug.print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    defer t.allocator.free(manifest);
    for ([_][]const u8{ "myl_native_bytes_split", "myl_native_bytes_join", "myl_native_bytes_slice", "myl_qbe_bytes_decode", "myl_qbe_bytes_from_list" }) |symbol| {
        try t.expect(std.mem.indexOf(u8, manifest, symbol) != null);
    }
    try run(source, 2);
}

/// Guest program: decode valid ASCII and 2/3/4-byte UTF-8, compare each result
/// with the `str` literal it must equal, and re-encode to pin the exact scalar
/// sequence rather than only the length.
const valid_utf8_decode =
    \\def text_of(raw: bytes) -> str:
    \\    match raw.decode():
    \\        case Ok(text):
    \\            return text
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\def main() -> int:
    \\    if text_of(b"abc") != "abc":
    \\        return 1
    \\    if text_of(b"abc").encode() != b"abc":
    \\        return 2
    \\    if text_of(b"\xc3\xa9") != "\u00e9":
    \\        return 3
    \\    if text_of(b"\xc3\xa9").encode() != b"\xc3\xa9":
    \\        return 4
    \\    if text_of(b"\xe2\x82\xac") != "\u20ac":
    \\        return 5
    \\    if text_of(b"\xe2\x82\xac").encode() != b"\xe2\x82\xac":
    \\        return 6
    \\    if text_of(b"\xf0\x9f\x98\x80") != "\U0001f600":
    \\        return 7
    \\    if text_of(b"\xf0\x9f\x98\x80").encode() != b"\xf0\x9f\x98\x80":
    \\        return 8
    \\    if len(text_of(b"a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80")) != 4:
    \\        return 9
    \\    return 0
;

/// Guest program: every overlong, surrogate and out-of-range encoding must
/// reach `Err` with the runtime's existing invalid-UTF-8 message, which is what
/// an `MYL_BYTES_INVALID` status publishes (an allocation failure would trap).
const invalid_utf8_encoding =
    \\def status_of(raw: bytes) -> str:
    \\    match raw.decode():
    \\        case Ok(_):
    \\            return "accepted"
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\def main() -> int:
    \\    if status_of(b"\xc0\x80") != "invalid UTF-8 in byte string":
    \\        return 1
    \\    if status_of(b"\xc1\xbf") != "invalid UTF-8 in byte string":
    \\        return 2
    \\    if status_of(b"\xe0\x80\x80") != "invalid UTF-8 in byte string":
    \\        return 3
    \\    if status_of(b"\xe0\x9f\xbf") != "invalid UTF-8 in byte string":
    \\        return 4
    \\    if status_of(b"\xf0\x80\x80\x80") != "invalid UTF-8 in byte string":
    \\        return 5
    \\    if status_of(b"\xf0\x8f\xbf\xbf") != "invalid UTF-8 in byte string":
    \\        return 6
    \\    if status_of(b"\xed\xa0\x80") != "invalid UTF-8 in byte string":
    \\        return 7
    \\    if status_of(b"\xed\xaf\xbf") != "invalid UTF-8 in byte string":
    \\        return 8
    \\    if status_of(b"\xed\xbf\xbf") != "invalid UTF-8 in byte string":
    \\        return 9
    \\    if status_of(b"\xf4\x90\x80\x80") != "invalid UTF-8 in byte string":
    \\        return 10
    \\    if status_of(b"\xf5\x80\x80\x80") != "invalid UTF-8 in byte string":
    \\        return 11
    \\    if status_of(b"\xf7\xbf\xbf\xbf") != "invalid UTF-8 in byte string":
    \\        return 12
    \\    return 0
;

/// Guest program: truncated sequences, stray continuation bytes and a bad
/// continuation byte are all still rejected by the single validating pass.
const truncated_utf8_decode =
    \\def status_of(raw: bytes) -> str:
    \\    match raw.decode():
    \\        case Ok(_):
    \\            return "accepted"
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\def main() -> int:
    \\    if status_of(b"\x80") != "invalid UTF-8 in byte string":
    \\        return 1
    \\    if status_of(b"\xbf") != "invalid UTF-8 in byte string":
    \\        return 2
    \\    if status_of(b"\xc2") != "invalid UTF-8 in byte string":
    \\        return 3
    \\    if status_of(b"\xe2\x82") != "invalid UTF-8 in byte string":
    \\        return 4
    \\    if status_of(b"\xf0\x9f\x98") != "invalid UTF-8 in byte string":
    \\        return 5
    \\    if status_of(b"\xc2\x20") != "invalid UTF-8 in byte string":
    \\        return 6
    \\    if status_of(b"\xe2\x28\xa1") != "invalid UTF-8 in byte string":
    \\        return 7
    \\    if status_of(b"\xf0\x28\x8c\x28") != "invalid UTF-8 in byte string":
    \\        return 8
    \\    if status_of(b"\xff") != "invalid UTF-8 in byte string":
    \\        return 9
    \\    return 0
;

// spec: UTF8-DECODE-1
test "UTF8-DECODE-1 the checked decoder preserves ASCII and multi-byte scalars" {
    try t.expectEqual(@as(i64, 0), try value(valid_utf8_decode));
}

// spec-case: UTF8-DECODE-1
test "UTF8-DECODE-1 overlong surrogate and out-of-range encodings stay invalid" {
    try t.expectEqual(@as(i64, 0), try value(invalid_utf8_encoding));
}

// spec-case: UTF8-DECODE-1
test "UTF8-DECODE-1 truncated and stray continuation bytes stay invalid" {
    try t.expectEqual(@as(i64, 0), try value(truncated_utf8_decode));
}
