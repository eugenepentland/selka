//! Python collection forms preserve evaluation order and tracing roots.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn run(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "collections.my", text);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{ .gc_stress = true }) catch |err| {
        for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try std.testing.expect(!result.trapped());
    try std.testing.expectEqual(expected, result.value);
}
// spec: PY-COLLECTIONS-1
test "inferred literal indexing negative indices and append" {
    try run(
        \\def main() -> i64:
        \\    items = [40, 1]
        \\    items.append(2)
        \\    return items[0] + items[-1]
    , 42);
}
// spec: PY-COLLECTIONS-4
test "contextual nested lists and receiver fields" {
    try run(
        \\class Box:
        \\    items: List[i64]
        \\
        \\
        \\def make() -> Box:
        \\    return Box(items=[40])
        \\
        \\
        \\def main() -> i64:
        \\    b = make()
        \\    b.items.append(2)
        \\    rows: List[List[i64]] = [b.items, []]
        \\    return rows[0][0] + rows[0][-1]
    , 42);
}
// spec: PY-COLLECTIONS-2
test "slice copies clamps and length uses signed index type" {
    try run(
        \\def main() -> i64:
        \\    items = [1, 40, 2, 8]
        \\    copy = items[-3:99]
        \\    copy[0] = 0
        \\    middle = items[1:3]
        \\    return middle[0] + len(middle)
    , 42);
}
// spec: PY-COLLECTIONS-3
test "foreach enumerate range and continue" {
    try run(
        \\def main() -> i64:
        \\    items = [10, 20, 9]
        \\    sum = 0
        \\    for i, x in enumerate(items):
        \\        sum += i + x
        \\    for i in range(3):
        \\        if i == 0:
        \\            continue
        \\        sum += i
        \\    return sum - 3
    , 42);
}

// spec: PY-COLLECTIONS-5
test "record fields update values and list slots without changing prior copies" {
    try run(
        \\class Point:
        \\    x: i64
        \\
        \\
        \\def main() -> i64:
        \\    point = Point(x=1)
        \\    point.x = 2
        \\    rows = [point]
        \\    before = rows[0]
        \\    rows[0].x = 40
        \\    return before.x + rows[0].x
    , 42);
}
// spec: PY-COLLECTIONS-7
test "field receiver index and right side run once in order under collection stress" {
    try run(
        \\class Point:
        \\    x: i64
        \\
        \\
        \\def receiver(log: List[i64], rows: List[Point]) -> List[Point]:
        \\    log.append(1)
        \\    return rows
        \\
        \\
        \\def index(log: List[i64]) -> i64:
        \\    log.append(2)
        \\    return 0
        \\
        \\
        \\def value(log: List[i64]) -> i64:
        \\    log.append(3)
        \\    return 42
        \\
        \\
        \\def main() -> i64:
        \\    log: List[i64] = []
        \\    rows = [Point(x=0)]
        \\    receiver(log, rows)[index(log)].x = value(log)
        \\    if len(log) != 3:
        \\        return 1
        \\    if log[0] != 3 or log[1] != 1 or log[2] != 2:
        \\        return 2
        \\    return rows[0].x
    , 42);
}
// spec: PY-COLLECTIONS-9
test "generic record slot updates and list aliases remain copyable" {
    try run(
        \\class Cell[T]:
        \\    value: T
        \\
        \\
        \\def set[T](cells: List[Cell[T]], value: T):
        \\    cells[0].value = value
        \\
        \\
        \\def main() -> i64:
        \\    cells: List[Cell[i64]] = [Cell[i64](value=1)]
        \\    set(cells, 42)
        \\    return cells[0].value
    , 42);
}
// spec: PY-COLLECTIONS-10
test "slice negative clamp empty and copy alias semantics" {
    try run(
        \\def main() -> i64:
        \\    items = [40, 2, 8]
        \\    copy = items[-99:-1]
        \\    copy[0] = 1
        \\    if len(items[99:]) != 0 or len(items[2:1]) != 0:
        \\        return 1
        \\    return items[0] + copy[-1]
    , 42);
}

// spec: PY-COLLECTIONS-11
test "outer annotated postfix expressions do not contaminate literal element inference" {
    try run(
        \\def main() -> i64:
        \\    value: i64 = [42][0]
        \\    row: List[i64] = [[value]][0]
        \\    return row[0]
    , 42);
}
// spec: PY-COLLECTIONS-12
test "range end syntax agrees in constant and runtime evaluation" {
    try run(
        \\def total() -> i64:
        \\    sum = 0
        \\    for i in range(7):
        \\        sum += i
        \\    return sum
        \\
        \\
        \\const VALUE: i64 = total()
        \\
        \\
        \\def main() -> i64:
        \\    return VALUE * 2
    , 42);
}

// spec: PY-COLLECTIONS-13
test "field writeback preserves sibling changes made by its right hand side" {
    try run(
        \\class Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def change(rows: List[Point]) -> i64:
        \\    rows[0].y = 2
        \\    return 40
        \\
        \\
        \\def main() -> i64:
        \\    rows = [Point(x=0, y=0)]
        \\    rows[0].x = change(rows)
        \\    return rows[0].x + rows[0].y
    , 42);
}

// spec: PY-COLLECTIONS-6
test "generic lists preserve literal foreach slice and write element types" {
    try run(
        \\def duplicate[T: copy + storable](value: T) -> List[T]:
        \\    values: List[T] = [value]
        \\    values.append(value)
        \\    copy = values[:]
        \\    for item in copy:
        \\        _ = item
        \\    return copy
        \\
        \\
        \\def main() -> i64:
        \\    xs = duplicate(21)
        \\    return xs[0] + xs[1]
    , 42);
}

// spec: PY-COLLECTIONS-8
test "iteration detects alias growth including continue and final step" {
    for ([_][]const u8{
        "for x in items:\n        _ = x\n        alias.append(2)",
        "for x in items:\n        _ = x\n        alias.append(2)\n        continue",
    }) |loop| {
        const source = try std.fmt.allocPrint(t.allocator,
            \\def main() -> i64:
            \\    items = [1]
            \\    alias = items
            \\    {s}
            \\    return 0
        , .{loop});
        defer t.allocator.free(source);
        var compilation = try language.Compilation.init(t.allocator, "mutation.my", source);
        defer compilation.deinit();
        const result = try native.runWithOptions(&compilation, .{ .gc_stress = true });
        try t.expect(result.trapped());
        try t.expectEqualStrings("R_LIST_ITERATION_MUTATION", result.trap.code);
    }
    try run(
        \\def main() -> i64:
        \\    items = [1]
        \\    for x in items:
        \\        _ = x
        \\        items.append(42)
        \\        break
        \\    return items[-1]
    , 42);
}
