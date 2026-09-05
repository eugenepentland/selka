//! Untyped expression and statement tables preserve source spelling and locations.
const std = @import("std");
const Span = @import("source.zig").Span;
pub const NodeId = enum(usize) { _ };
pub const StatementId = enum(usize) { _ };
pub const BinaryOp = enum { add, sub, mul, div, rem, logical_and, logical_or, eq, ne, lt, le, gt, ge };
pub const AssignmentOp = enum { set, add, sub };
pub const UnaryOp = enum { neg, not };
pub const Node = struct {
    span: Span,
    data: union(enum) {
        integer: Span,
        boolean: bool,
        name: Span,
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
pub const Statement = struct {
    span: Span,
    data: union(enum) {
        block: []const StatementId,
        ret: NodeId,
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        loop: struct { condition: NodeId, body: StatementId },
        binding: struct { name: Span, annotation: ?Span, mutable: bool, value: NodeId },
        assignment: struct { name: Span, value: NodeId, op: AssignmentOp, op_span: Span },
    },
};
pub const Program = struct {
    nodes: std.ArrayList(Node),
    statements: std.ArrayList(Statement),
    name: Span,
    return_type: Span,
    body: StatementId,
};
