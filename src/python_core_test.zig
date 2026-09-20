//! Canonical prelude identities, ordinary numbers, and runner entry conventions.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn run(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "core.my", text);
    defer compilation.deinit();
    const result = native.runWithOptions(&compilation, .{ .gc_stress = true }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}
fn expectMessage(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, failure.code);
    try t.expectEqualStrings(message, failure.message);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "values.my")) return allocator.dupe(u8,
            \\module values
            \\public def answer() -> Result[int, int] effects():
            \\    return Ok(42)
            \\public def maybe() -> Option[int] effects():
            \\    return Some(1)
            \\public def items() -> list[int] effects(managed_allocation):
            \\    return [1, 2]
        );
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return allocator.dupe(u8,
            \\module main
            \\import values
            \\
            \\
            \\def main() -> i64:
            \\    option: Option[i64] = values.maybe()
            \\    match option:
            \\        case Option.some(n):
            \\            if n != 1:
            \\                return 1
            \\        case Option.none:
            \\            return 2
            \\    numbers: list[i64] = values.items()
            \\    if len(numbers) != 2:
            \\        return 3
            \\    match values.answer():
            \\        case Result.ok(n):
            \\            return n
            \\        case Result.err(e):
            \\            return e
        );
    }
};
// spec: PYTHON-CORE-1
test "prelude list Result and Option keep one identity across modules and spellings" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}
// spec: PYTHON-CORE-2
test "unit and checked-result main adapt to scalar status without changing guest call signatures" {
    try run(
        \\def main():
        \\    pass
    , 0);
    try run(
        \\def main() -> Result[None, i64]:
        \\    return Ok(None)
    , 0);
    try run(
        \\def main() -> Result[None, i64]:
        \\    return Err(42)
    , 42);
    try run(
        \\def main() -> Result[i64, i64]:
        \\    return Ok(42)
    , 42);
}

const Entries = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return allocator.dupe(u8, "module main\n\ndef main() -> Result[None, int]:\n    return Ok(None)\n");
    }
};
// spec-case: PYTHON-CORE-2
test "PYTHON-CORE-2 a project with an adapted entry still emits native units" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Entries.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    const manifest = compilation.emitQbe(t.allocator) catch |err| {
        for (compilation.diagnostics.items.items) |diag| debug.print("{s}: {s}\n", .{ diag.code, diag.message });
        return err;
    };
    defer t.allocator.free(manifest);
    // The synthesized wrapper is the entry symbol and names no public export.
    try t.expect(std.mem.indexOf(u8, manifest, "language-schema-v1") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "qbe-units-v1") != null);
}
const PythonModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import helpers
            \\def main() -> int:
            \\    if helpers.Kind.atom != helpers.Kind.atom:
            \\        return 1
            \\    match helpers.answer([42], "answer", 1.5):
            \\        case Ok(values):
            \\            return values["answer"]
            \\        case Err(code):
            \\            return code
        );
        if (std.mem.eql(u8, path, "helpers.my")) return allocator.dupe(u8,
            \\module helpers
            \\public enum Kind:
            \\    atom,
            \\    group
            \\
            \\
            \\public def answer(values: list[int], key: str, number: float) -> Result[dict[str, int], int] effects(managed_allocation):
            \\    if number != 1.5:
            \\        return Err(2)
            \\    return Ok({key: values[0]})
        );
        return error.NotFound;
    }
};
// spec-case: PYTHON-CORE-1
test "Python exported module signatures share builtin types and resolve enum members" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = PythonModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try native.runWithOptions(&compilation, .{ .gc_stress = true })).value);
}
// spec: PYTHON-CORE-3
test "representable integer literals inherit parameter local and expression contexts" {
    try run(
        \\def widen(x: u8) -> i64:
        \\    return i64(x)
        \\
        \\
        \\def main() -> i64:
        \\    n: u8 = 40
        \\    return widen(n + 2)
    , 42);
    try run(
        \\def main() -> i64:
        \\    n: i8 = -128
        \\    wide: u64 = 18446744073709551615
        \\    _ = wide
        \\    return i64(n) + 170
    , 42);
    var compilation = try language.Compilation.init(t.allocator, "range.my",
        \\def main() -> i64:
        \\    x: u8 = 256
        \\    _ = x
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_INTEGER_RANGE", compilation.diagnostics.items[0].code);
}
// spec-case: CALLBACK-EFFECTS-1
test "an explicit narrow callback ceiling still rejects a wider function value" {
    var compilation = try language.Compilation.init(t.allocator, "callback-bound.my",
        \\def tick(value: int) -> int effects(clock):
        \\    _ = value
        \\    return 1
        \\
        \\
        \\def apply(f: def(int) -> int effects(), x: int) -> int:
        \\    return f(x)
        \\
        \\
        \\def main() -> int:
        \\    return apply(tick, 1)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_TYPE", compilation.diagnostics.items[0].code);
}
// spec: DEAD-RECORD-WRITE-1
test "dead record writes reject loop and parameter copies but not fresh locals" {
    var loop = try language.Compilation.init(t.allocator, "dead-loop.my",
        \\record Item:
        \\    visited: bool
        \\
        \\
        \\def main() -> int:
        \\    items = [Item(visited=False)]
        \\    for it in items:
        \\        it.visited = True
        \\    return 0
    );
    defer loop.deinit();
    try t.expectError(error.SourceError, loop.check());
    try t.expectEqualStrings("E_DEAD_RECORD_WRITE", loop.diagnostics.items[0].code);
    var parameter = try language.Compilation.init(t.allocator, "dead-parameter.my",
        \\record Counter:
        \\    n: int
        \\
        \\
        \\def bump(counter: Counter):
        \\    counter.n = 1
        \\
        \\
        \\def main() -> int:
        \\    bump(Counter(n=0))
        \\    return 0
    );
    defer parameter.deinit();
    try t.expectError(error.SourceError, parameter.check());
    try t.expectEqualStrings("E_DEAD_RECORD_WRITE", parameter.diagnostics.items[0].code);
    // A self-referential right-hand side reads the copy as part of the write, so
    // it still counts as a dead write when nothing observes the binding later.
    var increment = try language.Compilation.init(t.allocator, "dead-increment.my",
        \\record Counter:
        \\    n: int
        \\
        \\
        \\def bump(counter: Counter):
        \\    counter.n = counter.n + 1
        \\
        \\
        \\def main() -> int:
        \\    bump(Counter(n=0))
        \\    return 0
    );
    defer increment.deinit();
    try t.expectError(error.SourceError, increment.check());
    try t.expectEqualStrings("E_DEAD_RECORD_WRITE", increment.diagnostics.items[0].code);
    var collection = try language.Compilation.init(t.allocator, "dead-collection.my",
        \\record Node:
        \\    value: int
        \\
        \\
        \\def main() -> int:
        \\    nodes = [Node(value=1)]
        \\    node = nodes[0]
        \\    node.value = 42
        \\    return 0
    );
    defer collection.deinit();
    try t.expectError(error.SourceError, collection.check());
    try t.expectEqualStrings("E_DEAD_RECORD_WRITE", collection.diagnostics.items[0].code);
    var fresh = try language.Compilation.init(t.allocator, "fresh-record.my",
        \\record Point:
        \\    x: int
        \\
        \\
        \\def main() -> int:
        \\    point = Point(x=1)
        \\    point.x = 3
        \\    return point.x
    );
    defer fresh.deinit();
    try fresh.check();
    try t.expectEqual(@as(usize, 0), fresh.diagnostics.items.len);
}
// spec-case: DEAD-RECORD-WRITE-1
test "reading a parameter copy after a field write keeps the write accepted" {
    var observed = try language.Compilation.init(t.allocator, "read-after-write.my",
        \\record Counter:
        \\    n: int
        \\
        \\
        \\def bump(counter: Counter) -> int:
        \\    counter.n = 5
        \\    return counter.n
        \\
        \\
        \\def main() -> int:
        \\    return bump(Counter(n=0))
    );
    defer observed.deinit();
    try observed.check();
    try t.expectEqual(@as(usize, 0), observed.diagnostics.items.len);
}
// spec-case: CLASS-MANAGED-1
test "a self-referential class graph prints to the depth cap and terminates" {
    try run(
        \\class Node:
        \\    children: list[Node]
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    nodes: list[Node] = []
        \\    nodes.append(Node(children=nodes))
        \\    out.print(nodes[0])
        \\    return 0
    , 0);
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown local names suggest close declared bindings" {
    try expectMessage(
        \\def main() -> int:
        \\    value = 1
        \\    return valu
    , "E_UNKNOWN_NAME", "name is not defined in this scope; did you mean `value`?");
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown local names without a close candidate carry no suggestion" {
    try expectMessage(
        \\def main() -> int:
        \\    value = 1
        \\    return zzz
    , "E_UNKNOWN_NAME", "name is not defined in this scope");
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown list methods name the accepted spellings" {
    try expectMessage(
        \\def main() -> int:
        \\    items = [1, 2]
        \\    items.appnd(3)
        \\    return 0
    , "E_LIST_METHOD", "unknown method for a list[int] receiver; accepted methods: append, clear, copy, extend, index, insert, pop, remove, reverse, sort");
}
