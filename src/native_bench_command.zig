//! Reviewed promotion of a passing benchmark candidate into an approved baseline.
//! The command records who approved it, why, and the old and new measurements;
//! repository review rules, not this command, remain the source of approval.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const bench = @import("native_bench.zig");
/// Promotion argument, artifact and validation failures.
pub const Error = fs.Error || bench.Error || error{InvalidBenchPromotionArguments};
pub const usage = "usage: mylang bench-promote --candidate FILE --approver NAME --reason TEXT\n" ++
    "  [--baseline FILE] [--output FILE] [--revision REV]\n" ++
    "  Replaces the approved baseline with a complete, passing candidate and\n" ++
    "  retains the replaced measurements, approver and reason in history.\n";
/// Parsed promotion controls; exactly one destination is required.
const Request = struct {
    candidate: []const u8 = "",
    baseline: ?[]const u8 = null,
    output: ?[]const u8 = null,
    approver: []const u8 = "",
    reason: []const u8 = "",
    revision: []const u8 = "",
};
fn parse(args: []const []const u8) Error!Request {
    var request: Request = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
        if (std.mem.eql(u8, flag, "--help")) return error.InvalidBenchPromotionArguments;
        const value = value: {
            index += 1;
            if (index == args.len) return error.InvalidBenchPromotionArguments;
            break :value args[index];
        };
        if (value.len == 0) return error.InvalidBenchPromotionArguments;
        if (std.mem.eql(u8, flag, "--candidate")) {
            request.candidate = value;
        } else if (std.mem.eql(u8, flag, "--baseline")) {
            request.baseline = value;
        } else if (std.mem.eql(u8, flag, "--output")) {
            request.output = value;
        } else if (std.mem.eql(u8, flag, "--approver")) {
            request.approver = value;
        } else if (std.mem.eql(u8, flag, "--reason")) {
            request.reason = value;
        } else if (std.mem.eql(u8, flag, "--revision")) {
            request.revision = value;
        } else return error.InvalidBenchPromotionArguments;
    }
    if (request.candidate.len == 0 or request.approver.len == 0 or request.reason.len == 0) return error.InvalidBenchPromotionArguments;
    if (request.baseline == null and request.output == null) return error.InvalidBenchPromotionArguments;
    return request;
}
/// Read a candidate, validate it, and atomically write the promoted baseline.
fn promotePaths(context: fs.Context, request: Request) Error![]const u8 {
    const report = try bench.parseReport(context.allocator, try context.read(request.candidate));
    var old: ?bench.Baseline = null;
    if (request.baseline) |path| {
        if (context.exists(path)) old = try bench.parseBaseline(context.allocator, try context.read(path));
    }
    const approved: ?*const bench.Baseline = if (old) |*value| value else null;
    const rendered = try bench.promote(context.allocator, .{
        .report = report,
        .approver = request.approver,
        .reason = request.reason,
        .revision = request.revision,
        .old_baseline = approved,
    });
    const destination = request.output orelse request.baseline.?;
    try context.atomic(destination, rendered);
    return destination;
}
/// Parse promotion arguments, promote one candidate, and report the destination.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(process.io, usage);
        return 0;
    }
    const request = parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    var context = try fs.Context.init(process.arena.allocator(), process.io, process.environ_map);
    defer context.deinit();
    const destination = try promotePaths(context, request);
    try std.Io.File.stdout().writeStreamingAll(process.io, try std.fmt.allocPrint(context.allocator, "promoted {s} to {s}\n", .{ request.candidate, destination }));
    return 0;
}

// spec-case: NATIVE-BENCH-5
test "promotion requires complete evidence and records the approver and reason" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const candidate = try std.fs.path.join(context.allocator, &.{ root, "candidate.json" });
    const baseline = try std.fs.path.join(context.allocator, &.{ root, "baseline.json" });
    const report = try bench.renderReport(context.allocator, .{
        .provenance = .{ .identity = .{ .mode = "ReleaseFast", .runner_profile = "r" } },
        .measurements = &.{.{ .id = "main::bench_sum", .median_ns_per_op = 12, .fixture_identity = "f", .raw = &.{.{ .iterations = 2, .duration_ns = 24 }} }},
        .comparisons = &.{},
        .complete = true,
        .passed = true,
    });
    try context.write(candidate, report);
    const destination = try promotePaths(context, .{ .candidate = candidate, .baseline = baseline, .output = null, .approver = "maintainer", .reason = "reviewed 2026-09-16", .revision = "deadbeef" });
    try std.testing.expectEqualStrings(baseline, destination);
    const promoted = try bench.parseBaseline(context.allocator, try context.read(baseline));
    try std.testing.expectEqual(@as(usize, 0), promoted.history.len);
    try std.testing.expectEqual(@as(f64, 12), promoted.find("main::bench_sum").?.median_ns_per_op);
    try std.testing.expectEqualStrings("deadbeef", promoted.provenance.revision);
    try std.testing.expectError(error.InvalidBenchPromotionArguments, parse(&.{ "--candidate", "x", "--approver", "a" }));
    try std.testing.expectError(error.InvalidBenchPromotionArguments, parse(&.{ "--candidate", "x", "--approver", "a", "--reason", "r" }));
    // An incomplete candidate never replaces the approved baseline.
    const before = try context.read(baseline);
    const incomplete = try bench.renderReport(context.allocator, .{
        .provenance = .{},
        .measurements = &.{},
        .comparisons = &.{},
        .failures = &.{.{ .id = "main::bench_sum", .status = "trap", .reason = "boom" }},
        .complete = false,
        .passed = false,
    });
    try context.write(candidate, incomplete);
    try std.testing.expectError(error.InvalidBenchPromotion, promotePaths(context, .{ .candidate = candidate, .baseline = baseline, .output = null, .approver = "maintainer", .reason = "should not apply", .revision = "cafe" }));
    try std.testing.expectEqualStrings(before, try context.read(baseline));
}
