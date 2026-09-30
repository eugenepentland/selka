//! The embedded files (`EMBED-1`) a native manifest defines as static objects.
//!
//! A unit loads an embedded file as `loadl $myl_emb_<kind>_<digest>`. The
//! manifest's `embeds` table carries each distinct file once, with the header
//! facts the metadata unit needs to lay out the frozen `bytes` or `str` object
//! it points at. The payload is kept out of unit text on purpose: text that
//! held a whole file would be scanned by every text pass and hashed by every
//! cache key that names the unit, once per byte of the file each time.
const std = @import("std");
const source = @import("source.zig");
const native_types = @import("native_types.zig");
const native_descriptors = @import("native_descriptors.zig");

/// Element descriptor of a frozen `str`: its payload is UTF-8 octets, which hold no traced pointer.
pub const text_leaf = "myl_native_text_leaf";

/// The spelling of a static object symbol: `myl_emb_`, the kind letter, `_`, then 64 hex digits.
pub const Symbol = [10 + 64]u8;

/// The static object symbol of one embedded file, named by its kind and content digest.
pub fn symbol(text: bool, digest: [32]u8) Symbol {
    var out: Symbol = undefined;
    const kind: u8 = if (text) 's' else 'b';
    _ = std.fmt.bufPrint(&out, "myl_emb_{c}_{s}", .{ kind, std.fmt.bytesToHex(digest, .lower) }) catch return @splat('_');
    return out;
}

/// One distinct embedded file as the manifest states it: the object's symbol,
/// its element descriptor and width (zero for a `str`), its payload octet
/// count, for a `str` its scalar count and whether every scalar is ASCII, and
/// the payload as lowercase hex.
pub const Entry = struct {
    symbol: []const u8,
    element: []const u8,
    width: usize,
    count: usize,
    scalars: usize,
    ascii: bool,
    hex: []const u8,
};

/// Every distinct file the program's embed calls read, in canonical symbol
/// order, ready for the manifest. A call whose file did not read is skipped:
/// the checker already rejected it.
pub fn table(allocator: std.mem.Allocator, src: source.Source, layouts: *const native_types.Catalog) (std.mem.Allocator.Error || native_types.Error)![]const Entry {
    var entries: std.ArrayList(Entry) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    const sources: []const source.Source = if (src.origins.len == 0) (&.{src}) else blk: {
        const list = try allocator.alloc(source.Source, src.origins.len);
        for (list, src.origins) |*item, origin| item.* = origin.original;
        break :blk list;
    };
    for (sources) |one| for (one.embeds) |file| {
        if (file.status != .ok) continue;
        const name = try allocator.dupe(u8, symbol(file.text, file.digest)[0..]);
        if ((try seen.getOrPut(allocator, name)).found_existing) continue;
        try entries.append(allocator, try entry(allocator, layouts, name, file));
    };
    std.mem.sort(Entry, entries.items, {}, entryBefore);
    return entries.toOwnedSlice(allocator);
}

fn entryBefore(_: void, left: Entry, right: Entry) bool {
    return std.mem.order(u8, left.symbol, right.symbol) == .lt;
}

/// The manifest row for one file.
fn entry(allocator: std.mem.Allocator, layouts: *const native_types.Catalog, name: []const u8, file: source.Embed) (std.mem.Allocator.Error || native_types.Error)!Entry {
    const hex = try allocator.alloc(u8, file.contents.len * 2);
    for (file.contents, 0..) |byte, i| {
        hex[i * 2] = std.fmt.hex_charset[byte >> 4];
        hex[i * 2 + 1] = std.fmt.hex_charset[byte & 0xf];
    }
    var row: Entry = .{
        .symbol = name,
        .element = if (file.text) text_leaf else try native_descriptors.symbol(allocator, layouts, .u8),
        .width = if (file.text) 0 else 1,
        .count = file.contents.len,
        .scalars = file.contents.len,
        .ascii = true,
        .hex = hex,
    };
    if (file.text) {
        row.scalars = 0;
        for (file.contents) |byte| {
            // A UTF-8 scalar starts at every byte that is not a continuation byte.
            if (byte & 0xc0 != 0x80) row.scalars += 1;
            if (byte >= 0x80) row.ascii = false;
        }
    }
    return row;
}

test "embed symbols name the kind and the content digest" {
    var digest: [32]u8 = @splat(0xab);
    const bytes_symbol = symbol(false, digest);
    const text_symbol = symbol(true, digest);
    try std.testing.expect(std.mem.startsWith(u8, &bytes_symbol, "myl_emb_b_abab"));
    try std.testing.expect(std.mem.startsWith(u8, &text_symbol, "myl_emb_s_abab"));
    digest[0] = 0;
    try std.testing.expect(!std.mem.eql(u8, &bytes_symbol, &symbol(false, digest)));
}

// spec-case: EMBED-1
test "embed metadata uses the same canonical order across source and module visitation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var layouts = try native_types.Catalog.initRecords(a, &.{});
    defer layouts.deinit();
    const first: source.Embed = .{ .literal = .{ .start = 0, .end = 1 }, .path = "first", .status = .ok, .digest = @splat(1), .contents = "a" };
    const second: source.Embed = .{ .literal = .{ .start = 2, .end = 3 }, .path = "second", .status = .ok, .digest = @splat(2), .contents = "bb" };
    const forward: source.Source = .{ .path = "main.my", .bytes = "", .line_starts = &.{0}, .embeds = &.{ first, second, first } };
    var backward = forward;
    backward.embeds = &.{ second, first };
    const left = try table(a, forward, &layouts);
    const right = try table(a, backward, &layouts);
    try std.testing.expectEqual(@as(usize, 2), left.len);
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}
