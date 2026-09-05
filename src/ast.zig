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
        cast: struct { ty: Span, value: NodeId },
        array: struct { ty: Span, values: []const NodeId },
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: struct { name: Span, fields: []const FieldInit },
        update: struct { base: NodeId, fields: []const FieldInit },
        field: struct { base: NodeId, name: Span },
        call: struct { name: Span, arguments: []const NodeId },
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
pub const FieldInit = struct { name: Span, value: NodeId };
pub const Record = struct { name: Span, fields: []const Parameter };
pub const Parameter = struct { name: Span, ty: Span };
pub const Function = struct { conversion: bool = false, name: Span, parameters: []const Parameter, return_type: Span, body: StatementId };
pub const ArrayType = struct { span: Span, length: Span, element: Span };
pub const Program = struct {
    array_types: []const ArrayType = &.{},
    nodes: std.ArrayList(Node),
    statements: std.ArrayList(Statement),
    functions: []const Function,
    records: []const Record,
};
