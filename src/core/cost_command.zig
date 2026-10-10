//! Cost CLI: the build's reachable Core module and passes, without native linking.
const std = @import("std");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const remarks = @import("cost_remarks.zig");
const pipeline = @import("pipeline.zig");
const driver = @import("driver.zig");
const cli_run = @import("cli_run.zig");
const dynamic = @import("cost_dynamic.zig");

/// A malformed request is rendered as usage, with exit 2.
pub const Request = struct {
    path: []const u8,
    function: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
    mode: passes.Mode = .trusted,
    llvm_remarks: ?[]const u8 = null,
    /// `--counters FILE.json`: a counting run's counts, added after the static report.
    counters: ?[]const u8 = null,
};
const usage = "usage: mylang cost <entry.my> [function] [--json] [--debug | --no-facts | --verify-facts] [--llvm-remarks FILE.opt.yaml] [--counters FILE.json]\n";

/// Parse supported modes and reject flags rather than silently changing the analysis.
pub fn parse(args: []const []const u8) ?Request {
    var request: ?Request = null;
    var index: usize = 0;
    var mode_seen = false;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            if (request == null) return null;
            request.?.json = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "--no-facts") or std.mem.eql(u8, arg, "--verify-facts")) {
            if (request == null or mode_seen) return null;
            mode_seen = true;
            request.?.debug = std.mem.eql(u8, arg, "--debug");
            request.?.mode = if (std.mem.eql(u8, arg, "--verify-facts")) .verify else if (std.mem.eql(u8, arg, "--no-facts")) .off else .trusted;
        } else if (std.mem.eql(u8, arg, "--llvm-remarks")) {
            if (request == null or index + 1 == args.len) return null;
            index += 1;
            request.?.llvm_remarks = args[index];
        } else if (std.mem.eql(u8, arg, "--counters")) {
            if (request == null or request.?.counters != null or index + 1 == args.len) return null;
            index += 1;
            request.?.counters = args[index];
        } else if (std.mem.startsWith(u8, arg, "--")) return null else if (request == null) {
            request = .{ .path = arg };
        } else if (request.?.function == null) {
            request.?.function = arg;
        } else return null;
    }
    return request;
}

/// Errors already have diagnostics; other failures propagate to the shared CLI.
pub const Error = frontend.Error || build.Error || project_entry.Error || pipeline.Error || std.Io.File.Writer.Error;

/// Rendered command output and its diagnosed exit status.
pub const Output = struct { text: []const u8 = "", status: u8 = 0 };

/// Run one cost analysis and write its result.
pub fn run(init: std.process.Init, args: []const []const u8) Error!u8 {
    const request = parse(args) orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    };
    const rendered = try output(init, request);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered.text);
    return rendered.status;
}

/// Shared output for cost and list-interfaces --cost; one pipeline and schema.
pub fn output(init: std.process.Init, request: Request) Error!Output {
    const a = init.arena.allocator();
    var diagnostics: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(a, init.io, request.path, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    entry.configure(&session);
    const checked = session.checkFile(a, request.path, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    entry.validate(a, &session, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    var refusal: build.Refusal = .{};
    var module = build.buildExecutable(a, .{ .program = checked.program, .source = checked.src, .drop_debug = !request.debug }, &refusal) catch |err| {
        if (err != error.Unsupported) return err;
        const at = frontend.position(checked.src, .{ .start = refusal.span, .end = refusal.span });
        try diagnostics.print(a, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: the new core does not support {s} yet\n", .{ at.path, at.line, at.column, refusal.reason });
        return failure(init, diagnostics.items, err);
    };
    const options: pipeline.Options = .{
        .zig = cli_run.zigPath(init),
        .mode = if (request.debug) .debug else .release,
        .facts = if (request.mode == .verify) .verify else if (request.mode == .off) .off else .on,
        .show = .{ .stats = true },
    };
    const emission = pipeline.emittedWithScratch(a, init.gpa, &module, try pipeline.unitFor(a, checked, entry.path, session.single != null), options, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    var report = emission.cost_report.?;
    if (request.llvm_remarks == null) {
        const captured = try driver.optimizationRemarks(a, init.io, init.environ_map, .{ .zig = options.zig, .work = options.cache, .output = "", .mode = options.mode, .links = &.{}, .units = emission.units });
        if (captured.yaml) |yaml| remarks.apply(&report, yaml);
        var timing: std.ArrayList(u8) = .empty;
        try cost.llvmStats(a, &timing, report.totals, captured);
        try std.Io.File.stderr().writeStreamingAll(init.io, timing.items);
    }
    report = try cost.select(a, report, request.function);
    if (report.functions.len == 0) {
        const message = try std.fmt.allocPrint(a, "mylang cost: no reachable function named {s}\n", .{request.function orelse "<entry>"});
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return .{ .status = 2 };
    }
    if (request.llvm_remarks) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch {
            try std.Io.File.stderr().writeStreamingAll(init.io, "mylang cost: cannot read LLVM optimization remarks\n");
            return .{ .status = 2 };
        };
        remarks.apply(&report, bytes);
    }
    const path = request.counters orelse return .{ .text = try cost.render(a, report, request.json) };
    const document = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(256 << 20)) catch {
        try std.Io.File.stderr().writeStreamingAll(init.io, "mylang cost: cannot read the counters file\n");
        return .{ .status = 2 };
    };
    const section = dynamic.rows(a, report, document) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCounters => {
            try std.Io.File.stderr().writeStreamingAll(init.io, "mylang cost: the counters file is not a mylang-counters-v1 document\n");
            return .{ .status = 2 };
        },
    };
    return .{ .text = try withCounters(a, report, section, request.json) };
}

/// The static report followed by the counters section, as text or as one JSON document
/// whose `counters` member follows the static members unchanged.
fn withCounters(a: std.mem.Allocator, report: cost.Report, section: []const dynamic.Row, json: bool) std.mem.Allocator.Error![]const u8 {
    if (json) {
        const document = .{ .version = report.version, .functions = report.functions, .totals = report.totals, .counters = section };
        return std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, document, .{})});
    }
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, try cost.render(a, report, false));
    try dynamic.render(a, &out, section);
    return out.toOwnedSlice(a);
}

fn failure(init: std.process.Init, text: []const u8, err: anyerror) Error!Output {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    try std.Io.File.stderr().writeStreamingAll(init.io, text);
    return .{ .status = if (err == error.PolicyDenied) 3 else if (err == error.ConfigurationFailed or err == error.ToolFailed or err == error.InvalidIr or err == error.WriteFailed) 2 else 1 };
}
