//! Accessors for the compiler-owned JSON build manifest and generated C strings.
const std = @import("std");
/// Canonical parameter-list member shared by native embedding generators.
pub const parameters_key = "parameters";
/// Look up a manifest member, returning JSON null when absent.
pub fn get(value: std.json.Value, key: []const u8) std.json.Value {
    return if (value == .object) value.object.get(key) orelse .null else .null;
}
/// Read a manifest string; absent optional strings are empty.
pub fn text(value: std.json.Value) []const u8 {
    return if (value == .string) value.string else "";
}
/// Read a manifest array; absent optional arrays are empty.
pub fn array(value: std.json.Value) []const std.json.Value {
    return if (value == .array) value.array.items else &.{};
}
/// Read a nonnegative manifest integer; absent optional numbers are zero.
pub fn number(value: std.json.Value) u64 {
    return if (value == .integer and value.integer >= 0) @intCast(value.integer) else 0;
}
/// Read a manifest Boolean, defaulting to false.
pub fn boolean(value: std.json.Value) bool {
    return value == .bool and value.bool;
}
/// Escape UTF-8 bytes as a C string literal, including embedded controls.
pub fn quote(writer: *std.Io.Writer, value: []const u8) std.Io.Writer.Error!void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"', '\\' => {
            try writer.writeByte('\\');
            try writer.writeByte(byte);
        },
        32...33, 35...91, 93...126 => try writer.writeByte(byte),
        else => try writer.print("\\{o:0>3}", .{byte}),
    };
    try writer.writeByte('"');
}

test "manifest defaults and C byte escaping" {
    try std.testing.expectEqual(@as(u64, 0), number(.null));
    try std.testing.expectEqualStrings("", text(get(.null, "missing")));
    try std.testing.expectEqual(@as(usize, 0), array(.null).len);
    try std.testing.expect(!boolean(.null));
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try quote(&output.writer, "a\n\"é");
    try std.testing.expectEqualStrings("\"a\\012\\\"\\303\\251\"", output.written());
}
