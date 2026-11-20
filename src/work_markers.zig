//! The two files that keep a work directory out of git and out of backups: a `.gitignore` of `*` and a `CACHEDIR.TAG`.
//! A build, check or test of a project writes its caches into `.selka-cache` (or the folder `--cache-dir` names) in the
//! folder it runs in, and `git add -A` there would commit tens of thousands of files; the markers stop that.
const std = @import("std");
const product = @import("product.zig");

/// The `.gitignore` a work directory gets: it ignores everything in the folder, itself included.
pub const ignore_file = ".gitignore";
/// The file backup tools read to skip a cache folder (https://bford.info/cachedir/); its first line is the signature.
pub const tag_file = "CACHEDIR.TAG";
/// The tag's text: the signature line, then the standard comment.
pub const tag_text = "Signature: 8a477f597d28d172789f06886806bc55\n" ++
    "# This file is a cache directory tag created by selka.\n" ++
    "# For information about cache directory tags, see:\n" ++
    "#\thttps://bford.info/cachedir/\n";
/// The compiler's own cache folder, whose marker files are kept even when it already exists.
pub const own_directory = product.work_dir;

/// The folder the markers go in: `work` up to its last `.selka-cache` component (the default work directory is
/// `.selka-cache/core`, and other commands keep their stores beside `core`), else `work` itself.
pub fn markerRoot(work: []const u8) []const u8 {
    var found: ?usize = null;
    var start: usize = 0;
    while (start <= work.len) {
        const end = std.mem.indexOfScalarPos(u8, work, start, '/') orelse work.len;
        if (std.mem.eql(u8, work[start..end], own_directory)) found = end;
        start = end + 1;
    }
    return work[0 .. found orelse work.len];
}

/// Whether the folder `work` keeps its markers in is absent: asked before a command opens its stores, and handed to `mark`.
pub fn fresh(io: std.Io, work: []const u8) bool {
    std.Io.Dir.cwd().access(io, markerRoot(work), .{}) catch return true;
    return false;
}

/// Give the work directory `work` its two marker files, each only when absent and only in a folder that exists (it never makes
/// one). The compiler's own `.selka-cache` always gets them; any other folder only when `was_fresh` (`fresh`, asked before the
/// command ran) says this command made it, so `--cache-dir .` or a folder that holds someone's sources is never hidden from
/// git. Best effort: a command never fails for a marker it could not write.
pub fn mark(a: std.mem.Allocator, io: std.Io, work: []const u8, was_fresh: bool) void {
    const root = markerRoot(work);
    const own = root.len != work.len or std.mem.eql(u8, std.fs.path.basename(work), own_directory);
    if (!own and !was_fresh) return;
    writeOnce(a, io, root, ignore_file, "*\n");
    writeOnce(a, io, root, tag_file, tag_text);
}

fn writeOnce(a: std.mem.Allocator, io: std.Io, root: []const u8, leaf: []const u8, text: []const u8) void {
    const path = std.fs.path.join(a, &.{ root, leaf }) catch return;
    defer a.free(path);
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true }) catch return;
    defer file.close(io);
    file.writeStreamingAll(io, text) catch return removeUnfinished(io, path);
}

/// Take away a marker that was created but not written, so that the next command writes it again.
fn removeUnfinished(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return,
    };
}

test "the marker folder is the last .selka-cache component of the work directory, else the directory itself" {
    try std.testing.expectEqualStrings(".selka-cache", markerRoot(".selka-cache/core"));
    try std.testing.expectEqualStrings(".selka-cache", markerRoot(".selka-cache"));
    try std.testing.expectEqualStrings("/p/.selka-cache", markerRoot("/p/.selka-cache/core"));
    try std.testing.expectEqualStrings("/p/out/cache", markerRoot("/p/out/cache"));
    try std.testing.expectEqualStrings(".selka-cache-core", markerRoot(".selka-cache-core"));
}

test "the tag starts with the standard signature line" {
    try std.testing.expect(std.mem.startsWith(u8, tag_text, "Signature: 8a477f597d28d172789f06886806bc55\n"));
}

test "marking makes no folder: a command that left no work directory leaves no markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const work = try std.fs.path.join(a, &.{ root, ".selka-cache", "core" });
    try std.testing.expect(fresh(io, work));
    mark(a, io, work, true);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, try std.fs.path.join(a, &.{ root, ".selka-cache" }), .{}));
}
