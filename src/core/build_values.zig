//! Aggregate composition and per-type structural runtime adapters.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
const build_render = @import("build_render.zig");
/// Allocation or an unsupported representation stops this stage.
pub const Error = error{ OutOfMemory, Unsupported };

/// Build a checked list literal that was retained as one array-shaped node.
pub fn literal(comptime Context: type, b: Context, ty: ir.Type, items: []const typed.NodeId, span: u32) Error!ir.Ref {
    var result = try b.emit(.{ .op = .list_new, .ty = ty, .a = try b.constant(.u64, @intCast(items.len)), .span = span });
    for (items) |item| {
        var value = try b.expression(item);
        if (b.current == null) return .none;
        if (value == .none) value = try b.constant(.bool, 0);
        result = try b.emit(.{ .op = .list_push, .ty = ty, .a = result, .b = value, .span = span });
    }
    return result;
}

/// Append the elements of a borrowed list into a separate value.
pub fn concat(comptime Context: type, b: Context, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(left);
    const first = try b.emit(.{ .op = .list_len, .ty = .u64, .a = left, .span = span });
    const second = try b.emit(.{ .op = .list_len, .ty = .u64, .a = right, .span = span });
    const length = try b.emit(.{ .op = .add, .ty = .u64, .a = first, .b = second, .check = .exact, .span = span });
    const empty = try b.emit(.{ .op = .list_new, .ty = ty, .a = length, .span = span });
    return append(Context, b, try append(Context, b, empty, left, span), right, span);
}

fn append(comptime Context: type, b: Context, initial: ir.Ref, source: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(initial);
    const element = b.module().compound(ty).list;
    const result = try b.synthetic(ty);
    const counter = try b.synthetic(.u64);
    const length = try b.emit(.{ .op = .list_len, .ty = .u64, .a = source, .span = span });
    try b.write(result, b.current.?, initial);
    try b.write(counter, b.current.?, try b.constant(.u64, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const end = try b.newBlock();
    try b.jump(header);
    b.current = header;
    const index = try b.read(counter, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = length, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, end, span);
    try b.seal(body);
    try b.seal(end);
    b.current = body;
    const value = try b.emit(.{ .op = .list_get, .ty = element, .a = source, .b = index, .check = .exact, .span = span });
    const pushed = try b.emit(.{ .op = .list_push, .ty = ty, .a = try b.read(result, body), .b = value, .span = span });
    try b.write(result, b.current.?, pushed);
    try b.write(counter, b.current.?, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    b.enter(end);
    return b.read(result, end);
}

/// List membership uses element equality, including IEEE unordered NaNs.
pub fn contains(comptime Context: type, b: Context, source: ir.Ref, needle: ir.Ref, span: u32) Error!ir.Ref {
    const index = try firstIndex(Context, b, source, needle, span);
    const count = try b.emit(.{ .op = .list_len, .ty = .u64, .a = source, .span = span });
    return b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = count, .data = @backingInt(ir.Predicate.lt), .span = span });
}

/// The first structurally equal element, or the list length when absent.
pub fn firstIndex(comptime Context: type, b: Context, source: ir.Ref, needle: ir.Ref, span: u32) Error!ir.Ref {
    const element = b.module().compound(b.typeOfRef(source)).list;
    const count = try b.emit(.{ .op = .list_len, .ty = .u64, .a = source, .span = span });
    const counter = try b.synthetic(.u64);
    try b.write(counter, b.current.?, try b.constant(.u64, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const next = try b.newBlock();
    const end = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const index = try b.read(counter, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = count, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, end, span);
    try b.seal(body);
    b.enter(body);
    const same = if (needle == .none or element == .void) try b.constant(.bool, 1) else try b.equal(try b.emit(.{ .op = .list_get, .ty = element, .a = source, .b = index, .check = .exact, .span = span }), needle, span);
    try b.branch(same, end, next, span);
    try b.seal(next);
    b.enter(next);
    try b.write(counter, next, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(end);
    b.enter(end);
    return b.read(counter, end);
}

/// Repeat a text, byte string or list with the original operand evaluation order.
pub fn repeat(comptime Context: type, b: Context, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
    const reversed = b.typeOfRef(left).integer() != null;
    const collection = if (reversed) right else left;
    const count = if (reversed) left else right;
    const ty = b.typeOfRef(collection);
    const count_ty = b.typeOfRef(count);
    const info = count_ty.integer() orelse return b.mb.refuse("collection repeat count", span);
    const wide_ty: ir.Type = if (info.signed) .i64 else .u64;
    const wide = if (count_ty == wide_ty) count else try b.emit(.{ .op = .convert, .ty = wide_ty, .a = count, .span = span });
    if (ty == .str or ty == .bytes) return b.runtimeCall(if (info.signed) "myl_core_octets_repeat_signed" else "myl_core_octets_repeat_unsigned", &.{ ty, wide_ty }, ty, &.{ collection, wide }, span);
    if (b.module().kind(ty) != .list) return b.mb.refuse("collection repeat type", span);
    const result = try b.synthetic(ty);
    const counter = try b.synthetic(wide_ty);
    const length = try b.emit(.{ .op = .list_len, .ty = .u64, .a = collection, .span = span });
    const empty = try b.emit(.{ .op = .list_new, .ty = ty, .a = length, .span = span });
    try b.write(result, b.current.?, empty);
    try b.write(counter, b.current.?, try b.constant(wide_ty, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const end = try b.newBlock();
    try b.jump(header);
    b.current = header;
    const index = try b.read(counter, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = wide, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, end, span);
    try b.seal(body);
    try b.seal(end);
    b.current = body;
    const next = try append(Context, b, try b.read(result, body), collection, span);
    try b.write(result, b.current.?, next);
    try b.write(counter, b.current.?, try b.emit(.{ .op = .add, .ty = wide_ty, .a = index, .b = try b.constant(wide_ty, 1), .check = .exact, .span = span }));
    try b.jump(header);
    try b.seal(header);
    b.enter(end);
    return b.read(result, end);
}

/// Compare recursive values through two managed temporary boxes and a typed adapter.
pub fn equal(comptime Context: type, b: Context, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(left);
    const box = try b.mb.module.intern(b.allocator(), .{ .box = ty });
    const l = try b.emit(.{ .op = .box_make, .ty = box, .a = left, .span = span });
    const r = try b.emit(.{ .op = .box_make, .ty = box, .a = right, .span = span });
    const symbol = try std.fmt.allocPrint(b.allocator(), "myl_core_equal_{d}", .{@backingInt(ty)});
    const callee = try b.mb.runtimeFunction(symbol, &.{ box, box }, .bool, .runtime_c);
    return b.emit(.{ .op = .call, .ty = .bool, .a = @fromBackingInt(callee), .data = try b.extraSlice(&.{ l, r }), .span = span });
}

/// Render with the checked source schema, including information erased by the value IR.
pub fn render(comptime Context: type, b: Context, value: ir.Ref, source: typed.Type, span: u32) Error!ir.Ref {
    return build_render.render(Context, b, value, source, span);
}
