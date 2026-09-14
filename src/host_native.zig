//! Build one checked guest natively and run it in a private child process.
//! A Zig host application owns no interpreter: it compiles its guest and a
//! trusted C provider into a single executable, hands that executable one
//! invocation's bytes through private files, and reads the result back.
const std = @import("std");
const qbe_build = @import("qbe_build");
const tools = @import("host_tools");
/// Build, transport and guest-outcome failures of one native invocation.
pub const Error = qbe_build.Error || std.Io.Dir.CreateDirError || error{ GuestTrap, InvalidGuestResult };
/// Bound on what one child may leave on a captured stream before publication.
pub const stream_limit = 256 * 1024 * 1024;
/// Private per-invocation build products and transport files.
const Files = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    fn absolute(self: Files, path: []const u8) Error![]const u8 {
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(self.io, ".", self.allocator);
        return std.fs.path.resolve(self.allocator, &.{ cwd, path });
    }
    fn temporary(self: Files, parent: []const u8) Error![]const u8 {
        try std.Io.Dir.cwd().createDirPath(self.io, parent);
        var random: [16]u8 = undefined;
        std.Io.random(self.io, &random);
        const name = try std.fmt.allocPrint(self.allocator, ".guest-{s}", .{std.fmt.bytesToHex(random, .lower)});
        const path = try std.fs.path.join(self.allocator, &.{ parent, name });
        try std.Io.Dir.cwd().createDir(self.io, path, .default_dir);
        return path;
    }
    fn remove(self: Files, path: []const u8) void {
        std.Io.Dir.cwd().deleteTree(self.io, path) catch return;
    }
};
/// What one host application asks the native build driver to produce.
pub const Request = struct {
    project: []const u8,
    provider: []const u8,
    cache: ?[]const u8 = null,
    qbe: []const u8 = "qbe",
    zig: []const u8 = "zig",
};
/// One built guest executable and the private directory that holds it.
pub const Program = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: std.process.Environ.Map,
    directory: []const u8,
    path: []const u8,
    /// Compile the checked guest and the trusted provider into one executable.
    /// The host's own environment is inherited so the provider can be told where
    /// this invocation's bytes live without spending the guest's command line.
    pub fn build(process: std.process.Init, request: Request) Error!Program {
        const files: Files = .{ .allocator = process.arena.allocator(), .io = process.io };
        const cache = try cacheDirectory(files, process.environ_map, request.cache);
        const directory = try files.temporary(cache);
        errdefer files.remove(directory);
        var environment = try process.environ_map.clone(files.allocator);
        errdefer environment.deinit();
        var program: Program = .{
            .allocator = files.allocator,
            .io = files.io,
            .environment = environment,
            .directory = directory,
            .path = try std.fs.path.join(files.allocator, &.{ directory, "program" }),
        };
        try program.link(process, request, cache);
        return program;
    }
    fn link(self: *Program, process: std.process.Init, request: Request, cache: []const u8) Error!void {
        const files: Files = .{ .allocator = self.allocator, .io = self.io };
        const source = try self.file("provider.c");
        try self.write(source, request.provider);
        const entry = try std.fs.path.join(self.allocator, &.{ try files.absolute(request.project), "main.my" });
        const status = try qbe_build.run(process, &.{
            entry,   "--project",                                     "--provider",  source,
            "-o",    self.path,                                       "--cache-dir", cache,
            "--qbe", located(self.io, request.qbe, "qbe", tools.qbe), "--zig",       located(self.io, request.zig, "zig", tools.zig),
        });
        if (status != 0) return error.NativeToolFailed;
    }
    /// Remove every private file; nothing one host invocation produced outlives it.
    pub fn deinit(self: *Program) void {
        self.environment.deinit();
        const files: Files = .{ .allocator = self.allocator, .io = self.io };
        files.remove(self.directory);
    }
    /// Tell the trusted provider one thing about this invocation.
    pub fn set(self: *Program, name: []const u8, value: []const u8) Error!void {
        try self.environment.put(name, value);
    }
    /// Tell the trusted provider one decimal budget or count.
    pub fn setNumber(self: *Program, name: []const u8, value: u64) Error!void {
        try self.set(name, try std.fmt.allocPrint(self.allocator, "{d}", .{value}));
    }
    /// Name one private transport file beside the built executable.
    pub fn file(self: Program, name: []const u8) Error![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.directory, name });
    }
    /// Write one transport input the trusted provider will read back.
    pub fn write(self: Program, path: []const u8, data: []const u8) Error!void {
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = data });
    }
    /// Read one file the guest produced; bytes have this invocation's lifetime.
    pub fn read(self: Program, path: []const u8) Error![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .unlimited);
    }
    /// Run the guest once and report its entry-point result. A trapped or
    /// otherwise failing child leaves its diagnostics on the host's stderr.
    pub fn invoke(self: *Program, arguments: []const []const u8) Error!i64 {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.append(self.allocator, self.path);
        try argv.appendSlice(self.allocator, arguments);
        const result = try std.process.run(self.allocator, self.io, .{
            .argv = argv.items,
            .environ_map = &self.environment,
            .stdout_limit = .limited(stream_limit),
            .stderr_limit = .limited(stream_limit),
        });
        try std.Io.File.stderr().writeStreamingAll(self.io, result.stderr);
        if (result.term != .exited or result.term.exited != 0) return error.GuestTrap;
        return outcome(result.stdout);
    }
};
/// A host application runs from an arbitrary working directory, so its shared
/// object cache lives with the user's other caches rather than beside the guest.
fn cacheDirectory(files: Files, environ: *const std.process.Environ.Map, chosen: ?[]const u8) Error![]const u8 {
    if (chosen) |path| return files.absolute(path);
    if (environ.get("XDG_CACHE_HOME")) |base| return std.fs.path.join(files.allocator, &.{ base, "mylang-hosts" });
    const home = environ.get("HOME") orelse return files.absolute(".mylang-cache/qbe");
    return std.fs.path.join(files.allocator, &.{ home, ".cache", "mylang-hosts" });
}
/// Prefer an explicitly named tool, then the one this build produced, so an
/// uninstalled host still links a guest and an installed one still uses `PATH`.
fn located(io: std.Io, chosen: []const u8, name: []const u8, fallback: []const u8) []const u8 {
    if (!std.mem.eql(u8, chosen, name)) return chosen;
    std.Io.Dir.cwd().access(io, fallback, .{ .execute = true }) catch return chosen;
    return fallback;
}
/// A native executable reports its entry-point result as its final output line.
pub fn outcome(stdout: []const u8) error{InvalidGuestResult}!i64 {
    const trimmed = std.mem.trimEnd(u8, stdout, "\n");
    const start = if (std.mem.lastIndexOfScalar(u8, trimmed, '\n')) |index| index + 1 else 0;
    return std.fmt.parseInt(i64, trimmed[start..], 10) catch error.InvalidGuestResult;
}
