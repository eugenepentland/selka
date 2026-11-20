//! The generated operations table: one home per operation, one meaning per name.
const std = @import("std");
const product = @import("product.zig");
const operations = @import("operations.zig");
const standard_library = @import("standard_library.zig");

/// The one diagnostic this file prints when a recorded overlap goes missing.
const report = std.debug.print;

fn lessThanName(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Whether one name list holds `name` exactly.
fn holds(names: []const []const u8, name: []const u8) bool {
    for (names) |entry| if (std.mem.eql(u8, entry, name)) return true;
    return false;
}

/// The prelude names, sorted, for a stable report.
fn sortedPrelude() [operations.prelude.len][]const u8 {
    var copy: [operations.prelude.len][]const u8 = operations.prelude;
    std.mem.sort([]const u8, &copy, {}, lessThanName);
    return copy;
}

// spec: STDLIB-OPERATIONS-TABLE-1
test "the prelude holds each name once and stays under forty names" {
    const names = sortedPrelude();
    for (names[1..], 1..) |name, index| try std.testing.expect(!std.mem.eql(u8, name, names[index - 1]));
    try std.testing.expect(names.len <= 40);
    try std.testing.expect(holds(&names, "print"));
    try std.testing.expect(holds(&names, "write"));
    // `append` and `sort` are real spellings now; the promised list is empty.
    try std.testing.expect(holds(&names, "append"));
    try std.testing.expect(holds(&names, "sort"));
    try std.testing.expectEqual(@as(usize, 0), operations.planned.len);
}

// spec: STDLIB-OPERATIONS-TABLE-1
test "a module's exports are derived from its own source" {
    const exports = try operations.exportsOf(std.testing.allocator,
        \\# a comment
        \\public func split(text: str) -> str[]:
        \\    return []
        \\
        \\
        \\public record Builder:
        \\    buffer: byte_buffer
        \\
        \\
        \\public const limit = 3
        \\
        \\func hidden() -> int:
        \\    return 0
    );
    defer std.testing.allocator.free(exports);
    try std.testing.expectEqual(@as(usize, 3), exports.len);
    try std.testing.expectEqualStrings("split", exports[0].name);
    try std.testing.expectEqualStrings("func", exports[0].kind);
    try std.testing.expectEqualStrings("Builder", exports[1].name);
    try std.testing.expectEqualStrings("record", exports[1].kind);
    try std.testing.expectEqualStrings("limit", exports[2].name);
}

/// Every (module, name) pair where a module exports a spelling the prelude owns.
fn modulePreludeOverlaps(allocator: std.mem.Allocator) ![]operations.Overlap {
    var pairs: std.ArrayList(operations.Overlap) = .empty;
    errdefer pairs.deinit(allocator);
    for (standard_library.paths) |path| {
        const source = standard_library.source(path) orelse continue;
        const exports = try operations.exportsOf(allocator, source);
        defer allocator.free(exports);
        const module = product.chopSource(path);
        for (exports) |entry| {
            if (!holds(&operations.prelude, entry.name)) continue;
            try pairs.append(allocator, .{ .name = entry.name, .module = module });
        }
    }
    return pairs.toOwnedSlice(allocator);
}

/// Every recorded overlap is still a real one, so a resolved conflict removes its
/// record instead of leaving a stale entry.
fn expectEveryOverlapIsPresent(found: []const operations.Overlap) !void {
    for (operations.overlaps) |recorded| {
        var present = false;
        for (found) |pair| {
            if (std.mem.eql(u8, pair.name, recorded.name) and std.mem.eql(u8, pair.module, recorded.module)) present = true;
        }
        if (!present) report("recorded overlap is gone: {s}.{s}\n", .{ recorded.module, recorded.name });
        try std.testing.expect(present);
    }
}

// spec: STDLIB-OPERATIONS-TABLE-1
test "a prelude name a module also spells is a recorded overlap" {
    const found = try modulePreludeOverlaps(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(operations.overlaps.len, found.len);
    try expectEveryOverlapIsPresent(found);
}

/// Each standard module has a section of its own in the table.
fn expectEveryModuleHeading(allocator: std.mem.Allocator, text: []const u8) !void {
    for (standard_library.paths) |path| {
        const module = product.chopSource(path);
        const heading = try std.fmt.allocPrint(allocator, "\n## {s}\n", .{module});
        defer allocator.free(heading);
        try std.testing.expect(std.mem.indexOf(u8, text, heading) != null);
    }
}

// spec: STDLIB-OPERATIONS-TABLE-1
test "the generated table lists each prelude name and each module heading" {
    const text = try operations.render(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.startsWith(u8, text, "# Operation homes\n"));
    try std.testing.expect(std.mem.indexOf(u8, text, "## prelude (no import)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "## prelude, promised but not a spelling yet\n") != null);
    for (operations.prelude) |name| {
        const needle = try std.fmt.allocPrint(std.testing.allocator, "  {s}\n", .{name});
        defer std.testing.allocator.free(needle);
        try std.testing.expect(std.mem.indexOf(u8, text, needle) != null);
    }
    try expectEveryModuleHeading(std.testing.allocator, text);
    try std.testing.expect(std.mem.indexOf(u8, text, "  starts_with\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "  words (builtin: the compiler supplies it)\n") != null);
}

// spec-case: W10-OPERATIONS-1
test "W10 the operations table lists a builtin func with its word" {
    const exports = try operations.exportsOf(std.testing.allocator, "public builtin func upper(text: str) -> str\npublic func shout(text: str) -> str:\n    return text\n");
    defer std.testing.allocator.free(exports);
    try std.testing.expectEqual(@as(usize, 2), exports.len);
    try std.testing.expectEqualStrings("upper", exports[0].name);
    try std.testing.expectEqualStrings("builtin func", exports[0].kind);
    try std.testing.expectEqualStrings("func", exports[1].kind);
    const table = try operations.render(std.testing.allocator);
    defer std.testing.allocator.free(table);
    try std.testing.expect(std.mem.indexOf(u8, table, "  upper (builtin: the compiler supplies it)\n") != null);
    // `strings.find` keeps its body: it answers `int?` where the bounded search answers `-1` (W13-S3 made `strip` a home).
    try std.testing.expect(std.mem.indexOf(u8, table, "  find\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, table, "  strip (builtin: the compiler supplies it)\n") != null);
}
