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
        wrap: NodeId,
        unwrap: NodeId,
        array: []const NodeId,
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
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
pub const Array = struct { element: Type, length: usize };
// Aggregate schemas retain nominal record identities and intern structural arrays.
pub const Record = struct {
    id: Type,
    name: []const u8,
    declaration: Span,
    fields: []const Field,
    array: ?Array = null,
    domain: ?Type = null,
    pub fn count(self: Record) usize {
        return if (self.array) |a| a.length else if (self.domain != null) 1 else self.fields.len;
    }
    pub fn elementType(self: Record, index: usize) Type {
        return if (self.array) |a| a.element else self.domain orelse self.fields[index].ty;
    }
};
pub fn typeName(ty: Type, records: []const Record) []const u8 {
    return if (ty.isAggregate()) records[ty.recordIndex()].name else @tagName(ty);
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
    owner: ?Type = null,
    restricted: bool = false,
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
