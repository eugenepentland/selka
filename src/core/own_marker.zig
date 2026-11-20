//! Source edits for an ownership marker already judged by the Core checker.
const std = @import("std");
const language = @import("selka");
const Span = language.source.Span;
const Edit = language.diagnostic.Edit;

/// Remove only the written prefix and its separating horizontal whitespace.
pub fn remove(src: language.source.Source, span: Span) ?Edit {
    if (span.end > src.bytes.len or span.start >= span.end) return null;
    const text = src.text(span);
    var start: usize = 0;
    while (start < text.len) {
        if (text[start] == '(' or std.ascii.isWhitespace(text[start])) {
            start += 1;
        } else if (text[start] == '#') {
            while (start < text.len and text[start] != '\n') : (start += 1) {}
        } else break;
    }
    if (!std.mem.startsWith(u8, text[start..], "own")) return null;
    var end = start + 3;
    if (end == text.len) return null;
    if (std.ascii.isAlphanumeric(text[end]) or text[end] == '_') return null;
    while (end < text.len and (text[end] == ' ' or text[end] == '\t')) : (end += 1) {}
    return .{ .span = .{ .start = span.start + start, .end = span.start + end }, .text = "" };
}

/// Repair only a pure named place after Core has proved its move. Grouping a
/// base must not move the marker onto that base instead of the complete field.
/// Returned replacement text belongs to `a`; insertion-only text is static.
pub fn insert(a: std.mem.Allocator, src: language.source.Source, span: Span) std.mem.Allocator.Error!?Edit {
    if (span.start >= span.end or span.end > src.bytes.len) return null;
    const text = src.text(span);
    var place: Place = .{};
    const plain = (try namedPlace(a, text, &place)) orelse return null;
    defer a.free(plain);
    if (place.close == null or place.close.? >= place.last) {
        const position = span.start + place.first.?;
        return .{ .span = .{ .start = position, .end = position }, .text = "own " };
    }
    // `(owner).items` must transfer owner.items, not turn into
    // `(own owner).items`. One outer group retains multiline continuation.
    return .{ .span = span, .text = try std.fmt.allocPrint(a, "(own {s})", .{plain}) };
}

const Place = struct {
    state: enum { atom, member, done } = .atom,
    depth: usize = 0,
    first: ?usize = null,
    last: usize = 0,
    close: ?usize = null,

    fn identifier(self: *Place, text: []const u8, position: *usize) bool {
        if (self.state == .done) return false;
        const start = position.*;
        position.* += 1;
        while (position.* < text.len and (std.ascii.isAlphanumeric(text[position.*]) or text[position.*] == '_')) position.* += 1;
        if (!language.lexer.isIdentifier(text[start..position.*])) return false;
        if (self.first == null) self.first = start;
        self.last = position.*;
        self.state = .done;
        return true;
    }

    fn symbol(self: *Place, byte: u8, position: usize) bool {
        switch (byte) {
            '(' => {
                if (self.state != .atom) return false;
                self.depth += 1;
            },
            ')' => {
                if (self.state != .done or self.depth == 0) return false;
                self.depth -= 1;
                if (self.close == null) self.close = position;
            },
            '.' => {
                if (self.state != .done) return false;
                self.state = .member;
            },
            else => return false,
        }
        return true;
    }
};

fn namedPlace(a: std.mem.Allocator, text: []const u8, place: *Place) std.mem.Allocator.Error!?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    var position: usize = 0;
    while (position < text.len) {
        if (!try placePiece(a, text, &position, place, &out)) return null;
    }
    if (place.state != .done or place.depth != 0) return null;
    const bytes = try out.toOwnedSlice(a);
    return bytes;
}

/// Comments and whitespace retain their original bytes; only grouping tokens
/// are omitted. Calls, indices, operators and malformed spans fail closed.
fn placePiece(a: std.mem.Allocator, text: []const u8, position: *usize, place: *Place, out: *std.ArrayList(u8)) std.mem.Allocator.Error!bool {
    const start = position.*;
    const byte = text[start];
    if (std.ascii.isWhitespace(byte)) {
        position.* += 1;
    } else if (byte == '#') {
        while (position.* < text.len and text[position.*] != '\n') position.* += 1;
        // A trailing comment outside the expression is not part of a typed place.
        if (position.* == text.len) return false;
    } else if (std.ascii.isAlphabetic(byte) or byte == '_') {
        if (!place.identifier(text, position)) return false;
    } else {
        if (!place.symbol(byte, start)) return false;
        position.* += 1;
        if (byte == '(' or byte == ')') return true;
    }
    try out.appendSlice(a, text[start..position.*]);
    return true;
}

fn expectInsertion(a: std.mem.Allocator, before: []const u8, after: []const u8) !void {
    const src = try language.source.Source.init(a, "marker.selka", before);
    const edit = (try insert(a, src, .{ .start = 0, .end = before.len })) orelse return error.TestUnexpectedResult;
    const fixed = try std.mem.concat(a, u8, &.{ before[0..edit.span.start], edit.text, before[edit.span.end..] });
    try std.testing.expectEqualStrings(after, fixed);
}

test "F2 marker insertion marks complete grouped places and preserves comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const Case = struct { before: []const u8, after: []const u8 };
    for ([_]Case{
        .{ .before = "owner", .after = "own owner" },
        .{ .before = "(owner)", .after = "(own owner)" },
        .{ .before = "((owner))", .after = "((own owner))" },
        .{ .before = "(owner.items)", .after = "(own owner.items)" },
        .{ .before = "(owner).items", .after = "(own owner.items)" },
        .{ .before = "((owner)).items", .after = "(own owner.items)" },
        .{ .before = "((owner).inner).items", .after = "(own owner.inner.items)" },
        .{ .before = "(\n    # Keep (this) comment.\n    owner\n).items", .after = "(own \n    # Keep (this) comment.\n    owner\n.items)" },
    }) |case| try expectInsertion(arena.allocator(), case.before, case.after);
}

test "F2 marker insertion withholds edits for nonplace or uncertain spellings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "make().items", "owner[0].items", "(owner + other).items", "owner.(items)", "owner..items", "()", "(owner", "owner # trailing" }) |text| {
        const src = try language.source.Source.init(a, "uncertain.selka", text);
        try std.testing.expectEqual(@as(?Edit, null), try insert(a, src, .{ .start = 0, .end = text.len }));
    }
}
