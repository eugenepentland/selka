//! Focused coverage for the stage-0 `dump-tokens` oracle document.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = language.lexer;
const source = language.source;
const diagnostic = language.diagnostic;
const tokens_dump = language.tokens_dump;

/// Lex one source and serialize its document; the arena owns both allocations.
fn renderSource(arena: std.mem.Allocator, path: []const u8, bytes: []const u8) ![]u8 {
    const src = try source.Source.init(arena, path, bytes);
    var sink: diagnostic.Sink = .{ .allocator = arena };
    const tokens = try lexer.lex(arena, bytes, &sink);
    return tokens_dump.render(arena, path, src, tokens);
}

// spec: SELFHOST-LEXER-DUMP-1
test "tokens-v1 exact JSON for keyword identifier integer string indent dedent and eof" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const bytes = "def name(x):\n    return 42\ns = 'hi'";
    const json = try renderSource(arena_state.allocator(), "t.selka", bytes);
    const expected =
        "{\"version\":\"tokens-v1\",\"path\":\"t.selka\",\"count\":13,\"tokens\":[" ++
        "{\"kind\":\"kw_def\",\"start\":0,\"end\":3,\"line\":1,\"column\":1}," ++
        "{\"kind\":\"ident\",\"start\":4,\"end\":8,\"line\":1,\"column\":5}," ++
        "{\"kind\":\"lparen\",\"start\":8,\"end\":9,\"line\":1,\"column\":9}," ++
        "{\"kind\":\"ident\",\"start\":9,\"end\":10,\"line\":1,\"column\":10}," ++
        "{\"kind\":\"rparen\",\"start\":10,\"end\":11,\"line\":1,\"column\":11}," ++
        "{\"kind\":\"indent\",\"start\":11,\"end\":12,\"line\":1,\"column\":12}," ++
        "{\"kind\":\"kw_return\",\"start\":17,\"end\":23,\"line\":2,\"column\":5}," ++
        "{\"kind\":\"integer\",\"start\":24,\"end\":26,\"line\":2,\"column\":12}," ++
        "{\"kind\":\"dedent\",\"start\":27,\"end\":27,\"line\":3,\"column\":1}," ++
        "{\"kind\":\"ident\",\"start\":27,\"end\":28,\"line\":3,\"column\":1}," ++
        "{\"kind\":\"equal\",\"start\":29,\"end\":30,\"line\":3,\"column\":3}," ++
        "{\"kind\":\"bytes\",\"start\":31,\"end\":35,\"line\":3,\"column\":5}," ++
        "{\"kind\":\"eof\",\"start\":35,\"end\":35,\"line\":3,\"column\":9}]}";
    try t.expectEqualStrings(expected, json);
}

// spec-case: SELFHOST-LEXER-DUMP-1
test "unexpected character yields E_TOKEN with the right location and exit status 1" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const bytes = "x = $";
    const src = try source.Source.init(arena, "bad.selka", bytes);
    var sink: diagnostic.Sink = .{ .allocator = arena };
    try t.expectError(error.SourceError, lexer.lex(arena, bytes, &sink));
    try t.expectEqual(@as(usize, 1), sink.items.items.len);
    const item = sink.items.items[0];
    try t.expectEqualStrings("E_TOKEN", item.code);
    const at = src.locate(item.span.start);
    try t.expectEqual(@as(usize, 1), at.line);
    try t.expectEqual(@as(usize, 5), at.column);
    try t.expectEqual(@as(usize, 4), item.span.start);
    try t.expectEqual(@as(usize, 5), item.span.end);
    // The CLI maps error.SourceError to exit status 1 without a partial document.
    try t.expectEqual(@as(u8, 1), tokens_dump.exitStatus(error.SourceError));
}
