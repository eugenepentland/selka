//! Reading a standard-library declaration's call form and one-line description from its embedded source.
//!
//! `reference.zig` knows every exported declaration from the compiler's own listing: a `module::name` identity and a
//! canonical `func(text:str,separator:str)->str[]` signature. A program is written with the source's spelling instead
//! (`int`, `T`, defaults, `from` and `fails` clauses), and the library's source carries each description as the `#`
//! comment above the declaration. This file reads both from the embedded module text the listing was built from, so
//! an answer needs no second copy of the library. It is pure text in, text out, and it never fails on a shape it does
//! not know: a declaration it cannot read is simply absent from `scan`.

const std = @import("std");

/// The longest description a lookup prints, cut at a word.
const summary_limit = 160;

/// What the source of one declaration says about it.
pub const Found = struct {
    /// The call form, `strings.split(text: str, separator: str) -> str[]`, the name with its type and value for a
    /// constant (`process.SIGINT: int = 2`), or the keyword and qualified name of a type (`enum strings.Error`).
    call: []const u8,
    /// The first sentence of the comment above the declaration, or an empty string when it has none.
    summary: []const u8,
    /// The zero-based line of the declaration: its position in source order.
    line: usize,
};

/// One declaration of a module, by its unqualified name.
pub const Entry = struct {
    /// The declared name (`split`), borrowed from the module text.
    name: []const u8,
    /// What the source says about it.
    found: Found,
};

/// The declaration keywords a `public` line can begin with, after an optional `builtin`.
const keywords = [_][]const u8{ "func", "const", "record", "enum", "union", "result", "resource", "type", "domain", "constraint" };

/// The parts of one `public ...` declaration line the call form is built from.
const Head = struct {
    keyword: []const u8,
    name: []const u8,
    /// The rest of the line after the name.
    after: []const u8,
};

/// Every public declaration of one module's source, in source order, with its call form and description.
pub fn scan(arena: std.mem.Allocator, module: []const u8, text: []const u8) error{OutOfMemory}![]const Entry {
    var lines: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, text, '\n');
    while (split.next()) |line| try lines.append(arena, line);
    var found: std.ArrayList(Entry) = .empty;
    for (lines.items, 0..) |line, index| {
        const head = parseHead(line) orelse continue;
        const call = try callForm(arena, module, head, lines.items[index + 1 ..]) orelse continue;
        const summary = try summaryAbove(arena, lines.items[0..index]);
        try found.append(arena, .{ .name = head.name, .found = .{ .call = call, .summary = summary, .line = index } });
    }
    return found.toOwnedSlice(arena);
}

/// The entry that declares `name`, or null.
pub fn lookup(entries: []const Entry, name: []const u8) ?Found {
    for (entries) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.found;
    return null;
}

/// Whether `byte` can continue a declared name.
fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// Read a `public [builtin] KEYWORD NAME...` line, or null for any other line (a `public const`, a comment, code).
fn parseHead(line: []const u8) ?Head {
    const public = "public ";
    if (!std.mem.startsWith(u8, line, public)) return null;
    var rest = line[public.len..];
    const builtin = "builtin ";
    if (std.mem.startsWith(u8, rest, builtin)) rest = rest[builtin.len..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
    const keyword = rest[0..space];
    for (keywords) |known| {
        if (!std.mem.eql(u8, known, keyword)) continue;
        const named = rest[space + 1 ..];
        var end: usize = 0;
        while (end < named.len and isNameByte(named[end])) end += 1;
        if (end == 0) return null;
        return .{ .keyword = keyword, .name = named[0..end], .after = named[end..] };
    }
    return null;
}

/// The text of a balanced `[...]` group at the start of `text`, or an empty string when `text` does not start with one.
fn bracketGroup(text: []const u8) []const u8 {
    if (text.len == 0 or text[0] != '[') return "";
    var depth: usize = 0;
    for (text, 0..) |byte, index| {
        if (byte == '[') depth += 1;
        if (byte == ']') {
            depth -= 1;
            if (depth == 0) return text[0 .. index + 1];
        }
    }
    return "";
}

/// How many `(` are still open at the end of `text`; a quoted text is skipped.
fn openParentheses(text: []const u8) usize {
    var depth: usize = 0;
    var quoted = false;
    for (text) |byte| {
        if (byte == '"') quoted = !quoted;
        if (quoted) continue;
        if (byte == '(') depth += 1;
        if (byte == ')' and depth > 0) depth -= 1;
    }
    return depth;
}

/// Close up the spaces a parameter list written over several lines leaves.
fn tidy(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]const u8 {
    var current: []const u8 = text;
    const rewrites = [_][2][]const u8{ .{ "( ", "(" }, .{ ", )", ")" }, .{ " )", ")" } };
    for (rewrites) |rewrite| {
        const size = std.mem.replacementSize(u8, current, rewrite[0], rewrite[1]);
        const out = try arena.alloc(u8, size);
        _ = std.mem.replace(u8, current, rewrite[0], rewrite[1], out);
        current = out;
    }
    return current;
}

/// The call form of one declaration, or null when its parameter list is not closed.
fn callForm(arena: std.mem.Allocator, module: []const u8, head: Head, following: []const []const u8) error{OutOfMemory}!?[]const u8 {
    // A constant is used by its name, so its form is the name with its type and value.
    if (std.mem.eql(u8, head.keyword, "const")) {
        const constant = try std.fmt.allocPrint(arena, "{s}.{s}{s}", .{ module, head.name, std.mem.trimEnd(u8, head.after, " \t\r") });
        return constant;
    }
    if (!std.mem.eql(u8, head.keyword, "func")) {
        const shape = try std.fmt.allocPrint(arena, "{s} {s}.{s}{s}", .{ head.keyword, module, head.name, bracketGroup(head.after) });
        return shape;
    }
    // A generic function's `[T: bound]` group is the declaration's, not the call's.
    const group = bracketGroup(head.after);
    var written: std.ArrayList(u8) = .empty;
    try written.appendSlice(arena, head.after[group.len..]);
    var next: usize = 0;
    while (openParentheses(written.items) != 0) : (next += 1) {
        if (next >= following.len) return null;
        try written.append(arena, ' ');
        try written.appendSlice(arena, std.mem.trim(u8, following[next], " \t\r"));
    }
    if (written.items.len == 0 or written.items[0] != '(') return null;
    var clause = std.mem.trimEnd(u8, written.items, " \t\r");
    if (std.mem.endsWith(u8, clause, ":")) clause = std.mem.trimEnd(u8, clause[0 .. clause.len - 1], " \t\r");
    const call = try std.fmt.allocPrint(arena, "{s}.{s}{s}", .{ module, head.name, try tidy(arena, clause) });
    return call;
}

/// The first sentence of the `#` comment directly above a declaration, skipping attribute lines such as `@sealed`.
fn summaryAbove(arena: std.mem.Allocator, before: []const []const u8) error{OutOfMemory}![]const u8 {
    var end = before.len;
    while (end > 0 and std.mem.startsWith(u8, before[end - 1], "@")) end -= 1;
    var start = end;
    while (start > 0 and std.mem.startsWith(u8, before[start - 1], "#")) start -= 1;
    // The comment that opens a module's file is its header, and an empty `#` line ends it: the first declaration's own
    // description starts after the last one, so a header that runs into that comment is not read as its description (FR34).
    // A formatted file cannot hold a blank line there, which `selka fmt` removes between comment lines.
    if (start == 0) {
        var at = end;
        while (at > 0) : (at -= 1) {
            if (std.mem.trim(u8, before[at - 1][1..], " \t\r").len == 0) {
                start = at;
                break;
            }
        }
    }
    var joined: std.ArrayList(u8) = .empty;
    for (before[start..end]) |line| {
        const body = std.mem.trim(u8, line[1..], " \t\r");
        if (body.len == 0) continue;
        if (joined.items.len != 0) try joined.append(arena, ' ');
        try joined.appendSlice(arena, body);
    }
    return firstSentence(joined.items);
}

/// `text` up to and including its first full stop followed by a space or the end, cut at a word when it is still long.
pub fn firstSentence(text: []const u8) []const u8 {
    var cut = text.len;
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, at, '.')) |dot| : (at = dot + 1) {
        const ends = dot + 1 == text.len or text[dot + 1] == ' ';
        const abbreviation = std.mem.endsWith(u8, text[0..dot], "e.g") or std.mem.endsWith(u8, text[0..dot], "i.e");
        if (ends and !abbreviation) {
            cut = dot + 1;
            break;
        }
    }
    const sentence = text[0..cut];
    if (sentence.len <= summary_limit) return sentence;
    const word = std.mem.lastIndexOfScalar(u8, sentence[0..summary_limit], ' ') orelse summary_limit;
    return sentence[0..word];
}
