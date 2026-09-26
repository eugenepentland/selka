//! Install a normalized compiler mode in the actual inherited environment.
//! Replacing the process also covers children spawned without an explicit map.
const std = @import("std");

/// Allocation and diagnostic output failures while replacing this process.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error;

/// Restart with already filtered arguments and one resolved environment carrier.
pub fn replace(process: std.process.Init, args: []const [:0]const u8, variable: []const u8, value: []const u8) Error!u8 {
    const a = process.arena.allocator();
    try process.environ_map.put(variable, value);
    const self = std.Io.Dir.cwd().realPathFileAlloc(process.io, "/proc/self/exe", a) catch |err| return failed(process, variable, err);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(a, self);
    for (args[1..]) |arg| try argv.append(a, arg);
    const err = std.process.replace(process.io, .{ .argv = argv.items, .environ_map = process.environ_map });
    return failed(process, variable, err);
}

fn failed(process: std.process.Init, variable: []const u8, err: anyerror) Error!u8 {
    var buffer: [240]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "mylang: {s}: cannot restart the compiler ({s})\n", .{ variable, @errorName(err) }) catch "mylang: cannot restart the compiler\n";
    try std.Io.File.stderr().writeStreamingAll(process.io, message);
    return 2;
}
