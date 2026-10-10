//! `mylang-core`: the new compiler core's executable (decision N2). It imports
//! the existing front end as the `mylang` Zig module and owns everything below
//! `typed.Program`: the Core IR, its facts, LLVM emission and the native build.
const std = @import("std");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const typed_dump = @import("typed_dump.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const pipeline = @import("pipeline.zig");
const passes = @import("passes.zig");
const facts = @import("facts.zig");
const ir = @import("ir.zig");
const test_runner = @import("test_runner.zig");
const check_command = @import("check_command.zig");
const cli_run = @import("cli_run.zig");

/// The flag naming the build cache directory.
const cache_dir_flag = "--cache-dir";

const usage =
    \\usage: mylang build FILE.my -o OUT [--release | --unoptimized | --optimize-debug] [--link FILE.c]... [--emit-llvm PATH] [--no-facts | --verify-facts] [--stats] [--zig PATH] [--cache-dir DIR] [--verify-cache] [--cache-report]
    \\Default: optimized debug; --optimize-debug is a compatibility alias; --unoptimized disables optimization.
    \\       mylang check FILE.my [--typed] [--stats] [--timings=json] [--cache-dir DIR] [--no-cache]
    \\       mylang test FILE.my|DIR [options]   (`mylang test` alone lists them)
    \\       mylang coverage FILE.my...   (one line per function: ok with its checks, or the refusal reason)
    \\       mylang dump-typed FILE.my [FUNCTION]
    \\       mylang dump-ir FILE.my [--facts]   (--facts: after the release passes, with intervals)
    \\
;

/// `mylang test`'s usage: every flag `testCommand` and the CLI accept.
const test_usage =
    \\usage: mylang test <entry.my|directory> [--filter SUBSTRING|GLOB] [--cases FILE] [--json]
    \\Default: optimized debug; --optimize-debug and --mode Debug select the same mode.
    \\  --release | --unoptimized | --optimize-debug           --mode Debug|ReleaseFast
    \\  --no-facts | --verify-facts
    \\  --affected --against REF                run only tests reaching a declaration changed since REF
    \\  --jobs N                                tests at once (default: CPUs, capped by free memory)
    \\  --max-steps N --max-frames N --max-memory SIZE --timeout-ms N   per-test budgets
    \\  --seed N --property-runs N              property test inputs (runs: 1 to 1000000)
    \\  --property-policy legacy|indexed-v1    property generation and range reuse policy
    \\  --force --no-cache --cache-dir DIR      rerun every test / use a private cache / cache location
    \\  --link FILE.c (repeatable) --zig PATH
    \\
;

/// What stops a command before it has a status: memory, an unwritable stream, or a
/// test the runner cannot encode.
pub const Error = test_runner.Error || std.Io.File.Writer.Error || frontend.Error || project_entry.Error || build.Error || error{ReadFailed};

/// Dispatch one command; the process exit status is its result.
pub fn main(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "build")) return buildCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "check")) return check_command.run(init, args[2..]);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "test")) return testCommand(init, args[2..]);
    // `mylang`'s run command (NEW-CORE-S5-RUN-1), which the core's own tests drive.
    for ([_][]const u8{ "run", "run-project" }) |name| if (args.len >= 2 and std.mem.eql(u8, args[1], name)) return cli_run.runCommand(init, name, args[2..]);
    return developer(init, args);
}

/// The developer commands `mylang` shares (S5-D8): `dump-typed`, `dump-ir` and
/// `coverage`, from `args` (argv, the program name first). Anything else prints the usage.
pub fn developer(init: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len >= 3 and std.mem.eql(u8, args[1], "dump-typed")) return dumpTyped(init, args[2], if (args.len >= 4) args[3] else null);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "dump-ir")) return dumpIr(init, args[2], args.len == 4 and std.mem.eql(u8, args[3], "--facts"));
    if (args.len >= 3 and std.mem.eql(u8, args[1], "coverage")) return coverageCommand(init, args[2..]);
    try std.Io.File.stderr().writeStreamingAll(init.io, usage);
    return 2;
}

fn developerFailure(init: std.process.Init, report: []const u8, err: (project_entry.Error || frontend.Error || error{ReadFailed})) Error!u8 {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    if (err == error.InternalError) return error.InternalError;
    try std.Io.File.stderr().writeStreamingAll(init.io, report);
    return switch (err) {
        error.ConfigurationFailed => 2,
        error.PolicyDenied => 3,
        else => 1,
    };
}

fn dumpTyped(init: std.process.Init, path: []const u8, filter: ?[]const u8) !u8 {
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| return developerFailure(init, report.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = entry.check(allocator, &session, &report) catch |err| return developerFailure(init, report.items, err);
    const text = try typed_dump.render(allocator, checked.program, filter);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return 0;
}

fn dumpIr(init: std.process.Init, path: []const u8, with_facts: bool) !u8 {
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| return developerFailure(init, report.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = entry.check(allocator, &session, &report) catch |err| return developerFailure(init, report.items, err);
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
    var result_known: []const ?facts.Facts = &.{};
    if (with_facts) {
        const result = try passes.runWithScratch(allocator, init.gpa, &module, .trusted);
        result_known = result.known;
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
    if (with_facts) {
        // Whole-program field intervals (NEW-CORE-F2-FIELD-1), from the final facts' writes.
        const table = try @import("fields.zig").hulls(allocator, &module, result_known, try @import("fields.zig").closedTypes(allocator, &module), false);
        for (table.types, 0..) |maybe, k| {
            const fields = maybe orelse continue;
            for (fields, 0..) |range, field| if (range) |r| {
                const full = facts.typeRange(module.compound(@fromBackingInt(@as(u32, @intCast(k + ir.Type.first_compound)))).record[field]) orelse continue;
                if (r.lo > full.lo or r.hi < full.hi) try ranges.print(allocator, "field type{d}.{d}: [{d}, {d}]\n", .{ k + ir.Type.first_compound, field, r.lo, r.hi });
            };
        }
    }
    const text = try print.module(allocator, &module);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, ranges.items);
    return 0;
}

/// The fact mode a `--sabotage-facts[=RULE]` flag selects: verify with one wrong rule.
fn sabotageFlag(arg: []const u8) ?@FieldType(pipeline.Options, "facts") {
    const flags = [_]struct { []const u8, @FieldType(pipeline.Options, "facts") }{
        .{ "--sabotage-facts", .sabotage },
        .{ "--sabotage-facts=widening", .sabotage_widening },
        .{ "--sabotage-facts=length", .sabotage_length },
        .{ "--sabotage-facts=overflow", .sabotage_overflow },
        .{ "--sabotage-facts=index", .sabotage_index },
        .{ "--sabotage-facts=field", .sabotage_field },
        .{ "--sabotage-facts=version", .sabotage_version },
    };
    for (flags) |flag| if (std.mem.eql(u8, arg, flag[0])) return flag[1];
    return null;
}

/// The developer build (`mylang build` given `--sabotage-facts`,
/// `--generic-vectors` or `--trap-frames=`, S5-D8): the core's own flag set,
/// every failure exit 1, the source path displayed relative to its directory.
pub fn buildCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const allocator = init.arena.allocator();
    var options: pipeline.Options = .{ .zig = init.environ_map.get("ZIG") orelse "zig" };
    var links: std.ArrayList([]const u8) = .empty;
    var explicit_mode = false;
    var path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const has_value = index + 1 < args.len;
        if (std.mem.eql(u8, arg, "--release")) {
            options.mode.select(&explicit_mode, .release) catch return 2;
        } else if (std.mem.eql(u8, arg, "--optimize-debug")) {
            options.mode.select(&explicit_mode, .optimized_debug) catch return 2;
        } else if (std.mem.eql(u8, arg, "--unoptimized")) {
            options.mode.select(&explicit_mode, .debug) catch return 2;
        } else if (std.mem.eql(u8, arg, "--project")) {
            // Project configuration and graph checks are always applied.
        } else if (std.mem.eql(u8, arg, "--mode") and has_value) {
            index += 1;
            if (std.mem.eql(u8, args[index], "ReleaseFast")) {
                options.mode.select(&explicit_mode, .release) catch return 2;
            } else if (std.mem.eql(u8, args[index], "Debug")) {
                options.mode.select(&explicit_mode, .optimized_debug) catch return 2;
            } else return 2;
        } else if (std.mem.eql(u8, arg, "--no-facts")) {
            options.facts = .off;
        } else if (std.mem.eql(u8, arg, "--generic-vectors")) {
            options.show.codegen.generic_vectors = true;
        } else if (trapFrames(arg)) |frames| {
            options.show.codegen.trap_frames = frames;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            options.show.stats = true;
        } else if (std.mem.eql(u8, arg, "--verify-cache")) {
            options.show.verify_cache = true;
        } else if (std.mem.eql(u8, arg, "--cache-report")) {
            options.show.cache_report = .text;
        } else if (std.mem.eql(u8, arg, "--verify-facts")) {
            options.facts = .verify;
        } else if (sabotageFlag(arg)) |mode| {
            options.facts = mode;
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
        } else if (std.mem.eql(u8, arg, cache_dir_flag) and has_value) {
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
        error.OutOfMemory => return error.OutOfMemory,
        else => 1,
    };
    if (report.items.len != 0) try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
    return status;
}

const mode_conflict = "--release, --unoptimized and --optimize-debug/--mode Debug are mutually exclusive";

/// `mylang-core test` and `mylang test`: the per-test conformance runner (`test_runner.zig`).
pub fn testCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    var options: test_runner.Options = .{ .path = "", .build = .{ .zig = init.environ_map.get("ZIG") orelse "zig" } };
    var links: std.ArrayList([]const u8) = .empty;
    var explicit_mode = false;
    var affected = false;
    var no_cache = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const start = index;
        if (testControls(&options, args, &index, &explicit_mode) catch return invalidValue(init, args, start, index)) continue;
        const arg = args[index];
        const has_value = index + 1 < args.len;
        if (std.mem.eql(u8, arg, "--affected")) {
            affected = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            no_cache = true;
        } else if (flagValue(args, &index, "--against")) |reference| {
            options.controls.against = reference;
        } else if (std.mem.eql(u8, arg, "--release")) {
            options.build.mode.select(&explicit_mode, .release) catch return testUsage(init, mode_conflict);
        } else if (std.mem.eql(u8, arg, "--optimize-debug")) {
            options.build.mode.select(&explicit_mode, .optimized_debug) catch return testUsage(init, mode_conflict);
        } else if (std.mem.eql(u8, arg, "--unoptimized")) {
            options.build.mode.select(&explicit_mode, .debug) catch return testUsage(init, mode_conflict);
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
            options.properties.seed = std.fmt.parseInt(u64, args[index], 10) catch return invalidValue(init, args, index - 1, index);
        } else if (std.mem.eql(u8, arg, "--property-policy") and has_value) {
            index += 1;
            options.properties.policy = @import("property_campaign_contract.zig").Policy.parse(args[index]) orelse return invalidValue(init, args, index - 1, index);
        } else if (std.mem.eql(u8, arg, "--property-runs") and has_value) {
            index += 1;
            options.properties.runs = propertyRuns(args[index]) orelse return invalidValue(init, args, index - 1, index);
        } else if (std.mem.eql(u8, arg, "--filter") and has_value) {
            index += 1;
            options.filter = args[index];
        } else if (std.mem.eql(u8, arg, "--zig") and has_value) {
            index += 1;
            options.build.zig = args[index];
        } else if (std.mem.eql(u8, arg, cache_dir_flag) and has_value) {
            index += 1;
            options.build.cache = args[index];
        } else if (options.path.len == 0 and !std.mem.startsWith(u8, arg, "-")) {
            options.path = arg;
        } else {
            const problem = if (std.mem.startsWith(u8, arg, "-")) (if (has_value or !takesValue(arg)) "unknown option" else "missing value for") else "unexpected argument";
            return testUsage(init, try std.fmt.allocPrint(init.arena.allocator(), "{s} '{s}'", .{ problem, arg }));
        }
    }
    if (options.path.len == 0) return testUsage(init, null);
    // NEW-CORE-S5-AFFECTED-1: the two switches only mean something together.
    if (affected != (options.controls.against != null)) return testUsage(init, "--affected and --against REF go together");
    options.build.links = links.items;
    // NEW-CORE-S5-NO-CACHE-1: run against a private cache, removed afterwards.
    if (no_cache) options.build.cache = try cli_run.privateCache(init, options.build.cache);
    defer if (no_cache) cli_run.discard(init.io, options.build.cache);
    return test_runner.run(init, options);
}

fn propertyRuns(text: []const u8) ?u32 {
    const runs = std.fmt.parseInt(u32, text, 10) catch return null;
    return if (runs == 0 or runs > 1000000) null else runs;
}

/// Print `mylang test: PROBLEM` (when there is one) and the test usage; status 2.
fn testUsage(init: std.process.Init, problem: ?[]const u8) Error!u8 {
    const text = if (problem) |line| try std.fmt.allocPrint(init.arena.allocator(), "mylang test: {s}\n" ++ test_usage, .{line}) else test_usage;
    try std.Io.File.stderr().writeStreamingAll(init.io, text);
    return 2;
}

/// The usage error for the flag at `args[start]` whose value (after `=`, or the
/// argument at `index`) is not one the flag accepts (NEW-CORE-S5-TEST-USAGE-1).
fn invalidValue(init: std.process.Init, args: []const []const u8, start: usize, index: usize) Error!u8 {
    const arg = args[start];
    const split = std.mem.indexOfScalar(u8, arg, '=');
    const value = if (split) |at| arg[at + 1 ..] else if (index > start) args[index] else "";
    return testUsage(init, try std.fmt.allocPrint(init.arena.allocator(), "invalid value '{s}' for {s}", .{ value, arg[0 .. split orelse arg.len] }));
}

/// Whether `arg` is a `mylang test` flag that reads the next argument as its value.
fn takesValue(arg: []const u8) bool {
    const valued = [_][]const u8{ "--filter", "--cases", "--jobs", "--mode", "--max-steps", "--max-frames", "--max-memory", "--timeout-ms", "--seed", "--property-runs", "--property-policy", "--link", "--zig", cache_dir_flag, "--against" };
    for (valued) |name| if (std.mem.eql(u8, arg, name)) return true;
    return false;
}

fn testControls(options: *test_runner.Options, args: []const []const u8, index: *usize, explicit_mode: *bool) error{Usage}!bool {
    const arg = args[index.*];
    const has_value = index.* + 1 < args.len;
    if (std.mem.eql(u8, arg, "--mode") and has_value) {
        index.* += 1;
        if (std.mem.eql(u8, args[index.*], "ReleaseFast")) {
            try options.build.mode.select(explicit_mode, .release);
        } else if (std.mem.eql(u8, args[index.*], "Debug")) {
            try options.build.mode.select(explicit_mode, .optimized_debug);
        } else return error.Usage;
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
        options.controls.ceilings.explicit_steps = true;
    } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
        options.controls.max_steps = std.fmt.parseInt(u64, arg[12..], 10) catch return error.Usage;
        options.controls.ceilings.explicit_steps = true;
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
        var report: std.ArrayList(u8) = .empty;
        const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| {
            if (err == error.OutOfMemory) return err;
            try out.print(init.arena.allocator(), "frontend {s}\t{s}\n", .{ path, std.mem.sliceTo(report.items, '\n') });
            continue;
        };
        var session = frontend.Session.init(init.gpa, init.io, entry.root);
        defer session.deinit();
        const checked = entry.check(allocator, &session, &report) catch |err| switch (err) {
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
