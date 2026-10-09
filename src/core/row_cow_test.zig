//! A nested store's row update in place (NEW-CORE-PLACE-S4-1) only when nothing else
//! holds the row: a child read that ownership promotes to its own count, or an outer
//! list built by a store that may have copied it, leaves the row shared, so its update
//! keeps the count test (NEW-CORE-ROW-COW-1, NEW-CORE-ROW-COW-2). Rows nothing kept are
//! still updated with no test at all.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");

/// Instructions of operation `op` in IR text (`%N = op …` or `op …` at a line's start).
fn countOp(text: []const u8, op: []const u8) usize {
    var total: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trimStart(u8, raw, " ");
        if (std.mem.indexOf(u8, line, " = ")) |at| {
            if (line.len > 0 and line[0] == '%') line = line[at + 3 ..];
        }
        if (!std.mem.startsWith(u8, line, op)) continue;
        const rest = line[op.len..];
        if (rest.len == 0 or rest[0] == ' ' or rest[0] == '.') total += 1;
    }
    return total;
}

/// The uniqueness tests ownership leaves in `source`, at debug and after the release passes.
fn tests(arena: std.mem.Allocator, source: []const u8) ![2]usize {
    return .{ countOp(try support.ownedText(arena, source), "is_unique"), countOp(try support.optimizedText(arena, source), "is_unique") };
}

/// `b[i][0] = 7` for every row of a fresh `b` in a loop, with `setup` before the loop and
/// `after` printed after it.
fn program(comptime setup: []const u8, comptime after: []const u8) []const u8 {
    return "def main(out: Stream) -> int:\n    b = [[1, 2], [3, 4]]\n" ++ setup ++
        \\    for i in range(2):
        \\        b[i][0] = 7
        \\
    ++ "    out.print(b[1][0]" ++ after ++ ")\n    return 0\n";
}

// spec: NEW-CORE-ROW-COW-1
test "a row read out of a fresh list and kept across a loop's nested store keeps the row update's count test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Nothing keeps a row (a row read whose last use comes before the loop does not
    // either): the outer list and every row are updated in place, untested.
    try std.testing.expectEqual([2]usize{ 0, 0 }, try tests(a, program("    kb = b[1]\n    out.print(kb[0])\n", "")));
    try std.testing.expectEqual([2]usize{ 0, 0 }, try tests(a, program("", "")));
    // `kb = b[1]` is promoted to its own count when the loop consumes `b`: row 1 has two
    // owners, so the row update tests its count (the outer list is still unique).
    const kept = try tests(a, program("    kb = b[1]\n", ", kb[0]"));
    try std.testing.expect(kept[0] >= 1 and kept[1] >= 1);
}

// spec: NEW-CORE-ROW-COW-2
test "an outer list whose push may have copied it does not prove its rows unique" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `snap = b` before the push: the push copies `b`, and the copy shares row 0 with `snap`.
    const shared = try tests(a, program("    snap = b\n    b.append([5, 6])\n", ", snap[0][0]"));
    try std.testing.expect(shared[0] >= 1 and shared[1] >= 1);
    // The same push into a list nothing else holds is in place: still no test.
    try std.testing.expectEqual([2]usize{ 0, 0 }, try tests(a, program("    b.append([5, 6])\n", "")));
}

// spec-case: NEW-CORE-ROW-COW-1
// spec-case: NEW-CORE-ROW-COW-2
test "every aliased-row shape prints the same at debug, release and verify-facts with no leak" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fs.path.join(a, &.{ options.fixtures, "row_cow.my" });
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(a, &.{ options.fixtures, "row_cow.expected" }), a, .limited(1 << 20));
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };
    for (modes, 0..) |flags, index| {
        const output = try std.fmt.allocPrint(a, "{s}/row_cow-{d}", .{ root, index });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", root });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expectEqualStrings(expected, ran.stdout);
    }
}
