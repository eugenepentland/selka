//! Checked nodes use declaration identities, concrete types, and local slots.
const std = @import("std");
const provider_contracts = @import("provider_contracts.zig");
const external_resources = @import("external_resources.zig");
const values = @import("value.zig");
const Acquisition = struct { allocator: NodeId, capacity: NodeId };
const FieldAccess = struct { reference: ?ReferenceId = null, owner: LocalId, field: usize };
const Span = @import("source.zig").Span;
/// Index of a checked expression in Program.nodes.
pub const NodeId = enum(usize) { _ };
/// Index of a checked statement in Program.statements.
pub const StatementId = enum(usize) { _ };
/// Index of a resolved function in Program.functions.
pub const FunctionId = enum(usize) { _ };
/// Index of a function-local reference descriptor.
pub const ReferenceId = enum(usize) { _ };
/// Checked borrow provenance, owner slot, element type, and mutability metadata.
pub const Reference = struct { mode: ReferenceMode = .{}, name: []const u8, declaration: Span, owner: LocalId, parent: ?ReferenceId, ty: Type, mutable: bool };
/// Distinguish slice views and incoming parameter loans from local whole-value loans.
pub const ReferenceMode = struct { temporary: bool = false, slice: bool = false, parameter: bool = false };
/// Index of a function-local value slot.
pub const LocalId = enum(usize) { _ };
pub const Type = values.Type;
pub const Value = values.Value;
/// Checked arithmetic, logical, and comparison operation categories.
pub const BinaryOp = enum { add, sub, mul, div, rem, logical_and, logical_or, eq, ne, lt, le, gt, ge };
/// Checked numeric negation and Boolean inversion operations.
pub const UnaryOp = enum { neg, not };
/// Typed expression with resolved operands and source location.
pub const Node = struct {
    ty: Type,
    span: Span,
    data: union(enum) {
        integer: i128,
        boolean: bool,
        block_value: struct { body: StatementId, value: NodeId },
        local: LocalId,
        read_ref: ReferenceId,
        read_field: FieldAccess,
        take_field: FieldAccess,
        propagate: struct { value: NodeId, output: Type, cleanup: []const ReferenceId },
        read_slice: struct { reference: ReferenceId, index: NodeId },
        len_slice: ReferenceId,
        buffer_operation: struct { reference: ?ReferenceId = null, kind: @import("buffer_operations.zig").Kind, owner: LocalId, arguments: []const NodeId },
        pool_operation: struct { reference: ?ReferenceId = null, kind: @import("pool_operations.zig").Kind, owner: LocalId, arguments: []const NodeId },
        acquire_resource: struct { capability: NodeId, request: NodeId },
        complete_resource: NodeId,
        resource_io: struct { reference: ?ReferenceId = null, kind: external_resources.IoKind, owner: LocalId, value: ?NodeId },
        restrict_resource: struct { permissions: external_resources.Permissions, value: NodeId },
        environment_get: struct { capability: NodeId, name: NodeId },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, capability: NodeId },
        acquire_pool: Acquisition,
        acquire_buffer: Acquisition,
        json_codec: struct { document: bool = false, decode: bool, arguments: [3]NodeId },
        reset_arena: NodeId,
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
        call: struct { function: FunctionId, arguments: []const NodeId, references: []const ReferenceId = &.{}, literals: []const LiteralArgument = &.{} },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
/// Resolved aggregate field index and the expression supplying its value.
pub const FieldInit = struct { index: usize, value: NodeId };
/// Named aggregate field with its declaration location and resolved type.
pub const Field = struct { name: []const u8, declaration: Span, ty: Type };
/// Named closed variant case and its optional resolved payload type.
pub const Variant = struct { name: []const u8, declaration: Span, payload: ?Type };
/// Closed case set distinguishing enums, unions, and fallible results.
pub const Variants = struct { fallible: bool = false, is_union: bool, cases: []const Variant };
/// Fixed element count and type, with an optional enum key for tables.
pub const Array = struct { element: Type, length: usize, key: ?Type = null };
// Aggregate schemas retain nominal record identities and intern structural arrays.
/// Resolved pool element type and its nominal handle type.
pub const Pool = values.PoolSchema;
/// Declared domain wire type and resolved decoder/encoder function identities.
pub const Codec = struct { wire: Type, decode: FunctionId, encode: FunctionId };
/// Nominal aggregate schema and associated array, domain, pool, or variant metadata.
pub const Record = struct {
    id: Type,
    name: []const u8,
    declaration: Span,
    fields: []const Field,
    shape: RecordShape = .{},
    contract: RecordContract = .{},
    /// Return the enum key type for a table, or null for other aggregates.
    pub fn tableKey(self: Record) ?Type {
        return if (self.shape.array) |a| a.key else null;
    }
    /// Identify a plain record rather than a specialized aggregate schema.
    pub fn isRecord(self: Record) bool {
        return !self.shape.hasRuntimeIdentity() and !self.shape.hasValueRepresentation();
    }
    /// Identify a payload-free enum schema.
    pub fn isEnum(self: Record) bool {
        return if (self.shape.variants) |v| !v.is_union else false;
    }
    /// Return the number of statically addressable aggregate elements.
    pub fn count(self: Record) usize {
        return if (self.shape.array) |a| a.length else if (self.shape.domain != null) 1 else self.fields.len;
    }
    /// Resolve a field or array element type by its checked index.
    pub fn elementType(self: Record, index: usize) Type {
        return if (self.shape.array) |a| a.element else self.shape.domain orelse self.fields[index].ty;
    }
};
/// Optional specialized representations; bytecode validation rejects incompatible combinations.
pub const RecordShape = struct {
    array: ?Array = null,
    domain: ?Type = null,
    variants: ?Variants = null,
    pool: ?Pool = null,
    handle_pool: ?Type = null,
    buffer: ?Type = null,
    resource: ?external_resources.Kind = null,
    /// Identify representations carrying a buffer, resource, pool, or handle identity.
    pub fn hasRuntimeIdentity(self: RecordShape) bool {
        return self.pool != null or self.handle_pool != null or self.buffer != null or self.resource != null;
    }
    fn hasValueRepresentation(self: RecordShape) bool {
        return self.array != null or self.domain != null or self.variants != null;
    }
};
/// Checked obligations, type-argument visibility and an optional explicit domain wire contract.
pub const RecordContract = struct { public_arguments: bool = true, codec: ?Codec = null, codec_declared: bool = false, move_only: bool = false, requires_handling: bool = false };
/// Payload types and case tags of a checked ok/err result schema.
pub const ResultShape = struct { ok_type: Type, error_type: Type, ok_tag: usize, error_tag: usize };
/// Recognize a valid fallible result and return its payload types and tags.
pub fn resultShape(ty: Type, records: []const Record) ?ResultShape {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const variants = records[ty.recordIndex()].shape.variants orelse return null;
    if (!variants.fallible or !variants.is_union) return null;
    if (variants.cases.len != 2) return null;
    var ok: ?usize = null;
    var err: ?usize = null;
    for (variants.cases, 0..) |case, tag| {
        if (case.payload == null) return null;
        if (std.mem.eql(u8, case.name, "ok")) ok = tag;
        if (std.mem.eql(u8, case.name, "err")) err = tag;
    }
    return .{ .ok_type = variants.cases[ok orelse return null].payload.?, .error_type = variants.cases[err orelse return null].payload.?, .ok_tag = ok.?, .error_tag = err.? };
}
/// Element type for numeric fixed-array and owned-buffer views; enum tables are not slices.
pub fn sliceElement(ty: Type, records: []const Record) ?Type {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const shape = records[ty.recordIndex()].shape;
    if (shape.buffer) |element| return element;
    if (shape.array) |array| if (array.key == null) return array.element;
    return null;
}
/// Resolve a buffer/pool acquisition result with the required i64 error payload.
pub fn acquisitionShape(ty: Type, records: []const Record, pool: bool) ?ResultShape {
    const result = resultShape(ty, records) orelse return null;
    if (!result.ok_type.isAggregate() or result.error_type != .i64) return null;
    const schema = records[result.ok_type.recordIndex()];
    if (if (pool) schema.shape.pool == null else schema.shape.buffer == null) return null;
    return result;
}
/// Equality supported by concrete expressions and generic equality requirements.
pub fn supportsEquality(ty: Type, records: []const Record) bool {
    if (ty.isInteger() or ty == .bool) return true;
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    return record.isEnum() or record.shape.handle_pool != null or record.shape.domain != null;
}
/// Determine whether a type carries ownership that forbids implicit copying.
pub fn moveOnly(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].contract.move_only;
}
/// Determine whether a value contains an unacknowledged fallible result obligation.
pub fn requiresHandling(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].contract.requires_handling;
}
/// Return the scalar spelling or borrowed nominal schema name of a type.
pub fn typeName(ty: Type, records: []const Record) []const u8 {
    return if (ty.isAggregate()) records[ty.recordIndex()].name else @tagName(ty);
}
/// Resolved local assignment target and the expression being stored.
pub const Store = struct { slot: LocalId, value: NodeId };
/// Checked control flow, ownership operations, and expression statements.
pub const Statement = struct {
    span: Span,
    terminates: bool,
    owned_cleanup: []const LocalId = &.{},
    cleanup: []const ReferenceId = &.{},
    data: union(enum) {
        arena_scope: struct { parent: NodeId, slot: LocalId, body: StatementId },
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
        loop: struct { id: usize = 0, condition: NodeId, body: StatementId, step: ?StatementId = null },
        loop_exit: struct { target: usize, continuing: bool, regions: []const LocalId },
        initialize: Store,
        assign: Store,
    },
};
/// Resolved case tag, optional payload local, and checked arm body.
pub const MatchArm = struct { tag: usize, slot: ?LocalId, body: StatementId };
/// Checked expressions supplying the start and end of a slice.
pub const Range = struct { start: NodeId, end: NodeId };
/// A byte literal materialized and borrowed only for the duration of one call.
pub const LiteralArgument = struct { value: NodeId, owner: LocalId, reference: ReferenceId, length: usize };
/// Local type, declaration, usage counts, and tracked ownership/borrow state.
pub const Local = struct {
    ownership: LocalOwnership = .{},
    parameter: LocalParameter = .{},
    usage: LocalUsage = .{},
    name: []const u8,
    declaration: Span,
    ty: Type,
    mutable: bool,
};
/// Compile-time ownership availability, partial moves, and arena provenance.
pub const LocalOwnership = struct { transfer_span: ?Span = null, arena_depth: usize = 0, partial_fields: []const ?Span = &.{}, transfer_available: bool = false };
/// Passing convention for a reference or slice parameter binding.
pub const LocalParameter = struct { slice_parameter: bool = false, reference_parameter: ?bool = null };
/// Static binding reads, writes, and mutability evidence used by quality diagnostics.
pub const LocalUsage = struct { temporary: bool = false, mutable_borrow: bool = false, reads: usize = 0, writes: usize = 0 };

/// Caller parameter provenance and mutability of a returned reference or slice.
pub const ReturnReference = struct { parameter: LocalId, mutable: bool, slice: bool };
/// Checked function signature, local/reference metadata, effects, and body identity.
pub const Function = struct {
    policy: FunctionPolicy = .{},
    /// Concrete specialization arguments; empty for an ordinary source function.
    type_arguments: []const Type = &.{},
    signature: FunctionSignature = .{},
    scope: FunctionScope,
    id: FunctionId,
    name: []const u8,
    declaration: Span,
};
/// Declared visibility and effect policy, with its inferred execution effects.
pub const FunctionPolicy = struct {
    host: ?Span = null,
    effect_bound: ?@import("effect_set.zig").Bound = null,
    effects: @import("effect_set.zig").Mask = 0,
    owner: ?Type = null,
    restricted: bool = false,
    conversion: bool = false,
};
/// Resolved value result, parameter count, and optional returned-reference contract.
pub const FunctionSignature = struct {
    return_type: Type = .i64,
    parameter_count: usize = 0,
    return_reference: ?ReturnReference = null,
};
/// Checked function body and its lexical local/reference tables.
pub const FunctionScope = struct {
    body: StatementId,
    locals: []const Local = &.{},
    references: []const Reference = &.{},
};
/// Borrowed checked expression, statement, function, and nominal schema tables.
pub const Program = struct { nodes: []const Node, statements: []const Statement, functions: []const Function, main: FunctionId, records: []const Record = &.{} };

/// Identify the external provider family associated with a type.
pub fn resourceKind(ty: Type, records: []const Record) ?external_resources.Kind {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    return records[ty.recordIndex()].shape.resource;
}
/// Check whether a type has the byte-array representation required by provider requests.
pub fn byteRequest(ty: Type, records: []const Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const array = records[ty.recordIndex()].shape.array orelse return false;
    return array.element == .u8 and array.key == null;
}
/// Result schema and fields needed to preserve a resource on failed completion.
pub const CompletionShape = struct { result: ResultShape, resource_type: Type, resource_field: usize, code_field: usize };
/// Recognize the resource-preserving completion result layout.
pub fn completionShape(ty: Type, records: []const Record) ?CompletionShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.ok_type != .bool or !result.error_type.isAggregate() or result.error_type.recordIndex() >= records.len) return null;
    const schema = records[result.error_type.recordIndex()];
    const slots = providerFields(schema, records, .completion) orelse return null;
    return .{ .result = result, .resource_type = schema.fields[slots[0]].ty, .resource_field = slots[0], .code_field = slots[1] };
}

/// Result payload layout containing bytes, a length, and a status flag.
pub const ByteResultShape = struct { result: ResultShape, bytes_type: Type, bytes_field: usize, length_field: usize, flag_field: usize };
/// Recognize the required environment lookup result layout.
pub fn environmentShape(ty: Type, records: []const Record) ?ByteResultShape {
    return byteResultShape(ty, records, .environment);
}
/// Recognize the required fixed-buffer resource read result layout.
pub fn resourceReadShape(ty: Type, records: []const Record) ?ByteResultShape {
    return byteResultShape(ty, records, .read);
}
fn byteResultShape(ty: Type, records: []const Record, operation: provider_contracts.Operation) ?ByteResultShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.error_type != .i64 or !result.ok_type.isAggregate() or result.ok_type.recordIndex() >= records.len) return null;
    const schema = records[result.ok_type.recordIndex()];
    const slots = providerFields(schema, records, operation) orelse return null;
    return .{ .result = result, .bytes_type = schema.fields[slots[0]].ty, .bytes_field = slots[0], .length_field = slots[1], .flag_field = slots[2] };
}

/// Result fields describing the count and EOF state of a read into a slice.
pub const SliceReadShape = struct { result: ResultShape, length_field: usize, eof_field: usize };
/// Recognize the result layout for a resource read into caller-owned storage.
pub fn resourceSliceReadShape(ty: Type, records: []const Record) ?SliceReadShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.error_type != .i64 or !result.ok_type.isAggregate() or result.ok_type.recordIndex() >= records.len) return null;
    const slots = providerFields(records[result.ok_type.recordIndex()], records, .slice_read) orelse return null;
    return .{ .result = result, .length_field = slots[0], .eof_field = slots[1] };
}

fn providerFields(schema: Record, records: []const Record, operation: provider_contracts.Operation) ?[3]usize {
    const required = provider_contracts.fields(operation);
    if (!schema.isRecord() or schema.fields.len != required.len) return null;
    var slots: [3]usize = @splat(0);
    for (required, 0..) |rule, slot| {
        var found = false;
        for (schema.fields, 0..) |field, index| {
            if (!std.mem.eql(u8, field.name, rule.name)) continue;
            const matches = switch (rule.requirement) {
                .i64 => field.ty == .i64,
                .u64 => field.ty == .u64,
                .boolean => field.ty == .bool,
                .bytes => byteRequest(field.ty, records),
                .resource => resourceKind(field.ty, records) != null,
            };
            if (!matches) return null;
            slots[slot] = index;
            found = true;
        }
        if (!found) return null;
    }
    return slots;
}
