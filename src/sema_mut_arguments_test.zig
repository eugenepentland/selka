//! Transparent mutation markers consume their resolved target once.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

const nested_dictionary =
    \\func clone_during(mut target: dict[int,int], source: dict[int,dict[int,int]]) -> dict[int,dict[int,int]]:
    \\    target[1] = target[1]
    \\    return source.copy()
    \\
    \\func main(out: Stream) -> int:
    \\    mut original = {0:{1:7}}
    \\    mut copied = clone_during(mut original[0], original)
    \\    mut live = list(copied[0].values())
    \\    copied[0][1] = 13
    \\    out.print(list(live))
    \\    out.print(copied[0][1])
    \\    out.print(original[0][1])
    \\    return 0
;

// spec: MUT-EXPRESSION-STACK-1
test "mut expression stack accepts a dictionary element before its containing value" {
    var compilation = try language.Compilation.init(t.allocator, "mut-dictionary.selka", nested_dictionary);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

fn rejected(allocator: std.mem.Allocator, argument: []const u8, expected: []const u8) !void {
    const bytes = try std.fmt.allocPrint(allocator, "func touch(mut value: dict[int,int]) -> Unit:\n    value[1] = 2\n\nfunc main() -> int:\n    mut values = {{0:{{1:7}}}}\n    touch({s})\n    return 0\n", .{argument});
    defer allocator.free(bytes);
    var compilation = try language.Compilation.init(allocator, "mut-diagnostic.selka", bytes);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_MUTATION_MARKER", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, expected) != null);
}

// spec-case: MUT-EXPRESSION-STACK-1
test "mut expression stack preserves missing marker and nonassignable target diagnostics" {
    try rejected(t.allocator, "values[0]", "write `(mut values[0])`");
    try rejected(t.allocator, "mut {1:7}", "requires an assignable argument");
}

fn frontendRejected(bytes: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "frontend-mut.selka", bytes);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: FRONTEND-BINDINGS-1
test "frontend bindings reject undeclared assignment and provide declaration repair" {
    var compilation = try language.Compilation.init(t.allocator, "frontend-binding.selka", "func main() -> int:\n    value = 1\n    return value\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_BINDING_DECLARATION", compilation.diagnostics.items[0].code);
    try t.expect(compilation.diagnostics.items[0].provenance.fix != null);
}

// spec: FRONTEND-BINDINGS-2
test "frontend bindings confine declarations to lexical blocks" {
    try frontendRejected("func main() -> int:\n    if True:\n        const value = 1\n    return value\n", "E_UNKNOWN_NAME");
}

// spec: FRONTEND-MUT-1
test "frontend immutable values reject nested element updates" {
    try frontendRejected("record Box:\n    values: int[]\n\nfunc main() -> int:\n    const box = Box(values=[1])\n    box.values[0] = 2\n    return 0\n", "E_IMMUTABLE");
}

// spec-case: FRONTEND-MUT-1
test "frontend readonly parameters reject collection methods" {
    try frontendRejected("func change(values: int[]) -> Unit:\n    values.append(2)\n\nfunc main() -> int:\n    return 0\n", "E_IMMUTABLE");
}

// spec: FRONTEND-MUT-2
test "frontend mutable scalar parameters check and expose caller writeback" {
    var compilation = try language.Compilation.init(t.allocator, "frontend-scalar.selka", "func change(mut value: int) -> Unit:\n    value = 8\n\nfunc main() -> int:\n    mut value = 2\n    change(mut value)\n    return value\n");
    defer compilation.deinit();
    const result = try @import("native_execute.zig").run(&compilation);
    try t.expectEqual(@as(i64, 8), result.value);
}

// spec: FRONTEND-MUT-3
test "frontend dynamic overlapping mut indices trap before caller writeback" {
    var compilation = try language.Compilation.init(t.allocator, "frontend-overlap.selka",
        \\func two(mut left: int, mut right: int) -> Unit:
        \\    left = 10
        \\    right = 20
        \\
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    const index = len(values) - 1
        \\    two(mut values[index], mut values[1])
        \\    return 0
        \\
    );
    defer compilation.deinit();
    const result = try @import("native_execute.zig").run(&compilation);
    try t.expect(result.trapped());
    try t.expect(std.mem.indexOf(u8, result.stderr, "overlapping mut arguments") != null);
}

// spec: FRONTEND-NAMED-CALLBACK-1
test "frontend named callback parameters cannot erase their labels" {
    try frontendRejected(
        \\func labelled(named value: int) -> int:
        \\    return value
        \\
        \\func main() -> int:
        \\    const operation: func(int) -> int = labelled
        \\    return 0
    , "E_TYPE");
}

// spec-case: FRONTEND-NAMED-CALLBACK-1
test "frontend named callback parameters reject positional calls" {
    try frontendRejected(
        \\func labelled(named value: int) -> int:
        \\    return value
        \\
        \\func main() -> int:
        \\    const operation: func(named value: int) -> int = labelled
        \\    return operation(3)
    , "E_KEYWORD_ONLY");
}

// spec-case: FRONTEND-BINDINGS-2
test "frontend bindings reject shadowing an active outer declaration" {
    try frontendRejected(
        \\func main() -> int:
        \\    const value = 1
        \\    if True:
        \\        const value = 2
        \\    return value
    , "E_SHADOWING");
}

// spec-case: FRONTEND-MUT-1
test "frontend loop elements are read-only" {
    try frontendRejected(
        \\func main() -> int:
        \\    const values = [1, 2]
        \\    for value in values:
        \\        value = 4
        \\    return 0
    , "E_IMMUTABLE");
}

// spec-case: FRONTEND-FAILURES-1
test "frontend fail requires a declared failure clause" {
    try frontendRejected("func main() -> int:\n    fail 3\n", "E_FAIL_CONTEXT");
}

// spec-case: FRONTEND-FAILURES-1
test "frontend try requires a result-returning enclosing function" {
    try frontendRejected(
        \\func operation() -> Result[int, str]:
        \\    return Ok(1)
        \\
        \\func main() -> int:
        \\    return try operation()
    , "E_TRY_RETURN");
}

// spec-case: FRONTEND-FAILURES-1
test "frontend fail rejects an undeclared error type" {
    try frontendRejected(
        \\enum Error:
        \\    invalid
        \\
        \\func operation() -> int fails Error:
        \\    fail "invalid"
        \\
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
}

// spec-case: FRONTEND-FAILURES-1
test "frontend fallible return requires extracting success with try" {
    try frontendRejected(
        \\enum Error:
        \\    invalid
        \\
        \\func operation() -> int fails Error:
        \\    return 1
        \\
        \\func forwarded() -> int fails Error:
        \\    return operation()
        \\
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
}

// spec-case: FRONTEND-MATCH-1
test "frontend nested error patterns must exhaust error variants" {
    try frontendRejected(
        \\enum Error:
        \\    first
        \\    second
        \\
        \\func operation() -> int fails Error:
        \\    fail Error.first
        \\
        \\func main() -> int:
        \\    match operation():
        \\        case Ok(value):
        \\            return value
        \\        case Err(Error.first):
        \\            return 0
    , "E_INCOMPLETE_MATCH");
}

// spec-case: FRONTEND-MATCH-1
test "frontend match expression requires yield on every continuing path" {
    try frontendRejected(
        \\enum Choice:
        \\    first
        \\    second
        \\
        \\func main() -> int:
        \\    const value = match Choice.first:
        \\        case Choice.first:
        \\            yield 1
        \\        case Choice.second:
        \\            if False:
        \\                yield 2
        \\    return value
    , "E_MATCH_YIELD");
}

// spec-case: FRONTEND-TYPES-1
test "frontend growable literal cannot silently become a fixed array" {
    for ([_][]const u8{ "int", "int??[]", "FixedArray[int, 3]" }) |element| {
        const text = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    const values: FixedArray[{s}, 2] = []\n    return 0\n", .{element});
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "frontend-fixed.selka", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        const item = compilation.diagnostics.items[0];
        try t.expectEqualStrings("E_FIXED_ARRAY_LITERAL", item.code);
        const edit = item.provenance.fix.?.edit;
        try t.expectEqualStrings("[]", compilation.src.text(edit.span));
        const replacement = try std.fmt.allocPrint(t.allocator, "FixedArray[{s}, 2]([])", .{element});
        defer t.allocator.free(replacement);
        try t.expectEqualStrings(replacement, edit.text);
    }
}

// spec-case: FRONTEND-MATCH-1
test "frontend positional fielded enum construction requires a named-fields repair" {
    try frontendRejected(
        \\enum Message:
        \\    pair(left: int, right: int)
        \\
        \\func main() -> int:
        \\    const value = Message.pair(1, 2)
        \\    return 0
    , "E_FRONTEND_VARIANT");
}

// spec-case: FRONTEND-TYPES-1
test "frontend None requires optional context and repairs Unit spelling" {
    try frontendRejected("func main() -> Unit:\n    return None\n", "E_NONE_UNIT");
    try frontendRejected("func main() -> Unit:\n    return ((None))\n", "E_NONE_UNIT");
    try frontendRejected("func main() -> int:\n    const absent = None\n    return 0\n", "E_NONE_CONTEXT");
}

// spec-case: FRONTEND-MATCH-1
test "frontend nested product patterns cover every combination" {
    try frontendRejected(
        \\enum Bit:
        \\    low
        \\    high
        \\
        \\enum Pair:
        \\    value(left: Bit, right: Bit)
        \\
        \\func main() -> int:
        \\    match Pair.value(left=Bit.low, right=Bit.low):
        \\        case Pair.value(left=Bit.low, right=Bit.low):
        \\            return 0
        \\        case Pair.value(left=Bit.low, right=Bit.high):
        \\            return 1
        \\        case Pair.value(left=Bit.high, right=Bit.low):
        \\            return 2
    , "E_INCOMPLETE_MATCH");
}

// spec-case: FRONTEND-MUT-1
test "frontend tuple declarations preserve readonly and no shadowing" {
    try frontendRejected("func main() -> int:\n    const a, b = (1, 2)\n    a = 3\n    return b\n", "E_IMMUTABLE");
    try frontendRejected("func main() -> int:\n    const a = 0\n    mut a, b = (1, 2)\n    return b\n", "E_SHADOWING");
    try frontendRejected("func main() -> int:\n    a, b = (1, 2)\n    return b\n", "E_BINDING_DECLARATION");
}
