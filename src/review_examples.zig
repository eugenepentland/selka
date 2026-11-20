//! The docstring examples a change shows differently. For each public declaration that
//! both sides keep, the `>>>` examples of its docstring are read from the overview
//! documents. An example whose source is unchanged but whose printed output changed is
//! reported with its declaration. Pure over two documents.
const std = @import("std");
const types = @import("overview_types.zig");
const review_side = @import("review_side.zig");

/// Allocation is the only failure: the examples are read into memory.
pub const Error = std.mem.Allocator.Error;

const prompt = ">>> ";
const continuation = "... ";

/// One `>>>` example: its source lines joined by newlines, and the output lines after it joined the same way.
pub const Example = struct { source: []const u8, output: []const u8 };

/// An example whose source is unchanged and whose output differs, with its declaration's name.
pub const Change = struct { name: []const u8, source: []const u8, old: []const u8, new: []const u8 };

/// The examples of a docstring, in order. Each line is trimmed. A source starts at a
/// `>>> ` line and continues with `... ` lines; its output runs to the next blank line
/// or the next `>>> ` line.
pub fn parse(a: std.mem.Allocator, doc: []const u8) Error![]const Example {
    var split = std.mem.splitScalar(u8, doc, '\n');
    var lines: std.ArrayList([]const u8) = .empty;
    while (split.next()) |raw| try lines.append(a, std.mem.trim(u8, raw, " \t\r"));
    var out: std.ArrayList(Example) = .empty;
    var index: usize = 0;
    while (index < lines.items.len) {
        if (!std.mem.startsWith(u8, lines.items[index], prompt)) {
            index += 1;
            continue;
        }
        const source = try sourceAt(a, lines.items, &index);
        const output = try outputAt(a, lines.items, &index);
        try out.append(a, .{ .source = source, .output = output });
    }
    return out.items;
}

/// The source of the example at `index`, advancing `index` past its prompt and continuation lines.
fn sourceAt(a: std.mem.Allocator, lines: []const []const u8, index: *usize) Error![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(a, lines[index.*][prompt.len..]);
    index.* += 1;
    while (index.* < lines.len and std.mem.startsWith(u8, lines[index.*], continuation)) : (index.* += 1) {
        try source.append(a, '\n');
        try source.appendSlice(a, lines[index.*][continuation.len..]);
    }
    return source.items;
}

/// The output lines at `index`, up to a blank line or the next prompt, advancing `index` past them.
fn outputAt(a: std.mem.Allocator, lines: []const []const u8, index: *usize) Error![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    var first = true;
    while (index.* < lines.len and lines[index.*].len != 0 and !std.mem.startsWith(u8, lines[index.*], prompt)) : (index.* += 1) {
        if (!first) try output.append(a, '\n');
        first = false;
        try output.appendSlice(a, lines[index.*]);
    }
    return output.items;
}

/// The examples whose source both sides of the change show, with a different output.
/// Declarations are read in the head's order.
pub fn compare(a: std.mem.Allocator, base: *const types.Document, head: *const types.Document) Error![]const Change {
    var out: std.ArrayList(Change) = .empty;
    for (head.modules) |module| {
        for (module.declarations) |declaration| {
            const before = review_side.declaration(base, declaration.name) orelse continue;
            try appendChanges(a, &out, declaration.name, try parse(a, before.doc), try parse(a, declaration.doc));
        }
    }
    return out.items;
}

/// Append each new example whose source an old example also has with a different output.
fn appendChanges(a: std.mem.Allocator, out: *std.ArrayList(Change), name: []const u8, old: []const Example, new: []const Example) Error!void {
    for (new) |example| {
        const previous = matching(old, example.source) orelse continue;
        if (std.mem.eql(u8, previous.output, example.output)) continue;
        try out.append(a, .{ .name = name, .source = example.source, .old = previous.output, .new = example.output });
    }
}

/// The first example with this source, or null.
fn matching(examples: []const Example, source: []const u8) ?Example {
    for (examples) |example| {
        if (std.mem.eql(u8, example.source, source)) return example;
    }
    return null;
}

test "review examples reads each prompt with its continuation and output" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const doc = "Twice the value.\n\n    >>> double(2)\n    4\n\n    >>> add(\n    ... 1,\n    ... 2)\n    3\n    5\n    done\n";
    const found = try parse(arena.allocator(), doc);
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings("double(2)", found[0].source);
    try std.testing.expectEqualStrings("4", found[0].output);
    try std.testing.expectEqualStrings("add(\n1,\n2)", found[1].source);
    try std.testing.expectEqualStrings("3\n5\ndone", found[1].output);
}

test "review examples reads no examples from a docstring without a prompt" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const found = try parse(arena.allocator(), "Says nothing about examples.\n>>>no space\n");
    try std.testing.expectEqual(@as(usize, 0), found.len);
}

test "review examples names an example whose output changed while its source did not" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const old = try parse(scratch, "The stable answer.\n\n>>> answer()\n42\n");
    const new = try parse(scratch, "The stable answer.\n\n>>> answer()\n41\n>>> other()\n1\n");
    var out: std.ArrayList(Change) = .empty;
    try appendChanges(scratch, &out, "main::answer", old, new);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqualStrings("main::answer", out.items[0].name);
    try std.testing.expectEqualStrings("answer()", out.items[0].source);
    try std.testing.expectEqualStrings("42", out.items[0].old);
    try std.testing.expectEqualStrings("41", out.items[0].new);
}
