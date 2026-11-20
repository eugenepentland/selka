//! Tests of `selka-core test`: discovery, the dispatching entry, the report and the
//! command itself on `test/core/runner_cases.selka`, whose tests cover every verdict.
const std = @import("std");
const language = @import("selka");
const options = @import("core_test_options");
const support = @import("test_support.zig");
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
    \\func test_private_result() -> bool fails str:
    \\    return True
    \\
    \\
    \\@test
    \\func marked_result() -> bool fails str:
    \\    return True
    \\
    \\
    \\public func test_stream_stand_in(err: Stream) -> bool:
    \\    print(err, 1)
    \\    return True
    \\
    \\
    \\func helper() -> bool:
    \\    return True
    \\
;

fn discovered(arena: std.mem.Allocator) ![]discover.Case {
    var unit = try language.Compilation.init(arena, "found.selka", discovery_source ++ runner.check_stub);
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
    \\    print(out, 2)
    \\    return True
    \\
;

// spec: NEW-CORE-TEST-2
test "the dispatching entry parses argv[0] as a test index and calls that test, one process per test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "two.selka", two_tests ++ runner.check_stub);
    try unit.check();
    var refusal: build.Refusal = .{};
    const roots = [_]@import("selka").typed.FunctionId{ unit.program.?.functions[0].id, unit.program.?.functions[1].id };
    var module = try build.buildRoots(a, unit.program.?, &roots, &refusal);
    try entry.addEntry(a, &module, &.{ .{ .function = 0 }, .{ .function = 1, .streams = &.{1} } });
    const text = try print.module(a, &module);
    try std.testing.expect(std.mem.indexOf(u8, text, "fn __test_main(") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call bool test_first()") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call bool test_second(1:cap)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ret 64:i64") != null);
    const context: u8 = 0;
    const llvm = try emit_llvm.emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = lineOne }, .source_path = "two.selka", .main = .{} });
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call ptr @myl_core_args(i32 %argc, ptr %argv)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i32 @myl_core_exit(i64 %r)") != null);
}

fn lineOne(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

const verdicts = [_]report.Verdict{
    .{ .name = "m::test_a", .status = .passed },
    .{ .name = "m::test_b", .status = .failed, .reason = "R_LIST_BOUNDS (index 7, length 3)\n  in get at m.selka:2:12\n" },
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
        \\  in get at m.selka:2:12
        \\unsupported m::test_c: E_CORE_UNSUPPORTED (dict type) at 17:13
        \\1 passed, 0 cached, 1 failed, 0 skipped, 1 unsupported (not built, so not run: the run fails)
        \\
    , text);
    const clean = try report.text(arena.allocator(), verdicts[0..1]);
    try std.testing.expectEqualStrings("passed m::test_a\n1 passed, 0 cached, 0 failed, 0 skipped\n", clean);
}

// spec: NEW-CORE-TEST-3
test "a test that returned false carries one line of advice in the text and a field in the JSON, and no other verdict does (FR19)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const advised = [_]report.Verdict{
        .{ .name = "m::test_flag", .status = .failed, .reason = "expected true, got false", .details = .{ .advice = report.false_advice } },
        .{ .name = "m::test_assert", .status = .failed, .reason = "R_ASSERT: n == 4 (left 3, right 4)" },
    };
    const text = try report.text(arena.allocator(), &advised);
    try std.testing.expectEqualStrings(
        "failed m::test_flag: expected true, got false\n" ++
            "  advice: " ++ report.false_advice ++ "\n" ++
            "failed m::test_assert: R_ASSERT: n == 4 (left 3, right 4)\n" ++
            "0 passed, 0 cached, 2 failed, 0 skipped\n",
        text,
    );
    const json = try report.json(arena.allocator(), &advised);
    // The field follows the reason, which keeps its own text; the verdict without advice has no such field.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"reason\":\"expected true, got false\",\"advice\":\"this test returned false") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, json, "\"advice\""));
}

// spec-case: NEW-CORE-TEST-3
// spec-case: NEW-CORE-S5-TEST-STATUS-1
test "the JSON report keys tests by name, status and reason, and the exit status is 0, 1 or 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try report.json(arena.allocator(), &verdicts);
    try std.testing.expect(std.mem.indexOf(u8, text, "{\"name\":\"m::test_c\",\"status\":\"unsupported\",\"reason\":\"dict type\",\"at\":\"17:13\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"reason\":\"R_LIST_BOUNDS (index 7, length 3)\\n  in get at m.selka:2:12\\n\"") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, "\"passed\":1,\"failed\":1,\"skipped\":0,\"cached\":0,\"unsupported\":1,\"exec_receipts\":{\"hits\":0,\"saves\":0},\"result\":\"failed\"}\n"));
    try std.testing.expectEqual(@as(u8, 1), report.exitStatus(&verdicts));
    try std.testing.expectEqual(@as(u8, 0), report.exitStatus(verdicts[0..1]));
    // FX10: a test the core could not build did not run, so it fails the run as a failed test does.
    try std.testing.expectEqual(@as(u8, 1), report.exitStatus(verdicts[2..3]));
    try std.testing.expectEqual(@as(u8, 3), report.exitStatus(&.{}));
    const skipped = [_]report.Verdict{ .{ .name = "m::test_d", .status = .skipped, .reason = "later" }, .{ .name = "m::test_e", .status = .skipped, .reason = "later" } };
    try std.testing.expectEqual(@as(u8, 3), report.exitStatus(&skipped));
    try std.testing.expectEqual(@as(u8, 0), report.exitStatus(&.{ skipped[0], verdicts[0] }));
}

/// One run of `selka-core test` on a fixture: exit status and the parsed `--json` report.
const Run = struct { status: u8, parsed: std.json.Parsed(std.json.Value) };

fn runTest(arena: std.mem.Allocator, root: []const u8, fixture: []const u8, extra: []const []const u8) !Run {
    try support.requireReleaseArgs(extra);
    var argv: std.ArrayList([]const u8) = .empty;
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ options.fixtures, fixture });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    try argv.appendSlice(arena, &.{ options.corePath(), "test", source, "--json", "--cache-dir", cache });
    try argv.appendSlice(arena, extra);
    // The graded verdicts are fresh runs: no shared receipt may answer them.
    var environment = try options.privateEnvironment(arena);
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
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

/// Whether the test named `name` of a report carries the `advice` field, and, when it does, that it is the one sentence and that
/// the `reason` keeps its own text without it (FR19).
fn expectAdvice(parsed: std.json.Value, name: []const u8, present: bool) !void {
    var reported = false;
    for (parsed.object.get("tests").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("name").?.string, name)) continue;
        const advice = item.object.get("advice");
        try std.testing.expectEqual(present, advice != null);
        if (advice) |text| {
            try std.testing.expectEqualStrings(report.false_advice, text.string);
            try std.testing.expect(std.mem.indexOf(u8, item.object.get("reason").?.string, "advice") == null);
        }
        reported = true;
    }
    try std.testing.expect(reported);
}

fn expectEveryVerdict(parsed: std.json.Value) !void {
    // Only the test that returned false is advised; a trap and a passing test are not.
    try expectAdvice(parsed, "runner_cases::test_false_verdict_fails", true);
    try expectAdvice(parsed, "runner_cases::test_bounds_trap", false);
    try expectAdvice(parsed, "runner_cases::test_loop_sum_passes", false);
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
    try expectEveryVerdict(debug.parsed.value);
    try std.testing.expectEqual(@as(u8, 1), debug.status);
    try std.testing.expectEqual(@as(i64, 6), debug.parsed.value.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 4), debug.parsed.value.object.get("failed").?.integer);
    try std.testing.expectEqual(@as(i64, 0), debug.parsed.value.object.get("unsupported").?.integer);
    const release = try runTest(arena.allocator(), root, "runner_cases", &.{"--release"});
    try expectEveryVerdict(release.parsed.value);
    try std.testing.expectEqual(@as(u8, 1), release.status);
}

// spec-case: NEW-CORE-TEST-4
test "a failing assert of a comparison names the values it compared, and a passing one changes nothing (F-18)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const run = try runTest(arena.allocator(), root, "assert_operands", &.{});
    const parsed = run.parsed.value;
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try expectVerdict(parsed, "assert_operands::test_ints", "failed", "R_ASSERT: n == 4 (left 3, right 4)");
    // A failed assert says where and what already: no advice (FR19).
    try expectAdvice(parsed, "assert_operands::test_ints", false);
    try expectVerdict(parsed, "assert_operands::test_text_with_message", "failed", "R_ASSERT: the generated module (left \"a\\nb \\\"c\\\"\", right \"abd\")");
    try expectVerdict(parsed, "assert_operands::test_text_from_a_call", "failed", "R_ASSERT: label(2) == \"item 3\" (left \"item 2\", right \"item 3\")");
    try expectVerdict(parsed, "assert_operands::test_float_greater", "failed", "R_ASSERT: x > y (left 1.5, right 2.5)");
    try expectVerdict(parsed, "assert_operands::test_unsigned", "failed", "R_ASSERT: big < 1 (left 18446744073709551615, right 1)");
    try expectVerdict(parsed, "assert_operands::test_long_text", "failed", "R_ASSERT: long == \"y\" (left \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"... (300 octets), right \"y\")");
    try expectVerdict(parsed, "assert_operands::test_bool_names_no_values", "failed", "R_ASSERT: flag == True\n");
    try expectVerdict(parsed, "assert_operands::test_record_names_no_values", "failed", "R_ASSERT: p == q\n");
    try expectVerdict(parsed, "assert_operands::test_passes", "passed", "");
}

// spec-case: NEW-CORE-TEST-4
test "a bool test that returns one failing comparison names the values it compared and the line, and any other false keeps its advice (R3-TESTMSG)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const run = try runTest(arena.allocator(), root, "returned_comparison", &.{});
    const parsed = run.parsed.value;
    try std.testing.expectEqual(@as(u8, 1), run.status);
    const head = "expected true, got false\n  returned comparison: ";
    try expectVerdict(parsed, "returned_comparison::test_ints", "failed", head ++ "left 6, right 5\n  in returned_comparison::test_ints at returned_comparison.selka:24:12");
    // The values and the line are the report: no advice to write one `assert` for each fact (FR19).
    try expectAdvice(parsed, "returned_comparison::test_ints", false);
    try expectVerdict(parsed, "returned_comparison::test_text_from_a_call", "failed", head ++ "left \"item 2\", right \"item 3\"\n  in returned_comparison::test_text_from_a_call at returned_comparison.selka:28:12");
    try expectVerdict(parsed, "returned_comparison::test_float_greater", "failed", head ++ "left 1.5, right 2.5\n  in returned_comparison::test_float_greater at returned_comparison.selka:34:12");
    try expectVerdict(parsed, "returned_comparison::test_unsigned", "failed", head ++ "left 18446744073709551615, right 1");
    try expectVerdict(parsed, "returned_comparison::test_long_text", "failed", head ++ "left \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"... (300 octets), right \"y\"");
    // Operands the runtime does not print, and a false that is not one comparison, are reported as before.
    try expectVerdict(parsed, "returned_comparison::test_bool_names_no_values", "failed", "expected true, got false");
    try expectAdvice(parsed, "returned_comparison::test_bool_names_no_values", true);
    try expectVerdict(parsed, "returned_comparison::test_record_names_no_values", "failed", "expected true, got false");
    try expectAdvice(parsed, "returned_comparison::test_record_names_no_values", true);
    try expectVerdict(parsed, "returned_comparison::test_two_facts", "failed", "expected true, got false");
    try expectAdvice(parsed, "returned_comparison::test_two_facts", true);
    try expectVerdict(parsed, "returned_comparison::test_passes", "passed", "");
    try expectVerdict(parsed, "returned_comparison::test_passes_with_text", "passed", "");
}

// spec-case: SHARED-STORE-4
test "a private test environment disables both shared stores even where the default switch would choose them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var home = std.testing.tmpDir(.{});
    defer home.cleanup();
    var environment = try options.privateEnvironment(a);
    try std.testing.expectEqualStrings("", environment.get("SELKA_COMPILER_SHARED_CACHE").?);
    try std.testing.expectEqualStrings("", environment.get("SELKA_TEST_SHARED_CACHE").?);
    try environment.put("HOME", try home.dir.realPathFileAlloc(std.testing.io, ".", a));
    const policy = language.shared_cache_policy;
    try std.testing.expectEqual(@as(?policy.Selection, null), try policy.resolveWith(a, &environment, .compiler, null, true));
    try std.testing.expectEqual(@as(?policy.Selection, null), try policy.resolveWith(a, &environment, .tests, null, true));
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

// spec-case: NEW-CORE-TEST-4
test "FR-419 the test filesystem's root is `\".\"`, so a test can list it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const run = try runTest(arena.allocator(), root, "runner_fs_root", &.{});
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqual(@as(i64, 3), run.parsed.value.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 0), run.parsed.value.object.get("failed").?.integer);
    try expectVerdict(run.parsed.value, "runner_fs_root::test_the_test_filesystem_root_is_dot", "passed", "");
    try expectVerdict(run.parsed.value, "runner_fs_root::test_dot_names_the_same_root_as_the_empty_path", "passed", "");
    try expectVerdict(run.parsed.value, "runner_fs_root::test_reading_the_root_names_a_directory_not_a_grant", "passed", "");
}

// spec-case: NEW-CORE-TEST-4
test "FR-418 a text value keeps one quoting rule bare and nested in Ok, Err, a record and a list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const run = try runTest(arena.allocator(), root, "runner_quote_rule", &.{});
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqual(@as(i64, 4), run.parsed.value.object.get("passed").?.integer);
    try expectVerdict(run.parsed.value, "runner_quote_rule::nested.example", "passed", "");
    try expectVerdict(run.parsed.value, "runner_quote_rule::bare.example", "passed", "");
    try expectVerdict(run.parsed.value, "runner_quote_rule::tagged.example", "passed", "");
    try expectVerdict(run.parsed.value, "runner_quote_rule::listed.example", "passed", "");
}

/// A private source, receipt store and component deployment for admission tests.
const CacheProject = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8) !CacheProject {
        // Admission tests count this project's own receipts: no shared store.
        var environment = try options.privateEnvironment(a);
        errdefer environment.deinit();
        try environment.put("SELKA_CACHE_PLAN_MODE", "component");
        const artifact = try language.cache_plan_adapter.bind(a, std.testing.io, &environment);
        const contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, artifact.artifact.?.path, a, .limited(64 << 20));

        const directory = try std.fs.path.join(a, &.{ root, "components" });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, directory);
        try environment.put("SELKA_COMPONENT_DIR", directory);
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
        try argv.appendSlice(self.arena, &.{ options.corePath(), "test", try self.path(relative), "--json", "--cache-dir", try self.path("cache") });
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

const callback_short_name = "test_callback";
const callback_qualified_name = "app::test_callback";
const execution_key_field = "execution_key";

fn cacheExplanation(value: std.json.Value, name: []const u8) !std.json.Value {
    for (value.object.get("tests").?.array.items) |item| {
        if (std.mem.endsWith(u8, item.object.get("name").?.string, name)) return item.object.get("cache").?;
    }
    return error.MissingTestExplanation;
}

/// An IR edit can preserve the optimized executable. Prove the IR key missed
/// while the exact program key still authorizes execution-tier success reuse.
fn expectExecutionAfterIrEdit(before: std.json.Value, after: std.json.Value, name: []const u8) !void {
    try expectVerdict(after, name, "cached", "");
    const previous = (try cacheExplanation(before, name)).object;
    const current = (try cacheExplanation(after, name)).object;
    try std.testing.expectEqualStrings("reuse", current.get("action").?.string);
    try std.testing.expectEqualStrings("engine-program-hit", current.get("reason").?.string);
    try std.testing.expect(!std.mem.eql(u8, previous.get("key").?.string, current.get("key").?.string));
    try std.testing.expectEqualStrings(previous.get(execution_key_field).?.string, current.get(execution_key_field).?.string);
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = cache_source });
    // The receipt property below is an LLVM -O2 property (LLVM folds the two constants to
    // the same code). The -O0 default keeps the constant, so the program bytes change.
    const optimized = &.{"--optimize-debug"};
    const cold = try cacheReport(a, try project.run("app.selka", optimized));
    try expectVerdict(cold, "app::test_dependent", "passed", "");
    try std.testing.expectError(error.MissingTestExplanation, cacheExplanation(cold, "missing test"));
    const warm = try cacheReport(a, try project.run("app.selka", optimized));
    try std.testing.expectEqual(@as(i64, 0), warm.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 2), warm.object.get("cached").?.integer);
    try std.testing.expectEqualStrings("engine-report-hit", (try cacheExplanation(warm, "test_dependent")).object.get("reason").?.string);
    const edited = try a.dupe(u8, cache_source);
    edited[std.mem.indexOf(u8, edited, "return 1").? + "return ".len] = '2';
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = edited });
    const changed = try cacheReport(a, try project.run("app.selka", optimized));
    // Both positive helper constants fold to True. The IR key changes, while
    // stable dispatch membership preserves the program's execution receipt.
    try expectExecutionAfterIrEdit(cold, changed, "app::test_dependent");
    try expectVerdict(changed, "app::test_unrelated", "cached", "");
    try std.testing.expectEqualStrings("reuse", (try cacheExplanation(changed, "test_unrelated")).object.get("action").?.string);
    try qualifyDirectoryNamespaces(&project, temporary.dir);
}

// spec: D-48
test "the engine never serves a stale pass: a test an edit breaks runs and fails, and the unedited source is served again" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = cache_source });
    const cold = try cacheReport(a, try project.run("app.selka", &.{}));
    try expectVerdict(cold, "app::test_dependent", "passed", "");
    // The helper now returns a value the test rejects. The record of the pass exists, and is not what the run asks for: the
    // key of this check is another key.
    const broken = try a.dupe(u8, cache_source);
    broken[std.mem.indexOf(u8, broken, "return 1").? + "return ".len] = '0';
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = broken });
    const failing = try project.run("app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, failing.term);
    const report_after_edit = try std.json.parseFromSliceLeaky(std.json.Value, a, failing.stdout, .{});
    try expectVerdict(report_after_edit, "app::test_dependent", "failed", "");
    try expectVerdict(report_after_edit, "app::test_unrelated", "cached", "");
    try std.testing.expectEqualStrings("engine-hit", (try cacheExplanation(report_after_edit, "test_unrelated")).object.get("reason").?.string);
    // A failure is never recorded, so it runs again.
    const again = try project.run("app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, again.term);
    try expectVerdict(try std.json.parseFromSliceLeaky(std.json.Value, a, again.stdout, .{}), "app::test_dependent", "failed", "");
    // The source as it was: the pass recorded under its key is served again, with the engine's reason.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = cache_source });
    const restored = try cacheReport(a, try project.run("app.selka", &.{}));
    try expectVerdict(restored, "app::test_dependent", "cached", "");
    try std.testing.expectEqualStrings("engine-report-hit", (try cacheExplanation(restored, "test_dependent")).object.get("reason").?.string);
}

const engine_record = @import("engine/record.zig");
const engine_digest = @import("engine/digest.zig");
const engine_store = @import("engine/store.zig");

/// The first `test-exec` record under `store_root` whose argument ends with `suffix` (the test's name) and starts with `tag`,
/// decoded.
fn recordNamed(a: std.mem.Allocator, store_root: []const u8, tag: u8, suffix: []const u8) !engine_record.Record {
    const kind_root = try std.fmt.allocPrint(a, "{s}/records/test-exec", .{store_root});
    var kind_dir = try std.Io.Dir.cwd().openDir(std.testing.io, kind_root, .{ .iterate = true });
    defer kind_dir.close(std.testing.io);
    var identities = kind_dir.iterate();
    while (try identities.next(std.testing.io)) |identity| {
        if (identity.kind != .directory) continue;
        const identity_root = try std.fmt.allocPrint(a, "{s}/{s}", .{ kind_root, identity.name });
        var identity_dir = try std.Io.Dir.cwd().openDir(std.testing.io, identity_root, .{ .iterate = true });
        defer identity_dir.close(std.testing.io);
        var shards = identity_dir.iterate();
        while (try shards.next(std.testing.io)) |shard| {
            if (shard.kind != .directory) continue;
            const shard_root = try std.fmt.allocPrint(a, "{s}/{s}", .{ identity_root, shard.name });
            var shard_dir = try std.Io.Dir.cwd().openDir(std.testing.io, shard_root, .{ .iterate = true });
            defer shard_dir.close(std.testing.io);
            var files = shard_dir.iterate();
            while (try files.next(std.testing.io)) |file| {
                if (file.kind != .file) continue;
                const bytes = try shard_dir.readFileAlloc(std.testing.io, file.name, a, .limited(1 << 20));
                const found = engine_record.decode(a, bytes) catch continue;
                if (found.argument.len > 0 and found.argument[0] == tag and std.mem.endsWith(u8, found.argument, suffix)) return found;
            }
        }
    }
    return error.NoSuchRecord;
}

// spec: C2c1b
test "a served record that the check finds wrong is forgotten, and the next run runs the test instead of serving it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var project = try CacheProject.init(a, root);
    const log = try std.fmt.allocPrint(a, "{s}/engine.jsonl", .{root});
    try project.environment.put("SELKA_ENGINE_SHADOW_LOG", log);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = cache_source });
    const cold = try cacheReport(a, try project.run("app.selka", &.{}));
    try expectVerdict(cold, "app::test_dependent", "passed", "");
    // The record of that pass is the template of a wrong one.
    const store_root = try project.path("cache/engine-v1");
    const pass = try recordNamed(a, store_root, 'i', "::test_dependent");
    // The helper now returns a value the test rejects, and the run reports the key of that program.
    const broken = try a.dupe(u8, cache_source);
    broken[std.mem.indexOf(u8, broken, "return 1").? + "return ".len] = '0';
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = broken });
    const failing = try project.run("app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, failing.term);
    const failed_report = try std.json.parseFromSliceLeaky(std.json.Value, a, failing.stdout, .{});
    const key_hex = (try cacheExplanation(failed_report, "test_dependent")).object.get("key").?.string;
    // Seed the wrong record: a pass under the key of the failing program, in the engine's store, as if a run had proved it.
    var seeded_argument = try a.dupe(u8, pass.argument);
    _ = try std.fmt.hexToBytes(seeded_argument[1..33], key_hex);
    const seeded_key = engine_digest.key("test-exec", pass.identity, seeded_argument);
    const seeded = try engine_record.encode(a, .{ .kind = "test-exec", .identity = pass.identity, .key = seeded_key, .argument = seeded_argument, .result = pass.result, .payload = pass.payload, .reads = &.{} });
    const store = engine_store.Store.init(std.testing.io, store_root);
    const record_path = try store.recordPath(a, try store.partition(a, "test-exec", pass.identity), seeded_key);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(record_path).?);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = record_path, .data = seeded });
    // Served unchecked, the wrong record would pass the test. Checked, the test runs, fails, and the record is forgotten.
    try std.Io.Dir.cwd().access(std.testing.io, record_path, .{});
    try project.environment.put("SELKA_ENGINE_VERIFY", "1");
    const checked = try project.run("app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, checked.term);
    const checked_report = try std.json.parseFromSliceLeaky(std.json.Value, a, checked.stdout, .{});
    try expectVerdict(checked_report, "app::test_dependent", "failed", "");
    const lines = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, log, a, .limited(1 << 20));
    try std.testing.expect(std.mem.indexOf(u8, lines, "\"class\":\"verify\"") != null);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, record_path, .{}));
    // The next run, with no check at all, finds nothing to serve and runs the test again.
    _ = project.environment.swapRemove("SELKA_ENGINE_VERIFY");
    const again = try project.run("app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, again.term);
    const again_report = try std.json.parseFromSliceLeaky(std.json.Value, a, again.stdout, .{});
    try expectVerdict(again_report, "app::test_dependent", "failed", "");
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
    const left = "tests/left.selka";
    const right = "tests/right.selka";
    // -O2 for the same reason as the single-file test above (LLVM folds the edited constants).
    const jobs: []const []const u8 = &.{ "--jobs=1", "--optimize-debug" };
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
    try expectExecutionAfterIrEdit(cold, changed, "left::test_dependent");
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
// spec-case: EXEC-RECEIPT-1
test "bindPlan and sharedKeys ComponentUnavailable prevent warm file and directory replay with changed missing or corrupt cache planner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.createDir(std.testing.io, "tests", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.selka", .data = cache_source });
    _ = try cacheReport(a, try project.run("tests/app.selka", &.{}));
    const warm = try cacheReport(a, try project.run("tests", &.{}));
    try std.testing.expectEqual(@as(i64, 2), warm.object.get("cached").?.integer);
    const binary = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try project.path("components/cache-plan"), a, .limited(64 << 20));
    // ELF permits trailing bytes: same behavior, independently changed implementation identity.
    try project.deploy(try std.mem.concat(a, u8, &.{ binary, "\nidentity-only-qualification\n" }));
    // The IR keys miss; the linked program is unchanged, so its execution receipts
    // answer both tests (EXEC-RECEIPT-1).
    const changed = try cacheReport(a, try project.run("tests", &.{}));
    try std.testing.expectEqual(@as(i64, 2), changed.object.get("cached").?.integer);
    try std.testing.expectEqual(@as(i64, 2), changed.object.get("exec_receipts").?.object.get("hits").?.integer);
    const before = (try cacheExplanation(warm, "test_dependent")).object.get("component").?.string;
    const after = (try cacheExplanation(changed, "test_dependent")).object.get("component").?.string;
    try std.testing.expect(!std.mem.eql(u8, before, after));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "components/cache-plan.json", .data = "broken manifest" });
    for ([_][]const u8{ "tests/app.selka", "tests" }) |path| {
        const damaged = try project.run(path, &.{});
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, damaged.term);
        try std.testing.expect(std.mem.indexOf(u8, damaged.stderr, "ComponentManifest") != null);
    }
    try temporary.dir.deleteFile(std.testing.io, "components/cache-plan.json");
    const missing = try project.run("tests/app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try std.testing.expect(std.mem.indexOf(u8, missing.stderr, "ComponentMissing") != null);
    try project.deploy("#!/bin/sh\nexit 1\n");
    const failed = try project.run("tests/app.selka", &.{});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, failed.term);
    try std.testing.expect(std.mem.indexOf(u8, failed.stderr, "ComponentFailed") != null);
}

/// A failed allocation contract cannot execute, replay or publish a successful receipt.
fn allocationFailureReport(project: *CacheProject, path: []const u8, extra: []const []const u8) ![]const u8 {
    const result = try project.run(path, extra);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "error[E_NOALLOC_ALLOCATES]"));
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\":\"passed\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\":\"cached\"") == null);
    if (std.Io.Dir.cwd().openDir(std.testing.io, try project.path("cache/tests"), .{ .iterate = true })) |directory| {
        defer directory.close(std.testing.io);
        var iterator = directory.iterate();
        try std.testing.expect((try iterator.next(std.testing.io)) == null);
    } else |err| try std.testing.expect(err == error.FileNotFound);
    return result.stderr;
}

// spec-case: FRONTEND-CORE-NOALLOC-1
// spec-case: SELFHOST-CACHE-IDENTITY-1
// spec-case: SELFHOST-CACHE-REPORT-1
test "allocation failures publish no receipt across file directory and planner identity retries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.createDir(std.testing.io, "tests", .default_dir);
    // migrate-embedded: skip preserved original effect retirement witness
    const original_source = "func bounded() -> int noalloc:\n    const xs = [1]\n    return len(xs)\npublic func test_one() -> bool:\n    return bounded() == 1\n";
    var original = try language.Compilation.init(a, "warning_before.selka", original_source);
    defer original.deinit();
    try std.testing.expectError(error.SourceError, original.formatModule(a));
    try std.testing.expect(original.diagnostics.items.len > 0);
    try std.testing.expectEqualStrings("E_EFFECTS_REMOVED", original.diagnostics.items[0].code);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.selka", .data =
        \\@noalloc
        \\func bounded() -> int:
        \\    const xs = [1]
        \\    return len(xs)
        \\public func test_one() -> bool:
        \\    return bounded() == 1
        \\
    });
    const cold = try allocationFailureReport(&project, "tests/app.selka", &.{});
    const file_retry = try allocationFailureReport(&project, "tests/app.selka", &.{});
    const directory_retry = try allocationFailureReport(&project, "tests", &.{"--jobs=1"});
    try std.testing.expectEqualStrings(cold, file_retry);
    try std.testing.expectEqualStrings(cold, directory_retry);
    const forced_directory = try allocationFailureReport(&project, "tests", &.{ "--jobs=1", "--force" });
    try std.testing.expectEqualStrings(cold, forced_directory);

    const binary = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try project.path("components/cache-plan"), a, .limited(64 << 20));
    // Trailing ELF bytes preserve behavior while changing only the planner artifact.
    try project.deploy(try std.mem.concat(a, u8, &.{ binary, "\nallocation-failure-identity-only\n" }));
    const changed = try allocationFailureReport(&project, "tests/app.selka", &.{});
    const changed_file_retry = try allocationFailureReport(&project, "tests/app.selka", &.{});
    const changed_directory_retry = try allocationFailureReport(&project, "tests", &.{"--jobs=1"});
    const changed_forced_directory = try allocationFailureReport(&project, "tests", &.{ "--jobs=1", "--force" });
    try std.testing.expectEqualStrings(cold, changed);
    try std.testing.expectEqualStrings(cold, changed_file_retry);
    try std.testing.expectEqualStrings(cold, changed_directory_retry);
    try std.testing.expectEqualStrings(cold, changed_forced_directory);
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
        try project.environment.put("SELKA_CACHE_PLAN_MODE", mode);
        const identity = try qualifyCallbacks(&project, temporary.dir);
        try std.testing.expect(!std.mem.eql(u8, previous_identity, identity));
        previous_identity = identity;
    }
}

fn qualifyCallbacks(project: *CacheProject, directory: std.Io.Dir) ![]const u8 {
    const a = project.arena;
    const source = try a.dupe(u8, callback_cache_source);
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = source });
    const cold = try cacheReport(a, try project.run("app.selka", &.{}));
    try std.testing.expectEqual(@as(i64, 3), cold.object.get("passed").?.integer);
    const identity = (try cacheExplanation(cold, callback_short_name)).object.get("component").?.string;
    // A callback invoked through a local is no live effect: every function value the call tree creates is in the tree, so
    // the test publishes a receipt like any other and the warm run serves all three.
    const warm = try cacheReport(a, try project.run("app.selka", &.{}));
    try std.testing.expectEqual(@as(i64, 3), warm.object.get("cached").?.integer);
    try expectVerdict(warm, callback_qualified_name, "cached", "");
    // Editing the function the callback names changes the test's key: it runs again and passes.
    source[std.mem.indexOf(u8, source, "return 1").? + "return ".len] = '2';
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = source });
    const callback = try cacheReport(a, try project.run("app.selka", &.{}));
    try expectVerdict(callback, callback_qualified_name, "passed", "");
    const rerun = (try cacheExplanation(callback, callback_short_name)).object;
    try std.testing.expectEqualStrings("execute", rerun.get("action").?.string);
    try std.testing.expectEqualStrings("no-success-receipt", rerun.get("reason").?.string);
    try std.testing.expect(rerun.get("key").? != .null);
    try expectVerdict(callback, "app::test_constant", "cached", "");
    try expectVerdict(callback, "app::test_unrelated", "cached", "");
    source[std.mem.indexOf(u8, source, "int = 3").? + "int = ".len] = '4';
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = source });
    const constant = try cacheReport(a, try project.run("app.selka", &.{}));
    try expectExecutionAfterIrEdit(callback, constant, "app::test_constant");
    try expectVerdict(constant, callback_qualified_name, "cached", "");
    try expectVerdict(constant, "app::test_unrelated", "cached", "");
    const added = try std.mem.concat(a, u8, &.{ source, "\nfunc test_new() -> bool:\n    return True\n" });
    try directory.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = added });
    const discovery = try cacheReport(a, try project.run("app.selka", &.{}));
    try expectVerdict(discovery, "app::test_new", "passed", "");
    try std.testing.expectEqual(@as(i64, 3), discovery.object.get("cached").?.integer);
    try expectVerdict(discovery, callback_qualified_name, "cached", "");
    return identity;
}

const digest_receipt_path = "identity.selka";
const digest_test_name = "identity::test_digest";
const digest_test = "test_digest";
const digest_receipt_source =
    \\import strings
    \\func compatible(value: int) -> int:
    \\    _ = str(value)
    \\    return value
    \\
    \\func indirect(callback: func(int) -> int, value: int) -> int:
    \\    return callback(value)
    \\
    \\func test_digest() -> bool:
    \\    return strings.char_count(function_digest(indirect)) == 64
    \\
    \\func test_member() -> bool:
    \\    return compatible(1) == 1
    \\
    \\func test_ordinary() -> bool:
    \\    return True
;

fn digestReceiptReport(project: *CacheProject, extra: []const []const u8, status: u8) !std.json.Value {
    const result = try project.run(digest_receipt_path, extra);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
    return std.json.parseFromSliceLeaky(std.json.Value, project.arena, result.stdout, .{});
}

fn expectDigestFresh(value: std.json.Value, status: []const u8) !void {
    try expectVerdict(value, digest_test_name, status, "");
    const explanation = try cacheExplanation(value, digest_test);
    try std.testing.expectEqualStrings("execute", explanation.object.get("action").?.string);
    try std.testing.expectEqualStrings("uncacheable-metadata", explanation.object.get("reason").?.string);
    try std.testing.expect(explanation.object.get("key").? == .null);
}

/// The digest test has no IR key, but its linked program's bytes carry the digest
/// itself, so an identical program answers it from its execution receipt
/// (EXEC-RECEIPT-1).
fn expectDigestExecutionReuse(value: std.json.Value, reason: []const u8) !void {
    try expectVerdict(value, digest_test_name, "cached", "");
    const explanation = try cacheExplanation(value, digest_test);
    try std.testing.expectEqualStrings("reuse", explanation.object.get("action").?.string);
    try std.testing.expectEqualStrings(reason, explanation.object.get("reason").?.string);
    try std.testing.expect(explanation.object.get("key").? == .null);
}

fn qualifyDigestReceipts(a: std.mem.Allocator, mode: []const u8) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try project.environment.put("SELKA_TEST_KEYS", mode);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = digest_receipt_path, .data = digest_receipt_source });
    try qualifyCompleteDigestReceipts(a, mode);
    const cold = try digestReceiptReport(&project, &.{}, 0);
    try expectUnknownCallableRefused(cold, digest_test_name, digest_test, "passed");
    const warm = try digestReceiptReport(&project, &.{}, 0);
    // Unknown reachable callbacks forbid persistent reuse even for identical programs.
    try expectUnknownCallableRefused(warm, digest_test_name, digest_test, "passed");
    try expectVerdict(warm, "identity::test_member", "cached", "");
    try expectVerdict(warm, "identity::test_ordinary", "cached", "");
    const repeated = try digestReceiptReport(&project, &.{}, 0);
    try expectUnknownCallableRefused(repeated, digest_test_name, digest_test, "passed");
    const changed = try std.mem.replaceOwned(u8, a, digest_receipt_source, "_ = str(value)", "_ = function_digest(compatible)");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = digest_receipt_path, .data = changed });
    const edited = try digestReceiptReport(&project, &.{}, 1);
    try expectUnknownCallableRefused(edited, digest_test_name, digest_test, "failed");
    try expectVerdict(edited, "identity::test_ordinary", "cached", "");
    const forced = try digestReceiptReport(&project, &.{"--force"}, 1);
    try expectVerdict(forced, digest_test_name, "failed", "");
    const forced_cache = (try cacheExplanation(forced, digest_test)).object;
    try std.testing.expectEqualStrings("force", forced_cache.get("reason").?.string);
    try std.testing.expect(forced_cache.get("key").? == .null);
    try std.testing.expect(forced_cache.get(execution_key_field).? == .null);
    // This selection excludes the compatible target that introduced the self-
    // digest dependency. Its narrower program has no prior receipt: ordinary
    // cached members stayed linked in the earlier whole-selection runs.
    const isolated = try digestReceiptReport(&project, &.{ "--filter", digest_test }, 0);
    try expectUnknownCallableRefused(isolated, digest_test_name, digest_test, "passed");
    const isolated_warm = try digestReceiptReport(&project, &.{ "--filter", digest_test }, 0);
    try expectUnknownCallableRefused(isolated_warm, digest_test_name, digest_test, "passed");
    const combined = try digestReceiptReport(&project, &.{}, 1);
    try expectUnknownCallableRefused(combined, digest_test_name, digest_test, "failed");
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest receipt refusal tracks compatible target edits and live batch membership in shared keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualifyDigestReceipts(arena.allocator(), "shared");
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest receipt refusal protects per-test fallback and keeps unrelated receipts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualifyDigestReceipts(arena.allocator(), "per-test");
}

const pool_receipt_path = "sizes.selka";
const pool_receipt_source =
    \\import parallel
    \\
    \\func test_pool() -> bool:
    \\    return parallel.threads() >= 1
    \\
    \\func test_machine() -> bool:
    \\    return parallel.cpus() >= 1
    \\
    \\func test_ordinary() -> bool:
    \\    return True
;

// `--threads` and the machine decide what `parallel.threads` and `parallel.cpus` answer and no key binds either, so a test that
// reads one is run again each time (its reason names the read) while a neighbour that reads neither stays cached.
test "a test that reads parallel.threads or parallel.cpus is never answered from a receipt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = pool_receipt_path, .data = pool_receipt_source });
    for ([_][]const []const u8{ &.{}, &.{}, &.{ "--threads", "3" } }) |extra| {
        const result = try project.run(pool_receipt_path, extra);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        const reported = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
        for ([_][]const u8{ "test_pool", "test_machine" }) |name| {
            const explanation = (try cacheExplanation(reported, name)).object;
            try std.testing.expectEqualStrings("execute", explanation.get("action").?.string);
            try std.testing.expect(std.mem.startsWith(u8, explanation.get("reason").?.string, "live-effects: "));
            try std.testing.expect(std.mem.indexOf(u8, explanation.get("reason").?.string, "reads the thread count or the CPU count") != null);
            try std.testing.expect(explanation.get("key").? == .null);
        }
    }
    const warm = try project.run(pool_receipt_path, &.{});
    const last = try std.json.parseFromSliceLeaky(std.json.Value, a, warm.stdout, .{});
    try expectVerdict(last, "sizes::test_ordinary", "cached", "");
}

/// The `function_digest` test of `digest_receipt_source` is refused with the reason naming `indirect`.
fn expectUnknownCallableRefused(value: std.json.Value, name: []const u8, short_name: []const u8, status: []const u8) !void {
    try expectVerdict(value, name, status, "");
    const explanation = (try cacheExplanation(value, short_name)).object;
    try std.testing.expectEqualStrings("execute", explanation.get("action").?.string);
    // The reason names what stopped the proof: the function that calls a callback beside `function_digest`.
    const reason = explanation.get("reason").?.string;
    try std.testing.expect(std.mem.startsWith(u8, reason, "live-effects: "));
    try std.testing.expect(std.mem.indexOf(u8, reason, "indirect calls a callback beside function_digest") != null);
    try std.testing.expect(explanation.get("key").? == .null);
    try std.testing.expect(explanation.get(execution_key_field).? == .null);
}

// Complete reachability permits execution receipts for callable metadata while
// the IR tier still refuses that metadata. Linked source edits must miss.
fn qualifyCompleteDigestReceipts(a: std.mem.Allocator, mode: []const u8) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try CacheProject.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    try project.environment.put("SELKA_TEST_KEYS", mode);
    const complete = try std.mem.replaceOwned(u8, a, digest_receipt_source, "func indirect(callback: func(int) -> int, value: int) -> int:\n    return callback(value)", "func indirect(value: int) -> int:\n    return compatible(value)");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = digest_receipt_path, .data = complete });
    const cold = try digestReceiptReport(&project, &.{}, 0);
    try expectDigestFresh(cold, "passed");
    const warm = try digestReceiptReport(&project, &.{}, 0);
    try expectDigestExecutionReuse(warm, "engine-program-hit");
    const changed = try std.mem.replaceOwned(u8, a, complete, "return value", "return value + 1");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = digest_receipt_path, .data = changed });
    const edited = try digestReceiptReport(&project, &.{}, 1);
    try expectDigestFresh(edited, "passed");
    const edited_warm = try digestReceiptReport(&project, &.{}, 1);
    try expectDigestExecutionReuse(edited_warm, "engine-program-hit");
    const before = (try cacheExplanation(warm, digest_test)).object;
    const after = (try cacheExplanation(edited_warm, digest_test)).object;
    try std.testing.expect(!std.mem.eql(u8, before.get(execution_key_field).?.string, after.get(execution_key_field).?.string));
}
