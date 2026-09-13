//! Checked instruction model independent of validation and effect inference.
const external_resources = @import("external_resources.zig");
const std = @import("std");
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
        push_unit,
        push_integer: struct { ty: typed.Type, value: i128 },
        cast_integer: typed.Type,
        wrap_domain: typed.Type,
        make_variant: struct { ty: typed.Type, tag: usize },
        switch_variant: struct { ty: typed.Type, arms: []const SwitchArm },
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
        begin_arena: typed.LocalId,
        end_arena: typed.LocalId,
        arena_escape: typed.Type,
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: typed.LocalId, output: typed.Type },
        complete_resource: typed.Type,
        acquire_resource: struct { output: typed.Type, request: typed.Type },
        resource_io: struct { kind: external_resources.IoKind, owner: typed.LocalId, output: typed.Type, input: ?typed.Type },
        restrict_resource: struct { permissions: external_resources.Permissions, ty: typed.Type },
        environment_get: struct { output: typed.Type, name: typed.Type },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, output: typed.Type },
        acquire_buffer: typed.Type,
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
        unary_float: typed.UnaryOp,
        cmp_i64: Predicate,
        cmp_bool: Equality,
        not_bool,
        assert_true: []const u8,
        pop,
        acknowledge: typed.Type,
        jump: usize,
        jump_if_false: usize,
        function_value: struct { ty: typed.Type, function: typed.FunctionId },
        invoke: typed.Type,
        call: typed.FunctionId,
        ret,
    },
};
/// Checked function signature, locals, and instruction body.
pub const Function = struct {
    policy: typed.FunctionPolicy = .{},
    signature: typed.FunctionSignature = .{},
    scope: FunctionScope,
    id: typed.FunctionId,
    name: []const u8,
};
/// Lowered instructions and the checked lexical local table they address.
pub const FunctionScope = struct {
    locals: []const typed.Local = &.{},
    instructions: []const Instruction,
};
/// Complete instruction program and its nominal type metadata.
pub const Program = struct { functions: []const Function, main: typed.FunctionId = @fromBackingInt(0), records: []const typed.Record = &.{} };
/// Count stack-passed value arguments.
pub fn valueParameterCount(function: Function) usize {
    return function.signature.parameter_count;
}
