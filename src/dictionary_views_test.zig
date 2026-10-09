//! Ephemeral dictionary projections and explicit snapshot diagnostics.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn rejected(text: []const u8, expression: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "views.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const diagnostic = c.diagnostics.items[0];
    try t.expectEqualStrings("E_VIEW_STORED", diagnostic.code);
    try t.expectEqualStrings(expression, c.src.text(diagnostic.span));
    const expected = try std.fmt.allocPrint(t.allocator, "list({s})", .{expression});
    defer t.allocator.free(expected);
    if (diagnostic.provenance.fix) |fix| try t.expectEqualStrings(expected, fix.edit.text);
}

fn snapshotFix(text: []const u8, expected: ?[]const u8) !void {
    var c = try language.Compilation.init(t.allocator, "fix-view.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const diagnostic = c.diagnostics.items[0];
    try t.expectEqualStrings("E_VIEW_STORED", diagnostic.code);
    if (expected) |replacement| {
        const fix = diagnostic.provenance.fix orelse return error.TestUnexpectedResult;
        try t.expectEqualStrings(replacement, fix.edit.text);
    } else try t.expect(diagnostic.provenance.fix == null);
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 snapshot fixes distinguish inferred bindings from declared view APIs" {
    try snapshotFix("func main() -> int:\n    mut d = {1:7}\n    mut kept = d.values()\n    return 0\n", "list(d.values())");
    try snapshotFix("func main() -> int:\n    mut d = {1:7}\n    mut kept = [d.items()]\n    return 0\n", "list(d.items())");
    try snapshotFix("func main() -> int:\n    mut d = {1:7}\n    mut kept: DictKeys[int,int] = d.keys()\n    return 0\n", null);
    try snapshotFix("func held(d: dict[int,int]) -> DictValues[int,int]:\n    return d.values()\nfunc main() -> int:\n    return 0\n", null);
}

// spec: D2-VIEW-STORAGE-1
test "D2 rejects local stored keys values and items with contextual snapshots" {
    try rejected("func main() -> int:\n    mut d = {1: 7}\n    mut kept = d.keys()\n    return 0\n", "d.keys()");
    try rejected("func main() -> int:\n    mut d = {1: 7}\n    mut kept = d.values()\n    return 0\n", "d.values()");
    try rejected("func main() -> int:\n    mut d = {1: 7}\n    mut kept = d.items()\n    return 0\n", "d.items()");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects aggregate list fixed array return and interior stored views" {
    try rejected("record Held:\n    live: DictValues[int,int]\nfunc main() -> int:\n    mut d = {1:7}\n    mut kept = Held(d.values())\n    return 0\n", "DictValues");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    mut kept = [d.values()]\n    return 0\n", "d.values()");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    mut kept: FixedArray[DictKeys[int,int], 1] = [d.keys()]\n    return 0\n", "DictKeys");
    try rejected("func held(d: dict[int,int]) -> DictItems[int,int]:\n    return d.items()\nfunc main() -> int:\n    return 0\n", "DictItems");
    try rejected("func main() -> int:\n    mut rows = [{1:7}]\n    mut kept = rows[0].values()\n    return 0\n", "rows[0].values()");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects ordinary calls mapping projections discarded views and rebinding" {
    try rejected("func use[T: copy + storable](view: T) -> int:\n    return 0\nfunc main() -> int:\n    mut d = {1:7}\n    return use(d.values())\n", "d.values()");
    try rejected("func use(mut view: int[]) -> int:\n    return len(view)\nfunc main() -> int:\n    mut d = {1:7}\n    return use(mut d.values())\n", "d.values()");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    mut saved = d.values().mapping\n    return 0\n", "d.values()");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    _ = d.values()\n    return 0\n", "d.values()");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    mut kept = list(d.values())\n    kept = d.values()\n    return 0\n", "d.values()");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 checks unused generic bodies and denies numeric folds on direct views" {
    try rejected("func held[T: copy + storable](d: dict[int,T]) -> T[]:\n    return d.values()\nfunc main() -> int:\n    return 0\n", "d.values()");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    return sum(d.values())\n", "d.values()");
}

// spec: DICT-VIEWS-1
// spec-case: D2-VIEW-STORAGE-1
test "D2 keeps loops comprehensions enumerate len membership and snapshot consumers" {
    var c = try language.Compilation.init(t.allocator, "direct-views.selka",
        \\func main() -> int:
        \\    mut d = {1:7, 2:9}
        \\    mut result = len(d.keys()) + len(d.values()) + len(d.items())
        \\    for key in d.keys():
        \\        result += key
        \\    for value in d.values():
        \\        result += value
        \\    for key, value in d.items():
        \\        result += key + value
        \\    for index, item in enumerate(d.items()):
        \\        result += index + item.value
        \\    mut rows = [for item in d.items() yield item.value]
        \\    mut snapshots = [list(d.keys()), list(d.values()), sorted(d.values())]
        \\    mut unique = set(d.values())
        \\    return if (7 in d.values() and 2 in d.keys()) then (result) else (0)
    );
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
}

// spec-case: DICT-VIEWS-1
test "direct dictionary view iteration remains noalloc while snapshots allocate" {
    const text = "func total(d: dict[int,int]) -> int noalloc:\n    mut n = len(d.values())\n    for value in d.values():\n        n += value\n    return n\nfunc main() -> int:\n    return 0\n";
    var c = try language.Compilation.init(t.allocator, "noalloc-view.selka", text);
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
    var snapshot = try language.Compilation.init(t.allocator, "snapshot.selka", "func copy(d: dict[int,int]) -> int[] noalloc:\n    return list(d.values())\nfunc main() -> int:\n    return 0\n");
    defer snapshot.deinit();
    try t.expectError(error.SourceError, snapshot.check());
    try t.expectEqualStrings("E_EFFECT_BOUND", snapshot.diagnostics.items[0].code);
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects view annotations before unused ordinary and generic bodies" {
    try rejected("func unused(value: DictKeys[int,int]) -> int:\n    return 0\nfunc main() -> int:\n    return 0\n", "DictKeys");
    try rejected("func unused() -> DictValues[int,int]:\n    return 0\nfunc main() -> int:\n    return 0\n", "DictValues");
    try rejected("record Unused:\n    value: DictItems[int,int]\nfunc main() -> int:\n    return 0\n", "DictItems");
    try rejected("func unused(values: DictValues[int,int][]) -> int:\n    return 0\nfunc main() -> int:\n    return 0\n", "DictValues");
    try rejected("func unused[T: copy + storable](value: DictKeys[int,T]) -> int:\n    return 0\nfunc main() -> int:\n    return 0\n", "DictKeys");
    try rejected("func unused[T: copy + storable]() -> DictValues[int,T]:\n    return 0\nfunc main() -> int:\n    return 0\n", "DictValues");
    try rejected("record Unused[T]:\n    value: DictItems[int,T]\nfunc main() -> int:\n    return 0\n", "DictItems");
    try rejected("func unused[T: copy + storable](values: dict[int, DictItems[int,T][]]) -> int:\n    return 0\nfunc main() -> int:\n    return 0\n", "DictItems");
}

// spec-case: DICT-VIEWS-1
test "D2 keys membership uses dictionary hash contains without a generated loop" {
    const text = "func present(d: dict[int,int], key: int) -> bool noalloc:\n    return key in d.keys()\nfunc absent(d: dict[int,int], key: int) -> bool noalloc:\n    return key not in d.keys()\nfunc main() -> int:\n    return 0\n";
    var c = try language.Compilation.init(t.allocator, "key-membership.selka", text);
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(usize, 2), hashMembershipCount(c.program.?));
    for (c.program.?.statements) |statement| try t.expect(statement.data != .loop);
}

fn hashMembershipCount(program: @import("typed.zig").Program) usize {
    var count: usize = 0;
    for (program.nodes) |node| if (node.data == .buffer_operation and node.data.buffer_operation.kind == .contains) {
        count += 1;
    };
    return count;
}
