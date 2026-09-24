//! Build tools started at a cost that does not grow with this process.
//!
//! A native build holds the whole emitted program in memory — about 900 MB
//! resident for a 50,000-line project — and `fork` copies the page tables of
//! all of it for every tool it starts, then takes a write fault on each page
//! the parent touches afterwards. That made every QBE, assembler and linker
//! start cost tens of milliseconds more as the project grew, and a cold build
//! scale worse than linearly with it. A tool is instead started the way
//! `posix_spawn` starts one: `clone(CLONE_VM | CLONE_VFORK)` runs a small child
//! on its own stack inside this address space until `execve` replaces it, so a
//! start copies nothing whatever this process holds.
//!
//! The child touches only the request this module prepared before the clone
//! and its own stack: it resets every signal handler this process installed
//! to the default (the handlers would otherwise run on shared memory), points
//! its standard streams at `/dev/null` and, when asked, at a private pipe for
//! standard error, restores the signal mask, and executes the tool. The
//! environment block, argument vector and every `PATH` candidate are built
//! before the clone, because nothing may allocate between the clone and the
//! `execve`. Linux x86-64 is the only native build host.
const std = @import("std");
const linux = std.os.linux;

/// Why a tool could not be started or waited for: the same failures
/// `std.process.spawn` reports, so callers handle both alike.
pub const Error = std.process.SpawnError;

/// A running tool: its process id and the read end of the pipe its standard
/// error goes to, or -1 when it writes to this process's standard error.
pub const Started = struct { pid: linux.pid_t, stderr: linux.fd_t };

/// A reaped tool: how it ended and everything it wrote to standard error.
pub const Finished = struct { term: std.process.Child.Term, stderr: []const u8 };

/// How one tool is started: its argument vector (`argv[0]` is a path, or a
/// name looked up on `PATH`), its complete environment, and whether its
/// standard error is captured for the caller or shared with this process.
pub const Request = struct {
    argv: []const []const u8,
    environment: *const std.process.Environ.Map,
    capture: bool = true,
};

/// The stack the child runs on until `execve`: its frames are a handful of
/// system calls, so a small private block is ample in every optimize mode.
const child_stack_bytes = 64 * 1024;

/// Everything the child reads, laid out before the clone, and the one word it
/// writes back: the `execve` errno when no candidate could be executed.
const Shared = struct {
    candidates: []const [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
    null_fd: linux.fd_t,
    stderr_fd: linux.fd_t,
    mask: linux.sigset_t,
    failure: usize = 0,
};

/// Start one tool. The calling thread is suspended only until the tool has
/// executed (or failed to), so the return means the tool is running; reap it
/// with `finish`, which also collects its captured standard error.
pub fn start(allocator: std.mem.Allocator, request: Request) Error!Started {
    if (request.argv.len == 0) return error.FileNotFound;
    const argv = try allocator.allocSentinel(?[*:0]const u8, request.argv.len, null);
    for (request.argv, 0..) |argument, index| argv[index] = (try allocator.dupeSentinel(u8, argument, 0)).ptr;
    // `ZIG_PROGRESS` names a descriptor of this process's own parent; a tool
    // must never write progress frames into it, exactly as `std.process` drops it.
    const block = try request.environment.createPosixBlock(allocator, .{ .zig_progress_fd = -1 });
    const candidates = try candidatePaths(allocator, request.argv[0], request.environment);
    const stack = try allocator.alignedAlloc(u8, .fromByteUnits(16), child_stack_bytes);
    defer allocator.free(stack);

    const null_fd = try openNull();
    defer _ = linux.close(null_fd);
    var pipe: [2]linux.fd_t = .{ -1, -1 };
    if (request.capture) try check(linux.pipe2(&pipe, .{ .CLOEXEC = true }));
    errdefer if (request.capture) {
        _ = linux.close(pipe[0]);
    };
    defer if (request.capture) {
        _ = linux.close(pipe[1]);
    };

    var shared: Shared = .{
        .candidates = candidates,
        .argv = argv.ptr,
        .envp = block.slice.ptr,
        .null_fd = null_fd,
        .stderr_fd = pipe[1],
        .mask = undefined,
    };
    // No signal may run a handler in the child before `execve`: its handlers
    // would run on this process's memory. Block everything across the clone;
    // the child restores the caller's mask just before it executes the tool.
    const everything = linux.sigfillset();
    _ = linux.sigprocmask(linux.SIG.BLOCK, &everything, &shared.mask);
    defer _ = linux.sigprocmask(linux.SIG.SETMASK, &shared.mask, null);
    const flags: u32 = linux.CLONE.VM | linux.CLONE.VFORK | @as(u32, @backingInt(linux.SIG.CHLD));
    const rc = linux.clone(child, @intFromPtr(stack.ptr) + stack.len, flags, @intFromPtr(&shared), null, 0, null);
    try check(rc);
    const pid: linux.pid_t = @intCast(rc);
    // The child wrote this word, if at all, before the clone returned.
    const failure = @as(*volatile usize, &shared.failure).*;
    if (failure != 0) {
        // The child exited without executing anything; reap it and report why.
        var status: u32 = 0;
        waitFor(pid, &status);
        return execError(@fromBackingInt(@intCast(failure)));
    }
    return .{ .pid = pid, .stderr = if (request.capture) pipe[0] else -1 };
}

/// Read a started tool's captured standard error to its end, then reap it.
/// Reading first means a tool that writes more than a pipe holds is never
/// blocked while this process waits for it to exit.
pub fn finish(allocator: std.mem.Allocator, started: Started) Error!Finished {
    var captured: std.ArrayList(u8) = .empty;
    if (started.stderr >= 0) {
        defer _ = linux.close(started.stderr);
        var buffer: [16 * 1024]u8 = undefined;
        while (true) {
            const rc = linux.read(started.stderr, &buffer, buffer.len);
            switch (linux.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) break;
                    try captured.appendSlice(allocator, buffer[0..rc]);
                },
                .INTR => continue,
                else => break,
            }
        }
    }
    var status: u32 = 0;
    waitFor(started.pid, &status);
    return .{ .term = std.Io.Threaded.statusToTerm(status), .stderr = try captured.toOwnedSlice(allocator) };
}

/// Start a tool and wait for it: `start` then `finish`.
pub fn run(allocator: std.mem.Allocator, request: Request) Error!Finished {
    return finish(allocator, try start(allocator, request));
}

/// The paths the child tries in order: `argv[0]` itself when it names a path,
/// otherwise each `PATH` directory joined with it, as `execvp` searches.
fn candidatePaths(allocator: std.mem.Allocator, name: []const u8, environment: *const std.process.Environ.Map) Error![]const [*:0]const u8 {
    var list: std.ArrayList([*:0]const u8) = .empty;
    if (std.mem.indexOfScalar(u8, name, '/') != null) {
        try list.append(allocator, try allocator.dupeSentinel(u8, name, 0));
        return list.toOwnedSlice(allocator);
    }
    // Without a `PATH` there is nowhere to look, and the start reports the
    // tool missing rather than guessing a system directory.
    var directories = std.mem.splitScalar(u8, environment.get("PATH") orelse return list.toOwnedSlice(allocator), ':');
    while (directories.next()) |directory| {
        const base = if (directory.len == 0) "." else directory;
        try list.append(allocator, try std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ base, name }, 0));
    }
    return list.toOwnedSlice(allocator);
}

/// The child: reset handlers, wire the standard streams, restore the mask and
/// execute the first candidate that exists. It returns only by exiting.
fn child(argument: usize) callconv(.c) u8 {
    const shared: *Shared = @ptrFromInt(argument);
    var number: u32 = 1;
    while (number < linux.NSIG) : (number += 1) {
        const signal: linux.SIG = @fromBackingInt(@intCast(number));
        if (signal == .KILL or signal == .STOP) continue;
        var current: linux.Sigaction = undefined;
        if (linux.errno(linux.sigaction(signal, null, &current)) != .SUCCESS) continue;
        const handler = current.handler.handler;
        if (handler == linux.SIG.DFL or handler == linux.SIG.IGN) continue;
        const default: linux.Sigaction = .{ .handler = .{ .handler = linux.SIG.DFL }, .mask = linux.sigemptyset(), .flags = 0 };
        _ = linux.sigaction(signal, &default, null);
    }
    _ = linux.dup2(shared.null_fd, 0);
    _ = linux.dup2(shared.null_fd, 1);
    if (shared.stderr_fd >= 0) _ = linux.dup2(shared.stderr_fd, 2);
    _ = linux.sigprocmask(linux.SIG.SETMASK, &shared.mask, null);
    var failure: linux.E = .NOENT;
    for (shared.candidates) |path| {
        const rc = linux.execve(path, shared.argv, shared.envp);
        const code = linux.errno(rc);
        // Like `execvp`, keep searching past a directory that lacks the tool;
        // any other refusal is the answer.
        if (code == .NOENT or code == .NOTDIR) continue;
        failure = code;
        break;
    }
    @as(*volatile usize, &shared.failure).* = @backingInt(failure);
    linux.exit(127);
}

/// Reap one child, retrying an interrupted wait.
fn waitFor(pid: linux.pid_t, status: *u32) void {
    while (true) {
        var raw: i32 = 0;
        const rc = linux.wait4(pid, &raw, 0, null);
        switch (linux.errno(rc)) {
            .INTR => continue,
            else => {
                status.* = @bitCast(raw);
                return;
            },
        }
    }
}

fn openNull() Error!linux.fd_t {
    const rc = linux.open("/dev/null", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
    try check(rc);
    return @intCast(rc);
}

/// Map a failed system call's errno onto the spawn errors `std.process` uses.
fn check(rc: usize) Error!void {
    return switch (linux.errno(rc)) {
        .SUCCESS => {},
        .AGAIN, .NOMEM => error.SystemResources,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        else => error.Unexpected,
    };
}

/// The error an `execve` refusal stands for.
fn execError(code: linux.E) Error {
    return switch (code) {
        .NOENT => error.FileNotFound,
        .NOTDIR => error.NotDir,
        .ACCES, .PERM => error.AccessDenied,
        .NOEXEC, .INVAL => error.InvalidExe,
        .TXTBSY => error.FileBusy,
        .LOOP => error.SymLinkLoop,
        .NAMETOOLONG => error.NameTooLong,
        .NOMEM, .AGAIN => error.SystemResources,
        else => error.Unexpected,
    };
}

// spec: QBE-SPAWN-1
test "a tool starts without copying this process and reports status and standard error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    try environment.put("PATH", "/usr/bin:/bin");
    try environment.put("MYLANG_SPAWN_PROBE", "seen");
    const finished = try run(a, .{ .argv = &.{ "/bin/sh", "-c", "echo out; echo \"$MYLANG_SPAWN_PROBE\" >&2; exit 3" }, .environment = &environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 3 }, finished.term);
    // Standard output goes nowhere; standard error comes back, with the
    // environment the request named.
    try std.testing.expectEqualStrings("seen\n", finished.stderr);
    // A bare name is looked up on the request's PATH.
    const searched = try run(a, .{ .argv = &.{ "sh", "-c", "kill -TERM $$" }, .environment = &environment });
    try std.testing.expectEqual(std.process.Child.Term{ .signal = .TERM }, searched.term);
    // A tool that is not there is refused at start, with nothing left to reap.
    try std.testing.expectError(error.FileNotFound, start(a, .{ .argv = &.{"/no/such/mylang-tool"}, .environment = &environment }));
    try std.testing.expectError(error.FileNotFound, start(a, .{ .argv = &.{"no-such-mylang-tool"}, .environment = &environment }));
}

/// Start one `/bin/sh` per script at once, then reap them in order, returning
/// each exit code and the first byte each wrote to standard error.
fn startMany(a: std.mem.Allocator, environment: *const std.process.Environ.Map, count: usize) ![2][]u8 {
    const started = try a.alloc(Started, count);
    for (started, 0..) |*slot, index| {
        const script = try std.fmt.allocPrint(a, "printf {d} >&2; exit {d}", .{ index, index });
        slot.* = try start(a, .{ .argv = &.{ "/bin/sh", "-c", script }, .environment = environment });
    }
    const codes = try a.alloc(u8, count);
    const texts = try a.alloc(u8, count);
    for (started, 0..) |one, index| {
        const finished = try finish(a, one);
        codes[index] = finished.term.exited;
        texts[index] = finished.stderr[0];
    }
    return .{ codes, texts };
}

// spec-case: QBE-SPAWN-1
test "many started tools run at once and each is reaped with its own output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    const results = try startMany(arena.allocator(), &environment, 8);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, results[0]);
    try std.testing.expectEqualStrings("01234567", results[1]);
}
