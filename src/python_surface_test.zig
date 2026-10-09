//! Surface gaps found while writing the standard library in Python syntax.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "surface.selka", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "surface.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const shapes =
    \\enum Shape:
    \\    empty
    \\    radius(value: int)
    \\    width(value: int)
    \\
;

// spec: PY-WILDCARD-1
test "case _ covers every variant no earlier arm names" {
    const text = try std.mem.concat(t.allocator, u8, &.{
        shapes,
        \\func measure(shape: Shape) -> int:
        \\    match shape:
        \\        case Shape.radius(value=value):
        \\            return value * 2
        \\        case _:
        \\            return 1
        \\
        \\func main() -> int:
        \\    return measure(Shape.radius(value=20)) + measure(Shape.empty) + measure(Shape.width(value=9))
    });
    defer t.allocator.free(text);
    try execute(text, 42);
}

// spec: PY-WILDCARD-2
test "case _ must come last, must cover something, and must not drop a result payload" {
    const trailing = try std.mem.concat(t.allocator, u8, &.{
        shapes,
        \\func measure(shape: Shape) -> int:
        \\    match shape:
        \\        case _:
        \\            return 1
        \\        case Shape.empty:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return measure(Shape.empty)
    });
    defer t.allocator.free(trailing);
    try reject(trailing, "E_WILDCARD_ARM");
    const exhausted = try std.mem.concat(t.allocator, u8, &.{
        shapes,
        \\func measure(shape: Shape) -> int:
        \\    match shape:
        \\        case Shape.empty:
        \\            return 0
        \\        case Shape.radius(value=value):
        \\            return value
        \\        case Shape.width(value=value):
        \\            return value
        \\        case _:
        \\            return 1
        \\
        \\func main() -> int:
        \\    return measure(Shape.empty)
    });
    defer t.allocator.free(exhausted);
    try reject(exhausted, "E_WILDCARD_ARM");
}

// spec: PY-RESERVED-1
test "len and replace name ordinary declarations and members" {
    try execute(
        \\func replace(value: int) -> int:
        \\    return value * 2
        \\
        \\func len(value: int) -> int:
        \\    return value + 1
        \\
        \\func main() -> int:
        \\    mut text = "a-b"
        \\    mut changed = text.replace("-", "+")
        \\    if changed != "a+b":
        \\        return 1
        \\    if replace(21) != 42:
        \\        return 2
        \\    return len(41)
    , 42);
}

// spec: PY-LOOP-1
test "a while True with no break never falls through to a missing return" {
    try execute(
        \\func first_over(values: int[], bound: int) -> int:
        \\    mut index = 0
        \\    while True:
        \\        if index >= len(values):
        \\            return -1
        \\        if values[index] > bound:
        \\            return values[index]
        \\        index = index + 1
        \\
        \\func main() -> int:
        \\    return first_over([1, 42, 3], 10)
    , 42);
    try reject(
        \\func looping() -> int:
        \\    while True:
        \\        break
        \\
        \\func main() -> int:
        \\    return looping()
    , "E_MISSING_RETURN");
}

// spec: PY-FLOAT-1
test "prelude float operations replace hand-rolled bit-pattern intrinsics" {
    try execute(
        \\func main() -> int:
        \\    mut score = 0
        \\    if sqrt(16.0) == 4.0:
        \\        score = score + 1
        \\    if floor(2.7) == 2.0 and ceil(2.1) == 3.0:
        \\        score = score + 2
        \\    if trunc(-2.7) == -2.0 and abs(-2.5) == 2.5:
        \\        score = score + 4
        \\    return score * 6
    , 42);
    try reject("func main() -> int:\n    return int(sqrt(4))\n", "E_TYPE");
    try execute("func sqrt(value: int) -> int:\n    return value * 2\n\nfunc main() -> int:\n    return sqrt(21)\n", 42);
}
