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
            \\    values: list[i64] = []
            \\    values.append(42)
            \\    match model.answer(values):
            \\        case Result.ok(n):
            \\            return n
            \\        case Result.err(e):
            \\            return e
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\
            \\
            \\public def answer(values: list[i64]) -> Result[i64, i64] effects():
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
            \\    values: list[i64] = []
            \\    values.append(21)
            \\    return values[0] + model.answer()
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\
            \\
            \\record Bucket[T]:
            \\    value: T
            \\
            \\
            \\public def answer() -> i64 effects():
            \\    value = Bucket[i64](value=21)
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

// spec: BUILTIN-CONTEXT-7
test "builtin list and declared Result types retain their own nominal identity" {
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
        \\    values: list[i64] = []
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
        \\def main() -> int:
        \\    rows: list[list[int]] = []
        \\    rows.append([])
        \\    rows.insert(0, [])
        \\    rows.extend([])
        \\    rows[0].append(40)
        \\    buffer = byte_buffer([])
        \\    _ = buffer.append_byte(1)
        \\    empty = bytes([])
        \\    octets: list[u8] = []
        \\    octets.append(200)
        \\    return len(rows) + rows[0][0] + len(buffer) + len(empty) - 1 + int(octets[0]) - 200
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
        \\    values: list[Clock] = []
        \\    return 0
    , "E_LIST_CAPABILITY");
    try reject(
        \\def main() -> i64:
        \\    values: list[i64, bool] = []
        \\    return 0
    , "E_GENERIC_ARITY");
}
