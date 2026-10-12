//! List extrema carry a scalar index and borrow the selected element.
const std = @import("std");
const language = @import("mylang");
const contract = @import("single_owner.zig");

fn check(allocator: std.mem.Allocator, text: []const u8, expected: ?[]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "extrema.my", text);
    try unit.check();
    var failure: contract.Failure = .{};
    if (expected) |code| {
        try std.testing.expectError(error.Rejected, contract.checkMode(a, unit.program.?, &failure, true));
        try std.testing.expectEqualStrings(code, failure.code);
    } else {
        try contract.checkMode(a, unit.program.?, &failure, true);
    }
}

// spec-case: PRELUDE-EXTREME-1
test "A04 list extrema borrow selected text and permit an explicit independent copy" {
    try check(std.testing.allocator,
        \\func choose(words: str[]) -> str:
        \\    return min(words).copy()
        \\func main() -> int:
        \\    mut words = ["z" + str(1), "a" + str(2)]
        \\    const saved = choose(words)
        \\    words.clear()
        \\    return if saved == "a2" then 0 else 1
    , null);
}

// spec-case: PRELUDE-EXTREME-1
test "A04 list extrema do not permit borrowed selected text to escape" {
    try check(std.testing.allocator,
        \\func choose(words: str[]) -> str:
        \\    return min(words)
        \\func main() -> int:
        \\    return len(choose(["a" + str(1)]))
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: PRELUDE-EXTREME-1
test "A04 list extrema views invalidate when their parent is replaced" {
    try check(std.testing.allocator,
        \\func main() -> int:
        \\    mut words = ["a" + str(1), "z" + str(2)]
        \\    const selected = min(words).borrow(0, 1)
        \\    words[0] = "changed"
        \\    return len(selected)
    , "E_ZERO_RC_VIEW_INVALIDATED");
}

// spec-case: PRELUDE-EXTREME-1
test "A04 list extrema views invalidate when their parent moves" {
    try check(std.testing.allocator,
        \\func main() -> int:
        \\    mut words = ["a" + str(1), "z" + str(2)]
        \\    const selected = max(words).borrow(0, 1)
        \\    const moved = words
        \\    return len(selected) + len(moved)
    , "E_ZERO_RC_VIEW_INVALIDATED");
}
