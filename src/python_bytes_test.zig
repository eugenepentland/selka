//! Integrated Python byte-string syntax, conversions, storage and rejections.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const effect_bound = "E_EFFECT_BOUND";

fn printDiagnostics(c: *language.Compilation) void {
    for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
}

fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "bytes.my", source);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{}) catch |err| {
        printDiagnostics(&c);
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-trap.my", source);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{}) catch |err| {
        printDiagnostics(&c);
        return err;
    };
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
    const result = native.runWithOptions(&c, .{}) catch |err| {
        printDiagnostics(&c);
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    return result.value;
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 out-of-range indexes ranges and separators trap with located codes" {
    try trapped("func main() -> int:\n    mut raw = b\"ab\"\n    return raw[2]\n", "R_LIST_BOUNDS");
    try trapped("func main() -> int:\n    mut raw = b\"ab\"\n    return raw[-3]\n", "R_LIST_BOUNDS");
    try trapped("func main() -> int:\n    return len(b\"ab\".split(b\"\"))\n", "R_EMPTY_SEPARATOR");
    try trapped("func main() -> int:\n    mut values: int[] = [256]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
    try trapped("func main() -> int:\n    mut values: int[] = [0 - 1]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
}

// spec-case: PY-BYTES-6
test "PY-BYTES-6 the mutable octet buffer traps the same byte-range conversion errors" {
    try trapped("func main() -> int:\n    mut values: int[] = [256]\n    return len(byte_buffer(values))\n", "R_BYTE_RANGE");
    try trapped("func main() -> int:\n    mut values: int[] = [0 - 1]\n    return len(byte_buffer(values))\n", "R_BYTE_RANGE");
    try t.expectEqual(@as(i64, 42), try value("func main() -> int:\n    mut values: int[] = [65, 66]\n    if byte_buffer(values) != b\"AB\":\n        return 1\n    return 42\n"));
    try rejected("func main() -> int:\n    return len(byte_buffer(\"ab\"))\n", "E_BYTES_CONVERSION");
    try rejected("func main() -> int:\n    mut raw = b\"ab\"\n    return len(byte_buffer(raw))\n", "E_BYTES_CONVERSION");
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 byte strings are immutable and never convert through str" {
    try rejected("func main() -> int:\n    mut raw = b\"ab\"\n    raw[0] = 1\n    return 0\n", "E_COLLECTION_METHOD");
    try rejected("func main() -> int:\n    mut raw = b\"ab\"\n    raw.append(1)\n    return 0\n", "E_COLLECTION_METHOD");
    try rejected("func main() -> int:\n    return len(str(b\"ab\"))\n", "E_TEXT_CONVERSION");
    try rejected("func main() -> int:\n    mut raw = b\"ab\"\n    return len(raw - raw)\n", "E_TEXT_OPERATOR");
    // An immutable byte string is a hashable key (HASH-KEYS-1); the mutable
    // octet buffer is not.
    try rejected("func main() -> int:\n    mut values: dict[byte_buffer, int] = {}\n    return len(values)\n", "E_DICT_KEY");
    try rejected("func main() -> int:\n    return len(bytes(\"ab\"))\n", "E_BYTES_CONVERSION");
    try rejected("func main() -> int:\n    return len(b\"ab\".encode())\n", "E_COLLECTION_METHOD");
    try rejected(
        "func build() -> int effects():\n    mut raw = b\"ab\"\n    return len(raw)\nfunc main() -> int:\n    return build()\n",
        effect_bound,
    );
    try rejected(
        "func grow(a: bytes, b: bytes) -> int effects():\n    return len(a + b)\nfunc main() -> int:\n    return grow(b\"a\", b\"b\")\n",
        effect_bound,
    );
    try rejected(
        "func cut(a: bytes) -> int effects():\n    return len(a[0:1])\nfunc main() -> int:\n    return cut(b\"ab\")\n",
        effect_bound,
    );
}

// spec: PY-BYTES-5
test "PY-BYTES-5 every byte-string operation builds and runs natively" {
    const source =
        \\func parsed(digits: str) -> Result[bytes, str]:
        \\    return bytes.fromhex(digits)
        \\
        \\func main() -> int:
        \\    mut raw = b"a,b" + b",c"
        \\    mut parts = raw.split(b",")
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
    try run(source, 2);
}

/// Guest program: decode valid ASCII and 2/3/4-byte UTF-8, compare each result
/// with the `str` literal it must equal, and re-encode to pin the exact scalar
/// sequence rather than only the length.
const valid_utf8_decode =
    \\func text_of(raw: bytes) -> str:
    \\    match raw.decode():
    \\        case Ok(text):
    \\            return text
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\func main() -> int:
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
    \\func status_of(raw: bytes) -> str:
    \\    match raw.decode():
    \\        case Ok(_):
    \\            return "accepted"
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\func main() -> int:
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
    \\func status_of(raw: bytes) -> str:
    \\    match raw.decode():
    \\        case Ok(_):
    \\            return "accepted"
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\func main() -> int:
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

// spec-case: PY-BYTES-7
test "PY-BYTES-7 views require immutable bytes while text and buffers support copies" {
    try rejected("func main() -> int:\n    mut empty: int[] = []\n    mut data = byte_buffer(empty)\n    return len(data.view(0, 1))\n", "E_COLLECTION_METHOD");
    try t.expectEqual(@as(i64, 0), try value("func main() -> int:\n    mut empty: int[] = []\n    mut data = byte_buffer(empty)\n    return len(data.copy())\n"));
    try rejected("func main() -> int:\n    mut text = \"abc\"\n    return len(text.view(0, 1))\n", "E_COLLECTION_METHOD");
    try t.expectEqual(@as(i64, 3), try value("func main() -> int:\n    mut text = \"abc\"\n    return len(text.copy())\n"));
    try rejected("func main() -> int:\n    mut text = \"abc\"\n    return len(text.scalar_count())\n", "E_COLLECTION_METHOD");
    try rejected("func main() -> int:\n    mut raw = b\"abc\"\n    return len(raw.view(\"a\", 1))\n", "E_TYPE");
    try rejected("func main() -> int:\n    mut raw = b\"abc\"\n    return len(raw.view(0, 1, 2))\n", "E_ARITY");
}

// spec-case: PY-BYTES-9
test "PY-BYTES-9 numeric parsing is accepted under noalloc and an explicit ceiling rejects a view" {
    try t.expectEqual(@as(i64, 42), try value(
        "func parse(text: str) -> int noalloc:\n" ++
            "    match parse_int(text):\n" ++
            "        case Some(found):\n" ++
            "            return found\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func parse(raw: bytes) -> int noalloc:\n" ++
            "    match raw.parse_int():\n" ++
            "        case Some(found):\n" ++
            "            return found\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(b\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func measure(raw: bytes) -> int noalloc:\n" ++
            "    match raw.scalar_count():\n" ++
            "        case Ok(width):\n" ++
            "            return width + 40\n" ++
            "        case Err(_):\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return measure(b\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func same(raw: bytes, expected: bytes) -> int noalloc:\n    if raw == expected:\n        return 42\n    return 0\n" ++
            "func main() -> int:\n    return same(b\"42\", b\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func parse(text: str) -> int noalloc:\n" ++
            "    match parse_float(text):\n" ++
            "        case Some(found):\n" ++
            "            if found > 2.0:\n" ++
            "                return 42\n" ++
            "            return 0\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(\"2.5\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func parse(raw: bytes) -> int noalloc:\n" ++
            "    match raw.parse_float():\n" ++
            "        case Some(found):\n" ++
            "            if found > 2.0:\n" ++
            "                return 42\n" ++
            "            return 0\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(b\"2.5\")\n",
    ));
    try rejected("func peek(raw: bytes) -> int effects():\n    return len(raw.view(0, 1))\nfunc main() -> int:\n    return peek(b\"abc\")\n", effect_bound);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "noalloc scalar counting preserves the fixed invalid UTF8 payload" {
    try t.expectEqual(@as(i64, 42), try value(
        "func measure(raw: bytes) -> int noalloc:\n" ++
            "    match raw.scalar_count():\n" ++
            "        case Ok(width):\n" ++
            "            return width\n" ++
            "        case Err(message):\n" ++
            "            if message == \"invalid UTF-8 in byte string\":\n" ++
            "                return 42\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return measure(b\"\\xff\")\n",
    ));
}

// spec: PY-BYTES-RANGE-1
test "PY-BYTES-RANGE-1 range parsing and scalar counting clamp without a view allocation" {
    try t.expectEqual(@as(i64, 42), try value(
        "func ranged(raw: bytes) -> int noalloc:\n" ++
            "    match raw.parse_int_range(2, 4):\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match raw.parse_float_range(5, 8):\n" ++
            "        case Some(number):\n" ++
            "            if number != 2.5:\n" ++
            "                return 3\n" ++
            "        case None:\n" ++
            "            return 4\n" ++
            "    return 0\n" ++
            "func main() -> int:\n" ++
            "    mut raw = b\"xx42=2.5abc\"\n" ++
            "    if ranged(raw) != 0:\n" ++
            "        return 1\n" ++
            "    match raw.scalar_count_range(0 - 3, 99):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 39\n" ++
            "        case Err(_):\n" ++
            "            return 5\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func main() -> int:\n" ++
            "    mut raw = b\"x-9223372036854775808y\"\n" ++
            "    match raw.parse_int_range(1, 21):\n" ++
            "        case Some(number):\n" ++
            "            if number != -9223372036854775808:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match raw.parse_int_range(21, 1):\n" ++
            "        case Some(_):\n" ++
            "            return 3\n" ++
            "        case None:\n" ++
            "            pass\n" ++
            "    match b\"a\\xce\\xbbb\".scalar_count_range(1, 3):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 41\n" ++
            "        case Err(_):\n" ++
            "            return 4\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func main() -> int:\n" ++
            "    mut values: int[] = []\n" ++
            "    mut raw = bytes(values)\n" ++
            "    match raw.parse_int_range(0 - 10, 10):\n" ++
            "        case Some(_):\n" ++
            "            return 1\n" ++
            "        case None:\n" ++
            "            pass\n" ++
            "    match raw.scalar_count_range(0 - 10, 10):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 42\n" ++
            "        case Err(_):\n" ++
            "            return 2\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "func main() -> int:\n" ++
            "    match b\"a\\xffb\".scalar_count_range(1, 2):\n" ++
            "        case Ok(_):\n" ++
            "            return 1\n" ++
            "        case Err(message):\n" ++
            "            if message == \"invalid UTF-8 in byte string\":\n" ++
            "                return 42\n" ++
            "            return 2\n",
    ));
    try rejected(
        "func measure(raw: bytes) -> int effects():\n" ++
            "    match raw.scalar_count_range(0, len(raw)):\n" ++
            "        case Ok(width):\n" ++
            "            return width\n" ++
            "        case Err(_):\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return measure(b\"abc\")\n",
        effect_bound,
    );
}

// spec: PY-BYTES-FUSED-RANGE-1
test "PY-BYTES-FUSED-RANGE-1 immediate slices and views parse under noalloc" {
    try t.expectEqual(@as(i64, 42), try value(
        "func fused(raw: bytes) -> int noalloc:\n" ++
            "    match raw[2:4].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match raw.view(5, 8).parse_float():\n" ++
            "        case Some(number):\n" ++
            "            if number != 2.5:\n" ++
            "                return 3\n" ++
            "        case None:\n" ++
            "            return 4\n" ++
            "    match raw[0 - 8:0 - 6].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 5\n" ++
            "        case None:\n" ++
            "            return 6\n" ++
            "    match raw[8:2].parse_int():\n" ++
            "        case Some(_):\n" ++
            "            return 7\n" ++
            "        case None:\n" ++
            "            pass\n" ++
            "    return 42\n" ++
            "func main() -> int:\n" ++
            "    if fused(b\"xx42=2.5yy\") != 42:\n" ++
            "        return 8\n" ++
            "    match b\"42\"[:].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 9\n" ++
            "        case None:\n" ++
            "            return 10\n" ++
            "    match b\"42\"[0 - 99:99].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            return number\n" ++
            "        case None:\n" ++
            "            return 11\n",
    ));
    try rejected(
        "func retained(raw: bytes) -> int effects():\n" ++
            "    mut part = raw[0:2]\n" ++
            "    match part.parse_int():\n" ++
            "        case Some(number):\n" ++
            "            return number\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return retained(b\"42\")\n",
        effect_bound,
    );
    try rejected(
        "func retained(raw: bytes) -> int effects():\n" ++
            "    mut part = raw.view(0, 2)\n" ++
            "    match part.parse_int():\n" ++
            "        case Some(number):\n" ++
            "            return number\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return retained(b\"42\")\n",
        effect_bound,
    );
    try rejected(
        "func mutable(data: byte_buffer) -> int effects():\n" ++
            "    match data[0:2].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            return number\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    mut values: int[] = [52, 50]\n" ++
            "    return mutable(byte_buffer(values))\n",
        effect_bound,
    );
}

// spec-case: PY-BYTES-FUSED-RANGE-1
test "PY-BYTES-FUSED-RANGE-1 receiver and bounds keep source order and run once" {
    try t.expectEqual(@as(i64, 42), try value(
        "func source(mut log: int[], raw: bytes) -> bytes effects(mutation):\n" ++
            "    log[0] = log[0] + 1\n" ++
            "    return raw\n" ++
            "func bound(mut log: int[]) -> int effects(mutation):\n" ++
            "    mut value = log[0]\n" ++
            "    log[0] = value + 1\n" ++
            "    return value\n" ++
            "func main() -> int:\n" ++
            "    mut log: int[] = [0]\n" ++
            "    match source(mut log, b\"x42\")[bound(mut log):bound(mut log)].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            if number != 4 or log[0] != 3:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    return 42\n",
    ));
}

// spec-case: PY-BYTES-FUSED-RANGE-1
test "PY-BYTES-FUSED-RANGE-1 generic noalloc bodies accept immediate ranges" {
    try t.expectEqual(@as(i64, 42), try value(
        "func generic[T](raw: bytes, marker: T) -> int noalloc:\n" ++
            "    match raw[2:].parse_int():\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match raw.view(2, 4).parse_float():\n" ++
            "        case Some(number):\n" ++
            "            if number != 42.0:\n" ++
            "                return 3\n" ++
            "        case None:\n" ++
            "            return 4\n" ++
            "    return 42\n" ++
            "func main() -> int:\n" ++
            "    return generic[int](b\"xx42\", 0)\n",
    ));
}

// spec: FRONTEND-BYTES-PARENS-1
test "frontend parenthesized byte literals retain bytes identity through inferred conditionals" {
    try run(
        \\func choose(flag: bool) -> bytes:
        \\    const value = b"prefix" + (if flag then ((b"not_allowed")) else ((b"allowed")))
        \\    return value
        \\func main() -> int:
        \\    if choose(True) != b"prefixnot_allowed" or choose(False) != b"prefixallowed":
        \\        return 1
        \\    const raw = ((b"ab"))
        \\    return if raw == b"ab" then 42 else 2
    , 42);
}

// spec-case: FRONTEND-BYTES-PARENS-1
test "frontend parenthesized byte conditional arms respect contextual bytes and optional bytes" {
    try run(
        \\func choose(flag: bool) -> bytes:
        \\    return if flag then ((b"a")) else ((b"long"))
        \\func optional(flag: bool) -> bytes?:
        \\    return if flag then ((b"present")) else None
        \\func main() -> int:
        \\    const raw: bytes = if False then ((b"a")) else ((b"long"))
        \\    const present = optional(True)
        \\    if present is None:
        \\        return 1
        \\    return if raw == choose(False) and present == b"present" and optional(False) is None then 42 else 2
    , 42);
}

// spec-case: FRONTEND-BYTES-PARENS-1
test "frontend byte conditional fix preserves fixed array lengths and incompatible arm rejection" {
    try rejected("func main() -> int:\n    const values = if True then FixedArray[u8, 1]([1u8]) else FixedArray[u8, 2]([1u8, 2u8])\n    return len(values)\n", "E_TYPE");
    try rejected("func main() -> int:\n    const raw: bytes = if True then ((b\"a\")) else \"text\"\n    return len(raw)\n", "E_TYPE");
}
