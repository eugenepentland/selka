//! The text work behind the message of a nested pattern's refusal: the `case` line, the layers around a binding, and the
//! names the compiler made, which no diagnostic prints.
const std = @import("std");
const t = std.testing;
const pattern_message = @import("pattern_message.zig");

fn expectSteps(pattern: []const u8, binding: []const u8, matched: pattern_message.Matched, expected: ?[]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const at = std.mem.indexOf(u8, pattern, binding).?;
    const steps = try pattern_message.matchOwnSteps(arena.allocator(), pattern, at, matched);
    if (expected) |text| try t.expectEqualStrings(text, steps.?) else try t.expect(steps == null);
}

test "the case line holds the pattern and the position of a binding in it" {
    const source = "func f():\n    match g():\n        case Ok(Some(v)):\n            use(v)\n";
    const at = std.mem.indexOf(u8, source, "v)").?;
    const found = pattern_message.casePattern(source, at).?;
    try t.expectEqualStrings("Ok(Some(v))", found.text);
    try t.expectEqualStrings("v", found.text[found.at .. found.at + 1]);
    try t.expect(pattern_message.casePattern(source, std.mem.indexOf(u8, source, "use").?) == null);
    try t.expect(pattern_message.casePattern(source, std.mem.indexOf(u8, source, "case").?) == null);
}

test "two layers are bound by one name and matched with match own" {
    try expectSteps("Ok(Some(v))", "v", .fresh, "`case Ok(inner):`, then `match own inner:` with `case Some(v):`");
    try expectSteps("Ok(Some(v))", "v", .{ .owner = "r" }, "`match own r:` with `case Ok(inner):`, then `match own inner:` with `case Some(v):`");
}

test "three layers are matched one at a time, each with a name of its own" {
    try expectSteps(
        "Ok(Some(Some(v)))",
        "v",
        .fresh,
        "`case Ok(inner):`, then `match own inner:` with `case Some(inner2):`, then `match own inner2:` with `case Some(v):`",
    );
}

test "a labelled field keeps its label and the other nested fields become plain names" {
    try expectSteps(
        "both(left=Some(a), right=Some(b))",
        "a",
        .fresh,
        "`case both(left=inner, right=other):`, then `match own inner:` with `case Some(a):`",
    );
    try expectSteps(
        "Some(filled(value=v))",
        "v",
        .fresh,
        "`case Some(inner):`, then `match own inner:` with `case filled(value=v):`",
    );
}

test "a pattern with one layer, or whose matched value only lends, has no steps" {
    try expectSteps("Some(v)", "v", .fresh, null);
    try expectSteps("Ok(Some(v))", "v", .lent, null);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(!try pattern_message.nested(arena.allocator(), "Some(v)", 5));
    try t.expect(try pattern_message.nested(arena.allocator(), "Ok(Some(v))", 8));
}

test "a name the compiler made for a layer is hidden, and a name the author wrote is not" {
    try t.expect(pattern_message.hidden("\x00pattern269.0"));
    try t.expect(pattern_message.hidden(" pattern269.0"));
    try t.expect(pattern_message.hidden(""));
    try t.expect(!pattern_message.hidden("v"));
    try t.expect(!pattern_message.hidden("pattern269"));
}

test "a message never prints the name of a layer: it says the matched value instead" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings(
        "`v` is lent by the matched value, and the list `all` needs its own value",
        try pattern_message.withoutHiddenNames(a, "`v` is lent by the local `\x00pattern269.0`, and the list `all` needs its own value"),
    );
    try t.expectEqualStrings(
        "the matched value borrows from `r`",
        try pattern_message.withoutHiddenNames(a, "'\x00pattern7.1' borrows from `r`"),
    );
    const plain = "`v` is lent by the local `pattern269`";
    try t.expectEqualStrings(plain, try pattern_message.withoutHiddenNames(a, plain));
}
