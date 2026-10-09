//! Native receipt policy separation and integrity recovery.
const std = @import("std");
const receipt = @import("native_receipt.zig");
const emission = @import("emission_cache.zig");
const store = @import("stage_store.zig");
const units = @import("unit_cache.zig");

const settings: units.Settings = .{ .tool = @splat(1), .cpu = @splat(2), .runtime = @splat(3), .mode = .optimized_debug };
const artifact: emission.Artifact = .{ .text = "define i32 @f() { ret i32 7 }", .number = true, .math = false, .counting = false };

fn path(a: std.mem.Allocator, storage: *const store.Store, key: store.Digest) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}/{s}.stage", .{ storage.root, std.fmt.bytesToHex(key, .lower) });
}

// spec-case: NEW-CORE-STAGE-CACHE-9
test "native receipts preserve exact keys and isolate every native setting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const handle: emission.NativeArtifact = .{ .store = &storage, .key = storage.key("llvm-test", &.{}) };
    const exact = units.key(settings, artifact.text);
    try std.testing.expect((try receipt.lookup(a, handle, settings)) == null);
    try receipt.remember(handle, settings, exact);
    try std.testing.expectEqual(exact, (try receipt.lookup(a, handle, settings)).?);
    var changed = settings;
    changed.tool[0] ^= 1;
    try std.testing.expect((try receipt.lookup(a, handle, changed)) == null);
    changed = settings;
    changed.cpu[0] ^= 1;
    try std.testing.expect((try receipt.lookup(a, handle, changed)) == null);
    changed = settings;
    changed.runtime[0] ^= 1;
    try std.testing.expect((try receipt.lookup(a, handle, changed)) == null);
    changed = settings;
    changed.mode = .debug;
    try std.testing.expect((try receipt.lookup(a, handle, changed)) == null);
    changed.mode = .release;
    try std.testing.expect((try receipt.lookup(a, handle, changed)) == null);
    const other: emission.NativeArtifact = .{ .store = &storage, .key = storage.key("llvm-test", &.{"other"}) };
    try std.testing.expect((try receipt.lookup(a, other, settings)) == null);
    const policy = units.key(settings, "");
    const map_key = storage.key("native-unit-receipt-v1", &.{ &policy, &handle.key });
    try std.testing.expect(try storage.save(map_key, "bad mapping schema"));
    try std.testing.expect((try receipt.lookup(a, handle, settings)) == null);
    try receipt.remember(handle, settings, exact);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try path(a, &storage, map_key), .data = "damaged" });
    try std.testing.expect((try receipt.lookup(a, handle, settings)) == null);
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try path(a, &storage, map_key));
    try std.testing.expect((try receipt.lookup(a, handle, settings)) == null);
}

// spec-case: NEW-CORE-STAGE-CACHE-9
test "native receipts reload verified LLVM and reject missing corrupt or malformed artifacts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const handle: emission.NativeArtifact = .{ .store = &storage, .key = storage.key("llvm-test", &.{}) };
    try std.testing.expectError(error.CacheMiss, receipt.materialize(a, handle));
    try storage.storeValue(handle.key, emission.Artifact, artifact);
    const loaded = try receipt.materialize(a, handle);
    try std.testing.expectEqualStrings(artifact.text, loaded.text);
    try std.testing.expectEqual(artifact.number, loaded.number);
    try std.testing.expectEqual(artifact.math, loaded.math);
    try std.testing.expectEqual(artifact.counting, loaded.counting);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try path(a, &storage, handle.key), .data = "damaged" });
    try std.testing.expectError(error.CacheMiss, receipt.materialize(a, handle));
    try std.testing.expect(try storage.save(handle.key, "bad artifact schema"));
    try std.testing.expectError(error.CacheMiss, receipt.materialize(a, handle));
}
