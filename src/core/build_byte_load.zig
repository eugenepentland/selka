//! Fixed-width reads of bytes (`bytes.read_u32_be` and its siblings): one bounds check for the whole width,
//! then one load of the result type. The octets are read through a borrowed view, so an owned value, a
//! plain `bytes` parameter (a view) and a slice all read relative to their own first octet.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("selka").typed;
const build_borrowed_view = @import("build_borrowed_view.zig");
const text_checks = @import("text_checks.zig");

/// Allocation and unsupported-shape failures of the builder.
pub const Error = error{ OutOfMemory, Unsupported };

/// The octet count of one fixed-width read result.
pub fn width(ty: ir.Type) ?u64 {
    return switch (ty) {
        .u8, .i8 => 1,
        .u16, .i16 => 2,
        .u32, .i32, .f32 => 4,
        .u64, .i64, .f64 => 8,
        else => null,
    };
}

/// Read the `ty`-typed value at `offset` of the octets `source` names, with one unsigned compare
/// `offset <= length - width` that also covers `length >= width` and a negative offset (it is huge as
/// unsigned). The located trap is the one bytes indexing reports (`R_LIST_BOUNDS`).
pub fn read(comptime Context: type, context: Context, source: ir.Ref, offset_ref: ir.Ref, ty: ir.Type, big_endian: bool, span: u32) Error!ir.Ref {
    const size = width(ty) orelse return error.Unsupported;
    const view = try build_borrowed_view.whole(Context, context, source, span);
    const length = try context.emit(.{ .op = .list_len, .ty = .u64, .a = view, .span = span });
    const offset_type = context.typeOfRef(offset_ref);
    const signed = if (offset_type == .i64) offset_ref else try context.emit(.{ .op = .convert, .ty = .i64, .a = offset_ref, .span = span });
    const unsigned = try context.emit(.{ .op = .convert, .ty = .u64, .a = signed, .span = span });
    const need = try context.constant(.u64, @intCast(size));
    const fits = try context.emit(.{ .op = .cmp, .ty = .bool, .a = length, .b = need, .data = @backingInt(ir.Predicate.ge), .span = span });
    const limit = try context.emit(.{ .op = .sub, .ty = .u64, .a = length, .b = need, .span = span });
    const below = try context.emit(.{ .op = .cmp, .ty = .bool, .a = unsigned, .b = limit, .data = @backingInt(ir.Predicate.le), .span = span });
    const in_bounds = try context.emit(.{ .op = .bit_and, .ty = .bool, .a = fits, .b = below, .span = span });
    // Kind 2 is the runtime's `TRAP_LIST_BOUNDS`: the code a bytes index reports (`R_LIST_BOUNDS`, index and length).
    try text_checks.requireLocated(Context, context, in_bounds, 2, span, signed, try context.emit(.{ .op = .convert, .ty = .i64, .a = length, .span = span }));
    return context.emit(.{ .op = .byte_load, .ty = ty, .a = view, .b = unsigned, .data = @intFromBool(big_endian), .span = span });
}
