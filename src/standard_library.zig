//! Reserved standard modules are identical for disk, embedded and inspection providers.
const std = @import("std");
const Module = struct { path: []const u8, text: []const u8 };
const modules = [_]Module{
    .{ .path = "std_counter.my", .text = @embedFile("stdlib/std_counter.my") },
    .{ .path = "std_graph.my", .text = @embedFile("stdlib/std_graph.my") },
    .{ .path = "std_order.my", .text = @embedFile("stdlib/std_order.my") },
    .{ .path = "std_ascii.my", .text = @embedFile("stdlib/std_ascii.my") },
    .{ .path = "std_iter.my", .text = @embedFile("stdlib/std_iter.my") },

    .{ .path = "std_math.my", .text = @embedFile("stdlib/std_math.my") },
    .{ .path = "std_json.my", .text = @embedFile("stdlib/std_json.my") },
    .{ .path = "std_text.my", .text = @embedFile("stdlib/std_text.my") },
    .{ .path = "std_result.my", .text = @embedFile("stdlib/std_result.my") },
    .{ .path = "std_bytes.my", .text = @embedFile("stdlib/std_bytes.my") },
    .{ .path = "std_json_view.my", .text = @embedFile("stdlib/std_json_view.my") },
    .{ .path = "std_collections.my", .text = @embedFile("stdlib/std_collections.my") },
    .{ .path = "std_queue.my", .text = @embedFile("stdlib/std_queue.my") },
    .{ .path = "std_map.my", .text = @embedFile("stdlib/std_map.my") },
    .{ .path = "std_set.my", .text = @embedFile("stdlib/std_set.my") },
    .{ .path = "std_unit.my", .text = @embedFile("stdlib/std_unit.my") },
    .{ .path = "std_time.my", .text = @embedFile("stdlib/std_time.my") },
    .{ .path = "std_random.my", .text = @embedFile("stdlib/std_random.my") },
    .{ .path = "std_hash.my", .text = @embedFile("stdlib/std_hash.my") },
    .{ .path = "std_hash_map.my", .text = @embedFile("stdlib/std_hash_map.my") },
    .{ .path = "std_hash_bytes.my", .text = @embedFile("stdlib/std_hash_bytes.my") },
    .{ .path = "std_borrowed_set.my", .text = @embedFile("stdlib/std_borrowed_set.my") },
    .{ .path = "std_hash_set.my", .text = @embedFile("stdlib/std_hash_set.my") },
    .{ .path = "std_hash_byte_set.my", .text = @embedFile("stdlib/std_hash_byte_set.my") },
    .{ .path = "std_strings.my", .text = @embedFile("stdlib/std_strings.my") },
    .{ .path = "std_encoding.my", .text = @embedFile("stdlib/std_encoding.my") },
    .{ .path = "std_format.my", .text = @embedFile("stdlib/std_format.my") },
    .{ .path = "std_args.my", .text = @embedFile("stdlib/std_args.my") },
    .{ .path = "std_json_builder.my", .text = @embedFile("stdlib/std_json_builder.my") },
    .{ .path = "std_io.my", .text = @embedFile("stdlib/std_io.my") },
    .{ .path = "std_path.my", .text = @embedFile("stdlib/std_path.my") },
    .{ .path = "std_fs.my", .text = @embedFile("stdlib/std_fs.my") },
    .{ .path = "std_owned.my", .text = @embedFile("stdlib/std_owned.my") },
    .{ .path = "std_owned_map.my", .text = @embedFile("stdlib/std_owned_map.my") },
};
/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    for (modules) |module| if (std.mem.eql(u8, path, module.path)) return module.text;
    return null;
}
