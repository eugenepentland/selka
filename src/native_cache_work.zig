//! Exact-key native work coordination; waiters lease the namespace before opening lock inodes.
const std = @import("std");
const retention = @import("native_cache_retention.zig");
const storage = @import("shared_artifact_io.zig");

/// Failures to allocate or acquire a regular cooperative lock.
pub const Error = error{ OutOfMemory, WriteFailed };

/// Keep a namespace alive through native reads and output publication.
pub fn lease(a: std.mem.Allocator, io: std.Io, root: []const u8) Error!std.Io.File {
    std.Io.Dir.cwd().createDirPath(io, root) catch return error.WriteFailed;
    return retention.Context.init(a, io, root, .compiler).lease() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.WriteFailed;
}

/// One exclusive exact-key work claim protected from retention unlink races.
pub const Claim = struct {
    io: std.Io,
    lease: std.Io.File,
    work: std.Io.File,

    /// Lease the namespace before waiting; acquire batches in sorted unique key order.
    pub fn acquire(a: std.mem.Allocator, io: std.Io, root: []const u8, key: [32]u8) Error!Claim {
        const namespace_lease = try lease(a, io, root);
        errdefer namespace_lease.close(io);
        const directory = try std.fs.path.join(a, &.{ root, "work" });
        defer a.free(directory);
        std.Io.Dir.cwd().createDirPath(io, directory) catch return error.WriteFailed;
        const leaf = try std.fmt.allocPrint(a, "{s}.lock", .{std.fmt.bytesToHex(key, .lower)});
        defer a.free(leaf);
        const path = try std.fs.path.join(a, &.{ directory, leaf });
        defer a.free(path);
        const work = storage.lock(a, io, path) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.WriteFailed;
        return .{ .io = io, .lease = namespace_lease, .work = work };
    }

    /// Close both locks; process exit also releases claims without stale ownership.
    pub fn deinit(self: *Claim) void {
        self.work.close(self.io);
        self.lease.close(self.io);
        self.* = undefined;
    }
};

// spec: NATIVE-WORK-CLAIM-1
test "native work claims release for subsequent same key acquisition" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var first = try Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(7));
    var independent = try Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(8));
    try std.testing.expect(independent.work.handle != first.work.handle);
    independent.deinit();
    first.deinit();
    var second = try Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(7));
    defer second.deinit();
    try std.testing.expect(second.work.handle >= 0);
}

// spec-case: NATIVE-WORK-CLAIM-1
test "native work Claim acquire errors release the namespace lease" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "work", .data = "blocked" });
    try std.testing.expectError(error.WriteFailed, Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(7)));
    try std.testing.expectError(error.OutOfMemory, Claim.acquire(std.testing.failing_allocator, std.testing.io, root, @splat(7)));
}
