//! Canonical prelude identities, ordinary numbers, and runner entry conventions.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const native = @import("native_execute.zig");
fn run(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "core.selka", text);
    defer compilation.deinit();
    const result = native.runWithOptions(&compilation, .{}) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}
fn expectMessage(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, failure.code);
    try t.expectEqualStrings(message, failure.message);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "values.selka")) return allocator.dupe(u8,
            \\public func answer() -> Result[int, int] effects():
            \\    return Ok(42)
            \\public func maybe() -> int? effects():
            \\    return Some(1)
            \\public func items() -> int[] effects(managed_allocation):
            \\    return [1, 2]
            \\public func live_values[T: copy + storable](mapping: dict[str, T]) -> T[]:
            \\    return list(mapping.values())
            \\public func item_total(entries: DictItem[str, int[]][]) -> int noalloc:
            \\    mut total = 0
            \\    for key, value in entries:
            \\        total += len(key) + value[0]
            \\    return total
        );
        if (!std.mem.eql(u8, path, source_names.entry)) return error.NotFound;
        return allocator.dupe(u8,
            \\import values
            \\
            \\
            \\func main() -> i64:
            \\    mut option: i64? = values.maybe()
            \\    match option:
            \\        case Option.some(n):
            \\            if n != 1:
            \\                return 1
            \\        case Option.none:
            \\            return 2
            \\    mut numbers: i64[] = values.items()
            \\    if len(numbers) != 2:
            \\        return 3
            \\    mut mapping = {"a": [10], "bb": [20]}
            \\    mut live = values.live_values(mapping)
            \\    mut snapshot = list(live)
            \\    mut items = list(mapping.items())
            \\    mut alias = mapping
            \\    alias["a"] = [1]
            \\    for index in range(200):
            \\        mut garbage = [index, index + 1]
            \\        if len(garbage) != 2:
            \\            return 4
            \\    if snapshot[0][0] != 10 or list(live)[0][0] != 10:
            \\        return 5
            \\    if values.item_total(items) != 33:
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
    try compilation.check();
    try t.expectEqual(@as(i64, 42), (try native.runWithOptions(&compilation, .{})).value);
}
// spec: PYTHON-CORE-2
test "unit and checked-result main adapt to scalar status without changing guest call signatures" {
    try run(
        \\func main():
        \\    pass
    , 0);
    try run(
        \\func main() -> Result[Unit, i64]:
        \\    return Ok(())
    , 0);
    try run(
        \\func main() -> Result[Unit, i64]:
        \\    return Err(42)
    , 42);
    try run(
        \\func main() -> Result[i64, i64]:
        \\    return Ok(42)
    , 42);
}

const Entries = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, source_names.entry)) return error.NotFound;
        return allocator.dupe(u8, "\nfunc main() -> Result[Unit, int]:\n    return Ok(())\n");
    }
};
const PythonModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8,
            \\import helpers
            \\func main() -> int:
            \\    if helpers.Kind.atom != helpers.Kind.atom:
            \\        return 1
            \\    match helpers.answer([42], "answer", 1.5):
            \\        case Ok(values):
            \\            return values["answer"]
            \\        case Err(code):
            \\            return code
        );
        if (std.mem.eql(u8, path, "helpers.selka")) return allocator.dupe(u8,
            \\public enum Kind:
            \\    atom
            \\    group
            \\
            \\
            \\public func answer(values: int[], key: str, number: float) -> Result[dict[str, int], int] effects(managed_allocation):
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
    try compilation.check();
    try t.expectEqual(@as(i64, 42), (try native.runWithOptions(&compilation, .{})).value);
}
// spec: PYTHON-CORE-3
test "representable integer literals inherit parameter local and expression contexts" {
    try run(
        \\func widen(x: u8) -> i64:
        \\    return i64(x)
        \\
        \\
        \\func main() -> i64:
        \\    mut n: u8 = 40
        \\    return widen(n + 2)
    , 42);
    try run(
        \\func main() -> i64:
        \\    mut n: i8 = -128
        \\    mut wide: u64 = 18446744073709551615
        \\    _ = wide
        \\    return i64(n) + 170
    , 42);
    var compilation = try language.Compilation.init(t.allocator, "range.selka",
        \\func main() -> i64:
        \\    mut x: u8 = 256
        \\    _ = x
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_INTEGER_RANGE", compilation.diagnostics.items[0].code);
}
// spec-case: CALLBACK-EFFECTS-1
test "an explicit narrow callback ceiling still rejects a wider function value" {
    var compilation = try language.Compilation.init(t.allocator, "callback-bound.selka",
        \\func tick(value: int) -> int effects(clock):
        \\    _ = value
        \\    return 1
        \\
        \\
        \\func apply(f: func(int) -> int effects(), x: int) -> int:
        \\    return f(x)
        \\
        \\
        \\func main() -> int:
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
        \\func key(out: Stream, x: int) -> int:
        \\    out.print(x)
        \\    return x
        \\
        \\
        \\func run(out: Stream, f: func(Stream, int) -> int effects(), x: int) -> int noio:
        \\    return f(out, x)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    return run(out, key, 1)
    , "E_EFFECT_BOUND", "`key` fills a callback slot of type `func(stream_cap, int) -> int effects()`, but its body has effect `output`: key; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`");
    // A generic callee's slot is concrete only after inference; the same rule
    // holds there, with the witness path through the helper the body calls.
    try expectMessage(
        \\func show(out: Stream, x: int) -> int:
        \\    out.print(x)
        \\    return x
        \\
        \\
        \\func key(out: Stream, x: int) -> int:
        \\    return show(out, x)
        \\
        \\
        \\func run[T: copy + storable](out: Stream, f: func(Stream, T) -> int effects(), x: T) -> int:
        \\    return f(out, x)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    return run(out, key, 1)
    , "E_EFFECT_BOUND", "`key` fills a callback slot of type `func(stream_cap, int) -> int effects()`, but its body has effect `output`: key -> show; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`");
    // Allocation is held to the slot too: `run` is noalloc and calls through
    // an `effects()` slot, so an allocating helper cannot fill it.
    try expectMessage(
        \\func key(x: int) -> int:
        \\    return len(str(x))
        \\
        \\
        \\func run(f: func(int) -> int effects(), x: int) -> int noalloc:
        \\    return f(x)
        \\
        \\
        \\func main() -> int:
        \\    return run(key, 123)
    , "E_EFFECT_BOUND", "`key` fills a callback slot of type `func(int) -> int effects()`, but its body has effect `managed_allocation`: key; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`");
}
// spec: DEAD-RECORD-WRITE-1
test "record parameters are read-only and explicitly mutable local copies are writable" {
    var parameter = try language.Compilation.init(t.allocator, "dead-parameter.selka",
        \\record Counter:
        \\    n: int
        \\
        \\
        \\func bump(counter: Counter):
        \\    counter.n = 1
        \\
        \\
        \\func main() -> int:
        \\    bump(Counter(n=0))
        \\    return 0
    );
    defer parameter.deinit();
    try t.expectError(error.SourceError, parameter.check());
    try t.expectEqualStrings("E_IMMUTABLE", parameter.diagnostics.items[0].code);
    // Reading the parameter in its own update does not make it mutable.
    var increment = try language.Compilation.init(t.allocator, "dead-increment.selka",
        \\record Counter:
        \\    n: int
        \\
        \\
        \\func bump(counter: Counter):
        \\    counter.n = counter.n + 1
        \\
        \\
        \\func main() -> int:
        \\    bump(Counter(n=0))
        \\    return 0
    );
    defer increment.deinit();
    try t.expectError(error.SourceError, increment.check());
    try t.expectEqualStrings("E_IMMUTABLE", increment.diagnostics.items[0].code);
    var collection = try language.Compilation.init(t.allocator, "dead-collection.selka",
        \\record Node:
        \\    value: int
        \\
        \\
        \\func main() -> int:
        \\    mut nodes = [Node(value=1)]
        \\    mut node = nodes[0]
        \\    node.value = 42
        \\    return 0
    );
    defer collection.deinit();
    try collection.check();
    var fresh = try language.Compilation.init(t.allocator, "fresh-record.selka",
        \\record Point:
        \\    x: int
        \\
        \\
        \\func main() -> int:
        \\    mut point = Point(x=1)
        \\    point.x = 3
        \\    return point.x
    );
    defer fresh.deinit();
    try fresh.check();
    try t.expectEqual(@as(usize, 0), fresh.diagnostics.items.len);
}
// spec-case: DEAD-RECORD-WRITE-1
test "an explicitly mutable copy of a parameter accepts a field write" {
    var observed = try language.Compilation.init(t.allocator, "read-after-write.selka",
        \\record Counter:
        \\    n: int
        \\
        \\
        \\func bump(counter: Counter) -> int:
        \\    mut local = counter
        \\    local.n = 5
        \\    return local.n
        \\
        \\
        \\func main() -> int:
        \\    return bump(Counter(n=0))
    );
    defer observed.deinit();
    try observed.check();
    try t.expectEqual(@as(usize, 0), observed.diagnostics.items.len);
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown local names suggest close declared bindings" {
    try expectMessage(
        \\func main() -> int:
        \\    mut value = 1
        \\    return valu
    , "E_UNKNOWN_NAME", "name is not defined in this scope; did you mean `value`?");
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown local names without a close candidate carry no suggestion" {
    try expectMessage(
        \\func main() -> int:
        \\    mut value = 1
        \\    return zzz
    , "E_UNKNOWN_NAME", "name is not defined in this scope");
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown list methods name the accepted spellings" {
    try expectMessage(
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    items.appnd(3)
        \\    return 0
    , "E_LIST_METHOD", "unknown method for a int[] receiver; accepted methods: append, clear, copy, extend, index, insert, pop, remove, reverse, sort");
}

/// Assert the first diagnostic's code and the accepted spelling it carries under
/// the counted `alternative` role.
fn expectAlternative(text: []const u8, code: []const u8, accepted: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "alternative.selka", text);
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
        \\func main() -> int:
        \\    mut d = {"a": 1}
        \\    mut v = d.get("b")
        \\    return v
    , "E_ARITY", "a dictionary `get` always takes its fallback: `d.get(key, default)`");
}

// spec: CONDITIONAL-EXPR-1
test "conditional arms must agree on one type without widening between them" {
    try expectMessage(
        \\func main() -> int:
        \\    mut x = if (True) then (1) else ("a")
        \\    return 0
    , "E_TYPE", "conditional arms must agree: `int` here, `str` in the else arm");
}

// spec: CONDITIONAL-EXPR-2
test "a conditional condition is bool" {
    try expectMessage(
        \\func main() -> int:
        \\    mut x = if (2) then (1) else (3)
        \\    return 0
    , "E_TYPE", "expected bool, found int");
}

// spec: CONDITIONAL-EXPR-3
test "only the chosen conditional arm runs and a standalone conditional needs a discard" {
    try run(
        \\func fails() -> int:
        \\    mut zero = 0
        \\    return 1 // zero
        \\
        \\
        \\func main() -> int:
        \\    return if (True) then (42) else (fails())
    , 42);
    try expectMessage(
        \\func main() -> int:
        \\    if (True) then (1) else (2)
        \\    return 0
    , "E_EXPLICIT_DISCARD_REQUIRED", "a standalone non-unit value requires `_ =` or result handling");
}

// spec-case: CONDITIONAL-EXPR-3
test "both conditional arms count for definite assignment and for effects" {
    try expectMessage(
        \\func main() -> int:
        \\    if True:
        \\        const y = 1
        \\    return if (False) then (0) else (y)
    , "E_UNKNOWN_NAME", "name is not defined in this scope");
    try expectMessage(
        \\func shout(out: Stream) -> int effects():
        \\    _ = if (False) then (out.print("a")) else (out.print("b"))
        \\    return 0
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    return shout(out)
    , "E_EFFECT_BOUND", "effect `output` exceeds declared bound: shout; inferred bound is effects(output)");
}

// spec: CONDITIONAL-EXPR-4
test "a conditional takes its type from the expected type and nests in its else arm" {
    try run(
        \\func pick(value: bool) -> u8:
        \\    return if (value) then (1) else (2)
        \\
        \\
        \\func lookup(found: bool) -> int?:
        \\    return if (found) then (Some(7)) else (None)
        \\
        \\
        \\func describe(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func main() -> int:
        \\    mut x: u8 = pick(True)
        \\    mut y = if (False) then (9) else if ((False)) then ((8)) else ((7))
        \\    mut label = f"{y} {if (y == 1) then ('item') else ('items')}"
        \\    if label != "7 items":
        \\        return 0
        \\    match lookup(True):
        \\        case Some(index):
        \\            return describe(if (True) then (index) else (0)) + int(x) - 1
        \\        case None:
        \\            return 0
    , 8);
}
