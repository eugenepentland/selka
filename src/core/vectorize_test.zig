//! `@vectorize` above a `for` loop: the loop's back edge asks LLVM for vectorization, its header
//! branch carries the location a remark names, and only the marked loop is affected.
const std = @import("std");
const support = @import("test_support.zig");
const language = @import("selka");

const marked_source =
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    @vectorize
    \\    for i in range(n):
    \\        acc = acc + i
    \\    return acc
    \\func plain(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc = acc + i
    \\    return acc
    \\func main() -> int:
    \\    return total(4) + plain(4)
;

test "a @vectorize loop's back edge carries llvm.loop with the vectorize hint, and a plain loop carries none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), marked_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "!llvm.loop !") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "!{!\"llvm.loop.vectorize.enable\", i1 true}") != null);
    // Exactly one loop is marked: one hint on a back edge, one marker comment for the driver.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, llvm, "!llvm.loop !"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, llvm, "; vectorize "));
}

test "a @vectorize loop's header branch carries the loop's location, so a remark names its source line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), marked_source);
    const marker = std.mem.indexOf(u8, llvm, "; vectorize ") orelse return error.TestUnexpectedResult;
    // The marker follows the header's conditional branch, which holds the `!dbg` on its line.
    const branch = std.mem.lastIndexOf(u8, llvm[0..marker], "br i1 ") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, llvm[branch..marker], "!dbg !") != null);
}

test "@vectorize refuses anything but a for loop, with a named rule" {
    const source = "func main() -> int:\n    @vectorize\n    const x = 1\n    return x\n";
    var compilation = try language.Compilation.init(std.testing.allocator, "vectorize.selka", source);
    defer compilation.deinit();
    try std.testing.expectError(error.SourceError, compilation.check());
    try std.testing.expectEqualStrings("E_ATTRIBUTE_TARGET", compilation.diagnostics.items[0].code);
}
