//! A built binary has no frame budget; its recursion depth ends at the native stack, and the
//! trap says so (NEW-CORE-FRAME-FLOOR-1).
const std = @import("std");
const testing = std.testing;

/// A recursion whose depth the caller picks, with a frame small enough that 8 MiB holds
/// far fewer than three million of them.
const descend =
    \\func descend(n: int) -> int:
    \\    if n == 0:
    \\        return 0
    \\    return 1 + descend(n - 1)
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const parsed = parse_int(args[0])
    \\    if parsed is None:
    \\        return 2
    \\    print(out, descend(parsed))
    \\    return 0
    \\
;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: NEW-CORE-FRAME-FLOOR-1
test "a built binary that fills the native stack names the stack limit and a remedy it can take" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "descend.selka", .data = descend });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "descend.selka", "-o", "descend", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    // The usual 8 MiB stack (set explicitly: a test run may inherit a larger one) cannot hold three million frames.
    const trapped = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ "/bin/sh", "-c", "ulimit -s 8192 && exec ./descend 3000000" },
        .cwd = .{ .dir = temporary.dir },
    });
    defer testing.allocator.free(trapped.stdout);
    defer testing.allocator.free(trapped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
    try testing.expect(contains(trapped.stderr, "error[R_FRAME_LIMIT]: call-depth limit reached: the native stack is full"));
    try testing.expect(contains(trapped.stderr, "ulimit -s"));
    try testing.expect(!contains(trapped.stderr, "call-depth budget exhausted"));
    // The remedy the message names: a larger stack lets the same binary finish.
    const raised = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ "/bin/sh", "-c", "ulimit -s 1048576 && exec ./descend 3000000" },
        .cwd = .{ .dir = temporary.dir },
    });
    defer testing.allocator.free(raised.stdout);
    defer testing.allocator.free(raised.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, raised.term);
    try testing.expectEqualStrings("3000000\n", raised.stdout);
}
