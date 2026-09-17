//! Parse-only declaration listing keeps kinds, names, exports and byte ranges.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

const kinds_module =
    \\module kinds
    \\import math
    \\import shared.units as units
    \\
    \\
    \\# leading comment
    \\# second line
    \\type Count = i64
    \\
    \\
    \\# reusable contract
    \\constraint Prices[P] = copy
    \\
    \\
    \\export Count
    \\
    \\
    \\const LIMIT: Count = 3
    \\
    \\
    \\class Job:
    \\    id: Count
    \\
    \\
    \\enum Colour:
    \\    red,
    \\    green
    \\
    \\
    \\union Shape:
    \\    dot: i64,
    \\    line: i64
    \\
    \\
    \\result Outcome:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\domain Distance: i64:
    \\    def make(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    \\
    \\
    \\resource Handle: filesystem
    \\
    \\
    \\host def measure(host: Host, x: i64) -> i64 effects(host)
    \\
    \\
    \\export main
    \\
    \\
    \\def main() -> i64:
    \\    return LIMIT
;

const Range = struct { start: usize, end: usize };
const Wire = struct {
    version: []const u8,
    module: ?[]const u8,
    header: ?Range,
    imports: []const struct { name: []const u8, alias: ?[]const u8, bytes: Range },
    exports: []const struct { name: []const u8, bytes: Range },
    declarations: []const struct { kind: []const u8, name: []const u8, exported: bool, bytes: Range, comment_start: usize },
};
/// `comment` defaults to `text`: a declaration with no leading comment reports its own start.
const Expected = struct { kind: []const u8, name: []const u8, exported: bool, text: []const u8, comment: ?[]const u8 = null };
const expected_declarations = [_]Expected{
    .{ .kind = "alias", .name = "Count", .exported = true, .text = "type Count = i64", .comment = "# leading comment" },
    .{ .kind = "constraint", .name = "Prices", .exported = false, .text = "constraint Prices[P] = copy", .comment = "# reusable contract" },
    .{ .kind = "const", .name = "LIMIT", .exported = false, .text = "const LIMIT: Count = 3" },
    .{ .kind = "struct", .name = "Job", .exported = false, .text =
    \\class Job:
    \\    id: Count
    },
    .{ .kind = "enum", .name = "Colour", .exported = false, .text =
    \\enum Colour:
    \\    red,
    \\    green
    },
    .{ .kind = "union", .name = "Shape", .exported = false, .text =
    \\union Shape:
    \\    dot: i64,
    \\    line: i64
    },
    .{ .kind = "result", .name = "Outcome", .exported = false, .text =
    \\result Outcome:
    \\    ok: i64,
    \\    err: i64
    },
    .{ .kind = "domain", .name = "Distance", .exported = false, .text =
    \\domain Distance: i64:
    \\    def make(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    },
    .{ .kind = "resource", .name = "Handle", .exported = false, .text = "resource Handle: filesystem" },
    .{ .kind = "host_fn", .name = "measure", .exported = false, .text = "host def measure(host: Host, x: i64) -> i64 effects(host)" },
    .{ .kind = "fn", .name = "main", .exported = true, .text =
    \\def main() -> i64:
    \\    return LIMIT
    },
};

fn list(allocator: std.mem.Allocator, path: []const u8, text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(allocator, path, text);
    defer compilation.deinit();
    return compilation.listDeclarations(allocator);
}

fn scenario(allocator: std.mem.Allocator) !void {
    const listing = try list(allocator, "kinds.my", kinds_module);
    defer allocator.free(listing);
    const parsed = try std.json.parseFromSlice(Wire, allocator, listing, .{});
    defer parsed.deinit();
    const wire = parsed.value;
    try t.expectEqualStrings("declarations-v1", wire.version);
    try t.expectEqualStrings("kinds", wire.module.?);
    try t.expectEqual(@as(usize, 0), wire.header.?.start);
    try t.expectEqualStrings("module kinds", kinds_module[wire.header.?.start..wire.header.?.end]);
    try t.expectEqual(@as(usize, 2), wire.imports.len);
    try t.expectEqualStrings("math", wire.imports[0].name);
    try t.expect(wire.imports[0].alias == null);
    try t.expectEqualStrings("import math", kinds_module[wire.imports[0].bytes.start..wire.imports[0].bytes.end]);
    try t.expectEqualStrings("shared.units", wire.imports[1].name);
    try t.expectEqualStrings("units", wire.imports[1].alias.?);
    try t.expectEqual(@as(usize, 2), wire.exports.len);
    try t.expectEqualStrings("Count", wire.exports[0].name);
    try t.expectEqualStrings("export main", kinds_module[wire.exports[1].bytes.start..wire.exports[1].bytes.end]);
    try t.expectEqual(expected_declarations.len, wire.declarations.len);
    for (wire.declarations, expected_declarations) |listed, expected| {
        try t.expectEqualStrings(expected.kind, listed.kind);
        try t.expectEqualStrings(expected.name, listed.name);
        try t.expectEqual(expected.exported, listed.exported);
        try t.expectEqual(std.mem.indexOf(u8, kinds_module, expected.text).?, listed.bytes.start);
        try t.expectEqualStrings(expected.text, kinds_module[listed.bytes.start..listed.bytes.end]);
        try t.expectEqual(std.mem.indexOf(u8, kinds_module, expected.comment orelse expected.text).?, listed.comment_start);
    }
}

// spec: DECLARATION-LIST-1
test "declaration listing reports every top-level kind with names exports and byte ranges" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}

test "declaration listing parses without checking and rejects unresolved exports" {
    const unchecked =
        \\module m
        \\
        \\
        \\def main() -> i64:
        \\    flag: bool = 1
        \\    return flag
    ;
    const listing = try list(t.allocator, "unchecked.my", unchecked);
    defer t.allocator.free(listing);
    try t.expect(std.mem.indexOf(u8, listing, "\"name\":\"main\"") != null);
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\module m
        \\export missing
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        , .code = "E_UNKNOWN_EXPORT" },
        .{ .text =
        \\module m
        \\export main
        \\export main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        , .code = "E_DUPLICATE_EXPORT" },
        .{ .text =
        \\def main() -> i64:
        \\    return 1 +
        , .code = "E_EXPRESSION" },
        .{ .text =
        \\module m
        \\def broken(
        , .code = "E_SYNTAX" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.listDeclarations(t.allocator));
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "single-file listings report no module header and preserve declaration order" {
    const text =
        \\# note
        \\const X: i64 = 4
        \\
        \\
        \\class Point:
        \\    x: i64
        \\
        \\
        \\def main() -> i64:
        \\    return X
    ;
    const listing = try list(t.allocator, "single.my", text);
    defer t.allocator.free(listing);
    const parsed = try std.json.parseFromSlice(Wire, t.allocator, listing, .{});
    defer parsed.deinit();
    try t.expect(parsed.value.module == null);
    try t.expect(parsed.value.header == null);
    try t.expectEqual(@as(usize, 0), parsed.value.imports.len);
    try t.expectEqual(@as(usize, 3), parsed.value.declarations.len);
    try t.expectEqual(@as(usize, 0), parsed.value.declarations[0].comment_start);
    try t.expectEqualStrings("const", parsed.value.declarations[0].kind);
    var previous: usize = 0;
    for (parsed.value.declarations) |listed| {
        try t.expect(listed.bytes.start >= previous);
        try t.expect(listed.comment_start <= listed.bytes.start);
        previous = listed.bytes.end;
    }
}
