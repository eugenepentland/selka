//! Integrity, resource bounds and publication behavior for compiler artifact transport.
const std = @import("std");
const shared = @import("shared_artifact_store.zig");
const storage = @import("shared_artifact_io.zig");
const retention = @import("native_cache_retention.zig");

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler store checks domains corruption conflicts and special files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(3);
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expect(try store.save(.syntax, key, "syntax payload"));
    try std.testing.expectEqualStrings("syntax payload", (try store.load(a, .syntax, key)).?);
    try std.testing.expect(try store.save(.syntax, key, "syntax payload"));
    try std.testing.expectError(error.DeterminismMismatch, store.save(.syntax, key, "different payload"));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .typed, key));
    const path = try store.artifactPath(.syntax, key);
    const encoded = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1024));
    encoded[encoded.len - 1] ^= 1;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = encoded });
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expect(try store.save(.syntax, key, "repaired"));
    try std.testing.expectEqualStrings("repaired", (try store.load(a, .syntax, key)).?);
    try std.Io.Dir.cwd().deleteFile(io, path);
    try std.Io.Dir.cwd().symLink(io, try std.fs.path.join(a, &.{ store.root, "format" }), path, .{});
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expect(try store.save(.syntax, key, "after symlink"));
    try std.Io.Dir.cwd().deleteFile(io, path);
    const fifo = try a.dupeSentinel(u8, path, 0);
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(std.os.linux.mknod(fifo, std.os.linux.S.IFIFO | 0o600, 0)));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expect(try store.save(.syntax, key, "after fifo"));
    try std.testing.expectEqualStrings("after fifo", (try store.load(a, .syntax, key)).?);
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler store streams large files under a small allocation ceiling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "input" });
    const destination = try std.fs.path.join(a, &.{ root, "output" });
    const corrupt_output = try std.fs.path.join(a, &.{ root, "bad-output" });
    const bytes = try a.alloc(u8, 512 * 1024);
    @memset(bytes, 'x');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source, .data = bytes });
    var budget: [16 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&budget);
    var store = try shared.Store.open(fixed.allocator(), io, root);
    defer store.deinit();
    const key: shared.Key = @splat(5);
    try std.testing.expect(try store.publishFile(.program, key, source));
    try std.testing.expect(try store.restore(.program, key, destination));
    const input = (try storage.regular(a, io, source)).?;
    defer input.close(io);
    try std.testing.expectError(error.InputChanged, storage.transfer(io, input, null, 0, bytes.len + 1));
    const restored = try std.Io.Dir.cwd().readFileAlloc(io, destination, a, .limited(bytes.len + 1));
    try std.testing.expectEqualSlices(u8, bytes, restored);
    const artifact = try store.artifactPath(.program, key);
    defer fixed.allocator().free(artifact);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = "interrupted" });
    try std.testing.expect(!try store.restore(.program, key, corrupt_output));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, corrupt_output, .{}));
    try std.testing.expect(try store.publishFile(.program, key, source));
    const encoded = try std.Io.Dir.cwd().readFileAlloc(io, artifact, a, .limited(bytes.len + 256));
    @memset(encoded["selka-compiler-blob-v1\x00".len + 33 ..][0..8], 0xff);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = encoded });
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .program, key));
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler store rejects foreign formats and retains permanent lock ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const lock_path = try std.fs.path.join(a, &.{ store.root, ".lock" });
    const held = try storage.lock(a, io, lock_path);
    const other = try std.Io.Dir.cwd().openFile(io, lock_path, .{ .mode = .read_write });
    defer other.close(io);
    try std.testing.expect(!try other.tryLock(io, .exclusive));
    held.close(io);
    try std.testing.expect(try other.tryLock(io, .exclusive));
    other.unlock(io);
    const marker = try std.fs.path.join(a, &.{ store.root, "format" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = marker, .data = "foreign-format\n" });
    try std.testing.expectError(error.ReadFailed, shared.Store.open(a, io, root));
    try std.testing.expectError(error.ReadFailed, store.save(.syntax, @splat(1), "data"));
    try std.Io.Dir.cwd().deleteFile(io, marker);
    try temporary.dir.writeFile(io, .{ .sub_path = "compiler-artifacts-v2/foreign", .data = "preserve" });
    try std.testing.expectError(error.ReadFailed, shared.Store.open(a, io, root));
    try std.testing.expectEqualStrings("preserve", (try storage.bounded(a, io, try std.fs.path.join(a, &.{ store.root, "foreign" }), 16)).?);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "shared compiler verified hits refresh retention while corruption remains old" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(21);
    try std.testing.expect(try store.save(.typed, key, "retained"));
    const path = try store.artifactPath(.typed, key);
    try std.Io.Dir.cwd().setTimestamps(io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    try std.testing.expectEqualStrings("retained", (try store.load(a, .typed, key)).?);
    try std.testing.expect((try std.Io.Dir.cwd().statFile(io, path, .{})).mtime.nanoseconds > 1);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "corrupt" });
    try std.Io.Dir.cwd().setTimestamps(io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .typed, key));
    try std.testing.expectEqual(@as(i96, 1), (try std.Io.Dir.cwd().statFile(io, path, .{})).mtime.nanoseconds);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "shared compiler collection misses refill and protects publication lock inodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(22);
    try std.testing.expect(try store.save(.syntax, key, "refill"));
    const context = retention.Context.init(a, io, store.root, .compiler);
    var policy = retention.Policy.defaults(.compiler);
    policy.max_entries = 0;
    const lease = try context.lease();
    const target = try store.artifactPath(.syntax, key);
    const lock_path = try std.fmt.allocPrint(a, "{s}.lock", .{target});
    const publication = try storage.lock(a, io, lock_path);
    const before = try std.Io.Dir.cwd().statFile(io, lock_path, .{});
    try std.testing.expect((try context.collect(policy, false)).skipped_active);
    try std.testing.expectEqual(before.inode, (try std.Io.Dir.cwd().statFile(io, lock_path, .{})).inode);
    publication.close(io);
    lease.close(io);
    try std.testing.expect((try context.collect(policy, false)).removed.entries >= 1);
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expect(try store.save(.syntax, key, "refill"));
    try std.testing.expectEqualStrings("refill", (try store.load(a, .syntax, key)).?);
}
