//! Statement endings, unit spelling, propagation, and declaration discovery.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "statements.my", bytes);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "formatted.my", formatted);
    defer after.deinit();
    try t.expectEqual(expected, (try after.execute(t.allocator)).value);
    const twice = try after.format(t.allocator);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
}

// spec: SURFACE-STMT-1
test "a newline or a dedent ends a statement and a semicolon separates two on one line" {
    try evaluate(
        \\type Number = i64
        \\
        \\
        \\const ANSWER: Number = 42
        \\
        \\
        \\def main() -> i64:
        \\    value = ANSWER # retained comment
        \\    return value
    , 42);
    try evaluate(
        \\def main() -> i64:
        \\    x = 41; y = 1
        \\    return x + y
    , 42);
    var invalid = try language.Compilation.init(t.allocator, "missing-separator.my",
        \\def main() -> i64:
        \\    x = 41 return x + 1
    );
    defer invalid.deinit();
    try t.expectError(error.SourceError, invalid.check());
    try t.expectEqualStrings("E_SYNTAX", invalid.diagnostics.items[0].code);
}

// spec: SURFACE-STMT-2
test "postfix question propagates success and error with postfix precedence" {
    try evaluate(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def first() -> R:
        \\    return Ok(41)
        \\
        \\
        \\def next() -> R:
        \\    n = first()?
        \\    return Ok(n + 1)
        \\
        \\
        \\def main() -> i64:
        \\    match next():
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
    , 42);
    try evaluate(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def first() -> R:
        \\    return Err(42)
        \\
        \\
        \\def next() -> R:
        \\    return Ok(first()? + 1)
        \\
        \\
        \\def main() -> i64:
        \\    match next():
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
    , 42);
}

// spec: SURFACE-STMT-3
test "parentheses spell unit types values and bare returns" {
    try evaluate(
        \\type Done = None
        \\
        \\
        \\def nothing() -> Done:
        \\    return
        \\
        \\
        \\def explicit():
        \\    return None
        \\
        \\
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\def main() -> i64:
        \\    nothing()
        \\    explicit()
        \\    identity[None](None)
        \\    return 42
    , 42);
}

// spec: SURFACE-STMT-4
test "trailing call commas and multiline binary operators preserve semantics" {
    try evaluate(
        \\def add(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\def main() -> i64:
        \\    value = add(20, 22)
        \\    return cast<i64>(value) + 0
    , 42);
    try evaluate(
        \\def main() -> i64:
        \\    value = 40 + 2
        \\    return value
    , 42);
    try evaluate(
        \\def main() -> i64:
        \\    values: [3]i64 = [10, 20, 12]
        \\    return values[0] + values[1] + values[2]
    , 42);
}

// spec: SURFACE-STMT-5
test "module declaration discovery and formatting accept newline terminated directives" {
    const bytes =
        \\module example
        \\import dependency as dep
        \\export Value
        \\
        \\
        \\type Value = i64
        \\
        \\
        \\export main
        \\
        \\
        \\def main() -> i64:
        \\    return 42
    ;
    var compilation = try language.Compilation.init(t.allocator, "example.my", bytes);
    defer compilation.deinit();
    const declarations = try compilation.listDeclarations(t.allocator);
    defer t.allocator.free(declarations);
    try t.expect(std.mem.indexOf(u8, declarations, "Value") != null);
    const formatted = try compilation.formatModule(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "example.my", formatted);
    defer after.deinit();
    const repeated = try after.listDeclarations(t.allocator);
    defer t.allocator.free(repeated);
    try t.expect(std.mem.indexOf(u8, repeated, "main") != null);
}

// spec: SURFACE-STMT-8
test "nested generic record constructors retain list type arguments and field contexts" {
    try evaluate(
        \\class Holder[T]:
        \\    value: T
        \\
        \\
        \\def main() -> i64:
        \\    holder = Holder[List[i64]](value=[])
        \\    values = holder.value
        \\    values.push(42)
        \\    return values[0]
    , 42);
}

// spec: SURFACE-STMT-9
test "newline suffixes end an expression outside parentheses and continue inside parentheses" {
    try evaluate(
        \\def add(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\def main() -> i64:
        \\    return add(20, 22)
    , 42);
    var compilation = try language.Compilation.init(t.allocator, "newline-suffix.my",
        \\def add(a: i64) -> i64:
        \\    return a
        \\
        \\
        \\def main() -> i64:
        \\    callback = add
        \\    42
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const body = syntax.statements.items[@backingInt(syntax.functions[1].body)].data.block;
    try t.expectEqual(@as(usize, 3), body.len);
    const binding = syntax.statements.items[@backingInt(body[0])].data.binding;
    try t.expect(syntax.nodes.items[@backingInt(binding.value)].data == .name);
    const expression = syntax.statements.items[@backingInt(body[1])].data.discard;
    try t.expect(syntax.nodes.items[@backingInt(expression)].data == .integer);
}

// spec: SURFACE-STMT-7
test "condition calls admit nested record constructors without consuming condition blocks" {
    try evaluate(
        \\class point:
        \\    Value: i64
        \\
        \\
        \\def predicate(first: point, value: point) -> bool:
        \\    return first.Value == value.Value
        \\
        \\
        \\def main() -> i64:
        \\    flag = True
        \\    item = point(Value=42)
        \\    if flag:
        \\        if not False and predicate(item, point(Value=42)):
        \\            return 42
        \\    return 0
    , 42);
}
