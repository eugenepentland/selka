//! The host side of a component worker: every way a worker can misbehave fails closed, and the Selka echo worker
//! (`selfhost/worker/echo.selka`, built by the compiler under test) answers real round trips.
const std = @import("std");
const component_launch = @import("component_launch.zig");
const component_worker = @import("component_worker.zig");
const frame = @import("worker_frame.zig");
const wiring = @import("wiring/core_runner.zig");
const linux = std.os.linux;

/// Failure detail goes to the test's stderr.
const report = std.debug.print;
const t = std.testing;
const Worker = component_launch.Worker;
const Request = component_launch.Request;

/// The first twenty octets of a well formed reply: magic, version 1, schema 1, kind reply. The length, request id and snapshot follow.
const good_reply = "SLKWRK01\\001\\000\\000\\000\\001\\000\\000\\000\\001\\000\\000\\000";
/// How long an exchange that must not time out may take on a loaded machine.
const patient_ms = 20_000;

/// `piece` written `count` times, at compile time.
fn times(comptime piece: []const u8, comptime count: usize) []const u8 {
    comptime var out: []const u8 = "";
    inline for (0..count) |_| out = out ++ piece;
    return out;
}

/// A worker that waits for a kill ends its script in `exec sleep 30`. A plain `sleep 30` runs as a child of the shell, and
/// the harness kills the worker it started, the shell: the sleeper outlives it, an orphan for half a minute in every run.
fn shell(script: []const u8) !Worker {
    return Worker.start(t.io, &.{ "/bin/sh", "-c", script });
}

/// The pids of this process's live children (zombies are not live), read from every thread's `children` list. Called
/// once, it also makes this process the adopter of orphans, so a helper that outlives its parent is listed too.
fn liveChildren(a: std.mem.Allocator) ![]i32 {
    _ = linux.prctl(@backingInt(linux.PR.SET_CHILD_SUBREAPER), 1, 0, 0, 0);
    var found: std.ArrayList(i32) = .empty;
    var tasks = try std.Io.Dir.cwd().openDir(t.io, "/proc/self/task", .{ .iterate = true });
    defer tasks.close(t.io);
    var iterator = tasks.iterate();
    while (try iterator.next(t.io)) |task| {
        const path = try std.fmt.allocPrint(a, "{s}/children", .{task.name});
        defer a.free(path);
        // A procfs file states its size as 0, so it is read into a buffer, not sized by its length.
        var buffer: [8192]u8 = undefined;
        const text = tasks.readFile(t.io, path, &buffer) catch continue;
        var words = std.mem.tokenizeAny(u8, text, " \n");
        while (words.next()) |word| {
            const pid = std.fmt.parseInt(i32, word, 10) catch continue;
            if (!isZombie(a, pid)) try found.append(a, pid);
        }
    }
    return found.toOwnedSlice(a);
}

fn isZombie(a: std.mem.Allocator, pid: i32) bool {
    const path = std.fmt.allocPrint(a, "/proc/{d}/stat", .{pid}) catch return false;
    defer a.free(path);
    var buffer: [1024]u8 = undefined;
    const stat = std.Io.Dir.cwd().readFile(t.io, path, &buffer) catch return true;
    const close = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return false;
    return close + 2 < stat.len and stat[close + 2] == 'Z';
}

/// Let ten milliseconds pass while a condition is awaited; a cancelled sleep only ends the pause early.
fn pause() void {
    std.Io.sleep(t.io, .fromMilliseconds(10), .awake) catch return;
}

/// Wait, on the condition and not for a while, until the shell `pid` has started the command it was given.
fn shellHasForked(pid: i32) !bool {
    var path_buffer: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "/proc/{d}/task/{d}/children", .{ pid, pid });
    for (0..2000) |_| {
        var buffer: [256]u8 = undefined;
        const text = std.Io.Dir.cwd().readFile(t.io, path, &buffer) catch return false;
        if (std.mem.trim(u8, text, " \n").len > 0) return true;
        pause();
    }
    return false;
}

/// SIGKILL every pid of `now` that `before` does not have.
fn killNew(now: []const i32, before: []const i32) void {
    for (now) |pid| {
        if (std.mem.indexOfScalar(i32, before, pid) == null) _ = linux.kill(pid, linux.SIG.KILL);
    }
}

/// Wait, on the condition, until this process has exactly `count` live children.
fn settlesTo(count: usize) !bool {
    for (0..200) |_| {
        const now = try liveChildren(t.allocator);
        defer t.allocator.free(now);
        if (now.len == count) return true;
        pause();
    }
    return false;
}

/// What a test starts and does not end: the live children this process has when the test begins, against those it has
/// when the test says it is done. A worker's own helper that outlives the kill is one.
const Watch = struct {
    before: usize,

    fn begin() !Watch {
        const now = try liveChildren(t.allocator);
        defer t.allocator.free(now);
        return .{ .before = now.len };
    }

    fn expectNone(self: Watch) !void {
        // A child that is exiting (a failed spawn's, a killed shell's) is gone within moments: wait on that, for as long
        // as a loaded machine needs, and report only what is still there. A helper that outlives its worker never goes.
        var now = try liveChildren(t.allocator);
        defer t.allocator.free(now);
        for (0..1000) |_| {
            if (now.len <= self.before) break;
            pause();
            t.allocator.free(now);
            now = try liveChildren(t.allocator);
        }
        if (now.len > self.before) report("component worker test left {d} live child process(es) behind: {any}\n", .{ now.len - self.before, now });
        try t.expect(now.len <= self.before);
    }
};

fn hello(timeout_ms: u32) Request {
    return .{ .snapshot = @splat(7), .payload = "hello", .timeout_ms = timeout_ms };
}

fn elapsedMs(since: std.Io.Timestamp) i64 {
    return since.durationTo(std.Io.Timestamp.now(t.io, .awake)).toMilliseconds();
}

test "component worker: Died: a worker that exits before it answers, and a worker that crashes" {
    const watch = try Watch.begin();
    {
        var early = try shell("exit 0");
        defer early.abort(t.io);
        try t.expectError(error.Died, early.exchange(t.allocator, t.io, hello(patient_ms)));
        try t.expectEqual(@as(std.process.Child.Term, .{ .exited = 0 }), early.ended.?);
        var crashed = try shell("kill -9 $$");
        defer crashed.abort(t.io);
        try t.expectError(error.Died, crashed.exchange(t.allocator, t.io, hello(patient_ms)));
        try t.expect(crashed.ended.? == .signal);
    }
    try watch.expectNone();
}

test "component worker: Failed: a worker that failed once is gone and answers nothing again" {
    const watch = try Watch.begin();
    {
        var w = try shell("exit 3");
        defer w.abort(t.io);
        try t.expectError(error.Died, w.exchange(t.allocator, t.io, hello(patient_ms)));
        try t.expectEqual(@as(std.process.Child.Term, .{ .exited = 3 }), w.ended.?);
        try t.expect(w.child.id == null);
        try t.expectError(error.Failed, w.exchange(t.allocator, t.io, hello(patient_ms)));
        try t.expectError(error.Failed, w.finish(t.io, 100));
    }
    try watch.expectNone();
}

test "component worker: a failed worker is killed and reaped, so no process is left behind" {
    const watch = try Watch.begin();
    {
        var w = try shell("exec sleep 30");
        const pid = w.child.id.?;
        try t.expectError(error.TimedOut, w.exchange(t.allocator, t.io, hello(300)));
        try t.expect(w.child.id == null);
        try t.expectEqual(std.os.linux.E.SRCH, std.os.linux.errno(std.os.linux.kill(pid, @fromBackingInt(@intCast(0)))));
    }
    try watch.expectNone();
}

test "component worker: TimedOut: no reply by the deadline, and a request the worker never reads" {
    const watch = try Watch.begin();
    {
        var silent = try shell("exec sleep 30");
        defer silent.abort(t.io);
        const started = std.Io.Timestamp.now(t.io, .awake);
        try t.expectError(error.TimedOut, silent.exchange(t.allocator, t.io, hello(300)));
        try t.expect(elapsedMs(started) < 10_000);
        var deaf = try shell("exec sleep 30");
        defer deaf.abort(t.io);
        const big = try t.allocator.alloc(u8, 1 << 20);
        defer t.allocator.free(big);
        @memset(big, 'x');
        try t.expectError(error.TimedOut, deaf.exchange(t.allocator, t.io, .{ .snapshot = @splat(7), .payload = big, .timeout_ms = 300 }));
    }
    try watch.expectNone();
}

test "component worker: Malformed: a reply header that breaks a rule, a request where a reply belongs, and a byte after the reply" {
    const watch = try Watch.begin();
    {
        var zeros = try shell("head -c 64 /dev/zero; exec sleep 30");
        defer zeros.abort(t.io);
        try t.expectError(error.Malformed, zeros.exchange(t.allocator, t.io, hello(patient_ms)));
        var asked = try shell("printf 'SLKWRK01\\001\\000\\000\\000\\001\\000\\000\\000\\000\\000\\000\\000'; head -c 44 /dev/zero; exec sleep 30");
        defer asked.abort(t.io);
        try t.expectError(error.Malformed, asked.exchange(t.allocator, t.io, hello(patient_ms)));
        var extra = try shell("printf '" ++ good_reply ++ "\\000\\000\\000\\000\\001\\000\\000\\000\\000\\000\\000\\000" ++ comptime times("\\000", 32) ++ "X'; exec sleep 30");
        defer extra.abort(t.io);
        const empty: Request = .{ .snapshot = @splat(0), .payload = "", .timeout_ms = patient_ms };
        try t.expectError(error.Malformed, extra.exchange(t.allocator, t.io, empty));
    }
    try watch.expectNone();
}

test "component worker: Oversize: a reply announcing more than 16 MiB is refused before its payload is read, and so is a request" {
    const watch = try Watch.begin();
    {
        var w = try shell("printf 'SLKWRK01\\001\\000\\000\\000\\001\\000\\000\\000\\001\\000\\000\\000\\001\\000\\000\\001'; head -c 40 /dev/zero; exec sleep 30");
        defer w.abort(t.io);
        try t.expectError(error.Oversize, w.exchange(t.allocator, t.io, hello(patient_ms)));
        var quiet = try shell("exec sleep 30");
        defer quiet.abort(t.io);
        const over = try t.allocator.alloc(u8, frame.max_payload + 1);
        defer t.allocator.free(over);
        try t.expectError(error.Oversize, quiet.exchange(t.allocator, t.io, .{ .snapshot = @splat(7), .payload = over, .timeout_ms = patient_ms }));
    }
    try watch.expectNone();
}

test "component worker: Mismatch: a reply to another request id or snapshot identity" {
    const watch = try Watch.begin();
    {
        var other_id = try shell("printf '" ++ good_reply ++ "\\000\\000\\000\\000\\002\\000\\000\\000\\000\\000\\000\\000'; head -c 32 /dev/zero | tr '\\000' '\\007'; exec sleep 30");
        defer other_id.abort(t.io);
        try t.expectError(error.Mismatch, other_id.exchange(t.allocator, t.io, hello(patient_ms)));
        var other_snapshot = try shell("printf '" ++ good_reply ++ "\\000\\000\\000\\000\\001\\000\\000\\000\\000\\000\\000\\000'; head -c 32 /dev/zero; exec sleep 30");
        defer other_snapshot.abort(t.io);
        try t.expectError(error.Mismatch, other_snapshot.exchange(t.allocator, t.io, hello(patient_ms)));
    }
    try watch.expectNone();
}

test "component worker: finish fails a worker that stays, exits badly or speaks" {
    const watch = try Watch.begin();
    {
        var stays = try shell("cat > /dev/null; exec sleep 30");
        defer stays.abort(t.io);
        try t.expectError(error.TimedOut, stays.finish(t.io, 300));
        var bad = try shell("cat > /dev/null; exit 3");
        defer bad.abort(t.io);
        try t.expectError(error.Died, bad.finish(t.io, patient_ms));
        try t.expectEqual(@as(std.process.Child.Term, .{ .exited = 3 }), bad.ended.?);
        var talks = try shell("printf Z; exec sleep 30");
        defer talks.abort(t.io);
        try t.expectError(error.Malformed, talks.finish(t.io, patient_ms));
    }
    try watch.expectNone();
}

test "component worker: start fails closed when the program cannot be started" {
    const watch = try Watch.begin();
    {
        try t.expectError(error.FileNotFound, Worker.start(t.io, &.{"/no-such-directory/no-such-worker"}));
        try t.expectError(error.NonBlockingFailed, component_worker.nonBlocking(-1));
    }
    try watch.expectNone();
}

/// Build `selfhost/worker/echo.selka` with the compiler under test and answer the executable's path.
fn echoProgram() ![]const u8 {
    const session = try wiring.acquire();
    const a = session.allocator();
    const directory = try std.fs.path.join(a, &.{ session.cache, "worker-echo" });
    try std.Io.Dir.cwd().createDirPath(session.io, directory);
    const output = try std.fs.path.join(a, &.{ directory, "echo" });
    const argv = [_][]const u8{
        session.compiler,                                                     "build",
        "selfhost/worker/echo.selka",                                         "-o",
        output,                                                               try std.mem.concat(a, u8, &.{ "--zig=", session.zig }),
        try std.mem.concat(a, u8, &.{ "--cache-dir=", directory, "/build" }),
    };
    const done = try std.process.run(a, session.io, .{ .argv = &argv, .environ_map = try session.environment(null), .stdout_limit = .limited(1 << 20), .stderr_limit = .limited(4 << 20) });
    if (done.term != .exited or done.term.exited != 0) {
        report("echo worker build failed:\n{s}\n", .{done.stderr});
        return error.TestUnexpectedResult;
    }
    return output;
}

test "component worker: the Selka echo worker answers requests of every size and quits on request" {
    const watch = try Watch.begin();
    {
        var w = try Worker.start(t.io, &.{try echoProgram()});
        defer w.abort(t.io);
        for ([_]usize{ 0, 1, 63, 64, 70_000, 1 << 20 }) |size| {
            const payload = try t.allocator.alloc(u8, size);
            defer t.allocator.free(payload);
            for (payload, 0..) |*byte, index| byte.* = @truncate(index *% 31);
            const got = try w.exchange(t.allocator, t.io, .{ .snapshot = @splat(9), .payload = payload, .timeout_ms = 60_000 });
            defer t.allocator.free(got);
            try t.expectEqualSlices(u8, payload, got);
        }
        try w.finish(t.io, 10_000);
        try t.expectEqual(@as(std.process.Child.Term, .{ .exited = 0 }), w.ended.?);
    }
    try watch.expectNone();
}

test "component worker: the Selka echo worker exits cleanly when its input ends between frames" {
    const watch = try Watch.begin();
    {
        var w = try Worker.start(t.io, &.{try echoProgram()});
        defer w.abort(t.io);
        const got = try w.exchange(t.allocator, t.io, hello(60_000));
        defer t.allocator.free(got);
        try t.expectEqualStrings("hello", got);
        w.child.stdin.?.close(t.io);
        w.child.stdin = null;
        const term = try w.child.wait(t.io);
        try t.expectEqual(@as(std.process.Child.Term, .{ .exited = 0 }), term);
    }
    try watch.expectNone();
}

test "component worker: the watch sees a worker's helper that outlives the kill, and nothing else" {
    const before = try liveChildren(t.allocator);
    defer t.allocator.free(before);
    // A plain `sleep 30` runs as a child of the shell, so killing the worker (the shell) leaves it behind, adopted by this process.
    var w = try Worker.start(t.io, &.{ "/bin/sh", "-c", "sleep 30" });
    const during = try liveChildren(t.allocator);
    defer t.allocator.free(during);
    try t.expectEqual(before.len + 1, during.len);
    try t.expect(try shellHasForked(w.child.id.?));
    w.abort(t.io);
    const after = try liveChildren(t.allocator);
    defer t.allocator.free(after);
    try t.expectEqual(before.len + 1, after.len);
    // Ending the helper by hand leaves the watch what it was.
    killNew(after, before);
    try t.expect(try settlesTo(before.len));
}
