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

/// Why a tool could not be started or waited for: the failures
/// `std.process.spawn` reports, so callers handle both alike, plus
/// `ArgumentListTooLong` for an `execve` refused with `E2BIG`, which the
/// standard set can only call `Unexpected` (HOST-FAILURE-CAUSE-1).
pub const Error = std.process.SpawnError || error{ArgumentListTooLong};

/// A running tool: its process id and the read end of the pipe its standard
/// error goes to, or -1 when it writes to this process's standard error.
pub const Started = struct { pid: linux.pid_t, stderr: linux.fd_t };

/// A reaped tool: how it ended and everything it wrote to standard error.
pub const Finished = struct { term: std.process.Child.Term, stderr: []const u8 };

/// How one tool is started: its argument vector (`argv[0]` is a path, or a
/// name looked up on `PATH`), its complete environment — null inherits this
/// process's own, as `std.process` does — and whether its standard error is
/// captured for the caller or shared with this process. A `zig_cache` names
/// the directory the tool's `ZIG_LOCAL_CACHE_DIR` is set to, replacing any the
/// environment gave (NATIVE-ZIG-CACHE-1).
pub const Request = struct {
    argv: []const []const u8,
    environment: ?*const std.process.Environ.Map = null,
    capture: bool = true,
    zig_cache: ?[]const u8 = null,
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
    const given: [*:null]const ?[*:0]const u8 = if (request.environment) |map|
        (try map.createPosixBlock(allocator, .{ .zig_progress_fd = -1 })).slice.ptr
    else
        try inherited(allocator);
    const envp = if (request.zig_cache) |directory| try withZigCache(allocator, given, directory) else given;
    const candidates = try candidatePaths(allocator, request.argv[0], variable(envp, "PATH"));
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
        .envp = envp,
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
        const code: linux.E = @fromBackingInt(@intCast(failure));
        const err = execError(code);
        if (err == error.Unexpected) unexpected("execve", request.argv[0], code);
        return err;
    }
    return .{ .pid = pid, .stderr = if (request.capture) pipe[0] else -1 };
}

/// Read a started tool's captured standard error to its end, then reap it.
/// Reading first means a tool that writes more than a pipe holds is never
/// blocked while this process waits for it to exit.
pub fn finish(allocator: std.mem.Allocator, started: Started) Error!Finished {
    var captured: std.ArrayList(u8) = .empty;
    if (started.stderr >= 0) {
        while (!try pump(allocator, started, &captured)) {}
    }
    return .{ .term = reap(started), .stderr = try captured.toOwnedSlice(allocator) };
}

/// Block until at least one of `running` has written to its captured standard
/// error or closed it, and return the index of one that has. Every entry must
/// capture. A pool that waits this way advances whichever tool is ready first
/// instead of the one it happened to start first.
pub fn ready(allocator: std.mem.Allocator, running: []const Started) Error!usize {
    const fds = try allocator.alloc(linux.pollfd, running.len);
    defer allocator.free(fds);
    for (running, fds) |one, *fd| fd.* = .{ .fd = one.stderr, .events = linux.POLL.IN, .revents = 0 };
    while (true) {
        const rc = linux.poll(fds.ptr, fds.len, -1);
        switch (linux.errno(rc)) {
            .SUCCESS => for (fds, 0..) |fd, index| {
                if (fd.revents != 0) return index;
            },
            .INTR, .AGAIN => {},
            else => |code| {
                unexpected("poll", "", code);
                return error.Unexpected;
            },
        }
    }
}

/// Read what a tool has written to its captured standard error since the last
/// call, appending it to `into`, and report whether the stream has ended. One
/// call reads at most once, so it never blocks after `ready` named the tool.
pub fn pump(allocator: std.mem.Allocator, started: Started, into: *std.ArrayList(u8)) Error!bool {
    var buffer: [16 * 1024]u8 = undefined;
    while (true) {
        const rc = linux.read(started.stderr, &buffer, buffer.len);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return true;
                try into.appendSlice(allocator, buffer[0..rc]);
                return false;
            },
            .INTR => continue,
            else => return true,
        }
    }
}

/// Close a tool's captured standard error, if any, and wait for it to exit.
pub fn reap(started: Started) std.process.Child.Term {
    if (started.stderr >= 0) _ = linux.close(started.stderr);
    var status: u32 = 0;
    waitFor(started.pid, &status);
    return std.Io.Threaded.statusToTerm(status);
}

/// Start a tool and wait for it: `start` then `finish`.
pub fn run(allocator: std.mem.Allocator, request: Request) Error!Finished {
    return finish(allocator, try start(allocator, request));
}

/// The paths the child tries in order: `argv[0]` itself when it names a path,
/// otherwise each `PATH` directory joined with it, as `execvp` searches.
fn candidatePaths(allocator: std.mem.Allocator, name: []const u8, search: ?[]const u8) Error![]const [*:0]const u8 {
    var list: std.ArrayList([*:0]const u8) = .empty;
    if (std.mem.indexOfScalar(u8, name, '/') != null) {
        try list.append(allocator, try allocator.dupeSentinel(u8, name, 0));
        return list.toOwnedSlice(allocator);
    }
    // Without a `PATH` there is nowhere to look, and the start reports the
    // tool missing rather than guessing a system directory.
    var directories = std.mem.splitScalar(u8, search orelse return list.toOwnedSlice(allocator), ':');
    while (directories.next()) |directory| {
        const base = if (directory.len == 0) "." else directory;
        try list.append(allocator, try std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ base, name }, 0));
    }
    return list.toOwnedSlice(allocator);
}

/// This process's own environment as an `execve` block, read back from
/// `/proc/self/environ` — the block the kernel handed this process, which
/// nothing here rewrites — without its `ZIG_PROGRESS` entry.
fn inherited(allocator: std.mem.Allocator) Error![*:null]const ?[*:0]const u8 {
    const opened = linux.open("/proc/self/environ", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    try check(opened);
    const fd: linux.fd_t = @intCast(opened);
    defer _ = linux.close(fd);
    var bytes: std.ArrayList(u8) = .empty;
    var buffer: [16 * 1024]u8 = undefined;
    while (true) {
        const rc = linux.read(fd, &buffer, buffer.len);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) break;
                try bytes.appendSlice(allocator, buffer[0..rc]);
            },
            .INTR => continue,
            else => |code| {
                unexpected("reading", "/proc/self/environ", code);
                return error.Unexpected;
            },
        }
    }
    // Every entry ends in a NUL; one more keeps a truncated last entry whole.
    try bytes.append(allocator, 0);
    var entries: std.ArrayList(?[*:0]const u8) = .empty;
    var first: usize = 0;
    for (bytes.items, 0..) |byte, index| {
        if (byte != 0) continue;
        const entry = bytes.items[first..index :0];
        first = index + 1;
        if (entry.len == 0 or std.mem.startsWith(u8, entry, "ZIG_PROGRESS=")) continue;
        try entries.append(allocator, entry.ptr);
    }
    return (try entries.toOwnedSliceSentinel(allocator, null)).ptr;
}

/// `envp` with `ZIG_LOCAL_CACHE_DIR` naming `directory` in place of any entry it
/// had. `zig cc` and `zig build-obj` otherwise keep their compilation cache in
/// the nearest enclosing `build.zig` project's `.zig-cache`, or in the global
/// cache, keyed by the build's scratch paths, so every guest build added
/// objects there that no later build could reuse.
fn withZigCache(allocator: std.mem.Allocator, envp: [*:null]const ?[*:0]const u8, directory: []const u8) Error![*:null]const ?[*:0]const u8 {
    const name = "ZIG_LOCAL_CACHE_DIR=";
    var entries: std.ArrayList(?[*:0]const u8) = .empty;
    var index: usize = 0;
    while (envp[index]) |entry| : (index += 1) {
        if (!std.mem.startsWith(u8, std.mem.span(entry), name)) try entries.append(allocator, entry);
    }
    try entries.append(allocator, (try std.fmt.allocPrintSentinel(allocator, "{s}{s}", .{ name, directory }, 0)).ptr);
    return (try entries.toOwnedSliceSentinel(allocator, null)).ptr;
}

/// The value an environment block gives `name`, or null.
fn variable(envp: [*:null]const ?[*:0]const u8, name: []const u8) ?[]const u8 {
    var index: usize = 0;
    while (envp[index]) |entry| : (index += 1) {
        const text = std.mem.span(entry);
        if (text.len > name.len and text[name.len] == '=' and std.mem.startsWith(u8, text, name)) return text[name.len + 1 ..];
    }
    return null;
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

/// Map a failed system call's errno onto the spawn errors `std.process` uses;
/// an errno with no name there is written to standard error before the
/// generic `Unexpected`, so the host failure still names its cause.
fn check(rc: usize) Error!void {
    return switch (linux.errno(rc)) {
        .SUCCESS => {},
        .AGAIN, .NOMEM => error.SystemResources,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        else => |code| {
            unexpected("system call", "", code);
            return error.Unexpected;
        },
    };
}

/// HOST-FAILURE-CAUSE-1: name an errno the error set cannot, on standard
/// error, as `mylang: <what> <tool> failed: errno <NAME>`. It writes with one
/// system call from a stack buffer, so it cannot fail or allocate.
fn unexpected(what: []const u8, tool: []const u8, code: linux.E) void {
    var buffer: [512]u8 = undefined;
    const separator: []const u8 = if (tool.len == 0) "" else " ";
    const text = std.fmt.bufPrint(&buffer, "mylang: {s}{s}{s} failed: errno {s}\n", .{ what, separator, tool, @tagName(code) }) catch return;
    _ = linux.write(2, text.ptr, text.len);
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
        .@"2BIG" => error.ArgumentListTooLong,
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

// spec: HOST-FAILURE-CAUSE-1
test "an argument list past the kernel's limit is refused as ArgumentListTooLong, not Unexpected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    // 80 arguments of 100 KiB: 8 MB, over the 6 MiB `execve` admits under any stack limit.
    const argument = try a.alloc(u8, 100 * 1024);
    @memset(argument, 'x');
    const argv = try a.alloc([]const u8, 81);
    argv[0] = "/bin/sh";
    for (argv[1..]) |*slot| slot.* = argument;
    try std.testing.expectError(error.ArgumentListTooLong, start(a, .{ .argv = argv, .environment = &environment }));
    try std.testing.expectEqual(error.ArgumentListTooLong, execError(.@"2BIG"));
    try std.testing.expectEqual(error.Unexpected, execError(.IO));
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

// spec-case: QBE-SPAWN-1
test "a request that names no environment inherits this process's own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A bare name is found on the inherited PATH, and the tool sees it unchanged.
    const finished = try run(a, .{ .argv = &.{ "sh", "-c", "printf '%s' \"$PATH\" >&2" } });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, finished.term);
    try std.testing.expectEqualStrings(std.testing.environ.getPosix("PATH") orelse "", finished.stderr);
    const block = try inherited(a);
    try std.testing.expectEqualStrings(std.testing.environ.getPosix("PATH") orelse "", variable(block, "PATH") orelse "");
    try std.testing.expectEqual(@as(?[]const u8, null), variable(block, "ZIG_PROGRESS"));
}

// spec: NATIVE-ZIG-CACHE-1
test "a request with a zig cache hands the tool that directory as its only local cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    try environment.put("PATH", "/usr/bin:/bin");
    try environment.put("ZIG_LOCAL_CACHE_DIR", "/elsewhere");
    const script = "printf '%s|%s' \"$ZIG_LOCAL_CACHE_DIR\" \"$(env | grep -c '^ZIG_LOCAL_CACHE_DIR=')\" >&2";
    const given = try run(a, .{ .argv = &.{ "/bin/sh", "-c", script }, .environment = &environment, .zig_cache = "/scratch/zig-local" });
    try std.testing.expectEqualStrings("/scratch/zig-local|1", given.stderr);
    const inherits = try run(a, .{ .argv = &.{ "/bin/sh", "-c", script }, .zig_cache = "/scratch/zig-local" });
    try std.testing.expectEqualStrings("/scratch/zig-local|1", inherits.stderr);
    const untouched = try run(a, .{ .argv = &.{ "/bin/sh", "-c", script }, .environment = &environment });
    try std.testing.expectEqualStrings("/elsewhere|1", untouched.stderr);
}

/// Wait for the first of `started` to close its standard error, collecting
/// what it wrote, and return its index.
fn firstDone(a: std.mem.Allocator, started: []const Started, outputs: []std.ArrayList(u8)) !usize {
    while (true) {
        const index = try ready(a, started);
        if (try pump(a, started[index], &outputs[index])) return index;
    }
}

// spec-case: QBE-SPAWN-1
test "a pool hears first from the tool that finishes first, whatever order they started in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    const started = [_]Started{
        try start(a, .{ .argv = &.{ "/bin/sh", "-c", "sleep 1; printf slow >&2" }, .environment = &environment }),
        try start(a, .{ .argv = &.{ "/bin/sh", "-c", "printf fast >&2; exit 4" }, .environment = &environment }),
    };
    var outputs = [_]std.ArrayList(u8){ .empty, .empty };
    const first = try firstDone(a, &started, &outputs);
    try std.testing.expectEqual(@as(usize, 1), first);
    try std.testing.expectEqualStrings("fast", outputs[1].items);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 4 }, reap(started[1]));
    const rest = try finish(a, started[0]);
    try std.testing.expectEqualStrings("slow", rest.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, rest.term);
}
