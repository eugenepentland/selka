//! Text-sized byte literals share array semantics through checking and native execution.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const byte_literal = @import("byte_literal.zig");
const program =
    \\func first[T](x: T) -> T:
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    mut a = first[FixedArray[u8, 4]](b"A\x00\xffB")
    \\    return i64(a[0]) + i64(a[2]) + i64(len(b"µ"))
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "bytes.selka", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 322), (try native.run(&c)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 322), (try native.run(&again)).value);
}
// spec: BYTE-LITERAL-1
test "byte literals preserve arbitrary bytes UTF8 lengths generic arrays and formatting" {
    try scenario(t.allocator);
}
test "byte literals reject invalid escapes and retain ordinary array type checks" {
    const Case = struct { text: []const u8, code: []const u8 };
    for ([_]Case{
        .{ .text = "def main() -> i64:\n    return len(\"\\q\")\n", .code = "E_BYTE_ESCAPE" },
        .{ .text = "def main() -> i64:\n    return len(\"\\x+f\")\n", .code = "E_BYTE_ESCAPE" },
        .{ .text = "def main() -> i64:\n    return len(\"\\x0\")\n", .code = "E_BYTE_ESCAPE" },
        .{ .text = "def main() -> i64:\n    return len(\"x\n\")\n", .code = "E_BYTE_LITERAL" },
        .{ .text =
        \\func f() -> FixedArray[u8, 1]:
        \\    return b"ab"
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_TYPE" },
    }) |case| {
        var c = try language.Compilation.init(t.allocator, "bad-byte.selka", case.text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings(case.code, c.diagnostics.items[0].code);
    }
}

/// The accepted spelling that every refused Unicode escape ends with.
const unicode_form = "write `\\u` and exactly four hexadecimal digits, as in `\\u00e9`, or `\\U` and exactly eight, as in `\\U0001f600`, for a character above U+FFFF";

/// Check that `text` is refused with `E_BYTE_ESCAPE` and `message`. With `repaired`, the diagnostic carries one edit, and the
/// program with it applied is that text and checks; without it, the diagnostic carries no repair.
fn refusedEscape(text: []const u8, message: []const u8, repaired: ?[]const u8) !void {
    var c = try language.Compilation.init(t.allocator, "escape.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const found = c.diagnostics.items[0];
    try t.expectEqualStrings("E_BYTE_ESCAPE", found.code);
    try t.expectEqualStrings(message, found.message);
    const expected = repaired orelse return t.expect(found.provenance.fix == null);
    const fix = found.provenance.fix.?;
    try t.expectEqual(@as(usize, 1), fix.count());
    const edit = fix.at(0);
    const applied = try std.mem.concat(t.allocator, u8, &.{ text[0..edit.span.start], edit.text, text[edit.span.end..] });
    defer t.allocator.free(applied);
    try t.expectEqualStrings(expected, applied);
    var again = try language.Compilation.init(t.allocator, "escape.selka", applied);
    defer again.deinit();
    try again.check();
}

test "a Unicode escape with braces is refused with the accepted spelling, and repaired when the braces hold one to four digits" {
    const head = "func main() -> int:\n    return len(\"";
    const tail = "\")\n";
    const braced = "a Unicode escape has no braces: " ++ unicode_form;
    try refusedEscape(head ++ "\\u{fffd}" ++ tail, braced, head ++ "\\ufffd" ++ tail);
    try refusedEscape(head ++ "a\\u{E9}b" ++ tail, braced, head ++ "a\\u00E9b" ++ tail);
    try refusedEscape(head ++ "\\u{00e9}" ++ tail, braced, head ++ "\\u00e9" ++ tail);
    try refusedEscape(head ++ "\\u{1f600}" ++ tail, braced, null);
    try refusedEscape(head ++ "\\U{1f600}" ++ tail, braced, null);
    try refusedEscape(head ++ "\\u{d800}" ++ tail, braced, null);
    try refusedEscape(head ++ "\\u{}" ++ tail, braced, null);
}

test "a Unicode escape with too few or wrong digits is refused with the accepted spelling" {
    const head = "func main() -> int:\n    return len(\"";
    const tail = "\")\n";
    try refusedEscape(head ++ "\\uzzzz" ++ tail, "invalid Unicode escape: " ++ unicode_form, null);
    try refusedEscape(head ++ "\\u12" ++ tail, "Unicode escape has too few hexadecimal digits: " ++ unicode_form, null);
    try refusedEscape("func main(out: Stream) -> int:\n    print(out, f\"x\\u{1}\")\n    return 0\n", "Unicode escape has too few hexadecimal digits: " ++ unicode_form, null);
}

test "byte literal decoded size limit reports E_BYTE_LITERAL_LIMIT before lowering" {
    const text = try t.allocator.alloc(u8, 65536 + 1 + 40);
    defer t.allocator.free(text);
    const prefix = "def main() -> i64:\n    return len(\"";
    @memcpy(text[0..prefix.len], prefix);
    @memset(text[prefix.len..][0..65537], 'a');
    const suffix = "\")\n";
    @memcpy(text[prefix.len + 65537 ..][0..suffix.len], suffix);
    var c = try language.Compilation.init(t.allocator, "large.selka", text[0 .. prefix.len + 65537 + suffix.len]);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_BYTE_LITERAL_LIMIT", c.diagnostics.items[0].code);
}

/// The message of the first diagnostic for a one-constant program whose initializer is `opening`, `count` letters `a`, `tail` and a closing quote.
fn limitMessage(opening: []const u8, count: usize, tail: []const u8, closing: []const u8) ![]u8 {
    const letters = try t.allocator.alloc(u8, count);
    defer t.allocator.free(letters);
    @memset(letters, 'a');
    const source = try std.mem.concat(t.allocator, u8, &.{ "const BIG: str = ", opening, letters, tail, closing, "\n\n\nfunc main() -> int:\n    return 0\n" });
    defer t.allocator.free(source);
    var c = try language.Compilation.init(t.allocator, "large.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_BYTE_LITERAL_LIMIT", c.diagnostics.items[0].code);
    return t.allocator.dupe(u8, c.diagnostics.items[0].message);
}

test "a literal over the limit names the two ways to hold a larger text: a constant joined with + and embed_str or embed_bytes" {
    const text = try limitMessage("\"", 65537, "", "\"");
    defer t.allocator.free(text);
    try t.expect(std.mem.startsWith(u8, text, "text literal exceeds 65536 decoded bytes; join shorter text literals with + in a constant"));
    try t.expect(std.mem.indexOf(u8, text, "embed_str(\"file\")") != null);
    try t.expect(std.mem.indexOf(u8, text, "input buffers") == null);
    const escaped = try limitMessage("\"", 65535, "\\u00e9", "\"");
    defer t.allocator.free(escaped);
    try t.expectEqualStrings(text, escaped);
    const bytes = try limitMessage("b\"", 65537, "", "\"");
    defer t.allocator.free(bytes);
    try t.expect(std.mem.startsWith(u8, bytes, "byte literal exceeds 65536 decoded bytes; join shorter byte literals with + in a constant"));
    try t.expect(std.mem.indexOf(u8, bytes, "embed_bytes(\"file\")") != null);
}

// spec-case: PY-BYTES-1
test "managed byte literals create no unused fixed-array catalog entries" {
    var c = try language.Compilation.init(t.allocator, "managed-byte-catalog.selka",
        \\const usage: bytes = b"abcdefghijklmnopq"
        \\func main() -> int:
        \\    mut inferred = b"abcdefghijklmnopqrs"
        \\    return len(usage) + len(inferred)
    );
    defer c.deinit();
    try c.check();
    for (c.program.?.records) |record| {
        if (record.shape.array) |array| {
            try t.expect(array.element != .u8 or (array.length != 17 and array.length != 19));
        }
    }
}

// spec-case: PY-BYTES-1
// spec-case: GENERIC-INFERENCE-1
test "byte literals retain contextual fixed arrays and generic length inference" {
    var c = try language.Compilation.init(t.allocator, "fixed-byte-catalog.selka",
        \\func literal[T](marker: T) -> FixedArray[u8, 3]:
        \\    return b"xyz"
        \\func count[const N: u64](value: [N]u8) -> int:
        \\    return len(value)
        \\func main() -> int:
        \\    mut explicit: FixedArray[u8, 5] = b"abcde"
        \\    return count(explicit) + count(literal[int](0))
    );
    defer c.deinit();
    try c.check();
    var three = false;
    var five = false;
    for (c.program.?.records) |record| {
        if (record.shape.array) |array| {
            if (array.element != .u8) continue;
            three = three or array.length == 3;
            five = five or array.length == 5;
        }
    }
    try t.expect(three and five);
    var bad = try language.Compilation.init(t.allocator, "wrong-fixed-byte.selka",
        \\func literal[T](marker: T) -> FixedArray[u8, 3]:
        \\    return b"long"
        \\func main() -> int:
        \\    return 0
    );
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_GENERIC_TYPE", bad.diagnostics.items[0].code);
}

test "tripleEnd and tripleFormatEnd find the first unescaped three quotes, and a format string's refusal names its line" {
    const diagnostic = language.diagnostic;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    try t.expectEqual(@as(usize, 8), try byte_literal.tripleEnd("\"\"\"ab\"\"\"x", 0, &sink));
    try t.expectEqual(@as(usize, 9), try byte_literal.tripleFormatEnd("\"\"\"a\\\"\"\"\"", 0, &sink));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    const open = "a\nb\n'''never closed\nmore";
    try t.expectError(error.SourceError, byte_literal.tripleFormatEnd(open, 4, &sink));
    try t.expectEqualStrings("unterminated triple-quoted format string: it opened on line 3 and has no closing three quotes of the same kind", sink.items.items[0].message);
    try t.expectEqual(@as(usize, 4), sink.items.items[0].span.start);
    try t.expectError(error.SourceError, byte_literal.tripleEnd(open, 4, &sink));
    try t.expectEqualStrings("unterminated triple-quoted literal; close it with three matching quotes", sink.items.items[1].message);
}
