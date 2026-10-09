//! Verified, content-addressed intermediate compiler artifacts. Cache failures
//! lose reuse, never a build: records are bounded, checked, and atomically renamed.
const std = @import("std");
const codec = @import("mylang").persist_codec;
const unit_cache = @import("unit_cache.zig");

/// A compiler-stage input or artifact digest.
pub const Digest = [32]u8;
/// Cache I/O failures are misses; allocation failures remain explicit.
pub const Error = std.mem.Allocator.Error;

const magic = "mylang-stage-v1\n";
const header_size = magic.len + 32 + 32;
const maximum_bytes = 256 << 20;
const artifact_suffix = ".stage";

/// Immutable shared store settings. Backing must support concurrent callers when
/// emission workers share this store; each operation uses a private scratch arena.
pub const Store = struct {
    backing: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    identity: Digest,

    /// Prepare a lazily created store bound to the complete compiler identity.
    pub fn init(backing: std.mem.Allocator, io: std.Io, cache_root: []const u8) Error!Store {
        const root = try std.fs.path.join(backing, &.{ cache_root, "stages-v1" });
        var identity: Digest = undefined;
        std.crypto.hash.Blake3.hash(@import("frontend_reuse.zig").compiler_identity, &identity, .{});
        return .{ .backing = backing, .io = io, .root = root, .identity = identity };
    }

    /// Release the owned path after all users of the store finish.
    pub fn deinit(self: *Store) void {
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

    fn path(self: *const Store, a: std.mem.Allocator, digest: Digest) Error![]const u8 {
        return std.fmt.allocPrint(a, "{s}/{s}{s}", .{ self.root, std.fmt.bytesToHex(digest, .lower), artifact_suffix });
    }

    /// Read an owned payload after validating its complete key and checksum.
    /// Absent, oversized, truncated, foreign, and damaged entries are misses.
    pub fn load(self: *const Store, a: std.mem.Allocator, digest: Digest) Error!?[]u8 {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const work = scratch.allocator();
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, try self.path(work, digest), work, .limited(maximum_bytes + header_size)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
        if (!std.mem.eql(u8, bytes[magic.len..][0..32], &digest)) return null;
        const payload = bytes[header_size..];
        var actual: Digest = undefined;
        std.crypto.hash.Blake3.hash(payload, &actual, .{});
        if (!std.mem.eql(u8, bytes[magic.len + 32 ..][0..32], &actual)) return null;
        const owned = try a.dupe(u8, payload);
        return owned;
    }

    /// Publish one complete record by an atomic rename on the cache filesystem.
    /// An unavailable cache returns false; the freshly computed result remains valid.
    pub fn save(self: *const Store, digest: Digest, payload: []const u8) Error!bool {
        if (payload.len > maximum_bytes) return false;
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const a = scratch.allocator();
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(self.io, self.root) catch return false;
        const final_path = try self.path(a, digest);
        var nonce: [16]u8 = undefined;
        std.Io.random(self.io, &nonce);
        const partial = try std.fmt.allocPrint(a, "{s}.{s}.partial", .{ final_path, std.fmt.bytesToHex(nonce, .lower) });
        defer discard(self.io, partial);
        const bytes = try a.alloc(u8, header_size + payload.len);
        @memcpy(bytes[0..magic.len], magic);
        @memcpy(bytes[magic.len..][0..32], &digest);
        std.crypto.hash.Blake3.hash(payload, bytes[magic.len + 32 ..][0..32], .{});
        @memcpy(bytes[header_size..], payload);
        cwd.writeFile(self.io, .{ .sub_path = partial, .data = bytes }) catch return false;
        cwd.rename(partial, cwd, final_path, self.io) catch return false;
        return true;
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

fn discard(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}
