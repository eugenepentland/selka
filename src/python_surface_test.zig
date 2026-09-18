//! Surface gaps found while writing the standard library in Python syntax.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "surface.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "surface.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const shapes =
    \\union Shape:
    \\    empty,
    \\    radius: int,
    \\    width: int
    \\
;

// spec: PY-WILDCARD-1
test "case _ covers every variant no earlier arm names" {
    const text = try std.mem.concat(t.allocator, u8, &.{
        shapes,
        \\def measure(shape: Shape) -> int:
        \\    match shape:
        \\        case Shape.radius(value):
        \\            return value * 2
        \\        case _:
        \\            return 1
        \\
        \\def main() -> int:
        \\    return measure(Shape.radius(20)) + measure(Shape.empty) + measure(Shape.width(9))
    });
    defer t.allocator.free(text);
    try execute(text, 42);
}

// spec: PY-WILDCARD-2
test "case _ must come last, must cover something, and must not drop a result payload" {
    const trailing = try std.mem.concat(t.allocator, u8, &.{
        shapes,
        \\def measure(shape: Shape) -> int:
        \\    match shape:
        \\        case _:
        \\            return 1
        \\        case Shape.empty:
        \\            return 0
        \\
        \\def main() -> int:
        \\    return measure(Shape.empty)
    });
    defer t.allocator.free(trailing);
    try reject(trailing, "E_WILDCARD_ARM");
    const exhausted = try std.mem.concat(t.allocator, u8, &.{
        shapes,
        \\def measure(shape: Shape) -> int:
        \\    match shape:
        \\        case Shape.empty:
        \\            return 0
        \\        case Shape.radius(value):
        \\            return value
        \\        case Shape.width(value):
        \\            return value
        \\        case _:
        \\            return 1
        \\
        \\def main() -> int:
        \\    return measure(Shape.empty)
    });
    defer t.allocator.free(exhausted);
    try reject(exhausted, "E_WILDCARD_ARM");
}

// spec: PY-RESERVED-1
test "len and replace name ordinary declarations and members" {
    try execute(
        \\def replace(value: int) -> int:
        \\    return value * 2
        \\
        \\def len(value: int) -> int:
        \\    return value + 1
        \\
        \\def main() -> int:
        \\    text = "a-b"
        \\    changed = text.replace("-", "+")
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
        \\def first_over(values: list[int], bound: int) -> int:
        \\    index = 0
        \\    while True:
        \\        if index >= len(values):
        \\            return -1
        \\        if values[index] > bound:
        \\            return values[index]
        \\        index = index + 1
        \\
        \\def main() -> int:
        \\    return first_over([1, 42, 3], 10)
    , 42);
    try reject(
        \\def looping() -> int:
        \\    while True:
        \\        break
        \\
        \\def main() -> int:
        \\    return looping()
    , "E_MISSING_RETURN");
}

// spec: PY-FLOAT-1
test "prelude float operations replace hand-rolled bit-pattern intrinsics" {
    try execute(
        \\def main() -> int:
        \\    score = 0
        \\    if sqrt(16.0) == 4.0:
        \\        score = score + 1
        \\    if floor(2.7) == 2.0 and ceil(2.1) == 3.0:
        \\        score = score + 2
        \\    if trunc(-2.7) == -2.0 and abs(-2.5) == 2.5:
        \\        score = score + 4
        \\    return score * 6
    , 42);
    try reject("def main() -> int:\n    return int(sqrt(4))\n", "E_TYPE");
    try execute("def sqrt(value: int) -> int:\n    return value * 2\n\ndef main() -> int:\n    return sqrt(21)\n", 42);
}
