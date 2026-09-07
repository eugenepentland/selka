//! Checked instruction model independent of validation and effect inference.
const external_resources = @import("external_resources.zig");
const std = @import("std");
const FieldAccess = struct { reference: ?typed.ReferenceId = null, owner: typed.LocalId, field: usize, output: typed.Type };
const Span = @import("source.zig").Span;
const typed = @import("typed.zig");
/// Signed scalar ordering and equality predicates.
pub const Predicate = enum { eq, ne, lt, le, gt, ge };
/// Equality predicates for boolean and nominal identity values.
pub const Equality = enum { eq, ne };
/// Destination and optional payload local for one variant case.
pub const SwitchArm = struct { target: usize, slot: ?typed.LocalId };
/// Source-located operation in the checked instruction stream.
pub const Instruction = struct {
    span: Span,
    op: union(enum) {
        try_result: struct { input: typed.Type, output: typed.Type, error_target: usize },
        push_i64: i64,
        push_bool: bool,
        push_integer: struct { ty: typed.Type, value: i128 },
        cast_integer: typed.Type,
        wrap_domain: typed.Type,
        make_variant: struct { ty: typed.Type, tag: usize },
        switch_variant: struct { ty: typed.Type, arms: []const SwitchArm },
        cmp_handle: struct { ty: typed.Type, predicate: Equality },
        cmp_domain: struct { ty: typed.Type, predicate: Equality },
        cmp_enum: struct { ty: typed.Type, predicate: Equality },
        unwrap_domain: typed.Type,
        neg_integer: typed.Type,
        binary_integer: struct { ty: typed.Type, op: typed.BinaryOp },
        make_record: struct { ty: typed.Type, fields: usize, order: []const usize = &.{} },
        update_record: struct { ty: typed.Type, indices: []const usize },
        get_field: usize,
        get_index: typed.Type,
        replace_index: typed.Type,
        array_length: typed.Type,
        reset_arena: typed.Type,
        begin_region: typed.LocalId,
        end_region: typed.LocalId,
        begin_borrow: typed.ReferenceId,
        begin_slice: typed.ReferenceId,
        read_slice: typed.ReferenceId,
        write_slice: typed.ReferenceId,
        len_slice: typed.ReferenceId,
        end_borrow: typed.ReferenceId,
        read_ref: typed.ReferenceId,
        read_field: FieldAccess,
        take_field: FieldAccess,
        write_ref: typed.ReferenceId,
        buffer_operation: struct { reference: ?typed.ReferenceId = null, kind: @import("buffer_operations.zig").Kind, owner: typed.LocalId, output: typed.Type },
        pool_operation: struct { reference: ?typed.ReferenceId = null, kind: @import("pool_operations.zig").Kind, owner: typed.LocalId, output: typed.Type },
        complete_resource: typed.Type,
        acquire_resource: struct { output: typed.Type, request: typed.Type },
        resource_io: struct { reference: ?typed.ReferenceId = null, kind: external_resources.IoKind, owner: typed.LocalId, output: typed.Type, input: ?typed.Type },
        restrict_resource: struct { permissions: external_resources.Permissions, ty: typed.Type },
        environment_get: struct { output: typed.Type, name: typed.Type },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, output: typed.Type },
        acquire_pool: typed.Type,
        acquire_buffer: typed.Type,
        json_codec: struct { document: bool = false, decode: bool, input: typed.Type, output: typed.Type },
        move_local: typed.LocalId,
        drop_local: typed.LocalId,
        load_local: typed.LocalId,
        store_local: typed.LocalId,
        add_i64_checked,
        sub_i64_checked,
        mul_i64_checked,
        div_i64_checked,
        rem_i64_checked,
        neg_i64_checked,
        cmp_i64: Predicate,
        cmp_bool: Equality,
        not_bool,
        pop,
        acknowledge: typed.Type,
        jump: usize,
        jump_if_false: usize,
        call: typed.FunctionId,
        call_refs: struct { function: typed.FunctionId, references: []const typed.ReferenceId },
        ret,
        ret_ref,
        capture_ref: typed.ReferenceId,
        call_borrow: struct { function: typed.FunctionId, references: []const typed.ReferenceId, destination: typed.ReferenceId },
    },
};
/// Checked function signature, locals, references, and instruction body.
pub const Function = struct {
    policy: typed.FunctionPolicy = .{},
    signature: typed.FunctionSignature = .{},
    scope: FunctionScope,
    id: typed.FunctionId,
    name: []const u8,
};
/// Lowered instructions and the checked lexical local/reference tables they address.
pub const FunctionScope = struct {
    locals: []const typed.Local = &.{},
    references: []const typed.Reference = &.{},
    instructions: []const Instruction,
};
/// Complete instruction program and its nominal type metadata.
pub const Program = struct { functions: []const Function, main: typed.FunctionId = @fromBackingInt(0), records: []const typed.Record = &.{} };
/// Count stack-passed value arguments, excluding reference parameters.
pub fn valueParameterCount(function: Function) usize {
    var count: usize = 0;
    for (function.scope.locals[0..function.signature.parameter_count]) |local| if (local.parameter.reference_parameter == null) {
        count += 1;
    };
    return count;
}
