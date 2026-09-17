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
            \\export answer
            \\export maybe
            \\export items
            \\def answer() -> Result[int, int] effects():
            \\    return Ok(42)
            \\def maybe() -> Option[int] effects():
            \\    return Some(1)
            \\def items() -> list[int] effects(managed_allocation):
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
// spec: PYTHON-CORE-4
test "floating literals operators and comparisons use numeric binary64 semantics" {
    try run(
        \\def add(x: float, y: float) -> float:
        \\    return x + y
        \\
        \\
        \\def main() -> i64:
        \\    value = add(1.5, 2.5) * 10.0 + 2.0
        \\    if value == 42.0:
        \\        return 42
        \\    return 1
    , 42);
    try run(
        \\def main() -> i64:
        \\    zero = -0.0
        \\    nan = divtrunc(0.0, 0.0)
        \\    if zero != 0.0:
        \\        return 1
        \\    if nan == nan:
        \\        return 2
        \\    if not (nan != nan):
        \\        return 3
        \\    return 42
    , 42);
}
// spec-case: PYTHON-CORE-4
test "floating comparisons and remainder preserve operand evaluation once in source order" {
    try run(
        \\def operand(log: list[int], value: int) -> float:
        \\    log.append(value)
        \\    return float(value)
        \\def main() -> int:
        \\    log: list[int] = []
        \\    if operand(log, 5) > operand(log, 2):
        \\        value = operand(log, 7) % operand(log, 3)
        \\        if value != 1.0:
        \\            return 1
        \\    if len(log) != 4:
        \\        return 2
        \\    return log[0] + log[1] + log[2] + log[3] + 25
    , 42);
}
// spec-case: PY-COLLECTIONS-1
test "Python indexed assignment evaluates RHS before receiver and index exactly once" {
    try run(
        \\def receiver(log: list[int], values: list[int]) -> list[int]:
        \\    log.append(2)
        \\    return values
        \\def index(log: list[int]) -> int:
        \\    log.append(3)
        \\    return 0
        \\def value(log: list[int]) -> int:
        \\    log.append(1)
        \\    return 42
        \\def main() -> int:
        \\    log: list[int] = []
        \\    values = [0]
        \\    receiver(log, values)[index(log)] = value(log)
        \\    if len(log) != 3 or values[0] != 42:
        \\        return 1
        \\    return log[0] * 100 + log[1] * 10 + log[2]
    , 123);
}
// spec-case: PYTHON-3
test "Python payloadless enum values use ordinary dotted members" {
    try run(
        \\enum Kind:
        \\    atom,
        \\    group
        \\
        \\
        \\def main() -> int:
        \\    kind = Kind.atom
        \\    if kind == Kind.atom:
        \\        return 42
        \\    return 1
    , 42);
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
            \\export answer
            \\export Kind
            \\enum Kind:
            \\    atom,
            \\    group
            \\
            \\
            \\def answer(values: list[int], key: str, number: float) -> Result[dict[str, int], int] effects(managed_allocation):
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
// spec-case: PYTHON-CALL-1
test "Python string and float defaults remain typed and independent across repeated calls" {
    try run(
        \\def length(text: str = "é", scale: float = 2.5) -> int:
        \\    return len(text) + int(scale)
        \\def main() -> int:
        \\    return length() + length() + length(scale=33.5)
    , 40);
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
// spec-case: PYTHON-CORE-4
test "Python division remainder numeric conversions and generic numbers" {
    try run(
        \\def main() -> int:
        \\    if 5 / 2 != 2.5:
        \\        return 1
        \\    if -5 // 2 != -3 or -5 % 2 != 1:
        \\        return 2
        \\    if 5 // -2 != -3 or 5 % -2 != -1:
        \\        return 3
        \\    if -5.0 // 2.0 != -3.0 or -5.0 % 2.0 != 1.0:
        \\        return 4
        \\    return int(float(-2) + 4.4e1)
    , 42);
    try run(
        \\def adjust[T](unused: T, value: float) -> float:
        \\    _ = unused
        \\    return value + 1.5
        \\def main() -> int:
        \\    return int(adjust(0, 40.5))
    , 42);
}
// spec-case: PYTHON-CORE-1
test "Python contextual Option constructors work in generic functions" {
    try run(
        \\def present[T](value: T) -> Option[T]:
        \\    return Some(value)
        \\def absent[T](value: T) -> Option[T]:
        \\    _ = value
        \\    return None
        \\def main() -> int:
        \\    empty: Option[int] = absent(0)
        \\    _ = empty
        \\    match present(42):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            return 1
    , 42);
}
// spec: CALLBACK-EFFECTS-1
test "omitted callback ceilings are unbounded and unannotated functions fill slots" {
    try run(
        \\def double(value: int) -> int:
        \\    return value * 2
        \\
        \\
        \\def apply(f: def(int) -> int, x: int) -> int:
        \\    return f(x)
        \\
        \\
        \\def main() -> int:
        \\    return apply(double, 21)
    , 42);
}
// spec-case: CALLBACK-EFFECTS-1
test "unannotated functions fill the sorted key callback slot" {
    try run(
        \\class Score:
        \\    name: str
        \\    points: int
        \\
        \\
        \\def score(item: Score) -> int:
        \\    return item.points
        \\
        \\
        \\def main() -> int:
        \\    items = [Score(name="a", points=3), Score(name="b", points=1)]
        \\    ordered = sorted(items, key=score)
        \\    return ordered[0].points * 42
    , 42);
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
// spec: CLASS-MANAGED-1
test "class is a shared managed reference while record copies" {
    try run(
        \\class Counter:
        \\    n: int
        \\
        \\
        \\record Pair:
        \\    n: int
        \\
        \\
        \\def bump(counter: Counter):
        \\    counter.n = counter.n + 1
        \\
        \\
        \\def main() -> int:
        \\    a = Counter(n=1)
        \\    b = a
        \\    b.n = 7
        \\    bump(a)
        \\    pair = Pair(n=1)
        \\    copy = pair
        \\    copy.n = 9
        \\    return a.n * 10 + pair.n
    , 81);
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
    , "E_LIST_METHOD", "unknown managed collection method; methods: append, clear, copy, extend, index, insert, pop, remove, reverse, sort");
}
