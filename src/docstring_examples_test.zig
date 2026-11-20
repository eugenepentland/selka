//! Grammar acceptance for runnable docstrings, independent of the compiler.
const std = @import("std");
const examples = @import("docstring_examples.zig");
const t = std.testing;

const transcript =
    "Explain the operation.\n" ++
    "\n" ++
    "    >>> const values = [1, 2]\n" ++
    "    >>> for value in values:\n" ++
    "    ...     print(out, value)\n" ++
    "    1\n" ++
    "    2\n" ++
    "\n" ++
    "    More explanation.\n" ++
    "    >>> 'hello'\n" ++
    "    'hello'\n" ++
    "    ";

test "docstring examples parse statements continuations and original source lines" {
    const found = try examples.parse(t.allocator, transcript, 20);
    defer examples.release(t.allocator, found);
    try t.expectEqual(@as(usize, 3), found.len);
    try t.expectEqual(found.len, examples.count(transcript));
    try t.expectEqualStrings("const values = [1, 2]", found[0].lines[0].text);
    try t.expectEqualStrings("", found[0].expected);
    try t.expectEqual(@as(usize, 22), found[0].line);
    try t.expectEqualStrings("    print(out, value)", found[1].lines[1].text);
    try t.expectEqual(@as(usize, 24), found[1].lines[1].line);
    try t.expectEqualStrings("1\n2\n", found[1].expected);
    try t.expectEqualStrings("'hello'\n", found[2].expected);
}

test "docstring examples preserve exact whitespace blank lines and literal ellipsis" {
    const found = try examples.parse(t.allocator, "\n  >>> print(out, '  a  ')\r\n    a  \r\n  <BLANKLINE>\r\n  ...\r\n", 1);
    defer examples.release(t.allocator, found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("  a  \n\n...\n", found[0].expected);
    try t.expectEqual(@as(usize, 2), found[0].line);
}

test "docstring examples require exact markers at the docstring indentation" {
    const text = "Prose >>> value\n    >>>missing_space\n    >>>\n      >>> nested\n    ... orphan\n    >>> value\n    1";
    const found = try examples.parse(t.allocator, text, 1);
    defer examples.release(t.allocator, found);
    try t.expectEqual(@as(usize, 1), examples.count(text));
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("value", found[0].lines[0].text);
    try t.expectEqualStrings("1\n", found[0].expected);
    try t.expectEqual(@as(usize, 6), found[0].line);
    try t.expectEqual(@as(usize, 0), examples.count("Summary\n    prose\n      >>> nested\n      42\n    "));
}

test "docstring examples accept an inline first prompt and empty docs" {
    const found = try examples.parse(t.allocator, "   >>> 42\n    42", 8);
    defer examples.release(t.allocator, found);
    try t.expectEqualStrings("42\n", found[0].expected);
    try t.expectEqual(@as(usize, 8), found[0].line);
    try t.expectEqual(@as(usize, 0), examples.count(""));
    const empty = try examples.parse(t.allocator, "", 1);
    defer examples.release(t.allocator, empty);
    try t.expectEqual(@as(usize, 0), empty.len);
}

fn allocationWalk(allocator: std.mem.Allocator) !void {
    const found = try examples.parse(allocator, transcript, 1);
    defer examples.release(allocator, found);
    try t.expectEqual(@as(usize, 3), found.len);
}

test "docstring examples readExample releases every partial parse allocation" {
    try t.checkAllAllocationFailures(t.allocator, allocationWalk, .{});
}
