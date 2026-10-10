//! Verified, content-addressed intermediate compiler artifacts. Cache failures
//! lose reuse, never a build: bounded, checked journal records become immutable packs.
const std = @import("std");
const codec = @import("mylang").persist_codec;
const unit_cache = @import("unit_cache.zig");

/// A compiler-stage input or artifact digest.
pub const Digest = [32]u8;
/// Cache I/O failures are misses; allocation failures remain explicit.
pub const Error = std.mem.Allocator.Error;

const magic = "mylang-stage-v1\n";
const packs = @import("stage_pack.zig");

/// Store-local diagnostic write settings; existing blocks retain their encoding.
pub const Options = struct { compression: @import("stage_compression.zig").Policy = .zlib };

/// Immutable shared store settings. Backing must support concurrent callers when
/// emission workers share this store; each operation uses a private scratch arena.
pub const Store = struct {
    backing: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    identity: Digest,
    storage: *packs.State,

    /// Prepare a lazily created store bound to the complete compiler identity.
    pub fn init(backing: std.mem.Allocator, io: std.Io, cache_root: []const u8) Error!Store {
        return initWithOptions(backing, io, cache_root, .{});
    }

    /// Select new block encoding while preserving stage keys and read compatibility.
    pub fn initWithOptions(backing: std.mem.Allocator, io: std.Io, cache_root: []const u8, options: Options) Error!Store {
        const root = try std.fs.path.join(backing, &.{ cache_root, "stages-packed-v1" });
        errdefer backing.free(root);
        var identity: Digest = undefined;
        std.crypto.hash.Blake3.hash(@import("frontend_reuse.zig").compiler_identity, &identity, .{});
        return .{ .backing = backing, .io = io, .root = root, .identity = identity, .storage = try packs.State.init(backing, io, root, identity, options.compression) };
    }

    /// Release the owned path after all users of the store finish.
    pub fn deinit(self: *Store) void {
        self.storage.deinit();
        self.backing.free(self.root);
    }

    /// Bind length-delimited inputs to a stage schema and this compiler.
    pub fn key(self: *const Store, scope: []const u8, parts: []const []const u8) Digest {
        var hash = std.crypto.hash.Blake3.init(.{});
        unit_cache.field(&hash, magic);
        unit_cache.field(&hash, &self.identity);
        unit_cache.field(&hash, scope);
        for (parts) |part| unit_cache.field(&hash, part);
        var digest: Digest = undefined;
        hash.final(&digest);
        return digest;
    }

    /// Publish pending journal records as immutable compressed packs.
    pub fn flush(self: *const Store) Error!bool {
        return self.storage.flush();
    }

    /// Physical packed reads and block decoding expose warm-path amplification.
    pub fn statistics(self: *const Store) packs.Statistics {
        return self.storage.statistics();
    }

    /// Locate the durable file containing a key for diagnostics and loss tests.
    pub fn artifactPath(self: *const Store, a: std.mem.Allocator, digest: Digest) Error!?[]const u8 {
        return self.storage.artifactPath(a, digest);
    }

    /// Read an owned payload after validating its complete key and checksum.
    /// Absent, oversized, truncated, foreign, and damaged entries are misses.
    pub fn load(self: *const Store, a: std.mem.Allocator, digest: Digest) Error!?[]u8 {
        return self.loadExpected(a, digest, null);
    }

    /// Validate a known canonical payload digest during the ordinary checksum
    /// pass, avoiding a second hash by callers that already know its identity.
    pub fn loadExpected(self: *const Store, a: std.mem.Allocator, digest: Digest, expected: ?Digest) Error!?[]u8 {
        return self.storage.load(a, digest, expected);
    }

    /// Publish a complete journal record before returning; cache I/O fails closed.
    pub fn save(self: *const Store, digest: Digest, payload: []const u8) Error!bool {
        return self.storage.save(digest, payload);
    }

    /// Decode plain slice-owned data into the caller's arena; invalid schemas miss.
    /// Callers validate stage-specific indices before applying the restored value.
    pub fn loadValue(self: *const Store, arena: std.mem.Allocator, digest: Digest, comptime T: type) Error!?T {
        const bytes = try self.load(self.backing, digest) orelse return null;
        defer self.backing.free(bytes);
        var reader = codec.Reader.init(arena, bytes);
        const value = reader.read(T) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        if (!reader.done()) return null;
        return value;
    }

    /// Encode and publish plain slice-owned data without retaining encoding scratch.
    pub fn storeValue(self: *const Store, digest: Digest, comptime T: type, value: T) Error!void {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        var writer = codec.Writer.init(scratch.allocator());
        try writer.write(T, value);
        _ = try self.save(digest, writer.bytes.items);
    }
};
