//! Mutable octets, exact snapshots and content-addressed embedded asset lowering.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
const Source = @import("mylang").source.Source;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const flags = @import("flags.zig");

/// Allocation and precise refusal are the mutable byte builder's failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Mutable bytes use the frozen counted-leaf pointer type.
pub fn bufferType(_: anytype, _: u32) Error!ir.Type {
    return .byte_buffer;
}

/// Resolve checked content identity against loaded Source assets; unresolved data refuses.
pub fn blob(context: anytype, asset: typed.Blob, ty: ir.Type, span: u32) Error!ir.Ref {
    const source = context.mb.input.source orelse return context.mb.refuse("unresolved embedded asset", span);
    const bytes = contents(source, asset) orelse return context.mb.refuse("unresolved embedded asset", span);
    const index = context.mb.module.strings.items.len;
    try context.mb.module.strings.append(context.allocator(), bytes);
    return context.detached(.{ .op = .str_const, .ty = ty, .data = index });
}

fn contents(source: Source, asset: typed.Blob) ?[]const u8 {
    for (source.embeds) |embed| {
        if (embed.status == .ok and embed.contents.len == asset.length and std.mem.eql(u8, &embed.digest, &asset.digest)) return embed.contents;
    }
    for (source.origins) |origin| if (contents(origin.original, asset)) |found| return found;
    return null;
}

/// Construct an empty buffer with the checked capacity's octet count.
pub fn acquire(comptime Context: type, context: Context, capacity: ir.Ref, span: u32) Error!ir.Ref {
    const count = if (context.typeOfRef(capacity) == .u64) capacity else try context.emit(.{ .op = .convert, .ty = .u64, .a = capacity, .check = .exact, .span = span });
    return context.emit(.{ .op = .buffer_new, .ty = .byte_buffer, .a = count, .span = span });
}

/// A buffer conversion always allocates independent backing, including a converted list.
pub fn fromValue(comptime Context: type, context: Context, source: ir.Type, operand: ir.Ref, span: u32) Error!ir.Ref {
    if (source == .bytes or source == .byte_buffer) return context.runtimeCall("myl_core_buffer_from_bytes", &.{source}, .byte_buffer, &.{operand}, span);
    if (context.mb.module.kind(source) != .list or context.mb.module.compound(source).list != .i64) return context.mb.refuse("byte_buffer source", span);
    const valid = try context.runtimeCall("myl_core_bytes_valid_list", &.{source}, .bool, &.{operand}, span);
    try require(Context, context, valid, 14, span);
    return context.runtimeCall("myl_core_buffer_from_list", &.{source}, .byte_buffer, &.{operand}, span);
}

/// Lower hex/fromhex over borrowed octets, preserving checked Result tags and errors.
pub fn octet(comptime Context: type, context: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    const receiver = try context.receiverOf(node.owner);
    if (node.kind == .hex) return context.runtimeCall("myl_core_bytes_hex", &.{context.typeOfRef(receiver)}, .str, &.{receiver}, span);
    const valid = try context.runtimeCall("myl_core_from_hex_valid", &.{.str}, .bool, &.{receiver}, span);
    const result = try context.synthetic(ty);
    const yes = try context.newBlock();
    const no = try context.newBlock();
    const join = try context.newBlock();
    try context.branch(valid, yes, no, span);
    try context.seal(yes);
    context.current = yes;
    const value = try context.runtimeCall("myl_core_from_hex", &.{.str}, .bytes, &.{receiver}, span);
    try context.write(result, yes, try context.emit(.{ .op = .union_make, .ty = ty, .a = value, .data = 0, .span = span }));
    try context.jump(join);
    try context.seal(no);
    context.current = no;
    const index = context.mb.module.strings.items.len;
    try context.mb.module.strings.append(context.allocator(), "hexadecimal text requires an even number of hex digits");
    const failure = try context.detached(.{ .op = .str_const, .ty = .str, .data = index });
    _ = try context.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.runtime), .span = span });
    try context.write(result, no, try context.emit(.{ .op = .union_make, .ty = ty, .a = failure, .data = 1, .span = span }));
    try context.jump(join);
    try context.seal(join);
    context.enter(join);
    return context.read(result, join);
}

/// Buffer updates preserve source evaluation order and use the ownership pass's COW shapes.
pub fn operation(comptime Context: type, context: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    switch (node.kind) {
        .write => {
            const index = try context.expression(node.arguments[0]);
            const value = try context.expression(node.arguments[1]);
            const octet_value = if (context.typeOfRef(value) == .u8) value else try context.emit(.{ .op = .convert, .ty = .u8, .a = value, .check = .exact, .span = span });
            const receiver = try context.writableReceiverOf(node.owner, span);
            const changed = try context.emit(.{ .op = .buffer_set, .ty = .byte_buffer, .a = receiver, .b = index, .data = try context.extraSlice(&.{octet_value}), .check = .exact, .span = span });
            try context.writeOwner(node.owner, changed, span);
            return .none;
        },
        .buffer_append_byte => return appendByte(Context, context, node, span),
        .buffer_append_range, .buffer_append_utf8, .buffer_append_int, .buffer_append_float => return appendFragment(Context, context, node, span),
        .buffer_reserve => return reserve(Context, context, node, span),
        .capacity => return context.runtimeCall("myl_core_buffer_capacity", &.{.byte_buffer}, ty, &.{try context.receiverOf(node.owner)}, span),
        .clear => {
            try context.writeOwner(node.owner, try acquire(Context, context, try context.constant(.u64, 0), span), span);
            return .none;
        },
        .reverse => {
            const receiver = try context.writableReceiverOf(node.owner, span);
            const changed = try context.runtimeCall("myl_core_buffer_reverse", &.{.byte_buffer}, .byte_buffer, &.{receiver}, span);
            try context.writeOwner(node.owner, changed, span);
            return .none;
        },
        .copy => return if (context.module().zero_rc) @import("single_owner_copy.zig").copy(Context, context, try context.receiverOf(node.owner), span) else context.receiverOf(node.owner),
        .pop => {
            const receiver = try context.writableReceiverOf(node.owner, span);
            const length = try context.emit(.{ .op = .list_len, .ty = .u64, .a = receiver, .span = span });
            const last = try context.emit(.{ .op = .sub, .ty = .u64, .a = length, .b = try context.constant(.u64, 1), .span = span });
            const value = try context.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = last, .check = .exact, .data = @import("flags.zig").pop_read, .span = span });
            try context.writeOwner(node.owner, try context.emit(.{ .op = .buffer_pop, .ty = .byte_buffer, .a = receiver, .check = .exact, .span = span }), span);
            return if (ty == .u8) value else context.emit(.{ .op = .convert, .ty = ty, .a = value, .span = span });
        },
        .hex => return octet(Context, context, node, ty, span),
        else => return context.textOperation(node, ty, span),
    }
}

/// `buffer.append_byte(value)`: the receiver is read, handed to one runtime call that pushes the
/// octet when it is in 0..255, and written back, all in the statement's block, so a `mut`
/// place's buffer field is taken over and updated in place rather than copied per call.
fn appendByte(comptime Context: type, context: Context, node: Operation, span: u32) Error!ir.Ref {
    const value = try context.expression(node.arguments[0]);
    const low = try context.emit(.{ .op = .cmp, .ty = .bool, .a = value, .b = try context.constant(context.typeOfRef(value), 0), .data = @backingInt(ir.Predicate.ge), .span = span });
    const high = try context.emit(.{ .op = .cmp, .ty = .bool, .a = value, .b = try context.constant(context.typeOfRef(value), 255), .data = @backingInt(ir.Predicate.le), .span = span });
    const valid = try context.emit(.{ .op = .bit_and, .ty = .bool, .a = low, .b = high, .span = span });
    // The runtime pushes only an octet in 0..255; a wider value keeps its bits as an i64, so an
    // out-of-range value stays out of range.
    const wide = if (context.typeOfRef(value) == .i64) value else try context.emit(.{ .op = .convert, .ty = .i64, .a = value, .span = span });
    const receiver = try context.writableReceiverOf(node.owner, span);
    try context.writeOwner(node.owner, try handedOver(Context, context, "myl_core_buffer_push_checked", &.{ .byte_buffer, .i64 }, &.{ receiver, wide }, span), span);
    return valid;
}

/// `append_range`, `append_utf8` (and the integer and float spellings): the receiver is read,
/// updated by one call and written back in the statement's block, so a `mut` place's buffer
/// field is taken over and the append is in place when the buffer is unique. A range the
/// runtime finds invalid appends nothing, and the validity is the method's result.
fn appendFragment(comptime Context: type, context: Context, node: Operation, span: u32) Error!ir.Ref {
    const source = try context.expression(node.arguments[0]);
    if (node.kind == .buffer_append_int or node.kind == .buffer_append_float) {
        const integer = node.kind == .buffer_append_int;
        _ = try context.mb.runtimeFunction(if (integer) flags.buffer_int_symbol else flags.buffer_float_symbol, &.{ .byte_buffer, if (integer) .i64 else .f64 }, .byte_buffer, .extern_c);
        const receiver = try context.writableReceiverOf(node.owner, span);
        const updated = try context.emit(.{ .op = .buffer_push, .ty = .byte_buffer, .a = receiver, .b = source, .data = if (integer) flags.buffer_append_int else flags.buffer_append_float, .span = span });
        try context.writeOwner(node.owner, updated, span);
        return context.constant(.bool, 1);
    }
    const start = if (node.kind == .buffer_append_range) try context.expression(node.arguments[1]) else try context.constant(.i64, 0);
    const stop = if (node.kind == .buffer_append_range) try context.expression(node.arguments[2]) else try context.emit(.{ .op = if (context.typeOfRef(source) == .str) .str_len else .list_len, .ty = .u64, .a = source, .span = span });
    const end = if (context.typeOfRef(stop) == .i64) stop else try context.emit(.{ .op = .convert, .ty = .i64, .a = stop, .span = span });
    const valid = if (context.module().zero_rc)
        try context.effectCall("myl_core_buffer_range_valid", &.{ context.typeOfRef(source), .i64, .i64 }, .bool, &.{ source, start, end }, span)
    else
        try context.runtimeCall("myl_core_buffer_range_valid", &.{ context.typeOfRef(source), .i64, .i64 }, .bool, &.{ source, start, end }, span);
    // Text is encoded once; the encoding borrows the text's own octets.
    const octets = if (context.typeOfRef(source) == .str) encoded: {
        if (context.module().zero_rc) break :encoded try context.effectCall("myl_core_text_encode", &.{.str}, .bytes, &.{source}, span);
        break :encoded try context.runtimeCall("myl_core_text_encode", &.{.str}, .bytes, &.{source}, span);
    } else source;
    const receiver = try context.writableReceiverOf(node.owner, span);
    const updated = try handedOver(Context, context, "myl_core_buffer_append_checked", &.{ .byte_buffer, context.typeOfRef(octets), .i64, .i64 }, &.{ receiver, octets, start, end }, span);
    try context.writeOwner(node.owner, updated, span);
    return valid;
}

/// Call runtime `symbol`, handing it the buffer in argument 0 (an owned parameter): the
/// runtime updates the buffer in place when it holds the only reference and copies it
/// otherwise, and returns the updated buffer.
fn handedOver(comptime Context: type, context: Context, symbol: []const u8, params: []const ir.Type, arguments: []const ir.Ref, span: u32) Error!ir.Ref {
    if (context.module().zero_rc and @import("std").mem.eql(u8, symbol, "myl_core_buffer_append_checked"))
        return context.effectCall(symbol, params, .byte_buffer, arguments, span);
    const callee = try context.mb.runtimeFunction(symbol, params, .byte_buffer, .extern_c);
    context.mb.module.functions.items[callee].signature.owned = 1;
    return context.emit(.{ .op = .call, .ty = .byte_buffer, .a = @fromBackingInt(callee), .data = try context.extraSlice(arguments), .span = span });
}

fn reserve(comptime Context: type, context: Context, node: Operation, span: u32) Error!ir.Ref {
    const extra = try context.expression(node.arguments[0]);
    const receiver = try context.writableReceiverOf(node.owner, span);
    const valid = try context.runtimeCall("myl_core_buffer_reserve_valid", &.{ .byte_buffer, .i64 }, .bool, &.{ receiver, extra }, span);
    const yes = try context.newBlock();
    const join = try context.newBlock();
    try context.branch(valid, yes, join, span);
    try context.seal(yes);
    context.current = yes;
    const changed = try context.runtimeCall("myl_core_buffer_reserved", &.{ .byte_buffer, .i64 }, .byte_buffer, &.{ receiver, extra }, span);
    try context.writeOwner(node.owner, changed, span);
    try context.jump(join);
    try context.seal(join);
    context.enter(join);
    return valid;
}

fn require(comptime Context: type, context: Context, condition: ir.Ref, kind: u8, span: u32) Error!void {
    const good = try context.newBlock();
    const bad = try context.newBlock();
    try context.branch(condition, good, bad, span);
    try context.seal(bad);
    context.current = bad;
    _ = try context.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.text_trap | kind, .span = span });
    try context.seal(good);
    context.current = good;
}
