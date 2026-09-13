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
        .{ .text = "fn main()->i64{let values:List<i64>=[];values.push();return 0;}", .code = "E_ARITY" },
        .{ .text = "fn main()->i64{let values:List<i64>=[];values.push(true);return 0;}", .code = "E_TYPE" },
        .{ .text = "fn main()->i64{let values:List<i64>=[];values[false]=1;return 0;}", .code = "E_TYPE" },
        .{ .text = "fn main()->i64{let values:List<i64>=[];values.clear();return 0;}", .code = "E_LIST_METHOD" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid-list.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "list-oom.my", "fn make_values()->Result<List<i64>,i64>{let values:List<i64>=[];values.push(42);return Ok(values);}" ++
        "fn main()->i64{match make_values(){Result<List<i64>,i64>.ok(xs)=>{return xs[0];},Result<List<i64>,i64>.err(e)=>{return e;}}}");
    defer compilation.deinit();
    const result = try compilation.executeWithOptions(allocator, .{ .memory = .{ .gc = .{ .stress = true } } });
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: FAMILIAR-COLLECTIONS-5
test "contextual managed source compilation and execution clean every failed allocation" {
    try allocationScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}
