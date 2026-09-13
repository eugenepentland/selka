//! Trace bounds do not alter execution, and branch operands explain taken paths.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
// spec: VM-TRACE-1
test "bounded memory trace records branch values without affecting instruction budgets" {
    var c = try language.Compilation.init(t.allocator, "trace.my",
        \\def main() -> i64:
        \\    n = 3
        \\    if n < 4:
        \\        return 7
        \\    else:
        \\        return 9
    );
    defer c.deinit();
    var events: [64]language.vm_trace.Event = undefined;
    var trace: language.vm_trace.Trace = .{ .events = &events };
    const result = try c.executeWithOptions(t.allocator, .{ .memory = .{ .trace = &trace } });
    try t.expectEqual(@as(i64, 7), result.value);
    try t.expectEqual(@as(usize, 0), trace.omitted);
    var branches: usize = 0;
    for (events[0..trace.count]) |event| {
        if (std.mem.eql(u8, event.operation, "jump_if_false")) {
            try t.expect(event.top.boolean);
            branches += 1;
        }
    }
    try t.expectEqual(@as(usize, 1), branches);
    var tiny: language.vm_trace.Trace = .{ .events = events[0..1] };
    try t.expectEqual(@as(i64, 7), (try c.executeWithOptions(t.allocator, .{ .memory = .{ .trace = &tiny } })).value);
    try t.expectEqual(@as(usize, 1), tiny.count);
    try t.expect(tiny.omitted > 0);
}
