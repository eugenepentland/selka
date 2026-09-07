//! Explicit resource budgets for the standalone byte application runner.
const std = @import("std");
/// Project path and bounded input, unpublished output, and execution budgets.
pub const Options = struct {
    project: []const u8,
    grants: @import("grants.zig").Config = .{},
    input: usize = 2 * 1024 * 1024,
    output: usize = 128 * 1024 * 1024,
    execution: struct { steps: u64 = 2_000_000_000, calls: u64 = 300_000_000, work: u64 = 300_000_000 } = .{},
    memory: @import("memory_budget.zig").Config = .{},
};
/// Parse unique decimal limits; reject unknown flags, zero VM budgets and overflow.
pub fn parse(args: []const []const u8) error{InvalidArguments}!Options {
    if (args.len < 3 or !std.mem.eql(u8, args[1], "--project")) return error.InvalidArguments;
    var options: Options = .{ .project = args[2] };
    var seen: u8 = 0;
    for (args[3..]) |argument| {
        if (try options.grants.parse(argument)) continue;
        if (try options.memory.parse(argument)) continue;
        const split = std.mem.indexOfScalar(u8, argument, '=') orelse return error.InvalidArguments;
        const key = argument[0..split];
        const digits = argument[split + 1 ..];
        if (digits.len == 0) return error.InvalidArguments;
        for (digits) |digit| if (digit < '0' or digit > '9') return error.InvalidArguments;
        const value = std.fmt.parseInt(u64, digits, 10) catch return error.InvalidArguments;
        const names = [_][]const u8{ "--max-input", "--max-output", "--max-steps", "--max-calls", "--max-work" };
        var matched = false;
        for (names, 0..) |name, index| {
            if (!std.mem.eql(u8, key, name)) continue;
            const bit = @as(u8, 1) << @as(u3, @intCast(index));
            if (seen & bit != 0) return error.InvalidArguments;
            seen |= bit;
            if (index >= 2 and value == 0) return error.InvalidArguments;
            switch (index) {
                0 => {
                    if (value >= std.math.maxInt(usize) or value > std.math.maxInt(i64)) return error.InvalidArguments;
                    options.input = @intCast(value);
                },
                1 => {
                    if (value > std.math.maxInt(usize)) return error.InvalidArguments;
                    options.output = @intCast(value);
                },
                2 => options.execution.steps = value,
                3 => options.execution.calls = value,
                4 => options.execution.work = value,
                else => unreachable,
            }
            matched = true;
        }
        if (!matched) return error.InvalidArguments;
    }
    if (options.grants.writable and options.grants.directory == null) return error.InvalidArguments;
    return options;
}
