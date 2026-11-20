//! The stage store a process shares (`Options.process_shared`, `stage_pack.State.acquire`): the process indexes each pack
//! once, a later session lists the directory and reads only what is new, and what vanished is dropped.
const std = @import("std");
const store = @import("stage_store.zig");
const stage_pack = @import("stage_pack.zig");

/// The key of the `index`-th test value, under a scope no other test file uses.
fn valueKey(storage: *const store.Store, index: usize) store.Digest {
    const discriminator: [1]u8 = .{@intCast(index)};
    return storage.key("process-shared", &.{&discriminator});
}

/// Save and seal `count` values, one pack each, as one process per value would.
fn sealValues(storage: *store.Store, first: usize, count: usize) !void {
    var payload: [64]u8 = @splat(7);
    for (first..first + count) |index| {
        payload[0] = @intCast(index);
        try std.testing.expect(try storage.save(valueKey(storage, index), &payload));
        try std.testing.expect(try storage.flush());
    }
}

/// A session of this process on the store under `root`: its catalog is the process's.
fn session(a: std.mem.Allocator, root: []const u8) !store.Store {
    return store.Store.initWithOptions(a, std.testing.io, root, .{ .process_shared = true });
}

test "a second session of the process shares the first one's catalog and reads no pack again" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 3);
    var first = try session(std.testing.allocator, root);
    try std.testing.expect(try first.contains(valueKey(&first, 0)));
    try std.testing.expect(try first.contains(valueKey(&first, 2)));
    try std.testing.expect(!(try first.contains(valueKey(&first, 3))));
    try std.testing.expectEqual(@as(u64, 3), first.statistics().indexes_read);
    first.deinit();
    var second = try session(std.testing.allocator, root);
    defer second.deinit();
    try std.testing.expect(try second.contains(valueKey(&second, 1)));
    try std.testing.expectEqual(@as(u64, 3), second.statistics().indexes_read);
    try std.testing.expectEqual(@as(usize, 0), (try second.touchedKeys(arena.allocator())).len);
}

test "a pack another writer publishes between two sessions is found, and only that pack is read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 2);
    var first = try session(std.testing.allocator, root);
    try std.testing.expect(!(try first.contains(valueKey(&first, 2))));
    first.deinit();
    try sealValues(&writer, 2, 1);
    var second = try session(std.testing.allocator, root);
    defer second.deinit();
    try std.testing.expect(try second.contains(valueKey(&second, 2)));
    try std.testing.expect(try second.contains(valueKey(&second, 0)));
    try std.testing.expectEqual(@as(u64, 3), second.statistics().indexes_read);
}

test "a compaction by another writer is honoured: kept records come from the new pack, dropped ones read as absent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 4);
    var before = try session(std.testing.allocator, root);
    try std.testing.expect(try before.contains(valueKey(&before, 3)));
    before.deinit();
    var ranks: stage_pack.Ranks = .empty;
    try ranks.put(a, stage_pack.rankKey(valueKey(&writer, 0)), 0);
    try ranks.put(a, stage_pack.rankKey(valueKey(&writer, 1)), 1);
    _ = (try writer.storage.compactLive(&ranks, stage_pack.default_band_bytes)) orelse return error.TestUnexpectedResult;
    var after = try session(std.testing.allocator, root);
    defer after.deinit();
    try std.testing.expect(try after.contains(valueKey(&after, 0)));
    try std.testing.expect(try after.contains(valueKey(&after, 1)));
    try std.testing.expect(!(try after.contains(valueKey(&after, 2))));
    try std.testing.expect(!(try after.contains(valueKey(&after, 3))));
    try std.testing.expectEqual(@as(u64, 5), after.statistics().indexes_read);
    const kept = (try after.load(a, valueKey(&after, 1))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 1), kept[0]);
    try std.testing.expectEqual(@as(?[]u8, null), try after.load(a, valueKey(&after, 3)));
}

test "a directory removed between two sessions leaves the next session an empty store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 2);
    var first = try session(std.testing.allocator, root);
    try std.testing.expect(try first.contains(valueKey(&first, 0)));
    first.deinit();
    try std.Io.Dir.cwd().deleteTree(std.testing.io, try std.fs.path.join(a, &.{ root, "stages-packed-v1" }));
    var second = try session(std.testing.allocator, root);
    defer second.deinit();
    try std.testing.expect(!(try second.contains(valueKey(&second, 0))));
    try std.testing.expect(!(try second.contains(valueKey(&second, 1))));
    try std.testing.expectEqual(@as(?[]u8, null), try second.load(a, valueKey(&second, 0)));
}
