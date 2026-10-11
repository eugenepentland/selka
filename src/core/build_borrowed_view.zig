//! Explicit nonowning text and byte spans in the zero-RC prototype.
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");

/// Builder allocation and unsupported operation failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Borrow the entire physical octet range; source checking protects its owner.
pub fn whole(comptime B: type, b: B, source: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(source);
    if (ty == .str_view) return source;
    const extent = try b.emit(.{ .op = if (ty == .str) .str_len else .list_len, .ty = .u64, .a = source, .span = span });
    return b.emit(.{ .op = .str_view_of, .ty = .str_view, .a = source, .b = try b.constant(.u64, 0), .data = try b.extraSlice(&.{extent}), .span = span });
}

/// Scalar length preserves text's Unicode indexing and bytes' octet indexing.
pub fn length(comptime B: type, b: B, value: ir.Ref, text: bool, span: u32) Error!ir.Ref {
    if (text) return b.runtimeCall("myl_core_view_chars", &.{.str}, .i64, &.{value}, span);
    const size = try b.emit(.{ .op = .str_len, .ty = .u64, .a = value, .span = span });
    return b.emit(.{ .op = .convert, .ty = .i64, .a = size, .check = .exact, .span = span });
}

/// An indexed character is an owned string; an indexed byte is a scalar.
pub fn indexed(comptime B: type, b: B, value: ir.Ref, index: ir.Ref, text: bool, result: ir.Type, span: u32) Error!ir.Ref {
    const wide = if (b.typeOfRef(index) == .i64) index else try b.emit(.{ .op = .convert, .ty = .i64, .a = index, .check = .exact, .span = span });
    const offset = try b.runtimeCall("myl_core_view_index", &.{ .str, .i64, .bool }, .u64, &.{ value, wide, try b.constant(.bool, @intFromBool(text)) }, span);
    const size = try b.emit(.{ .op = .str_len, .ty = .u64, .a = value, .span = span });
    const valid = try b.emit(.{ .op = .cmp, .ty = .bool, .a = offset, .b = size, .data = @backingInt(ir.Predicate.lt), .span = span });
    try @import("build_text.zig").require(@TypeOf(b), b, valid, 11, span);
    const got = try b.runtimeCall(if (text) "myl_core_view_char" else "myl_core_view_byte", &.{ .str, .u64 }, if (text) .str else .u8, &.{ value, offset }, span);
    return if (b.typeOfRef(got) == result) got else b.emit(.{ .op = .convert, .ty = result, .a = got, .span = span });
}

/// Lower only audited span operations; no implicit materialization is allowed.
pub fn operation(comptime B: type, b: B, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    if (!b.module().zero_rc) return b.mb.refuse("borrowed views require --experimental-zero-rc", span);
    const source_type = b.checked.scope.locals[@backingInt(node.owner)].ty;
    const text = b.mb.input.program.records[source_type.recordIndex()].collection.kind == .string;
    const value = try whole(B, b, try b.receiverOf(node.owner), span);
    switch (node.kind) {
        .borrow_view, .slice => {
            const first = try b.expression(node.arguments[0]);
            const last = try b.expression(node.arguments[1]);
            const start = if (b.typeOfRef(first) == .i64) first else try b.emit(.{ .op = .convert, .ty = .i64, .a = first, .check = .exact, .span = span });
            const end = if (b.typeOfRef(last) == .i64) last else try b.emit(.{ .op = .convert, .ty = .i64, .a = last, .check = .exact, .span = span });
            return b.runtimeCall("myl_core_view_slice", &.{ .str, .i64, .i64, .bool }, .str_view, &.{ value, start, end, try b.constant(.bool, @intFromBool(text)) }, span);
        },
        .length => return length(B, b, value, text, span),
        .copy => return b.runtimeCall(if (text) "myl_core_view_copy_text" else "myl_core_view_copy_bytes", &.{.str}, ty, &.{value}, span),
        .read => return indexed(B, b, value, try b.expression(node.arguments[0]), text, ty, span),
        else => return b.mb.refuse("this borrowed-view operation", span),
    }
}

/// Optional dispatch keeps the main collection builder independent of view APIs.
pub fn dispatch(comptime B: type, b: B, node: Operation, ty: ir.Type, receiver: ir.Type, span: u32) Error!?ir.Ref {
    if (node.kind != .borrow_view and receiver != .str_view) return null;
    const result = try operation(B, b, node, ty, span);
    return result;
}
