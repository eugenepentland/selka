//! The build graph's environment tool, `build-env` (ENV-PROJECTION-1,
//! ENV-PROJECTION-2): one definition both keys the environment a cached test
//! verdict depends on and projects the environment its command runs in, so a
//! variable that is not keyed cannot reach a test ("run what you key",
//! `docs/tooling/environment-identity.md`).
//!
//! Like `build_identity.zig`, the file has two halves. `tool` runs in
//! `build.zig`'s configure phase and only declares the host executable; `main`
//! is the same file compiled for the build host and run in the make phase:
//!
//! - `build-env digest OUT TOOL...` writes the environment manifest to `OUT`:
//!   the host-scope digest of `environment_identity.zig` over the live
//!   environment and the named tools on the first line, then the keyed
//!   `NAME=VALUE` lines and one `tool:NAME=SHA256` line per tool. A `TOOL` is
//!   `NAME=PATH`, or a bare `NAME` that is resolved on the live `PATH` here, at
//!   make time, so the configure phase never bakes a tool location.
//! - `build-env project -- CMD ARGS...` runs `CMD ARGS...` with only the
//!   variables the contract lets a child receive. With a positive
//!   `SELKA_STEP_DEADLINE_SECONDS` it starts the command in its own process
//!   group, kills that group when the deadline passes, prints one line naming
//!   the command and exits 124. Otherwise it replaces itself, keeping this
//!   process's pid, exit status and resource accounting. It exits with status 2
//!   when `CMD` cannot be executed.
//!
//! The parsing, projection and manifest rendering are pure functions in
//! `src/build_env_rules.zig`, tested from the unit root.
const std = @import("std");
const identity = @import("src/environment_identity.zig");
const rules = @import("src/build_env_rules.zig");

const STEP_DEADLINE_ENVIRONMENT = "SELKA_STEP_DEADLINE_SECONDS";
const DEFAULT_STEP_DEADLINE_SECONDS = 1800.0;
const DEADLINE_EXIT_STATUS = 124;
const POLL_MILLISECONDS = 100;

var interrupted = std.atomic.Value(u8).init(0);

/// Record the first termination signal so the run loop can kill the child group.
fn forwardSignal(number: std.posix.SIG) callconv(.c) void {
    interrupted.store(@truncate(@backingInt(number)), .monotonic);
}

/// Declare the `build-env` host executable. It is compiled for the build
/// host, optimized because `digest` hashes the whole Zig toolchain binary on
/// every build, and run by `build.zig` around every cached test step.
pub fn tool(b: *std.Build, compile_rss: u64) *std.Build.Step.Compile {
    return b.addExecutable(.{ .max_rss = compile_rss, .name = "build-env", .root_module = b.createModule(.{
        .root_source_file = b.path("build_env.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) });
}

/// Make-phase entry point: `build-env digest OUT TOOL...` or
/// `build-env project -- CMD ARGS...`.
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "run-child")) {
        // The deadline path re-executes this binary as the child's process-group
        // leader, so the command inherits a parent-death signal across exec and
        // is killed when the supervising build-env is SIGKILLed.
        try parentDeathSignal();
        const child = if (args.len >= 3 and std.mem.eql(u8, args[2], "--")) args[3..] else args[2..];
        if (child.len == 0) fail("run-child requires a command", .{});
        const failure = std.process.replace(init.io, .{ .argv = child });
        fail("cannot execute {s}: {t}", .{ child[0], failure });
    }
    const command = rules.parse(args[1..]) orelse fail("usage: build-env digest OUT [NAME[=PATH]...] | build-env project -- CMD [ARGS...]", .{});
    switch (command) {
        .digest => |request| try writeDigest(init, request.out, request.tools),
        .project => |argv| {
            var projected = std.process.Environ.Map.init(a);
            try rules.project(init.environ_map, &projected);
            try rules.isolateStageStore(&projected);
            const seconds = try stepDeadlineSeconds(init);
            if (seconds == 0) {
                const failure = std.process.replace(init.io, .{ .argv = argv, .environ_map = &projected });
                fail("cannot execute {s}: {t}", .{ argv[0], failure });
            }
            std.process.exit(try runWithDeadline(init, argv, &projected, seconds));
        },
    }
}

/// The positive wall-clock deadline for one step, `0` when it is turned off.
fn stepDeadlineSeconds(init: std.process.Init) !f64 {
    const text = init.environ_map.get(STEP_DEADLINE_ENVIRONMENT) orelse return DEFAULT_STEP_DEADLINE_SECONDS;
    const seconds = std.fmt.parseFloat(f64, text) catch fail("{s} is not a number: {s}", .{ STEP_DEADLINE_ENVIRONMENT, text });
    if (!std.math.isFinite(seconds) or seconds < 0) fail("{s} must be a finite, non-negative number of seconds: {s}", .{ STEP_DEADLINE_ENVIRONMENT, text });
    return seconds;
}

/// Run one command in its own process group and kill that group at the deadline.
fn runWithDeadline(init: std.process.Init, argv: []const []const u8, projected: *std.process.Environ.Map, seconds: f64) !u8 {
    var action: std.posix.Sigaction = .{ .handler = .{ .handler = forwardSignal }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(.TERM, &action, null);
    std.posix.sigaction(.INT, &action, null);
    std.posix.sigaction(.HUP, &action, null);
    const self = try std.Io.Dir.cwd().realPathFileAlloc(init.io, "/proc/self/exe", init.arena.allocator());
    const supervised = try init.arena.allocator().alloc([]const u8, argv.len + 3);
    supervised[0] = self;
    supervised[1] = "run-child";
    supervised[2] = "--";
    @memcpy(supervised[3..], argv);
    const child = try std.process.spawn(init.io, .{ .argv = supervised, .environ_map = projected, .pgid = 0 });
    const pid = child.id orelse fail("cannot identify the child process of {s}", .{argv[0]});
    const started = std.Io.Clock.Timestamp.now(init.io, .awake);
    const limit: i96 = @intFromFloat(seconds * std.time.ns_per_s);
    var status: i32 = undefined;
    while (true) {
        const number = interrupted.load(.monotonic);
        if (number != 0) {
            killGroup(pid);
            _ = std.os.linux.wait4(pid, &status, 0, null);
            std.process.exit(128 +| number);
        }
        const waited = std.os.linux.wait4(pid, &status, std.os.linux.W.NOHANG, null);
        switch (std.os.linux.errno(waited)) {
            .SUCCESS => {
                if (waited != 0) return exitStatus(status);
            },
            .INTR => continue,
            else => |failure| fail("waiting for {s} failed: {t}", .{ argv[0], failure }),
        }
        const elapsed = std.Io.Clock.Timestamp.now(init.io, .awake).raw.nanoseconds - started.raw.nanoseconds;
        if (elapsed >= limit) {
            std.debug.print("step deadline: {s} ran {d:.1} s (limit {d:.1} s); killed\n", .{
                argv[0], secondsFloat(elapsed), seconds,
            });
            killGroup(pid);
            _ = std.os.linux.wait4(pid, &status, 0, null);
            return DEADLINE_EXIT_STATUS;
        }
        std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(POLL_MILLISECONDS), .awake) catch {};
    }
}

/// Ask the kernel to SIGKILL this process when its parent dies.
fn parentDeathSignal() !void {
    _ = std.posix.prctl(.SET_PDEATHSIG, .{@backingInt(std.posix.SIG.KILL)}) catch |err| fail("cannot set parent-death signal: {t}", .{err});
}

/// Kill the child's whole process group; it was started as the group leader.
fn killGroup(pid: std.os.linux.pid_t) void {
    _ = std.os.linux.errno(std.os.linux.kill(-pid, .KILL));
}

/// Map a waited-for status to the shell's exit-status convention.
fn exitStatus(status: i32) u8 {
    const code: u32 = @bitCast(status);
    if (std.os.linux.W.IFEXITED(code)) return std.os.linux.W.EXITSTATUS(code);
    if (std.os.linux.W.IFSIGNALED(code)) return 128 +| @as(u8, @truncate(@backingInt(std.os.linux.W.TERMSIG(code))));
    return 1;
}

/// A monotonic duration in seconds as a float, for the one deadline line.
fn secondsFloat(nanoseconds: i96) f64 {
    return @as(f64, @floatFromInt(nanoseconds)) / @as(f64, std.time.ns_per_s);
}

/// Report a usage or execution failure on standard error and exit with status 2.
fn fail(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print("build-env: " ++ format ++ "\n", arguments);
    std.process.exit(2);
}

/// Write the manifest of the live environment and the named tools to `out`.
fn writeDigest(init: std.process.Init, out: []const u8, requests: []const []const u8) !void {
    const a = init.arena.allocator();
    const variables = rules.variablesOf(init.environ_map, try a.alloc(identity.Variable, init.environ_map.count()));
    const tools = try a.alloc(identity.Tool, requests.len);
    for (requests, 0..) |argument, index| {
        const request = rules.toolRequest(argument).?;
        for (tools[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.name, request.name)) fail("tool {s} is named twice", .{request.name});
        }
        const path = request.path orelse if (std.mem.eql(u8, request.name, rules.lake_tool)) lakePath(init) else searchPath(init, request.name);
        tools[index] = .{ .name = request.name, .digest = if (path) |file| try fileDigest(init, file) else rules.absent_tool };
    }
    var text: std.Io.Writer.Allocating = .init(a);
    try rules.writeManifest(&text.writer, variables, tools);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = text.written() });
}

/// The Lean build tool: the first executable of `SELKA_LAKE` and `$HOME/.elan/bin/lake`, else one named `lake` on the live
/// `PATH`, else null (the manifest then records it as absent and the `ownership-proof` action fails with a message).
fn lakePath(init: std.process.Init) ?[]const u8 {
    const a = init.arena.allocator();
    const candidates = rules.lakeCandidates(a, init.environ_map.get("SELKA_LAKE"), init.environ_map.get("HOME")) catch return null;
    for (candidates) |candidate| {
        const stat = std.Io.Dir.cwd().statFile(init.io, candidate, .{}) catch continue;
        if (stat.kind != .file) continue;
        std.Io.Dir.cwd().access(init.io, candidate, .{ .execute = true }) catch continue;
        return candidate;
    }
    return searchPath(init, "lake");
}

/// The first executable `name` in a directory of the live `PATH`, as a shell
/// would find it, or null when there is none.
fn searchPath(init: std.process.Init, name: []const u8) ?[]const u8 {
    const a = init.arena.allocator();
    var directories = std.mem.splitScalar(u8, init.environ_map.get("PATH") orelse return null, ':');
    while (directories.next()) |directory| {
        const candidate = std.fs.path.join(a, &.{ if (directory.len == 0) "." else directory, name }) catch return null;
        const stat = std.Io.Dir.cwd().statFile(init.io, candidate, .{}) catch continue;
        if (stat.kind != .file) continue;
        std.Io.Dir.cwd().access(init.io, candidate, .{ .execute = true }) catch continue;
        return candidate;
    }
    return null;
}

/// Lowercase hex SHA-256 of the file at `path`, or `absent_tool` when it cannot be read.
fn fileDigest(init: std.process.Init, path: []const u8) ![]const u8 {
    const file = std.Io.Dir.cwd().openFile(init.io, path, .{}) catch return rules.absent_tool;
    defer file.close(init.io);
    var buffer: [1 << 16]u8 = undefined;
    var reader = file.reader(init.io, &buffer);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var chunk: [1 << 16]u8 = undefined;
    while (true) {
        const count = reader.interface.readSliceShort(&chunk) catch return rules.absent_tool;
        if (count == 0) break;
        hash.update(chunk[0..count]);
    }
    var bytes: [32]u8 = undefined;
    hash.final(&bytes);
    return try init.arena.allocator().dupe(u8, &std.fmt.bytesToHex(bytes, .lower));
}
