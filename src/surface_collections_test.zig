//! collection syntax preserves managed aliasing and value record semantics.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    try t.expectEqual(expected, try fixture.value(t.allocator, bytes));
}

// spec: SURFACE-COLLECTIONS-4
test "list syntax rejects invalid methods element types and indices" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    append(mut values)
        \\    return 0
        , .code = "E_ARITY" },
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    append(mut values, True)
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    values[False] = 1
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\import lists
        \\
        \\
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    lists.remove(mut values, True)
        \\    return 0
        , .code = "E_TYPE" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const report = try fixture.check(arena.allocator(), case.text);
        try t.expect(!report.passed);
        try t.expectEqualStrings(case.code, report.diagnostics[0].code);
    }
}

/// `text` with every edit of `fix` applied, in span order.
fn spliced(a: std.mem.Allocator, text: []const u8, fix: language.diagnostic.Fix) ![]const u8 {
    const edits = try a.alloc(language.diagnostic.Edit, fix.count());
    for (edits, 0..) |*slot, index| slot.* = fix.at(index);
    std.mem.sort(language.diagnostic.Edit, edits, {}, struct {
        fn earlier(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start < right.span.start;
        }
    }.earlier);
    var out: std.ArrayList(u8) = .empty;
    var cursor: usize = 0;
    for (edits) |edit| {
        try out.appendSlice(a, text[cursor..edit.span.start]);
        try out.appendSlice(a, edit.text);
        cursor = edit.span.end;
    }
    try out.appendSlice(a, text[cursor..]);
    return out.toOwnedSlice(a);
}

/// One retired spelling: the retirement answers with the `module` call as its
/// certain repair and the import that makes it resolve, and the repaired program
/// checks and returns `result`.
fn refusedSpelling(text: []const u8, module: []const u8, repair: []const u8, result: i64) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.check(a, text);
    try t.expect(!report.passed);
    const first = report.firstError().?;
    try t.expectEqualStrings("E_METHOD_REMOVED", first.code);
    try t.expect(std.mem.indexOf(u8, first.message, "is a function now") != null);
    const fix = first.provenance.fix.?;
    try t.expectEqualStrings(repair, fix.edit.text);
    try t.expectEqual(@as(usize, 2), fix.count());
    const import = try std.fmt.allocPrint(a, "import {s}", .{module});
    try t.expect(std.mem.indexOf(u8, fix.at(1).text, import) != null);
    const repaired = try spliced(a, report.src.bytes, fix);
    try fixture.accept(a, repaired);
    try t.expectEqual(result, try fixture.value(a, repaired));
}

// spec-case: METHOD-REMOVED-1
test "each of the seven retired list methods is refused with its lists home and the import" {
    const cases = [_]struct { text: []const u8, repair: []const u8, result: i64 }{
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    _ = values.pop()\n    return 0\n", .repair = "lists.pop(mut values)", .result = 0 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    _ = values.pop(0)\n    return 0\n", .repair = "lists.pop_at(mut values, 0)", .result = 0 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    values.extend([3])\n    return len(values)\n", .repair = "lists.extend(mut values, [3])", .result = 3 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    values.insert(0, 3)\n    return len(values)\n", .repair = "lists.insert(mut values, 0, 3)", .result = 3 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    values.remove(1)\n    return len(values)\n", .repair = "lists.remove(mut values, 1)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    return values.index(2)\n", .repair = "lists.index_of(values, 2)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    values.clear()\n    return len(values)\n", .repair = "lists.clear(mut values)", .result = 0 },
        .{ .text = "func main() -> int:\n    mut values = [1, 2]\n    values.reverse()\n    return values[0]\n", .repair = "lists.reverse(mut values)", .result = 2 },
    };
    for (cases) |case| try refusedSpelling(case.text, "lists", case.repair, case.result);
}

// spec-case: METHOD-REMOVED-1
test "each of the nine retired dictionary methods is refused with its dicts home and the import" {
    const cases = [_]struct { text: []const u8, repair: []const u8, result: i64 }{
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    return counts.get(\"a\", 7)\n", .repair = "dicts.get(counts, \"a\", 7)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    mut total = 0\n    for key in counts.keys():\n        total += len(key)\n    return total\n", .repair = "dicts.keys(counts)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    mut total = 0\n    for value in counts.values():\n        total += value\n    return total\n", .repair = "dicts.values(counts)", .result = 1 },
        .{
            .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    mut total = 0\n" ++
                "    for name, value in counts.items():\n        total += value + len(name)\n    return total\n",
            .repair = "dicts.items(counts)",
            .result = 2,
        },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    _ = counts.setdefault(\"b\", 2)\n    return len(counts)\n", .repair = "dicts.setdefault(mut counts, \"b\", 2)", .result = 2 },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    counts.update({\"b\": 2})\n    return len(counts)\n", .repair = "dicts.update(mut counts, {\"b\": 2})", .result = 2 },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    return counts.pop(\"a\")\n", .repair = "dicts.pop(mut counts, \"a\")", .result = 1 },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    return counts.pop(\"z\", 5)\n", .repair = "dicts.pop_default(mut counts, \"z\", 5)", .result = 5 },
        .{ .text = "func main() -> int:\n    mut counts: dict[str, int] = {\"a\": 1}\n    counts.clear()\n    return len(counts)\n", .repair = "dicts.clear(mut counts)", .result = 0 },
    };
    for (cases) |case| try refusedSpelling(case.text, "dicts", case.repair, case.result);
}

// The set family (F-b): each of the nine operations is refused with its sets home
// and the import, and the repaired program runs to the same answer.
test "each of the nine retired set methods is refused with its sets home and the import" {
    const cases = [_]struct { text: []const u8, repair: []const u8, result: i64 }{
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1}\n    seen.add(2)\n    return len(seen)\n", .repair = "sets.add(mut seen, 2)", .result = 2 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1, 2}\n    seen.discard(1)\n    return len(seen)\n", .repair = "sets.discard(mut seen, 1)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1}\n    const other: set[int] = {2}\n    return len(seen.union(other))\n", .repair = "sets.union(seen, other)", .result = 2 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1, 2}\n    const other: set[int] = {2, 3}\n    return len(seen.intersection(other))\n", .repair = "sets.intersection(seen, other)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1, 2}\n    const other: set[int] = {2}\n    return len(seen.difference(other))\n", .repair = "sets.difference(seen, other)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1, 2}\n    const other: set[int] = {2, 3}\n    return len(seen.symmetric_difference(other))\n", .repair = "sets.symmetric_difference(seen, other)", .result = 2 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1}\n    const other: set[int] = {1, 2}\n    if seen.issubset(other):\n        return 1\n    return 0\n", .repair = "sets.subset(seen, other)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1, 2}\n    const other: set[int] = {1}\n    if seen.issuperset(other):\n        return 1\n    return 0\n", .repair = "sets.superset(seen, other)", .result = 1 },
        .{ .text = "func main() -> int:\n    mut seen: set[int] = {1}\n    const other: set[int] = {2}\n    if seen.isdisjoint(other):\n        return 1\n    return 0\n", .repair = "sets.disjoint(seen, other)", .result = 1 },
    };
    for (cases) |case| try refusedSpelling(case.text, "sets", case.repair, case.result);
}

// A set shares the dictionary kind, but its update, pop and clear are its own
// vocabulary (SET-1), so no dictionary home refuses them.
test "a set keeps its update, pop and clear" {
    try t.expectEqual(@as(i64, 2), try fixture.value(t.allocator,
        \\import sets
        \\
        \\func main() -> int:
        \\    mut seen: set[int] = {1}
        \\    sets.update(mut seen, {2, 3})
        \\    _ = sets.pop(mut seen)
        \\    sets.clear(mut seen)
        \\    return len(seen) + 2
        \\
    ));
}
