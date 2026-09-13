//! Checked nodes use declaration identities, concrete types, and local slots.
const effect_set = @import("effect_set.zig");
const std = @import("std");
const provider_contracts = @import("provider_contracts.zig");
const external_resources = @import("external_resources.zig");
const values = @import("value.zig");
const Span = @import("source.zig").Span;
/// Index of a checked expression in Program.nodes.
pub const NodeId = enum(usize) { _ };
/// Index of a checked statement in Program.statements.
pub const StatementId = enum(usize) { _ };
/// Index of a resolved function in Program.functions.
pub const FunctionId = enum(usize) { _ };
/// Index of a function-local value slot.
pub const LocalId = enum(usize) { _ };
pub const Type = values.Type;
pub const Value = values.Value;
/// Checked arithmetic, logical, and comparison operation categories.
pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    rem,
    floor_div,
    floor_rem,
    logical_and,
    logical_or,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    bit_and,
    bit_or,
    bit_xor,
    shift_left,
    shift_right,
    wrapping_add,
    wrapping_sub,
    wrapping_mul,
    saturating_add,
    saturating_sub,
    saturating_mul,
    f64_add,
    f64_sub,
    f64_mul,
    f64_div,
    f64_eq,
    f64_lt,
    f64_le,
};
/// Checked numeric negation and Boolean inversion operations.
pub const UnaryOp = enum { neg, not, f64_sqrt, f64_floor, f64_ceil, f64_trunc, f64_abs, f64_neg, f64_from_u64, f64_to_u64, f64_from_i64, f64_to_i64 };
/// Typed expression with resolved operands and source location.
pub const Node = struct {
    ty: Type,
    span: Span,
    data: union(enum) {
        integer: i128,
        boolean: bool,
        unit,
        block_value: struct { body: StatementId, value: NodeId },
        function_value: FunctionId,
        invoke: struct { callee: NodeId, arguments: []const NodeId },
        local: LocalId,
        propagate: struct { value: NodeId, output: Type },
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: LocalId, arguments: []const NodeId },
        acquire_resource: struct { capability: NodeId, request: NodeId },
        complete_resource: NodeId,
        resource_io: struct { kind: external_resources.IoKind, owner: LocalId, value: ?NodeId },
        restrict_resource: struct { permissions: external_resources.Permissions, value: NodeId },
        environment_get: struct { capability: NodeId, name: NodeId },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, capability: NodeId },
        acquire_buffer: struct { capacity: NodeId },
        arena_escape: NodeId,
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
        call: struct { evaluation: ?struct { body: StatementId, cleanup: []const LocalId } = null, function: FunctionId, arguments: []const NodeId },
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
/// Declared domain wire type and resolved decoder/encoder function identities.
pub const Codec = struct { wire: Type, decode: FunctionId, encode: FunctionId };
/// Nominal aggregate schema and associated array, domain, collection, or variant metadata.
pub const Record = struct {
    collection: @import("runtime_values.zig").CollectionShape = .{},
    managed: bool = false,
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
    buffer: ?Type = null,
    resource: ?external_resources.Kind = null,
    /// Identify representations carrying a managed collection or resource identity.
    pub fn hasRuntimeIdentity(self: RecordShape) bool {
        return self.buffer != null or self.resource != null;
    }
    fn hasValueRepresentation(self: RecordShape) bool {
        return self.array != null or self.domain != null or self.variants != null;
    }
};
/// Checked obligations, type-argument visibility and an optional explicit domain wire contract.
/// Exact value parameter/result types and declared callback effect ceiling.
pub const Callable = struct {
    parameters: []const Type,
    return_type: Type,
    effects: effect_set.Mask,
    /// Every callback parameter is an ordinary operand-stack value.
    pub fn valueCount(self: Callable) usize {
        return self.parameters.len;
    }
};
/// Ownership and public schema policy for each concrete type.
pub const RecordContract = struct { callback: ?Callable = null, public_arguments: bool = true, codec: ?Codec = null, codec_declared: bool = false, move_only: bool = false, storable: bool = true, requires_handling: bool = false };
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
/// Equality supported by concrete expressions and generic equality requirements.
pub fn supportsEquality(ty: Type, records: []const Record) bool {
    if (ty.isInteger() or ty == .bool) return true;
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    if (record.contract.callback != null) return false;
    return record.isEnum() or record.shape.domain != null;
}
/// Determine whether a type carries ownership that forbids implicit copying.
pub fn moveOnly(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].contract.move_only;
}
/// Values whose destruction requires neither result handling nor external provider effects.
pub fn storable(ty: Type, records: []const Record) bool {
    return !ty.isAggregate() or records[ty.recordIndex()].contract.storable;
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
    data: union(enum) {
        managed_arena: struct { watermark: LocalId, body: StatementId },
        block: []const StatementId,
        ret: NodeId,
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { id: usize = 0, condition: NodeId, body: StatementId, step: ?StatementId = null },
        loop_exit: struct { target: usize, continuing: bool, arenas: []const LocalId = &.{} },
        initialize: Store,
        assign: Store,
    },
};
/// Resolved case tag, optional payload local, and checked arm body.
pub const MatchArm = struct { tag: usize, slot: ?LocalId, body: StatementId };
/// Local type, declaration, usage counts, and tracked ownership/borrow state.
pub const Local = struct {
    ownership: LocalOwnership = .{},
    usage: LocalUsage = .{},
    name: []const u8,
    declaration: Span,
    ty: Type,
    mutable: bool,
};
/// Compile-time ownership availability and managed arena provenance.
pub const LocalOwnership = struct { transfer_span: ?Span = null, arena_depth: usize = 0, transfer_available: bool = false };
/// Static binding reads and writes used by quality diagnostics.
pub const LocalUsage = struct { temporary: bool = false, reads: usize = 0, writes: usize = 0 };

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
    c_abi: bool = false,
    host: ?Span = null,
    effect_bound: ?effect_set.Bound = null,
    effects: effect_set.Mask = 0,
    owner: ?Type = null,
    restricted: bool = false,
    conversion: bool = false,
};
/// Resolved value result and parameter count of a checked function.
pub const FunctionSignature = struct {
    constant_arguments: []const ?usize = &.{},
    return_type: Type = .i64,
    parameter_count: usize = 0,
};
/// Checked function body and its lexical local table.
pub const FunctionScope = struct {
    body: StatementId,
    locals: []const Local = &.{},
};
/// Borrowed checked expression, statement, function, and nominal schema tables.
/// Checked transparent name and its canonical target, retained for public interfaces.
pub const TypeAlias = struct { name: []const u8, target: Type, declaration: Span };
/// Checked semantic graph with arena-owned type and alias identities.
pub const Program = struct { aliases: []const TypeAlias = &.{}, nodes: []const Node, statements: []const Statement, functions: []const Function, main: FunctionId, records: []const Record = &.{} };

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
/// Acquisition accepts an ordinary fixed byte array without an enum key.
pub fn acquisitionBytes(ty: Type, records: []const Record) bool {
    return byteRequest(ty, records);
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
