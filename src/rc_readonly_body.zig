//! Whole-activation loans for scalar-result bodies with no escaping effects.
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const native = @import("native_types.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// Prove that every managed bit remains anchored by the read-only caller inputs.
/// This linear closed grammar permits self recursion, but no other calls,
/// allocation, mutation, unique resource, arena, callback or owning result.
pub fn certify(catalog: *shapes.Catalog, function: bytecode.Function) native.Error!bool {
    if (function.policy.c_abi or function.policy.host != null) return false;
    if (function.signature.mutates.len != 0 or function.signature.declared_mutates.len != 0) return false;
    const output = try catalog.get(function.signature.return_type);
    if (output.counted or output.unique_drop) return false;
    for (function.scope.locals) |local| if ((try catalog.get(local.ty)).unique_drop) return false;
    if (function.scope.instructions.len == 0) return false;
    for (function.scope.instructions) |instruction| if (!allowed(catalog, function, instruction.op)) return false;
    return true;
}

fn allowed(catalog: *shapes.Catalog, function: bytecode.Function, op: Op) bool {
    return switch (op) {
        .load_local,
        .move_local,
        .drop_local,
        .value_copy,
        .pop,
        .acknowledge,
        .push_i64,
        .push_integer,
        .push_bool,
        .push_unit,
        .get_field,
        .switch_variant,
        .wrap_domain,
        .unwrap_domain,
        .array_length,
        .cmp_i64,
        .cmp_bool,
        .cmp_enum,
        .not_bool,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        .unary_float,
        .jump,
        .jump_if_false,
        .assert_true,
        .ret,
        => true,
        .store_local => |id| @backingInt(id) >= function.signature.parameter_count,
        .call => |id| id == function.id,
        .cast_integer, .neg_integer => |ty| ty.integer() != null,
        .binary_integer => |operation| operation.ty.integer() != null,
        .make_record => |record| !catalog.native.records[record.ty.recordIndex()].managed,
        .make_variant => true,
        .get_index => |access| !catalog.native.records[access.ty.recordIndex()].managed,
        .buffer_operation => |operation| readList(catalog, function, operation),
        else => false,
    };
}

fn readList(catalog: *shapes.Catalog, function: bytecode.Function, operation: @FieldType(Op, "buffer_operation")) bool {
    if (operation.kind != .read) return false;
    const ty = function.scope.locals[@backingInt(operation.owner)].ty;
    const record = catalog.native.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .list;
}
