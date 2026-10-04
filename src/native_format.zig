//! Native scalar-to-text formatting and text-to-number parsing share the VM's
//! canonical Zig implementations, so `str(value)`, `int(text)` and `float(text)`
//! cannot answer differently on the two backends.
const std = @import("std");
const builtin = @import("builtin");
const number_text = @import("number_text.zig");
const format_spec = @import("format_spec.zig");
const Kind = enum { signed, unsigned, boolean, unit, floating };
const FormatError = error{NoSpaceLeft};
comptime {
    if (!builtin.is_test) @export(&scalarC, .{ .name = "myl_native_text_scalar" });
    if (!builtin.is_test) @export(&signedC, .{ .name = "myl_native_text_integer" });
    if (!builtin.is_test) @export(&unsignedC, .{ .name = "myl_native_text_unsigned" });
    if (!builtin.is_test) @export(&numberC, .{ .name = "myl_native_number_parse" });
    if (!builtin.is_test) @export(&numberBytesC, .{ .name = "myl_native_bytes_number_parse" });
    if (!builtin.is_test) @export(&bufferFloatC, .{ .name = "myl_native_bytes_buffer_append_float" });
    if (!builtin.is_test) @export(&formatNumberC, .{ .name = "myl_native_text_format_number" });
    if (!builtin.is_test) @export(&formatTextC, .{ .name = "myl_native_text_format_text" });
    if (!builtin.is_test) @export(&roundFloatC, .{ .name = "myl_native_float_round" });
}
/// The header of a native text (`native_text.h`): scalar count, then octet count.
const Text = extern struct { length: usize, bytes: usize, flags: u32, hash: u32 };
extern fn myl_native_text_payload(text: *const Text) [*]const u8;
extern fn myl_native_text_build(heap: *anyopaque, bytes: usize) ?*Text;
/// A fresh unpublished text of `bytes` octets, with `*keep` rooted across the
/// allocation so a formatted text's source survives it.
extern fn myl_native_text_build_keeping(heap: *anyopaque, bytes: usize, keep: *?*const Text) ?*Text;
extern fn myl_native_text_publish(text: *Text, scalars: usize, plain: c_int) void;
/// PY-FSTRING-SPEC-1: one number under a packed format specification, as a
/// fresh text; null for a refused allocation or a word the checker never packed.
fn formatNumberC(heap: *anyopaque, bits: u64, word: u64) callconv(.c) ?*anyopaque {
    const spec = format_spec.unpack(word) orelse return null;
    if (spec.family == .text) return null;
    return formattedInput(heap, spec, null, bits);
}
/// PY-FSTRING-SPEC-1: one text under a packed format specification. The source
/// text stays rooted while the result is allocated and is read after it.
fn formatTextC(heap: *anyopaque, text: *const Text, word: u64) callconv(.c) ?*anyopaque {
    const spec = format_spec.unpack(word) orelse return null;
    if (spec.family != .text) return null;
    return formattedInput(heap, spec, text, 0);
}
/// The input one render reads: a text's own payload, or a number.
fn inputOf(spec: format_spec.Spec, source: ?*const Text, bits: u64) format_spec.Input {
    const text = source orelse return switch (spec.family) {
        .signed => .{ .signed = @bitCast(bits) },
        .unsigned => .{ .unsigned = bits },
        else => .{ .float = @bitCast(bits) },
    };
    return .{ .text = .{ .bytes = myl_native_text_payload(text)[0..text.bytes], .scalars = text.length } };
}
/// Measure one rendering, build a text of exactly that many octets, render
/// into its payload and publish it. Nothing is copied through a temporary.
fn formattedInput(heap: *anyopaque, spec: format_spec.Spec, source: ?*const Text, bits: u64) ?*anyopaque {
    var measure: format_spec.Out = .{};
    format_spec.render(&measure, spec, inputOf(spec, source, bits));
    var keep = source;
    const built = myl_native_text_build_keeping(heap, measure.len, &keep) orelse return null;
    const payload = @as([*]u8, @ptrCast(built)) + @sizeOf(Text);
    var out: format_spec.Out = .{ .buffer = payload[0..measure.len] };
    format_spec.render(&out, spec, inputOf(spec, keep, bits));
    const written = payload[0..out.len];
    const scalars = std.unicode.utf8CountCodepoints(written) catch written.len;
    const plain = for (written) |octet| {
        if (octet >= 0x80) break false;
    } else true;
    myl_native_text_publish(built, scalars, @intFromBool(plain));
    return built;
}

/// PRELUDE-ROUND-2: `round(x, n)` on a binary64's bits, answering bits.
fn roundFloatC(bits: u64, digits: i64) callconv(.c) u64 {
    return @bitCast(format_spec.roundFloat(@bitCast(bits), digits));
}
/// Append `count` octets of caller-owned raw storage to a byte buffer, answering
/// the byte runtime's status enum. Defined by the C runtime beside the buffer
/// growth it must share; declared here so the float formatter can hand it a
/// spelling it built on its own stack.
extern fn myl_native_bytes_buffer_append_raw(heap: *anyopaque, buffer: *anyopaque, data: [*]const u8, count: usize) c_int;
/// Format one binary64 into a mutable byte buffer, spelling it exactly as
/// `str(value)` does, so a buffered float and a printed float cannot disagree.
/// The spelling is built on this stack and appended while the buffer's own
/// capacity grows, so no managed intermediate value exists at all.
fn bufferFloatC(heap: ?*anyopaque, buffer: ?*anyopaque, bits: u64) callconv(.c) c_uint {
    const target = buffer orelse return 0;
    var text: [1024]u8 = undefined;
    const bytes = format(&text, bits, .floating) catch return 0;
    const status = myl_native_bytes_buffer_append_raw(heap orelse return 0, target, bytes.ptr, bytes.len);
    return @intCast(status);
}
/// Parse Unicode scalars under the pinned grammar, publishing the value's bits
/// and answering 1 for a number or 0 for text that is not exactly one.
fn numberC(points: ?[*]const u32, count: usize, floating: c_uint, output: *u64) callconv(.c) c_uint {
    const scalars: []const u32 = if (points) |found| found[0..count] else &.{};
    if (floating != 0) return floatingPoints(scalars, output);
    const value = number_text.integer(scalars) orelse return 0;
    output.* = @bitCast(value);
    return 1;
}
/// Parse the UTF-8 octets of a byte string under the same pinned grammar, so a
/// byte string or a view of one parses without decoding a temporary `str`.
fn numberBytesC(bytes: ?[*]const u8, length: usize, floating: c_uint, output: *u64) callconv(.c) c_uint {
    const text: []const u8 = if (bytes) |found| found[0..length] else &.{};
    if (floating != 0) return floatingOctets(text, output);
    const value = number_text.integerBytes(text) orelse return 0;
    output.* = @bitCast(value);
    return 1;
}
/// Keep the floating grammar's canonical scratch buffer in floating calls;
/// an integer parse must not reserve its large frame before testing the mode.
noinline fn floatingPoints(points: []const u32, output: *u64) c_uint {
    const value = number_text.floating(points) orelse return 0;
    output.* = @bitCast(value);
    return 1;
}
noinline fn floatingOctets(bytes: []const u8, output: *u64) c_uint {
    const value = number_text.floatingBytes(bytes) orelse return 0;
    output.* = @bitCast(value);
    return 1;
}
extern fn myl_native_text_from_utf8(heap: *anyopaque, bytes: [*]const u8, length: usize) ?*anyopaque;
/// A signed or unsigned 64-bit integer needs at most twenty ASCII octets. The
/// formatter proves the metadata, so construction keeps the ordinary allocation
/// size and refusal point without rescanning the decimal spelling as UTF-8.
fn integerText(heap: *anyopaque, bits: u64, comptime kind: Kind) ?*anyopaque {
    var buffer: [20]u8 = undefined;
    const bytes = formatInteger(&buffer, bits, kind) catch return null;
    const built = myl_native_text_build(heap, bytes.len) orelse return null;
    const payload = @as([*]u8, @ptrCast(built)) + @sizeOf(Text);
    @memcpy(payload[0..bytes.len], bytes);
    myl_native_text_publish(built, bytes.len, 1);
    return built;
}
fn signedC(heap: *anyopaque, value: i64) callconv(.c) ?*anyopaque {
    return integerText(heap, @bitCast(value), .signed);
}
fn unsignedC(heap: *anyopaque, value: u64) callconv(.c) ?*anyopaque {
    return integerText(heap, value, .unsigned);
}
fn formatInteger(buffer: []u8, bits: u64, comptime kind: Kind) FormatError![]const u8 {
    return switch (kind) {
        .signed => std.fmt.bufPrint(buffer, "{d}", .{@as(i64, @bitCast(bits))}),
        .unsigned => std.fmt.bufPrint(buffer, "{d}", .{bits}),
        else => unreachable,
    };
}
fn scalarC(heap: *anyopaque, bits: u64, kind: c_uint) callconv(.c) ?*anyopaque {
    const selected: Kind = switch (kind) {
        0 => .signed,
        1 => .unsigned,
        2 => .boolean,
        3 => .unit,
        4 => .floating,
        else => return null,
    };
    var buffer: [1024]u8 = undefined;
    const bytes = format(&buffer, bits, selected) catch return null;
    return myl_native_text_from_utf8(heap, bytes.ptr, bytes.len);
}
fn format(buffer: []u8, bits: u64, kind: Kind) FormatError![]const u8 {
    switch (kind) {
        .unit => return "None",
        .boolean => return if (bits == 0) "False" else "True",
        .signed => return formatInteger(buffer, bits, .signed),
        .unsigned => return formatInteger(buffer, bits, .unsigned),
        .floating => {},
    }
    const number: f64 = @bitCast(bits);
    if (std.math.isNan(number)) return "nan";
    if (std.math.isInf(number)) return if (number < 0) "-inf" else "inf";
    const bytes = try std.fmt.bufPrint(buffer, "{d}", .{number});
    if (std.mem.indexOfAny(u8, bytes, ".eE") != null) return bytes;
    if (buffer.len - bytes.len < 2) return error.NoSpaceLeft;
    @memcpy(buffer[bytes.len..][0..2], ".0");
    return buffer[0 .. bytes.len + 2];
}

test "native scalar text uses canonical integer and floating spellings" {
    var buffer: [1024]u8 = undefined;
    try std.testing.expectEqualStrings("-9223372036854775808", try format(&buffer, @bitCast(@as(i64, std.math.minInt(i64))), .signed));
    try std.testing.expectEqualStrings("18446744073709551615", try format(&buffer, std.math.maxInt(u64), .unsigned));
    try std.testing.expectEqualStrings("False", try format(&buffer, 0, .boolean));
    try std.testing.expectEqualStrings("None", try format(&buffer, 0, .unit));
    try std.testing.expectEqualStrings("0.1", try format(&buffer, @bitCast(@as(f64, 0.1)), .floating));
    try std.testing.expectEqualStrings("-0.0", try format(&buffer, @bitCast(@as(f64, -0.0)), .floating));
    try std.testing.expectEqualStrings("nan", try format(&buffer, @bitCast(std.math.nan(f64)), .floating));
    try std.testing.expectEqualStrings("inf", try format(&buffer, @bitCast(std.math.inf(f64)), .floating));
    try std.testing.expectEqualStrings("-inf", try format(&buffer, @bitCast(-std.math.inf(f64)), .floating));
    _ = try format(&buffer, 1, .floating);
}

// spec-case: PY-NUM-3
test "native integer formatting fits its twenty ASCII octet bound" {
    var buffer: [20]u8 = undefined;
    const signed = [_]i64{ 0, 1, -1, 10, -10, std.math.minInt(i64), std.math.maxInt(i64) };
    for (signed) |value| {
        var expected: [40]u8 = undefined;
        const actual = try formatInteger(&buffer, @bitCast(value), .signed);
        try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "{d}", .{value}), actual);
        for (actual) |octet| try std.testing.expect(octet < 0x80);
    }
    try std.testing.expectEqualStrings("18446744073709551615", try formatInteger(&buffer, std.math.maxInt(u64), .unsigned));
}

test "native scalar formatting rejects insufficient caller storage" {
    var small: [1]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, format(&small, 42, .unsigned));
    try std.testing.expectError(error.NoSpaceLeft, format(&small, @bitCast(@as(f64, 1.0)), .floating));
}

// spec-case: PY-NUM-1
test "native numeric exports publish only successful grammar answers" {
    const marker: u64 = 0x123456789abcdef0;
    var bits = marker;
    const integer = " \t-9_223_372_036_854_775_808\r ";
    try std.testing.expectEqual(@as(c_uint, 1), numberBytesC(integer.ptr, integer.len, 0, &bits));
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, std.math.minInt(i64)))), bits);
    bits = marker;
    const overflow = "9223372036854775808";
    try std.testing.expectEqual(@as(c_uint, 0), numberBytesC(overflow.ptr, overflow.len, 0, &bits));
    try std.testing.expectEqual(marker, bits);
    const points = [_]u32{ ' ', '+', '4', '_', '2', '\t' };
    try std.testing.expectEqual(@as(c_uint, 1), numberC(&points, points.len, 0, &bits));
    try std.testing.expectEqual(@as(u64, 42), bits);
    const decimal = " -1.25e+2 ";
    try std.testing.expectEqual(@as(c_uint, 1), numberBytesC(decimal.ptr, decimal.len, 9, &bits));
    try std.testing.expectEqual(@as(u64, @bitCast(@as(f64, -125))), bits);
    const named = [_]u32{ '+', 'i', 'n', 'f' };
    try std.testing.expectEqual(@as(c_uint, 1), numberC(&named, named.len, 1, &bits));
    try std.testing.expectEqual(@as(u64, @bitCast(std.math.inf(f64))), bits);
    bits = marker;
    const bad = "1e+";
    try std.testing.expectEqual(@as(c_uint, 0), numberBytesC(bad.ptr, bad.len, 1, &bits));
    try std.testing.expectEqual(@as(c_uint, 0), numberC(null, 0, 0, &bits));
    try std.testing.expectEqual(marker, bits);
}
