//! What an ownership refusal says about a pattern that looks through more than one layer (`case Ok(Some(v)):`).
//!
//! The front end keeps each layer's payload in a local of its own whose name is made for the compiler (`\x00pattern269.0`,
//! or no name at all for the payload record of a case with named fields). A refusal must never print such a name: it names
//! the pattern the author wrote, and says how to write the layers so that the payload is owned (one `match own` for each
//! layer). Nothing here decides what the check accepts; it only reads the source text of the `case` line.
const std = @import("std");

/// The pattern of a `case` line, and where a position of the source lies in it.
pub const CasePattern = struct {
    /// The text after `case ` and before the colon that ends the line.
    text: []const u8,
    /// The offset in `text` of the position asked for.
    at: usize,
};

/// Who gives the payloads of the matched value.
pub const Matched = union(enum) {
    /// A fresh value, such as a call's result: it is already owned, so a plain `match` binds its payload.
    fresh,
    /// A local the function owns: `match own NAME:` gives it away.
    owner: []const u8,
    /// A parameter that only lends: nothing here can give its payloads.
    lent,
};

/// Whether `name` is one the compiler made for a layer of a pattern: no name, or a name that begins with a control byte or a
/// space, which no source can write.
pub fn hidden(name: []const u8) bool {
    return name.len == 0 or name[0] <= ' ';
}

/// The `case` line that holds source offset `at`: the pattern it writes and where `at` lies in it. Null when the line is
/// no `case` line or `at` is not inside the pattern.
pub fn casePattern(bytes: []const u8, at: usize) ?CasePattern {
    if (at >= bytes.len) return null;
    const line_start = if (std.mem.lastIndexOfScalar(u8, bytes[0..at], '\n')) |newline| newline + 1 else 0;
    const line_end = std.mem.indexOfScalarPos(u8, bytes, at, '\n') orelse bytes.len;
    const line = bytes[line_start..line_end];
    const text = std.mem.trimStart(u8, line, " ");
    if (!std.mem.startsWith(u8, text, "case ")) return null;
    const start = line_start + (line.len - text.len) + "case ".len;
    const end = line_start + std.mem.trimEnd(u8, line, " :\r").len;
    if (at < start or at >= end) return null;
    return .{ .text = bytes[start..end], .at = at - start };
}

/// One argument of a variant pattern: the text from `start` to `end`, whose first `label` bytes are `name=`.
const Argument = struct { start: usize, end: usize, label: usize };

/// A variant pattern that holds the position asked for, with every argument and the one that holds it.
const Group = struct { arguments: []const Argument, holder: usize };

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn skipText(pattern: []const u8, quote: usize) usize {
    var at = quote + 1;
    while (at < pattern.len and pattern[at] != '"') at += if (pattern[at] == '\\') 2 else 1;
    return @min(at, pattern.len - 1);
}

fn argumentOf(pattern: []const u8, from: usize, to: usize) Argument {
    var start = from;
    var end = to;
    while (start < end and pattern[start] == ' ') start += 1;
    while (end > start and pattern[end - 1] == ' ') end -= 1;
    var label = start;
    while (label < end and identifierByte(pattern[label])) label += 1;
    const labelled = label > start and label + 1 < end and pattern[label] == '=' and pattern[label + 1] != '=';
    return .{ .start = start, .end = end, .label = if (labelled) label + 1 - start else 0 };
}

/// The arguments of the pattern whose first argument starts at `first`, split at the commas outside any bracket, up to the
/// closing parenthesis; null when the text ends before it.
fn argumentsFrom(a: std.mem.Allocator, pattern: []const u8, first: usize) std.mem.Allocator.Error!?[]const Argument {
    var arguments: std.ArrayList(Argument) = .empty;
    var depth: usize = 0;
    var start = first;
    var at = first;
    while (at < pattern.len) : (at += 1) switch (pattern[at]) {
        '"' => at = skipText(pattern, at),
        '(', '[', '{' => depth += 1,
        ']', '}' => depth -|= 1,
        ')' => if (depth == 0) {
            try arguments.append(a, argumentOf(pattern, start, at));
            return arguments.items;
        } else {
            depth -= 1;
        },
        ',' => if (depth == 0) {
            try arguments.append(a, argumentOf(pattern, start, at));
            start = at + 1;
        },
        else => {},
    };
    return null;
}

/// The variant patterns around offset `at`, outermost first, each with the argument that holds `at`. Null when `at` is not
/// inside a variant pattern, or the text is not one this reads.
fn groupsAround(a: std.mem.Allocator, pattern: []const u8, at: usize) std.mem.Allocator.Error!?[]const Group {
    var opens: std.ArrayList(usize) = .empty;
    var index: usize = 0;
    while (index < at) : (index += 1) switch (pattern[index]) {
        '"' => index = skipText(pattern, index),
        '(' => {
            if (index == 0 or !identifierByte(pattern[index - 1])) return null;
            try opens.append(a, index + 1);
        },
        ')' => if (opens.pop() == null) return null,
        else => {},
    };
    var groups: std.ArrayList(Group) = .empty;
    for (opens.items) |first| {
        const arguments = (try argumentsFrom(a, pattern, first)) orelse return null;
        const holder = for (arguments, 0..) |argument, position| {
            if (argument.start <= at and at < argument.end) break position;
        } else return null;
        try groups.append(a, .{ .arguments = arguments, .holder = holder });
    }
    return groups.items;
}

/// Whether an argument is a bare name or `_`, which a case of named fields binds without nesting.
fn plain(pattern: []const u8, argument: Argument) bool {
    const value = pattern[argument.start + argument.label .. argument.end];
    if (value.len == 0) return false;
    for (value) |byte| if (!identifierByte(byte)) return false;
    return true;
}

/// How many names the case lines made so far, so that no two share one.
const Names = struct {
    layers: usize = 0,
    others: usize = 0,

    fn layer(self: *Names, a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        self.layers += 1;
        return if (self.layers == 1) a.dupe(u8, "inner") else std.fmt.allocPrint(a, "inner{d}", .{self.layers});
    }

    fn other(self: *Names, a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        self.others += 1;
        return if (self.others == 1) a.dupe(u8, "other") else std.fmt.allocPrint(a, "other{d}", .{self.others});
    }
};

/// The pattern text from `from` to `to` with the arguments of `group` that hold a nested pattern replaced by names: the
/// argument that holds the binding by `held` when it is not null, the others by names of their own, because a case of named
/// fields owns its payloads only when every field is bound to a plain name.
fn namedLayer(a: std.mem.Allocator, pattern: []const u8, range: [2]usize, group: Group, held: ?[]const u8, names: *Names) std.mem.Allocator.Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, pattern[range[0]..group.arguments[0].start]);
    for (group.arguments, 0..) |argument, position| {
        if (position != 0) try text.appendSlice(a, pattern[group.arguments[position - 1].end..argument.start]);
        try text.appendSlice(a, pattern[argument.start .. argument.start + argument.label]);
        if (position == group.holder and held != null) {
            try text.appendSlice(a, held.?);
        } else if (position != group.holder and !plain(pattern, argument) and group.arguments.len > 1) {
            try text.appendSlice(a, try names.other(a));
        } else {
            try text.appendSlice(a, pattern[argument.start + argument.label .. argument.end]);
        }
    }
    try text.appendSlice(a, pattern[group.arguments[group.arguments.len - 1].end..range[1]]);
    return text.items;
}

/// Whether the binding at offset `at` of `pattern` lies inside a variant pattern that is itself inside another: the layers
/// between them are the ones a check lends instead of owning.
pub fn nested(a: std.mem.Allocator, pattern: []const u8, at: usize) std.mem.Allocator.Error!bool {
    const groups = (try groupsAround(a, pattern, at)) orelse return false;
    return groups.len >= 2;
}

/// The lines that give the payload bound at offset `at` of `pattern` its own owner, one layer at a time: the `case` that binds
/// the first layer to a name, then a `match own` of that name for each further layer. Null when the pattern has no layer to
/// bind (the binding is in the outermost variant) or is not a nest of variants this reads, or when nothing can give it.
pub fn matchOwnSteps(a: std.mem.Allocator, pattern: []const u8, at: usize, matched: Matched) std.mem.Allocator.Error!?[]const u8 {
    if (matched == .lent) return null;
    const groups = (try groupsAround(a, pattern, at)) orelse return null;
    if (groups.len < 2) return null;
    var steps: std.ArrayList(u8) = .empty;
    var names: Names = .{};
    var range: [2]usize = .{ 0, pattern.len };
    var previous: []const u8 = "";
    for (groups[0 .. groups.len - 1], 0..) |group, depth| {
        const held = try names.layer(a);
        const line = try namedLayer(a, pattern, range, group, held, &names);
        if (depth == 0) {
            switch (matched) {
                .owner => |owner| try steps.print(a, "`match own {s}:` with `case {s}:`", .{ owner, line }),
                else => try steps.print(a, "`case {s}:`", .{line}),
            }
        } else {
            try steps.print(a, ", then `match own {s}:` with `case {s}:`", .{ previous, line });
        }
        previous = held;
        const argument = group.arguments[group.holder];
        range = .{ argument.start + argument.label, argument.end };
    }
    const last = groups[groups.len - 1];
    const final = try namedLayer(a, pattern, range, last, null, &names);
    try steps.print(a, ", then `match own {s}:` with `case {s}:`", .{ previous, final });
    return steps.items;
}

/// `message` with each name the compiler made for a layer of a pattern (`\x00pattern269.0`) replaced by words: the check
/// reads such a name from a local, and a message built anywhere must never print it. The name, the backticks or quotes around
/// it and a `the local` before it become `the matched value`. A message without one is returned as it is.
pub fn withoutHiddenNames(a: std.mem.Allocator, message: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.indexOfScalar(u8, message, 0) == null) return message;
    var text: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (at < message.len) {
        if (message[at] != 0) {
            try text.append(a, message[at]);
            at += 1;
            continue;
        }
        at += 1;
        while (at < message.len and (identifierByte(message[at]) or message[at] == '.')) at += 1;
        if (at < message.len and (message[at] == '`' or message[at] == '\'')) at += 1;
        if (std.mem.endsWith(u8, text.items, "the local `")) {
            text.shrinkRetainingCapacity(text.items.len - "the local `".len);
        } else if (std.mem.endsWith(u8, text.items, "`") or std.mem.endsWith(u8, text.items, "'")) {
            text.shrinkRetainingCapacity(text.items.len - 1);
        }
        try text.appendSlice(a, "the matched value");
    }
    return text.items;
}
