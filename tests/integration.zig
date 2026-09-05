//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;

fn invoke(command: []const u8, text: []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, command, path } });
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
