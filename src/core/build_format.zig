//! `PY-FSTRING-1`: an `f"..."` literal reaches Core as its pieces, and lowers
//! once for each way a program uses it, with a direct path per hole kind.
//! - Printing or writing one writes each piece in order, straight to the stream:
//!   a literal is one static block, a plain scalar or text hole is one helper
//!   call, and only a hole with a written specification goes through the
//!   specification renderer. Nothing is joined and nothing allocates.
//! - Using one as a `str` reserves one text buffer from the pieces' lengths and
//!   bounds and fills it in place, so the whole string costs one allocation and a
//!   plain hole is rendered once.
//! - `print` discards the count `write` answers, so it asks for none: a literal's
//!   scalars are a compile-time constant and a plain hole's are the length its
//!   own spelling returns.
//! A hole whose own rendering allocates today (a record, a list, a union or an
//! option) still renders through `myl_core_show_*`, but its text is written or
//! appended directly instead of joining pieces.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("selka").typed;

/// Allocation and a hole with no rendering stop the format builder.
pub const Error = error{ OutOfMemory, Unsupported };

/// The renderer one hole selects, in `myl_core_format_*`'s order.
pub const Kind = enum(u32) { signed, unsigned, float_spec, text_spec, float_plain, text_raw, octets, boolean };

/// One hole, evaluated: which rendering reads it, the value or the text it
/// reads, and the specification word the source gave it.
pub const Hole = struct {
    kind: Kind,
    /// A written specification keeps the general renderer for this hole; every
    /// other kind takes one of the direct paths below.
    specified: bool = false,
    /// The value: an integer's bits (the signed reading for a signed kind), a
    /// plain float as the `f64` itself, a boolean as its `bool`, or a binary64
    /// pattern for a specified float. `.none` for a text or byte hole.
    bits: ir.Ref = .none,
    /// A written specification's packed word, unused by a plain rendering.
    word: u64 = 0,
    /// The text a text, byte or literal hole reads; `.none` for a scalar.
    text: ir.Ref = .none,
};

/// A format string whose holes are all evaluated, in source order, before any
/// piece is written, so a hole's side effects keep their source order.
pub const Prepared = struct { pieces: []const typed.FormatPiece, holes: []const Hole };

/// The widest decimal spelling a plain signed hole can have.
const signed_bound: u64 = 21; // "-9223372036854775808" is 20; one spare
/// The widest decimal spelling a plain unsigned hole can have.
const unsigned_bound: u64 = 20; // "18446744073709551615"
/// The widest spelling a plain float hole can have.
const float_bound: u64 = 32; // a shortest decimal with a signed exponent
/// "False" is the longest boolean spelling.
const boolean_bound: u64 = 5;

/// The declaration of one hole renderer: a stream, the renderer, its bits, its
/// specification word, and the text span it reads, which crosses by value.
fn params(text: ir.Type) [5]ir.Type {
    return .{ .cap, .u32, .u64, .u64, text };
}

/// Evaluate every hole of `format` in source order, and keep the pieces to write.
pub fn evaluate(comptime Context: type, c: Context, format: typed.Format, span: u32) Error!Prepared {
    var count: usize = 0;
    for (format.pieces) |piece| {
        if (piece == .hole) count += 1;
    }
    const holes = try c.allocator().alloc(Hole, count);
    var next: usize = 0;
    for (format.pieces) |piece| switch (piece) {
        .literal => {},
        .hole => |hole| {
            holes[next] = try evaluateHole(Context, c, hole, span);
            next += 1;
        },
    };
    return .{ .pieces = format.pieces, .holes = holes };
}

/// Write every piece of `prepared` to `stream` in order, for a `print` that
/// discards the scalar count: no piece is counted and no text is scanned.
pub fn print(comptime Context: type, c: Context, prepared: Prepared, stream: ir.Ref, span: u32) Error!ir.Ref {
    return streamPieces(Context, c, prepared, .{ .stream = stream, .span = span, .count = false });
}

/// Write every piece of `prepared` to `stream` in order, with no text buffer, and
/// answer how many Unicode scalars it wrote: the count `write` returns.
pub fn write(comptime Context: type, c: Context, prepared: Prepared, stream: ir.Ref, span: u32) Error!ir.Ref {
    return streamPieces(Context, c, prepared, .{ .stream = stream, .span = span, .count = true });
}

/// One stream write in progress: the descriptor, the span every piece is
/// credited to, and whether the caller needs the scalar count.
const Sink = struct { stream: ir.Ref, span: u32, count: bool };

/// Write the pieces in order, summing each piece's scalar count when asked.
fn streamPieces(comptime Context: type, c: Context, prepared: Prepared, sink: Sink) Error!ir.Ref {
    var scalars: ir.Ref = .none;
    if (sink.count) scalars = try c.constant(.u64, 0);
    var next: usize = 0;
    for (prepared.pieces) |piece| switch (piece) {
        .literal => |bytes| {
            if (bytes.len == 0) continue;
            _ = try c.effectCall("myl_core_print_str", &.{ .cap, .str }, .void, &.{ sink.stream, try literal(Context, c, bytes, sink.span) }, sink.span);
            if (sink.count) scalars = try addConstant(Context, c, scalars, scalarCount(bytes), sink.span);
        },
        .hole => {
            const written = try writeHole(Context, c, prepared.holes[next], sink);
            next += 1;
            if (sink.count) scalars = try c.emit(.{ .op = .add, .ty = .u64, .a = scalars, .b = written, .span = sink.span });
        },
    };
    return scalars;
}

/// `sum` plus a compile-time count, or `sum` itself when that count is zero.
fn addConstant(comptime Context: type, c: Context, sum: ir.Ref, value: u64, span: u32) Error!ir.Ref {
    if (value == 0) return sum;
    return c.emit(.{ .op = .add, .ty = .u64, .a = sum, .b = try c.constant(.u64, value), .span = span });
}

/// How many Unicode scalars a literal piece holds: its `write` count is fixed
/// when the program is built, so no piece is ever counted at run time.
fn scalarCount(bytes: []const u8) u64 {
    const scalars = std.unicode.utf8CountCodepoints(bytes) catch return @intCast(bytes.len);
    return @intCast(scalars);
}

/// Build `format` as one `str`: one allocation, each piece written in place.
pub fn string(comptime Context: type, c: Context, format: typed.Format, span: u32) Error!ir.Ref {
    const prepared = try evaluate(Context, c, format, span);
    if (prepared.holes.len == 0) return literal(Context, c, try constantText(c, format.pieces), span);
    var text = try c.runtimeCall("myl_core_str_reserve", &.{.u64}, .str, &.{try capacity(Context, c, prepared, span)}, span);
    var next: usize = 0;
    for (format.pieces) |piece| switch (piece) {
        .literal => |bytes| {
            if (bytes.len == 0) continue;
            text = try appendLiteral(Context, c, bytes, text, span);
        },
        .hole => {
            text = try appendHole(Context, c, prepared.holes[next], text, span);
            next += 1;
        },
    };
    return text;
}

/// The one reservation a stored format string makes: every literal's octets, a
/// fixed upper bound for each plain scalar hole (so it renders once, never to be
/// measured), and the exact measure a text, byte or specified hole reports.
fn capacity(comptime Context: type, c: Context, prepared: Prepared, span: u32) Error!ir.Ref {
    var fixed: u64 = literalLen(prepared.pieces);
    var runtime: ?ir.Ref = null;
    for (prepared.holes) |hole| {
        if (!hole.specified) switch (hole.kind) {
            .signed => {
                fixed += signed_bound;
                continue;
            },
            .unsigned => {
                fixed += unsigned_bound;
                continue;
            },
            .float_plain => {
                fixed += float_bound;
                continue;
            },
            .boolean => {
                fixed += boolean_bound;
                continue;
            },
            else => {},
        };
        const measured = try measure(Context, c, hole, span);
        runtime = if (runtime) |sum| try c.emit(.{ .op = .add, .ty = .u64, .a = sum, .b = measured, .span = span }) else measured;
    }
    const base = try c.constant(.u64, fixed);
    return if (runtime) |dynamic| c.emit(.{ .op = .add, .ty = .u64, .a = base, .b = dynamic, .span = span }) else base;
}

/// How many octets one hole adds to a stored format string.
fn measure(comptime Context: type, c: Context, hole: Hole, span: u32) Error!ir.Ref {
    if (!hole.specified) switch (hole.kind) {
        .text_raw => return c.emit(.{ .op = .str_len, .ty = .u64, .a = hole.text, .span = span }),
        .octets => return c.runtimeCall("myl_core_format_octets_len", &.{.str}, .u64, &.{hole.text}, span),
        else => {},
    };
    const source_text = try holeText(Context, c, hole, span);
    const declared = params(textParam(c.typeOfRef(source_text)));
    return c.runtimeCall("myl_core_format_len", declared[1..], .u64, &.{
        try c.constant(.u32, @backingInt(hole.kind)),
        try holeBits(Context, c, hole, span),
        try c.constant(.u64, hole.word),
        source_text,
    }, span);
}

/// One evaluated hole: its renderer and the value it reads.
fn evaluateHole(comptime Context: type, c: Context, hole: typed.FormatHole, span: u32) Error!Hole {
    const value = try c.expression(hole.value);
    const source = c.nodeOf(hole.value).ty;
    // A binary32 value rendered under a written specification takes its own shortest digits, so the
    // specified text is made here, where the value's width is known, and the hole carries the text.
    if (hole.spec) |spec| if (spec.family == .float and c.typeOfRef(value) == .f32) return .{
        .kind = .text_raw,
        .text = try c.runtimeCall("myl_core_format_float32", &.{ .f32, .u64 }, .str, &.{ value, try c.constant(.u64, spec.word) }, span),
    };
    if (hole.spec) |spec| return .{
        .kind = switch (spec.family) {
            .signed => .signed,
            .unsigned => .unsigned,
            .float => .float_spec,
            .text => .text_spec,
        },
        .specified = true,
        .bits = try bitsOf(Context, c, value, spec.family, span),
        .word = spec.word,
        .text = if (spec.family == .text) value else .none,
    };
    // No specification: the value's own `print` spelling, which is what an
    // interpolation has always rendered.
    if (value == .none or source == .unit) return .{ .kind = .text_raw, .text = try literal(Context, c, "None", span) };
    const physical = c.typeOfRef(value);
    if (c.renderDomain(source)) return .{ .kind = .text_raw, .text = try c.textOf(value, source, span) };
    if (physical == .bool) return .{ .kind = .boolean, .bits = value };
    // A plain float crosses as the `f64` itself, so its spelling needs no round
    // trip through the bits a specified float renders from.
    if (physical == .f64) return .{ .kind = .float_plain, .bits = value };
    if (physical == .f32) return .{ .kind = .text_raw, .text = try c.textOf(value, source, span) };
    if (physical == .str or physical == .str_view) {
        if (!isBytes(c, source)) return .{ .kind = .text_raw, .text = value };
        // A borrowed byte view is rendered from the span it already is.
        return .{ .kind = .octets, .text = value };
    }
    if (physical == .bytes) return .{ .kind = .octets, .text = value };
    // A byte buffer renders as `print` shows it (its own renderer, as a record's), since the octet helpers take a block of
    // bytes and a buffer is not one (FX12: the call did not match its signature, E_CORE_INVALID_IR).
    if (physical == .byte_buffer) return .{ .kind = .text_raw, .text = try c.textOf(value, source, span) };
    if (physical.integer()) |info| return .{
        .kind = if (info.signed) .signed else .unsigned,
        .bits = try widen(Context, c, value, if (info.signed) .i64 else .u64, span),
        .word = typed.plainWord(if (info.signed) .signed else .unsigned),
    };
    // A record, list, union, option or result renders to its own text, which is
    // the one allocation such a hole has always made.
    return .{ .kind = .text_raw, .text = try c.textOf(value, source, span) };
}

/// Whether a managed source type is byte text rather than a string, so a borrowed
/// view of it renders as bytes.
fn isBytes(c: anytype, source: typed.Type) bool {
    if (!source.isAggregate()) return false;
    return c.mb.input.program.records[source.recordIndex()].collection.kind == .bytes;
}

/// The bits a specified hole renders from: an integer's widening, a float's
/// pattern, or nothing for text. One entry point reads both, so a float hands over
/// its eight bytes and the runtime reads them back as the double they are.
fn bitsOf(comptime Context: type, c: Context, value: ir.Ref, family: typed.FormatFamily, span: u32) Error!ir.Ref {
    return switch (family) {
        .text => .none,
        .float => c.runtimeCall("myl_core_f64_bits", &.{.f64}, .u64, &.{value}, span),
        .signed => widen(Context, c, value, .i64, span),
        .unsigned => widen(Context, c, value, .u64, span),
    };
}

/// A signed value's own eight bytes, which the runtime reads as the same integer.
fn asBits(comptime Context: type, c: Context, value: ir.Ref, span: u32) Error!ir.Ref {
    return if (c.typeOfRef(value) == .u64) value else c.emit(.{ .op = .convert, .ty = .u64, .a = value, .span = span });
}

/// `value` as integer type `target`: the value itself when it already is.
fn widen(comptime Context: type, c: Context, value: ir.Ref, target: ir.Type, span: u32) Error!ir.Ref {
    return if (c.typeOfRef(value) == target) value else c.emit(.{ .op = .convert, .ty = target, .a = value, .span = span });
}

/// The text parameter's type in a specified hole call. A view and a byte value
/// cross as a borrowed span (`str` with the span bit), and a byte buffer keeps its
/// own type so the argument needs no copy.
fn textParam(ty: ir.Type) ir.Type {
    return if (ty == .byte_buffer) .byte_buffer else .str;
}

/// The bits one specified hole passes, or the zero a text hole's renderer ignores.
fn holeBits(comptime Context: type, c: Context, hole: Hole, span: u32) Error!ir.Ref {
    if (hole.bits == .none) return c.constant(.u64, 0);
    return if (hole.kind == .signed) asBits(Context, c, hole.bits, span) else hole.bits;
}

/// The empty text a scalar hole passes, which its renderer never reads.
fn emptyText(comptime Context: type, c: Context, span: u32) Error!ir.Ref {
    return literal(Context, c, "", span);
}

/// The text span a specified hole reads: its own text, or the empty block a
/// scalar ignores.
fn holeText(comptime Context: type, c: Context, hole: Hole, span: u32) Error!ir.Ref {
    return if (hole.text == .none) emptyText(Context, c, span) else hole.text;
}

/// The two entry points one plain scalar class uses: the `print` spelling, and the
/// one that also answers how many octets it wrote.
const Symbols = struct { plain: []const u8, counted: []const u8 };

/// Write one evaluated hole to `stream`, and answer its scalar count when the
/// caller needs one.
fn writeHole(comptime Context: type, c: Context, hole: Hole, sink: Sink) Error!ir.Ref {
    if (hole.specified) return specifiedPrint(Context, c, hole, sink);
    switch (hole.kind) {
        .signed => return scalarPrint(Context, c, &.{ .cap, .i64 }, hole.bits, sink, .{ .plain = "myl_core_print_i64", .counted = "myl_core_print_i64_count" }),
        .unsigned => return scalarPrint(Context, c, &.{ .cap, .u64 }, hole.bits, sink, .{ .plain = "myl_core_print_u64", .counted = "myl_core_print_u64_count" }),
        .float_plain => return scalarPrint(Context, c, &.{ .cap, .f64 }, hole.bits, sink, .{ .plain = "myl_core_print_f64", .counted = "myl_core_print_f64_count" }),
        .boolean => if (!sink.count) return c.effectCall("myl_core_print_bool", &.{ .cap, .bool }, .void, &.{ sink.stream, hole.bits }, sink.span),
        .text_raw => return textPrint(Context, c, hole.text, sink),
        .octets => return c.effectCall("myl_core_format_octets_print", &.{ .cap, .str }, .u64, &.{ sink.stream, hole.text }, sink.span),
        // A specified hole is the only way to reach the two specification kinds.
        .float_spec, .text_spec => unreachable,
    }
    return c.effectCall("myl_core_format_bool_print", &.{ .cap, .bool }, .u64, &.{ sink.stream, hole.bits }, sink.span);
}

/// Write a plain scalar with the class's own spelling: digits into a stack frame
/// or a double's spelling, then one stream write.
fn scalarPrint(comptime Context: type, c: Context, declared: []const ir.Type, value: ir.Ref, sink: Sink, symbols: Symbols) Error!ir.Ref {
    if (!sink.count) {
        _ = try c.effectCall(symbols.plain, declared, .void, &.{ sink.stream, value }, sink.span);
        return .none;
    }
    return c.effectCall(symbols.counted, declared, .u64, &.{ sink.stream, value }, sink.span);
}

/// Write a text hole: a block as it is, or a borrowed view's span. `write` counts
/// its scalars once, in the same pass that writes them.
fn textPrint(comptime Context: type, c: Context, text: ir.Ref, sink: Sink) Error!ir.Ref {
    if (sink.count) return c.effectCall("myl_core_print_span_count", &.{ .cap, .str }, .u64, &.{ sink.stream, text }, sink.span);
    if (c.typeOfRef(text) == .str_view) {
        _ = try c.effectCall("myl_core_print_view", &.{ .cap, .str }, .void, &.{ sink.stream, text }, sink.span);
        return .none;
    }
    _ = try c.effectCall("myl_core_print_str", &.{ .cap, .str }, .void, &.{ sink.stream, text }, sink.span);
    return .none;
}

/// A hole with a written specification keeps the general renderer; `print` takes
/// its write-only entry point, so a printed hole is never scanned for a count.
fn specifiedPrint(comptime Context: type, c: Context, hole: Hole, sink: Sink) Error!ir.Ref {
    const source_text = try holeText(Context, c, hole, sink.span);
    const declared = params(textParam(c.typeOfRef(source_text)));
    const arguments = [_]ir.Ref{
        sink.stream,
        try c.constant(.u32, @backingInt(hole.kind)),
        try holeBits(Context, c, hole, sink.span),
        try c.constant(.u64, hole.word),
        source_text,
    };
    if (!sink.count) {
        _ = try c.effectCall("myl_core_format_write", &declared, .void, &arguments, sink.span);
        return .none;
    }
    return c.effectCall("myl_core_format_print", &declared, .u64, &arguments, sink.span);
}

/// Append one evaluated hole to the reserved text `target`.
fn appendHole(comptime Context: type, c: Context, hole: Hole, target: ir.Ref, span: u32) Error!ir.Ref {
    if (!hole.specified) switch (hole.kind) {
        .signed => return c.runtimeCall("myl_core_str_append_i64", &.{ .str, .i64 }, .str, &.{ target, hole.bits }, span),
        .unsigned => return c.runtimeCall("myl_core_str_append_u64", &.{ .str, .u64 }, .str, &.{ target, hole.bits }, span),
        .float_plain => return c.runtimeCall("myl_core_str_append_f64", &.{ .str, .f64 }, .str, &.{ target, hole.bits }, span),
        .boolean => return c.runtimeCall("myl_core_format_bool_append", &.{ .str, .bool }, .str, &.{ target, hole.bits }, span),
        .text_raw => return c.runtimeCall("myl_core_str_append_bytes", &.{ .str, .str }, .str, &.{ target, hole.text }, span),
        .octets => return c.runtimeCall("myl_core_format_octets_append", &.{ .str, .str }, .str, &.{ target, hole.text }, span),
        .float_spec, .text_spec => unreachable,
    };
    const source_text = try holeText(Context, c, hole, span);
    const declared = params(textParam(c.typeOfRef(source_text)));
    const arguments = [_]ir.Ref{ target, try c.constant(.u32, @backingInt(hole.kind)), try holeBits(Context, c, hole, span), try c.constant(.u64, hole.word), source_text };
    return c.runtimeCall("myl_core_format_append", &.{ .str, .u32, declared[2], declared[3], declared[4] }, .str, &arguments, span);
}

/// Append a literal piece's octets. The compiler knows whether they are ASCII, so
/// an ASCII piece keeps the block's ASCII flag and a later `len` stays O(1).
fn appendLiteral(comptime Context: type, c: Context, bytes: []const u8, target: ir.Ref, span: u32) Error!ir.Ref {
    const piece = try literal(Context, c, bytes, span);
    const symbol = if (asciiOnly(bytes)) "myl_core_str_append_ascii" else "myl_core_str_append_bytes";
    return c.runtimeCall(symbol, &.{ .str, .str }, .str, &.{ target, piece }, span);
}

/// Whether every octet of a literal is ASCII.
fn asciiOnly(bytes: []const u8) bool {
    for (bytes) |byte| if (byte >= 0x80) return false;
    return true;
}

/// One immortal string constant holding `bytes`.
fn literal(comptime Context: type, c: Context, bytes: []const u8, span: u32) Error!ir.Ref {
    const index = c.module().strings.items.len;
    try c.module().strings.append(c.allocator(), bytes);
    return c.detached(.{ .op = .str_const, .ty = .str, .data = index, .span = span });
}

/// The bytes every literal piece of `pieces` spells, in order. A format string
/// with a hole has no single constant spelling; its caller never asks for one.
fn constantText(c: anytype, pieces: []const typed.FormatPiece) Error![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    for (pieces) |piece| switch (piece) {
        .literal => |literal_bytes| try bytes.appendSlice(c.allocator(), literal_bytes),
        .hole => {},
    };
    return bytes.toOwnedSlice(c.allocator());
}

/// The octets the literal pieces of `pieces` spell, which reserve room at once.
fn literalLen(pieces: []const typed.FormatPiece) u64 {
    var total: u64 = 0;
    for (pieces) |piece| switch (piece) {
        .literal => |literal_bytes| total += literal_bytes.len,
        .hole => {},
    };
    return total;
}
