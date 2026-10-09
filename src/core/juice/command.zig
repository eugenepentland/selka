//! Native `selka juice` dispatch. Installed commands need no script or interpreter.
const std = @import("std");
const d = @import("data.zig");
const p = @import("platform.zig");
const report = @import("report.zig");
const calibration = @import("calibration.zig");
const collectors = @import("collectors.zig");
const manifest = @import("manifest.zig");
const engine = @import("engine.zig");
const help =
    \\usage: selka juice <command> [options]
    \\  doctor [--collector perf|callgrind|cachegrind] [--cpu N]
    \\  analyze MANIFEST --output REPORT.json [--against OLD.json]
    \\  record MANIFEST --name LABEL [--tier quick|validation|all] [--repeats N]
    \\  compare BASE.json CANDIDATE.json --output REPORT.json [--mode application|backend|combined]
    \\  validate QUICK.json LARGER.json --output REPORT.json [--tolerance N]
    \\  calibrate DATASET.json --output MODEL.json
    \\Build options: --compiler PATH --cache-dir DIR
    \\Record options: --workload NAME (repeatable) --static --collector KIND --cpu N --perf PATH --valgrind PATH
    \\Compare options: --max-spread N --min-change N --fail-above N --model MODEL.json
    \\Juice measures instructions per completed unit. Baseline 100; it is not a runtime percentage.
    \\Capture currently supports Linux x86_64. Reporting requires no external tools.
    \\
;
/// Diagnosed Juice failures return exit 2; only stream and allocator errors propagate.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error;
/// One parsed command with strict options and ordered input paths.
pub const Request = struct { command: []const u8, options: d.Value, positional: d.Value };
fn contains(words: []const u8, word: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, words, ' ');
    while (it.next()) |w| if (std.mem.eql(u8, w, word)) return true;
    return false;
}
fn allowed(command: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, command, "doctor")) return "collector cpu perf valgrind";
    if (std.mem.eql(u8, command, "record")) return "name compiler cache-dir tier repeats workload static collector cpu perf valgrind";
    if (std.mem.eql(u8, command, "analyze")) return "compiler cache-dir output against";
    if (std.mem.eql(u8, command, "compare")) return "mode output max-spread min-change fail-above model";
    if (std.mem.eql(u8, command, "validate")) return "tolerance output";
    if (std.mem.eql(u8, command, "calibrate")) return "output";
    return null;
}
/// Reject unknown, duplicated and mis-scoped flags instead of silently ignoring them.
pub fn parse(c: *d.Context, args: []const []const u8) d.Error!Request {
    return parseImpl(c, args) catch |err| d.failure(c, err);
}
fn parseImpl(c: *d.Context, args: []const []const u8) !Request {
    if (args.len == 0) return c.fail(help);
    const flags = allowed(args[0]) orelse return c.fail(help);
    var options = d.object();
    var positional = d.array(c);
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!std.mem.startsWith(u8, arg, "--")) {
            try d.add(c, &positional, d.string(arg));
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, arg, '=');
        const key = arg[2 .. eq orelse arg.len];
        if (!contains(flags, key)) return c.fail("unknown or misplaced Juice option (see selka juice --help)");
        if (std.mem.eql(u8, key, "static")) {
            if (eq != null or d.get(options, key) != .null) return error.InvalidExperiment;
            try d.put(c, &options, key, .{ .bool = true });
            continue;
        }
        const value = if (eq) |at| arg[at + 1 ..] else blk: {
            i += 1;
            if (i == args.len) return c.fail("missing option value");
            break :blk args[i];
        };
        if (value.len == 0) return c.fail("empty option value");
        if (std.mem.eql(u8, key, "workload")) {
            var names = d.get(options, key);
            if (names == .null) names = d.array(c);
            try d.add(c, &names, d.string(value));
            try d.put(c, &options, key, names);
        } else {
            if (d.get(options, key) != .null) return c.fail("duplicate Juice option");
            try d.put(c, &options, key, d.string(value));
        }
    }
    const count: usize = if (contains("doctor", args[0])) 0 else if (contains("compare validate", args[0])) 2 else 1;
    if (positional.array.items.len != count) return c.fail(help);
    return .{ .command = args[0], .options = options, .positional = positional };
}
/// String option with a default; validated during parse.
pub fn option(r: Request, key: []const u8, fallback: []const u8) []const u8 {
    return d.str(d.get(r.options, key)) catch fallback;
}
/// Numeric option with finite bounds.
pub fn number(r: Request, key: []const u8, fallback: f64, low: f64, high: f64) d.Error!f64 {
    return numberImpl(r, key, fallback, low, high) catch |err| d.failure(null, err);
}
fn numberImpl(r: Request, key: []const u8, fallback: f64, low: f64, high: f64) !f64 {
    const v = d.get(r.options, key);
    const n = if (v == .null) fallback else try std.fmt.parseFloat(f64, try d.str(v));
    if (!std.math.isFinite(n) or n < low or n > high) return error.InvalidExperiment;
    return n;
}
fn input(r: Request, index: usize) ![]const u8 {
    return d.str((try d.items(r.positional))[index]);
}
fn output(c: *d.Context, r: Request) ![]const u8 {
    const path = try d.str(try d.req(r.options, "output"));
    if (!std.mem.endsWith(u8, path, ".json")) return c.fail("output must have a .json suffix");
    const absolute = try p.absolute(c, path);
    const markdown = if (std.mem.eql(u8, r.command, "compare"))
        try std.fmt.allocPrint(c.a, "{s}.md", .{absolute[0 .. absolute.len - 5]})
    else
        absolute;
    for (try d.items(r.positional)) |v| {
        const source = try p.absolute(c, try d.str(v));
        if (std.mem.eql(u8, absolute, source) or std.mem.eql(u8, markdown, source)) {
            return c.fail("output must not overwrite an input record/report");
        }
    }
    for ([_][]const u8{ "model", "against" }) |k| if (d.get(r.options, k) != .null and std.mem.eql(u8, absolute, try p.absolute(c, try d.str(d.get(r.options, k))))) return c.fail("output must not overwrite an input record/report");
    return absolute;
}
fn execute(c: *d.Context, r: Request) !u8 {
    if (std.mem.eql(u8, r.command, "compare")) {
        const destination = try output(c, r);
        const mode = option(r, "mode", "combined");
        if (!contains("application backend combined", mode)) return c.fail("invalid comparison mode");
        var result = try report.compare(c, try report.load(c, try input(r, 0)), try report.load(c, try input(r, 1)), .{
            .mode = mode,
            .max_spread = try number(r, "max-spread", 0.005, 0, 0.1),
            .min_change = try number(r, "min-change", 0.001, 0, 0.1),
        });
        if (d.get(r.options, "model") != .null) try calibration.predict(c, &result, try c.read(option(r, "model", "")));
        const limit = try number(r, "fail-above", std.math.floatMax(f64), std.math.floatMin(f64), std.math.floatMax(f64));
        try c.write(destination, result);
        const text = try report.render(c, result);
        try c.writeBytes(try std.fmt.allocPrint(c.a, "{s}.md", .{destination[0 .. destination.len - 5]}), text);
        try std.Io.File.stdout().writeStreamingAll(c.io, text);
        if (d.get(r.options, "fail-above") != .null) for (try d.keys(c, d.get(result, "workloads"))) |name| {
            const cell = d.get(d.get(result, "workloads"), name);
            if (try d.num(d.get(cell, "juice")) > limit or d.is(d.get(cell, "assessment"), "uncertain") or d.is(d.get(cell, "assessment"), "mixed")) return 1;
        };
        return 0;
    }
    if (std.mem.eql(u8, r.command, "validate")) {
        const destination = try output(c, r);
        const result = try report.validate(c, try c.read(try input(r, 0)), try c.read(try input(r, 1)), try number(r, "tolerance", 0.03, 0, 0.25));
        try c.write(destination, result);
        const passed = d.equal(d.get(result, "passed"), .{ .bool = true });
        try std.Io.File.stdout().writeStreamingAll(c.io, if (passed) "Quick-scenario validation: passed\n" else "Quick-scenario validation: failed\n");
        return if (passed) 0 else 1;
    }
    if (std.mem.eql(u8, r.command, "calibrate")) {
        const destination = try output(c, r);
        try c.write(destination, try calibration.fit(c, try input(r, 0)));
        try std.Io.File.stdout().writeStreamingAll(c.io, "Validated model written. Predictions remain limited to matched contexts and families.\n");
        return 0;
    }
    if (std.mem.eql(u8, r.command, "doctor")) {
        const selected = try collector(c, r);
        try std.Io.File.stdout().writeStreamingAll(c.io, try std.fmt.allocPrint(c.a, "{s}\nTool found. Permissions, ISA and complete counts are checked during recording.\n", .{
            try std.json.Stringify.valueAlloc(c.a, selected.identity, .{
                .whitespace = .indent_2,
            }),
        }));
        return 0;
    }
    const m = try manifest.load(c, try input(r, 0));
    const options: engine.Options = .{
        .cache = option(r, "cache-dir", "~/.cache/selka/juice"),
        .compiler = if (d.get(r.options, "compiler") == .null) null else option(r, "compiler", ""),
        .name = option(r, "name", ""),
        .tier = option(r, "tier", "quick"),
        .workloads = d.get(r.options, "workload"),
        .repeats = try integer(r, "repeats", 3, 2, 30),
        .static = d.equal(d.get(r.options, "static"), .{
            .bool = true,
        }),
    };
    if (std.mem.eql(u8, r.command, "record")) {
        const path = try engine.capture(c, m, try collector(c, r), options);
        try std.Io.File.stdout().writeStreamingAll(c.io, try std.fmt.allocPrint(c.a, "{s}\n", .{path}));
        return 0;
    }
    const destination = try output(c, r);
    var analysis = try engine.analyze(c, m, options);
    if (d.get(r.options, "against") != .null) {
        const base = try c.read(option(r, "against", ""));
        if (!d.is(d.get(base, "version"), "juice-analysis-v1")) return c.fail("against must name a juice-analysis-v1 report");
        const a = d.get(d.get(base, "build"), "code");
        const b = d.get(d.get(analysis, "build"), "code");
        var changes = try c.value(.{
            .sections = try report.differences(c, d.get(a, "sections"), d.get(b, "sections")),
            .functions = try report.differences(c, d.get(a, "functions"), d.get(b, "functions")),
        });
        const ca = d.get(d.get(base, "build"), "static_cost");
        const cb = d.get(d.get(analysis, "build"), "static_cost");
        if (d.is(d.get(ca, "version"), "cost-v1") and d.is(d.get(cb, "version"), "cost-v1")) try d.put(c, &changes, "core_totals", try report.differences(c, d.get(ca, "totals"), d.get(cb, "totals")));
        try d.put(c, &analysis, "changes", changes);
    }
    try c.write(destination, analysis);
    try std.Io.File.stdout().writeStreamingAll(c.io, "Static analysis written. No application execution or runtime prediction.\n");
    return 0;
}
fn integer(r: Request, key: []const u8, fallback: usize, low: usize, high: usize) !usize {
    const value = d.get(r.options, key);
    const n = if (value == .null) fallback else try std.fmt.parseInt(usize, try d.str(value), 10);
    if (n < low or n > high) return error.InvalidExperiment;
    return n;
}
fn collector(c: *d.Context, r: Request) !collectors.Collector {
    const cpu = if (d.get(r.options, "cpu") == .null) null else try integer(r, "cpu", 0, 0, 1023);
    return collectors.init(c, option(r, "collector", "perf"), cpu, option(r, "perf", "perf"), option(r, "valgrind", c.env.get("JUICE_VALGRIND") orelse "valgrind"));
}
/// Native entry point called directly by the compiler dispatcher.
pub fn run(init: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len == 0 or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, help);
        return 0;
    }
    const self = std.process.executablePathAlloc(init.io, init.arena.allocator()) catch return error.OutOfMemory;
    var c: d.Context = .{ .a = init.arena.allocator(), .io = init.io, .env = init.environ_map, .self = self };
    return execute(&c, parse(&c, args) catch |err| return diagnosed(&c, err)) catch |err| diagnosed(&c, err);
}
fn diagnosed(c: *d.Context, err: anyerror) Error!u8 {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    const message = try std.fmt.allocPrint(c.a, "selka juice: {s}{s}{s}\n", .{ @errorName(err), if (c.message.len > 0) ": " else "", c.message });
    try std.Io.File.stderr().writeStreamingAll(c.io, message);
    return 2;
}
