//! Filesystem and child-process operations for native builds.
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;
/// The one hidden folder every invocation stages beneath, so a destination
/// directory keeps at most one shared staging folder instead of one
/// `.pending-<hex>` sibling per build.
const staging_name = ".pending";
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
    self_directory: []const u8,
    /// Own a stable child arena for every allocation made during this build.
    pub fn init(parent: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) Error!Context {
        const arena = try parent.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(parent);
        const allocator = arena.allocator();
        const own = std.Io.Dir.cwd().realPathFileAlloc(io, "/proc/self/exe", allocator) catch "";
        const directory = if (own.len == 0) "" else std.fs.path.dirname(own) orelse "";
        return .{ .allocator = allocator, .arena = arena, .parent = parent, .io = io, .environ = environ, .self_directory = directory };
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
    /// The environment variable, if any, that names a bare native tool.
    fn toolVariable(name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, "qbe")) return "MYLANG_QBE";
        if (std.mem.eql(u8, name, "zig")) return "MYLANG_ZIG";
        return null;
    }
    /// Resolve an explicit path, then `MYLANG_QBE`/`MYLANG_ZIG`, then a tool beside
    /// this compiler, then `PATH`; the working directory never selects a build tool.
    pub fn executable(self: Context, name: []const u8) Error![]const u8 {
        if (std.mem.indexOfScalar(u8, name, '/') != null) {
            if (!self.runnable(name)) return error.ToolNotFound;
            return std.Io.Dir.cwd().realPathFileAlloc(self.io, name, self.allocator);
        }
        // `MYLANG_QBE` and `MYLANG_ZIG` name the native tools when neither a flag,
        // a tool beside the compiler, nor `PATH` does — a host or driver run from
        // an uninstalled binary whose directory holds no tools.
        if (toolVariable(name)) |variable| if (self.environ.get(variable)) |path| {
            if (self.runnable(path)) return std.Io.Dir.cwd().realPathFileAlloc(self.io, path, self.allocator);
        };
        if (self.self_directory.len != 0) {
            const sibling = try std.fs.path.join(self.allocator, &.{ self.self_directory, name });
            if (self.runnable(sibling)) return std.Io.Dir.cwd().realPathFileAlloc(self.io, sibling, self.allocator);
        }
        var paths = std.mem.splitScalar(u8, self.environ.get("PATH") orelse "", ':');
        while (paths.next()) |path| {
            const candidate = try std.fs.path.join(self.allocator, &.{ path, name });
            if (!self.runnable(candidate)) continue;
            const resolved = std.Io.Dir.cwd().realPathFileAlloc(self.io, candidate, self.allocator) catch continue;
            return resolved;
        }
        return error.ToolNotFound;
    }
    /// Identify an external tool by path, size and modification time; rehashing a
    /// multi-hundred-megabyte toolchain on every build costs more than a whole native build.
    pub fn stamp(self: Context, path: []const u8) Error![]const u8 {
        const info = try std.Io.Dir.cwd().statFile(self.io, path, .{});
        return std.fmt.allocPrint(self.allocator, "{s}\x00{d}\x00{d}", .{ path, info.size, info.mtime.nanoseconds });
    }
    /// Report whether a content-addressed cache entry has already been published.
    pub fn exists(self: Context, path: []const u8) bool {
        std.Io.Dir.cwd().access(self.io, path, .{}) catch return false;
        return true;
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
    /// Report the byte length of a published artifact without reading it.
    pub fn size(self: Context, path: []const u8) Error!u64 {
        return (try std.Io.Dir.cwd().statFile(self.io, path, .{})).size;
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
    /// Every invocation in one parent shares a single `.pending/` folder, and
    /// each gets a unique child, so many concurrent builders leave one folder
    /// rather than one sibling each, and stale scratch stays contained.
    pub fn temporary(self: Context, parent: []const u8) Error![]const u8 {
        const staging = try std.fs.path.join(self.allocator, &.{ parent, staging_name });
        // A concurrent `remove` may delete the shared folder after it empties
        // and before this child is created; recreate it and retry.
        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            try std.Io.Dir.cwd().createDirPath(self.io, staging);
            var random: [16]u8 = undefined;
            std.Io.random(self.io, &random);
            const name = std.fmt.bytesToHex(random, .lower);
            const path = try std.fs.path.join(self.allocator, &.{ staging, &name });
            std.Io.Dir.cwd().createDir(self.io, path, .default_dir) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            return path;
        }
        return error.FileNotFound;
    }
    /// Remove only this invocation's private staging directory, then the shared
    /// `.pending/` folder when nothing else is using it. Removal stays best
    /// effort: a failed or interrupted one leaves scratch inside that single
    /// folder, where it is contained and can be swept as a unit.
    pub fn remove(self: Context, path: []const u8) void {
        // The staging child may already have been renamed into place, which
        // `deleteTree` treats as success; a non-empty or non-staging parent is
        // simply left alone.
        std.Io.Dir.cwd().deleteTree(self.io, path) catch return;
        const staging = std.fs.path.dirname(path) orelse return;
        if (!std.mem.eql(u8, std.fs.path.basename(staging), staging_name)) return;
        std.Io.Dir.cwd().deleteDir(self.io, staging) catch return;
    }
    /// Remove every entry of `parent` except the one named `keep` and the shared
    /// staging folder. Eviction is best effort, like `remove`: a cache that cannot
    /// be swept still serves the generation it keeps, and a stale entry a
    /// concurrent sweep already removed is simply found gone. Names are collected
    /// before anything is deleted, so the sweep never mutates a directory it is
    /// still iterating.
    pub fn sweep(self: Context, parent: []const u8, keep: []const u8) void {
        var directory = std.Io.Dir.cwd().openDir(self.io, parent, .{ .iterate = true, .follow_symlinks = false }) catch return;
        defer directory.close(self.io);
        var names: std.ArrayList([]const u8) = .empty;
        var iterator = directory.iterate();
        while (iterator.next(self.io) catch null) |entry| {
            if (std.mem.eql(u8, entry.name, keep) or std.mem.eql(u8, entry.name, staging_name)) continue;
            names.append(self.allocator, self.allocator.dupe(u8, entry.name) catch return) catch return;
        }
        for (names.items) |name| directory.deleteTree(self.io, name) catch continue;
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
        if (self.runnable(output) and self.unchanged(candidate, output)) return false;
        try self.rename(candidate, output);
        return true;
    }
    /// Compare lengths before bytes: a relinked program that really changed is
    /// never read twice, and an unchanged one costs one comparison, not two digests.
    fn unchanged(self: Context, candidate: []const u8, output: []const u8) bool {
        const produced = self.size(candidate) catch return false;
        const published = self.size(output) catch return false;
        if (produced != published) return false;
        const left = self.read(candidate) catch return false;
        const right = self.read(output) catch return false;
        return std.mem.eql(u8, left, right);
    }
    /// This process's environment with a guest byte ceiling added, for a child
    /// that runs guest code. The runtime reads it before its first allocation,
    /// so no spawner needs a new argument ABI to bound a guest.
    pub fn bounded(self: Context, bytes: u64) Error!*const std.process.Environ.Map {
        const environment = try self.allocator.create(std.process.Environ.Map);
        environment.* = try self.environ.clone(self.allocator);
        try environment.put(@import("memory_budget").variable, try std.fmt.allocPrint(self.allocator, "{d}", .{bytes}));
        return environment;
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
/// Stable hexadecimal SHA-256 naming a cache entry by the inputs that produced it.
pub fn hash(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    var result: [32]u8 = undefined;
    Sha.hash(bytes, &result, .{});
    return allocator.dupe(u8, &std.fmt.bytesToHex(result, .lower));
}
/// Integrity fingerprint for stored native objects, covering length and contents.
/// Keys stay on SHA-256 because they name small inputs; a warm build instead
/// re-reads megabytes of cached objects, where a cryptographic hash costs more
/// than the whole link it protects.
pub fn digest(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "mylang-object-v1:{d}:{x:0>16}", .{ bytes.len, std.hash.XxHash3.hash(0, bytes) });
}
/// Translate abnormal child termination into the CLI's host failure status.
pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 2,
    };
}

/// Allocate scratch through a fresh context, then release it back to `parent`.
fn buildRound(parent: std.mem.Allocator, environment: *const std.process.Environ.Map) !void {
    var context = try Context.init(parent, std.testing.io, environment);
    defer context.deinit();
    _ = try context.absolute("guest.my");
    context.remove(try context.temporary(try context.absolute(".")));
}
// spec: NATIVE-BUILD-RECLAIM-1
test "a build context reclaims its scratch on deinit, so repeated builds do not accumulate" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    // The testing allocator asserts every byte is freed, so a context that did
    // not reclaim its arena to its parent would leak across these repeated builds.
    try buildRound(std.testing.allocator, &environment);
    try buildRound(std.testing.allocator, &environment);
    try buildRound(std.testing.allocator, &environment);
}
// spec: NATIVE-STAGING-1
test "one staging folder per directory contains concurrent and abandoned scratch" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const parent = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const first = try context.temporary(parent);
    const second = try context.temporary(parent);
    // Both invocations stage under the one shared folder, never as siblings.
    const staging = try std.fs.path.join(context.allocator, &.{ parent, staging_name });
    try std.testing.expectEqualStrings(staging, std.fs.path.dirname(first).?);
    try std.testing.expectEqualStrings(staging, std.fs.path.dirname(second).?);
    try std.testing.expect(!std.mem.eql(u8, first, second));
    // The first removal cannot take the folder while the second still uses it.
    context.remove(first);
    try std.testing.expect(context.exists(staging));
    // A child renamed into place still reclaims the shared folder afterwards.
    const published = try std.fs.path.join(context.allocator, &.{ parent, "published" });
    try context.rename(second, published);
    context.remove(second);
    try std.testing.expect(!context.exists(staging));
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
// spec-case: QBE-2
test "object integrity fingerprints separate truncated, padded and altered bytes" {
    const a = std.testing.allocator;
    const original = try digest(a, "native object bytes");
    defer a.free(original);
    const truncated = try digest(a, "native object byte");
    defer a.free(truncated);
    const altered = try digest(a, "native object bytez");
    defer a.free(altered);
    const repeated = try digest(a, "native object bytes");
    defer a.free(repeated);
    try std.testing.expect(!std.mem.eql(u8, original, truncated));
    try std.testing.expect(!std.mem.eql(u8, original, altered));
    try std.testing.expectEqualStrings("mylang-object-v1:18:", truncated[0..20]);
    try std.testing.expectEqualStrings(original, repeated);
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
    try std.testing.expect(context.exists(output));
    try std.testing.expect(!context.exists(try std.fs.path.join(context.allocator, &.{ directory, "absent" })));
    const atomic_path = try std.fs.path.join(context.allocator, &.{ directory, "checksum" });
    try context.atomic(atomic_path, "updated");
    try std.testing.expectEqualStrings("updated", try context.read(atomic_path));
    _ = try context.absolute(atomic_path);
    try context.mkdir(try std.fs.path.join(context.allocator, &.{ directory, "parents/child" }));
}
// spec: QBE-4
test "native tools resolve beside the compiler then PATH, never from the working directory" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const beside = try std.fs.path.join(context.allocator, &.{ directory, "beside" });
    const searched = try std.fs.path.join(context.allocator, &.{ directory, "searched" });
    try context.mkdir(beside);
    try context.mkdir(searched);
    for ([_][]const u8{ beside, searched }) |parent| {
        const tool = try std.fs.path.join(context.allocator, &.{ parent, "qbe" });
        try context.write(tool, parent);
        try std.Io.Dir.cwd().setFilePermissions(std.testing.io, tool, .executable_file, .{});
    }
    try environment.put("PATH", searched);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ searched, "qbe" }), try context.executable("qbe"));
    context.self_directory = beside;
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ beside, "qbe" }), try context.executable("qbe"));
    context.self_directory = "";
    try environment.put("PATH", "");
    // A `.mylang-cache/toolchain/qbe` under the current directory is no longer a lookup path.
    try std.testing.expectError(error.ToolNotFound, context.executable("qbe"));
    // `MYLANG_QBE` names the tool when neither a sibling nor PATH does.
    try environment.put("MYLANG_QBE", try std.fs.path.join(context.allocator, &.{ searched, "qbe" }));
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ searched, "qbe" }), try context.executable("qbe"));
}
test "tool stamps distinguish rebuilt tools without rereading their contents" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const tool = try std.fs.path.join(context.allocator, &.{ directory, "tool" });
    try context.write(tool, "one");
    const before = try context.stamp(tool);
    try std.testing.expectEqualStrings(before, try context.stamp(tool));
    try context.write(tool, "a longer replacement");
    try std.testing.expect(!std.mem.eql(u8, before, try context.stamp(tool)));
    try std.testing.expect(std.mem.indexOf(u8, before, tool) != null);
    try std.testing.expectError(error.FileNotFound, context.stamp(try std.fs.path.join(context.allocator, &.{ directory, "absent" })));
}
// spec-case: QBE-GENERATION-1
test "sweeping a cache family removes every entry but the kept generation and the staging folder" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const parent = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const kept = try std.fs.path.join(context.allocator, &.{ parent, "current" });
    const stale = try std.fs.path.join(context.allocator, &.{ parent, "stale", "nested" });
    const loose = try std.fs.path.join(context.allocator, &.{ parent, "loose.o" });
    try context.mkdir(kept);
    try context.mkdir(stale);
    try context.write(try std.fs.path.join(context.allocator, &.{ kept, "unit.o" }), "kept");
    try context.write(try std.fs.path.join(context.allocator, &.{ stale, "unit.o" }), "stale");
    try context.write(loose, "loose");
    const staging = try context.temporary(parent);
    context.sweep(parent, "current");
    try std.testing.expect(context.exists(try std.fs.path.join(context.allocator, &.{ kept, "unit.o" })));
    try std.testing.expect(context.exists(staging));
    try std.testing.expect(!context.exists(stale));
    try std.testing.expect(!context.exists(std.fs.path.dirname(stale).?));
    try std.testing.expect(!context.exists(loose));
    // A missing family is not an error: there is nothing to evict.
    context.sweep(try std.fs.path.join(context.allocator, &.{ parent, "absent" }), "current");
    try std.testing.expect(context.exists(kept));
}
