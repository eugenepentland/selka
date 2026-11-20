//! The compiler's work directory keeps itself out of git and backups: a `.gitignore` of `*` and a `CACHEDIR.TAG`, written
//! once when the directory is made by a build, check or test, and never over a file that is already there.
const std = @import("std");
const testing = std.testing;

const program = "func main(out: Stream) -> int:\n    print(out, \"hi\")\n    return 0\n";
const unit_test = "public func test_it() -> bool:\n    return True\n";
const tag_signature = "Signature: 8a477f597d28d172789f06886806bc55\n";

/// Run `argv` (the compiler first) in `dir` with the shared stores off; the caller frees the result.
fn run(dir: std.Io.Dir, args: []const []const u8) !std.process.RunResult {
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, compiler);
    try argv.appendSlice(testing.allocator, args);
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir }, .environ_map = &environment });
}

fn succeeded(result: std.process.RunResult) !void {
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

fn release(result: std.process.RunResult) void {
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}

/// Both marker files under `folder` of `dir` hold what the compiler writes.
fn expectMarkers(dir: std.Io.Dir, folder: []const u8) !void {
    const ignore = try std.fs.path.join(testing.allocator, &.{ folder, ".gitignore" });
    defer testing.allocator.free(ignore);
    const tag = try std.fs.path.join(testing.allocator, &.{ folder, "CACHEDIR.TAG" });
    defer testing.allocator.free(tag);
    const ignored = try dir.readFileAlloc(testing.io, ignore, testing.allocator, .limited(4096));
    defer testing.allocator.free(ignored);
    const tagged = try dir.readFileAlloc(testing.io, tag, testing.allocator, .limited(4096));
    defer testing.allocator.free(tagged);
    try testing.expectEqualStrings("*\n", ignored);
    try testing.expect(std.mem.startsWith(u8, tagged, tag_signature));
}

test "a build in an empty folder leaves the markers, git sees only the program, and a replay rewrites neither file" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = program });
    const init = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ "git", "init", "-q", "." }, .cwd = .{ .dir = temp.dir } });
    release(init);
    const first = try run(temp.dir, &.{ "build", "main.selka", "-o", "prog", "--report" });
    defer release(first);
    try succeeded(first);
    try testing.expect(std.mem.indexOf(u8, first.stderr, "\"program\":\"linked\"") != null);
    try expectMarkers(temp.dir, ".selka-cache");
    const status = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ "git", "status", "--porcelain", "--untracked-files=all" }, .cwd = .{ .dir = temp.dir } });
    defer release(status);
    try testing.expectEqualStrings("?? main.selka\n?? prog\n", status.stdout);
    // Dated long ago, so that any rewrite shows; an unchanged build replays and touches neither.
    for ([_][]const u8{ ".selka-cache/.gitignore", ".selka-cache/CACHEDIR.TAG" }) |leaf| try temp.dir.setTimestamps(testing.io, leaf, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 5 * std.time.ns_per_s } } });
    const again = try run(temp.dir, &.{ "build", "main.selka", "-o", "prog", "--report" });
    defer release(again);
    try succeeded(again);
    try testing.expect(std.mem.indexOf(u8, again.stderr, "\"program\":\"replayed\"") != null);
    for ([_][]const u8{ ".selka-cache/.gitignore", ".selka-cache/CACHEDIR.TAG" }) |leaf| {
        const stat = try temp.dir.statFile(testing.io, leaf, .{});
        try testing.expectEqual(@as(i96, 5 * std.time.ns_per_s), stat.mtime.nanoseconds);
    }
}

test "a check and a test of a project leave the markers too, and a .gitignore that was there is left alone" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = program });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main_test.selka", .data = unit_test });
    const checked = try run(temp.dir, &.{ "check", "main.selka" });
    defer release(checked);
    try succeeded(checked);
    try expectMarkers(temp.dir, ".selka-cache");
    try temp.dir.deleteTree(testing.io, ".selka-cache");
    try temp.dir.createDirPath(testing.io, ".selka-cache");
    try temp.dir.writeFile(testing.io, .{ .sub_path = ".selka-cache/.gitignore", .data = "mine\n" });
    const tested = try run(temp.dir, &.{ "test", "main_test.selka" });
    defer release(tested);
    try succeeded(tested);
    const kept = try temp.dir.readFileAlloc(testing.io, ".selka-cache/.gitignore", testing.allocator, .limited(64));
    defer testing.allocator.free(kept);
    try testing.expectEqualStrings("mine\n", kept);
    const tag = try temp.dir.readFileAlloc(testing.io, ".selka-cache/CACHEDIR.TAG", testing.allocator, .limited(4096));
    defer testing.allocator.free(tag);
    try testing.expect(std.mem.startsWith(u8, tag, tag_signature));
}

test "a --cache-dir the command makes gets the markers, and a folder that was already there is not hidden" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = program });
    try temp.dir.createDirPath(testing.io, "sources");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "sources/keep.txt", .data = "mine" });
    const built = try run(temp.dir, &.{ "build", "main.selka", "-o", "prog", "--cache-dir", "out/store" });
    defer release(built);
    try succeeded(built);
    try expectMarkers(temp.dir, "out/store");
    const checked = try run(temp.dir, &.{ "check", "main.selka", "--cache-dir", "out/checks" });
    defer release(checked);
    try succeeded(checked);
    try expectMarkers(temp.dir, "out/checks");
    const named = try run(temp.dir, &.{ "build", "main.selka", "-o", "prog2", "--cache-dir", "sources" });
    defer release(named);
    try succeeded(named);
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "sources/.gitignore", .{}));
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "sources/CACHEDIR.TAG", .{}));
}

test "a command that makes no work directory leaves no .selka-cache behind" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = program });
    const formatted = try run(temp.dir, &.{ "fmt", "main.selka" });
    defer release(formatted);
    try succeeded(formatted);
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, ".selka-cache", .{}));
}
