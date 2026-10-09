//! Features retired in new-core stage S5 that the checker still recognises:
//! removed `with arena():` blocks and the structured repair their error carries;
//! and `host def`, refused at check time (S5-D5).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const arena_fix = @import("arena_fix.zig");
const retired_path = "retired.my";

/// Require the removal error, apply its fixes, and require a clean check.
/// Return the original diagnostic codes so nested removals remain covered.
fn migrated(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var c = try language.Compilation.init(t.allocator, retired_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    var codes: std.ArrayList(u8) = .empty;
    for (c.diagnostics.items, 0..) |item, index| {
        if (index != 0) try codes.append(allocator, ',');
        try codes.appendSlice(allocator, item.code);
        try t.expectEqualStrings("E_ARENA_REMOVED", item.code);
        try t.expectEqual(diagnostic.Severity.err, item.severity);
    }
    var text = try applied(allocator, source, c.diagnostics.items[0].provenance.fix.?);
    for (0..4) |_| {
        var next = try language.Compilation.init(t.allocator, "migrated.my", text);
        defer next.deinit();
        next.check() catch |err| {
            try t.expectEqual(error.SourceError, err);
            try t.expectEqualStrings("E_ARENA_REMOVED", next.diagnostics.items[0].code);
            text = try applied(allocator, text, next.diagnostics.items[0].provenance.fix.?);
            continue;
        };
        return codes.toOwnedSlice(allocator);
    }
    return error.TestUnexpectedResult;
}

/// Check `source` and require its first diagnostic to carry `code`.
fn rejected(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, retired_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const found = for (c.diagnostics.items) |item| {
        if (std.mem.eql(u8, code, item.code)) break true;
    } else false;
    try t.expect(found);
}

// spec: NEW-CORE-S5-ARENA-2
// spec: FRONTEND-ARENA-REMOVED-1
test "removed arena blocks migrate across stores returns and nested escapes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Assigning, storing and returning a managed value across the block, and
    // updating a binding declared outside it, check as they would
    // without the block: the removal repair preserves these values.
    try t.expectEqualStrings("E_ARENA_REMOVED", try migrated(a,
        \\func main() -> int:
        \\    mut keeper: int[] = []
        \\    with arena() as scratch:
        \\        keeper = [1, 2]
        \\    return len(keeper)
    ));
    try t.expectEqualStrings("E_ARENA_REMOVED", try migrated(a,
        \\func main() -> int:
        \\    mut outer: str[] = []
        \\    mut seen: set[str] = set()
        \\    mut inside = ""
        \\    with arena():
        \\        inside = "a" + str(1)
        \\        outer.append(inside)
        \\        seen.add(inside)
        \\    return len(outer) + len(seen) + len(inside)
    ));
    try t.expectEqualStrings("E_ARENA_REMOVED", try migrated(a,
        \\func build() -> int[]:
        \\    with arena():
        \\        return [1, 2, 3]
        \\
        \\func main() -> int:
        \\    return len(build())
    ));
    // `name.escape(value)` is `value`, from any enclosing arena, nested or not.
    try t.expectEqualStrings("E_ARENA_REMOVED,E_ARENA_REMOVED", try migrated(a,
        \\func main() -> int:
        \\    mut kept = "z"
        \\    with arena() as outer:
        \\        with arena() as inner:
        \\            kept = outer.escape("a" + str(2))
        \\    return len(kept)
    ));
    // The binding name has no other use: anything else is diagnosed as the
    // same use of an undefined name is.
    try rejected(
        \\func main() -> int:
        \\    with arena() as scratch:
        \\        mut other = scratch
        \\    return 0
    , "E_UNKNOWN_NAME");
    try rejected(
        \\func main() -> int:
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
        \\func main() -> int:
        \\    with arena():  # phase one
        \\        mut x = 1
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
        \\func main() -> int:
        \\    # phase one
        \\    mut x = 1
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
    const tabbed = "func main() -> int:\n    with arena():\n\tx = 1\n    return x\n";
    try t.expectEqual(@as(?diagnostic.Fix, null), try arena_fix.retirementFix(a, tabbed, .{ .with_start = 23, .body_start = 38, .body_end = 43 }, &.{}));
    // A triple-quoted string, whose continuation lines must not move.
    const quoted = "func main() -> int:\n    with arena():\n        s = \"\"\"a\n  b\"\"\"\n    return len(s)\n";
    try t.expectEqual(@as(?diagnostic.Fix, null), try arena_fix.retirementFix(a, quoted, blockOf(quoted), &.{}));
    // A body that starts on the header's own line.
    const inline_body = "func main() -> int:\n    with arena(): x = 1\n    return x\n";
    const inline_with = std.mem.indexOf(u8, inline_body, "with").?;
    try t.expectEqual(@as(?diagnostic.Fix, null), try arena_fix.retirementFix(a, inline_body, .{ .with_start = inline_with, .body_start = inline_with + 14, .body_end = inline_with + 19 }, &.{}));
}

// spec-case: NEW-CORE-S5-ARENA-3
test "the arena removal error carries the fix that unwraps its escapes" {
    var c = try language.Compilation.init(t.allocator, retired_path, "func main() -> int:\n    mut kept = \"z\"\n    mut n = 0" ++
        "\n    with arena() as s:\n        kept = s.escape(\"a\" + str(1))\n        n = len(s.escape(kept))\n    return n\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_ARENA_REMOVED", c.diagnostics.items[0].code);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings(
        "func main() -> int:\n    mut kept = \"z\"\n    mut n = 0\n    kept = (\"a\" + str(1))\n    n = len(kept)\n    return n\n",
        try applied(arena.allocator(), c.src.bytes, c.diagnostics.items[0].provenance.fix.?),
    );
}

// spec: NEW-CORE-S5-HOST-1
test "a host declaration is refused at check time with the extern replacement named" {
    var c = try language.Compilation.init(t.allocator, retired_path,
        \\host func measure(host: Host, x: i64) -> i64 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return measure(host, 6)
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqual(@as(usize, 1), c.diagnostics.items.len);
    const refusal = c.diagnostics.items[0];
    try t.expectEqualStrings("E_HOST_RETIRED", refusal.code);
    try t.expectEqualStrings("host", c.src.text(refusal.span));
    try t.expect(std.mem.indexOf(u8, refusal.message, "declare the function `extern func`") != null);
    try t.expect(std.mem.indexOf(u8, refusal.message, "--link FILE.c") != null);
    // The same declaration spelled `extern func` checks.
    var extern_unit = try language.Compilation.init(t.allocator, "extern.my",
        \\extern func measure(host: Host, x: i64) -> i64 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return measure(host, 6)
    );
    defer extern_unit.deinit();
    try extern_unit.check();
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "checkCore arena removal preserves its real fix alongside an independent semantic error" {
    var compilation = try language.Compilation.init(t.allocator, retired_path, "func main() -> int:\n    with arena():\n        const count = 1\n        return count + missing\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_ARENA_REMOVED", compilation.diagnostics.items[0].code);
    try t.expect(compilation.diagnostics.items[0].provenance.fix != null);
    try t.expectEqualStrings("E_UNKNOWN_NAME", compilation.diagnostics.items[1].code);
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds fixes when its name is shadowed by an ordinary local" {
    var compilation = try language.Compilation.init(t.allocator, retired_path,
        \\record Local:
        \\    value: int
        \\func main() -> int:
        \\    with arena() as scratch:
        \\        const scratch = Local(value=1)
        \\        return scratch.escape(42)
        \\
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_ARENA_REMOVED", compilation.diagnostics.items[0].code);
    try t.expectEqual(@as(?diagnostic.Fix, null), compilation.diagnostics.items[0].provenance.fix);
    try t.expect(compilation.diagnostics.items.len > 1);
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds dedent when a later declaration would collide" {
    var compilation = try language.Compilation.init(t.allocator, retired_path,
        \\func main() -> int:
        \\    with arena():
        \\        const token = 1
        \\    const token = 2
        \\    return token
        \\
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_ARENA_REMOVED", compilation.diagnostics.items[0].code);
    try t.expectEqual(@as(?diagnostic.Fix, null), compilation.diagnostics.items[0].provenance.fix);
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds escape rewrites when a loop rebinds its name" {
    var compilation = try language.Compilation.init(t.allocator, retired_path,
        \\func main() -> int:
        \\    with arena() as scratch:
        \\        for scratch in [1]:
        \\            return scratch.escape(42)
        \\        return 0
        \\
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_ARENA_REMOVED", compilation.diagnostics.items[0].code);
    try t.expectEqual(@as(?diagnostic.Fix, null), compilation.diagnostics.items[0].provenance.fix);
}

fn legacyArenaFixAvailable(text: []const u8) !bool {
    var compilation = try language.Compilation.init(t.allocator, retired_path, text);
    defer compilation.deinit();
    const allocator = compilation.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = try @import("lexer.zig").lex(allocator, compilation.src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = compilation.src, .storage = allocator, .tokens = tokens, .sink = &sink, .cursor = .{ .dialect = .migration } };
    const syntax = try parser.parse();
    try arena_fix.reject(allocator, compilation.src, syntax, &sink);
    for (sink.items.items) |item| {
        if (std.mem.eql(u8, item.code, arena_fix.removed_code)) return item.provenance.fix != null;
    }
    return error.TestUnexpectedResult;
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds dedent of a colliding legacy implicit declaration" {
    try t.expect(!try legacyArenaFixAvailable("func main() -> int:\n    with arena():\n        token = 1\n    token = 2\n    return token\n"));
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds escape rewrites for legacy callback and gather binders" {
    try t.expect(!try legacyArenaFixAvailable("func main() -> int:\n    with arena() as scratch:\n        const action = lambda scratch: scratch.escape(42)\n        return 0\n"));
    try t.expect(!try legacyArenaFixAvailable("func main() -> int:\n    with arena() as scratch:\n        const values = [scratch.escape(42) for scratch in [1] for other in [2]]\n        return 0\n"));
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds escape rewrites for legacy match payload bindings" {
    try t.expect(!try legacyArenaFixAvailable("union Choice:\n    item: int\nfunc main() -> int:\n    with arena() as scratch:\n" ++
        "        match Choice.item(1):\n            case Choice.item(scratch):\n                return scratch.escape(42)\n        return 0\n"));
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds explicit dedent that captures a later global function call" {
    try t.expect(!try legacyArenaFixAvailable("func answer() -> int:\n    return 7\nfunc main() -> int:\n    with arena():\n        const answer = 1\n    return answer()\n"));
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement withholds explicit dedent that captures a later global value" {
    try t.expect(!try legacyArenaFixAvailable("const answer: int = 7\nfunc main() -> int:\n    with arena():\n        const answer = 1\n    return answer\n"));
}

// spec-case: FRONTEND-ARENA-REMOVED-1
test "arena retirement preserves legacy implicit scope migration for a later read" {
    try t.expect(try legacyArenaFixAvailable("func main() -> int:\n    with arena():\n        size = 1\n    return size\n"));
}
