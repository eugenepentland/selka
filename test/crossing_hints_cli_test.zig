//! rename: keep-file (this file names the old spellings on purpose, and the rename program leaves it alone).
//! The one-line hints for what the language spelled before its rename (decision GH-D4), through the command line: an entry file
//! that ends in `.my` and a project folder with `mylang.json` and no `selka.json` end the command with status 2 and one line; a set
//! old variable is mentioned once on standard error and the command goes on.
const std = @import("std");
const testing = std.testing;

const crossing = "move the project across with `python3 scripts/rename_to_selka.py --project DIR`\n";

/// The compiler run in `directory` with `argv` after its path, over `environment`.
fn run(directory: std.Io.Dir, environment: *const std.process.Environ.Map, argv: []const []const u8) !std.process.RunResult {
    var full: std.ArrayList([]const u8) = .empty;
    defer full.deinit(testing.allocator);
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    try full.append(testing.allocator, compiler);
    try full.appendSlice(testing.allocator, argv);
    return std.process.run(testing.allocator, testing.io, .{ .argv = full.items, .cwd = .{ .dir = directory }, .environ_map = environment });
}

/// The test process's environment with private stores and none of the variables a case sets.
fn quietEnvironment() !std.process.Environ.Map {
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    var doomed: std.ArrayList([]const u8) = .empty;
    defer doomed.deinit(testing.allocator);
    var entries = environment.iterator();
    while (entries.next()) |entry| {
        const name = entry.key_ptr.*;
        if (std.mem.startsWith(u8, name, "MYLANG_") or std.mem.startsWith(u8, name, "MYL_CORE_")) try doomed.append(testing.allocator, name);
    }
    for (doomed.items) |name| _ = environment.swapRemove(name);
    return environment;
}

test "an entry file that ends in .my ends the command with one line that names .selka and the crossing command" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment = try quietEnvironment();
    defer environment.deinit();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "func main() -> int:\n    return 0\n" });
    for ([_][]const u8{ "check", "run", "build", "test" }) |command| {
        const result = try run(temporary.dir, &environment, &.{ command, "main.my" });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqualStrings("", result.stdout);
        try testing.expectEqualStrings("selka: main.my ends in .my: source files end in .selka now; " ++ crossing, result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
    }
}

test "a project folder with mylang.json and no selka.json ends the command with one line that names selka.json" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment = try quietEnvironment();
    defer environment.deinit();
    try temporary.dir.createDirPath(testing.io, "old");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "old/mylang.json", .data = "{}\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "old/main.selka", .data = "func main() -> int:\n    return 0\n" });
    const result = try run(temporary.dir, &environment, &.{ "check", "old" });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expectEqualStrings("selka: old holds mylang.json and no selka.json: the project file is selka.json now; " ++ crossing, result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
    // With the new project file beside it the folder is a project again, and the hint is silent.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "old/selka.json", .data = "{}\n" });
    const crossed = try run(temporary.dir, &environment, &.{ "check", "old" });
    defer testing.allocator.free(crossed.stdout);
    defer testing.allocator.free(crossed.stderr);
    try testing.expect(std.mem.indexOf(u8, crossed.stderr, "mylang.json") == null);
}

test "a set old variable is named once on standard error, with its new spelling and how many more there are, and the command goes on" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment = try quietEnvironment();
    defer environment.deinit();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main() -> int:\n    return 0\n" });
    try environment.put("MYLANG_CROSSING_ONE", "2");
    try environment.put("MYLANG_CROSSING_TWO", "2");
    try environment.put("MYL_CORE_CROSSING", "1");
    const result = try run(temporary.dir, &environment, &.{ "check", "main.selka" });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    const line = "selka: the variable MYLANG_CROSSING_ONE is set and SELKA_CROSSING_ONE is not: variables begin with SELKA_ now, and the old name is ignored; more old names set: 2\n";
    try testing.expect(std.mem.startsWith(u8, result.stderr, line));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "the variable "));
    try testing.expect(std.mem.indexOf(u8, result.stderr, "check: ok") != null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    // Neither old name is honoured, and with each new spelling set there is nothing to say.
    try environment.put("SELKA_CROSSING_ONE", "2");
    try environment.put("SELKA_CROSSING_TWO", "2");
    try environment.put("SELKA_CORE_CROSSING", "1");
    const answered = try run(temporary.dir, &environment, &.{ "check", "main.selka" });
    defer testing.allocator.free(answered.stdout);
    defer testing.allocator.free(answered.stderr);
    try testing.expect(std.mem.indexOf(u8, answered.stderr, "the variable ") == null);
    try testing.expect(std.mem.indexOf(u8, answered.stderr, "check: ok") != null);
}
