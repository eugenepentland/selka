//! Which modules a directory `fix` run's earlier entries already checked, so a later
//! entry that imports them is not checked again in the same round.
const std = @import("std");

/// Add every path `reached` names to `covered` except the entries themselves. Each
/// new path is copied into `allocator`, so the caller may free `reached` at once.
pub fn add(allocator: std.mem.Allocator, covered: *std.StringHashMapUnmanaged(void), entries: []const []const u8, reached: []const []const u8) error{OutOfMemory}!void {
    for (reached) |path| {
        if (isEntry(entries, path)) continue;
        if (covered.contains(path)) continue;
        try covered.put(allocator, try allocator.dupe(u8, path), {});
    }
}

/// Whether `path` is one of the entries.
fn isEntry(entries: []const []const u8, path: []const u8) bool {
    for (entries) |entry| if (std.mem.eql(u8, entry, path)) return true;
    return false;
}

test "coverage keeps reached modules but never an entry, and copies each path once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var covered: std.StringHashMapUnmanaged(void) = .empty;
    const entries = [_][]const u8{"/root/main.selka"};
    const reached = [_][]const u8{ "/root/main.selka", "/root/helper.selka", "/root/helper.selka" };
    try add(allocator, &covered, &entries, &reached);
    try std.testing.expect(covered.contains("/root/helper.selka"));
    try std.testing.expect(!covered.contains("/root/main.selka"));
    try std.testing.expectEqual(@as(usize, 1), covered.count());
}
