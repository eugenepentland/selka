//! `W_COPY_FOR_STORE` (`copy_for_store.zig`): the warning and its repair where every caller in a project check passes a
//! new value, and silence for each rule that withholds it.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const copy_for_store = @import("copy_for_store.zig");
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

/// A test file of the module; `test/fix_cli_test.zig` has one that calls the private function itself.
const rows_test =
    \\import rows
    \\
    \\
    \\public func test_pair() -> bool:
    \\    return len(rows.pair()) > 0
    \\
;

/// One warning that survives the caller judge, as `check` prints it, and its edits as written into the source.
const Found = struct { message: []const u8, edits: []const []const u8 };

/// Check `rows` (with the test file) from `entry` and give the `W_COPY_FOR_STORE` warnings whose callers in the program
/// accept the repair (`copy_for_store.callersAccept`, the argument half of the judge a check without stood-in bodies runs;
/// `src/core/single_owner_test.zig` adds the ownership half), with the callers' `own ` marks. Each edit is
/// written `offset:old->new` against the module text, an insertion with an empty `old`.
fn warnings(arena: std.mem.Allocator, entry: []const u8, rows: []const u8) ![]const Found {
    return warningsOf(arena, try checked(arena, entry, rows, false), rows);
}

/// `warnings` of an already checked project.
fn warningsOf(arena: std.mem.Allocator, compilation: language.project_compile.Compilation, rows: []const u8) ![]const Found {
    const program = compilation.program.?;
    const start = std.mem.indexOf(u8, compilation.src.bytes, rows).?;
    var found: std.ArrayList(Found) = .empty;
    for (compilation.diagnostics.items.items) |item| {
        const judged = copy_for_store.judged(item.code, item.message) orelse continue;
        // The message opens with the function's name in backquotes.
        const name = item.message[1 .. std.mem.indexOfScalarPos(u8, item.message, 1, '`') orelse return error.TestUnexpectedResult];
        const callee = try functionNamed(arena, program, name);
        const position = for (program.functions[callee].scope.locals, 0..) |local, slot| {
            if (std.mem.eql(u8, local.name, judged.parameter)) break slot;
        } else return error.TestUnexpectedResult;
        const marks = try copy_for_store.callersAccept(arena, program, callee, position) orelse continue;
        const fix = try copy_for_store.withMarks(arena, item.provenance.fix.?, marks);
        const edits = try arena.alloc([]const u8, fix.count());
        for (edits, 0..) |*slot, at| {
            const edit = fix.at(at);
            slot.* = try std.fmt.allocPrint(arena, "{d}:{s}->{s}", .{ edit.span.start - start, compilation.src.text(edit.span), edit.text });
        }
        try found.append(arena, .{ .message = item.message, .edits = edits });
    }
    return found.items;
}

/// The position of the ordinary function `name` (of any module) in a checked program.
fn functionNamed(arena: std.mem.Allocator, program: language.typed.Program, name: []const u8) !usize {
    const qualified = try std.fmt.allocPrint(arena, "::{s}", .{name});
    for (program.functions, 0..) |function, position| {
        if (std.mem.endsWith(u8, function.name, qualified) and function.type_arguments.len == 0) return position;
    }
    return error.TestUnexpectedResult;
}

/// The checked project of `rows` and its test file, from `entry`.
fn checked(arena: std.mem.Allocator, entry: []const u8, rows: []const u8, repairs_public: bool) !language.project_compile.Compilation {
    var tree: Tree = .{ .files = &.{
        .{ .path = "selka_check_all.selka", .text = check_all },
        .{ .path = "main.selka", .text = "import rows\n\n\nfunc main() -> int:\n    return 0\n" },
        .{ .path = "rows.selka", .text = rows },
        .{ .path = "rows_test.selka", .text = rows_test },
    } };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &tree, .read = Tree.read }, entry, .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.repairs_public = repairs_public;
    try compilation.check();
    return compilation;
}

/// How many `W_COPY_FOR_STORE` warnings a project check of `rows` keeps.
fn count(rows: []const u8) !usize {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    return (try warnings(arena.allocator(), "selka_check_all", rows)).len;
}

const record_row =
    \\public record Row:
    \\    name: str
    \\    size: int
    \\
    \\
;

test "copy-for-store warns with the own repair when every caller passes a literal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1)]
        \\
    ;
    const found = try warnings(arena.allocator(), "selka_check_all", rows);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`make_row` copies parameter `name` into storage it keeps, and no caller needs the value after the call: " ++
        "declare it `own name` and the function keeps that value rather than a copy", found[0].message);
    const signature = std.mem.indexOf(u8, rows, "name: str, size").?;
    const body = std.mem.indexOf(u8, rows, "copy(name)").?;
    try t.expectEqual(@as(usize, 2), found[0].edits.len);
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:->own ", .{signature}), found[0].edits[0]);
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:copy(name)->own name", .{body}), found[0].edits[1]);
}

test "copy-for-store warns when a caller passes a call's result, staged beside another call, or a concatenation" {
    const rows = record_row ++
        \\func label(text: str) -> str:
        \\    return f"<{text}>"
        \\
        \\
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row(label("beta"), len(label("x"))), make_row("a" + "b", 3)]
        \\
    ;
    try t.expectEqual(@as(usize, 1), try count(rows));
}

test "copy-for-store takes a list literal as a new value, and moves the last of two copies of a parameter in one record" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\public record Pair:
        \\    id: str
        \\    title: str
        \\    tags: str[]
        \\
        \\
        \\func make_pair(id: str, tags: str[]) -> Pair:
        \\    return Pair(id=copy(id), title=copy(id), tags=copy(tags))
        \\
        \\
        \\public func pair() -> Row[]:
        \\    const made = make_pair("a", ["x", "y"])
        \\    const size = len(made.tags)
        \\    return [Row(name=own made.title, size=size)]
        \\
    ;
    const found = try warnings(arena.allocator(), "selka_check_all", rows);
    // The needless-copy pass moves the last of two copies of `id` in one record (COPY-A1c); the earlier stays a copy.
    try t.expectEqual(@as(usize, 2), found.len);
    const title = std.mem.indexOf(u8, rows, "copy(id), tags").?;
    try t.expectEqual(@as(usize, 2), found[0].edits.len);
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:copy(id)->own id", .{title}), found[0].edits[1]);
    const tags = std.mem.indexOf(u8, rows, "copy(tags)").?;
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:copy(tags)->own tags", .{tags}), found[1].edits[1]);
}

test "copy-for-store marks a caller's owned local or own parameter it passes by name, in the caller's own file" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\func handed(own label: str) -> Row:
        \\    return make_row(label, 2)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    const text = f"a{1}"
        \\    return [make_row(text, 1), handed("b")]
        \\
    ;
    const found = try warnings(arena.allocator(), "selka_check_all", rows);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`make_row` copies parameter `name` into storage it keeps, and no caller needs the value after the call: " ++
        "declare it `own name` and the function keeps that value rather than a copy", found[0].message);
    try t.expectEqual(@as(usize, 4), found[0].edits.len);
    const label = std.mem.indexOf(u8, rows, "label, 2").?;
    const text = std.mem.indexOf(u8, rows, "text, 1").?;
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:->own ", .{label}), found[0].edits[2]);
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:->own ", .{text}), found[0].edits[3]);
}

test "copy-for-store marks the name a caller in another module passes, and a caller in the test file" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("a", 1)]
        \\
    ;
    const tests =
        \\import rows
        \\
        \\
        \\public func test_pair() -> bool:
        \\    const word = "w" + "x"
        \\    return rows.make_row(word, 1).size == 1
        \\
    ;
    var tree: Tree = .{ .files = &.{
        .{ .path = "selka_check_all.selka", .text = check_all },
        .{ .path = "rows.selka", .text = rows },
        .{ .path = "rows_test.selka", .text = tests },
    } };
    var project = language.project.Project.init(arena.allocator());
    try project.load(.{ .context = &tree, .read = Tree.read }, "selka_check_all", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    const program = compilation.program.?;
    const callee = try functionNamed(arena.allocator(), program, "make_row");
    const marks = (try copy_for_store.callersAccept(arena.allocator(), program, callee, 0)).?;
    try t.expectEqual(@as(usize, 1), marks.len);
    const word = std.mem.indexOf(u8, compilation.src.bytes, "word, 1").?;
    try t.expectEqual(@as(u32, @intCast(word)), marks[0]);
    const caller = try functionNamed(arena.allocator(), program, "test_pair");
    try t.expectEqualSlices(u32, marks, (try copy_for_store.callerMarks(arena.allocator(), program, program.functions[caller], callee, 0)).?);
    const fix = try copy_for_store.withMarks(arena.allocator(), .{ .edit = .{ .span = .{ .start = 0, .end = 0 }, .text = "own " } }, &.{ marks[0], marks[0] });
    try t.expectEqual(@as(usize, 2), fix.count());
    try t.expectEqualStrings("word", compilation.src.text(.{ .start = fix.at(1).span.start, .end = fix.at(1).span.start + 4 }));
}

test "copy-for-store is withheld for a caller that passes a place, a loop element, a pattern binding or a plain parameter" {
    const declaration = record_row ++
        \\enum Pick:
        \\    named(text: str)
        \\    blank
        \\
        \\
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return built("g")
        \\
        \\
        \\func built(given: str) -> Row[]:
        \\
    ;
    try t.expectEqual(@as(usize, 0), try count(declaration ++
        \\    const first = make_row("a", 1)
        \\    return [make_row(first.name, 2)]
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(declaration ++
        \\    mut made: Row[] = []
        \\    for name in ["a", "b"]:
        \\        append(mut made, make_row(name, 1))
        \\    return made
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(declaration ++
        \\    const picked = Pick.named(text=given + "!")
        \\    match picked:
        \\        case named(text):
        \\            return [make_row(text, 1)]
        \\        case blank:
        \\            return []
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(declaration ++
        \\    return [make_row(given, 1)]
        \\
    ));
}

/// A `public` `make_row` whose callers are the module's own `pair` and a test file's `test_pair` (which passes a name at its last use).
const public_rows = record_row ++
    \\public func make_row(name: str, size: int) -> Row:
    \\    return Row(name=copy(name), size=size)
    \\
    \\
    \\public func pair() -> Row[]:
    \\    return [make_row("alpha", 1)]
    \\
;
const public_callers =
    \\import rows
    \\
    \\
    \\public func test_pair() -> bool:
    \\    const word = "w" + "x"
    \\    return rows.make_row(word, 1).size == 1
    \\
;

/// The project check of `public_rows` and its test file, with `repairs_public` as the command layer sets it.
fn publicProject(arena: std.mem.Allocator, repairs_public: bool, entry: []const u8) !language.project_compile.Compilation {
    var tree: Tree = .{ .files = &.{
        .{ .path = "selka_check_all.selka", .text = check_all },
        .{ .path = "main.selka", .text = "import rows\n\n\nfunc main() -> int:\n    return 0\n" },
        .{ .path = "rows.selka", .text = public_rows },
        .{ .path = "rows_test.selka", .text = public_callers },
    } };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &tree, .read = Tree.read }, entry, .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.repairs_public = repairs_public;
    try compilation.check();
    return compilation;
}

test "copy-for-store repairs a public function of a project that is no package, and says its signature changes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const compilation = try publicProject(arena.allocator(), true, "selka_check_all");
    const found = try warningsOf(arena.allocator(), compilation, public_rows);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`make_row` copies parameter `name` into storage it keeps, and no caller needs the value after the call: " ++
        "declare it `own name` and the function keeps that value rather than a copy; `make_row` is public, so its signature changes", found[0].message);
    // The repair's two edits, and the caller in the test file marked beside them.
    try t.expectEqual(@as(usize, 3), found[0].edits.len);
    const word = std.mem.indexOf(u8, compilation.src.bytes, "word, 1").?;
    try t.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{d}:->own ", .{word - std.mem.indexOf(u8, compilation.src.bytes, public_rows).?}), found[0].edits[2]);
}

test "copy-for-store keeps a public function when the project is a package, has interface files or is checked one entry at a time" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // `repairs_public` stays false for `interface_files` and for modules a package root could hold (`main.zig`'s `repairsPublic`).
    try t.expectEqual(@as(usize, 0), (try warningsOf(arena.allocator(), try publicProject(arena.allocator(), false, "selka_check_all"), public_rows)).len);
    // A check of one entry does not hold every caller, whatever the command layer says.
    try t.expectEqual(@as(usize, 0), (try warningsOf(arena.allocator(), try publicProject(arena.allocator(), true, "main"), public_rows)).len);
}

test "copy-for-store is withheld for a public, generic, recursive or function-value function" {
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\public func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1)]
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func make_row[T](name: str, size: int, tag: T) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1, 2)]
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    if size > 5:
        \\        return make_row("deep", size - 1)
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1)]
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    const build = make_row
        \\    return [make_row("alpha", 1), build("beta", 2)]
        \\
    ));
}

test "copy-for-store reads a parameter on a line of its own, and one after a type with commas and before a default" {
    try t.expectEqual(@as(usize, 1), try count(record_row ++
        \\func make_row(
        \\    size: int,
        \\    name: str
        \\) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row(1, "alpha")]
        \\
    ));
    try t.expectEqual(@as(usize, 1), try count(record_row ++
        \\func make_row(sizes: dict[str, int], name: str, size: int = 2) -> Row:
        \\    return Row(name=copy(name), size=size + len(sizes))
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row({"a": 1}, "alpha")]
        \\
    ));
}

test "copy-for-store is withheld for a default value, a from clause and a type with no storage" {
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func make_row(size: int, name: str = "z") -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row(1, "alpha")]
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func stash(row: Row, mut kept: Row[]) -> str from row:
        \\    append(mut kept, copy(row))
        \\    return row.name
        \\
        \\
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name="n", size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    mut made: Row[] = []
        \\    const name = stash(make_row("a", 1), mut made)
        \\    append(mut made, Row(name=copy(name), size=2))
        \\    return made
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\public record Point:
        \\    x: int
        \\
        \\
        \\public record Held:
        \\    at: Point
        \\    name: str
        \\
        \\
        \\func make_row(point: Point, size: int) -> Held:
        \\    return Held(at=copy(point), name="p")
        \\
        \\
        \\public func pair() -> Held[]:
        \\    return [make_row(Point(x=1), 1)]
        \\
    ));
}

test "copy-for-store is withheld for a parameter read after its stored copy and a copy stored in a loop" {
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    const row = Row(name=copy(name), size=size)
        \\    if name == "x":
        \\        return Row(name="y", size=size)
        \\    return row
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1)]
        \\
    ));
    try t.expectEqual(@as(usize, 0), try count(record_row ++
        \\func make_rows(name: str, size: int) -> Row[]:
        \\    mut rows: Row[] = []
        \\    for at in range(0, size):
        \\        append(mut rows, Row(name=copy(name), size=at))
        \\    return rows
        \\
        \\
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name="n", size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return make_rows("alpha", 2)
        \\
    ));
}

test "copy-for-store is silent in a check of one entry, which does not hold every caller" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1)]
        \\
    ;
    try t.expectEqual(@as(usize, 1), (try warnings(arena.allocator(), "selka_check_all", rows)).len);
    try t.expectEqual(@as(usize, 0), (try warnings(arena.allocator(), "main", rows)).len);
}

test "copy-for-store's judged advice names the parameter, and no other code" {
    const judged = copy_for_store.judged(copy_for_store.code, "`f` copies parameter `name` into storage it keeps").?;
    try t.expectEqualStrings("name", judged.parameter);
    try t.expect(copy_for_store.judged("W_COPY_MOVE", "`f` copies parameter `name` into storage") == null);
}

test "provedWithOwn gives the move of a stored copy, and leaves a read-only copy to the warning it already has" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func shout(text: str) -> int:
        \\    return len(text)
        \\
        \\
        \\func make_row(name: str, size: int) -> Row:
        \\    const n = shout(copy(name))
        \\    return Row(name=copy(name), size=size + n)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    return [make_row("alpha", 1)]
        \\
    ;
    const compilation = try checked(arena.allocator(), "selka_check_all", rows, false);
    const program = compilation.program.?;
    const edits = try needless_copy.provedWithOwn(arena.allocator(), program, compilation.src, try functionNamed(arena.allocator(), program, "make_row"), 0);
    try t.expectEqual(@as(usize, 1), edits.len);
    try t.expectEqualStrings("own name", edits[0].text);
    try t.expectEqualStrings("copy(name)", compilation.src.text(edits[0].span));
    try t.expect(edits[0].span.start > std.mem.indexOf(u8, compilation.src.bytes, "Row(name=copy").?);
}

test "acceptedByCallers judges several targets in one walk: a name is marked, a place or a function value withholds" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = record_row ++
        \\func make_row(name: str, size: int) -> Row:
        \\    return Row(name=copy(name), size=size)
        \\
        \\
        \\func tag_row(tag: str, size: int) -> Row:
        \\    return Row(name=copy(tag), size=size)
        \\
        \\
        \\func size_row(text: str, size: int) -> Row:
        \\    return Row(name=copy(text), size=size)
        \\
        \\
        \\public func pair() -> Row[]:
        \\    const tag = f"t{1}"
        \\    const first = make_row("alpha", 1)
        \\    const sized = size_row
        \\    return [first, tag_row(tag, 2), make_row(first.name, 4), sized("s", 3)]
        \\
    ;
    const compilation = try checked(arena.allocator(), "selka_check_all", rows, false);
    const program = compilation.program.?;
    const targets = [_]copy_for_store.Target{
        .{ .callee = try functionNamed(arena.allocator(), program, "make_row"), .position = 0 },
        .{ .callee = try functionNamed(arena.allocator(), program, "tag_row"), .position = 0 },
        .{ .callee = try functionNamed(arena.allocator(), program, "size_row"), .position = 0 },
    };
    const accepted = try copy_for_store.acceptedByCallers(arena.allocator(), program, &targets);
    try t.expectEqual(@as(usize, 3), accepted.len);
    try t.expectEqual(@as(?[]const u32, null), accepted[0]);
    const tag = std.mem.indexOf(u8, compilation.src.bytes, "tag, 2").?;
    try t.expectEqualSlices(u32, &.{@intCast(tag)}, accepted[1].?);
    try t.expectEqual(@as(?[]const u32, null), accepted[2]);
    try t.expectEqual(@as(?[]const u32, null), try copy_for_store.callersAccept(arena.allocator(), program, targets[0].callee, 0));
}

test "a stored W_COPY_FOR_STORE answer keeps its callers' own marks through the summary codec" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const summary = @import("semantic_summary.zig");
    const keeps = [_]summary.Keep{
        .{ .callee = "fn\x1frows\x1f\x1fmake_row", .parameter = "own name", .result = false, .keeps = false, .marks = &.{ 12, 300 } },
        .{ .callee = "fn\x1frows\x1f\x1ftag_row", .parameter = "own tag", .result = false, .keeps = true },
    };
    const row: summary.Summary = .{ .key = "fn\x1frows\x1f\x1fpair", .context = @splat(1), .region = .{ .len = 3, .digest = @splat(2) }, .fact = .{}, .stubbable = true, .notes = .{ .complete = true, .keeps = &keeps } };
    const payload = try summary.encode(arena.allocator(), .{ .summaries = &.{row} });
    const decoded = summary.decode(arena.allocator(), payload).?;
    const stored = decoded.keepsAt(0);
    try t.expectEqual(@as(usize, 2), stored.len);
    try t.expectEqualSlices(u32, &.{ 12, 300 }, stored[0].marks);
    try t.expect(!stored[0].keeps and stored[1].keeps);
    try t.expectEqual(@as(usize, 0), stored[1].marks.len);
    try t.expectEqualStrings("check-summaries-v29", summary.format_version);
}
