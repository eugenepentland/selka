//! Check-at-scale coverage: the lexer-free paths the per-edit check relies on
//! agree exactly with the full lexer.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = language.lexer;
const diagnostic = language.diagnostic;

/// Count spellings whose lexer-free answer differs from `qualifiedName(lex(...))`.
/// A spelling the fast path defers (`slow`) is not compared: the caller lexes it.
fn quickDisagreements(spellings: []const []const u8) !usize {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var count: usize = 0;
    for (spellings) |text| {
        const quick = lexer.quickQualifiedName(text);
        if (quick == .slow) continue;
        var sink: diagnostic.Sink = .{ .allocator = arena };
        const tokens = lexer.lex(arena, text, &sink) catch {
            count += 1;
            continue;
        };
        const slow = lexer.qualifiedName(text, tokens);
        const same = switch (quick) {
            .slow => unreachable,
            .none => slow == null,
            .name => |name| if (slow) |expected|
                std.mem.eql(u8, name.name, expected.name) and
                    (name.alias == null) == (expected.alias == null) and
                    std.mem.eql(u8, name.alias orelse "", expected.alias orelse "")
            else
                false,
        };
        if (!same) count += 1;
    }
    return count;
}

/// Lex `bytes` and return its token tags, owned by `arena`.
fn tags(arena: std.mem.Allocator, bytes: []const u8) ![]lexer.Tag {
    var sink: diagnostic.Sink = .{ .allocator = arena };
    const tokens = try lexer.lex(arena, bytes, &sink);
    const out = try arena.alloc(lexer.Tag, tokens.len);
    for (tokens, out) |token, *tag| tag.* = token.tag;
    return out;
}

// spec: CHECK-SCALE-LEX-1
test "a dotted reference spelling normalizes without the lexer exactly as with it" {
    const spellings = [_][]const u8{
        "value",         "m239.f239_00", "shared.units.area", "_hidden.x9", "len",     "xs.len",    "a.b.len", "True",
        "a.None",        "push",         "List",              "contains",   "f64_add", "a.f64_add", "a . b",   "a::b",
        "9lives",        "a..b",         ".a",                "a.",         "",        "x#y",
        "é",
        "Domain.member",
    };
    try t.expectEqual(@as(usize, 0), try quickDisagreements(&spellings));
    try t.expectEqualStrings("m239", lexer.quickQualifiedName("m239.f239_00").name.alias.?);
    try t.expectEqualStrings("f239_00", lexer.quickQualifiedName("m239.f239_00").name.name);
    try t.expectEqualStrings("shared.units", lexer.quickQualifiedName("shared.units.area").name.alias.?);
    try t.expect(lexer.quickQualifiedName("xs.len") == .none);
    try t.expect(lexer.quickQualifiedName("a . b") == .slow);
    // A removed spelling is left to the lexer, which alone reports it.
    try t.expect(lexer.quickQualifiedName("a.f64_add") == .slow);
}

// spec-case: CHECK-SCALE-LEX-1
test "reserved words removed spellings and layout lex exactly as before the keyword map" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const words = try tags(arena, "def class True False None and or not while whilex len push List __float_sqrt assert");
    const expected = [_]lexer.Tag{
        .kw_def, .kw_class, .kw_true, .kw_false, .kw_none, .and_and, .or_or, .bang, .kw_while, .ident, .kw_len, .ident, .ident, .kw_f64_sqrt, .kw_assert, .eof,
    };
    try t.expectEqualSlices(lexer.Tag, &expected, words);
    try t.expect(!lexer.isIdentifier("while"));
    try t.expect(lexer.isIdentifier("whilex"));
    var sink: diagnostic.Sink = .{ .allocator = arena };
    try t.expectError(error.SourceError, lexer.lex(arena, "x = f64_add", &sink));
    try t.expectEqualStrings("E_REMOVED_SPELLING", sink.items.items[0].code);
    // A multi-line string ends its line; the next token opens a new statement.
    const layout = try tags(arena, "def f() -> str:\n    s = '''a\nb'''\n    return s\nx = 1\n");
    const layout_expected = [_]lexer.Tag{
        .kw_def, .ident, .lparen, .rparen, .arrow, .ident, .indent, .ident, .equal, .bytes, .kw_return, .ident, .dedent, .ident, .equal, .integer, .eof,
    };
    try t.expectEqualSlices(lexer.Tag, &layout_expected, layout);
}
