//! `selka engine`: the engine's developer commands (spec §3, §10 and §11).
//!
//! ```
//! selka engine closure KIND                      the files a kind's code identity covers, and the identity
//! selka engine kinds                             the engine's kinds with their identities
//! selka engine query KIND ARGUMENT [flags]       answer a query and print its payload
//! selka engine explain KIND ARGUMENT [flags]     say why a query would not be served
//! flags: --cache-dir DIR  --verify N  --engine-report
//! ```
//! `query` and `explain` run against the machine's filesystem with the work directory's store.
const std = @import("std");
const product = @import("selka").product;
const builtin = @import("builtin");
const kinds = @import("kinds.zig");
const context = @import("context.zig");
const engine_rules = @import("engine.zig");
const explain_rules = @import("explain.zig");
const bench_rules = @import("bench.zig");
const os_world = @import("os_world.zig");
const work_retention = @import("../work_retention.zig");

/// What stops a command before it has a status.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error || work_retention.Error;

/// The variable that sets verify mode's sampling (spec §10).
pub const verify_variable = "SELKA_ENGINE_VERIFY";

/// The Debug compiler's default sampling: one served query in this many is recomputed and compared.
pub const debug_verify_every = 64;

const usage =
    \\usage: selka engine closure KIND
    \\       selka engine kinds
    \\       selka engine query KIND ARGUMENT [--cache-dir DIR] [--verify N] [--engine-report]
    \\       selka engine explain KIND ARGUMENT [--cache-dir DIR]
    \\       selka engine bench [--queries N] [--reads N] [--files N] [--deps N] [--objects PERCENT] [--read-payloads] [--os] [--phase all|compute|serve|verify] [--cache-dir DIR]
    \\
;

/// How a command runs the engine.
pub const Options = struct {
    cache: []const u8 = product.core_work_dir,
    verify: ?u32 = null,
    report: bool = false,
    /// The positional arguments after the subcommand.
    words: []const []const u8 = &.{},
};

/// The sampling spec §10 sets: `SELKA_ENGINE_VERIFY=N` when given and a number, else 64 in a Debug compiler and
/// off in a release one.
pub fn verifyEvery(environment: *const std.process.Environ.Map) u32 {
    if (environment.get(verify_variable)) |text| return std.fmt.parseInt(u32, text, 10) catch 0;
    return if (builtin.mode == .debug) debug_verify_every else 0;
}

/// Split the arguments after the subcommand into options and words; null when a flag is malformed.
pub fn parse(a: std.mem.Allocator, args: []const []const u8) std.mem.Allocator.Error!?Options {
    var options: Options = .{};
    var words: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--engine-report")) {
            options.report = true;
        } else if (std.mem.eql(u8, arg, "--cache-dir") or std.mem.eql(u8, arg, "--verify")) {
            if (index + 1 == args.len) return null;
            index += 1;
            if (std.mem.eql(u8, arg, "--cache-dir")) {
                options.cache = args[index];
            } else options.verify = std.fmt.parseInt(u32, args[index], 10) catch return null;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return null;
        } else try words.append(a, arg);
    }
    options.words = words.items;
    return options;
}

/// Run `selka engine ARGS` and return its exit status.
pub fn run(init: std.process.Init, args: []const []const u8) Error!u8 {
    const a = init.arena.allocator();
    if (args.len == 0) return refuse(init);
    if (std.mem.eql(u8, args[0], "bench")) return bench(init, a, args[1..]);
    const options = (try parse(a, args[1..])) orelse return refuse(init);
    const words = options.words.len;
    if (std.mem.eql(u8, args[0], "kinds") and words == 0) return listKinds(init, a);
    if (std.mem.eql(u8, args[0], "closure") and words == 1) return closure(init, a, options.words[0]);
    if (std.mem.eql(u8, args[0], "query") and words == 2) return inspect(init, a, false, options);
    if (std.mem.eql(u8, args[0], "explain") and words == 2) return inspect(init, a, true, options);
    return refuse(init);
}

/// Measure the engine on a synthetic graph (`bench.zig`) and print one JSON line.
fn bench(init: std.process.Init, a: std.mem.Allocator, args: []const []const u8) Error!u8 {
    var settings: bench_rules.Options = .{};
    var at: usize = 0;
    while (at < args.len) : (at += 1) {
        const flag = args[at];
        if (std.mem.eql(u8, flag, "--os")) {
            settings.os = true;
            continue;
        }
        if (std.mem.eql(u8, flag, "--read-payloads")) {
            settings.mix.read_payloads = true;
            continue;
        }
        if (at + 1 == args.len) return refuse(init);
        at += 1;
        if (std.mem.eql(u8, flag, "--phase")) {
            settings.phase = std.meta.stringToEnum(bench_rules.Phase, args[at]) orelse return refuse(init);
            continue;
        }
        const number = std.fmt.parseInt(usize, args[at], 10) catch 0;
        if (std.mem.eql(u8, flag, "--queries") and number > 0) {
            settings.queries = number;
        } else if (std.mem.eql(u8, flag, "--reads") and number > 0) {
            settings.reads = number;
        } else if (std.mem.eql(u8, flag, "--files") and number > 0) {
            settings.files = number;
        } else if (std.mem.eql(u8, flag, "--deps")) {
            settings.mix.deps = number;
        } else if (std.mem.eql(u8, flag, "--objects") and number <= 100) {
            settings.mix.objects = number;
        } else if (std.mem.eql(u8, flag, "--cache-dir")) {
            settings.cache = args[at];
        } else return refuse(init);
    }
    const found = bench_rules.measure(init.gpa, init.io, init.environ_map, settings) catch |err| return benchFailed(init, a, err);
    var writer: std.Io.Writer.Allocating = .init(a);
    bench_rules.write(&writer.writer, settings, found) catch return error.OutOfMemory;
    try std.Io.File.stdout().writeStreamingAll(init.io, writer.written());
    return 0;
}

fn benchFailed(init: std.process.Init, a: std.mem.Allocator, err: anyerror) Error!u8 {
    const message = try std.fmt.allocPrint(a, "selka engine bench: {s}\n", .{@errorName(err)});
    try std.Io.File.stderr().writeStreamingAll(init.io, message);
    return 1;
}

fn refuse(init: std.process.Init) Error!u8 {
    try std.Io.File.stderr().writeStreamingAll(init.io, usage);
    return 2;
}

fn listKinds(init: std.process.Init, a: std.mem.Allocator) Error!u8 {
    var text: std.ArrayList(u8) = .empty;
    for (kinds.all) |kind| try text.print(a, "{s} {s}\n", .{ kind.name, std.fmt.bytesToHex(kind.identity, .lower) });
    try std.Io.File.stdout().writeStreamingAll(init.io, text.items);
    return 0;
}

fn closure(init: std.process.Init, a: std.mem.Allocator, name: []const u8) Error!u8 {
    const found = kinds.closureOf(name) orelse {
        const message = try std.fmt.allocPrint(a, "selka engine: no engine kind called {s}; `selka engine kinds` lists them\n", .{name});
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return 1;
    };
    var text: std.ArrayList(u8) = .empty;
    try text.print(a, "kind {s}\nidentity {s}\nfiles {d}\ncode {d}\n", .{ name, found.identity, found.files.len, found.code.len });
    for (found.files) |path| try text.print(a, "{s}{s}\n", .{ path, if (isCode(found.code, path)) "" else " (covered)" });
    try std.Io.File.stdout().writeStreamingAll(init.io, text.items);
    return 0;
}

/// Whether `path` is one of the files the kind implements, as against runner code its identity covers.
fn isCode(code: []const []const u8, path: []const u8) bool {
    for (code) |known| if (std.mem.eql(u8, known, path)) return true;
    return false;
}

fn inspect(init: std.process.Init, a: std.mem.Allocator, explaining: bool, options: Options) Error!u8 {
    const kind = kinds.byName(options.words[0]) orelse {
        const message = try std.fmt.allocPrint(a, "selka engine: no engine kind called {s}; `selka engine kinds` lists them\n", .{options.words[0]});
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return 1;
    };
    const status = try answer(init, a, kind, explaining, options);
    work_retention.automatic(a, init.gpa, init.io, options.cache, init.environ_map);
    return status;
}

/// Answer or explain one query with the work directory held, so no collection runs under it.
fn answer(init: std.process.Init, a: std.mem.Allocator, kind: *const context.Kind, explaining: bool, options: Options) Error!u8 {
    const lease = try work_retention.hold(a, init.io, options.cache);
    defer lease.release();
    var machine: os_world.OsWorld = .{ .io = init.io, .environment = init.environ_map, .work = options.cache };
    var runner = try engine_rules.Engine.init(init.gpa, init.io, machine.world(), .{
        .work = options.cache,
        .verify_every = options.verify orelse verifyEvery(init.environ_map),
        .timing = options.report,
    });
    defer runner.deinit();
    for (kinds.all) |known| runner.register(known) catch |err| return failed(init, a, &runner, err);
    var text: std.ArrayList(u8) = .empty;
    if (explaining) {
        const verdict = explain_rules.explain(&runner, a, kind, options.words[1]) catch |err| return failed(init, a, &runner, err);
        var writer: std.Io.Writer.Allocating = .init(a);
        explain_rules.write(&writer.writer, verdict) catch return error.OutOfMemory;
        try text.appendSlice(a, writer.written());
    } else {
        const answered = runner.query(kind, options.words[1]) catch |err| return failed(init, a, &runner, err);
        try text.print(a, "{s}\n", .{answered.payload() catch |err| return failed(init, a, &runner, err)});
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, text.items);
    if (options.report) try printReport(init, a, &runner);
    return 0;
}

fn printReport(init: std.process.Init, a: std.mem.Allocator, runner: *engine_rules.Engine) Error!void {
    var writer: std.Io.Writer.Allocating = .init(a);
    runner.report(&writer.writer) catch return error.OutOfMemory;
    try std.Io.File.stderr().writeStreamingAll(init.io, writer.written());
}

/// Report a failed query on standard error and give its exit status: 2 for the internal error of verify mode
/// (`E_ENGINE_VERIFY`), 1 for anything else.
fn failed(init: std.process.Init, a: std.mem.Allocator, runner: *engine_rules.Engine, err: anyerror) Error!u8 {
    const detail = switch (err) {
        error.VerifyMismatch => try runner.lastMismatch(a),
        error.Cycle => try runner.lastCycle(a),
        else => "",
    };
    const message = try std.fmt.allocPrint(a, "selka engine: {s}{s}{s}\n", .{ @errorName(err), if (detail.len != 0) ": " else "", detail });
    try std.Io.File.stderr().writeStreamingAll(init.io, message);
    return if (err == error.VerifyMismatch) 2 else 1;
}

test "options split flags from words and refuse a flag without its value" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const options = (try parse(a, &.{ "engine-probe", "--cache-dir", "work", "src/a.selka", "--engine-report", "--verify", "16" })).?;
    try std.testing.expectEqualStrings("work", options.cache);
    try std.testing.expectEqual(@as(?u32, 16), options.verify);
    try std.testing.expect(options.report);
    try std.testing.expectEqual(@as(usize, 2), options.words.len);
    try std.testing.expectEqual(@as(?Options, null), try parse(a, &.{"--cache-dir"}));
    try std.testing.expectEqual(@as(?Options, null), try parse(a, &.{ "--verify", "many" }));
    try std.testing.expectEqual(@as(?Options, null), try parse(a, &.{"--bogus"}));
}

/// What `verifyEvery` gives when the variable is unset, for this build.
fn unsetDefault() u32 {
    return if (builtin.mode == .debug) debug_verify_every else 0;
}

test "verify sampling follows the variable, and the build mode when it is unset" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    try std.testing.expectEqual(unsetDefault(), verifyEvery(&environment));
    try environment.put(verify_variable, "16");
    try std.testing.expectEqual(@as(u32, 16), verifyEvery(&environment));
    try environment.put(verify_variable, "off");
    try std.testing.expectEqual(@as(u32, 0), verifyEvery(&environment));
}
