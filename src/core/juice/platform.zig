//! Linux process and executable services. Host-specific capture stays behind this module.
const std = @import("std");
const builtin = @import("builtin");
const d = @import("data.zig");
const C = d.Context;
const V = d.Value;
const linux = std.os.linux;
/// Fail explicitly on an unsupported capture host; reports need no host adapter.
pub fn supported(c: *C) d.Error!void {
    return supportedImpl(c) catch |err| d.failure(c, err);
}
fn supportedImpl(c: *C) !void {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return c.fail("capture currently supports Linux x86_64; compare, validate and calibrate use portable data");
}
/// Existing absolute path, including symlink resolution.
pub fn real(c: *C, path: []const u8) d.Error![]const u8 {
    return realImpl(c, path) catch |err| d.failure(c, err);
}
fn realImpl(c: *C, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().realPathFileAlloc(c.io, path, c.a);
}
/// Absolute path even for an output that does not yet exist.
pub fn absolute(c: *C, path: []const u8) d.Error![]const u8 {
    return absoluteImpl(c, path) catch |err| d.failure(c, err);
}
fn absoluteImpl(c: *C, path: []const u8) ![]const u8 {
    const expanded = if (std.mem.startsWith(u8, path, "~/")) try c.join(&.{ c.env.get("HOME") orelse return error.InvalidExperiment, path[2..] }) else path;
    return std.fs.path.resolve(c.a, &.{ try real(c, "."), expanded });
}
/// Resolve a tool using the declared environment, never a shell.
pub fn executable(c: *C, name: []const u8, env: *const std.process.Environ.Map) d.Error![]const u8 {
    return executableImpl(c, name, env) catch |err| d.failure(c, err);
}
fn executableImpl(c: *C, name: []const u8, env: *const std.process.Environ.Map) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return real(c, name);
    var paths = std.mem.splitScalar(u8, env.get("PATH") orelse "", ':');
    while (paths.next()) |part| {
        const path = try c.join(&.{ if (part.len == 0) "." else part, name });
        std.Io.Dir.cwd().access(c.io, path, .{ .execute = true }) catch continue;
        return real(c, path);
    }
    return c.fail(try std.fmt.allocPrint(c.a, "executable unavailable: {s}", .{name}));
}
/// Tool bytes plus its human-readable version; the current compiler resolves to itself.
pub fn identity(c: *C, name: []const u8) d.Error!V {
    return identityImpl(c, name) catch |err| d.failure(c, err);
}
fn identityImpl(c: *C, name: []const u8) !V {
    const path = try executable(c, name, c.env);
    const result = try std.process.run(c.a, c.io, .{
        .argv = &.{
            path, "--version",
        },
        .timeout = .{
            .duration = .{
                .raw = .fromSeconds(15),
                .clock = .awake,
            },
        },
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(1 << 20),
    });
    const version = std.mem.trim(u8, try std.mem.concat(c.a, u8, &.{ result.stdout, result.stderr }), " \r\n\t");
    if (std.mem.eql(u8, path, c.self)) {
        return c.value(.{
            .path = path,
            .identity_kind = "selka-embedded-build-v1",
            .source_sha256 = @import("build_identity").compiler_identity,
            .architecture = @tagName(builtin.cpu.arch),
            .os = @tagName(builtin.os.tag),
            .abi = @tagName(builtin.abi),
            .version = version[0..@min(version.len, 4096)],
        });
    }
    return c.value(.{ .path = path, .sha256 = try c.fileHash(path), .version = version[0..@min(version.len, 4096)] });
}
/// Execution controls, including fixed directory, bounded time and optional CPU.
pub const Run = struct { argv: []const []const u8, cwd: []const u8, env: *const std.process.Environ.Map, prefix: []const u8, seconds: f64, cpu: ?usize = null };
fn elapsed(c: *C, start: std.Io.Timestamp) f64 {
    return @as(f64, @floatFromInt(start.durationTo(std.Io.Timestamp.now(c.io, .awake)).nanoseconds)) / std.time.ns_per_s;
}
fn endGroup(c: *C, child: *std.process.Child, pid: linux.pid_t) void {
    _ = linux.kill(-pid, .KILL);
    child.kill(c.io);
}
/// Run with file-backed output, a private process group, and a whole-process timeout.
pub fn run(c: *C, options: Run) d.Error!V {
    return runImpl(c, options) catch |err| d.failure(c, err);
}
fn runImpl(c: *C, options: Run) !V {
    try supported(c);
    if (!std.math.isFinite(options.seconds) or options.seconds <= 0) return error.InvalidExperiment;
    try c.mkdir(std.fs.path.dirname(options.prefix) orelse ".");
    const stdout = try std.fmt.allocPrint(c.a, "{s}.stdout", .{options.prefix});
    const stderr = try std.fmt.allocPrint(c.a, "{s}.stderr", .{options.prefix});
    var out = try std.Io.Dir.cwd().createFile(c.io, stdout, .{});
    defer out.close(c.io);
    var err = try std.Io.Dir.cwd().createFile(c.io, stderr, .{});
    defer err.close(c.io);
    const argv = try c.a.dupe([]const u8, options.argv);
    if (argv.len == 0) return error.InvalidExperiment;
    argv[0] = try executable(c, argv[0], options.env);
    const start = std.Io.Timestamp.now(c.io, .awake);
    var child = try spawnPinned(c, options, argv, out, err);
    const pid = child.id.?;
    defer endGroup(c, &child, pid);
    var status: i32 = 0;
    while (true) {
        const waited = linux.wait4(pid, &status, linux.W.NOHANG, null);
        if (linux.errno(waited) != .SUCCESS and linux.errno(waited) != .INTR) return c.fail("cannot wait for workload");
        if (waited == @as(usize, @intCast(pid))) {
            child.id = null;
            break;
        }
        if (elapsed(c, start) > options.seconds) return c.fail("incomplete run: timeout; process group killed, raw output retained");
        try std.Io.sleep(c.io, .fromMilliseconds(5), .awake);
    }
    const code: i64 = if (linux.W.IFEXITED(@bitCast(status))) linux.W.EXITSTATUS(@bitCast(status)) else -@as(i64, @intCast(status & 127));
    return c.value(.{ .exit_code = code, .wall_seconds = elapsed(c, start), .stdout_sha256 = try c.fileHash(stdout), .stderr_sha256 = try c.fileHash(stderr) });
}
// Linux affinity belongs to the calling thread and is inherited by fork/exec.
// Pin only during spawn and restore before waiting; no race with guest startup.
fn spawnPinned(c: *C, options: Run, argv: []const []const u8, out: std.Io.File, err: std.Io.File) !std.process.Child {
    var original: linux.cpu_set_t = undefined;
    if (linux.errno(linux.sched_getaffinity(0, @sizeOf(linux.cpu_set_t), &original)) != .SUCCESS) return c.fail("cannot read affinity");
    if (options.cpu) |cpu| {
        var mask: linux.cpu_set_t = @splat(0);
        const bytes = std.mem.asBytes(&mask);
        if (cpu >= bytes.len * 8) return error.InvalidExperiment;
        bytes[cpu / 8] |= @as(u8, 1) << @intCast(cpu % 8);
        try linux.sched_setaffinity(0, &mask);
    }
    const child = std.process.spawn(c.io, .{
        .argv = argv,
        .cwd = .{
            .path = options.cwd,
        },
        .environ_map = options.env,
        .stdin = .ignore,
        .stdout = .{
            .file = out,
        },
        .stderr = .{
            .file = err,
        },
        .pgid = 0,
    });
    linux.sched_setaffinity(0, &original) catch |restore_error| {
        if (child) |value| {
            var spawned = value;
            endGroup(c, &spawned, spawned.id.?);
        } else |_| {}
        return restore_error;
    };
    return child;
}
/// Copy bytes and executable permissions without leaving writable source aliases.
pub fn copy(c: *C, source: []const u8, target: []const u8) d.Error!void {
    return copyImpl(c, source, target) catch |err| d.failure(c, err);
}
fn copyImpl(c: *C, source: []const u8, target: []const u8) !void {
    try c.mkdir(std.fs.path.dirname(target) orelse ".");
    try std.Io.Dir.cwd().copyFile(source, .cwd(), target, c.io, .{});
}
/// Resolve paths within a root; reject escaping symbolic links.
pub fn inside(c: *C, root: []const u8, path: []const u8) d.Error![]const u8 {
    return insideImpl(c, root, path) catch |err| d.failure(c, err);
}
fn insideImpl(c: *C, root: []const u8, path: []const u8) ![]const u8 {
    try d.relative(path);
    const resolved = try real(c, try c.join(&.{ root, path }));
    const prefix = try std.fmt.allocPrint(c.a, "{s}/", .{root});
    if (!std.mem.startsWith(u8, resolved, prefix)) return c.fail("input or output symlink escapes the project");
    return resolved;
}
/// Explicit runtime environment with private, stable home and scratch paths.
pub fn environment(c: *C, work: []const u8, extra: V) d.Error!std.process.Environ.Map {
    return environmentImpl(c, work, extra) catch |err| d.failure(c, err);
}
fn environmentImpl(c: *C, work: []const u8, extra: V) !std.process.Environ.Map {
    var map: std.process.Environ.Map = .init(c.a);
    // This Linux adapter's default executable search path is an OS convention.
    try map.put("PATH", "/bin:/usr/bin");
    try map.put("LC_ALL", "C");
    try map.put("LANG", "C");
    try map.put("TZ", "UTC");
    try map.put("PWD", work);
    const home = try c.join(&.{ work, "home" });
    const temporary = try c.join(&.{ work, "tmp" });
    try c.mkdir(home);
    try c.mkdir(temporary);
    try map.put("HOME", home);
    try map.put("TMPDIR", temporary);
    for (try d.keys(c, extra)) |key| try map.put(key, try d.str(d.get(extra, key)));
    return map;
}
/// Hash the live build environment without persisting its secret values.
pub fn buildEnvironment(c: *C) d.Error!V {
    return buildEnvironmentImpl(c) catch |err| d.failure(c, err);
}
fn buildEnvironmentImpl(c: *C) !V {
    var map = d.object();
    var it = c.env.iterator();
    while (it.next()) |entry| {
        var skip = false;
        for ([_][]const u8{ "PWD", "OLDPWD", "SHLVL", "_", "JUICE_VALGRIND", "VALGRIND_LIB" }) |key| if (std.mem.eql(u8, key, entry.key_ptr.*)) {
            skip = true;
            break;
        };
        if (!skip) try d.put(c, &map, entry.key_ptr.*, d.string(entry.value_ptr.*));
    }
    return c.hash(map);
}
