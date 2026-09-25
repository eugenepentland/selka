//! Integrated Python text/dictionary syntax and deterministic iteration behavior.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "trapped-values.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings(code, result.trap.code);
}
// spec-case: PY-DICT-1
test "Python values absent keys and structural iteration mutation trap" {
    try trapped("def main() -> int:\n    values = {1:10}\n    return values[2]\n", "R_MISSING_KEY");
    try trapped("def main() -> int:\n    values = {1:10}\n    for key in values:\n        values[2] = key\n    return 0\n", "R_LIST_ITERATION_MUTATION");
    try trapped("def main() -> int:\n    return len(\"text\".split(\"\"))\n", "R_EMPTY_SEPARATOR");
}

// spec: GC-SCAN-PLAN-1
test "a dictionary reclaimed and replaced at its address is traced with the new entry layout" {
    // `d` and `x` are dead after their literals, so a stress collection
    // reclaims them and the string-keyed dictionary is allocated where `d`
    // was. A scan plan cached for `d`'s integer entries would then skip every
    // string key, the collector would reclaim the keys, and the pops would
    // miss.
    var c = try language.Compilation.init(t.allocator, "scan-plan.my",
        \\def main() -> int:
        \\    d: dict[int, int] = {1: 1}
        \\    x = [1, 2]
        \\    s: dict[str, int] = {}
        \\    for i in range(40):
        \\        s[str(i)] = i
        \\    for i in range(40):
        \\        _ = s.pop(str(i))
        \\    return len(s)
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 0), result.value);
}

// spec: GC-SCAN-PLAN-2
test "the collector traces every generated shape by the plan its descriptor carries" {
    // Under stress every allocation collects, and every plan the collector
    // follows is first checked against the runtime's own flattening of the
    // descriptor, so a record, union, fixed array, optional, class body or
    // dictionary entry whose plan named the wrong slots would abort the run
    // or reclaim a string the sums below still read. `Outer` nests a union in
    // a union and `by_label`'s entries hold three references, so both keep
    // the recursive walk beside the planned shapes.
    var c = try language.Compilation.init(t.allocator, "scan-plans.my",
        \\class Node:
        \\    name: str
        \\    left: Option[Node]
        \\    right: Option[Node]
        \\
        \\
        \\record Pair:
        \\    label: str
        \\    count: int
        \\    tail: str
        \\    items: list[int]
        \\
        \\
        \\union Shape:
        \\    empty,
        \\    named: str,
        \\    number: int,
        \\    boxed: Node
        \\
        \\
        \\union Outer:
        \\    wrapped: Shape,
        \\    blank
        \\
        \\
        \\record Grid:
        \\    cells: [3]str
        \\
        \\
        \\def build(depth: int, tag: str) -> Node:
        \\    if depth == 0:
        \\        return Node(name=tag, left=None, right=None)
        \\    return Node(name=tag + str(depth), left=Some(build(depth - 1, tag)), right=Some(build(depth - 1, tag)))
        \\
        \\
        \\def weight(node: Node) -> int:
        \\    left = node.left
        \\    right = node.right
        \\    if left is None or right is None:
        \\        return len(node.name)
        \\    return len(node.name) + weight(left) + weight(right)
        \\
        \\
        \\def measure(shape: Shape) -> int:
        \\    match shape:
        \\        case Shape.empty:
        \\            return 0
        \\        case Shape.named(text):
        \\            return len(text)
        \\        case Shape.number(value):
        \\            return value
        \\        case Shape.boxed(node):
        \\            return weight(node)
        \\
        \\
        \\def main() -> int:
        \\    pairs: list[Pair] = []
        \\    shapes: list[Shape] = []
        \\    outers: list[Outer] = []
        \\    grids: list[Grid] = []
        \\    by_label: dict[str, Pair] = {}
        \\    runs: dict[str, list[int]] = {}
        \\    for i in range(24):
        \\        pair = Pair(label="p" + str(i), count=i, tail=str(i * 7), items=[i, i + 1])
        \\        pairs.append(pair)
        \\        by_label[pair.label] = pair
        \\        runs[str(i)] = [i, i, i]
        \\        shapes.append(Shape.named("s" + str(i)))
        \\        shapes.append(Shape.boxed(build(2, "n" + str(i))))
        \\        outers.append(Outer.wrapped(Shape.named("o" + str(i))))
        \\        grids.append(Grid(cells=[str(i), "x" + str(i), "y" + str(i)]))
        \\    total = 0
        \\    for held in pairs:
        \\        total += len(held.label) + len(held.tail) + len(held.items) + held.count
        \\    for shape in shapes:
        \\        total += measure(shape)
        \\    for outer in outers:
        \\        match outer:
        \\            case Outer.wrapped(inner):
        \\                total += measure(inner)
        \\            case Outer.blank:
        \\                total += 0
        \\    for grid in grids:
        \\        total += len(grid.cells[0]) + len(grid.cells[1]) + len(grid.cells[2])
        \\    for label in by_label:
        \\        total += len(by_label[label].tail)
        \\    for key in runs:
        \\        total += len(runs[key]) + len(key)
        \\    return total
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1398), result.value);
}
