//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "std_json.my")) return @embedFile("stdlib/std_json.my");
    if (std.mem.eql(u8, path, "std_text.my")) return @embedFile("stdlib/std_text.my");
    if (std.mem.eql(u8, path, "std_result.my")) return @embedFile("stdlib/std_result.my");
    if (std.mem.eql(u8, path, "std_bytes.my")) return @embedFile("stdlib/std_bytes.my");
    if (std.mem.eql(u8, path, "std_json_view.my")) return @embedFile("stdlib/std_json_view.my");
    if (std.mem.eql(u8, path, "std_collections.my")) return @embedFile("stdlib/std_collections.my");
    if (std.mem.eql(u8, path, "std_queue.my")) return @embedFile("stdlib/std_queue.my");
    if (std.mem.eql(u8, path, "std_map.my")) return @embedFile("stdlib/std_map.my");
    if (std.mem.eql(u8, path, "std_set.my")) return @embedFile("stdlib/std_set.my");
    return null;
}
