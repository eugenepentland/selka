//! Native lowering of the Python string methods and the pinned number grammar.
//! `tests/qbe_text.py` compares the produced executables against the VM; these
//! tests pin that every method reaches the native runtime at all, rather than
//! reporting `E_QBE_UNSUPPORTED` and falling back to the interpreter.
const std = @import("std");
const language = @import("compiler.zig");

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
    "myl_native_text_trim",    "myl_native_text_case",    "myl_native_text_zfill",
    "myl_native_text_replace", "myl_native_text_count",   "myl_native_text_find",
    "myl_native_text_lines",   "myl_native_text_edge",    "myl_native_text_every",
    "myl_native_text_points",  "myl_native_number_parse", "myl_qbe_fail_empty_separator",
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
    try std.testing.expect(std.mem.indexOf(u8, emitted, "myl_native_number_parse") != null);
    const plain = try manifest(a, "def main() -> int:\n    return len(\"ab\")\n");
    defer a.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "\"text_format\":false") != null);
}
