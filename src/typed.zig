//! Checked nodes use declaration identities, concrete types, and local slots.
const Span = @import("source.zig").Span;
pub const NodeId = enum(usize) { _ };
pub const StatementId = enum(usize) { _ };
pub const FunctionId = enum(usize) { _ };
pub const ReferenceId = enum(usize) { _ };
pub const Reference = struct { slice: bool = false, parameter: bool = false, name: []const u8, declaration: Span, owner: LocalId, parent: ?ReferenceId, ty: Type, mutable: bool };
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
        read_ref: ReferenceId,
        read_slice: struct { reference: ReferenceId, index: NodeId },
        len_slice: ReferenceId,
        cast: NodeId,
        wrap: NodeId,
        variant: struct { tag: usize, value: ?NodeId },
        unwrap: NodeId,
        array: []const NodeId,
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: []const FieldInit,
        update: struct { base: NodeId, fields: []const FieldInit },
        field: struct { base: NodeId, index: usize },
        call: struct { function: FunctionId, arguments: []const NodeId, references: []const ReferenceId = &.{} },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
pub const FieldInit = struct { index: usize, value: NodeId };
pub const Field = struct { name: []const u8, declaration: Span, ty: Type };
pub const Variant = struct { name: []const u8, declaration: Span, payload: ?Type };
pub const Variants = struct { is_union: bool, cases: []const Variant };
pub const Array = struct { element: Type, length: usize, key: ?Type = null };
// Aggregate schemas retain nominal record identities and intern structural arrays.
pub const Record = struct {
    id: Type,
    name: []const u8,
    declaration: Span,
    fields: []const Field,
    array: ?Array = null,
    domain: ?Type = null,
    variants: ?Variants = null,
    pub fn tableKey(self: Record) ?Type {
        return if (self.array) |a| a.key else null;
    }
    pub fn isRecord(self: Record) bool {
        return self.array == null and self.domain == null and self.variants == null;
    }
    pub fn isEnum(self: Record) bool {
        return if (self.variants) |v| !v.is_union else false;
    }
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
    cleanup: []const ReferenceId = &.{},
    data: union(enum) {
        block: []const StatementId,
        ret: NodeId,
        borrow: struct { reference: ReferenceId, body: StatementId, range: ?Range = null },
        write_slice: struct { reference: ReferenceId, index: NodeId, value: NodeId },
        write_ref: struct { reference: ReferenceId, value: NodeId },
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { condition: NodeId, body: StatementId },
        initialize: Store,
        assign: Store,
    },
};
pub const MatchArm = struct { tag: usize, slot: ?LocalId, body: StatementId };
pub const Range = struct { start: NodeId, end: NodeId };
pub const Local = struct { slice_parameter: bool = false, reference_parameter: ?bool = null, name: []const u8, declaration: Span, ty: Type, mutable: bool, mutable_borrow: bool = false, reads: usize = 0, writes: usize = 0 };
pub const Function = struct {
    references: []const Reference = &.{},
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
