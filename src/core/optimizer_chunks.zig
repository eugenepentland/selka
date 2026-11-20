//! The optimizer's dense program record, first form (part 2, G3p (a)): the stored entries of one module's functions in one
//! chunk, so that a build reads one record where it read one per function.
//!
//! A group of functions is stored as two chunks (`optimizer_rows.zig`): the core rows, which every build reads, and the rest rows, which
//! a build reads only for a function that is recomputed or compared with. A chunk is the rows' encodings (local names inside each)
//! side by side behind a table of offsets, ordered by the functions' lowering keys. It names nothing outside itself: no path, no
//! function ordinal, no position among the program's functions, and no state of the build that wrote it, except that a core chunk
//! names its rest chunk by digest. A chunk's key is the digest of its bytes, so a chunk another tree wrote for the same functions is
//! the same record, and a group with no changed function is not written again. A manifest names the core chunks a build used and,
//! for each function, its chunk and row; a row is read in place from the chunk's bytes, so what a function only passes along is
//! decoded when the function is, and not before.
const std = @import("std");
const stage = @import("stage_store.zig");
const fast_blake3 = @import("fast_blake3.zig");

/// The scope of chunk records: shared like the entry records they replace, keyed by the digest of the chunk's bytes.
pub const scope = "optimizer-chunk-v3";

const magic: u32 = 0x4b48_4333;
const header_bytes = 8 + 32;

/// About how many functions share a chunk: a chunk is rewritten whole when any of its rows changes, so the writes of an edit grow with it
/// (24 rows wrote 1.5 to 2 times the entry-record scheme's bytes for an edit with callers spread over the program), and a build reads one record per
/// chunk, so the reads grow with the program over it (a record read is 5 us, an entry's decode 7).
pub const rows_per_chunk = 6;

/// The module a function's checked name is qualified with: the part before the first `::` and before any type arguments. A function with
/// none (the entry module's own, a generic instance, a helper) has the module `""`. It reads the name, which outlives the build, and not
/// `ir.Function.module`, whose text lives in a source the build has let go of.
pub fn moduleOf(name: []const u8) []const u8 {
    const head = name[0 .. std.mem.indexOfScalar(u8, name, '[') orelse name.len];
    const at = std.mem.indexOf(u8, head, "::") orelse return "";
    return head[0..at];
}

/// How many chunks a module of `count` functions is cut into: the smallest power of two that leaves at most `rows_per_chunk` functions in a chunk
/// on average, so a module's chunks change only when its size passes a power of two.
pub fn bucketsFor(count: usize) u32 {
    var buckets: u32 = 1;
    while (@as(usize, buckets) * rows_per_chunk < count) buckets *= 2;
    return buckets;
}

/// The bucket of the function `name` among `buckets` of its module: a hash of the name, so it is the same in every build.
pub fn bucketOf(name: []const u8, buckets: u32) u32 {
    return @intCast(std.hash.Wyhash.hash(0, name) % buckets);
}

/// Where a function's stored entry stands: the digest of its chunk and its row in it.
pub const Held = struct { chunk: [32]u8, row: u32 };

/// The scope of heads: the manifest of a program state, stored under the digest of that state (`stateOf`).
pub const head_scope = "optimizer-head-v3";

/// The key the head of program state `state` is stored under.
pub fn headKey(storage: *const stage.Store, state: [32]u8) [32]u8 {
    return storage.key(head_scope, &.{&state});
}

/// The scope of latest-state pointers: for a project, the program state some tree published last (`Latest`), under a key that no edit moves.
pub const latest_scope = "optimizer-latest-v1";

/// What a latest-state pointer holds: the state whose head (`headKey`) is the manifest of the program some tree optimized last. It is a hint
/// and never a result: the head it names is read, checked against the build's own program and served only entry by entry, as any head is.
pub const Latest = struct { state: [32]u8 };

/// The key of the pointer to the latest state of project `project` (`ProjectId`) under any raw layout: an edit that adds a function or
/// changes a type moves the layout and not the project, so a build that has no pointer for its layout still starts from the nearest state.
pub fn latestKey(storage: *const stage.Store, project: [32]u8) [32]u8 {
    return storage.key(latest_scope, &.{ "project", &project });
}

/// The key of the pointer to the latest state of project `project` whose raw layout is `layout`: a body edit moves neither, so a tree
/// that edited a body finds the state another tree published with the bodies it had.
pub fn latestLayoutKey(storage: *const stage.Store, project: [32]u8, layout: [32]u8) [32]u8 {
    return storage.key(latest_scope, &.{ "layout", &project, &layout });
}

/// The identity of a project as the optimizer sees it: the mode and the key paths (project-relative, the same in every worktree) of the
/// entry source and of every module merged into it, added in order. A body edit moves none of them. Another project with the same entry and
/// modules is the same project to a pointer, and a head it names is then served entry by entry or not at all.
pub const ProjectId = struct {
    hash: fast_blake3.Blake3,

    /// The identity of a project built in `mode` from the entry source at key path `entry`.
    pub fn init(mode: u8, entry: []const u8) ProjectId {
        var hash = fast_blake3.Blake3.init(.{});
        hash.update("optimizer-project-v1\x00");
        hash.update(&.{mode});
        hash.update(entry);
        return .{ .hash = hash };
    }

    /// Add the key path of one module merged into the entry.
    pub fn module(self: *ProjectId, path: []const u8) void {
        self.hash.update("\x00");
        self.hash.update(path);
    }

    /// The digest of the identity.
    pub fn final(self: *ProjectId) [32]u8 {
        var out: [32]u8 = undefined;
        self.hash.final(&out);
        return out;
    }
};

/// The digest of a program state as the optimizer starts: its mode, the raw layout and every function's lowering key, in the order of
/// the function table. It names no path and no worktree, so a tree that lowered the same functions in the same order names the same
/// state, and a head stored under it is the manifest of that program.
pub fn stateOf(mode: u8, raw_layout: [32]u8, keys: []const ?[32]u8) [32]u8 {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("optimizer-state-v1\x00");
    hash.update(&.{mode});
    hash.update(&raw_layout);
    for (keys) |maybe| {
        if (maybe) |key| {
            hash.update("\x01");
            hash.update(&key);
        } else hash.update("\x00");
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// The key a chunk with digest `digest` is stored under.
pub fn keyOf(storage: *const stage.Store, digest: [32]u8) [32]u8 {
    return storage.key(scope, &.{&digest});
}

/// The digest of a chunk's bytes, which names it.
pub fn digestOf(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    fast_blake3.hash(bytes, &digest);
    return digest;
}

/// The rows of a chunk, read in place.
pub const View = struct {
    bytes: []const u8,
    count: u32,
    /// The digest of the chunk that holds the rest rows of these rows (zero in a chunk that is one).
    rest: [32]u8,

    /// The bytes of row `row`, or null past the last.
    pub fn row(self: View, row_index: u32) ?[]const u8 {
        if (row_index >= self.count) return null;
        const at = header_bytes + @as(usize, row_index) * 4;
        const start = std.mem.readInt(u32, self.bytes[at..][0..4], .little);
        const end = std.mem.readInt(u32, self.bytes[at + 4 ..][0..4], .little);
        return self.bytes[start..end];
    }
};

/// A view of `bytes` when they are a well-formed chunk: the magic, a count, and offsets that rise through the data.
pub fn view(bytes: []const u8) ?View {
    if (bytes.len < header_bytes) return null;
    if (std.mem.readInt(u32, bytes[0..4], .little) != magic) return null;
    const count = std.mem.readInt(u32, bytes[4..8], .little);
    const rest: [32]u8 = bytes[8..40].*;
    const table_end = header_bytes + (@as(usize, count) + 1) * 4;
    if (table_end > bytes.len) return null;
    var previous: u32 = @intCast(table_end);
    var at: usize = header_bytes;
    var index: usize = 0;
    while (index <= count) : (index += 1) {
        const offset = std.mem.readInt(u32, bytes[at..][0..4], .little);
        if (offset < previous or offset > bytes.len) return null;
        previous = offset;
        at += 4;
    }
    if (previous != bytes.len) return null;
    return .{ .bytes = bytes, .count = count, .rest = rest };
}

/// The chunk that holds `rows`, in order, whose rest rows are in the chunk `rest`.
pub fn frame(a: std.mem.Allocator, rows: []const []const u8, rest: [32]u8) std.mem.Allocator.Error![]u8 {
    var total: usize = header_bytes + (rows.len + 1) * 4;
    for (rows) |each| total += each.len;
    const out = try a.alloc(u8, total);
    std.mem.writeInt(u32, out[0..4], magic, .little);
    std.mem.writeInt(u32, out[4..8], @intCast(rows.len), .little);
    @memcpy(out[8..40], &rest);
    var offset: usize = header_bytes + (rows.len + 1) * 4;
    var at: usize = header_bytes;
    for (rows) |each| {
        std.mem.writeInt(u32, out[at..][0..4], @intCast(offset), .little);
        at += 4;
        @memcpy(out[offset..][0..each.len], each);
        offset += each.len;
    }
    std.mem.writeInt(u32, out[at..][0..4], @intCast(offset), .little);
    return out;
}

/// The chunks a build has read, each once: a chunk is read when its first function is looked up and held for the rest of the build,
/// which also copies the rows of a chunk that changes only in part.
pub const Cache = struct {
    storage: *const stage.Store,
    arena: std.mem.Allocator,
    held: std.AutoHashMapUnmanaged([32]u8, ?View) = .empty,
    /// Whether the store holds a chunk, for the chunks asked about and not read.
    present: std.AutoHashMapUnmanaged([32]u8, bool) = .empty,
    /// Chunks read from the store and chunks asked for that it did not hold.
    reads: u32 = 0,
    absent: u32 = 0,

    /// The chunk `digest`, or null when the store does not hold a well-formed one under that name.
    pub fn get(self: *Cache, digest: [32]u8) std.mem.Allocator.Error!?View {
        const slot = try self.held.getOrPut(self.arena, digest);
        if (slot.found_existing) return slot.value_ptr.*;
        slot.value_ptr.* = null;
        const bytes = try self.storage.load(self.arena, keyOf(self.storage, digest)) orelse {
            self.absent += 1;
            return null;
        };
        self.reads += 1;
        slot.value_ptr.* = view(bytes);
        return slot.value_ptr.*;
    }

    /// Whether the store holds a record under chunk `digest`, without reading it.
    pub fn has(self: *Cache, digest: [32]u8) std.mem.Allocator.Error!bool {
        if (self.held.get(digest)) |known| return known != null;
        const slot = try self.present.getOrPut(self.arena, digest);
        if (!slot.found_existing) slot.value_ptr.* = self.storage.contains(keyOf(self.storage, digest)) catch false;
        return slot.value_ptr.*;
    }
};

test "a chunk keeps its rows in order and reads each in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try frame(a, &.{ "first", "", "third row" }, @splat(7));
    const chunk = view(bytes).?;
    try std.testing.expectEqual(@as(u32, 3), chunk.count);
    try std.testing.expectEqualStrings("first", chunk.row(0).?);
    try std.testing.expectEqualStrings("", chunk.row(1).?);
    try std.testing.expectEqualStrings("third row", chunk.row(2).?);
    try std.testing.expectEqual(@as(?[]const u8, null), chunk.row(3));
    try std.testing.expectEqual(digestOf(bytes), digestOf(try frame(a, &.{ "first", "", "third row" }, @splat(7))));
    try std.testing.expectEqual(@as([32]u8, @splat(7)), chunk.rest);
    try std.testing.expect(!std.mem.eql(u8, &digestOf(bytes), &digestOf(try frame(a, &.{ "first", "", "third row" }, @splat(8)))));
}

test "a program state is named by its mode, layout and lowering keys, in order" {
    const layout: [32]u8 = @splat(1);
    const keys = [_]?[32]u8{ @as([32]u8, @splat(2)), null, @as([32]u8, @splat(3)) };
    const same = stateOf(0, layout, &keys);
    try std.testing.expectEqual(same, stateOf(0, layout, &keys));
    try std.testing.expect(!std.mem.eql(u8, &same, &stateOf(1, layout, &keys)));
    try std.testing.expect(!std.mem.eql(u8, &same, &stateOf(0, @splat(9), &keys)));
    const reordered = [_]?[32]u8{ keys[2], keys[1], keys[0] };
    try std.testing.expect(!std.mem.eql(u8, &same, &stateOf(0, layout, &reordered)));
}

test "functions are grouped by the module their checked name is qualified with, and a module is cut into chunks of about six by a hash of the name" {
    try std.testing.expectEqualStrings("export_kicad_sch", moduleOf("export_kicad_sch::build_components"));
    try std.testing.expectEqualStrings("a", moduleOf("a::b::c"));
    try std.testing.expectEqualStrings("", moduleOf("main"));
    try std.testing.expectEqualStrings("", moduleOf("Box[a::b]::get"));
    try std.testing.expectEqual(@as(u32, 1), bucketsFor(0));
    try std.testing.expectEqual(@as(u32, 1), bucketsFor(rows_per_chunk));
    try std.testing.expectEqual(@as(u32, 2), bucketsFor(rows_per_chunk + 1));
    try std.testing.expectEqual(@as(u32, 128), bucketsFor(713));
    try std.testing.expectEqual(bucketOf("main", 32), bucketOf("main", 32));
    try std.testing.expect(bucketOf("main", 32) < 32);
}

test "bytes that are not a chunk, or a chunk cut short or altered, are no view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try frame(a, &.{ "one", "two" }, @splat(0));
    try std.testing.expect(view(bytes) != null);
    try std.testing.expectEqual(@as(?View, null), view(bytes[0 .. bytes.len - 1]));
    try std.testing.expectEqual(@as(?View, null), view("not a chunk at all"));
    const altered = try a.dupe(u8, bytes);
    std.mem.writeInt(u32, altered[header_bytes..][0..4], 4000, .little);
    try std.testing.expectEqual(@as(?View, null), view(altered));
}
