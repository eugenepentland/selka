//! The stores a project's `selka.json` names (FR8), through the installed compiler: the file alone decides, the
//! caller's environment (an empty variable too) beats it, a flag beats both, `false` turns a store off, the temporary
//! folder is made and left empty, a guest sees the caller's environment, and `selka cache where` names what decided
//! each place. Every child runs with the six variables removed and `HOME` in the test's own directory, so nothing
//! can reach the real per-user stores.
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// The variables the `stores` object stands for, and the record of what a file set.
const placed = [_][]const u8{ "XDG_CACHE_HOME", "SELKA_CORE_RUNTIME_CACHE", "SELKA_STAGE_SHARED_CACHE", "SELKA_COMPILER_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE", "TMPDIR", "SELKA_STORE_SETTINGS" };

const program =
    \\func main(out: Stream, env: Environment) -> int:
    \\    match env.get("TMPDIR"):
    \\        case Some(value):
    \\            print(out, value)
    \\        case None:
    \\            print(out, "TMPDIR unset")
    \\    return 0
    \\
;

const tests_source =
    \\public func test_one() -> bool:
    \\    return 1 + 1 == 2
    \\
;

const Fixture = struct {
    temp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: []const u8 = "",
    environment: std.process.Environ.Map = undefined,

    fn init(self: *Fixture) !void {
        self.temp = testing.tmpDir(.{});
        self.arena = std.heap.ArenaAllocator.init(testing.allocator);
        const a = self.arena.allocator();
        try self.temp.dir.createDirPath(testing.io, "project");
        try self.temp.dir.createDirPath(testing.io, "home");
        self.root = try self.temp.dir.realPathFileAlloc(testing.io, ".", a);
        self.environment = try std.process.Environ.createMap(testing.environ, a);
        for (placed) |name| _ = self.environment.swapRemove(name);
        try self.environment.put("HOME", try self.path("home"));
        try self.temp.dir.writeFile(testing.io, .{ .sub_path = "project/main.selka", .data = program });
        try self.temp.dir.writeFile(testing.io, .{ .sub_path = "project/sum_test.selka", .data = tests_source });
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.temp.cleanup();
    }

    fn path(self: *Fixture, relative: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ self.root, relative });
    }

    /// Write the project's `selka.json` with `stores` as its stores object, `@` standing for the test's directory.
    fn configure(self: *Fixture, stores: []const u8) !void {
        const a = self.arena.allocator();
        const body = try std.mem.replaceOwned(u8, a, stores, "@", self.root);
        const text = try std.fmt.allocPrint(a, "{{\"version\": 1,\n  \"stores\": {s}}}\n", .{body});
        try self.temp.dir.writeFile(testing.io, .{ .sub_path = "project/selka.json", .data = text });
    }

    /// Run the compiler in the project directory with the fixture's environment and `extra` set on top.
    fn run(self: *Fixture, argv: []const []const u8, extra: []const [2][]const u8) !std.process.RunResult {
        const a = self.arena.allocator();
        var environment = try self.environment.clone(a);
        for (extra) |pair| try environment.put(pair[0], pair[1]);
        var full: std.ArrayList([]const u8) = .empty;
        try full.append(a, try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), a));
        try full.appendSlice(a, argv);
        return std.process.run(a, testing.io, .{ .argv = full.items, .cwd = .{ .path = try self.path("project") }, .environ_map = &environment });
    }

    fn exists(self: *Fixture, relative: []const u8) bool {
        self.temp.dir.access(testing.io, relative, .{}) catch return false;
        return true;
    }

    fn empty(self: *Fixture, relative: []const u8) !bool {
        var dir = try self.temp.dir.openDir(testing.io, relative, .{ .iterate = true });
        defer dir.close(testing.io);
        var iterator = dir.iterate();
        return try iterator.next(testing.io) == null;
    }
};

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const every_place =
    \\{"cache_home": "@/stores/xdg", "objects": "~/objects", "stages": "@/stores/stages", "compiler": false, "tests": false, "temporary": "@/tmp"}
;

// FR8: the file alone decides, the build uses what it says and `where` names it; the guest keeps the caller's TMPDIR.
test "project stores: a project's stores decide where a build keeps its stores and temporary files, and nothing reaches the home's cache" {
    var fixture: Fixture = .{ .temp = undefined, .arena = undefined };
    try fixture.init();
    defer fixture.deinit();
    try fixture.configure(every_place);
    const where = try fixture.run(&.{ "cache", "where", "main.selka" }, &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, where.term);
    const file = try fixture.path("project/selka.json");
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(fixture.arena.allocator(), "cache_home  {s}  (selka.json {s})", .{ try fixture.path("stores/xdg"), file })));
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(fixture.arena.allocator(), "objects     {s}  (selka.json {s})", .{ try fixture.path("home/objects"), file })));
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(fixture.arena.allocator(), "compiler    off  (selka.json {s})", .{file})));
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(fixture.arena.allocator(), "temporary   {s}  (selka.json {s})", .{ try fixture.path("tmp"), file })));
    const ran = try fixture.run(&.{ "run", "main.selka" }, &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    // The program reads TMPDIR as its caller set it: here, not at all.
    try testing.expectEqualStrings("TMPDIR unset\n", ran.stdout);
    try testing.expect(fixture.exists("home/objects/units-v1"));
    try testing.expect(fixture.exists("stores/stages/stage-artifacts-v1"));
    try testing.expect(fixture.exists("stores/xdg/selka"));
    try testing.expect(try fixture.empty("tmp"));
    // `compiler` and `tests` are off, and every other store is the file's: the home's cache was never made.
    try testing.expect(!fixture.exists("home/.cache"));
    try testing.expect(!fixture.exists("stores/xdg/selka/compiler-artifacts"));
    // A flag beats the environment and the file: `--shared-cache-dir` names the test store.
    try fixture.configure("{\"cache_home\": \"@/stores/xdg\", \"objects\": \"~/objects\", \"stages\": \"@/stores/stages\", \"compiler\": false, \"tests\": \"@/stores/file-tests\"}");
    const flagged = try fixture.run(&.{ "test", "sum_test.selka", "--shared-cache-dir", try fixture.path("stores/flag-tests") }, &.{.{ "SELKA_TEST_SHARED_CACHE", try fixture.path("stores/environment-tests") }});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, flagged.term);
    try testing.expect(fixture.exists("stores/flag-tests/native-tests-v3"));
    try testing.expect(!fixture.exists("stores/environment-tests"));
    try testing.expect(!fixture.exists("stores/file-tests"));
    try testing.expect(!fixture.exists("home/.cache"));
}

// FR8: the caller's environment beats the file, an empty variable too, and `where` says so.
test "project stores: the caller's environment beats a project's stores, and an empty variable turns a store off" {
    var fixture: Fixture = .{ .temp = undefined, .arena = undefined };
    try fixture.init();
    defer fixture.deinit();
    try fixture.configure(every_place);
    const where = try fixture.run(&.{ "cache", "where" }, &.{ .{ "XDG_CACHE_HOME", try fixture.path("caller-xdg") }, .{ "SELKA_CORE_RUNTIME_CACHE", "" }, .{ "SELKA_COMPILER_SHARED_CACHE", try fixture.path("caller-compiler") } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, where.term);
    const a = fixture.arena.allocator();
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(a, "cache_home  {s}  (environment XDG_CACHE_HOME)", .{try fixture.path("caller-xdg")})));
    try testing.expect(contains(where.stdout, "objects     off  (environment SELKA_CORE_RUNTIME_CACHE)"));
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(a, "compiler    {s}  (environment SELKA_COMPILER_SHARED_CACHE)", .{try fixture.path("caller-compiler")})));
    try testing.expect(contains(where.stdout, try std.fmt.allocPrint(a, "stages      {s}  (selka.json {s})", .{ try fixture.path("stores/stages"), try fixture.path("project/selka.json") })));
    // Without a stores object every place is the environment's or the default, under the home's cache.
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = "project/selka.json", .data = "{\"version\": 1}\n" });
    const plain = try fixture.run(&.{ "cache", "where", "main.selka" }, &.{});
    try testing.expect(contains(plain.stdout, try std.fmt.allocPrint(a, "stages      {s}  (under cache_home, default)", .{try fixture.path("home/.cache/selka/stage-artifacts")})));
    try testing.expect(contains(plain.stdout, "temporary   /tmp  (default)"));
}

// FR8: a store the project's own checkout could supply is refused before anything is built.
test "project stores: a project's store inside its own directory is refused with the file, line and key" {
    var fixture: Fixture = .{ .temp = undefined, .arena = undefined };
    try fixture.init();
    defer fixture.deinit();
    try fixture.configure("{\"objects\": \"@/project/.objects\"}");
    const checked = try fixture.run(&.{ "check", "main.selka" }, &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, checked.term);
    const a = fixture.arena.allocator();
    try testing.expect(contains(checked.stderr, try std.fmt.allocPrint(a, "{s}:2:", .{try fixture.path("project/selka.json")})));
    try testing.expect(contains(checked.stderr, "error[E_PROJECT_CONFIG]: stores.objects lies inside the project that names it"));
    try testing.expect(!fixture.exists("project/.objects"));
    try testing.expect(!fixture.exists("project/.selka-cache"));
    try fixture.configure("{\"objects\": \"objects\"}");
    const relative = try fixture.run(&.{ "build", "main.selka", "-o", "main" }, &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, relative.term);
    try testing.expect(contains(relative.stderr, "a store must lie outside the project: spell it as an absolute path or from ~/"));
}

// spec: STORE-WHERE-REFUSE-1
// FR18: `cache where` reads the same file, so it refuses it the same way rather than describe the default stores.
test "project stores: cache where refuses a relative store the way check does" {
    var fixture: Fixture = .{ .temp = undefined, .arena = undefined };
    try fixture.init();
    defer fixture.deinit();
    try fixture.configure("{\"cache_home\": \"stores\"}");
    const checked = try fixture.run(&.{ "check", "main.selka" }, &.{});
    const where = try fixture.run(&.{ "cache", "where", "main.selka" }, &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, where.term);
    try testing.expectEqual(checked.term, where.term);
    try testing.expectEqualStrings(checked.stderr, where.stderr);
    try testing.expect(contains(where.stderr, "error[E_PROJECT_CONFIG]: a store must lie outside the project"));
    try testing.expectEqualStrings("", where.stdout);
}
