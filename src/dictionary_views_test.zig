//! Ephemeral dictionary projections and explicit snapshot diagnostics.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");

fn rejected(text: []const u8, expression: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try t.expect(!report.passed);
    const diagnostic = report.diagnostics[0];
    try t.expectEqualStrings("E_VIEW_STORED", diagnostic.code);
    try t.expectEqualStrings(expression, report.text(diagnostic.span));
    const expected = try std.fmt.allocPrint(arena.allocator(), "list({s})", .{expression});
    if (diagnostic.provenance.fix) |fix| try t.expectEqualStrings(expected, fix.edit.text);
}

fn snapshotFix(text: []const u8, expected: ?[]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try t.expect(!report.passed);
    const diagnostic = report.diagnostics[0];
    try t.expectEqualStrings("E_VIEW_STORED", diagnostic.code);
    if (expected) |replacement| {
        const fix = diagnostic.provenance.fix orelse return error.TestUnexpectedResult;
        try t.expectEqualStrings(replacement, fix.edit.text);
    } else try t.expect(diagnostic.provenance.fix == null);
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 snapshot fixes distinguish inferred bindings from declared view APIs" {
    try snapshotFix("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    mut kept = dicts.values(d)\n    return 0\n", "list(dicts.values(d))");
    try snapshotFix("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    mut kept = [dicts.items(d)]\n    return 0\n", "list(dicts.items(d))");
    try snapshotFix("func main() -> int:\n    mut d = {1:7}\n    mut kept: DictKeys[int,int] = d.keys()\n    return 0\n", null);
    try snapshotFix("func held(d: dict[int,int]) -> DictValues[int,int]:\n    return d.values()\nfunc main() -> int:\n    return 0\n", null);
}

// spec: D2-VIEW-STORAGE-1
test "D2 rejects local stored keys values and items with contextual snapshots" {
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1: 7}\n    mut kept = dicts.keys(d)\n    return 0\n", "dicts.keys(d)");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1: 7}\n    mut kept = dicts.values(d)\n    return 0\n", "dicts.values(d)");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1: 7}\n    mut kept = dicts.items(d)\n    return 0\n", "dicts.items(d)");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects aggregate list fixed array return and interior stored views" {
    try rejected("record Held:\n    live: DictValues[int,int]\nfunc main() -> int:\n    mut d = {1:7}\n    mut kept = Held(d.values())\n    return 0\n", "DictValues");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    mut kept = [dicts.values(d)]\n    return 0\n", "dicts.values(d)");
    try rejected("func main() -> int:\n    mut d = {1:7}\n    mut kept: FixedArray[DictKeys[int,int], 1] = [d.keys()]\n    return 0\n", "DictKeys");
    try rejected("func held(d: dict[int,int]) -> DictItems[int,int]:\n    return d.items()\nfunc main() -> int:\n    return 0\n", "DictItems");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut rows = [{1:7}]\n    mut kept = dicts.values(rows[0])\n    return 0\n", "dicts.values(rows[0])");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects ordinary calls mapping projections discarded views and rebinding" {
    try rejected("import dicts\n\nfunc use[T: copy + storable](view: T) -> int:\n    return 0\nfunc main() -> int:\n    mut d = {1:7}\n    return use(dicts.values(d))\n", "dicts.values(d)");
    try rejected("import dicts\n\nfunc use(mut view: int[]) -> int:\n    return len(view)\nfunc main() -> int:\n    mut d = {1:7}\n    return use(mut dicts.values(d))\n", "dicts.values(d)");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    mut saved = dicts.values(d).mapping\n    return 0\n", "dicts.values(d)");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    _ = dicts.values(d)\n    return 0\n", "dicts.values(d)");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    mut kept = list(dicts.values(d))\n    kept = dicts.values(d)\n    return 0\n", "dicts.values(d)");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 checks unused generic bodies and denies numeric folds on direct views" {
    try rejected("import dicts\n\nfunc held[T: copy + storable](d: dict[int,T]) -> T[]:\n    return dicts.values(d)\nfunc main() -> int:\n    return 0\n", "dicts.values(d)");
    try rejected("import dicts\n\nfunc main() -> int:\n    mut d = {1:7}\n    return sum(dicts.values(d))\n", "dicts.values(d)");
}

// spec: DICT-VIEWS-1
// spec-case: D2-VIEW-STORAGE-1
test "D2 keeps loops comprehensions enumerate len membership and snapshot consumers" {
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut d = {1:7, 2:9}
        \\    mut result = len(dicts.keys(d)) + len(dicts.values(d)) + len(dicts.items(d))
        \\    for key in dicts.keys(d):
        \\        result += key
        \\    for value in dicts.values(d):
        \\        result += value
        \\    for key, value in dicts.items(d):
        \\        result += key + value
        \\    for index, item in enumerate(dicts.items(d)):
        \\        result += index + item.value
        \\    mut rows: int[] = []
        \\    for item in dicts.items(d):
        \\        append(mut rows, item.value)
        \\    mut snapshots = [list(dicts.keys(d)), list(dicts.values(d)), sorted(dicts.values(d))]
        \\    mut unique = set(dicts.values(d))
        \\    mut has_seven = False
        \\    for value in dicts.values(d):
        \\        if value == 7:
        \\            has_seven = True
        \\    if has_seven and 2 in dicts.keys(d):
        \\        return result
        \\    else:
        \\        return 0
    );
    defer program.deinit();
    try t.expect(program.compilation.program != null);
}

// spec-case: DICT-VIEWS-1
test "direct dictionary view iteration remains noalloc while snapshots allocate" {
    const text = "import dicts\n\n@noalloc\nfunc total(d: dict[int,int]) -> int:\n    mut n = len(dicts.values(d))\n    for value in dicts.values(d):\n        n += value\n    return n\nfunc main() -> int:\n    return 0\n";
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator, text);
    defer program.deinit();
    try t.expect(program.compilation.program != null);
    var snapshot = try language.Compilation.init(t.allocator, "snapshot.selka", "func copy(d: dict[int,int]) -> int[] effects():\n    return list(d.values())\nfunc main() -> int:\n    return 0\n");
    defer snapshot.deinit();
    try t.expectError(error.SourceError, snapshot.check());
    try t.expectEqualStrings("E_EFFECTS_REMOVED", snapshot.diagnostics.items[0].code);
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
    const text = "import dicts\n\n@noalloc\nfunc present(d: dict[int,int], key: int) -> bool:\n" ++
        "    return key in dicts.keys(d)\n@noalloc\nfunc absent(d: dict[int,int], key: int) -> bool:\n" ++
        "    return key not in dicts.keys(d)\nfunc main() -> int:\n    return 0\n";
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator, text);
    defer program.deinit();
    try t.expectEqual(@as(usize, 2), hashMembershipCount(program.compilation.program.?));
    for (program.compilation.program.?.statements) |statement| try t.expect(statement.data != .loop);
}

fn hashMembershipCount(program: @import("typed.zig").Program) usize {
    var count: usize = 0;
    for (program.nodes) |node| if (node.data == .buffer_operation and node.data.buffer_operation.kind == .contains) {
        count += 1;
    };
    return count;
}
