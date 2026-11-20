//! List extrema carry a scalar index and borrow the selected element.
const std = @import("std");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");

fn check(allocator: std.mem.Allocator, text: []const u8, expected: ?[]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a, text);
    var failure: contract.Failure = .{};
    if (expected) |code| {
        try std.testing.expectError(error.Rejected, contract.check(a, program, &failure));
        try std.testing.expectEqualStrings(code, failure.code);
    } else {
        try contract.check(a, program, &failure);
    }
}

// spec-case: PRELUDE-EXTREME-1
test "A04 list extrema borrow selected text and permit an explicit independent copy" {
    try check(std.testing.allocator,
        \\import lists
        \\
        \\func choose(words: str[]) -> str:
        \\    return copy(min(words))
        \\func main() -> int:
        \\    mut words = ["z" + str(1), "a" + str(2)]
        \\    const saved = choose(words)
        \\    lists.clear(mut words)
        \\    if saved == "a2":
        \\        return 0
        \\    else:
        \\        return 1
    , null);
}

// spec-case: PRELUDE-EXTREME-1
// R3b: a returned extremum of a list parameter is an accepted borrow (tests/lang/borrowed_results.selka pins it).
