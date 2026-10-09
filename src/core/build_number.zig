//! Number conversions keep the integer fast path and use the exact ported Zig runtime.
const ir = @import("ir.zig");
const typed = @import("selka").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");

/// Allocation and precise feature refusals are the number builder's failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Lower checked format and parse operations, with no assumptions about finite parsed floats.
pub fn operation(comptime Context: type, context: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    if (node.kind == .number_format) {
        const value = try context.expression(node.arguments[0]);
        const spec = try widen(Context, context, try context.expression(node.arguments[1]), .u64, span);
        if (context.typeOfRef(value) == .f64) return context.runtimeCall("myl_core_format_float", &.{ .f64, .u64 }, .str, &.{ value, spec }, span);
        // The C ABI carries either signed or unsigned i64 as the same 64 bits.
        // Preserve signed interpretation in IR rather than inventing a numeric cast.
        const width: ir.Type = if (context.typeOfRef(value).integer().?.signed) .i64 else .u64;
        const bits = try widen(Context, context, value, width, span);
        return context.runtimeCall("myl_core_format_number", &.{ width, .u64 }, .str, &.{ bits, spec }, span);
    }
    if (node.kind != .parse_int and node.kind != .parse_int_range and node.kind != .parse_float and node.kind != .parse_float_range) return context.mb.refuse(@tagName(node.kind), span);
    const receiver = try context.receiverOf(node.owner);
    const receiver_type = context.typeOfRef(receiver);
    if (node.kind == .parse_int and receiver_type == .str) return context.emit(.{ .op = .str_parse_int, .ty = ty, .a = receiver, .span = span });
    const ranged = node.kind == .parse_int_range or node.kind == .parse_float_range;
    const start = if (ranged) try context.expression(node.arguments[0]) else try context.constant(.i64, 0);
    const end = if (ranged) try context.expression(node.arguments[1]) else try context.emit(.{ .op = if (receiver_type == .str) .str_len else .list_len, .ty = .u64, .a = receiver, .span = span });
    const last = try widen(Context, context, end, .i64, span);
    const floating = node.kind == .parse_float or node.kind == .parse_float_range;
    // SysV scalar Option returns use the integer tag register and one payload register.
    // Returning the checked union directly keeps grammar operations allocation-free.
    return context.runtimeCall(if (floating) "myl_core_parse_float_range" else "myl_core_parse_int_range", &.{ receiver_type, .i64, .i64 }, ty, &.{ receiver, start, last }, span);
}

fn widen(comptime Context: type, context: Context, ref: ir.Ref, target: ir.Type, span: u32) Error!ir.Ref {
    return if (context.typeOfRef(ref) == target) ref else context.emit(.{ .op = .convert, .ty = target, .a = ref, .span = span });
}
