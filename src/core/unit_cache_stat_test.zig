//! The unit object store serves an object by the stat tuple its writer recorded, and hashes any object whose tuple moved (G4c part 2b).
const std = @import("std");
const unit_cache = @import("unit_cache.zig");

const key: unit_cache.Digest = @splat(0x5a);

/// A store under `root`, holding the object `bytes` published under `key`; the object's path is returned beside it.
const Fixture = struct { store: unit_cache.Store, object: []const u8, record: []const u8 };

fn publish(a: std.mem.Allocator, root: []const u8, bytes: []const u8) !Fixture {
    const io = std.testing.io;
    const store: unit_cache.Store = .{ .directory = try std.fmt.allocPrint(a, "{s}/units-v1", .{root}) };
    const staged = try std.fmt.allocPrint(a, "{s}/staged.o", .{root});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = staged, .data = bytes });
    const published = try store.publish(a, io, key, ".o", staged);
    return .{ .store = store, .object = published.path, .record = try std.fmt.allocPrint(a, "{s}.sum", .{published.path}) };
}

fn tamperDigest(a: std.mem.Allocator, record: []const u8) !void {
    const io = std.testing.io;
    const text = try std.Io.Dir.cwd().readFileAlloc(io, record, a, .limited(1024));
    const at = std.mem.indexOfScalar(u8, text, '\n').? + 1;
    const second = std.mem.indexOfScalarPos(u8, text, at, '\n').? + 1;
    const changed = try a.dupe(u8, text);
    changed[second] = if (changed[second] == '0') '1' else '0';
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = record, .data = changed });
}

fn rootOf(a: std.mem.Allocator, directory: *std.testing.TmpDir) ![]const u8 {
    return directory.dir.realPathFileAlloc(std.testing.io, ".", a);
}

test "an object whose stat tuple is the one its writer recorded is served without being read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const fixture = try publish(a, try rootOf(a, &directory), "object bytes of one unit");
    const honest = (try fixture.store.lookup(a, std.testing.io, key, ".o")).?;
    // A record whose digest is wrong but whose tuple still matches is believed: the bytes are not hashed.
    try tamperDigest(a, fixture.record);
    const believed = (try fixture.store.lookup(a, std.testing.io, key, ".o")).?;
    try std.testing.expect(!std.mem.eql(u8, &honest.digest, &believed.digest));
    try std.testing.expectEqualStrings(fixture.object, believed.path);
}

test "an object rewritten in place, with the same size, is hashed and refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const fixture = try publish(a, try rootOf(a, &directory), "object bytes of one unit");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = fixture.object, .data = "OBJECT bytes of one unit" });
    try std.testing.expectEqual(@as(?unit_cache.Found, null), try fixture.store.lookup(a, std.testing.io, key, ".o"));
}

test "a truncated object is hashed and refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const fixture = try publish(a, try rootOf(a, &directory), "object bytes of one unit");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = fixture.object, .data = "object bytes" });
    try std.testing.expectEqual(@as(?unit_cache.Found, null), try fixture.store.lookup(a, std.testing.io, key, ".o"));
}

test "an equal copy under another inode is hashed, served, and recorded for the next lookup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const fixture = try publish(a, try rootOf(a, &directory), "object bytes of one unit");
    const io = std.testing.io;
    try std.Io.Dir.cwd().deleteFile(io, fixture.object);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fixture.object, .data = "object bytes of one unit" });
    const first = (try fixture.store.lookup(a, io, key, ".o")).?;
    try tamperDigest(a, fixture.record);
    const second = (try fixture.store.lookup(a, io, key, ".o")).?;
    // The first lookup hashed and refreshed the record's tuple; the tampered record is then believed, so the second did not hash.
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
}

test "an object published before tuples were recorded is hashed, and its record gains one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const fixture = try publish(a, try rootOf(a, &directory), "object bytes of one unit");
    const io = std.testing.io;
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fixture.record, a, .limited(1024));
    var lines = std.mem.splitScalar(u8, text, '\n');
    _ = lines.next();
    const old = try std.fmt.allocPrint(a, "core-unit-sum-v1\n{s}\n{s}\n", .{ lines.next().?, lines.next().? });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fixture.record, .data = old });
    const hashed = (try fixture.store.lookup(a, io, key, ".o")).?;
    const upgraded = try std.Io.Dir.cwd().readFileAlloc(io, fixture.record, a, .limited(1024));
    try std.testing.expect(std.mem.startsWith(u8, upgraded, "core-unit-sum-v2\n"));
    try std.testing.expectEqualStrings(fixture.object, hashed.path);
}
