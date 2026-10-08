//! Batched test processes (NEW-CORE-TEST-BATCH-1): every fixture's verdicts are the
//! same batched and with `MYLANG_TEST_ISOLATE=1`, one process per test.
const std = @import("std");
const options = @import("core_test_options");
const v = @import("property_value.zig");
const Value = std.json.Value;

/// Whether a run shares processes between tests or gives each its own.
const Mode = enum { batched, isolated };
/// The probe's settings: where it counts processes, and whether it ends a process
/// at its second trial.
const Probe = struct { log: []const u8 = "", fault: bool = false };

/// `mylang test FIXTURE --json` with `flags`, in a fresh cache, under `mode`.
fn run(a: std.mem.Allocator, fixture: []const u8, flags: []const []const u8, mode: Mode, probe: Probe) !Value {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    if (mode == .isolated) try environment.put("MYLANG_TEST_ISOLATE", "1");
    if (probe.log.len != 0) try environment.put("MYL_BATCH_PROBE_LOG", probe.log);
    if (probe.fault) try environment.put("MYL_BATCH_PROBE_FAULT", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "test", try std.fs.path.join(a, &.{ options.fixtures, fixture }), "--json", "--jobs", "1", "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expectEqualStrings("", result.stderr);
    return std.json.parseFromSliceLeaky(Value, a, result.stdout, .{});
}

/// The named test's verdict in `report`.
fn named(report: Value, suffix: []const u8) !Value {
    for (v.array(v.get(report, "tests"))) |item| if (std.mem.endsWith(u8, v.text(v.get(item, "name")), suffix)) return item;
    return error.MissingTest;
}

/// Both reports name the same tests with the same status and reason.
fn sameVerdicts(batched: Value, isolated: Value) !void {
    const left = v.array(v.get(batched, "tests"));
    const right = v.array(v.get(isolated, "tests"));
    try std.testing.expectEqual(right.len, left.len);
    for (left, right) |one, other| {
        try std.testing.expectEqualStrings(v.text(v.get(other, "name")), v.text(v.get(one, "name")));
        try std.testing.expectEqualStrings(v.text(v.get(other, "status")), v.text(v.get(one, "status")));
        try std.testing.expectEqualStrings(v.text(v.get(other, "reason")), v.text(v.get(one, "reason")));
    }
}

/// How many test processes the probe counted in `log`.
fn processes(a: std.mem.Allocator, log: []const u8) !usize {
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, log, a, .limited(1 << 16));
    return std.mem.count(u8, text, "process\n");
}

// spec: NEW-CORE-TEST-BATCH-1
test "batched tests keep their own output, memory ceiling and timeout, as each does alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const flags: []const []const u8 = &.{ "--max-steps", "0", "--max-memory", "32M", "--timeout-ms", "400" };
    const batched = try run(a, "c_runner_batch.my", flags, .batched, .{});
    const isolated = try run(a, "c_runner_batch.my", flags, .isolated, .{});
    try sameVerdicts(batched, isolated);
    const printed = try named(batched, "::test_a_prints_then_fails");
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(printed, "reason")), "noisy") != null);
    const quiet = try named(batched, "::test_b_fails_quietly");
    try std.testing.expectEqualStrings("expected true, got false", v.text(v.get(quiet, "reason")));
    const exhausted = try named(batched, "::test_c_exhausts_memory");
    try std.testing.expectEqualStrings("failed", v.text(v.get(exhausted, "status")));
    try std.testing.expect(std.mem.indexOf(u8, v.text(v.get(exhausted, "reason")), "R_MEMORY") != null);
    try std.testing.expectEqualStrings("passed", v.text(v.get(try named(batched, "::test_d_allocates_after"), "status")));
    const hung = try named(batched, "::test_e_hangs");
    try std.testing.expectEqualStrings("timed out after 400 ms", v.text(v.get(hung, "reason")));
    try std.testing.expectEqualStrings("passed", v.text(v.get(try named(batched, "::test_f_passes_after_a_hang"), "status")));
}

// spec-case: NEW-CORE-TEST-BATCH-1
test "plain tests share one process, and a test that ends it is rerun alone while the rest continue" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const helper = try std.fs.path.join(a, &.{ options.fixtures, "c_runner_batch_probe.c" });
    const flags: []const []const u8 = &.{ "--link", helper };
    const shared_log = try std.fs.path.join(a, &.{ root, "batched.log" });
    const alone_log = try std.fs.path.join(a, &.{ root, "isolated.log" });
    const batched = try run(a, "c_runner_batch_probe.my", flags, .batched, .{ .log = shared_log });
    const isolated = try run(a, "c_runner_batch_probe.my", flags, .isolated, .{ .log = alone_log });
    try sameVerdicts(batched, isolated);
    try std.testing.expectEqual(@as(usize, 1), try processes(a, shared_log));
    try std.testing.expectEqual(@as(usize, 3), try processes(a, alone_log));
    // Tests run in name order: one, three, two. The second trial of a process dies
    // with SIGSEGV, so `three` is rerun alone and `two` continues in a new process:
    // three processes, and every test passes.
    const fault_log = try std.fs.path.join(a, &.{ root, "fault.log" });
    const faulted = try run(a, "c_runner_batch_probe.my", flags, .batched, .{ .log = fault_log, .fault = true });
    try sameVerdicts(faulted, isolated);
    try std.testing.expectEqual(@as(u64, 3), v.number(v.get(faulted, "passed")));
    try std.testing.expectEqual(@as(usize, 3), try processes(a, fault_log));
}

// spec-case: NEW-CORE-TEST-BATCH-1
test "tests whose every trial ends its process fail with the same ending batched and alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Every trial exits 17 before answering (a signal would add a crash report per process).
    const helper = try std.fs.path.resolve(a, &.{ options.fixtures, "../../experiments/new-core-s3-20261006/wave-b/s3-runner/c_runner_exit.c" });
    const flags: []const []const u8 = &.{ "--link", helper };
    const batched = try run(a, "c_runner_batch_probe.my", flags, .batched, .{});
    const isolated = try run(a, "c_runner_batch_probe.my", flags, .isolated, .{});
    try sameVerdicts(batched, isolated);
    try std.testing.expectEqual(@as(u64, 3), v.number(v.get(batched, "failed")));
    const one = try named(batched, "::test_one");
    try std.testing.expect(std.mem.startsWith(u8, v.text(v.get(one, "reason")), "NativeTestProcessFailed"));
}
