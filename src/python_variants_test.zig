//! Python-surface payload variant construction, patterns and their rejections.
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
    var c = try language.Compilation.init(t.allocator, "variant.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const shapes =
    \\record Point:
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
        \\
        \\
        \\public record Box:
        \\    value: i64
        \\
        \\
        \\public union Slot[T]:
        \\    none,
        \\    some: T
    ;
    var entries = [_]File{
        .{ .path = "main.my", .bytes = main_module },
        .{ .path = "model.my", .bytes = model_module },
    };
    try executeProject(&entries, 42);
}

fn runValue(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "variant_run.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

// spec: PY-VARIANT-4
test "a parenthesized case construction reports arity, unknown, duplicate and missing fields" {
    const header =
        \\union Node:
        \\    atom(text: str, count: i64),
        \\    blank
        \\
        \\def main() -> i64:
        \\    _ =
    ;
    const cases = [_]struct { tail: []const u8, code: []const u8 }{
        .{ .tail = "Node.atom(\"x\", 1, 2)\n    return 0\n", .code = "E_ARITY" },
        .{ .tail = "Node.atom(\"x\", z=1)\n    return 0\n", .code = "E_UNKNOWN_FIELD" },
        .{ .tail = "Node.atom(\"x\", text=\"y\")\n    return 0\n", .code = "E_DUPLICATE_FIELD" },
        .{ .tail = "Node.atom(\"x\")\n    return 0\n", .code = "E_INCOMPLETE_CONSTRUCTION" },
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
        \\union Node:
        \\    atom(text: str, count: i64 = 2),
        \\    blank
        \\
        \\
        \\def measure(node: Node) -> i64:
        \\    match node:
        \\        case Node.blank:
        \\            return 0
        \\        case Node.atom(text, count):
        \\            return len(text) * 100 + count
        \\
        \\
        \\def label(node: Node) -> str:
        \\    match node:
        \\        case Node.blank:
        \\            return ""
        \\        case Node.atom(text, _):
        \\            return text
        \\
        \\
        \\def main() -> i64:
        \\    positional = Node.atom("ab", 5)
        \\    named = Node.atom(text="c", count=7)
        \\    defaulted = Node.atom("de")
        \\    return measure(positional) + measure(named) + measure(defaulted) + len(label(defaulted))
    , 516);
}

// spec-case: PY-VARIANT-4
test "named-field patterns bind one name per field and report mismatches and dropped results" {
    try reject(
        \\union N:
        \\    atom(x: i64, y: i64),
        \\    blank
        \\
        \\def f(n: N) -> i64:
        \\    match n:
        \\        case N.blank:
        \\            return 0
        \\        case N.atom(x):
        \\            return x
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_PATTERN_PAYLOAD");
    try reject(
        \\union N:
        \\    atom(x: Result[i64, str], y: i64),
        \\    blank
        \\
        \\def f(n: N) -> i64:
        \\    match n:
        \\        case N.blank:
        \\            return 0
        \\        case N.atom(_, y):
        \\            return y
        \\
        \\def main() -> i64:
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
        \\def main() -> i64:
        \\    return 0
    , "E_CASE_FIELDS");
    try reject(
        \\result R:
        \\    ok(x: i64, y: i64),
        \\    err: str
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_SCHEMA");
}
