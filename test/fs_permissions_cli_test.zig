//! The in-memory filesystem honours the permission bits it keeps (friction F-42), checked against the real one call by call.
//! `fixtures/fs-permissions/matrix.selka` runs about 490 calls (every Filesystem call that reads, writes, creates, removes,
//! renames, locks or lists, against directories and files of chosen modes) and prints `TAG CALL: ok` or the failure text of
//! each. `fixtures/fs-permissions/expected.txt` is what a real directory answers to an ordinary user. This test runs the
//! matrix on a real directory and on `filesystem.memory()` and requires both to print exactly that file, so a refusal the
//! stand-in leaves out, adds or words differently fails here, and so does a change of the real provider the stand-in has to
//! follow. A privileged user passes every permission check, so the test skips there.
const std = @import("std");
const testing = std.testing;

const matrix = @embedFile("fixtures/fs-permissions/matrix.selka");
const expected = @embedFile("fixtures/fs-permissions/expected.txt");

/// A privileged user is never refused by a mode, so the matrix says nothing there.
fn requireOrdinaryUser() error{SkipZigTest}!void {
    if (std.os.linux.geteuid() == 0) return error.SkipZigTest;
}

/// Run the matrix with `entry` appended as its `main`, in a fresh directory, and return what it printed.
fn runMatrix(arena: std.mem.Allocator, entry: []const u8) ![]const u8 {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const source = try std.mem.concat(arena, u8, &.{ matrix, "\n\n", entry });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{ compiler, "run", "probe.selka", "--zig=" ++ @import("test_options").zig_path, "--cache-dir=cache" },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return result.stdout;
}

test "a real directory answers every call of the permission matrix as the expected file says" {
    try requireOrdinaryUser();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const printed = try runMatrix(arena_state.allocator(), "func main(fs: Filesystem, out: Stream) -> int:\n    run_all(fs, out)\n    return 0\n");
    try testing.expectEqualStrings(expected, printed);
}

test "the in-memory filesystem answers every call of the permission matrix as the real one does" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const printed = try runMatrix(arena_state.allocator(), "func main(out: Stream) -> int:\n    run_all(filesystem.memory(), out)\n    return 0\n");
    try testing.expectEqualStrings(expected, printed);
}
