//! `selka lint --copies`: the count of `copy(...)` calls a program writes, by the lint finding that names each one.
//! Each case checks a real project from a temporary folder, runs the lint rules over it and counts the result; the
//! `cost --sites` rows the loop rule reads are handed over by hand, as the command line's own analysis would.
const std = @import("std");
const t = std.testing;
const copy_count = @import("copy_count.zig");
const interfaces = @import("interfaces.zig");
const language = @import("compiler.zig");
const project = @import("project.zig");
const project_compile = @import("project_compile.zig");
const project_files = @import("project_files.zig");

const lint = language.lint;

/// One copy of each category and one that nothing names. `needless` passes a copy to a function that only reads it;
/// `gather` copies each element of a list nothing reads after the loop (a move replaces it); `plan` stores a parameter;
/// `spread` copies a value it reads again in a loop (the loop rule reads the row the test hands over); `kept` copies a
/// parameter it then writes.
const one_of_each =
    \\record Plan:
    \\    head: int[]
    \\
    \\
    \\func show(name: str) -> int:
    \\    return len(name)
    \\
    \\
    \\func needless(name: str) -> int:
    \\    return show(copy(name))
    \\
    \\
    \\func gather(rows: str[]) -> str[]:
    \\    mut taken: str[] = []
    \\    for row in rows:
    \\        append(mut taken, copy(row))
    \\    return taken
    \\
    \\
    \\func plan(head: int[]) -> Plan:
    \\    return Plan(head=copy(head))
    \\
    \\
    \\func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
    \\
    \\func kept(xs: int[]) -> int:
    \\    mut ys = copy(xs)
    \\    append(mut ys, 1)
    \\    return len(ys)
    \\
    \\
    \\func main() -> int:
    \\    const made = plan([1])
    \\    return needless("a") + len(gather(["b"])) + len(made.head) + len(spread(2)) + kept([2])
    \\
;

/// The count of the project in `root` whose entry module is `module`, with the loop rule's rows as `sites`.
fn countProject(scratch: std.mem.Allocator, root: []const u8, module: []const u8, sites: []const lint.AllocationSite) !copy_count.Report {
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), module, .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = try std.fs.path.join(scratch, &.{ root, try std.fmt.allocPrint(scratch, "{s}.selka", .{module}) });
    const outcome = try lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = null,
        .entry_path = entry,
        .options = .{},
        .data = .{ .sites = sites },
    }, scratch);
    return copy_count.count(scratch, .{
        .program = compilation.program.?,
        .src = compilation.src,
        .entry_path = entry,
        .findings = outcome.findings,
    });
}

/// The `cost --sites` row of the first `copy(` that `needle` starts in `text`, one loop deep.
fn loopSite(text: []const u8, needle: []const u8, path: []const u8) lint.AllocationSite {
    const at = std.mem.indexOf(u8, text, needle).? + std.mem.indexOf(u8, needle, "copy(").?;
    const line = std.mem.count(u8, text[0..at], "\n") + 1;
    const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
    return .{ .function = "spread", .path = path, .line = @intCast(line), .column = @intCast(at - line_start + 1), .kind = .copy, .loop_depth = 1, .hint = "ignored" };
}

fn writeModule(temp: *std.testing.TmpDir, name: []const u8, bytes: []const u8) !void {
    const file = try std.fmt.allocPrint(t.allocator, "{s}.selka", .{name});
    defer t.allocator.free(file);
    try temp.dir.writeFile(t.io, .{ .sub_path = file, .data = bytes });
}

test "copy count names one copy of each category once and leaves the other copy named by nothing" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "main", one_of_each);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const site = loopSite(one_of_each, "append(mut out, copy(base))", "main.selka");
    const report = try countProject(arena.allocator(), root, "main", &.{site});
    try t.expectEqual(copy_count.Tally{ .needless = 1, .move = 1, .for_store = 1, .in_loop = 1, .unnamed = 1 }, report.tally);
    try t.expectEqual(@as(usize, 5), report.tally.total());
    try t.expectEqual(@as(usize, 1), report.files.len);
    try t.expect(std.mem.endsWith(u8, report.files[0].path, "main.selka"));
    try t.expectEqual(@as(usize, 5), report.files[0].copies);
    try t.expectEqual(std.mem.count(u8, one_of_each, "\n"), report.lines);
}

test "copy count takes a copy that two findings name in the first category only" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "main", one_of_each);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // A loop row on the parameter store: the store finding comes before the loop finding, so it stays a store.
    const site = loopSite(one_of_each, "return Plan(head=copy(head))", "main.selka");
    const report = try countProject(arena.allocator(), root, "main", &.{site});
    try t.expectEqual(@as(usize, 0), report.tally.in_loop);
    try t.expectEqual(@as(usize, 1), report.tally.for_store);
    try t.expectEqual(@as(usize, 5), report.tally.total());
}

/// A file named `_test.selka` with a copy in a loop: a test file is counted like any other.
const copy_loop_in_test_file =
    \\"""A test file with a copy in a loop."""
    \\
    \\
    \\func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
    \\
    \\public func test_spread() -> bool:
    \\    return len(spread(2)) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "copy count counts the copy a test file writes" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "spread_test", copy_loop_in_test_file);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const site = loopSite(copy_loop_in_test_file, "append(mut out, copy(base))", "spread_test.selka");
    const report = try countProject(arena.allocator(), root, "spread_test", &.{site});
    try t.expectEqual(copy_count.Tally{ .in_loop = 1 }, report.tally);
    try t.expectEqual(@as(usize, 1), report.files.len);
    try t.expect(std.mem.endsWith(u8, report.files[0].path, "spread_test.selka"));
}

/// A program whose one written copy sits beside a call into the standard library, which copies inside.
const uses_standard_library =
    \\import lists
    \\
    \\
    \\func main() -> int:
    \\    const names = lists.filled(2, "a")
    \\    mut mine = copy(names)
    \\    append(mut mine, "b")
    \\    return len(mine)
    \\
;

test "copy count leaves the standard library's own copies out of the count and the files" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "main", uses_standard_library);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try countProject(arena.allocator(), root, "main", &.{});
    try t.expectEqual(@as(usize, 1), report.tally.total());
    try t.expectEqual(@as(usize, 1), report.files.len);
    try t.expect(!std.mem.startsWith(u8, report.files[0].path, "@stdlib/"));
}

/// A copy `selka fix` would remove, under a waiver comment: the finding goes and the copy stays.
const waived_needless =
    \\func show(name: str) -> int:
    \\    return len(name)
    \\
    \\
    \\func needless(name: str) -> int:
    \\    # lint: allow needless-copy reason="the copy is what this function shows"
    \\    return show(copy(name))
    \\
    \\
    \\func main() -> int:
    \\    return needless("a")
    \\
;

test "copy count counts a waived copy as named by nothing" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "main", waived_needless);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try countProject(arena.allocator(), root, "main", &.{});
    try t.expectEqual(copy_count.Tally{ .unnamed = 1 }, report.tally);
}

test "copy count renders the text and the one-line JSON from a report" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const files = [_]copy_count.FileCount{
        .{ .path = "src/a.selka", .copies = 3, .lines = 1000 },
        .{ .path = "src/b \"q\".selka", .copies = 0, .lines = 24 },
    };
    const report: copy_count.Report = .{
        .tally = .{ .needless = 1, .move = 2, .for_store = 3, .in_loop = 4, .unnamed = 5 },
        .lines = 1024,
        .files = &files,
    };
    const text = try copy_count.renderText(arena.allocator(), report);
    try t.expectEqualStrings(
        \\copies: 15 in 1024 lines, 14.6 per 1000 lines
        \\     1 selka fix removes them (L_NEEDLESS_COPY)
        \\     2 a move replaces them (L_COPY_MOVE)
        \\     3 stored from a parameter (L_COPY_FOR_STORE)
        \\     4 in a loop (L_COPY_IN_LOOP)
        \\     5 named by nothing
        \\
    , text);
    const json = try copy_count.renderJson(arena.allocator(), report);
    try t.expectEqualStrings(
        \\{"schema":"copy-count-v1","entries":1,"copies":15,"lines":1024,"per_1000":14.6,"needless":1,"move":2,"for_store":3,"in_loop":4,"unnamed":5,"files":[{"path":"src/a.selka","copies":3,"lines":1000},{"path":"src/b \"q\".selka","copies":0,"lines":24}]}
        \\
    , json);
}

test "copy count says the split is not known, and keeps what is known, when the loop rule's analysis failed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const files = [_]copy_count.FileCount{.{ .path = "a.selka", .copies = 3, .lines = 18 }};
    const report: copy_count.Report = .{ .tally = .{ .needless = 1, .unnamed = 2 }, .lines = 18, .files = &files, .split_known = false };
    try t.expectEqualStrings(
        \\copies: 3 in 18 lines, 166.7 per 1000 lines
        \\     1 selka fix removes them (L_NEEDLESS_COPY)
        \\     0 a move replaces them (L_COPY_MOVE)
        \\     0 stored from a parameter (L_COPY_FOR_STORE)
        \\     ? in a loop (L_COPY_IN_LOOP): not known, the analysis failed
        \\     ? named by nothing: not known, the analysis failed (the two lines share 2 copies)
        \\
    , try copy_count.renderText(arena.allocator(), report));
    try t.expectEqualStrings(
        \\{"schema":"copy-count-v1","entries":1,"copies":3,"lines":18,"per_1000":166.7,"needless":1,"move":0,"for_store":0,"in_loop":null,"unnamed":null,"split_known":false,"in_loop_or_unnamed":2,"files":[{"path":"a.selka","copies":3,"lines":18}]}
        \\
    , try copy_count.renderJson(arena.allocator(), report));
    const single: copy_count.Report = .{ .tally = .{ .unnamed = 1 }, .lines = 10, .files = &files, .split_known = false };
    try t.expect(std.mem.indexOf(u8, try copy_count.renderText(arena.allocator(), single), "(the two lines share 1 copy)\n") != null);
}

test "copy total says the split is not known when any entry's is not, and counts a known one as before" {
    const files = [_]copy_count.FileCount{.{ .path = "lib.selka", .copies = 1, .lines = 5 }};
    const found = [_]copy_count.Found{.{ .path = "lib.selka", .line = 1, .column = 1, .slot = 4 }};
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var known = copy_count.Total.init(t.allocator);
    defer known.deinit();
    try known.add(entryCount(&files, &found));
    try t.expect((try known.report(arena.allocator())).split_known);
    var failed = copy_count.Total.init(t.allocator);
    defer failed.deinit();
    try failed.add(entryCount(&files, &found));
    var unknown = entryCount(&files, &found);
    unknown.split_known = false;
    try failed.add(unknown);
    try t.expect(!(try failed.report(arena.allocator())).split_known);
}

test "copy count of a program with no lines is zero per thousand" {
    const empty: copy_count.Report = .{ .tally = .{}, .lines = 0, .files = &.{} };
    try t.expectEqual(@as(f64, 0), empty.perThousand());
}

test "copy count says how many entries it reads in the text only from two, and in the JSON always" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const files = [_]copy_count.FileCount{.{ .path = "a.selka", .copies = 1, .lines = 10 }};
    const two: copy_count.Report = .{ .tally = .{ .unnamed = 1 }, .lines = 10, .files = &files, .entries = 2 };
    const text = try copy_count.renderText(arena.allocator(), two);
    try t.expect(std.mem.startsWith(u8, text, "entries: 2\ncopies: 1 in 10 lines, 100.0 per 1000 lines\n"));
    const one: copy_count.Report = .{ .tally = .{ .unnamed = 1 }, .lines = 10, .files = &files };
    try t.expect(std.mem.startsWith(u8, try copy_count.renderText(arena.allocator(), one), "copies: 1 in 10 lines"));
    const json = try copy_count.renderJson(arena.allocator(), two);
    try t.expect(std.mem.startsWith(u8, json, "{\"schema\":\"copy-count-v1\",\"entries\":2,\"copies\":1,"));
    try t.expect(std.mem.indexOf(u8, try copy_count.renderJson(arena.allocator(), one), "\"entries\":1,\"copies\":1") != null);
}

/// A count of one entry as a union reads it: the files it lists and the copies it found, `slots` being each copy's category.
fn entryCount(files: []const copy_count.FileCount, found: []const copy_count.Found) copy_count.Report {
    return .{ .tally = .{}, .lines = 0, .files = files, .found = found };
}

test "copy total counts a file two entries reach once, its lines once and each of its copies once" {
    var total = copy_count.Total.init(t.allocator);
    defer total.deinit();
    const shared = [_]copy_count.FileCount{ .{ .path = "src/lib.selka", .copies = 2, .lines = 30 }, .{ .path = "src/a.selka", .copies = 1, .lines = 5 } };
    const shared_b = [_]copy_count.FileCount{ .{ .path = "src/lib.selka", .copies = 2, .lines = 30 }, .{ .path = "src/b.selka", .copies = 0, .lines = 7 } };
    const from_a = [_]copy_count.Found{
        .{ .path = "src/lib.selka", .line = 4, .column = 9, .slot = 3 },
        .{ .path = "src/lib.selka", .line = 8, .column = 12, .slot = 4 },
        .{ .path = "src/a.selka", .line = 2, .column = 5, .slot = 4 },
    };
    const from_b = [_]copy_count.Found{
        .{ .path = "src/lib.selka", .line = 4, .column = 9, .slot = 3 },
        .{ .path = "src/lib.selka", .line = 8, .column = 12, .slot = 4 },
    };
    try total.add(entryCount(&shared, &from_a));
    try total.add(entryCount(&shared_b, &from_b));
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try total.report(arena.allocator());
    try t.expectEqual(@as(usize, 2), report.entries);
    try t.expectEqual(@as(usize, 3), report.files.len);
    try t.expectEqual(@as(usize, 42), report.lines);
    try t.expectEqual(copy_count.Tally{ .in_loop = 1, .unnamed = 2 }, report.tally);
    try t.expectEqualStrings("src/a.selka", report.files[0].path);
    try t.expectEqual(@as(usize, 1), report.files[0].copies);
    try t.expectEqualStrings("src/b.selka", report.files[1].path);
    try t.expectEqual(@as(usize, 0), report.files[1].copies);
    try t.expectEqualStrings("src/lib.selka", report.files[2].path);
    try t.expectEqual(@as(usize, 2), report.files[2].copies);
}

test "copy total keeps the best category any entry gave a copy, whichever entry comes first" {
    const files = [_]copy_count.FileCount{.{ .path = "lib.selka", .copies = 4, .lines = 20 }};
    const unseen = [_]copy_count.Found{
        .{ .path = "lib.selka", .line = 1, .column = 1, .slot = 4 },
        .{ .path = "lib.selka", .line = 2, .column = 1, .slot = 3 },
        .{ .path = "lib.selka", .line = 3, .column = 1, .slot = 1 },
        .{ .path = "lib.selka", .line = 4, .column = 1, .slot = 4 },
    };
    const seen = [_]copy_count.Found{
        .{ .path = "lib.selka", .line = 1, .column = 1, .slot = 0 },
        .{ .path = "lib.selka", .line = 2, .column = 1, .slot = 2 },
        .{ .path = "lib.selka", .line = 3, .column = 1, .slot = 4 },
        .{ .path = "lib.selka", .line = 4, .column = 1, .slot = 4 },
    };
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for ([_][2][]const copy_count.Found{ .{ &unseen, &seen }, .{ &seen, &unseen } }) |order| {
        var total = copy_count.Total.init(t.allocator);
        defer total.deinit();
        for (order) |found| try total.add(entryCount(&files, found));
        const report = try total.report(arena.allocator());
        try t.expectEqual(copy_count.Tally{ .needless = 1, .move = 1, .for_store = 1, .unnamed = 1 }, report.tally);
        try t.expectEqual(@as(usize, 20), report.lines);
    }
}

test "copy total reads two spellings of one path as one file" {
    var total = copy_count.Total.init(t.allocator);
    defer total.deinit();
    const one = [_]copy_count.FileCount{.{ .path = "./src/a.selka", .copies = 1, .lines = 9 }};
    const two = [_]copy_count.FileCount{.{ .path = "tools/../src/a.selka", .copies = 1, .lines = 9 }};
    const three = [_]copy_count.FileCount{.{ .path = "/abs/../abs/b.selka", .copies = 0, .lines = 4 }};
    const here = [_]copy_count.Found{.{ .path = "./src/a.selka", .line = 3, .column = 4, .slot = 4 }};
    const there = [_]copy_count.Found{.{ .path = "tools/../src/a.selka", .line = 3, .column = 4, .slot = 1 }};
    try total.add(entryCount(&one, &here));
    try total.add(entryCount(&two, &there));
    try total.add(entryCount(&three, &.{}));
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try total.report(arena.allocator());
    try t.expectEqual(@as(usize, 2), report.files.len);
    try t.expectEqualStrings("/abs/b.selka", report.files[0].path);
    try t.expectEqualStrings("src/a.selka", report.files[1].path);
    try t.expectEqual(copy_count.Tally{ .move = 1 }, report.tally);
    try t.expectEqual(@as(usize, 13), report.lines);
}

/// A module with a copy in a loop, which two entries reach.
const shared_loop_module =
    \\public func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
;
/// An entry that reaches `shared_loop_module`.
const entry_of_shared =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    return len(lib.spread(2))
    \\
;

test "copy total of two real entries sharing a module counts it once, in the loop category the one entry that saw it gave" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "lib", shared_loop_module);
    try writeModule(&temp, "first", entry_of_shared);
    try writeModule(&temp, "second", entry_of_shared);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const site = loopSite(shared_loop_module, "append(mut out, copy(base))", "lib.selka");
    // The first entry has no `cost --sites` row for the copy, as an entry whose rules could not see the loop; the second has.
    const blind = try countProject(arena.allocator(), root, "first", &.{});
    const sighted = try countProject(arena.allocator(), root, "second", &.{site});
    try t.expectEqual(copy_count.Tally{ .unnamed = 1 }, blind.tally);
    try t.expectEqual(copy_count.Tally{ .in_loop = 1 }, sighted.tally);
    for ([_][2]copy_count.Report{ .{ blind, sighted }, .{ sighted, blind } }) |order| {
        var total = copy_count.Total.init(t.allocator);
        defer total.deinit();
        for (order) |one| try total.add(one);
        const report = try total.report(arena.allocator());
        try t.expectEqual(copy_count.Tally{ .in_loop = 1 }, report.tally);
        try t.expectEqual(@as(usize, 3), report.files.len);
        const lines = blind.lines + sighted.lines - std.mem.count(u8, shared_loop_module, "\n");
        try t.expectEqual(lines, report.lines);
    }
}
