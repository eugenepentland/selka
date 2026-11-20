//! Integrated Python byte-string syntax, conversions, storage and rejections.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const native = @import("native_execute.zig");
const effect_bound = "E_EFFECTS_REMOVED";

fn printDiagnostics(c: *language.Compilation) void {
    for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
}

fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "bytes.selka", source);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{}) catch |err| {
        printDiagnostics(&c);
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}

/// The one source an embedded project holds: `main.selka` and nothing else.
const ProjectEntry = struct {
    text: []const u8,
    /// Answer the project's only module, `main.selka`; every other path is absent.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
    }
};

/// Run one program that imports a standard module and require its exit value.
/// A single-unit compilation cannot carry an `import`, so the source is checked
/// as an embedded project.
fn valueProject(source: []const u8) !i64 {
    var entry: ProjectEntry = .{ .text = source };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = ProjectEntry.read });
    defer program.deinit();
    const result = native.runWithOptions(&program.compilation, .{}) catch |err| {
        for (program.compilation.diagnostics.items.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, program.compilation.src.text(d.span) });
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    return result.value;
}

/// Run one program that imports a standard module and require its trap code.
fn trappedProject(source: []const u8, code: []const u8) !void {
    var entry: ProjectEntry = .{ .text = source };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = ProjectEntry.read });
    defer program.deinit();
    const result = native.runWithOptions(&program.compilation, .{}) catch |err| {
        for (program.compilation.diagnostics.items.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, program.compilation.src.text(d.span) });
        return err;
    };
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
}

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-trap.selka", source);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{}) catch |err| {
        printDiagnostics(&c);
        return err;
    };
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
}

/// `rejected` for a program that imports a standard module (F-b11): the single-unit
/// checker refuses an import, so the program is checked as a project.
fn rejectedProject(source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), source);
    try t.expect(!report.passed);
    for (report.diagnostics) |d| if (std.mem.eql(u8, d.code, code)) return;
    return t.expect(false);
}

fn rejected(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-reject.selka", source);
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
    // A program that imports a standard module (W13-S5's function forms) is checked as an embedded project.
    if (std.mem.startsWith(u8, source, "import ")) return valueProject(source);
    var c = try language.Compilation.init(t.allocator, "utf8-decode.selka", source);
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
    // The original literal-negative source remains an executable removal diagnostic.
    try rejected("func main() -> int:\n    mut raw = b\"ab\"\n    return raw[-3]\n", "E_NEGATIVE_INDEX_REMOVED");
    var negative = try language.Compilation.init(t.allocator, "bytes-negative-trap.selka", "func main() -> int:\n    mut raw = b\"ab\"\n    return raw[0 - len(raw) - 1]\n");
    defer negative.deinit();
    const result = try native.runWithOptions(&negative, .{});
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
    try t.expect(std.mem.indexOf(u8, result.stderr, "(index -3, length 2)") != null);
    try trappedProject("import bytes\n\nfunc main() -> int:\n    return len(bytes.split(b\"ab\", b\"\"))\n", "R_EMPTY_SEPARATOR");
    try trapped("func main() -> int:\n    mut values: int[] = [256]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
    try trapped("func main() -> int:\n    mut values: int[] = [0 - 1]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
    // The bounded `find_any` (R3-FINDEND): a literal negative `end` is the removal diagnostic, a computed one traps.
    try rejectedProject("import bytes\n\nfunc main() -> int:\n    return bytes.find_any(b\"ab\", b\"a\", 0, -1)\n", "E_NEGATIVE_INDEX_REMOVED");
    try trappedProject("import bytes\n\nfunc scan(data: bytes, end: int) -> int:\n    return bytes.find_any(data, b\"a\", 0, end)\n\nfunc main() -> int:\n    mut raw = b\"ab\"\n    return scan(raw, 0 - len(raw))\n", "R_LIST_BOUNDS");
}

test "bytes.replace with an empty needle traps with R_EMPTY_SEPARATOR, as split does" {
    try trappedProject("import bytes\n\nfunc main() -> int:\n    return len(bytes.replace(b\"ab\", b\"\", b\"x\"))\n", "R_EMPTY_SEPARATOR");
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
    // migrate-embedded: skip intentional original retirement/negative-bound source
    try rejected(
        "func build() -> int effects():\n    mut raw = b\"ab\"\n    return len(raw)\nfunc main() -> int:\n    return build()\n",
        effect_bound,
    );
    // migrate-embedded: skip intentional original retirement/negative-bound source
    try rejected(
        "func grow(a: bytes, b: bytes) -> int effects():\n    return len(a + b)\nfunc main() -> int:\n    return grow(b\"a\", b\"b\")\n",
        effect_bound,
    );
    // migrate-embedded: skip intentional original retirement/negative-bound source
    try rejected(
        "func cut(a: bytes) -> int effects():\n    return len(a[0:1])\nfunc main() -> int:\n    return cut(b\"ab\")\n",
        effect_bound,
    );
}

// spec: PY-BYTES-5
test "PY-BYTES-5 every byte-string operation builds and runs natively" {
    const source =
        \\import bytes
        \\import hex
        \\import strings
        \\
        \\func main() -> int:
        \\    mut raw = b"a,b" + b",c"
        \\    mut parts = bytes.split(raw, b",")
        \\    if bytes.join(parts, b",") != raw or raw[0:1] != b"a":
        \\        return 1
        \\    if not bytes.starts_with(raw, b"a") or bytes.ends_with(raw, b"z") or bytes.find(raw, b"b") != 2:
        \\        return 2
        \\    if 97 not in raw or b"b," not in raw:
        \\        return 3
        \\    if bytes(bytes.to_list(raw)) != raw or hex.encode(raw) != "612c622c63":
        \\        return 4
        \\    match strings.decode(raw):
        \\        case Ok(text):
        \\            if strings.encode(text) != raw:
        \\                return 5
        \\        case Err(message):
        \\            return 0 - strings.char_count(message)
        \\    match hex.decode("612c"):
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(message):
        \\            return 0 - strings.char_count(message)
    ;
    try t.expectEqual(@as(i64, 2), try valueProject(source));
}

/// Guest program: decode valid ASCII and 2/3/4-byte UTF-8, compare each result
/// with the `str` literal it must equal, and re-encode to pin the exact scalar
/// sequence rather than only the length.
const valid_utf8_decode =
    \\import strings
    \\
    \\func text_of(raw: bytes) -> str:
    \\    match strings.decode(raw):
    \\        case Ok(text):
    \\            return text
    \\        case Err(message):
    \\            return message
    \\
    \\
    \\func main() -> int:
    \\    if text_of(b"abc") != "abc":
    \\        return 1
    \\    if strings.encode(text_of(b"abc")) != b"abc":
    \\        return 2
    \\    if text_of(b"\xc3\xa9") != "\u00e9":
    \\        return 3
    \\    if strings.encode(text_of(b"\xc3\xa9")) != b"\xc3\xa9":
    \\        return 4
    \\    if text_of(b"\xe2\x82\xac") != "\u20ac":
    \\        return 5
    \\    if strings.encode(text_of(b"\xe2\x82\xac")) != b"\xe2\x82\xac":
    \\        return 6
    \\    if text_of(b"\xf0\x9f\x98\x80") != "\U0001f600":
    \\        return 7
    \\    if strings.encode(text_of(b"\xf0\x9f\x98\x80")) != b"\xf0\x9f\x98\x80":
    \\        return 8
    \\    if strings.char_count(text_of(b"a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80")) != 4:
    \\        return 9
    \\    return 0
;

/// Guest program: every overlong, surrogate and out-of-range encoding must
/// reach `Err` with the runtime's existing invalid-UTF-8 message, which is what
/// an `MYL_BYTES_INVALID` status publishes (an allocation failure would trap).
const invalid_utf8_encoding =
    \\import strings
    \\
    \\func status_of(raw: bytes) -> str:
    \\    match strings.decode(raw):
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
    \\import strings
    \\
    \\func status_of(raw: bytes) -> str:
    \\    match strings.decode(raw):
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

// spec-case: PY-BYTES-6
test "byte_buffer append takes the whole argument like append_range" {
    try t.expectEqual(@as(i64, 42), try valueProject(
        \\import buffers
        \\
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut out = byte_buffer(empty)
        \\    buffers.append(mut out, b"ab")
        \\    buffers.append(mut out, b"cd")
        \\    if len(out) != 4 or out[0] != 97 or out[3] != 100:
        \\        return 3
        \\    buffers.append(mut out, b"")
        \\    if len(out) != 4:
        \\        return 5
        \\    return 42
    ));
    try rejected("func main() -> int:\n    mut raw = b\"ab\"\n    return len(raw.append(b\"c\"))\n", "E_COLLECTION_METHOD");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "text and buffers support independent copies" {
    try t.expectEqual(@as(i64, 0), try value("func main() -> int:\n    mut empty: int[] = []\n    mut data = byte_buffer(empty)\n    return len(copy(data))\n"));
    try t.expectEqual(@as(i64, 3), try value("func main() -> int:\n    mut text = \"abc\"\n    return strings.char_count(copy(text))\n"));
}

// spec-case: PY-BYTES-8
test "scalar_count requires immutable bytes" {
    try rejected("func main() -> int:\n    mut text = \"abc\"\n    return len(text.scalar_count())\n", "E_COLLECTION_METHOD");
}

// spec-case: PY-BYTES-9
test "PY-BYTES-9 numeric parsing is accepted under noalloc and an explicit ceiling rejects a view" {
    try t.expectEqual(@as(i64, 42), try value(
        "@noalloc\nfunc parse(text: str) -> int:\n" ++
            "    match parse_int(text):\n" ++
            "        case Some(found):\n" ++
            "            return found\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "import bytes\n\n@noalloc\nfunc parse(raw: bytes) -> int:\n" ++
            "    match bytes.parse_int(raw):\n" ++
            "        case Some(found):\n" ++
            "            return found\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(b\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "import bytes\n\n@noalloc\nfunc measure(raw: bytes) -> int:\n" ++
            "    match bytes.scalar_count(raw):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 40\n" ++
            "        case Err(_):\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return measure(b\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "@noalloc\nfunc same(raw: bytes, expected: bytes) -> int:\n    if raw == expected:\n        return 42\n    return 0\n" ++
            "func main() -> int:\n    return same(b\"42\", b\"42\")\n",
    ));
    try t.expectEqual(@as(i64, 42), try value(
        "@noalloc\nfunc parse(text: str) -> int:\n" ++
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
        "import bytes\n\n@noalloc\nfunc parse(raw: bytes) -> int:\n" ++
            "    match bytes.parse_float(raw):\n" ++
            "        case Some(found):\n" ++
            "            if found > 2.0:\n" ++
            "                return 42\n" ++
            "            return 0\n" ++
            "        case None:\n" ++
            "            return 0\n" ++
            "func main() -> int:\n" ++
            "    return parse(b\"2.5\")\n",
    ));
    // migrate-embedded: skip intentional original retirement/negative-bound source
    try rejected("func peek(raw: bytes) -> int effects():\n    return len(raw.view(0, 1))\nfunc main() -> int:\n    return peek(b\"abc\")\n", effect_bound);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "noalloc scalar counting preserves the fixed invalid UTF8 payload" {
    try t.expectEqual(@as(i64, 42), try value(
        "import bytes\n\n@noalloc\nfunc measure(raw: bytes) -> int:\n" ++
            "    match bytes.scalar_count(raw):\n" ++
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

const ExplicitBound = struct { before: []const u8, after: []const u8 };

/// Keep the legacy source executable as a removal assertion, then run its explicit-bound copy.
fn explicitBoundsValue(source: []const u8, bounds: []const ExplicitBound) !i64 {
    const noalloc_clause = " noalloc:";
    const legacy_noalloc = std.mem.indexOf(u8, source, noalloc_clause) != null;
    try rejectedProject(source, if (legacy_noalloc) "E_EFFECTS_REMOVED" else "E_NEGATIVE_INDEX_REMOVED");
    var modern = try t.allocator.dupe(u8, source);
    defer t.allocator.free(modern);
    if (legacy_noalloc) {
        try t.expectEqual(@as(usize, 1), std.mem.count(u8, source, noalloc_clause));
        const declaration = try std.mem.replaceOwned(u8, t.allocator, modern, noalloc_clause, ":");
        defer t.allocator.free(declaration);
        // The annotation goes on the declaration, after any `import` the program now starts with (F-b11).
        const at = std.mem.indexOf(u8, declaration, "func ") orelse return error.TestUnexpectedResult;
        const annotated = try std.mem.concat(t.allocator, u8, &.{ declaration[0..at], "@noalloc\n", declaration[at..] });
        t.allocator.free(modern);
        modern = annotated;
        try rejectedProject(modern, "E_NEGATIVE_INDEX_REMOVED");
    }
    for (bounds) |bound| {
        try t.expect(std.mem.indexOf(u8, modern, bound.before) != null);
        const updated = try std.mem.replaceOwned(u8, t.allocator, modern, bound.before, bound.after);
        t.allocator.free(modern);
        modern = updated;
    }
    return valueProject(modern);
}

// spec: PY-BYTES-RANGE-1
test "PY-BYTES-RANGE-1 range parsing and scalar counting clamp without a view allocation" {
    try t.expectEqual(@as(i64, 42), try explicitBoundsValue(
        "import bytes\n\n" ++
            "func ranged(raw: bytes) -> int noalloc:\n" ++
            "    match bytes.parse_int_range(raw, 2, 4):\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match bytes.parse_float_range(raw, 5, 8):\n" ++
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
            "    match bytes.scalar_count_range(raw, 0 - 3, 99):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 39\n" ++
            "        case Err(_):\n" ++
            "            return 5\n",
        &.{
            .{ .before = "scalar_count_range(raw, 0 - 3, 99)", .after = "scalar_count_range(raw, max(len(raw) - 3, 0), 99)" },
        },
    ));
    try t.expectEqual(@as(i64, 42), try valueProject(
        "import bytes\n\n" ++
            "func main() -> int:\n" ++
            "    mut raw = b\"x-9223372036854775808y\"\n" ++
            "    match bytes.parse_int_range(raw, 1, 21):\n" ++
            "        case Some(number):\n" ++
            "            if number != -9223372036854775808:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match bytes.parse_int_range(raw, 21, 1):\n" ++
            "        case Some(_):\n" ++
            "            return 3\n" ++
            "        case None:\n" ++
            "            pass\n" ++
            "    match bytes.scalar_count_range(b\"a\\xce\\xbbb\", 1, 3):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 41\n" ++
            "        case Err(_):\n" ++
            "            return 4\n",
    ));
    try t.expectEqual(@as(i64, 42), try explicitBoundsValue(
        "import bytes\n\n" ++
            "func main() -> int:\n" ++
            "    mut values: int[] = []\n" ++
            "    mut raw = bytes(values)\n" ++
            "    match bytes.parse_int_range(raw, 0 - 10, 10):\n" ++
            "        case Some(_):\n" ++
            "            return 1\n" ++
            "        case None:\n" ++
            "            pass\n" ++
            "    match bytes.scalar_count_range(raw, 0 - 10, 10):\n" ++
            "        case Ok(width):\n" ++
            "            return width + 42\n" ++
            "        case Err(_):\n" ++
            "            return 2\n",
        &.{
            .{ .before = "0 - 10", .after = "max(len(raw) - 10, 0)" },
        },
    ));
    try t.expectEqual(@as(i64, 42), try valueProject(
        "import bytes\n\n" ++
            "func main() -> int:\n" ++
            "    match bytes.scalar_count_range(b\"a\\xffb\", 1, 2):\n" ++
            "        case Ok(_):\n" ++
            "            return 1\n" ++
            "        case Err(message):\n" ++
            "            if message == \"invalid UTF-8 in byte string\":\n" ++
            "                return 42\n" ++
            "            return 2\n",
    ));
    try rejectedProject(
        "import bytes\n\n" ++
            "func measure(raw: bytes) -> int effects():\n" ++
            "    match bytes.scalar_count_range(raw, 0, len(raw)):\n" ++
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
test "PY-BYTES-FUSED-RANGE-1 immediate slices parse under noalloc" {
    // migrate-embedded: skip intentional original retirement/negative-bound source
    try t.expectEqual(@as(i64, 42), try explicitBoundsValue(
        "import bytes\n\n" ++
            "func fused(raw: bytes) -> int noalloc:\n" ++
            "    match bytes.parse_int(raw[2:4]):\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match bytes.parse_float(raw[5:8]):\n" ++
            "        case Some(number):\n" ++
            "            if number != 2.5:\n" ++
            "                return 3\n" ++
            "        case None:\n" ++
            "            return 4\n" ++
            "    match bytes.parse_int(raw[0 - 8:0 - 6]):\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 5\n" ++
            "        case None:\n" ++
            "            return 6\n" ++
            "    match bytes.parse_int(raw[8:2]):\n" ++
            "        case Some(_):\n" ++
            "            return 7\n" ++
            "        case None:\n" ++
            "            pass\n" ++
            "    return 42\n" ++
            "func main() -> int:\n" ++
            "    if fused(b\"xx42=2.5yy\") != 42:\n" ++
            "        return 8\n" ++
            "    match bytes.parse_int(b\"42\"[:]):\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 9\n" ++
            "        case None:\n" ++
            "            return 10\n" ++
            "    match bytes.parse_int(b\"42\"[0 - 99:99]):\n" ++
            "        case Some(number):\n" ++
            "            return number\n" ++
            "        case None:\n" ++
            "            return 11\n",
        &.{
            .{ .before = "raw[0 - 8:0 - 6]", .after = "raw[max(len(raw) - 8, 0):max(len(raw) - 6, 0)]" },
            .{ .before = "0 - 99:99", .after = "0:99" },
        },
    ));
    // migrate-embedded: skip intentional original retirement/negative-bound source
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
    // migrate-embedded: skip intentional original retirement/negative-bound source
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
    // migrate-embedded: skip intentional original retirement/negative-bound source
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
        \\import bytes
        \\
        \\func source(mut log: int[], raw: bytes) -> bytes:
        \\    log[0] = log[0] + 1
        \\    return copy(raw)
        \\func bound(mut log: int[]) -> int:
        \\    mut value = log[0]
        \\    log[0] = value + 1
        \\    return value
        \\func main() -> int:
        \\    mut log: int[] = [0]
        \\    match bytes.parse_int(source(mut log, b"x42")[bound(mut log):bound(mut log)]):
        \\        case Some(number):
        \\            if number != 4 or log[0] != 3:
        \\                return 1
        \\        case None:
        \\            return 2
        \\    return 42
        \\
        ,
    ));
}

// spec-case: PY-BYTES-FUSED-RANGE-1
test "PY-BYTES-FUSED-RANGE-1 generic noalloc bodies accept immediate ranges" {
    try t.expectEqual(@as(i64, 42), try value(
        "import bytes\n\n@noalloc\nfunc generic[T](raw: bytes, marker: T) -> int:\n" ++
            "    match bytes.parse_int(raw[2:]):\n" ++
            "        case Some(number):\n" ++
            "            if number != 42:\n" ++
            "                return 1\n" ++
            "        case None:\n" ++
            "            return 2\n" ++
            "    match bytes.parse_float(raw[2:4]):\n" ++
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
        \\    const prefix = b"prefix"
        \\    const suffix: bytes
        \\    if flag:
        \\        suffix = ((b"not_allowed"))
        \\    else:
        \\        suffix = ((b"allowed"))
        \\    const value = prefix + suffix
        \\    return value
        \\func main() -> int:
        \\    if choose(True) != b"prefixnot_allowed" or choose(False) != b"prefixallowed":
        \\        return 1
        \\    const raw = ((b"ab"))
        \\    if raw == b"ab":
        \\        return 42
        \\    else:
        \\        return 2
    , 42);
}

// spec-case: FRONTEND-BYTES-PARENS-1
test "frontend parenthesized byte conditional arms respect contextual bytes and optional bytes" {
    try run(
        \\func choose(flag: bool) -> bytes:
        \\    if flag:
        \\        return ((b"a"))
        \\    else:
        \\        return ((b"long"))
        \\func optional(flag: bool) -> bytes?:
        \\    if flag:
        \\        return ((b"present"))
        \\    else:
        \\        return None
        \\func main() -> int:
        \\    const raw: bytes
        \\    if False:
        \\        raw = ((b"a"))
        \\    else:
        \\        raw = ((b"long"))
        \\    const present = optional(True)
        \\    if present is None:
        \\        return 1
        \\    if raw == choose(False) and present == b"present" and optional(False) is None:
        \\        return 42
        \\    else:
        \\        return 2
    , 42);
}

// spec-case: FRONTEND-BYTES-PARENS-1
test "frontend byte conditional fix preserves fixed array lengths and incompatible arm rejection" {
    try rejected("func main() -> int:\n    const values = if True then FixedArray[u8, 1]([1u8]) else FixedArray[u8, 2]([1u8, 2u8])\n    return len(values)\n", "E_TYPE");
    try rejected("func main() -> int:\n    const raw: bytes = if True then ((b\"a\")) else \"text\"\n    return len(raw)\n", "E_CONDITIONAL_EXPRESSION_REMOVED");
}

// spec-case: FRONTEND-BYTES-PARENS-1
test "statement byte selection rejects an incompatible typed string arm" {
    try rejected("func main() -> int:\n    const text: str = \"text\"\n    mut raw: bytes\n    if True:\n        raw = ((b\"a\"))\n    else:\n        raw = text\n    return len(raw)\n", "E_TYPE");
}

test "PY-BYTES-FUSED-RANGE-1 generic grouped literals preserve bytes text and array contexts" {
    try run(
        \\func grouped[T](marker: T) -> bool:
        \\    const raw = (( b"42" ))
        \\    const text = (( "42" ))
        \\    const fixed: FixedArray[u8, 2] = (( b"42" ))
        \\    return raw == b"42" and text == "42" and fixed[0] == 52u8 and len(raw) == 2
        \\func main() -> int:
        \\    if grouped[int](0):
        \\        return 42
        \\    return 0
    , 42);
}
