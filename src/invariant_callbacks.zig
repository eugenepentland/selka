//! Reserved compiler-only function identities for validating decoded values.
const std = @import("std");
/// Source identifiers cannot contain this prefix, so callbacks cannot be forged.
pub const prefix = "@invariant:";
/// Recognize an invariant callback in native metadata or a trap frame.
pub fn isName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, prefix);
}
/// Give a type's boundary validator a stable identity across compilations.
pub fn functionName(allocator: std.mem.Allocator, type_name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, type_name });
}
