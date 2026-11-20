//! `value is PATTERN`: what the test refuses and how. The accepted forms are the guest tests in `tests/lang/variant_test.selka`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

const header =
    \\enum Node:
    \\    text(value: str)
    \\    pair(left: int, right: int)
    \\    holder(inner: int?)
    \\    leaf
    \\
    \\
;

/// The first refusal of `header` followed by `body`, as (code, message).
fn refused(arena: std.mem.Allocator, body: []const u8) !struct { []const u8, []const u8 } {
    const text = try std.fmt.allocPrint(arena, "{s}{s}\n\n\nfunc main() -> int:\n    return 0\n", .{ header, body });
    const report = try fixture.check(arena, text);
    const first = report.firstError() orelse return error.TestUnexpectedResult;
    return .{ first.code, first.message };
}

// spec-case: VARIANT-TEST-1
test "a pattern that binds names is refused outside the whole condition of an if, elif or while" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try refused(a, "func f(node: Node) -> bool:\n    return node is text(value)");
    try t.expectEqualStrings("E_IS_BINDING", value[0]);
    try t.expect(std.mem.indexOf(u8, value[1], "whole condition of an `if`, `elif` or `while`") != null);
    const joined = try refused(a, "func f(node: Node) -> bool:\n    return node is text(value) and True");
    try t.expectEqualStrings("E_IS_BINDING", joined[0]);
    const compound = try refused(a, "func f(node: Node) -> int:\n    if node is text(value) and True:\n        return 1\n    return 0");
    try t.expectEqualStrings("E_IS_BINDING", compound[0]);
    const negated = try refused(a, "func f(node: Node) -> int:\n    if not (node is pair(left, right)):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_IS_BINDING", negated[0]);
}

// spec-case: VARIANT-TEST-2
test "the operand of an is test must hold cases, and the cases must exist" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const number = try refused(a, "func f(n: int) -> bool:\n    return n is leaf");
    try t.expectEqualStrings("E_IS_OPERAND", number[0]);
    try t.expect(std.mem.indexOf(u8, number[1], "this value has no cases") != null);
    const text = try refused(a, "func f(s: str) -> bool:\n    return s is text");
    try t.expectEqualStrings("E_IS_OPERAND", text[0]);
    const unknown = try refused(a, "func f(node: Node) -> bool:\n    return node is nonesuch");
    try t.expectEqualStrings("E_UNKNOWN_VARIANT", unknown[0]);
    const twice = try refused(a, "func f(node: Node) -> bool:\n    return node is text | text");
    try t.expectEqualStrings("E_DUPLICATE_ARM", twice[0]);
}

// spec-case: VARIANT-TEST-3
test "a test names a case and its own fields, never a nested pattern or a literal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nested = try refused(a, "func f(node: Node) -> bool:\n    return node is holder(inner=Some(x))");
    try t.expectEqualStrings("E_SYNTAX", nested[0]);
    try t.expect(std.mem.indexOf(u8, nested[1], "match a nested pattern with `match`") != null);
    const literal = try refused(a, "func f(node: Node) -> bool:\n    return node is pair(1, 2)");
    try t.expectEqualStrings("E_SYNTAX", literal[0]);
    const arity = try refused(a, "func f(node: Node) -> bool:\n    return node is pair(_)");
    try t.expectEqualStrings("E_FRONTEND_VARIANT", arity[0]);
}

// spec-case: VARIANT-TEST-4
test "the alternatives of a binding test bind the same names, and its other cases are not bound" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const names = try refused(a, "func f(node: Node) -> int:\n    if node is text(value) | pair(left, right):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ALTERNATIVE_BINDINGS", names[0]);
    const scope = try refused(a, "func f(node: Node) -> int:\n    if node is text(value):\n        return len(value)\n    return len(value)");
    try t.expectEqualStrings("E_UNKNOWN_NAME", scope[0]);
}

// spec-case: VARIANT-TEST-5
test "is None keeps its meaning and an is test over an Option needs the case spelled" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.fmt.allocPrint(a, "{s}func f(x: int?) -> bool:\n    return x is None or x is Some\n\n\nfunc g(x: int?) -> bool:\n    return x is not None\n\n\nfunc main() -> int:\n    return 0\n", .{header});
    const report = try fixture.check(a, text);
    try t.expect(report.firstError() == null);
}
