//! Command-line controls for native application tests.
const std = @import("std");
const execute = @import("native_test_execute.zig");
/// Invalid native test command arguments.
pub const Error = error{InvalidTestArguments};
/// Discovery, execution and cache policy.
pub const Options = struct {
    link_arguments: []const []const u8 = &.{},
    source: []const u8 = "",
    filter: []const u8 = "*",
    cases: ?[]const u8 = null,
    cache: []const u8 = ".mylang-cache/tests",
    qbe: []const u8 = "qbe",
    zig: []const u8 = "zig",
    mode: []const u8 = "Debug",
    force: bool = false,
    json: bool = false,
    limits: execute.Limits = .{},
};
/// Native tests require no Python interpreter.
pub const usage = "usage: mylang test <entry.my> [--filter GLOB] [--cases FILE]\n" ++
    "  --link FILE --link-library NAME --library-path DIR (repeatable)\n" ++
    "  --cache-dir DIR --force --json --qbe PATH --zig PATH --mode Debug|ReleaseFast\n" ++
    "  --max-steps N --max-frames N --max-calls N --timeout-ms N\n";
/// Parse options, rejecting malformed budgets and unknown flags.
pub fn parse(args: []const []const u8) Error!Options {
    var result: Options = .{ .link_arguments = args };
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!std.mem.startsWith(u8, arg, "-")) {
            if (result.source.len != 0) return error.InvalidTestArguments;
            result.source = arg;
            continue;
        }
        if (std.mem.eql(u8, arg, "--force")) {
            result.force = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            result.json = true;
            continue;
        }
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
        const flag = std.meta.stringToEnum(Flag, arg[0..split]) orelse return error.InvalidTestArguments;
        const value = if (split < arg.len) arg[split + 1 ..] else value: {
            i += 1;
            if (i == args.len) return error.InvalidTestArguments;
            break :value args[i];
        };
        if (value.len == 0) return error.InvalidTestArguments;
        if (@import("native_link.zig").isFlag(@tagName(flag)) and !@import("native_link.zig").valid(@tagName(flag), value)) return error.InvalidTestArguments;
        try assign(&result, flag, value);
    }
    if (result.source.len == 0) return error.InvalidTestArguments;
    if (!std.mem.eql(u8, result.mode, "Debug") and !std.mem.eql(u8, result.mode, "ReleaseFast")) return error.InvalidTestArguments;
    return result;
}
const Flag = enum { @"--link", @"--link-library", @"--library-path", @"--filter", @"--cases", @"--cache-dir", @"--qbe", @"--zig", @"--mode", @"--max-steps", @"--max-frames", @"--max-calls", @"--timeout-ms" };
fn assign(result: *Options, flag: Flag, value: []const u8) Error!void {
    switch (flag) {
        .@"--link", .@"--link-library", .@"--library-path" => {},
        .@"--filter" => result.filter = value,
        .@"--cases" => result.cases = value,
        .@"--cache-dir" => result.cache = value,
        .@"--qbe" => result.qbe = value,
        .@"--zig" => result.zig = value,
        .@"--mode" => result.mode = value,
        .@"--max-steps" => result.limits.max_steps = try number(value),
        .@"--max-frames" => result.limits.max_frames = try number(value),
        .@"--max-calls" => result.limits.max_calls = try number(value),
        .@"--timeout-ms" => result.limits.timeout_ms = @intCast(try number(value)),
    }
}
fn number(value: []const u8) Error!u64 {
    const n = std.fmt.parseInt(u64, value, 10) catch return error.InvalidTestArguments;
    if (n == 0 or n > std.math.maxInt(u32)) return error.InvalidTestArguments;
    return n;
}
test "native test options validate budgets and discovery controls" {
    const opts = try parse(&.{ "main.my", "--filter=*ok", "--force", "--json", "--max-steps", "100" });
    try std.testing.expect(opts.force and opts.json);
    try std.testing.expectEqual(@as(u64, 100), opts.limits.max_steps);
    for ([_][]const []const u8{ &.{}, &.{ "x", "--wat" }, &.{ "x", "--max-steps=0" }, &.{ "x", "--mode=Fast" }, &.{ "x", "--cases" } }) |args| {
        try std.testing.expectError(error.InvalidTestArguments, parse(args));
    }
}
