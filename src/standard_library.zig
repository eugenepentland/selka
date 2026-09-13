//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
const Module = struct { path: []const u8, text: []const u8 };
const modules = [_]Module{
    .{ .path = "std_iter.my", .text = @embedFile("stdlib/std_iter.my") },
    .{ .path = "std_math.my", .text = @embedFile("stdlib/std_math.my") },
    .{ .path = "std_result.my", .text = @embedFile("stdlib/std_result.my") },
    .{ .path = "std_unit.my", .text = @embedFile("stdlib/std_unit.my") },
    .{ .path = "std_time.my", .text = @embedFile("stdlib/std_time.my") },
    .{ .path = "std_random.my", .text = @embedFile("stdlib/std_random.my") },
};
/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    for (modules) |module| if (std.mem.eql(u8, path, module.path)) return module.text;
    return null;
}
