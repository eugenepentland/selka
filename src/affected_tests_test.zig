//! Boundary coverage for the `mylang test --affected` derivation.
const std = @import("std");
const language = @import("compiler.zig");
const ref_diff = @import("ref_diff.zig");

// spec-case: AFFECTED-TEST-1
test "affected selection rejects an entry that is not a mylang source" {
    const request: language.affected_tests.Request = .{
        .memory = std.testing.allocator,
        .io = std.testing.io,
        .git_root = ".",
        .entry = "main.txt",
        .reference = "HEAD",
    };
    try std.testing.expectError(error.InvalidEntry, language.affected_tests.changes(request));
}

fn git(allocator: std.mem.Allocator, root: []const u8, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "git", "-C", root });
    try argv.appendSlice(allocator, args);
    const result = try std.process.run(allocator, std.testing.io, .{ .argv = argv.items });
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

// spec-case: AFFECTED-TEST-2
test "one git diff names every changed module, a deleted line and an untracked file" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "\n\nfunc helper() -> int:\n    mut x = 1\n    return x\n\n\nfunc other() -> int:\n    return 2\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "notes.txt", .data = "unrelated\n" });
    try git(std.testing.allocator, root, &.{ "init", "-q" });
    try git(std.testing.allocator, root, &.{ "add", "." });
    try git(std.testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    // Removing a body line is a pure deletion; it still changes `helper`.
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "\n\nfunc helper() -> int:\n    return x\n\n\nfunc other() -> int:\n    return 2\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "fresh_test.my", .data = "\n\npublic func test_fresh() -> bool:\n    return True\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "notes.txt", .data = "changed\n" });
    const changed = try language.affected_tests.changes(.{ .memory = arena.allocator(), .io = std.testing.io, .git_root = root, .entry = "app.my", .reference = "HEAD" });
    try std.testing.expect(changed.reaches("app::helper"));
    try std.testing.expect(!changed.reaches("app::other"));
    try std.testing.expect(changed.reaches("fresh_test::test_fresh"));
    try std.testing.expectError(error.GitFailed, ref_diff.changedModules(arena.allocator(), std.testing.io, root, "no-such-revision"));
}
