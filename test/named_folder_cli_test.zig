//! A folder the command line names is walked whatever it is called (FR85): `selka test build` and `selka check build` find the
//! sources of a folder named `build`, while a walk of a project root, or of a folder above, still leaves `build`, `zig-out`,
//! `node_modules` and the hidden folders alone, and a directory run that finds nothing says which folders it left alone.
const std = @import("std");
const testing = std.testing;

/// What one run of the compiler printed, and how it ended.
const Outcome = struct {
    code: u8,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

const config = [2][]const u8{ "selka.json", "{\"version\": 1}\n" };
const passing = "public func test_one() -> bool:\n    return 1 + 1 == 2\n";
/// The project root as a command-line path. It has a name because the test-inputs coverage check reads the command
/// word and a dot written side by side as a path of this repository.
const root_argument = ".";

/// The compiler run from a fresh directory holding `files` (path and text pairs), with `argv` after its path and the cache in the
/// directory's own `.cache` folder.
fn run(files: []const [2][]const u8, argv: []const []const u8) !Outcome {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    for (files) |file| {
        if (std.fs.path.dirname(file[0])) |parent| try temporary.dir.createDirPath(testing.io, parent);
        try temporary.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    }
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const here = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(here);
    const cache = try std.fs.path.join(testing.allocator, &.{ here, ".cache" });
    defer testing.allocator.free(cache);
    var command: std.ArrayList([]const u8) = .empty;
    defer command.deinit(testing.allocator);
    try command.append(testing.allocator, compiler);
    try command.appendSlice(testing.allocator, argv);
    try command.appendSlice(testing.allocator, &.{ "--cache-dir", cache });
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = command.items,
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    return .{ .code = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stdout = result.stdout, .stderr = result.stderr };
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

test "test build: a project folder named build is walked, as one named bld is" {
    const files = [_][2][]const u8{ config, .{ "build/t.selka", passing }, .{ "bld/t.selka", passing } };
    const named = try run(&files, &.{ "test", "build" });
    defer named.deinit();
    try testing.expectEqual(@as(u8, 0), named.code);
    try testing.expect(contains(named.stdout, "passed build.t::test_one"));
    try testing.expect(contains(named.stdout, "1 passed"));
    const other = try run(&files, &.{ "test", "bld" });
    defer other.deinit();
    try testing.expectEqual(@as(u8, 0), other.code);
    try testing.expect(contains(other.stdout, "passed bld.t::test_one"));
}

test "test DIR: the project root and the folder above one named build still leave it alone, and a run that finds nothing says so" {
    const files = [_][2][]const u8{ config, .{ "top.selka", passing }, .{ "build/t.selka", passing }, .{ "tools/build/t.selka", passing }, .{ "tools/node_modules/n.selka", passing } };
    const root = try run(&files, &.{ "test", root_argument });
    defer root.deinit();
    try testing.expectEqual(@as(u8, 0), root.code);
    try testing.expect(contains(root.stdout, "passed top::test_one"));
    try testing.expect(!contains(root.stdout, "build.t"));
    try testing.expectEqualStrings("", root.stderr);
    const above = try run(&files, &.{ "test", "tools" });
    defer above.deinit();
    try testing.expectEqual(@as(u8, 3), above.code);
    try testing.expect(contains(above.stdout, "0 passed, 0 cached, 0 failed, 0 skipped"));
    try testing.expect(contains(above.stderr, "note: no tests found under `tools`: `tools/build/` is left alone as a build-output folder, `tools/node_modules/` as a dependency folder; name one to include it\n"));
    const inside = try run(&files, &.{ "test", "tools/build" });
    defer inside.deinit();
    try testing.expectEqual(@as(u8, 0), inside.code);
    try testing.expect(contains(inside.stdout, "passed tools.build.t::test_one"));
}

test "check build: a module in a folder named build is checked, and a check of the project root leaves it alone" {
    const broken = "public func f() -> int:\n    return \"text\"\n";
    const files = [_][2][]const u8{ config, .{ "top.selka", "public func g() -> int:\n    return 1\n" }, .{ "build/t.selka", broken } };
    const named = try run(&files, &.{ "check", "build", "--no-cache" });
    defer named.deinit();
    try testing.expectEqual(@as(u8, 1), named.code);
    try testing.expect(contains(named.stderr, "build/t.selka:2:5: error[E_TYPE]: expected int, found str"));
    const root = try run(&files, &.{ "check", ".", "--no-cache" });
    defer root.deinit();
    try testing.expectEqual(@as(u8, 0), root.code);
    try testing.expect(contains(root.stderr, "check: ok (1 module, 0 cached)"));
}

test "a module of a folder named build is imported by its dotted name under a selka.json, and refused with the way out without one" {
    const test_file = "import build.x\n\npublic func test_one() -> bool:\n    return x.f() == 2\n";
    const library = "public func f() -> int:\n    return 2\n";
    const configured = try run(&.{ config, .{ "build/x.selka", library }, .{ "build/t.selka", test_file } }, &.{ "test", "build" });
    defer configured.deinit();
    try testing.expectEqual(@as(u8, 0), configured.code);
    try testing.expect(contains(configured.stdout, "passed build.t::test_one"));
    const bare = [_][2][]const u8{ .{ "build/x.selka", library }, .{ "build/t.selka", test_file } };
    const refused = try run(&bare, &.{ "test", "build" });
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.code);
    try testing.expect(contains(refused.stderr, "error[E_MODULE_READ]: cannot load build/x.selka"));
    try testing.expect(contains(refused.stderr, "(no `selka.json` sets it)"));
    try testing.expect(contains(refused.stderr, "run again with `--import-root DIR`"));
    const rooted = try run(&bare, &.{ "test", "build", "--import-root", "." });
    defer rooted.deinit();
    try testing.expectEqual(@as(u8, 0), rooted.code);
    try testing.expect(contains(rooted.stdout, "passed build.t::test_one"));
}
