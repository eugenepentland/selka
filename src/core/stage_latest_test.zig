//! A fresh tree's first edit starts from the latest state another tree published (G3p round 11, `optimizer_chunks.Latest`): with the stage
//! store's shared half on, a second tree whose program differs from every published state by a body edit starts from the first tree's head, and
//! the program it builds equals a `--no-cache` build of the same files, also under `--verify-cutoff`. That the head is used is the unit tests'
//! (`optimizer_shortcut.zig`): a debug compiler runs the cutoff in its verify mode for one program in four, which bypasses nothing.
const std = @import("std");
const tools = @import("core_test_options");

const io = std.testing.io;

/// The program of the first tree: functions enough that the optimizer's shortcut has entries to serve.
const first_program =
    \\func twice(x: int) -> int:
    \\    return x + x
    \\
    \\func thrice(x: int) -> int:
    \\    return twice(x) + x
    \\
    \\func offset(x: int) -> int:
    \\    mut total = x
    \\    for i in range(4):
    \\        total = total + i
    \\    return total
    \\
    \\func leaf(x: int) -> int:
    \\    return x * 7
    \\
    \\func combine(a: int, b: int) -> int:
    \\    return thrice(a) + offset(b) + leaf(a)
    \\
    \\func main() -> int:
    \\    return combine(3, 4) - combine(3, 4) + leaf(0)
    \\
;

/// The same program with the body of `leaf` edited: the raw layout is the same, the state is not.
const edited_program =
    \\func twice(x: int) -> int:
    \\    return x + x
    \\
    \\func thrice(x: int) -> int:
    \\    return twice(x) + x
    \\
    \\func offset(x: int) -> int:
    \\    mut total = x
    \\    for i in range(4):
    \\        total = total + i
    \\    return total
    \\
    \\func leaf(x: int) -> int:
    \\    return x * 9
    \\
    \\func combine(a: int, b: int) -> int:
    \\    return thrice(a) + offset(b) + leaf(a)
    \\
    \\func main() -> int:
    \\    return combine(3, 4) - combine(3, 4) + leaf(0)
    \\
;

/// Two trees `a` and `b` under one root, with a stage store's shared half and a per-user cache of their own.
const Trees = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn path(self: Trees, parts: []const []const u8) ![]const u8 {
        const joined = try std.fs.path.join(self.arena, parts);
        return std.fs.path.join(self.arena, &.{ self.root, joined });
    }

    /// Write `bytes` as `main.selka` of tree `name`, creating the tree.
    fn write(self: Trees, name: []const u8, bytes: []const u8) !void {
        try std.Io.Dir.cwd().createDirPath(io, try self.path(&.{name}));
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try self.path(&.{ name, "main.selka" }), .data = bytes });
    }

    /// Build tree `name` into `output` under cache directory `cache`; `shared` says whether the stage store's shared half is on,
    /// `plain` asks for a `--no-cache` build and `verify` for `--verify-cutoff`. Returns the compiler's output (stdout, then stderr).
    fn build(self: Trees, name: []const u8, output: []const u8, cache: []const u8, mode: struct { shared: bool, plain: bool, verify: bool = false }) ![]const u8 {
        const executable = try std.Io.Dir.cwd().realPathFileAlloc(io, tools.corePath(), self.arena);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(self.arena, &.{ executable, "build", "main.selka", "-o", try self.path(&.{output}), "--report" });
        try argv.appendSlice(self.arena, if (mode.plain) &.{"--no-cache"} else &.{ "--cache-dir", try self.path(&.{cache}) });
        if (mode.verify) try argv.append(self.arena, "--verify-cutoff");
        var environment = try tools.privateEnvironment(self.arena);
        try environment.put("XDG_CACHE_HOME", try self.path(&.{"xdg"}));
        if (mode.shared) try environment.put("SELKA_STAGE_SHARED_CACHE", try self.path(&.{"shared"}));
        const result = try std.process.run(self.arena, io, .{ .argv = argv.items, .cwd = .{ .path = try self.path(&.{name}) }, .environ_map = &environment });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        return std.mem.concat(self.arena, u8, &.{ result.stdout, result.stderr });
    }

    /// The bytes of the program `output`.
    fn program(self: Trees, output: []const u8) ![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(io, try self.path(&.{output}), self.arena, .limited(64 << 20));
    }
};

/// The optimizer's findings under `--verify-cutoff` (`restores.cutoff.findings`), from the `cache-report-v1` line in `text`.
fn findings(a: std.mem.Allocator, text: []const u8) !i64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "cache-report-v1") == null) continue;
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
        return parsed.object.get("stages").?.object.get("optimizer").?.object.get("restores").?.object.get("cutoff").?.object.get("findings").?.integer;
    }
    return error.TestUnexpectedResult;
}

test "G3p-r11 pointer: a fresh tree with a body edit, started from the state another tree published, builds the program a no-cache build does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const trees: Trees = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()) };
    try trees.write("a", first_program);
    try trees.write("b", edited_program);
    try trees.write("c", edited_program);
    _ = try trees.build("a", "a.out", "a-cache", .{ .shared = true, .plain = false });
    _ = try trees.build("b", "b.out", "b-cache", .{ .shared = true, .plain = false });
    _ = try trees.build("b", "plain.out", "unused", .{ .shared = false, .plain = true });
    try std.testing.expectEqualSlices(u8, try trees.program("plain.out"), try trees.program("b.out"));
    // A third tree, whose own work directory is empty, under the verify mode: it starts from the state the second tree published last, and
    // every function it takes is derived afresh and compared with the entry, with no finding.
    const verified = try trees.build("c", "c.out", "c-cache", .{ .shared = true, .plain = false, .verify = true });
    try std.testing.expectEqual(@as(i64, 0), try findings(arena.allocator(), verified));
    try std.testing.expectEqualSlices(u8, try trees.program("plain.out"), try trees.program("c.out"));
    // The same fresh tree with no shared half builds the same program.
    _ = try trees.build("c", "alone.out", "alone-cache", .{ .shared = false, .plain = false });
    try std.testing.expectEqualSlices(u8, try trees.program("plain.out"), try trees.program("alone.out"));
}
