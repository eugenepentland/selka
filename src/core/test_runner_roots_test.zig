//! Stage 2 of the test-loop plan (`docs/audits/test-loop-plan-2026-11-09.md`, decisions in
//! `experiments/test-loop-20261109/DECISIONS.md`): a pass belongs to the test, not to its root, and a directory run gives
//! each test to one root (D-TL2-1 to D-TL2-3).
const std = @import("std");
const options = @import("core_test_options");
const v = @import("property_value.zig");

/// A library with one test, imported by two roots with one test each.
const library = "public func value() -> int:\n    return 3\n\n\npublic func test_lib() -> bool:\n    return value() == 3\n";
const first_root = "import lib\n\n\npublic func test_one() -> bool:\n    return lib.value() + 1 == 4\n";
const second_root = "import lib\n\n\npublic func test_two() -> bool:\n    return lib.value() + 2 == 5\n";

const Run = struct { status: u8, report: std.json.Value, stderr: []const u8 };

/// A directory of the three files in a temporary root, and the runs of `selka test` over it with one private cache.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8) !Project {
        var project: Project = .{ .arena = a, .root = root, .environment = try options.privateEnvironment(a) };
        errdefer project.environment.deinit();
        try project.write("lib.selka", library);
        try project.write("one.selka", first_root);
        try project.write("two.selka", second_root);
        try project.write("selka.json", "{\"version\":2}");
        return project;
    }

    fn write(self: Project, name: []const u8, data: []const u8) !void {
        const path = try std.fs.path.join(self.arena, &.{ self.root, "project", name });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(path).?);
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = data });
    }

    /// `selka test TARGET --json` (TARGET relative to the project; "." for the directory) with `extra` flags.
    fn run(self: *const Project, target: []const u8, extra: []const []const u8) !Run {
        var argv: std.ArrayList([]const u8) = .empty;
        const path = try std.fs.path.join(self.arena, &.{ self.root, "project", target });
        try argv.appendSlice(self.arena, &.{ options.corePath(), "test", path, "--json", "--cache-dir", try std.fs.path.join(self.arena, &.{ self.root, "cache" }), "--jobs", "1" });
        try argv.appendSlice(self.arena, extra);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = argv.items, .environ_map = &self.environment });
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, self.arena, result.stdout, .{}) catch .null;
        return .{ .status = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .report = parsed, .stderr = result.stderr };
    }
};

/// The report's tests as `name status` lines, in report order.
fn listing(a: std.mem.Allocator, report: std.json.Value) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (v.array(v.get(report, "tests"))) |item| try out.print(a, "{s} {s}\n", .{ v.text(v.get(item, "name")), v.text(v.get(item, "status")) });
    return out.items;
}

/// The report's tests as `name status` lines, sorted, so two runs that list in a different root order compare.
fn sortedListing(a: std.mem.Allocator, report: std.json.Value) ![]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var all = std.mem.splitScalar(u8, try listing(a, report), '\n');
    while (all.next()) |line| if (line.len != 0) try lines.append(a, line);
    std.mem.sort([]const u8, lines.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    return std.mem.join(a, "\n", lines.items);
}

fn passedCount(report: std.json.Value) u64 {
    return v.number(v.get(report, "passed"));
}

// spec: TEST-LOOP-ONE-ROOT-1
test "two roots that import one library run its tests once and list them once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    const cold = try project.run(".", &.{});
    try std.testing.expectEqual(@as(u8, 0), cold.status);
    // `lib` belongs to `one.selka`, the first root in path order whose closure holds it; `two.selka` runs only its own test.
    try std.testing.expectEqualStrings("lib::test_lib passed\none::test_one passed\ntwo::test_two passed\n", try listing(a, cold.report));
    // An unchanged rerun replays each root's own report, which lists what that root ran (D-TL2-2).
    const warm = try project.run(".", &.{});
    try std.testing.expectEqualStrings("lib::test_lib cached\none::test_one cached\ntwo::test_two cached\n", try listing(a, warm.report));
}

// spec-case: TEST-LOOP-ONE-ROOT-1
test "a file run after a directory run runs nothing, and the reverse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    try std.testing.expectEqual(@as(u8, 0), (try project.run(".", &.{})).status);
    // The file run of `two.selka` runs both tests its closure declares, and the directory run passed both under its roots.
    const file = try project.run("two.selka", &.{});
    try std.testing.expectEqualStrings("lib::test_lib cached\ntwo::test_two cached\n", try listing(a, file.report));
    // An edit the file run reruns, then the directory run finds that pass.
    try project.write("two.selka", "import lib\n\n\npublic func test_two() -> bool:\n    return lib.value() * 2 == 6\n");
    const edited = try project.run("two.selka", &.{});
    // The edited test runs (or, when its built program is one an earlier run linked, is served by that program's record).
    const rerun = try listing(a, edited.report);
    try std.testing.expect(std.mem.eql(u8, rerun, "lib::test_lib cached\ntwo::test_two passed\n") or std.mem.eql(u8, rerun, "lib::test_lib cached\ntwo::test_two cached\n"));
    const directory = try project.run(".", &.{});
    try std.testing.expectEqual(@as(u64, 0), passedCount(directory.report));
    try std.testing.expectEqualStrings("lib::test_lib cached\none::test_one cached\ntwo::test_two cached\n", try listing(a, directory.report));
}

// spec-case: TEST-LOOP-ONE-ROOT-1
test "two roots with different cases for one library test keep two verdicts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    // Each root's cases file names the library's test: under `one` it is skipped, under `two` it runs, and each root's
    // verdict is its own, so both are listed.
    try project.write("one.cases.json", "{\"lib::test_lib\":{\"skip\":\"one skips it\"}}");
    try project.write("two.cases.json", "{\"lib::test_lib\":{\"expected\":true}}");
    const run = try project.run(".", &.{});
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("lib::test_lib skipped\none::test_one passed\nlib::test_lib passed\ntwo::test_two passed\n", try listing(a, run.report));
}

// spec-case: TEST-LOOP-ONE-ROOT-1
test "--filter selects as before across owned modules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    try std.testing.expectEqualStrings("lib::test_lib passed\n", try listing(a, (try project.run(".", &.{ "--filter", "test_lib" })).report));
    try std.testing.expectEqualStrings("two::test_two passed\n", try listing(a, (try project.run(".", &.{ "--filter", "test_two" })).report));
    // The file run is not scoped: the library's test is its own there.
    try std.testing.expectEqualStrings("lib::test_lib cached\n", try listing(a, (try project.run("two.selka", &.{ "--filter", "test_lib" })).report));
}

// spec-case: TEST-LOOP-ONE-ROOT-1
test "the child-per-root oracle reports what the shared check reports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    const shared = try project.run(".", &.{"--force"});
    try project.environment.put("SELKA_TEST_CHILDREN", "1");
    // A child root learns which modules another root owns from `--skip-test-modules`; the listing is the same.
    const children = try project.run(".", &.{"--force"});
    try std.testing.expectEqualStrings(try sortedListing(a, shared.report), try sortedListing(a, children.report));
    try std.testing.expectEqual(@as(u64, 3), passedCount(children.report));
}

// spec-case: TEST-LOOP-ONE-ROOT-1
test "a root left nothing to skip is run and named as a file run of it is, so either replays the other's report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    // `one.selka` comes first, so nothing in its closure is another root's.
    try std.testing.expectEqual(@as(u8, 0), (try project.run(".", &.{})).status);
    const file = try project.run("one.selka", &.{});
    try std.testing.expectEqualStrings("lib::test_lib cached\none::test_one cached\n", try listing(a, file.report));
    try expectEveryReason(file.report, "engine-report-hit");
}

/// Every test of `report` is cached for `reason`.
fn expectEveryReason(report: std.json.Value, reason: []const u8) !void {
    for (v.array(v.get(report, "tests"))) |item| try std.testing.expectEqualStrings(reason, v.text(v.get(v.get(item, "cache"), "reason")));
}

// spec-case: TEST-LOOP-ONE-ROOT-1
test "a directory of one root runs every test its closure declares and replays as a file run of it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer project.environment.deinit();
    // `two.selka` imports `lib` too: a directory of `lib.selka` and `one.selka` alone has one root, which owns everything.
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try std.fs.path.join(a, &.{ project.root, "project", "two.selka" }));
    const directory = try project.run(".", &.{});
    try std.testing.expectEqualStrings("lib::test_lib passed\none::test_one passed\n", try listing(a, directory.report));
    const file = try project.run("one.selka", &.{});
    try std.testing.expectEqualStrings("lib::test_lib cached\none::test_one cached\n", try listing(a, file.report));
    try expectEveryReason(file.report, "engine-report-hit");
}
