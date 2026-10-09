//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
const Module = struct { path: []const u8, text: []const u8 };
const modules = [_]Module{
    .{ .path = "base64.selka", .text = @embedFile("stdlib/base64.selka") },
    .{ .path = "byte_builder.selka", .text = @embedFile("stdlib/byte_builder.selka") },
    .{ .path = "environment.selka", .text = @embedFile("stdlib/environment.selka") },
    .{ .path = "filesystem.selka", .text = @embedFile("stdlib/filesystem.selka") },
    .{ .path = "hex.selka", .text = @embedFile("stdlib/hex.selka") },
    .{ .path = "json.selka", .text = @embedFile("stdlib/json.selka") },
    .{ .path = "math.selka", .text = @embedFile("stdlib/math.selka") },
    .{ .path = "network.selka", .text = @embedFile("stdlib/network.selka") },
    .{ .path = "path.selka", .text = @embedFile("stdlib/path.selka") },
    .{ .path = "pool.selka", .text = @embedFile("stdlib/pool.selka") },
    .{ .path = "random.selka", .text = @embedFile("stdlib/random.selka") },
    .{ .path = "sort.selka", .text = @embedFile("stdlib/sort.selka") },
    .{ .path = "strings.selka", .text = @embedFile("stdlib/strings.selka") },
    .{ .path = "time.selka", .text = @embedFile("stdlib/time.selka") },
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
        try joined.appendSlice(allocator, module.path[0 .. module.path.len - ".selka".len]);
    }
    return joined.toOwnedSlice(allocator);
}
