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
const facts = @import("facts.zig");
const test_runner = @import("test_runner.zig");

const usage =
    \\usage: mylang-core build FILE.my -o OUT [--release] [--link FILE.c]... [--emit-llvm PATH] [--no-facts | --verify-facts] [--stats] [--zig PATH] [--cache-dir DIR]
    \\       mylang-core coverage FILE.my...   (one line per function: ok with its checks, or the refusal reason)
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
    if (args.len >= 3 and std.mem.eql(u8, args[1], "coverage")) return coverageCommand(init, args[2..]);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "test")) return testCommand(init, args[2..]);
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
        } else if (std.mem.eql(u8, arg, "--generic-vectors")) {
            options.show.generic_vectors = true;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            options.show.stats = true;
        } else if (std.mem.eql(u8, arg, "--verify-facts")) {
            options.facts = .verify;
        } else if (std.mem.eql(u8, arg, "--sabotage-facts")) {
            options.facts = .sabotage;
        } else if (std.mem.eql(u8, arg, "--sabotage-facts=widening")) {
            options.facts = .sabotage_widening;
        } else if (std.mem.eql(u8, arg, "--sabotage-facts=length")) {
            options.facts = .sabotage_length;
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

/// `mylang-core test`: the per-test conformance runner (`test_runner.zig`).
fn testCommand(init: std.process.Init, args: []const []const u8) !u8 {
    var options: test_runner.Options = .{ .path = "", .build = .{ .zig = init.environ_map.get("ZIG") orelse "zig" } };
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const has_value = index + 1 < args.len;
        if (std.mem.eql(u8, arg, "--release")) {
            options.build.release = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--no-facts")) {
            options.build.facts = .off;
        } else if (std.mem.eql(u8, arg, "--verify-facts")) {
            options.build.facts = .verify;
        } else if (std.mem.eql(u8, arg, "--filter") and has_value) {
            index += 1;
            options.filter = args[index];
        } else if (std.mem.eql(u8, arg, "--zig") and has_value) {
            index += 1;
            options.build.zig = args[index];
        } else if (std.mem.eql(u8, arg, "--cache-dir") and has_value) {
            index += 1;
            options.build.cache = args[index];
        } else if (options.path.len == 0 and !std.mem.startsWith(u8, arg, "-")) {
            options.path = arg;
        } else {
            try std.Io.File.stderr().writeStreamingAll(init.io, usage);
            return 2;
        }
    }
    if (options.path.len == 0) {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    }
    return test_runner.run(init, options);
}

/// The coverage sweep: check each file and try to build each of its functions alone.
/// Prints `ok NAME\tproven=P exact=E` (the checks the fact pass proves and keeps in
/// reachable code of the function analysed alone), `refused REASON\tNAME` or
/// `frontend FILE` per line.
fn coverageCommand(init: std.process.Init, arguments: []const []const u8) !u8 {
    var out: std.ArrayList(u8) = .empty;
    for (arguments) |path| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        const entry = frontend.entryOf(path);
        var session = frontend.Session.init(init.gpa, init.io, entry.root);
        defer session.deinit();
        var report: std.ArrayList(u8) = .empty;
        const checked = session.checkFile(allocator, path, &report) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                const first = std.mem.sliceTo(report.items, '\n');
                try out.print(init.arena.allocator(), "frontend {s}\t{s}\n", .{ path, first });
                continue;
            },
        };
        for (try build.coverage(allocator, checked.program)) |outcome| {
            const keep = init.arena.allocator();
            if (outcome.refusal) |reason| {
                try out.print(keep, "refused {s}\t{s}\n", .{ reason, outcome.name });
                continue;
            }
            var function = outcome.function.?;
            const known = try facts.analyze(allocator, &function, .{});
            var exact: u32 = 0;
            for (function.blocks.items, known.reachable) |block, live| {
                if (!live) continue;
                for (block.insts.items) |ref| exact += @intFromBool(function.inst(ref).check == .exact);
            }
            try out.print(keep, "ok {s}\tproven={d} exact={d}\n", .{ outcome.name, known.proven, exact });
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return 0;
}
