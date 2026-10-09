//! Python-surface payload variant construction, patterns and their rejections.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

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
    var c = try language.Compilation.init(t.allocator, "variant.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const shapes =
    \\record Point:
    \\    x: i64
    \\    y: i64
    \\
    \\enum Shape:
    \\    point(value: Point)
    \\    radius(value: i64)
    \\    empty
    \\
    \\func score(shape: Shape) -> i64:
    \\    match shape:
    \\        case Shape.empty:
    \\            return 0
    \\        case Shape.radius(value=r):
    \\            return r * r
    \\        case Shape.point(value=p):
    \\            return p.x + p.y
    \\
    \\func main() -> i64:
    \\    mut total = score(Shape.point(value=Point(x=2, y=3)))
    \\    total = total + score(Shape.radius(value=6))
    \\    return total + score(Shape.empty)
;

// spec: PY-VARIANT-2
test "Python variant construction rejects wrong arity, unknown cases and payload mismatch" {
    const header =
        \\enum Shape:
        \\    radius(value: i64)
        \\    empty
        \\
        \\func main() -> i64:
        \\    _ =
    ;
    const cases = [_]struct { tail: []const u8, code: []const u8 }{
        .{ .tail = "Shape.radius(value=1, extra=2)\n    return 0\n", .code = "E_ARITY" },
        .{ .tail = "Shape.radius()\n    return 0\n", .code = "E_INCOMPLETE_CONSTRUCTION" },
        .{ .tail = "Shape.empty(1)\n    return 0\n", .code = "E_VARIANT_PAYLOAD" },
        .{ .tail = "Shape.missing(1)\n    return 0\n", .code = "E_TYPE" },
        .{ .tail = "Shape.radius(value=True)\n    return 0\n", .code = "E_TYPE" },
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
        \\enum Shape:
        \\    radius(value: i64)
        \\    empty
        \\
        \\func main() -> i64:
        \\    mut Shape = 1
        \\    _ = Shape.radius(2)
        \\    return 0
    , "E_SHADOWING");
}

// spec-case: PY-VARIANT-3
test "a generic variant without an expected type reports its missing arguments" {
    try reject(
        \\enum Slot[T]:
        \\    none
        \\    some(value: T)
        \\
        \\func main() -> i64:
        \\    mut held = Slot.some(value=1)
        \\    _ = held
        \\    return 0
    , "E_GENERIC_INFERENCE");
}

// spec-case: PY-VARIANT-3
test "an imported generic variant takes its arguments from the expected type across modules" {
    const main_module =
        \\import model as m
        \\
        \\
        \\func main() -> i64:
        \\    mut held: m.Slot[m.Box] = m.Slot.some(value=m.Box(value=42))
        \\    mut empty: m.Slot[m.Box] = m.Slot.none
        \\    match empty:
        \\        case m.Slot[m.Box].some(value=other):
        \\            return other.value
        \\        case m.Slot[m.Box].none:
        \\            pass
        \\    match held:
        \\        case m.Slot[m.Box].none:
        \\            return 0
        \\        case m.Slot[m.Box].some(value=box):
        \\            return box.value
    ;
    const model_module =
        \\
        \\
        \\public record Box:
        \\    value: i64
        \\
        \\
        \\public enum Slot[T]:
        \\    none
        \\    some(value: T)
    ;
    var entries = [_]File{
        .{ .path = source_names.entry, .bytes = main_module },
        .{ .path = "model.selka", .bytes = model_module },
    };
    try executeProject(&entries, 42);
}

fn runValue(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "variant_run.selka", text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

// spec: PY-VARIANT-4
test "a parenthesized case construction reports arity, unknown, duplicate and missing fields" {
    const header =
        \\enum Node:
        \\    atom(text: str, count: i64)
        \\    blank
        \\
        \\func main() -> i64:
        \\    _ =
    ;
    const cases = [_]struct { tail: []const u8, code: []const u8 }{
        .{ .tail = "Node.atom(text=\"x\", count=1, extra=2)\n    return 0\n", .code = "E_ARITY" },
        .{ .tail = "Node.atom(text=\"x\", z=1)\n    return 0\n", .code = "E_UNKNOWN_FIELD" },
        .{ .tail = "Node.atom(text=\"x\", text=\"y\")\n    return 0\n", .code = "E_DUPLICATE_FIELD" },
        .{ .tail = "Node.atom(text=\"x\")\n    return 0\n", .code = "E_INCOMPLETE_CONSTRUCTION" },
        .{ .tail = "Node.atom\n    return 0\n", .code = "E_VARIANT_PAYLOAD" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, case.tail });
        defer t.allocator.free(text);
        try reject(text, case.code);
    }
}

// spec-case: PY-VARIANT-4
test "a parenthesized case constructs positionally, by name and with defaults, and reads each field" {
    try runValue(
        \\enum Node:
        \\    atom(text: str, count: i64 = 2)
        \\    blank
        \\
        \\
        \\func measure(node: Node) -> i64:
        \\    match node:
        \\        case Node.blank:
        \\            return 0
        \\        case Node.atom(text=text, count=count):
        \\            return len(text) * 100 + count
        \\
        \\
        \\func label(node: Node) -> str:
        \\    match node:
        \\        case Node.blank:
        \\            return ""
        \\        case Node.atom(text=text, count=_):
        \\            return text
        \\
        \\
        \\func main() -> i64:
        \\    mut positional = Node.atom(text="ab", count=5)
        \\    mut named = Node.atom(text="c", count=7)
        \\    mut defaulted = Node.atom(text="de")
        \\    return measure(positional) + measure(named) + measure(defaulted) + len(label(defaulted))
    , 516);
}

// spec-case: PY-VARIANT-4
test "named-field patterns bind one name per field and report mismatches and dropped results" {
    try reject(
        \\enum N:
        \\    atom(x: i64, y: i64)
        \\    blank
        \\
        \\func f(n: N) -> i64:
        \\    match n:
        \\        case N.blank:
        \\            return 0
        \\        case N.atom(x=x):
        \\            return x
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_PATTERN_PAYLOAD");
    try reject(
        \\enum N:
        \\    atom(x: Result[i64, str], y: i64)
        \\    blank
        \\
        \\func f(n: N) -> i64:
        \\    match n:
        \\        case N.blank:
        \\            return 0
        \\        case N.atom(x=_, y=y):
        \\            return y
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_DISCARD");
}

// spec-case: PY-VARIANT-4
test "a parenthesized case declaration reports empty fields and rejects result cases" {
    try reject(
        \\union N:
        \\    atom(),
        \\    blank
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_CASE_FIELDS");
    try reject(
        \\result R:
        \\    ok(x: i64, y: i64),
        \\    err: str
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_SCHEMA");
}
