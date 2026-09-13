//! Half-open integer iteration reuses scoped loop exits and evaluates bounds once.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const generic_text =
    \\def sum_range[T: integer](start: T, end: T) -> i64:
    \\    sum = 0
    \\    for i in range(start, end):
    \\        if i == cast<T>(2):
    \\            continue
    \\        for j in range(0, 3):
    \\            if j == 1:
    \\                break
    \\            sum += cast<i64>(i)
    \\    return sum
    \\
    \\
    \\def main() -> i64:
    \\    result = 0
    \\    for i in range(0, 4):
    \\        result += i
    \\    return result + sum_range[u8](0u8, 5u8)
;
const once_text =
    \\def bound(counter: list[int], value: int) -> int:
    \\    counter.append(1)
    \\    return value
    \\
    \\def main() -> int:
    \\    counter: list[int] = []
    \\    result: int = 0
    \\    for i in range(bound(counter, 0), bound(counter, 4)):
    \\        result += i
    \\    return result + len(counter)
    \\
;
fn run(allocator: std.mem.Allocator, path: []const u8, text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, path, text);
    defer compilation.deinit();
    try t.expectEqual(expected, (try compilation.execute(allocator)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, path, formatted);
    defer again.deinit();
    try t.expectEqual(expected, (try again.execute(allocator)).value);
}
fn scenario(allocator: std.mem.Allocator) !void {
    try run(allocator, "for.my", generic_text, 14);
    try run(allocator, "once.my", once_text, 8);
}
// spec: FOR-RANGE-1
test "half-open ranges evaluate bounds once and support generic nested exits with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
