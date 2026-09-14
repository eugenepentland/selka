//! Explicit resource budgets for the standalone byte application runner.
const std = @import("std");
/// Native build tools; an explicit path always wins over the environment.
pub const Tools = struct {
    qbe: []const u8 = "qbe",
    zig: []const u8 = "zig",
    cache: ?[]const u8 = null,
};
/// Project path and bounded input, unpublished output, and execution budgets.
pub const Options = struct {
    project: []const u8,
    timings_json: bool = false,
    grants: @import("grants.zig").Config = .{},
    tools: Tools = .{},
    input: usize = 2 * 1024 * 1024,
    output: usize = 128 * 1024 * 1024,
    execution: struct { steps: u64 = 2_000_000_000, calls: u64 = 300_000_000, work: u64 = 300_000_000 } = .{},
};
/// Named build tools follow the environment only when no flag supplied a path.
pub fn inherit(options: *Options, environ: *const std.process.Environ.Map) void {
    if (std.mem.eql(u8, options.tools.qbe, "qbe")) options.tools.qbe = environ.get("MYLANG_QBE") orelse options.tools.qbe;
    if (std.mem.eql(u8, options.tools.zig, "zig")) options.tools.zig = environ.get("MYLANG_ZIG") orelse options.tools.zig;
}
/// Parse unique decimal limits; reject unknown flags, zero execution budgets and overflow.
pub fn parse(args: []const []const u8) error{InvalidArguments}!Options {
    if (args.len < 3 or !std.mem.eql(u8, args[1], "--project")) return error.InvalidArguments;
    var options: Options = .{ .project = args[2] };
    var seen: u8 = 0;
    for (args[3..]) |argument| {
        if (std.mem.eql(u8, argument, "--timings=json")) {
            if (options.timings_json) return error.InvalidArguments;
            options.timings_json = true;
            continue;
        }
        if (try options.grants.parse(argument)) continue;
        if (try tool(&options.tools, argument, &seen)) continue;
        const split = std.mem.indexOfScalar(u8, argument, '=') orelse return error.InvalidArguments;
        try budget(&options, argument[0..split], argument[split + 1 ..], &seen);
    }
    if (options.grants.writable and options.grants.directory == null) return error.InvalidArguments;
    return options;
}
/// Consume one unique native build tool control.
fn tool(tools: *Tools, argument: []const u8, seen: *u8) error{InvalidArguments}!bool {
    const names = [_][]const u8{ "--qbe=", "--zig=", "--cache-dir=" };
    for (names, 0..) |name, index| {
        if (!std.mem.startsWith(u8, argument, name)) continue;
        const value = argument[name.len..];
        const bit = @as(u8, 0x20) << @as(u3, @intCast(index));
        if (value.len == 0 or seen.* & bit != 0) return error.InvalidArguments;
        seen.* |= bit;
        switch (index) {
            0 => tools.qbe = value,
            1 => tools.zig = value,
            else => tools.cache = value,
        }
        return true;
    }
    return false;
}
/// Consume one unique decimal budget; input and output limits may be zero.
fn budget(options: *Options, key: []const u8, digits: []const u8, seen: *u8) error{InvalidArguments}!void {
    if (digits.len == 0) return error.InvalidArguments;
    for (digits) |digit| if (digit < '0' or digit > '9') return error.InvalidArguments;
    const value = std.fmt.parseInt(u64, digits, 10) catch return error.InvalidArguments;
    const names = [_][]const u8{ "--max-input", "--max-output", "--max-steps", "--max-calls", "--max-work" };
    for (names, 0..) |name, index| {
        if (!std.mem.eql(u8, key, name)) continue;
        const bit = @as(u8, 1) << @as(u3, @intCast(index));
        if (seen.* & bit != 0) return error.InvalidArguments;
        seen.* |= bit;
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
            else => options.execution.work = value,
        }
        return;
    }
    return error.InvalidArguments;
}
