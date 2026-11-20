//! Prelude helpers for truncating integer division and remainder.
//! Python `//` floors and `%` follows that quotient, which is the only division the surface
//! spells. `divtrunc(a, b)` and `remtrunc(a, b)` keep the toward-zero rounding that binary
//! formats, C interfaces and migrated legacy code depend on, and trap on the same inputs.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Call = @import("call_arguments.zig").Call;

/// Truncating operator named by a prelude helper, or null for every other name.
pub fn operation(name: []const u8) ?ast.BinaryOp {
    if (std.mem.eql(u8, name, "divtrunc")) return .div;
    if (std.mem.eql(u8, name, "remtrunc")) return .rem;
    return null;
}

/// Rewrite `divtrunc(a, b)` or `remtrunc(a, b)` into the truncating binary node, so operand
/// typing, lowering, execution and native emission follow the existing integer rules.
/// `shadowed` reports a local binding or declared function of the same name, which wins.
pub fn lower(src: source.Source, call: Call, span: source.Span, shadowed: bool, sink: *diagnostic.Sink) diagnostic.Error!?ast.Node {
    if (call.owner != null or call.type_arguments.len != 0 or shadowed) return null;
    const op = operation(src.text(call.name)) orelse return null;
    try @import("call_arguments.zig").positional(call, sink);
    if (call.arguments.len != 2) return sink.fail(
        "E_ARITY",
        call.name,
        "divtrunc and remtrunc take a dividend and a divisor",
    );
    return .{ .span = span, .data = .{ .binary = .{
        .op = op,
        .left = call.arguments[0],
        .right = call.arguments[1],
        .op_span = call.name,
    } } };
}
