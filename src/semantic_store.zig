//! Durable, validated storage for one compiler's successful checked bodies.
//!
//! C2 persists the owned, remappable checked body representation without dumping
//! any in-memory pointer, allocator capacity, catalog ordinal or process address.
//! A file is written as a complete header/body/checksum image into a temporary
//! name in the destination directory and atomically renamed over the stable key,
//! so a concurrent reader either sees the previous complete entry or the new one.
//!
//! Every decode is a miss unless the file's format version, contract fingerprint,
//! mutation-contract version, stable declaration key, dependency context,
//! checksum, lengths, reference ordinals and source ranges all validate. The
//! cache caller still remaps declaration identities through C1R and treats a
//! missing or ambiguous remap as a miss; this module never integrates a decoded
//! body by itself.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const codec = @import("persist_codec.zig");
const owned = @import("semantic_entry.zig");
const cache_key = @import("cache_key.zig");

/// On-disk format version. Bump for any layout, tag or validation change.
pub const format_version = "semantic-cache-v1";
/// Default root for ordinary one-shot commands; `--cache-dir=DIR` maps to
/// `DIR/semantic` through the same shared cache-root option.
pub const default_directory = ".mylang-cache/semantic";
/// Default total-byte budget for one contract namespace. `put` evicts the
/// oldest complete files after a successful publication when this is exceeded.
/// mirror-of: src/frontend_cache.zig.default_max_bytes
pub const default_max_bytes: usize = 128 * 1024 * 1024;
/// Default entry-count budget for one contract namespace.
pub const default_max_entries: usize = 65_536;
/// A single body never grows beyond this, so a damaged length field cannot make
/// a reader allocate an unbounded in-memory entry.
pub const max_entry_bytes: usize = 64 * 1024 * 1024;
/// Declaration counts are bounded because lookup allocates remap arrays sized by
/// the decoded counts before any body can be trusted.
pub const max_declarations: usize = 1 << 20;

const entry_magic: u32 = 0x4d595343; // "CSYM" little-endian.

/// Optional source slices for the body and declaration region. Keeping them in
/// one field leaves room in the public `StoredBody` shape for the persisted
/// metadata notes.
pub const SourceBytes = struct {
    old_len: usize = 0,
    body: []const u8 = &.{},
    region: []const u8 = &.{},
};

/// Persisted payload for one checked body. It carries the complete relocatable
/// tree, the stable references C1R uses to remap it, the source-region bytes
/// used to prove the declaration was not edited, and the body-local notes in
/// `meta.notes`.
pub const StoredBody = struct {
    meta: owned.Metadata,
    function: typed.Function,
    nodes: []const typed.Node,
    statements: []const typed.Statement,
    range: @import("semantic_copy.zig").Range,
    source_bytes: SourceBytes = .{},
};

/// Actual durable-store observations reported by the host. A hit is returned
/// only after a complete checksum, identity and bounds validation.
pub const Statistics = struct {
    hits: usize = 0,
    misses: usize = 0,
    stored: usize = 0,
    damaged: usize = 0,
    bypassed: usize = 0,
    evicted: usize = 0,
    retained: Retained = .{},
};

/// Bytes and file count retained in one contract namespace.
pub const Retained = struct {
    bytes: usize = 0,
    entries: usize = 0,
};

/// One contract-namespaced durable directory. `deinit` releases only borrowed
/// paths; cache files remain on disk for later processes.
pub const Root = struct {
    path: []const u8,
    owned: bool = false,
};
/// Versioned compiler contract that isolates one durable namespace.
pub const Context = struct {
    contract: cache_key.Contract,
    hex: [64]u8,
    mutation_contract: []const u8,
};
/// Total-byte, entry-count and single-entry bounds for one namespace.
pub const Limits = struct {
    max_bytes: usize = default_max_bytes,
    max_entries: usize = default_max_entries,
    max_entry_bytes: usize = max_entry_bytes,
};
/// Durable store for one contract namespace. Public methods return misses for
/// every malformed, foreign or unvalidated entry and never mutate compiler state.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: Root,
    context: Context,
    limits: Limits = .{},
    statistics: Statistics = .{},

    /// Open a store rooted at `root` under one cache-key contract and mutation
    /// version. The caller keeps `root` and `mutation_contract` alive.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, root: []const u8, contract: cache_key.Contract, mutation_contract: []const u8) Store {
        var hex: [64]u8 = undefined;
        contract.fingerprintHex(&hex);
        return .{
            .allocator = allocator,
            .io = io,
            .root = .{ .path = root },
            .context = .{ .contract = contract, .hex = hex, .mutation_contract = mutation_contract },
        };
    }

    pub fn deinit(self: *Store) void {
        if (self.root.owned) self.allocator.free(self.root.path);
    }

    /// Stable key for one declaration under one dependency context.
    fn entryKey(self: *const Store, stable_key: []const u8, context: [32]u8) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(format_version);
        hash.update(&self.context.hex);
        frame(&hash, self.context.mutation_contract);
        frame(&hash, stable_key);
        hash.update(&context);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    fn namespace(self: *Store) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.root.path, format_version, &self.context.hex });
    }

    fn entryPath(self: *Store, stable_key: []const u8, context: [32]u8) error{OutOfMemory}![]const u8 {
        const directory = try self.namespace();
        defer self.allocator.free(directory);
        const key = self.entryKey(stable_key, context);
        const hex = std.fmt.bytesToHex(key, .lower);
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ directory, hex });
    }

    /// Decode at most one exact stable-key/context entry. Every malformed or
    /// version-incompatible file is a miss and never reaches the caller.
    pub fn lookup(self: *Store, allocator: std.mem.Allocator, stable_key: []const u8, context: [32]u8) error{ OutOfMemory, InternalError }!?owned.Entry {
        const path = self.entryPath(stable_key, context) catch return error.OutOfMemory;
        defer self.allocator.free(path);
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(@min(self.limits.max_entry_bytes, self.limits.max_bytes))) catch |err| switch (err) {
            error.FileNotFound => {
                self.statistics.misses += 1;
                return null;
            },
            error.StreamTooLong => {
                self.statistics.damaged += 1;
                self.statistics.misses += 1;
                return null;
            },
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.misses += 1;
                return null;
            },
        };
        defer self.allocator.free(bytes);

        var reader = codec.Reader.init(self.allocator, bytes);
        const magic = reader.integer(u32) catch return self.reject();
        if (magic != entry_magic) return self.reject();
        const version = takeString(&reader) catch return self.reject();
        if (!std.mem.eql(u8, version, format_version)) return self.reject();
        const contract = reader.integer([64]u8) catch return self.reject();
        if (!std.mem.eql(u8, &contract, &self.context.hex)) return self.reject();
        const mutation = takeString(&reader) catch return self.reject();
        if (!std.mem.eql(u8, mutation, self.context.mutation_contract)) return self.reject();
        const entry_count = reader.integer(u64) catch return self.reject();
        if (entry_count != 1) return self.reject();
        const key = takeString(&reader) catch return self.reject();
        if (!std.mem.eql(u8, key, stable_key)) return self.reject();
        const stored_context = reader.integer([32]u8) catch return self.reject();
        if (!std.mem.eql(u8, &stored_context, &context)) return self.reject();
        const payload_len = reader.integer(u64) catch return self.reject();
        const payload = reader.slice(std.math.cast(usize, payload_len) orelse return self.reject()) catch return self.reject();
        const checksum = reader.integer(u64) catch return self.reject();
        if (!reader.done()) return self.reject();
        const checksum_offset = reader.at - @sizeOf(u64);
        if (std.hash.XxHash3.hash(0, bytes[0..checksum_offset]) != checksum) return self.reject();

        var arena = std.heap.ArenaAllocator.init(allocator);
        var accepted = false;
        defer if (!accepted) arena.deinit();
        var payload_reader = codec.Reader.init(arena.allocator(), payload);
        const body = payload_reader.read(StoredBody) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.reject(),
        };
        if (!payload_reader.done()) return self.reject();
        if (!self.valid(body)) return self.reject();
        if (!std.mem.eql(u8, body.meta.identity.key, stable_key)) return self.reject();
        if (!std.mem.eql(u8, &body.meta.identity.context, &context)) return self.reject();

        self.statistics.hits += 1;
        accepted = true;
        return .{
            .arena = arena,
            .function = body.function,
            .nodes = body.nodes,
            .statements = body.statements,
            .range = body.range,
            .source = .{ .old_len = body.source_bytes.old_len, .body_bytes = body.source_bytes.body, .region_bytes = body.source_bytes.region },
            .meta = body.meta,
        };
    }

    fn reject(self: *Store) ?owned.Entry {
        self.statistics.damaged += 1;
        self.statistics.misses += 1;
        return null;
    }

    /// Validate decoded ranges/tags/ordinals before constructing an entry.
    fn valid(self: *Store, body: StoredBody) bool {
        const identity = body.meta.identity;
        if (identity.key.len == 0 or identity.key.len > self.limits.max_entry_bytes) return false;
        if (body.source_bytes.old_len == 0) return false;
        if (identity.body.start > identity.body.end or identity.body.end > body.source_bytes.old_len) return false;
        if (identity.region.start > identity.region.end or identity.region.end > body.source_bytes.old_len) return false;
        if (identity.body.end - identity.body.start != body.source_bytes.body.len) return false;
        if (identity.region.end - identity.region.start != body.source_bytes.region.len) return false;
        if (body.range.nodes.start > body.range.nodes.end) return false;
        if (body.range.nodes.end - body.range.nodes.start != body.nodes.len) return false;
        if (body.range.statements.start > body.range.statements.end) return false;
        if (body.range.statements.end - body.range.statements.start != body.statements.len) return false;
        return self.validRefs(body) and self.validNotes(body);
    }

    fn validRefs(self: *Store, body: StoredBody) bool {
        if (body.meta.old_function_count > max_declarations or body.meta.old_record_count > max_declarations) return false;
        if (body.meta.function_refs.len > max_declarations or body.meta.record_refs.len > max_declarations) return false;
        for (body.meta.function_refs) |reference| {
            if (@backingInt(reference.id) >= body.meta.old_function_count) return false;
            if (reference.key.len == 0 or reference.key.len > self.limits.max_entry_bytes) return false;
        }
        for (body.meta.record_refs) |reference| {
            if (reference.index >= body.meta.old_record_count) return false;
            if (reference.key.len == 0 or reference.key.len > self.limits.max_entry_bytes) return false;
        }
        return true;
    }

    fn validNotes(self: *Store, body: StoredBody) bool {
        if (body.meta.notes.len > max_declarations) return false;
        for (body.meta.notes) |note| {
            if (note.code.len == 0 or note.code.len > self.limits.max_entry_bytes) return false;
            if (note.message.len == 0 or note.message.len > self.limits.max_entry_bytes) return false;
            if (note.span.start > note.span.end or note.span.end > body.source_bytes.old_len) return false;
            if (note.related) |related| {
                if (related.message.len > self.limits.max_entry_bytes) return false;
                if (related.span.start > related.span.end or related.span.end > body.source_bytes.old_len) return false;
            }
            if (note.provenance) |related| {
                if (related.message.len > self.limits.max_entry_bytes) return false;
                if (related.span.start > related.span.end or related.span.end > body.source_bytes.old_len) return false;
            }
        }
        return true;
    }

    /// Publish one entry atomically. Write failures are cache bypasses, never
    /// command failures; only allocation failure is returned to the caller.
    pub fn put(self: *Store, entry: *const owned.Entry) error{OutOfMemory}!bool {
        if (!self.validOwned(entry)) {
            self.statistics.bypassed += 1;
            return false;
        }
        const context = entry.meta.identity.context;
        var payload = codec.Writer.init(self.allocator);
        defer payload.deinit();
        payload.write(StoredBody, .{
            .meta = entry.meta,
            .function = entry.function,
            .nodes = entry.nodes,
            .statements = entry.statements,
            .range = entry.range,
            .source_bytes = .{ .old_len = entry.source.old_len, .body = entry.source.body_bytes, .region = entry.source.region_bytes },
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (payload.bytes.items.len > self.limits.max_entry_bytes) {
            self.statistics.bypassed += 1;
            return false;
        }

        var image = codec.Writer.init(self.allocator);
        defer image.deinit();
        image.integer(entry_magic) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.write([]const u8, format_version) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.raw(&self.context.hex) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.write([]const u8, self.context.mutation_contract) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.integer(@as(u64, 1)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.write([]const u8, entry.meta.identity.key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.raw(&context) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.integer(@as(u64, payload.bytes.items.len)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.raw(payload.bytes.items) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.integer(std.hash.XxHash3.hash(0, image.bytes.items)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };

        const path = self.entryPath(entry.meta.identity.key, context) catch return error.OutOfMemory;
        defer self.allocator.free(path);
        const directory = std.fs.path.dirname(path) orelse return false;
        std.Io.Dir.cwd().createDirPath(self.io, directory) catch {
            self.statistics.bypassed += 1;
            return false;
        };
        var staging_buffer: [std.fs.max_path_bytes + 64]u8 = undefined;
        var nonce: [8]u8 = undefined;
        std.Io.random(self.io, &nonce);
        const staging = std.fmt.bufPrint(&staging_buffer, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return false;
        const file = std.Io.Dir.cwd().createFile(self.io, staging, .{ .truncate = true }) catch {
            self.statistics.bypassed += 1;
            return false;
        };
        var open = true;
        defer if (open) file.close(self.io);
        file.writeStreamingAll(self.io, image.bytes.items) catch {
            file.close(self.io);
            open = false;
            std.Io.Dir.cwd().deleteFile(self.io, staging) catch |err| switch (err) {
                error.FileNotFound => {},
                else => self.statistics.bypassed += 1,
            };
            self.statistics.bypassed += 1;
            return false;
        };
        file.sync(self.io) catch {
            file.close(self.io);
            open = false;
            std.Io.Dir.cwd().deleteFile(self.io, staging) catch |err| switch (err) {
                error.FileNotFound => {},
                else => self.statistics.bypassed += 1,
            };
            self.statistics.bypassed += 1;
            return false;
        };
        file.close(self.io);
        open = false;
        std.Io.Dir.rename(.cwd(), staging, .cwd(), path, self.io) catch {
            std.Io.Dir.cwd().deleteFile(self.io, staging) catch |err| switch (err) {
                error.FileNotFound => {},
                else => self.statistics.bypassed += 1,
            };
            self.statistics.bypassed += 1;
            return false;
        };
        self.statistics.stored += 1;
        self.trim() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.WriteFailed => self.statistics.bypassed += 1,
        };
        return true;
    }

    fn validOwned(self: *Store, entry: *const owned.Entry) bool {
        if (entry.meta.identity.key.len == 0 or entry.meta.identity.key.len > self.limits.max_entry_bytes) return false;
        if (entry.source.old_len == 0) return false;
        if (entry.meta.identity.body.start > entry.meta.identity.body.end or entry.meta.identity.body.end > entry.source.old_len) return false;
        if (entry.meta.identity.region.start > entry.meta.identity.region.end or entry.meta.identity.region.end > entry.source.old_len) return false;
        if (entry.source.body_bytes.len != entry.meta.identity.body.end - entry.meta.identity.body.start) return false;
        if (entry.source.region_bytes.len != entry.meta.identity.region.end - entry.meta.identity.region.start) return false;
        if (entry.range.nodes.start > entry.range.nodes.end) return false;
        if (entry.range.nodes.end - entry.range.nodes.start != entry.nodes.len) return false;
        if (entry.range.statements.start > entry.range.statements.end) return false;
        if (entry.range.statements.end - entry.range.statements.start != entry.statements.len) return false;
        if (entry.meta.old_function_count > max_declarations or entry.meta.old_record_count > max_declarations) return false;
        if (entry.meta.function_refs.len > max_declarations or entry.meta.record_refs.len > max_declarations or entry.meta.notes.len > max_declarations) return false;
        for (entry.meta.function_refs) |reference| {
            if (reference.key.len == 0 or reference.key.len > self.limits.max_entry_bytes) return false;
        }
        for (entry.meta.record_refs) |reference| {
            if (reference.key.len == 0 or reference.key.len > self.limits.max_entry_bytes) return false;
        }
        for (entry.meta.notes) |note| {
            if (note.code.len == 0 or note.code.len > self.limits.max_entry_bytes) return false;
            if (note.message.len == 0 or note.message.len > self.limits.max_entry_bytes) return false;
            if (note.span.start > note.span.end or note.span.end > entry.source.old_len) return false;
        }
        return true;
    }

    /// Bound the contract namespace by bytes and entry count. Trimming is a
    /// best-effort operation: a concurrent publisher may add a file while this
    /// iterates, and a lost race only costs a later miss.
    fn trim(self: *Store) error{ OutOfMemory, WriteFailed }!void {
        const directory = self.namespace() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer self.allocator.free(directory);
        var dir = std.Io.Dir.cwd().openDir(self.io, directory, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var entries: std.ArrayList(DiskEntry) = .empty;
        defer {
            for (entries.items) |entry| self.allocator.free(entry.name);
            entries.deinit(self.allocator);
        }
        var total: usize = 0;
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch return error.WriteFailed) |item| {
            if (item.kind != .file or std.mem.endsWith(u8, item.name, ".tmp")) continue;
            const stat = dir.statFile(self.io, item.name, .{}) catch continue;
            const name = self.allocator.dupe(u8, item.name) catch return error.OutOfMemory;
            entries.append(self.allocator, .{ .name = name, .size = @intCast(stat.size), .mtime = stat.mtime.nanoseconds }) catch {
                self.allocator.free(name);
                return error.OutOfMemory;
            };
            total += @intCast(stat.size);
        }
        self.statistics.retained.bytes = total;
        self.statistics.retained.entries = entries.items.len;
        if (total <= self.limits.max_bytes and entries.items.len <= self.limits.max_entries) return;
        std.mem.sort(DiskEntry, entries.items, {}, oldestFirst);
        var remaining = entries.items.len;
        for (entries.items) |entry| {
            if (total <= self.limits.max_bytes and remaining <= self.limits.max_entries) break;
            dir.deleteFile(self.io, entry.name) catch continue;
            total -= entry.size;
            remaining -= 1;
            self.statistics.evicted += 1;
            self.statistics.retained.entries -= 1;
        }
        self.statistics.retained.bytes = total;
    }
};

fn takeString(reader: *codec.Reader) ![]const u8 {
    const length = try reader.integer(u64);
    const count = std.math.cast(usize, length) orelse return error.InvalidEncoding;
    if (count > reader.bytes.len - reader.at) return error.Truncated;
    return reader.slice(count);
}

fn frame(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

const DiskEntry = struct { name: []const u8, size: usize, mtime: i128 };

fn oldestFirst(_: void, a: DiskEntry, b: DiskEntry) bool {
    return a.mtime < b.mtime;
}
