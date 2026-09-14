//! Copied fixed-size byte blocks with explicit EOF and short-write counts.
const std = @import("std");
/// The declared host effect bit shared by every trusted registration.
const host_effect: i64 = 32;
/// Maximum useful byte payload in one copied host call.
pub const block_size = 256;
/// Structural validation failures of the optional copied-block declarations.
pub const Error = error{ HostSignatureMismatch, InvalidNativeManifest, OutOfMemory };
/// The exact native type names one validated block is copied through.
pub const Shape = struct { record: []const u8, array: []const u8 };
/// Accept the optional bulk declarations only when both exist with the exact
/// structural ABI: `read_block(i64) -> R` and `write_block(R) -> i64` for a
/// plain record of `[256]u8` followed by `i64`. A guest that declares neither
/// keeps the scalar-only boundary; anything else rejects before invocation.
pub fn validate(allocator: std.mem.Allocator, manifest: []const u8) Error!?Shape {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest, .{ .allocate = .alloc_always }) catch return error.InvalidNativeManifest;
    const host = object(parsed.value, "host") orelse return error.InvalidNativeManifest;
    const declarations = array(host, "declarations");
    const read = find(declarations, "name", "io::read_block");
    const write = find(declarations, "name", "io::write_block");
    if (read == null and write == null) return null;
    const reader = read orelse return error.HostSignatureMismatch;
    const writer = write orelse return error.HostSignatureMismatch;
    if (!signature(reader, "i64") or !signature(writer, text(reader, "result"))) return error.HostSignatureMismatch;
    if (!std.mem.eql(u8, text(writer, "result"), "i64")) return error.HostSignatureMismatch;
    const shape = try block(array(host, "types"), text(reader, "result"));
    return shape;
}
/// Validate the copied block's record and array shapes by their native layout.
fn block(types: []const std.json.Value, name: []const u8) Error!Shape {
    const record = find(types, "name", name) orelse return error.HostSignatureMismatch;
    if (!std.mem.eql(u8, text(record, "kind"), "record") or count(record) != 2) return error.HostSignatureMismatch;
    const fields = array(record, "fields");
    if (fields.len != 2 or !std.mem.eql(u8, text(fields[1], "type"), "i64")) return error.HostSignatureMismatch;
    const element = text(fields[0], "type");
    const payload = find(types, "name", element) orelse return error.HostSignatureMismatch;
    if (!std.mem.eql(u8, text(payload, "kind"), "array") or count(payload) != block_size) return error.HostSignatureMismatch;
    const inner = array(payload, "fields");
    if (inner.len != 1 or !std.mem.eql(u8, text(inner[0], "type"), "u8")) return error.HostSignatureMismatch;
    return .{ .record = name, .array = element };
}
/// One trusted declaration takes exactly one parameter and declares only `host`.
fn signature(declaration: std.json.Value, parameter: []const u8) bool {
    const parameters = array(declaration, "parameters");
    if (parameters.len != 1 or parameters[0] != .string) return false;
    if (!std.mem.eql(u8, parameters[0].string, parameter)) return false;
    return integer(declaration, "effects") == host_effect;
}
fn find(items: []const std.json.Value, key: []const u8, name: []const u8) ?std.json.Value {
    for (items) |item| if (std.mem.eql(u8, text(item, key), name)) return item;
    return null;
}
fn object(value: std.json.Value, key: []const u8) ?std.json.Value {
    return if (value == .object) value.object.get(key) else null;
}
fn array(value: std.json.Value, key: []const u8) []const std.json.Value {
    const found = object(value, key) orelse return &.{};
    return if (found == .array) found.array.items else &.{};
}
fn text(value: std.json.Value, key: []const u8) []const u8 {
    const found = object(value, key) orelse return "";
    return if (found == .string) found.string else "";
}
fn integer(value: std.json.Value, key: []const u8) i64 {
    const found = object(value, key) orelse return -1;
    return if (found == .integer) found.integer else -1;
}
fn count(value: std.json.Value) i64 {
    return integer(value, "count");
}
