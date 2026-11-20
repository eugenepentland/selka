//! Explicit nonowning text and byte spans in the zero-RC prototype.
const ir = @import("ir.zig");
const typed = @import("selka").typed;
const operations = @import("selka").reference_tables.buffer_operations;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");

/// Builder allocation and unsupported operation failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Borrow the entire physical octet range; source checking protects its owner.
pub fn whole(comptime B: type, b: B, source: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(source);
    if (ty.isSpan()) return source;
    const extent = try b.emit(.{ .op = if (ty == .str) .str_len else .list_len, .ty = .u64, .a = source, .span = span });
    return b.emit(.{ .op = .str_view_of, .ty = if (ty == .bytes) .bytes_view else .str_view, .a = source, .b = try b.constant(.u64, 0), .data = try b.extraSlice(&.{extent}), .span = span });
}

/// The cache owner of borrowed text `source` (C9 S1): an owned text is its own owner, a view its parameter's
/// frame header or the sentinel (`FnBuilder.viewOwner`).
pub fn cacheOwner(comptime B: type, b: B, source: ir.Ref) Error!ir.Ref {
    // A bytes value or view has no cached facts: its own value stands for the owner, unread.
    const ty = b.typeOfRef(source);
    if (ty == .str or ty == .bytes or ty == .bytes_view) return source;
    return b.viewOwner(source);
}

/// The scalar count of the text `value`, read through its cache owner (`myl_core_xc_chars`).
pub fn chars(comptime B: type, b: B, owner: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
    return b.runtimeCall("myl_core_xc_chars", &.{ .str, .str_view }, .i64, &.{ owner, value }, span);
}

/// Scalar length preserves text's Unicode indexing and bytes' octet indexing.
pub fn length(comptime B: type, b: B, owner: ir.Ref, value: ir.Ref, text: bool, span: u32) Error!ir.Ref {
    if (text) return chars(B, b, owner, value, span);
    const size = try b.emit(.{ .op = if (b.typeOfRef(value) == .bytes_view) .list_len else .str_len, .ty = .u64, .a = value, .span = span });
    return b.emit(.{ .op = .convert, .ty = .i64, .a = size, .check = .exact, .span = span });
}

/// The element a text or bytes index reads: text is an owned character, bytes an octet.
pub const Element = struct { text: bool, result: ir.Type };

/// An indexed character is an owned string; an indexed byte is a scalar.
pub fn indexed(comptime B: type, b: B, owner: ir.Ref, value: ir.Ref, index: ir.Ref, element: Element, span: u32) Error!ir.Ref {
    const result = element.result;
    const source_type = b.typeOfRef(index);
    const raw = if (source_type == .i64 or source_type == .u64) index else try b.emit(.{ .op = .convert, .ty = .i64, .a = index, .span = span });
    if (!element.text) {
        // A signed index takes the span form of the owned read's offset (`myl_core_bytes_index_offset`), so the vector
        // planner sees the same shape for a bytes view (C9 bytes). The list read keeps the bounds check.
        const offset = if (b.typeOfRef(raw) == .u64) raw else try b.effectCall("myl_core_span_bytes_index_offset", &.{ .str, .i64 }, .u64, &.{ value, raw }, span);
        const got = try b.emit(.{ .op = .list_get, .ty = .u8, .a = value, .b = offset, .check = .exact, .span = span });
        return if (result == .u8) got else b.emit(.{ .op = .convert, .ty = result, .a = got, .span = span });
    }
    const offset = try checkedTextOffset(B, b, owner, value, raw, span);
    const got = try b.runtimeCall("myl_core_view_char", &.{ .str, .u64 }, .str, &.{ value, offset }, span);
    return if (b.typeOfRef(got) == result) got else b.emit(.{ .op = .convert, .ty = result, .a = got, .span = span });
}

/// Check a text-view position while preserving the written index on a failed access.
/// The offset can be discarded without constructing an owned character.
pub fn checkedTextOffset(comptime B: type, b: B, owner: ir.Ref, value: ir.Ref, index: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(index);
    const raw = if (ty == .i64 or ty == .u64) index else try b.emit(.{ .op = .convert, .ty = .i64, .a = index, .span = span });
    const wide = if (ty == .u64) try b.runtimeCall("myl_core_text_bound", &.{.u64}, .i64, &.{raw}, span) else raw;
    const offset = try b.runtimeCall("myl_core_xc_index", &.{ .str, .str_view, .i64 }, .u64, &.{ owner, value, wide }, span);
    const size = try b.emit(.{ .op = .str_len, .ty = .u64, .a = value, .span = span });
    const valid = try b.emit(.{ .op = .cmp, .ty = .bool, .a = offset, .b = size, .data = @backingInt(ir.Predicate.lt), .span = span });
    try requireIndex(B, b, valid, .{ .index = wide, .view = value, .owner = owner }, span);
    return offset;
}

/// The written index, borrowed source and its cache owner of one failed text access.
const IndexFailure = struct { index: ir.Ref, view: ir.Ref, owner: ir.Ref };

/// Preserve the original negative position and scalar length on the cold trap path.
fn requireIndex(comptime B: type, b: B, valid: ir.Ref, failure: IndexFailure, span: u32) Error!void {
    const good = try b.newBlock();
    const bad = try b.newBlock();
    try b.branch(valid, good, bad, span);
    try b.seal(bad);
    b.current = bad;
    const count = try length(B, b, failure.owner, failure.view, true, span);
    _ = try b.emit(.{ .op = .@"unreachable", .ty = .void, .a = failure.index, .b = count, .data = @import("flags.zig").text_trap | 11, .span = span });
    try b.seal(good);
    b.current = good;
}

/// Whether the span forms cover this operation; anything else copies the borrowed
/// octets first (`FnBuilder.materializeAs`).
pub fn handles(kind: @FieldType(Operation, "kind")) bool {
    return switch (kind) {
        .borrow_view, .slice, .text_tail, .length, .copy, .read => true,
        else => false,
    };
}

/// Whether the text operation `kind` on a borrowed receiver is lowered with the receiver's own span:
/// its runtime helper reads each text argument as `(data, length)` (a span form, or a sentinel-owner
/// form), so the receiver is passed as the view and no owned copy of it is made (C9). `text` says the
/// receiver is text, not bytes. `dispatch` still answers only `handlesOn`, the operations this file lowers.
pub fn spanReceiver(kind: @FieldType(Operation, "kind"), text: bool) bool {
    if (handlesOn(kind, text)) return true;
    if (!text) return bytesSpanned(kind);
    if (operations.trim(kind) != null or operations.search(kind) != null) return true;
    return switch (kind) {
        .starts_with, .ends_with, .find, .encode, .blake3, .from_hex, .upper, .lower, .replace, .split, .split_whitespace, .join, .contains, .text_repr, .slice_bytes => true,
        // The numeric parses of text read a view in place, `parse_f32` too (FR28: a copy made before its span form was
        // read left an unnamed copy that nothing used but its drop: `E_CORE_HIDDEN_COPY`).
        .parse_int, .parse_int_range, .parse_float, .parse_float_range, .parse_f32 => true,
        // The SHA-256 of a view reads its span like the BLAKE3 one.
        .sha256 => true,
        // The three predicates call `myl_core_span_text_every` on a view (F20); they are text-only (`sema_collections`).
        // `ord` counts the scalars of a view in place and decodes the first from its span (`myl_core_span_text_ord`).
        .is_digit, .is_alpha, .is_space, .text_ord => true,
        // `strings.lines` and `zfill` read the receiver's span with a sentinel owner (lane HC): a view is never copied for them.
        .splitlines, .zfill => true,
        // `strings.char_stride` copies the scalars it keeps; its helper reads the receiver as a view (`zero_rc`'s contract,
        // `views = 1`), so a view receiver is passed as it is. Before N5 lowering copied the view first and a pass then handed
        // the helper the view itself, which left that first copy unwritten and dropped: a hidden copy of the whole text.
        .slice_step => true,
        else => false,
    };
}

/// The bytes operations whose helper has a span form (C9 bytes): a bytes view receiver is read in place by them.
fn bytesSpanned(kind: @FieldType(Operation, "kind")) bool {
    if (operations.trim(kind) != null or operations.search(kind) != null) return true;
    return switch (kind) {
        .find, .find_any, .find_any_range, .contains, .starts_with, .ends_with, .hex, .blake3, .sha256, .decode, .scalar_count, .scalar_count_range, .text_repr, .to_list => true,
        .split, .join, .split_whitespace => true,
        .parse_int, .parse_int_range, .parse_float, .parse_float_range => true,
        else => false,
    };
}

/// `handles` for an operation on a receiver of the given family. An octet slice of text borrows
/// its octets (`myl_core_view_slice` with octet offsets); a bytes slice has no span form yet.
pub fn handlesOn(kind: @FieldType(Operation, "kind"), text: bool) bool {
    _ = text;
    return handles(kind);
}

/// Lower only audited span operations; no implicit materialization is allowed.
pub fn operation(comptime B: type, b: B, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    const source_type = b.checked.scope.locals[@backingInt(node.owner)].ty;
    const text = b.mb.input.program.records[source_type.recordIndex()].collection.kind == .string;
    const source = try b.receiverOf(node.owner);
    const value = try whole(B, b, source, span);
    switch (node.kind) {
        .borrow_view, .slice, .text_tail => {
            const first = try b.expression(node.arguments[0]);
            const last = try b.expression(node.arguments[1]);
            const start = if (b.typeOfRef(first) == .i64) first else try b.emit(.{ .op = .convert, .ty = .i64, .a = first, .check = .exact, .span = span });
            const end = if (b.typeOfRef(last) == .i64) last else try b.emit(.{ .op = .convert, .ty = .i64, .a = last, .check = .exact, .span = span });
            // Scalar endpoints of text are looked up through the source's cache owner (C9 S1).
            if (text) return b.runtimeCall("myl_core_xc_slice", &.{ .str, .str_view, .i64, .i64 }, .str_view, &.{ try cacheOwner(B, b, source), value, start, end }, span);
            // A bytes slice borrows its octets too: the same helper with octet endpoints (C9 bytes).
            return b.runtimeCall("myl_core_view_slice", &.{ .bytes, .i64, .i64, .bool }, .bytes_view, &.{ value, start, end, try b.constant(.bool, 0) }, span);
        },
        // `len(view)` is the octet length of the view (CLAUDE.md: `len(text)` reads octets). The scalar count
        // (`strings.char_count`) is the typed length node, which `build.stringLength` answers in scalars.
        .length => return length(B, b, if (text) try cacheOwner(B, b, source) else value, value, false, span),
        // The `copy(value)` of a view: its owned copy is written (`flags.written_copy`).
        // A text view copies through the `str_from_view` op, so the copy elision of the key and slice fusions sees it.
        .copy => if (text) return b.markWritten(try b.materializeAs(value, .text, span)) else return b.markWritten(try b.runtimeCall("myl_core_view_copy_bytes", &.{.bytes_view}, ty, &.{value}, span)),
        .read => return indexed(B, b, try cacheOwner(B, b, source), value, try b.expression(node.arguments[0]), .{ .text = text, .result = ty }, span),
        else => return b.mb.refuse("this borrowed-view operation", span),
    }
}

/// Optional dispatch keeps the main collection builder independent of view APIs.
pub fn dispatch(comptime B: type, b: B, node: Operation, ty: ir.Type, receiver: ir.Type, span: u32) Error!?ir.Ref {
    if (node.kind != .borrow_view and !receiver.isSpan()) return null;
    // The caller copies the borrowed octets for an operation with no span form.
    if (!handlesOn(node.kind, b.textReceiver(node.owner))) return null;
    const result = try operation(B, b, node, ty, span);
    return result;
}
