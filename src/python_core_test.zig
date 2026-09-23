//! Canonical prelude identities, ordinary numbers, and runner entry conventions.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
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
            \\public def live_values[T: copy + storable](mapping: dict[str, T]) -> DictValues[str, T] noalloc:
            \\    return mapping.values()
            \\public def item_total(entries: DictItems[str, list[int]]) -> int noalloc:
            \\    total = 0
            \\    for key, value in entries:
            \\        total += len(key) + value[0]
            \\    return total
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
            \\    mapping = {"a": [10], "bb": [20]}
            \\    live = values.live_values(mapping)
            \\    snapshot = list(live)
            \\    items = mapping.items()
            \\    alias = mapping
            \\    alias["a"] = [1]
            \\    for index in range(200):
            \\        garbage = [index, index + 1]
            \\        if len(garbage) != 2:
            \\            return 4
            \\    if snapshot[0][0] != 10 or list(live)[0][0] != 1:
            \\        return 5
            \\    if values.item_total(items) != 24:
            \\        return 6
            \\    match values.answer():
            \\        case Result.ok(n):
            \\            return n
            \\        case Result.err(e):
            \\            return e
        );
    }
};
// spec: PYTHON-CORE-1
// spec-case: DICT-VIEWS-1
test "prelude containers results options and dictionary views keep one identity across modules" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try native.runWithOptions(&compilation, .{ .gc_stress = true })).value);
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
// spec-case: CALLBACK-SLOT-1
test "an unannotated function whose body exceeds the slot it fills is rejected at the value" {
    // A direct call fixes the slot up front; `run` is noio, so accepting the
    // value would let `output` through a callback its bound never sees.
    try expectMessage(
        \\def key(out: Stream, x: int) -> int:
        \\    out.print(x)
        \\    return x
        \\
        \\
        \\def run(out: Stream, f: def(Stream, int) -> int effects(), x: int) -> int noio:
        \\    return f(out, x)
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    return run(out, key, 1)
    , "E_EFFECT_BOUND", "`key` fills a callback slot of type `def(stream_cap, int) -> int effects()`, but its body has effect `output`: key; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`");
    // A generic callee's slot is concrete only after inference; the same rule
    // holds there, with the witness path through the helper the body calls.
    try expectMessage(
        \\def show(out: Stream, x: int) -> int:
        \\    out.print(x)
        \\    return x
        \\
        \\
        \\def key(out: Stream, x: int) -> int:
        \\    return show(out, x)
        \\
        \\
        \\def run[T: copy + storable](out: Stream, f: def(Stream, T) -> int effects(), x: T) -> int:
        \\    return f(out, x)
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    return run(out, key, 1)
    , "E_EFFECT_BOUND", "`key` fills a callback slot of type `def(stream_cap, int) -> int effects()`, but its body has effect `output`: key -> show; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`");
    // Allocation is held to the slot too: `run` is noalloc and calls through
    // an `effects()` slot, so an allocating helper cannot fill it.
    try expectMessage(
        \\def key(x: int) -> int:
        \\    return len(str(x))
        \\
        \\
        \\def run(f: def(int) -> int effects(), x: int) -> int noalloc:
        \\    return f(x)
        \\
        \\
        \\def main() -> int:
        \\    return run(key, 123)
    , "E_EFFECT_BOUND", "`key` fills a callback slot of type `def(int) -> int effects()`, but its body has effect `managed_allocation`: key; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`");
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

/// Assert the first diagnostic's code and the accepted spelling it carries under
/// the counted `alternative` role.
fn expectAlternative(text: []const u8, code: []const u8, accepted: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "alternative.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, failure.code);
    try t.expect(failure.related != null);
    try t.expectEqual(diagnostic.Role.alternative, failure.related.?.role);
    try t.expectEqualStrings(accepted, failure.related.?.message);
}

// spec: DIAG-ALTERNATIVE-1
test "a dict get without its fallback names the operand the accepted call carries" {
    try expectAlternative(
        \\def main() -> int:
        \\    d = {"a": 1}
        \\    v = d.get("b")
        \\    return v
    , "E_ARITY", "a dictionary `get` always takes its fallback: `d.get(key, default)`");
}

// spec: CONDITIONAL-EXPR-1
test "conditional arms must agree on one type without widening between them" {
    try expectMessage(
        \\def main() -> int:
        \\    x = 1 if True else "a"
        \\    return 0
    , "E_TYPE", "conditional arms must agree: `int` here, `str` in the else arm");
}

// spec: CONDITIONAL-EXPR-2
test "a conditional condition is bool" {
    try expectMessage(
        \\def main() -> int:
        \\    x = 1 if 2 else 3
        \\    return 0
    , "E_TYPE", "expected bool, found int");
}

// spec: CONDITIONAL-EXPR-3
test "only the chosen conditional arm runs and a standalone conditional needs a discard" {
    try run(
        \\def fails() -> int:
        \\    zero = 0
        \\    return 1 // zero
        \\
        \\
        \\def main() -> int:
        \\    return 42 if True else fails()
    , 42);
    try expectMessage(
        \\def main() -> int:
        \\    1 if True else 2
        \\    return 0
    , "E_EXPLICIT_DISCARD_REQUIRED", "a standalone non-unit value requires `_ =` or result handling");
}

// spec-case: CONDITIONAL-EXPR-3
test "both conditional arms count for definite assignment and for effects" {
    try expectMessage(
        \\def main() -> int:
        \\    if True:
        \\        y = 1
        \\    return 0 if False else y
    , "E_UNBOUND", "name may be read before it is assigned; some control-flow path reaching here leaves it unbound");
    try expectMessage(
        \\def shout(out: Stream) -> int effects():
        \\    _ = out.print("a") if False else out.print("b")
        \\    return 0
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    return shout(out)
    , "E_EFFECT_BOUND", "effect `output` exceeds declared bound: shout; inferred bound is effects(output)");
}

// spec: CONDITIONAL-EXPR-4
test "a conditional takes its type from the expected type and nests in its else arm" {
    try run(
        \\def pick(value: bool) -> u8:
        \\    return 1 if value else 2
        \\
        \\
        \\def lookup(found: bool) -> Option[int]:
        \\    return Some(7) if found else None
        \\
        \\
        \\def describe(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\def main() -> int:
        \\    x: u8 = pick(True)
        \\    y = 9 if False else 8 if False else 7
        \\    label = f"{y} {'item' if y == 1 else 'items'}"
        \\    if label != "7 items":
        \\        return 0
        \\    match lookup(True):
        \\        case Some(index):
        \\            return describe(index if True else 0) + int(x) - 1
        \\        case None:
        \\            return 0
    , 8);
}
