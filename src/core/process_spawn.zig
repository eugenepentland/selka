//! Starting a child process without copying this one (NEW-CORE-SPAWN-1).
//!
//! `std.process` forks, so every child begins as a copy of this process's page
//! tables, which `execve` then throws away. For a compiler holding a few hundred
//! megabytes that copy costs about 13 ms of system time per launch, serialized on
//! the address space, and a test run launches hundreds. Here the child is a
//! `clone(CLONE_VM | CLONE_VFORK)` that shares this process's memory on a small
//! stack of its own, as `posix_spawn` does: it only rewires its standard streams,
//! resets every signal handler, restores the caller's signal mask and calls
//! `execve`, while the calling thread waits for that `execve` or the child's exit.
//! Signals stay blocked from before the clone until then, so no handler of this
//! process runs on the shared memory. The returned `std.process.Child` waits and
//! is killed like any other. Linux only, like the core's runtime.
const std = @import("std");
const linux = std.os.linux;

/// The child's environment: this process's own block, passed as it is, or a map.
pub const Environment = union(enum) { block: std.process.Environ.PosixBlock, map: *const std.process.Environ.Map };

/// Where one of the child's standard streams goes. `empty` (stdin only) is a pipe
/// whose write end is already closed, so a read sees end of file at once.
pub const Stdio = union(enum) { inherit, empty, pipe, file: std.Io.File };

/// What to start: `argv[0]` is a path, or a name looked up in the environment's `PATH`.
pub const Options = struct {
    argv: []const []const u8,
    environment: Environment,
    stdin: Stdio = .empty,
    stdout: Stdio = .inherit,
    stderr: Stdio = .inherit,
};

/// Why a child did not start: the errors `std.process.spawn` gives.
pub const Error = std.process.SpawnError;

/// What `run` starts and how long it lets the child take.
pub const RunOptions = struct {
    argv: []const []const u8,
    environment: Environment,
    timeout: std.Io.Timeout = .none,
    stdout_limit: std.Io.Limit = .unlimited,
    stderr_limit: std.Io.Limit = .unlimited,
};

/// The child's stack: enough for the `PATH` search's one path buffer.
const stack_size = 64 << 10;

/// What the child reads from the caller's memory, and where it leaves the errno of
/// a failed start.
const Request = struct {
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
    path: []const u8,
    streams: [3]i32,
    mask: linux.sigset_t,
    failure: usize = 0,
};

/// Start `options.argv` as a child process. `gpa` holds the argument and
/// environment copies until the child has called `execve`.
pub fn spawn(gpa: std.mem.Allocator, options: Options) Error!std.process.Child {
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    if (options.argv.len == 0) return error.FileNotFound;
    const argv = try a.allocSentinel(?[*:0]const u8, options.argv.len, null);
    for (options.argv, argv) |argument, *slot| slot.* = (try a.dupeSentinel(u8, argument, 0)).ptr;
    const envp = switch (options.environment) {
        .block => |block| block,
        .map => |map| try map.createPosixBlock(a, .{}),
    };
    var pipes: Pipes = .{};
    errdefer pipes.close(.both);
    const streams: [3]i32 = .{ try pipes.open(0, options.stdin), try pipes.open(1, options.stdout), try pipes.open(2, options.stderr) };
    // The calling thread is suspended while the child runs on this, so its own frame
    // is a safe home for the child's stack.
    var stack: [stack_size]u8 align(16) = undefined;
    var request: Request = .{ .argv = argv.ptr, .envp = envp.slice.ptr, .path = searchPath(envp), .streams = streams, .mask = undefined };
    const blocked = linux.sigfillset();
    _ = linux.sigprocmask(linux.SIG.SETMASK, &blocked, &request.mask);
    const flags: u32 = linux.CLONE.VM | linux.CLONE.VFORK | @backingInt(linux.SIG.CHLD);
    const started = linux.clone(start, @intFromPtr(&stack) + stack.len, flags, @intFromPtr(&request), null, 0, null);
    _ = linux.sigprocmask(linux.SIG.SETMASK, &request.mask, null);
    pipes.close(.child);
    if (linux.errno(started) != .SUCCESS) return error.SystemResources;
    const pid: linux.pid_t = @intCast(started);
    if (request.failure != 0) {
        var status: i32 = undefined;
        while (linux.errno(linux.wait4(pid, &status, 0, null)) == .INTR) {}
        return failed(request.failure);
    }
    return .{
        .id = pid,
        .thread_handle = {},
        .stdin = pipes.parentEnd(0),
        .stdout = pipes.parentEnd(1),
        .stderr = pipes.parentEnd(2),
        .request_resource_usage_statistics = false,
    };
}

/// `std.process.run` with `spawn`: start the child with an empty stdin, collect its
/// stdout and stderr, and wait for it. A timeout or an output limit kills it.
pub fn run(gpa: std.mem.Allocator, io: std.Io, options: RunOptions) std.process.RunError!std.process.RunResult {
    var child = try spawn(gpa, .{ .argv = options.argv, .environment = options.environment, .stdout = .pipe, .stderr = .pipe });
    defer child.kill(io);
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(gpa, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (reader.fill(64, options.timeout)) |_| {
        if (options.stdout_limit.toInt()) |limit| if (reader.reader(0).buffered().len > limit) return error.StreamTooLong;
        if (options.stderr_limit.toInt()) |limit| if (reader.reader(1).buffered().len > limit) return error.StreamTooLong;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |other| return other,
    }
    try reader.checkAnyError();
    const term = try child.wait(io);
    const stdout = try reader.toOwnedSlice(0);
    errdefer gpa.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    return .{ .term = term, .stdout = stdout, .stderr = stderr };
}

/// The pipes of one spawn: per stream, the child's end and the parent's end.
const Pipes = struct {
    ends: [3][2]i32 = @splat(.{ -1, -1 }),

    const Side = enum { child, both };

    /// The descriptor the child's stream `fd` becomes, or -1 to inherit it.
    fn open(self: *Pipes, fd: usize, stdio: Stdio) Error!i32 {
        switch (stdio) {
            .inherit => return -1,
            .file => |file| return file.handle,
            .empty, .pipe => {
                var pair: [2]i32 = undefined;
                switch (linux.errno(linux.pipe2(&pair, .{ .CLOEXEC = true }))) {
                    .SUCCESS => {},
                    .MFILE => return error.ProcessFdQuotaExceeded,
                    .NFILE => return error.SystemFdQuotaExceeded,
                    else => return error.SystemResources,
                }
                // stdin reads pair[0]; stdout and stderr write pair[1].
                const child_end: usize = if (fd == 0) 0 else 1;
                self.ends[fd] = .{ pair[child_end], pair[1 - child_end] };
                if (stdio == .empty) {
                    _ = linux.close(self.ends[fd][1]);
                    self.ends[fd][1] = -1;
                }
                return self.ends[fd][0];
            },
        }
    }

    fn close(self: *Pipes, side: Side) void {
        for (&self.ends) |*end| {
            if (end[0] != -1) _ = linux.close(end[0]);
            end[0] = -1;
            if (side == .child) continue;
            if (end[1] != -1) _ = linux.close(end[1]);
            end[1] = -1;
        }
    }

    fn parentEnd(self: *const Pipes, fd: usize) ?std.Io.File {
        const handle = self.ends[fd][1];
        if (handle == -1) return null;
        return .{ .handle = handle, .flags = .{ .nonblocking = false } };
    }
};

/// The `PATH` of `envp`, or "" when it names none.
fn searchPath(envp: std.process.Environ.PosixBlock) []const u8 {
    const key = "PATH=";
    for (envp.slice) |entry| {
        const text = std.mem.span(entry orelse continue);
        if (std.mem.startsWith(u8, text, key)) return text[key.len..];
    }
    return "";
}

/// The child: runs on its own stack in the caller's memory, with every signal
/// blocked, and touches nothing but `request` and its own stack.
fn start(address: usize) callconv(.c) u8 {
    const request: *Request = @ptrFromInt(address);
    var signal: u32 = 1;
    while (signal < linux.NSIG) : (signal += 1) {
        const which: linux.SIG = @fromBackingInt(@intCast(signal));
        if (which == .KILL or which == .STOP) continue;
        var installed: linux.Sigaction = undefined;
        if (linux.errno(linux.sigaction(which, null, &installed)) != .SUCCESS) continue;
        const handler = installed.handler.handler;
        if (handler == linux.SIG.DFL or handler == linux.SIG.IGN) continue;
        const default: linux.Sigaction = .{ .handler = .{ .handler = linux.SIG.DFL }, .mask = linux.sigemptyset(), .flags = 0 };
        _ = linux.sigaction(which, &default, null);
    }
    for (request.streams, 0..) |source, target| {
        if (source == -1) continue;
        // dup2 clears close-on-exec on the copy; a stream already in place needs fcntl.
        const result = if (source == target) linux.fcntl(source, linux.F.SETFD, 0) else linux.dup2(source, @intCast(target));
        if (linux.errno(result) != .SUCCESS) leave(request, result);
    }
    _ = linux.sigprocmask(linux.SIG.SETMASK, &request.mask, null);
    leave(request, execute(request));
}

/// `execve` the request's program, searching `PATH` for a bare name as `execvp`
/// does, and return the errno of the last failure that decides the outcome.
fn execute(request: *const Request) usize {
    const file = std.mem.span(request.argv[0].?);
    if (std.mem.indexOfScalar(u8, file, '/') != null) return linux.execve(file.ptr, request.argv, request.envp);
    var buffer: [4096]u8 = undefined;
    var denied = false;
    var directories = std.mem.tokenizeScalar(u8, request.path, ':');
    while (directories.next()) |directory| {
        if (directory.len + file.len + 2 > buffer.len) continue;
        @memcpy(buffer[0..directory.len], directory);
        buffer[directory.len] = '/';
        @memcpy(buffer[directory.len + 1 ..][0..file.len], file);
        buffer[directory.len + 1 + file.len] = 0;
        const result = linux.execve(buffer[0 .. directory.len + 1 + file.len :0].ptr, request.argv, request.envp);
        switch (linux.errno(result)) {
            .ACCES => denied = true,
            .NOENT, .NOTDIR => {},
            else => return result,
        }
    }
    return @bitCast(-@as(isize, @backingInt(if (denied) linux.E.ACCES else linux.E.NOENT)));
}

/// Leave the errno in `result` for the waiting caller and end the child.
fn leave(request: *Request, result: usize) noreturn {
    request.failure = @backingInt(linux.errno(result));
    linux.exit_group(127);
}

/// The `std.process` error for a child that could not start with `errno`.
fn failed(errno: usize) Error {
    const code: linux.E = @fromBackingInt(@intCast(errno));
    return switch (code) {
        .@"2BIG", .NOMEM => error.SystemResources,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .NAMETOOLONG => error.NameTooLong,
        .ACCES => error.AccessDenied,
        .PERM => error.PermissionDenied,
        .INVAL, .NOEXEC, .LIBBAD => error.InvalidExe,
        .IO, .LOOP => error.FileSystem,
        .ISDIR => error.IsDir,
        .NOENT => error.FileNotFound,
        .NOTDIR => error.NotDir,
        .TXTBSY => error.FileBusy,
        else => error.Unexpected,
    };
}

/// The test process's environment with `name` set to `value`.
fn environmentWith(a: std.mem.Allocator, name: []const u8, value: []const u8) !std.process.Environ.Map {
    var map = try std.testing.environ.createMap(a);
    try map.put(name, value);
    return map;
}

// spec: NEW-CORE-SPAWN-1
test "run starts a program found on PATH with the given environment and collects both streams" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var map = try environmentWith(a, "SPAWN_PROBE", "from the map");
    const result = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "echo \"$SPAWN_PROBE\"; echo diagnostic >&2; exit 3" }, .environment = .{ .map = &map } });
    try std.testing.expectEqualStrings("from the map\n", result.stdout);
    try std.testing.expectEqualStrings("diagnostic\n", result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 3 }, result.term);
}

// spec-case: NEW-CORE-SPAWN-1
test "spawn reports FileNotFound and AccessDenied for programs that cannot start" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "plain.txt", .data = "not a program" });
    var map = try environmentWith(a, "SPAWN_PROBE", "unused");
    const environment: Environment = .{ .map = &map };
    const missing = try std.fs.path.join(a, &.{ root, "missing" });
    try std.testing.expectError(error.FileNotFound, spawn(a, .{ .argv = &.{missing}, .environment = environment }));
    try std.testing.expectError(error.FileNotFound, spawn(a, .{ .argv = &.{"mylang-no-such-program"}, .environment = environment }));
    try std.testing.expectError(error.FileNotFound, spawn(a, .{ .argv = &.{}, .environment = environment }));
    const plain = try std.fs.path.join(a, &.{ root, "plain.txt" });
    try std.testing.expectError(error.AccessDenied, spawn(a, .{ .argv = &.{plain}, .environment = environment }));
}

// spec-case: NEW-CORE-SPAWN-1
test "run gives the child an empty stdin and an unblocked signal mask, and enforces its timeout and StreamTooLong" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var map = try environmentWith(a, "SPAWN_PROBE", "unused");
    const environment: Environment = .{ .map = &map };
    // `cat` sees end of file at once; a TERM the shell sends itself is not blocked.
    const ended = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "cat; kill -TERM $$; exit 0" }, .environment = environment });
    try std.testing.expectEqual(std.process.Child.Term{ .signal = .TERM }, ended.term);
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(50), .clock = .awake } };
    try std.testing.expectError(error.Timeout, run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "sleep 5" }, .environment = environment, .timeout = timeout }));
    try std.testing.expectError(error.StreamTooLong, run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "echo 0123456789" }, .environment = environment, .stdout_limit = .limited(4) }));
}

// spec-case: NEW-CORE-SPAWN-1
test "failed maps a child's errno to the std.process error, SystemResources and the fd quotas included" {
    try std.testing.expectEqual(error.SystemResources, failed(@backingInt(linux.E.NOMEM)));
    try std.testing.expectEqual(error.ProcessFdQuotaExceeded, failed(@backingInt(linux.E.MFILE)));
    try std.testing.expectEqual(error.SystemFdQuotaExceeded, failed(@backingInt(linux.E.NFILE)));
    try std.testing.expectEqual(error.InvalidExe, failed(@backingInt(linux.E.NOEXEC)));
    try std.testing.expectEqual(error.Unexpected, failed(@backingInt(linux.E.SPIPE)));
}
