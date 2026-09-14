//! Python-surface payload variant construction, patterns and their rejections.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "variant.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

const File = language.embedded_project.File;
const Files = struct {
    entries: []File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

/// Execute a module graph, so declared template names resolve through project names
/// rather than the single-file catalog.
fn executeProject(entries: []File, expected: i64) !void {
    var files: Files = .{ .entries = entries };
    var loaded = language.project.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&loaded);
    var compilation = try language.project_compile.Compilation.init(&index);
    const result = try native.run(&compilation);
    try t.expectEqual(expected, result.value);
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
        .{ .tail = "Shape.empty(1)\n    return 0\n", .code = "E_VARIANT_PAYLOAD" },
        .{ .tail = "Shape.missing(1)\n    return 0\n", .code = "E_TYPE" },
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
    , "E_SHADOWING");
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
        \\def hold[T](value: T) -> Slot[T]:
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
        \\    return choose(held, Box[i64](value=0)).value + choose(hold[i64](0), 0) + choose(empty, 0)
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

// spec-case: PY-VARIANT-3
test "an imported generic variant takes its arguments from the expected type across modules" {
    const main_module =
        \\module main
        \\import model as m
        \\
        \\
        \\def main() -> i64:
        \\    held: m.Slot[m.Box] = m.Slot.some(m.Box(value=42))
        \\    empty: m.Slot[m.Box] = m.Slot.none
        \\    match empty:
        \\        case m.Slot[m.Box].some(other):
        \\            return other.value
        \\        case m.Slot[m.Box].none:
        \\            pass
        \\    match held:
        \\        case m.Slot[m.Box].none:
        \\            return 0
        \\        case m.Slot[m.Box].some(box):
        \\            return box.value
    ;
    const model_module =
        \\module model
        \\export Box
        \\export Slot
        \\
        \\
        \\class Box:
        \\    value: i64
        \\
        \\
        \\union Slot[T]:
        \\    none,
        \\    some: T
    ;
    var entries = [_]File{
        .{ .path = "main.my", .bytes = main_module },
        .{ .path = "model.my", .bytes = model_module },
    };
    try executeProject(&entries, 42);
}
