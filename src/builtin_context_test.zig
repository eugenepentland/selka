//! Prelude types and context-directed constructors preserve existing type rules.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const debug = std.debug;
fn run(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "builtin.selka", text);
    defer compilation.deinit();
    const result = native.runWithOptions(&compilation, .{}) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-builtin.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8,
            \\import model
            \\
            \\
            \\func main() -> i64:
            \\    mut values: i64[] = []
            \\    values.append(42)
            \\    match model.answer(values):
            \\        case Result.ok(n):
            \\            return n
            \\        case Result.err(e):
            \\            return e
        );
        if (std.mem.eql(u8, path, "model.selka")) return allocator.dupe(u8,
            \\
            \\
            \\public func answer(values: i64[]) -> Result[i64, i64] effects():
            \\    return Ok(values[0])
        );
        return error.NotFound;
    }
};

// spec: BUILTIN-CONTEXT-8
test "builtin list and Result share identity across imported module signatures" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}

const ShadowModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8,
            \\import model
            \\
            \\
            \\func main() -> i64:
            \\    mut values: i64[] = []
            \\    values.append(21)
            \\    return values[0] + model.answer()
        );
        if (std.mem.eql(u8, path, "model.selka")) return allocator.dupe(u8,
            \\
            \\
            \\record Bucket[T]:
            \\    value: T
            \\
            \\
            \\public func answer() -> i64 effects():
            \\    mut value = Bucket[i64](value=21)
            \\    return value.value
        );
        return error.NotFound;
    }
};

// spec: BUILTIN-CONTEXT-9
test "module-local Bucket declaration remains distinct from the prelude list" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ShadowModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}

const ConstructorModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, source_names.entry)) return error.NotFound;
        return allocator.dupe(u8,
            \\
            \\
            \\func Ok(value: i64) -> i64:
            \\    return value + 1
            \\
            \\
            \\func Err(value: i64) -> i64:
            \\    return value - 1
            \\
            \\
            \\func combine[T](ignored: T) -> i64:
            \\    _ = ignored
            \\    return Ok(20) + Err(22)
            \\
            \\
            \\func main() -> i64:
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
    try compilation.check();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}

// spec: BUILTIN-CONTEXT-7
test "builtin list and declared Result types retain their own nominal identity" {
    try run(
        \\result Result:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func answer() -> Result:
        \\    return Ok(42)
        \\
        \\
        \\func main() -> i64:
        \\    mut values: i64[] = []
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

// spec: BUILTIN-CONTEXT-11
test "list method operands and byte conversions give an empty list its expected type" {
    try run(
        \\func main() -> int:
        \\    mut rows: int[][] = []
        \\    rows.append([])
        \\    rows.insert(0, [])
        \\    rows.extend([])
        \\    rows[0].append(40)
        \\    mut buffer = byte_buffer([])
        \\    _ = buffer.append_byte(1)
        \\    mut empty = bytes([])
        \\    mut octets: u8[] = []
        \\    octets.append(200)
        \\    return len(rows) + rows[0][0] + len(buffer) + len(empty) - 1 + int(octets[0]) - 200
    );
}

// spec: BUILTIN-CONTEXT-6
test "contextual constructors reject ambiguity mismatched payloads and capability storage" {
    try reject(
        \\func main() -> i64:
        \\    mut values = []
        \\    return 0
    , "E_LIST_INFERENCE");
    try reject(
        \\func main() -> i64:
        \\    mut value = Ok(42)
        \\    return 0
    , "E_RESULT_INFERENCE");
    try reject(
        \\func fail() -> Result[bool, i64]:
        \\    return Ok(42)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_TYPE");
    try reject(
        \\func main() -> i64:
        \\    mut values: Clock[] = []
        \\    return 0
    , "E_LIST_CAPABILITY");
    try reject(
        \\func main() -> i64:
        \\    mut values: list[i64, bool] = []
        \\    return 0
    , "E_GENERIC_ARITY");
}
