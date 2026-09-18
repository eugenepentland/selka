//! Transparent aliases retain target identity, ownership and module privacy.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text =
        \\type Count = i64
        \\
        \\
        \\type Counts = [2]Count
        \\
        \\
        \\type Chosen = Pair[Count]
        \\
        \\
        \\type Other = Chosen
        \\
        \\
        \\class Pair[T]:
        \\    left: T
        \\    right: T
        \\
        \\
        \\const ANSWER: Count = 42
        \\
        \\
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\def read_value(value: Chosen) -> Count:
        \\    return value.left
        \\
        \\
        \\def main() -> i64:
        \\    pair = Other(left=ANSWER, right=0)
        \\    values: Counts = [read_value(pair), 1]
        \\    return identity[Count](values[0]) + values[1]
    ;
    var compilation = try language.Compilation.init(allocator, "aliases.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 43), (try native.run(&compilation)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 43), (try native.run(&again)).value);
}
// spec: TYPE-ALIAS-1
test "transparent aliases compose scalar arrays nominal applications constants and generic functions" {
    try scenario(t.allocator);
}
test "aliases preserve nominal domains and owned result obligations and reject cycles" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\type A = B
        \\
        \\
        \\type B = A
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        , .code = "E_ALIAS_CYCLE" },
        .{ .text =
        \\type A = i64
        \\
        \\
        \\type A = bool
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        , .code = "E_DUPLICATE_TYPE" },
        .{ .text =
        \\class A:
        \\    pass
        \\
        \\
        \\type A = i64
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        , .code = "E_DUPLICATE_TYPE" },
        .{ .text =
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\type Alias = D
        \\
        \\
        \\def main() -> i64:
        \\    value: Alias = 1
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\type Alias = R
        \\
        \\
        \\def main() -> i64:
        \\    value: Alias = Ok(1)
        \\    return 0
        , .code = "E_RESULT_UNHANDLED" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
fn provider(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const hidden = context != null;
    const text = if (std.mem.eql(u8, path, "main.my"))
        \\module main
        \\import shapes
        \\
        \\
        \\def main() -> i64:
        \\    value: shapes.Count = 42
        \\    return value
    else if (std.mem.eql(u8, path, "shapes.my"))
        if (hidden) "module shapes\ntype Count = i64\n" else "module shapes\npublic type Count = i64\n"
    else
        return error.NotFound;
    return allocator.dupe(u8, text);
}
test "module aliases export canonical types while private aliases remain inaccessible" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&program.compilation)).value);
    var hidden: language.embedded_project.Program = undefined;
    var marker: u8 = 0;
    try t.expectError(error.SourceError, hidden.init(t.allocator, .{ .context = &marker, .read = provider }));
}

fn privateTarget(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8,
        \\module main
        \\
        \\
        \\class Secret:
        \\    value: i64
        \\
        \\
        \\public type Public = Secret
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
}
test "exported aliases cannot expose private nominal types" {
    var program: language.embedded_project.Program = undefined;
    try t.expectError(error.SourceError, program.init(t.allocator, .{ .context = null, .read = privateTarget }));
}

fn schemaAliases(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8,
        \\module main
        \\
        \\
        \\public type Count = i64
        \\
        \\
        \\public class Pair[T]:
        \\    value: T
        \\
        \\
        \\public type Chosen = Pair[Count]
        \\
        \\
        \\public type Other = Chosen
        \\
        \\
        \\public type Array = [2]Count
        \\
        \\
        \\type Hidden = bool
        \\
        \\
        \\def main() -> i64:
        \\    x = Other(value=42)
        \\    return x.value
    );
}
fn schemaScenario(allocator: std.mem.Allocator) !void {
    var program: language.embedded_project.Program = undefined;
    try program.init(allocator, .{ .context = null, .read = schemaAliases });
    defer program.deinit();
    try t.expectEqual(@import("typed.zig").Type.i64, try program.compilation.publicValueType("main::Count"));
    try t.expectEqual(try program.compilation.publicValueType("main::Chosen"), try program.compilation.publicValueType("main::Other"));
    try t.expectError(error.UnknownPublicValueType, program.compilation.publicValueType("main::Hidden"));
    const rendered = try language.schema.render(allocator, &program.compilation);
    defer allocator.free(rendered);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, rendered, .{});
    defer parsed.deinit();
    const exports = parsed.value.object.get("exports").?.array.items;
    try t.expectEqual(@as(usize, 4), exports.len);
    try t.expectEqualStrings("[2]i64", exports[0].string);
    try t.expectEqualStrings("i64", exports[1].string);
    try t.expectEqualStrings(exports[2].string, exports[3].string);
}
// spec: TYPE-ALIAS-SCHEMA-1
test "public scalar array and generic aliases retain canonical schemas and native emission" {
    try schemaScenario(t.allocator);
}
