//! Checked nodes use declaration identities, concrete types, and local slots.
const std = @import("std");
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
        read_field: struct { owner: LocalId, field: usize },
        propagate: struct { value: NodeId, output: Type, cleanup: []const ReferenceId },
        read_slice: struct { reference: ReferenceId, index: NodeId },
        len_slice: ReferenceId,
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: LocalId, arguments: []const NodeId },
        acquire_resource: struct { capability: NodeId, request: NodeId },
        complete_resource: NodeId,
        resource_io: struct { reference: ?ReferenceId = null, kind: @import("external_resources.zig").IoKind, owner: LocalId, value: ?NodeId },
        restrict_resource: struct { permissions: @import("external_resources.zig").Permissions, value: NodeId },
        environment_get: struct { capability: NodeId, name: NodeId },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, capability: NodeId },
        acquire_buffer: struct { allocator: NodeId, capacity: NodeId },
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
pub const Variants = struct { fallible: bool = false, is_union: bool, cases: []const Variant };
pub const Array = struct { element: Type, length: usize, key: ?Type = null };
// Aggregate schemas retain nominal record identities and intern structural arrays.
pub const Record = struct {
    buffer: ?Type = null,
    resource: ?@import("external_resources.zig").Kind = null,
    move_only: bool = false,
    requires_handling: bool = false,
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
        return self.resource == null and self.buffer == null and self.array == null and self.domain == null and self.variants == null;
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
pub const ResultShape = struct { ok_type: Type, error_type: Type, ok_tag: usize, error_tag: usize };
pub fn resultShape(ty: Type, records: []const Record) ?ResultShape {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const variants = records[ty.recordIndex()].variants orelse return null;
    if (!variants.fallible or !variants.is_union or variants.cases.len != 2) return null;
    var ok: ?usize = null;
    var err: ?usize = null;
    for (variants.cases, 0..) |case, tag| {
        if (case.payload == null) return null;
        if (std.mem.eql(u8, case.name, "ok")) ok = tag;
        if (std.mem.eql(u8, case.name, "err")) err = tag;
    }
    return .{ .ok_type = variants.cases[ok orelse return null].payload.?, .error_type = variants.cases[err orelse return null].payload.?, .ok_tag = ok.?, .error_tag = err.? };
}
pub fn moveOnly(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].move_only;
}
pub fn requiresHandling(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].requires_handling;
}
pub fn typeName(ty: Type, records: []const Record) []const u8 {
    return if (ty.isAggregate()) records[ty.recordIndex()].name else @tagName(ty);
}
pub const Store = struct { slot: LocalId, value: NodeId };
pub const Statement = struct {
    span: Span,
    terminates: bool,
    owned_cleanup: []const LocalId = &.{},
    cleanup: []const ReferenceId = &.{},
    data: union(enum) {
        block: []const StatementId,
        ret: NodeId,
        ret_ref: ReferenceId,
        borrow_call: struct { call: NodeId, reference: ReferenceId, body: StatementId },
        borrow: struct { reference: ReferenceId, body: StatementId, range: ?Range = null },
        write_slice: struct { reference: ReferenceId, index: NodeId, value: NodeId },
        write_ref: struct { reference: ReferenceId, value: NodeId },
        discard: NodeId,
        acknowledge: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { condition: NodeId, body: StatementId },
        initialize: Store,
        assign: Store,
    },
};
pub const MatchArm = struct { tag: usize, slot: ?LocalId, body: StatementId };
pub const Range = struct { start: NodeId, end: NodeId };
pub const Local = struct { transfer_available: bool = false, slice_parameter: bool = false, reference_parameter: ?bool = null, name: []const u8, declaration: Span, ty: Type, mutable: bool, mutable_borrow: bool = false, reads: usize = 0, writes: usize = 0 };
pub const ReturnReference = struct { parameter: LocalId, mutable: bool, slice: bool };
pub const Function = struct {
    effect_bound: ?@import("effect_set.zig").Bound = null,
    effects: @import("effect_set.zig").Mask = 0,
    return_reference: ?ReturnReference = null,
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

pub fn resourceKind(ty: Type, records: []const Record) ?@import("external_resources.zig").Kind {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    return records[ty.recordIndex()].resource;
}
pub fn byteRequest(ty: Type, records: []const Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const array = records[ty.recordIndex()].array orelse return false;
    return array.element == .u8 and array.key == null;
}
pub const CompletionShape = struct { result: ResultShape, resource_type: Type, resource_field: usize, code_field: usize };
pub fn completionShape(ty: Type, records: []const Record) ?CompletionShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.ok_type != .bool or !result.error_type.isAggregate() or result.error_type.recordIndex() >= records.len) return null;
    const schema = records[result.error_type.recordIndex()];
    if (!schema.isRecord() or schema.fields.len != 2) return null;
    var resource_field: ?usize = null;
    var code_field: ?usize = null;
    for (schema.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.name, "resource") and resourceKind(field.ty, records) != null) resource_field = index;
        if (std.mem.eql(u8, field.name, "code") and field.ty == .i64) code_field = index;
    }
    const resource = resource_field orelse return null;
    return .{ .result = result, .resource_type = schema.fields[resource].ty, .resource_field = resource, .code_field = code_field orelse return null };
}

pub const ByteResultShape = struct { result: ResultShape, bytes_type: Type, bytes_field: usize, length_field: usize, flag_field: usize };
pub fn environmentShape(ty: Type, records: []const Record) ?ByteResultShape {
    return byteResultShape(ty, records, "present");
}
pub fn resourceReadShape(ty: Type, records: []const Record) ?ByteResultShape {
    return byteResultShape(ty, records, "eof");
}
fn byteResultShape(ty: Type, records: []const Record, flag_name: []const u8) ?ByteResultShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.error_type != .i64 or !result.ok_type.isAggregate() or result.ok_type.recordIndex() >= records.len) return null;
    const schema = records[result.ok_type.recordIndex()];
    if (!schema.isRecord() or schema.fields.len != 3) return null;
    var bytes: ?usize = null;
    var length: ?usize = null;
    var present: ?usize = null;
    for (schema.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.name, "bytes") and byteRequest(field.ty, records)) bytes = index;
        if (std.mem.eql(u8, field.name, "length") and field.ty == .u64) length = index;
        if (std.mem.eql(u8, field.name, flag_name) and field.ty == .bool) present = index;
    }
    const byte_field = bytes orelse return null;
    return .{ .result = result, .bytes_type = schema.fields[byte_field].ty, .bytes_field = byte_field, .length_field = length orelse return null, .flag_field = present orelse return null };
}

pub const SliceReadShape = struct { result: ResultShape, length_field: usize, eof_field: usize };
pub fn resourceSliceReadShape(ty: Type, records: []const Record) ?SliceReadShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.error_type != .i64 or !result.ok_type.isAggregate() or result.ok_type.recordIndex() >= records.len) return null;
    const schema = records[result.ok_type.recordIndex()];
    if (!schema.isRecord() or schema.fields.len != 2) return null;
    var length: ?usize = null;
    var eof: ?usize = null;
    for (schema.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.name, "length") and field.ty == .u64) length = index;
        if (std.mem.eql(u8, field.name, "eof") and field.ty == .bool) eof = index;
    }
    return .{ .result = result, .length_field = length orelse return null, .eof_field = eof orelse return null };
}
