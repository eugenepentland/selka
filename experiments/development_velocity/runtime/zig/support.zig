//! Small schema helpers over Zig's standard JSON DOM; not task behavior.
const std = @import("std");
pub const V = std.json.Value;
pub const E = error{InvalidRequest};

pub fn fields(value: V, names: []const []const u8) E!void {
    if (value != .object or value.object.count() != names.len) return error.InvalidRequest;
    for (names) |name| if (!value.object.contains(name)) return error.InvalidRequest;
}
pub fn array(value: V, maximum: usize) E![]V {
    if (value != .array or value.array.items.len > maximum) return error.InvalidRequest;
    return value.array.items;
}
pub fn integer(value: V, low: i64, high: i64) E!i64 {
    if (value != .number_string) return error.InvalidRequest;
    const n = std.fmt.parseInt(i64, value.number_string, 10) catch return error.InvalidRequest;
    if (n < low or n > high) return error.InvalidRequest;
    return n;
}
pub fn id(value: V) E![]const u8 {
    if (value != .string) return error.InvalidRequest;
    const s = value.string;
    if (s.len == 0 or s.len > 32 or s[0] < 'a' or s[0] > 'z') return error.InvalidRequest;
    for (s[1..]) |c| if (!((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or c == '-')) return error.InvalidRequest;
    return s;
}
pub fn get(value: V, name: []const u8) V { return value.object.get(name).?; }
pub fn object() V { return .{ .object = .{} }; }
pub fn list(a: std.mem.Allocator) V { return .{ .array = std.json.Array.init(a) }; }
pub fn put(a: std.mem.Allocator, value: *V, name: []const u8, child: V) !void { try value.object.put(a, name, child); }
