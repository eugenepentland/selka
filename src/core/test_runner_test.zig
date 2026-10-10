//! Tests of `mylang-core test`: discovery, the dispatching entry, the report and the
//! command itself on `test/core/runner_cases.my`, whose tests cover every verdict.
const std = @import("std");
const language = @import("mylang");
const options = @import("core_test_options");
const build = @import("build.zig");
const print = @import("print.zig");
const emit_llvm = @import("emit_llvm.zig");
const discover = @import("test_runner_discover.zig");
const entry = @import("test_runner_entry.zig");
const report = @import("test_runner_report.zig");
const runner = @import("test_runner.zig");

const discovery_source =
    \\public func test_public_with_a_parameter(x: int) -> bool:
    \\    return x == x
    \\
    \\
    \\func test_private_with_a_parameter(x: int) -> bool:
    \\    return x == x
    \\
    \\
    \\func test_private_zero_arguments() -> bool:
    \\    return True
    \\
    \\
    \\func test_private_result() -> Result[bool, str]:
    \\    return Ok(True)
    \\
    \\
    \\@test
    \\func marked_result() -> Result[bool, str]:
    \\    return Ok(True)
    \\
    \\
    \\public func test_stream_stand_in(err: Stream) -> bool:
    \\    err.print(1)
    \\    return True
    \\
    \\
    \\func helper() -> bool:
    \\    return True
    \\
;

fn discovered(arena: std.mem.Allocator) ![]discover.Case {
    var unit = try language.Compilation.init(arena, "found.my", discovery_source ++ runner.check_stub);
    try unit.check();
    return discover.discover(arena, unit.program.?, "found", &.{.{ .name = "found", .text = discovery_source }});
}

// spec: NEW-CORE-TEST-1
test "discovery follows the old rule: public or defaulting test_ functions and @test declarations, sorted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const found = try discovered(arena.allocator());
    try std.testing.expectEqual(@as(usize, 4), found.len);
    try std.testing.expectEqualStrings("found::marked_result", found[0].name);
    try std.testing.expectEqualStrings("found::test_private_zero_arguments", found[1].name);
    try std.testing.expectEqualStrings("found::test_public_with_a_parameter", found[2].name);
    try std.testing.expectEqualStrings("found::test_stream_stand_in", found[3].name);
    try std.testing.expectEqual(discover.Shape.result_of_bool, found[0].shape);
    try std.testing.expectEqual(discover.Shape.boolean, found[1].shape);
    try std.testing.expectEqual(@as(usize, 1), found[2].other_parameters);
    try std.testing.expectEqual(@as(usize, 0), found[3].other_parameters);
    try std.testing.expectEqual(@as(i64, 2), found[3].streams[0]);
}

// spec-case: NEW-CORE-TEST-1
test "a filter without a wildcard is a substring of the qualified name, otherwise a glob" {
    try std.testing.expect(discover.matches("test_sum", "prog042::test_sum"));
    try std.testing.expect(discover.matches("prog042", "prog042::test_sum"));
    try std.testing.expect(discover.matches("", "prog042::test_sum"));
    try std.testing.expect(!discover.matches("Test_sum", "prog042::test_sum"));
    try std.testing.expect(discover.matches("*::test_[a-c]?", "checks::test_b1"));
    try std.testing.expect(!discover.matches("*::test_[!a-c]?", "checks::test_b1"));
    try std.testing.expect(discover.matches("*a*b", "xxaaabyb"));
    try std.testing.expect(!discover.matches("*a*b", "xxaac"));
    try std.testing.expect(discover.matches("[]]", "]"));
    try std.testing.expect(!discover.matches("*arena*", "mod::test_plain"));
}

const two_tests =
    \\func test_first() -> bool:
    \\    return 1 + 1 == 2
    \\
    \\
    \\func test_second(out: Stream) -> bool:
    \\    out.print(2)
    \\    return True
    \\
;

// spec: NEW-CORE-TEST-2
test "the dispatching entry parses argv[0] as a test index and calls that test, one process per test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "two.my", two_tests ++ runner.check_stub);
    try unit.check();
    var refusal: build.Refusal = .{};
    const roots = [_]@import("mylang").typed.FunctionId{ unit.program.?.functions[0].id, unit.program.?.functions[1].id };
    var module = try build.buildRoots(a, unit.program.?, &roots, &refusal);
    try entry.addEntry(a, &module, &.{ .{ .function = 0 }, .{ .function = 1, .streams = &.{1} } });
    const text = try print.module(a, &module);
    try std.testing.expect(std.mem.indexOf(u8, text, "fn __test_main(") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call bool test_first()") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call bool test_second(1:cap)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ret 64:i64") != null);
    const context: u8 = 0;
    const llvm = try emit_llvm.emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = lineOne }, .source_path = "two.my", .main = .{} });
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call ptr @myl_core_args(i32 %argc, ptr %argv)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i32 @myl_core_exit(i64 %r)") != null);
}

fn lineOne(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

const verdicts = [_]report.Verdict{
    .{ .name = "m::test_a", .status = .passed },
    .{ .name = "m::test_b", .status = .failed, .reason = "R_LIST_BOUNDS (index 7, length 3)\n  in get at m.my:2:12\n" },
    .{ .name = "m::test_c", .status = .unsupported, .reason = "dict type", .at = "17:13" },
};

// spec: NEW-CORE-TEST-3
test "the text report is the old runner's lines and summary, with unsupported tests counted apart" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try report.text(arena.allocator(), &verdicts);
    try std.testing.expectEqualStrings(
        \\passed m::test_a
        \\failed m::test_b: R_LIST_BOUNDS (index 7, length 3)
        \\  in get at m.my:2:12
        \\unsupported m::test_c: E_CORE_UNSUPPORTED (dict type) at 17:13
        \\1 passed, 0 cached, 1 failed, 0 skipped, 1 unsupported
        \\
    , text);
    const clean = try report.text(arena.allocator(), verdicts[0..1]);
    try std.testing.expectEqualStrings("passed m::test_a\n1 passed, 0 cached, 0 failed, 0 skipped\n", clean);
}

// spec-case: NEW-CORE-TEST-3
// spec-case: NEW-CORE-S5-TEST-STATUS-1
test "the JSON report keys tests by name, status and reason, and the exit status is 0, 1 or 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try report.json(arena.allocator(), &verdicts);
    try std.testing.expect(std.mem.indexOf(u8, text, "{\"name\":\"m::test_c\",\"status\":\"unsupported\",\"reason\":\"dict type\",\"at\":\"17:13\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"reason\":\"R_LIST_BOUNDS (index 7, length 3)\\n  in get at m.my:2:12\\n\"") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, "\"passed\":1,\"failed\":1,\"skipped\":0,\"cached\":0,\"unsupported\":1}\n"));
    try std.testing.expectEqual(@as(u8, 1), report.exitStatus(&verdicts));
    try std.testing.expectEqual(@as(u8, 0), report.exitStatus(verdicts[0..1]));
    try std.testing.expectEqual(@as(u8, 0), report.exitStatus(verdicts[2..3]));
    try std.testing.expectEqual(@as(u8, 3), report.exitStatus(&.{}));
    const skipped = [_]report.Verdict{ .{ .name = "m::test_d", .status = .skipped, .reason = "later" }, .{ .name = "m::test_e", .status = .skipped, .reason = "later" } };
    try std.testing.expectEqual(@as(u8, 3), report.exitStatus(&skipped));
    try std.testing.expectEqual(@as(u8, 0), report.exitStatus(&.{ skipped[0], verdicts[0] }));
}

/// One run of `mylang-core test` on a fixture: exit status and the parsed `--json` report.
const Run = struct { status: u8, parsed: std.json.Parsed(std.json.Value) };

fn runTest(arena: std.mem.Allocator, root: []const u8, fixture: []const u8, extra: []const []const u8) !Run {
    var argv: std.ArrayList([]const u8) = .empty;
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, fixture });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    try argv.appendSlice(arena, &.{ options.core_path, "test", source, "--json", "--cache-dir", cache });
    try argv.appendSlice(arena, extra);
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    const status: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .status = status, .parsed = try std.json.parseFromSlice(std.json.Value, arena, result.stdout, .{}) };
}

/// The test named `name` of a report: its status and the start of its reason.
fn expectVerdict(parsed: std.json.Value, name: []const u8, status: []const u8, reason_start: []const u8) !void {
    var reported = false;
    for (parsed.object.get("tests").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("name").?.string, name)) continue;
        try std.testing.expectEqualStrings(status, item.object.get("status").?.string);
        try std.testing.expect(std.mem.startsWith(u8, item.object.get("reason").?.string, reason_start));
        reported = true;
    }
    try std.testing.expect(reported);
}

fn expectEveryVerdict(parsed: std.json.Value) !void {
    try expectVerdict(parsed, "runner_cases::checks_marked_by_attribute", "passed", "");
    try expectVerdict(parsed, "runner_cases::test_loop_sum_passes", "passed", "");
    try expectVerdict(parsed, "runner_cases::test_comparison_passes", "passed", "");
    try expectVerdict(parsed, "runner_cases::test_takes_a_stream", "passed", "");
    try expectVerdict(parsed, "runner_cases::test_false_verdict_fails", "failed", "expected true, got false");
    try expectVerdict(parsed, "runner_cases::test_bounds_trap", "failed", "R_LIST_BOUNDS (index 7, length 3)");
    try expectVerdict(parsed, "runner_cases::test_overflow_trap", "failed", "R_OVERFLOW (add: left 9223372036854775807, right 1, width 64)");
    try expectVerdict(parsed, "runner_cases::test_division_trap", "failed", "R_DIVISION_BY_ZERO");
    try expectVerdict(parsed, "runner_cases::test_reaches_a_dict", "passed", "");
    try expectVerdict(parsed, "runner_cases::test_property", "passed", "");
}

// spec: NEW-CORE-TEST-4
test "every verdict is graded per test function at debug and release, and the file's other tests still run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const debug = try runTest(arena.allocator(), root, "runner_cases", &.{});
    const release = try runTest(arena.allocator(), root, "runner_cases", &.{"--release"});
    try expectEveryVerdict(debug.parsed.value);
    try expectEveryVerdict(release.parsed.value);
    try std.testing.expectEqual(@as(u8, 1), debug.status);
    try std.testing.expectEqual(@as(u8, 1), release.status);
    try std.testing.expectEqual(@as(i64, 6), debug.parsed.value.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 4), debug.parsed.value.object.get("failed").?.integer);
    try std.testing.expectEqual(@as(i64, 0), debug.parsed.value.object.get("unsupported").?.integer);
}

// spec-case: NEW-CORE-TEST-4
test "a filter narrows the run, and a filter that selects nothing exits 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const loops = try runTest(arena.allocator(), root, "runner_cases", &.{ "--filter", "test_loop" });
    const globbed = try runTest(arena.allocator(), root, "runner_cases", &.{ "--filter", "*_trap" });
    const none = try runTest(arena.allocator(), root, "runner_cases", &.{ "--filter", "no_such_test" });
    try std.testing.expectEqual(@as(u8, 0), loops.status);
    try std.testing.expectEqual(@as(usize, 1), loops.parsed.value.object.get("tests").?.array.items.len);
    try std.testing.expectEqual(@as(u8, 1), globbed.status);
    try std.testing.expectEqual(@as(usize, 3), globbed.parsed.value.object.get("tests").?.array.items.len);
    try std.testing.expectEqual(@as(u8, 3), none.status);
    try std.testing.expectEqual(@as(usize, 0), none.parsed.value.object.get("tests").?.array.items.len);
}

/// A private source, receipt store and component deployment for admission tests.
const CacheProject = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8) !CacheProject {
        var environment = try std.testing.environ.createMap(a);
        errdefer environment.deinit();
        try environment.put("MYLANG_CACHE_PLAN_MODE", "component");
        const artifact = try language.cache_plan_adapter.bind(a, std.testing.io, &environment);
        const contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, artifact.artifact.?.path, a, .limited(64 << 20));

        const directory = try std.fs.path.join(a, &.{ root, "components" });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, directory);
        try environment.put("MYLANG_COMPONENT_DIR", directory);
        var project: CacheProject = .{ .arena = a, .root = root, .environment = environment };
        try project.deploy(contents);
        return project;
    }

    fn path(self: CacheProject, relative: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, relative });
    }

    fn deploy(self: CacheProject, contents: []const u8) !void {
        const binary = try self.path("components/cache-plan");
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = binary, .data = contents });
        try std.Io.Dir.cwd().setFilePermissions(std.testing.io, binary, .executable_file, .{});
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        const manifest = try std.json.Stringify.valueAlloc(self.arena, .{ .format = 1, .component = "cache-plan", .protocol = 2, .schema = 2, .artifact = "cache-plan", .sha256 = @as([]const u8, &hex) }, .{});
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try self.path("components/cache-plan.json"), .data = manifest });
    }

    fn run(self: *CacheProject, relative: []const u8, extra: []const []const u8) !std.process.RunResult {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(self.arena, &.{ options.core_path, "test", try self.path(relative), "--json", "--cache-dir", try self.path("cache") });
        try argv.appendSlice(self.arena, extra);
        return std.process.run(self.arena, std.testing.io, .{ .argv = argv.items, .environ_map = &self.environment });
    }
};

const cache_source =
    \\func helper() -> int:
    \\    return 1
    \\
    \\
    \\func test_dependent() -> bool:
    \\    return helper() > 0
    \\
    \\
    \\func test_unrelated() -> bool:
    \\    return True
    \\
;

fn cacheReport(a: std.mem.Allocator, result: std.process.RunResult) !std.json.Value {
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
}

fn cacheExplanation(value: std.json.Value, name: []const u8) !std.json.Value {
    for (value.object.get("tests").?.array.items) |item| {
        if (std.mem.endsWith(u8, item.object.get("name").?.string, name)) return item.object.get("cache").?;
    }
    return error.MissingTestExplanation;
}

// spec: SELFHOST-CACHE-REPORT-1
// spec-case: SELFHOST-CACHE-PLAN-1
// spec-case: NEW-CORE-TEST-FACTS-1
test "cache planner cacheExplanation reuses unrelated tests after a helper edit and explains current invocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = cache_source });
    const cold = try cacheReport(a, try project.run("app.my", &.{}));
    try expectVerdict(cold, "app::test_dependent", "passed", "");
    try std.testing.expectError(error.MissingTestExplanation, cacheExplanation(cold, "missing test"));
    const warm = try cacheReport(a, try project.run("app.my", &.{}));
    try std.testing.expectEqual(@as(i64, 0), warm.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 2), warm.object.get("cached").?.integer);
    try std.testing.expectEqualStrings("whole-report-hit", (try cacheExplanation(warm, "test_dependent")).object.get("reason").?.string);
    const edited = try a.dupe(u8, cache_source);
    edited[std.mem.indexOf(u8, edited, "return 1").? + "return ".len] = '2';
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = edited });
    const changed = try cacheReport(a, try project.run("app.my", &.{}));
    try expectVerdict(changed, "app::test_dependent", "passed", "");
    try expectVerdict(changed, "app::test_unrelated", "cached", "");
    try std.testing.expectEqualStrings("execute", (try cacheExplanation(changed, "test_dependent")).object.get("action").?.string);
    try std.testing.expectEqualStrings("reuse", (try cacheExplanation(changed, "test_unrelated")).object.get("action").?.string);
    try qualifyDirectoryNamespaces(&project, temporary.dir);
}

fn keyNamespace(project: CacheProject, source: []const u8) ![]const u8 {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, try project.path(source), project.arena);
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(absolute, &digest, .{});
    return project.path(try std.fs.path.join(project.arena, &.{ "cache/test-keys", &std.fmt.bytesToHex(digest, .lower), "stages-packed-v1" }));
}

fn namespaceSequence(project: CacheProject, source: []const u8) ![]const u8 {
    const path = try std.fs.path.join(project.arena, &.{ try keyNamespace(project, source), "sequence" });
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, project.arena, .limited(64));
}

fn damageNamespace(project: CacheProject, source: []const u8) !void {
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, try keyNamespace(project, source), .{ .iterate = true });
    defer directory.close(std.testing.io);
    var entries = directory.iterate();
    var damaged: usize = 0;
    while (try entries.next(std.testing.io)) |item| {
        if (!std.mem.endsWith(u8, item.name, ".pack")) continue;
        try directory.writeFile(std.testing.io, .{ .sub_path = item.name, .data = "damaged namespace pack" });
        damaged += 1;
    }
    try std.testing.expect(damaged != 0);
}

fn qualifyDirectoryNamespaces(project: *CacheProject, directory: std.Io.Dir) !void {
    const left = "tests/left.my";
    const right = "tests/right.my";
    const jobs: []const []const u8 = &.{"--jobs=1"};
    try directory.createDir(std.testing.io, "tests", .default_dir);
    try directory.writeFile(std.testing.io, .{ .sub_path = left, .data = cache_source });
    try directory.writeFile(std.testing.io, .{ .sub_path = right, .data = cache_source });
    const cold = try cacheReport(project.arena, try project.run("tests", jobs));
    try std.testing.expectEqual(@as(i64, 4), cold.object.get("passed").?.integer);
    const left_before = try namespaceSequence(project.*, left);
    const right_before = try namespaceSequence(project.*, right);
    try std.testing.expectEqual(@as(usize, 48), left_before.len);
    try std.testing.expectEqual(@as(usize, 48), right_before.len);
    try std.testing.expect(!std.mem.eql(u8, try keyNamespace(project.*, left), try keyNamespace(project.*, right)));
    const edited = try project.arena.dupe(u8, cache_source);
    const literal = std.mem.indexOf(u8, edited, "return 1").? + "return ".len;
    edited[literal] = '2';
    try directory.writeFile(std.testing.io, .{ .sub_path = left, .data = edited });
    const changed = try cacheReport(project.arena, try project.run("tests", jobs));
    try expectVerdict(changed, "left::test_dependent", "passed", "");
    try expectVerdict(changed, "right::test_dependent", "cached", "");
    try std.testing.expect(!std.mem.eql(u8, left_before, try namespaceSequence(project.*, left)));
    try std.testing.expectEqualSlices(u8, right_before, try namespaceSequence(project.*, right));
    const left_after = try namespaceSequence(project.*, left);
    try damageNamespace(project.*, right);
    edited[literal] = '0';
    try directory.writeFile(std.testing.io, .{ .sub_path = right, .data = edited });
    const damaged = try project.run("tests", jobs);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, damaged.term);
    const repaired = try std.json.parseFromSliceLeaky(std.json.Value, project.arena, damaged.stdout, .{});
    try expectVerdict(repaired, "right::test_dependent", "failed", "expected true, got false");
    try expectVerdict(repaired, "left::test_dependent", "cached", "");
    try std.testing.expectEqualSlices(u8, left_after, try namespaceSequence(project.*, left));
}

// spec: SELFHOST-CACHE-IDENTITY-1
// spec-case: SELFHOST-CACHE-REPORT-1
test "bindPlan and sharedKeys ComponentUnavailable prevent warm file and directory replay with changed missing or corrupt cache planner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.createDir(std.testing.io, "tests", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.my", .data = cache_source });
    _ = try cacheReport(a, try project.run("tests/app.my", &.{}));
    const warm = try cacheReport(a, try project.run("tests", &.{}));
    try std.testing.expectEqual(@as(i64, 2), warm.object.get("cached").?.integer);
    const binary = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try project.path("components/cache-plan"), a, .limited(64 << 20));
    // ELF permits trailing bytes: same behavior, independently changed implementation identity.
    try project.deploy(try std.mem.concat(a, u8, &.{ binary, "\nidentity-only-qualification\n" }));
    const changed = try cacheReport(a, try project.run("tests", &.{}));
    try std.testing.expectEqual(@as(i64, 2), changed.object.get("passed").?.integer);
    const before = (try cacheExplanation(warm, "test_dependent")).object.get("component").?.string;
    const after = (try cacheExplanation(changed, "test_dependent")).object.get("component").?.string;
    try std.testing.expect(!std.mem.eql(u8, before, after));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "components/cache-plan.json", .data = "broken manifest" });
    for ([_][]const u8{ "tests/app.my", "tests" }) |path| {
        const damaged = try project.run(path, &.{});
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, damaged.term);
        try std.testing.expect(std.mem.indexOf(u8, damaged.stderr, "ComponentManifest") != null);
    }
    try temporary.dir.deleteFile(std.testing.io, "components/cache-plan.json");
    const missing = try project.run("tests/app.my", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try std.testing.expect(std.mem.indexOf(u8, missing.stderr, "ComponentMissing") != null);
    try project.deploy("#!/bin/sh\nexit 1\n");
    const failed = try project.run("tests/app.my", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, failed.term);
    try std.testing.expect(std.mem.indexOf(u8, failed.stderr, "ComponentFailed") != null);
}

const WarningReport = struct { value: std.json.Value, warnings: []const u8 };

/// Check execution or replay counts and retain the exact observable warning bytes.
fn allocationWarningReport(project: *CacheProject, path: []const u8, extra: []const []const u8, cached: bool) !WarningReport {
    const result = try project.run(path, extra);
    const value = try cacheReport(project.arena, result);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "warning[W_NOALLOC_ALLOCATES]"));
    try std.testing.expectEqual(@as(i64, @intFromBool(!cached)), value.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, @intFromBool(cached)), value.object.get("cached").?.integer);
    try std.testing.expectEqual(@as(usize, 1), value.object.get("tests").?.array.items.len);
    const explanation = try cacheExplanation(value, "test_one");
    try std.testing.expectEqualStrings(if (cached) "reuse" else "execute", explanation.object.get("action").?.string);
    return .{ .value = value, .warnings = result.stderr };
}

// spec-case: FRONTEND-CORE-NOALLOC-1
// spec-case: SELFHOST-CACHE-IDENTITY-1
// spec-case: SELFHOST-CACHE-REPORT-1
test "allocation warnings survive cold file and directory replay with a planner-only identity change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.createDir(std.testing.io, "tests", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.my", .data = "func bounded() -> int noalloc:\n    const xs = [1]\n    return len(xs)\npublic func test_one() -> bool:\n    return bounded() == 1\n" });
    const cold = try allocationWarningReport(&project, "tests/app.my", &.{}, false);
    const file_replay = try allocationWarningReport(&project, "tests/app.my", &.{}, true);
    const directory_replay = try allocationWarningReport(&project, "tests", &.{"--jobs=1"}, true);
    try std.testing.expectEqualStrings(cold.warnings, file_replay.warnings);
    try std.testing.expectEqualStrings(cold.warnings, directory_replay.warnings);
    const directory_cold = try allocationWarningReport(&project, "tests", &.{ "--jobs=1", "--force" }, false);
    try std.testing.expectEqualStrings(cold.warnings, directory_cold.warnings);

    const binary = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try project.path("components/cache-plan"), a, .limited(64 << 20));
    // Trailing ELF bytes preserve behavior while changing only the planner artifact.
    try project.deploy(try std.mem.concat(a, u8, &.{ binary, "\nallocation-warning-identity-only\n" }));
    const changed = try allocationWarningReport(&project, "tests/app.my", &.{}, false);
    const changed_file_replay = try allocationWarningReport(&project, "tests/app.my", &.{}, true);
    const changed_directory_replay = try allocationWarningReport(&project, "tests", &.{"--jobs=1"}, true);
    const changed_directory_cold = try allocationWarningReport(&project, "tests", &.{ "--jobs=1", "--force" }, false);
    try std.testing.expectEqualStrings(cold.warnings, changed.warnings);
    try std.testing.expectEqualStrings(cold.warnings, changed_file_replay.warnings);
    try std.testing.expectEqualStrings(cold.warnings, changed_directory_replay.warnings);
    try std.testing.expectEqualStrings(cold.warnings, changed_directory_cold.warnings);
    const before = (try cacheExplanation(file_replay.value, "test_one")).object.get("component").?.string;
    const after = (try cacheExplanation(changed.value, "test_one")).object.get("component").?.string;
    try std.testing.expect(!std.mem.eql(u8, before, after));
    try std.testing.expectEqualStrings(after, (try cacheExplanation(changed_file_replay.value, "test_one")).object.get("component").?.string);
    try std.testing.expectEqualStrings(after, (try cacheExplanation(changed_directory_replay.value, "test_one")).object.get("component").?.string);
}

const callback_cache_source =
    \\const NUMBER: int = 3
    \\
    \\func helper() -> int:
    \\    return 1
    \\
    \\func choose() -> func() -> int:
    \\    return helper
    \\
    \\func test_callback() -> bool:
    \\    mut callback = choose()
    \\    return callback() > 0
    \\
    \\func test_constant() -> bool:
    \\    return NUMBER > 0
    \\
    \\func test_unrelated() -> bool:
    \\    return True
    \\
;

// spec-case: SELFHOST-CACHE-PLAN-1
// spec-case: SELFHOST-CACHE-IDENTITY-1
test "sharedFacts eagerFacts and deriveLegacy qualify reference shadow and component modes with callback constants and discovery edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    var previous_identity: []const u8 = "";
    for ([_][]const u8{ "reference", "shadow", "component" }) |mode| {
        try project.environment.put("MYLANG_CACHE_PLAN_MODE", mode);
        const identity = try qualifyCallbacks(&project, temporary.dir);
        try std.testing.expect(!std.mem.eql(u8, previous_identity, identity));
        previous_identity = identity;
    }
}

fn qualifyCallbacks(project: *CacheProject, directory: std.Io.Dir) ![]const u8 {
    const a = project.arena;
    const source = try a.dupe(u8, callback_cache_source);
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = source });
    const cold = try cacheReport(a, try project.run("app.my", &.{}));
    try std.testing.expectEqual(@as(i64, 3), cold.object.get("passed").?.integer);
    const identity = (try cacheExplanation(cold, "test_callback")).object.get("component").?.string;
    const warm = try cacheReport(a, try project.run("app.my", &.{}));
    try std.testing.expectEqual(@as(i64, 3), warm.object.get("cached").?.integer);
    source[std.mem.indexOf(u8, source, "return 1").? + "return ".len] = '2';
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = source });
    const callback = try cacheReport(a, try project.run("app.my", &.{}));
    try expectVerdict(callback, "app::test_callback", "passed", "");
    try expectVerdict(callback, "app::test_constant", "cached", "");
    try expectVerdict(callback, "app::test_unrelated", "cached", "");
    source[std.mem.indexOf(u8, source, "int = 3").? + "int = ".len] = '4';
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = source });
    const constant = try cacheReport(a, try project.run("app.my", &.{}));
    try expectVerdict(constant, "app::test_constant", "passed", "");
    try expectVerdict(constant, "app::test_callback", "cached", "");
    try expectVerdict(constant, "app::test_unrelated", "cached", "");
    const added = try std.mem.concat(a, u8, &.{ source, "\nfunc test_new() -> bool:\n    return True\n" });
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = added });
    const discovery = try cacheReport(a, try project.run("app.my", &.{}));
    try expectVerdict(discovery, "app::test_new", "passed", "");
    try std.testing.expectEqual(@as(i64, 3), discovery.object.get("cached").?.integer);
    return identity;
}
