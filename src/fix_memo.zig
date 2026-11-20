//! Which check outcomes a later `selka fix` round may reuse. An entry's
//! outcome stands while no round writes a file its source graph read or one
//! its fixes edit; only a complete graph is trusted to name every file read.
const std = @import("std");

/// The files a remembered outcome depends on: its graph's files and the files
/// its fixes edit. Null when the graph is not complete (a load failure, a source
/// that does not parse, a linked path), so that entry is checked every round.
pub fn inputs(allocator: std.mem.Allocator, graph: []const []const u8, complete: bool, edited: []const []const u8) error{OutOfMemory}!?[]const []const u8 {
    if (!complete or graph.len == 0) return null;
    const all = try allocator.alloc([]const u8, graph.len + edited.len);
    @memcpy(all[0..graph.len], graph);
    @memcpy(all[graph.len..], edited);
    return all;
}

/// The paths a round wrote, each also by its canonical path when it resolves,
/// so a file written through a link still matches the graph's canonical paths.
pub fn touched(allocator: std.mem.Allocator, io: std.Io, written: []const []const u8) error{OutOfMemory}!std.StringHashMapUnmanaged(void) {
    var set: std.StringHashMapUnmanaged(void) = .empty;
    for (written) |path| {
        try set.put(allocator, path, {});
        const canonical = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try set.put(allocator, canonical, {});
    }
    return set;
}

/// Whether a round's writes reach an outcome's inputs, so it must be checked again.
pub fn stale(dependencies: []const []const u8, written: *const std.StringHashMapUnmanaged(void)) bool {
    for (dependencies) |path| if (written.contains(path)) return true;
    return false;
}

test "an outcome is remembered only from a complete graph, and depends on its graph and its fixes' files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const graph = [_][]const u8{ "/p/main.selka", "/p/util.selka" };
    const edited = [_][]const u8{"/p/util.selka"};
    try std.testing.expectEqual(@as(?[]const []const u8, null), try inputs(a, &graph, false, &edited));
    try std.testing.expectEqual(@as(?[]const []const u8, null), try inputs(a, &.{}, true, &edited));
    const kept = (try inputs(a, &graph, true, &edited)).?;
    try std.testing.expectEqual(@as(usize, 3), kept.len);
    try std.testing.expectEqualStrings("/p/main.selka", kept[0]);
    try std.testing.expectEqualStrings("/p/util.selka", kept[2]);
}

test "a write to any file an outcome read or would edit makes it stale, and others stay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const written = try touched(a, std.testing.io, &.{"/p/absent/util.selka"});
    try std.testing.expect(stale(&.{ "/p/main.selka", "/p/absent/util.selka" }, &written));
    try std.testing.expect(!stale(&.{ "/p/main.selka", "/p/solo.selka" }, &written));
    try std.testing.expect(!stale(&.{}, &written));
}

test "a file written through a link makes stale an outcome that read its canonical path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.createDirPath(std.testing.io, "real");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "real/util.selka", .data = "" });
    try directory.dir.symLink(std.testing.io, "real", "linked", .{ .is_directory = true });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const canonical = try std.fs.path.join(a, &.{ root, "real", "util.selka" });
    const through_link = try std.fs.path.join(a, &.{ root, "linked", "util.selka" });
    const written = try touched(a, std.testing.io, &.{through_link});
    try std.testing.expect(stale(&.{canonical}, &written));
}
