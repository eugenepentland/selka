//! The toolchain files `zig` reads for the commands the core runs, tracked one by
//! one (K1 of the provable-cache plan, gap 1).
//!
//! A toolchain's library root used to stand for its whole tree through its own
//! status, which an edit inside the tree does not change: a same-size edit of a libc
//! header was served stale on a warm replay. Walking and hashing the 19,600 files of
//! the library on every build costs about 65 ms, so the set tracked is what a build
//! can reach, about 1,200 files and directories:
//! - whole subtrees of Zig sources: `zig` compiles compiler-rt, the C library stubs and the
//!   C runtime from them, and which `std` files a compile opens varies from run to run
//!   (analysis is lazy and concurrent), so every file counts;
//! - the C headers and the glibc stub sources the commands of the core opened under
//!   `strace`, listed in `tool_files.list` (`scripts/audit_cache_reads.py toolchain
//!   --write-list`): preprocessing is deterministic, and a `--link` source's own headers
//!   are tracked per compile by its dependency file instead;
//! - for a thread-sanitizer build, the sanitizer runtime's sources whole.
//! The directories above these files are in the set too, so a file that appears (a header
//! that shadows another on the include path) moves it as well.
//!
//! Each entry's status (size, inode, modification and change time) enters the toolchain's
//! generation, so any edit moves it and the review of the whole tree against the approved
//! digest runs again. `scripts/audit_cache_reads.py toolchain` compares the set with what
//! `zig` opens, so a toolchain upgrade that reads from a new place is found.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");

/// The headers and stub sources the core's commands open, one path below the library root per line.
pub const listed = @embedFile("tool_files.list");

/// Subtrees of a library root whose every file is tracked.
pub const subtrees = [_][]const u8{ "std", "compiler_rt", "c", "libunwind" };

/// Subtrees tracked in addition, whole, for a thread-sanitizer build.
pub const thread_subtrees = [_][]const u8{
    "libtsan",
    "libcxx",
    "libcxxabi",
    "include",
    "libc/include/generic-glibc",
    "libc/include/any-linux-any",
    "libc/include/x86-linux-gnu",
    "libc/include/x86-linux-any",
};

/// Single files of a library root that are tracked.
pub const files = [_][]const u8{ "compiler_rt.zig", "c.zig", "zig.h", "ubsan_rt.zig" };

/// Feed what defines the tracked set (the list, the subtrees and the single files) into `hash`, so
/// that a hint made under another definition is not mistaken for one of this.
pub fn definition(hash: *fast_blake3.Blake3) void {
    definitionOf(hash, listed);
}

/// `definition` for another list of header and stub-source paths.
pub fn definitionOf(hash: *fast_blake3.Blake3, names: []const u8) void {
    hash.update("core-tool-files-definition-v1\x00");
    hash.update(names);
    inline for (.{ subtrees, thread_subtrees, files }) |group| {
        hash.update("\x00group\x00");
        inline for (group) |name| {
            hash.update(name);
            hash.update("\x00");
        }
    }
}

/// What identifies a file's bytes, or a directory's entries, without reading them:
/// the status that changes on replacement, rewriting or truncation of a file and on
/// an entry being added, removed or renamed in a directory.
pub const Mark = struct { size: u64, inode: u64, mtime: i64, ctime: i64, directory: bool };

/// One tracked file or directory: its path below the library root and its status.
pub const Entry = struct { name: []const u8, mark: Mark };

/// Why the tracked set could not be taken.
pub const Error = error{ OutOfMemory, ReadFailed };

/// The tracked files and directories below `root` that exist, in path order (directory,
/// then name), for a build with the thread sanitizer or without. A symbolic link is
/// followed, to a directory too.
pub fn collect(arena: std.mem.Allocator, io: std.Io, root: []const u8, thread: bool) Error![]const Entry {
    return collectListed(arena, io, root, listed, thread);
}

/// `collect` with another list of header and stub-source paths, one per line.
pub fn collectListed(arena: std.mem.Allocator, io: std.Io, root: []const u8, names: []const u8, thread: bool) Error![]const Entry {
    var found: std.ArrayList(Entry) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(arena);
    var queue: std.ArrayList(Walk) = .empty;
    var base = std.Io.Dir.cwd().openDir(io, root, .{}) catch |err| return readError(err);
    defer base.close(io);
    for (files) |name| try add(arena, io, base, name, &found, &seen);
    var lines = std.mem.tokenizeScalar(u8, names, '\n');
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        try add(arena, io, base, line, &found, &seen);
        // The directories above a file move when a file appears beside it.
        var ancestor = std.fs.path.dirname(line);
        while (ancestor) |name| : (ancestor = std.fs.path.dirname(name)) try add(arena, io, base, name, &found, &seen);
    }
    // Zig imports name exact paths, so a file that appears among the sources shadows nothing and
    // their directories are not tracked; a C compile searches directories, so theirs are.
    try queueSubtrees(arena, io, base, &subtrees, false, &queue);
    if (thread) try queueSubtrees(arena, io, base, &thread_subtrees, true, &queue);
    var next: usize = 0;
    while (next < queue.items.len) : (next += 1) {
        if (next > max_directories) return error.ReadFailed;
        const name = queue.items[next].name;
        const directories = queue.items[next].directories;
        if (directories) try add(arena, io, base, name, &found, &seen);
        var directory = base.openDir(io, name, .{ .iterate = true }) catch |err| return readError(err);
        defer directory.close(io);
        var iterator = directory.iterate();
        while (iterator.next(io) catch return error.ReadFailed) |item| {
            const child = try std.fs.path.join(arena, &.{ name, item.name });
            const kind = if (item.kind == .sym_link) (base.statFile(io, child, .{}) catch |err| return readError(err)).kind else item.kind;
            if (kind == .directory) try queue.append(arena, .{ .name = child, .directories = directories }) else try add(arena, io, base, child, &found, &seen);
        }
    }
    std.mem.sort(Entry, found.items, {}, before);
    return found.items;
}

/// A directory to walk, and whether the directories in it are tracked too.
const Walk = struct { name: []const u8, directories: bool };

/// Queue each of `names` that is a directory of the library, to be walked.
fn queueSubtrees(arena: std.mem.Allocator, io: std.Io, base: std.Io.Dir, names: []const []const u8, directories: bool, queue: *std.ArrayList(Walk)) Error!void {
    for (names) |subtree| {
        const status = base.statFile(io, subtree, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => continue,
            else => return readError(err),
        };
        if (status.kind == .directory) try queue.append(arena, .{ .name = subtree, .directories = directories });
    }
}

/// More directories than any toolchain has: a loop of symbolic links, not a library.
const max_directories = 1 << 16;

fn add(arena: std.mem.Allocator, io: std.Io, base: std.Io.Dir, name: []const u8, found: *std.ArrayList(Entry), seen: *std.StringHashMapUnmanaged(void)) Error!void {
    if ((try seen.getOrPut(arena, name)).found_existing) return;
    const status = base.statFile(io, name, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return,
        else => return readError(err),
    };
    try found.append(arena, .{ .name = try arena.dupe(u8, name), .mark = markOf(status) });
}

/// How many threads check a set at most: the checks are system calls on warm directory entries,
/// so a few cores shorten the wait of every replay, and more would cost more to start than they save.
const check_threads = 4;

/// The smallest set worth sharing among threads.
const share_from = 256;

/// Whether every tracked file and directory under `root` still has the status
/// recorded. A file added to a tracked directory moves that directory's status. A large
/// set is checked by a few threads at once, each taking whole directories.
pub fn unchanged(io: std.Io, root: []const u8, entries: []const Entry) bool {
    if (entries.len < share_from) return unchangedRange(io, root, entries);
    const cuts = splitPoints(entries);
    var failed: std.atomic.Value(bool) = .init(false);
    var threads: [check_threads - 1]?std.Thread = @splat(null);
    for (&threads, 1..) |*slot, index| {
        if (cuts[index] == cuts[index + 1]) continue;
        // The default stack: a libc-linked binary refuses a stack smaller than its static thread-local
        // block (see `tool_identity.zig`), and an explicit 128 KiB request panics there instead of failing.
        slot.* = std.Thread.spawn(.{}, checkRange, .{ io, root, entries[cuts[index]..cuts[index + 1]], &failed }) catch null;
        // A thread that cannot start is run here, after the first range.
        if (slot.* == null) checkRange(io, root, entries[cuts[index]..cuts[index + 1]], &failed);
    }
    checkRange(io, root, entries[cuts[0]..cuts[1]], &failed);
    for (threads) |slot| if (slot) |thread| thread.join();
    return !failed.load(.acquire);
}

/// Where a set is cut into `check_threads` ranges of about the same size.
fn splitPoints(entries: []const Entry) [check_threads + 1]usize {
    var cuts: [check_threads + 1]usize = undefined;
    for (&cuts, 0..) |*cut, index| cut.* = entries.len * index / check_threads;
    return cuts;
}

fn checkRange(io: std.Io, root: []const u8, entries: []const Entry, failed: *std.atomic.Value(bool)) void {
    if (!unchangedRange(io, root, entries)) failed.store(true, .release);
}

fn unchangedRange(io: std.Io, root: []const u8, entries: []const Entry) bool {
    var base = std.Io.Dir.cwd().openDir(io, root, .{}) catch return false;
    defer base.close(io);
    for (entries) |entry| {
        const status = base.statFile(io, entry.name, .{}) catch return false;
        if (!std.meta.eql(markOf(status), entry.mark)) return false;
    }
    return true;
}

/// The digest of the set: the names and status of every file and directory, which stands for
/// the whole set in a generation. A hint keeps it beside the set, so a generation does not hash
/// thousands of entries again.
pub fn digest(entries: []const Entry) [32]u8 {
    var hash = fast_blake3.Blake3.init(.{});
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    word(&buffer, &used, &hash, entries.len);
    for (entries) |entry| {
        if (used + entry.name.len + 48 > buffer.len) flush(&buffer, &used, &hash);
        word(&buffer, &used, &hash, entry.name.len);
        if (entry.name.len > buffer.len) {
            hash.update(entry.name);
        } else {
            @memcpy(buffer[used..][0..entry.name.len], entry.name);
            used += entry.name.len;
        }
        word(&buffer, &used, &hash, entry.mark.size);
        word(&buffer, &used, &hash, entry.mark.inode);
        word(&buffer, &used, &hash, @bitCast(entry.mark.mtime));
        word(&buffer, &used, &hash, @bitCast(entry.mark.ctime));
        word(&buffer, &used, &hash, @intFromBool(entry.mark.directory));
    }
    flush(&buffer, &used, &hash);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}

fn word(buffer: *[4096]u8, used: *usize, hash: *fast_blake3.Blake3, value: u64) void {
    if (used.* + 8 > buffer.len) flush(buffer, used, hash);
    std.mem.writeInt(u64, buffer[used.*..][0..8], value, .little);
    used.* += 8;
}

fn flush(buffer: *[4096]u8, used: *usize, hash: *fast_blake3.Blake3) void {
    hash.update(buffer[0..used.*]);
    used.* = 0;
}

/// Feed the bytes of every tracked file into a content identity, refusing a file
/// whose status is no longer the one recorded.
pub fn contentInto(io: std.Io, root: []const u8, entries: []const Entry, hash: *fast_blake3.Blake3) error{ ReadFailed, SourceChanged }!void {
    var base = std.Io.Dir.cwd().openDir(io, root, .{}) catch return error.ReadFailed;
    defer base.close(io);
    var buffer: [64 << 10]u8 = undefined;
    for (entries) |entry| {
        if (entry.mark.directory) continue;
        const file = base.openFile(io, entry.name, .{}) catch return error.ReadFailed;
        defer file.close(io);
        const before_status = file.stat(io) catch return error.ReadFailed;
        if (!std.meta.eql(markOf(before_status), entry.mark)) return error.SourceChanged;
        var reader_hash = fast_blake3.Blake3.init(.{});
        var offset: u64 = 0;
        while (true) {
            const count = file.readPositionalAll(io, &buffer, offset) catch return error.ReadFailed;
            reader_hash.update(buffer[0..count]);
            offset += count;
            if (count < buffer.len) break;
        }
        const after_status = file.stat(io) catch return error.ReadFailed;
        if (offset != entry.mark.size or !std.meta.eql(markOf(after_status), entry.mark)) return error.SourceChanged;
        var content: [32]u8 = undefined;
        reader_hash.final(&content);
        hash.update(&content);
    }
}

/// Write the set: a count, then each file's name length, name and status.
pub fn encode(writer: *std.Io.Writer, entries: []const Entry) std.Io.Writer.Error!void {
    try writer.writeInt(u32, @intCast(entries.len), .little);
    for (entries) |entry| {
        try writer.writeInt(u32, @intCast(entry.name.len), .little);
        try writer.writeAll(entry.name);
        try writer.writeInt(u64, entry.mark.size, .little);
        try writer.writeInt(u64, entry.mark.inode, .little);
        try writer.writeInt(i64, entry.mark.mtime, .little);
        try writer.writeInt(i64, entry.mark.ctime, .little);
        try writer.writeByte(@intFromBool(entry.mark.directory));
    }
}

/// Read what `encode` wrote. Names borrow from the reader's buffer; the caller has already
/// checked the bytes against their checksum.
pub fn decode(arena: std.mem.Allocator, reader: *std.Io.Reader) (std.Io.Reader.Error || error{ OutOfMemory, Malformed })![]const Entry {
    const count = try reader.takeInt(u32, .little);
    if (count > 1 << 20) return error.Malformed;
    const entries = try arena.alloc(Entry, count);
    for (entries) |*entry| {
        const name = try reader.take(try reader.takeInt(u32, .little));
        entry.* = .{ .name = name, .mark = .{
            .size = try reader.takeInt(u64, .little),
            .inode = try reader.takeInt(u64, .little),
            .mtime = try reader.takeInt(i64, .little),
            .ctime = try reader.takeInt(i64, .little),
            .directory = (try reader.takeByte()) != 0,
        } };
    }
    return entries;
}

fn markOf(status: std.Io.File.Stat) Mark {
    return .{ .size = status.size, .inode = @intCast(status.inode), .mtime = clamp(status.mtime.nanoseconds), .ctime = clamp(status.ctime.nanoseconds), .directory = status.kind == .directory };
}

fn clamp(nanoseconds: i96) i64 {
    return std.math.cast(i64, nanoseconds) orelse if (nanoseconds < 0) std.math.minInt(i64) else std.math.maxInt(i64);
}

/// Directory first, then name, so the files of one directory are consecutive.
fn before(_: void, left: Entry, right: Entry) bool {
    const left_parent = std.fs.path.dirname(left.name) orelse "";
    const right_parent = std.fs.path.dirname(right.name) orelse "";
    const order = std.mem.order(u8, left_parent, right_parent);
    if (order != .eq) return order == .lt;
    return std.mem.lessThan(u8, std.fs.path.basename(left.name), std.fs.path.basename(right.name));
}

fn readError(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
}

const fixture_list = "# the headers of the fixture\ninclude/stdbool.h\nlibc/include/generic-glibc/stdio.h\n";

const Fixture = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        self.* = .{ .temporary = std.testing.tmpDir(.{}), .arena = .init(allocator) };
        errdefer self.release();
        try self.temporary.dir.createDirPath(std.testing.io, "lib/std/os");
        try self.temporary.dir.createDirPath(std.testing.io, "lib/include");
        try self.temporary.dir.createDirPath(std.testing.io, "lib/libc/include/generic-glibc");
        try self.temporary.dir.createDirPath(std.testing.io, "lib/libc/include/x86_64-freebsd-none");
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/std.zig", .data = "std" });
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/os/linux.zig", .data = "linux" });
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/include/stdbool.h", .data = "#define true 1\n" });
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/libc/include/generic-glibc/stdio.h", .data = "stdio" });
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/libc/include/x86_64-freebsd-none/stdio.h", .data = "bsd" });
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/compiler_rt.zig", .data = "rt" });
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/README", .data = "not tracked" });
        return self;
    }

    fn release(self: *Fixture) void {
        self.arena.deinit();
        self.temporary.cleanup();
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.release();
        allocator.destroy(self);
    }

    fn root(self: *Fixture) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", self.arena.allocator()), "lib" });
    }
};

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "the tracked set is the Zig sources, the listed headers with their directories, and single files, ordered by directory" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, try fixture.root(), fixture_list, false);
    try std.testing.expectEqual(@as(usize, 9), found.len);
    try std.testing.expectEqualStrings("compiler_rt.zig", found[0].name);
    try std.testing.expectEqualStrings("include", found[1].name);
    try std.testing.expect(found[1].mark.directory);
    try std.testing.expectEqualStrings("libc", found[2].name);
    try std.testing.expectEqualStrings("include/stdbool.h", found[3].name);
    try std.testing.expectEqualStrings("libc/include", found[4].name);
    try std.testing.expectEqualStrings("libc/include/generic-glibc", found[5].name);
    try std.testing.expectEqualStrings("libc/include/generic-glibc/stdio.h", found[6].name);
    try std.testing.expectEqualStrings("std/std.zig", found[7].name);
    try std.testing.expectEqualStrings("std/os/linux.zig", found[8].name);
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "an edit of a tracked file moves the set whatever the edit keeps, and an untracked file does not" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const root = try fixture.root();
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try std.testing.expect(unchanged(std.testing.io, root, found));
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/README", .data = "edited" });
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/libc/include/x86_64-freebsd-none/stdio.h", .data = "other" });
    try std.testing.expect(unchanged(std.testing.io, root, found));
    // The same size, with the modification time put back: the change time still moves.
    const before_edit = try fixture.temporary.dir.statFile(std.testing.io, "lib/include/stdbool.h", .{});
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/include/stdbool.h", .data = "#define true 0\n" });
    try fixture.temporary.dir.setTimestamps(std.testing.io, "lib/include/stdbool.h", .{ .modify_timestamp = .init(before_edit.mtime) });
    try std.testing.expect(!unchanged(std.testing.io, root, found));
}

// A set of `share_from` entries or more is checked by threads of their own; a libc-linked binary
// aborted here before the threads took the default stack.
test "a large set is checked on threads, and an edit in it still moves the set" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const arena = fixture.arena.allocator();
    const root = try fixture.root();
    const found = try collectListed(arena, std.testing.io, root, fixture_list, false);
    const large = try arena.alloc(Entry, share_from + 44);
    for (large, 0..) |*entry, index| entry.* = found[index % found.len];
    try std.testing.expect(unchanged(std.testing.io, root, large));
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/include/stdbool.h", .data = "#define true 0 /* changed */\n" });
    try std.testing.expect(!unchanged(std.testing.io, root, large));
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "a file that appears in a tracked directory, or in a tracked place that did not exist, moves the set" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const root = try fixture.root();
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/include/stdint.h", .data = "shadow" });
    try std.testing.expect(!unchanged(std.testing.io, root, found));
    const second = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try std.testing.expect(unchanged(std.testing.io, root, second));
    // A header directory beside the ones `zig` opened headers from is made: their parent moves.
    try fixture.temporary.dir.createDirPath(std.testing.io, "lib/libc/include/x86-linux-any");
    try std.testing.expect(!unchanged(std.testing.io, root, second));
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "a tracked file that goes away moves the set, and the set survives its stored form" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const a = fixture.arena.allocator();
    const root = try fixture.root();
    const found = try collectListed(a, std.testing.io, root, fixture_list, false);
    var written: std.Io.Writer.Allocating = .init(a);
    try encode(&written.writer, found);
    var reader = std.Io.Reader.fixed(written.written());
    const decoded = try decode(a, &reader);
    try std.testing.expectEqual(found.len, decoded.len);
    try std.testing.expectEqualStrings(found[8].name, decoded[8].name);
    try std.testing.expectEqual(found[8].mark, decoded[8].mark);
    try std.testing.expectEqual(digest(found), digest(decoded));
    try std.testing.expect(!std.mem.eql(u8, &digest(found), &digest(found[1..])));
    try fixture.temporary.dir.deleteFile(std.testing.io, "lib/std/os/linux.zig");
    try std.testing.expect(!unchanged(std.testing.io, root, decoded));
    var truncated = std.Io.Reader.fixed(written.written()[0 .. written.written().len - 3]);
    try std.testing.expectError(error.EndOfStream, decode(a, &truncated));
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "the content of the tracked files reaches the identity and a file that changed under the read is refused" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const root = try fixture.root();
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    var one = fast_blake3.Blake3.init(.{});
    try contentInto(std.testing.io, root, found, &one);
    var again = fast_blake3.Blake3.init(.{});
    try contentInto(std.testing.io, root, found, &again);
    var first: [32]u8 = undefined;
    var second: [32]u8 = undefined;
    one.final(&first);
    again.final(&second);
    try std.testing.expectEqual(first, second);
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/std.zig", .data = "other" });
    var changed = fast_blake3.Blake3.init(.{});
    try std.testing.expectError(error.SourceChanged, contentInto(std.testing.io, root, found, &changed));
}

/// Many directories of many files, enough to be shared among threads.
fn populate(directory: std.Io.Dir) !void {
    var name: [32]u8 = undefined;
    for (0..12) |group| {
        const folder = try std.fmt.bufPrint(&name, "lib/std/group{d}", .{group});
        try directory.createDirPath(std.testing.io, folder);
        for (0..30) |member| {
            var path: [64]u8 = undefined;
            try directory.writeFile(std.testing.io, .{ .sub_path = try std.fmt.bufPrint(&path, "{s}/member{d}.zig", .{ folder, member }), .data = "pub const x = 1;" });
        }
    }
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "a large set is checked by several threads and one change anywhere in it is found" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try populate(fixture.temporary.dir);
    const root = try fixture.root();
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try std.testing.expect(found.len >= share_from);
    try std.testing.expect(unchanged(std.testing.io, root, found));
    // The first directory, one near the middle and the last file all sit in different ranges.
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/group0/member0.zig", .data = "pub const x = 2;" });
    try std.testing.expect(!unchanged(std.testing.io, root, found));
    const again = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try std.testing.expect(unchanged(std.testing.io, root, again));
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/group6/member15.zig", .data = "pub const x = 2;" });
    try std.testing.expect(!unchanged(std.testing.io, root, again));
    const third = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try fixture.temporary.dir.deleteFile(std.testing.io, "lib/std/std.zig");
    try std.testing.expect(!unchanged(std.testing.io, root, third));
    const fourth = try collectListed(fixture.arena.allocator(), std.testing.io, root, fixture_list, false);
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/group11/member29.zig", .data = "pub const x = 3;" });
    try std.testing.expect(!unchanged(std.testing.io, root, fourth));
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "a set is cut into ranges that cover every entry once" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try populate(fixture.temporary.dir);
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, try fixture.root(), fixture_list, false);
    const cuts = splitPoints(found);
    try std.testing.expectEqual(@as(usize, 0), cuts[0]);
    try std.testing.expectEqual(found.len, cuts[check_threads]);
    try std.testing.expect(std.sort.isSorted(usize, &cuts, {}, std.sort.asc(usize)));
    try std.testing.expect(cuts[1] > 0 and cuts[check_threads - 1] < found.len);
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "the directories of Zig sources are not tracked, those of headers are" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const found = try collectListed(fixture.arena.allocator(), std.testing.io, try fixture.root(), fixture_list, false);
    var sources: usize = 0;
    var header_directories: usize = 0;
    for (found) |entry| {
        if (std.mem.startsWith(u8, entry.name, "std") and entry.mark.directory) sources += 1;
        if (std.mem.startsWith(u8, entry.name, "libc/include") and entry.mark.directory) header_directories += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), sources);
    try std.testing.expectEqual(@as(usize, 2), header_directories);
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "the definition of the set follows the list of headers" {
    var first = fast_blake3.Blake3.init(.{});
    var again = fast_blake3.Blake3.init(.{});
    var other = fast_blake3.Blake3.init(.{});
    definitionOf(&first, fixture_list);
    definitionOf(&again, fixture_list);
    definitionOf(&other, "include/stdbool.h\n");
    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    var c: [32]u8 = undefined;
    first.final(&a);
    again.final(&b);
    other.final(&c);
    try std.testing.expectEqual(a, b);
    try std.testing.expect(!std.mem.eql(u8, &a, &c));
}
