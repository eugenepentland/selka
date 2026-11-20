//! The sentence a revealing rename's refusal adds (FR19): one error and several, and a long message cut.
const std = @import("std");
const t = std.testing;
const revealed = @import("rename_revealed.zig");

// spec: RENAME-CLI-17
test "one revealed error is quoted with its code and message and its place is said to follow" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = try revealed.sentence(arena.allocator(), .{ .count = 1, .severity = "error", .code = "E_BORROW_MIXED", .message = "wrap each borrowed return in copy(...)" });
    try t.expectEqualStrings(". The rename itself is right: the name clash had stopped the check of the function it is in, so the program had an " ++
        "error that no check could show: error[E_BORROW_MIXED]: wrap each borrowed return in copy(...). Its place is printed below. " ++
        "Fix it, then run the same command again", text);
}

// spec: RENAME-CLI-17
test "several revealed errors name the first and say that their places follow" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = try revealed.sentence(arena.allocator(), .{ .count = 3, .severity = "error", .code = "E_X", .message = "first" });
    try t.expect(std.mem.indexOf(u8, text, "so the program had errors that no check could show; the first is error[E_X]: first. Their places are printed below. Fix them, then") != null);
}

// spec: RENAME-CLI-17
test "a message longer than the limit is cut" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const long = try a.alloc(u8, 300);
    @memset(long, 'x');
    const text = try revealed.sentence(a, .{ .count = 1, .severity = "error", .code = "E_X", .message = long });
    const cut = try std.fmt.allocPrint(a, "{s}. Its place", .{long[0..240]});
    try t.expect(std.mem.indexOf(u8, text, cut) != null);
    try t.expect(std.mem.indexOf(u8, text, long[0..241]) == null);
}
