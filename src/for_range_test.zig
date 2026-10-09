//! Half-open integer iteration reuses scoped loop exits and evaluates bounds once.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const generic_text =
    \\func sum_range[T: integer](start: T, end: T) -> i64:
    \\    mut sum = 0
    \\    for i in range(start, end):
    \\        if i == T(2):
    \\            continue
    \\        for j in range(0, 3):
    \\            if j == 1:
    \\                break
    \\            sum += i64(i)
    \\    return sum
    \\
    \\
    \\func main() -> i64:
    \\    mut result = 0
    \\    for i in range(0, 4):
    \\        result += i
    \\    return result + sum_range[u8](0u8, 5u8)
;
const once_text =
    \\func bound(mut counter: int[], value: int) -> int:
    \\    counter.append(1)
    \\    return value
    \\
    \\func main() -> int:
    \\    mut counter: int[] = []
    \\    mut result: int = 0
    \\    for i in range(bound(mut counter, 0), bound(mut counter, 4)):
    \\        result += i
    \\    return result + len(counter)
    \\
;
fn run(allocator: std.mem.Allocator, path: []const u8, text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, path, text);
    defer compilation.deinit();
    try t.expectEqual(expected, (try native.run(&compilation)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, path, formatted);
    defer again.deinit();
    try t.expectEqual(expected, (try native.run(&again)).value);
}
fn scenario(allocator: std.mem.Allocator) !void {
    try run(allocator, "for.my", generic_text, 14);
    try run(allocator, "once.my", once_text, 8);
}
// spec: FOR-RANGE-1
test "half-open ranges evaluate bounds once and support generic nested exits" {
    try scenario(t.allocator);
}
