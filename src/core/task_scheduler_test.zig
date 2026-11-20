//! TASK-SCHEDULER-1: C runtime stress, lazy startup and forbidden-fork guards.
const std = @import("std");
const native = @import("native_fixture.zig");
const support = @import("test_support.zig");
const source = @embedFile("task_scheduler_fixture.c");
const Error = native.Error;

// spec-case: ASAN-BUILD-1
test "ASAN task startup guest joins large borrowed aliases at two and four threads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "tasks.selka", .data = @embedFile("task_asan_guest.selka") });
    const input = try std.fs.path.join(a, &.{ root, "tasks.selka" });
    const options = @import("core_test_options");
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_SANITIZE", "address");
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    for ([_][]const u8{ "2", "4" }) |threads| {
        try support.requireRelease();
        const run = try std.process.run(a, std.testing.io, .{
            .argv = &.{ options.corePath(), "run", input, "--release", "--threads", threads, "--max-memory=0", "--cache-dir", root },
            .environ_map = &environment,
        });
        if (run.term != .exited or run.term.exited != 0) std.debug.print("ASAN guest threads {s}: {s}{s}\n", .{ threads, run.stdout, run.stderr });
        try std.testing.expect(run.term == .exited and run.term.exited == 0);
        try std.testing.expectEqualStrings("159600\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
    }
}

// spec-case: ASAN-BUILD-1
test "ASAN task startup runs every requested worker with large inputs and preserves ordinary heap ceilings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const fixture = @embedFile("task_asan_fixture.c");
    const address = try native.buildProgram(a, root, .{
        .source = fixture,
        .runtime_name = "core_rt_all.c",
        .binary_name = "task-address",
        // Keep optimized ASAN worker coverage within the cold-build RSS limit;
        // inlining the combined runtime exceeds 512 MiB before the fixture runs.
        .flags = &.{ "-O2", "-fno-inline-functions", "-std=c11", "-pthread" },
        .address_sanitized = true,
    });
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("SELKA_MEMORY_LIMIT", "0");
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    for ([_][]const u8{ "2", "4" }) |threads| {
        try environment.put("SELKA_THREADS", threads);
        const run = try std.process.run(a, std.testing.io, .{ .argv = &.{address}, .environ_map = &environment });
        if (run.term != .exited or run.term.exited != 0) std.debug.print("ASAN threads {s}: {s}{s}\n", .{ threads, run.stdout, run.stderr });
        try std.testing.expect(run.term == .exited and run.term.exited == 0);
        try std.testing.expectEqualStrings("", run.stderr);
        const expected = if (std.mem.eql(u8, threads, "2"))
            "threads=2 workers=1 mask=2 input_bytes=32768 sum=8386560 live=0\n"
        else
            "threads=4 workers=3 mask=14 input_bytes=32768 sum=25159680 live=0\n";
        try std.testing.expectEqualStrings(expected, run.stdout);
    }
    const ordinary = try native.buildProgram(a, root, .{ .source = fixture, .runtime_name = "core_rt_all.c", .binary_name = "task-ordinary" });
    const limited = try std.process.run(a, std.testing.io, .{ .argv = &.{ ordinary, "heap-limit" }, .environ_map = &environment });
    try std.testing.expect(limited.term == .exited and limited.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, limited.stderr, "R_MEMORY_BUDGET") != null);
    try std.testing.expect(std.mem.indexOf(u8, limited.stdout, "threads=4 workers=3 mask=14") != null);
    const refused = try native.buildProgram(a, root, .{
        .source = fixture,
        .runtime_name = "core_rt_all.c",
        .binary_name = "task-refused",
        .flags = &.{ "-O2", "-std=c11", "-pthread", "-DTASK_REFUSE_MALLOPT" },
    });
    const failure = try std.process.run(a, std.testing.io, .{ .argv = &.{refused}, .environ_map = &environment });
    try std.testing.expect(failure.term == .exited and failure.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, failure.stderr, "R_THREAD_START") != null);
}

fn matrix(allocator: std.mem.Allocator) Error!usize {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var fixture = try native.Fixture.init(a, root, source, .{});
    var passed: usize = 0;
    for ([_][]const u8{ "1", "2", "8" }) |threads| {
        for ([_][]const u8{ "lazy", "budget", "frames", "stress" }) |mode| {
            const run = try fixture.run(mode, threads);
            try std.testing.expectEqual(@as(u8, 0), run.status);
            try std.testing.expectEqualStrings("", run.stderr);
            try std.testing.expect(run.stdout.len != 0);
            if (std.mem.eql(u8, mode, "stress")) try std.testing.expect(std.mem.indexOf(u8, run.stdout, "1010000 submits, binary depth 12, chain 2048") != null);
            passed += 1;
        }
        const batch = try fixture.run("batch", threads);
        try std.testing.expectEqual(@as(u8, 1), batch.status);
        try std.testing.expect(std.mem.indexOf(u8, batch.stderr, "R_TASK_FORK") != null);
    }
    for ([_][]const u8{ "2", "8" }) |threads| {
        const fork = try fixture.run("fork", threads);
        try std.testing.expectEqual(@as(u8, 1), fork.status);
        try std.testing.expect(std.mem.indexOf(u8, fork.stderr, "R_TASK_FORK") != null);
    }
    return passed;
}
// spec: TASK-SCHEDULER-1
test "scheduler runs million-submit deep nested and own-deque waits at 1 2 8 threads and prohibits fork" {
    try std.testing.expectEqual(@as(usize, 12), try matrix(std.testing.allocator));
}
// spec: RUNTIME-THREADS-3
test "pool start under a 64 MiB ceiling starts its workers or traps R_THREAD_START, never R_MEMORY_BUDGET" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    const cases = [_]struct { threads: []const u8, may_start: bool }{
        .{ .threads = "20", .may_start = true },
        .{ .threads = "64", .may_start = true },
        .{ .threads = "0", .may_start = false },
        .{ .threads = "300", .may_start = false },
    };
    for (cases) |case| {
        const run = try fixture.run("reserve", case.threads);
        if (run.status == 0) {
            try std.testing.expect(case.may_start);
            try std.testing.expectEqualStrings("", run.stderr);
            try std.testing.expect(std.mem.indexOf(u8, run.stdout, "live 0") != null);
        } else {
            try std.testing.expectEqual(@as(u8, 1), run.status);
            try std.testing.expect(std.mem.indexOf(u8, run.stderr, "R_THREAD_START") != null);
            try std.testing.expect(std.mem.indexOf(u8, run.stderr, "R_MEMORY_BUDGET") == null);
        }
    }
}

// spec: TASK-SCHEDULER-2
test "scheduler waits on own work and preserves recursive depth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    const own = try fixture.run("ownwait", "8");
    try std.testing.expectEqual(@as(u8, 0), own.status);
    try std.testing.expectEqualStrings("own wait: foreign deque untouched\n", own.stdout);
    try std.testing.expectEqualStrings("", own.stderr);
    const cases = [_][]const u8{ "1", "8" };
    for (cases) |threads| {
        const recursion = try fixture.run("recursion", threads);
        try std.testing.expectEqual(@as(u8, 0), recursion.status);
        try std.testing.expectEqualStrings("", recursion.stderr);
        try std.testing.expectEqualStrings("recursion: completed, live 0\n", recursion.stdout);
    }
}

// spec: TASK-SCHEDULER-2
test "targeted result waits and idle wakes lose no wakeup at eight threads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    const run = try fixture.run("targeted", "8");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("targeted waits: 200 results, live 0\n", run.stdout);
}

// spec: TASK-SCHEDULER-2
test "a task that submits into another thread's group traps R_TASK_ESCAPE, never races" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    const forged = try fixture.run("escape", "8");
    try std.testing.expectEqual(@as(u8, 1), forged.status);
    try std.testing.expect(std.mem.indexOf(u8, forged.stderr, "R_TASK_ESCAPE") != null);
    const serial = try fixture.run("escape", "1");
    try std.testing.expectEqual(@as(u8, 0), serial.status);
    try std.testing.expectEqualStrings("escape: no trap\n", serial.stdout);
}

// spec-case: TSAN-BUILD-1
test "native scheduler submit stress has no ThreadSanitizer reports at eight threads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{ .sanitized = true });
    const mode = native.stressMode("stress-tsan", "stress");
    const run = try fixture.run(mode, "8");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expect(std.mem.indexOf(u8, run.stdout, try sanitizedReport(mode)) != null);
    try fixture.exportBinary("native-tasks");
}

/// The line a ThreadSanitizer stress run prints: 100,000 submits in the gate, a million
/// under SELKA_FULL_STRESS, each plus the 10,000 the nested and chained phases add.
fn sanitizedReport(mode: []const u8) Error![]const u8 {
    if (std.mem.eql(u8, mode, "stress-tsan")) return "110000 submits, binary depth 12, chain 2048, threads 8, live 0";
    if (std.mem.eql(u8, mode, "stress")) return "1010000 submits, binary depth 12, chain 2048, threads 8, live 0";
    return error.TestUnexpectedResult;
}

const mask_source = @embedFile("task_mask_fixture.c");

/// Run every drop-mask mode at each thread count, returning how many runs passed.
fn maskMatrix(allocator: std.mem.Allocator) Error!usize {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var fixture = try native.Fixture.init(a, root, mask_source, .{});
    var passed: usize = 0;
    for ([_][]const u8{ "1", "8" }) |threads| {
        for ([_][]const u8{ "lent", "owned", "mixed", "taken" }) |mode| {
            const run = try fixture.run(mode, threads);
            try std.testing.expectEqual(@as(u8, 0), run.status);
            try std.testing.expectEqualStrings("", run.stderr);
            try std.testing.expectEqualStrings("mask: ok\n", run.stdout);
            passed += 1;
        }
    }
    return passed;
}

// E1 drop mask (core_tasks.c): a lent reference survives the join and is not released by the environment; an owned
// reference is released once, by the environment or by the thunk that takes it; no mode leaves a live block.
test "E1 drop mask releases owned references once and never a lent one, at one and eight threads" {
    const passed = try maskMatrix(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 8), passed);
}
