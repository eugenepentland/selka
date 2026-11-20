//! The prelude's names: every function a program can call with no import and no qualifier.
//!
//! This is the one list. Before it, `operations.prelude` (the names `selka docs operations` prints) and
//! `prelude_builtins.reserved` (the names the checker builds from collection operations) were two lists that
//! disagreed: `abs`, `round`, `take`, `exchange`, `list`, `set`, `dict`, `same_function`, `function_digest` and
//! `case_name` were in the second only, and most of the first was not in the second. Both now read this table,
//! each through the attribute it needs, so each answers exactly as it did. Lane N4 added the four bare binary64 operations
//! `sqrt`, `floor`, `ceil` and `trunc` (`float_intrinsics.operation`), which neither old list held.
const std = @import("std");

/// One prelude function name and what each reader of the table does with it.
pub const Entry = struct {
    name: []const u8,
    /// Listed under "prelude" by `selka docs operations` and held there to one home (`operations.prelude`).
    listed: bool,
    /// Built by `prelude_builtins` from checked collection operations, when no binding or declaration shadows it
    /// (`prelude_builtins.reserved`).
    built: bool,
    /// Answered by `float_intrinsics.operation` as one binary64 operation on a `float` (`sqrt(x)`, `abs(x)`).
    float: bool = false,
};

fn entry(name: []const u8, listed: bool, built: bool) Entry {
    return .{ .name = name, .listed = listed, .built = built };
}

/// A prelude float operation that neither `operations.prelude` nor `prelude_builtins.reserved` holds.
fn floatOperation(name: []const u8) Entry {
    return .{ .name = name, .listed = false, .built = false, .float = true };
}

/// Every prelude function, in alphabetical order. A name appears once.
pub const entries = [_]Entry{
    .{ .name = "abs", .listed = false, .built = true, .float = true },
    entry("all", true, true),
    entry("any", true, true),
    entry("append", true, false),
    entry("bit_and", true, false),
    entry("bit_not", true, false),
    entry("bit_or", true, false),
    entry("bit_xor", true, false),
    entry("bool", true, false),
    entry("bytes", true, false),
    entry("case_name", false, true),
    floatOperation("ceil"),
    entry("chr", true, true),
    entry("copy", true, true),
    entry("dict", false, true),
    entry("enumerate", true, false),
    entry("exchange", false, true),
    entry("float", true, false),
    floatOperation("floor"),
    entry("flush", true, false),
    entry("function_digest", false, true),
    entry("int", true, false),
    entry("len", true, false),
    entry("list", false, true),
    entry("max", true, true),
    entry("min", true, true),
    entry("ord", true, true),
    entry("parse_float", true, false),
    entry("parse_int", true, false),
    entry("print", true, false),
    entry("range", true, false),
    entry("repr", true, true),
    entry("reversed", true, true),
    entry("round", false, true),
    entry("same_function", false, true),
    entry("saturating_add", true, false),
    entry("saturating_mul", true, false),
    entry("saturating_sub", true, false),
    entry("set", false, true),
    entry("shift_left", true, false),
    entry("shift_right", true, false),
    entry("sort", true, false),
    entry("sorted", true, true),
    floatOperation("sqrt"),
    entry("str", true, false),
    entry("sum", true, true),
    entry("take", false, true),
    floatOperation("trunc"),
    entry("unwrap_or", true, false),
    entry("wrapping_add", true, false),
    entry("wrapping_mul", true, false),
    entry("wrapping_sub", true, false),
    entry("write", true, false),
    entry("zip", true, true),
};

const by_name = map: {
    var pairs: [entries.len]struct { []const u8, Entry } = undefined;
    for (entries, &pairs) |item, *pair| pair.* = .{ item.name, item };
    break :map std.StaticStringMap(Entry).initComptime(pairs);
};

/// The table's entry for `name`, or null when `name` is no prelude function.
pub fn find(name: []const u8) ?Entry {
    return by_name.get(name);
}

/// Whether `name` is a prelude function: an entry of the table, whatever its attributes.
pub fn isPrelude(name: []const u8) bool {
    return by_name.has(name);
}

fn countWhere(comptime field: []const u8) usize {
    var count: usize = 0;
    for (entries) |item| {
        if (@field(item, field)) count += 1;
    }
    return count;
}

/// The names of the entries whose attribute `field` is set, in table order.
pub fn namesWhere(comptime field: []const u8) [countWhere(field)][]const u8 {
    @setEvalBranchQuota(entries.len * 100);
    var names: [countWhere(field)][]const u8 = undefined;
    var at: usize = 0;
    for (entries) |item| {
        if (!@field(item, field)) continue;
        names[at] = item.name;
        at += 1;
    }
    return names;
}

comptime {
    for (entries[1..], 1..) |item, index| {
        if (!std.mem.lessThan(u8, entries[index - 1].name, item.name)) @compileError("prelude_names.entries must be sorted and hold each name once");
    }
}
