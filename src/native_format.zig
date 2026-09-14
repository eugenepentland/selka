//! Native scalar-to-text formatting and text-to-number parsing share the VM's
//! canonical Zig implementations, so `str(value)`, `int(text)` and `float(text)`
//! cannot answer differently on the two backends.
const std = @import("std");
const builtin = @import("builtin");
const number_text = @import("number_text.zig");
const Kind = enum { signed, unsigned, boolean, unit, floating };
const FormatError = error{NoSpaceLeft};
comptime {
    if (!builtin.is_test) @export(&scalarC, .{ .name = "myl_native_text_scalar" });
    if (!builtin.is_test) @export(&numberC, .{ .name = "myl_native_number_parse" });
}
/// Parse Unicode scalars under the pinned grammar, publishing the value's bits
/// and answering 1 for a number or 0 for text that is not exactly one.
fn numberC(points: ?[*]const u32, count: usize, floating: c_uint, output: *u64) callconv(.c) c_uint {
    const scalars: []const u32 = if (points) |found| found[0..count] else &.{};
    if (floating != 0) {
        const value = number_text.floating(scalars) orelse return 0;
        output.* = @bitCast(value);
        return 1;
    }
    const value = number_text.integer(scalars) orelse return 0;
    output.* = @bitCast(value);
    return 1;
}
extern fn myl_native_text_from_utf8(heap: *anyopaque, bytes: [*]const u8, length: usize) ?*anyopaque;
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
        .signed => return std.fmt.bufPrint(buffer, "{d}", .{@as(i64, @bitCast(bits))}),
        .unsigned => return std.fmt.bufPrint(buffer, "{d}", .{bits}),
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

test "native scalar formatting rejects insufficient caller storage" {
    var small: [1]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, format(&small, 42, .unsigned));
    try std.testing.expectError(error.NoSpaceLeft, format(&small, @bitCast(@as(f64, 1.0)), .floating));
}
