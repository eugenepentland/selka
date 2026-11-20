//! The `W_COPY_MOVE` loop hint as repairs (`copy_loop_repair.zig`, `needless_copy.zig` `loopRepair`): inside one function a
//! `W_NEEDLESS_COPY` repair over a list a call returns or an owned local, and for a plain list parameter a `W_COPY_FOR_STORE`
//! warning with its callers' `own ` marks; each with its exact edits, and the hint kept for each condition that withholds it.
//! `test/fix_cli_test.zig` runs the parameter form cold and cached, with a caller in another file.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const copy_for_store = @import("copy_for_store.zig");
const copy_loop_repair = @import("copy_loop_repair.zig");
const diagnostic = @import("diagnostic.zig");
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

/// One diagnostic of `rows.selka`: its code, message, and edits written `offset:old->new` against the module text (an
/// insertion has an empty `old`), with the `own ` marks the callers in the program accept for a `W_COPY_FOR_STORE` warning.
const Found = struct { code: []const u8, message: []const u8, edits: []const []const u8 };

/// Check `rows` (with a test file that calls `rows.total`) from `entry` and give its loop diagnostics: the loop hints, the
/// loop repairs, and the `W_COPY_FOR_STORE` warnings whose callers accept the repair (`copy_for_store.callersAccept`).
fn found(arena: std.mem.Allocator, entry: []const u8, rows: []const u8) ![]const Found {
    return foundIn(arena, entry, rows, false);
}

/// `found`, with `repairs_public` as the command layer sets it: true for a project that is no package.
fn foundIn(arena: std.mem.Allocator, entry: []const u8, rows: []const u8, repairs_public: bool) ![]const Found {
    var tree: Tree = .{ .files = &.{
        .{ .path = "selka_check_all.selka", .text = check_all },
        .{ .path = "main.selka", .text = "import rows\n\n\nfunc main() -> int:\n    return rows.total()\n" },
        .{ .path = "rows.selka", .text = rows },
        .{ .path = "rows_test.selka", .text = "import rows\n\n\npublic func test_total() -> bool:\n    return rows.total() > 0\n" },
    } };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &tree, .read = Tree.read }, entry, .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.repairs_public = repairs_public;
    try compilation.check();
    const program = compilation.program.?;
    const start = std.mem.indexOf(u8, compilation.src.bytes, rows).?;
    var list: std.ArrayList(Found) = .empty;
    for (compilation.diagnostics.items.items) |item| {
        if (item.severity == .err) return error.TestUnexpectedResult;
        const hint = needless_copy.judgedByCallers(item.code, item.message) != null and std.mem.indexOf(u8, item.message, "each element") != null;
        const loop = std.mem.eql(u8, item.code, needless_copy.code) and std.mem.indexOf(u8, item.message, "owned element") != null;
        const store = copy_for_store.judged(item.code, item.message);
        const wanted = hint or loop or store != null;
        if (!wanted) continue;
        var fix = item.provenance.fix orelse diagnostic.Fix{ .edit = .{ .span = item.span, .text = "" } };
        if (store) |judged| {
            const name = item.message[1 .. std.mem.indexOfScalarPos(u8, item.message, 1, '`') orelse return error.TestUnexpectedResult];
            const callee = try functionNamed(arena, program, name);
            const position = for (program.functions[callee].scope.locals, 0..) |local, slot| {
                if (std.mem.eql(u8, local.name, judged.parameter)) break slot;
            } else return error.TestUnexpectedResult;
            const marks = try copy_for_store.callersAccept(arena, program, callee, position) orelse continue;
            fix = try copy_for_store.withMarks(arena, fix, marks);
        }
        const edits = try arena.alloc([]const u8, if (item.provenance.fix == null) 0 else fix.count());
        for (edits, 0..) |*slot, at| {
            const edit = fix.at(at);
            slot.* = try std.fmt.allocPrint(arena, "{d}:{s}->{s}", .{ edit.span.start - start, compilation.src.text(edit.span), edit.text });
        }
        try list.append(arena, .{ .code = item.code, .message = item.message, .edits = edits });
    }
    return list.items;
}

/// The diagnostics of `list` with code `code`, in order.
fn coded(arena: std.mem.Allocator, list: []const Found, code: []const u8) ![]const Found {
    var kept: std.ArrayList(Found) = .empty;
    for (list) |item| if (std.mem.eql(u8, item.code, code)) try kept.append(arena, item);
    return kept.items;
}

/// The position of the ordinary function `name` (of any module) in a checked program.
fn functionNamed(arena: std.mem.Allocator, program: language.typed.Program, name: []const u8) !usize {
    const qualified = try std.fmt.allocPrint(arena, "::{s}", .{name});
    for (program.functions, 0..) |function, position| {
        if (std.mem.endsWith(u8, function.name, qualified) and function.type_arguments.len == 0) return position;
    }
    return error.TestUnexpectedResult;
}

/// An insertion of `text` at the `nth` (from 0) occurrence of `at` in `rows`, as `found` writes it.
fn insertion(arena: std.mem.Allocator, rows: []const u8, at: []const u8, nth: usize, text: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{d}:->{s}", .{ try nthIndex(rows, at, nth), text });
}

/// A replacement of the `nth` (from 0) occurrence of `old` in `rows` by `new`, as `found` writes it.
fn replacement(arena: std.mem.Allocator, rows: []const u8, old: []const u8, nth: usize, new: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{d}:{s}->{s}", .{ try nthIndex(rows, old, nth), old, new });
}

/// The offset of the `nth` (from 0) occurrence of `needle` in `text`.
fn nthIndex(text: []const u8, needle: []const u8, nth: usize) !usize {
    var from: usize = 0;
    var left = nth;
    while (std.mem.indexOfPos(u8, text, from, needle)) |at| {
        if (left == 0) return at;
        left -= 1;
        from = at + 1;
    }
    return error.TestUnexpectedResult;
}

const record_row =
    \\public record Row:
    \\    name: str
    \\    tags: str[]
    \\
    \\
    \\public func made() -> Row[]:
    \\    return [Row(name="a", tags=["x"]), Row(name="b", tags=[])]
    \\
    \\
;

test "a loop over the list a call returns, an owned local or a fresh payload repairs a copied field: `for r in own xs:`, `own r.name`" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\func fresh_names() -> str[]:
        \\    mut out: str[] = []
        \\    for r in made():
        \\        append(mut out, copy(r.name))
        \\    return out
        \\
        \\
        \\func local_names() -> str[]:
        \\    const rows = made()
        \\    mut out: str[] = []
        \\    for r in rows:
        \\        append(mut out, copy(r.name))
        \\    return out
        \\
        \\
        \\func maybe() -> Row[]?:
        \\    return Some(made())
        \\
        \\
        \\func bound_names() -> str[]:
        \\    mut out: str[] = []
        \\    if maybe() is Some(rows):
        \\        for r in rows:
        \\            append(mut out, copy(r.name))
        \\    return out
        \\
        \\
        \\public func total() -> int:
        \\    return len(fresh_names()) + len(local_names()) + len(bound_names())
        \\
    ;
    // A check of one entry gives the repairs too: they are inside one function.
    const list = try found(a, "main", rows);
    try t.expectEqual(@as(usize, 3), list.len);
    try t.expectEqualStrings("W_NEEDLESS_COPY", list[0].code);
    try t.expectEqualStrings("the list `made()` returns is named by nothing else, so `for r in own made()` makes `r` an owned element " ++
        "and the copy becomes a move", list[0].message);
    try t.expectEqual(@as(usize, 2), list[0].edits.len);
    try t.expectEqualStrings(try insertion(a, rows, "made():\n        append", 0, "own "), list[0].edits[0]);
    try t.expectEqualStrings(try replacement(a, rows, "copy(r.name)", 0, "own r.name"), list[0].edits[1]);
    try t.expectEqualStrings("`rows` is not used after the loop, so `for r in own rows` makes `r` an owned element and the copy becomes a move", list[1].message);
    try t.expectEqualStrings(try insertion(a, rows, "rows:\n        append", 0, "own "), list[1].edits[0]);
    try t.expectEqualStrings(try replacement(a, rows, "copy(r.name)", 1, "own r.name"), list[1].edits[1]);
    // A payload a match takes from a fresh value is owned too (`if ... is Some(rows):`, `const rows = ... else:`).
    try t.expectEqualStrings(try insertion(a, rows, "rows:\n            append", 0, "own "), list[2].edits[0]);
    try t.expectEqualStrings(try replacement(a, rows, "copy(r.name)", 2, "own r.name"), list[2].edits[1]);
}

test "a plain list parameter is declared own, its loop takes the elements, and a caller's last use of a name is marked" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\func names_of(rows: Row[]) -> str[]:
        \\    mut out: str[] = []
        \\    for r in rows:
        \\        append(mut out, copy(r.name))
        \\    return out
        \\
        \\
        \\func all_of(words: str[]) -> str[]:
        \\    mut out: str[] = ["start"]
        \\    for w in words:
        \\        append(mut out, copy(w))
        \\    return out
        \\
        \\
        \\public func total() -> int:
        \\    const words = ["p", "q"]
        \\    return len(names_of(made())) + len(all_of(words))
        \\
    ;
    const all = try found(a, "selka_check_all", rows);
    // The hints stay beside the warnings until the callers are judged (`dropHintsBeside`).
    try t.expectEqual(@as(usize, 4), all.len);
    try t.expectEqual(@as(usize, 2), (try coded(a, all, "W_COPY_MOVE")).len);
    const list = try coded(a, all, "W_COPY_FOR_STORE");
    try t.expectEqualStrings("`names_of` copies each element of parameter `rows` into storage it keeps, and no caller needs the list " ++
        "after the call: declare it `own rows` and loop over `own rows`, and the function keeps the elements rather than copies", list[0].message);
    try t.expectEqual(@as(usize, 3), list[0].edits.len);
    try t.expectEqualStrings(try insertion(a, rows, "rows: Row[]", 0, "own "), list[0].edits[0]);
    try t.expectEqualStrings(try insertion(a, rows, "rows:\n        append", 0, "own "), list[0].edits[1]);
    try t.expectEqualStrings(try replacement(a, rows, "copy(r.name)", 0, "own r.name"), list[0].edits[2]);
    try t.expectEqual(@as(usize, 4), list[1].edits.len);
    try t.expectEqualStrings(try insertion(a, rows, "words: str[]", 0, "own "), list[1].edits[0]);
    try t.expectEqualStrings(try insertion(a, rows, "words:\n        append", 0, "own "), list[1].edits[1]);
    try t.expectEqualStrings(try replacement(a, rows, "copy(w)", 0, "own w"), list[1].edits[2]);
    try t.expectEqualStrings(try insertion(a, rows, "words))", 0, "own "), list[1].edits[3]);
}

test "the parameter form is withheld for a check of one entry, a public function and a caller that passes a place" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\func all_of(words: str[]) -> str[]:
        \\    mut out: str[] = []
        \\    for w in words:
        \\        append(mut out, copy(w))
        \\    return out
        \\
        \\
        \\public func shown(words: str[]) -> str[]:
        \\    mut out: str[] = []
        \\    for w in words:
        \\        append(mut out, copy(w))
        \\    return out
        \\
        \\
        \\public func total() -> int:
        \\    const row = Row(name="a", tags=["x"])
        \\    return len(all_of(row.tags)) + len(shown(["p"])) + len(row.name)
        \\
    ;
    for ([_][]const u8{ "main", "selka_check_all" }) |entry| {
        const list = try found(a, entry, rows);
        try t.expectEqual(@as(usize, 2), list.len);
        try t.expectEqualStrings("W_COPY_MOVE", list[0].code);
        try t.expectEqualStrings("W_COPY_MOVE", list[1].code);
    }
}

test "the parameter form repairs a public function of a project that is no package, and says its signature changes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\public func shown(words: str[]) -> str[]:
        \\    mut out: str[] = []
        \\    for w in words:
        \\        append(mut out, copy(w))
        \\    return out
        \\
        \\
        \\public func total() -> int:
        \\    return len(shown(["p"]))
        \\
    ;
    // A package, or a project with interface files: the hint alone, as before.
    const kept = try foundIn(a, "selka_check_all", rows, false);
    try t.expectEqual(@as(usize, 1), kept.len);
    try t.expectEqualStrings("W_COPY_MOVE", kept[0].code);
    const list = try coded(a, try foundIn(a, "selka_check_all", rows, true), "W_COPY_FOR_STORE");
    try t.expectEqual(@as(usize, 1), list.len);
    try t.expectEqualStrings("`shown` copies each element of parameter `words` into storage it keeps, and no caller needs the list " ++
        "after the call: declare it `own words` and loop over `own words`, and the function keeps the elements rather than copies; " ++
        "`shown` is public, so its signature changes", list[0].message);
    try t.expectEqual(@as(usize, 3), list[0].edits.len);
    try t.expectEqualStrings(try insertion(a, rows, "words: str[]", 0, "own "), list[0].edits[0]);
    try t.expectEqualStrings(try insertion(a, rows, "words:\n        append", 0, "own "), list[0].edits[1]);
    try t.expectEqualStrings(try replacement(a, rows, "copy(w)", 0, "own w"), list[0].edits[2]);
}

test "the loop repairs are withheld for a list read after the loop, an element read after its copy, a loop that runs them twice, another copy of the element" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = record_row ++
        \\func again(words: str[]) -> str[]:
        \\    mut out: str[] = []
        \\    for w in words:
        \\        append(mut out, copy(w))
        \\    append(mut out, copy(words[0]))
        \\    return out
        \\
        \\
        \\func read_after() -> str[]:
        \\    mut out: str[] = []
        \\    for r in made():
        \\        append(mut out, copy(r.name))
        \\        append(mut out, copy(r.tags[0]))
        \\    return out
        \\
        \\
        \\func twice(rows: Row[]) -> str[]:
        \\    mut out: str[] = []
        \\    for round in [1, 2]:
        \\        for r in rows:
        \\            append(mut out, copy(r.name))
        \\    return out
        \\
        \\
        \\func inner(rows: Row[]) -> str[]:
        \\    mut out: str[] = []
        \\    for row in rows:
        \\        mut names: Row[] = []
        \\        append(mut names, copy(row))
        \\        for tag in row.tags:
        \\            for named in names:
        \\                append(mut out, copy(named.name))
        \\    return out
        \\
        \\
        \\func both() -> Row[]:
        \\    mut out: Row[] = []
        \\    for r in made():
        \\        append(mut out, Row(name=copy(r.name), tags=copy(r.tags)))
        \\    return out
        \\
        \\
        \\public func total() -> int:
        \\    return len(again(["a"])) + len(read_after()) + len(twice(made())) + len(inner(made())) + len(both())
        \\
    ;
    const list = try found(a, "selka_check_all", rows);
    for (list) |item| try t.expect(!std.mem.eql(u8, item.code, "W_COPY_FOR_STORE") and item.edits.len == 0);
}

test "a W_COPY_FOR_STORE warning that stays leaves out the loop hint at the copy it repairs, and no other" {
    var items: std.ArrayList(diagnostic.Diagnostic) = .empty;
    defer items.deinit(t.allocator);
    const hint = "`w` is copied out of each element of `words`, which nothing reads after the loop; `for w in own words` hands the " ++
        "elements over when `words` is an owned local or an `own` parameter (each of its callers then gives its list with `own`)";
    const edits = [_]diagnostic.Edit{ .{ .span = .{ .start = 40, .end = 40 }, .text = "own " }, .{ .span = .{ .start = 50, .end = 57 }, .text = "own w" } };
    try items.appendSlice(t.allocator, &.{
        .{ .code = "W_COPY_MOVE", .severity = .warning, .span = .{ .start = 50, .end = 57 }, .message = hint },
        .{ .code = "W_COPY_MOVE", .severity = .warning, .span = .{ .start = 90, .end = 97 }, .message = hint },
        .{ .code = "W_COPY_FOR_STORE", .severity = .warning, .span = .{ .start = 50, .end = 57 }, .message = "`f` copies each element of parameter `words` into storage", .provenance = .{
            .fix = .{ .edit = .{ .span = .{ .start = 10, .end = 10 }, .text = "own " }, .more = &edits },
        } },
    });
    copy_loop_repair.dropHintsBeside(&items);
    try t.expectEqual(@as(usize, 2), items.items.len);
    try t.expectEqual(@as(u32, 90), items.items[0].span.start);
    try t.expectEqualStrings("W_COPY_FOR_STORE", items.items[1].code);
    // The caller judge reads the parameter of the element form as it reads a stored copy's.
    try t.expectEqualStrings("words", copy_for_store.judged("W_COPY_FOR_STORE", items.items[1].message).?.parameter);
}
