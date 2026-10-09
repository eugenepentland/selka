//! Structured loop exits retain ownership obligations and release exited scopes.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn execute(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "loops.selka", text);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, result.value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(expected, (try native.run(&again)).value);
}
// spec: LOOP-EXIT-1
test "break and continue target nearest loops and preserve generic flow and formatting" {
    for ([_]bool{ false, true }) |generic| {
        const source = try std.mem.concat(t.allocator, u8, &.{
            if (generic) "func work[T]() -> i64:\n" else "func work() -> i64:\n",
            \\    mut sum = 0
            \\    mut i = 0
            \\    while i < 5:
            \\        i += 1
            \\        if i == 2:
            \\            continue
            \\        mut j = 0
            \\        while j < 10:
            \\            j += 1
            \\            if j == 3:
            \\                break
            \\            sum += i
            \\        if i == 4:
            \\            break
            \\    return sum
            \\
            \\
            \\
            ,
            if (generic)
                \\func main() -> i64:
                \\    return work[bool]()
            else
                \\func main() -> i64:
                \\    return work()
            ,
        });
        defer t.allocator.free(source);
        try execute(source, 16);
    }
}
