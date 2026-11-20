//! The work directory's linked programs (`programs-v2/`). A program is named by its exact key and by its
//! family, the compile arguments of the mode it was built in, so each family keeps its newest few programs
//! (`per_family`) and the leftovers of old edits go first. A private program that the per-user compiler
//! store also holds is a hardlink to that store's executable, so no executable is stored twice.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const unit_cache = @import("unit_cache.zig");
const Digest = unit_cache.Digest;

/// The directory of linked programs. Its name carries the layout: `<key>.<family>` beside `<key>.<family>.sum`.
pub const directory_name = "programs-v2";

/// How many programs of one family the directory keeps, newest first.
pub const per_family = 4;

/// The family of a program: the identity of what it links (`entry`: a build's entry, or a test program's file
/// and case) and its mode's compile argument list (`build_mode.Mode.keyed`). It does not depend on the program's
/// bytes, so every edit of one entry is one family, and a directory of many test programs keeps each one's newest
/// four. The compiler's identity is not part of it, because a program's bytes do not depend on the compiler that linked it.
pub fn family(entry: []const u8, compile: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-program-family-v2");
    unit_cache.field(&hash, entry);
    unit_cache.field(&hash, compile);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// The name suffix that places a program of `family_digest` beside its key (`unit_cache.Store` appends it).
pub fn suffix(a: std.mem.Allocator, family_digest: Digest) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, ".{s}", .{std.fmt.bytesToHex(family_digest, .lower)});
}

/// Remove the programs of `family_digest` in `directory` beyond the newest `per_family`, with their sidecars,
/// oldest first. A program is as new as its sidecar, which the directory wrote when it published the program, or touched when a replay
/// last served it (`markUsed`), so the programs kept are the ones used last, not the ones linked last. The
/// program's own file says nothing about that: a program restored from the shared store is a second name for the
/// shared record, so its file keeps the time the program was first linked anywhere, and ranking by it would
/// remove the program just restored (F49). Best effort: a program removed here only costs a later miss, and a
/// directory that cannot be read keeps everything.
pub fn keepNewest(a: std.mem.Allocator, io: std.Io, directory: []const u8, family_digest: Digest) std.mem.Allocator.Error!void {
    const wanted = try suffix(a, family_digest);
    defer a.free(wanted);
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return;
    defer dir.close(io);
    const Named = struct { name: []const u8, written: i96 };
    var found: std.ArrayList(Named) = .empty;
    defer found.deinit(a);
    var entries = dir.iterate();
    while (entries.next(io) catch return) |entry| {
        if (entry.kind != .file or !isProgram(entry.name, wanted)) continue;
        try found.append(a, .{ .name = try a.dupe(u8, entry.name), .written = publishedAt(a, io, dir, entry.name) });
    }
    if (found.items.len <= per_family) return;
    std.mem.sort(Named, found.items, {}, struct {
        fn newer(_: void, left: Named, right: Named) bool {
            return left.written > right.written or (left.written == right.written and std.mem.lessThan(u8, left.name, right.name));
        }
    }.newer);
    for (found.items[per_family..]) |item| {
        removeQuietly(dir, io, item.name);
        const sidecar = std.fmt.allocPrint(a, "{s}.sum", .{item.name}) catch continue;
        defer a.free(sidecar);
        removeQuietly(dir, io, sidecar);
    }
}

/// Mark the program at `path` as used now: its sidecar takes the current time, which is what `keepNewest` ranks by. A replay serves a program without
/// publishing it again, so without this a program every build returns to would age out behind four newer ones (F58). The sidecar is written by the
/// work directory that publishes the program; the program itself is left alone, because its file status is what a replay record compares. Best
/// effort: a program that is gone, or a file system that refuses, only leaves the program where it was.
pub fn markUsed(a: std.mem.Allocator, io: std.Io, path: []const u8) void {
    const sidecar = std.fmt.allocPrint(a, "{s}.sum", .{path}) catch return;
    defer a.free(sidecar);
    stampUsed(io, sidecar);
}

/// Set the modification time of the regular file at `path` to now, which is how this directory's stores rank a file by use. A file with a second
/// name (a hard link, which nothing in the compiler makes of a sidecar or a replay record) and a symbolic link are left alone: moving their time would
/// move the order in whichever other directory holds them. Best effort; a missing file is no error.
pub fn stampUsed(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    const status = cwd.statFile(io, path, .{ .follow_symlinks = false }) catch return;
    if (status.kind != .file or status.nlink != 1) return;
    cwd.setTimestampsNow(io, path, .{ .follow_symlinks = false }) catch return;
}

/// When `directory` published the program `name`, or last had it served by a replay (`markUsed`): the modification time of its sidecar. A program
/// without one cannot be served, so it ranks as the oldest.
fn publishedAt(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, name: []const u8) i96 {
    const sidecar = std.fmt.allocPrint(a, "{s}.sum", .{name}) catch return std.math.minInt(i96);
    defer a.free(sidecar);
    const status = directory.statFile(io, sidecar, .{ .follow_symlinks = false }) catch return std.math.minInt(i96);
    return status.mtime.nanoseconds;
}

/// Whether `name` is `<64 hex>` followed by `suffix`: a program of that family, not its sidecar or a partial.
fn isProgram(name: []const u8, suffix_text: []const u8) bool {
    if (!std.mem.endsWith(u8, name, suffix_text) or name.len != 64 + suffix_text.len) return false;
    for (name[0..64]) |byte| {
        const decimal = byte >= '0' and byte <= '9';
        const letter = byte >= 'a' and byte <= 'f';
        if (!decimal and !letter) return false;
    }
    return true;
}

/// Pin the program at `source` under `destination`, a private name the caller owns: a hardlink (or a copy when
/// linking fails), so the bytes stay whole even if the store removes its own name afterwards. False when `source`
/// is gone, which is a miss: nothing is written to `destination`. The caller then links the program afresh.
pub fn pin(io: std.Io, source: []const u8, destination: []const u8) std.mem.Allocator.Error!bool {
    _ = share(io, source, destination, hardLink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return false,
    };
    return true;
}

/// Make the file at `destination` a second name for the file at `source`. The hardlink step is a
/// parameter so that its fallback is testable; `hardLink` is the real one.
pub const Linker = *const fn (io: std.Io, source: []const u8, destination: []const u8) std.Io.Dir.HardLinkError!void;

/// The real hardlink step: a second name for `source`, on the same file system.
pub fn hardLink(io: std.Io, source: []const u8, destination: []const u8) std.Io.Dir.HardLinkError!void {
    const cwd = std.Io.Dir.cwd();
    try cwd.hardLink(source, cwd, destination, io, .{});
}

/// Make `destination`, a file that already holds `source`'s bytes, a second name for `source`'s file when `link` allows one,
/// replacing it by one rename. False, with `destination` untouched, when the link is refused (another file system, no hard links):
/// the bytes are equal, so a copy would only rewrite them.
pub fn relink(io: std.Io, source: []const u8, destination: []const u8, link: Linker) bool {
    // Already one file under two names (a record published as a hardlink of this very program): nothing to replace, and a replacement would
    // only move the file's change time.
    if (sameFile(source, destination)) return true;
    const cwd = std.Io.Dir.cwd();
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    var buffer: [std.fs.max_path_bytes + 64]u8 = undefined;
    const staged = std.fmt.bufPrint(&buffer, "{s}.{s}.link.partial", .{ destination, std.fmt.bytesToHex(nonce, .lower) }) catch return false;
    removeQuietly(cwd, io, staged);
    link(io, source, staged) catch return false;
    cwd.rename(staged, cwd, destination, io) catch {
        removeQuietly(cwd, io, staged);
        return false;
    };
    // When `destination` already names the file at `source`, the rename does nothing and `staged` stays behind: remove it.
    removeQuietly(cwd, io, staged);
    return true;
}

/// Replace `destination` with `source`'s bytes: a hardlink when `link` allows one (no bytes copied), else a
/// copy (across file systems, for instance). Returns true for a link. The replacement is one rename, so a
/// reader sees the old file or the new one, never a partial.
pub fn share(io: std.Io, source: []const u8, destination: []const u8, link: Linker) (std.mem.Allocator.Error || error{WriteFailed})!bool {
    const cwd = std.Io.Dir.cwd();
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    // The staged name is the destination plus a 46-byte suffix, so the buffer holds any destination path the OS allows.
    var buffer: [std.fs.max_path_bytes + 64]u8 = undefined;
    const staged = std.fmt.bufPrint(&buffer, "{s}.{s}.link.partial", .{ destination, std.fmt.bytesToHex(nonce, .lower) }) catch return error.WriteFailed;
    removeQuietly(cwd, io, staged);
    var linked = true;
    link(io, source, staged) catch {
        linked = false;
        cwd.copyFile(source, cwd, staged, io, .{}) catch {
            removeQuietly(cwd, io, staged);
            return error.WriteFailed;
        };
    };
    cwd.rename(staged, cwd, destination, io) catch {
        removeQuietly(cwd, io, staged);
        return error.WriteFailed;
    };
    // When `destination` already names the file at `source` (a hard link of it), the rename does nothing and
    // `staged` stays behind as a third name that keeps the inode after the store prunes its own. Remove it.
    removeQuietly(cwd, io, staged);
    return linked;
}

/// How `place` put a program at its output path.
pub const Placement = enum {
    /// The output already was a name of the program's file; nothing was touched.
    already,
    /// The output is a second name for a stored program's file: no bytes were copied.
    linked,
    /// The output is a copy (another file system, or a file system without hard links).
    copied,
};

/// Take the write permission off the program at `path` (best effort; a program that already is read-only is
/// left alone, so its status does not change). A program is stored once and every output of it is another
/// name of that file, so an in-place write through an output (a program that patches itself, `cat > prog`)
/// would change what the store holds; with no write bit that is refused. The stores verify every program
/// they hand out, so this is the first line against the accident and never the only one.
pub fn protect(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    const status = cwd.statFile(io, path, .{}) catch return;
    if (status.permissions.readOnly()) return;
    cwd.setFilePermissions(io, path, status.permissions.setReadOnly(true), .{}) catch return;
}

/// Whether `left` and `right` name one file (one device and one inode), without following a final symlink.
pub fn sameFile(left: []const u8, right: []const u8) bool {
    var first: std.os.linux.Statx = undefined;
    var second: std.os.linux.Statx = undefined;
    if (!identify(left, &first) or !identify(right, &second)) return false;
    return first.dev_major == second.dev_major and first.dev_minor == second.dev_minor and first.ino == second.ino;
}

fn identify(path: []const u8, into: *std.os.linux.Statx) bool {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len >= buffer.len) return false;
    @memcpy(buffer[0..path.len], path);
    buffer[path.len] = 0;
    const mask: std.os.linux.STATX = .{ .INO = true };
    const flags: u32 = std.os.linux.AT.SYMLINK_NOFOLLOW;
    return std.os.linux.errno(std.os.linux.statx(std.posix.AT.FDCWD, buffer[0..path.len :0], flags, mask, into)) == .SUCCESS;
}

/// Put the program at `output`: leave it alone when it already is a name of the file at `sources[0]`, else
/// remove it and make it a second name for the first of `sources` that `link` accepts (no bytes copied), else
/// a copy of the first source that exists. `sources[0]` is the stored program, the others are this build's own
/// names for the same bytes, kept in case a concurrent sweep removes the stored name. The old output is
/// removed, never written through: it may be a name of a stored program, and a write (or an open that
/// truncates) would change what the store holds. A missing parent directory is created. Removing first also
/// avoids the flush ext4 does for a file renamed over another (`auto_da_alloc`), which cost an unchanged
/// build 50-300 ms for a 10 MB program.
pub fn place(io: std.Io, sources: []const []const u8, output: []const u8, link: Linker) std.Io.Dir.CopyFileError!Placement {
    const cwd = std.Io.Dir.cwd();
    if (sources.len != 0 and sameFile(sources[0], output)) return .already;
    // `-o build/prog` makes `build/`, as `go build -o` does; a parent that cannot be made (a regular file in the
    // way, no permission) surfaces in the copy as its own error.
    if (std.fs.path.dirname(output)) |parent| cwd.createDirPath(io, parent) catch |err| switch (err) {
        // The link or the copy below meets the same obstacle and reports it against the output path.
        else => {},
    };
    // A missing output is the usual case; any other failure surfaces in the link or the copy.
    removeQuietly(cwd, io, output);
    for (sources) |source| {
        link(io, source, output) catch continue;
        return .linked;
    }
    var failure: std.Io.Dir.CopyFileError = error.FileNotFound;
    for (sources) |source| {
        cwd.copyFile(source, cwd, output, io, .{}) catch |err| {
            failure = err;
            continue;
        };
        return .copied;
    }
    return failure;
}

/// Remove `name` when it exists; a file that cannot be removed is left for the next sweep.
fn removeQuietly(dir: std.Io.Dir, io: std.Io, name: []const u8) void {
    dir.deleteFile(io, name) catch return;
}

fn failingLink(io: std.Io, source: []const u8, destination: []const u8) std.Io.Dir.HardLinkError!void {
    _ = io;
    _ = source;
    _ = destination;
    return error.CrossDevice;
}

test "a program's family names its entry and its mode's compile arguments, not its bytes" {
    const mine = family("src/main.selka", "-O0");
    try std.testing.expectEqual(mine, family("src/main.selka", "-O0"));
    try std.testing.expect(!std.mem.eql(u8, &mine, &family("src/other.selka", "-O0")));
    try std.testing.expect(!std.mem.eql(u8, &mine, &family("src/main.selka", "-O2")));
    // The lean build and the -O0 build of one entry are two families, so alternating them evicts neither's programs.
    try std.testing.expect(!std.mem.eql(u8, &mine, &family("src/main.selka", @import("build_mode.zig").Mode.lean_debug.keyed())));
    try std.testing.expectEqual(mine, family("src/main.selka", @import("build_mode.zig").Mode.optimized_debug.keyed()));
}

test "a pinned program survives its store entry being pruned, and a program already gone is a miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "entry" });
    const pinned = try std.fs.path.join(a, &.{ root, "pinned" });
    const late = try std.fs.path.join(a, &.{ root, "late" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = entry, .data = "linked executable" });
    try std.testing.expect(try pin(io, entry, pinned));
    try std.Io.Dir.cwd().deleteFile(io, entry);
    try std.testing.expectEqualStrings("linked executable", try std.Io.Dir.cwd().readFileAlloc(io, pinned, a, .limited(64)));
    try std.testing.expect(!try pin(io, entry, late));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, late, .{}));
}

test "a fifth program of one family removes the oldest, with its sidecar, and leaves other families alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const directory = try std.fs.path.join(a, &.{ root, directory_name });
    const store: unit_cache.Store = .{ .directory = directory };
    const mine = family("src/main.selka", "-O0");
    const other = family("src/other.selka", "-O0");
    try publishRun(a, io, store, root, mine, 5);
    try publishRun(a, io, store, root, other, 1);
    try keepNewest(a, io, directory, mine);
    try std.testing.expectEqual(@as(usize, per_family), try countPrograms(a, io, store, mine, 5));
    try std.testing.expect(!(try hasProgram(a, io, store, mine, 1)));
    try std.testing.expect(try hasProgram(a, io, store, mine, 2));
    const oldest_sidecar = try std.fmt.allocPrint(a, "{s}.sum", .{try store.path(a, @splat(1), try suffix(a, mine))});
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, oldest_sidecar, .{}));
    try std.testing.expect(try hasProgram(a, io, store, other, 1));
}

test "a program restored from the shared store keeps the place of its publication, whatever modification time its file carries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const directory = try std.fs.path.join(a, &.{ root, directory_name });
    const store: unit_cache.Store = .{ .directory = directory };
    const mine = family("src/main.selka", "-O0");
    const suffix_text = try suffix(a, mine);
    try publishRun(a, io, store, root, mine, 4);
    // The fifth program is published last, but its file is a second name for a record linked long before the others: its modification time is ancient.
    const staged = try std.fmt.allocPrint(a, "{s}/staged-restored", .{root});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = staged, .data = "restored" });
    const key: Digest = @splat(5);
    _ = try store.publish(a, io, key, suffix_text, staged);
    try stampAt(io, a, store, key, suffix_text, 4);
    try std.Io.Dir.cwd().setTimestamps(io, try store.path(a, key, suffix_text), .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 10 * std.time.ns_per_s } } });
    try keepNewest(a, io, directory, mine);
    try std.testing.expect(try hasProgram(a, io, store, mine, 5));
    try std.testing.expect(!(try hasProgram(a, io, store, mine, 1)));
    try std.testing.expectEqual(@as(usize, per_family), try countPrograms(a, io, store, mine, 5));
}

test "a program a replay served keeps its place behind a newer publication, and the oldest unused one goes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const directory = try std.fs.path.join(a, &.{ root, directory_name });
    const store: unit_cache.Store = .{ .directory = directory };
    const mine = family("src/main.selka", "-O0");
    const suffix_text = try suffix(a, mine);
    try publishRun(a, io, store, root, mine, 4);
    // The oldest program is the one a replay serves; its own file keeps the status a replay record compares.
    const served = try store.path(a, @splat(1), suffix_text);
    const before = try std.Io.Dir.cwd().statFile(io, served, .{});
    markUsed(a, io, served);
    const after = try std.Io.Dir.cwd().statFile(io, served, .{});
    try std.testing.expectEqual(before.mtime.nanoseconds, after.mtime.nanoseconds);
    try std.testing.expectEqual(before.ctime.nanoseconds, after.ctime.nanoseconds);
    // A fifth program is linked, newer than the three unused ones: the used oldest stays, the oldest unused goes.
    const staged = try std.fmt.allocPrint(a, "{s}/staged-fifth", .{root});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = staged, .data = "fifth" });
    _ = try store.publish(a, io, @splat(5), suffix_text, staged);
    try stampAt(io, a, store, @splat(5), suffix_text, 4);
    try keepNewest(a, io, directory, mine);
    try std.testing.expect(try hasProgram(a, io, store, mine, 1));
    try std.testing.expect(!(try hasProgram(a, io, store, mine, 2)));
    try std.testing.expectEqual(@as(usize, per_family), try countPrograms(a, io, store, mine, 5));
    // A program that is gone is not an error, and a sidecar with a second name keeps its time.
    markUsed(a, io, try store.path(a, @splat(2), suffix_text));
    const third = try store.path(a, @splat(3), suffix_text);
    const alias = try std.fmt.allocPrint(a, "{s}/alias", .{root});
    try std.Io.Dir.cwd().hardLink(try std.fmt.allocPrint(a, "{s}.sum", .{third}), std.Io.Dir.cwd(), alias, io, .{});
    markUsed(a, io, third);
    const kept = try std.Io.Dir.cwd().statFile(io, alias, .{});
    try std.testing.expectEqual(@as(i96, 1002 * std.time.ns_per_s), kept.mtime.nanoseconds);
}

// Publish `count` programs of `family_digest`, the first with the oldest modification time; key i is @splat(i + 1).
fn publishRun(a: std.mem.Allocator, io: std.Io, store: unit_cache.Store, root: []const u8, family_digest: Digest, count: u8) !void {
    const suffix_text = try suffix(a, family_digest);
    var index: u8 = 0;
    while (index < count) : (index += 1) {
        const staged = try std.fmt.allocPrint(a, "{s}/staged-{x}-{d}", .{ root, family_digest[0], index });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = staged, .data = &.{ 'p', index } });
        const key: Digest = @splat(index + 1);
        _ = try store.publish(a, io, key, suffix_text, staged);
        try stampAt(io, a, store, key, suffix_text, index);
    }
}

fn countPrograms(a: std.mem.Allocator, io: std.Io, store: unit_cache.Store, family_digest: Digest, count: u8) !usize {
    var kept: usize = 0;
    var index: u8 = 1;
    while (index <= count) : (index += 1) {
        if (try hasProgram(a, io, store, family_digest, index)) kept += 1;
    }
    return kept;
}

fn hasProgram(a: std.mem.Allocator, io: std.Io, store: unit_cache.Store, family_digest: Digest, number: u8) !bool {
    const key: Digest = @splat(number);
    return (try store.lookup(a, io, key, try suffix(a, family_digest))) != null;
}

// Place the program published for `key` at its index in the order of publication: later indexes are newer. A program is ranked by when its sidecar was written, so
// the sidecar takes the time of its index, and the program's own file takes the reverse order, so that a ranking by the file's time would invert the result.
fn stampAt(io: std.Io, a: std.mem.Allocator, store: unit_cache.Store, key: Digest, suffix_text: []const u8, index: u8) !void {
    const path = try store.path(a, key, suffix_text);
    const sidecar = try std.fmt.allocPrint(a, "{s}.sum", .{path});
    const published: i96 = 1000 + @as(i96, index);
    const linked: i96 = 5000 - @as(i96, index);
    try std.Io.Dir.cwd().setTimestamps(io, sidecar, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = published * std.time.ns_per_s } } });
    try std.Io.Dir.cwd().setTimestamps(io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = linked * std.time.ns_per_s } } });
}

test "a private program that the shared store holds is a hardlink to it, and a failed link is a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const shared_program = try std.fs.path.join(a, &.{ root, "shared" });
    const private_program = try std.fs.path.join(a, &.{ root, "private" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = shared_program, .data = "linked executable" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = private_program, .data = "linked executable" });
    try std.testing.expect(try share(io, shared_program, private_program, hardLink));
    const linked_stat = try std.Io.Dir.cwd().statFile(io, private_program, .{});
    try std.testing.expectEqual((try std.Io.Dir.cwd().statFile(io, shared_program, .{})).inode, linked_stat.inode);
    const copied_from = try std.fs.path.join(a, &.{ root, "copied" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = copied_from, .data = "linked executable" });
    try std.testing.expectError(error.CrossDevice, failingLink(io, shared_program, copied_from));
    try std.testing.expect(!try share(io, shared_program, copied_from, failingLink));
    try std.testing.expect((try std.Io.Dir.cwd().statFile(io, copied_from, .{})).inode != linked_stat.inode);
    try std.testing.expectEqualStrings("linked executable", try std.Io.Dir.cwd().readFileAlloc(io, copied_from, a, .limited(64)));
    try std.testing.expectError(error.WriteFailed, share(io, try std.fs.path.join(a, &.{ root, "absent" }), private_program, failingLink));
}

test "sharing into a private program that is already its hard link leaves no partial name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const record = try std.fs.path.join(a, &.{ root, "record" });
    const private_program = try std.fs.path.join(a, &.{ root, "private" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = record, .data = "linked executable" });
    try std.testing.expect(try share(io, record, private_program, hardLink));
    try std.testing.expect(try share(io, record, private_program, hardLink));
    const record_stat = try std.Io.Dir.cwd().statFile(io, record, .{});
    try std.testing.expectEqual(record_stat.inode, (try std.Io.Dir.cwd().statFile(io, private_program, .{})).inode);
    try std.testing.expectEqual(@as(@TypeOf(record_stat.nlink), 2), record_stat.nlink);
}

test "sharing into a private program at a path longer than 256 bytes still links it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var segment: [200]u8 = undefined;
    @memset(&segment, 'a');
    const deep = try std.fs.path.join(a, &.{ root, &segment });
    try std.Io.Dir.cwd().createDirPath(io, deep);
    const record = try std.fs.path.join(a, &.{ root, "record" });
    const private_program = try std.fs.path.join(a, &.{ deep, "private" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = record, .data = "linked executable" });
    try std.testing.expect(try share(io, record, private_program, hardLink));
    const record_stat = try std.Io.Dir.cwd().statFile(io, record, .{});
    try std.testing.expectEqual(record_stat.inode, (try std.Io.Dir.cwd().statFile(io, private_program, .{})).inode);
}

test "placing a program links the output to the stored file and leaves an output that already is that file alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const stored = try std.fs.path.join(a, &.{ root, "stored" });
    const output = try std.fs.path.join(a, &.{ root, "build", "deep", "prog" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = stored, .data = "linked executable" });
    try std.testing.expectEqual(Placement.linked, try place(io, &.{stored}, output, hardLink));
    try std.testing.expect(sameFile(stored, output));
    try std.testing.expectEqualStrings("linked executable", try std.Io.Dir.cwd().readFileAlloc(io, output, a, .limited(64)));
    const before = try std.Io.Dir.cwd().statFile(io, stored, .{});
    try std.testing.expectEqual(Placement.already, try place(io, &.{stored}, output, hardLink));
    const after = try std.Io.Dir.cwd().statFile(io, stored, .{});
    try std.testing.expectEqual(@as(@TypeOf(before.nlink), 2), after.nlink);
    try std.testing.expectEqual(before.ctime.nanoseconds, after.ctime.nanoseconds);
}

test "placing a program replaces an output that is another name of a stored file without writing through it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const older = try std.fs.path.join(a, &.{ root, "older" });
    const newer = try std.fs.path.join(a, &.{ root, "newer" });
    const output = try std.fs.path.join(a, &.{ root, "prog" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = older, .data = "old program" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = newer, .data = "new program" });
    try std.testing.expectEqual(Placement.linked, try place(io, &.{older}, output, hardLink));
    try std.testing.expectEqual(Placement.linked, try place(io, &.{newer}, output, hardLink));
    try std.testing.expectEqualStrings("new program", try std.Io.Dir.cwd().readFileAlloc(io, output, a, .limited(64)));
    try std.testing.expectEqualStrings("old program", try std.Io.Dir.cwd().readFileAlloc(io, older, a, .limited(64)));
    try std.testing.expect(!sameFile(older, output));
    try std.testing.expectEqual(@as(@TypeOf((try std.Io.Dir.cwd().statFile(io, older, .{})).nlink), 1), (try std.Io.Dir.cwd().statFile(io, older, .{})).nlink);
}

test "placing a program copies when the link fails, tries the build's own name when the stored one is gone, and fails when nothing exists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const absent = try std.fs.path.join(a, &.{ root, "absent" });
    const kept = try std.fs.path.join(a, &.{ root, "kept" });
    const copied = try std.fs.path.join(a, &.{ root, "copied" });
    const linked = try std.fs.path.join(a, &.{ root, "linked" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = kept, .data = "linked executable" });
    try std.testing.expectEqual(Placement.copied, try place(io, &.{kept}, copied, failingLink));
    try std.testing.expect(!sameFile(kept, copied));
    try std.testing.expectEqualStrings("linked executable", try std.Io.Dir.cwd().readFileAlloc(io, copied, a, .limited(64)));
    try std.testing.expectEqual(Placement.linked, try place(io, &.{ absent, kept }, linked, hardLink));
    try std.testing.expect(sameFile(kept, linked));
    try std.testing.expectError(error.FileNotFound, place(io, &.{absent}, try std.fs.path.join(a, &.{ root, "never" }), hardLink));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, try std.fs.path.join(a, &.{ root, "never" }), .{}));
}

test "relinking a private program to the shared record links when the file system allows it and leaves the program alone when it does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const record = try std.fs.path.join(a, &.{ root, "record" });
    const linked = try std.fs.path.join(a, &.{ root, "linked" });
    const kept = try std.fs.path.join(a, &.{ root, "kept" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = record, .data = "linked executable" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = linked, .data = "linked executable" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = kept, .data = "linked executable" });
    try std.testing.expect(relink(io, record, linked, hardLink));
    try std.testing.expect(sameFile(record, linked));
    // A refused link leaves the private program exactly as it was: the same file, not a copy of the record.
    const before = (try std.Io.Dir.cwd().statFile(io, kept, .{})).inode;
    try std.testing.expect(!relink(io, record, kept, failingLink));
    try std.testing.expectEqual(before, (try std.Io.Dir.cwd().statFile(io, kept, .{})).inode);
    try std.testing.expect(!sameFile(record, kept));
    try std.testing.expectEqualStrings("linked executable", try std.Io.Dir.cwd().readFileAlloc(io, kept, a, .limited(64)));
    // A record that is gone changes nothing either.
    try std.testing.expect(!relink(io, try std.fs.path.join(a, &.{ root, "absent" }), kept, hardLink));
    // A program that already is the record's file is left alone, even where no link could be made: no replacement, no change time moved.
    const settled = (try std.Io.Dir.cwd().statFile(io, linked, .{})).ctime.nanoseconds;
    try std.testing.expect(relink(io, record, linked, failingLink));
    try std.testing.expect(sameFile(record, linked));
    try std.testing.expectEqual(settled, (try std.Io.Dir.cwd().statFile(io, linked, .{})).ctime.nanoseconds);
}
