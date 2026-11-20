//! A refused file read names why: the operating system's reason, not the grant policy's
//! (FILE-ERROR-REASON-1).
const std = @import("std");
const testing = std.testing;

/// Reads each argument and prints its error text, one line per path.
const reader =
    \\func main(args: str[], fs: Filesystem, out: Stream) -> int:
    \\    for path in args:
    \\        match fs.read_file(path):
    \\            case Ok(data):
    \\                print(out, path, "ok", len(data))
    \\            case Err(message):
    \\                print(out, message)
    \\    return 0
    \\
;

/// Run `reader` in a fresh directory holding `adir/` and `plain.txt`, with `paths` as its arguments,
/// and return what it printed.
fn printed(paths: []const []const u8, restrict: bool) ![]u8 {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "reader.selka", .data = reader });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "plain.txt", .data = "text" });
    try temporary.dir.createDir(testing.io, "adir", .default_dir);
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compiler, "run", "reader.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path });
    if (restrict) try argv.appendSlice(testing.allocator, &.{ "--restrict", "--allow-read=." });
    try argv.append(testing.allocator, "--");
    try argv.appendSlice(testing.allocator, paths);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = temporary.dir }, .environ_map = &environment });
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return result.stdout;
}

// spec: FILE-ERROR-REASON-1
test "file read errors: a directory, a file used as a parent and a missing file say why" {
    const text = try printed(&.{ "adir", "plain.txt/child", "missing.txt", "plain.txt" }, false);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(
        \\read 'adir': is a directory
        \\read 'plain.txt/child': a parent of the path is not a directory
        \\read 'missing.txt': the path does not exist
        \\plain.txt ok 4
        \\
    , text);
}

// spec-case: FILE-ERROR-REASON-1
test "file read errors: a grant that excludes the path still says so, and a directory inside it still says why" {
    const text = try printed(&.{ "/outside.txt", "adir" }, true);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(
        \\read '/outside.txt': denied: '/outside.txt' is outside the granted directories
        \\read 'adir': is a directory
        \\
    , text);
}
