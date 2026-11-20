//! A pack of semantic-store entries (G4c3): the payloads one build published to its work directory, one file instead of hundreds, so
//! that a worktree whose work directory is empty reads the entries its sibling checked and replays them instead of checking again.
//!
//! The bytes are sorted by entry key, so a lookup is a binary search over the index in place and a reader parses nothing:
//!
//! ```
//! magic "selka-semantic-pack-v1\n" | count u32 | count x (key [32]u8 | offset u32 | length u32) | payloads
//! ```
//!
//! Offsets are from the start of the payload area. The pack carries no checksum of its own: the shared store's record around it
//! verifies every byte (BLAKE3), and every payload is checked again by the decoder that uses it, exactly as an entry read from a
//! work directory's own file is.
const std = @import("std");

/// The first bytes of a pack.
pub const magic = "selka-semantic-pack-v1\n";
/// Bytes of one index row: the entry key, then the payload's offset and length.
const row_size = 32 + 4 + 4;
/// The largest pack: offsets and lengths are 32 bits.
pub const maximum_bytes: usize = std.math.maxInt(u32);

/// One entry of a pack under construction: its key and payload (borrowed).
pub const Item = struct { key: [32]u8, payload: []const u8 };

/// Encode `items` as a pack in memory owned by `allocator`. Entries with equal keys keep one payload (the last of them), since a key names
/// its payload. Null when the pack would not fit 32-bit offsets.
pub fn encode(allocator: std.mem.Allocator, items: []Item) error{OutOfMemory}!?[]u8 {
    std.mem.sort(Item, items, {}, keyBefore);
    var unique: usize = 0;
    var payload_bytes: usize = 0;
    for (items, 0..) |item, i| {
        if (i + 1 < items.len and std.mem.eql(u8, &item.key, &items[i + 1].key)) continue;
        items[unique] = item;
        unique += 1;
        payload_bytes += item.payload.len;
    }
    const kept = items[0..unique];
    const header = magic.len + 4 + kept.len * row_size;
    if (header + payload_bytes > maximum_bytes) return null;
    const out = try allocator.alloc(u8, header + payload_bytes);
    @memcpy(out[0..magic.len], magic);
    std.mem.writeInt(u32, out[magic.len..][0..4], @intCast(kept.len), .little);
    var offset: usize = 0;
    for (kept, 0..) |item, i| {
        const row = out[magic.len + 4 + i * row_size ..][0..row_size];
        @memcpy(row[0..32], &item.key);
        std.mem.writeInt(u32, row[32..36], @intCast(offset), .little);
        std.mem.writeInt(u32, row[36..40], @intCast(item.payload.len), .little);
        @memcpy(out[header + offset ..][0..item.payload.len], item.payload);
        offset += item.payload.len;
    }
    return out;
}

fn keyBefore(_: void, left: Item, right: Item) bool {
    return std.mem.order(u8, &left.key, &right.key) == .lt;
}

/// A pack's bytes, validated once: the index lies inside them and every row's payload lies inside the payload area.
pub const Reader = struct {
    bytes: []const u8,
    count: usize,

    /// The reader of `bytes`, or null when they are not a well-formed pack.
    pub fn open(bytes: []const u8) ?Reader {
        if (bytes.len < magic.len + 4 or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
        const count: usize = std.mem.readInt(u32, bytes[magic.len..][0..4], .little);
        const header = std.math.add(usize, magic.len + 4, std.math.mul(usize, count, row_size) catch return null) catch return null;
        if (header > bytes.len) return null;
        const area = bytes.len - header;
        for (0..count) |i| {
            const row = bytes[magic.len + 4 + i * row_size ..][0..row_size];
            const offset: usize = std.mem.readInt(u32, row[32..36], .little);
            const length: usize = std.mem.readInt(u32, row[36..40], .little);
            if (offset > area or length > area - offset) return null;
        }
        return .{ .bytes = bytes, .count = count };
    }

    /// The key of row `index`.
    pub fn keyAt(self: Reader, index: usize) *const [32]u8 {
        return self.bytes[magic.len + 4 + index * row_size ..][0..32];
    }

    /// The payload of row `index`.
    pub fn payloadAt(self: Reader, index: usize) []const u8 {
        const row = self.bytes[magic.len + 4 + index * row_size ..][0..row_size];
        const header = magic.len + 4 + self.count * row_size;
        const offset: usize = std.mem.readInt(u32, row[32..36], .little);
        const length: usize = std.mem.readInt(u32, row[36..40], .little);
        return self.bytes[header + offset ..][0..length];
    }

    /// The payload stored under `key`, or null.
    // twin-drift-ok: the same binary search as `engine/context.zig` `findPart`, over the rows of a packed index (32-byte keys read in place), not over named parts.
    pub fn find(self: Reader, key: [32]u8) ?[]const u8 {
        var low: usize = 0;
        var high: usize = self.count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            switch (std.mem.order(u8, self.keyAt(middle), &key)) {
                .eq => return self.payloadAt(middle),
                .lt => low = middle + 1,
                .gt => high = middle,
            }
        }
        return null;
    }
};

test "a pack finds each payload by its key, keeps one payload for a repeated key, and refuses damaged bytes" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var items = [_]Item{
        .{ .key = @splat(9), .payload = "nine" },
        .{ .key = @splat(2), .payload = "two" },
        .{ .key = @splat(5), .payload = "" },
        .{ .key = @splat(2), .payload = "two" },
    };
    const bytes = (try encode(a, &items)).?;
    const reader = Reader.open(bytes).?;
    try t.expectEqual(@as(usize, 3), reader.count);
    try t.expectEqualStrings("nine", reader.find(@splat(9)).?);
    try t.expectEqualStrings("two", reader.find(@splat(2)).?);
    try t.expectEqualStrings("", reader.find(@splat(5)).?);
    try t.expect(reader.find(@splat(3)) == null);
    try t.expect(Reader.open(bytes[0 .. bytes.len - 1]) == null);
    try t.expect(Reader.open(bytes[0 .. magic.len + 2]) == null);
    const wrong = try a.dupe(u8, bytes);
    wrong[0] ^= 1;
    try t.expect(Reader.open(wrong) == null);
    const empty = (try encode(a, items[0..0])).?;
    try t.expectEqual(@as(usize, 0), Reader.open(empty).?.count);
}
