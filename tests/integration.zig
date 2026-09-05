//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;

fn invoke(command: []const u8, text: []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    return invokeOptions(command, text, &.{}, expected_status, expected_stdout, stderr_part);
}

fn invokeOptions(command: []const u8, text: []const u8, options: []const []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, command, path });
    try args.appendSlice(testing.allocator, options);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, outcome.term);
    try testing.expectEqualStrings(expected_stdout, outcome.stdout);
    if (stderr_part.len == 0) try testing.expectEqualStrings("", outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}

test "CLI run and check success" {
    try invoke("run", @embedFile("fixtures/arithmetic.my"), 0, "7\n", "");
    try invoke("check", @embedFile("fixtures/arithmetic.my"), 0, "", "");
}

test "CLI dumps actual instructions" {
    try invoke("dump-bytecode", @embedFile("fixtures/arithmetic.my"), 0, @embedFile("fixtures/arithmetic.dump"), "");
}

test "CLI distinguishes source errors runtime traps and usage" {
    try invoke("check", "fn main() -> i64 { return 1 + ; }", 1, "", "error[E_EXPRESSION]");
    try invoke("check", "fn main() -> i64 { return 9223372036854775807 + 1; }", 0, "", "");
    try invoke("run", "fn main() -> i64 { return 9223372036854775807 + 1; }", 1, "", "error[R_OVERFLOW]");
    try invoke("unknown", "", 2, "", "usage:");
}

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

test "CLI executes control flow and preserves discarded traps" {
    try invoke("run", "fn main() -> i64 { let mut sum = 0; let mut i = 0; while i < 100 { sum += i; i += 1; } return sum; }", 0, "4950\n", "");
    try invoke("run", "fn main() -> i64 { if false && 1 / 0 == 0 { return 1; } else { return 7; } }", 0, "7\n", "");
    try invoke("run", "fn main() -> i64 { discard 1 / 0; return 7; }", 1, "", "error[R_DIVISION_BY_ZERO]");
    try invoke("check", "fn main() -> i64 { while true { return 7; } }", 1, "", "error[E_MISSING_RETURN]");
}

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
