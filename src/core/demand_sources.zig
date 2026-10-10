//! Exact original-file authority for nonlocal cached source locations.
const std = @import("std");
const language = @import("mylang");
const stage = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");

/// Exact bytes and path belonging to one ordered original-source slot.
pub const Proof = struct { origin: ?u32, path: []const u8, digest: stage.Digest };

/// Only origins actually referenced by receipts or bodies are hashed.
pub const Cache = struct {
    arena: std.mem.Allocator,
    source: ?language.source.Source = null,
    proofs: std.AutoHashMapUnmanaged(?u32, Proof) = .empty,

    /// Reset memoized authority for the fresh checked source catalog.
    pub fn bind(self: *Cache, source: language.source.Source) void {
        self.source = source;
        self.proofs.clearRetainingCapacity();
    }

    /// Hash one valid original source once, rejecting absent provenance.
    pub fn get(self: *Cache, origin: ?u32) std.mem.Allocator.Error!?Proof {
        if (self.proofs.get(origin)) |proof| return proof;
        const source = self.source orelse return null;
        const original = if (origin) |index| original: {
            if (index >= source.origins.len) return null;
            break :original source.origins[index].original;
        } else original: {
            if (source.origins.len != 0) return null;
            break :original source;
        };
        var proof: Proof = .{ .origin = origin, .path = original.path, .digest = undefined };
        std.crypto.hash.Blake3.hash(original.bytes, &proof.digest, .{});
        try self.proofs.put(self.arena, origin, proof);
        return proof;
    }

    /// Compare stored authority with already prepared fresh source digests.
    pub fn matches(self: *const Cache, proofs: []const Proof) bool {
        for (proofs) |proof| {
            const current = self.proofs.get(proof.origin) orelse return false;
            if (!std.mem.eql(u8, current.path, proof.path) or !std.mem.eql(u8, &current.digest, &proof.digest)) return false;
        }
        return true;
    }

    /// Add the original-file proof for a location, deduplicated by origin.
    pub fn collect(self: *Cache, list: *std.ArrayList(Proof), location: snapshot.Location) std.mem.Allocator.Error!bool {
        const proof = try self.get(location.origin) orelse return false;
        for (list.items) |existing| if (existing.origin == proof.origin) return true;
        try list.append(self.arena, proof);
        return true;
    }
};
