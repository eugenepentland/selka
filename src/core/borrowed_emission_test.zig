//! Borrowed payload memory layouts at native wrapper and writeback boundaries.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");

test "O3 borrowed text and byte spans use word aligned wrapper payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const writeback = try module.intern(a, .{ .record = &.{ .u64, .str_view, .bytes_view } });
    try std.testing.expectEqual(@as(u32, 8), module.alignment(.str_view));
    try std.testing.expectEqual(@as(u32, 8), module.alignment(.bytes_view));
    try std.testing.expectEqual(@as(u32, 8), module.fieldOffset(writeback, 1));
    try std.testing.expectEqual(@as(u32, 24), module.fieldOffset(writeback, 2));
    try std.testing.expectEqual(@as(u32, 40), module.size(writeback));
    const llvm = try support.llvmText(a,
        \\func text(value: str, bad: bool) -> str from value fails str:
        \\    if bad:
        \\        fail "text error"
        \\    return value[0:2]
        \\func bytes_part(value: bytes, bad: bool) -> bytes from value fails str:
        \\    if bad:
        \\        fail "bytes error"
        \\    return value[1:3]
        \\func main() -> int:
        \\    const first = text("abcd", False)
        \\    match first:
        \\        case Ok(value):
        \\            assert value == "ab"
        \\        case Err(message):
        \\            return len(message)
        \\    const second = bytes_part(b"abcd", False)
        \\    match second:
        \\        case Ok(value):
        \\            assert value == b"bc"
        \\        case Err(message):
        \\            return len(message)
        \\    return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, llvm, "store { ptr, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load { ptr, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "align 16") == null);
}
