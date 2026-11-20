//! rename: keep-file (this file names the old spellings on purpose, and the rename program leaves it alone).
//! The one-line hints for what the language spelled differently before its rename.
const std = @import("std");
const hints = @import("crossing_hints.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

fn entry(args: []const [:0]const u8) !?[]u8 {
    return hints.entryHint(std.testing.allocator, args);
}

test "an entry file that ends in .my gets one line that names .selka and the crossing command" {
    const line = (try entry(&.{ "selka", "check", "src/main.my" })).?;
    defer std.testing.allocator.free(line);
    try expectEqualStrings("selka: src/main.my ends in .my: source files end in .selka now; move the project across with `python3 scripts/rename_to_selka.py --project DIR`\n", line);
    const run = (try entry(&.{ "selka", "run", "--max-steps=5", "main.my", "--", "data.selka" })).?;
    defer std.testing.allocator.free(run);
    try expect(std.mem.startsWith(u8, run, "selka: main.my ends in .my: "));
}

test "a name that only looks like the old suffix, an option's value and a program's arguments get no hint" {
    for ([_][]const [:0]const u8{
        &.{ "selka", "check", "main.selka" },
        &.{ "selka", "check", "notes.mypy", "dummy", "x.my.json" },
        &.{ "selka", "build", "main.selka", "-o", "out.my" },
        &.{ "selka", "run", "main.selka", "--", "data.my" },
        &.{ "selka", "run", "main.selka", "--cache-dir=cache.my" },
        &.{ "selka", "version" },
        &.{"selka"},
    }) |args| try expect((try entry(args)) == null);
}

test "a project folder with mylang.json and no selka.json gets one line that names selka.json" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = std.testing.allocator;
    try temporary.dir.createDirPath(std.testing.io, "old");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "old/mylang.json", .data = "{}\n" });
    try temporary.dir.createDirPath(std.testing.io, "both");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "both/mylang.json", .data = "{}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "both/selka.json", .data = "{}\n" });
    try temporary.dir.createDirPath(std.testing.io, "new");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "new/selka.json", .data = "{}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "plain.selka", .data = "func main() -> int:\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const old = try std.fs.path.joinZ(arena.allocator(), &.{ root, "old" });

    const line = (try hints.projectFileHint(a, std.testing.io, &.{ "selka", "check", old })).?;
    defer a.free(line);
    const expected = try std.fmt.allocPrint(a, "selka: {s} holds mylang.json and no selka.json: the project file is selka.json now; move the project across with `python3 scripts/rename_to_selka.py --project DIR`\n", .{old});
    defer a.free(expected);
    try expectEqualStrings(expected, line);
    for ([_][]const u8{ "both", "new", "plain.selka" }) |name| {
        const operand = try std.fs.path.joinZ(arena.allocator(), &.{ root, name });
        try expect((try hints.projectFileHint(a, std.testing.io, &.{ "selka", "check", operand })) == null);
    }
    try expect((try hints.projectFileHint(a, std.testing.io, &.{ "selka", "check", "no-such-folder" })) == null);
}

test "the command word is never taken for a folder" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    // A folder named like the command, with the old project file in it, is not what `check` is asked to check.
    try temporary.dir.createDirPath(std.testing.io, "check");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "check/mylang.json", .data = "{}\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const command = try std.fs.path.joinZ(arena.allocator(), &.{ root, "check" });
    try expect((try hints.projectFileHint(arena.allocator(), std.testing.io, &.{ "selka", command })) == null);
}

fn variables(pairs: []const [2][]const u8) !std.process.Environ.Map {
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    for (pairs) |pair| try environment.put(pair[0], pair[1]);
    return environment;
}

test "a set old variable is named once with its new spelling, the first of them in sorted order, and how many more there are" {
    var environment = try variables(&.{ .{ "MYLANG_ZIG", "z" }, .{ "MYL_CORE_LEAKCHECK", "1" }, .{ "MYLANG_JOBS", "2" }, .{ "SELKA_JOBS", "2" }, .{ "PATH", "/bin" } });
    defer environment.deinit();
    const line = (try hints.variableHint(std.testing.allocator, &environment)).?;
    defer std.testing.allocator.free(line);
    try expectEqualStrings("selka: the variable MYLANG_ZIG is set and SELKA_ZIG is not: variables begin with SELKA_ now, and the old name is ignored; more old names set: 1\n", line);
}

test "one old variable gets the line without a count, and MYL_CORE_ becomes SELKA_CORE_" {
    var environment = try variables(&.{ .{ "MYL_CORE_LEAKCHECK", "1" }, .{ "HOME", "/home/u" } });
    defer environment.deinit();
    const line = (try hints.variableHint(std.testing.allocator, &environment)).?;
    defer std.testing.allocator.free(line);
    try expectEqualStrings("selka: the variable MYL_CORE_LEAKCHECK is set and SELKA_CORE_LEAKCHECK is not: variables begin with SELKA_ now, and the old name is ignored\n", line);
}

test "no hint when no old variable is set, or when each has its new spelling set" {
    var none = try variables(&.{ .{ "SELKA_JOBS", "2" }, .{ "MYLINE", "x" }, .{ "MYL_HEADER", "x" }, .{ "XMYLANG_JOBS", "x" } });
    defer none.deinit();
    try expect((try hints.variableHint(std.testing.allocator, &none)) == null);
    var answered = try variables(&.{ .{ "MYLANG_JOBS", "1" }, .{ "SELKA_JOBS", "2" }, .{ "MYL_CORE_LEAKCHECK", "1" }, .{ "SELKA_CORE_LEAKCHECK", "" } });
    defer answered.deinit();
    try expect((try hints.variableHint(std.testing.allocator, &answered)) == null);
}
