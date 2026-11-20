//! S3 text methods borrow inputs and return independent, counted results.
const ir = @import("ir.zig");
const typed = @import("selka").typed;
const operations = @import("selka").reference_tables.buffer_operations;
const require = @import("text_checks.zig").require;
const build_view = @import("build_borrowed_view.zig");
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");

/// Allocation and precise feature refusals are the text builder's failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Identify methods implemented by the S3 borrowed text helper family.
pub fn handles(kind: operations.Kind) bool {
    if (operations.search(kind) != null) return kind != .find and kind != .starts_with and kind != .ends_with;
    if (operations.trim(kind) != null) return true;
    return switch (kind) {
        .upper, .lower, .is_digit, .is_alpha, .is_space, .replace, .splitlines, .zfill, .text_chr, .text_ord, .text_repr, .text_format, .find_any, .find_any_range, .view, .decode, .scalar_count, .scalar_count_range => true,
        else => false,
    };
}

/// Lower one additional checked method without changing the S2 hot helpers.
pub fn operation(comptime Context: type, b: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    const receiver = try b.receiverOf(node.owner);
    const receiver_type = b.typeOfRef(receiver);
    const text = b.textReceiver(node.owner);
    if (operations.search(node.kind)) |mode| return search(Context, b, receiver, node, .{ .result = ty, .span = span, .mode = mode });
    if (operations.trim(node.kind)) |ends| return trim(Context, b, receiver, node, span, ends);
    switch (node.kind) {
        // A view receiver's case is a new owned text (C9 str): its result is `str`, not the view's type.
        .upper, .lower => return b.runtimeCall("myl_core_text_case", &.{ receiver_type, .bool }, ownedResult(receiver_type), &.{ receiver, try b.constant(.bool, @intFromBool(node.kind == .upper)) }, span),
        .is_digit, .is_alpha, .is_space => return b.runtimeCall("myl_core_text_every", &.{ receiver_type, .i32 }, .bool, &.{ receiver, try b.constant(.i32, switch (node.kind) {
            .is_digit => 0,
            .is_alpha => 1,
            else => 2,
        }) }, span),
        .text_chr => return character(Context, b, try b.expression(node.arguments[0]), span),
        .text_ord => {
            // A borrowed text counts its scalars in place and decodes from its span (F20); an owned one keeps the block form.
            const length = if (receiver_type == .str_view) try b.viewScalarCount(receiver, span) else try b.stringChars(receiver, span);
            try require(Context, b, try compare(Context, b, length, try b.constant(.u64, 1), .eq, span), 15, span);
            return b.runtimeCall("myl_core_text_ord", &.{receiver_type}, .i64, &.{receiver}, span);
        },
        // The flag is the family: bytes spell `b'...'` (C9 bytes: a bytes view takes the span form of the same helper).
        .text_repr => return b.runtimeCall("myl_core_text_repr", &.{ receiver_type, .bool }, .str, &.{ receiver, try b.constant(.bool, @intFromBool(!text)) }, span),
        .text_format => {
            const word = try b.expression(node.arguments[0]);
            return b.runtimeCall("myl_core_text_format", &.{ .str, b.typeOfRef(word) }, .str, &.{ receiver, word }, span);
        },
        .splitlines => return b.runtimeCall("myl_core_text_splitlines", &.{receiver_type}, ty, &.{receiver}, span),
        // A view receiver's padded text is a new owned text (C9 str), as upper and lower are.
        .zfill => return b.runtimeCall("myl_core_text_zfill", &.{ receiver_type, .i64 }, ownedResult(receiver_type), &.{ receiver, try bound(Context, b, node.arguments[0], span) }, span),
        .replace => {
            const needle = try b.expression(node.arguments[0]);
            const insert = try b.expression(node.arguments[1]);
            // The needle's length is its octets for text (a view or an owned text alike), its elements for bytes.
            const length = try b.emit(.{ .op = if (b.textReceiver(node.owner)) .str_len else .list_len, .ty = .u64, .a = needle, .span = span });
            try require(Context, b, try compare(Context, b, length, try b.constant(.u64, 0), .ne, span), 12, span);
            return b.runtimeCall("myl_core_text_replace", &.{ receiver_type, b.typeOfRef(needle), b.typeOfRef(insert) }, ty, &.{ receiver, needle, insert }, span);
        },
        .find_any, .find_any_range => {
            const needle = try b.expression(node.arguments[0]);
            const start = try bound(Context, b, node.arguments[1], span);
            const end = if (node.kind == .find_any_range) try bound(Context, b, node.arguments[2], span) else try b.constant(.i64, 9223372036854775807);
            return b.runtimeCall("myl_core_bytes_find_any", &.{ receiver_type, b.typeOfRef(needle), .i64, .i64 }, .i64, &.{ receiver, needle, start, end }, span);
        },
        .view => return b.runtimeCall("myl_core_bytes_slice", &.{ receiver_type, .i64, .i64 }, .bytes, &.{ receiver, try bound(Context, b, node.arguments[0], span), try bound(Context, b, node.arguments[1], span) }, span),
        .decode, .scalar_count, .scalar_count_range => return decoded(Context, b, receiver, node, ty, span),
        else => return b.mb.refuse(@tagName(node.kind), span),
    }
}

/// A scalar search over borrowed text `receiver` through its cache owner (C9 S1, `myl_core_xc_search`): the owner
/// is the receiver's frame or sentinel, the needle is a span, and the sentinel stands for the needle's block.
/// `range` holds the start and end octets of the search.
pub fn viewSearch(comptime Context: type, b: Context, receiver: ir.Ref, needle: ir.Ref, range: [2]ir.Ref, mode: anytype, span: u32) Error!ir.Ref {
    const owner = try b.viewOwner(receiver);
    const sentinel = try b.detached(.{ .op = .text_sentinel, .ty = .str });
    const needle_view = try build_view.whole(Context, b, needle, span);
    const mode_value = try b.constant(.i32, @as(i64, @intCast(@backingInt(mode))));
    return b.runtimeCall("myl_core_xc_search", &.{ .str, .str_view, .str, .str_view, .i64, .i64, .i32 }, .i64, &.{ owner, receiver, sentinel, needle_view, range[0], range[1], mode_value }, span);
}

const SearchSite = struct { result: ir.Type, span: u32, mode: operations.Search };

fn search(comptime Context: type, b: Context, receiver: ir.Ref, node: Operation, site: SearchSite) Error!ir.Ref {
    const receiver_type = b.typeOfRef(receiver);
    const needle = try b.expression(node.arguments[0]);
    const start = if (node.arguments.len > 1) try bound(Context, b, node.arguments[1], site.span) else try b.constant(.i64, 0);
    const end = if (node.arguments.len > 2) try bound(Context, b, node.arguments[2], site.span) else try b.constant(.i64, 9223372036854775807);
    const mode = try b.constant(.i32, @backingInt(site.mode));
    // C2: the method spelling takes and answers byte offsets, and an endpoint
    // inside a scalar traps R_TEXT_BOUNDARY; a scalar helper keeps the scalar
    // window and answer through `myl_core_text_search`.
    // A borrowed receiver is text or bytes by its checked owner (both are `str_view` in SSA), never by its type.
    const symbol = if (!b.textReceiver(node.owner)) "myl_core_bytes_search" else if (node.scalar) "myl_core_text_search" else "myl_core_text_search_bytes";
    // A scalar search of a borrowed text reads its scalar positions through the receiver's cache owner (C9 S1).
    const result = if (receiver_type == .str_view and node.scalar and b.textReceiver(node.owner))
        try viewSearch(@TypeOf(b), b, receiver, needle, .{ start, end }, site.mode, site.span)
    else
        try b.runtimeCall(symbol, &.{ receiver_type, b.typeOfRef(needle), .i64, .i64, .i32 }, .i64, &.{ receiver, needle, start, end, mode }, site.span);
    if (site.mode == .index or site.mode == .rindex) try require(Context, b, try compare(Context, b, result, try b.constant(.i64, 0), .ge, site.span), 16, site.span);
    return if (site.result == .bool) compare(Context, b, result, try b.constant(.i64, 0), .ne, site.span) else result;
}

fn trim(comptime Context: type, b: Context, receiver: ir.Ref, node: Operation, span: u32, ends: u2) Error!ir.Ref {
    const receiver_type = b.typeOfRef(receiver);
    // The receiver is text or bytes by its checked owner: a bytes view is `str_view` too (D-2b-5).
    const text = b.textReceiver(node.owner);
    // A text trim without a character set borrows the octets it keeps (C7): the
    // result is a view of the receiver, so the call allocates nothing.
    if (node.arguments.len == 0 and text) {
        return b.runtimeCall("myl_core_text_trim_view", &.{ receiver_type, .i32 }, .str_view, &.{ receiver, try b.constant(.i32, ends) }, span);
    }
    const chars = if (node.arguments.len != 0) try b.expression(node.arguments[0]) else receiver;
    // A text set or receiver that is a view takes the span form (C9 2b); an owned text keeps the block form, so its call is main's.
    const symbol = if (!text) "myl_core_bytes_trim" else if (receiver_type == .str_view or b.typeOfRef(chars) == .str_view) "myl_core_text_trim_span" else "myl_core_text_trim";
    const direction = try b.constant(.i32, ends);
    const explicit = try b.constant(.bool, @intFromBool(node.arguments.len != 0));
    // A bytes trim and a trim with a character set name new storage: the checker holds their result owned
    // (`single_owner.textTrimBorrow`), as `bytes.strip`'s signature (`-> bytes`, no `from`) says. The runtime's copy is
    // that new value, so it is written (rule C), as `split` and `encode` are. A trim whose result is only read still
    // borrows its octets (`fuse_slice_key`, CX-4), and the mark carries over to any copy that view later needs.
    return b.markWritten(try b.runtimeCall(symbol, &.{ receiver_type, b.typeOfRef(chars), .i32, .bool }, ownedResult(receiver_type), &.{ receiver, chars, direction, explicit }, span));
}

/// The type of a fresh owned result of a text operation on `receiver_type`: a view's result is owned `str`.
fn ownedResult(receiver_type: ir.Type) ir.Type {
    return switch (receiver_type) {
        .str_view => .str,
        .bytes_view => .bytes,
        else => receiver_type,
    };
}

fn character(comptime Context: type, b: Context, input: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(input);
    const code = if (ty == .i64 or ty == .u64) input else try b.emit(.{ .op = .convert, .ty = .i64, .a = input, .span = span });
    const valid = try b.runtimeCall("myl_core_text_scalar_valid", &.{b.typeOfRef(code)}, .bool, &.{code}, span);
    try require(Context, b, valid, 15, span);
    return b.runtimeCall("myl_core_text_chr", &.{b.typeOfRef(code)}, .str, &.{code}, span);
}

fn compare(comptime Context: type, b: Context, left: ir.Ref, right: ir.Ref, predicate: ir.Predicate, span: u32) Error!ir.Ref {
    return b.emit(.{ .op = .cmp, .ty = .bool, .a = left, .b = right, .data = @backingInt(predicate), .span = span });
}

/// Normalize a Python bound, saturating unsigned words instead of wrapping to negative.
pub fn bound(comptime Context: type, b: Context, node: typed.NodeId, span: u32) Error!ir.Ref {
    const input = try b.expression(node);
    const ty = b.typeOfRef(input);
    if (ty == .i64) return input;
    if (ty != .u64) return b.emit(.{ .op = .convert, .ty = .i64, .a = input, .span = span });
    return b.runtimeCall("myl_core_text_bound", &.{.u64}, .i64, &.{input}, span);
}

fn decoded(comptime Context: type, b: Context, input: ir.Ref, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    if (node.kind != .scalar_count_range) return checkedDecode(Context, b, input, ty, node.kind == .decode, span);
    const count = try b.runtimeCall("myl_core_bytes_utf8_count_range", &.{ b.typeOfRef(input), .i64, .i64 }, .i64, &.{ input, try bound(Context, b, node.arguments[0], span), try bound(Context, b, node.arguments[1], span) }, span);
    return decodeResult(Context, b, .{ .receiver = input, .ty = ty, .text = false, .count = count, .span = span });
}

/// Construct the built-in Result from one validation result, with a located error origin.
pub fn checkedDecode(comptime Context: type, b: Context, receiver: ir.Ref, ty: ir.Type, text: bool, span: u32) Error!ir.Ref {
    const count = try b.effectCall("myl_core_bytes_utf8_count", &.{b.typeOfRef(receiver)}, .i64, &.{receiver}, span);
    return decodeResult(Context, b, .{ .receiver = receiver, .ty = ty, .text = text, .count = count, .span = span });
}

const DecodeSite = struct { receiver: ir.Ref, ty: ir.Type, text: bool, count: ir.Ref, span: u32 };

fn decodeResult(comptime Context: type, b: Context, site: DecodeSite) Error!ir.Ref {
    const receiver = site.receiver;
    const ty = site.ty;
    const text = site.text;
    const count = site.count;
    const span = site.span;
    const good = try b.newBlock();
    const bad = try b.newBlock();
    const join = try b.newBlock();
    const slot = try b.synthetic(ty);
    try b.branch(try compare(Context, b, count, try b.constant(.i64, 0), .ge, span), good, bad, span);
    try b.seal(good);
    try b.seal(bad);
    b.current = good;
    const value = if (!text) count else try b.effectCall("myl_core_bytes_decode_text", &.{b.typeOfRef(receiver)}, .str, &.{receiver}, span);
    try b.write(slot, good, try b.emit(.{ .op = .union_make, .ty = ty, .a = value, .data = 0, .span = span }));
    try b.jump(join);
    b.current = bad;
    // A fixed validation message needs no managed backing, including this cold
    // failure path. Pool it exactly like source string literals.
    const message_index = b.mb.module.strings.items.len;
    try b.mb.module.strings.append(b.allocator(), "invalid UTF-8 in byte string");
    const message = try b.emit(.{ .op = .str_const, .ty = .str, .data = message_index, .span = span });
    try b.write(slot, bad, try b.emit(.{ .op = .union_make, .ty = ty, .a = message, .data = 1, .span = span }));
    _ = try b.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.runtime), .span = span });
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(slot, join);
}
