//! The compiler's work runs on a stack of its own choosing, so a deep expression does not depend on the shell's `ulimit -s` or on
//! how many registers one build of the compiler saves in a frame (DL2).
const std = @import("std");
const testing = std.testing;

/// How many numbers the program adds: one left-nested expression this long took about 10 MiB of stack to lower, which
/// the usual 8 MiB limit did not hold.
const terms = 1024;

/// The sum 1 + 2 + ... + `terms`.
const expected = terms * (terms + 1) / 2;

/// A program whose `main` returns the sum of 1 to `terms` as one expression, and whose test function compares the same sum with
/// its value.
fn sumProgram(a: std.mem.Allocator) ![]u8 {
    var sum: std.ArrayList(u8) = .empty;
    try sum.appendSlice(a, "1");
    for (2..terms + 1) |number| try sum.print(a, " + {d}", .{number});
    return std.fmt.allocPrint(a, "func main() -> int:\n    return {s}\n\npublic func test_sum() -> bool:\n    return {s} == {d}\n", .{ sum.items, sum.items, expected });
}

/// Run the compiler in `dir` with `args` after lowering the stack limit to `kibibytes`, in a shell that then replaces itself with it.
/// The shell's `ulimit -s` lowers the hard limit too: with a higher hard limit, the start code Zig puts in every ordinary build raises
/// the soft limit to the 16 MiB the executable declares, and the program would not meet the small limit at all.
fn underStack(a: std.mem.Allocator, dir: std.Io.Dir, kibibytes: usize, args: []const []const u8) !std.process.RunResult {
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), a);
    const script = try std.fmt.allocPrint(a, "ulimit -s {d} && exec \"$@\"", .{kibibytes});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "/bin/sh", "-c", script, "limited-stack", compiler });
    try argv.appendSlice(a, args);
    var environment = try paths.privateEnvironment(a);
    return std.process.run(a, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir }, .environ_map = &environment });
}

test "a 1,024-term expression runs and is tested under a 4 MiB stack limit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "terms.selka", .data = try sumProgram(a) });
    const zig = "--zig=" ++ @import("test_options").zig_path;
    // The limit is the shell's own: the compiler's recursion must not depend on it.
    const ran = try underStack(a, temporary.dir, 4096, &.{ "run", "terms.selka", "--print-result", "--cache-dir", "cache-run", zig });
    try testing.expectEqual(std.process.Child.Term{ .exited = expected & 0xff }, ran.term);
    try testing.expectEqualStrings(std.fmt.comptimePrint("{d}\n", .{expected}), ran.stdout);
    try testing.expectEqualStrings("", ran.stderr);
    const tested = try underStack(a, temporary.dir, 4096, &.{ "test", "terms.selka", "--cache-dir", "cache-test", zig });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 passed") != null);
}
