//! Familiar collection syntax preserves managed aliasing and value record semantics.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "familiar-collections.my", bytes);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}

// spec: FAMILIAR-COLLECTIONS-4
test "list syntax rejects invalid methods element types and indices" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.push()
        \\    return 0
        , .code = "E_ARITY" },
        .{ .text =
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.push(True)
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
        \\    values.clear()
        \\    return 0
        , .code = "E_LIST_METHOD" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid-list.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "list-oom.my",
        \\def make_values() -> Result[List[i64], i64]:
        \\    values: List[i64] = []
        \\    values.push(42)
        \\    return Ok(values)
        \\
        \\
        \\def main() -> i64:
        \\    match make_values():
        \\        case Result.ok(xs):
        \\            return xs[0]
        \\        case Result.err(e):
        \\            return e
    );
    defer compilation.deinit();
    const result = try compilation.executeWithOptions(allocator, .{ .memory = .{ .gc = .{ .stress = true } } });
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: FAMILIAR-COLLECTIONS-5
test "contextual managed source compilation and execution clean every failed allocation" {
    try allocationScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}

// spec: FAMILIAR-COLLECTIONS-2
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

// spec: FAMILIAR-COLLECTIONS-1
test "list methods indexing and indexed assignment share aliases" {
    try evaluate(
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    alias = values
        \\    alias.push(10)
        \\    values[0] = 41
        \\    return alias[0] + cast<i64>(values.len())
    , 42);
}

// spec: FAMILIAR-COLLECTIONS-3
test "generic list methods retain element type checking" {
    try evaluate(
        \\def add[T](values: List[T], value: T):
        \\    values.push(value)
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
