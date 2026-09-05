//! Checked nodes use declaration identities, concrete types, and local slots.
const Span = @import("source.zig").Span;
pub const NodeId = enum(usize) { _ };
pub const StatementId = enum(usize) { _ };
pub const FunctionId = enum(usize) { _ };
pub const LocalId = enum(usize) { _ };
pub const Type = enum { i64, bool };
pub const Value = union(Type) { i64: i64, bool: bool };
pub const BinaryOp = enum { add, sub, mul, div, rem, logical_and, logical_or, eq, ne, lt, le, gt, ge };
pub const UnaryOp = enum { neg, not };
pub const Node = struct {
    ty: Type,
    span: Span,
    data: union(enum) {
        integer: i64,
        boolean: bool,
        local: LocalId,
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
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
    id: FunctionId,
    name: []const u8,
    declaration: Span,
    return_type: Type,
    body: StatementId,
    locals: []const Local,
};
pub const Program = struct { nodes: []const Node, statements: []const Statement, functions: []const Function };
