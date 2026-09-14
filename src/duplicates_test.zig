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
    try groups(
        \\def a(x: i64, y: i64) -> i64:
        \\    first = x - y
        \\    return first * 2
        \\
        \\
        \\def b(left: i64, right: i64) -> i64:
        \\    second = left - right
        \\    return second * 2
        \\
        \\
        \\def main() -> i64:
        \\    return a(8, 3)
    , 1);
    try groups(
        \\def a(x: i64, y: i64) -> i64:
        \\    return x - y
        \\
        \\
        \\def b(x: i64, y: i64) -> i64:
        \\    return y - x
        \\
        \\
        \\def main() -> i64:
        \\    return a(8, 3)
    , 0);
    try groups(
        \\def a(x: i64) -> i64:
        \\    y = x
        \\    y += 1
        \\    return y
        \\
        \\
        \\def b(n: i64) -> i64:
        \\    result = n
        \\    result = result + 1
        \\    return result
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , 1);
}

test "direct recursion is normalized while mutually recursive callees retain identity" {
    try groups(
        \\def a(n: i64) -> i64:
        \\    if n == 0:
        \\        return 1
        \\    return n * a(n - 1)
        \\
        \\
        \\def b(x: i64) -> i64:
        \\    if x == 0:
        \\        return 1
        \\    return x * b(x - 1)
        \\
        \\
        \\def main() -> i64:
        \\    return a(5)
    , 1);
    try groups(
        \\def a(n: i64) -> i64:
        \\    return b(n)
        \\
        \\
        \\def b(n: i64) -> i64:
        \\    return a(n)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , 0);
}

test "discovery groups many matches once and emits deterministic locations" {
    var compilation = try language.Compilation.init(testing.allocator, "groups.my",
        \\def a(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\def b(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def c(y: i64) -> i64:
        \\    return y + 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
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
    try testing.expect(std.mem.indexOf(u8, first, "groups.my:5:5: b") != null);
    try testing.expect(std.mem.indexOf(u8, first, "population=intentional") != null);
    var filtered = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 100 });
    defer filtered.deinit();
    try testing.expectEqual(@as(usize, 0), filtered.groups.len);
    try testing.expectEqual(@as(usize, 0), filtered.functions_indexed);
    try testing.expectError(error.InvalidThreshold, language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 0 }));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "allocation.my",
        \\def a(n: i64) -> i64:
        \\    return n * 2 + 1
        \\
        \\
        \\def b(x: i64) -> i64:
        \\    return x * 2 + 1
        \\
        \\
        \\def main() -> i64:
        \\    return a(4)
    );
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
    try groups(
        \\def helper(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def a(x: i64) -> i64:
        \\    return helper(x) + 1
        \\
        \\
        \\def b(x: i64) -> i64:
        \\    return helper(x) + 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , 1);
    try groups(
        \\def b(x: i64) -> i64:
        \\    return helper(x) + 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        \\
        \\
        \\def helper(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def a(x: i64) -> i64:
        \\    return helper(x) + 1
    , 1);
}
