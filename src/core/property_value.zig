//! Accessors for the Core property input schema and generated JSON values.
const std = @import("std");
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
