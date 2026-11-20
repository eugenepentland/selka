//! A module constant a function computes (`const VALUE: int = build(4)`) is folded into its readers, so a cached build must follow
//! an edit of that function's body although no reader's text changed (CONSTSTALE). Each test builds and runs a project in one work
//! directory, edits one body, and builds again through the same caches: the reader holds the new value under `run`, `build -o` and
//! `selka test`, as a build with `--no-cache` does.
const std = @import("std");
const testing = std.testing;

/// The constant, computed by a loop: 60, and 66 once `index * 10` reads `index * 11`.
const constants_text =
    \\func build(n: int) -> int:
    \\    mut total = 0
    \\    for index in range(n):
    \\        total = total + index * 10
    \\    return total
    \\
    \\
    \\public const VALUE: int = build(4)
    \\
;
/// A reader of `constants.VALUE` in another module.
const main_text =
    \\import constants
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, constants.VALUE)
    \\    return 0
    \\
;

/// A project in a temporary directory, built through one cache directory and the private stores of `test_paths`.
const Project = struct {
    temporary: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    environment: std.process.Environ.Map,

    fn init(files: []const [2][]const u8) !Project {
        var temporary = testing.tmpDir(.{});
        errdefer temporary.cleanup();
        for (files) |file| try temporary.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
        return .{
            .temporary = temporary,
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .environment = try @import("test_paths").privateEnvironment(testing.allocator),
        };
    }

    fn deinit(self: *Project) void {
        self.environment.deinit();
        self.arena.deinit();
        self.temporary.cleanup();
    }

    /// Replace the first `old` in `path` with `new`.
    fn edit(self: *Project, path: []const u8, old: []const u8, new: []const u8) !void {
        const a = self.arena.allocator();
        const text = try self.temporary.dir.readFileAlloc(testing.io, path, a, .limited(1 << 20));
        const at = std.mem.indexOf(u8, text, old) orelse return error.TestUnexpectedResult;
        const edited = try std.mem.concat(a, u8, &.{ text[0..at], new, text[at + old.len ..] });
        try self.temporary.dir.writeFile(testing.io, .{ .sub_path = path, .data = edited });
    }

    /// The standard output of `argv` run in the project, which must exit with `code`.
    fn output(self: *Project, argv: []const []const u8, code: u8) ![]const u8 {
        const a = self.arena.allocator();
        const result = try std.process.run(a, testing.io, .{ .argv = argv, .cwd = .{ .dir = self.temporary.dir }, .environ_map = &self.environment });
        testing.expectEqual(std.process.Child.Term{ .exited = code }, result.term) catch |err| {
            std.debug.print("{s}\n{s}\n", .{ result.stdout, result.stderr });
            return err;
        };
        return result.stdout;
    }

    /// `selka COMMAND ENTRY` with the cache directory and this build's Zig.
    fn selka(self: *Project, command: []const u8, entry: []const u8, code: u8) ![]const u8 {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), self.arena.allocator());
        return self.output(&.{ compiler, command, entry, "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path }, code);
    }

    /// What the entry prints under `run`, and under a program `build -o` writes; the two must agree.
    fn printed(self: *Project) ![]const u8 {
        const ran = try self.selka("run", "main.selka", 0);
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), self.arena.allocator());
        _ = try self.output(&.{ compiler, "build", "main.selka", "-o", "program", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path }, 0);
        const program = try self.temporary.dir.realPathFileAlloc(testing.io, "program", self.arena.allocator());
        try testing.expectEqualStrings(ran, try self.output(&.{program}, 0));
        return ran;
    }
};

/// Build and run `files`, apply the edit to `path`, and expect `before` and then `after` from the cached builds.
fn expectFollows(files: []const [2][]const u8, path: []const u8, old: []const u8, new: []const u8, before: []const u8, after: []const u8) !void {
    var project = try Project.init(files);
    defer project.deinit();
    try testing.expectEqualStrings(before, try project.printed());
    try project.edit(path, old, new);
    try testing.expectEqualStrings(after, try project.printed());
}

test "constant cache: an edit of the body a constant calls reaches a reader in another module (case 1)" {
    try expectFollows(&.{ .{ "constants.selka", constants_text }, .{ "main.selka", main_text } }, "constants.selka", "index * 10", "index * 11", "60\n", "66\n");
}

test "constant cache: an edit of the body a constant calls reaches a reader in the constant's own module (case 2)" {
    const text = constants_text ++
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, VALUE)
        \\    return 0
        \\
    ;
    try expectFollows(&.{.{ "main.selka", text }}, "main.selka", "index * 10", "index * 11", "60\n", "66\n");
}

test "constant cache: an edit two calls down, in a third module, reaches the reader (case 3)" {
    const steps =
        \\public func step(index: int) -> int:
        \\    return index * 10
        \\
    ;
    const constants =
        \\import steps
        \\
        \\
        \\func build(n: int) -> int:
        \\    mut total = 0
        \\    for index in range(n):
        \\        total = total + steps.step(index)
        \\    return total
        \\
        \\
        \\public const VALUE: int = build(4)
        \\
    ;
    try expectFollows(&.{ .{ "steps.selka", steps }, .{ "constants.selka", constants }, .{ "main.selka", main_text } }, "steps.selka", "index * 10", "index * 11", "60\n", "66\n");
}

test "constant cache: a constant that reads another module's constant follows the body behind it (case 4)" {
    const derived =
        \\import constants
        \\
        \\
        \\public const DOUBLE: int = constants.VALUE * 2
        \\
    ;
    const main =
        \\import derived
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, derived.DOUBLE)
        \\    return 0
        \\
    ;
    try expectFollows(&.{ .{ "constants.selka", constants_text }, .{ "derived.selka", derived }, .{ "main.selka", main } }, "constants.selka", "index * 10", "index * 11", "120\n", "132\n");
}

test "constant cache: an edit of the body that builds a bytes table reaches its readers, under run, build and test (case 5)" {
    const tables =
        \\import buffers
        \\
        \\
        \\public const SQUARES: bytes = squares(4)
        \\
        \\
        \\func squares(count: int) -> bytes:
        \\    mut table = buffers.empty()
        \\    for index in range(count):
        \\        _ = buffers.append_byte(mut table, index * index)
        \\    return bytes(table)
        \\
    ;
    const main =
        \\import tables
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, int(tables.SQUARES[3]))
        \\    return 0
        \\
    ;
    const pinned =
        \\import tables
        \\
        \\
        \\public func test_square_is_nine() -> bool:
        \\    return int(tables.SQUARES[3]) == 9
        \\
    ;
    var project = try Project.init(&.{ .{ "tables.selka", tables }, .{ "main.selka", main }, .{ "value_test.selka", pinned } });
    defer project.deinit();
    try testing.expectEqualStrings("9\n", try project.printed());
    try testing.expect(std.mem.indexOf(u8, try project.selka("test", "value_test.selka", 0), "1 passed") != null);
    try project.edit("tables.selka", "index * index)", "index * index + 1)");
    try testing.expectEqualStrings("10\n", try project.printed());
    try testing.expect(std.mem.indexOf(u8, try project.selka("test", "value_test.selka", 1), "1 failed") != null);
    // The same octets from another body: the readers keep what they printed.
    try project.edit("tables.selka", "index * index + 1)", "1 + index * index)");
    try testing.expectEqualStrings("10\n", try project.printed());
}

test "constant cache: a test that pins the old value fails after the body edit, it is not served as passed (case 6)" {
    const pinned =
        \\import constants
        \\
        \\
        \\public func test_value_is_sixty() -> bool:
        \\    return constants.VALUE == 60
        \\
    ;
    var project = try Project.init(&.{ .{ "constants.selka", constants_text }, .{ "value_test.selka", pinned } });
    defer project.deinit();
    try testing.expect(std.mem.indexOf(u8, try project.selka("test", "value_test.selka", 0), "1 passed") != null);
    try project.edit("constants.selka", "index * 10", "index * 11");
    try testing.expect(std.mem.indexOf(u8, try project.selka("test", "value_test.selka", 1), "1 failed") != null);
    try testing.expect(std.mem.indexOf(u8, try project.selka("test", "value_test.selka", 1), "1 failed") != null);
}

test "constant cache: an edit that keeps the value keeps the reader's output (case 7)" {
    try expectFollows(&.{ .{ "constants.selka", constants_text }, .{ "main.selka", main_text } }, "constants.selka", "index * 10", "10 * index", "60\n", "60\n");
}
