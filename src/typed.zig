//! Checked nodes use declaration identities, concrete types, and local slots.
const Span = @import("source.zig").Span;
pub const NodeId = enum(usize) { _ };
pub const StatementId = enum(usize) { _ };
pub const FunctionId = enum(usize) { _ };
pub const LocalId = enum(usize) { _ };
pub const Type = @import("value.zig").Type;
pub const Value = @import("value.zig").Value;
pub const BinaryOp = enum { add, sub, mul, div, rem, logical_and, logical_or, eq, ne, lt, le, gt, ge };
pub const UnaryOp = enum { neg, not };
pub const Node = struct {
    ty: Type,
    span: Span,
    data: union(enum) {
        integer: i128,
        boolean: bool,
        local: LocalId,
        cast: NodeId,
        record: []const FieldInit,
        update: struct { base: NodeId, fields: []const FieldInit },
        field: struct { base: NodeId, index: usize },
        call: struct { function: FunctionId, arguments: []const NodeId },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
pub const FieldInit = struct { index: usize, value: NodeId };
pub const Field = struct { name: []const u8, declaration: Span, ty: Type };
pub const Record = struct { id: Type, name: []const u8, declaration: Span, fields: []const Field };
pub fn typeName(ty: Type, records: []const Record) []const u8 {
    return if (ty.isRecord()) records[ty.recordIndex()].name else @tagName(ty);
}
pub const Store = struct { slot: LocalId, value: NodeId };
pub const Statement = struct {
    span: Span,
    terminates: bool,
    data: union(enum) {
        block: []const StatementId,
        ret: NodeId,
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        loop: struct { condition: NodeId, body: StatementId },
        initialize: Store,
        assign: Store,
    },
};
pub const Local = struct { name: []const u8, declaration: Span, ty: Type, mutable: bool, reads: usize = 0, writes: usize = 0 };
pub const Function = struct {
    conversion: bool = false,
    id: FunctionId,
    name: []const u8,
    declaration: Span,
    return_type: Type,
    parameter_count: usize,
    body: StatementId,
    locals: []const Local,
};
pub const Program = struct { nodes: []const Node, statements: []const Statement, functions: []const Function, main: FunctionId, records: []const Record = &.{} };
