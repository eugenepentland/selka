//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "std_json.my")) return @embedFile("stdlib/std_json.my");
    if (std.mem.eql(u8, path, "std_text.my")) return @embedFile("stdlib/std_text.my");
    return null;
}
