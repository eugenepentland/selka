//! `tokens-v1` machine output for the stage-0 lexer oracle.
//!
//! The document is deliberately compact and single-line: a differential harness
//! converts each record to the `<kind> <start> <end>` protocol the selka
//! lexer prints. `kind` is the exact `@tagName` spelling so a renamed tag can
//! never silently agree with a different token category.
const std = @import("std");
const lexer = @import("lexer.zig");
const source = @import("source.zig");

/// One token record in the versioned document, in fixed field order.
pub const Entry = struct {
    kind: []const u8,
    start: usize,
    end: usize,
    line: usize,
    column: usize,
};

/// Process exit status for an unsuccessful lexing outcome: a lexical failure is
/// a source error (1), any other failure is a host failure (2).
pub fn exitStatus(err: anyerror) u8 {
    return if (err == error.SourceError) 1 else 2;
}

/// Serialize a successful token stream with the caller's allocator.
pub fn render(allocator: std.mem.Allocator, path: []const u8, src: source.Source, tokens: []const lexer.Token) std.mem.Allocator.Error![]u8 {
    const entries = try allocator.alloc(Entry, tokens.len);
    defer allocator.free(entries);
    for (tokens, 0..) |token, index| {
        const at = src.locate(token.span.start);
        entries[index] = .{
            .kind = @tagName(token.tag),
            .start = token.span.start,
            .end = token.span.end,
            .line = at.line,
            .column = at.column,
        };
    }
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "tokens-v1",
        .path = path,
        .count = entries.len,
        .tokens = entries,
    }, .{});
}

/// The lexer's closed vocabularies as text, for tools that must stay in step with
/// them: `tokens-tables-v1`, then `kinds N` and every tag name in declaration order,
/// then `keywords M` and one `keyword WORD TAG` line per reserved spelling in the
/// lexer's table order. The Selka lexer's generated kind and keyword tables are
/// produced from this and checked against it.
pub fn renderTables(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const names = @typeInfo(lexer.Tag).@"enum".field_names;
    out.writer.print("tokens-tables-v1\nkinds {d}\n", .{names.len}) catch return error.OutOfMemory;
    inline for (names) |name| out.writer.print("{s}\n", .{name}) catch return error.OutOfMemory;
    out.writer.print("keywords {d}\n", .{lexer.keyword_pairs.len}) catch return error.OutOfMemory;
    for (lexer.keyword_pairs) |pair| out.writer.print("keyword {s} {s}\n", .{ pair[0], @tagName(pair[1]) }) catch return error.OutOfMemory;
    const text = try out.toOwnedSlice();
    return text;
}
