//! RUNTIME-THREADS-1: real native threads, complete output units and bounded fatal paths.
const std = @import("std");
const driver = @import("driver.zig");
const counting = @import("count_runtime.zig");
const fixture = @embedFile("runtime_threads_fixture.c");
const Error = counting.Error || error{ Unexpected, TestUnexpectedResult, TestExpectedEqual };
const Run = struct { stdout: []const u8, stderr: []const u8, status: u8, counts: []const u8 };

fn runFixture(a: std.mem.Allocator, counted: bool, mode: []const u8) Error!Run {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const io = std.testing.io;
    const root = directory.dir.realPathFileAlloc(io, ".", a) catch return error.TestUnexpectedResult;
    const runtime = if (counted) try counting.source(a, driver.runtime_source) else driver.runtime_source;
    directory.dir.writeFile(io, .{ .sub_path = "core_rt.c", .data = runtime }) catch return error.TestUnexpectedResult;
    directory.dir.writeFile(io, .{ .sub_path = "fixture.c", .data = fixture }) catch return error.TestUnexpectedResult;
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    try environment.put("MYLANG_COUNTERS", try std.fs.path.join(a, &.{ root, "counts.json" }));
    const binary = try std.fs.path.join(a, &.{ root, "fixture" });
    const source = try std.fs.path.join(a, &.{ root, "fixture.c" });
    const built = std.process.run(a, io, .{ .argv = &.{ environment.get("ZIG") orelse "zig", "cc", "-O2", "-g", "-std=c11", "-pthread", source, "-o", binary }, .environ_map = &environment }) catch return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", built.stderr);
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = std.process.run(a, io, .{ .argv = &.{ binary, mode }, .environ_map = &environment, .stdout_limit = .limited(2 << 20), .stderr_limit = .limited(1 << 20) }) catch return error.TestUnexpectedResult;
    try std.testing.expect(ran.term == .exited);
    const counts = if (counted) directory.dir.readFileAlloc(io, "counts.json", a, .limited(1 << 20)) catch return error.TestUnexpectedResult else "";
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited, .counts = counts };
}

const Units = struct { lines: usize = 0, malformed: usize = 0, writers: [8]usize = @splat(0) };
fn outputUnits(bytes: []const u8) Units {
    var result: Units = .{};
    var at: usize = 0;
    while (at < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, at, '\n') orelse {
            result.malformed += 1;
            break;
        };
        const line = bytes[at..end];
        result.lines += 1;
        if (line.len != 70000 or line[0] < 'a' or line[0] > 'h') {
            result.malformed += 1;
        } else {
            result.writers[line[0] - 'a'] += 1;
            for (line) |byte| if (byte != line[0]) {
                result.malformed += 1;
                break;
            };
        }
        at = end + 1;
    }
    return result;
}

// spec: RUNTIME-THREADS-1
test "runtime threads isolate allocator traces and signal stacks and serialize providers and large print units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), false, "normal");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    const units = outputUnits(run.stdout);
    try std.testing.expectEqual(@as(usize, 16), units.lines);
    try std.testing.expectEqual(@as(usize, 0), units.malformed);
    try std.testing.expectEqualSlices(usize, &@as([8]usize, @splat(2)), &units.writers);
}

// spec-case: RUNTIME-THREADS-1
test "runtime threads aggregate counted allocations and cross-thread frees after worker retirement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), true, "normal");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    const units = outputUnits(run.stdout);
    try std.testing.expectEqual(@as(usize, 16), units.lines);
    try std.testing.expectEqual(@as(usize, 0), units.malformed);
    try std.testing.expectEqualSlices(usize, &@as([8]usize, @splat(2)), &units.writers);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"allocs\":18") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"frees\":18") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"live_bytes_at_exit\":0") != null);
}

// spec-case: RUNTIME-THREADS-1
test "runtime threads report one fatal winner without entering locked IO cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), false, "fatal");
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stderr, "error[R_DIVISION_BY_ZERO]"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stderr, "task submitted at"));
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "in task submitted at <unknown>") != null);
}

// spec-case: RUNTIME-THREADS-1
test "runtime threads fall back to raw fatal output when another thread holds the stream lock" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), false, "locked");
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stderr, "error[R_DIVISION_BY_ZERO]"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stderr, "task submitted at"));
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "in task submitted at <unknown>") != null);
}

// spec-case: RUNTIME-THREADS-1
test "runtime threads report the worker stack floor on its alternate signal stack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), false, "floor");
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stderr, "error[R_FRAME_LIMIT]"));
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "item 19") != null);
}

// spec-case: RUNTIME-THREADS-1
test "runtime thread output boundaries preserve dynamic print separators and terminators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const support = @import("test_support.zig");
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(),
        \\def main(out: Stream) -> int:
        \\    xs = [1, 2]
        \\    out.print(xs[0], xs[1], sep="|", end="!")
        \\    return 0
    , &refusal);
    const run = try support.runOwned(arena.allocator(), &module, .{});
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("1|2!", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "@myl_core_output_begin") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "@myl_core_output_end") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "@myl_core_free_lists = external thread_local(") != null);
}

// spec-case: RUNTIME-THREADS-1
test "runtime threads preserve exact live counts at quiescent mid-flight and retirement checkpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), true, "accounting");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings(
        "live accounting: 1024 concurrent small/large blocks, zero after retirement\n",
        run.stdout,
    );
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"allocs\":1026") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"frees\":1026") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"live_bytes_at_exit\":0") != null);
}
