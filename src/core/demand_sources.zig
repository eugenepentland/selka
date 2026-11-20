//! Exact original-file authority for nonlocal cached source locations.
//!
//! A function whose lowering holds a position outside its own declaration (a default expanded into a caller, a generic
//! instance) is valid only while the file that holds the position still reads the same up to that position. The authority
//! is a proof of the file's bytes from its start to the end of the last line the function's positions touch, so an edit
//! after that line leaves the function's key alone. Files are named by key path, never by their place in the program's
//! source order, so adding, removing or reordering a module moves no proof.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const language = @import("selka");
const stage = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");

/// A position outside the function that holds it: the key path of the file that contains it and the line and column in that
/// file. A program of one file has no origin; a program of several names the file, never its index among them.
pub const Site = struct {
    origin: ?[]const u8 = null,
    offset: u32,
    point: ?Point = null,

    /// A one-based line and column of a file.
    pub const Point = struct { line: u32, column: u32 };
};

/// Authority for one file: the digest of its bytes from the start up to `length`, which ends a line.
pub const Proof = struct { path: []const u8, length: u32, digest: stage.Digest };

/// The files the external positions of one body are in, and how far into each the last of them reaches.
pub const Reach = struct {
    entries: std.ArrayList(Entry) = .empty,

    /// One file and the end of the last line a position of the body touches in it.
    pub const Entry = struct { path: []const u8, end: u32 };
};

/// The size of the blocks a file is digested in. A proof of a prefix is made of the digests of the whole blocks in it and the bytes
/// of the part block at its end, so a file is hashed once however many prefixes are proven, and a prefix costs its tail.
const block_size: u32 = 4096;

/// The domain of a prefix proof: what its digest is of, so no other hash of the same bytes can stand for one.
const proof_domain = "selka-source-prefix-proof-v2";

/// Only the files actually referenced by receipts or bodies are digested, and each block of one once however many prefixes of it are
/// proven (the whole blocks up to the farthest prefix asked for, and the tail of each prefix).
pub const Cache = struct {
    arena: std.mem.Allocator,
    source: ?language.source.Source = null,
    /// The original source of each key path asked for (null: the program has no such file, or two), and the digests of its
    /// prefixes by length.
    files: std.StringHashMapUnmanaged(File) = .empty,
    /// The entry's key name (`entry_name.zig`), set by the build before checking. Empty when none was set.
    entry_name: []const u8 = "",
    /// Digest of the entry's key name: what the receipts of this build scope to. Null until a source is bound. The receipts
    /// carry the content they depend on in their own inputs (region, context, proofs), so the entry's bytes are not here.
    identity: ?stage.Digest = null,
    /// How many bytes of files this cache has hashed for proofs: the whole blocks once each, and the tail of each prefix.
    hashed: u64 = 0,

    const File = struct {
        path: []const u8,
        source: ?language.source.Source,
        /// The digests of the whole blocks of the file hashed so far, from its start.
        blocks: std.ArrayList(stage.Digest) = .empty,
        prefixes: std.AutoHashMapUnmanaged(u32, stage.Digest) = .empty,
    };

    /// Reset memoized authority for the fresh checked source catalog, and digest the entry name it is scoped to.
    pub fn bind(self: *Cache, source: language.source.Source) void {
        self.source = source;
        self.files.clearRetainingCapacity();
        self.identity = identityOf(self.entry_name);
    }

    /// The digest of the entry's key name.
    fn identityOf(name: []const u8) stage.Digest {
        var hash = fast_blake3.Blake3.init(.{});
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, name.len, .little);
        hash.update(&length);
        hash.update(name);
        var digest: stage.Digest = undefined;
        hash.final(&digest);
        return digest;
    }

    /// The original source that has key path `path` in the bound source: the one source of an unmerged program, else the one
    /// module of that name. Null when there is none or when two modules share the name.
    fn find(source: language.source.Source, path: []const u8) ?language.source.Source {
        if (source.origins.len == 0) return if (std.mem.eql(u8, path, source.keyPath())) source else null;
        var found: ?language.source.Source = null;
        for (source.origins) |origin| {
            if (!std.mem.eql(u8, origin.original.keyPath(), path)) continue;
            if (found != null) return null;
            found = origin.original;
        }
        return found;
    }

    /// The file with key path `path`, looked up once per bound source; null for a path the source does not hold.
    fn file(self: *Cache, path: []const u8) std.mem.Allocator.Error!?*File {
        const bound = self.source orelse return null;
        if (self.files.getPtr(path)) |known| return if (known.source != null) known else null;
        const owned = try self.arena.dupe(u8, path);
        const slot = try self.files.getOrPut(self.arena, owned);
        slot.value_ptr.* = .{ .path = owned, .source = find(bound, owned) };
        return if (slot.value_ptr.source != null) slot.value_ptr else null;
    }

    /// The digest of the first `length` bytes of `entry`, made once per length from the digests of the whole blocks in it (each hashed
    /// once for the file, and only as far as the farthest prefix asked for) and the bytes of the part block at its end; null when the
    /// file is shorter. Equal bytes up to `length` give equal digests, and a byte changed inside the prefix gives another.
    fn prefix(self: *Cache, entry: *File, length: u32) std.mem.Allocator.Error!?stage.Digest {
        const bytes = entry.source.?.bytes;
        if (length > bytes.len) return null;
        const slot = try entry.prefixes.getOrPut(self.arena, length);
        if (slot.found_existing) return slot.value_ptr.*;
        const whole = length / block_size;
        while (entry.blocks.items.len < whole) {
            const at = entry.blocks.items.len * block_size;
            var digest: stage.Digest = undefined;
            fast_blake3.hash(bytes[at..][0..block_size], &digest);
            self.hashed += block_size;
            try entry.blocks.append(self.arena, digest);
        }
        const tail = bytes[@as(usize, whole) * block_size .. length];
        self.hashed += tail.len;
        var hash = fast_blake3.Blake3.init(.{});
        hash.update(proof_domain);
        var size: [8]u8 = undefined;
        std.mem.writeInt(u64, &size, length, .little);
        hash.update(&size);
        for (entry.blocks.items[0..whole]) |digest| hash.update(&digest);
        hash.update(tail);
        hash.final(slot.value_ptr);
        return slot.value_ptr.*;
    }

    /// Note, in `reach`, the file of `site` and the end of the line the site is on. False when the site cannot be proven: it
    /// has no file or line in the bound source.
    pub fn collect(self: *Cache, reach: *Reach, site: Site) std.mem.Allocator.Error!bool {
        const bound = self.source orelse return false;
        const point = site.point orelse return false;
        const path = site.origin orelse if (bound.origins.len == 0) bound.keyPath() else return false;
        const entry = try self.file(path) orelse return false;
        const original = entry.source.?;
        const at = snapshot.pointOffset(original, point.line, point.column) catch return false;
        const end: u32 = @intCast(if (std.mem.indexOfScalarPos(u8, original.bytes, at, '\n')) |newline| newline + 1 else original.bytes.len);
        for (reach.entries.items) |*known| if (std.mem.eql(u8, known.path, entry.path)) {
            known.end = @max(known.end, end);
            return true;
        };
        try reach.entries.append(self.arena, .{ .path = entry.path, .end = end });
        return true;
    }

    /// The proofs of the files in `reach`, in the order the files were first reached. Null when a file cannot be proven.
    pub fn seal(self: *Cache, reach: *const Reach) std.mem.Allocator.Error!?[]const Proof {
        const proofs = try self.arena.alloc(Proof, reach.entries.items.len);
        for (reach.entries.items, proofs) |entry, *proof| {
            const found = try self.file(entry.path) orelse return null;
            const digest = try self.prefix(found, entry.end) orelse return null;
            proof.* = .{ .path = found.path, .length = entry.end, .digest = digest };
        }
        return proofs;
    }

    /// Whether every stored proof still holds: its file is in the bound source, and its first `length` bytes digest as they did.
    pub fn matches(self: *Cache, proofs: []const Proof) std.mem.Allocator.Error!bool {
        for (proofs) |proof| {
            const found = try self.file(proof.path) orelse return false;
            const current = try self.prefix(found, proof.length) orelse return false;
            if (!std.mem.eql(u8, &current, &proof.digest)) return false;
        }
        return true;
    }

    /// Whether `proofs` cover every file `needed` names, each at least as far.
    pub fn covers(proofs: []const Proof, needed: []const Proof) bool {
        for (needed) |want| {
            var found = false;
            for (proofs) |have| if (std.mem.eql(u8, have.path, want.path) and have.length >= want.length) {
                found = true;
                break;
            };
            if (!found) return false;
        }
        return true;
    }
};

test "a demand identity names the entry by its key name alone: edits to its bytes or to merged modules keep it" {
    var cache: Cache = .{ .arena = std.testing.allocator };
    defer cache.files.deinit(std.testing.allocator);
    cache.entry_name = "app/main.selka";
    const entry: language.source.Source = .{ .path = "main.selka", .bytes = "func main() -> int:\n    return 0\n", .line_starts = &.{} };
    const lib: language.source.Source = .{ .path = "lib.selka", .bytes = "public func one() -> int:\n    return 1\n", .line_starts = &.{} };
    const lib_edited: language.source.Source = .{ .path = "lib.selka", .bytes = "public func one() -> int:\n    return 2\n", .line_starts = &.{} };
    const entry_edited: language.source.Source = .{ .path = "main.selka", .bytes = "func main() -> int:\n    return 1\n", .line_starts = &.{} };
    const merged = language.source.Source{ .path = "<project>", .bytes = "", .line_starts = &.{}, .origins = &.{ .{ .start = 0, .original = entry }, .{ .start = 40, .original = lib } } };
    const merged_lib = language.source.Source{ .path = "<project>", .bytes = "", .line_starts = &.{}, .origins = &.{ .{ .start = 0, .original = entry }, .{ .start = 40, .original = lib_edited } } };
    const merged_entry = language.source.Source{ .path = "<project>", .bytes = "", .line_starts = &.{}, .origins = &.{ .{ .start = 0, .original = entry_edited }, .{ .start = 40, .original = lib } } };
    cache.bind(merged);
    const first = cache.identity.?;
    cache.bind(merged_lib);
    try std.testing.expectEqualSlices(u8, &first, &cache.identity.?);
    cache.bind(merged_entry);
    try std.testing.expectEqualSlices(u8, &first, &cache.identity.?);
    cache.entry_name = "other/main.selka";
    cache.bind(merged);
    try std.testing.expect(!std.mem.eql(u8, &first, &cache.identity.?));
}

/// A file of `blocks` blocks and a bit, every byte telling its own place, as a source with key path `lib.selka`.
fn bigFile(a: std.mem.Allocator, blocks: usize) std.mem.Allocator.Error!language.source.Source {
    const bytes = try a.alloc(u8, blocks * block_size + 100);
    for (bytes, 0..) |*byte, at| byte.* = @truncate(at *% 31 +% at / 251);
    return .{ .path = "lib.selka", .bytes = bytes, .line_starts = &.{} };
}

/// The proof digest of the first `length` bytes of `source` in a cache of its own.
fn proofOf(a: std.mem.Allocator, source: language.source.Source, length: u32) !stage.Digest {
    var cache: Cache = .{ .arena = a };
    cache.bind(source);
    const found = (try cache.file(source.keyPath())).?;
    return (try cache.prefix(found, length)).?;
}

test "a prefix proof changes when a byte inside the prefix changes and keeps when a byte after it changes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try bigFile(a, 5);
    const short: u32 = 10;
    const long: u32 = 3 * block_size + 100;
    const baseline_short = try proofOf(a, original, short);
    const baseline_long = try proofOf(a, original, long);
    // A byte inside the first block: inside both prefixes (5 < 10) or only the long one (20 > 10).
    const early = try a.dupe(u8, original.bytes);
    early[5] ^= 1;
    const later = try a.dupe(u8, original.bytes);
    later[20] ^= 1;
    // A byte in a middle block, in the tail of the long prefix, and after it.
    const middle = try a.dupe(u8, original.bytes);
    middle[block_size + 7] ^= 1;
    const tail = try a.dupe(u8, original.bytes);
    tail[3 * block_size + 50] ^= 1;
    const beyond = try a.dupe(u8, original.bytes);
    beyond[3 * block_size + 200] ^= 1;
    var changed: language.source.Source = original;
    changed.bytes = early;
    try std.testing.expect(!std.mem.eql(u8, &baseline_short, &(try proofOf(a, changed, short))));
    try std.testing.expect(!std.mem.eql(u8, &baseline_long, &(try proofOf(a, changed, long))));
    changed.bytes = later;
    try std.testing.expectEqual(baseline_short, try proofOf(a, changed, short));
    try std.testing.expect(!std.mem.eql(u8, &baseline_long, &(try proofOf(a, changed, long))));
    changed.bytes = middle;
    try std.testing.expectEqual(baseline_short, try proofOf(a, changed, short));
    try std.testing.expect(!std.mem.eql(u8, &baseline_long, &(try proofOf(a, changed, long))));
    changed.bytes = tail;
    try std.testing.expect(!std.mem.eql(u8, &baseline_long, &(try proofOf(a, changed, long))));
    changed.bytes = beyond;
    try std.testing.expectEqual(baseline_short, try proofOf(a, changed, short));
    try std.testing.expectEqual(baseline_long, try proofOf(a, changed, long));
    // The same bytes up to a length give the same digest, and a different length of the same bytes another.
    try std.testing.expect(!std.mem.eql(u8, &baseline_short, &baseline_long));
    try std.testing.expect(!std.mem.eql(u8, &(try proofOf(a, original, long)), &(try proofOf(a, original, long + 1))));
}

/// Prove `file` at every multiple of `step` below its length.
fn proveEvery(cache: *Cache, file: *Cache.File, step: u32) !void {
    var length: u32 = step;
    while (length < file.source.?.bytes.len) : (length += step) _ = try cache.prefix(file, length);
}

test "a file is hashed once for all the prefixes proven of it, and a prefix asked for twice costs nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try bigFile(a, 16);
    var cache: Cache = .{ .arena = a };
    cache.bind(source);
    const found = (try cache.file(source.keyPath())).?;
    // Twenty distinct lengths, 3,000 bytes apart (one to the end of the file): hashed one by one from the start, they would cost the
    // sum of the lengths, about 600 KB.
    try proveEvery(&cache, found, 3000);
    _ = try cache.prefix(found, @intCast(source.bytes.len));
    const asked = cache.hashed;
    try std.testing.expect(asked <= source.bytes.len + 22 * block_size);
    _ = try cache.prefix(found, 3000);
    _ = try cache.prefix(found, @intCast(source.bytes.len));
    try std.testing.expectEqual(asked, cache.hashed);
    try std.testing.expectEqual(@as(usize, 16), found.blocks.items.len);
}
