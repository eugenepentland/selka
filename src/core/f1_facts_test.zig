//! Lane F1 (docs/audits/runtime-parity-plan-2026-10-08.md §8): element data tagged by
//! scalar type, no store-back of an unchanged element pointer, and overflow facts for
//! counters, loop variables and floor-mod results. Every expected output is the base
//! compiler's (main cafe7fea7) for the same program and arguments.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The LLVM definition whose `define` line names `symbol`, up to its closing brace.
fn definition(llvm: []const u8, symbol: []const u8) ![]const u8 {
    var lines = std.mem.splitScalar(u8, llvm, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "define ") or std.mem.indexOf(u8, line, symbol) == null) continue;
        const start = @intFromPtr(line.ptr) - @intFromPtr(llvm.ptr);
        const end = std.mem.indexOfPos(u8, llvm, start, "\n}\n") orelse llvm.len;
        return llvm[start..end];
    }
    return error.TestUnexpectedResult;
}

/// How many lines of `text` contain both `first` and `second`.
fn linesWith(text: []const u8, first: []const u8, second: []const u8) usize {
    var total: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (contains(line, first) and contains(line, second)) total += 1;
    }
    return total;
}

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.my` with `flags` and run it with `args` under the leak check.
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}", .{ root, name, flags.len });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

const tagged_elements =
    \\record P:
    \\    x: float
    \\    n: int
    \\
    \\
    \\union Num:
    \\    i: int,
    \\    f: float
    \\
    \\
    \\def touch(xs: mut list[float], rows: mut list[list[int]], ps: mut list[P], us: mut list[Num], k: int) -> int:
    \\    xs[k] = xs[k] + 1.0
    \\    rows[k][k] = rows[k][k] + 1
    \\    ps[k].x = ps[k].x * 2.0
    \\    us[k] = Num.f(float(k))
    \\    return len(rows[k]) + ps[k].n
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    xs = [1.5, 2.5]
    \\    rows = [[1, 2], [3, 4]]
    \\    ps = [P(x=1.0, n=2), P(x=3.0, n=4)]
    \\    us = [Num.i(1), Num.f(2.0)]
    \\    out.print(touch(mut xs, mut rows, mut ps, mut us, 1), xs[1], rows[1][1], ps[1].x)
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-TBAA-1
test "list element data is tagged by its scalar type, and union words keep the generic data tag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), tagged_elements);
    // The element tags are children of `myl.data`, so the generic tag aliases each of them.
    try std.testing.expect(contains(llvm, "!11 = !{!\"myl.data.double\", !6, i64 0}\n!12 = !{!11, !11, i64 0}\n"));
    try std.testing.expect(contains(llvm, "!13 = !{!\"myl.data.i64\", !6, i64 0}\n!14 = !{!13, !13, i64 0}\n"));
    try std.testing.expect(contains(llvm, "!21 = !{!\"myl.data.ptr\", !6, i64 0}\n!22 = !{!21, !21, i64 0}\n"));
    const touch = try definition(llvm, "@\"my.touch\"");
    // A float element, a row pointer, an int element and a record's float field each carry
    // their scalar's tag.
    try std.testing.expect(linesWith(touch, "store double", "!tbaa !12") >= 2);
    try std.testing.expect(linesWith(touch, "load double", "!tbaa !12") >= 2);
    try std.testing.expect(linesWith(touch, "load ptr", "!tbaa !22") >= 1);
    try std.testing.expect(linesWith(touch, "store i64", "!tbaa !14") >= 1);
    // The union element's tag word is stored with the generic tag, and so is its payload:
    // its cases share the payload word.
    try std.testing.expect(linesWith(touch, "store i64", "!tbaa !7") >= 1);
    try std.testing.expect(linesWith(touch, "store double", "!tbaa !7") >= 1);
}

// spec: NEW-CORE-F1-TBAA-2
test "the inline free orders every access before it: a compiler barrier precedes the free-list push" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), tagged_elements);
    const free = try definition(llvm, "@myl_core_free(");
    const barrier = std.mem.indexOf(u8, free, "call void asm sideeffect \"\", \"~{memory}\"()") orelse return error.TestUnexpectedResult;
    const push = std.mem.indexOf(u8, free, "store ptr %block, ptr %slot") orelse return error.TestUnexpectedResult;
    try std.testing.expect(barrier < push);
}

// spec-case: NEW-CORE-F1-TBAA-1
test "typed element tags keep every answer: records copied whole, unions, mixed lists, reused blocks, aliasing rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f1_tbaa", flags, &.{});
        try std.testing.expectEqualStrings("6077 67108861 671088849\n902 30518 100056\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "f1_tbaa", flags, &.{ "x", "y" });
        try std.testing.expectEqualStrings("6234 234881021 968884428\n5055 31739 100084\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
}

const store_backs =
    \\def fill(n: int) -> int:
    \\    c = [[0.5 for j in range(n)] for i in range(n)]
    \\    for i in range(n):
    \\        for j in range(n):
    \\            c[i][j] = c[i][j] + float(j)
    \\    return int(c[n - 1][n - 1])
    \\
    \\
    \\def scale(c: mut list[list[float]], n: int):
    \\    for i in range(n):
    \\        for j in range(n):
    \\            c[i][j] = c[i][j] * 2.0
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    rows = [[1.0, 2.0], [3.0, 4.0]]
    \\    scale(mut rows, 2)
    \\    out.print(fill(4), rows[1][1])
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-STOREBACK-1
test "a row updated in place is not stored back; a row copy on write may move is stored only when it moved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), store_backs);
    // `fill`'s rows are unique, so `c[i][j] = …` updates the row in place and its pointer
    // never changes: the only element pointer store left is the comprehension's push.
    const fill = try definition(llvm, "@\"my.fill\"");
    try std.testing.expectEqual(@as(usize, 1), linesWith(fill, "store ptr", "!tbaa !22"));
    try std.testing.expect(!contains(fill, "%moved"));
    // `scale`'s rows may be shared, so the row's update may copy it: every store-back
    // runs only when the pointer differs from the one the slot holds.
    const scale = try definition(llvm, "@\"my.scale\"");
    const moved = linesWith(scale, "%moved", "icmp ne ptr");
    try std.testing.expect(moved >= 1);
    try std.testing.expectEqual(moved, linesWith(scale, "store ptr", "!tbaa !22"));
}

// spec-case: NEW-CORE-F1-STOREBACK-1
test "store-backs keep every answer: shared rows, rows replaced in the loop, aliasing rows, break and early return, list fields and text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f1_storeback", flags, &.{});
        try std.testing.expectEqualStrings("7000070 600 457114\n-2513 -2993 -3000 8053\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "f1_storeback", flags, &.{ "x", "y" });
        try std.testing.expectEqualStrings("25970094 1750 1399118\n-10353 -11753 -11760 14003\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
}
