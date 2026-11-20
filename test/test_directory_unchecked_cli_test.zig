//! A test directory with one file that does not check reports that file once, naming the cause
//! (TEST-DIR-UNCHECKED-1).
const std = @import("std");
const testing = std.testing;

/// Occurrences of `needle` in `haystack`.
fn occurrences(haystack: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, haystack, needle);
}

// spec: TEST-DIR-UNCHECKED-1
test "a test file that does not check is reported once, as failing to check" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(testing.io, "suite", .default_dir);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "suite/ok_test.selka", .data = "public func test_fine() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "suite/broken_test.selka", .data = "public func test_broken() -> bool:\n    return 1\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, "suite", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".cache" });
    defer testing.allocator.free(cache);
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ @import("test_paths").corePath(), "test", root, "--cache-dir", cache },
        .environ_map = &environment,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "error[E_TYPE]") != null);
    // One line for the broken file, in words that say what happened and where the cause is.
    try testing.expectEqual(@as(usize, 1), occurrences(result.stdout, "broken_test.selka"));
    try testing.expect(std.mem.indexOf(u8, result.stdout, "broken_test.selka: failed to check or build") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "was not loaded") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "no usable report") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 failed") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "ok_test::test_fine") != null);
}
