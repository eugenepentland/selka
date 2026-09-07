//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "std_math.my")) return @embedFile("stdlib/std_math.my");
    if (std.mem.eql(u8, path, "std_json.my")) return @embedFile("stdlib/std_json.my");
    if (std.mem.eql(u8, path, "std_text.my")) return @embedFile("stdlib/std_text.my");
    if (std.mem.eql(u8, path, "std_result.my")) return @embedFile("stdlib/std_result.my");
    if (std.mem.eql(u8, path, "std_bytes.my")) return @embedFile("stdlib/std_bytes.my");
    if (std.mem.eql(u8, path, "std_json_view.my")) return @embedFile("stdlib/std_json_view.my");
    if (std.mem.eql(u8, path, "std_collections.my")) return @embedFile("stdlib/std_collections.my");
    if (std.mem.eql(u8, path, "std_queue.my")) return @embedFile("stdlib/std_queue.my");
    if (std.mem.eql(u8, path, "std_map.my")) return @embedFile("stdlib/std_map.my");
    if (std.mem.eql(u8, path, "std_set.my")) return @embedFile("stdlib/std_set.my");
    if (std.mem.eql(u8, path, "std_unit.my")) return @embedFile("stdlib/std_unit.my");
    if (std.mem.eql(u8, path, "std_time.my")) return @embedFile("stdlib/std_time.my");
    if (std.mem.eql(u8, path, "std_random.my")) return @embedFile("stdlib/std_random.my");
    if (std.mem.eql(u8, path, "std_hash.my")) return @embedFile("stdlib/std_hash.my");
    if (std.mem.eql(u8, path, "std_hash_map.my")) return @embedFile("stdlib/std_hash_map.my");
    if (std.mem.eql(u8, path, "std_hash_bytes.my")) return @embedFile("stdlib/std_hash_bytes.my");
    if (std.mem.eql(u8, path, "std_borrowed_set.my")) return @embedFile("stdlib/std_borrowed_set.my");
    if (std.mem.eql(u8, path, "std_hash_set.my")) return @embedFile("stdlib/std_hash_set.my");
    if (std.mem.eql(u8, path, "std_hash_byte_set.my")) return @embedFile("stdlib/std_hash_byte_set.my");
    if (std.mem.eql(u8, path, "std_strings.my")) return @embedFile("stdlib/std_strings.my");
    if (std.mem.eql(u8, path, "std_encoding.my")) return @embedFile("stdlib/std_encoding.my");
    if (std.mem.eql(u8, path, "std_format.my")) return @embedFile("stdlib/std_format.my");
    if (std.mem.eql(u8, path, "std_args.my")) return @embedFile("stdlib/std_args.my");
    if (std.mem.eql(u8, path, "std_json_builder.my")) return @embedFile("stdlib/std_json_builder.my");
    return null;
}
