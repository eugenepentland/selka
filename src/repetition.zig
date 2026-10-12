//! PY-REPEAT-1: `sequence * count` and `count * sequence` for `str`, `bytes`
//! and `list[T]`, as Python repeats them.
//!
//! A repeated `str` or `bytes` remains a binary operation: Core borrows its
//! operands and produces one exactly-sized allocation. A repeated list creates
//! independent elements under value semantics. A count of zero or less answers
//! an empty value. Both operands are evaluated once, left to right.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

/// The sequence kinds `*` repeats: text, immutable octets and lists.
pub fn repeatable(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    // A value record such as `float` has a collection kind field too; only a
    // managed collection is a sequence.
    if (!record.isCollection()) return false;
    return switch (record.collection.kind) {
        .string, .list => true,
        .bytes => !std.mem.eql(u8, record.name, "byte_buffer"),
        else => false,
    };
}

/// One checked repetition: the sequence operand, the count operand and which
/// of the two the source wrote first.
pub const Operands = struct { sequence: typed.NodeId, count: typed.NodeId, count_first: bool };

/// Preserve repetition as a binary operation so Core can borrow its operands.
pub fn build(comptime Checker: type, checker: *Checker, span: source.Span, operands: Operands) diagnostic.Error!typed.Node {
    const sequence_type = checker.nodes.items[@backingInt(operands.sequence)].ty;
    return .{ .span = span, .ty = sequence_type, .data = .{ .binary = .{
        .op = .mul,
        .op_span = span,
        .left = if (operands.count_first) operands.count else operands.sequence,
        .right = if (operands.count_first) operands.sequence else operands.count,
    } } };
}
