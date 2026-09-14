//! Prelude types and context-directed constructors preserve existing type rules.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const debug = std.debug;
fn run(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "builtin.my", text);
    defer compilation.deinit();
    const result = native.runWithOptions(&compilation, .{ .gc_stress = true }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: BUILTIN-CONTEXT-5
test "generic List Result and contextual constructors keep symbolic type parameters" {
    try run(
        \\def singleton[T](value: T) -> List[T]:
        \\    values: List[T] = []
        \\    values.append(value)
        \\    return values
        \\
        \\
        \\def answer[T](value: T) -> Result[T, i64]:
        \\    return Ok(value)
        \\
        \\
        \\def main() -> i64:
        \\    values = singleton(42)
        \\    value = values[0]
        \\    match answer(value):
        \\        case Result.ok(n):
        \\            return n
        \\        case Result.err(e):
        \\            return e
    );
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-builtin.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import model
            \\
            \\
            \\def main() -> i64:
            \\    values: List[i64] = []
            \\    values.append(42)
            \\    match model.answer(values):
            \\        case Result.ok(n):
            \\            return n
            \\        case Result.err(e):
            \\            return e
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\export answer
            \\
            \\
            \\def answer(values: List[i64]) -> Result[i64, i64]:
            \\    return Ok(values[0])
        );
        return error.NotFound;
    }
};

// spec: BUILTIN-CONTEXT-8
test "builtin List and Result share identity across imported module signatures" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}

const ShadowModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import model
            \\
            \\
            \\def main() -> i64:
            \\    values: List[i64] = []
            \\    values.append(21)
            \\    return values[0] + model.answer()
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\export answer
            \\
            \\
            \\class List[T]:
            \\    value: T
            \\
            \\
            \\def answer() -> i64:
            \\    value = List[i64](value=21)
            \\    return value.value
        );
        return error.NotFound;
    }
};

// spec: BUILTIN-CONTEXT-9
test "module-local List declaration shadows the prelude only inside its module" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ShadowModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}

const ConstructorModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return allocator.dupe(u8,
            \\module main
            \\
            \\
            \\def Ok(value: i64) -> i64:
            \\    return value + 1
            \\
            \\
            \\def Err(value: i64) -> i64:
            \\    return value - 1
            \\
            \\
            \\def combine[T](ignored: T) -> i64:
            \\    _ = ignored
            \\    return Ok(20) + Err(22)
            \\
            \\
            \\def main() -> i64:
            \\    if Ok(1) != 2:
            \\        return 1
            \\    if Err(1) != 0:
            \\        return 2
            \\    return combine(True)
        );
    }
};

// spec: BUILTIN-CONTEXT-10
test "module-local Ok and Err functions shadow contextual constructors in generic and ordinary bodies" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ConstructorModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}

// spec: BUILTIN-CONTEXT-1
test "builtin List and Result resolve without imports or explicit declarations" {
    try run(
        \\def answer() -> Result[i64, i64]:
        \\    return Ok(42)
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.append(42)
        \\    match answer():
        \\        case Result.ok(n):
        \\            return n
        \\        case Result.err(e):
        \\            return e
    );
}

// spec: BUILTIN-CONTEXT-2
test "empty lists and Ok Err inherit binding return and argument contexts" {
    try run(
        \\def empty() -> List[i64]:
        \\    return []
        \\
        \\
        \\def answer() -> Result[i64, i64]:
        \\    return Ok(42)
        \\
        \\
        \\def recover(value: Result[i64, i64]) -> i64:
        \\    match value:
        \\        case Result.ok(n):
        \\            return n
        \\        case Result.err(e):
        \\            return e
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.append(42)
        \\    result: Result[i64, i64] = Err(values[0u64])
        \\    _ = result
        \\    return recover(Ok(42))
    );
}

// spec: BUILTIN-CONTEXT-3
test "record fields and nested list elements propagate empty list context" {
    try run(
        \\class Holder:
        \\    values: List[i64]
        \\
        \\
        \\def choose(value: Holder, other: List[i64]) -> i64:
        \\    _ = other
        \\    xs = value.values
        \\    xs.append(42)
        \\    return xs[0u64]
        \\
        \\
        \\def main() -> i64:
        \\    nested: List[List[i64]] = []
        \\    inner: List[i64] = []
        \\    nested.append(inner)
        \\    return choose(Holder(values=[]), [])
    );
}

// spec: BUILTIN-CONTEXT-4
test "Ok unit values preserve fallible result handling" {
    try run(
        \\def done() -> Result[None, i64]:
        \\    return Ok(None)
        \\
        \\
        \\def main() -> i64:
        \\    match done():
        \\        case Result.ok(_):
        \\            return 42
        \\        case Result.err(e):
        \\            return e
    );
}

// spec: BUILTIN-CONTEXT-7
test "declared List and Result types retain their own nominal identity" {
    try run(
        \\result Result:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def answer() -> Result:
        \\    return Ok(42)
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.append(42)
        \\    if values[0u64] != 42:
        \\        return 0
        \\    match answer():
        \\        case Result.ok(n):
        \\            return n
        \\        case Result.err(e):
        \\            return e
    );
}

// spec: BUILTIN-CONTEXT-6
test "contextual constructors reject ambiguity mismatched payloads and capability storage" {
    try reject(
        \\def main() -> i64:
        \\    values = []
        \\    return 0
    , "E_LIST_INFERENCE");
    try reject(
        \\def main() -> i64:
        \\    value = Ok(42)
        \\    return 0
    , "E_RESULT_INFERENCE");
    try reject(
        \\def fail() -> Result[bool, i64]:
        \\    return Ok(42)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_TYPE");
    try reject(
        \\def main() -> i64:
        \\    values: List[clock_cap] = []
        \\    return 0
    , "E_LIST_CAPABILITY");
    try reject(
        \\def main() -> i64:
        \\    values: List[i64, bool] = []
        \\    return 0
    , "E_GENERIC_ARITY");
}
