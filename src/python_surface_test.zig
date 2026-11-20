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

/// Run one program that checks, as an embedded project so it may import a module.
fn executeProject(source: []const u8, expected: i64) !void {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var entry: Entry = .{ .text = source };
    var project: language.embedded_project.Program = undefined;
    try project.init(t.allocator, .{ .context = &entry, .read = Entry.read });
    defer project.deinit();
    try t.expectEqual(expected, (try native.run(&project.compilation)).value);
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
        \\        case radius(value=value):
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
        \\        case empty:
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
        \\        case empty:
        \\            return 0
        \\        case radius(value=value):
        \\            return value
        \\        case width(value=value):
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
    try executeProject(
        \\import strings
        \\
        \\func replace(value: int) -> int:
        \\    return value * 2
        \\
        \\func my_len(value: int) -> int:
        \\    return value + 1
        \\
        \\func main() -> int:
        \\    mut text = "a-b"
        \\    mut changed = strings.replace(text, "-", "+")
        \\    if changed != "a+b":
        \\        return 1
        \\    if replace(21) != 42:
        \\        return 2
        \\    return my_len(41)
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
    // A bare `sqrt` is always the prelude float operation (lane N4), so a module `sqrt` called bare is refused.
    try reject("func sqrt(value: int) -> int:\n    return value * 2\n\nfunc main() -> int:\n    return sqrt(21)\n", "E_BUILTIN_FUNCTION_NAME");
}
