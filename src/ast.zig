//! Untyped expression and statement tables preserve source spelling and locations.
const std = @import("std");
const Span = @import("source.zig").Span;
pub const NodeId = enum(usize) { _ };
pub const StatementId = enum(usize) { _ };
pub const BinaryOp = enum { add, sub, mul, div, rem, logical_and, logical_or, eq, ne, lt, le, gt, ge };
pub const AssignmentOp = enum { set, add, sub };
pub const UnaryOp = enum { neg, not };
pub const TypedValue = struct { ty: Span, value: NodeId };
pub const Node = struct {
    span: Span,
    data: union(enum) {
        integer: Span,
        boolean: bool,
        name: Span,
        read_ref: Span,
        propagate: NodeId,
        read_slice: struct { name: Span, index: NodeId },
        len_slice: Span,
        cast: TypedValue,
        wrap: TypedValue,
        variant: struct { ty: Span, name: Span, value: ?NodeId },
        unwrap: NodeId,
        array: struct { ty: Span, values: []const NodeId },
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: struct { name: Span, fields: []const FieldInit },
        update: struct { base: NodeId, fields: []const FieldInit },
        field: struct { base: NodeId, name: Span },
        call: struct { owner: ?Span = null, name: Span, arguments: []const NodeId },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
pub const Statement = struct {
    span: Span,
    data: union(enum) {
        block: []const StatementId,
        ret: NodeId,
        borrow_call: struct { call: NodeId, name: Span, mutable: bool, body: StatementId },
        borrow: struct { owner: Span, name: Span, mutable: bool, body: StatementId, range: ?Range = null },
        write_slice: struct { name: Span, index: NodeId, value: NodeId },
        write_ref: struct { name: Span, value: NodeId },
        discard: NodeId,
        acknowledge: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { condition: NodeId, body: StatementId },
        binding: struct { name: Span, annotation: ?Span, mutable: bool, value: NodeId },
        assignment: struct { name: Span, value: NodeId, op: AssignmentOp, op_span: Span },
    },
};
pub const MatchArm = struct { ty: Span, name: Span, binding: ?Span, discard_payload: bool, body: StatementId };
pub const Variant = struct { name: Span, payload: ?Span };
pub const Variants = struct { fallible: bool = false, name: Span, is_union: bool, cases: []const Variant };
pub const FieldInit = struct { name: Span, value: NodeId };
pub const Record = struct { name: Span, fields: []const Parameter };
pub const Range = struct { start: NodeId, end: NodeId };
pub const Parameter = struct { name: Span, ty: Span, reference: ?bool = null, slice: bool = false };
pub const Domain = struct { name: Span, backing: Span };
pub const ReturnReference = struct { source: Span, mutable: bool, slice: bool };
pub const Function = struct { return_reference: ?ReturnReference = null, owner: ?Span = null, restricted: bool = false, conversion: bool = false, name: Span, parameters: []const Parameter, return_type: Span, body: StatementId };
pub const ArrayIndex = union(enum) { length: Span, enum_type: Span };
pub const ArrayType = struct { span: Span, index: ArrayIndex, element: Span };
pub const Program = struct {
    domains: []const Domain = &.{},
    variants: []const Variants = &.{},
    array_types: []const ArrayType = &.{},
    nodes: std.ArrayList(Node),
    statements: std.ArrayList(Statement),
    functions: []const Function,
    records: []const Record,
};
