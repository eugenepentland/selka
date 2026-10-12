//! Eager two-input selection without manufacturing an owning alias.
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
const selections = @import("borrow_selection.zig");

/// Validate generated choices against the live logical catalog before reading inputs.
pub fn valid(program: typed.Program, selection: typed.BorrowSelection, result: typed.Type) bool {
    const first_id = @backingInt(selection.first);
    const second_id = @backingInt(selection.second);
    if (first_id >= program.nodes.len or second_id >= program.nodes.len) return false;
    if (result.isAggregate() and result.recordIndex() >= program.records.len) return false;
    const first = program.nodes[first_id].ty;
    if (program.nodes[second_id].ty != result or !first.isAggregate() or first.recordIndex() >= program.records.len) return false;
    if (selection.kind != .optional_default)
        return first == result and program.records[first.recordIndex()].collection.kind == .string;
    const shape = @import("mylang").reference_tables.prelude.optionShape(first, program.records) orelse return false;
    return shape.element == result and !typed.moveOnly(first, program.records) and !typed.requiresHandling(first, program.records);
}

/// Allocation or an unsupported representation stops this stage.
pub const Error = error{ OutOfMemory, Unsupported };

/// Evaluate inputs once, then preserve their borrowed choice through the join.
pub fn lower(comptime Context: type, b: Context, selection: typed.BorrowSelection, logical: typed.Type, ty: ir.Type, span: u32) Error!ir.Ref {
    if (!valid(b.mb.input.program, selection, logical)) return b.mb.refuse("borrowed selection logical contract", span);
    const first = try b.expression(selection.first);
    if (b.current == null) return .none;
    const second = try b.expression(selection.second);
    if (b.current == null) return .none;
    if (first == .none or second == .none or b.typeOfRef(second) != ty)
        return b.mb.refuse("borrowed selection operand types", span);
    const kind: selections.Kind = switch (selection.kind) {
        .min_text => .min_text,
        .max_text => .max_text,
        .optional_default => .optional_default,
    };
    const selected_input = try conditionOf(Context, b, selection.kind, first, second, ty, span);
    const result = try b.synthetic(ty);
    const chosen_first = try b.newBlock();
    const chosen_second = try b.newBlock();
    const join = try b.newBlock();
    try b.branch(selected_input.condition, chosen_first, chosen_second, span);
    try b.seal(chosen_first);
    b.enter(chosen_first);
    var value = first;
    if (selected_input.some) |tag| {
        const payload_ty = b.module().compound(b.typeOfRef(first)).@"union"[tag];
        value = try b.emit(.{ .op = .union_payload, .ty = payload_ty, .a = first, .data = tag, .span = span });
        if (b.module().kind(payload_ty) == .box)
            value = try b.emit(.{ .op = .box_get, .ty = ty, .a = value, .span = span });
    }
    try b.write(result, b.current.?, value);
    try b.jump(join);
    try b.seal(chosen_second);
    b.enter(chosen_second);
    try b.write(result, b.current.?, second);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    const selected = try b.read(result, join);
    return if (b.module().zero_rc and b.module().managed(ty)) b.borrowChoice(kind, selected, first, second, span) else selected;
}

const InputSelection = struct { condition: ir.Ref, some: ?usize = null };

fn conditionOf(comptime Context: type, b: Context, kind: @FieldType(typed.BorrowSelection, "kind"), first: ir.Ref, second: ir.Ref, ty: ir.Type, span: u32) Error!InputSelection {
    if (kind == .optional_default) return optionalCondition(Context, b, first, ty, span);
    if (b.typeOfRef(first) != .str or ty != .str)
        return b.mb.refuse("borrowed text selection types", span);
    const order = try b.runtimeCall("myl_core_octets_compare", &.{ .str, .str }, .i64, &.{ first, second }, span);
    const predicate: ir.Predicate = if (kind == .min_text) .le else .ge;
    return .{ .condition = try b.emit(.{ .op = .cmp, .ty = .bool, .a = order, .b = try b.constant(.i64, 0), .data = @backingInt(predicate), .span = span }) };
}

fn optionalCondition(comptime Context: type, b: Context, first: ir.Ref, ty: ir.Type, span: u32) Error!InputSelection {
    const first_ty = b.typeOfRef(first);
    if (b.module().kind(first_ty) != .@"union") return b.mb.refuse("borrowed optional selection type", span);
    const cases = b.module().compound(first_ty).@"union";
    if (cases.len != 2) return b.mb.refuse("borrowed optional selection cases", span);
    var some: ?usize = null;
    for (cases, 0..) |case, index| if (case != .void) {
        if (some != null) return b.mb.refuse("borrowed optional selection payload", span);
        const value_ty = if (b.module().kind(case) == .box) b.module().compound(case).box else case;
        if (value_ty != ty) return b.mb.refuse("borrowed optional selection payload type", span);
        some = index;
    };
    const tag = some orelse return b.mb.refuse("borrowed optional selection empty payload", span);
    const actual = try b.emit(.{ .op = .union_tag, .ty = .u32, .a = first, .span = span });
    return .{
        .condition = try b.emit(.{ .op = .cmp, .ty = .bool, .a = actual, .b = try b.constant(.u32, tag), .data = @backingInt(ir.Predicate.eq), .span = span }),
        .some = tag,
    };
}
