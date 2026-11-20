//! A refused directory operation names why: `mkdir` of a directory that exists, of one whose parent is
//! missing or is a file, `listdir` of a file and `remove` of a directory that is not empty
//! (MKDIR-ERROR-REASON-1).
const std = @import("std");
const testing = std.testing;

/// Runs one operation per argument, `name:path`, and prints the error text or `ok`, one line each.
const operations =
    \\import strings
    \\
    \\func show(out: Stream, result: Result[Unit, str]):
    \\    match result:
    \\        case Ok(_):
    \\            print(out, "ok")
    \\        case Err(message):
    \\            print(out, message)
    \\
    \\
    \\func main(args: str[], fs: Filesystem, out: Stream) -> int:
    \\    for arg in args:
    \\        if strings.starts_with(arg, "mkdir:"):
    \\            show(out, fs.mkdir(strings.char_slice(arg, 6, None)))
    \\        elif strings.starts_with(arg, "remove:"):
    \\            show(out, fs.remove(strings.char_slice(arg, 7, None)))
    \\        else:
    \\            match fs.listdir(strings.char_slice(arg, 8, None)):
    \\                case Ok(_):
    \\                    print(out, "ok")
    \\                case Err(message):
    \\                    print(out, message)
    \\    return 0
    \\
;

/// Run `operations` in a fresh directory holding `adir/`, `full/inner` and `plain.txt`, with `requests` as
/// its arguments, and return what it printed.
fn printed(requests: []const []const u8) ![]u8 {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "operations.selka", .data = operations });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "plain.txt", .data = "text" });
    try temporary.dir.createDir(testing.io, "adir", .default_dir);
    try temporary.dir.createDirPath(testing.io, "full/inner");
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compiler, "run", "operations.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path, "--" });
    try argv.appendSlice(testing.allocator, requests);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = temporary.dir }, .environ_map = &environment });
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return result.stdout;
}

// spec: MKDIR-ERROR-REASON-1
test "directory errors: mkdir, listdir and remove say why the operating system refused" {
    const text = try printed(&.{ "mkdir:adir", "mkdir:missing/child", "mkdir:plain.txt/child", "listdir:plain.txt", "remove:full", "mkdir:fresh" });
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(
        \\mkdir 'adir': already exists
        \\mkdir 'missing/child': the parent directory does not exist
        \\mkdir 'plain.txt/child': a parent of the path is not a directory
        \\listdir 'plain.txt': is not a directory
        \\remove 'full': the directory is not empty
        \\ok
        \\
    , text);
}
