//! The shared slice repair for removed `.borrow(start, end)` and `.view(start, end)` calls.
//!
//! A slice is a view of its source, so the certain replacement is the slice
//! spelling of the same range: `s[start:end]`. One builder serves every checker
//! that still meets the removed spelling, so the repair cannot drift between
//! them.
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

/// The code every removed-view refusal reports.
pub const code = "E_BORROW_VIEWS_REMOVED";

/// The message every removed-view refusal prints.
pub const message = "`.borrow(start, end)` was removed; a slice is a view of its source, so write `s[start:end]` — it allocates nothing when the source is unchanged";

/// The message for the retired owner-retaining byte range spelling.
pub const view_message = "`.view(start, end)` was removed; a slice is a view of its source, so write `s[start:end]`";

/// The single edit that rewrites `receiver.borrow(start, end)` — the call spans
/// `call` — into `receiver[start:end]`. The receiver is parenthesised unless it
/// is a plain path, so the slice cannot change how it parses.
pub fn edit(allocator: std.mem.Allocator, src: source.Source, receiver: source.Span, start: source.Span, end: source.Span, call: source.Span) std.mem.Allocator.Error!diagnostic.Edit {
    const text = src.text(receiver);
    const spelled = if (pathLike(text))
        try std.fmt.allocPrint(allocator, "{s}[{s}:{s}]", .{ text, src.text(start), src.text(end) })
    else
        try std.fmt.allocPrint(allocator, "({s})[{s}:{s}]", .{ text, src.text(start), src.text(end) });
    return .{ .span = call, .text = spelled };
}

/// Whether `text` is a plain path (`a`, `a.b`, `a.b_c`) that needs no parentheses
/// before `[`.
fn pathLike(text: []const u8) bool {
    if (text.len == 0 or std.ascii.isDigit(text[0])) return false;
    for (text) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.') continue;
        return false;
    }
    return true;
}
