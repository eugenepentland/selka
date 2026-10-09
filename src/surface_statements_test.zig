//! Statement endings, unit spelling, propagation, and declaration discovery.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "statements.selka", bytes);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "formatted.selka", formatted);
    defer after.deinit();
    try t.expectEqual(expected, (try native.run(&after)).value);
    const twice = try after.format(t.allocator);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
}

// spec: SURFACE-STMT-1
test "newlines and dedents end statements without semicolon separators" {
    try evaluate(
        \\type Number = i64
        \\
        \\
        \\const ANSWER: Number = 42
        \\
        \\
        \\func main() -> i64:
        \\    mut value = ANSWER # retained comment
        \\    return value
    , 42);
    try evaluate(
        \\func main() -> i64:
        \\    mut x = 41
        \\    mut y = 1
        \\    return x + y
    , 42);
    var invalid = try language.Compilation.init(t.allocator, "missing-separator.selka",
        \\def main() -> i64:
        \\    x = 41 return x + 1
    );
    defer invalid.deinit();
    try t.expectError(error.SourceError, invalid.check());
    try t.expectEqualStrings("E_SYNTAX", invalid.diagnostics.items[0].code);
}

// spec: SURFACE-STMT-5
test "module declaration discovery and formatting accept newline terminated directives" {
    const bytes =
        \\import dependency as dep
        \\
        \\
        \\public type Value = i64
        \\
        \\
        \\
        \\
        \\public func main() -> i64:
        \\    return 42
    ;
    var compilation = try language.Compilation.init(t.allocator, "example.selka", bytes);
    defer compilation.deinit();
    const declarations = try compilation.listDeclarations(t.allocator);
    defer t.allocator.free(declarations);
    try t.expect(std.mem.indexOf(u8, declarations, "Value") != null);
    const formatted = try compilation.formatModule(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "example.selka", formatted);
    defer after.deinit();
    const repeated = try after.listDeclarations(t.allocator);
    defer t.allocator.free(repeated);
    try t.expect(std.mem.indexOf(u8, repeated, "main") != null);
}

// spec: SURFACE-STMT-9
test "newline suffixes end an expression outside parentheses and continue inside parentheses" {
    try evaluate(
        \\func add(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\func main() -> i64:
        \\    return add(20, 22)
    , 42);
    var compilation = try language.Compilation.init(t.allocator, "newline-suffix.selka",
        \\func add(a: i64) -> i64:
        \\    return a
        \\
        \\
        \\func main() -> i64:
        \\    mut callback = add
        \\    42
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const body = syntax.statements.items[@backingInt(syntax.functions[1].body)].data.block;
    try t.expectEqual(@as(usize, 3), body.len);
    const assignment = syntax.statements.items[@backingInt(body[0])].data.binding;
    try t.expect(syntax.nodes.items[@backingInt(assignment.value)].data == .name);
    const expression = syntax.statements.items[@backingInt(body[1])].data.discard;
    try t.expect(syntax.nodes.items[@backingInt(expression)].data == .integer);
}
