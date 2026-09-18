//! Immutable constants fold scalars and retain managed literals before publication.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text =
        \\const ANSWER: i64 = BASE * 2
        \\
        \\
        \\const BASE: i64 = 21
        \\
        \\
        \\const MIN: i64 = -9223372036854775808
        \\
        \\
        \\const SAFE: bool = False and 1 // 0 == 1
        \\
        \\
        \\const WIDTH: u8 = u8(BASE)
        \\
        \\
        \\def work[T]() -> i64:
        \\    if SAFE:
        \\        return MIN
        \\    return ANSWER + i64(WIDTH)
        \\
        \\
        \\def main() -> i64:
        \\    return work[bool]()
    ;
    var compilation = try language.Compilation.init(allocator, "constants.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 63), (try native.run(&compilation)).value);
    try t.expectEqual(@as(@import("effect_set.zig").Mask, 0), compilation.program.?.functions[0].policy.effect_bound.?.allowed);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 63), (try native.run(&again)).value);
}
// spec: CONSTANT-1
test "scalar constants support forward dependencies checked widths short circuit and generic uses" {
    try scenario(t.allocator);
}
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const text = if (std.mem.eql(u8, path, "main.my"))
        \\module main
        \\import constants
        \\
        \\
        \\def main() -> i64:
        \\    return constants.VALUE
    else if (std.mem.eql(u8, path, "constants.my"))
        \\module constants
        \\
        \\
        \\public const VALUE: i64 = FACTOR * 6
        \\
        \\
        \\const FACTOR: i64 = 7
    else
        return error.NotFound;
    return allocator.dupe(u8, text);
}
test "exported constants retain module identity and private initializer dependencies" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&program.compilation)).value);
}

const managed_literals =
    \\type Text = str
    \\type Octets = bytes
    \\const TEXT: Text = "hé🙂\n\0"
    \\const DATA: Octets = b"\x00\xff\n"
    \\const EMPTY_TEXT: str = ""
    \\const EMPTY_DATA: bytes = b""
    \\def read[T]() -> int effects(managed_allocation):
    \\    return len(TEXT) + len(DATA) + len(EMPTY_TEXT) + len(EMPTY_DATA)
    \\def main() -> int effects(managed_allocation):
    \\    if TEXT != "hé🙂\n\0" or DATA != b"\x00\xff\n":
    \\        return 1
    \\    return read[bool]() + read[int]() + DATA[1]
;
// spec: CONSTANT-2
test "managed constants preserve literal content aliases generic reads effects and formatting" {
    var compilation = try language.Compilation.init(t.allocator, "managed-constants.my", managed_literals);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 271), (try native.run(&compilation)).value);
    const allocation = @import("effect_set.zig").bit(.managed_allocation);
    // Constant initializers are published as synthetic functions: a str constant
    // materializes its scalar codepoints without a managed allocation, while a
    // bytes constant keeps its owned byte buffer. An explicit ceiling stays
    // published as an upper bound.
    try t.expectEqual(@as(@import("effect_set.zig").Mask, 0), compilation.program.?.functions[0].policy.effects);
    try t.expectEqual(allocation, compilation.program.?.functions[1].policy.effects);
    try t.expectEqual(allocation, compilation.program.?.functions[0].policy.effect_bound.?.allowed);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 271), (try native.run(&again)).value);
}

fn acceptConstant(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "valid-constant.my", text);
    defer compilation.deinit();
    try compilation.check();
}

fn rejectConstant(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-constant.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec-case: CONSTANT-2
test "managed constants reject nonliteral initializers even when unused" {
    for ([_][]const u8{
        "const S: str = make()\ndef make() -> str:\n    return \"x\"\n",
        "const B: bytes = make()\ndef make() -> bytes:\n    return b\"x\"\n",
        "const S: str = \"x\" + \"y\"\n",
        "const B: bytes = b\"x\" + b\"y\"\n",
        "const S: str = str(42)\n",
        "const B: bytes = bytes.fromhex(\"ff\")\n",
        "const S: str = OTHER\nconst OTHER: str = \"x\"\n",
        "const B: bytes = OTHER\nconst OTHER: bytes = b\"x\"\n",
        "const S: str = f\"value {42}\"\n",
        "const S: str = \"xy\"[0]\n",
        "const B: bytes = b\"xy\"[0:1]\n",
    }) |declaration| {
        const text = try std.mem.concat(t.allocator, u8, &.{ declaration, "def main() -> int:\n    return 0\n" });
        defer t.allocator.free(text);
        try rejectConstant(text, "E_CONSTANT_EXPRESSION");
    }
}

// spec-case: CONSTANT-2
test "managed constants require matching literal types and keep byte or generic reads allocating" {
    try rejectConstant("const S: str = b\"x\"\ndef main() -> int:\n    return 0\n", "E_TYPE");
    try rejectConstant("const B: bytes = \"x\"\ndef main() -> int:\n    return 0\n", "E_TYPE");
    // A non-generic str constant read is a compile-time scalar, so an explicit
    // noalloc ceiling accepts it; a bytes constant, and any generic body that
    // returns one, still contributes managed_allocation.
    try acceptConstant("const S: str = \"x\"\ndef main() -> int noalloc:\n    return len(S)\n");
    try rejectConstant("const B: bytes = b\"x\"\ndef main() -> int effects():\n    return len(B)\n", "E_EFFECT_BOUND");
    try rejectConstant("const S: str = \"x\"\ndef unused[T]() -> str noalloc:\n    return S\ndef main() -> int:\n    return 0\n", "E_EFFECT_BOUND");
    try rejectConstant("const B: bytes = b\"x\"\ndef unused[T]() -> bytes effects():\n    return B\ndef main() -> int:\n    return 0\n", "E_EFFECT_BOUND");
}
