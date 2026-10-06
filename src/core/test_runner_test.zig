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
    \\public def test_public_with_a_parameter(x: int) -> bool:
    \\    return x == x
    \\
    \\
    \\def test_private_with_a_parameter(x: int) -> bool:
    \\    return x == x
    \\
    \\
    \\def test_private_zero_arguments() -> bool:
    \\    return True
    \\
    \\
    \\def test_private_result() -> Result[bool, str]:
    \\    return Ok(True)
    \\
    \\
    \\@test
    \\def marked_result() -> Result[bool, str]:
    \\    return Ok(True)
    \\
    \\
    \\public def test_stream_stand_in(err: Stream) -> bool:
    \\    err.print(1)
    \\    return True
    \\
    \\
    \\def helper() -> bool:
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
    \\def test_first() -> bool:
    \\    return 1 + 1 == 2
    \\
    \\
    \\def test_second(out: Stream) -> bool:
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
    try expectVerdict(parsed, "runner_cases::test_property", "unsupported", "test parameters other than Stream");
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
    try std.testing.expectEqual(@as(i64, 5), debug.parsed.value.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 4), debug.parsed.value.object.get("failed").?.integer);
    try std.testing.expectEqual(@as(i64, 1), debug.parsed.value.object.get("unsupported").?.integer);
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
