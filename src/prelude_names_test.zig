//! The one prelude table answers each of its readers exactly as the two tables it replaced did.
const std = @import("std");
const t = std.testing;
const prelude_names = @import("prelude_names.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const operations = @import("operations.zig");

/// `operations.prelude` as it was written before the one table, in its own order.
const listed_before = [_][]const u8{
    "all",          "any",            "append",         "bit_and",        "bit_not",    "bit_or",
    "bit_xor",      "bool",           "bytes",          "chr",            "copy",       "enumerate",
    "float",        "flush",          "int",            "len",            "max",        "min",
    "ord",          "parse_float",    "parse_int",      "print",          "range",      "repr",
    "reversed",     "saturating_add", "saturating_mul", "saturating_sub", "shift_left", "shift_right",
    "sort",         "sorted",         "str",            "sum",            "unwrap_or",  "wrapping_add",
    "wrapping_mul", "wrapping_sub",   "write",          "zip",
};

/// `prelude_builtins.reserved` as it was written before the one table.
const built_before = [_][]const u8{
    "sum",      "min",  "max", "sorted", "abs", "round", "any", "all", "copy",          "take",            "exchange",
    "reversed", "list", "set", "dict",   "zip", "repr",  "ord", "chr", "same_function", "function_digest", "case_name",
};

/// The bare float operations of `float_intrinsics` that neither old table held; lane N4 added them to the prelude table.
const float_added = [_][]const u8{ "ceil", "floor", "sqrt", "trunc" };

fn holds(names: []const []const u8, name: []const u8) bool {
    for (names) |entry| if (std.mem.eql(u8, entry, name)) return true;
    return false;
}

/// Every name either old table held, and some names neither held: the table answers each as that table did. The prelude
/// is those names and the four float operations N4 added, which neither of the two readers answers.
fn expectSameAnswers(name: []const u8) !void {
    try t.expectEqual(holds(&built_before, name), prelude_builtins.reserved(name));
    try t.expectEqual(holds(&listed_before, name), holds(&operations.prelude, name));
    try t.expectEqual(holds(&built_before, name) or holds(&listed_before, name) or holds(&float_added, name), prelude_names.isPrelude(name));
}

/// Every entry, every name of the two old tables and a few names of neither.
fn expectEveryNameSame() !void {
    for (prelude_names.entries) |item| try expectSameAnswers(item.name);
    for (listed_before) |name| try expectSameAnswers(name);
    for (built_before) |name| try expectSameAnswers(name);
    for (float_added) |name| try expectSameAnswers(name);
    for ([_][]const u8{ "replace", "unwrap", "exp", "Option", "f32", "lenx", "" }) |name| try expectSameAnswers(name);
}

test "the one prelude table is the union of the two tables it replaced and answers each as before" {
    try t.expectEqual(listed_before.len, operations.prelude.len);
    try t.expectEqual(@as(usize, 54), prelude_names.entries.len);
    try expectEveryNameSame();
}

test "the operations table lists the prelude functions that have no home of their own under a heading of their own" {
    const text = try operations.render(t.allocator);
    defer t.allocator.free(text);
    const heading = "\n## prelude, built from collection operations\n";
    const at = std.mem.indexOf(u8, text, heading).?;
    const section_end = std.mem.indexOfPos(u8, text, at + heading.len, "\n## ").?;
    const section = text[at + heading.len .. section_end];
    try t.expectEqualStrings("  abs\n  case_name\n  dict\n  exchange\n  function_digest\n  list\n  round\n  same_function\n  set\n  take\n", section);
    try t.expect(std.mem.indexOf(u8, text, "A name appears once in this table") == null);
}

test "the operations table lists the four float operations under a heading of their own" {
    const text = try operations.render(t.allocator);
    defer t.allocator.free(text);
    const heading = "\n## prelude, float operations\n";
    const at = std.mem.indexOf(u8, text, heading).?;
    const section_end = std.mem.indexOfPos(u8, text, at + heading.len, "\n## ").?;
    try t.expectEqualStrings("  ceil\n  floor\n  sqrt\n  trunc\n", text[at + heading.len .. section_end]);
}
