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
const check_command = @import("check_command.zig");

const usage =
    \\usage: mylang-core build FILE.my -o OUT [--release] [--link FILE.c]... [--emit-llvm PATH] [--no-facts | --verify-facts] [--stats] [--zig PATH] [--cache-dir DIR] [--verify-cache] [--cache-report]
    \\       mylang-core check FILE.my [--typed] [--stats] [--timings=json] [--cache-dir DIR] [--no-cache]
    \\       mylang-core test FILE.my|DIR [--release] [--json] [--filter S] [--jobs N] [--force] [--cases PATH] [--max-steps N] [--max-frames N] [--max-memory SIZE] [--timeout-ms N]
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
    if (args.len >= 2 and std.mem.eql(u8, args[1], "check")) return check_command.run(init, args[2..]);
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
    var module = build.buildModuleSource(allocator, checked.program, checked.src, &refusal) catch |err| switch (err) {
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
            // List facts (settled, length, elements, len), for the lists that carry any.
            for (known.aggregates.lists, 0..) |list, index| {
                if (!list.settled and list.len == null and list.elements == null) continue;
                try ranges.print(allocator, "list {s} %{d}: settled={} length=%{d}", .{ function.name, index, list.settled, if (list.length == .none) -1 else @as(i64, @intCast(list.length.index())) });
                if (list.elements) |e| try ranges.print(allocator, " elements=[{d},{d}]", .{ e.lo, e.hi });
                if (list.len) |e| try ranges.print(allocator, " len=[{d},{d}]", .{ e.lo, e.hi });
                try ranges.appendSlice(allocator, "\n");
            }
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
        } else if (std.mem.eql(u8, arg, "--project")) {
            // Project configuration and graph checks are always applied.
        } else if (std.mem.eql(u8, arg, "--mode") and has_value) {
            index += 1;
            if (std.mem.eql(u8, args[index], "ReleaseFast")) options.release = true else if (std.mem.eql(u8, args[index], "Debug")) options.release = false else return 2;
        } else if (std.mem.eql(u8, arg, "--no-facts")) {
            options.facts = .off;
        } else if (std.mem.eql(u8, arg, "--generic-vectors")) {
            options.show.generic_vectors = true;
        } else if (trapFrames(arg)) |frames| {
            options.show.trap_frames = frames;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            options.show.stats = true;
        } else if (std.mem.eql(u8, arg, "--verify-cache")) {
            options.show.verify_cache = true;
        } else if (std.mem.eql(u8, arg, "--cache-report")) {
            options.show.cache_report = true;
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
    var links: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (testControls(&options, args, &index) catch return 2) continue;
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
        } else if (std.mem.eql(u8, arg, "--link") and has_value) {
            index += 1;
            try links.append(init.arena.allocator(), args[index]);
        } else if (std.mem.eql(u8, arg, "--seed") and has_value) {
            index += 1;
            options.seed = std.fmt.parseInt(u64, args[index], 10) catch return 2;
        } else if (std.mem.eql(u8, arg, "--property-runs") and has_value) {
            index += 1;
            options.property_runs = std.fmt.parseInt(u32, args[index], 10) catch return 2;
            if (options.property_runs == 0 or options.property_runs > 1000000) return 2;
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
    options.build.links = links.items;
    return test_runner.run(init, options);
}

fn testControls(options: *test_runner.Options, args: []const []const u8, index: *usize) error{Usage}!bool {
    const arg = args[index.*];
    const has_value = index.* + 1 < args.len;
    if (std.mem.eql(u8, arg, "--mode") and has_value) {
        index.* += 1;
        if (std.mem.eql(u8, args[index.*], "ReleaseFast")) options.build.release = true else if (std.mem.eql(u8, args[index.*], "Debug")) options.build.release = false else return error.Usage;
    } else if (std.mem.eql(u8, arg, "--force")) {
        options.controls.force = true;
    } else if (std.mem.eql(u8, arg, "--cases") and has_value) {
        index.* += 1;
        options.controls.cases = args[index.*];
    } else if (std.mem.eql(u8, arg, "--jobs") and has_value) {
        index.* += 1;
        options.controls.jobs = std.fmt.parseInt(usize, args[index.*], 10) catch return error.Usage;
        if (options.controls.jobs.? == 0) return error.Usage;
    } else if (std.mem.startsWith(u8, arg, "--jobs=")) {
        options.controls.jobs = std.fmt.parseInt(usize, arg[7..], 10) catch return error.Usage;
        if (options.controls.jobs.? == 0) return error.Usage;
    } else if (std.mem.eql(u8, arg, "--timeout-ms") and has_value) {
        index.* += 1;
        options.controls.timeout_ms = std.fmt.parseInt(u32, args[index.*], 10) catch return error.Usage;
        if (options.controls.timeout_ms == 0) return error.Usage;
    } else if (std.mem.eql(u8, arg, "--max-steps") and has_value) {
        index.* += 1;
        options.controls.max_steps = std.fmt.parseInt(u64, args[index.*], 10) catch return error.Usage;
        options.controls.explicit_steps = true;
    } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
        options.controls.max_steps = std.fmt.parseInt(u64, arg[12..], 10) catch return error.Usage;
        options.controls.explicit_steps = true;
    } else if (flagValue(args, index, "--max-frames")) |text| {
        options.controls.ceilings.frames = std.fmt.parseInt(u32, text, 10) catch return error.Usage;
        if (options.controls.ceilings.frames == 0) return error.Usage;
        options.controls.ceilings.explicit_frames = true;
    } else if (flagValue(args, index, "--max-memory")) |text| {
        options.controls.ceilings.memory = @import("memory_budget").parse(text) catch return error.Usage;
        options.controls.ceilings.explicit_memory = true;
    } else return false;
    return true;
}

/// The value of `--NAME VALUE` or `--NAME=VALUE` at `index` (advancing past a separate
/// value), or null when the argument is another flag.
fn flagValue(args: []const []const u8, index: *usize, comptime name: []const u8) ?[]const u8 {
    const arg = args[index.*];
    if (std.mem.startsWith(u8, arg, name ++ "=")) return arg[name.len + 1 ..];
    if (!std.mem.eql(u8, arg, name) or index.* + 1 >= args.len) return null;
    index.* += 1;
    return args[index.*];
}

/// The coverage sweep: check each file and try to build each of its functions alone.
/// Prints `ok NAME\tproven=P exact=E` (the checks the fact pass proves and keeps in
/// reachable code of the function analysed alone; `stack=S`, the lists it would put on
/// the stack), `refused REASON\tNAME` or
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
        for (try build.coverageSource(allocator, checked.program, checked.src)) |outcome| {
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
            // Lists the release build would put on the stack (`promote.zig`).
            const stack = try @import("promote.zig").promote(allocator, &outcome.module.?, &function, &known, false, null);
            try out.print(keep, "ok {s}\tproven={d} exact={d} stack={d}\n", .{ outcome.name, known.proven, exact, stack.lists });
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return 0;
}

/// The mechanism `--trap-frames=NAME` names (a `target.Traps`), or null for any other argument.
fn trapFrames(arg: []const u8) ?@import("target.zig").Traps {
    const flag = "--trap-frames=";
    if (!std.mem.startsWith(u8, arg, flag)) return null;
    return std.meta.stringToEnum(@import("target.zig").Traps, arg[flag.len..]);
}
