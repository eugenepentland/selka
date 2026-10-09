//! TASK-SCHEDULER-1: real fastcc task thunks through the C ABI bridge.
const std = @import("std");
const program = @import("task_ir_program.zig");
const support = @import("test_support.zig");
const driver = @import("driver.zig");
const emitter = @import("emit_llvm.zig");
const own = @import("own.zig");
const io = std.testing.io;
const Error = support.Error || driver.Error || error{ Unexpected, TestUnexpectedResult, TestExpectedEqual };
const Flavor = enum { captures, ranges, trapped, range_trapped };
const Options = struct { flavor: Flavor = .captures, release: bool = false, verify: bool = false, counters: bool = false, sanitized: bool = false, frames: bool = true };
const Artifact = struct { binary: []const u8, llvm: []const u8, environment: std.process.Environ.Map };
const Run = struct { status: u8, stdout: []const u8, stderr: []const u8, counts: []const u8 };

fn location(_: *const anyopaque, span: u32) emitter.Location {
    return .{ .path = "task-hand.my", .line = if (span == 200) 21 else 11, .column = 1 };
}
fn build(a: std.mem.Allocator, root: []const u8, options: Options) Error!Artifact {
    var module = switch (options.flavor) {
        .captures => try program.captures(a),
        .ranges => try program.mapRanges(a),
        .trapped => try program.trapped(a),
        .range_trapped => try program.mapTrapped(a),
    };
    try support.verified(a, &module, &.{});
    _ = try own.run(a, &module, .{ .verify = options.verify });
    try support.verified(a, &module, &.{});
    const context: u8 = 0;
    var target = @import("target.zig").current;
    if (!options.frames) target.traps = .posix_exit;
    const llvm = try emitter.emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = location },
        .source_path = "task-hand.my",
        .main = .{ .parameters = &.{"out"} },
        .verify = options.verify,
        .counters = options.counters,
        .target = target,
    });
    var environment = try std.testing.environ.createMap(a);
    if (options.sanitized) try environment.put("MYLANG_CORE_SANITIZE", "thread");
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    try environment.put("MYLANG_COUNTERS", try std.fs.path.join(a, &.{ root, "counts.json" }));
    const binary = try std.fs.path.join(a, &.{ root, "task-hand" });
    var log: std.ArrayList(u8) = .empty;
    const linked = driver.link(a, io, &environment, .{ .zig = environment.get("ZIG") orelse "zig", .work = root, .output = binary, .release = options.release, .links = &.{}, .units = &.{driver.wholeUnit(llvm)} }, &log);
    try std.testing.expectEqualStrings("", log.items);
    _ = try linked;
    return .{ .binary = binary, .llvm = llvm, .environment = environment };
}
fn run(a: std.mem.Allocator, artifact: *Artifact, threads: []const u8, counters: bool) Error!Run {
    try artifact.environment.put("MYLANG_THREADS", threads);
    const result = std.process.run(a, io, .{ .argv = &.{artifact.binary}, .environ_map = &artifact.environment }) catch return error.TestUnexpectedResult;
    try std.testing.expect(result.term == .exited);
    const counts = if (counters) std.Io.Dir.cwd().readFileAlloc(io, artifact.environment.get("MYLANG_COUNTERS").?, a, .limited(1 << 20)) catch return error.TestUnexpectedResult else "";
    return .{ .status = result.term.exited, .stdout = result.stdout, .stderr = result.stderr, .counts = counts };
}
fn expected(a: std.mem.Allocator, flavor: Flavor) Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    if (flavor == .captures) {
        try text.appendSlice(a, "4\n");
        for (0..8) |_| try text.appendSlice(a, "3 keyé 60\n");
    } else for (100..132) |n| try text.print(a, "{d}\n", .{n});
    return text.items;
}
fn matrix(allocator: std.mem.Allocator, options: Options) Error!usize {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(io, ".", a) catch return error.TestUnexpectedResult;
    var artifact = try build(a, root, options);
    const output = try expected(a, options.flavor);
    var passed: usize = 0;
    for ([_][]const u8{ "1", "2", "8" }) |threads| {
        const result = try run(a, &artifact, threads, options.counters);
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings(output, result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        passed += 1;
        if (options.counters) try std.testing.expect(std.mem.indexOf(u8, result.counts, "\"live_bytes_at_exit\":0") != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, artifact.llvm, "call fastcc ptr %run(ptr %env)") != null);
    if (options.sanitized) try exportArtifact(a, artifact, options.flavor);
    return passed;
}
// Explicit experiment-only export lets the 100-repetition gate rerun exactly
// this test's instrumented binary, recording its hash and each process outcome.
fn exportArtifact(a: std.mem.Allocator, artifact: Artifact, flavor: Flavor) Error!void {
    const directory = artifact.environment.get("MYLANG_P1_FIXTURE_OUTPUT") orelse return;
    const path = try std.fs.path.join(a, &.{ directory, @tagName(flavor) });
    std.Io.Dir.cwd().createDirPath(io, directory) catch return error.TestUnexpectedResult;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, artifact.binary, a, .limited(64 << 20)) catch return error.TestUnexpectedResult;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch return error.TestUnexpectedResult;
    std.Io.Dir.cwd().setFilePermissions(io, path, .executable_file, .{}) catch return error.TestUnexpectedResult;
}

// spec-case: TASK-SCHEDULER-1
test "emitted task bridge preserves mixed captures results and parent copy-on-write at 1 2 8 threads" {
    try std.testing.expectEqual(@as(usize, 3), try matrix(std.testing.allocator, .{}));
}
// spec-case: TASK-SCHEDULER-1
test "emitted tasks preserve ownership assertions and aggregate counters at 1 2 8 threads" {
    try std.testing.expectEqual(@as(usize, 3), try matrix(std.testing.allocator, .{ .release = true, .verify = true, .counters = true }));
}
// spec-case: TASK-SCHEDULER-1
test "emitted range thunk proves ordered parallel map lowering at 1 2 8 threads" {
    try std.testing.expectEqual(@as(usize, 3), try matrix(std.testing.allocator, .{ .flavor = .ranges, .release = true, .verify = true }));
}
// spec-case: TSAN-BUILD-1
test "emitted mixed capture tasks have no ThreadSanitizer reports" {
    try std.testing.expectEqual(@as(usize, 3), try matrix(std.testing.allocator, .{ .release = true, .sanitized = true }));
}
// spec-case: TSAN-BUILD-1
test "emitted range tasks have no ThreadSanitizer reports" {
    try std.testing.expectEqual(@as(usize, 3), try matrix(std.testing.allocator, .{ .flavor = .ranges, .release = true, .sanitized = true }));
}
fn fatal(allocator: std.mem.Allocator, frames: bool) Error!u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(io, ".", a) catch return error.TestUnexpectedResult;
    var artifact = try build(a, root, .{ .flavor = .trapped, .release = true, .frames = frames });
    const result = try run(a, &artifact, "8", false);
    try std.testing.expectEqual(@as(u8, 1), result.status);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "error[R_DIVISION_BY_ZERO]"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "in task submitted at"));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, if (frames) "task-hand.my:11" else "in task submitted at <unknown>") != null);
    return result.status;
}
// spec-case: TASK-SCHEDULER-1
test "emitted task fatal report resolves its captured submission PC" {
    try std.testing.expectEqual(@as(u8, 1), try fatal(std.testing.allocator, true));
}
// spec-case: TASK-SCHEDULER-1
test "emitted task fatal report without DWARF has the required unknown site" {
    try std.testing.expectEqual(@as(u8, 1), try fatal(std.testing.allocator, false));
}

fn mapFatal(allocator: std.mem.Allocator) Error!usize {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(io, ".", a) catch return error.TestUnexpectedResult;
    var artifact = try build(a, root, .{ .flavor = .range_trapped, .release = true });
    var passed: usize = 0;
    for ([_][]const u8{ "1", "2", "8" }) |threads| {
        const result = try run(a, &artifact, threads, false);
        try std.testing.expectEqual(@as(u8, 1), result.status);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "error[R_DIVISION_BY_ZERO]"));
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "in parallel.map item 17 at task-hand.my:11"));
        passed += 1;
    }
    return passed;
}
// spec-case: TASK-SCHEDULER-1
test "range task reports the current item rather than its first item at 1 2 8 threads" {
    try std.testing.expectEqual(@as(usize, 3), try mapFatal(std.testing.allocator));
}
