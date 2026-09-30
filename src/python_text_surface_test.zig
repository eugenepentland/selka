//! Diagnostics and checked misses of the Python text surface; values live in guest tests.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn reject(allocator: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "text-surface.my", source);
    defer compilation.deinit();
    try std.testing.expectError(error.SourceError, compilation.check());
    try std.testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

fn miss(allocator: std.mem.Allocator, source: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "text-surface.my", source);
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try std.testing.expect(result.trapped());
    try std.testing.expectEqualStrings("R_SUBSTRING_NOT_FOUND", result.trap.code);
}

// spec: PY-TEXT-RANGE-2
test "Python text surface: text and bytes index misses carry the substring trap" {
    try miss(std.testing.allocator, "def main() -> int:\n    return \"abc\".index(\"z\")\n");
    try miss(std.testing.allocator, "def main() -> int:\n    return b\"abc\".rindex(b\"\", 4, 9)\n");
}

// spec-case: PY-TEXT-RANGE-1
test "Python text surface: ranged search rejects mismatched needles noninteger bounds and excess arguments" {
    try reject(std.testing.allocator, "def main() -> int:\n    return \"abc\".find(b\"a\", 1)\n", "E_TYPE");
    try reject(std.testing.allocator, "def main() -> int:\n    text = \"abc\"\n    return text.find(b\"a\")\n", "E_TYPE");
    try reject(std.testing.allocator, "def main() -> int:\n    return b\"abc\".find(b\"a\", \"bad\")\n", "E_TYPE");
    try reject(std.testing.allocator, "def main() -> int:\n    return \"abc\".rfind(\"a\", 0, 3, 4)\n", "E_ARITY");
}

// spec-case: PY-TEXT-TRIM-1
test "Python text surface: trim charset family and source arity are checked" {
    try reject(std.testing.allocator, "def main() -> int:\n    return len(\"abc\".strip(b\"a\"))\n", "E_TYPE");
    try reject(std.testing.allocator, "def main() -> int:\n    return len(b\"abc\".strip(b\"a\", b\"b\"))\n", "E_ARITY");
}

// spec-case: PRELUDE-REPR-1
test "Python text surface: repr rejects unsupported collections and invalid arity" {
    try reject(std.testing.allocator, "def main() -> int:\n    return len(repr([1, 2]))\n", "E_REPR_TYPE");
    try reject(std.testing.allocator, "def main() -> int:\n    return len(repr())\n", "E_ARITY");
}
