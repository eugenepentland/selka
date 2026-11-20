//! Explicit copies recursively duplicate every owned child, including text and bytes. Every
//! copy site this file emits is written (`flags.written_copy`): the source spelled `copy(value)`.
const ir = @import("ir.zig");
const single_owner = @import("single_owner.zig");
const view_materialize = @import("view_materialize.zig");

/// The lowering builder's allocation and unsupported-shape failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Emit an independent value tree in the caller's current block.
pub fn copy(comptime Context: type, b: Context, value: ir.Ref, span: u32) Error!ir.Ref {
    return copyAs(Context, b, value, try copiedType(Context, b, b.typeOfRef(value)), span);
}

/// Copy into the checked expression's owning layout, including recursive
/// payload boxes removed by a read-only wrapper's transient representation.
pub fn copyAs(comptime Context: type, b: Context, value: ir.Ref, target: ir.Type, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(value);
    const module = b.module();
    if (module.isBorrowed(ty)) return copyAs(Context, b, try b.borrowStorage(value, span), target, span);
    if (module.kind(ty) == .box and ty != target) {
        const payload = try b.emit(.{ .op = .box_get, .ty = module.compound(ty).box, .a = value, .span = span });
        return copyAs(Context, b, payload, target, span);
    }
    if (module.kind(target) == .box and ty != target) {
        const payload = try copyAs(Context, b, value, module.compound(target).box, span);
        return b.emit(.{ .op = .box_make, .ty = target, .a = payload, .span = span });
    }
    // A view has no owned storage of its own: its written copy is the owned value it names.
    if (ty.isSpan()) return b.materializeWritten(value, if (ty == .bytes_view) .bytes else .text, span);
    // A list view copies its elements into an owned list (C9 lists); a plain value with no managed child is its own copy.
    if (b.module().kind(ty) == .list_view) return copyView(Context, b, value, span);
    if (!single_owner.containsList(b.module(), ty)) return value;
    if ((ty == .str or ty == .bytes)) return writtenCall(Context, b, "myl_core_owned_octets_copy", ty, value, span);
    if (ty == .byte_buffer) return b.markWritten(try b.emit(.{ .op = .buffer_copy, .ty = ty, .a = value, .span = span }));
    switch (b.module().compound(ty)) {
        .list => |element| {
            if (!single_owner.containsList(b.module(), element)) return b.markWritten(try b.emit(.{ .op = .list_copy, .ty = ty, .a = value, .span = span }));
            return copyBlock(Context, b, value, span);
        },
        .box => return copyBlock(Context, b, value, span),
        .@"union" => |cases| return copyUnion(Context, b, value, cases, target, span),
        .dict => return copyBlock(Context, b, value, span),
        .record => |fields| {
            const children = try b.mb.allocator.alloc(ir.Ref, fields.len);
            for (fields, 0..) |field, index| {
                const child = try b.emit(.{ .op = .record_get, .ty = field, .a = value, .data = index, .span = span });
                children[index] = try copyAs(Context, b, child, module.compound(target).record[index], span);
            }
            return b.emit(.{ .op = .record_make, .ty = target, .data = try b.extraSlice(children), .span = span });
        },
        .array => |array| {
            const children = try b.mb.allocator.alloc(ir.Ref, array.n);
            for (children, 0..) |*child, index| {
                const at = try b.constant(.u64, index);
                const value_at = try b.emit(.{ .op = .array_get, .ty = array.elem, .a = value, .b = at, .check = .exact, .span = span });
                child.* = try copyAs(Context, b, value_at, module.compound(target).array.elem, span);
            }
            return b.emit(.{ .op = .record_make, .ty = target, .data = try b.extraSlice(children), .span = span });
        },
        else => return b.mb.refuse("explicit copy of this single-owner aggregate", span),
    }
}

fn copyUnion(comptime Context: type, b: Context, value: ir.Ref, cases: []const ir.Type, ty: ir.Type, span: u32) Error!ir.Ref {
    const tag = try b.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
    const result = try b.synthetic(ty);
    const join = try b.newBlock();
    for (cases, 0..) |payload_type, index| {
        const body = try b.newBlock();
        const next = if (index + 1 < cases.len) try b.newBlock() else null;
        if (next) |other| {
            const matches = try b.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try b.constant(.u32, index), .data = @backingInt(ir.Predicate.eq), .span = span });
            try b.branch(matches, body, other, span);
            try b.seal(other);
        } else try b.jump(body);
        try b.seal(body);
        b.enter(body);
        const payload = if (payload_type == .void) .none else try b.emit(.{ .op = .union_payload, .ty = payload_type, .a = value, .data = index, .span = span });
        const cloned = if (payload == .none) .none else try copyAs(Context, b, payload, b.module().compound(ty).@"union"[index], span);
        const made = try b.emit(.{ .op = .union_make, .ty = ty, .a = cloned, .data = index, .span = span });
        try b.write(result, b.current.?, made);
        try b.jump(join);
        if (next) |other| b.enter(other);
    }
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

/// Copies turn a borrowed payload into owned storage while preserving its
/// surrounding option/result tags and independently owned failure payloads.
fn copiedType(comptime Context: type, b: Context, ty: ir.Type) Error!ir.Type {
    if (ty == .str_view) return .str;
    if (ty == .bytes_view) return .bytes;
    const module = b.module();
    if (module.isBorrowed(ty)) return module.storageType(ty);
    if (!ty.isCompound()) return ty;
    return switch (module.compound(ty)) {
        .list_view => |element| module.intern(b.allocator(), .{ .list = element }),
        .@"union" => |cases| types: {
            const owned = try b.allocator().alloc(ir.Type, cases.len);
            var changed = false;
            for (cases, owned) |child, *target| {
                target.* = try copiedType(Context, b, child);
                changed = changed or target.* != child;
            }
            if (!changed) break :types ty;
            break :types module.intern(b.allocator(), .{ .@"union" = owned });
        },
        .record => |fields| types: {
            const owned = try b.allocator().alloc(ir.Type, fields.len);
            var changed = false;
            for (fields, owned) |child, *target| {
                target.* = try copiedType(Context, b, child);
                changed = changed or target.* != child;
            }
            if (!changed) break :types ty;
            break :types module.intern(b.allocator(), .{ .record = owned });
        },
        .array => |array| types: {
            const element = try copiedType(Context, b, array.elem);
            if (element == array.elem) break :types ty;
            break :types module.intern(b.allocator(), .{ .array = .{ .elem = element, .n = array.n } });
        },
        else => ty,
    };
}

// A block boundary stops compiler expansion even when recursion passes through
// a list or dictionary rather than a box. The runtime visits its finite graph.
fn copyBlock(comptime Context: type, b: Context, value: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(value);
    const symbol = try b.mb.helperName(@import("emit_values.zig").copy_prefix, &.{ty});
    return writtenCall(Context, b, symbol, ty, value, span);
}

/// A runtime helper call that copies `value`, marked as written. The runtime performs the child
/// copies of a recursive copy inside the call, so the call is the one site that carries the mark.
fn writtenCall(comptime Context: type, b: Context, symbol: []const u8, ty: ir.Type, value: ir.Ref, span: u32) Error!ir.Ref {
    return b.markWritten(try b.effectCall(symbol, &.{ty}, ty, &.{value}, span));
}

/// An owned list holding a copy of each element of list view `view` (C9 lists): an explicit `copy` of a view, and
/// what `sorted(...)` and `list(...)` copy, is built here element by element, so the source is read in place.
pub fn copyView(comptime Context: type, b: Context, view: ir.Ref, span: u32) Error!ir.Ref {
    const element = b.module().listElement(b.typeOfRef(view)) orelse return b.mb.refuse("copy of a value that is not a list", span);
    const list = try b.module().intern(b.allocator(), .{ .list = element });
    // A list whose elements hold no blocks is copied in one span: its elements are independent scalars.
    if (!single_owner.containsList(b.module(), element)) return b.markWritten(try b.emit(.{ .op = .list_copy, .ty = list, .a = view, .span = span }));
    const count = try b.emit(.{ .op = .list_len, .ty = .u64, .a = view, .span = span });
    const result = try b.synthetic(list);
    const counter = try b.synthetic(.u64);
    try b.write(result, b.current.?, try b.emit(.{ .op = .list_new, .ty = list, .a = count, .span = span }));
    try b.write(counter, b.current.?, try b.constant(.u64, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const end = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const index = try b.read(counter, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = count, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, end, span);
    try b.seal(body);
    b.enter(body);
    const source = try b.emit(.{ .op = .list_get, .ty = element, .a = view, .b = index, .check = .exact, .span = span });
    // An element is copied by the ordinary copy: a scalar is its own copy, and a managed element is duplicated.
    const copied = try copy(Context, b, source, span);
    const pushed = try b.emit(.{ .op = .list_push, .ty = list, .a = try b.read(result, b.current.?), .b = copied, .span = span });
    try b.write(result, b.current.?, pushed);
    try b.write(counter, b.current.?, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(end);
    b.enter(end);
    return b.read(result, end);
}
