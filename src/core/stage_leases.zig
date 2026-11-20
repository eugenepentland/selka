//! The live users of the shared stage store. A process that opens the store creates one lease file under `leases/`, locked
//! shared until it closes the store. Registration holds `registry.lock` shared, and the collector's scan holds it exclusive,
//! so a scan never sees a lease that exists but is not yet locked. A lease's start is its file's modification time, which the
//! file system sets when the lease is created; the collector compares it with pack times. A lease another process can lock
//! exclusively has no holder: that process is gone, and the collector removes the file.
const std = @import("std");

/// The directory of leases under a shared namespace root.
pub const directory_leaf = "leases";
/// The lock file that orders registration and the collector's scan.
pub const registry_leaf = "registry.lock";

/// A registered lease: the open, shared-locked file, and its path.
pub const Lease = struct {
    file: std.Io.File,
    path: []const u8,

    /// Close the lease and remove its file, so the collector has nothing to scan for this process. `a` owns `path`.
    pub fn release(self: Lease, io: std.Io, a: std.mem.Allocator) void {
        defer a.free(self.path);
        self.file.close(io);
        // A file that cannot be removed is a stale lease: the collector finds it unlocked and removes it.
        std.Io.Dir.cwd().deleteFile(io, self.path) catch return;
    }
};

/// Register a lease under the namespace `root`. Null when the namespace cannot be written, and the caller then keeps
/// its records private (a miss, never a wrong result).
pub fn register(a: std.mem.Allocator, io: std.Io, root: []const u8) std.mem.Allocator.Error!?Lease {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    const registry = try std.fs.path.join(temporary, &.{ root, registry_leaf });
    const registry_file = std.Io.Dir.cwd().createFile(io, registry, .{ .read = true, .truncate = false }) catch return null;
    defer registry_file.close(io);
    registry_file.lock(io, .shared) catch return null;
    defer registry_file.unlock(io);
    const directory = try std.fs.path.join(temporary, &.{ root, directory_leaf });
    std.Io.Dir.cwd().createDirPath(io, directory) catch return null;
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const hex = std.fmt.bytesToHex(nonce, .lower);
    const path = try std.fs.path.join(a, &.{ directory, &hex });
    errdefer a.free(path);
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .read = true, .exclusive = true, .lock = .shared }) catch {
        a.free(path);
        return null;
    };
    return .{ .file = file, .path = path };
}

/// What a collector's scan of the leases found: the number of live leases, the oldest live start (the modification time
/// of its file, in nanoseconds), and the leases it removed as dead.
pub const Scan = struct { live: u64 = 0, oldest: ?i96 = null, removed: u64 = 0 };

/// Scan `root`'s leases. A file another process can lock exclusively is dead and is removed; a locked one is live and
/// its start counts toward the oldest. The caller holds `registry.lock` exclusively.
pub fn scan(io: std.Io, root: []const u8, a: std.mem.Allocator) std.mem.Allocator.Error!Scan {
    var result: Scan = .{};
    const directory_path = try std.fs.path.join(a, &.{ root, directory_leaf });
    var directory = std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch return result;
    defer directory.close(io);
    var entries = directory.iterate();
    while (entries.next(io) catch return result) |entry| {
        if (entry.kind != .file) continue;
        const path = try std.fs.path.join(a, &.{ directory_path, entry.name });
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch continue;
        defer file.close(io);
        const held = file.tryLock(io, .exclusive) catch true;
        if (!held) {
            const stat = file.stat(io) catch continue;
            result.live += 1;
            if (result.oldest == null or stat.mtime.nanoseconds < result.oldest.?) result.oldest = stat.mtime.nanoseconds;
            continue;
        }
        file.unlock(io);
        std.Io.Dir.cwd().deleteFile(io, path) catch continue;
        result.removed += 1;
    }
    return result;
}
