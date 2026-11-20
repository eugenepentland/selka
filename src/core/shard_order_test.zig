//! The order of the core test root's imports is its shard assignment (CORE-SHARD-ORDER-1):
//! the runner gives the named test at position P to shard P mod N and the binary lists tests in
//! import order. Reordering is safe only while the set is untouched, so this checks the set.
const std = @import("std");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();

/// Test files that are not roots of their own: another test file imports them.
const imported_elsewhere = [_][]const u8{"cache_fixture_sources_test.zig"};

fn importsOf(a: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const start = std.mem.indexOf(u8, line, "_ = @import(\"") orelse continue;
        const rest = line[start + "_ = @import(\"".len ..];
        try found.append(a, rest[0 .. std.mem.indexOfScalar(u8, rest, '"') orelse continue]);
    }
    return found.toOwnedSlice(a);
}

fn contains(names: []const []const u8, wanted: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, wanted)) return true;
    return false;
}

fn repeated(names: []const []const u8) usize {
    var count: usize = 0;
    for (names, 0..) |name, index| {
        if (contains(names[0..index], name)) count += 1;
    }
    return count;
}

fn unimportedTestFiles(a: std.mem.Allocator, imports: []const []const u8) !usize {
    var directory = try cwd.openDir(io, "src/core", .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    var missing: usize = 0;
    while (try iterator.next(io)) |entry| {
        const name = try a.dupe(u8, entry.name);
        if (!std.mem.endsWith(u8, name, "_test.zig") or std.mem.eql(u8, name, "root_test.zig")) continue;
        if (contains(&imported_elsewhere, name) or contains(imports, name)) continue;
        missing += 1;
    }
    return missing;
}

// spec: CORE-SHARD-ORDER-1
test "the core test root imports every test file once, so reordering its imports only moves tests between shards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try cwd.readFileAlloc(io, "src/core/root_test.zig", a, .limited(1 << 20));
    const imports = try importsOf(a, text);
    try std.testing.expect(imports.len > 150);
    try std.testing.expectEqual(@as(usize, 0), repeated(imports));
    try std.testing.expectEqual(@as(usize, 0), try unimportedTestFiles(a, imports));
    try std.testing.expect(contains(imports, "shard_order_test.zig"));
}
