//! Compact verified final facts retained for decoding only by LLVM render misses.
const std = @import("std");
const facts = @import("facts.zig");
const codec = @import("mylang").persist_codec;
const stages = @import("stage_store.zig");
pub const Error = std.mem.Allocator.Error || error{CacheMiss};

/// Canonical encoded analysis identity used by eager and deferred emission keys.
pub const Digest = [32]u8;
/// Immutable verified bytes; their dense tables belong only to a decoding worker.
pub const Artifact = struct { bytes: []const u8, digest: Digest, loop_ids: []const usize = &.{} };

/// Verified durable analysis retains only its key and loop-ID sidecar.
pub const Handle = struct { key: Digest, digest: Digest, loop_ids: []const usize };

/// Prepared on the coordinator and immutable while emission workers run.
pub const Table = struct {
    entries: []?Artifact = &.{},
    handles: []?Handle = &.{},
    store: ?*const stages.Store = null,

    /// Allocate one optional encoded artifact slot per physical function.
    pub fn init(a: std.mem.Allocator, count: usize) std.mem.Allocator.Error!Table {
        const entries = try a.alloc(?Artifact, count);
        errdefer a.free(entries);
        const handles = try a.alloc(?Handle, count);
        @memset(entries, null);
        @memset(handles, null);
        return .{ .entries = entries, .handles = handles };
    }

    /// No dense decoding is needed to key an unchanged LLVM unit.
    pub fn identity(self: *const Table, index: usize) ?Digest {
        if (index >= self.entries.len) return null;
        if (self.entries[index]) |artifact| return artifact.digest;
        if (index < self.handles.len) if (self.handles[index]) |handle| return handle.digest;
        return null;
    }

    /// Keep a durable handle after cached bytes were verified before IR mutation.
    /// Fresh facts remain in entries because cache publication may have failed.
    pub fn deferArtifact(self: *Table, a: std.mem.Allocator, index: usize, store: *const stages.Store, key: Digest, artifact: Artifact) std.mem.Allocator.Error!void {
        std.debug.assert(index < self.handles.len);
        self.handles[index] = .{ .key = key, .digest = artifact.digest, .loop_ids = try a.dupe(usize, artifact.loop_ids) };
        self.entries[index] = null;
        self.store = store;
    }

    /// Decode selected facts on worker scratch; cache loss requests eager retry.
    pub fn load(self: *const Table, a: std.mem.Allocator, index: usize) Error!?facts.Facts {
        if (index >= self.entries.len) return null;
        const artifact = self.entries[index] orelse blk: {
            if (index >= self.handles.len) return null;
            const handle = self.handles[index] orelse return null;
            const store = self.store orelse return error.CacheMiss;
            const bytes = try store.loadExpected(a, handle.key, handle.digest) orelse return error.CacheMiss;
            break :blk Artifact{ .bytes = bytes, .digest = handle.digest, .loop_ids = handle.loop_ids };
        };
        const known = try decode(a, artifact);
        return known;
    }
};

/// Encode retained analysis without checker-global loop IDs affecting identity.
pub fn encode(a: std.mem.Allocator, known: facts.Facts) std.mem.Allocator.Error!Artifact {
    var normalized = known;
    const counted = try a.dupe(facts.Counted, known.counted);
    defer a.free(counted);
    const loop_ids = try a.alloc(usize, counted.len);
    errdefer a.free(loop_ids);
    for (counted, loop_ids) |*loop, *id| {
        id.* = loop.loop.id;
        loop.loop.id = 0;
    }
    normalized.counted = counted;
    var writer = codec.Writer.init(a);
    defer writer.deinit();
    try writer.write(facts.Facts, normalized);
    const bytes = try writer.bytes.toOwnedSlice(a);
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return .{ .bytes = bytes, .digest = digest, .loop_ids = loop_ids };
}

/// Eager emission uses the same canonical analysis identity as deferred emission.
pub fn fingerprint(a: std.mem.Allocator, known: ?facts.Facts) std.mem.Allocator.Error!?Digest {
    const present = known orelse return null;
    const artifact = try encode(a, present);
    defer a.free(artifact.bytes);
    defer a.free(artifact.loop_ids);
    return artifact.digest;
}

/// Decode trusted immutable bytes, restoring checker IDs from the metadata sidecar.
pub fn decode(a: std.mem.Allocator, artifact: Artifact) std.mem.Allocator.Error!facts.Facts {
    var reader = codec.Reader.init(a, artifact.bytes);
    const known = reader.read(facts.Facts) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // Bytes are freshly encoded or content-verified before applying final IR.
        else => unreachable,
    };
    std.debug.assert(reader.done());
    std.debug.assert(known.counted.len == artifact.loop_ids.len);
    for (@constCast(known.counted), artifact.loop_ids) |*counted, id| counted.loop.id = id;
    return known;
}
