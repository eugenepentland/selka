//! D1 guards trap structural changes along a refreshed iteration place.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_execute.zig");
const t = std.testing;

/// The program traps `R_LIST_ITERATION_MUTATION` on the refreshed place.
fn trapsOnRefreshedPlace(source: []const u8) !void {
    var compilation = try compiler.Compilation.init(t.allocator, "live_place.my", source);
    defer compilation.deinit();
    const result = try native.runWithOptions(&compilation, .{});
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_LIST_ITERATION_MUTATION", result.trap.code);
}

// spec-case: D1-LIVE-PLACE
test "D1 live list shrink traps on the final continued step" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    for value in items:
        \\        _ = value
        \\        _ = items.pop()
        \\        continue
        \\    return 0
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 growth then shrink traps against the last observed length" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut items = [1]
        \\    for value in items:
        \\        if value == 1:
        \\            items.append(2)
        \\        else:
        \\            _ = items.pop()
        \\    return 0
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 indexed ancestor growth traps before switching storage" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut rows = [[1, 2]]
        \\    for value in rows[0]:
        \\        rows.append([value])
        \\    return 0
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 indexed ancestor shrink by mut callee traps" {
    try trapsOnRefreshedPlace(
        \\func shrink(mut rows: int[][]) -> Unit:
        \\    rows.clear()
        \\func main() -> int:
        \\    mut rows = [[1, 2]]
        \\    for value in rows[0]:
        \\        _ = value
        \\        shrink(mut rows)
        \\    return 0
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 shared dictionary growth still traps" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut values = {1: 10}
        \\    mut snapshot = values
        \\    for key in values:
        \\        values[2] = key
        \\    return len(snapshot)
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 shared set growth still traps" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut values = {1}
        \\    mut snapshot = values
        \\    for value in values:
        \\        values.add(value + 1)
        \\    return len(snapshot)
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 dictionary ancestor growth traps before indexed list refresh" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut rows = {1: [1, 2]}
        \\    for value in rows[1]:
        \\        rows[2] = [value]
        \\    return 0
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 managed ancestor of a fixed array still guards length" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut rows: FixedArray[int, 2][] = [FixedArray[int, 2]([1, 2])]
        \\    for value in rows[0]:
        \\        rows.append(FixedArray[int, 2]([value, value]))
        \\    return 0
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 managed ancestor of immutable text still guards length" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut rows = ["a🙂"]
        \\    mut snapshot = rows
        \\    for letter in rows[0]:
        \\        _ = letter
        \\        rows.clear()
        \\    return len(snapshot)
    );
}

// spec-case: D1-LIVE-PLACE
test "D1 managed ancestor of immutable bytes still guards length" {
    try trapsOnRefreshedPlace(
        \\func main() -> int:
        \\    mut rows = [b"ab"]
        \\    mut snapshot = rows
        \\    for octet in rows[0]:
        \\        rows.append(b"cd")
        \\        _ = octet
        \\    return len(snapshot)
    );
}
