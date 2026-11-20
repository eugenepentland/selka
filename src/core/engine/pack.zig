//! The records pack of a work directory (round 14, D-L1r14-1): the records one build was served, in one file.
//!
//! A fresh work directory is served hundreds of records by the shared tier, and each used to be copied into the directory as a file of its own, a
//! create and a rename per record. A pack holds them in one file, written once, with an index the lookup searches in place. A pack is a hint like every
//! record: it names no result, its records are decoded and validated exactly as loose files are (under this tree's stat tuples), and a pack that does
//! not parse is ignored whole.
//!
//! ```
//! "SLKPACK1"  u32 format  u32 count  u32 groups
//! groups x { u32 length, kind name, identity[32] }       the (kind, code identity) pairs the pack holds records of
//! count x { key[32], u32 offset, u32 length }            sorted ascending by key, strictly
//! digest[32]                                             BLAKE3 of everything above
//! records                                                each the encoded record, trailer included, as a loose file holds it
//! ```
const std = @import("std");
const digest_rules = @import("digest.zig");
const Digest = digest_rules.Digest;

/// The eight bytes that start a pack.
pub const magic = "SLKPACK1";
/// The pack format this file writes and reads.
pub const format_version: u32 = 1;
/// The directory of a work directory's store that holds its packs.
pub const directory_leaf = "packs";
/// The extension of a pack's file name.
pub const suffix = ".pack";
/// The most packs one process reads, the newest first: a retirement that lags does not make every build read every pack.
pub const max_loaded: usize = 8;
/// The packs with a live group that a retirement keeps, least recently used first out.
pub const max_kept: usize = 4;
/// How much of a file is read before deciding whether any of its records is one this process can use.
pub const peek_bytes: usize = 4096;
/// The largest pack: offsets are 32 bits.
pub const max_pack_bytes: u64 = 1 << 30;

const fixed_length = magic.len + 12;
const entry_length = 40;
const longest_name = 4096;

/// A kind and the code identity of the records a pack holds of it.
pub const Group = struct { kind: []const u8, identity: Digest };

/// One record to pack: the key it is stored under and its encoded bytes.
pub const Item = struct { key: Digest, bytes: []const u8 };

fn byKey(_: void, left: Item, right: Item) bool {
    return std.mem.lessThan(u8, &left.key, &right.key);
}

/// A pack made by `build`: its bytes and the digest of its header and index, which its file name is made of (`fileName`).
pub const Built = struct { bytes: []u8, digest: Digest };

/// The pack of `items` (any order) whose records belong to `groups`, or null when two items share a key or the pack would be too large to address.
pub fn build(a: std.mem.Allocator, groups: []const Group, items: []const Item) std.mem.Allocator.Error!?Built {
    const sorted = try a.dupe(Item, items);
    defer a.free(sorted);
    std.mem.sort(Item, sorted, {}, byKey);
    for (1..sorted.len) |at| {
        if (std.mem.eql(u8, &sorted[at].key, &sorted[at - 1].key)) return null;
    }
    var at: u64 = fixed_length;
    for (groups) |group| at += 4 + group.kind.len + 32;
    const index_end = at + @as(u64, sorted.len) * entry_length;
    var total = index_end + 32;
    for (sorted) |item| total += item.bytes.len;
    if (total > max_pack_bytes) return null;
    const out = try a.alloc(u8, @intCast(total));
    @memcpy(out[0..magic.len], magic);
    std.mem.writeInt(u32, out[magic.len..][0..4], format_version, .little);
    std.mem.writeInt(u32, out[magic.len + 4 ..][0..4], @intCast(sorted.len), .little);
    std.mem.writeInt(u32, out[magic.len + 8 ..][0..4], @intCast(groups.len), .little);
    var cursor: usize = fixed_length;
    for (groups) |group| {
        std.mem.writeInt(u32, out[cursor..][0..4], @intCast(group.kind.len), .little);
        @memcpy(out[cursor + 4 ..][0..group.kind.len], group.kind);
        cursor += 4 + group.kind.len;
        @memcpy(out[cursor..][0..32], &group.identity);
        cursor += 32;
    }
    var offset: u64 = index_end + 32;
    for (sorted) |item| {
        @memcpy(out[cursor..][0..32], &item.key);
        std.mem.writeInt(u32, out[cursor + 32 ..][0..4], @intCast(offset), .little);
        std.mem.writeInt(u32, out[cursor + 36 ..][0..4], @intCast(item.bytes.len), .little);
        @memcpy(out[@intCast(offset)..][0..item.bytes.len], item.bytes);
        cursor += entry_length;
        offset += item.bytes.len;
    }
    const sum = digest_rules.hash(out[0..cursor]);
    @memcpy(out[cursor..][0..32], &sum);
    return .{ .bytes = out, .digest = sum };
}

/// A parsed pack: the bytes, which the view borrows, and where its index is.
pub const View = struct {
    bytes: []const u8,
    count: u32,
    index_at: usize,
    groups_at: usize,
    groups: u32,
    /// The digest of the header and index, which names the pack.
    digest: Digest,

    /// The pack `bytes` hold, or null when they are not a whole pack: wrong magic or format, a group or an entry outside the bytes, keys out of order or
    /// repeated, a record outside the file, or an index that does not hash to its digest.
    pub fn parse(bytes: []const u8) ?View {
        if (bytes.len < fixed_length + 32 or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
        if (std.mem.readInt(u32, bytes[magic.len..][0..4], .little) != format_version) return null;
        const count = std.mem.readInt(u32, bytes[magic.len + 4 ..][0..4], .little);
        const groups = std.mem.readInt(u32, bytes[magic.len + 8 ..][0..4], .little);
        var at: usize = fixed_length;
        for (0..groups) |_| {
            if (at + 4 > bytes.len) return null;
            const length = std.mem.readInt(u32, bytes[at..][0..4], .little);
            if (length > longest_name or at + 4 + length + 32 > bytes.len) return null;
            at += 4 + length + 32;
        }
        const index_end = at + @as(u64, count) * entry_length;
        if (index_end + 32 > bytes.len) return null;
        const records_at: usize = @intCast(index_end + 32);
        const sum = digest_rules.hash(bytes[0..@intCast(index_end)]);
        if (!std.mem.eql(u8, &sum, bytes[@intCast(index_end)..][0..32])) return null;
        var view: View = .{ .bytes = bytes, .count = count, .index_at = at, .groups_at = fixed_length, .groups = groups, .digest = sum };
        var previous: ?Digest = null;
        for (0..count) |slot| {
            const key = view.keyAt(slot);
            if (previous) |before| if (!std.mem.lessThan(u8, &before, &key)) return null;
            previous = key;
            const where = view.span(slot);
            if (where.offset < records_at or where.offset + where.length > bytes.len) return null;
        }
        return view;
    }

    /// The key of entry `slot`.
    pub fn keyAt(self: View, slot: usize) Digest {
        return self.bytes[self.index_at + slot * entry_length ..][0..32].*;
    }

    const Span = struct { offset: usize, length: usize };

    fn span(self: View, slot: usize) Span {
        const entry = self.bytes[self.index_at + slot * entry_length + 32 ..][0..8];
        return .{ .offset = std.mem.readInt(u32, entry[0..4], .little), .length = std.mem.readInt(u32, entry[4..8], .little) };
    }

    /// The encoded record of entry `slot`.
    pub fn recordAt(self: View, slot: usize) []const u8 {
        const where = self.span(slot);
        return self.bytes[where.offset..][0..where.length];
    }

    /// The encoded record stored under `key`, or null when the pack holds none.
    // twin-drift-ok: this searches the fixed-size entries of a pack's index in place; `context.findPart` searches a slice of named parts.
    pub fn find(self: View, key: Digest) ?[]const u8 {
        var low: usize = 0;
        var high: usize = self.count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const here = self.keyAt(middle);
            switch (std.mem.order(u8, &here, &key)) {
                .eq => return self.recordAt(middle),
                .lt => low = middle + 1,
                .gt => high = middle,
            }
        }
        return null;
    }

    /// The groups of the pack, their names borrowed from its bytes, in `a`.
    pub fn groupList(self: View, a: std.mem.Allocator) std.mem.Allocator.Error![]Group {
        const out = try a.alloc(Group, self.groups);
        var at = self.groups_at;
        for (out) |*group| {
            const length = std.mem.readInt(u32, self.bytes[at..][0..4], .little);
            group.* = .{ .kind = self.bytes[at + 4 ..][0..length], .identity = self.bytes[at + 4 + length ..][0..32].* };
            at += 4 + length + 32;
        }
        return out;
    }
};

/// What a pack's first bytes say about the records in it.
pub const Liveness = enum {
    /// Some group is a kind at an identity in the list: the pack may serve.
    live,
    /// No group is: every record in it is of an identity no registered kind has.
    dead,
    /// The bytes are not the start of a pack.
    damaged,
};

/// Whether the pack that starts with `prefix` holds records of any of the `current` kinds at their identities. `whole` says the prefix is the entire file,
/// so a group cut off by its end is damage; otherwise it only means the answer needs more bytes, and the pack counts as live.
pub fn liveness(prefix: []const u8, whole: bool, current: []const Group) Liveness {
    if (prefix.len < fixed_length or !std.mem.eql(u8, prefix[0..magic.len], magic)) return .damaged;
    if (std.mem.readInt(u32, prefix[magic.len..][0..4], .little) != format_version) return .damaged;
    const groups = std.mem.readInt(u32, prefix[magic.len + 8 ..][0..4], .little);
    var at: usize = fixed_length;
    for (0..groups) |_| {
        if (at + 4 > prefix.len) return if (whole) .damaged else .live;
        const length = std.mem.readInt(u32, prefix[at..][0..4], .little);
        if (length > longest_name) return .damaged;
        if (at + 4 + length + 32 > prefix.len) return if (whole) .damaged else .live;
        const kind = prefix[at + 4 ..][0..length];
        const identity = prefix[at + 4 + length ..][0..32];
        for (current) |known| {
            if (std.mem.eql(u8, kind, known.kind) and std.mem.eql(u8, identity, &known.identity)) return .live;
        }
        at += 4 + length + 32;
    }
    return .dead;
}

/// The file name of the pack with index digest `sum`, written at `now` (nanoseconds, never negative): the time first, so newer packs sort later.
pub fn fileName(a: std.mem.Allocator, now: i64, sum: Digest) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(a, "{d:0>20}-{s}{s}", .{ @as(u64, @intCast(@max(now, 0))), digest_rules.hex(sum)[0..16], suffix });
}

/// Whether `name` is the file name of a pack.
pub fn isPackName(name: []const u8) bool {
    return std.mem.endsWith(u8, name, suffix) and std.mem.indexOfScalar(u8, name, '.') == name.len - suffix.len;
}

fn sampleGroups() [2]Group {
    return .{ .{ .kind = "module-check", .identity = @splat(1) }, .{ .kind = "module-syntax", .identity = @splat(2) } };
}

fn keyOf(byte: u8) Digest {
    return @splat(byte);
}

test "a pack finds each record by its key and nothing else, whatever order the items came in" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const items = [_]Item{ .{ .key = keyOf(9), .bytes = "nine" }, .{ .key = keyOf(3), .bytes = "three" }, .{ .key = keyOf(200), .bytes = "" }, .{ .key = keyOf(5), .bytes = "five!" } };
    const groups = sampleGroups();
    const built = (try build(a, &groups, &items)).?;
    const view = View.parse(built.bytes).?;
    try std.testing.expectEqual(built.digest, view.digest);
    try std.testing.expectEqual(@as(u32, 4), view.count);
    try std.testing.expectEqualStrings("nine", view.find(keyOf(9)).?);
    try std.testing.expectEqualStrings("three", view.find(keyOf(3)).?);
    try std.testing.expectEqualStrings("five!", view.find(keyOf(5)).?);
    try std.testing.expectEqualStrings("", view.find(keyOf(200)).?);
    try std.testing.expectEqual(@as(?[]const u8, null), view.find(keyOf(4)));
    try std.testing.expectEqual(@as(?[]const u8, null), view.find(keyOf(255)));
    const listed = try view.groupList(a);
    try std.testing.expectEqual(@as(usize, 2), listed.len);
    try std.testing.expectEqualStrings("module-syntax", listed[1].kind);
    try std.testing.expectEqual(keyOf(2), listed[1].identity);
}

test "two items under one key make no pack" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const items = [_]Item{ .{ .key = keyOf(1), .bytes = "a" }, .{ .key = keyOf(1), .bytes = "b" } };
    try std.testing.expect(try build(a, &.{}, &items) == null);
}

test "a pack that is damaged anywhere in its header or index is not a pack, and a damaged record does not damage the pack" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const items = [_]Item{ .{ .key = keyOf(1), .bytes = "one" }, .{ .key = keyOf(2), .bytes = "two" } };
    const groups = sampleGroups();
    const bytes = (try build(a, &groups, &items)).?.bytes;
    try std.testing.expect(View.parse(bytes) != null);
    const records_at = bytes.len - "onetwo".len;
    try expectEveryFlipRefused(a, bytes, records_at);
    // A flipped byte of a record leaves the pack parsing: the record's own trailer is what refuses it.
    const hurt = try a.dupe(u8, bytes);
    hurt[records_at] ^= 1;
    try std.testing.expectEqualStrings("nne", View.parse(hurt).?.find(keyOf(1)).?);
    // Every shorter file is not a pack either.
    try expectEveryPrefixRefused(bytes);
}

fn expectEveryFlipRefused(a: std.mem.Allocator, bytes: []const u8, upto: usize) !void {
    for (0..upto) |at| {
        const copy = try a.dupe(u8, bytes);
        copy[at] ^= 0x40;
        try std.testing.expectEqual(@as(?View, null), View.parse(copy));
    }
}

fn expectEveryPrefixRefused(bytes: []const u8) !void {
    for (0..bytes.len) |length| try std.testing.expectEqual(@as(?View, null), View.parse(bytes[0..length]));
}

test "a pack is live while any of its groups is a kind at its identity in the list" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const groups = sampleGroups();
    const bytes = (try build(a, &groups, &.{.{ .key = keyOf(1), .bytes = "x" }})).?.bytes;
    const other = [_]Group{ .{ .kind = "module-check", .identity = @splat(9) }, .{ .kind = "elsewhere", .identity = @splat(2) } };
    try std.testing.expectEqual(Liveness.dead, liveness(bytes, true, &other));
    try std.testing.expectEqual(Liveness.dead, liveness(bytes, true, &.{}));
    const kept = [_]Group{ .{ .kind = "module-syntax", .identity = @splat(2) }, .{ .kind = "elsewhere", .identity = @splat(2) } };
    try std.testing.expectEqual(Liveness.live, liveness(bytes, true, &kept));
    // A prefix that ends inside the groups cannot say no: the pack is read whole; a whole file that ends there is damaged.
    try std.testing.expectEqual(Liveness.live, liveness(bytes[0 .. fixed_length + 10], false, &other));
    try std.testing.expectEqual(Liveness.damaged, liveness(bytes[0 .. fixed_length + 10], true, &other));
    try std.testing.expectEqual(Liveness.damaged, liveness("not a pack at all, though it is long enough", true, &kept));
}

test "a pack's file name carries the time and the index digest, and only such names are packs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const name = try fileName(a, 1234, keyOf(0xab));
    try std.testing.expectEqualStrings("00000000000000001234-abababababababab.pack", name);
    try std.testing.expect(isPackName(name));
    try std.testing.expect(!isPackName("00000000000000001234-abababababababab.pack.1.2.partial"));
    try std.testing.expect(!isPackName("notes.txt"));
    try std.testing.expect(std.mem.lessThan(u8, name, try fileName(a, 1235, keyOf(0))));
}
