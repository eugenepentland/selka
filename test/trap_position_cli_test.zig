//! A trap names the line it happened on, in the build that made the binary: lines added above a function move the line a warm
//! build reports, exactly as a cold build reports it. The engine's optimizer parts carry no source positions (G-D13), so what keeps
//! this true is the relocation of positions from the run's lines.
const std = @import("std");
const testing = std.testing;

const header =
    \\# a comment above the function that traps
    \\
;

/// The program after the comment: `pick` traps on an index past the end of a three-element list.
const body =
    \\func pick(items: int[], at: int) -> int:
    \\    return items[at]
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const items = [1, 2, 3]
    \\    print(out, pick(items, 7))
    \\    return 0
    \\
;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// Build `trap.selka` in `dir` into `binary`, with the shared cache `cache` (null: `--no-cache`), and run the binary: its stderr.
fn buildAndRun(dir: std.Io.Dir, binary: []const u8, cache: ?[]const u8) ![]u8 {
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const zig = "--zig=" ++ @import("test_options").zig_path;
    const argv: []const []const u8 = if (cache) |named|
        &.{ compiler, "build", "trap.selka", "-o", binary, "--cache-dir", named, zig }
    else
        &.{ compiler, "build", "trap.selka", "-o", binary, "--no-cache", zig };
    const built = try std.process.run(testing.allocator, testing.io, .{ .argv = argv, .cwd = .{ .dir = dir }, .environ_map = &environment });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const dot_binary = try std.fmt.allocPrint(testing.allocator, "./{s}", .{binary});
    defer testing.allocator.free(dot_binary);
    const trapped = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{dot_binary}, .cwd = .{ .dir = dir } });
    defer testing.allocator.free(trapped.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
    return trapped.stderr;
}

test "lines added above a trapping function move the line a warm build reports, and a cold build reports the same" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "trap.selka", .data = header ++ body });
    const first = try buildAndRun(temporary.dir, "first", "cache");
    defer testing.allocator.free(first);
    try testing.expect(contains(first, "trap.selka:3:12: error[R_LIST_BOUNDS]"));
    try testing.expect(contains(first, "in main at trap.selka:8:16"));
    // Two lines above: the same program, the trap two lines lower, built warm on the cache the first build filled.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "trap.selka", .data = header ++ "# two\n# lines\n" ++ body });
    const moved = try buildAndRun(temporary.dir, "moved", "cache");
    defer testing.allocator.free(moved);
    try testing.expect(contains(moved, "trap.selka:5:12: error[R_LIST_BOUNDS]"));
    try testing.expect(contains(moved, "in main at trap.selka:10:16"));
    try testing.expect(!contains(moved, "trap.selka:3:12"));
    const cold = try buildAndRun(temporary.dir, "cold", null);
    defer testing.allocator.free(cold);
    try testing.expectEqualStrings(cold, moved);
}

/// The same trap, called from a hole on the fourth line of a triple-quoted format string (F-19).
const triple_body =
    \\func pick(items: int[], at: int) -> int:
    \\    return items[at]
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const items = [1, 2, 3]
    \\    const text = f"""first line
    \\second line {pick(items, 1)}
    \\third line
    \\fourth line {pick(items, 7)} end"""
    \\    print(out, text)
    \\    return 0
    \\
;

test "a trap in a hole on a later line of a triple-quoted format string names that line, warm or cold (F-19)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "trap.selka", .data = header ++ triple_body });
    const first = try buildAndRun(temporary.dir, "first", "cache");
    defer testing.allocator.free(first);
    try testing.expect(contains(first, "trap.selka:3:12: error[R_LIST_BOUNDS]"));
    try testing.expect(contains(first, "in main at trap.selka:11:14"));
    // Two lines added inside the literal above the hole: the hole is two lines lower, built warm on the first build's cache.
    const longer = try std.mem.replaceOwned(u8, testing.allocator, header ++ triple_body, "first line\n", "first line\nextra one\nextra two\n");
    defer testing.allocator.free(longer);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "trap.selka", .data = longer });
    const moved = try buildAndRun(temporary.dir, "moved", "cache");
    defer testing.allocator.free(moved);
    try testing.expect(contains(moved, "trap.selka:3:12: error[R_LIST_BOUNDS]"));
    try testing.expect(contains(moved, "in main at trap.selka:13:14"));
    const cold = try buildAndRun(temporary.dir, "cold", null);
    defer testing.allocator.free(cold);
    try testing.expectEqualStrings(cold, moved);
}
