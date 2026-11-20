//! The formatter's safety net: text `selka fmt` is about to write must parse, and must parse to the syntax its input had.
//!
//! The formatter works on tokens and never builds a tree, so a layout rule that is wrong for one construct writes code that
//! no longer parses (`return (a and b,)` is a one-element tuple, F-S1a-10) or, worse, parses to something else. `judge` takes
//! the input's parse and the parse of the formatted text and finds the first fact on which they differ. Layout and comments
//! are not facts: a node's covering span is skipped, a name span is compared by its text without whitespace, comments or a
//! comma before a closing delimiter, and a string literal by its canonical quoting. The one reordering the formatter makes
//! on purpose, the names of a `from` clause into parameter order, compares as a set.
//!
//! A difference is reported at the input line of the construct that changed, with the formatted line beside it, so the
//! report names a place in the file the person wrote.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const formatter = @import("formatter.zig");
const lex = @import("lexer.zig");
const source = @import("source.zig");

const Allocator = std.mem.Allocator;

/// The diagnostic code of a formatter result that was refused.
pub const code = "E_FORMAT_VERIFY";

/// One parse of a unit: its source, tokens and syntax, or the first diagnostic that stopped it.
pub const Parse = struct {
    src: source.Source,
    tokens: ?[]const lex.Token = null,
    syntax: ?ast.Program = null,
    /// The first diagnostic of a parse that failed.
    failure: ?diagnostic.Diagnostic = null,
    /// Whether the unit was parsed as a module, whose `import` directives the syntax tree does not keep.
    module: bool = false,
};

/// Why the formatted text was refused: where in the input the construct stands, and what is wrong with the text.
pub const Finding = struct {
    input: source.Span,
    message: []const u8,
};

/// Compare the parse of the input with the parse of its formatted text. Null means the formatted text parses to the same
/// syntax. The finding's message is allocated from `allocator`; the comparison itself uses a private arena.
pub fn judge(allocator: Allocator, input: Parse, output: Parse) Allocator.Error!?Finding {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (output.failure) |failure| {
        // A parse that failed after the lexer leaves its tokens behind; one that failed in the lexer has none to place the failure by.
        var again = output;
        if (again.tokens == null) {
            var sink: diagnostic.Sink = .{ .allocator = scratch.allocator() };
            again.tokens = lex.lex(scratch.allocator(), output.src.bytes, &sink) catch null;
        }
        const at = inputSpanFor(input, again, failure.span.start);
        const line = lineText(output.src, failure.span.start);
        const message = try std.fmt.allocPrint(allocator, "the formatted text does not parse, so nothing was written: {s}: {s} (formatted line {d}: `{s}`)", .{
            failure.code, failure.message, output.src.locate(failure.span.start).line, line,
        });
        return .{ .input = at, .message = message };
    }
    const left = input.syntax orelse return null;
    const right = output.syntax orelse return null;
    var walk: Walk = .{ .input = input.src, .output = output.src, .scratch = scratch.allocator() };
    const difference = (try compareTables(&walk, left, right)) orelse
        (if (input.module) try compareImports(&walk) else null) orelse return null;
    const output_at = difference.output orelse source.Span{ .start = 0, .end = 0 };
    const message = try std.fmt.allocPrint(allocator, "the formatted text parses to different syntax ({s}), so nothing was written (formatted line {d}: `{s}`)", .{
        difference.what, output.src.locate(output_at.start).line, lineText(output.src, output_at.start),
    });
    return .{ .input = difference.input orelse .{ .start = 0, .end = 0 }, .message = message };
}

/// The text of the line an offset is on, cut to a length a message can carry.
fn lineText(src: source.Source, offset: usize) []const u8 {
    const line = std.mem.trim(u8, src.locate(@min(offset, src.bytes.len)).text, " \t\r");
    return if (line.len > 100) line[0..100] else line;
}

/// Where a place in the formatted text came from in the input. The formatter only moves layout, drops or adds a comma and
/// re-quotes a literal, so the n-th token that is none of those is the same token in both; a reordered `import` run lands on
/// another line of the same run.
fn inputSpanFor(input: Parse, output: Parse, offset: usize) source.Span {
    const from = input.tokens orelse return .{ .start = 0, .end = 0 };
    const to = output.tokens orelse return .{ .start = 0, .end = 0 };
    var count: usize = 0;
    for (to) |token| {
        if (token.span.start > offset) break;
        if (significant(token.tag)) count += 1;
    }
    if (count == 0) return .{ .start = 0, .end = 0 };
    var seen: usize = 0;
    var last: source.Span = .{ .start = 0, .end = 0 };
    for (from) |token| {
        if (!significant(token.tag)) continue;
        seen += 1;
        last = token.span;
        if (seen == count) break;
    }
    // A formatter that added a token has no counterpart for it: the last input token the count reached is the nearest place.
    return last;
}

/// Whether a token is one the formatter keeps one for one.
fn significant(tag: lex.Tag) bool {
    return switch (tag) {
        .indent, .dedent, .eof, .comma, .semicolon => false,
        else => true,
    };
}

const Difference = struct {
    what: []const u8,
    input: ?source.Span = null,
    output: ?source.Span = null,
};

/// The two sources a comparison reads names from, and the memory it normalizes them in.
const Walk = struct {
    input: source.Source,
    output: source.Source,
    scratch: Allocator,
};

/// The `import` directives of a module are not in its syntax tree, so they are compared as text: each directive of the input must
/// stand in the output, in any order (the formatter sorts a run of them), and the output must hold no other.
fn compareImports(walk: *Walk) Allocator.Error!?Difference {
    const before = try importDirectives(walk.scratch, walk.input);
    const after = try importDirectives(walk.scratch, walk.output);
    const taken = try walk.scratch.alloc(bool, after.len);
    @memset(taken, false);
    for (before) |directive| {
        var found = false;
        for (after, 0..) |other, at| {
            if (taken[at] or !std.mem.eql(u8, directive.text, other.text)) continue;
            taken[at] = true;
            found = true;
            break;
        }
        if (!found) return .{ .what = "import directives", .input = lineSpan(walk.input, directive.line), .output = null };
    }
    for (after, taken) |other, used| {
        if (!used) return .{ .what = "import directives", .input = if (before.len > 0) lineSpan(walk.input, before[0].line) else null, .output = lineSpan(walk.output, other.line) };
    }
    return null;
}

const Directive = struct { line: usize, text: []const u8 };

/// The lines of a source that begin an `import` directive, each as its significant text.
fn importDirectives(allocator: Allocator, src: source.Source) Allocator.Error![]Directive {
    var found: std.ArrayList(Directive) = .empty;
    var line: usize = 1;
    var lines = std.mem.splitScalar(u8, src.bytes, '\n');
    while (lines.next()) |text_line| : (line += 1) {
        if (!std.mem.startsWith(u8, text_line, "import ")) continue;
        try found.append(allocator, .{ .line = line, .text = try normalized(allocator, text_line) });
    }
    return found.items;
}

/// The span of the first byte of a one-based line.
fn lineSpan(src: source.Source, line: usize) source.Span {
    const start = if (line >= 1 and line <= src.line_starts.len) src.line_starts[line - 1] else 0;
    return .{ .start = start, .end = start };
}

/// The first table of the two programs that differs, and the entry in it.
fn compareTables(walk: *Walk, left: ast.Program, right: ast.Program) Allocator.Error!?Difference {
    if (try firstEntry(walk, left.nodes.items, right.nodes.items)) |at| {
        return .{
            .what = try std.fmt.allocPrint(walk.scratch, "expression {d}", .{at}),
            .input = if (at < left.nodes.items.len) left.nodes.items[at].span else null,
            .output = if (at < right.nodes.items.len) right.nodes.items[at].span else null,
        };
    }
    if (try firstEntry(walk, left.statements.items, right.statements.items)) |at| {
        return .{
            .what = try std.fmt.allocPrint(walk.scratch, "statement {d}", .{at}),
            .input = if (at < left.statements.items.len) left.statements.items[at].span else null,
            .output = if (at < right.statements.items.len) right.statements.items[at].span else null,
        };
    }
    if (try firstEntry(walk, left.functions, right.functions)) |at| {
        return .{
            .what = try std.fmt.allocPrint(walk.scratch, "function {d}", .{at}),
            .input = if (at < left.functions.len) left.functions[at].name else null,
            .output = if (at < right.functions.len) right.functions[at].name else null,
        };
    }
    inline for (.{ "types", "lambdas", "attributes", "docstrings" }) |field| {
        if (!try same(walk, @TypeOf(@field(left, field)), @field(left, field), @field(right, field))) return .{ .what = field };
    }
    return null;
}

/// The index of the first entry of two tables that differs; a table of another length differs at the shorter one's end.
fn firstEntry(walk: *Walk, left: anytype, right: anytype) Allocator.Error!?usize {
    const shared = @min(left.len, right.len);
    for (0..shared) |at| if (!try same(walk, @TypeOf(left[at]), left[at], right[at])) return at;
    return if (left.len == right.len) null else shared;
}

/// Whether two values hold the same syntax. Fields called `span` cover a whole construct, layout and comments included,
/// and are skipped; every other span is a name or a spelling, compared by its significant text.
fn same(walk: *Walk, comptime T: type, left: T, right: T) Allocator.Error!bool {
    switch (@typeInfo(T)) {
        .bool, .int, .float, .comptime_int, .comptime_float, .@"enum" => return left == right,
        .void, .null, .undefined => return true,
        .optional => |optional| {
            if (left == null or right == null) return (left == null) == (right == null);
            return same(walk, optional.child, left.?, right.?);
        },
        .array => |array| {
            for (left, right) |a, b| if (!try same(walk, array.child, a, b)) return false;
            return true;
        },
        .pointer => |pointer| switch (pointer.size) {
            .slice => {
                if (left.len != right.len) return false;
                if (pointer.child == u8) return std.mem.eql(u8, left, right);
                for (left, right) |a, b| if (!try same(walk, pointer.child, a, b)) return false;
                return true;
            },
            .one => switch (@typeInfo(pointer.child)) {
                .@"opaque", .@"fn" => return true,
                else => return same(walk, pointer.child, left.*, right.*),
            },
            else => return true,
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return std.meta.eql(left, right);
            if (@as(Tag, left) != @as(Tag, right)) return false;
            switch (left) {
                inline else => |payload, tag| return same(walk, @TypeOf(payload), payload, @field(right, @tagName(tag))),
            }
        },
        .@"struct" => |struct_info| {
            if (T == source.Span) return spansSame(walk, left, right);
            if (T == ast.Assertion) return sameAssertion(walk, left, right);
            // `std.ArrayList` and its kin: the items are the value, the capacity is not.
            if (@hasField(T, "items") and @hasField(T, "capacity")) return same(walk, @TypeOf(left.items), left.items, right.items);
            inline for (struct_info.field_names, struct_info.field_types) |name, Field| {
                if (comptime std.mem.eql(u8, name, "span")) continue;
                const ok = if (comptime std.mem.eql(u8, name, "borrowing"))
                    try sameSet(walk, @field(left, name), @field(right, name))
                else
                    try same(walk, Field, @field(left, name), @field(right, name));
                if (!ok) return false;
            }
            return true;
        },
        else => return true,
    }
}

/// An `assert` without a message reports its condition as written (`Assertion.message` holds that source text), so the
/// formatter's re-spelling of the condition, a literal's quoting or its spacing, changes the text without changing the
/// syntax. The text compares as a spelling then; a written message is a decoded literal and compares by its bytes.
fn sameAssertion(walk: *Walk, left: ast.Assertion, right: ast.Assertion) Allocator.Error!bool {
    if (!try same(walk, ast.NodeId, left.condition, right.condition)) return false;
    if (!try same(walk, ?source.Span, left.literal, right.literal)) return false;
    if (!try same(walk, ?ast.NodeId, left.value, right.value)) return false;
    if (left.literal != null or left.value != null) return std.mem.eql(u8, left.message, right.message);
    if (std.mem.eql(u8, left.message, right.message)) return true;
    return std.mem.eql(u8, try normalized(walk.scratch, left.message), try normalized(walk.scratch, right.message));
}

/// The names of a `from` clause, which the formatter puts in parameter order: equal when each name of one is a name of the other.
fn sameSet(walk: *Walk, left: []const source.Span, right: []const source.Span) Allocator.Error!bool {
    if (left.len != right.len) return false;
    const taken = try walk.scratch.alloc(bool, right.len);
    @memset(taken, false);
    for (left) |name| {
        var found = false;
        for (right, 0..) |other, at| {
            if (taken[at] or !try spansSame(walk, name, other)) continue;
            taken[at] = true;
            found = true;
            break;
        }
        if (!found) return false;
    }
    return true;
}

/// Whether two spans spell the same thing: the same bytes, or the same significant text.
fn spansSame(walk: *Walk, left: source.Span, right: source.Span) Allocator.Error!bool {
    const a = text(walk.input, left) orelse return text(walk.output, right) == null;
    const b = text(walk.output, right) orelse return false;
    if (std.mem.eql(u8, a, b)) return true;
    return std.mem.eql(u8, try normalized(walk.scratch, a), try normalized(walk.scratch, b));
}

/// The text of a span, or null when the span does not lie in its source.
fn text(src: source.Source, span: source.Span) ?[]const u8 {
    if (span.start > span.end or span.end > src.bytes.len) return null;
    return src.bytes[span.start..span.end];
}

/// The significant text of a spelling: no whitespace beyond a single space between two words, no comment, no comma before a
/// closing delimiter, and every string literal in the formatter's canonical quoting.
fn normalized(allocator: Allocator, spelling: []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    var gap = false;
    while (at < spelling.len) {
        const c = spelling[at];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            gap = true;
            at += 1;
            continue;
        }
        if (c == '#') {
            while (at < spelling.len and spelling[at] != '\n') at += 1;
            gap = true;
            continue;
        }
        if (c == ',' and closerFollows(spelling, at + 1)) {
            at += 1;
            continue;
        }
        if (c == '\'' or c == '"') {
            // A prefix (`b`, `f`) written just before the quote belongs to the literal.
            var start = out.items.len;
            while (start > 0 and !gap and std.ascii.isAlphabetic(out.items[start - 1])) start -= 1;
            const end = literalEnd(spelling, at);
            const raw = try std.mem.concat(allocator, u8, &.{ out.items[start..], spelling[at..end] });
            out.shrinkRetainingCapacity(start);
            try out.appendSlice(allocator, try formatter.canonicalLiteral(allocator, raw));
            at = end;
            gap = false;
            continue;
        }
        if (gap and out.items.len > 0 and isWordByte(out.items[out.items.len - 1]) and isWordByte(c)) try out.append(allocator, ' ');
        gap = false;
        try out.append(allocator, c);
        at += 1;
    }
    return out.items;
}

fn isWordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Whether the next significant byte at or after `from` closes a delimiter.
fn closerFollows(spelling: []const u8, from: usize) bool {
    var at = from;
    while (at < spelling.len) : (at += 1) {
        switch (spelling[at]) {
            ' ', '\t', '\r', '\n' => {},
            '#' => while (at + 1 < spelling.len and spelling[at + 1] != '\n') : (at += 1) {},
            ')', ']', '}' => return true,
            else => return false,
        }
    }
    return false;
}

/// The offset just past the string literal that opens with the quote at `start`.
fn literalEnd(spelling: []const u8, start: usize) usize {
    const quote = spelling[start];
    const triple = start + 2 < spelling.len and spelling[start + 1] == quote and spelling[start + 2] == quote;
    var at = start + (if (triple) @as(usize, 3) else 1);
    while (at < spelling.len) {
        if (spelling[at] == '\\') {
            at += 2;
            continue;
        }
        if (spelling[at] == quote) {
            if (!triple) return at + 1;
            if (at + 2 < spelling.len and spelling[at + 1] == quote and spelling[at + 2] == quote) return at + 3;
        }
        at += 1;
    }
    return spelling.len;
}
