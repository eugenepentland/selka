//! `mylang-core`: the new compiler core's executable (decision N2). It imports
//! the existing front end as the `mylang` Zig module and owns everything below
//! `typed.Program`: the Core IR, its facts, LLVM emission and the native build.
const std = @import("std");
const frontend = @import("frontend.zig");
const typed_dump = @import("typed_dump.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const pipeline = @import("pipeline.zig");
const passes = @import("passes.zig");

const usage =
    \\usage: mylang-core build FILE.my -o OUT [--release] [--link FILE.c]... [--emit-llvm PATH] [--no-facts | --verify-facts] [--stats] [--zig PATH] [--cache-dir DIR]
    \\       mylang-core dump-typed FILE.my [FUNCTION]
    \\       mylang-core dump-ir FILE.my [--facts]   (--facts: after the release passes, with intervals)
    \\
;

/// Dispatch one command; the process exit status is its result.
pub fn main(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "dump-typed")) return dumpTyped(init, args[2], if (args.len >= 4) args[3] else null);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "dump-ir")) return dumpIr(init, args[2], args.len == 4 and std.mem.eql(u8, args[3], "--facts"));
    if (args.len >= 2 and std.mem.eql(u8, args[1], "build")) return buildCommand(init, args[2..]);
    try std.Io.File.stderr().writeStreamingAll(init.io, usage);
    return 2;
}

fn dumpTyped(init: std.process.Init, path: []const u8, filter: ?[]const u8) !u8 {
    const allocator = init.arena.allocator();
    const entry = frontend.entryOf(path);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    var report: std.ArrayList(u8) = .empty;
    const checked = session.checkFile(allocator, path, &report) catch |err| switch (err) {
        error.SourceError, error.ReadFailed => {
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            return 1;
        },
        else => return err,
    };
    const text = try typed_dump.render(allocator, checked.program, filter);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return 0;
}

fn dumpIr(init: std.process.Init, path: []const u8, with_facts: bool) !u8 {
    const allocator = init.arena.allocator();
    const entry = frontend.entryOf(path);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    var report: std.ArrayList(u8) = .empty;
    const checked = session.checkFile(allocator, path, &report) catch |err| switch (err) {
        error.SourceError, error.ReadFailed => {
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            return 1;
        },
        else => return err,
    };
    var refusal: build.Refusal = .{};
    var module = build.buildModule(allocator, checked.program, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            const at = frontend.position(checked.src, .{ .start = refusal.span, .end = refusal.span });
            const text = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: the new core does not support {s} yet\n", .{ at.path, at.line, at.column, refusal.reason });
            try std.Io.File.stderr().writeStreamingAll(init.io, text);
            return 1;
        },
        else => return err,
    };
    var ranges: std.ArrayList(u8) = .empty;
    if (with_facts) {
        const result = try passes.run(allocator, &module, .trusted);
        for (module.functions.items, result.known) |function, maybe| {
            const known = maybe orelse continue;
            try ranges.print(allocator, "facts {s}:", .{function.name});
            for (known.ranges, known.floats, 0..) |range, float, index| {
                if (range) |r| try ranges.print(allocator, " %{d}=[{d},{d}]", .{ index, r.lo, r.hi });
                if (float) |r| try ranges.print(allocator, " %{d}=[{e},{e}]", .{ index, r.lo, r.hi });
            }
            try ranges.appendSlice(allocator, "\n");
        }
    }
    const text = try print.module(allocator, &module);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, ranges.items);
    return 0;
}

fn buildCommand(init: std.process.Init, args: []const []const u8) !u8 {
    const allocator = init.arena.allocator();
    var options: pipeline.Options = .{ .zig = init.environ_map.get("ZIG") orelse "zig" };
    var links: std.ArrayList([]const u8) = .empty;
    var path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const has_value = index + 1 < args.len;
        if (std.mem.eql(u8, arg, "--release")) {
            options.release = true;
        } else if (std.mem.eql(u8, arg, "--no-facts")) {
            options.facts = .off;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            options.show.stats = true;
        } else if (std.mem.eql(u8, arg, "--verify-facts")) {
            options.facts = .verify;
        } else if (std.mem.eql(u8, arg, "--sabotage-facts")) {
            options.facts = .sabotage;
        } else if (std.mem.eql(u8, arg, "-o") and has_value) {
            index += 1;
            options.output = args[index];
        } else if (std.mem.eql(u8, arg, "--link") and has_value) {
            index += 1;
            try links.append(allocator, args[index]);
        } else if (std.mem.eql(u8, arg, "--emit-llvm") and has_value) {
            index += 1;
            options.show.llvm = args[index];
        } else if (std.mem.eql(u8, arg, "--zig") and has_value) {
            index += 1;
            options.zig = args[index];
        } else if (std.mem.eql(u8, arg, "--cache-dir") and has_value) {
            index += 1;
            options.cache = args[index];
        } else if (path == null and !std.mem.startsWith(u8, arg, "-")) {
            path = arg;
        } else {
            try std.Io.File.stderr().writeStreamingAll(init.io, usage);
            return 2;
        }
    }
    options.links = links.items;
    const source = path orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    };
    if (options.output.len == 0) {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    }
    var report: std.ArrayList(u8) = .empty;
    const status = pipeline.build(init, source, options, &report) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => 1,
    };
    if (report.items.len != 0) try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
    return status;
}
