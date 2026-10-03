//! Native lowering of the Python string methods and the pinned number grammar.
//! `tests/qbe_text.py` compares the produced executables against the VM; these
//! tests pin that every method reaches the native runtime at all, rather than
//! reporting `E_QBE_UNSUPPORTED` and falling back to the interpreter.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const debug = std.debug;

/// One guest program that touches every `str` method and both intrinsics.
const every_method =
    \\def main() -> int:
    \\    padded = "  7  "
    \\    total = len(padded.strip()) + len(padded.lstrip()) + len(padded.rstrip())
    \\    total = total + len("a".upper()) + len("A".lower()) + len("x".zfill(3))
    \\    total = total + len("aba".replace("a", "b")) + "aba".count("a") + "aba".find("b")
    \\    total = total + len("a\nb".splitlines())
    \\    if "aba".startswith("a"):
    \\        total = total + 1
    \\    if "aba".endswith("a"):
    \\        total = total + 1
    \\    if "42".isdigit():
    \\        total = total + 1
    \\    if "ab".isalpha():
    \\        total = total + 1
    \\    if " ".isspace():
    \\        total = total + 1
    \\    match int("42"):
    \\        case Some(value):
    \\            total = total + value
    \\        case None:
    \\            total = total - 1
    \\    for letter in "abc":
    \\        total = total + len(letter)
    \\    for index, letter in enumerate("ab"):
    \\        total = total + index + len(letter)
    \\    match float("2.5"):
    \\        case Some(number):
    \\            total = total + len(str(number))
    \\        case None:
    \\            total = total - 1
    \\    return total
;

/// Runtime entry points the lowering must reach for the methods above.
const required = [_][]const u8{
    "myl_native_text_trim",    "myl_native_text_case",          "myl_native_text_zfill",
    "myl_native_text_replace", "myl_native_text_count",         "myl_native_text_find",
    "myl_native_text_lines",   "myl_native_text_edge",          "myl_native_text_every",
    "myl_native_text_payload", "myl_native_bytes_number_parse", "myl_qbe_fail_empty_separator",
};

fn manifest(a: std.mem.Allocator, source: []const u8) ![]u8 {
    var c = try language.Compilation.init(a, "text.my", source);
    defer c.deinit();
    return c.emitQbe(a);
}

// spec: PY-STR-4
test "every Python string method lowers onto the native text runtime" {
    const a = std.testing.allocator;
    const emitted = try manifest(a, every_method);
    defer a.free(emitted);
    for (required) |symbol| try std.testing.expect(std.mem.indexOf(u8, emitted, symbol) != null);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "E_QBE_UNSUPPORTED") == null);
}

// spec: PY-NUM-3
test "number parsing selects the shared text runtime unit and answers an option" {
    const a = std.testing.allocator;
    const emitted = try manifest(a, "def main() -> int:\n    match int(\"42\"):\n        case Some(value):\n            return value\n        case None:\n            return 0\n");
    defer a.free(emitted);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "\"text_format\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "myl_native_bytes_number_parse") != null);
    const plain = try manifest(a, "def main() -> int:\n    return len(\"ab\")\n");
    defer a.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "\"text_format\":false") != null);
}

// spec-case: UTF8-TEXT-1
// spec-case: PY-BYTES-1
// spec-case: EQUALITY-SCRATCH-1
test "immutable equality resolves text and bytes leaves without structural failure branches" {
    const a = std.testing.allocator;
    const emitted = try manifest(a,
        \\def same_text(left: str, right: str) -> bool:
        \\    return left == right
        \\def different_bytes(left: bytes, right: bytes) -> bool:
        \\    return left != right
        \\def main() -> int:
        \\    if same_text("a", "b") or different_bytes(b"a", b"a"):
        \\        return 0
        \\    return 42
    );
    defer a.free(emitted);
    for ([_][]const u8{ "call $myl_native_text_equal", "call $myl_native_bytes_equal" }) |symbol|
        try std.testing.expect(std.mem.indexOf(u8, emitted, symbol) != null);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "call $myl_native_equal(") == null);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "call $myl_qbe_fail_equality(") == null);
    const structural = try manifest(a,
        \\def same(left: list[float], right: list[float]) -> bool:
        \\    return left == right
        \\def main() -> int:
        \\    values: list[float] = [0.0 / 0.0]
        \\    if same(values, values):
        \\        return 0
        \\    return 42
    );
    defer a.free(structural);
    try std.testing.expect(std.mem.indexOf(u8, structural, "call $myl_native_equal(") != null);
    try std.testing.expect(std.mem.indexOf(u8, structural, "call $myl_qbe_fail_equality(") != null);
}

// spec-case: PY-NUM-3
test "integer text conversions resolve bounded signed and unsigned helpers" {
    const a = std.testing.allocator;
    const emitted = try manifest(a,
        \\def signed(value: int) -> str:
        \\    return str(value)
        \\def unsigned(value: u64) -> str:
        \\    return str(value)
        \\def main() -> int:
        \\    return len(signed(42)) + len(unsigned(42))
    );
    defer a.free(emitted);
    for ([_][]const u8{ "call $myl_native_text_integer", "call $myl_native_text_unsigned" }) |symbol|
        try std.testing.expect(std.mem.indexOf(u8, emitted, symbol) != null);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "call $myl_native_text_scalar(") == null);
}

/// Run one guest program under GC stress and return its exit value. A trap is
/// reported and turned into an assertion failure so a runtime refusal cannot
/// look like an ordinary nonzero result a test forgot to check.
fn value(allocator: std.mem.Allocator, source: []const u8) !i64 {
    var c = try language.Compilation.init(allocator, "text-find.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try std.testing.expect(!result.trapped());
    return result.value;
}

/// Guest program pinning `str.find`'s first-scalar-index answer for one-scalar,
/// multi-scalar and longer-than-the-receiver needles, including multi-byte
/// scalars whose low byte also occurs inside another scalar.
const find_shapes =
    \\def main() -> int:
    \\    text = "the quick brown fox"
    \\    if text.find("t") != 0:
    \\        return 1
    \\    if text.find("q") != 4:
    \\        return 2
    \\    if text.find("quick") != 4:
    \\        return 3
    \\    if text.find("fox") != 16:
    \\        return 4
    \\    if text.find("zebra") != -1:
    \\        return 5
    \\    if "aaa".find("aaaa") != -1:
    \\        return 6
    \\    if "héllo".find("é") != 1:
    \\        return 7
    \\    if "héllo".find("llo") != 2:
    \\        return 8
    \\    if "日本語".find("本") != 1:
    \\        return 9
    \\    if "日本語".find("語日") != -1:
    \\        return 10
    \\    return 42
;

// spec-case: PY-STR-2
test "PY-STR-2 find answers the first scalar index for short long and overlong needles" {
    try std.testing.expectEqual(@as(i64, 42), try value(std.testing.allocator, find_shapes));
}
