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
    /// The soft `RLIMIT_AS` the child starts under, never above its hard limit;
    /// null leaves it the limit this process runs under. Only the child changes: this
    /// process keeps its own ceiling, which is how a compiler that bounds itself
    /// still hands a test program the caller's address space.
    address_space: ?u64 = null,
    /// The directory the child starts in; null keeps this process's own.
    cwd: ?[]const u8 = null,
    /// End the child with SIGKILL when the thread that started it ends, which is when this process is killed: the
    /// child asks the kernel for that signal (`PR_SET_PDEATHSIG`) before `execve`, so a program the caller waits for
    /// never outlives it. Only for a child the starting thread waits for itself.
    die_with_parent: bool = false,
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
    /// The child's soft `RLIMIT_AS`, as `Options.address_space` says.
    address_space: ?u64 = null,
    /// The directory the child starts in, as `Options.cwd` says.
    cwd: ?[]const u8 = null,
    /// Whether the child dies with this process, as `Options.die_with_parent` says.
    die_with_parent: bool = false,
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
    /// The address-space limit the child installs just before `execve`, if any.
    limit: ?linux.rlimit = null,
    /// The directory the child changes to just before `execve`, if any.
    cwd: ?[*:0]const u8 = null,
    /// The process that started the child when it must die with it (`Options.die_with_parent`), or 0. The child
    /// compares it with its own parent after asking for the signal, so a parent that ended in between is seen.
    parent: linux.pid_t = 0,
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
    if (options.address_space) |wanted| request.limit = childLimit(wanted);
    if (options.cwd) |directory| request.cwd = (try a.dupeSentinel(u8, directory, 0)).ptr;
    if (options.die_with_parent) request.parent = linux.getpid();
    var attempt: u5 = 0;
    const pid = while (true) : (attempt += 1) {
        const child = try launch(&request, &stack);
        if (request.failure == 0) break child;
        reap(child);
        // ETXTBSY: another thread's child, between its clone and its execve, still
        // holds a descriptor this program was just written through. That window
        // closes at its execve, so wait it out, briefly and a bounded number of times.
        if (request.failure != @backingInt(linux.E.TXTBSY) or attempt == busy_retries) return failed(request.failure);
        request.failure = 0;
        pause(attempt);
    };
    pipes.close(.child);
    return .{
        .id = pid,
        .thread_handle = {},
        .stdin = pipes.parentEnd(0),
        .stdout = pipes.parentEnd(1),
        .stderr = pipes.parentEnd(2),
        .request_resource_usage_statistics = false,
    };
}

/// The `RLIMIT_AS` pair a child installs for a wanted soft limit: the wanted size,
/// held to this process's hard limit, which the child keeps. Null when the limit
/// cannot be read, and the child then keeps what it inherited.
fn childLimit(wanted: u64) ?linux.rlimit {
    var current: linux.rlimit = undefined;
    if (linux.errno(linux.getrlimit(.AS, &current)) != .SUCCESS) return null;
    return .{ .cur = @min(wanted, current.max), .max = current.max };
}

/// How many times a start refused with ETXTBSY is tried again, after pauses of
/// 0.25 ms doubling each time (about a quarter second in all).
const busy_retries = 10;

/// Start the request's child; its pid. The child has called `execve`, or exited
/// with the errno it left in `request.failure`.
fn launch(request: *Request, stack: *[stack_size]u8) Error!linux.pid_t {
    const blocked = linux.sigfillset();
    _ = linux.sigprocmask(linux.SIG.SETMASK, &blocked, &request.mask);
    const flags: u32 = linux.CLONE.VM | linux.CLONE.VFORK | @backingInt(linux.SIG.CHLD);
    const started = linux.clone(start, @intFromPtr(stack) + stack.len, flags, @intFromPtr(request), null, 0, null);
    _ = linux.sigprocmask(linux.SIG.SETMASK, &request.mask, null);
    if (linux.errno(started) != .SUCCESS) return error.SystemResources;
    return @intCast(started);
}

/// Wait for a child that exited before `execve`.
fn reap(pid: linux.pid_t) void {
    var status: i32 = undefined;
    while (linux.errno(linux.wait4(pid, &status, 0, null)) == .INTR) {}
}

/// Pause before start attempt `attempt + 1`: 0.25 ms doubled `attempt` times.
fn pause(attempt: u5) void {
    const nanoseconds: u64 = @as(u64, 250_000) << attempt;
    const delay: linux.timespec = .{ .sec = @intCast(nanoseconds / std.time.ns_per_s), .nsec = @intCast(nanoseconds % std.time.ns_per_s) };
    _ = linux.nanosleep(&delay, null);
}

/// `std.process.run` with `spawn`: start the child with an empty stdin, collect its
/// stdout and stderr, and wait for it. A timeout or an output limit kills it.
pub fn run(gpa: std.mem.Allocator, io: std.Io, options: RunOptions) std.process.RunError!std.process.RunResult {
    var child = try spawn(gpa, .{ .argv = options.argv, .environment = options.environment, .stdout = .pipe, .stderr = .pipe, .address_space = options.address_space, .cwd = options.cwd, .die_with_parent = options.die_with_parent });
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
    // Only this child's limit changes; a refusal leaves it the inherited one.
    if (request.limit) |*limit| _ = linux.setrlimit(.AS, limit);
    // The child shares no filesystem state with its parent (no CLONE_FS), so only it moves.
    if (request.cwd) |directory| {
        const moved = linux.chdir(directory);
        if (linux.errno(moved) != .SUCCESS) leave(request, moved);
    }
    if (request.parent != 0) dieWithParent(request);
    leave(request, execute(request));
}

/// Ask the kernel for a SIGKILL when the starting thread ends, the runtime's own way (`core_process.c`, `core_test.c`),
/// and leave if that thread already ended: it did so before the request, so nobody waits for this child.
fn dieWithParent(request: *Request) void {
    const asked = linux.prctl(@backingInt(linux.PR.SET_PDEATHSIG), @backingInt(linux.SIG.KILL), 0, 0, 0);
    if (linux.errno(asked) != .SUCCESS) leave(request, asked);
    if (linux.getppid() != request.parent) leave(request, @bitCast(-@as(isize, @backingInt(linux.E.SRCH))));
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
    try std.testing.expectError(error.FileNotFound, spawn(a, .{ .argv = &.{"selka-no-such-program"}, .environment = environment }));
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

/// A copy of `sh`, found on PATH, at `path` and executable.
fn copyShell(a: std.mem.Allocator, map: *const std.process.Environ.Map, path: []const u8) !void {
    var directories = std.mem.tokenizeScalar(u8, map.get("PATH") orelse "", ':');
    const shell = while (directories.next()) |directory| {
        const candidate = try std.fs.path.join(a, &.{ directory, "sh" });
        std.Io.Dir.cwd().access(std.testing.io, candidate, .{}) catch continue;
        break candidate;
    } else return error.FileNotFound;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, shell, a, .limited(16 << 20));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes, .flags = .{ .permissions = .executable_file } });
}

/// Close `file` after a short pause, from another thread.
fn closeLater(file: std.Io.File) void {
    pause(3);
    file.close(std.testing.io);
}

// spec-case: NEW-CORE-SPAWN-1
test "spawn retries a FileBusy start until the writer's descriptor is gone, and reports FileBusy while it stays" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var map = try environmentWith(a, "SPAWN_PROBE", "unused");
    const program = try std.fs.path.join(a, &.{ root, "busy" });
    try copyShell(a, &map, program);
    // A descriptor open for writing makes every start ETXTBSY.
    const writer = try std.Io.Dir.cwd().openFile(std.testing.io, program, .{ .mode = .write_only });
    try std.testing.expectError(error.FileBusy, spawn(a, .{ .argv = &.{ program, "-c", "exit 0" }, .environment = .{ .map = &map } }));
    // Once the writer closes it, a retry starts the program.
    const closer = try std.Thread.spawn(.{}, closeLater, .{writer});
    defer closer.join();
    const result = try run(a, std.testing.io, .{ .argv = &.{ program, "-c", "exit 4" }, .environment = .{ .map = &map } });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 4 }, result.term);
}

// spec-case: MEMORY-HOST-GUEST-1
test "a child starts under the address space it is given while its parent keeps its own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var map = try environmentWith(a, "SPAWN_PROBE", "unused");
    const before = try std.posix.getrlimit(.AS);
    // 1 GiB is 1048576 KiB, the unit `ulimit -v` prints.
    const bounded = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "ulimit -S -v" }, .environment = .{ .map = &map }, .address_space = 1 << 30 });
    try std.testing.expectEqualStrings("1048576\n", bounded.stdout);
    // Asking for more than the hard limit grants the hard limit, never more.
    const hard = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "ulimit -S -v; ulimit -H -v" }, .environment = .{ .map = &map }, .address_space = std.math.maxInt(u64) });
    var lines = std.mem.splitScalar(u8, hard.stdout, '\n');
    const soft = lines.next().?;
    try std.testing.expectEqualStrings(soft, lines.next().?);
    // The parent's own limit did not move, and a child given nothing inherits it.
    const after = try std.posix.getrlimit(.AS);
    try std.testing.expectEqual(before.cur, after.cur);
    try std.testing.expectEqual(before.max, after.max);
    const inherited = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "ulimit -S -v" }, .environment = .{ .map = &map } });
    try std.testing.expectEqual(before.cur == std.math.maxInt(u64), std.mem.eql(u8, inherited.stdout, "unlimited\n"));
}

// spec-case: NEW-CORE-SPAWN-1
test "a child starts in the directory it is given and its parent stays where it was" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var map = try environmentWith(a, "SPAWN_PROBE", "unused");
    const here = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", a);
    const moved = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "pwd -P" }, .environment = .{ .map = &map }, .cwd = root });
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}\n", .{root}), moved.stdout);
    const top = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "pwd -P" }, .environment = .{ .map = &map }, .cwd = "/" });
    try std.testing.expectEqualStrings("/\n", top.stdout);
    const kept = try run(a, std.testing.io, .{ .argv = &.{ "sh", "-c", "pwd -P" }, .environment = .{ .map = &map } });
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}\n", .{here}), kept.stdout);
    try std.testing.expectEqualStrings(here, try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", a));
    try std.testing.expectError(error.FileNotFound, spawn(a, .{ .argv = &.{"sh"}, .environment = .{ .map = &map }, .cwd = try std.fs.path.join(a, &.{ root, "no-such-directory" }) }));
}

/// Start `sleep 30` the way a caller that does not wait does, and end this thread, leaving the child's number in `pid`.
fn startAndLeave(gpa: std.mem.Allocator, map: *const std.process.Environ.Map, die: bool, pid: *std.atomic.Value(i32)) void {
    const child = spawn(gpa, .{ .argv = &.{ "sleep", "30" }, .environment = .{ .map = map }, .die_with_parent = die }) catch return;
    pid.store(child.id.?, .seq_cst);
}

/// The state letter of process `pid` in `/proc`, or 'X' when there is no such process: 'Z' is a zombie, which has ended.
fn stateOf(pid: i32) u8 {
    var path: [64]u8 = undefined;
    var text: [512]u8 = undefined;
    const name = std.fmt.bufPrint(&path, "/proc/{d}/stat", .{pid}) catch return 'X';
    const read = std.Io.Dir.cwd().readFile(std.testing.io, name, &text) catch return 'X';
    const close = std.mem.lastIndexOfScalar(u8, read, ')') orelse return 'X';
    return if (close + 2 < read.len) read[close + 2] else 'X';
}

/// Whether process `pid` has ended (or is a zombie) within `milliseconds`, looked at every 50 ms.
fn endsWithin(pid: i32, milliseconds: u64) bool {
    var waited: u64 = 0;
    while (waited <= milliseconds) : (waited += 50) {
        const state = stateOf(pid);
        if (state == 'Z' or state == 'X') return true;
        const delay: linux.timespec = .{ .sec = 0, .nsec = 50_000_000 };
        _ = linux.nanosleep(&delay, null);
    }
    return false;
}

// spec-case: NEW-CORE-SPAWN-1
test "a child started with die_with_parent ends when the thread that started it ends, and one started without it stays" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var map = try environmentWith(arena.allocator(), "SPAWN_PROBE", "unused");
    var dying: std.atomic.Value(i32) = .init(0);
    var staying: std.atomic.Value(i32) = .init(0);
    (try std.Thread.spawn(.{}, startAndLeave, .{ std.testing.allocator, &map, true, &dying })).join();
    (try std.Thread.spawn(.{}, startAndLeave, .{ std.testing.allocator, &map, false, &staying })).join();
    try std.testing.expect(dying.load(.seq_cst) != 0 and staying.load(.seq_cst) != 0);
    try std.testing.expect(endsWithin(dying.load(.seq_cst), 5000));
    try std.testing.expect(!endsWithin(staying.load(.seq_cst), 500));
    std.posix.kill(staying.load(.seq_cst), .KILL) catch {};
    try std.testing.expect(endsWithin(staying.load(.seq_cst), 5000));
}
