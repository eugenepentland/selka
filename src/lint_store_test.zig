//! Tests for the `.selka/lint/` baseline and ratchet stores.
const std = @import("std");
const t = std.testing;
const lint_store = @import("lint_store.zig");

fn rootOf(temp: *std.testing.TmpDir) ![:0]u8 {
    return temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
}

// spec: LINT-3
test "lint store saveBaseline loadBaseline saveRatchet loadRatchet round-trip rows and ceilings" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try rootOf(&temp);
    defer t.allocator.free(root);
    var missing = try lint_store.loadBaseline(t.allocator, t.io, root, "dead-private");
    defer missing.deinit();
    try t.expect(!missing.contains("app|app::gone"));
    var baseline: lint_store.Baseline = .{ .allocator = t.allocator };
    defer baseline.deinit();
    try baseline.record("app|app::a");
    try baseline.record("app|app::b");
    try lint_store.saveBaseline(&baseline, t.allocator, t.io, root, "dead-private");
    var loaded = try lint_store.loadBaseline(t.allocator, t.io, root, "dead-private");
    defer loaded.deinit();
    try t.expect(loaded.contains("app|app::a"));
    try t.expect(loaded.contains("app|app::b"));
    var ratchet: lint_store.Ratchet = .{ .allocator = t.allocator };
    defer ratchet.deinit();
    try ratchet.record("app::big", 80);
    try lint_store.saveRatchet(&ratchet, t.allocator, t.io, root, "function-length");
    var reloaded = try lint_store.loadRatchet(t.allocator, t.io, root, "function-length");
    defer reloaded.deinit();
    try t.expectEqual(@as(?usize, 80), reloaded.ceiling("app::big"));
    try t.expectEqual(@as(?usize, null), reloaded.ceiling("app::small"));
}

// spec-case: LINT-3
test "lint store loadBaseline readStore rejects conflict markers with error.ConflictMarkers" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try rootOf(&temp);
    defer t.allocator.free(root);
    try temp.dir.createDirPath(t.io, lint_store.directory);
    const path = try std.fs.path.join(t.allocator, &.{ root, lint_store.directory, "baseline-dead-private.txt" });
    defer t.allocator.free(path);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = "<<<<<<< HEAD\napp|app::a\n=======\n" });
    try t.expectError(error.ConflictMarkers, lint_store.loadBaseline(t.allocator, t.io, root, "dead-private"));
}
