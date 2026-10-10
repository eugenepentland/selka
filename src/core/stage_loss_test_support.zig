//! Packed artifact loss fixtures preserve unrelated discovery and receipt records.
const std = @import("std");
const stage = @import("stage_store.zig");

const PublishError = stage.Error || error{TestUnexpectedResult};
const RemoveError = PublishError || std.Io.Dir.DeleteFileError;
const DamageError = PublishError || std.Io.Dir.OpenError || std.Io.Dir.Iterator.Error || std.Io.Dir.WriteFileError;

/// Publish a duplicate key alone so damaging its pack leaves other keys intact.
pub fn isolatedPath(a: std.mem.Allocator, storage: *const stage.Store, key: stage.Digest) PublishError![]const u8 {
    const payload = (try storage.load(a, key)).?;
    try std.testing.expect(try storage.flush());
    try std.testing.expect(try storage.save(key, payload));
    try std.testing.expect(try storage.flush());
    return (try storage.artifactPath(a, key)).?;
}

/// Remove the newest physical artifact without deleting unrelated cached inputs.
pub fn remove(a: std.mem.Allocator, storage: *const stage.Store, key: stage.Digest) RemoveError!void {
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try isolatedPath(a, storage, key));
}

/// Damage all published packs after flushing any pending journal records.
pub fn damage(storage: *const stage.Store) DamageError!usize {
    try std.testing.expect(try storage.flush());
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, storage.root, .{ .iterate = true });
    defer directory.close(std.testing.io);
    var iterator = directory.iterate();
    var count: usize = 0;
    while (try iterator.next(std.testing.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".pack")) continue;
        try directory.writeFile(std.testing.io, .{ .sub_path = entry.name, .data = "truncated" });
        count += 1;
    }
    return count;
}
