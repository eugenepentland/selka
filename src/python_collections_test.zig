//! Python collection forms preserve evaluation order and tracing roots.
const std = @import("std");
const transition = @import("ownership_transition_test_support.zig");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");

// spec: PY-COLLECTIONS-19
test "push is rejected with a migration diagnostic naming append" {
    var compilation = try language.Compilation.init(t.allocator, "push.selka",
        \\func main() -> i64:
        \\    mut xs = [1]
        \\    xs.push(2)
        \\    return len(xs)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_REMOVED_SPELLING", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, "append") != null);
}

// spec: PY-COLLECTIONS-20
test "absent list and dictionary values trap instead of returning a sentinel" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source =
        \\import lists
        \\
        \\
        \\func main() -> i64:
        \\    mut xs = [1, 2]
        \\    return lists.index_of(xs, 9)
        , .code = "R_LIST_VALUE" },
        .{ .source =
        \\import lists
        \\
        \\
        \\func main() -> i64:
        \\    mut xs: i64[] = []
        \\    return lists.pop(mut xs)
        , .code = "R_LIST_BOUNDS" },
        .{ .source =
        \\import dicts
        \\
        \\func main() -> i64:
        \\    mut d = {"a": 1}
        \\    return dicts.pop(mut d, "z")
        , .code = "R_MISSING_KEY" },
    };
    for (cases) |case| try fixture.trap(t.allocator, case.source, .{}, case.code);
}

// spec: PY-COLLECTIONS-20
test "an embedded fixture imports the list module and its writer shortens the list" {
    try t.expectEqual(@as(i64, 1), try fixture.value(t.allocator,
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut xs: int[] = [1, 2]
        \\    _ = lists.pop(mut xs)
        \\    return len(xs)
    ));
}

// spec: PY-COLLECTIONS-20
test "the list module's seven words answer what their retired methods answered" {
    try t.expectEqual(@as(i64, 3712), try fixture.value(t.allocator,
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut values = [3, 1, 2]
        \\    lists.extend(mut values, [7])
        \\    lists.insert(mut values, 1, 9)
        \\    lists.reverse(mut values)
        \\    lists.remove(mut values, 1)
        \\    const tail = lists.pop(mut values)
        \\    const head = lists.pop_at(mut values, 0)
        \\    const at = lists.index_of(values, 9)
        \\    const size = len(values)
        \\    lists.clear(mut values)
        \\    return tail * 1000 + head * 100 + at * 10 + size + len(values)
    ));
}

// spec: METHOD-REMOVED-1
test "a list module writer needs its receiver's mut marker" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    _ = lists.pop(xs)
        \\    return 0
    , "E_MUTATION_MARKER");
}

// spec: PY-COLLECTIONS-20
test "the list module's search words trap when the value is absent" {
    try fixture.trap(t.allocator,
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    return lists.index_of(xs, 9)
    , .{}, "R_LIST_VALUE");
    try fixture.trap(t.allocator,
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    lists.remove(mut xs, 9)
        \\    return len(xs)
    , .{}, "R_LIST_VALUE");
}

// spec: PY-COLLECTIONS-8
test "iteration mutation is rejected even when the loop would break" {
    const source =
        \\func main() -> i64:
        \\    mut items = [1]
        \\    for x in items:
        \\        _ = x
        \\        append(mut items, 42)
        \\        break
        \\    return items[len(items) - 1]
    ;
    try transition.refuses(t.allocator, source, "E_SINGLE_OWNER_OVERLAP");
}

test "record field growth is rejected through the active iterator place" {
    const source =
        \\record Holder:
        \\    items: int[]
        \\func main() -> int:
        \\    mut holder = Holder(items=[7])
        \\    for value in holder.items:
        \\        _ = value
        \\        if value == 7:
        \\            holder.items += [9]
        \\    return len(holder.items)
    ;
    try transition.refuses(t.allocator, source, "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: DICT-TOMBSTONES-1
test "popping and putting back one key of a small dictionary costs the same on the last round as the first" {
    // Before the fix each round scanned every deleted entry before it: 300,000 rounds took over a minute.
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut table: dict[int, int] = {}
        \\    table[1] = 0
        \\    table[2] = 0
        \\    mut cycle = 0
        \\    while cycle < 300000:
        \\        mut value = dicts.pop(mut table, 1)
        \\        table[1] = value + 1
        \\        cycle += 1
        \\    return table[1] // 30000 + len(table)
    );
    defer program.deinit();
    const run = try native.runWithOptions(&program.compilation, .{ .arguments = &.{"--timeout=20"} });
    try t.expect(!run.trapped());
    try t.expectEqual(@as(i64, 12), run.value);
}
