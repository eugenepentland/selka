//! Features retired in new-core stage S5 that the checker still recognises:
//! `with arena():` blocks, which check as ordinary blocks with no arena rules
//! of their own (S5-D3).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check `source`, require it to pass, and answer the codes of its diagnostics
/// joined by commas (warnings only, since the check passed).
fn accepted(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var c = try language.Compilation.init(t.allocator, "retired.my", source);
    defer c.deinit();
    try c.check();
    var codes: std.ArrayList(u8) = .empty;
    for (c.diagnostics.items, 0..) |item, index| {
        if (index != 0) try codes.append(allocator, ',');
        try codes.appendSlice(allocator, item.code);
    }
    return codes.toOwnedSlice(allocator);
}

/// Check `source` and require its first diagnostic to carry `code`.
fn rejected(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "retired.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: NEW-CORE-S5-ARENA-2
test "an arena block has no escape, confinement or binding rules of its own" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Assigning, storing and returning a managed value across the block, and
    // reading a binding first assigned inside it afterwards, check as they would
    // without the block: only the retirement warning remains.
    try t.expectEqualStrings("W_ARENA_RETIRED", try accepted(a,
        \\def main() -> int:
        \\    keeper: list[int] = []
        \\    with arena() as scratch:
        \\        keeper = [1, 2]
        \\    return len(keeper)
    ));
    try t.expectEqualStrings("W_ARENA_RETIRED", try accepted(a,
        \\def main() -> int:
        \\    outer: list[str] = []
        \\    seen: set[str] = set()
        \\    with arena():
        \\        inside = "a" + str(1)
        \\        outer.append(inside)
        \\        seen.add(inside)
        \\    return len(outer) + len(seen) + len(inside)
    ));
    try t.expectEqualStrings("W_ARENA_RETIRED", try accepted(a,
        \\def build() -> list[int]:
        \\    with arena():
        \\        return [1, 2, 3]
        \\
        \\def main() -> int:
        \\    return len(build())
    ));
    // `name.escape(value)` is `value`, from any enclosing arena, nested or not.
    try t.expectEqualStrings("W_ARENA_RETIRED,W_ARENA_RETIRED", try accepted(a,
        \\def main() -> int:
        \\    kept = "z"
        \\    with arena() as outer:
        \\        with arena() as inner:
        \\            kept = outer.escape("a" + str(2))
        \\    return len(kept)
    ));
    // The binding name has no other use: anything else is diagnosed as the
    // same use of an undefined name is.
    try rejected(
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        other = scratch
        \\    return 0
    , "E_UNKNOWN_NAME");
    try rejected(
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        scratch.reset()
        \\    return 0
    , "E_UNKNOWN_TYPE");
}
