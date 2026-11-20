//! The digest of a text's tokens as a check reads it (test-loop stage 6, D-TL6-1 of `experiments/test-loop-20261109/DECISIONS.md`):
//! the lexer's tokens (layout delimiters included) and, for each token with bytes, the bytes between it and the token before it
//! on the same line, or a line break and the bytes from the start of its line when it begins a line, then its own bytes. A
//! comment, a blank line, the whitespace that ends a line and the number of lines between two tokens leave it. The `module-tokens`
//! kind keys a source by it (`core/test_runner_tokens.zig`), and the judgment of a generic body at its declaration keys the
//! declaration by it (`stand_in_kinds.tokenDigest`, W3 step 2); each passes its own domain.
const std = @import("std");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");

/// The digest of `bytes` as a check reads them, under `domain`, or null when the lexer refuses them (the caller then keys the
/// bytes).
pub fn digest(a: std.mem.Allocator, bytes: []const u8, domain: []const u8) std.mem.Allocator.Error!?[32]u8 {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const tokens = lexer.lex(scratch, bytes, &sink) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (sink.items.items.len != 0) return null;
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update(domain);
    var previous_end: usize = 0;
    for (tokens) |token| {
        hash.update(@tagName(token.tag));
        hash.update("\x00");
        const span = token.span;
        if (span.end <= span.start or span.end > bytes.len) continue;
        const gap = bytes[@min(previous_end, span.start)..span.start];
        if (previous_end == 0 or std.mem.indexOfScalar(u8, gap, '\n') != null) {
            const line = if (std.mem.lastIndexOfScalar(u8, bytes[0..span.start], '\n')) |newline| newline + 1 else 0;
            hash.update("\n");
            hash.update(bytes[line..span.start]);
        } else hash.update(gap);
        hash.update("\x01");
        hash.update(bytes[span.start..span.end]);
        hash.update("\x01");
        previous_end = span.end;
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

test "W3 a token digest leaves a comment and a blank line out and keeps a token, and refuses what the lexer refuses" {
    const a = std.testing.allocator;
    const plain = (try digest(a, "func f() -> int:\n    return 1\n", "test")).?;
    const commented = (try digest(a, "func f() -> int:\n    # why\n\n    return 1\n", "test")).?;
    const changed = (try digest(a, "func f() -> int:\n    return 2\n", "test")).?;
    try std.testing.expectEqualSlices(u8, &plain, &commented);
    try std.testing.expect(!std.mem.eql(u8, &plain, &changed));
    try std.testing.expect(!std.mem.eql(u8, &plain, &(try digest(a, "func f() -> int:\n    return 1\n", "other")).?));
    try std.testing.expectEqual(@as(?[32]u8, null), try digest(a, "func f() -> int:\n    return \"open\n", "test"));
}
