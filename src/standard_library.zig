//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
const Module = struct { path: []const u8, text: []const u8 };
const modules = [_]Module{
    .{ .path = "base64.my", .text = @embedFile("stdlib/base64.my") },
    .{ .path = "byte_builder.my", .text = @embedFile("stdlib/byte_builder.my") },
    .{ .path = "hex.my", .text = @embedFile("stdlib/hex.my") },
    .{ .path = "json.my", .text = @embedFile("stdlib/json.my") },
    .{ .path = "math.my", .text = @embedFile("stdlib/math.my") },
    .{ .path = "network.my", .text = @embedFile("stdlib/network.my") },
    .{ .path = "path.my", .text = @embedFile("stdlib/path.my") },
    .{ .path = "pool.my", .text = @embedFile("stdlib/pool.my") },
    .{ .path = "random.my", .text = @embedFile("stdlib/random.my") },
    .{ .path = "sort.my", .text = @embedFile("stdlib/sort.my") },
    .{ .path = "strings.my", .text = @embedFile("stdlib/strings.my") },
    .{ .path = "time.my", .text = @embedFile("stdlib/time.my") },
};
/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    for (modules) |module| if (std.mem.eql(u8, path, module.path)) return module.text;
    return null;
}

/// The reserved standard module names, comma-separated in table order, for
/// diagnostics that tell a user which imports need no project module.
pub fn names(allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
    var joined: std.ArrayList(u8) = .empty;
    errdefer joined.deinit(allocator);
    for (modules, 0..) |module, index| {
        if (index != 0) try joined.appendSlice(allocator, ", ");
        try joined.appendSlice(allocator, module.path[0 .. module.path.len - ".my".len]);
    }
    return joined.toOwnedSlice(allocator);
}
