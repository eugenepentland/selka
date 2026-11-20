//! Text and immutable octet lowering; all storage remains one counted leaf block.
const ir = @import("ir.zig");
const std = @import("std");
const typed = @import("selka").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const offset_symbol = "myl_core_str_offset";
const encode_symbol = "myl_core_text_encode";
const more = @import("build_text_more.zig");
const flags = @import("flags.zig");

/// Allocation and precise feature refusals are the builder's only failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Number-conversion dispatch hook, replaced by S2-T2 without changing text dispatch.
pub fn number(comptime Context: type, context: Context, operation_node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    return @import("build_number.zig").operation(Context, context, operation_node, ty, span);
}

/// Lower one checked text or bytes operation with the original evaluation order.
pub fn operation(comptime Context: type, context: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    if (node.kind == .hex or node.kind == .from_hex or node.kind == .blake3 or node.kind == .sha256) return @import("build_bytes.zig").octet(Context, context, node, ty, span);
    switch (node.kind) {
        .parse_int, .parse_int_range, .parse_float, .parse_float_range, .parse_f32, .number_format => return number(Context, context, node, ty, span),
        else => {},
    }
    if (more.handles(node.kind)) return more.operation(Context, context, node, ty, span);
    // Only operations with no span form reach this point with a borrowed view
    // receiver (`build_borrowed_view.handles`), so the octets are copied first
    // and the receiver and its type stay in step for every branch below.
    var receiver = try context.receiverOf(node.owner);
    // An operation with a span form reads the borrowed octets directly; only a
    // kind with no span form copies first (and `build_borrowed_view.handles` is
    // the one list of those).
    const span_form = @import("build_borrowed_view.zig").spanReceiver(node.kind, context.textReceiver(node.owner));
    if (context.typeOfRef(receiver).isSpan() and !span_form) receiver = try context.materializeOwned(node.owner, receiver, span);
    const receiver_type = context.typeOfRef(receiver);
    // A view receiver is still text (or bytes): the checked local's type says
    // which, because the SSA form of a text view is the same `str_view` a byte
    // view uses.
    const text = context.textReceiver(node.owner);
    switch (node.kind) {
        // Wave 3 phase 2: `len(text)` is its byte length, so it is the same load a
        // bytes value's length is. The scalar count stays behind the helper, which
        // is the `.length` node the checker gives `strings.char_count`.
        // A view is `{ptr, len}`: its length is the second field, which `str_len`
        // reads; only an owned byte block asks the header.
        // A bytes view's octets are its list length, the length the owned read's bounds facts use (C9 bytes).
        .length => return context.emit(.{ .op = if (text or receiver_type == .str_view) .str_len else .list_len, .ty = .u64, .a = receiver, .span = span }),
        .read => {
            const index = try context.expression(node.arguments[0]);
            if (!text) {
                const value = try context.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = index, .check = .exact, .span = span });
                return if (ty != .u8) context.emit(.{ .op = .convert, .ty = ty, .a = value, .span = span }) else value;
            }
            const offset = try context.effectCall(offset_symbol, &.{ .str, context.typeOfRef(index) }, .u64, &.{ receiver, index }, span);
            return context.emit(.{ .op = .str_char, .ty = .str, .a = receiver, .b = offset, .check = .exact, .span = span });
        },
        // The receiver's own type: a borrowed text takes the span form (C9 S1), an owned text keeps the block form.
        // `encode` names new octets: its copy is written (CX2). A view receiver takes the span form (build.zig).
        .encode => return context.markWritten(try context.effectCall(encode_symbol, &.{receiver_type}, .bytes, &.{receiver}, span)),
        .slice_step => {
            const start = try context.expression(node.arguments[0]);
            const end = try context.expression(node.arguments[1]);
            const step = try context.expression(node.arguments[2]);
            const nonzero = try context.emit(.{ .op = .cmp, .ty = .bool, .a = step, .b = try context.constant(.i64, 0), .data = @backingInt(ir.Predicate.ne), .span = span });
            try require(Context, context, nonzero, 13, span);
            // `strings.char_stride` names this copy (CLAUDE.md: the stepped copies), so the copy is written. A text view receiver
            // is passed as it is (`build_borrowed_view.spanReceiver`): the helper is declared on `str` and reads its first
            // argument as a view, and its result is an owned `str`.
            const owned: ir.Type = if (receiver_type == .str_view) .str else receiver_type;
            return context.markWritten(try context.runtimeCall(if (text) "myl_core_str_slice_step" else "myl_core_bytes_slice_step", &.{ owned, .i64, .i64, .i64 }, owned, &.{ receiver, start, end, step }, span));
        },
        .slice, .text_tail => {
            const start = try context.expression(node.arguments[0]);
            const end = try context.expression(node.arguments[1]);
            if (!text) return bufferSliceCopy(Context, context, receiver_type, .{ receiver, start, end }, span);
            // `text[start:end]` here is the scalar helper's copy.
            return context.emit(.{ .op = .str_slice, .ty = .str, .a = receiver, .b = start, .data = try context.extraSlice(&.{end}), .span = span });
        },
        .slice_bytes => {
            const start = try context.expression(node.arguments[0]);
            const end = try context.expression(node.arguments[1]);
            if (!text) return bufferSliceCopy(Context, context, receiver_type, .{ receiver, start, end }, span);
            // A borrowed text (a plain parameter) slices its octets as a view of the view, without a copy (C9 str), and its
            // endpoints are checked against the scalars exactly as an owned text's are: one inside a scalar traps
            // `R_TEXT_BOUNDARY` at this slice (FX8; from 07d555f724 to FX8 a view's slice skipped the check).
            if (receiver_type == .str_view) return context.runtimeCall("myl_core_view_slice_text", &.{ .str, .i64, .i64 }, .str_view, &.{ receiver, start, end }, span);
            return context.runtimeCall("myl_core_ir_str_slice_bytes", &.{ .str, .i64, .i64 }, .str, &.{ receiver, start, end }, span);
        },
        .find, .contains, .starts_with, .ends_with => {
            const needle = try context.expression(node.arguments[0]);
            if (!text and node.kind == .contains and context.typeOfRef(needle).integer() != null) {
                const value = if (context.typeOfRef(needle) == .i64) needle else try context.emit(.{ .op = .convert, .ty = .i64, .a = needle, .span = span });
                return context.runtimeCall("myl_core_bytes_contains_value", &.{ receiver_type, .i64 }, .bool, &.{ receiver, value }, span);
            }
            // A scalar find of a borrowed text reads through its cache owner (C9 S1), as the scalar search does.
            if (text and node.scalar and context.typeOfRef(receiver) == .str_view and node.kind == .find) {
                const search_mode = @import("selka").reference_tables.buffer_operations.Search.find;
                const found = try @import("build_text_more.zig").viewSearch(Context, context, receiver, needle, .{ try context.constant(.i64, 0), try context.constant(.i64, 9223372036854775807) }, search_mode, span);
                return if (ty == .i64) found else try context.emit(.{ .op = .convert, .ty = ty, .a = found, .span = span });
            }
            const symbol: []const u8 = switch (node.kind) {
                // C2: the method spelling answers in octets; only the scalar helper
                // (`node.scalar`) keeps the scalar index.
                .find => if (!text) "myl_core_bytes_find" else if (node.scalar) "myl_core_str_find" else "myl_core_str_find_byte",
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
            // A list view of parts is joined in place (C9 lists): the runtime reads the elements from the view.
            const view_parts = node.kind == .join and context.mb.module.kind(context.typeOfRef(argument)) == .list_view;
            const symbol = if (view_parts) flags.str_join_view_symbol else if (node.kind == .join) flags.str_join_symbol else splitSymbol(receiver_type, context.typeOfRef(argument));
            const call = try context.runtimeCall(symbol, &.{ receiver_type, context.typeOfRef(argument) }, ty, &.{ receiver, argument }, span);
            // `split` names new pieces: the runtime copies each one, and that copy is written (CX2).
            return if (node.kind == .split) context.markWritten(call) else call;
        },
        .parse_int, .parse_float, .parse_f32, .parse_int_range, .parse_float_range, .number_format, .hex, .from_hex, .float_round => return number(Context, context, node, ty, span),
        .split_whitespace => return context.markWritten(try context.effectCall("myl_core_str_split_whitespace", &.{receiver_type}, ty, &.{receiver}, span)),
        .to_list => return context.runtimeCall("myl_core_bytes_to_list", &.{receiver_type}, ty, &.{receiver}, span),
        .copy => return @import("single_owner_copy.zig").copy(Context, context, receiver, span),
        else => return context.mb.refuse(@tagName(node.kind), span),
    }
}

/// The octets `receiver[start:end]` of a bytes value as a new `bytes`, or of a `byte_buffer` as a new `byte_buffer` (FR27: the
/// checker types a buffer's slice a buffer, and a name that is written or passed on needs one). A buffer has no borrowed slice
/// (it can grow under a view, and the checker does not track a slice of one), so the slice expression is the copy and names
/// it: it is written. A comparison's operand and `bytes(...)` of the slice take it as `bytes` instead (`build.zig:
/// sliceAsViewOf`, `cast`), so they make no second copy. A bytes receiver's slice is rewritten to a borrowed view where it is
/// read (`sliceAsView`), so a copy made here for it stays an unwritten one that the hidden-copy check refuses.
fn bufferSliceCopy(comptime Context: type, context: Context, receiver_type: ir.Type, operands: [3]ir.Ref, span: u32) Error!ir.Ref {
    if (receiver_type == .byte_buffer) {
        return context.markWritten(try context.runtimeCall("myl_core_buffer_slice", &.{ .byte_buffer, .i64, .i64 }, .byte_buffer, &operands, span));
    }
    return context.runtimeCall("myl_core_bytes_slice", &.{ receiver_type, .i64, .i64 }, .bytes, &operands, span);
}

/// The runtime split for a receiver and separator: a `byte_buffer` operand has no span admission, so it takes the
/// block form, which reads the buffer's octets as the span form reads a text's (W13).
fn splitSymbol(receiver: ir.Type, separator: ir.Type) []const u8 {
    if (receiver == .byte_buffer or separator == .byte_buffer) return "myl_core_buffer_split";
    return "myl_core_str_split";
}

/// Validate the octet range before converting a list of integers to immutable bytes.
pub fn fromList(comptime Context: type, context: Context, source: ir.Type, operand: ir.Ref, span: u32) Error!ir.Ref {
    // A list view's integers are read in place by the span forms (C9 lists); a block takes the block forms.
    const view = context.mb.module.kind(source) == .list_view;
    const valid = try context.runtimeCall(if (view) "myl_core_span_bytes_valid_list" else "myl_core_bytes_valid_list", &.{source}, .bool, &.{operand}, span);
    try require(Context, context, valid, 14, span);
    return context.runtimeCall(if (view) "myl_core_span_bytes_from_list" else "myl_core_bytes_from_list", &.{source}, .bytes, &.{operand}, span);
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
    // Immutable octets use the existing static byte-literal layout. No writable
    // buffer or independently requested copy aliases this storage.
    return context.detached(.{ .op = .str_const, .ty = .bytes, .data = index, .span = span });
}

/// Index text or bytes with the written position; negative bits fail the bounds check.
pub fn indexed(comptime Context: type, context: Context, base: typed.NodeId, index_node: typed.NodeId, span: u32, result_type: ir.Type) Error!ir.Ref {
    const receiver = try context.expression(base);
    const receiver_type = context.typeOfRef(receiver);
    // A bytes view reads its octets as the owned read does, through the index offset adapter (C9 bytes).
    if (receiver_type == .bytes_view) return @import("build_borrowed_view.zig").indexed(Context, context, receiver, receiver, try context.expression(index_node), .{ .text = false, .result = result_type }, span);
    if (receiver_type.isSpan()) return viewByteIndex(Context, context, receiver, index_node, span, result_type);
    if (receiver_type != .str and receiver_type != .bytes and receiver_type != .byte_buffer) return context.mb.refuse("index receiver", span);
    const raw = try context.expression(index_node);
    const input_type = context.typeOfRef(raw);
    const selected = if (input_type == .u64 or input_type == .i64) raw else try context.emit(.{ .op = .convert, .ty = .i64, .a = raw, .span = span });
    const unsigned = context.typeOfRef(selected) == .u64;
    // Wave 3 phase 2: indexing a `str` is a byte read. The scalar read stays in
    // the `.read` operation, which is what `strings.char_at` lowers to.
    if (receiver_type == .str) {
        const byte_index = if (unsigned) try context.emit(.{ .op = .convert, .ty = .i64, .a = selected, .span = span }) else selected;
        // One unsigned compare catches a negative offset and one past the end, and
        // it carries the source location the runtime trap cannot.
        const length = try context.emit(.{ .op = .str_len, .ty = .u64, .a = receiver, .span = span });
        const unsigned_index = try context.emit(.{ .op = .convert, .ty = .u64, .a = byte_index, .span = span });
        const in_bounds = try context.emit(.{ .op = .cmp, .ty = .bool, .a = unsigned_index, .b = length, .data = @backingInt(ir.Predicate.lt), .span = span });
        try @import("text_checks.zig").requireLocated(Context, context, in_bounds, 11, span, byte_index, try context.emit(.{ .op = .convert, .ty = .i64, .a = length, .span = span }));
        return context.runtimeCall("myl_core_ir_str_byte", &.{ .str, .i64 }, .i64, &.{ receiver, byte_index }, span);
    }
    const offset = if (unsigned)
        selected
    else
        try context.effectCall("myl_core_bytes_index_offset", &.{ receiver_type, .i64 }, .u64, &.{ receiver, selected }, span);
    const value = try context.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = offset, .check = .exact, .span = span });
    return if (result_type != .u8) context.emit(.{ .op = .convert, .ty = result_type, .a = value, .span = span }) else value;
}

/// Index a borrowed text or byte span with the written position. The guard is the
/// same unsigned compare the owned text read makes, because the span load itself
/// is unchecked.
fn viewByteIndex(comptime Context: type, context: Context, receiver: ir.Ref, index_node: typed.NodeId, span: u32, result_type: ir.Type) Error!ir.Ref {
    const raw = try context.expression(index_node);
    const selected = if (context.typeOfRef(raw) == .u64 or context.typeOfRef(raw) == .i64) raw else try context.emit(.{ .op = .convert, .ty = .i64, .a = raw, .span = span });
    const index = if (context.typeOfRef(selected) == .u64) try context.emit(.{ .op = .convert, .ty = .i64, .a = selected, .span = span }) else selected;
    // A bytes view's length is its list length (C9 bytes), the same fact the owned read's loop bound proves.
    const length = try context.emit(.{ .op = if (context.typeOfRef(receiver) == .bytes_view) .list_len else .str_len, .ty = .u64, .a = receiver, .span = span });
    const unsigned_index = try context.emit(.{ .op = .convert, .ty = .u64, .a = index, .span = span });
    const in_bounds = try context.emit(.{ .op = .cmp, .ty = .bool, .a = unsigned_index, .b = length, .data = @backingInt(ir.Predicate.lt), .span = span });
    try @import("text_checks.zig").requireLocated(Context, context, in_bounds, 11, span, index, try context.emit(.{ .op = .convert, .ty = .i64, .a = length, .span = span }));
    const value = try context.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = unsigned_index, .check = .exact, .span = span });
    return if (result_type != .u8) context.emit(.{ .op = .convert, .ty = result_type, .a = value, .span = span }) else value;
}

/// Check a discarded text read without allocating its unobserved character result.
/// This applies to every discarded checked buffer read, including generated bounds guards.
pub fn discardedRead(comptime Context: type, context: Context, id: typed.NodeId, span: u32) Error!bool {
    const node = context.nodeOf(id);
    if (node.data != .buffer_operation or node.data.buffer_operation.kind != .read) return false;
    const operation_node = node.data.buffer_operation;
    const owner_type = context.checked.scope.locals[@backingInt(operation_node.owner)].ty;
    if (!owner_type.isAggregate() or context.mb.input.program.records[owner_type.recordIndex()].collection.kind != .string) return false;
    // Root the receiver before evaluating the index, just as the ordinary read does.
    const receiver = try context.receiverOf(operation_node.owner);
    const raw = try context.expression(operation_node.arguments[0]);
    if (context.current == null) return true;
    if (context.typeOfRef(receiver) == .str_view) {
        _ = try @import("build_borrowed_view.zig").checkedTextOffset(Context, context, try context.viewOwner(receiver), receiver, raw, span);
        return true;
    }
    // The receiver and index have already been evaluated; never fall back and
    // repeat them if an unsupported representation reaches this path.
    if (context.typeOfRef(receiver) != .str) return error.Unsupported;
    const ty = context.typeOfRef(raw);
    const index = if (ty == .i64 or ty == .u64) raw else try context.emit(.{ .op = .convert, .ty = .i64, .a = raw, .span = span });
    const offset = try context.effectCall(if (context.typeOfRef(index) == .u64) offset_symbol else "myl_core_str_index_offset", &.{ .str, context.typeOfRef(index) }, .u64, &.{ receiver, index }, span);
    _ = try context.emit(.{ .op = .str_code, .ty = .u32, .a = receiver, .b = offset, .check = .exact, .span = span });
    return true;
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
