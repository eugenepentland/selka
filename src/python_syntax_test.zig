//! Python surface syntax retains typed semantics and original diagnostic offsets.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

const program =
    \\# Python records remain value records.
    \\class Point:
    \\    x: int
    \\    y: int
    \\
    \\def noop():
    \\    pass
    \\
    \\def main() -> int:
    \\    noop()
    \\    p = Point(x=40, y=2)
    \\    total: int = 0
    \\    while total < 2:
    \\        total += 1
    \\    if not total == 2:
    \\        return 0
    \\    elif True and not False:
    \\        return p.x + p.y
    \\    else:
    \\        return total
;

fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "python.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    try t.expectEqualStrings(program, formatted);
}

// spec: PYTHON-1
test "Python indentation records assignment boolean precedence and omitted unit execute" {
    try scenario(t.allocator);
}

// spec-case: PYTHON-1
test "Python layout retains original spans and ignores blank comment and continuation lines" {
    const text = "def main() -> int:\n    # ignored\n\n    return (\n        40 +\n        2\n    )\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    const tokens = try lexer.lex(arena.allocator(), text, &sink);
    var last: usize = 0;
    var virtual_closes: usize = 0;
    for (tokens) |token| {
        try t.expect(token.span.start >= last);
        try t.expect(token.span.end <= text.len);
        last = token.span.end;
        if (token.tag == .dedent and token.span.start == token.span.end) virtual_closes += 1;
    }
    try t.expectEqual(@as(usize, 1), virtual_closes);
    var c = try language.Compilation.init(t.allocator, "continuation.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}

// spec-case: PYTHON-1
test "Python layout lower rejects missing blocks inconsistent dedents tabs and excess indentation" {
    for ([_][]const u8{
        "def main() -> int:\nreturn 42\n",
        "def main() -> int:\n    if True:\n        return 42\n  return 0\n",
        "def main() -> int:\n\treturn 42\n",
        "def main() -> int:\n    x = 1\n        return x\n",
        "def main() -> int:\n    # empty\n",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "indent.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings("E_INDENTATION", c.diagnostics.items[0].code);
    }
}

// spec: PYTHON-2
test "Python generics default to copy and None means unit" {
    const text = "def keep[T](value: T) -> T:\n    result = value\n    return result\n\ndef noop() -> None:\n    return None\n\ndef main() -> int:\n    noop()\n    return keep(42)\n";
    var c = try language.Compilation.init(t.allocator, "generic.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}

// spec-case: PYTHON-2
test "Python parameters rebind and existing locals update across blocks" {
    const text = "def bump[T: integer](value: T) -> T:\n    value = value + value\n    return value\n\ndef main() -> int:\n    answer = 0\n    if True:\n        answer = bump(21)\n    return answer\n";
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    // A name assigned only on one branch is not definitely bound afterwards.
    var bad = try language.Compilation.init(t.allocator, "scope.my", "def main() -> int:\n    if True:\n        answer = 42\n    return answer\n");
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_UNBOUND", bad.diagnostics.items[0].code);
}

fn scopeValue(text: []const u8) !i64 {
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    return (try native.run(&c)).value;
}

fn scopeReject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-SCOPE-1
test "PY-SCOPE-1 predeclared loop state and complete branches bind after the block" {
    // total = 2 + 9 = 11, last = 9, so total + last = 20.
    try t.expectEqual(@as(i64, 20), try scopeValue(
        \\def main() -> int:
        \\    total = 0
        \\    last = 0
        \\    for row in [[1, 2], [3, 9]]:
        \\        last = row[1]
        \\        total = total + last
        \\    return total + last
    ));
    // A name assigned in both branches of an if/else is bound afterwards.
    try t.expectEqual(@as(i64, 5), try scopeValue(
        \\def main() -> int:
        \\    flag = True
        \\    if flag:
        \\        chosen = 5
        \\    else:
        \\        chosen = 9
        \\    return chosen
    ));
    // Every loop form may execute zero times, so predeclared state is required
    // before the loop and remains definitely assigned after it.
    try t.expectEqual(@as(i64, 3), try scopeValue(
        \\def main() -> int:
        \\    answer = 0
        \\    i = 0
        \\    while i < 3:
        \\        answer = answer + i
        \\        i += 1
        \\    return answer
    ));
    try t.expectEqual(@as(i64, 10), try scopeValue(
        \\def main() -> int:
        \\    total = 0
        \\    for i in range(5):
        \\        total = total + i
        \\    return total
    ));
    try t.expectEqual(@as(i64, 6), try scopeValue(
        \\def main() -> int:
        \\    total = 0
        \\    for i in reversed([1, 2, 3]):
        \\        total = total + i
        \\    return total
    ));
    try t.expectEqual(@as(i64, 11), try scopeValue(
        \\def main() -> int:
        \\    total = 0
        \\    for a, b in zip([1, 2], [3, 4]):
        \\        total = total + a * b
        \\    return total
    ));
}

// spec-case: PY-SCOPE-2
test "PY-SCOPE-2 assignments only in a loop body are unbound after the loop" {
    try scopeReject(
        \\def main() -> int:
        \\    while False:
        \\        answer = 42
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for item in [1, 2]:
        \\        answer = item
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for item in range(2):
        \\        answer = item
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for item in reversed([1, 2]):
        \\        answer = item
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for a, b in zip([1, 2], [3, 4]):
        \\        answer = a + b
        \\    return answer
    , "E_UNBOUND");
}

// spec: PY-SCOPE-2
test "PY-SCOPE-2 reading a name unbound on some path is rejected" {
    try scopeReject(
        \\def main() -> int:
        \\    flag = True
        \\    if flag:
        \\        chosen = 5
        \\    return chosen
    , "E_UNBOUND");
    // A name never assigned before the read stays E_UNKNOWN_NAME.
    try scopeReject(
        \\def main() -> int:
        \\    return missing
    , "E_UNKNOWN_NAME");
    // A method call reads its receiver, so a maybe-unbound owner is rejected too.
    try scopeReject(
        \\def main() -> int:
        \\    flag = True
        \\    if flag:
        \\        data = [1, 2]
        \\    data.append(3)
        \\    return 0
    , "E_UNBOUND");
}

// spec: PY-RECORD-1
test "record is the canonical declaration head without reserving the name" {
    try t.expectEqual(@as(i64, 42), try scopeValue(
        \\record Point:
        \\    x: int
        \\    y: int
        \\
        \\
        \\def main() -> int:
        \\    record = Point(x=20, y=22)
        \\    return record.x + record.y
    ));
    try t.expectEqual(@as(i64, 42), try scopeValue(
        \\class LegacyPoint:
        \\    x: int
        \\    y: int
        \\
        \\
        \\def main() -> int:
        \\    point = LegacyPoint(x=20, y=22)
        \\    return point.x + point.y
    ));
}

// spec-case: PYTHON-3
test "Python generic value records use square construction and default copy constraints" {
    const text = "class Box[T]:\n    value: T\n\ndef main() -> int:\n    box = Box[int](value=42)\n    return box.value\n";
    var c = try language.Compilation.init(t.allocator, "box.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}

// spec-case: PYTHON-1
test "Python declaration listings and formatting retain comment and original name positions" {
    const text = "# documentation\ndef first() -> int:\n    return 40\n\ndef main() -> int:\n    return first() + 2\n";
    var c = try language.Compilation.init(t.allocator, "listing.my", text);
    defer c.deinit();
    const listing = try c.listDeclarations(t.allocator);
    defer t.allocator.free(listing);
    try t.expect(std.mem.indexOf(u8, listing, "\"name\":\"first\"") != null);
    try t.expect(std.mem.indexOf(u8, listing, "\"comment_start\":0") != null);
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(text, formatted);
}

fn lowerAllocations(allocator: std.mem.Allocator) !void {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = try lexer.lex(allocator, program, &sink);
    defer allocator.free(tokens);
    try t.expectEqual(lexer.Tag.eof, tokens[tokens.len - 1].tag);
}

// spec: PYTHON-3
test "Python match cases retain contextual pattern names square types and discard payloads" {
    const text = "def extract(value: Result[int, int]) -> int:\n    match value:\n        case Ok(answer):\n            return answer\n        case Err(_):\n            return 0\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "patterns.my", text);
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    const tokens = try lexer.lex(arena.allocator(), text, &sink);
    var p: parser.Parser = .{ .src = src, .arena = &arena, .tokens = tokens, .sink = &sink };
    const syntax = try p.parse();
    try t.expectEqual(@as(usize, 1), syntax.types.expressions.applications.len);
    const body = syntax.statements.items[@backingInt(syntax.functions[0].body)].data.block;
    const arms = syntax.statements.items[@backingInt(body[0])].data.match.arms;
    try t.expectEqualStrings("Ok", src.text(arms[0].name));
    try t.expectEqual(arms[0].ty.start, arms[0].ty.end);
    try t.expect(arms[1].discard_payload);
}

// spec-case: PYTHON-1
test "Python layout lower frees partial token allocations on every allocator failure" {
    try t.checkAllAllocationFailures(t.allocator, lowerAllocations, .{});
}
