//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;
const arena_example_path = @import("test_options").arena_example_path;
const host_program = "host fn measure(x:i64)->i64 effects(host);fn main()->i64{return measure(6);}";
test "CLI checks host declarations and reports missing VM registration as a located trap" {
    try invoke("check", host_program, 0, "", "");
    try invoke("run", host_program, 1, "", "error[R_HOST_REGISTRATION]");
    try invokeOptions("run", host_program, &.{"--diagnostics=json"}, 1, "", "\"code\":\"R_HOST_REGISTRATION\"");
}
// spec-case: ARENA-MANAGED-1
test "CLI runs the managed arena example under normal and stress collection" {
    for ([_][]const []const u8{ &.{}, &.{"--gc-stress"} }) |options| {
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(testing.allocator);
        try args.appendSlice(testing.allocator, &.{ compiler_path, "run", arena_example_path });
        try args.appendSlice(testing.allocator, options);
        const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
        try testing.expectEqualStrings("38\n", outcome.stdout);
        try testing.expectEqualStrings("", outcome.stderr);
    }
}
// spec-case: ARENA-MANAGED-4
test "CLI reports managed arena escapes as machine-readable diagnostics" {
    const source =
        \\def main() -> int:
        \\    keeper: list[int] = []
        \\    with arena() as scratch:
        \\        keeper = [1, 2]
        \\    return len(keeper)
    ;
    try invoke("check", source, 1, "", "error[E_ARENA_ESCAPE]");
    try invokeOptions("check", source, &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_ARENA_ESCAPE\"");
}
fn invoke(command: []const u8, text: []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    return invokeOptions(command, text, &.{}, expected_status, expected_stdout, stderr_part);
}
fn invokeOptions(command: []const u8, text: []const u8, options: []const []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    const outcome = try runFixture(command, text, options);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, outcome.term);
    try testing.expectEqualStrings(expected_stdout, outcome.stdout);
    if (stderr_part.len == 0) try testing.expectEqualStrings("", outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}
fn runFixture(command: []const u8, text: []const u8, options: []const []const u8) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, command, path });
    try args.appendSlice(testing.allocator, options);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}
test "CLI run and check success" {
    try invoke("run", @embedFile("fixtures/arithmetic.my"), 0, "7\n", "");
    try invoke("check", @embedFile("fixtures/arithmetic.my"), 0, "", "");
}
// spec: VM-TIMING-1
test "CLI execution timings preserve results and runtime diagnostics" {
    const source = "fn main() -> i64 { return 42; }";
    for ([_][]const u8{ "--dispatch=optimized", "--dispatch=generic" }) |dispatch| {
        const outcome = try runFixture("run", source, &.{ "--timings", dispatch });
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
        try testing.expectEqualStrings("42\n", outcome.stdout);
        const prefix = "timings: bytecode_ns=";
        try testing.expect(std.mem.startsWith(u8, outcome.stderr, prefix));
        _ = try std.fmt.parseInt(u64, std.mem.trim(u8, outcome.stderr[prefix.len..], "\n"), 10);
    }
    try invokeOptions("run", "fn main() -> i64 { return 1 / 0; }", &.{"--timings"}, 1, "", "error[R_DIVISION_BY_ZERO]");
    try invokeOptions("run", source, &.{ "--timings", "--timings" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--timings"}, 2, "", "usage:");
}
test "CLI dumps actual instructions" {
    try invoke("dump-bytecode", @embedFile("fixtures/arithmetic.my"), 0, @embedFile("fixtures/arithmetic.dump"), "");
}
// spec: CLI-1
test "CLI distinguishes source errors runtime traps and Usage errors" {
    try invoke("check", "fn main() -> i64 { return 1 + ; }", 1, "", "error[E_EXPRESSION]");
    try invoke("check", "fn main() -> i64 { return 9223372036854775807 + 1; }", 0, "", "");
    try invoke("run", "fn main() -> i64 { return 9223372036854775807 + 1; }", 1, "", "error[R_OVERFLOW]");
    try invoke("unknown", "", 2, "", "usage:");
}
// spec: CLI-2
test "CLI missing arguments and missing files are host or usage failures" {
    const no_args = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{compiler_path} });
    defer testing.allocator.free(no_args.stdout);
    defer testing.allocator.free(no_args.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_args.term);
    try testing.expectEqualStrings("", no_args.stdout);
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const absolute_compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(absolute_compiler);
    const absent = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ absolute_compiler, "run", "missing.my" },
        .cwd = .{ .dir = temp.dir },
    });
    defer testing.allocator.free(absent.stdout);
    defer testing.allocator.free(absent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, absent.term);
    try testing.expectEqualStrings("", absent.stdout);
    try testing.expect(std.mem.indexOf(u8, absent.stderr, "FileNotFound") != null);
}
test "CLI binding warnings do not alter status or result output" {
    const text = "fn main() -> i64 { let mut x = 7; return x; }";
    try invoke("run", text, 0, "7\n", "warning[W_UNNECESSARY_MUT]");
    try invoke("check", text, 0, "", "warning[W_UNNECESSARY_MUT]");
    try invoke("run", "fn main() -> i64 { let unused = 9223372036854775807 + 1; return 7; }", 1, "", "error[R_OVERFLOW]");
    try invoke("run", "fn main() -> i64 { return -9223372036854775808; }", 0, "-9223372036854775808\n", "");
    try invoke("check", "fn main() -> i64 { let mut x = true; x = 1; return 7; }", 1, "", "error[E_TYPE]");
}
test "CLI step budgets count dispatch and reject invalid options" {
    const text = "fn main() -> i64 { return 1; }";
    try invokeOptions("run", text, &.{"--max-steps=2"}, 0, "1\n", "");
    try invokeOptions("run", text, &.{"--max-steps=1"}, 1, "", "error[R_STEP_LIMIT]");
    try invokeOptions("run", "fn main() -> i64 { while true {} return 1; }", &.{"--max-steps=100"}, 1, "", "error[R_STEP_LIMIT]");
    for ([_][]const u8{ "--max-steps=0", "--max-steps=-1", "--max-steps=+1", "--max-steps=", "--max-steps=abc", "--max-steps=18446744073709551616", "--unknown=1" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-steps=2", "--max-steps=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-steps=2"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", text, &.{"--max-steps=2"}, 2, "", "usage:");
}
// spec: CLI-3
test "CLI executes the exact plan acceptance programs and recursive functions" {
    try invoke("run", @embedFile("fixtures/sum.my"), 0, "4950\n", "");
    try invoke("run", @embedFile("fixtures/gcd.my"), 0, "6\n", "");
    try invoke("run", "fn fact(n: i64) -> i64 { if n <= 1 { return 1; } return n * fact(n - 1); } fn main() -> i64 { return fact(10); }", 0, "3628800\n", "");
    try invoke("run", "fn main() -> i64 { return 1 + add(add(2, 3), add(4, 5)); } fn add(a: i64, b: i64) -> i64 { return a + b; }", 0, "15\n", "");
    try invoke("run", "fn main() -> i64 { return bad(); } fn bad() -> i64 { return 1 / 0; }", 1, "", "in main at");
}
test "CLI frame budgets count main and reject invalid overrides" {
    const text = "fn main() -> i64 { return f(); } fn f() -> i64 { return 7; }";
    try invokeOptions("run", text, &.{"--max-frames=2"}, 0, "7\n", "");
    try invokeOptions("run", text, &.{"--max-frames=1"}, 1, "", "error[R_FRAME_LIMIT]");
    try invokeOptions("run", text, &.{ "--max-frames=2", "--max-steps=4" }, 0, "7\n", "");
    for ([_][]const u8{ "--max-frames=0", "--max-frames=-1", "--max-frames=+1", "--max-frames=", "--max-frames=abc", "--max-frames=18446744073709551616" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-frames=2", "--max-frames=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-frames=2"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", text, &.{"--max-frames=2"}, 2, "", "usage:");
}
test "all commands reject invalid programs before execution and locate runtime traps" {
    for ([_][]const u8{ "check", "run", "dump-bytecode" }) |command| {
        try invoke(command, @embedFile("fixtures/rejected.my"), 1, "", ":2:12: error[E_UNKNOWN_NAME]");
        try invoke(command, "", 1, "", "error[E_MAIN]");
        try invoke(command, "fn main() -> bool { return true; }", 1, "", "error[E_TYPE]");
    }
    try invoke("check", @embedFile("fixtures/trap.my"), 0, "", "");
    try invoke("run", @embedFile("fixtures/trap.my"), 1, "", ":2:11: error[R_DIVISION_BY_ZERO]");
}
test "oversized source is a host resource failure with no result output" {
    const text = try testing.allocator.alloc(u8, 16 * 1024 * 1024 + 1);
    defer testing.allocator.free(text);
    @memset(text, ' ');
    try invoke("run", text, 2, "", "host failure:");
}
test "duplicate discovery is separate advisory analysis with explicit options" {
    const source = "fn a(n: i64) -> i64 { return n * 2 + 1; } fn b(x: i64) -> i64 { return x * 2 + 1; } fn main() -> i64 { return 7; }";
    const outcome = try runFixture("discover-duplicates", source, &.{ "--min-nodes=1", "--population=reference", "--timings" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "1 candidate groups") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "population=reference") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "discovery_ns=") != null);
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 0, "7\n", "");
    try invoke("discover-duplicates", "fn main() -> i64 { return unknown; }", 1, "", "error[E_UNKNOWN_NAME]");
    for ([_][]const u8{ "--min-nodes=0", "--min-nodes=", "--min-nodes=-1", "--population=unknown", "--max-steps=10" }) |option| {
        try invokeOptions("discover-duplicates", source, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("discover-duplicates", source, &.{ "--min-nodes=1", "--min-nodes=2" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--min-nodes=1"}, 2, "", "usage:");
}
test "CLI checks runs and dumps records and declared complete conversions" {
    try invoke("run", @embedFile("fixtures/records.my"), 0, "12\n", "");
    try invoke("run", @embedFile("fixtures/conversions.my"), 0, "11\n", "");
    try invoke("check", @embedFile("fixtures/conversions.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/conversions.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "conversion function to_view(source: Source) -> View") != null);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "MAKE_RECORD") != null);
    const incomplete = "struct Source { x: i64, added: bool } struct View { y: i64 } conversion fn convert(src: Source) -> View { return new View { y: src.x }; } fn main() -> i64 { return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, incomplete, 1, "", "error[E_INCOMPLETE_CONVERSION]");
    }
}
test "CLI checks resource ownership completion and implicit cleanup effects without ambient access" {
    const source = @embedFile("fixtures/resources.my");
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 2, "", "host failure: CapabilityUnavailable");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "ACQUIRE_RESOURCE", "COMPLETE_RESOURCE", "effects {filesystem}", "provider filesystem (owned)" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid = "resource File: filesystem; struct Wrapper { file: File } fn cleanup(input: Wrapper) -> i64 noio { return 0; } fn main() -> i64 { return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI checks resource data operations effects and required mutation without ambient providers" {
    const source = @embedFile("fixtures/resource-io.my");
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 2, "", "host failure: CapabilityUnavailable");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "RESOURCE_read", "RESOURCE_write", "effects {filesystem}" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid = "resource File: filesystem; result Written { ok: u64, err: i64 } fn f(file: File) -> Written { return write_resource<Written>(file, new [0]u8 []); } fn main() -> i64 { return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_IMMUTABLE]");
}
test "CLI approximate discovery is advisory explains drift and reports budget exhaustion" {
    const source = "fn a(x: i64) -> i64 { return x * 2 + 1; } fn b(x: i64) -> i64 { return x * 2 + 3; } fn main() -> i64 { return 0; }";
    const outcome = try runFixture("discover-duplicates", source, &.{ "--approximate", "--min-nodes=1" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    for ([_][]const u8{ "near-v3", "near candidate:", "- 1", "+ 3", "Advisory only" }) |part| try testing.expect(std.mem.indexOf(u8, outcome.stdout, part) != null);
    const limited = try runFixture("discover-duplicates", source, &.{ "--approximate", "--min-nodes=1", "--max-work=1" });
    defer testing.allocator.free(limited.stdout);
    defer testing.allocator.free(limited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, limited.term);
    try testing.expect(std.mem.indexOf(u8, limited.stdout, "Incomplete approximate search") != null);
    for ([_][]const []const u8{ &.{"--max-work=1"}, &.{ "--approximate", "--max-work=0" }, &.{ "--approximate", "--approximate" } }) |options| try invokeOptions("discover-duplicates", source, options, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--approximate"}, 2, "", "usage:");
}
test "CLI static quality report uses advisory thresholds and rejects invalid options" {
    const source = "fn helper(x: i64) -> i64 { return x; } fn main() -> i64 { return helper(7); }";
    const outcome = try runFixture("report-quality", source, &.{"--max-line-bytes=1"});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    for ([_][]const u8{ "quality-v1", "calls helper", "reachable-from-main=true", "exceeds configured 1", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, outcome.stdout, part) != null);
    for ([_][]const []const u8{ &.{"--max-nesting=-1"}, &.{"--max-decisions="}, &.{ "--max-parameters=1", "--max-parameters=2" }, &.{"--max-steps=1"} }) |options| try invokeOptions("report-quality", source, options, 2, "", "usage:");
    try invokeOptions("run", source, &.{"--max-nesting=1"}, 2, "", "usage:");
    try invoke("report-quality", "fn main() -> i64 { return false; }", 1, "", "error[E_TYPE]");
}
test "CLI formatter supports stdout check mode and syntax-only formatting" {
    const compact = "fn main()->i64{return 7;}";
    const formatted = "fn main() -> i64 {\n    return 7;\n}\n";
    try invoke("fmt", compact, 0, formatted, "");
    try invokeOptions("fmt", compact, &.{"--check"}, 1, "", "formatting differs");
    try invokeOptions("fmt", formatted, &.{"--check"}, 0, "", "");
    try invoke("fmt", "fn main()->i64{return false;}", 0, "fn main() -> i64 {\n    return false;\n}\n", "");
    try invoke("fmt", "fn main()->i64{return +;}", 1, "", "error[E_EXPRESSION]");
    try invokeOptions("fmt", compact, &.{ "--check", "--check" }, 2, "", "usage:");
    try invokeOptions("check", compact, &.{"--check"}, 2, "", "usage:");
}
test "CLI module discovery loads real files and diagnoses cross-file cycles" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "shared");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input; import shared.data as data; fn main() -> i64 { return 0; }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.my", .data = "module shared.data;" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-modules", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    const child = std.mem.indexOf(u8, result.stdout, "module shared.data path=shared/data.my sha256=").?;
    const root = std.mem.indexOf(u8, result.stdout, "module input path=input.my sha256=").?;
    try testing.expect(child < root);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "bodies/exports/types not checked") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.my", .data = "module shared.data;\nimport input;" });
    const cycle = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-modules", path } });
    defer testing.allocator.free(cycle.stdout);
    defer testing.allocator.free(cycle.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cycle.term);
    try testing.expectEqualStrings("", cycle.stdout);
    for ([_][]const u8{ "E_IMPORT_CYCLE", "shared/data.my:2:", "input.my:1:", "input -> shared.data -> input" }) |part| try testing.expect(std.mem.indexOf(u8, cycle.stderr, part) != null);
}
test "CLI module discovery keeps header validity separate from compilation" {
    const result = try runFixture("list-modules", "module input; fn broken( ;", &.{});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "header discovery only") != null);
    try invoke("list-modules", "module input; import missing;", 1, "", "E_MODULE_READ");
    try invokeOptions("list-modules", "module input;", &.{"--max-steps=10"}, 2, "", "usage:");
    const compilation = try runFixture("check", "module input; fn main() -> i64 { return 0; }", &.{});
    defer testing.allocator.free(compilation.stdout);
    defer testing.allocator.free(compilation.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, compilation.term);
}
test "CLI module interfaces parse bodies and check exported signature visibility" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input; import units; export Sample; struct Sample { distance: units::Distance } fn main() -> i64 { return unknown(); }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.my", .data = "module units; export Distance; domain Distance: i64 { fn make(x: i64) -> Distance { return wrap<Distance>(x); } }" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    for ([_][]const u8{ "bodies not type checked", "export type Sample", "export type Distance", "export function Distance.make" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.my", .data = "module units; domain Distance: i64 {}" });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    try testing.expectEqualStrings("", hidden.stdout);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "input.my:1:", "units.my:1:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invoke("list-interfaces", "module input; fn broken( ;", 1, "", "E_SYNTAX");
    try invoke("list-interfaces", "module input; export f; struct Secret {} fn f() -> Secret { return new Secret {}; }", 1, "", "E_PRIVATE_INTERFACE");
    try invokeOptions("list-interfaces", "module input;", &.{"--check"}, 2, "", "usage:");
}
test "CLI checks and runs module programs with private boundaries and cross-file traps" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input; import helper; fn main() -> i64 { return helper::value(); }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "module helper; export value; fn value() -> i64 { return 42; }" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    for ([_][]const u8{ "check-project", "run-project", "eval-project" }) |command| {
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, command, path } });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try testing.expectEqualStrings(if (std.mem.eql(u8, command, "check-project")) "" else "42\n", result.stdout);
        try testing.expectEqualStrings("", result.stderr);
    }
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "module helper; export value; fn value() -> i64 { return 1 / 0; }" });
    const trap = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "run-project", path } });
    defer testing.allocator.free(trap.stdout);
    defer testing.allocator.free(trap.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trap.term);
    for ([_][]const u8{ "R_DIVISION_BY_ZERO", "helper.my:1:", "input.my:1:" }) |part| try testing.expect(std.mem.indexOf(u8, trap.stderr, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "module helper; fn value() -> i64 { return 42; }" });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "helper.my:1:", "input.my:1:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invokeOptions("run-project", "module input; fn main() -> i64 { return 7; }", &.{"--max-steps=1"}, 1, "", "R_STEP_LIMIT");
    try invokeOptions("check-project", "module input; fn main() -> i64 { return 7; }", &.{"--max-steps=1"}, 2, "", "usage:");
}
test "CLI checkProjectPolicy distinguishes language failures policy failures and configuration failures" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input; import core; fn main() -> i64 { return core::value(); }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.my", .data = "module core; export value; fn value() -> i64 { return 7; }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const policy_path = try temp.dir.realPathFileAlloc(testing.io, "rules file.json", testing.allocator);
    defer testing.allocator.free(policy_path);
    const option = try std.fmt.allocPrint(testing.allocator, "--policy={s}", .{policy_path});
    defer testing.allocator.free(option);
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expectEqualStrings("", denied.stderr);
    for ([_][]const u8{ "language: valid", "import-direction-v1: failed", "edges=1; denied=1", "input -> core: deny; rule=default" }) |part| try testing.expect(std.mem.indexOf(u8, denied.stdout, part) != null);
    const ordinary = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "run-project", path } });
    defer testing.allocator.free(ordinary.stdout);
    defer testing.allocator.free(ordinary.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ordinary.term);
    try testing.expectEqualStrings("7\n", ordinary.stdout);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}" });
    const allowed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);
    try testing.expect(std.mem.indexOf(u8, allowed.stdout, "import-direction-v1: passed") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":99,\"default_action\":\"allow\",\"rules\":[]}" });
    const config_error = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(config_error.stdout);
    defer testing.allocator.free(config_error.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, config_error.term);
    try testing.expectEqualStrings("", config_error.stdout);
    try testing.expect(std.mem.indexOf(u8, config_error.stderr, "UnsupportedPolicyVersion") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.my", .data = "module core; export value; fn value() -> i64 { return true; }" });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invoke("check-policy", "module input; fn main() -> i64 { return 0; }", 2, "", "usage:");
    try invokeOptions("check-project", "module input; fn main() -> i64 { return 0; }", &.{"--policy=some.json"}, 2, "", "usage:");
    try invokeOptions("check-policy", "module input; fn main() -> i64 { return 0; }", &.{ "--policy=a", "--policy=b" }, 2, "", "usage:");
}
test "CLI discovers cross module duplicates with options and rejects invalid dependencies" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input; import helper; fn twice(value: i64) -> i64 { return value * 2 + 3; } fn main() -> i64 { return 0; }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "module helper; fn copy(x: i64) -> i64 { return x * 2 + 3; }" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "discover-project-duplicates", path, "--min-nodes=1", "--approximate", "--max-work=1", "--population=reference", "--timings" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "scope: reachable module graph", "population=reference", "input::twice", "helper::copy", "input.my:1:", "helper.my:1:", "approximate near-v3", "truncated=true" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "project_frontend_ns=") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "modules=2") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "module helper; fn copy(x: i64) -> i64 { return true; }" });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "discover-project-duplicates", path } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invokeOptions("discover-project-duplicates", "module input; fn main() -> i64 { return 0; }", &.{"--max-work=1"}, 2, "", "usage:");
    try invokeOptions("discover-project-duplicates", "module input; fn main() -> i64 { return 0; }", &.{"--max-steps=1"}, 2, "", "usage:");
}
test "CLI module quality reports preserve export roots and advisory thresholds" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input; import api; fn main() -> i64 { return 0; }" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.my", .data = "module api;\nexport entry;\nfn entry() -> i64 {\n return hidden();\n}\nfn hidden() -> i64 { return 1; }" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "report-project-quality", path, "--max-function-lines=1" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    for ([_][]const u8{ "quality-modules-v1", "api.my:3:", "api::entry; private=false; reachable-from-main=false", "module-exported=true reachable-from-exports=true", "module-exported=false reachable-from-exports=true", "function-lines 3 exceeds configured 1", "calls api::hidden at api.my:4:", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "no call path from main or exported interfaces") == null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.my", .data = "module api; fn invalid() -> i64 { return true; }" });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "report-project-quality", path } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invokeOptions("report-project-quality", "module input; fn main() -> i64 { return 0; }", &.{"--approximate"}, 2, "", "usage:");
}
test "CLI module formatting is syntax only and project checking reports every changed file" {
    const draft = "module input;import absent as a;export Missing;fn f(x:a :: T)->a::T{return x;}";
    const formatted = "module input;\nimport absent as a;\nexport Missing;\nfn f(x: a::T) -> a::T {\n    return x;\n}\n";
    try invoke("fmt-module", draft, 0, formatted, "");
    try invokeOptions("fmt-module", draft, &.{"--check"}, 1, "", "formatting differs");
    try invokeOptions("fmt-module", formatted, &.{"--check"}, 0, "", "");
    try invoke("fmt-module", "module input; fn broken( ;", 1, "", "E_SYNTAX");
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input;import child;fn main()->i64{return unknown();}" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.my", .data = "module child;fn f()->Missing{return unknown();}" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const changed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-project", path, "--check" } });
    defer testing.allocator.free(changed.stdout);
    defer testing.allocator.free(changed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, changed.term);
    try testing.expectEqualStrings("", changed.stdout);
    try testing.expectEqualStrings("child.my: formatting differs\ninput.my: formatting differs\n", changed.stderr);
    // Apply each formatter's stdout explicitly in this fixture, then check the graph.
    for ([_][]const u8{ "input.my", "child.my" }) |name| {
        const absolute = try temp.dir.realPathFileAlloc(testing.io, name, testing.allocator);
        defer testing.allocator.free(absolute);
        const output = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-module", absolute } });
        defer testing.allocator.free(output.stdout);
        defer testing.allocator.free(output.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, output.term);
        try temp.dir.writeFile(testing.io, .{ .sub_path = name, .data = output.stdout });
    }
    const clean = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-project", path, "--check" } });
    defer testing.allocator.free(clean.stdout);
    defer testing.allocator.free(clean.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, clean.term);
    try testing.expectEqualStrings("", clean.stdout);
    try testing.expectEqualStrings("", clean.stderr);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.my", .data = "module child; fn broken( ;" });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-project", path, "--check" } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_SYNTAX") != null);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "formatting differs") == null);
    try invoke("fmt-project", "module input;", 2, "", "usage:");
    try invokeOptions("fmt-module", "module input;", &.{"--max-steps=1"}, 2, "", "usage:");
}
// spec: CLI-4
test "CLI schema inputs load fresh generated modules and reject malformed manifests" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "values.json", .data =
        \\{"version":1,"module":"config","values":[{"name":"value","type":"i64","value":"7"}]}
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "values.json", testing.allocator);
    defer testing.allocator.free(path);
    const option = try std.fmt.allocPrint(testing.allocator, "--inputs={s}", .{path});
    defer testing.allocator.free(option);
    const source = "module input; import config; export read; fn read()->i64{return config::value();} fn main()->i64{return 0;}";
    const result = try runFixture("schema-project", source, &.{option});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "input::read") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "values.json", .data = "{}" });
    try invokeOptions("schema-project", source, &.{option}, 2, "", "MissingField");
    try invokeOptions("schema-project", source, &.{ option, option }, 2, "", "usage:");
}
fn sessionScript(script: []const u8, flags: []const []const u8, expected_status: u8) ![]u8 {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "module input;fn main()->i64{return 0;}" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "commands", .data = script });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const input = try temp.dir.openFile(testing.io, "commands", .{});
    defer input.close(testing.io);
    const output = try temp.dir.createFile(testing.io, "replies", .{});
    defer output.close(testing.io);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check-session", path });
    try args.appendSlice(testing.allocator, flags);
    var child = try std.process.spawn(testing.io, .{ .argv = args.items, .stdin = .{ .file = input }, .stdout = .{ .file = output }, .stderr = .ignore });
    defer child.kill(testing.io);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, try child.wait(testing.io));
    return temp.dir.readFileAlloc(testing.io, "replies", testing.allocator, .limited(16384));
}
// spec: CLI-5
test "CLI check session reuses parses and clears retained storage" {
    const replies = try sessionScript("check\ncheck\nclear\ncheck\nquit\n", &.{}, 0);
    defer testing.allocator.free(replies);
    try testing.expect(std.mem.indexOf(u8, replies, "\"version\":\"check-session-v1\"") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"semantic\":{\"hits\":1,\"misses\":1") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"retained_bytes\":0") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"status\":1") == null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"status\":2") == null);
}
test "CLI sessionCheck returns host failure without terminating the session" {
    const replies = try sessionScript("check\nclear\nquit\n", &.{"--inputs=/nonexistent-mylang-manifest/inputs.json"}, 0);
    defer testing.allocator.free(replies);
    try testing.expect(std.mem.indexOf(u8, replies, "\"failure\":\"FileNotFound\"") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"action\":\"quit\",\"status\":0") != null);
}
test "CLI executes generic fixed arrays and reports uncalled template shape errors" {
    try invoke("run", "fn twice<T:integer>(x:T)->[2]T{return new [2]T[x,x+x];}fn main()->i64{return twice::<i64>(6)[1];}", 0, "12\n", "");
    try invokeOptions("check", "fn bad<T:copy>(a:[2]T)->[3]T{return a;}fn main()->i64{return 0;}", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_TYPE\"");
}
test "CLI formats nominal templates and runs programs with unused declarations" {
    const source = "struct Box<T:copy>{value:T}fn main()->i64{return 0;}";
    try invoke("fmt", source, 0, "struct Box<T: copy> {\n    value: T\n}\nfn main() -> i64 {\n    return 0;\n}\n", "");
    try invokeOptions("run", source, &.{"--diagnostics=json"}, 0, "0\n", "");
}
test "CLI reports unused nominal template requirement errors" {
    try invokeOptions("check", "struct Key<T:equality>{value:T}struct Bad<U:copy>{key:Key<U>}fn main()->i64{return 0;}", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_REQUIREMENT\"");
    try invokeOptions("check", "struct Bad<T:copy>{value:Missing}fn main()->i64{return 0;}", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_UNKNOWN_TYPE\"");
}
test "CLI rejects recursive nominal layouts but preserves finite nested and phantom forms" {
    try invokeOptions("check", "struct Node<T:copy>{next:Node<T>}fn main()->i64{return 0;}", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_RECURSIVE_RECORD\"");
    try invokeOptions("check", "struct Box<T:copy>{value:T}struct Empty<T:copy>{}struct Finite<U:copy>{nested:Box<Box<U>>,phantom:Empty<Finite<[1]U>>}fn main()->i64{return 0;}", &.{"--diagnostics=json"}, 0, "", "");
}
test "CLI executes concrete nominal instances and reports argument identity errors" {
    const definitions = "struct Box<T:copy>{value:T}union Slot<T:copy>{none,some:T}";
    const program = definitions ++ "fn main()->i64{let slot=new Slot<Box<i64>>.some(new Box<i64>{value:12});" ++
        "match slot{Slot<Box<i64>>.none=>{return 0;},Slot<Box<i64>>.some(box)=>{return box.value;}}}";
    try invoke("run", program, 0, "12\n", "");
    try invokeOptions("check", definitions ++
        "fn takes(box:Box<i64>)->i64{return box.value;}fn main()->i64{return takes(new Box<bool>{value:true});}", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_TYPE\"");
}
test "CLI specializes nominal generic bodies and reports uncalled shape errors" {
    const definitions = "struct Box<T:copy>{value:T}";
    try invoke("run", definitions ++ "fn pack<T:copy>(x:T)->Box<T>{return new Box<T>{value:x};}fn main()->i64{return pack::<i64>(31).value;}", 0, "31\n", "");
    try invokeOptions("check", definitions ++ "fn bad<T:copy>(x:T)->Box<T>{return new Box<T>{value:1};}fn main()->i64{return 0;}", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_TYPE\"");
}
// spec: DEPENDENCIES-1
test "CLI project-dependencies buildIndex emits checked graph identity and rejects invalid bodies" {
    const outcome = try runFixture("project-dependencies", "module input; fn main()->i64 { return 7; }", &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, outcome.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("project-dependencies-v1", parsed.value.object.get("version").?.string);
    try testing.expect(parsed.value.object.get("complete").?.bool);
    try testing.expectEqualStrings("input.my", parsed.value.object.get("inputs").?.array.items[0].object.get("path").?.string);
    try testing.expectEqual(@as(usize, 64), parsed.value.object.get("implementation").?.object.get("compiler_sha256").?.string.len);
    try invoke("project-dependencies", "module input; fn main()->i64 { return true; }", 1, "", "E_TYPE");
    try invoke("project-dependencies", "module input; export absent; fn main()->i64 { return 0; }", 1, "", "error[");
}
// spec: FEATURE-REPORT-1
test "CLI features identify installed compiler without source input" {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "--features" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, result.stdout, .{});
    defer parsed.deinit();
    const report = parsed.value.object;
    try testing.expectEqualStrings("language-features-v1", report.get("version").?.string);
    try testing.expectEqual(@as(usize, 64), report.get("compiler_sha256").?.string.len);
    try testing.expectEqualStrings("vm", report.get("features").?.object.get("primary_backend").?.string);
    // The identity is the compiler's embedded build-time digest, not a fresh hash of its
    // own executable, so a receipt from the same compiler reports exactly the same value.
    const receipt = try runFixture("project-dependencies", "module input; fn main()->i64 { return 7; }", &.{});
    defer testing.allocator.free(receipt.stdout);
    defer testing.allocator.free(receipt.stderr);
    const graph = try std.json.parseFromSlice(std.json.Value, testing.allocator, receipt.stdout, .{});
    defer graph.deinit();
    try testing.expectEqualStrings(report.get("compiler_sha256").?.string, graph.value.object.get("implementation").?.object.get("compiler_sha256").?.string);
}
const listing_module = "module input;\nimport math;\nimport shared.units as units;\n" ++
    "export Count;\n// leading comment\n// second line\ntype Count = i64;\n\n" ++
    "const LIMIT: Count = 3; // trailing note\nstruct Job { id: Count }\n" ++
    "host fn measure(x: i64) -> i64 effects(host);\nexport main;\n" ++
    "fn main() -> i64 { return LIMIT; }\n";
const Listing = struct {
    version: []const u8,
    module: ?[]const u8,
    header: ?Extent,
    imports: []const struct { name: []const u8, alias: ?[]const u8, bytes: Extent },
    exports: []const struct { name: []const u8, bytes: Extent },
    declarations: []const struct { kind: []const u8, name: []const u8, exported: bool, bytes: Extent, comment_start: usize },
    const Extent = struct { start: usize, end: usize };
};
fn expectTrivia(text: []const u8) !void {
    var at: usize = 0;
    while (at < text.len) {
        if (std.ascii.isWhitespace(text[at])) {
            at += 1;
            continue;
        }
        if (!std.mem.startsWith(u8, text[at..], "//")) return error.UnaccountedSourceByte;
        at = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
    }
}
// spec: DECLARATION-LIST-2
test "CLI declaration listing accounts for every byte with disjoint ordered ranges" {
    const outcome = try runFixture("list-declarations", listing_module, &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stderr);
    const parsed = try std.json.parseFromSlice(Listing, testing.allocator, outcome.stdout, .{});
    defer parsed.deinit();
    const listing = parsed.value;
    try testing.expectEqualStrings("declarations-v1", listing.version);
    try testing.expectEqualStrings("input", listing.module.?);
    try testing.expectEqualStrings("units", listing.imports[1].alias.?);
    try testing.expectEqual(@as(usize, 5), listing.declarations.len);
    var ranges: std.ArrayList(Listing.Extent) = .empty;
    defer ranges.deinit(testing.allocator);
    try ranges.append(testing.allocator, listing.header.?);
    for (listing.imports) |imported| try ranges.append(testing.allocator, imported.bytes);
    for (listing.exports) |exported| try ranges.append(testing.allocator, exported.bytes);
    var previous: usize = 0;
    for (listing.declarations) |declaration| {
        try testing.expect(declaration.bytes.start >= previous);
        try testing.expect(declaration.comment_start <= declaration.bytes.start);
        previous = declaration.bytes.start;
        try ranges.append(testing.allocator, .{ .start = declaration.comment_start, .end = declaration.bytes.end });
    }
    std.mem.sort(Listing.Extent, ranges.items, {}, struct {
        fn before(_: void, a: Listing.Extent, b: Listing.Extent) bool {
            return a.start < b.start;
        }
    }.before);
    var accounted: usize = 0;
    for (ranges.items) |range| {
        try testing.expect(range.start >= accounted and range.end > range.start);
        try expectTrivia(listing_module[accounted..range.start]);
        accounted = range.end;
    }
    try expectTrivia(listing_module[accounted..]);
    try testing.expect(listing.declarations[0].comment_start < listing.declarations[0].bytes.start);
    try testing.expect(listing.declarations[3].exported == false and listing.declarations[4].exported);
}
test "CLI declaration listing separates parse failures from checking and usage failures" {
    try invoke("list-declarations", "fn main() -> i64 { return 1 + ; }", 1, "", "error[E_EXPRESSION]");
    try invokeOptions("list-declarations", "module m; export absent; fn main() -> i64 { return 0; }", &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_UNKNOWN_EXPORT\"");
    try invokeOptions("list-declarations", "fn main() -> i64 { return 0; }", &.{"--check"}, 2, "", "usage:");
    const unchecked = "module m; fn main() -> i64 { let flag: bool = 1; return flag; }";
    const outcome = try runFixture("list-declarations", unchecked, &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "\"kind\":\"fn\",\"name\":\"main\"") != null);
}
const legacy_migration = "// Keep this note.\nstruct Point { x: i64 }\nfn main() -> i64 {\n    let p = new Point { x: 42 };\n    if !(p.x < 0) && true { return p.x; }\n    return 0;\n}\n";
const python_migration = "# Keep this note.\nclass Point:\n    x: i64\n\n\ndef main() -> i64:\n    p = Point(x=42)\n    if not (p.x < 0) and True:\n        return p.x\n    return 0\n";
// spec-case: MIGRATE-1
test "CLI migrate prints checked Python source and is idempotent" {
    try invoke("migrate", legacy_migration, 0, python_migration, "");
    try invokeOptions("migrate", legacy_migration, &.{"--check"}, 0, python_migration, "");
    try invoke("migrate", python_migration, 0, python_migration, "");
    try invokeOptions("migrate", python_migration, &.{"--check"}, 0, python_migration, "");
    try invoke("run", legacy_migration, 0, "42\n", "");
    try invoke("run", python_migration, 0, "42\n", "");
}
// spec-case: MIGRATE-5
test "CLI migrate reports unconvertible constructs and supports partial output" {
    const scoped = "fn main() -> i64 {\n    let a = 7;\n    { let b = 1; }\n    return a;\n}\n";
    try invoke("migrate", scoped, 1, "", "error[E_MIGRATE_UNSUPPORTED]");
    try invokeOptions("migrate", scoped, &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_MIGRATE_UNSUPPORTED\"");
    const partial = try runFixture("migrate", scoped, &.{"--allow-partial"});
    defer testing.allocator.free(partial.stdout);
    defer testing.allocator.free(partial.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, partial.term);
    try testing.expect(std.mem.indexOf(u8, partial.stdout, "# MIGRATE: unsupported a bare nested scope block") != null);
    try testing.expect(std.mem.indexOf(u8, partial.stderr, "warning[E_MIGRATE_UNSUPPORTED]") != null);
    try invokeOptions("check", legacy_migration, &.{"--allow-partial"}, 2, "", "usage:");
    try invokeOptions("migrate", legacy_migration, &.{ "--check", "--check" }, 2, "", "usage:");
    try invokeOptions("fmt", legacy_migration, &.{"--write"}, 2, "", "usage:");
}
// spec-case: MIGRATE-6
test "CLI migrate rewrites files in place and walks a module graph" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = legacy_migration });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const written = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "migrate", path, "--write" } });
    defer testing.allocator.free(written.stdout);
    defer testing.allocator.free(written.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    try testing.expectEqualStrings("", written.stdout);
    const bytes = try temp.dir.readFileAlloc(testing.io, "input.my", testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings(python_migration, bytes);
    const module = "module input;\nexport main;\nfn main() -> i64 { let value = 42; return value; }\n";
    try invokeOptions("migrate-project", module, &.{"--check"}, 0, "", "");
    try invokeOptions("migrate-project", "module input;\nfn main() -> i64 { { let a = 1; } return 0; }\n", &.{"--check"}, 1, "", "error[E_MIGRATE_UNSUPPORTED]");
}
test "CLI executes control flow and preserves discarded traps" {
    try invoke("run", "fn main() -> i64 { let mut sum = 0; let mut i = 0; while i < 100 { sum += i; i += 1; } return sum; }", 0, "4950\n", "");
    try invoke("run", "fn main() -> i64 { if false && 1 / 0 == 0 { return 1; } else { return 7; } }", 0, "7\n", "");
    try invoke("run", "fn main() -> i64 { _ = 1 / 0; return 7; }", 1, "", "error[R_DIVISION_BY_ZERO]");
    try invoke("check", "fn main() -> i64 { while true { return 7; } }", 1, "", "error[E_MISSING_RETURN]");
}
test "all commands preserve stdout and deterministic advisory stderr" {
    const source = @embedFile("fixtures/warnings.my");
    const commands = [_][]const u8{ "check", "run", "dump-bytecode" };
    const outputs = [_][]const u8{ "", "7\n", @embedFile("fixtures/warnings.dump") };
    for (commands, outputs) |command, expected| {
        const outcome = try runFixture(command, source, &.{});
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
        try testing.expectEqualStrings(expected, outcome.stdout);
        const first = std.mem.indexOf(u8, outcome.stderr, ":2:13: warning[W_UNNECESSARY_MUT]") orelse return error.MissingWarning;
        const second = std.mem.indexOf(u8, outcome.stderr, ":2:13: warning[W_UNUSED_BINDING]") orelse return error.MissingWarning;
        try testing.expect(first < second);
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, outcome.stderr, "warning["));
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "`_ =`") != null);
    }
}
test "CLI preserves integer width bounds and explicit casts" {
    try invoke("run", @embedFile("fixtures/integers.my"), 0, "6148914691236516950\n", "");
    try invoke("check", "fn main() -> i64 { _ = cast<u8>(256); return 0; }", 0, "", "");
    try invoke("run", "fn main() -> i64 { _ = cast<u8>(256); return 0; }", 1, "", "error[R_OVERFLOW]");
    try invoke("run", "fn main() -> i64 { _ = 255u8 + 1u8; return 0; }", 1, "", "error[R_OVERFLOW]");
    try invoke("check", "fn main() -> i64 { _ = 256u8; return 0; }", 1, "", "error[E_INTEGER_RANGE]");
    try invoke("check", "fn main() -> u8 { return 0u8; }", 1, "", "error[E_TYPE]");
}
test "CLI checks array schemas dumps indexing and reports bounds traps" {
    try invoke("run", @embedFile("fixtures/arrays.my"), 0, "44\n", "");
    try invoke("check", @embedFile("fixtures/arrays.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/arrays.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "array [3]i64", "GET_INDEX [3]i64", "REPLACE_INDEX [3]i64", "ARRAY_LENGTH [3]i64" }) |instruction| {
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    }
    const invalid = "fn main() -> i64 { _ = new [2]i64 [1]; return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, invalid, 1, "", "error[E_ARRAY_ARITY]");
    }
    const bounds = "fn main() -> i64 {\n    return new [1]i64 [7][-1];\n}";
    try invoke("check", bounds, 0, "", "");
    try invoke("run", bounds, 1, "", ":2:12: error[R_INDEX_BOUNDS]");
    try invoke("run", "fn main() -> i64 { _ = replace(new [1]u8 [7u8], 18446744073709551615u64, 8u8); return 0; }", 1, "", "error[R_INDEX_BOUNDS]");
}
test "CLI checks domain privacy unit mismatches and qualified factory execution" {
    try invoke("run", @embedFile("fixtures/domains.my"), 0, "1003\n", "");
    try invoke("check", @embedFile("fixtures/domains.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/domains.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "domain Millimeters", "private function Millimeters.raw", "WRAP_DOMAIN Millimeters", "UNWRAP_DOMAIN Seconds" }) |instruction| {
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    }
    const private = "domain D: i64 { private fn raw(n: i64) -> D { return wrap<D>(n); } } fn main() -> i64 { _ = D.raw(1); return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, private, 1, "", "error[E_PRIVATE_FUNCTION]");
    }
    try invoke("check", "domain D: i64 {} fn main() -> i64 { _ = wrap<D>(1); return 0; }", 1, "", "error[E_PRIVATE_DOMAIN]");
    try invoke("check", "domain Seconds: i64 { fn from(n: i64) -> Seconds { return wrap<Seconds>(n); } } domai" ++
        "n Millimeters: i64 {} fn distance(n: Millimeters) -> i64 { _ = n; return 0; } fn " ++
        "main() -> i64 { return distance(Seconds.from(1)); }", 1, "", "expected Millimeters, found Seconds");
}
test "CLI executes variants dumps dispatch and rejects newly incomplete matches" {
    try invoke("run", @embedFile("fixtures/variants.my"), 0, "24\n", "");
    try invoke("check", @embedFile("fixtures/variants.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/variants.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "enum Color", "union Shape", "MAKE_VARIANT Shape.point", "SWITCH_VARIANT Shape" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const added = "enum Color { red, green, added } fn main() -> i64 { match new Color.red { Color.red => { return 1; }, Color.green => { return 2; } } }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "match does not handle variant `added`");
    try invoke("check", "union U { value: i64, empty } fn main() -> i64 { _ = new U.value(true); return 0; }", 1, "", "error[E_TYPE]");
    try invoke("run", "union U { value: i64 } fn main() -> i64 { match new U.value(1 / 0) { U.value(_) => { return 0; } } }", 1, "", "error[R_DIVISION_BY_ZERO]");
}
test "CLI executes complete enum tables and rejects missing mappings in every command" {
    try invoke("run", @embedFile("fixtures/tables.my"), 0, "1407\n", "");
    try invoke("check", @embedFile("fixtures/tables.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/tables.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "table [Status]u16", "GET_INDEX [Status]u16", "REPLACE_INDEX [Status]u16" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const added = "enum Key { old, added } fn main() -> i64 { return new [Key]i64 { old: 7 }[new Key.old]; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "missing initializer for key `added`");
    try invoke("check", "enum Key { a } fn main() -> i64 { return new [Key]i64 { a: 7 }[0]; }", 1, "", "expected Key, found i64");
    try invoke("check", "enum Key { a } fn main() -> i64 { _ = new [Key]i64 [7]; return 0; }", 1, "", "error[E_TABLE_CONSTRUCTION]");
}
test "CLI handles recoverable results and rejects silent error loss" {
    const source = @embedFile("fixtures/results.my");
    try invoke("run", source, 0, "7\n", "");
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "result Quotient", "ACKNOWLEDGE Quotient" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const ignored = "result R { ok: i64, err: i64 } fn main() -> i64 { let r = new R.err(7); return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, ignored, 1, "", "error[E_RESULT_UNHANDLED]");
    try invoke("check", "result R { ok: i64, err: i64 } fn main() -> i64 { new R.err(7); return 0; }", 1, "", "error[E_EXPLICIT_DISCARD_REQUIRED]");
}
test "CLI checks external capabilities but cannot silently grant ambient providers" {
    const source = @embedFile("fixtures/external-capabilities.my");
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 2, "", "host failure: CapabilityUnavailable");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "EXTERNAL_clock", "EXTERNAL_random", "effects {clock, random}" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid = "result T { ok: i64, err: i64 } fn main(c: clock_cap) -> i64 effects() { _ = clock_now<T>(c); return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI checks bounded environment access without granting ambient process access" {
    const source = @embedFile("fixtures/environment.my");
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 2, "", "host failure: CapabilityUnavailable");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "ENVIRONMENT_GET", "effects {environment}" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid = "struct Entry { bytes: [1]u8, length: u64, present: bool } result Lookup { ok: Entry, err: i64 } fn main(env: environment_cap) -> i64 effects() { _ = environment_get<Lookup>(env, new [1]u8 [75u8]); return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI exposes resource permission attenuation and rejects malformed permission sets" {
    const source = @embedFile("fixtures/attenuation.my");
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 2, "", "host failure: CapabilityUnavailable");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "RESTRICT_RESOURCE permissions=1 -> filesystem_cap") != null);
    const invalid = "fn main(fs: filesystem_cap) -> i64 { _ = restrict_resource<read, read>(fs); return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_PERMISSION]");
}
