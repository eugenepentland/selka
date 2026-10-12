//! Explicit copies recursively duplicate owned children. Zero-RC mode includes
//! strings and bytes; the earlier list-only mode preserves their shared form.
const ir = @import("ir.zig");
const single_owner = @import("single_owner.zig");

/// The lowering builder's allocation and unsupported-shape failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Emit an independent value tree in the caller's current block.
pub fn copy(comptime Context: type, b: Context, value: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(value);
    if (!single_owner.containsList(b.module(), ty)) return value;
    if (b.module().zero_rc and (ty == .str or ty == .bytes)) return b.effectCall("myl_core_owned_octets_copy", &.{ty}, ty, &.{value}, span);
    if (b.module().zero_rc and ty == .byte_buffer) return b.emit(.{ .op = .buffer_copy, .ty = ty, .a = value, .span = span });
    switch (b.module().compound(ty)) {
        .list => |element| {
            if (!single_owner.containsList(b.module(), element)) return b.emit(.{ .op = .list_copy, .ty = ty, .a = value, .span = span });
            if (b.module().zero_rc) return copyBlock(Context, b, value, span);
            const count = try b.emit(.{ .op = .list_len, .ty = .u64, .a = value, .span = span });
            const target = try b.synthetic(ty);
            const counter = try b.synthetic(.u64);
            try b.write(target, b.current.?, try b.emit(.{ .op = .list_new, .ty = ty, .a = count, .span = span }));
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
            const child = try b.emit(.{ .op = .list_get, .ty = element, .a = value, .b = index, .check = .exact, .span = span });
            const cloned = try copy(Context, b, child, span);
            const at = b.current.?;
            const pushed = try b.emit(.{ .op = .list_push, .ty = ty, .a = try b.read(target, at), .b = cloned, .span = span });
            try b.write(target, at, pushed);
            try b.write(counter, at, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
            try b.jump(header);
            try b.seal(header);
            try b.seal(end);
            b.enter(end);
            return b.read(target, end);
        },
        .box => return copyBlock(Context, b, value, span),
        .@"union" => |cases| return copyUnion(Context, b, value, cases, span),
        .dict => return if (b.module().zero_rc) copyBlock(Context, b, value, span) else @import("build_dict.zig").copy(Context, b, value, span),
        .record => |fields| {
            const children = try b.mb.allocator.alloc(ir.Ref, fields.len);
            for (fields, 0..) |field, index| {
                const child = try b.emit(.{ .op = .record_get, .ty = field, .a = value, .data = index, .span = span });
                children[index] = try copy(Context, b, child, span);
            }
            return b.emit(.{ .op = .record_make, .ty = ty, .data = try b.extraSlice(children), .span = span });
        },
        .array => |array| {
            const children = try b.mb.allocator.alloc(ir.Ref, array.n);
            for (children, 0..) |*child, index| {
                const at = try b.constant(.u64, index);
                const value_at = try b.emit(.{ .op = .array_get, .ty = array.elem, .a = value, .b = at, .check = .exact, .span = span });
                child.* = try copy(Context, b, value_at, span);
            }
            return b.emit(.{ .op = .record_make, .ty = ty, .data = try b.extraSlice(children), .span = span });
        },
        else => return b.mb.refuse("explicit copy of this single-owner aggregate", span),
    }
}

fn copyUnion(comptime Context: type, b: Context, value: ir.Ref, cases: []const ir.Type, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(value);
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
        const cloned = if (payload == .none) .none else try copy(Context, b, payload, span);
        const made = try b.emit(.{ .op = .union_make, .ty = ty, .a = cloned, .data = index, .span = span });
        try b.write(result, b.current.?, made);
        try b.jump(join);
        if (next) |other| b.enter(other);
    }
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

// A block boundary stops compiler expansion even when recursion passes through
// a list or dictionary rather than a box. The runtime visits its finite graph.
fn copyBlock(comptime Context: type, b: Context, value: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(value);
    const symbol = try @import("std").fmt.allocPrint(b.mb.allocator, "{s}{d}", .{ @import("emit_values.zig").copy_prefix, @backingInt(ty) });
    return b.effectCall(symbol, &.{ty}, ty, &.{value}, span);
}
