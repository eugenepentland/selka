//! Two projects that share a library file, built in turn through one stage store's shared half (F54): the artifact a function is stored
//! under its key depends on which types lowering found in the module and which it made, so it depends on the order the project lowers
//! its functions in, and the shared store keeps the first writer's. A project that lowers the shared function in the other order
//! keeps its own artifact in its work directory and reads it first; without that, its edits asked the front end to omit a function
//! whose shared artifact it could not replay, and every build started again with complete trees (`fallbacks`).
const std = @import("std");
const tools = @import("core_test_options");

const io = std.testing.io;

/// The library both projects hold byte for byte: two functions that decode bytes, so whichever one a project lowers first makes the
/// result type the other finds.
const library =
    \\import strings
    \\
    \\public func dec1(b: bytes) -> str:
    \\    match strings.decode(b):
    \\        case Ok(s):
    \\            return s
    \\        case Err(_):
    \\            assert False, "bad one"
    \\    return ""
    \\
    \\public func dec2(b: bytes) -> str:
    \\    match strings.decode(b):
    \\        case Ok(s):
    \\            return s
    \\        case Err(_):
    \\            assert False, "bad two"
    \\    return ""
    \\
;

/// The entry of the project that calls `dec1` before `dec2`; `{d}` is a constant an edit changes, and no declaration.
const first_order =
    \\import lib
    \\
    \\func main() -> int:
    \\    const a = lib.dec1(b"abc")
    \\    const b = lib.dec2(b"abcd")
    \\    return len(a) + len(b) + {d}
    \\
;

/// The entry of the project that calls them the other way round.
const second_order =
    \\import lib
    \\
    \\func main() -> int:
    \\    const b = lib.dec2(b"abcd")
    \\    const a = lib.dec1(b"abc")
    \\    return len(b) + len(a) + {d}
    \\
;

/// Directories under one root: the projects' trees, their work directories, the shared half and a per-user cache.
const Trees = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn path(self: Trees, parts: []const []const u8) ![]const u8 {
        const joined = try std.fs.path.join(self.arena, parts);
        return std.fs.path.join(self.arena, &.{ self.root, joined });
    }

    /// Write `main.selka` of project `name` from `template`, with `bias` where the template says `{d}`, and its copy of the library.
    fn write(self: Trees, name: []const u8, template: []const u8, bias: u32) !void {
        try std.Io.Dir.cwd().createDirPath(io, try self.path(&.{name}));
        const at = std.mem.indexOf(u8, template, "{d}").?;
        const entry = try std.fmt.allocPrint(self.arena, "{s}{d}{s}", .{ template[0..at], bias, template[at + 3 ..] });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try self.path(&.{ name, "main.selka" }), .data = entry });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try self.path(&.{ name, "lib.selka" }), .data = library });
    }

    /// Build project `name` into `output`, with its own work directory `cache` and the shared half (`plain` asks for a `--no-cache` build).
    /// Returns the compiler's output (stdout, then stderr).
    fn build(self: Trees, name: []const u8, output: []const u8, cache: []const u8, plain: bool) ![]const u8 {
        const executable = try std.Io.Dir.cwd().realPathFileAlloc(io, tools.corePath(), self.arena);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(self.arena, &.{ executable, "build", "main.selka", "-o", try self.path(&.{output}), "--report" });
        try argv.appendSlice(self.arena, if (plain) &.{"--no-cache"} else &.{ "--cache-dir", try self.path(&.{cache}) });
        var environment = try tools.privateEnvironment(self.arena);
        try environment.put("XDG_CACHE_HOME", try self.path(&.{"xdg"}));
        // The compiler's own store is what gives a function the key every project that checks it alike shares (`Session.keyedByPart`).
        if (!plain) try environment.put("SELKA_STAGE_SHARED_CACHE", try self.path(&.{"shared"}));
        if (!plain) try environment.put("SELKA_COMPILER_SHARED_CACHE", try self.path(&.{"compiler"}));
        const result = try std.process.run(self.arena, io, .{ .argv = argv.items, .cwd = .{ .path = try self.path(&.{name}) }, .environ_map = &environment });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        return std.mem.concat(self.arena, u8, &.{ result.stdout, result.stderr });
    }

    fn program(self: Trees, output: []const u8) ![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(io, try self.path(&.{output}), self.arena, .limited(64 << 20));
    }
};

/// The whole-tree retries of the build whose `cache-report-v1` line is in `text` (`stages.lowering.fallbacks`); null for a build that replayed.
fn fallbacks(a: std.mem.Allocator, text: []const u8) !?i64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "cache-report-v1") == null) continue;
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
        const stages = parsed.object.get("stages") orelse return null;
        if (stages != .object) return null;
        return stages.object.get("lowering").?.object.get("fallbacks").?.integer;
    }
    return error.TestUnexpectedResult;
}

/// One edit in each project in turn (the entries change in a constant and no declaration), each built through the shared half and
/// compared with a `--no-cache` build of the same files; the whole-tree retries of the two builds.
fn round(trees: Trees, bias: u32) !i64 {
    const a = trees.arena;
    try trees.write("first", first_order, bias);
    const retries_first = (try fallbacks(a, try trees.build("first", "first.out", "first-cache", false))) orelse 0;
    try trees.write("second", second_order, bias);
    const retries_second = (try fallbacks(a, try trees.build("second", "second.out", "second-cache", false))) orelse 0;
    _ = try trees.build("first", "first.plain", "unused", true);
    _ = try trees.build("second", "second.plain", "unused", true);
    try std.testing.expectEqualSlices(u8, try trees.program("first.plain"), try trees.program("first.out"));
    try std.testing.expectEqualSlices(u8, try trees.program("second.plain"), try trees.program("second.out"));
    return retries_first + retries_second;
}

test "F54 two projects that lower a shared library in different orders, built in turn through one shared half, never start a build again with complete trees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const trees: Trees = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()) };
    try trees.write("first", first_order, 1);
    try trees.write("second", second_order, 1);
    _ = try trees.build("first", "first.out", "first-cache", false);
    _ = try trees.build("second", "second.out", "second-cache", false);
    // The build of a body edit omits the library functions it holds receipts for and restores their artifacts: the second project's,
    // with the shared half holding the first one's, must come from its own work directory.
    const retries = (try round(trees, 2)) + (try round(trees, 3)) + (try round(trees, 4));
    try std.testing.expectEqual(@as(i64, 0), retries);
}
