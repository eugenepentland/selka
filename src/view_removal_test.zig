//! Wave 3 §5.4 removed the prototype view spelling: `.borrow()` and the
//! `TextView`/`ByteView` type names. A slice is a view of its source, and both
//! refusals name the repair so `selka fix` migrates a program.
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");

// spec: BORROW-VIEWS-REMOVED-1
test "a removed borrow call carries the slice repair" {
    const source =
        \\func my_take(text: str) -> int:
        \\    const piece = text.borrow(0, 2)
        \\    return len(piece)
        \\func main() -> int:
        \\    return my_take("abcdef")
    ;
    var unit = try language.Compilation.init(testing.allocator, "borrow.selka", source);
    defer unit.deinit();
    try testing.expectError(error.SourceError, unit.check());
    const diagnostic = unit.diagnostics.items[0];
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", diagnostic.code);
    try testing.expectEqualStrings("text[0:2]", diagnostic.provenance.fix.?.edit.text);
}

// spec: BORROW-VIEWS-REMOVED-1
test "a text view annotation renames to str" {
    const source =
        \\func tail(source: TextView) -> str:
        \\    return source
        \\func main() -> int:
        \\    return 0
    ;
    var unit = try language.Compilation.init(testing.allocator, "text-view.selka", source);
    defer unit.deinit();
    try testing.expectError(error.SourceError, unit.check());
    const diagnostic = unit.diagnostics.items[0];
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", diagnostic.code);
    try testing.expectEqualStrings("str", diagnostic.provenance.fix.?.edit.text);
}

// spec: BORROW-VIEWS-REMOVED-1
test "a byte view annotation renames to bytes" {
    const source =
        \\func tail(source: bytes) -> ByteView:
        \\    return source
        \\func main() -> int:
        \\    return 0
    ;
    var unit = try language.Compilation.init(testing.allocator, "byte-view.selka", source);
    defer unit.deinit();
    try testing.expectError(error.SourceError, unit.check());
    const diagnostic = unit.diagnostics.items[0];
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", diagnostic.code);
    try testing.expectEqualStrings("bytes", diagnostic.provenance.fix.?.edit.text);
}

fn expectRemovedRange(source: []const u8, replacement: []const u8) !void {
    var unit = try language.Compilation.init(testing.allocator, "removed-range.selka", source);
    defer unit.deinit();
    try testing.expectError(error.SourceError, unit.checkLibrary());
    const diagnostic = unit.diagnostics.items[0];
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", diagnostic.code);
    try testing.expect(std.mem.startsWith(u8, diagnostic.message, "`.view(start, end)` was removed"));
    try testing.expectEqual(@as(?language.diagnostic.Rule, null), diagnostic.provenance.rule);
    const edit = diagnostic.provenance.fix.?.edit;
    try testing.expectEqualStrings(replacement, edit.text);
    const repaired = try std.mem.concat(testing.allocator, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    defer testing.allocator.free(repaired);
    var fixed = try language.Compilation.init(testing.allocator, "repaired-range.selka", repaired);
    defer fixed.deinit();
    try fixed.checkLibrary();
}

/// `expectRemovedRange` for a library that imports a standard module: it is checked as the entry module of an embedded
/// project, whose spans index the merged source, so the repair is applied at the entry's offset in it.
fn expectRemovedRangeProject(source: []const u8, replacement: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try libraryProject(a, source);
    try testing.expect(!first.passed);
    const diagnostic = first.diagnostics[0];
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", diagnostic.code);
    try testing.expect(std.mem.startsWith(u8, diagnostic.message, "`.view(start, end)` was removed"));
    try testing.expectEqual(@as(?language.diagnostic.Rule, null), diagnostic.provenance.rule);
    const edit = diagnostic.provenance.fix.?.edit;
    try testing.expectEqualStrings(replacement, edit.text);
    const base = std.mem.indexOf(u8, first.src.bytes, source) orelse return error.TestUnexpectedResult;
    const repaired = try std.mem.concat(a, u8, &.{ source[0 .. edit.span.start - base], edit.text, source[edit.span.end - base ..] });
    try testing.expect((try libraryProject(a, repaired)).passed);
}

/// The diagnostics of checking `source` as a library that may import standard modules, the merged source their spans
/// index, and whether it checked.
const LibraryCheck = struct { diagnostics: []const language.diagnostic.Diagnostic, src: language.source.Source, passed: bool };

/// Check `source` as the entry module of an embedded project with no `main`; `a` owns every part.
fn libraryProject(a: std.mem.Allocator, source: []const u8) !LibraryCheck {
    const fixture = @import("stdlib_fixture.zig");
    var entry: fixture.Entry = .{ .text = source };
    const project = try a.create(language.project.Project);
    project.* = language.project.Project.init(a);
    try project.load(.{ .context = &entry, .read = fixture.Entry.read }, "main", .{});
    const index = try a.create(language.interfaces.Index);
    index.* = try language.interfaces.build(project);
    const compilation = try a.create(language.project_compile.Compilation);
    compilation.* = try language.project_compile.Compilation.init(index);
    const passed = if (compilation.checkLibrary()) |_| true else |failure| switch (failure) {
        error.SourceError => false,
        else => return failure,
    };
    return .{ .diagnostics = compilation.diagnostics.items.items, .src = compilation.src, .passed = passed };
}

test "removed retained view on a named byte value carries a slice repair" {
    try expectRemovedRange(
        \\func my_take(raw: bytes) -> int:
        \\    return len(raw.view(0, 2))
    , "raw[0:2]");
}

test "removed retained view on an expression preserves receiver parentheses" {
    try expectRemovedRange(
        \\func my_take() -> int:
        \\    return len(b"abcdef".view(0, 2))
    , "(b\"abcdef\")[0:2]");
}

test "removed retained view on a module constant carries a slice repair" {
    try expectRemovedRange(
        \\const RAW: bytes = b"abcdef"
        \\func my_take() -> int:
        \\    return len(RAW.view(0, 2))
    , "RAW[0:2]");
}

test "removed retained view is refused before numeric range fusion" {
    // The parse is `bytes.parse_int` now (W13-S5), which needs `import bytes`, so the library is an embedded project.
    try expectRemovedRangeProject(
        \\import bytes
        \\
        \\func number(raw: bytes) -> int?:
        \\    return bytes.parse_int(raw.view(0, 2))
    , "raw[0:2]");
}

test "removed retained view in an uninstantiated generic body carries a slice repair" {
    try expectRemovedRange(
        \\func my_take[T](raw: bytes, marker: T) -> int:
        \\    return len(raw.view(0, 2))
    , "raw[0:2]");
}

test "removed retained view in a generic expression carries a slice repair" {
    try expectRemovedRange(
        \\func my_take[T](marker: T) -> int:
        \\    return len(b"abcdef".view(0, 2))
    , "(b\"abcdef\")[0:2]");
}

test "removed retained view in a generic constant call carries a slice repair" {
    try expectRemovedRange(
        \\const RAW: bytes = b"abcdef"
        \\func my_take[T](marker: T) -> int:
        \\    return len(RAW.view(0, 2))
    , "RAW[0:2]");
}

test "removed retained view in a generic numeric range is refused before fusion" {
    try expectRemovedRange(
        \\@noalloc
        \\func number[T](raw: bytes, marker: T) -> int?:
        \\    return raw.view(0, 2).parse_int()
    , "raw[0:2]");
}

test "removed borrow spelling keeps its repair inside generic bodies" {
    var unit = try language.Compilation.init(testing.allocator, "generic-borrow.selka",
        \\func my_take[T](raw: bytes, marker: T) -> int:
        \\    return len(raw.borrow(0, 2))
    );
    defer unit.deinit();
    try testing.expectError(error.SourceError, unit.check());
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", unit.diagnostics.items[0].code);
    try testing.expectEqualStrings("raw[0:2]", unit.diagnostics.items[0].provenance.fix.?.edit.text);
}

test "removed view type in a generic local annotation keeps its certain repair" {
    var unit = try language.Compilation.init(testing.allocator, "generic-view-type.selka",
        \\func my_take[T](marker: T) -> int:
        \\    const saved: TextView = "hello"
        \\    return len(saved)
    );
    defer unit.deinit();
    try testing.expectError(error.SourceError, unit.check());
    try testing.expectEqualStrings("E_BORROW_VIEWS_REMOVED", unit.diagnostics.items[0].code);
    try testing.expectEqualStrings("str", unit.diagnostics.items[0].provenance.fix.?.edit.text);
}

test "removed retained view in a generic literal numeric range has a valid repair" {
    try expectRemovedRange(
        \\@noalloc
        \\func number[T](marker: T) -> int?:
        \\    return b"42".view(0, 2).parse_int()
    , "(b\"42\")[0:2]");
}
