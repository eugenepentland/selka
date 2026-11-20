//! Diagnostics and checked misses of the Python text surface; values live in guest tests.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");

fn reject(allocator: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    // A program that imports a module for a function form (W13-S5) is checked as an embedded project.
    if (std.mem.startsWith(u8, source, "import ")) return rejectProject(allocator, source, code);
    var compilation = try language.Compilation.init(allocator, "text-surface.selka", source);
    defer compilation.deinit();
    try std.testing.expectError(error.SourceError, compilation.check());
    try std.testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

/// `reject` for a program that imports a standard module: its first error carries `code`.
fn rejectProject(allocator: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), source);
    try std.testing.expect(!report.passed);
    try std.testing.expectEqualStrings(code, report.firstError().?.code);
}

fn miss(allocator: std.mem.Allocator, source: []const u8) !void {
    if (std.mem.startsWith(u8, source, "import ")) return fixture.trap(allocator, source, .{}, "R_SUBSTRING_NOT_FOUND");
    var compilation = try language.Compilation.init(allocator, "text-surface.selka", source);
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try std.testing.expect(result.trapped());
    try std.testing.expectEqualStrings("R_SUBSTRING_NOT_FOUND", result.trap.code);
}

// spec: PY-TEXT-RANGE-2
test "Python text surface: text and bytes index misses carry the substring trap" {
    try miss(std.testing.allocator, "func main() -> int:\n    return strings.char_index(\"abc\", \"z\")\n");
    try miss(std.testing.allocator, "import bytes\n\nfunc main() -> int:\n    return bytes.rindex(b\"abc\", b\"\", 4, 9)\n");
}

// spec-case: PY-TEXT-RANGE-1
test "Python text surface: ranged search rejects mismatched needles noninteger bounds and excess arguments" {
    try reject(std.testing.allocator, "func main() -> int:\n    return strings.char_find(\"abc\", b\"a\", 1)\n", "E_TYPE");
    try reject(std.testing.allocator, "func main() -> int:\n    mut text = \"abc\"\n    return strings.char_find(text, b\"a\")\n", "E_TYPE");
    try reject(std.testing.allocator, "import bytes\n\nfunc main() -> int:\n    return bytes.find(b\"abc\", b\"a\", \"bad\")\n", "E_TYPE");
    try reject(std.testing.allocator, "func main() -> int:\n    return strings.char_rfind(\"abc\", \"a\", 0, 3, 4)\n", "E_ARITY");
}

// spec-case: PY-TEXT-TRIM-1
test "Python text surface: trim charset family and source arity are checked" {
    try reject(std.testing.allocator, "import strings\n\nfunc main() -> int:\n    return len(strings.strip_chars(\"abc\", b\"a\"))\n", "E_TYPE");
    try reject(std.testing.allocator, "import bytes\n\nfunc main() -> int:\n    return len(bytes.strip_chars(b\"abc\", b\"a\", b\"b\"))\n", "E_ARITY");
}

// spec-case: PRELUDE-REPR-1
test "Python text surface: repr rejects a value with no repr and invalid arity" {
    // A list, set, dictionary, option, record, result or fixed array has one (F-38, F-38b, `src/collection_text_test.zig`); an
    // enum case does not (it has `case_name`).
    try reject(std.testing.allocator, "enum Kind:\n    alpha\n\nfunc main() -> int:\n    return len(repr(Kind.alpha))\n", "E_REPR_TYPE");
    try reject(std.testing.allocator, "func main() -> int:\n    return len(repr())\n", "E_ARITY");
}
