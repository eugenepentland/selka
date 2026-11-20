//! Required dictionary removal transfers managed values along the proven edge.
const std = @import("std");
const language = @import("selka");
const build = @import("build.zig");
const ownership = @import("single_owner.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

fn executes(parent: std.mem.Allocator, source: []const u8, status: u8, diagnostic: []const u8) !bool {
    for ([_]passes.Mode{ .off, .trusted, .verify }) |mode| {
        var arena = std.heap.ArenaAllocator.init(parent);
        defer arena.deinit();
        const a = arena.allocator();
        // Checked through the core's shared runner, which takes an embedded project
        // when the program imports a standard module.
        const checked = try support.checkSource(a, source);
        try std.testing.expect(checked.passed);
        var failure: ownership.Failure = .{};
        try ownership.check(a, checked.program.?, &failure);
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = checked.program.? }, &refusal);
        const result = if (mode == .off) try passes.debug(a, &module) else try passes.run(a, &module, mode);
        const ran = try support.runOwned(a, &module, .{ .own = false, .release = mode != .off, .verify = mode == .verify, .analysis = support.analysis(&result), .main = .{} });
        try std.testing.expectEqual(status, ran.status);
        try std.testing.expectEqualStrings("", ran.stdout);
        if (diagnostic.len == 0) try std.testing.expectEqualStrings("", ran.stderr) else try std.testing.expect(std.mem.indexOf(u8, ran.stderr, diagnostic) != null);
    }
    return true;
}

// spec-case: NEW-CORE-DICT-1
test "ownership dictionary pop transfers a nested managed value and evaluates its key once" {
    try std.testing.expect(try executes(std.testing.allocator,
        \\import dicts
        \\
        \\record Holder:
        \\    values: dict[int, str[]]
        \\func key(mut events: int[]) -> int:
        \\    append(mut events, 2)
        \\    return 2
        \\func main() -> int:
        \\    mut holder = Holder(values={1: ["a" + str(1)], 2: ["b" + str(2)]})
        \\    const saved = copy(holder)
        \\    append(mut holder.values[1], "tail" + str(3))
        \\    mut events: int[] = []
        \\    mut removed = dicts.pop(mut holder.values, key(mut events))
        \\    append(mut removed, "end" + str(4))
        \\    assert len(holder.values) == 1
        \\    assert holder.values[1][1] == "tail3"
        \\    assert saved.values[2][0] == "b2"
        \\    holder.values[2] = copy(removed)
        \\    assert holder.values[2][1] == "end4"
        \\    return len(events) * 10 + len(removed)
    , 12, ""));
}

// spec-case: NEW-CORE-DICT-1
test "ownership dictionary pop default evaluates arguments once and removes only present keys" {
    try std.testing.expect(try executes(std.testing.allocator,
        \\import dicts
        \\
        \\func key(mut events: int[], value: int) -> int:
        \\    append(mut events, value)
        \\    return value
        \\func fallback(mut events: int[]) -> int:
        \\    append(mut events, 9)
        \\    return 42
        \\func main() -> int:
        \\    mut values = {1: 7, 3: 11}
        \\    mut events: int[] = []
        \\    const present = dicts.pop_default(mut values, key(mut events, 1), fallback(mut events))
        \\    const missing = dicts.pop_default(mut values, key(mut events, 2), fallback(mut events))
        \\    assert present == 7 and missing == 42
        \\    assert len(values) == 1 and values[3] == 11
        \\    assert events == [1, 9, 2, 9]
        \\    return 0
    , 0, ""));
}

// spec-case: NEW-CORE-DICT-1
test "ownership dictionary pop without a fallback preserves the missing key trap" {
    try std.testing.expect(try executes(std.testing.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut values: dict[int, int] = {}
        \\    return dicts.pop(mut values, 7)
    , 1, "error[R_MISSING_KEY]"));
}
