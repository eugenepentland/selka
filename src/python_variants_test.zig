//! Python-surface payload variant construction, patterns and their rejections.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "variant.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}

fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "variant.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const shapes =
    \\class Point:
    \\    x: i64
    \\    y: i64
    \\
    \\union Shape:
    \\    point: Point,
    \\    radius: i64,
    \\    empty
    \\
    \\def score(shape: Shape) -> i64:
    \\    match shape:
    \\        case Shape.empty:
    \\            return 0
    \\        case Shape.radius(r):
    \\            return r * r
    \\        case Shape.point(p):
    \\            return p.x + p.y
    \\
    \\def main() -> i64:
    \\    total = score(Shape.point(Point(x=2, y=3)))
    \\    total = total + score(Shape.radius(6))
    \\    return total + score(Shape.empty)
;

// spec: PY-VARIANT-1
test "Python payload variant construction names the union case like a call" {
    try execute(shapes, 41);
}

// spec-case: PY-VARIANT-1
test "Python payload variants nest, flow through locals and reach record fields" {
    try execute(
        \\union Link:
        \\    some: i64,
        \\    none
        \\
        \\class Node:
        \\    next: Link
        \\
        \\def step(node: Node) -> i64:
        \\    match node.next:
        \\        case Link.some(id):
        \\            return id
        \\        case Link.none:
        \\            return 0
        \\
        \\def main() -> i64:
        \\    held = Link.some(42)
        \\    filled = Node(next=held)
        \\    empty = Node(next=Link.none)
        \\    return step(filled) + step(empty)
    , 42);
}

// spec: PY-VARIANT-2
test "Python variant construction rejects wrong arity, unknown cases and payload mismatch" {
    const header =
        \\union Shape:
        \\    radius: i64,
        \\    empty
        \\
        \\def main() -> i64:
        \\    _ =
    ;
    const cases = [_]struct { tail: []const u8, code: []const u8 }{
        .{ .tail = "Shape.radius(1, 2)\n    return 0\n", .code = "E_ARITY" },
        .{ .tail = "Shape.radius()\n    return 0\n", .code = "E_ARITY" },
        .{ .tail = "Shape.empty(1)\n    return 0\n", .code = "E_CONSTRUCTION" },
        .{ .tail = "Shape.missing(1)\n    return 0\n", .code = "E_UNKNOWN_FUNCTION" },
        .{ .tail = "Shape.radius(True)\n    return 0\n", .code = "E_TYPE" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, case.tail });
        defer t.allocator.free(text);
        try reject(text, case.code);
    }
}

// spec-case: PY-VARIANT-2
test "a local binding shadowing a union name keeps ordinary member resolution" {
    try reject(
        \\union Shape:
        \\    radius: i64,
        \\    empty
        \\
        \\def main() -> i64:
        \\    Shape = 1
        \\    _ = Shape.radius(2)
        \\    return 0
    , "E_LIST_METHOD");
}

// spec: PY-VARIANT-3
test "a generic variant infers its type arguments from the expected type" {
    try execute(
        \\class Box[T]:
        \\    value: T
        \\
        \\union Slot[T]:
        \\    none,
        \\    some: T
        \\
        \\def wrap[T](value: T) -> Slot[T]:
        \\    return Slot.some(value)
        \\
        \\def choose[T](slot: Slot[T], fallback: T) -> T:
        \\    match slot:
        \\        case Slot.none:
        \\            return fallback
        \\        case Slot.some(value):
        \\            return value
        \\
        \\def main() -> i64:
        \\    held: Slot[Box[i64]] = Slot.some(Box[i64](value=42))
        \\    empty: Slot[i64] = Slot.none
        \\    return choose(held, Box[i64](value=0)).value + choose(wrap[i64](0), 0) + choose(empty, 0)
    , 42);
}

// spec-case: PY-VARIANT-3
test "a generic variant without an expected type reports its missing arguments" {
    try reject(
        \\union Slot[T]:
        \\    none,
        \\    some: T
        \\
        \\def main() -> i64:
        \\    held = Slot.some(1)
        \\    _ = held
        \\    return 0
    , "E_GENERIC_INFERENCE");
}
