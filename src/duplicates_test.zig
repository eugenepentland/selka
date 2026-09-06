const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");

fn groups(source: []const u8, expected: usize) !void {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try testing.expectEqual(expected, analysis.groups.len);
    try testing.expect(compilation.code == null);
}

// spec: TOOL-1
test "exact discovery normalizes binding spelling but retains binding identity" {
    try groups("fn a(x: i64, y: i64) -> i64 { let first = x - y; return first * 2; } fn b(left: i64, right: i64) -> i64 { let second = left - right; return second * 2; } fn main() -> i64 { return a(8, 3); }", 1);
    try groups("fn a(x: i64, y: i64) -> i64 { return x - y; } fn b(x: i64, y: i64) -> i64 { return y - x; } fn main() -> i64 { return a(8, 3); }", 0);
    try groups("fn a(x: i64) -> i64 { let mut y = x; y += 1; return y; } fn b(n: i64) -> i64 { let mut result = n; result = result + 1; return result; } fn main() -> i64 { return 0; }", 1);
}

test "literals operators control flow types and resolved external calls remain distinct" {
    const bodies = [_][]const u8{ "return x + 2;", "return x - 1;", "return 1 + x;", "discard x; return 1;", "if x > 0 { return x + 1; } return 0;" };
    for (bodies) |body| {
        const source = try std.fmt.allocPrint(testing.allocator, "fn a(x: i64) -> i64 {{ return x + 1; }} fn b(x: i64) -> i64 {{ {s} }} fn main() -> i64 {{ return 0; }}", .{body});
        defer testing.allocator.free(source);
        try groups(source, 0);
    }
    try groups("fn a(x: bool) -> bool { return x; } fn b(x: i64) -> i64 { return x; } fn main() -> i64 { return 0; }", 0);
    try groups("fn left(x: i64) -> i64 { return x + 1; } fn right(x: i64) -> i64 { return x + 2; } fn a(x: i64) -> i64 { return left(x); } fn b(x: i64) -> i64 { return right(x); } fn main() -> i64 { return 0; }", 0);
    try groups("fn a(x: bool, y: bool) -> bool { return x && y; } fn b(x: bool, y: bool) -> bool { return x || y; } fn main() -> i64 { return 0; }", 0);
}

test "direct recursion is normalized while mutually recursive callees retain identity" {
    try groups("fn a(n: i64) -> i64 { if n == 0 { return 1; } return n * a(n - 1); } fn b(x: i64) -> i64 { if x == 0 { return 1; } return x * b(x - 1); } fn main() -> i64 { return a(5); }", 1);
    try groups("fn a(n: i64) -> i64 { return b(n); } fn b(n: i64) -> i64 { return a(n); } fn main() -> i64 { return 0; }", 0);
}

test "discovery groups many matches once and emits deterministic locations" {
    var compilation = try language.Compilation.init(testing.allocator, "groups.my", "fn a(n: i64) -> i64 { return n + 1; }\nfn b(x: i64) -> i64 { return x + 1; }\nfn c(y: i64) -> i64 { return y + 1; }\nfn main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1, .population = .intentional });
    defer analysis.deinit();
    try testing.expectEqual(@as(usize, 1), analysis.groups.len);
    try testing.expectEqual(@as(usize, 3), analysis.groups[0].members.len);
    const first = try language.duplicates.render(testing.allocator, analysis, compilation.program.?, compilation.src);
    defer testing.allocator.free(first);
    const second = try language.duplicates.render(testing.allocator, analysis, compilation.program.?, compilation.src);
    defer testing.allocator.free(second);
    try testing.expectEqualStrings(first, second);
    try testing.expect(std.mem.indexOf(u8, first, "groups.my:2:4: b") != null);
    try testing.expect(std.mem.indexOf(u8, first, "population=intentional") != null);
    var filtered = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 100 });
    defer filtered.deinit();
    try testing.expectEqual(@as(usize, 0), filtered.groups.len);
    try testing.expectEqual(@as(usize, 0), filtered.functions_indexed);
    try testing.expectError(error.InvalidThreshold, language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 0 }));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "allocation.my", "fn a(n: i64) -> i64 { return n * 2 + 1; } fn b(x: i64) -> i64 { return x * 2 + 1; } fn main() -> i64 { return a(4); }");
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    const rendered = try language.duplicates.render(allocator, analysis, compilation.program.?, compilation.src);
    defer allocator.free(rendered);
}

test "discovery and rendering clean up after every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationScenario, .{});
}

test "declaration reordering cannot change resolved external call comparisons" {
    try groups("fn helper(x: i64) -> i64 { return x; } fn a(x: i64) -> i64 { return helper(x) + 1; } fn b(x: i64) -> i64 { return helper(x) + 1; } fn main() -> i64 { return 0; }", 1);
    try groups("fn b(x: i64) -> i64 { return helper(x) + 1; } fn main() -> i64 { return 0; } fn helper(x: i64) -> i64 { return x; } fn a(x: i64) -> i64 { return helper(x) + 1; }", 1);
}
