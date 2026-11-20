//! Core-block adapters for the ported native_format/number_text/format_spec algorithms.
const std = @import("std");
const builtin = @import("builtin");
const grammar = @import("core_number_parse.zig");
const formatting = @import("core_number_format.zig");

// The first word belongs to the selected C runtime: kind plus padding in the
// owned ABI, or count plus kind in the historical ABI. Never inspect it here.
const Block = extern struct { header_prefix: [8]u8, len: i64, cap: i64, reserved: u64 };
extern fn myl_core_number_text_new(length: usize) *Block;
extern fn myl_core_number_text_clear_ascii(text: *Block) void;
extern fn myl_core_buffer_append_spelled(buffer: *Block, bytes: [*]const u8, length: usize) *Block;
extern fn myl_core_number_text_invalid() noreturn;
extern fn myl_core_negative_position(index: i64, length: i64, text: bool) noreturn;
extern fn myl_core_print_write(fd: i64, bytes: [*]const u8, length: usize) void;
extern fn myl_core_str_append_bytes(text: *Block, bytes: [*]const u8, length: usize) *Block;
extern fn myl_core_str_append_ascii(text: *Block, bytes: [*]const u8, length: usize) *Block;
extern fn myl_core_digest_new() *Block;

comptime {
    // The embedded object's CPU is chosen in build.zig (`skylake`: Haswell's AVX2 with Skylake scheduling, so the
    // BLAKE3 digest runs eight lanes wide at the speed of a native Zig build). The compiler identity digests the
    // bytes of the built object, so a change of CPU in build.zig moves the identity by itself; naming the model here
    // keeps the performance contract (an AVX2 model) and fails the build while the two disagree.
    if (!builtin.is_test and !std.mem.eql(u8, builtin.cpu.model.name, "skylake")) @compileError("core_number_text is built for the skylake CPU model (build.zig)");
    if (!builtin.is_test) {
        @export(&appendFloat, .{ .name = "myl_core_buffer_append_f64" });
        @export(&floatText, .{ .name = "myl_core_str_from_f64" });
        @export(&formatNumber, .{ .name = "myl_core_format_number" });
        @export(&formatFloat, .{ .name = "myl_core_format_float" });
        @export(&formatText, .{ .name = "myl_core_format_text" });
        @export(&parseFloat, .{ .name = "myl_core_parse_float_range" });
        @export(&spanParseFloat, .{ .name = "myl_core_span_parse_float_range" });
        @export(&parseF32, .{ .name = "myl_core_parse_f32_range" });
        @export(&spanParseF32, .{ .name = "myl_core_span_parse_f32_range" });
        @export(&roundFloat, .{ .name = "myl_core_round_float" });
        @export(&holeLen, .{ .name = "myl_core_format_len" });
        @export(&holeAppend, .{ .name = "myl_core_format_append" });
        @export(&holePrint, .{ .name = "myl_core_format_print" });
        @export(&holeWrite, .{ .name = "myl_core_format_write" });
        @export(&printFloat, .{ .name = "myl_core_print_f64" });
        @export(&printFloatCount, .{ .name = "myl_core_print_f64_count" });
        @export(&appendFloatText, .{ .name = "myl_core_str_append_f64" });
        @export(&floatText32, .{ .name = "myl_core_str_from_f32" });
        @export(&formatFloat32, .{ .name = "myl_core_format_float32" });
        @export(&octetsPrint, .{ .name = "myl_core_format_octets_print" });
        @export(&octetsAppend, .{ .name = "myl_core_format_octets_append" });
        @export(&octetsLength, .{ .name = "myl_core_format_octets_len" });
        @export(&blockDigest, .{ .name = "myl_core_bytes_blake3" });
        @export(&spanDigest, .{ .name = "myl_core_span_bytes_blake3" });
    }
}

fn data(block: *const Block) [*]const u8 {
    return @as([*]const u8, @ptrCast(block)) + @sizeOf(Block);
}

fn output(block: *Block) [*]u8 {
    return @as([*]u8, @ptrCast(block)) + @sizeOf(Block);
}

/// A fresh 32-octet `bytes` holding the BLAKE3 digest of `input` (`bytes.blake3()`, `hashes.blake3`). The hash is the
/// standard library's, compiled once here at ReleaseFast, so it runs at the speed of the Zig reference.
fn digestOf(input: []const u8) *Block {
    const out = myl_core_digest_new();
    std.crypto.hash.Blake3.hash(input, output(out)[0..32], .{});
    return out;
}

/// The digest of an owned `str`, `bytes` or buffer block's octets.
fn blockDigest(source: *const Block) callconv(.c) *Block {
    return digestOf(data(source)[0..@intCast(source.len)]);
}

/// The digest of a borrowed view's octets (the span form of `blockDigest`).
fn spanDigest(bytes: [*]const u8, length: u64) callconv(.c) *Block {
    return digestOf(bytes[0..length]);
}

fn copied(bytes: []const u8) *Block {
    const text = myl_core_number_text_new(bytes.len);
    @memcpy(output(text)[0..bytes.len], bytes);
    return text;
}

// Port of native_format.format's floating case, including integral .0 and -0.0.
fn spelledFloat(buffer: []u8, value: f64) error{NoSpaceLeft}![]const u8 {
    return spelledFloatOf(f64, buffer, value);
}

// The same spelling for a binary32 value: `{d}` prints its shortest digits that read back as binary32.
fn spelledFloatOf(comptime T: type, buffer: []u8, value: T) error{NoSpaceLeft}![]const u8 {
    if (std.math.isNan(value)) return "nan";
    if (std.math.isInf(value)) return if (value < 0) "-inf" else "inf";
    const bytes = try std.fmt.bufPrint(buffer, "{d}", .{value});
    if (std.mem.indexOfAny(u8, bytes, ".eE") != null) return bytes;
    if (buffer.len - bytes.len < 2) return error.NoSpaceLeft;
    @memcpy(buffer[bytes.len..][0..2], ".0");
    return buffer[0 .. bytes.len + 2];
}

fn floatText(value: f64) callconv(.c) *Block {
    var buffer: [1024]u8 = undefined;
    return copied(spelledFloat(&buffer, value) catch |err| switch (err) {
        error.NoSpaceLeft => myl_core_number_text_invalid(),
    });
}

/// The `str` of a binary32 value: its shortest round-trip decimal, as `str` of a float spells it.
fn floatText32(value: f32) callconv(.c) *Block {
    var buffer: [1024]u8 = undefined;
    return copied(spelledFloatOf(f32, &buffer, value) catch |err| switch (err) {
        error.NoSpaceLeft => myl_core_number_text_invalid(),
    });
}

/// A specified binary32 hole: the value under its packed specification, rendered from its own shortest digits.
fn formatFloat32(value: f32, word: u64) callconv(.c) *Block {
    const spec = formatting.unpack(word) orelse return myl_core_number_text_invalid();
    if (spec.family != .float) return myl_core_number_text_invalid();
    return rendered(spec, .{ .float32 = value });
}

fn rendered(spec: formatting.Spec, input: formatting.Input) *Block {
    var measure: formatting.Out = .{};
    formatting.render(&measure, spec, input);
    const text = myl_core_number_text_new(measure.len);
    var out: formatting.Out = .{ .buffer = output(text)[0..measure.len] };
    formatting.render(&out, spec, input);
    // Numeric and text format fills may be non-ASCII. Publish no false ASCII premise.
    myl_core_number_text_clear_ascii(text);
    return text;
}

fn formatNumber(bits: u64, word: u64) callconv(.c) *Block {
    const spec = formatting.unpack(word) orelse return myl_core_number_text_invalid();
    return rendered(spec, switch (spec.family) {
        .signed => .{ .signed = @bitCast(bits) },
        .unsigned => .{ .unsigned = bits },
        .float => .{ .float = @bitCast(bits) },
        .text => unreachable,
    });
}

fn formatFloat(value: f64, word: u64) callconv(.c) *Block {
    return formatNumber(@bitCast(value), word);
}

fn formatText(source: *const Block, word: u64) callconv(.c) *Block {
    const spec = formatting.unpack(word) orelse return myl_core_number_text_invalid();
    const bytes = data(source)[0..@intCast(source.len)];
    return rendered(spec, .{ .text = .{ .bytes = bytes, .scalars = std.unicode.utf8CountCodepoints(bytes) catch |err| switch (err) {
        else => myl_core_number_text_invalid(),
    } } });
}

fn endpoint(index: i64, length: i64) usize {
    if (index < 0) myl_core_negative_position(index, length, false);
    return @intCast(@min(length, index));
}

// The frozen x86-64 scalar Option ABI returns tag in rax and binary64 in xmm0.
const ParsedFloat = extern struct { tag: u64, value: f64 };

fn parseFloat(source: *const Block, start: i64, end: i64) callconv(.c) ParsedFloat {
    return spanParseFloat(data(source), source.len, start, end);
}

/// The ranged float parse over a borrowed text (C9 S1): the octets are a span, so a parameter view needs no copy.
fn spanParseFloat(bytes: [*]const u8, length: i64, start: i64, end: i64) callconv(.c) ParsedFloat {
    const lower = endpoint(start, length);
    const upper = @max(lower, endpoint(end, length));
    const value = grammar.floatingBytes(bytes[lower..upper]) orelse return .{ .tag = 0, .value = 0 };
    return .{ .tag = 1, .value = value };
}

// The frozen x86-64 scalar Option ABI for binary32: tag in rax, the float in xmm0.
const ParsedF32 = extern struct { tag: u64, value: f32 };

fn parseF32(source: *const Block, start: i64, end: i64) callconv(.c) ParsedF32 {
    return spanParseF32(data(source), source.len, start, end);
}

/// The ranged binary32 parse over a borrowed text, with the same endpoints and grammar as `float`.
fn spanParseF32(bytes: [*]const u8, length: i64, start: i64, end: i64) callconv(.c) ParsedF32 {
    const lower = endpoint(start, length);
    const upper = @max(lower, endpoint(end, length));
    const value = grammar.floatingBytes32(bytes[lower..upper]) orelse return .{ .tag = 0, .value = 0 };
    return .{ .tag = 1, .value = value };
}

fn roundFloat(value: f64, digits: i64) callconv(.c) f64 {
    return formatting.roundFloat(value, digits);
}

fn appendFloat(buffer: *Block, value: f64) callconv(.c) *Block {
    var frame: [1024]u8 = undefined;
    const bytes = spelledFloat(&frame, value) catch return myl_core_number_text_invalid();
    return myl_core_buffer_append_spelled(buffer, bytes.ptr, bytes.len);
}

// ---- format-string holes (PY-FSTRING-1) -------------------------------------
// An f-string hole is the value plus the one rendering it was written with: a
// specification's packed word, or the value's own `str`/`print` spelling. A
// specified hole runs the general renderer into a sink, so `myl_core_format_len`
// measures, `myl_core_format_append` fills a text block reserved for that
// measurement, `myl_core_format_print` writes to a stream and counts, and
// `myl_core_format_write` writes without counting. A plain hole needs none of
// that: its spelling is written or appended by a direct helper below. Nothing
// here is joined, and a scalar or text hole allocates nothing. A text parameter
// is a borrowed span (pointer and length), so a view crosses it without being
// copied.

/// Write a double's `print` spelling straight to a stream: one bounded frame,
/// one stream write, no text block behind it.
fn printFloat(fd: i64, value: f64) callconv(.c) void {
    var frame: [1024]u8 = undefined;
    const bytes = spelledFloat(&frame, value) catch myl_core_number_text_invalid();
    myl_core_print_write(fd, bytes.ptr, bytes.len);
}

/// The same spelling, answering the octets a `write` counts: the spelling is
/// ASCII, so its octet count is its scalar count.
fn printFloatCount(fd: i64, value: f64) callconv(.c) u64 {
    var frame: [1024]u8 = undefined;
    const bytes = spelledFloat(&frame, value) catch myl_core_number_text_invalid();
    myl_core_print_write(fd, bytes.ptr, bytes.len);
    return bytes.len;
}

/// Append a double's spelling to the text block a stored format string reserved.
fn appendFloatText(text: *Block, value: f64) callconv(.c) *Block {
    var frame: [1024]u8 = undefined;
    const bytes = spelledFloat(&frame, value) catch return myl_core_number_text_invalid();
    return myl_core_str_append_ascii(text, bytes.ptr, bytes.len);
}

/// The rendering one hole selects, in the order Core's `build_format.Kind` shares.
const HoleKind = enum(u32) { signed, unsigned, float_spec, text_spec, float_plain, text_raw, octets };

/// One hole as the entry points receive it: what to render and how.
const Hole = struct {
    kind: HoleKind,
    /// The value's bits: its integer, or its binary64 pattern.
    bits: u64,
    /// A specification's packed word (`formatting.unpack`).
    word: u64,
    /// The text a text hole reads.
    text: []const u8 = &.{},
};

fn hole(kind: u32, bits: u64, word: u64, text: [*]const u8, len: usize) ?Hole {
    if (kind > @backingInt(HoleKind.octets)) return null;
    return .{ .kind = @fromBackingInt(@intCast(kind)), .bits = bits, .word = word, .text = text[0..len] };
}

/// The quote `myl_core_text_repr` picks for these bytes: `'` unless the value
/// holds one and no `"` (FR-418's one display rule).
fn octetQuote(bytes: []const u8) u8 {
    return if (std.mem.indexOfScalar(u8, bytes, '\'') != null and std.mem.indexOfScalar(u8, bytes, '"') == null) '"' else '\'';
}

/// One byte's escaped spelling (`repr`'s escapes), written into `frame`.
fn escapedByte(frame: *[4]u8, byte: u8, quote: u8) []const u8 {
    if (byte == quote or byte == '\\') {
        frame[0] = '\\';
        frame[1] = byte;
        return frame[0..2];
    }
    if (byte == '\n') return "\\n";
    if (byte == '\r') return "\\r";
    if (byte == '\t') return "\\t";
    if (byte < 0x20 or byte >= 0x7f) {
        frame.* = .{ '\\', 'x', "0123456789abcdef"[byte >> 4], "0123456789abcdef"[byte & 15] };
        return frame[0..4];
    }
    frame[0] = byte;
    return frame[0..1];
}

/// The octets of one byte value as its `repr` spells them, `b'...'` (or
/// `b"..."`) with the escapes `print` writes: one implementation of the bytes
/// spelling, rendered into whatever sink the caller has. Escapes are handed over
/// in runs, so a sink makes a call per block rather than one per byte.
fn octets(out: *formatting.Out, bytes: []const u8) void {
    const quote = octetQuote(bytes);
    var run: [512]u8 = undefined;
    var used: usize = 2;
    run[0] = 'b';
    run[1] = quote;
    for (bytes) |byte| {
        var frame: [4]u8 = undefined;
        const escaped = escapedByte(&frame, byte, quote);
        if (used + escaped.len + 1 > run.len) {
            out.put(run[0..used]);
            used = 0;
        }
        @memcpy(run[used..][0..escaped.len], escaped);
        used += escaped.len;
    }
    if (used + 1 > run.len) {
        out.put(run[0..used]);
        used = 0;
    }
    run[used] = quote;
    out.put(run[0 .. used + 1]);
}

/// The octets `octets` writes for the same bytes, so a stored format string
/// reserves exactly the room its byte holes need.
fn octetsLen(bytes: []const u8) usize {
    const quote = octetQuote(bytes);
    var total: usize = 3;
    for (bytes) |byte| {
        var frame: [4]u8 = undefined;
        total += escapedByte(&frame, byte, quote).len;
    }
    return total;
}

/// Render one hole into `out`, which may count, fill a buffer, or write onward.
fn renderHole(out: *formatting.Out, value: Hole) void {
    switch (value.kind) {
        .signed, .unsigned, .float_spec => {
            const spec = formatting.unpack(value.word) orelse myl_core_number_text_invalid();
            formatting.render(out, spec, switch (value.kind) {
                .signed => .{ .signed = @bitCast(value.bits) },
                .unsigned => .{ .unsigned = value.bits },
                else => .{ .float = @bitCast(value.bits) },
            });
        },
        .text_spec => {
            const spec = formatting.unpack(value.word) orelse myl_core_number_text_invalid();
            formatting.render(out, spec, .{ .text = .{ .bytes = value.text, .scalars = std.unicode.utf8CountCodepoints(value.text) catch myl_core_number_text_invalid() } });
        },
        .float_plain => {
            var frame: [1024]u8 = undefined;
            out.put(spelledFloat(&frame, @bitCast(value.bits)) catch myl_core_number_text_invalid());
        },
        .text_raw => out.put(value.text),
        .octets => octets(out, value.text),
    }
}

/// The octets a hole renders to, so a `str` build can reserve exactly that room.
fn holeLen(kind: u32, bits: u64, word: u64, text: [*]const u8, len: usize) callconv(.c) u64 {
    var measure: formatting.Out = .{};
    renderHole(&measure, hole(kind, bits, word, text, len) orelse myl_core_number_text_invalid());
    return measure.len;
}

/// Where a text-block sink appends: the block itself, which may move as it grows,
/// and whether its runs are known ASCII.
const BlockSink = struct {
    text: *Block,
    ascii: bool = false,
};

fn blockWrite(context: ?*anyopaque, bytes: [*]const u8, len: usize) void {
    const sink: *BlockSink = @ptrCast(@alignCast(context.?));
    sink.text = if (sink.ascii) myl_core_str_append_ascii(sink.text, bytes, len) else myl_core_str_append_bytes(sink.text, bytes, len);
}

/// Append one hole's rendering to `text` (reserved with room for it) and answer
/// the block that holds it: the same block unless it had to grow.
fn holeAppend(text: *Block, kind: u32, bits: u64, word: u64, source: [*]const u8, len: usize) callconv(.c) *Block {
    var sink: BlockSink = .{ .text = text };
    var out: formatting.Out = .{ .sink = .{ .context = &sink, .write = blockWrite } };
    renderHole(&out, hole(kind, bits, word, source, len) orelse myl_core_number_text_invalid());
    return sink.text;
}

/// The bytes a byte value's `repr` spells, appended to the reserved text block.
fn octetsAppend(text: *Block, source: [*]const u8, len: usize) callconv(.c) *Block {
    var sink: BlockSink = .{ .text = text, .ascii = true };
    var out: formatting.Out = .{ .sink = .{ .context = &sink, .write = blockWrite } };
    octets(&out, source[0..len]);
    return sink.text;
}

/// The octets a byte value's `repr` spells, which a stored format string reserves.
fn octetsLength(source: [*]const u8, len: usize) callconv(.c) u64 {
    return @intCast(octetsLen(source[0..len]));
}

/// Write a byte value's `repr` straight to a stream, answering its octet count
/// (`write` counts those scalars): no text block and no scan behind it.
fn octetsPrint(fd: i64, source: [*]const u8, len: usize) callconv(.c) u64 {
    var sink: PrintSink = .{ .fd = fd };
    var out: formatting.Out = .{ .sink = .{ .context = &sink, .write = printWrite } };
    octets(&out, source[0..len]);
    return @intCast(out.len);
}

/// Where a stream sink writes without counting: a `print` needs no scalar count,
/// so nothing walks the bytes it hands over.
const PrintSink = struct { fd: i64 };

fn printWrite(context: ?*anyopaque, bytes: [*]const u8, len: usize) void {
    const sink: *PrintSink = @ptrCast(@alignCast(context.?));
    myl_core_print_write(sink.fd, bytes, len);
}

/// Where a stream sink writes: one already-open output descriptor, and the
/// Unicode scalars it has written, which is what `write` returns.
const StreamSink = struct { fd: i64, scalars: u64 = 0 };

fn streamWrite(context: ?*anyopaque, bytes: [*]const u8, len: usize) void {
    const sink: *StreamSink = @ptrCast(@alignCast(context.?));
    for (bytes[0..len]) |byte| if ((byte & 0xc0) != 0x80) {
        sink.scalars += 1;
    };
    myl_core_print_write(sink.fd, bytes, len);
}

/// Write one hole's rendering to stream `fd`, with no text buffer at all, and
/// answer how many Unicode scalars it wrote.
fn holePrint(fd: i64, kind: u32, bits: u64, word: u64, text: [*]const u8, len: usize) callconv(.c) u64 {
    var sink: StreamSink = .{ .fd = fd };
    var out: formatting.Out = .{ .sink = .{ .context = &sink, .write = streamWrite } };
    renderHole(&out, hole(kind, bits, word, text, len) orelse myl_core_number_text_invalid());
    return sink.scalars;
}

/// Write one hole's rendering to stream `fd` for a `print`, which discards the
/// scalar count: the sink writes and never scans.
fn holeWrite(fd: i64, kind: u32, bits: u64, word: u64, text: [*]const u8, len: usize) callconv(.c) void {
    var sink: PrintSink = .{ .fd = fd };
    var out: formatting.Out = .{ .sink = .{ .context = &sink, .write = printWrite } };
    renderHole(&out, hole(kind, bits, word, text, len) orelse myl_core_number_text_invalid());
}

// spec-case: PY-FSTRING-1
test "a byte value's repr escapes once and measures its own octets" {
    const bytes = "a\n'\xff";
    var frame: [64]u8 = undefined;
    var out: formatting.Out = .{ .buffer = &frame };
    octets(&out, bytes);
    try std.testing.expectEqualStrings("b\"a\\n'\\xff\"", frame[0..out.len]);
    try std.testing.expectEqual(out.len, octetsLen(bytes));
    try std.testing.expectEqual(@as(usize, 3), octetsLen(""));
    // A value holding both quotes keeps `'` and escapes it, as `repr` does.
    var both_frame: [64]u8 = undefined;
    var both: formatting.Out = .{ .buffer = &both_frame };
    octets(&both, "a'\"b");
    try std.testing.expectEqualStrings("b'a\\'\"b'", both_frame[0..both.len]);
    try std.testing.expectEqual(both.len, octetsLen("a'\"b"));
}

// spec-case: NEW-CORE-S3-NUMBER-1
test "number text adapter leaves selected runtime header fields opaque" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Block));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Block, "len"));
    try std.testing.expect(!@hasField(Block, "count"));
    try std.testing.expect(!@hasField(Block, "kind"));
}

// spec-case: NEW-CORE-S3-NUMBER-1
test "number text rejects invalid Unicode format fill" {
    try std.testing.expect(formatting.parse("\xff^10.2f") == .rejected);
    try std.testing.expect(formatting.parse("\xed\xa0\x80^10.2f") == .rejected);
    try std.testing.expect(formatting.parse("é^10.2f") == .ok);
}

test "binary32 text reports a full buffer as NoSpaceLeft" {
    var tiny: [1]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, spelledFloatOf(f32, &tiny, 1.5));
    var roomy: [16]u8 = undefined;
    try std.testing.expectEqualStrings("1.5", try spelledFloatOf(f32, &roomy, 1.5));
}
