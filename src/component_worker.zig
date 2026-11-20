//! The host side of a resident component worker (component-worker-v1): one child process that serves framed requests
//! over its standard input and output for the life of the compiler process, so a stage that is called thousands of
//! times pays one launch. The frame is `worker_frame.zig`; the first worker is `selfhost/worker/echo.selka`.
//!
//! Every way a worker can misbehave ends the exchange and the worker, and nothing is retried or substituted:
//!
//!   Died       its standard output closed (a crash, or an exit before it answered) or it stopped reading its input
//!   TimedOut   no complete reply arrived by the deadline
//!   Malformed  a reply header broke a rule, was not a reply, or an extra byte followed the reply
//!   Oversize   a reply (or a request) payload over the 16 MiB limit, refused before any payload is read
//!   Mismatch   the reply echoed another request id or snapshot identity
//!   Failed     an earlier exchange failed; the worker is gone and stays gone
//!
//! A failed exchange kills and reaps the child, so no process is left behind and no later call can read a stale reply.
const std = @import("std");
const linux = std.os.linux;
const frame = @import("worker_frame.zig");

/// What an exchange can fail with besides starting the child.
pub const Error = error{ Died, TimedOut, Malformed, Oversize, Mismatch, Failed } || std.mem.Allocator.Error;
/// Why the worker did not start.
pub const StartError = std.process.SpawnError || error{NonBlockingFailed};

/// One request: the opaque identity it belongs to, the payload and how long the whole exchange may take.
pub const Request = struct {
    snapshot: [32]u8,
    payload: []const u8,
    timeout_ms: u32 = 30_000,
};

/// A running worker. Keep it where it is after `start`; its pipes are the child's.
pub const Worker = struct {
    child: std.process.Child,
    failed: bool = false,
    next_id: u64 = 1,
    /// How the child ended, when it ended on its own before being killed.
    ended: ?std.process.Child.Term = null,

    /// Start `argv` with its standard input and output piped to this process and its standard error discarded.
    pub fn start(io: std.Io, argv: []const []const u8) StartError!Worker {
        var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .pipe, .stdout = .pipe, .stderr = .ignore });
        errdefer child.kill(io);
        try nonBlocking(child.stdin.?.handle);
        return .{ .child = child };
    }

    /// Send `request` and answer the reply's payload, owned by `allocator`. Any failure kills the worker.
    pub fn exchange(self: *Worker, allocator: std.mem.Allocator, io: std.Io, request: Request) Error![]u8 {
        if (self.failed) return error.Failed;
        return self.attempt(allocator, io, request) catch |err| {
            self.fail(io, err);
            return err;
        };
    }

    /// Ask the worker to quit: send the quit frame, close its input and wait for it to end with status 0, within
    /// `timeout_ms`. A worker that answers, stays or ends otherwise has failed.
    pub fn finish(self: *Worker, io: std.Io, timeout_ms: u32) Error!void {
        if (self.failed) return error.Failed;
        return self.close(io, timeout_ms) catch |err| {
            self.fail(io, err);
            return err;
        };
    }

    /// Kill the worker and reap it; idempotent.
    pub fn abort(self: *Worker, io: std.Io) void {
        self.failed = true;
        self.child.kill(io);
    }

    fn fail(self: *Worker, io: std.Io, err: Error) void {
        self.failed = true;
        // A worker that died on its own tells how: a signal is a crash, an exit status an early exit.
        if (err == error.Died and self.child.id != null) self.ended = self.reapIfEnded(io);
        self.child.kill(io);
    }

    fn attempt(self: *Worker, allocator: std.mem.Allocator, io: std.Io, request: Request) Error![]u8 {
        if (request.payload.len > frame.max_payload) return error.Oversize;
        const deadline = deadlineIn(io, request.timeout_ms);
        const sending = self.child.stdin.?.handle;
        const receiving = self.child.stdout.?.handle;
        var id: [8]u8 = undefined;
        std.mem.writeInt(u64, &id, self.next_id, .little);
        self.next_id += 1;
        const header = frame.encodeHeader(.{ .kind = .request, .payload_length = @intCast(request.payload.len), .request_id = id, .snapshot = request.snapshot });
        try writeAll(io, sending, &header, deadline);
        try writeAll(io, sending, request.payload, deadline);
        var reply: [frame.header_len]u8 = undefined;
        try readExactly(io, receiving, &reply, deadline);
        const got = frame.decodeHeader(&reply) catch |err| return switch (err) {
            error.PayloadTooLarge => error.Oversize,
            else => error.Malformed,
        };
        if (got.kind != .reply) return error.Malformed;
        if (!std.mem.eql(u8, &got.request_id, &id) or !std.mem.eql(u8, &got.snapshot, &request.snapshot)) return error.Mismatch;
        const payload = try allocator.alloc(u8, got.payload_length);
        errdefer allocator.free(payload);
        try readExactly(io, receiving, payload, deadline);
        if (readable(receiving)) return error.Malformed;
        return payload;
    }

    fn close(self: *Worker, io: std.Io, timeout_ms: u32) Error!void {
        const deadline = deadlineIn(io, timeout_ms);
        const sending = self.child.stdin.?.handle;
        const quit = frame.encodeHeader(.{ .kind = .quit, .payload_length = 0, .request_id = @splat(0), .snapshot = @splat(0) });
        try writeAll(io, sending, &quit, deadline);
        self.child.stdin.?.close(io);
        self.child.stdin = null;
        // The worker answers a quit with nothing: its output ends, and it ends with status 0. Anything it writes is wrong.
        var byte: [1]u8 = undefined;
        if (readExactly(io, self.child.stdout.?.handle, &byte, deadline)) |_| return error.Malformed else |err| switch (err) {
            error.Died => {},
            else => return err,
        }
        while (!ended(self.child.id.?)) {
            if (remaining(io, deadline) == 0) return error.TimedOut;
            sleepMillis(2);
        }
        const term = self.child.wait(io) catch return error.Died;
        self.ended = term;
        if (!term.success()) return error.Died;
    }

    fn reapIfEnded(self: *Worker, io: std.Io) ?std.process.Child.Term {
        var waited: u32 = 0;
        while (waited < 100) : (waited += 1) {
            if (ended(self.child.id.?)) return self.child.wait(io) catch null;
            sleepMillis(2);
        }
        return null;
    }
};

/// The time `ms` from now.
fn deadlineIn(io: std.Io, ms: u32) std.Io.Timestamp {
    return std.Io.Timestamp.now(io, .awake).addDuration(.fromMilliseconds(ms));
}

/// Milliseconds left before `deadline`, 0 once it has passed.
fn remaining(io: std.Io, deadline: std.Io.Timestamp) u32 {
    const left = std.Io.Timestamp.now(io, .awake).durationTo(deadline).toMilliseconds();
    return if (left <= 0) 0 else @intCast(@min(left, std.math.maxInt(i32)));
}

fn sleepMillis(ms: isize) void {
    const wait: linux.timespec = .{ .sec = 0, .nsec = ms * std.time.ns_per_ms };
    _ = linux.nanosleep(&wait, null);
}

/// Make `fd` non-blocking, so a read or write returns instead of waiting for the peer.
pub fn nonBlocking(fd: std.posix.fd_t) StartError!void {
    const flags = linux.fcntl(fd, linux.F.GETFL, 0);
    if (linux.errno(flags) != .SUCCESS) return error.NonBlockingFailed;
    var mode: linux.O = @bitCast(@as(u32, @intCast(flags)));
    mode.NONBLOCK = true;
    if (linux.errno(linux.fcntl(fd, linux.F.SETFL, @as(u32, @bitCast(mode)))) != .SUCCESS) return error.NonBlockingFailed;
}

/// Wait until `fd` is ready for `events` (a poll event mask) or the deadline passes.
fn ready(io: std.Io, fd: std.posix.fd_t, events: i16, deadline: std.Io.Timestamp) Error!void {
    while (true) {
        const left = remaining(io, deadline);
        if (left == 0) return error.TimedOut;
        var fds = [1]std.posix.pollfd{.{ .fd = fd, .events = events, .revents = 0 }};
        const count = std.posix.poll(&fds, @intCast(left)) catch return error.Died;
        if (count != 0) return;
    }
}

/// Whether `fd` has input (or has ended) right now.
fn readable(fd: std.posix.fd_t) bool {
    var fds = [1]std.posix.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const count = std.posix.poll(&fds, 0) catch return false;
    return count != 0 and (fds[0].revents & linux.POLL.IN) != 0;
}

/// Whether the child has ended and waits to be reaped; the child is left to `wait`.
fn ended(pid: std.posix.pid_t) bool {
    var info: linux.siginfo_t = std.mem.zeroes(linux.siginfo_t);
    const rc = linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT, null);
    return linux.errno(rc) == .SUCCESS and @backingInt(info.signo) != 0;
}

fn writeAll(io: std.Io, fd: std.posix.fd_t, bytes: []const u8, deadline: std.Io.Timestamp) Error!void {
    var sent: usize = 0;
    while (sent < bytes.len) {
        try ready(io, fd, linux.POLL.OUT, deadline);
        const rc = linux.write(fd, bytes.ptr + sent, bytes.len - sent);
        switch (linux.errno(rc)) {
            .SUCCESS => sent += rc,
            .AGAIN, .INTR => {},
            else => return error.Died,
        }
    }
}

fn readExactly(io: std.Io, fd: std.posix.fd_t, buffer: []u8, deadline: std.Io.Timestamp) Error!void {
    var got: usize = 0;
    while (got < buffer.len) {
        try ready(io, fd, linux.POLL.IN, deadline);
        const rc = linux.read(fd, buffer.ptr + got, buffer.len - got);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return error.Died;
                got += rc;
            },
            .AGAIN, .INTR => {},
            else => return error.Died,
        }
    }
}
