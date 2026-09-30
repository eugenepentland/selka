//! Owned Linux seeder pauses whose watcher resumes after foreground death.
const std = @import("std");
const linux = std.os.linux;

/// A seeder pause and its private watcher/socket, closed after the run.
pub const Paused = struct {
    socket: linux.fd_t,
    identity: linux.fd_t,
    watcher: linux.pid_t,
    group: linux.pid_t,

    /// Resume the verified live group and reap only this pause's watcher.
    pub fn proceed(self: Paused) void {
        if (live(self.identity)) _ = linux.kill(-self.group, .CONT);
        _ = linux.close(self.socket);
        _ = linux.close(self.identity);
        reap(self.watcher);
    }
};

/// Pause a caller-verified seeder that leads its own group. A bounded watcher
/// retains a kernel process identity and one close-on-exec socket, closes every
/// inherited descriptor, and resumes that live group when foreground death or
/// normal cleanup closes the socket. Any setup refusal leaves the group running.
pub fn start(group: linux.pid_t) ?Paused {
    if (group <= 1 or group == linux.getpid()) return null;
    if (linux.getpgid(group) != @as(usize, @intCast(group))) return null;
    const opened = linux.pidfd_open(group, 0);
    if (linux.errno(opened) != .SUCCESS) return null;
    const identity: linux.fd_t = @intCast(opened);
    var pair: [2]linux.fd_t = undefined;
    if (linux.errno(linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0, &pair)) != .SUCCESS) {
        _ = linux.close(identity);
        return null;
    }
    const forked = linux.fork();
    if (linux.errno(forked) != .SUCCESS) {
        closeSetup(pair, identity);
        return null;
    }
    if (forked == 0) watch(pair[1], identity, group);
    _ = linux.close(pair[1]);
    const paused: Paused = .{ .socket = pair[0], .identity = identity, .watcher = @intCast(forked), .group = group };
    var ready: [1]u8 = undefined;
    if (readByte(pair[0], &ready) != 1 or ready[0] != 1 or !live(identity)) {
        paused.proceed();
        return null;
    }
    if (linux.errno(linux.kill(-group, .STOP)) != .SUCCESS) {
        paused.proceed();
        return null;
    }
    return paused;
}

fn closeSetup(pair: [2]linux.fd_t, identity: linux.fd_t) void {
    _ = linux.close(pair[0]);
    _ = linux.close(pair[1]);
    _ = linux.close(identity);
}
fn reap(pid: linux.pid_t) void {
    var status: i32 = 0;
    while (linux.errno(linux.waitpid(pid, &status, 0)) == .INTR) {}
}
fn readByte(fd: linux.fd_t, byte: *[1]u8) usize {
    while (true) {
        const result = linux.read(fd, byte, 1);
        if (linux.errno(result) != .INTR) return result;
    }
}
fn live(identity: linux.fd_t) bool {
    var item: [1]linux.pollfd = .{.{ .fd = identity, .events = linux.POLL.IN, .revents = 0 }};
    return linux.poll(&item, 1, 0) == 0;
}
fn closeOthers(left: linux.fd_t, right: linux.fd_t) bool {
    const lower = @min(left, right);
    const upper = @max(left, right);
    const flags: linux.CLOSE_RANGE = .{ .UNSHARE = false, .CLOEXEC = false };
    if (lower != 0 and linux.errno(linux.close_range(0, lower - 1, flags)) != .SUCCESS) return false;
    if (upper > lower + 1 and linux.errno(linux.close_range(lower + 1, upper - 1, flags)) != .SUCCESS) return false;
    return linux.errno(linux.close_range(upper + 1, std.math.maxInt(linux.fd_t), flags)) == .SUCCESS;
}
fn watch(socket: linux.fd_t, identity: linux.fd_t, group: linux.pid_t) noreturn {
    // After fork this branch calls only raw syscalls: inherited allocator and
    // I/O locks may belong to threads absent from this single-threaded child.
    if (linux.errno(linux.setpgid(0, 0)) != .SUCCESS or !closeOthers(socket, identity)) linux.exit(1);
    const ready: [1]u8 = .{1};
    if (linux.write(socket, &ready, 1) != 1) linux.exit(1);
    var items: [2]linux.pollfd = .{
        .{ .fd = socket, .events = linux.POLL.IN | linux.POLL.HUP, .revents = 0 },
        .{ .fd = identity, .events = linux.POLL.IN, .revents = 0 },
    };
    while (true) {
        const result = linux.poll(&items, items.len, -1);
        if (linux.errno(result) == .INTR) continue;
        if (linux.errno(result) != .SUCCESS or items[1].revents != 0) linux.exit(0);
        if (items[0].revents != 0) {
            if (live(identity)) _ = linux.kill(-group, .CONT);
            linux.exit(0);
        }
    }
}

fn state(pid: linux.pid_t) !u8 {
    var path_buffer: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "/proc/{d}/stat", .{pid});
    const file = try std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
    defer file.close(std.testing.io);
    var buffer: [4096]u8 = undefined;
    const count = try file.readStreaming(std.testing.io, &.{&buffer});
    const end = std.mem.lastIndexOfScalar(u8, buffer[0..count], ')') orelse return error.TestUnexpectedResult;
    return buffer[end + 2];
}
fn waitRunning(pid: linux.pid_t) !bool {
    return waitState(pid, false);
}
fn waitState(pid: linux.pid_t, stopped: bool) !bool {
    for (0..100) |_| {
        if ((try state(pid) == 'T') == stopped) return true;
        idle(10);
    }
    return false;
}
fn sleeper() !std.process.Child {
    return std.process.spawn(std.testing.io, .{ .argv = &.{ "sleep", "600" }, .pgid = 0, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
}
// spec-case: MODULE-TEST-6
test "an owned pause resumes normally and refuses self or nonexistent groups" {
    var child = try sleeper();
    defer child.kill(std.testing.io);
    const pid = child.id.?;
    const paused = start(pid) orelse return error.TestUnexpectedResult;
    try std.testing.expect(try waitState(pid, true));
    paused.proceed();
    try std.testing.expect(try waitRunning(pid));
    try std.testing.expect(start(linux.getpid()) == null);
    try std.testing.expect(start(1) == null);
    try std.testing.expect(start(std.math.maxInt(linux.pid_t)) == null);
}
// spec-case: MODULE-TEST-6
test "SIGKILL of the foreground resumes its owned seeder without retaining caller descriptors" {
    var seeder = try sleeper();
    defer seeder.kill(std.testing.io);
    var pair: [2]linux.fd_t = undefined;
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.pipe2(&pair, .{ .CLOEXEC = true })));
    defer _ = linux.close(pair[0]);
    const forked = linux.fork();
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(forked));
    foregroundBranch(forked, pair, seeder.id.?);
    _ = linux.close(pair[1]);
    var ready: [1]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 1), readByte(pair[0], &ready));
    try std.testing.expectEqual(@as(u8, 1), ready[0]);
    try std.testing.expect(try waitState(seeder.id.?, true));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.kill(-@as(linux.pid_t, @intCast(forked)), .KILL)));
    reap(@intCast(forked));
    try std.testing.expect(try waitRunning(seeder.id.?));
    try std.testing.expect(ended(pair[0]));
}
fn foregroundBranch(forked: usize, pair: [2]linux.fd_t, group: linux.pid_t) void {
    if (forked != 0) return;
    _ = linux.close(pair[0]);
    if (linux.errno(linux.setpgid(0, 0)) != .SUCCESS) linux.exit(1);
    const paused = start(group) orelse linux.exit(1);
    _ = paused;
    const ready: [1]u8 = .{1};
    if (linux.write(pair[1], &ready, 1) != 1) linux.exit(1);
    while (true) idle(-1);
}

fn idle(timeout: i32) void {
    var empty: [0]linux.pollfd = .{};
    _ = linux.poll(&empty, 0, timeout);
}

fn ended(fd: linux.fd_t) bool {
    var item: [1]linux.pollfd = .{.{ .fd = fd, .events = linux.POLL.HUP, .revents = 0 }};
    return linux.poll(&item, 1, 1000) == 1 and item[0].revents & linux.POLL.HUP != 0;
}
