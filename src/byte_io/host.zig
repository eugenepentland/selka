//! Trusted raw byte operations; all input interpretation belongs to the guest.
//! The operations themselves are compiled into the guest's own native executable
//! (`native_byte_io.c`); this module is the driver that builds that executable,
//! hands it one invocation's bytes, and decides what reaches the real stdout.
const std = @import("std");
const qbe_build = @import("qbe_build");
const tools = @import("host_tools");
const limits = @import("limits.zig");
const bulk = @import("bulk.zig");
/// The trusted provider translation unit linked into every guest executable.
pub const provider = @embedFile("native_byte_io.c");
/// Bound on what one child may leave on a captured stream before publication.
pub const stream_limit = 256 * 1024 * 1024;
/// Build, transport and guest-outcome failures of one native invocation.
pub const Error = qbe_build.Error || std.Io.Dir.CreateDirError ||
    std.Io.Dir.StatFileError || error{ GuestTrap, InvalidGuestResult };
/// Private per-invocation build products and byte transport files.
const Files = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    /// Resolve even a not-yet-created output against the current directory.
    fn absolute(self: Files, path: []const u8) ![]const u8 {
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(self.io, ".", self.allocator);
        return std.fs.path.resolve(self.allocator, &.{ cwd, path });
    }
    /// Private directories isolate concurrent runners and failed tool output.
    fn temporary(self: Files, parent: []const u8) ![]const u8 {
        try std.Io.Dir.cwd().createDirPath(self.io, parent);
        var random: [16]u8 = undefined;
        std.Io.random(self.io, &random);
        const name = try std.fmt.allocPrint(self.allocator, ".byte-io-{s}", .{std.fmt.bytesToHex(random, .lower)});
        const path = try std.fs.path.join(self.allocator, &.{ parent, name });
        try std.Io.Dir.cwd().createDir(self.io, path, .default_dir);
        return path;
    }
    fn write(self: Files, path: []const u8, data: []const u8) !void {
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = data });
    }
    fn read(self: Files, path: []const u8) ![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .unlimited);
    }
    fn remove(self: Files, path: []const u8) void {
        std.Io.Dir.cwd().deleteTree(self.io, path) catch return;
    }
    fn join(self: Files, parent: []const u8, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.allocator, &.{ parent, name });
    }
    /// Name the program, its bounded input, and its unpublished output together.
    fn triple(self: Files, parent: []const u8) ![3][]const u8 {
        return .{ try self.join(parent, "program"), try self.join(parent, "input"), try self.join(parent, "output") };
    }
};
/// Own one invocation's private build products and byte transport files.
pub const Session = struct {
    files: Files,
    environment: std.process.Environ.Map,
    cache: []const u8,
    directory: []const u8,
    program: []const u8,
    input: []const u8,
    published: []const u8,
    /// Create the private directory and describe this authority to the provider.
    pub fn init(process: std.process.Init, options: limits.Options) Error!Session {
        const files: Files = .{ .allocator = process.arena.allocator(), .io = process.io };
        const cache = try cacheDirectory(files, process.environ_map, options.tools.cache);
        const directory = try files.temporary(cache);
        errdefer files.remove(directory);
        var environment = try process.environ_map.clone(files.allocator);
        errdefer environment.deinit();
        const paths = try files.triple(directory);
        var session: Session = .{
            .files = files,
            .environment = environment,
            .cache = cache,
            .directory = directory,
            .program = paths[0],
            .input = paths[1],
            .published = paths[2],
        };
        try session.describe(options);
        return session;
    }
    /// Remove every private file; nothing an invocation produced outlives it.
    pub fn deinit(self: *Session) void {
        self.environment.deinit();
        self.files.remove(self.directory);
    }
    fn describe(self: *Session, options: limits.Options) !void {
        const a = self.files.allocator;
        try self.environment.put("MYLANG_BYTE_IO_INPUT", self.input);
        try self.environment.put("MYLANG_BYTE_IO_OUTPUT", self.published);
        const budgets = [_]u64{ options.output, options.execution.calls, options.execution.work };
        for ([_][]const u8{ "MYLANG_BYTE_IO_MAX_OUTPUT", "MYLANG_BYTE_IO_MAX_CALLS", "MYLANG_BYTE_IO_MAX_WORK" }, budgets) |name, budget| {
            try self.environment.put(name, try std.fmt.allocPrint(a, "{d}", .{budget}));
        }
        try options.grants.install(a, &self.environment);
    }
    /// Compile the checked guest and the trusted provider into one executable.
    /// A validated copied-block shape names the exact types the provider copies,
    /// so a differently shaped block never reaches a callback.
    pub fn compile(self: *Session, process: std.process.Init, options: limits.Options, shape: ?bulk.Shape) Error!void {
        if (shape) |names| {
            try self.environment.put("MYLANG_BYTE_IO_BLOCK_TYPE", names.record);
            try self.environment.put("MYLANG_BYTE_IO_ARRAY_TYPE", names.array);
        }
        const source = try self.files.join(self.directory, "native_byte_io.c");
        try self.files.write(source, provider);
        const entry = try self.files.join(try self.files.absolute(options.project), "main.my");
        const qbe = located(self.files.io, options.tools.qbe, "qbe", tools.qbe);
        const zig = located(self.files.io, options.tools.zig, "zig", tools.zig);
        const status = try qbe_build.run(process, &.{
            entry,         "--project", "--provider", source, "-o",    self.program,
            "--cache-dir", self.cache,  "--qbe",      qbe,    "--zig", zig,
        });
        if (status != 0) return error.NativeToolFailed;
    }
    /// Run the guest once against these bytes and report its entry-point result.
    pub fn invoke(self: *Session, bytes: []const u8, steps: u64) Error!i64 {
        const a = self.files.allocator;
        const io = self.files.io;
        try self.files.write(self.input, bytes);
        const result = try std.process.run(a, io, .{
            .argv = &.{ self.program, try std.fmt.allocPrint(a, "--max-steps={d}", .{steps}) },
            .environ_map = &self.environment,
            .stdout_limit = .limited(stream_limit),
            .stderr_limit = .limited(stream_limit),
        });
        try std.Io.File.stderr().writeStreamingAll(io, result.stderr);
        if (result.term != .exited or result.term.exited != 0) return error.GuestTrap;
        return outcome(result.stdout);
    }
    /// Read back the bytes the guest asked to publish during this invocation.
    pub fn output(self: *Session) Error![]const u8 {
        return self.files.read(self.published);
    }
};
/// A byte application runs from an arbitrary working directory, so its shared
/// object cache lives with the user's other caches rather than beside the guest.
fn cacheDirectory(files: Files, environ: *const std.process.Environ.Map, chosen: ?[]const u8) Error![]const u8 {
    if (chosen) |path| return files.absolute(path);
    if (environ.get("XDG_CACHE_HOME")) |base| return files.join(base, "mylang-io");
    const home = environ.get("HOME") orelse return files.absolute(".mylang-cache/qbe");
    return std.fs.path.join(files.allocator, &.{ home, ".cache", "mylang-io" });
}
/// Prefer an explicitly named tool, then the one this build produced, so an
/// uninstalled host still links a guest and an installed one still uses `PATH`.
fn located(io: std.Io, chosen: []const u8, name: []const u8, fallback: []const u8) []const u8 {
    if (!std.mem.eql(u8, chosen, name)) return chosen;
    std.Io.Dir.cwd().access(io, fallback, .{ .execute = true }) catch return chosen;
    return fallback;
}
/// A native executable reports its entry-point result as its final output line.
fn outcome(stdout: []const u8) error{InvalidGuestResult}!i64 {
    const trimmed = std.mem.trimEnd(u8, stdout, "\n");
    const start = if (std.mem.lastIndexOfScalar(u8, trimmed, '\n')) |index| index + 1 else 0;
    return std.fmt.parseInt(i64, trimmed[start..], 10) catch error.InvalidGuestResult;
}
test "a native guest result is the final output line and nothing else" {
    try std.testing.expectEqual(@as(i64, 0), try outcome("0\n"));
    try std.testing.expectEqual(@as(i64, -7), try outcome("printed\n-7\n"));
    try std.testing.expectError(error.InvalidGuestResult, outcome(""));
    try std.testing.expectError(error.InvalidGuestResult, outcome("nothing numeric\n"));
}
