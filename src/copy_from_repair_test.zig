//! `W_COPY_RETURNED` (`copy_from_repair.zig`): the "every return copies a place of `p`" hint as a repair in a project check,
//! with its exact edits, and no warning for each rule that withholds it; the hint itself no longer names a new value beside
//! the copies. The callers' judge is Core's (`single_owner.callerFacts`); `test/fix_cli_test.zig` runs it cold and cached.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const copy_from_repair = @import("copy_from_repair.zig");
const needless_copy = @import("needless_copy.zig");

/// The project's files, served by name; every other path is a standard module.
const Tree = struct {
    files: []const File,

    const File = struct { path: []const u8, text: []const u8 };

    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Tree = @ptrCast(@alignCast(context.?));
        for (self.files) |file| if (std.mem.eql(u8, file.path, path)) return allocator.dupe(u8, file.text);
        return error.NotFound;
    }
};

/// The entry `selka check DIR` writes for a directory of `rows.selka` and its test file.
const check_all = "import rows\nimport rows_test as root_0\n\n\nfunc main() -> int:\n    return 0\n";

/// What a check of `rows` from `entry` says about returned copies: each `W_COPY_RETURNED` warning's message with its edits,
/// written `offset:old->new` against the module text, and how many "every return" `W_COPY_MOVE` hints it gives.
const Found = struct { warnings: []const Warning, hints: usize };
const Warning = struct { message: []const u8, edits: []const []const u8 };

fn found(arena: std.mem.Allocator, entry: []const u8, rows: []const u8) !Found {
    return foundIn(arena, entry, rows, false);
}

/// `found`, with `repairs_public` as the command layer sets it: true for a project that is no package.
fn foundIn(arena: std.mem.Allocator, entry: []const u8, rows: []const u8, repairs_public: bool) !Found {
    var tree: Tree = .{ .files = &.{
        .{ .path = "selka_check_all.selka", .text = check_all },
        .{ .path = "main.selka", .text = "import rows\n\n\nfunc main() -> int:\n    return 0\n" },
        .{ .path = "rows.selka", .text = rows },
        .{ .path = "rows_test.selka", .text = "import rows\n\n\npublic func test_rows() -> bool:\n    return rows.size() > 0\n" },
    } };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &tree, .read = Tree.read }, entry, .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.repairs_public = repairs_public;
    try compilation.check();
    const start = std.mem.indexOf(u8, compilation.src.bytes, rows).?;
    var warnings: std.ArrayList(Warning) = .empty;
    var hints: usize = 0;
    for (compilation.diagnostics.items.items) |item| {
        if (needless_copy.judgedByCallers(item.code, item.message)) |advice| {
            if (advice.form == .result) hints += 1;
        }
        if (copy_from_repair.judged(item.code, item.message) == null) continue;
        const fix = item.provenance.fix.?;
        const edits = try arena.alloc([]const u8, fix.count());
        for (edits, 0..) |*slot, at| {
            const one = fix.at(at);
            slot.* = try std.fmt.allocPrint(arena, "{d}:{s}->{s}", .{ one.span.start - start, compilation.src.text(one.span), one.text });
        }
        try warnings.append(arena, .{ .message = item.message, .edits = edits });
    }
    return .{ .warnings = warnings.items, .hints = hints };
}

/// `edit` as `found` writes it: the offset of `at` in `rows`, the text replaced and the text written.
fn edit(arena: std.mem.Allocator, rows: []const u8, at: []const u8, old: []const u8, new: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{d}:{s}->{s}", .{ std.mem.indexOf(u8, rows, at).?, old, new });
}

const record_row =
    \\public record Row:
    \\    name: str
    \\    tags: str[]
    \\
    \\
    \\public func size() -> int:
    \\    const row = Row(name="a", tags=["b"])
    \\    const tag = first_tag(row) else:
    \\        return 0
    \\    return len(tag) + len(label(row, 1))
    \\
    \\
;

test "copy-returned declares the result from the parameter and returns the places, beside None and a text literal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\func first_tag(row: Row) -> str?:
        \\    if len(row.tags) == 0:
        \\        return None
        \\    return Some(copy(row.tags[0]))
        \\
        \\
        \\func label(row: Row, k: int) -> str:
        \\    if k == 0:
        \\        return ""
        \\    return copy( row.name )
        \\
    ;
    const result = try found(a, "selka_check_all", rows);
    try t.expectEqual(@as(usize, 2), result.warnings.len);
    try t.expectEqual(@as(usize, 2), result.hints);
    try t.expectEqualStrings("every return of `first_tag` copies a place of `row`, and no caller keeps the result: " ++
        "declare it `from row` and return the places themselves", result.warnings[0].message);
    try t.expectEqual(@as(usize, 2), result.warnings[0].edits.len);
    try t.expectEqualStrings(try edit(a, rows, ":\n    if len(row.tags) == 0", "", " from row"), result.warnings[0].edits[0]);
    try t.expectEqualStrings(try edit(a, rows, "copy(row.tags[0])", "copy(row.tags[0])", "row.tags[0]"), result.warnings[0].edits[1]);
    try t.expectEqualStrings(try edit(a, rows, ":\n    if k == 0", "", " from row"), result.warnings[1].edits[0]);
    try t.expectEqualStrings(try edit(a, rows, "copy( row.name )", "copy( row.name )", "row.name"), result.warnings[1].edits[1]);
}

test "copy-returned writes the clause before a fails clause, and turns every returned copy" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\func first_tag(row: Row) -> str?:
        \\    return None
        \\
        \\
        \\func label(row: Row, k: int) -> str:
        \\    const got = named(row, k) else Err(_):
        \\        return ""
        \\    return got
        \\
        \\
        \\func named(row: Row, k: int) -> str fails str:
        \\    if k == 0:
        \\        fail "none"
        \\    if k == 1:
        \\        return copy(row.tags[0])
        \\    return copy(row.name)
        \\
    ;
    const result = try found(a, "selka_check_all", rows);
    try t.expectEqual(@as(usize, 1), result.warnings.len);
    try t.expectEqual(@as(usize, 3), result.warnings[0].edits.len);
    try t.expectEqualStrings(try edit(a, rows, " fails str:", "", " from row"), result.warnings[0].edits[0]);
    try t.expectEqualStrings(try edit(a, rows, "copy(row.tags[0])", "copy(row.tags[0])", "row.tags[0]"), result.warnings[0].edits[1]);
    try t.expectEqualStrings(try edit(a, rows, "copy(row.name)", "copy(row.name)", "row.name"), result.warnings[0].edits[2]);
}

test "copy-returned gives neither warning nor hint where a new value stands beside the copies" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func first_tag(row: Row) -> str?:
        \\    if len(row.tags) == 0:
        \\        return Some(f"{len(row.name)}")
        \\    return Some(copy(row.tags[0]))
        \\
        \\
        \\func label(row: Row, k: int) -> str:
        \\    if k == 0:
        \\        return ["x"][0]
        \\    return copy(row.name)
        \\
    ;
    const result = try found(arena.allocator(), "selka_check_all", rows);
    try t.expectEqual(@as(usize, 0), result.warnings.len);
    try t.expectEqual(@as(usize, 0), result.hints);
}

test "copy-returned is withheld for a public function, one named as a value and a recursive one; the hint stays" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\public func first_tag(row: Row) -> str?:
        \\    return Some(copy(row.name))
        \\
        \\
        \\func label(row: Row, k: int) -> str:
        \\    const pick = labelled
        \\    return pick(row) + f"{k}"
        \\
        \\
        \\func labelled(row: Row) -> str:
        \\    return copy(row.name)
        \\
        \\
        \\func deep(row: Row, k: int) -> str:
        \\    if k > 0:
        \\        _ = deep(row, k - 1)
        \\    return copy(row.name)
        \\
        \\
        \\public func more(row: Row) -> int:
        \\    return len(deep(row, 2))
        \\
    ;
    const result = try found(arena.allocator(), "selka_check_all", rows);
    try t.expectEqual(@as(usize, 0), result.warnings.len);
    // `first_tag`, `labelled` and `deep`.
    try t.expectEqual(@as(usize, 3), result.hints);
}

test "copy-returned repairs a public function in a project that is no package, and says its signature changes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\public func first_tag(row: Row) -> str?:
        \\    return Some(copy(row.name))
        \\
        \\
        \\func label(row: Row, k: int) -> str:
        \\    return f"{row.name}{k}"
        \\
        \\
        \\func plain(row: Row) -> str:
        \\    return copy(row.name)
        \\
        \\
        \\public func nested(row: Row, k: int) -> str:
        \\    if k > 0:
        \\        _ = nested(row, k - 1)
        \\    return copy(row.name)
        \\
        \\
        \\public func apart(row: Row) -> str:
        \\    return copy(row.name)
        \\
        \\
        \\public func valued(row: Row) -> int:
        \\    const pick = apart
        \\    return len(pick(row))
        \\
    ;
    // A package, or a project with interface files: the private `plain` only, and the hints of all four.
    const kept = try foundIn(a, "selka_check_all", rows, false);
    try t.expectEqual(@as(usize, 1), kept.warnings.len);
    try t.expect(std.mem.indexOf(u8, kept.warnings[0].message, "`plain`") != null);
    try t.expectEqual(@as(usize, 4), kept.hints);
    // No package: `first_tag` too, its message with the clause the private `plain`'s lacks; the recursive `nested` and `apart`,
    // named as a value, stay withheld whoever may call them.
    const result = try foundIn(a, "selka_check_all", rows, true);
    try t.expectEqual(@as(usize, 2), result.warnings.len);
    try t.expectEqualStrings("every return of `first_tag` copies a place of `row`, and no caller keeps the result: " ++
        "declare it `from row` and return the places themselves; `first_tag` is public, so its signature changes", result.warnings[0].message);
    try t.expectEqual(@as(usize, 2), result.warnings[0].edits.len);
    try t.expectEqualStrings(try edit(a, rows, ":\n    return Some(copy(row.name))", "", " from row"), result.warnings[0].edits[0]);
    try t.expectEqualStrings(try edit(a, rows, "copy(row.name))", "copy(row.name)", "row.name"), result.warnings[0].edits[1]);
    try t.expectEqualStrings("every return of `plain` copies a place of `row`, and no caller keeps the result: " ++
        "declare it `from row` and return the places themselves", result.warnings[1].message);
    try t.expectEqual(kept.hints, result.hints);
}

test "copy-returned gives no hint for a mut parameter of a function failing with text, and no warning for one entry" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func first_tag(row: Row) -> str?:
        \\    return Some(copy(row.name))
        \\
        \\
        \\func label(row: Row, k: int) -> str:
        \\    mut held = Row(name=copy(row.name), tags=[])
        \\    const got = touched(mut held) else Err(_):
        \\        return ""
        \\    return got + f"{k}"
        \\
        \\
        \\func touched(mut row: Row) -> str fails str:
        \\    append(mut row.tags, "t")
        \\    if len(row.tags) > 5:
        \\        fail "full"
        \\    return copy(row.name)
        \\
    ;
    const project = try found(arena.allocator(), "selka_check_all", rows);
    try t.expectEqual(@as(usize, 1), project.warnings.len);
    try t.expect(std.mem.indexOf(u8, project.warnings[0].message, "`first_tag`") != null);
    const alone = try found(arena.allocator(), "main", rows);
    try t.expectEqual(@as(usize, 0), alone.warnings.len);
    // The hint of `first_tag` only: `from row` on `touched` is `E_CORE_UNSUPPORTED` whatever the callers do.
    try t.expectEqual(@as(usize, 1), alone.hints);
}

test "copy-returned's judged advice names the parameter, and a warning that stays stands for the hint at its span" {
    const judged = copy_from_repair.judged(copy_from_repair.code, "every return of `f` copies a place of `row`, and no caller").?;
    try t.expectEqualStrings("row", judged.parameter);
    try t.expect(judged.form == .result);
    try t.expect(copy_from_repair.judged("W_COPY_MOVE", "every return of `f` copies a place of `row`") == null);
    var items: std.ArrayList(language.diagnostic.Diagnostic) = .empty;
    defer items.deinit(t.allocator);
    const hint = "every return of `f` copies a place of `row`: if every caller only reads the result";
    try items.append(t.allocator, .{ .code = "W_COPY_MOVE", .severity = .warning, .span = .{ .start = 4, .end = 9 }, .message = hint });
    try items.append(t.allocator, .{ .code = "W_COPY_MOVE", .severity = .warning, .span = .{ .start = 20, .end = 29 }, .message = hint });
    try items.append(t.allocator, .{ .code = copy_from_repair.code, .severity = .warning, .span = .{ .start = 4, .end = 9 }, .message = "m" });
    copy_from_repair.dropHintsBeside(&items);
    try t.expectEqual(@as(usize, 2), items.items.len);
    try t.expectEqual(@as(u32, 20), items.items[0].span.start);
    try t.expectEqualStrings(copy_from_repair.code, items.items[1].code);
}
