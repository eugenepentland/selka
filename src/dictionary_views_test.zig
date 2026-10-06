//! Ephemeral dictionary projections and explicit snapshot diagnostics.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn rejected(text: []const u8, expression: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "views.my", text);
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
    var c = try language.Compilation.init(t.allocator, "fix-view.my", text);
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
    try snapshotFix("def main() -> int:\n    d = {1:7}\n    kept = d.values()\n    return 0\n", "list(d.values())");
    try snapshotFix("def main() -> int:\n    d = {1:7}\n    kept = [d.items()]\n    return 0\n", "list(d.items())");
    try snapshotFix("def main() -> int:\n    d = {1:7}\n    kept: DictKeys[int,int] = d.keys()\n    return 0\n", null);
    try snapshotFix("def held(d: dict[int,int]) -> DictValues[int,int]:\n    return d.values()\ndef main() -> int:\n    return 0\n", null);
}

// spec: D2-VIEW-STORAGE-1
test "D2 rejects local stored keys values and items with contextual snapshots" {
    try rejected("def main() -> int:\n    d = {1: 7}\n    kept = d.keys()\n    return 0\n", "d.keys()");
    try rejected("def main() -> int:\n    d = {1: 7}\n    kept = d.values()\n    return 0\n", "d.values()");
    try rejected("def main() -> int:\n    d = {1: 7}\n    kept = d.items()\n    return 0\n", "d.items()");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects aggregate list fixed array return and interior stored views" {
    try rejected("record Held:\n    live: DictValues[int,int]\ndef main() -> int:\n    d = {1:7}\n    kept = Held(d.values())\n    return 0\n", "DictValues");
    try rejected("def main() -> int:\n    d = {1:7}\n    kept = [d.values()]\n    return 0\n", "d.values()");
    try rejected("def main() -> int:\n    d = {1:7}\n    kept: [1]DictKeys[int,int] = [d.keys()]\n    return 0\n", "DictKeys");
    try rejected("def held(d: dict[int,int]) -> DictItems[int,int]:\n    return d.items()\ndef main() -> int:\n    return 0\n", "DictItems");
    try rejected("def main() -> int:\n    rows = [{1:7}]\n    kept = rows[0].values()\n    return 0\n", "rows[0].values()");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects ordinary calls mapping projections discarded views and rebinding" {
    try rejected("def use[T: copy + storable](view: T) -> int:\n    return 0\ndef main() -> int:\n    d = {1:7}\n    return use(d.values())\n", "d.values()");
    try rejected("def use(view: mut list[int]) -> int:\n    return len(view)\ndef main() -> int:\n    d = {1:7}\n    return use(mut d.values())\n", "d.values()");
    try rejected("def main() -> int:\n    d = {1:7}\n    saved = d.values().mapping\n    return 0\n", "d.values()");
    try rejected("def main() -> int:\n    d = {1:7}\n    _ = d.values()\n    return 0\n", "d.values()");
    try rejected("def main() -> int:\n    d = {1:7}\n    kept = list(d.values())\n    kept = d.values()\n    return 0\n", "d.values()");
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 checks unused generic bodies and denies numeric folds on direct views" {
    try rejected("def held[T: copy + storable](d: dict[int,T]) -> list[T]:\n    return d.values()\ndef main() -> int:\n    return 0\n", "d.values()");
    try rejected("def main() -> int:\n    d = {1:7}\n    return sum(d.values())\n", "d.values()");
}

// spec: DICT-VIEWS-1
// spec-case: D2-VIEW-STORAGE-1
test "D2 keeps loops comprehensions enumerate len membership and snapshot consumers" {
    var c = try language.Compilation.init(t.allocator, "direct-views.my",
        \\def main() -> int:
        \\    d = {1:7, 2:9}
        \\    result = len(d.keys()) + len(d.values()) + len(d.items())
        \\    for key in d.keys():
        \\        result += key
        \\    for value in d.values():
        \\        result += value
        \\    for key, value in d.items():
        \\        result += key + value
        \\    for index, item in enumerate(d.items()):
        \\        result += index + item.value
        \\    rows = [item.value for item in d.items()]
        \\    snapshots = [list(d.keys()), list(d.values()), sorted(d.values())]
        \\    unique = set(d.values())
        \\    return result if 7 in d.values() and 2 in d.keys() else 0
    );
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
}

// spec-case: DICT-VIEWS-1
test "direct dictionary view iteration remains noalloc while snapshots allocate" {
    const text = "def total(d: dict[int,int]) -> int noalloc:\n    n = len(d.values())\n    for value in d.values():\n        n += value\n    return n\ndef main() -> int:\n    return 0\n";
    var c = try language.Compilation.init(t.allocator, "noalloc-view.my", text);
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
    var snapshot = try language.Compilation.init(t.allocator, "snapshot.my", "def copy(d: dict[int,int]) -> list[int] noalloc:\n    return list(d.values())\ndef main() -> int:\n    return 0\n");
    defer snapshot.deinit();
    try t.expectError(error.SourceError, snapshot.check());
    try t.expectEqualStrings("E_EFFECT_BOUND", snapshot.diagnostics.items[0].code);
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects view annotations before unused ordinary and generic bodies" {
    try rejected("def unused(value: DictKeys[int,int]) -> int:\n    return 0\ndef main() -> int:\n    return 0\n", "DictKeys");
    try rejected("def unused() -> DictValues[int,int]:\n    return 0\ndef main() -> int:\n    return 0\n", "DictValues");
    try rejected("record Unused:\n    value: DictItems[int,int]\ndef main() -> int:\n    return 0\n", "DictItems");
    try rejected("def unused(values: list[DictValues[int,int]]) -> int:\n    return 0\ndef main() -> int:\n    return 0\n", "DictValues");
    try rejected("def unused[T: copy + storable](value: DictKeys[int,T]) -> int:\n    return 0\ndef main() -> int:\n    return 0\n", "DictKeys");
    try rejected("def unused[T: copy + storable]() -> DictValues[int,T]:\n    return 0\ndef main() -> int:\n    return 0\n", "DictValues");
    try rejected("record Unused[T]:\n    value: DictItems[int,T]\ndef main() -> int:\n    return 0\n", "DictItems");
    try rejected("def unused[T: copy + storable](values: dict[int,list[DictItems[int,T]]]) -> int:\n    return 0\ndef main() -> int:\n    return 0\n", "DictItems");
}

// spec-case: DICT-VIEWS-1
test "D2 keys membership uses dictionary hash contains without a generated loop" {
    const text = "def present(d: dict[int,int], key: int) -> bool noalloc:\n    return key in d.keys()\ndef absent(d: dict[int,int], key: int) -> bool noalloc:\n    return key not in d.keys()\ndef main() -> int:\n    return 0\n";
    var c = try language.Compilation.init(t.allocator, "key-membership.my", text);
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
