//! Filesystem and child-process operations for native builds.
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;
/// Native filesystem, process, and allocation failures preserve their diagnostics.
pub const Error = std.Io.Dir.RealPathFileAllocError || std.Io.Dir.ReadFileAllocError ||
    std.Io.Dir.WriteFileError || std.Io.Dir.CreateDirPathError || std.Io.Dir.RenameError ||
    std.process.RunError || std.Io.File.Writer.Error || error{ ToolNotFound, NativeToolFailed };
/// A build owns temporary allocations until the command exits.
pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    arena: *std.heap.ArenaAllocator,
    parent: std.mem.Allocator,
    /// Own a stable child arena for every allocation made during this build.
    pub fn init(parent: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) Error!Context {
        const arena = try parent.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(parent);
        return .{ .allocator = arena.allocator(), .arena = arena, .parent = parent, .io = io, .environ = environ };
    }
    /// Release all build-lifetime paths, captured tool output, and fingerprints.
    pub fn deinit(self: *Context) void {
        self.arena.deinit();
        self.parent.destroy(self.arena);
        self.* = undefined;
    }
    /// Resolve even a not-yet-created output against the current directory.
    pub fn absolute(self: Context, path: []const u8) Error![]const u8 {
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(self.io, ".", self.allocator);
        return std.fs.path.resolve(self.allocator, &.{ cwd, path });
    }
    /// Resolve tool executables once so cache fingerprints match invoked tools.
    pub fn executable(self: Context, name: []const u8) Error![]const u8 {
        if (std.mem.indexOfScalar(u8, name, '/') != null) {
            if (!self.runnable(name)) return error.ToolNotFound;
            return std.Io.Dir.cwd().realPathFileAlloc(self.io, name, self.allocator);
        }
        var paths = std.mem.splitScalar(u8, self.environ.get("PATH") orelse "", ':');
        while (paths.next()) |path| {
            const candidate = try std.fs.path.join(self.allocator, &.{ path, name });
            if (!self.runnable(candidate)) continue;
            const resolved = std.Io.Dir.cwd().realPathFileAlloc(self.io, candidate, self.allocator) catch continue;
            return resolved;
        }
        const bundled = ".mylang-cache/toolchain/qbe";
        if (std.mem.eql(u8, name, "qbe") and self.runnable(bundled))
            return std.Io.Dir.cwd().realPathFileAlloc(self.io, bundled, self.allocator);
        return error.ToolNotFound;
    }
    fn runnable(self: Context, path: []const u8) bool {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        if (stat.kind != .file) return false;
        std.Io.Dir.cwd().access(self.io, path, .{ .execute = true }) catch return false;
        return true;
    }
    /// Read a build input; allocated bytes have command lifetime.
    pub fn read(self: Context, path: []const u8) Error![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .unlimited);
    }
    /// Hash exact tool or object contents rather than timestamps.
    pub fn fileHash(self: Context, path: []const u8) Error![]const u8 {
        const bytes = try self.read(path);
        return hash(self.allocator, bytes);
    }
    /// Write an input in an already-created private build directory.
    pub fn write(self: Context, path: []const u8, bytes: []const u8) Error!void {
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = bytes });
    }
    /// Create all parents for materialized bundled runtime inputs.
    pub fn mkdir(self: Context, path: []const u8) Error!void {
        try std.Io.Dir.cwd().createDirPath(self.io, path);
    }
    /// Private directories isolate concurrent compilers and failed tool output.
    pub fn temporary(self: Context, parent: []const u8) Error![]const u8 {
        var random: [16]u8 = undefined;
        std.Io.random(self.io, &random);
        const name = try std.fmt.allocPrint(self.allocator, ".pending-{s}", .{std.fmt.bytesToHex(random, .lower)});
        const path = try std.fs.path.join(self.allocator, &.{ parent, name });
        try std.Io.Dir.cwd().createDir(self.io, path, .default_dir);
        return path;
    }
    /// Remove only this invocation's private temporary directory.
    pub fn remove(self: Context, path: []const u8) void {
        std.Io.Dir.cwd().deleteTree(self.io, path) catch return;
    }
    /// Rename within a filesystem for atomic publication.
    pub fn rename(self: Context, from: []const u8, to: []const u8) Error!void {
        try std.Io.Dir.renameAbsolute(from, to, self.io);
    }
    /// Publish bytes without exposing a partially written checksum or manifest.
    pub fn atomic(self: Context, path: []const u8, bytes: []const u8) Error!void {
        const temporary_dir = try self.temporary(std.fs.path.dirname(path).?);
        defer self.remove(temporary_dir);
        const candidate = try std.fs.path.join(self.allocator, &.{ temporary_dir, "value" });
        try self.write(candidate, bytes);
        try self.rename(candidate, path);
    }
    /// Preserve an unchanged executable's inode and modification time.
    pub fn publish(self: Context, candidate: []const u8, output: []const u8) Error!bool {
        const existing = self.fileHash(output) catch null;
        if (existing) |old| {
            if (self.runnable(output) and std.mem.eql(u8, old, try self.fileHash(candidate))) return false;
        }
        try self.rename(candidate, output);
        return true;
    }
    /// Capture frontend output and replay diagnostics without interpreting them.
    pub fn capture(self: Context, argv: []const []const u8) Error!std.process.RunResult {
        const result = try std.process.run(self.allocator, self.io, .{ .argv = argv });
        try std.Io.File.stderr().writeStreamingAll(self.io, result.stderr);
        return result;
    }
    /// Invoke tools directly, preserving inherited environment and stderr.
    pub fn command(self: Context, argv: []const []const u8, environment: ?*const std.process.Environ.Map) Error!void {
        const result = try std.process.run(self.allocator, self.io, .{ .argv = argv, .environ_map = environment });
        try std.Io.File.stderr().writeStreamingAll(self.io, result.stderr);
        if (exitCode(result.term) != 0) return error.NativeToolFailed;
    }
};
/// Stable hexadecimal SHA-256 used by the private native object cache.
pub fn hash(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    var digest: [32]u8 = undefined;
    Sha.hash(bytes, &digest, .{});
    return allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}
/// Translate abnormal child termination into the CLI's host failure status.
pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 2,
    };
}

test "native build IO owns allocations and rejects missing tools or failing commands" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    try std.testing.expectError(error.ToolNotFound, context.executable("mylang-no-such-build-tool"));
    try std.testing.expectError(error.NativeToolFailed, context.command(&.{ "/bin/sh", "-c", "exit 7" }, null));
    const captured = try context.capture(&.{ "/bin/sh", "-c", "printf hello" });
    try std.testing.expectEqualStrings("hello", captured.stdout);
    try std.testing.expectEqual(@as(u8, 0), exitCode(captured.term));
    try std.testing.expectEqual(@as(u8, 2), exitCode(.{ .signal = .KILL }));
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", try hash(context.allocator, "abc"));
}
test "native publication repairs executable permissions and tool lookup skips directories" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const output = try std.fs.path.join(context.allocator, &.{ directory, "program" });
    const candidate = try std.fs.path.join(context.allocator, &.{ directory, "candidate" });
    try context.write(output, "same");
    try context.write(candidate, "same");
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, candidate, .executable_file, .{});
    try std.testing.expect(try context.publish(candidate, output));
    try std.testing.expect(context.runnable(output));
    try context.write(candidate, "same");
    try std.testing.expect(!try context.publish(candidate, output));
    try std.testing.expectError(error.ToolNotFound, context.executable(directory));
    try environment.put("PATH", directory);
    try std.testing.expectEqualStrings(output, try context.executable("program"));
    try std.testing.expectError(error.ToolNotFound, context.executable("candidate"));
    const atomic_path = try std.fs.path.join(context.allocator, &.{ directory, "checksum" });
    try context.atomic(atomic_path, "updated");
    try std.testing.expectEqualStrings("updated", try context.read(atomic_path));
    _ = try context.absolute(atomic_path);
    try context.mkdir(try std.fs.path.join(context.allocator, &.{ directory, "parents/child" }));
}
