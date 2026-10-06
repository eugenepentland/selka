//! Text and immutable octet lowering; all storage remains one counted leaf block.
const ir = @import("ir.zig");
const std = @import("std");
const typed = @import("mylang").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const more = @import("build_text_more.zig");

/// Allocation and precise feature refusals are the builder's only failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Number-conversion dispatch hook, replaced by S2-T2 without changing text dispatch.
pub fn number(comptime Context: type, context: Context, operation_node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    return @import("build_number.zig").operation(Context, context, operation_node, ty, span);
}

/// Lower one checked text or bytes operation with the original evaluation order.
pub fn operation(comptime Context: type, context: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    if (node.kind == .hex or node.kind == .from_hex) return @import("build_bytes.zig").octet(Context, context, node, ty, span);
    switch (node.kind) {
        .parse_int, .parse_int_range, .parse_float, .parse_float_range, .number_format => return number(Context, context, node, ty, span),
        else => {},
    }
    if (more.handles(node.kind)) return more.operation(Context, context, node, ty, span);
    const receiver = try context.receiverOf(node.owner);
    const receiver_type = context.typeOfRef(receiver);
    const text = receiver_type == .str;
    switch (node.kind) {
        .length => return if (text) context.stringChars(receiver, span) else context.emit(.{ .op = .list_len, .ty = .u64, .a = receiver, .span = span }),
        .read => {
            const index = try context.expression(node.arguments[0]);
            if (!text) {
                const value = try context.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = index, .check = .exact, .span = span });
                return if (ty != .u8) context.emit(.{ .op = .convert, .ty = ty, .a = value, .span = span }) else value;
            }
            const offset = try context.runtimeCall("myl_core_str_offset", &.{ .str, context.typeOfRef(index) }, .u64, &.{ receiver, index }, span);
            return context.emit(.{ .op = .str_char, .ty = .str, .a = receiver, .b = offset, .check = .exact, .span = span });
        },
        .encode => return context.runtimeCall("myl_core_text_encode", &.{.str}, .bytes, &.{receiver}, span),
        .slice_step => {
            const start = try context.expression(node.arguments[0]);
            const end = try context.expression(node.arguments[1]);
            const step = try context.expression(node.arguments[2]);
            const nonzero = try context.emit(.{ .op = .cmp, .ty = .bool, .a = step, .b = try context.constant(.i64, 0), .data = @backingInt(ir.Predicate.ne), .span = span });
            try require(Context, context, nonzero, 13, span);
            return context.runtimeCall(if (text) "myl_core_str_slice_step" else "myl_core_bytes_slice_step", &.{ receiver_type, .i64, .i64, .i64 }, receiver_type, &.{ receiver, start, end, step }, span);
        },
        .slice, .text_tail => {
            const start = try context.expression(node.arguments[0]);
            const end = try context.expression(node.arguments[1]);
            if (!text) return context.runtimeCall("myl_core_bytes_slice", &.{ receiver_type, .i64, .i64 }, .bytes, &.{ receiver, start, end }, span);
            return context.emit(.{ .op = .str_slice, .ty = .str, .a = receiver, .b = start, .data = try context.extraSlice(&.{end}), .span = span });
        },
        .find, .contains, .starts_with, .ends_with => {
            const needle = try context.expression(node.arguments[0]);
            if (!text and node.kind == .contains and context.typeOfRef(needle).integer() != null) {
                const value = if (context.typeOfRef(needle) == .i64) needle else try context.emit(.{ .op = .convert, .ty = .i64, .a = needle, .span = span });
                return context.runtimeCall("myl_core_bytes_contains_value", &.{ receiver_type, .i64 }, .bool, &.{ receiver, value }, span);
            }
            const symbol: []const u8 = switch (node.kind) {
                .find => if (text) "myl_core_str_find" else "myl_core_bytes_find",
                .contains => "myl_core_str_contains",
                .starts_with => "myl_core_str_starts",
                else => "myl_core_str_ends",
            };
            return context.runtimeCall(symbol, &.{ receiver_type, context.typeOfRef(needle) }, ty, &.{ receiver, needle }, span);
        },
        .join, .split => {
            const argument = try context.expression(node.arguments[0]);
            if (node.kind == .split) {
                const length = try context.emit(.{ .op = if (text) .str_len else .list_len, .ty = .u64, .a = argument, .span = span });
                const nonempty = try context.emit(.{ .op = .cmp, .ty = .bool, .a = length, .b = try context.constant(.u64, 0), .data = @backingInt(ir.Predicate.ne), .span = span });
                try require(Context, context, nonempty, 12, span);
            }
            return context.runtimeCall(if (node.kind == .join) "myl_core_str_join" else "myl_core_str_split", &.{ receiver_type, context.typeOfRef(argument) }, ty, &.{ receiver, argument }, span);
        },
        .parse_int, .parse_float, .parse_int_range, .parse_float_range, .number_format, .hex, .from_hex, .float_round => return number(Context, context, node, ty, span),
        .split_whitespace => return context.runtimeCall("myl_core_str_split_whitespace", &.{receiver_type}, ty, &.{receiver}, span),
        .to_list => return context.runtimeCall("myl_core_bytes_to_list", &.{receiver_type}, ty, &.{receiver}, span),
        .copy => return receiver,
        else => return context.mb.refuse(@tagName(node.kind), span),
    }
}

/// Validate the octet range before converting a list of integers to immutable bytes.
pub fn fromList(comptime Context: type, context: Context, source: ir.Type, operand: ir.Ref, span: u32) Error!ir.Ref {
    const valid = try context.runtimeCall("myl_core_bytes_valid_list", &.{source}, .bool, &.{operand}, span);
    try require(Context, context, valid, 14, span);
    return context.runtimeCall("myl_core_bytes_from_list", &.{source}, .bytes, &.{operand}, span);
}

/// Build raw byte literals without UTF-8 encoding their octets.
pub fn literal(comptime Context: type, context: Context, items: []const typed.NodeId, span: u32) Error!ir.Ref {
    var bytes: std.ArrayList(u8) = .empty;
    for (items) |item| {
        const value = context.nodeOf(item);
        if (value.data != .integer) return context.mb.refuse("byte literal element", span);
        try bytes.append(context.allocator(), std.math.cast(u8, value.data.integer) orelse return context.mb.refuse("byte literal value", span));
    }
    const index = context.mb.module.strings.items.len;
    try context.mb.module.strings.append(context.allocator(), try bytes.toOwnedSlice(context.allocator()));
    const source = try context.detached(.{ .op = .str_const, .ty = .str, .data = index });
    return context.runtimeCall("myl_core_text_encode", &.{.str}, .bytes, &.{source}, span);
}

/// Index a non-place string/bytes expression; the offset helper normalizes negatives.
pub fn indexed(comptime Context: type, context: Context, base: typed.NodeId, index_node: typed.NodeId, span: u32, result_type: ir.Type) Error!ir.Ref {
    const receiver = try context.expression(base);
    const receiver_type = context.typeOfRef(receiver);
    if (receiver_type != .str and receiver_type != .bytes and receiver_type != .byte_buffer) return context.mb.refuse("index receiver", span);
    const selected = try context.expression(index_node);
    const offset = try context.runtimeCall(if (receiver_type == .str) "myl_core_str_index_offset" else "myl_core_bytes_index_offset", &.{ receiver_type, .i64 }, .u64, &.{ receiver, selected }, span);
    const value = try context.emit(.{ .op = if (receiver_type == .str) .str_char else .list_get, .ty = if (receiver_type == .str) .str else .u8, .a = receiver, .b = offset, .check = .exact, .span = span });
    return if (receiver_type != .str and result_type != .u8) context.emit(.{ .op = .convert, .ty = result_type, .a = value, .span = span }) else value;
}

/// Branch to a located text trap unless the checked runtime condition holds.
pub fn require(comptime Context: type, context: Context, condition: ir.Ref, kind: u8, span: u32) Error!void {
    return @import("text_checks.zig").require(Context, context, condition, kind, span);
}

/// Compile-time cache words for an immortal string literal; malformed raw byte constants omit scalars.
pub fn metadata(bytes: []const u8) struct { kind: u32, meta: u64 } {
    const scalars: ?usize = std.unicode.utf8CountCodepoints(bytes) catch null;
    const ascii = isAscii(bytes);
    var kind: u32 = 1 | 512;
    if (ascii) kind |= 256;
    if (scalars != null and scalars.? <= std.math.maxInt(u32)) kind |= 1024;
    return .{ .kind = kind, .meta = @as(u64, hash(bytes)) | (if (scalars != null and scalars.? <= std.math.maxInt(u32)) @as(u64, @intCast(scalars.?)) << 32 else 0) };
}

fn hash(bytes: []const u8) u32 {
    const word_key: u64 = 0xa0761d6478bd642f;
    const state_key: u64 = 0xe7037ed1a0b428db;
    var state: u64 = 0x243f6a8885a308d3 ^ bytes.len;
    var result: u64 = undefined;
    if (bytes.len <= 8) {
        var low: u64 = 0;
        var high: u64 = 0;
        if (bytes.len >= 4) {
            low = std.mem.readInt(u32, bytes[0..4], .little);
            high = std.mem.readInt(u32, bytes[bytes.len - 4 ..][0..4], .little);
        } else if (bytes.len != 0) low = @as(u64, bytes[0]) << 16 | @as(u64, bytes[bytes.len >> 1]) << 8 | bytes[bytes.len - 1];
        result = fold(low ^ word_key, high ^ state ^ state_key);
    } else {
        var at: usize = 0;
        while (at + 8 < bytes.len) : (at += 8) state = fold(std.mem.readInt(u64, bytes[at..][0..8], .little) ^ word_key, state ^ state_key);
        result = fold(std.mem.readInt(u64, bytes[bytes.len - 8 ..][0..8], .little) ^ word_key, state ^ state_key);
    }
    return @truncate(result ^ (result >> 32));
}

fn fold(a: u64, b: u64) u64 {
    const product: u128 = @as(u128, a) * b;
    return @as(u64, @truncate(product)) ^ @as(u64, @truncate(product >> 64));
}

fn isAscii(bytes: []const u8) bool {
    for (bytes) |byte| if (byte >= 128) return false;
    return true;
}
