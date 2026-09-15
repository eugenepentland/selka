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
        \\    items: list[i64]
        \\
        \\
        \\def make() -> Box:
        \\    return Box(items=[40])
        \\
        \\
        \\def main() -> i64:
        \\    b = make()
        \\    b.items.append(2)
        \\    rows: list[list[i64]] = [b.items, []]
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
        \\def receiver(log: list[i64], rows: list[Point]) -> list[Point]:
        \\    log.append(1)
        \\    return rows
        \\
        \\
        \\def index(log: list[i64]) -> i64:
        \\    log.append(2)
        \\    return 0
        \\
        \\
        \\def value(log: list[i64]) -> i64:
        \\    log.append(3)
        \\    return 42
        \\
        \\
        \\def main() -> i64:
        \\    log: list[i64] = []
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
        \\def set[T](cells: list[Cell[T]], value: T):
        \\    cells[0].value = value
        \\
        \\
        \\def main() -> i64:
        \\    cells: list[Cell[i64]] = [Cell[i64](value=1)]
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

// spec: PY-COLLECTIONS-14
test "slice step selects every nth element of a list and of text in both directions" {
    try run(
        \\def main() -> i64:
        \\    items = [1, 2, 3, 4, 5, 6]
        \\    text = "abcdef"
        \\    if len(items[0:6:2]) != 3 or items[0:6:2][1] != 3:
        \\        return 1
        \\    if len(items[::-1]) != 6 or items[::-1][0] != 6:
        \\        return 2
        \\    if len(items[5:0:-2]) != 3 or items[5:0:-2][1] != 4:
        \\        return 3
        \\    if len(items[99:0:-1]) != 5 or len(items[0:6:99]) != 1:
        \\        return 4
        \\    if text[1:5:2] != "bd" or len(text[::-2]) != 3:
        \\        return 5
        \\    if text[4:0:-3] != "eb" or len(text[2:2:1]) != 0:
        \\        return 6
        \\    return items[-1:0:-2][0] * 7
    , 42);
}

// spec: PY-AUGASSIGN-1
test "augmented assignment applies each binding type's own operator rules" {
    try run(
        \\def main() -> i64:
        \\    n = 5
        \\    n *= 8
        \\    n += 2
        \\    m = 17
        \\    m //= 2
        \\    if m != 8:
        \\        return 1
        \\    m %= 5
        \\    if m != 3:
        \\        return 2
        \\    ratio = 1.0
        \\    ratio += 2.5
        \\    ratio *= 2.0
        \\    if int(ratio) != 7:
        \\        return 3
        \\    ratio -= 0.5
        \\    if int(ratio) != 6:
        \\        return 4
        \\    label = "a"
        \\    label += "b"
        \\    if label != "ab":
        \\        return 5
        \\    return n
    , 42);
}

// spec: PY-AUGASSIGN-2
test "augmented assignment writes a list slot and a dictionary entry in place" {
    try run(
        \\def main() -> i64:
        \\    xs = [1, 2]
        \\    xs[0] += 5
        \\    xs[1] *= 3
        \\    xs[-1] -= 6
        \\    counts = {"a": 1}
        \\    counts["a"] += 41
        \\    label = {"k": "a"}
        \\    label["k"] += "b"
        \\    if xs[0] != 6 or xs[1] != 0:
        \\        return 1
        \\    if label["k"] != "ab":
        \\        return 2
        \\    return counts["a"]
    , 42);
}

// spec: PY-COLLECTIONS-15
test "list methods mutate in place with Python-shaped bounds" {
    try run(
        \\def main() -> i64:
        \\    xs = [3, 1, 2]
        \\    xs.sort()
        \\    if xs[0] != 1 or xs[2] != 3:
        \\        return 1
        \\    xs.reverse()
        \\    if xs[0] != 3 or xs[2] != 1:
        \\        return 2
        \\    xs.insert(0, 9)
        \\    if xs[0] != 9 or len(xs) != 4:
        \\        return 3
        \\    xs.remove(9)
        \\    if xs[0] != 3 or len(xs) != 3:
        \\        return 4
        \\    xs.extend([7, 8])
        \\    if len(xs) != 5 or xs[4] != 8:
        \\        return 5
        \\    last = xs.pop()
        \\    if last != 8 or len(xs) != 4:
        \\        return 6
        \\    middle = xs.pop(1)
        \\    if middle != 2 or len(xs) != 3:
        \\        return 7
        \\    xs.clear()
        \\    if len(xs) != 0:
        \\        return 8
        \\    return 42
    , 42);
}

// spec: PY-COLLECTIONS-16
test "list index and copy are read forms with first-occurrence order" {
    try run(
        \\def main() -> i64:
        \\    xs = [10, 20, 30, 20]
        \\    if xs.index(20) != 1:
        \\        return 1
        \\    ys = xs.copy()
        \\    ys.append(99)
        \\    if len(xs) != 4 or len(ys) != 5:
        \\        return 2
        \\    return ys[4] + xs[0] - 67
    , 42);
}

// spec: PY-COLLECTIONS-17
test "dictionary pop update and setdefault keep insertion order" {
    try run(
        \\def main() -> i64:
        \\    d = {"a": 1, "b": 2}
        \\    if d.pop("a") != 1:
        \\        return 1
        \\    if d.pop("z", 7) != 7:
        \\        return 2
        \\    d.update({"b": 20, "c": 3})
        \\    if d["b"] != 20 or d["c"] != 3:
        \\        return 3
        \\    if d.setdefault("d", 4) != 4:
        \\        return 4
        \\    if d.setdefault("d", 9) != 4:
        \\        return 5
        \\    if len(d) != 3:
        \\        return 6
        \\    return 42
    , 42);
}

// spec: PY-COLLECTIONS-18
test "list += extends in place and items yields the value snapshot in order" {
    try run(
        \\def main() -> i64:
        \\    xs = [1]
        \\    alias = xs
        \\    xs += [2, 3]
        \\    if len(xs) != 3 or len(alias) != 3:
        \\        return 1
        \\    d = {"a": 1, "b": 2}
        \\    total = 0
        \\    for position, value in d.items():
        \\        total += position + value
        \\    if total != 4:
        \\        return 2
        \\    return 42
    , 42);
}

// spec: PY-COLLECTIONS-19
test "push is rejected with a migration diagnostic naming append" {
    var compilation = try language.Compilation.init(t.allocator, "push.my",
        \\def main() -> i64:
        \\    xs = [1]
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
        \\def main() -> i64:
        \\    xs = [1, 2]
        \\    return xs.index(9)
        , .code = "R_LIST_VALUE" },
        .{ .source =
        \\def main() -> i64:
        \\    xs: list[i64] = []
        \\    return xs.pop()
        , .code = "R_LIST_BOUNDS" },
        .{ .source =
        \\def main() -> i64:
        \\    d = {"a": 1}
        \\    return d.pop("z")
        , .code = "R_MISSING_KEY" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "absent.my", case.source);
        defer compilation.deinit();
        const result = try native.runWithOptions(&compilation, .{ .gc_stress = true });
        try t.expect(result.trapped());
        try t.expectEqualStrings(case.code, result.trap.code);
    }
}

// spec: PY-COLLECTIONS-11
test "outer annotated postfix expressions do not contaminate literal element inference" {
    try run(
        \\def main() -> i64:
        \\    value: i64 = [42][0]
        \\    row: list[i64] = [[value]][0]
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
        \\def change(rows: list[Point]) -> i64:
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
        \\def duplicate[T: copy + storable](value: T) -> list[T]:
        \\    values: list[T] = [value]
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
