//! Features retired in new-core stage S5 that the checker still recognises:
//! `with arena():` blocks, which check as ordinary blocks with no arena rules
//! of their own (S5-D3), and the `mylang fix` repair their warning carries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const arena_fix = @import("arena_fix.zig");

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

/// Apply `fix` to `bytes` the way `mylang fix` does: every edit at once, from
/// the end of the text backwards.
fn applied(allocator: std.mem.Allocator, bytes: []const u8, fix: diagnostic.Fix) ![]const u8 {
    const edits = try allocator.alloc(diagnostic.Edit, fix.count());
    for (edits, 0..) |*edit, index| edit.* = fix.at(index);
    std.mem.sort(diagnostic.Edit, edits, {}, struct {
        fn later(_: void, a: diagnostic.Edit, b: diagnostic.Edit) bool {
            return a.span.start > b.span.start;
        }
    }.later);
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(allocator, bytes);
    for (edits) |edit| try text.replaceRange(allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
    return text.items;
}

/// The arena block whose `with` is the first in `bytes` and whose body runs
/// from its next line to the end of the last line indented deeper than it.
fn blockOf(bytes: []const u8) arena_fix.Block {
    const with_start = std.mem.indexOf(u8, bytes, "with ").?;
    const body_line = std.mem.indexOfScalarPos(u8, bytes, with_start, '\n').? + 1;
    var body_start = body_line;
    while (bytes[body_start] == ' ') body_start += 1;
    const end = std.mem.indexOf(u8, bytes, "\n    return").?;
    return .{ .with_start = with_start, .body_start = body_start, .body_end = end };
}

// spec-case: NEW-CORE-S5-ARENA-3
test "the arena retirement fix deletes the header, dedents the body and keeps comments" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\def main() -> int:
        \\    with arena():  # phase one
        \\        x = 1
        \\
        \\# margin comment
        \\        if x > 0:
        \\            x = 2
        \\        # trailing
        \\    return x
        \\
    ;
    const fix = (try arena_fix.retirementFix(a, source, blockOf(source), &.{})).?;
    try t.expectEqualStrings(
        \\def main() -> int:
        \\    # phase one
        \\    x = 1
        \\
        \\# margin comment
        \\    if x > 0:
        \\        x = 2
        \\    # trailing
        \\    return x
        \\
    , try applied(a, source, fix));
}

// spec-case: NEW-CORE-S5-ARENA-3
test "the arena retirement fix is withheld wherever the edit is not certain" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A tab in the body's indentation.
    const tabbed = "def main() -> int:\n    with arena():\n\tx = 1\n    return x\n";
    try t.expectEqual(@as(?diagnostic.Fix, null), try arena_fix.retirementFix(a, tabbed, .{ .with_start = 23, .body_start = 38, .body_end = 43 }, &.{}));
    // A triple-quoted string, whose continuation lines must not move.
    const quoted = "def main() -> int:\n    with arena():\n        s = \"\"\"a\n  b\"\"\"\n    return len(s)\n";
    try t.expectEqual(@as(?diagnostic.Fix, null), try arena_fix.retirementFix(a, quoted, blockOf(quoted), &.{}));
    // A body that starts on the header's own line.
    const inline_body = "def main() -> int:\n    with arena(): x = 1\n    return x\n";
    const inline_with = std.mem.indexOf(u8, inline_body, "with").?;
    try t.expectEqual(@as(?diagnostic.Fix, null), try arena_fix.retirementFix(a, inline_body, .{ .with_start = inline_with, .body_start = inline_with + 14, .body_end = inline_with + 19 }, &.{}));
}

// spec-case: NEW-CORE-S5-ARENA-3
test "the arena warning carries the fix that unwraps its escapes" {
    var c = try language.Compilation.init(t.allocator, "retired.my", "def main() -> int:\n    kept = \"z\"\n    with arena() as s:\n        kept = s.escape(\"a\" + str(1))\n        n = len(s.escape(kept))\n    return n\n");
    defer c.deinit();
    try c.check();
    try t.expectEqualStrings("W_ARENA_RETIRED", c.diagnostics.items[0].code);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings(
        "def main() -> int:\n    kept = \"z\"\n    kept = (\"a\" + str(1))\n    n = len(kept)\n    return n\n",
        try applied(arena.allocator(), c.src.bytes, c.diagnostics.items[0].provenance.fix.?),
    );
}
