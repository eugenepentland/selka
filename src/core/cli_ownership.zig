//! Retired ownership selectors are refused at the process boundary.
const std = @import("std");

/// Allocation and stream failures while preparing one command line.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error;

/// Refuse removed selectors before command parsing, preserving guest arguments.
pub fn normalize(a: std.mem.Allocator, args: []const []const u8, report: *std.ArrayList(u8)) error{ OutOfMemory, OwnershipSelectorRetired }![]const []const u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    const prefix = @min(args.len, 2);
    try kept.appendSlice(a, args[0..prefix]);
    var guest = false;
    for (args[prefix..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) guest = true;
        if (!guest and isSelector(arg)) {
            try report.print(a, "selka: {s} was removed; reference counting was removed; checked ownership is the only memory model; drop the flag\n", .{arg});
            return error.OwnershipSelectorRetired;
        } else try kept.append(a, arg);
    }
    return kept.items;
}

/// Prepare process arguments, returning null after a retired-selector diagnostic.
pub fn prepare(init: std.process.Init, args: []const []const u8) Error!?[]const []const u8 {
    var report: std.ArrayList(u8) = .empty;
    const prepared = normalize(init.arena.allocator(), args, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.OwnershipSelectorRetired => {
            try writeReport(init, args, report.items);
            return null;
        },
    };
    if (report.items.len != 0) try writeReport(init, args, report.items);
    return prepared;
}

fn isSelector(arg: []const u8) bool {
    const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
    return std.mem.eql(u8, name, "--experimental-single-owner") or std.mem.eql(u8, name, "--experimental-zero-rc");
}

fn writeReport(init: std.process.Init, args: []const []const u8, report: []const u8) Error!void {
    var json = false;
    for (args[@min(args.len, 2)..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) break;
        if (std.mem.eql(u8, arg, "--diagnostics=json")) json = true;
        if (std.mem.eql(u8, arg, "--diagnostics=text")) json = false;
    }
    const rendered = if (json)
        try std.json.Stringify.valueAlloc(init.arena.allocator(), .{ .version = "diagnostic-v1", .kind = "message", .message = report }, .{})
    else
        report;
    try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
    if (json) try std.Io.File.stderr().writeStreamingAll(init.io, "\n");
}
