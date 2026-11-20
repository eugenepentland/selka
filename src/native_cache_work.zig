//! Exact-key native work coordination; waiters lease the namespace before opening lock inodes.
const std = @import("std");
const retention = @import("native_cache_retention.zig");
const storage = @import("shared_artifact_io.zig");

/// Failures to allocate or acquire a regular cooperative lock.
pub const Error = error{ OutOfMemory, WriteFailed };

/// Keep a namespace alive through native reads and output publication. Waits for as long as a collection holds the namespace;
/// a build uses `leaseWithin`, which gives up, so that a sweep can never stall it.
pub fn lease(a: std.mem.Allocator, io: std.Io, root: []const u8) Error!std.Io.File {
    std.Io.Dir.cwd().createDirPath(io, root) catch return error.WriteFailed;
    return retention.Context.init(a, io, root, .compiler).lease() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.WriteFailed;
}

/// How long a build waits for a collection that holds a namespace exclusively before it works without the lease. The collector of
/// the per-user object store takes no lease that builds wait on, and the one it can take (for the runtime objects) is a try that
/// lasts seconds, so this bounds the stall of a build behind any other exclusive holder. A build asks for a few namespaces, not
/// for every unit it claims: it takes one lease on the store root and, past the first claim that finds a namespace held, none
/// of the rest (`driver.claimAll`).
pub const lease_wait_ms: u32 = 1000;

/// Milliseconds between two tries for a lease held exclusively.
const lease_poll_ms: u32 = 20;

/// Like `lease`, but wait at most `wait_ms` for a collection that holds the namespace: null then, and the caller works without
/// the lease (and so without the protection from a sweep it gives, which the collector's grace period makes unnecessary for
/// the objects a build is using).
pub fn leaseWithin(a: std.mem.Allocator, io: std.Io, root: []const u8, wait_ms: u32) Error!?std.Io.File {
    std.Io.Dir.cwd().createDirPath(io, root) catch return error.WriteFailed;
    const context = retention.Context.init(a, io, root, .compiler);
    var waited: u32 = 0;
    while (true) {
        if (context.tryLease() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.WriteFailed) |file| return file;
        if (waited >= wait_ms) return null;
        std.Io.sleep(io, .fromMilliseconds(lease_poll_ms), .awake) catch return null;
        waited += lease_poll_ms;
    }
}

/// One exclusive exact-key work claim protected from retention unlink races.
pub const Claim = struct {
    io: std.Io,
    lease: std.Io.File,
    work: std.Io.File,

    /// Lease the namespace before waiting for the key; acquire batches in sorted unique key order. Null when a collection held
    /// the namespace for `lease_wait_ms`: the caller then works unclaimed, as it does when `attempt` finds a sweep running.
    pub fn acquire(a: std.mem.Allocator, io: std.Io, root: []const u8, key: [32]u8) Error!?Claim {
        return acquireWithin(a, io, root, key, lease_wait_ms);
    }

    /// `acquire` with its own bound on the wait for the namespace; the wait for another holder of the same key is not bounded.
    pub fn acquireWithin(a: std.mem.Allocator, io: std.Io, root: []const u8, key: [32]u8, wait_ms: u32) Error!?Claim {
        const namespace_lease = (try leaseWithin(a, io, root, wait_ms)) orelse return null;
        const claim = try held(a, io, root, key, namespace_lease);
        return claim;
    }

    /// Like `acquire`, but return null instead of waiting while a collection holds
    /// the namespace: the caller then works unclaimed and never waits on a sweep.
    pub fn attempt(a: std.mem.Allocator, io: std.Io, root: []const u8, key: [32]u8) Error!?Claim {
        return acquireWithin(a, io, root, key, 0);
    }

    fn held(a: std.mem.Allocator, io: std.Io, root: []const u8, key: [32]u8, namespace_lease: std.Io.File) Error!Claim {
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
    var first = (try Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(7))).?;
    var independent = (try Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(8))).?;
    try std.testing.expect(independent.work.handle != first.work.handle);
    independent.deinit();
    first.deinit();
    var second = (try Claim.acquire(std.testing.allocator, std.testing.io, root, @splat(7))).?;
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

/// Wall-clock milliseconds, for the bounds the tests below check.
fn nowMs(io: std.Io) i64 {
    return @intCast(@divTrunc(std.Io.Timestamp.now(io, .awake).nanoseconds, std.time.ns_per_ms));
}

test "native work: a build stops waiting for a collection that holds the namespace and works unclaimed" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const sweep = (try retention.Context.init(std.testing.allocator, io, root, .compiler).tryExclusive()).?;
    defer sweep.close(io);
    const started = nowMs(io);
    try std.testing.expect(try leaseWithin(std.testing.allocator, io, root, 100) == null);
    try std.testing.expect(try Claim.acquireWithin(std.testing.allocator, io, root, @splat(9), 100) == null);
    try std.testing.expect(try Claim.attempt(std.testing.allocator, io, root, @splat(9)) == null);
    const waited = nowMs(io) - started;
    try std.testing.expect(waited >= 200);
    try std.testing.expect(waited < 2 * lease_wait_ms);
}

test "native work: a build waits out a collection that ends within the bound and then takes its claim" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const sweep = (try retention.Context.init(std.testing.allocator, io, root, .compiler).tryExclusive()).?;
    const release = try std.Thread.spawn(.{}, struct {
        fn run(held: std.Io.File, thread_io: std.Io) void {
            std.Io.sleep(thread_io, .fromMilliseconds(150), .awake) catch {};
            held.close(thread_io);
        }
    }.run, .{ sweep, io });
    defer release.join();
    var claim = (try Claim.acquire(std.testing.allocator, io, root, @splat(11))).?;
    defer claim.deinit();
    try std.testing.expect(claim.work.handle >= 0);
}

test "native work: a claim file removed while a builder waits for it is opened again, so two builders never hold one key" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var first = (try Claim.acquire(std.testing.allocator, io, root, @splat(12))).?;
    var contender: ?Claim = null;
    const waiter = try std.Thread.spawn(.{}, struct {
        fn run(thread_root: []const u8, thread_io: std.Io, result: *?Claim) void {
            result.* = Claim.acquire(std.testing.allocator, thread_io, thread_root, @splat(12)) catch null;
        }
    }.run, .{ root, io, &contender });
    // Give the waiter time to open the held file and block on its lock, then sweep the name away as an idle-claim sweep would
    // once it could lock the file (here the holder still has it, so remove it directly) and release the holder.
    std.Io.sleep(io, .fromMilliseconds(200), .awake) catch {};
    const name = try std.fmt.allocPrint(std.testing.allocator, "work/{s}.lock", .{std.fmt.bytesToHex(@as([32]u8, @splat(12)), .lower)});
    defer std.testing.allocator.free(name);
    try temporary.dir.deleteFile(io, name);
    first.deinit();
    waiter.join();
    var second = contender.?;
    defer second.deinit();
    const held = try second.work.stat(io);
    const named = try temporary.dir.statFile(io, name, .{ .follow_symlinks = false });
    try std.testing.expectEqual(named.inode, held.inode);
}
