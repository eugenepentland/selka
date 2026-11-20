//! Integrity, resource bounds and publication behavior for compiler artifact transport.
const std = @import("std");
const shared = @import("shared_artifact_store.zig");
const storage = @import("shared_artifact_io.zig");
const retention = @import("native_cache_retention.zig");

/// Make a stored program record writable again, as a disk fault ignores its mode (records are read-only: build outputs are names of the file).
fn damaged(io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().setFilePermissions(io, path, .fromMode(0o600), .{});
}

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
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "syntax payload"));
    try std.testing.expectEqualStrings("syntax payload", (try store.load(a, .syntax, key)).?);
    try std.testing.expectEqual(shared.Publication.present, try store.save(.syntax, key, "syntax payload"));
    try std.testing.expectEqual(shared.Publication.mismatch, try store.save(.syntax, key, "different payload"));
    try std.testing.expectEqualStrings("syntax payload", (try store.load(a, .syntax, key)).?);
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .typed, key));
    const path = try store.artifactPath(.syntax, key);
    const encoded = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1024));
    encoded[encoded.len - 1] ^= 1;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = encoded });
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "repaired"));
    try std.testing.expectEqualStrings("repaired", (try store.load(a, .syntax, key)).?);
    try std.Io.Dir.cwd().deleteFile(io, path);
    try std.Io.Dir.cwd().symLink(io, try std.fs.path.join(a, &.{ store.root, "format" }), path, .{});
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "after symlink"));
    try std.Io.Dir.cwd().deleteFile(io, path);
    const fifo = try a.dupeSentinel(u8, path, 0);
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(std.os.linux.mknod(fifo, std.os.linux.S.IFIFO | 0o600, 0)));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "after fifo"));
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
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, source));
    try std.testing.expect(try store.restore(.program, key, destination));
    const input = (try storage.regular(a, io, source)).?;
    defer input.close(io);
    try std.testing.expectError(error.InputChanged, storage.transfer(io, input, null, 0, bytes.len + 1));
    const restored = try std.Io.Dir.cwd().readFileAlloc(io, destination, a, .limited(bytes.len + 1));
    try std.testing.expectEqualSlices(u8, bytes, restored);
    const artifact = try store.artifactPath(.program, key);
    defer fixed.allocator().free(artifact);
    try damaged(io, artifact);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = "interrupted" });
    try std.testing.expect(!try store.restore(.program, key, corrupt_output));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, corrupt_output, .{}));
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, source));
    const encoded = try std.Io.Dir.cwd().readFileAlloc(io, artifact, a, .limited(bytes.len + 256));
    @memset(encoded["selka-compiler-blob-v1\x00".len + 33 ..][0..8], 0xff);
    try damaged(io, artifact);
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
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.typed, key, "retained"));
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
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "refill"));
    const context = retention.Context.init(a, io, store.root, .compiler);
    var policy = retention.Policy.defaults(.compiler);
    policy.max_entries = 0;
    const lease = try context.lease();
    const target = try store.artifactPath(.syntax, key);
    const lock_path = try std.fmt.allocPrint(a, "{s}.lock", .{target});
    const publication = try storage.lock(a, io, lock_path);
    const before = try std.Io.Dir.cwd().statFile(io, lock_path, .{});
    // A builder holds the namespace and is publishing this very key: the sweep runs beside it and leaves the record and its lock.
    const beside = try context.collect(policy, false);
    try std.testing.expect(beside.walk.leased and !beside.skipped_active);
    try std.testing.expectEqual(before.inode, (try std.Io.Dir.cwd().statFile(io, lock_path, .{})).inode);
    try std.testing.expectEqualStrings("refill", (try store.load(a, .syntax, key)).?);
    publication.close(io);
    lease.close(io);
    try std.testing.expect((try context.collect(policy, false)).removed.entries >= 1);
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .syntax, key));
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "refill"));
    try std.testing.expectEqualStrings("refill", (try store.load(a, .syntax, key)).?);
}

fn blake(bytes: []const u8) [64]u8 {
    var digest: shared.Key = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

// spec-case: SHARED-STORE-3
test "shared compiler mismatch is a logged miss that keeps the first program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(51);
    const first = try std.fs.path.join(a, &.{ root, "first" });
    const second = try std.fs.path.join(a, &.{ root, "second" });
    const restored = try std.fs.path.join(a, &.{ root, "restored" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = first, .data = "first program bytes" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = second, .data = "second program bytes" });
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, first));
    try std.testing.expectEqual(shared.Publication.mismatch, try store.publishFile(.program, key, second));
    try std.testing.expect(try store.restore(.program, key, restored));
    try std.testing.expectEqualStrings("first program bytes", try std.Io.Dir.cwd().readFileAlloc(io, restored, a, .limited(64)));
    const log = try std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(a, &.{ store.root, "mismatches.log" }), a, .limited(1024));
    const expected = try std.fmt.allocPrint(a, "mismatch program {s} existing={s} attempted={s}\n", .{ std.fmt.bytesToHex(key, .lower), blake("first program bytes"), blake("second program bytes") });
    try std.testing.expectEqualStrings(expected, log);
    const report = try retention.Context.init(a, io, store.root, .compiler).collect(null, true);
    try std.testing.expect(!report.unmet_budget);
}

test "FX11 a record replaced on purpose takes the new bytes, logs no mismatch, and the same bytes again are present" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(52);
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.frontend, key, "first table"));
    // `save` keeps the first and logs; `replace` is for the writer that means to replace it (a check-summary table, a pack).
    try std.testing.expectEqual(shared.Publication.stored, try store.replace(.frontend, key, "second table"));
    try std.testing.expectEqualStrings("second table", (try store.load(a, .frontend, key)).?);
    try std.testing.expectEqual(shared.Publication.present, try store.replace(.frontend, key, "second table"));
    try std.testing.expectEqual(shared.Publication.stored, try store.replace(.frontend, @splat(54), "a table nobody held"));
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.engine_record, @splat(53), "a fresh one"));
    try std.testing.expectEqual(shared.Publication.skipped, try store.replace(.program, key, "never a program"));
    // An offer of other bytes is a kept-out `mismatch` the caller judges (the engine's tier compares results and reads): no line.
    try std.testing.expectEqual(shared.Publication.mismatch, try store.offer(.engine_record, @splat(53), "another one"));
    try std.testing.expectEqual(shared.Publication.present, try store.offer(.engine_record, @splat(53), "a fresh one"));
    try std.testing.expectEqualStrings("a fresh one", (try store.load(a, .engine_record, @splat(53))).?);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, try std.fs.path.join(a, &.{ store.root, "mismatches.log" }), .{}));
}

// spec-case: COMPILER-SHARED-CACHE-1
test "a repeated shared publication compares in place and stages nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(52);
    const source = try std.fs.path.join(a, &.{ root, "program" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source, .data = "linked program" });
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, source));
    const artifact = try store.artifactPath(.program, key);
    const before = try std.Io.Dir.cwd().statFile(io, artifact, .{});
    // A staging file or a rename would need write access to the tier directory.
    const tier = try a.dupeSentinel(u8, std.fs.path.dirname(artifact).?, 0);
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(std.os.linux.chmod(tier, 0o500)));
    const repeated = store.publishFile(.program, key, source);
    const saved = store.save(.program, key, "different bytes");
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(std.os.linux.chmod(tier, 0o700)));
    try std.testing.expectEqual(shared.Publication.present, try repeated);
    try std.testing.expectEqual(shared.Publication.mismatch, try saved);
    try std.testing.expectEqual(before.inode, (try std.Io.Dir.cwd().statFile(io, artifact, .{})).inode);
}

// spec-case: SHARED-STORE-5
test "shared compiler opens and lookups complete while a sweep holds the store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(53);
    const source = try std.fs.path.join(a, &.{ root, "program" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source, .data = "linked program" });
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, source));
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.syntax, key, "syntax"));
    // A second open file description holds the lock exactly as a sweep in
    // another process would; a blocking lookup would hang here.
    const sweep = try std.Io.Dir.cwd().openFile(io, try std.fs.path.join(a, &.{ store.root, ".retention.lock" }), .{ .mode = .read_write });
    defer sweep.close(io);
    try std.testing.expect(try sweep.tryLock(io, .exclusive));
    var second = try shared.Store.open(a, io, root);
    defer second.deinit();
    try std.testing.expect(try second.restore(.program, key, try std.fs.path.join(a, &.{ root, "restored" })));
    try std.testing.expectEqualStrings("syntax", (try second.load(a, .syntax, key)).?);
    try std.testing.expectEqual(shared.Publication.skipped, try second.save(.syntax, @splat(54), "skipped"));
    try std.testing.expect((try second.claim(.program, key)) == null);
    const artifact = try second.artifactPath(.program, key);
    const whole = try std.Io.Dir.cwd().readFileAlloc(io, artifact, a, .limited(1024));
    try damaged(io, artifact);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = whole[0 .. whole.len - 3] });
    try std.testing.expect(!try second.restore(.program, key, try std.fs.path.join(a, &.{ root, "truncated" })));
    try std.Io.Dir.cwd().deleteFile(io, artifact);
    try std.testing.expect(!try second.restore(.program, key, try std.fs.path.join(a, &.{ root, "vanished" })));
    sweep.unlock(io);
    try std.testing.expectEqual(shared.Publication.stored, try second.publishFile(.program, key, source));
    try std.testing.expect(try store.restore(.program, key, try std.fs.path.join(a, &.{ root, "refilled" })));
}

// spec-case: PROGRAM-RECORD-2
test "a program record is its executable: a restore is a hardlink, a damaged one misses, and eviction takes its sidecar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const key: shared.Key = @splat(11);
    const source = try std.fs.path.join(a, &.{ root, "program" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source, .data = "linked executable" });
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, source));
    const artifact = try store.artifactPath(.program, key);
    const sidecar = try std.fmt.allocPrint(a, "{s}.sum", .{artifact});
    try std.testing.expectEqualStrings("linked executable", try std.Io.Dir.cwd().readFileAlloc(io, artifact, a, .limited(64)));
    const destination = try std.fs.path.join(a, &.{ root, "restored" });
    try std.testing.expect(try store.restore(.program, key, destination));
    try std.testing.expectEqual((try std.Io.Dir.cwd().statFile(io, artifact, .{})).inode, (try std.Io.Dir.cwd().statFile(io, destination, .{})).inode);
    // A damaged executable misses and leaves nothing at the destination; publishing again repairs it.
    try std.Io.Dir.cwd().deleteFile(io, artifact);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = "interrupted" });
    const corrupt = try std.fs.path.join(a, &.{ root, "corrupt" });
    try std.testing.expect(!try store.restore(.program, key, corrupt));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, corrupt, .{}));
    try std.testing.expectEqual(shared.Publication.stored, try store.publishFile(.program, key, source));
    try std.testing.expect(try store.restore(.program, key, corrupt));
    // Eviction removes the executable and its sidecar together, and a later restore misses.
    const report = try retention.Context.init(a, io, store.root, .compiler).collect(.{ .max_bytes = 0, .max_entries = 0 }, false);
    try std.testing.expect(report.removed.entries >= 1);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, artifact, .{}));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, sidecar, .{}));
    try std.testing.expect(!try store.restore(.program, key, try std.fs.path.join(a, &.{ root, "evicted" })));
}

test "a program published with the digest its caller already made is copied without being hashed, and a wrong digest makes a record that misses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const source = try std.fs.path.join(a, &.{ root, "program" });
    const bytes = "linked executable, hashed once by the caller";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source, .data = bytes });
    var digest: shared.Key = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    var other: shared.Key = digest;
    other[0] ^= 1;
    const key: shared.Key = @splat(21);
    try std.testing.expectEqual(shared.Publication.stored, try store.publishHashedFile(.program, key, source, digest));
    const restored = try std.fs.path.join(a, &.{ root, "restored" });
    try std.testing.expect(try store.restore(.program, key, restored));
    try std.testing.expectEqualStrings(bytes, try std.Io.Dir.cwd().readFileAlloc(io, restored, a, .limited(256)));
    // The same digest is present; another digest for the same key is a mismatch that keeps the first record.
    try std.testing.expectEqual(shared.Publication.present, try store.publishHashedFile(.program, key, source, digest));
    try std.testing.expectEqual(shared.Publication.mismatch, try store.publishHashedFile(.program, key, source, other));
    try std.testing.expect(try store.restore(.program, key, try std.fs.path.join(a, &.{ root, "again" })));
    // A digest that does not describe the bytes is stored as given, and the restore that checks the bytes against it misses.
    const wrong_key: shared.Key = @splat(22);
    try std.testing.expectEqual(shared.Publication.stored, try store.publishHashedFile(.program, wrong_key, source, other));
    try std.testing.expect(!try store.restore(.program, wrong_key, try std.fs.path.join(a, &.{ root, "never" })));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, try std.fs.path.join(a, &.{ root, "never" }), .{}));
}

// spec-case: PROGRAM-RECORD-2
test "a program published from a read-only file is a second name for it, a writable one is copied, and either restores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const bytes = "linked executable, written once by the linker";
    var digest: shared.Key = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    const locked = try std.fs.path.join(a, &.{ root, "locked" });
    const open = try std.fs.path.join(a, &.{ root, "open" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = locked, .data = bytes, .flags = .{ .permissions = .fromMode(0o500) } });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = open, .data = bytes });
    // A file nobody can write through becomes the record itself: no bytes are written, and the sidecar describes it.
    const linked_key: shared.Key = @splat(31);
    try std.testing.expectEqual(shared.Publication.stored, try store.publishHashedFile(.program, linked_key, locked, digest));
    const linked_record = try store.artifactPath(.program, linked_key);
    try std.testing.expectEqual((try std.Io.Dir.cwd().statFile(io, locked, .{})).inode, (try std.Io.Dir.cwd().statFile(io, linked_record, .{})).inode);
    try std.testing.expect(try store.restore(.program, linked_key, try std.fs.path.join(a, &.{ root, "from-linked" })));
    // A writable file could be changed under the record's sidecar, so it is copied.
    const copied_key: shared.Key = @splat(32);
    try std.testing.expectEqual(shared.Publication.stored, try store.publishHashedFile(.program, copied_key, open, digest));
    const copied_record = try store.artifactPath(.program, copied_key);
    try std.testing.expect((try std.Io.Dir.cwd().statFile(io, open, .{})).inode != (try std.Io.Dir.cwd().statFile(io, copied_record, .{})).inode);
    const restored = try std.fs.path.join(a, &.{ root, "from-copy" });
    try std.testing.expect(try store.restore(.program, copied_key, restored));
    try std.testing.expectEqualStrings(bytes, try std.Io.Dir.cwd().readFileAlloc(io, restored, a, .limited(256)));
    // Linked or copied, the same program published again is present, and another digest is a mismatch.
    try std.testing.expectEqual(shared.Publication.present, try store.publishHashedFile(.program, linked_key, locked, digest));
    var other = digest;
    other[0] ^= 1;
    try std.testing.expectEqual(shared.Publication.mismatch, try store.publishHashedFile(.program, linked_key, locked, other));
}

// spec-case: PROGRAM-RECORD-2
test "holdsProgram answers from the sidecar and the executable's size, and reads no bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const bytes = "linked executable";
    var digest: shared.Key = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    const key: shared.Key = @splat(33);
    const source = try std.fs.path.join(a, &.{ root, "program" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source, .data = bytes });
    try std.testing.expect(!store.holdsProgram(key, digest));
    try std.testing.expectEqual(shared.Publication.stored, try store.publishHashedFile(.program, key, source, digest));
    try std.testing.expect(store.holdsProgram(key, digest));
    var other = digest;
    other[0] ^= 1;
    try std.testing.expect(!store.holdsProgram(key, other));
    try std.testing.expect(!store.holdsProgram(@splat(34), digest));
    // The record's bytes are not read: an executable of the right size with other bytes is still held. Whoever restores it checks them.
    const artifact = try store.artifactPath(.program, key);
    try damaged(io, artifact);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = "LINKED EXECUTABLE" });
    try std.testing.expect(store.holdsProgram(key, digest));
    try std.testing.expect(!try store.restore(.program, key, try std.fs.path.join(a, &.{ root, "never" })));
    // A truncated executable is not held.
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = artifact, .data = "LINKED" });
    try std.testing.expect(!store.holdsProgram(key, digest));
    // A held record whose use is over an hour old gets its recency refreshed (retention reads the modification time).
    try std.testing.expectEqual(shared.Publication.stored, try store.publishHashedFile(.program, key, source, digest));
    const old: std.Io.Timestamp = .{ .nanoseconds = std.Io.Timestamp.now(io, .real).nanoseconds - 3 * 3600 * std.time.ns_per_s };
    const record = try std.Io.Dir.cwd().openFile(io, artifact, .{});
    defer record.close(io);
    try record.setTimestamps(io, .{ .modify_timestamp = .{ .new = old } });
    try std.testing.expect(store.holdsProgram(key, digest));
    const idle = std.Io.Timestamp.now(io, .real).nanoseconds - (try record.stat(io)).mtime.nanoseconds;
    try std.testing.expect(idle < 3600 * std.time.ns_per_s);
}

test "a publication makes its kind directory once, and again after a sweep removed it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = try shared.Store.open(a, io, root);
    defer store.deinit();
    const first: shared.Key = @splat(5);
    const second: shared.Key = @splat(6);
    const third: shared.Key = @splat(7);
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.engine_record, first, "first"));
    // The directory is known now: a second publication stores into it without making it (it would fail on a read-only parent, and the memo says it is there).
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.engine_record, second, "second"));
    // A sweep removes the whole kind directory under the process: the publication that finds it gone makes it again and is not lost.
    const directory = try std.fs.path.join(a, &.{ store.root, "engine_record" });
    try std.Io.Dir.cwd().deleteTree(io, directory);
    try std.testing.expectEqual(shared.Publication.stored, try store.save(.engine_record, third, "third"));
    try std.testing.expectEqualStrings("third", (try store.load(a, .engine_record, third)).?);
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .engine_record, first));
}
