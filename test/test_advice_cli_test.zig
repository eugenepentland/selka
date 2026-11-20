//! The advice a test that returned false is given reaches the report of a directory run (FR19, item 8). A directory run reads
//! each root's report back, from a child process or from the root's run in its own process, and used to hand on only the
//! fields it knew: the failure printed with no advice line and `--json` with no `advice` field, though `selka test FILE` had both.
const std = @import("std");
const testing = std.testing;
const paths = @import("test_paths");

const chain_source = "public func test_chain() -> bool:\n    const a = 1\n    const b = 2\n    return a == 1 and b == 3\n\n\n" ++
    "public func test_assert() -> bool:\n    assert 1 + 1 == 3\n    return True\n";
const other_source = "public func test_other() -> bool:\n    const name = \"abc\"\n    return name == \"abc\" and len(name) == 4\n";
const advice_start = "  advice: this test returned false from one expression, so the report cannot say which fact failed: write one `assert` for each fact";

/// Run `selka test t --force` (with `--json` when asked) over the two files, a child process per root or not.
fn runDirectory(directory: std.Io.Dir, json: bool, children: bool) !std.process.RunResult {
    var environment = try paths.privateEnvironment(testing.allocator);
    defer environment.deinit();
    if (children) try environment.put("SELKA_TEST_CHILDREN", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ paths.corePath(), "test", "t", "--force" });
    if (json) try argv.append(testing.allocator, "--json");
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = directory }, .environ_map = &environment });
}

// spec: NEW-CORE-TEST-3
test "a directory run of two files prints the advice of a test that returned false, and none for a failed assert (FR19)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(testing.io, "t", .default_dir);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "t/chain_test.selka", .data = chain_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "t/other_test.selka", .data = other_source });
    for ([_]bool{ false, true }) |children| {
        const text = try runDirectory(temporary.dir, false, children);
        defer testing.allocator.free(text.stdout);
        defer testing.allocator.free(text.stderr);
        errdefer std.debug.print("children={} stdout:\n{s}\nstderr:\n{s}\n", .{ children, text.stdout, text.stderr });
        // Two tests returned false, in two files: both are advised; the failed assert is not.
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, text.stdout, advice_start));
        try testing.expect(std.mem.indexOf(u8, text.stdout, "chain_test::test_chain: expected true, got false\n" ++ advice_start) != null);
        try testing.expect(std.mem.indexOf(u8, text.stdout, "other_test::test_other: expected true, got false\n" ++ advice_start) != null);
        try testing.expect(std.mem.indexOf(u8, text.stdout, "R_ASSERT: 1 + 1 == 3 (left 2, right 3)\n  in ") != null);
        try testing.expect(std.mem.indexOf(u8, text.stdout, "R_ASSERT: 1 + 1 == 3 (left 2, right 3)\n" ++ advice_start) == null);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, text.term);
        const json = try runDirectory(temporary.dir, true, children);
        defer testing.allocator.free(json.stdout);
        defer testing.allocator.free(json.stderr);
        // The field sits beside `reason`, which keeps its own text, on the two tests that returned false only.
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, json.stdout, "\"advice\":\"this test returned false from one expression"));
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, json.stdout, "\"reason\":\"expected true, got false\",\"advice\":"));
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, json.stdout, "\"reason\":\"R_ASSERT: 1 + 1 == 3"));
    }
}
