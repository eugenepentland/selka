//! The whole-build replay record's envelope, shared by `build_replay.zig` (which writes and reads records) and the stage
//! roots (`stage_roots.zig`, which needs only the demand generation each record names). A leaf module: it imports no
//! front-end code, so reading a record's generation does not depend on the driver.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");

/// The record format. Version 8 names the demand scope of the generation a record publishes; older records are misses.
pub const version = "core-build-replay-v8";

/// The demand generation the recorded build published, in the scope `scope` names (`demand_generation.scopeName`).
/// Ownership proofs name no generation, and an uncached build publishes generation 0.
pub const Published = struct { demand: u64 = 0, scope: []const u8 = "" };

/// The JSON envelope of a record: its version, its payload text and the payload's hex checksum.
pub const Envelope = struct { version: []const u8, payload: []const u8, checksum: []const u8 };

/// The part of a payload the roots read.
const Named = struct { published: Published = .{} };

/// Parse a record's envelope and verify its version and checksum; null for a damaged or foreign record.
pub fn open(a: std.mem.Allocator, bytes: []const u8) ?Envelope {
    const envelope = std.json.parseFromSliceLeaky(Envelope, a, bytes, .{ .ignore_unknown_fields = true }) catch return null;
    if (!std.mem.eql(u8, envelope.version, version)) return null;
    if (envelope.checksum.len != 64) return null;
    var recorded: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&recorded, envelope.checksum) catch return null;
    var digest: [32]u8 = undefined;
    fast_blake3.hash(envelope.payload, &digest);
    if (!std.mem.eql(u8, &digest, &recorded)) return null;
    return envelope;
}

/// The generation a record names, read from its payload; null for a damaged or foreign record.
pub fn publishedOf(a: std.mem.Allocator, bytes: []const u8) ?Published {
    const envelope = open(a, bytes) orelse return null;
    const named = std.json.parseFromSliceLeaky(Named, a, envelope.payload, .{ .ignore_unknown_fields = true }) catch return null;
    return named.published;
}

/// The generations of every readable record in `directory` (`replay-v1`) that publishes one, in no particular order.
/// A missing directory names none; a record that cannot be read is skipped, which costs its generation's roots only.
pub fn scan(a: std.mem.Allocator, io: std.Io, directory: []const u8) std.mem.Allocator.Error![]Published {
    var found: std.ArrayList(Published) = .empty;
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return found.items;
    defer dir.close(io);
    var entries = dir.iterate();
    while (entries.next(io) catch return found.items) |entry| {
        if (entry.kind != .file or std.mem.endsWith(u8, entry.name, ".partial")) continue;
        const path = try std.fs.path.join(a, &.{ directory, entry.name });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(64 << 20)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        const published = publishedOf(a, bytes) orelse continue;
        if (published.demand == 0 or published.scope.len == 0) continue;
        try found.append(a, published);
    }
    return found.items;
}

test "a record names the generation it published, and a damaged or foreign one names none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const payload = try std.json.Stringify.valueAlloc(a, .{ .published = Published{ .demand = 3, .scope = "abc" } }, .{});
    var digest: [32]u8 = undefined;
    fast_blake3.hash(payload, &digest);
    const checksum = std.fmt.bytesToHex(digest, .lower);
    const record = try std.json.Stringify.valueAlloc(a, Envelope{ .version = version, .payload = payload, .checksum = &checksum }, .{});
    const published = publishedOf(a, record) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 3), published.demand);
    try std.testing.expectEqualStrings("abc", published.scope);
    const foreign = try std.json.Stringify.valueAlloc(a, Envelope{ .version = "core-build-replay-v7", .payload = payload, .checksum = &checksum }, .{});
    try std.testing.expect(publishedOf(a, foreign) == null);
    const damaged = try std.json.Stringify.valueAlloc(a, Envelope{ .version = version, .payload = "{}", .checksum = &checksum }, .{});
    try std.testing.expect(publishedOf(a, damaged) == null);
}
