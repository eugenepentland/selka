//! collection syntax preserves managed aliasing and value record semantics.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "familiar-collections.my", bytes);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}

// spec: SURFACE-COLLECTIONS-4
test "list syntax rejects invalid methods element types and indices" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.append()
        \\    return 0
        , .code = "E_ARITY" },
        .{ .text =
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.append(True)
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values[False] = 1
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.remove(True)
        \\    return 0
        , .code = "E_TYPE" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid-list.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

// spec: SURFACE-COLLECTIONS-2
test "record constructors without new support generic records and trailing fields" {
    try evaluate(
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\class Empty:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    box = Box[i64](value=42)
        \\    _ = Empty()
        \\    if box.value == 0:
        \\        pass
        \\    return box.value
    , 42);
}

// spec: SURFACE-COLLECTIONS-1
test "list methods indexing and indexed assignment share aliases" {
    try evaluate(
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    alias = values
        \\    alias.append(10)
        \\    values[0] = 41
        \\    return alias[0] + i64(values.len())
    , 42);
}

// spec: SURFACE-COLLECTIONS-3
test "generic list methods retain element type checking" {
    try evaluate(
        \\def add[T](values: List[T], value: T):
        \\    values.append(value)
        \\
        \\
        \\def first[T](values: List[T]) -> T:
        \\    return values[0]
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    add(values, 42)
        \\    return first(values)
    , 42);
}
