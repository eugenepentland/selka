//! An unsuffixed literal beside a typed operand takes that operand's type (`docs/integer-operations.md`), whatever shape
//! the operand has. The hint pass gives a literal its type before either operand is checked, from what the syntax alone
//! shows (`Checker.obviousType`: a name, a field, an index); a call's result, a nested operator or a conversion shows
//! nothing there, so the literal kept `int` and the operator refused the pair. When the hint pass leaves a literal
//! operand without a numeric type, its neighbour is checked first and the neighbour's checked type becomes the
//! literal's expectation (the work queue's `hint_from`, the comparison chain's own order). The rule for that expectation
//! and the refusals that point at the literal live here.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const float_syntax = @import("float_syntax.zig");
const integer_literal = @import("integer_literal.zig");
const number_literal = @import("number_literal.zig");
const numeric_surface = @import("numeric_surface.zig");
const Error = diagnostic.Error;

/// Where a literal meets its neighbour. An operator converts an integer beside a `float` itself, so a literal there
/// keeps the `int` it has today; the two arguments of `min` and `max` must already have one type.
pub const Site = enum { operator, argument };

/// Whether `text` spells a literal with no type of its own: an unsuffixed integer, or a float without `f32`.
pub fn bareText(text: []const u8) bool {
    if (float_syntax.isLiteral(text)) return !float_syntax.isF32Literal(text);
    return integer_literal.unsuffixed(text);
}

/// The literal token of an unsuffixed literal operand, `k` or `-k`, or null for any other expression.
pub fn token(src: source.Source, nodes: []const ast.Node, id: ast.NodeId) ?source.Span {
    const node = nodes[@backingInt(id)];
    const spelled = switch (node.data) {
        .integer => |at| at,
        .unary => |u| if (u.op == .neg and nodes[@backingInt(u.operand)].data == .integer) nodes[@backingInt(u.operand)].data.integer else return null,
        else => return null,
    };
    return if (bareText(src.text(spelled))) spelled else null;
}

/// The type a literal spelled `text` takes beside an operand of type `beside` at `site`, or null when it keeps its own:
/// an integer type for an integer spelling, `f32` for any spelling, and `float` for an argument of `min` or `max`.
/// A neighbour of the literal's own type (`int` beside an integer spelling, `float` beside a float one) changes nothing,
/// so the literal is left exactly as it was typed before (`-1 * f()` stays a negation of `1`).
pub fn adopted(records: []const typed.Record, text: []const u8, beside: typed.Type, site: Site) ?typed.Type {
    const float_spelling = float_syntax.isLiteral(text);
    if (beside.isInteger()) return if (float_spelling or beside == .i64) null else beside;
    if (numeric_surface.isF32(beside, records)) return beside;
    if (numeric_surface.isBinaryFloat(beside, records) and site == .argument and !float_spelling) return beside;
    return null;
}

/// The literal and the operand it takes its type from, when exactly one of two operands is an unsuffixed literal and
/// the hint pass gave it no numeric type.
pub const Pair = struct { literal: ast.NodeId, peer: ast.NodeId };

/// The literal-and-peer pair of two operands that the peer's checked type must type, or null.
pub fn awaiting(comptime Checker: type, self: *Checker, left: ast.NodeId, right: ast.NodeId) ?Pair {
    const nodes = self.syntax.nodes.items;
    const left_literal = token(self.src, nodes, left) != null;
    const right_literal = token(self.src, nodes, right) != null;
    if (left_literal == right_literal) return null;
    const pair: Pair = if (left_literal) .{ .literal = left, .peer = right } else .{ .literal = right, .peer = left };
    if (self.expected_types.get(nodes[@backingInt(pair.literal)].span)) |hinted| {
        if (hinted.isInteger() or numeric_surface.isBinaryFloat(hinted, self.catalog.records)) return null;
    }
    return pair;
}

/// Give the literal `literal` the type its checked neighbour `peer` has, by `adopted`'s rule, refusing at the literal a
/// value that type cannot hold.
pub fn hint(comptime Checker: type, self: *Checker, literal: ast.NodeId, peer: ast.NodeId, site: Site) Error!void {
    const checked = self.resolved.at(@backingInt(peer)) orelse return error.InternalError;
    const beside = self.nodes.items[@backingInt(checked)].ty;
    const spelled = token(self.src, self.syntax.nodes.items, literal) orelse return;
    const ty = adopted(self.catalog.records, self.src.text(spelled), beside, site) orelse return;
    try refuseUnfit(Checker, self, literal, ty, peer);
    try self.hint(literal, ty);
}

/// Refuse, at the literal, an unsuffixed integer literal operand whose value the integer type `ty` of its neighbour
/// `peer` cannot hold, naming the neighbour. Any other operand, or a value that fits, passes.
pub fn refuseUnfit(comptime Checker: type, self: *Checker, literal: ast.NodeId, ty: typed.Type, peer: ast.NodeId) Error!void {
    if (!ty.isInteger()) return;
    const nodes = self.syntax.nodes.items;
    const spelled = token(self.src, nodes, literal) orelse return;
    const text = self.src.text(spelled);
    if (float_syntax.isLiteral(text)) return;
    const parts = switch (number_literal.integer(text)) {
        .ok => |parts| parts,
        .bad => return,
    };
    const negated = nodes[@backingInt(literal)].data == .unary;
    const limit: i128 = if (negated) -ty.min() else ty.max();
    if (number_literal.magnitude(parts)) |magnitude| if (magnitude <= limit) return;
    const span = nodes[@backingInt(literal)].span;
    const name = try typed.surfaceTypeName(self.allocator, ty, self.catalog.records);
    const message = try std.fmt.allocPrint(self.allocator, "the literal `{s}` does not fit {s}, the type it takes beside the {s} value of `{s}`{s}", .{
        self.src.text(span), name, name, try describe(self.allocator, self.src.text(nodes[@backingInt(peer)].span)), wider(ty),
    });
    return self.sink.fail(number_literal.range_code, span, message);
}

/// The advice that ends a range refusal: a narrower neighbour can be converted to a 64-bit type first.
fn wider(ty: typed.Type) []const u8 {
    if (ty == .i64 or ty == .u64) return "";
    return if (ty.integer().?.signed) "; to compute with it, convert the other operand with i64(...)" else "; to compute with it, convert the other operand with u64(...) or i64(...)";
}

/// Refuse, at the literal, a float literal beside an integer operand where the two must have one type (an integer
/// operation, `min`, `max`): `rule` says why they must agree. Any other pair passes, and the caller's own refusal follows.
pub fn refuseMismatch(comptime Checker: type, self: *Checker, code: []const u8, left: typed.NodeId, right: typed.NodeId, rule: []const u8) Error!void {
    const left_node = self.nodes.items[@backingInt(left)];
    const right_node = self.nodes.items[@backingInt(right)];
    const left_literal = floatLiteral(self.src.text(left_node.span));
    if (left_literal == floatLiteral(self.src.text(right_node.span))) return;
    const literal = if (left_literal) left_node else right_node;
    const peer = if (left_literal) right_node else left_node;
    if (!peer.ty.isInteger()) return;
    const message = try std.fmt.allocPrint(self.allocator, "the literal `{s}` is {s} and cannot take the {s} type of `{s}` beside it; {s}", .{
        self.src.text(literal.span),
        try typed.surfaceTypeName(self.allocator, literal.ty, self.catalog.records),
        try typed.surfaceTypeName(self.allocator, peer.ty, self.catalog.records),
        try describe(self.allocator, self.src.text(peer.span)),
        rule,
    });
    return self.sink.fail(code, literal.span, message);
}

/// Whether a checked operand's source text is an unsuffixed float literal, `k` or `-k`: one number token, so an
/// expression that only starts with a literal (`2u32 * ep.number`, whose `.` and `e` look like a float's) is not one.
fn floatLiteral(text: []const u8) bool {
    const digits = std.mem.trimStart(u8, if (std.mem.startsWith(u8, text, "-")) text[1..] else text, " ");
    return digits.len != 0 and std.ascii.isDigit(digits[0]) and oneNumberToken(digits) and float_syntax.isLiteral(digits) and bareText(digits);
}

/// Whether `text` is a single number token: digits, letters, `_` and `.`, with a sign only right after an exponent `e`.
fn oneNumberToken(text: []const u8) bool {
    for (text, 0..) |c, index| {
        if (std.ascii.isAlphanumeric(c) or c == '_' or c == '.') continue;
        const exponent_sign = (c == '-' or c == '+') and index > 0 and (text[index - 1] == 'e' or text[index - 1] == 'E');
        if (!exponent_sign) return false;
    }
    return true;
}

/// A neighbour's spelling short enough for one message: a long call keeps its name (`bit_xor(...)`).
pub fn describe(allocator: std.mem.Allocator, text: []const u8) Error![]const u8 {
    const limit = 24;
    if (text.len <= limit) return text;
    if (std.mem.indexOfScalar(u8, text, '(')) |open| if (open > 0 and open <= limit) return std.fmt.allocPrint(allocator, "{s}(...)", .{text[0..open]});
    return std.fmt.allocPrint(allocator, "{s}...", .{text[0..limit]});
}

test "an unsuffixed literal takes an integer or f32 neighbour's type, and a float one only as an argument" {
    const records: []const typed.Record = &.{};
    try std.testing.expectEqual(@as(?typed.Type, .u64), adopted(records, "24", .u64, .operator));
    try std.testing.expectEqual(@as(?typed.Type, .i8), adopted(records, "0x7F", .i8, .argument));
    try std.testing.expectEqual(@as(?typed.Type, null), adopted(records, "2.5", .i32, .operator));
    try std.testing.expectEqual(@as(?typed.Type, null), adopted(records, "1", .bool, .operator));
    try std.testing.expectEqual(@as(?typed.Type, null), adopted(records, "1", .i64, .operator));
}

test "a literal operand is an unsuffixed integer or float spelling, never a suffixed one" {
    try std.testing.expect(bareText("24"));
    try std.testing.expect(bareText("0b1010"));
    try std.testing.expect(bareText("2.5"));
    try std.testing.expect(!bareText("24u64"));
    try std.testing.expect(!bareText("2.5f32"));
}

test "a float operand spelled as a literal is recognised with or without its sign" {
    try std.testing.expect(floatLiteral("2.5"));
    try std.testing.expect(floatLiteral("-2.5"));
    try std.testing.expect(!floatLiteral("2"));
    try std.testing.expect(!floatLiteral("2.5f32"));
    try std.testing.expect(!floatLiteral("x"));
    try std.testing.expect(floatLiteral("1.5e-3"));
    // An expression that starts with a literal is not one, though `ep.number` holds a `.` and an `e` (FR84).
    try std.testing.expect(!floatLiteral("2u32 * ep.number"));
    try std.testing.expect(!floatLiteral("2.5 * x"));
    try std.testing.expect(!floatLiteral("2e3-x"));
}

test "a long neighbour is named by its call" {
    try std.testing.expectEqualStrings("n32(x)", try describe(std.testing.allocator, "n32(x)"));
    const long = try describe(std.testing.allocator, "bit_xor(x, shift_right(x, 29))");
    defer std.testing.allocator.free(long);
    try std.testing.expectEqualStrings("bit_xor(...)", long);
}
