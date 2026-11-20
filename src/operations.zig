//! One home per operation: the prelude's spellings and each standard module's
//! exports, as `selka docs operations` prints them.
//!
//! Stage 2 gives every operation exactly one home. The prelude is a declared,
//! short list that needs no import; a module's exports are *derived* from the
//! embedded module source, so the generated table cannot drift from what the
//! compiler actually ships. `operations_test` holds the two invariants: an
//! operation has one home, and a name means one thing (a name the prelude and a
//! module both spell today is listed as a known overlap until that stage decides
//! which one keeps it).
const std = @import("std");
const product = @import("product.zig");
const standard_library = @import("standard_library.zig");
const prelude_names = @import("prelude_names.zig");

/// Where an operation lives: the prelude (no import) or one standard module.
pub const Home = union(enum) { prelude, module: []const u8 };

/// Stage 2's prelude as `selka docs operations` prints it: the prelude functions that are held to one home (the
/// table's `listed` attribute). The whole prelude, these and the functions the checker builds from collection operations,
/// is `prelude_names.entries`. The list stays under about forty names; a later stage may move an entry to a module and
/// log why.
pub const prelude = prelude_names.namesWhere("listed");

/// Stage 2's prelude spellings that are not a function yet. Every promised spelling
/// has landed, so the list is empty; a later entry keeps the same treatment.
pub const planned = [_][]const u8{};

/// One declaration a module exports: its name and the keyword that declared it.
pub const Export = struct { name: []const u8, kind: []const u8 };

/// The public declarations one embedded module source spells, in source order.
pub fn exportsOf(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]const Export {
    var list: std.ArrayList(Export) = .empty;
    errdefer list.deinit(allocator);
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        const rest = if (std.mem.startsWith(u8, trimmed, "public ")) trimmed["public ".len..] else continue;
        // A `builtin func` is a function the compiler supplies (W10); it keeps its two words as its kind.
        const keyword_len = for ([_][]const u8{ "builtin func", "func", "enum", "record", "result", "union", "type", "constraint", "const" }) |keyword| {
            if (std.mem.startsWith(u8, rest, keyword) and rest.len > keyword.len and rest[keyword.len] == ' ') break keyword.len;
        } else continue;
        const keyword = rest[0..keyword_len];
        const after = rest[keyword_len + 1 ..];
        const name_len = for (after, 0..) |byte, index| {
            if (!std.ascii.isAlphanumeric(byte) and byte != '_') break index;
        } else after.len;
        if (name_len == 0) continue;
        try list.append(allocator, .{ .name = after[0..name_len], .kind = keyword });
    }
    return list.toOwnedSlice(allocator);
}

/// The generated operations table: the prelude, then one section per standard
/// module, each listing its exports once.
pub fn render(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator,
        \\# Operation homes
        \\
        \\Every prelude function is listed under one of the first three headings and needs
        \\no import. A bare call of one is always the prelude function: a module function
        \\with its name is refused when its module calls it bare (E_BUILTIN_FUNCTION_NAME).
        \\A standard module's exports follow, each reached by its qualified name, so a
        \\prelude name can appear again under a module (`math.min` beside `min`). A module
        \\function marked builtin is declared `builtin func`: the compiler supplies every call.
        \\
        \\## prelude (no import)
        \\
    );
    var sorted: [prelude.len][]const u8 = prelude;
    std.mem.sort([]const u8, &sorted, {}, lessThanName);
    for (sorted) |name| {
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, name);
        try out.append(allocator, '\n');
    }
    // The prelude functions the checker builds from collection operations and that are held to no home of their own.
    const built = prelude_names.namesWhere("built");
    try out.appendSlice(allocator, "\n## prelude, built from collection operations\n");
    for (built) |name| {
        if (prelude_names.find(name).?.listed) continue;
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, name);
        try out.append(allocator, '\n');
    }
    // The bare binary64 operations (`float_intrinsics`) that neither of the lists above holds.
    try out.appendSlice(allocator, "\n## prelude, float operations\n");
    for (prelude_names.namesWhere("float")) |name| {
        const item = prelude_names.find(name).?;
        if (item.listed or item.built) continue;
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, name);
        try out.append(allocator, '\n');
    }
    var promised: [planned.len][]const u8 = planned;
    std.mem.sort([]const u8, &promised, {}, lessThanName);
    try out.appendSlice(allocator, "\n## prelude, promised but not a spelling yet\n");
    for (promised) |name| {
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, name);
        try out.append(allocator, '\n');
    }
    for (standard_library.paths) |path| {
        const source = standard_library.source(path) orelse continue;
        const exports = try exportsOf(allocator, source);
        defer allocator.free(exports);
        const module = product.chopSource(path);
        try out.appendSlice(allocator, "\n## ");
        try out.appendSlice(allocator, module);
        try out.append(allocator, '\n');
        for (exports) |entry| {
            try out.appendSlice(allocator, "  ");
            try out.appendSlice(allocator, entry.name);
            // The compiler supplies a `builtin func`'s calls; the page has no body for it (W10).
            if (std.mem.eql(u8, entry.kind, "builtin func")) try out.appendSlice(allocator, " (builtin: the compiler supplies it)");
            try out.append(allocator, '\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

fn lessThanName(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// A name the prelude and one module both spell today. Stage 2b decides which one
/// keeps it; until then the table reports the overlap instead of hiding it.
pub const Overlap = struct { name: []const u8, module: []const u8 };

/// Every prelude/module overlap the module sources spell today, exactly. A new one
/// fails `operations_test` until it is recorded here with the stage that resolves
/// it: the prelude's `append` is an operation on a mutable sequence, while
/// `write` is the stream's output in the prelude and a codec's operation in `csv`
/// and `network`, and `min`, `max`, `sum`, `ord` and `chr` exist in a module as
/// well as the prelude. `append` is the prelude's list push beside
/// `byte_builder.append` and `strings.append`, which write into a builder, and
/// `strings.bytes` is the loop source over a text's octets beside the prelude's
/// conversion. `bytes.parse_int` and `bytes.parse_float` read a whole byte string,
/// the homes of `data.parse_int()` (W13), beside the prelude's parses of a `str`.
pub const overlaps = [_]Overlap{
    .{ .name = "append", .module = "buffers" },
    .{ .name = "append", .module = "byte_builder" },
    .{ .name = "append", .module = "strings" },
    .{ .name = "bytes", .module = "strings" },
    .{ .name = "chr", .module = "strings" },
    .{ .name = "max", .module = "math" },
    .{ .name = "max", .module = "simd" },
    .{ .name = "min", .module = "math" },
    .{ .name = "min", .module = "simd" },
    .{ .name = "ord", .module = "strings" },
    .{ .name = "parse_float", .module = "bytes" },
    .{ .name = "parse_int", .module = "bytes" },
    .{ .name = "sum", .module = "simd" },
    .{ .name = "sum", .module = "time" },
    .{ .name = "write", .module = "csv" },
    .{ .name = "write", .module = "logging" },
    .{ .name = "write", .module = "network" },
};
