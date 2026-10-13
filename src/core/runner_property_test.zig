//! Generated-input regression tests for real Core trials, discards and shrinking.
const std = @import("std");
const options = @import("core_test_options");
const v = @import("property_value.zig");
const Value = std.json.Value;
const Run = struct { status: u8, report: Value };
fn run(a: std.mem.Allocator, fixture: []const u8, flags: []const []const u8) !Run {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try options.privateEnvironment(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "test", try std.fs.path.join(a, &.{ options.fixtures, fixture }), "--json", "--seed", "7", "--property-runs", "12", "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expectEqualStrings("", result.stderr);
    return .{ .status = if (result.term == .exited) result.term.exited else 255, .report = try std.json.parseFromSliceLeaky(Value, a, result.stdout, .{}) };
}
fn named(report: Value, suffix: []const u8) !Value {
    for (v.array(v.get(report, "tests"))) |item| if (std.mem.endsWith(u8, v.text(v.get(item, "name")), suffix)) return item;
    return error.MissingTest;
}
// spec: NEW-CORE-S3-RUNNER-1
test "S3 runner generated records and recursive inputs pass with fresh capability state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "c_runner_properties.my", "c_runner_standins.my" }) |fixture| {
        const debug = try run(a, fixture, &.{});
        const verify = try run(a, fixture, &.{ "--release", "--verify-facts" });
        try std.testing.expectEqual(@as(u8, 0), debug.status);
        try std.testing.expectEqual(@as(u8, 0), verify.status);
        try std.testing.expectEqual(@as(u64, 0), v.number(v.get(debug.report, "unsupported")));
        for (v.array(v.get(debug.report, "tests"))) |item| {
            const counts = v.get(v.get(item, "property"), "counts");
            try std.testing.expectEqual(@as(u64, 12), v.number(v.get(counts, "passed")));
        }
    }
}
// spec: PROPERTY-TEST-6
test "byte_buffer parameters generate, copy and shrink like bytes and render as byte_buffer literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const debug = try run(a, "c_runner_byte_buffer.my", &.{});
    const verify = try run(a, "c_runner_byte_buffer.my", &.{ "--release", "--verify-facts" });
    try std.testing.expectEqual(@as(u8, 1), debug.status);
    try std.testing.expectEqual(@as(u8, 1), verify.status);
    for ([_]Run{ debug, verify }) |result| {
        const copied = v.get(v.get(try named(result.report, "::test_buffer_copy_appends_alone"), "property"), "counts");
        try std.testing.expectEqual(@as(u64, 12), v.number(v.get(copied, "passed")));
        const nested = v.get(v.get(try named(result.report, "::test_buffers_inside_records_lists_and_options"), "property"), "counts");
        try std.testing.expectEqual(@as(u64, 12), v.number(v.get(nested, "passed")));
        const short = try named(result.report, "::test_short_buffer");
        const minimal = v.get(v.get(v.get(short, "property"), "failure"), "minimal");
        try std.testing.expectEqualStrings("byte_buffer(b\"\\x00\\x00\\x00\")", v.text(v.get(v.get(minimal, "literals"), "buffer")));
        const returned = v.text(v.get(try named(result.report, "::test_buffer_error_result"), "reason"));
        try std.testing.expect(std.mem.indexOf(u8, returned, "returned Err(byte_buffer(b\"\\x00\\x00\\x00\"))") != null);
    }
}
// spec-case: NEW-CORE-S3-RUNNER-1
test "S3 runner shrinks actual failures and enforces the old discard limit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.MissingTest, named(.null, "missing"));
    const result = try run(a, "c_runner_failures.my", &.{"--release"});
    try std.testing.expectEqual(@as(u8, 1), result.status);
    try std.testing.expectEqual(@as(u64, 0), v.number(v.get(result.report, "unsupported")));
    const threshold = try named(result.report, "::test_integer_threshold_shrinks");
    const minimal = v.get(v.get(v.get(v.get(threshold, "property"), "failure"), "minimal"), "literals");
    try std.testing.expectEqualStrings("8", v.text(v.get(minimal, "n")));
    const discard = try named(result.report, "::test_discard_limit");
    const counts = v.get(v.get(discard, "property"), "counts");
    try std.testing.expectEqual(@as(u64, 121), v.number(v.get(counts, "discarded")));
    const helper = try named(result.report, "::test_helper_requires_fails");
    try std.testing.expectEqualStrings("failed", v.text(v.get(helper, "status")));
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(helper, "reason")), "R_REQUIRES") != null);
    const returned = try named(result.report, "::test_result_error");
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(returned, "reason")), "returned Err(\"counterexample\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(returned, "reason")), "c_runner_failures::test_result_error  Err(...) created") != null);
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(returned, "reason")), "__test_trial_") == null);
    const captured = try named(result.report, "::test_failed_trial_captures_buffered_output");
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(captured, "reason")), "trial 0\n") != null);
}

// spec-case: NEW-CORE-S3-RUNNER-1
test "S3 runner retries a native signal or silent exit with old batch counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "c_runner_signal.c", "c_runner_exit.c" }) |filename| {
        const helper = try std.fs.path.resolve(a, &.{ options.fixtures, "../../experiments/new-core-s3-20261006/wave-b/s3-runner", filename });
        const result = try run(a, "c_runner_signal.my", &.{ "--link", helper });
        try std.testing.expectEqual(@as(u8, 1), result.status);
        const signal = try named(result.report, "::test_signal_is_a_failure");
        const counts = v.get(v.get(signal, "property"), "counts");
        try std.testing.expectEqual(@as(u64, 4), v.number(v.get(counts, "processes")));
        try std.testing.expectEqual(@as(u64, 1), v.number(v.get(counts, "shrinks")));
        try std.testing.expectEqual(@as(u64, 1), v.number(v.get(counts, "attempts")));
        try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(signal, "reason")), "NativeTestProcessFailed") != null);
    }
}
