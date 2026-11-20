//! An unsuffixed literal beside a typed operand takes that operand's type, whatever shape the operand has: a name, a
//! field, an index, a call, a nested operator or a conversion (`docs/integer-operations.md`, `literal_peer.zig`). Each
//! program binds the expression without an annotation, so no context types the literal, and then requires the
//! binding's exact type with a typed `const`, which no implicit conversion satisfies.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn accepts(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "literal.selka", source);
    defer c.deinit();
    // A refusal fails here with its message shown beside the empty one expected.
    c.check() catch try t.expectEqualStrings("", c.diagnostics.items[0].message);
}

/// Refused with `code` at `at` (the first occurrence of that text in the program) and a message holding `advice`.
fn refusesAt(source: []const u8, code: []const u8, at: []const u8, advice: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "literal.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const first = c.diagnostics.items[0];
    try t.expectEqualStrings(code, first.code);
    try t.expectEqual(std.mem.indexOf(u8, source, at).?, first.span.start);
    try t.expect(std.mem.indexOf(u8, first.message, advice) != null);
}

/// One program per type: the literal beside each operand shape, on both sides, for an arithmetic operator, a comparison,
/// `bit_and` (integers) and `min`/`max`, each result bound and then required to have its exact type.
fn shapes(comptime ty: []const u8, comptime integer: bool) ![]u8 {
    const operands = [_][]const u8{ "x", "b.v", "xs[0]", "n(x)", "(x + x)", ty ++ "(x)" };
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(t.allocator);
    const head = "record Box:\n    v: " ++ ty ++ "\n\n\nfunc n(x: " ++ ty ++ ") -> " ++ ty ++ ":\n    return x\n\n\n" ++
        "func probe(x: " ++ ty ++ ", b: Box, xs: " ++ ty ++ "[]) -> int:\n";
    try text.appendSlice(t.allocator, head);
    for (operands, 0..) |operand, index| {
        const forms = if (integer)
            [_][]const u8{ "{s} + 1", "1 + {s}", "{s} != 0", "0 != {s}", "bit_and({s}, 1)", "bit_and(1, {s})", "max({s}, 1)", "min(1, {s})" }
        else
            [_][]const u8{ "{s} + 1", "1 + {s}", "{s} != 0", "0 != {s}", "{s} * 2.5", "2.5 * {s}", "max({s}, 1)", "min(1, {s})" };
        inline for (forms, 0..) |form, slot| {
            const result = if (std.mem.indexOf(u8, form, "!=") != null) "bool" else ty;
            const expression = try std.fmt.allocPrint(t.allocator, form, .{operand});
            defer t.allocator.free(expression);
            const line = try std.fmt.allocPrint(t.allocator, "    const v{d}_{d} = {s}\n    const w{d}_{d}: {s} = v{d}_{d}\n    _ = w{d}_{d}\n", .{ index, slot, expression, index, slot, result, index, slot, index, slot });
            defer t.allocator.free(line);
            try text.appendSlice(t.allocator, line);
        }
    }
    try text.appendSlice(t.allocator, "    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    return text.toOwnedSlice(t.allocator);
}

test "a literal takes the integer type of a name, field, index, call, nested operator or conversion beside it, on either side" {
    inline for (.{ "i8", "i16", "i32", "i64", "int", "u8", "u16", "u32", "u64" }) |ty| {
        const program = try shapes(ty, true);
        defer t.allocator.free(program);
        try accepts(program);
    }
}

test "a literal takes the f32 or float type of a name, field, index, call, nested operator or conversion beside it" {
    inline for (.{ "f32", "float" }) |ty| {
        const program = try shapes(ty, false);
        defer t.allocator.free(program);
        try accepts(program);
    }
}

test "a literal inside a comparison chain takes the type of the call beside it" {
    try accepts("func n(x: u16) -> u16:\n    return x\n\n\nfunc main() -> int:\n    const inside = 0 <= n(3u16) < 10\n" ++
        "    const flag: bool = inside\n    const also = 1 < n(5u16) <= 60000\n    if flag and also:\n        return 0\n    return 1\n");
}

test "the three reported lines check: a call's result, a nested builtin and a nested sum beside a literal" {
    // selka-protobuf F-PB-3: `num(x) != 0` with `num -> i32`.
    try accepts("func num(x: int) -> i32:\n    return 0i32\n\n\nfunc a(x: int) -> bool:\n    if num(x) != 0:\n        return True\n" ++
        "    return num(x) != 0\n\n\nfunc main() -> int:\n    if a(1):\n        return 1\n    return 0\n");
    // selka-samples SP3-F-7: a `u64` mix whose shift counts are literals.
    try accepts("func mix(x: u64) -> int:\n    return int(shift_right(bit_xor(x, shift_right(x, 29)), 24))\n\n\n" ++
        "func main() -> int:\n    return mix(12345u64)\n");
    // selka-protobuf F-PB-1: a literal after a nested sum of an `i32` and a literal, inside a conversion.
    try accepts("func b(x: i32) -> u32:\n    return u32(x + 2147483647 + 1) + 2147483648u32\n\n\n" ++
        "func d(x: i64) -> u64:\n    return u64(x + 9223372036854775807 + 1) + 9223372036854775808u64\n\n\nfunc main() -> int:\n    return 0\n");
}

// Each of these checked before the rule reached calls and nested operators; each keeps the type it had. The binding has
// no annotation, so only the operands type it, and the typed `const` after it requires that exact type.
const pinned = [_]struct { expression: []const u8, ty: []const u8 }{
    .{ .expression = "x + 1", .ty = "i32" },
    .{ .expression = "1 - x", .ty = "i32" },
    .{ .expression = "MASK + 1", .ty = "u32" },
    .{ .expression = "b.v * 2", .ty = "u16" },
    .{ .expression = "bytes8[0] + 1", .ty = "u8" },
    .{ .expression = "whole(2) + 1", .ty = "int" },
    .{ .expression = "1 + whole(2)", .ty = "int" },
    .{ .expression = "len(names) == 0", .ty = "bool" },
    .{ .expression = "0 < len(names)", .ty = "bool" },
    .{ .expression = "half(1.5) * 2", .ty = "float" },
    .{ .expression = "2 * half(1.5)", .ty = "float" },
    .{ .expression = "half(1.5) + 0x10", .ty = "float" },
    .{ .expression = "whole(2) / 2", .ty = "float" },
    .{ .expression = "whole(2) // 2", .ty = "int" },
    .{ .expression = "narrow(x) * 2.5", .ty = "float" },
    .{ .expression = "single(1.0f32) * 2.0", .ty = "f32" },
    .{ .expression = "2.0 * single(1.0f32)", .ty = "f32" },
    .{ .expression = "1 + 2", .ty = "int" },
    .{ .expression = "1.5 + 2", .ty = "float" },
    .{ .expression = "whole(2) % 3", .ty = "int" },
    .{ .expression = "max(whole(2), 1)", .ty = "int" },
    .{ .expression = "-1 * whole(2)", .ty = "int" },
};

test "twenty-two expressions that checked before keep their types" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "const MASK: u32 = 0xFF00_0000\n\n\nrecord Box:\n    v: u16\n\n\n" ++
        "func whole(x: int) -> int:\n    return x\n\n\nfunc half(x: float) -> float:\n    return x\n\n\n" ++
        "func narrow(x: i32) -> i32:\n    return x\n\n\nfunc single(x: f32) -> f32:\n    return x\n\n\n" ++
        "func probe(x: i32, b: Box, bytes8: u8[], names: str[]) -> int:\n");
    for (pinned, 0..) |case, index| {
        const line = try std.fmt.allocPrint(t.allocator, "    const v{d} = {s}\n    const w{d}: {s} = v{d}\n    _ = w{d}\n", .{ index, case.expression, index, case.ty, index, index });
        defer t.allocator.free(line);
        try text.appendSlice(t.allocator, line);
    }
    try text.appendSlice(t.allocator, "    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try accepts(text.items);
}

test "a literal its neighbour's type cannot hold is refused at the literal, naming the neighbour" {
    const head = "func n(x: i8) -> i8:\n    return x\n\n\nfunc u(x: u64) -> u64:\n    return x\n\n\n";
    try refusesAt(head ++ "func main() -> int:\n    return int(n(3i8) + 200)\n", "E_INTEGER_RANGE", "200", "does not fit i8, the type it takes beside the i8 value of `n(3i8)`");
    try refusesAt(head ++ "func main() -> int:\n    const x: i8 = 3i8\n    return int(300 + x)\n", "E_INTEGER_RANGE", "300", "beside the i8 value of `x`");
    try refusesAt(head ++ "func main() -> int:\n    return int(u(3u64) - -1)\n", "E_INTEGER_RANGE", "-1", "does not fit u64");
    const shift = "func main() -> int:\n    return int(shift_right(bit_xor(u(1u64), shift_right(u(1u64), 29u64)), 2.5))\n";
    try refusesAt(head ++ shift, "E_TYPE", "2.5", "cannot take the u64 type of `bit_xor(...)` beside it; `shift_right` takes two operands of one integer type");
    try refusesAt(head ++ "func main() -> int:\n    return int(min(n(3i8), 2.5))\n", "E_PRELUDE_TYPE", "2.5", "the literal `2.5` is float and cannot take the i8 type of `n(3i8)` beside it");
}

test "a product that starts with a suffixed literal is an operand, not the literal, beside a peer of its type (FR84)" {
    const head = "record Ep:\n    number: u32\n    wide: u64\n    small: u8\n\n\nfunc probe(ep: Ep) -> int:\n";
    const tail = "\n\nfunc main() -> int:\n    return 0\n";
    try accepts(head ++ "    const a = shift_left(1u32, 2u32 * ep.number)\n    const b = bit_or(1u32, 2u32 * ep.number)\n" ++
        "    const c = shift_left(1u64, 2u64 * ep.wide)\n    const d = wrapping_add(1u32, 2u32 + ep.number)\n" ++
        "    const e = min(1u8, 2u8 * ep.small)\n    return int(a) + int(b) + int(c) + int(d) + int(e)\n" ++ tail);
    // Two different integer types stay refused, at the operator's first operand, with the operator's own message.
    try refusesAt(head ++ "    return int(shift_left(1u32, 2u64 * ep.wide))\n" ++ tail, "E_TYPE", "shift_left(1u32", "expected u32, found u64");
    // A literal its peer's type cannot hold keeps its message.
    try refusesAt(head ++ "    return int(bit_or(1u8, 300))\n" ++ tail, "E_INTEGER_RANGE", "300", "the literal `300` does not fit u8, the type it takes beside the u8 value of `1u8`");
}

test "a literal with no typed neighbour keeps int or float, and a context type still wins over a neighbour" {
    try accepts("func main() -> int:\n    const a = 7 * 6\n    const b = 1.5 * 2\n    const c: int = a\n    const d: float = b\n    return c - 42 + int(d) - 3\n");
    // The annotation types the literal `1` as `i64`; the `i32` call beside it is still refused, at the operator.
    try refusesAt("func n(x: i32) -> i32:\n    return x\n\n\nfunc main() -> int:\n    const y: i64 = n(3i32) + 1\n    return int(y)\n", "E_TYPE", "+ 1", "expected i32, found int");
}

test "the literal rule reads the syntax tables only as a checker internal, audited for lazy loading" {
    const lazy_readers = @import("lazy_readers.zig");
    var found: ?lazy_readers.Safety = null;
    for (lazy_readers.audited) |entry| {
        if (std.mem.eql(u8, entry.path, "src/literal_peer.zig")) found = entry.safety;
    }
    try t.expectEqual(@as(?lazy_readers.Safety, .checker), found);
}
