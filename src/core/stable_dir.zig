//! A working directory whose absolute path is the same on every run (CORE-STABLE-DIR-1).
//!
//! The LLVM of a single-file program carries its source path (`!DIFile`), and a unit
//! object is keyed by the unit's text, so a test that writes its program into a random
//! temporary directory compiles and links it again on every run even when nothing it
//! depends on changed: about 0.25 s of `zig cc` per build, and a five-mode test builds
//! four to sixteen times. A test that builds into the suite cache (so that it asserts
//! nothing about cold caches) can keep its sources in a stable directory instead: the
//! same text at the same path finds its objects and its program in the stores, and the
//! compiler under test still checks, lowers and emits the program every time, so a
//! change that alters the emitted text compiles and runs.
const std = @import("std");
const options = @import("core_test_options");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();

/// Why a directory could not be made.
const Error = error{ OutOfMemory, Unavailable };

/// A directory with `std.testing.TmpDir`'s `dir` and `cleanup`. It starts empty, and keeps its
/// contents after `cleanup` until the next run opens the same name.
pub const StableDir = struct {
    dir: std.Io.Dir,
    /// The absolute path.
    path: []const u8,
    /// Held while the directory is in use; null for a unique fallback.
    lock: ?std.Io.File,
    /// A fallback directory is removed when the test is done.
    unique: bool,
    /// Owns `path`.
    allocator: std.mem.Allocator,

    /// Release the directory and its path.
    pub fn deinit(self: *StableDir) void {
        self.dir.close(io);
        if (self.lock) |file| file.close(io);
        if (self.unique) removeTree(self.path);
        self.allocator.free(self.path);
    }

    /// `std.testing.TmpDir`'s name for `deinit`, so a test changes one line.
    pub fn cleanup(self: *StableDir) void {
        self.deinit();
    }
};

fn removeTree(path: []const u8) void {
    // A fallback directory that stays behind only wastes a little disk.
    cwd.deleteTree(io, path) catch return;
}

/// An empty directory for the test at `where` (pass `@src()`; two directories in one function
/// differ by line). Its name is the same on every run, in the file's suite cache. A second
/// process that finds the name in use (two runs of one tree at once) gets a unique name
/// instead, which only loses the reuse. It cannot fail, like `std.testing.tmpDir`: a test
/// that cannot have its directory stops.
pub fn tmpDir(gpa: std.mem.Allocator, where: std.lang.SourceLocation) StableDir {
    return make(gpa, where) catch |err| std.debug.panic("no stable test directory: {s}", .{@errorName(err)});
}

fn make(gpa: std.mem.Allocator, where: std.lang.SourceLocation) Error!StableDir {
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    const base = options.suiteCache(a, where) catch return error.Unavailable;
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(where.fn_name, &hash, .{});
    const stable = try std.fmt.allocPrint(a, "{s}/stable-{d}-{x}", .{ base, where.line, hash[0..6].* });
    const lock_path = try std.fmt.allocPrint(a, "{s}.lock", .{stable});
    const lock = cwd.createFile(io, lock_path, .{ .truncate = false }) catch return error.Unavailable;
    const held = lock.tryLock(io, .exclusive) catch false;
    if (held) cwd.deleteTree(io, stable) catch return error.Unavailable;
    var nonce: [8]u8 = undefined;
    std.Io.random(io, &nonce);
    const path = if (held) try gpa.dupe(u8, stable) else try std.fmt.allocPrint(gpa, "{s}-{x}", .{ stable, nonce });
    errdefer gpa.free(path);
    cwd.createDirPath(io, path) catch return error.Unavailable;
    const dir = cwd.openDir(io, path, .{}) catch return error.Unavailable;
    if (!held) lock.close(io);
    return .{ .dir = dir, .path = path, .lock = if (held) lock else null, .unique = !held, .allocator = gpa };
}

// spec: CORE-STABLE-DIR-1
test "a stable directory has the same path in every run, starts empty, and a second holder gets a unique one" {
    const site = @src();
    var first = tmpDir(std.testing.allocator, site);
    const path = try std.testing.allocator.dupe(u8, first.path);
    defer std.testing.allocator.free(path);
    try first.dir.writeFile(io, .{ .sub_path = "left-over", .data = "from the first use" });
    // While it is held, the same call site gets a directory that is not the stable one.
    var second = tmpDir(std.testing.allocator, site);
    try std.testing.expect(!std.mem.eql(u8, path, second.path));
    try std.testing.expect(second.unique);
    const unique_path = try std.testing.allocator.dupe(u8, second.path);
    defer std.testing.allocator.free(unique_path);
    second.cleanup();
    try std.testing.expectError(error.FileNotFound, cwd.access(io, unique_path, .{}));
    first.cleanup();
    // After cleanup the contents stay for debugging; the next open of the name empties them.
    const kept = try std.fs.path.join(std.testing.allocator, &.{ path, "left-over" });
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings("left-over", std.fs.path.basename(kept));
    try cwd.access(io, kept, .{});
    var again = tmpDir(std.testing.allocator, site);
    defer again.cleanup();
    try std.testing.expectEqualStrings(path, again.path);
    try std.testing.expectError(error.FileNotFound, again.dir.access(io, "left-over", .{}));
}
