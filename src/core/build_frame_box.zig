//! O4: the lent options of a borrowed record. `Some(p)` of a read-only record parameter holds the parameter in place (and
//! `Some(place)` of a projection holds that place, RB1): an
//! unboxed payload is lent as the record's other fields are, and a boxed (recursive) payload is a frame box, a slot of
//! this call's stack that holds the parameter's value behind a box header (`ir.Op.box_frame`). The checker never lets a
//! record that holds a frame box leave the call (`single_owner.BorrowedRecords.frameOption`).
const typed = @import("selka").typed;
const ir = @import("ir.zig");

/// Allocation, or a shape the builder cannot lower.
pub const Error = error{ OutOfMemory, Unsupported };

/// The field value of lent option `id` (`Some(p)` or `Some(place)`), stored in a field of type `field_type`: the union of the lent payload,
/// lent to the record as its storage type, so the record owns nothing of it.
pub fn lent(comptime Context: type, b: Context, id: typed.NodeId, field_type: ir.Type, span: u32) Error!ir.Ref {
    const node = b.nodeOf(id);
    const payload_node = b.nodeOf(node.data.variant.value orelse return b.refuse("a lent option without a payload", span));
    var value = try b.expression(node.data.variant.value.?);
    if (b.current == null) return .none;
    // A bare plain text, bytes or list parameter arrives as a view: the option holds its frame block (RB1), as a record does.
    if (b.borrowed_records.?.framedRead(node.data.variant.value.?)) value = try b.frameBlock(value, span);
    const m = b.module();
    if (m.kind(field_type) != .@"union") return b.refuse("a lent option field that is not an option", span);
    const cases = m.compound(field_type).@"union";
    const tag = node.data.variant.tag;
    if (tag >= cases.len) return b.refuse("a lent option case", span);
    // A boxed payload is lent only from a parameter (O4); a projection is lent only into an unboxed case (RB1).
    const boxed = m.kind(cases[tag]) == .box;
    if (boxed and payload_node.data != .local) return b.refuse("a lent option of a value that is not a parameter", span);
    const payload = if (boxed)
        try frameBox(Context, b, @backingInt(payload_node.data.local), cases[tag], span)
    else
        try b.borrowStorage(try b.readOnlyArgument(value, try m.borrowedType(b.allocator(), m.storageType(b.typeOfRef(value))), span), span);
    const made = try b.emit(.{ .op = .union_make, .ty = field_type, .a = payload, .data = tag, .span = span });
    return b.borrowStorage(try b.readOnlyArgument(made, try m.borrowedType(b.allocator(), field_type), span), span);
}

/// The frame box of the parameter in local `slot`, made once per parameter and attached to the entry block (as a text frame
/// is), so it is written before any use and never again: the parameter cannot change during the call. It reads the
/// parameter's entry value, which every read of a plain parameter is.
fn frameBox(comptime Context: type, b: Context, slot: usize, box_type: ir.Type, span: u32) Error!ir.Ref {
    const at = (try entryParameter(Context, b, slot)) orelse return b.refuse("a frame box of a value that is not a parameter", span);
    if (b.module().compound(box_type).box != b.typeOfRef(at)) return b.refuse("a frame box of another type", span);
    const key: u32 = @intCast(at.index());
    if (b.frames.get(key)) |frame| return frame;
    const frame = try b.detached(.{ .op = .box_frame, .ty = box_type, .a = at, .span = span });
    try b.frames.put(b.allocator(), key, frame);
    return frame;
}

/// The `param` instruction of the parameter in local `slot`: the passed position counts the parameters before it that are
/// passed (a `Unit` parameter is not).
fn entryParameter(comptime Context: type, b: Context, slot: usize) Error!?ir.Ref {
    const locals = b.checked.scope.locals;
    if (slot >= b.checked.signature.parameter_count) return null;
    var passed: u64 = 0;
    for (locals[0..slot]) |local| {
        if (try b.mb.mapType(local.ty, @intCast(local.declaration.start)) != .void) passed += 1;
    }
    for (b.function.insts.items, 0..) |inst, index| {
        if (inst.op == .param and inst.data == passed) return @fromBackingInt(@as(u32, @intCast(index)));
    }
    return null;
}
