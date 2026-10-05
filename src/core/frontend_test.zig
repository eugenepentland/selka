//! Front-end adapter tests.
const std = @import("std");
const frontend = @import("frontend.zig");
const language = @import("mylang");

// spec: NEW-CORE-FRONTEND-1
test "an entry path splits into the loader root and module name, and offsets map to lines and columns" {
    const entry = frontend.entryOf("bench/kernels/int_math.my");
    try std.testing.expectEqualStrings("bench/kernels", entry.root);
    try std.testing.expectEqualStrings("int_math", entry.module);
    const bare = frontend.entryOf("main.my");
    try std.testing.expectEqualStrings(".", bare.root);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "p.my", "a = 1\nbb = 22\n");
    const at = frontend.position(src, .{ .start = 9, .end = 10 });
    try std.testing.expectEqual(@as(u32, 2), at.line);
    try std.testing.expectEqual(@as(u32, 4), at.column);
    try std.testing.expectEqualStrings("p.my", at.path);
}
