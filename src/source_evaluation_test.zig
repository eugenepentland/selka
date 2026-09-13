//! Compile-time source functions are scalar, authority-free and bounded.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text =
        \\const ANSWER: i64 = calculate(10) + factorial(5)
        \\
        \\
        \\const BASE: i64 = 7
        \\
        \\
        \\def factorial(n: i64) -> i64:
        \\    if n <= 1:
        \\        return 1
        \\    return n * factorial(n - 1)
        \\
        \\
        \\def calculate(limit: i64) -> i64:
        \\    total = 0
        \\    for i in range(0, limit):
        \\        if i == 2:
        \\            continue
        \\        if i == 7:
        \\            break
        \\        total += i
        \\    left = 3
        \\    while left > 0:
        \\        left -= 1
        \\        total += BASE
        \\    return total
        \\
        \\
        \\def main() -> i64:
        \\    if ANSWER != calculate(10) + factorial(5):
        \\        return 1
        \\    return ANSWER
    ;
    var c = try language.Compilation.init(allocator, "evaluation.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 160), (try c.execute(allocator)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 160), (try again.execute(allocator)).value);
}
// spec: SOURCE-EVAL-1
test "source constant evaluation executes scalar functions recursion loops and exits with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn provider(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
        \\module main
        \\import calculation
        \\
        \\
        \\const ANSWER: i64 = calculation.value(2)
        \\
        \\
        \\def main() -> i64:
        \\    return ANSWER
    );
    if (std.mem.eql(u8, path, "calculation.my")) return allocator.dupe(u8, if (context == null)
        \\module calculation
        \\export value
        \\
        \\
        \\const INPUT: i64 = 20
        \\
        \\
        \\def value(n: i64) -> i64:
        \\    return INPUT + n
    else
        \\module calculation
        \\export value
        \\
        \\
        \\const INPUT: i64 = 40
        \\
        \\
        \\def value(n: i64) -> i64:
        \\    return INPUT + n
    );
    return error.NotFound;
}
test "changed source input modules recompute generated constants without a stale result cache" {
    var token: u8 = 0;
    var first: language.embedded_project.Program = undefined;
    try first.init(t.allocator, .{ .context = null, .read = provider });
    defer first.deinit();
    var second: language.embedded_project.Program = undefined;
    try second.init(t.allocator, .{ .context = &token, .read = provider });
    defer second.deinit();
    try t.expectEqual(@as(i64, 22), (try language.vm.run(t.allocator, first.compilation.code.?)).value);
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, second.compilation.code.?)).value);
}

test "compile-time loops are folded before guest execution budgets are consumed" {
    var c = try language.Compilation.init(t.allocator, "folded.my",
        \\const ANSWER: i64 = count()
        \\
        \\
        \\def count() -> i64:
        \\    n = 0
        \\    while n < 1000:
        \\        n += 1
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return ANSWER
    );
    defer c.deinit();
    try c.emit();
    const result = try language.vm.runWithOptions(t.allocator, c.code.?, .{ .max_steps = 10 });
    try t.expectEqual(@as(i64, 1000), result.value);
}
test "compile-time source call frames cannot capture caller locals" {
    const text =
        \\const ANSWER: i64 = outer()
        \\
        \\
        \\def inner() -> i64:
        \\    return hidden
        \\
        \\
        \\def outer() -> i64:
        \\    hidden = 99
        \\    return inner()
        \\
        \\
        \\def main() -> i64:
        \\    return ANSWER
    ;
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_CONSTANT_NAME", c.diagnostics.items[0].code);
}
