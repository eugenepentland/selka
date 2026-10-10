//! Compact final facts preserve dense results without retaining analysis scratch.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const facts = @import("facts.zig");
const ir = @import("ir.zig");
const deferred = @import("deferred_facts.zig");

fn fixture(a: std.mem.Allocator) !facts.Facts {
    const n = 1000;
    const known: facts.Facts = .{
        .ranges = try a.alloc(?facts.Interval, n),
        .aggregates = .{
            .lists = try a.alloc(facts.ListFact, n),
            .dicts = try a.alloc(facts.DictFact, n),
            .fields = try a.alloc(?[]const ?facts.Interval, n),
        },
        .floats = try a.alloc(?facts.FloatInterval, n),
        .reachable = try a.dupe(bool, &.{ true, true, true, false }),
        .counted = try a.dupe(facts.Counted, &.{.{
            .loop = .{ .id = 777, .header = @fromBackingInt(0), .body = @fromBackingInt(1), .latch = @fromBackingInt(2), .exit = @fromBackingInt(3) },
            .counter = @fromBackingInt(1),
            .start = @fromBackingInt(2),
            .bound = @fromBackingInt(3),
        }}),
    };
    @memset(known.ranges, null);
    @memset(known.aggregates.lists, .{});
    @memset(known.aggregates.dicts, .{});
    @memset(known.aggregates.fields, null);
    @memset(known.floats, null);
    known.ranges[1] = facts.Interval.point(9);
    known.aggregates.fields[7] = try a.dupe(?facts.Interval, &.{ facts.Interval.point(13), null });
    known.aggregates.lists[9] = .{ .length = @fromBackingInt(11), .elements = .{ .lo = 1, .hi = 17 } };
    return known;
}

// spec-case: NEW-CORE-STAGE-CACHE-4
test "deferred final facts retain compact bytes reclaim scratch and preserve nested tables and checker IDs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const known = try fixture(scratch.allocator());
    const expected = try known.clone(a);
    var table = try deferred.Table.init(a, 2);
    table.entries[1] = try deferred.encode(a, known);
    const canonical = table.identity(1).?;
    try std.testing.expectEqual(@as(usize, 777), known.counted[0].loop.id);
    const dense_per_instruction = @sizeOf(?facts.Interval) + @sizeOf(facts.ListFact) + @sizeOf(facts.DictFact) + @sizeOf(?[]const ?facts.Interval) + @sizeOf(?facts.FloatInterval);
    try std.testing.expect(table.entries[1].?.bytes.len < known.ranges.len * dense_per_instruction / 2);
    @constCast(known.counted)[0].loop.id = 999;
    try std.testing.expectEqual(canonical, (try deferred.fingerprint(a, known)).?);
    _ = scratch.reset(.free_all);
    const restored = (try table.load(a, 1)).?;
    try std.testing.expectEqualDeep(expected, restored);
    try std.testing.expectEqual(facts.Interval.point(13), restored.aggregates.fields[7].?[0].?);
    try std.testing.expectEqual(@as(usize, 777), restored.counted[0].loop.id);
    try std.testing.expectEqual(@as(?deferred.Digest, null), table.identity(0));
    try std.testing.expect((try table.load(a, 0)) == null);
    try std.testing.expectEqual(ir.Ref.none, restored.aggregates.lists[0].length);
}

// spec-case: NEW-CORE-STAGE-CACHE-4
test "deferArtifact retains only durable fact handles and load rejects cache loss after admission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const stages = @import("stage_store.zig");
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const known = try fixture(scratch.allocator());
    const expected = try known.clone(a);
    const artifact = try deferred.encode(scratch.allocator(), known);
    const key = store.key("durable-facts-test", &.{&artifact.digest});
    try std.testing.expect(try store.save(key, artifact.bytes));
    var table = try deferred.Table.init(a, 1);
    try table.deferArtifact(a, 0, &store, key, artifact);
    const identity = table.identity(0).?;
    try std.testing.expect(table.entries[0] == null);
    try std.testing.expectEqual(@as(usize, 1), table.handles[0].?.loop_ids.len);
    try std.testing.expect(artifact.bytes.len > @sizeOf(deferred.Handle) * 100);
    _ = scratch.reset(.free_all);
    try std.testing.expectEqualDeep(expected, (try table.load(a, 0)).?);
    try stage_loss.remove(a, &store, key);
    try std.testing.expectEqual(identity, table.identity(0).?);
    try std.testing.expectError(error.CacheMiss, table.load(a, 0));
    try std.testing.expect(try store.save(key, "changed payload with a valid stage checksum"));
    try std.testing.expectError(error.CacheMiss, table.load(a, 0));
    // Fresh facts are usable even when publication was never available.
    table.entries[0] = try deferred.encode(a, expected);
    try std.testing.expectEqualDeep(expected, (try table.load(a, 0)).?);
}
