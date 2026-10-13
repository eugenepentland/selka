//! Durable, validated storage for one compiler's successful checked bodies.
//!
//! C2 persists the owned, remappable checked body representation without dumping
//! any in-memory pointer, allocator capacity, catalog ordinal or process address.
//! A file is written as a complete header/body/checksum image into a temporary
//! name in the destination directory and atomically renamed over the stable key,
//! so a concurrent reader either sees the previous complete entry or the new one.
//!
//! Publication through `beginBatch`/`endBatch` writes and atomically renames each
//! entry and inventories the namespace once per bounded group. Nothing is ever
//! synchronized to disk (SEMANTIC-CACHE-15): a crash can leave a torn or missing
//! image, which the entry checksum rejects as a miss; no partial or incompatible
//! image is ever accepted. `--no-cache` never opens a store.
//!
//! Every decode is a miss unless the file's format version, contract fingerprint,
//! mutation-contract version, stable declaration key, dependency context,
//! checksum, lengths, reference ordinals and source ranges all validate. The
//! cache caller still remaps declaration identities through C1R and treats a
//! missing or ambiguous remap as a miss; this module never integrates a decoded
//! body by itself.
const std = @import("std");
const sources = @import("semantic_sources.zig");
const typed = @import("typed.zig");
const semantic_copy = @import("semantic_copy.zig");
const source = @import("source.zig");
const codec = @import("persist_codec.zig");
const owned = @import("semantic_entry.zig");
const cache_key = @import("cache_key.zig");
const shared_artifacts = @import("shared_artifact_store.zig");

/// On-disk format version (`semantic_cache_format.zig`, which `build.zig` reads
/// without compiling this store). Bump it there for any layout, tag or
/// validation change.
pub const format_version = @import("semantic_cache_format.zig").version;
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
    modules: []const sources.Reference = &.{},
    trailing: []const u8 = &.{},
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
    range: semantic_copy.Range,
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

/// Bytes, file count and publication observations for one contract namespace.
pub const Retained = struct {
    bytes: usize = 0,
    entries: usize = 0,
    /// Full namespace inventories observed by this store. A publication batch
    /// performs at most one seeding inventory, one per bounded-slack
    /// reconciliation and one final inventory, never one per published body.
    /// Exposed so tests can assert the population path is not per-body.
    inventories: usize = 0,
};

/// One contract-namespaced durable directory. `deinit` releases only borrowed
/// paths; cache files remain on disk for later processes.
pub const Root = struct {
    path: []const u8,
    owned: bool = false,
    /// Optional process-owned immutable transport for path-free ordinary bodies.
    shared: ?*shared_artifacts.Store = null,
    /// Exact source/catalog layout supplied before this request's hydration.
    shared_source: ?[32]u8 = null,
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
/// Incremental accounting for one publication batch. The hot path adds each
/// published body's on-disk size without touching the namespace; when those
/// additions grow large enough to matter the batch seeds from one namespace
/// inventory, and `endBatch` always reconciles once more. That keeps a fresh
/// population linear in the number of bodies while still converging on the
/// retention bounds.
const Batch = struct {
    bytes: usize,
    entries: usize,
    /// True once `bytes`/`entries` describe the whole namespace. A namespace
    /// that did not exist at `beginBatch` is empty and starts seeded.
    seeded: bool,
};
/// How far a batch's incremental accounting may exceed a bound before it
/// reconciles with the on-disk namespace. The slack is proportional to the
/// bound, so a namespace held at its limit still amortizes one O(namespace)
/// inventory over O(bound / slack) publications, with a floor that keeps tiny
/// test bounds batching instead of reconciling on every body.
fn reconciliationSlack(limit: usize) usize {
    return @max(limit / 16, 1024);
}
/// Durable store for one contract namespace. Public methods return misses for
/// every malformed, foreign or unvalidated entry and never mutate compiler state.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: Root,
    context: Context,
    limits: Limits = .{},
    statistics: Statistics = .{},
    /// Non-null while a caller is inside a publication batch. See `beginBatch`.
    batch: ?Batch = null,

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

    /// Borrow an immutable artifact store; all retained catalogs remain private.
    pub fn setSharedStore(self: *Store, store: ?*shared_artifacts.Store) void {
        self.root.shared = store;
        self.root.shared_source = null;
    }

    /// Bind immutable typed payloads to a proven logical source/catalog layout.
    pub fn setSharedSource(self: *Store, digest: ?[32]u8) void {
        self.root.shared_source = digest;
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
        const previous_misses = self.statistics.misses;
        const local_payload = try self.readPayload(stable_key, context);
        const from_shared = local_payload == null;
        const payload = local_payload orelse (try self.readSharedBody(stable_key, context)) orelse return null;
        defer self.allocator.free(payload);
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
        if (!validSelectionStorage(body.nodes, body.range)) return self.reject();
        if (!try validUnpackStorage(self.allocator, body.function, body.nodes, body.statements, body.range)) return self.reject();
        if (!std.mem.eql(u8, body.meta.identity.key, stable_key)) return self.reject();
        if (!std.mem.eql(u8, &body.meta.identity.context, &context)) return self.reject();
        if (from_shared and !portableBody(body)) return self.reject();

        self.statistics.misses = previous_misses;
        self.statistics.hits += 1;
        accepted = true;
        return .{
            .arena = arena,
            .function = body.function,
            .nodes = body.nodes,
            .statements = body.statements,
            .range = body.range,
            .source = .{ .old_len = body.source_bytes.old_len, .body_bytes = body.source_bytes.body, .region_bytes = body.source_bytes.region, .modules = body.source_bytes.modules, .trailing_bytes = body.source_bytes.trailing },
            .meta = body.meta,
        };
    }

    fn readSharedBody(self: *Store, stable_key: []const u8, context: [32]u8) error{ OutOfMemory, InternalError }!?[]u8 {
        const shared = self.root.shared orelse return null;
        if (!portableFunctionKey(stable_key)) return null;
        const key = self.sharedBodyKey(stable_key, context) orelse return null;
        return shared.load(self.allocator, .typed, key) catch |err| return sharedFailure(shared, err);
    }

    fn sharedBodyKey(self: *Store, stable_key: []const u8, context: [32]u8) ?[32]u8 {
        const layout = self.root.shared_source orelse return null;
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        frame(&hash, "portable-typed-body-v1");
        const key = self.entryKey(stable_key, context);
        hash.update(&key);
        hash.update(&layout);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        return digest;
    }

    /// Decode one abstract-checked symbolic entry. Uses the same header,
    /// checksum and bounds validation as `lookup`; the payload kind and every
    /// relative span are validated before the entry is returned.
    pub fn lookupSymbolic(self: *Store, allocator: std.mem.Allocator, stable_key: []const u8, context: [32]u8) error{ OutOfMemory, InternalError }!?owned.SymbolicEntry {
        const payload_bytes = (try self.readPayload(stable_key, context)) orelse return null;
        defer self.allocator.free(payload_bytes);
        var arena = std.heap.ArenaAllocator.init(allocator);
        var accepted = false;
        defer if (!accepted) arena.deinit();
        var payload_reader = codec.Reader.init(arena.allocator(), payload_bytes);
        const payload = payload_reader.read(owned.StoredSymbolic) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.rejectSymbolic(),
        };
        if (!payload_reader.done()) return self.rejectSymbolic();
        if (!owned.validSymbolic(payload, max_declarations, self.limits.max_entry_bytes)) return self.rejectSymbolic();
        if (!std.mem.eql(u8, payload.identity.key, stable_key)) return self.rejectSymbolic();
        if (!std.mem.eql(u8, &payload.identity.context, &context)) return self.rejectSymbolic();

        self.statistics.hits += 1;
        accepted = true;
        return .{ .arena = arena, .payload = payload };
    }

    /// Decode one checked concrete-specialization entry. Uses the same header,
    /// checksum and bounds validation as `lookup`; the payload kind, canonical
    /// fingerprint, ordered descriptors and every function/record reference are
    /// validated before the entry is returned. The caller still remaps the
    /// references against the fresh compilation and treats a missing or
    /// ambiguous remap as a miss.
    pub fn lookupSpecialization(self: *Store, allocator: std.mem.Allocator, stable_key: []const u8, context: [32]u8) error{ OutOfMemory, InternalError }!?owned.SpecializationEntry {
        const payload_bytes = (try self.readPayload(stable_key, context)) orelse return null;
        defer self.allocator.free(payload_bytes);
        var arena = std.heap.ArenaAllocator.init(allocator);
        var accepted = false;
        defer if (!accepted) arena.deinit();
        var payload_reader = codec.Reader.init(arena.allocator(), payload_bytes);
        const payload = payload_reader.read(owned.StoredSpecialization) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.rejectSpecialization(),
        };
        if (!payload_reader.done()) return self.rejectSpecialization();
        if (!owned.validSpecialization(payload, max_declarations, self.limits.max_entry_bytes)) return self.rejectSpecialization();
        if (!validSelectionStorage(payload.body.nodes, payload.body.range)) return self.rejectSpecialization();
        if (!try validUnpackStorage(self.allocator, payload.body.function, payload.body.nodes, payload.body.statements, payload.body.range)) return self.rejectSpecialization();
        if (!std.mem.eql(u8, payload.identity.key, stable_key)) return self.rejectSpecialization();
        if (!std.mem.eql(u8, &payload.identity.context, &context)) return self.rejectSpecialization();

        self.statistics.hits += 1;
        accepted = true;
        return .{ .arena = arena, .payload = payload };
    }

    /// Read and validate one complete on-disk image, returning an owned copy of
    /// its payload bytes. Header, contract, key, context, length and checksum
    /// are all checked before the caller decodes the payload kind.
    fn readPayload(self: *Store, stable_key: []const u8, context: [32]u8) error{ OutOfMemory, InternalError }!?[]u8 {
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
        const magic = reader.integer(u32) catch return self.rejectPayload();
        if (magic != entry_magic) return self.rejectPayload();
        const version = takeString(&reader) catch return self.rejectPayload();
        if (!std.mem.eql(u8, version, format_version)) return self.rejectPayload();
        const contract = reader.integer([64]u8) catch return self.rejectPayload();
        if (!std.mem.eql(u8, &contract, &self.context.hex)) return self.rejectPayload();
        const mutation = takeString(&reader) catch return self.rejectPayload();
        if (!std.mem.eql(u8, mutation, self.context.mutation_contract)) return self.rejectPayload();
        const entry_count = reader.integer(u64) catch return self.rejectPayload();
        if (entry_count != 1) return self.rejectPayload();
        const key = takeString(&reader) catch return self.rejectPayload();
        if (!std.mem.eql(u8, key, stable_key)) return self.rejectPayload();
        const stored_context = reader.integer([32]u8) catch return self.rejectPayload();
        if (!std.mem.eql(u8, &stored_context, &context)) return self.rejectPayload();
        const payload_len = reader.integer(u64) catch return self.rejectPayload();
        const payload = reader.slice(std.math.cast(usize, payload_len) orelse return self.rejectPayload()) catch return self.rejectPayload();
        const checksum = reader.integer(u64) catch return self.rejectPayload();
        if (!reader.done()) return self.rejectPayload();
        const checksum_offset = reader.at - @sizeOf(u64);
        if (codec.checksum(bytes[0..checksum_offset]) != checksum) return self.rejectPayload();
        return self.allocator.dupe(u8, payload) catch error.OutOfMemory;
    }

    fn reject(self: *Store) ?owned.Entry {
        self.statistics.damaged += 1;
        self.statistics.misses += 1;
        return null;
    }

    fn rejectSymbolic(self: *Store) ?owned.SymbolicEntry {
        self.statistics.damaged += 1;
        self.statistics.misses += 1;
        return null;
    }

    fn rejectSpecialization(self: *Store) ?owned.SpecializationEntry {
        self.statistics.damaged += 1;
        self.statistics.misses += 1;
        return null;
    }

    fn rejectPayload(self: *Store) ?[]u8 {
        self.statistics.damaged += 1;
        self.statistics.misses += 1;
        return null;
    }

    /// Validate decoded ranges/tags/ordinals before constructing an entry.
    fn valid(self: *Store, body: StoredBody) bool {
        const identity = body.meta.identity;
        if (identity.key.len == 0 or identity.key.len > self.limits.max_entry_bytes) return false;
        if (body.source_bytes.old_len == 0) return false;
        if (body.source_bytes.trailing.len > 3 or body.source_bytes.trailing.len > body.source_bytes.old_len -| body.meta.identity.region.end) return false;
        if (body.source_bytes.modules.len > max_declarations) return false;
        if (!sources.valid(body.source_bytes.modules, body.source_bytes.old_len)) return false;
        if (identity.body.start > identity.body.end or identity.body.end > body.source_bytes.old_len) return false;
        if (identity.region.start > identity.region.end or identity.region.end > body.source_bytes.old_len) return false;
        if (identity.body.end - identity.body.start != body.source_bytes.body.len) return false;
        if (identity.region.end - identity.region.start != body.source_bytes.region.len) return false;
        if (body.range.nodes.start > body.range.nodes.end) return false;
        if (body.range.nodes.end - body.range.nodes.start != body.nodes.len) return false;
        if (body.range.statements.start > body.range.statements.end) return false;
        if (body.range.statements.end - body.range.statements.start != body.statements.len) return false;
        return owned.validRangeHeaders(body.statements) and self.validRefs(body) and self.validNotes(body);
    }

    fn validRefs(self: *Store, body: StoredBody) bool {
        if (!owned.validTypeRecipes(body.meta, max_declarations)) return false;
        if (body.meta.old_function_count > max_declarations or body.meta.old_record_count > max_declarations) return false;
        if (body.meta.function_refs.len > max_declarations or body.meta.record_refs.len > max_declarations) return false;
        for (body.meta.function_refs) |reference| {
            if (@backingInt(reference.id) >= body.meta.old_function_count) return false;
            if (reference.key.len == 0 or reference.key.len > self.limits.max_entry_bytes) return false;
            if (reference.template) |template| if (template.len == 0 or template.len > self.limits.max_entry_bytes) return false;
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

    /// Publish one entry atomically. Private write failures bypass retention;
    /// configured shared-store failures are reported and fail the request.
    pub fn put(self: *Store, entry: *const owned.Entry) error{ OutOfMemory, InternalError }!bool {
        const valid_body = self.validOwned(entry) and validSelectionStorage(entry.nodes, entry.range);
        if (!valid_body or !try validUnpackStorage(self.allocator, entry.function, entry.nodes, entry.statements, entry.range)) {
            self.statistics.bypassed += 1;
            return false;
        }
        var payload = codec.Writer.init(self.allocator);
        defer payload.deinit();
        const body: StoredBody = .{
            .meta = entry.meta,
            .function = entry.function,
            .nodes = entry.nodes,
            .statements = entry.statements,
            .range = entry.range,
            .source_bytes = .{ .old_len = entry.source.old_len, .body = entry.source.body_bytes, .region = entry.source.region_bytes, .modules = entry.source.modules, .trailing = entry.source.trailing_bytes },
        };
        payload.write(StoredBody, body) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (self.root.shared) |shared| {
            if (portableBody(body)) {
                if (self.sharedBodyKey(entry.meta.identity.key, entry.meta.identity.context)) |key| _ = shared.save(.typed, key, payload.bytes.items) catch |err| return sharedFailure(shared, err);
            }
        }
        return self.publishPayload(entry.meta.identity.key, entry.meta.identity.context, payload.bytes.items);
    }

    /// Publish one abstract-checked symbolic entry under the C3 entry kind.
    pub fn putSymbolic(self: *Store, entry: *const owned.SymbolicEntry) error{OutOfMemory}!bool {
        if (!owned.validSymbolic(entry.payload, max_declarations, self.limits.max_entry_bytes)) {
            self.statistics.bypassed += 1;
            return false;
        }
        var payload = codec.Writer.init(self.allocator);
        defer payload.deinit();
        payload.write(owned.StoredSymbolic, entry.payload) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        return self.publishPayload(entry.payload.identity.key, entry.payload.identity.context, payload.bytes.items);
    }

    /// Publish one checked concrete-specialization entry under its own kind.
    pub fn putSpecialization(self: *Store, entry: *const owned.SpecializationEntry) error{OutOfMemory}!bool {
        const body = entry.payload.body;
        const valid_body = owned.validSpecialization(entry.payload, max_declarations, self.limits.max_entry_bytes) and validSelectionStorage(body.nodes, body.range);
        if (!valid_body or !try validUnpackStorage(self.allocator, body.function, body.nodes, body.statements, body.range)) {
            self.statistics.bypassed += 1;
            return false;
        }
        var payload = codec.Writer.init(self.allocator);
        defer payload.deinit();
        payload.write(owned.StoredSpecialization, entry.payload) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        return self.publishPayload(entry.payload.identity.key, entry.payload.identity.context, payload.bytes.items);
    }

    /// Encode and atomically publish one already-serialized payload. The
    /// checksum covers the complete header and payload image, and the rename is
    /// the only step visible to a concurrent reader.
    fn publishPayload(self: *Store, stable_key: []const u8, context: [32]u8, payload_bytes: []const u8) error{OutOfMemory}!bool {
        if (payload_bytes.len > self.limits.max_entry_bytes) {
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
        image.write([]const u8, stable_key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.raw(&context) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.integer(@as(u64, payload_bytes.len)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.raw(payload_bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        image.integer(codec.checksum(image.bytes.items)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };

        const path = self.entryPath(stable_key, context) catch return error.OutOfMemory;
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
        // No data sync (SEMANTIC-CACHE-15): a cache needs no durability. The
        // rename below is atomic, so a concurrent reader sees the complete image
        // from the page cache, and a crash before the disk kept the data can only
        // leave a torn or empty image that the entry checksum rejects as a miss.
        // A sync would instead wait for every dirty page of the filesystem.
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
        if (self.batch != null) {
            // Inside a batch: only note the new file's size. The full namespace
            // inventory happens when the accounting crosses a bound (bounded
            // slack) or once at `endBatch`, whichever comes first.
            try self.noteBatch(image.bytes.items.len);
        } else {
            self.trim() catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.WriteFailed => self.statistics.bypassed += 1,
            };
        }
        return true;
    }

    /// Begin a publication batch. A missing namespace is known empty, so a
    /// fresh population starts with accurate accounting and never seeds; an
    /// existing namespace starts unseeded and is inventoried lazily only once
    /// the batch's own additions are large enough to matter. Nested
    /// `beginBatch` calls are no-ops.
    pub fn beginBatch(self: *Store) error{OutOfMemory}!void {
        if (self.batch != null) return;
        self.batch = .{ .bytes = 0, .entries = 0, .seeded = !try self.namespaceExists() };
    }

    /// Finish a publication batch with one final namespace inventory. The
    /// inventory reconciles files added or removed by concurrent publishers and
    /// converges the store on its byte and entry bounds. Safe with no active
    /// batch; the accounting is discarded first so an allocation failure cannot
    /// leave the store expecting a future reconciliation.
    pub fn endBatch(self: *Store) error{OutOfMemory}!void {
        if (self.batch == null) return;
        self.batch = null;
        self.trim() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.WriteFailed => self.statistics.bypassed += 1,
        };
    }

    /// Whether the contract namespace directory exists. This is a single
    /// directory open, not an inventory: it never iterates or stats entries.
    fn namespaceExists(self: *Store) error{OutOfMemory}!bool {
        const directory = self.namespace() catch return error.OutOfMemory;
        defer self.allocator.free(directory);
        var dir = std.Io.Dir.cwd().openDir(self.io, directory, .{ .iterate = true }) catch return false;
        dir.close(self.io);
        return true;
    }

    /// Count and sum the complete files currently in the contract namespace.
    /// Used only to seed a batch's accounting, so the file names are not kept.
    fn countNamespace(self: *Store, total: *usize, count: *usize) error{OutOfMemory}!void {
        const directory = self.namespace() catch return error.OutOfMemory;
        defer self.allocator.free(directory);
        var dir = std.Io.Dir.cwd().openDir(self.io, directory, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        self.statistics.retained.inventories += 1;
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch return) |item| {
            if (item.kind != .file or std.mem.endsWith(u8, item.name, ".tmp")) continue;
            const stat = dir.statFile(self.io, item.name, .{}) catch continue;
            total.* += @intCast(stat.size);
            count.* += 1;
        }
    }

    /// Add one successfully published file to the batch accounting and
    /// reconcile if the batch is large enough to seed or a bound has been
    /// exceeded by the bounded slack.
    fn noteBatch(self: *Store, size: usize) error{OutOfMemory}!void {
        const batch = self.batch orelse return;
        const updated: Batch = .{
            .bytes = batch.bytes +| size,
            .entries = batch.entries +| 1,
            .seeded = batch.seeded,
        };
        self.batch = updated;
        self.statistics.retained.bytes = updated.bytes;
        self.statistics.retained.entries = updated.entries;
        try self.reconcileBatch();
    }

    /// Seed a batch from one namespace inventory once its own additions are
    /// large enough that a bound could be exceeded, then reconcile if the
    /// accounting has crossed a bound by more than the slack. Eviction is
    /// always chosen from a fresh inventory, so a concurrently republished
    /// entry is seen with its fresh mtime and is not evicted from stale names.
    fn reconcileBatch(self: *Store) error{OutOfMemory}!void {
        var batch = self.batch orelse return;
        if (!batch.seeded and self.batchNeedsSeed(batch)) {
            var total: usize = 0;
            var count: usize = 0;
            try self.countNamespace(&total, &count);
            // The inventory already includes this batch's published files, so
            // it replaces the incremental totals rather than adding to them.
            batch = .{ .bytes = total, .entries = count, .seeded = true };
            self.batch = batch;
        }
        if (!self.batchOverBound(batch)) return;
        self.trim() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.WriteFailed => self.statistics.bypassed += 1,
        };
        self.batch = .{
            .bytes = self.statistics.retained.bytes,
            .entries = self.statistics.retained.entries,
            .seeded = true,
        };
    }

    /// Whether a still-unseeded batch has published enough to justify the one
    /// namespace inventory that makes an existing population visible. Below
    /// this the batch's own additions are within the slack, so `endBatch`'s
    /// single inventory converges without an extra pass.
    fn batchNeedsSeed(self: *Store, batch: Batch) bool {
        if (batch.entries > reconciliationSlack(self.limits.max_entries)) return true;
        if (batch.bytes > reconciliationSlack(self.limits.max_bytes)) return true;
        return false;
    }

    fn batchOverBound(self: *Store, batch: Batch) bool {
        if (batch.bytes > self.limits.max_bytes and batch.bytes - self.limits.max_bytes > reconciliationSlack(self.limits.max_bytes)) return true;
        if (batch.entries > self.limits.max_entries and batch.entries - self.limits.max_entries > reconciliationSlack(self.limits.max_entries)) return true;
        return false;
    }

    fn validOwned(self: *Store, entry: *const owned.Entry) bool {
        if (entry.meta.identity.key.len == 0 or entry.meta.identity.key.len > self.limits.max_entry_bytes) return false;
        if (entry.source.old_len == 0) return false;
        if (entry.source.trailing_bytes.len > 3 or entry.source.trailing_bytes.len > entry.source.old_len -| entry.meta.identity.region.end) return false;
        if (entry.source.modules.len > max_declarations) return false;
        if (!sources.valid(entry.source.modules, entry.source.old_len)) return false;
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
            if (reference.template) |template| if (template.len == 0 or template.len > self.limits.max_entry_bytes) return false;
        }
        for (entry.meta.record_refs) |reference| {
            if (reference.key.len == 0 or reference.key.len > self.limits.max_entry_bytes) return false;
        }
        for (entry.meta.notes) |note| {
            if (note.code.len == 0 or note.code.len > self.limits.max_entry_bytes) return false;
            if (note.message.len == 0 or note.message.len > self.limits.max_entry_bytes) return false;
            if (note.span.start > note.span.end or note.span.end > entry.source.old_len) return false;
        }
        return owned.validRangeHeaders(entry.statements) and owned.validTypeRecipes(entry.meta, max_declarations);
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
        self.statistics.retained.inventories += 1;
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

// Shared bodies keep their complete identities. A pathname fallback is never
// shortened into a module name, and external source proofs remain local.
fn portableFunctionKey(key: []const u8) bool {
    var parts = std.mem.splitScalar(u8, key, '\x1f');
    if (!std.mem.eql(u8, parts.next() orelse return false, "fn")) return false;
    const module = parts.next() orelse return false;
    if (module.len == 0 or std.mem.endsWith(u8, module, ".my")) return false;
    var components = std.mem.splitScalar(u8, module, '.');
    while (components.next()) |component| {
        if (component.len == 0) return false;
        if (!(std.ascii.isAlphabetic(component[0]) or component[0] == '_')) return false;
        for (component) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    }
    const owner = parts.next() orelse return false;
    const name = parts.next() orelse return false;
    if (name.len == 0 or parts.next() != null) return false;
    return pathFree(owner) and pathFree(name);
}

fn pathFree(name: []const u8) bool {
    return std.mem.indexOfAny(u8, name, "/\\") == null;
}

/// Check body-local, acyclic selection operands before record-catalog relocation.
/// The live checker/Core must separately prove exact str and Optional shapes.
fn validSelectionStorage(nodes: []const typed.Node, range: semantic_copy.Range) bool {
    if (range.nodes.start > range.nodes.end or range.nodes.end - range.nodes.start != nodes.len) return false;
    for (nodes, 0..) |node, index| {
        const selection = switch (node.data) {
            .borrow_selection => |value| value,
            else => continue,
        };
        const first = @backingInt(selection.first);
        const second = @backingInt(selection.second);
        const current = range.nodes.start + index;
        if (first < range.nodes.start or first >= current) return false;
        if (second < range.nodes.start or second >= current) return false;
        const left = nodes[first - range.nodes.start].ty;
        const right = nodes[second - range.nodes.start].ty;
        if (!left.isAggregate() or right != node.ty) return false;
        switch (selection.kind) {
            .min_text, .max_text => if (left != node.ty) return false,
            .optional_default => {},
        }
    }
    return true;
}

/// Validate unpack storage before catalog relocation. The restored checker/Core
/// must additionally prove tuple arity and field types against the live catalog.
/// Local IDs stay local when the complete function scope is restored.
fn validUnpackStorage(allocator: std.mem.Allocator, function: typed.Function, nodes: []const typed.Node, statements: []const typed.Statement, range: semantic_copy.Range) error{OutOfMemory}!bool {
    const locals = function.scope.locals;
    var seen: []bool = &.{};
    defer allocator.free(seen);
    for (statements) |statement| switch (statement.data) {
        .assign => |store| if (store.unpack != null) return false,
        .range_loop => |loop| for (loop.parts) |part| {
            if (part.start.unpack != null or part.end.unpack != null) return false;
        },
        .initialize => |store| {
            const fields = store.unpack orelse continue;
            const whole = @backingInt(store.slot);
            const value = @backingInt(store.value);
            if (store.element or whole >= locals.len) return false;
            if (!locals[whole].usage.temporary or locals[whole].ownership.transfer_available) return false;
            if (value < range.nodes.start or value >= range.nodes.end) return false;
            if (value - range.nodes.start >= nodes.len) return false;
            const ty = nodes[value - range.nodes.start].ty;
            if (!ty.isAggregate() or locals[whole].ty != ty) return false;
            if (seen.len == 0) {
                seen = try allocator.alloc(bool, locals.len);
                @memset(seen, false);
            }
            for (fields) |field| if (field) |id| {
                const slot = @backingInt(id);
                if (slot >= locals.len or slot == whole or seen[slot]) return false;
                if (!locals[slot].usage.temporary) return false;
                seen[slot] = true;
            };
            // Clear only touched slots: many small unpacks after a wide one
            // remain O(locals + total field bindings), without repeated scans.
            for (fields) |field| if (field) |id| {
                seen[@backingInt(id)] = false;
            };
        },
        else => {},
    };
    return true;
}

fn portableBody(body: StoredBody) bool {
    if (!portableFunctionKey(body.meta.identity.key) or body.source_bytes.modules.len != 0) return false;
    for (body.meta.function_refs) |reference| {
        if (reference.template != null or !portableFunctionKey(reference.key)) return false;
    }
    for (body.meta.record_refs) |reference| if (!pathFree(reference.key)) return false;
    return true;
}

fn sharedFailure(store: *shared_artifacts.Store, err: anyerror) error{ OutOfMemory, InternalError } {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    store.reportFailure(err);
    return error.InternalError;
}

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

fn rangeHeaderImage(allocator: std.mem.Allocator, store: *Store, count: usize) !void {
    const header: typed.RangeParts = .{
        .binding = .{ .start = 0, .end = 1 },
        .start = .{ .slot = @fromBackingInt(0), .value = @fromBackingInt(0) },
        .end = .{ .slot = @fromBackingInt(1), .value = @fromBackingInt(0) },
        .setup = &.{},
        .loop = .{ .condition = @fromBackingInt(1), .body = @fromBackingInt(1) },
    };
    const headers = [_]typed.RangeParts{ header, header };
    const statements = [_]typed.Statement{
        .{ .span = .{ .start = 0, .end = 1 }, .terminates = false, .data = .{ .range_loop = .{
            .parts = headers[0..count],
        } } },
        .{ .span = .{ .start = 0, .end = 1 }, .terminates = true, .data = .{ .ret = @fromBackingInt(0) } },
    };
    const nodes = [_]typed.Node{
        .{ .span = .{ .start = 0, .end = 1 }, .ty = .i64, .data = .{ .integer = 0 } },
        .{ .span = .{ .start = 0, .end = 1 }, .ty = .bool, .data = .{ .boolean = false } },
    };
    const body: StoredBody = .{
        .meta = .{
            .identity = .{ .key = "range-header", .context = @splat(0), .body = .{ .start = 0, .end = 1 }, .region = .{ .start = 0, .end = 1 } },
            .old_function_count = 1,
            .old_record_count = 0,
            .function_refs = &.{},
            .record_refs = &.{},
        },
        .function = .{ .id = @fromBackingInt(0), .name = "main", .declaration = .{ .start = 0, .end = 1 }, .scope = .{ .body = @fromBackingInt(0) } },
        .nodes = &nodes,
        .statements = &statements,
        .range = .{ .nodes = .{ .start = 0, .end = 2 }, .statements = .{ .start = 0, .end = 2 } },
        .source_bytes = .{ .old_len = 1, .body = "x", .region = "x" },
    };
    var payload = codec.Writer.init(allocator);
    defer payload.deinit();
    try payload.write(StoredBody, body);
    try std.testing.expect(try store.publishPayload("range-header", @splat(0), payload.bytes.items));
}

// spec-case: TYPED-RANGE-1
test "durable range header corruption is a miss for empty and multiple owned headers" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, "range-header-test");
    defer store.deinit();
    try rangeHeaderImage(t.allocator, &store, 0);
    try t.expect((try store.lookup(t.allocator, "range-header", @splat(0))) == null);
    try rangeHeaderImage(t.allocator, &store, 2);
    try t.expect((try store.lookup(t.allocator, "range-header", @splat(0))) == null);
    try t.expectEqual(@as(usize, 2), store.statistics.damaged);
    try rangeHeaderImage(t.allocator, &store, 1);
    var entry = (try store.lookup(t.allocator, "range-header", @splat(0))).?;
    defer entry.deinit();
    try t.expectEqual(@as(usize, 1), entry.statements[0].data.range_loop.parts.len);
}

const UnpackDamage = enum { none, duplicate, outside, whole, node_before, node_after, element, assignment, range_start, range_end, visible_whole, available_whole, visible_field, mismatched_type, scalar };
const unpack_test_temporary = "<collection>";

fn unpackImage(allocator: std.mem.Allocator, store: *Store, damage: UnpackDamage) !void {
    const tuple: typed.Type = @fromBackingInt(typed.Type.record_base);
    const span: source.Span = .{ .start = 0, .end = 1 };
    var locals = [_]typed.Local{
        .{ .name = unpack_test_temporary, .declaration = span, .ty = tuple, .mutable = false, .usage = .{ .temporary = true } },
        .{ .name = unpack_test_temporary, .declaration = span, .ty = .i64, .mutable = false, .usage = .{ .temporary = true } },
        .{ .name = unpack_test_temporary, .declaration = span, .ty = .i64, .mutable = false, .usage = .{ .temporary = true } },
    };
    var nodes = [_]typed.Node{.{ .span = span, .ty = tuple, .data = .{ .record = &.{} } }};
    var fields = [_]?typed.LocalId{ @fromBackingInt(1), null, @fromBackingInt(2) };
    var binding: typed.Store = .{ .slot = @fromBackingInt(0), .value = @fromBackingInt(7), .unpack = &fields };
    switch (damage) {
        .duplicate => fields[2] = fields[0],
        .outside => fields[2] = @fromBackingInt(locals.len),
        .whole => fields[2] = binding.slot,
        .node_before => binding.value = @fromBackingInt(6),
        .node_after => binding.value = @fromBackingInt(8),
        .element => binding.element = true,
        .visible_whole => locals[0].usage.temporary = false,
        .available_whole => locals[0].ownership.transfer_available = true,
        .visible_field => locals[1].usage.temporary = false,
        .mismatched_type => locals[0].ty = .i64,
        .scalar => {
            nodes[0].ty = .i64;
            locals[0].ty = .i64;
        },
        else => {},
    }
    var statements = [_]typed.Statement{.{ .span = span, .terminates = false, .data = .{ .initialize = binding } }};
    var part: typed.RangeParts = .{
        .binding = span,
        .start = .{ .slot = @fromBackingInt(0), .value = @fromBackingInt(7) },
        .end = .{ .slot = @fromBackingInt(0), .value = @fromBackingInt(7) },
        .setup = &.{},
        .loop = .{ .condition = @fromBackingInt(7), .body = @fromBackingInt(11) },
    };
    if (damage == .assignment) statements[0].data = .{ .assign = binding };
    if (damage == .range_start or damage == .range_end) {
        if (damage == .range_start) part.start = binding else part.end = binding;
        statements[0].data = .{ .range_loop = .{ .parts = (&part)[0..1] } };
    }
    const body: StoredBody = .{
        .meta = .{
            .identity = .{ .key = "unpack", .context = @splat(0), .body = span, .region = span },
            .old_function_count = 1,
            .old_record_count = 1,
            .function_refs = &.{},
            .record_refs = &.{.{ .index = 0, .key = "tuple", .recipes = &.{.{ .tuple = &.{ .i64, .i64, .i64 } }} }},
        },
        .function = .{ .id = @fromBackingInt(0), .name = "main", .declaration = span, .scope = .{ .body = @fromBackingInt(11), .locals = &locals } },
        .nodes = &nodes,
        .statements = &statements,
        .range = .{ .nodes = .{ .start = 7, .end = 8 }, .statements = .{ .start = 11, .end = 12 } },
        .source_bytes = .{ .old_len = 1, .body = "x", .region = "x" },
    };
    var payload = codec.Writer.init(allocator);
    defer payload.deinit();
    try payload.write(StoredBody, body);
    try std.testing.expect(try store.publishPayload("unpack", @splat(0), payload.bytes.items));
}

// spec-case: SEMANTIC-CACHE-1
test "A08 unpack durable malformed slot contracts are cache misses" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, "unpack-test");
    defer store.deinit();
    for (std.meta.tags(UnpackDamage)[1..]) |damage| {
        try unpackImage(t.allocator, &store, damage);
        try t.expect((try store.lookup(t.allocator, "unpack", @splat(0))) == null);
    }
    try t.expectEqual(std.meta.tags(UnpackDamage).len - 1, store.statistics.damaged);
    try unpackImage(t.allocator, &store, .none);
    var entry = (try store.lookup(t.allocator, "unpack", @splat(0))).?;
    defer entry.deinit();
    const fields = entry.statements[0].data.initialize.unpack.?;
    try t.expectEqualSlices(?typed.LocalId, &.{ @fromBackingInt(1), null, @fromBackingInt(2) }, fields);
    try t.expect(try store.put(&entry));
    @constCast(entry.statements)[0].data.initialize.unpack = &.{ @fromBackingInt(1), @fromBackingInt(1) };
    try t.expect(!try store.put(&entry));
}

// spec-case: SEMANTIC-CACHE-1
test "A08 unpack prior semantic wire version refuses even with a valid checksum" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, "unpack-version-test");
    defer store.deinit();
    try unpackImage(t.allocator, &store, .none);
    const path = try store.entryPath("unpack", @splat(0));
    defer t.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .limited(max_entry_bytes));
    defer t.allocator.free(bytes);
    const old = "semantic-cache-v7";
    try t.expectEqual(old.len, format_version.len);
    @memcpy(bytes[12..][0..old.len], old);
    std.mem.writeInt(u64, bytes[bytes.len - 8 ..][0..8], codec.checksum(bytes[0 .. bytes.len - 8]), .little);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
    try t.expect((try store.lookup(t.allocator, "unpack", @splat(0))) == null);
    try t.expectEqual(@as(usize, 1), store.statistics.damaged);
}

// spec-case: SEMANTIC-CACHE-1
test "A08 unpack specialization decode and publication enforce the same slot contract" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, "unpack-specialization-test");
    defer store.deinit();
    try unpackImage(t.allocator, &store, .none);
    var entry = (try store.lookup(t.allocator, "unpack", @splat(0))).?;
    defer entry.deinit();
    var specialization: owned.SpecializationEntry = .{
        .arena = std.heap.ArenaAllocator.init(t.allocator),
        .payload = .{
            .identity = .{ .key = "unpack-specialization", .context = @splat(0), .fingerprint = "fixture", .template = "tuple", .arguments = &.{}, .lengths = &.{} },
            .source = .{ .old_len = 1, .region = entry.meta.identity.region, .body = entry.meta.identity.body, .region_bytes = "x", .body_bytes = "x" },
            .body = .{ .function = entry.function, .nodes = entry.nodes, .statements = entry.statements, .range = entry.range },
            .refs = .{ .function_refs = &.{}, .record_refs = entry.meta.record_refs },
            .counts = .{ .old_function_count = 1, .old_record_count = 1 },
        },
    };
    defer specialization.deinit();
    try t.expect(try store.putSpecialization(&specialization));
    var restored = (try store.lookupSpecialization(t.allocator, "unpack-specialization", @splat(0))).?;
    defer restored.deinit();
    @constCast(entry.statements)[0].data.initialize.unpack = &.{ @fromBackingInt(1), @fromBackingInt(1) };
    try t.expect(!try store.putSpecialization(&specialization));
    try t.expectEqual(@as(usize, 3), restored.payload.body.statements[0].data.initialize.unpack.?.len);
    var encoded = codec.Writer.init(t.allocator);
    defer encoded.deinit();
    try encoded.write(owned.StoredSpecialization, specialization.payload);
    try t.expect(try store.publishPayload("unpack-specialization", @splat(0), encoded.bytes.items));
    try t.expect((try store.lookupSpecialization(t.allocator, "unpack-specialization", @splat(0))) == null);
}

const SelectionKind = @TypeOf(@as(typed.BorrowSelection, undefined).kind);
const SelectionDamage = enum { none, first_before, second_before, first_self, second_self, first_after, second_after, scalar_first, wrong_second, wrong_result };
const selection_test_key = "selection-body";

fn selectionImage(allocator: std.mem.Allocator, store: *Store, kind: SelectionKind, damage: SelectionDamage, scalar_payload: bool) !void {
    const aggregate: typed.Type = @fromBackingInt(typed.Type.record_base);
    const optional: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    const value_type: typed.Type = if (scalar_payload) .i64 else aggregate;
    const owner_type = if (kind == .optional_default) optional else value_type;
    const span: source.Span = .{ .start = 0, .end = 1 };
    const locals = [_]typed.Local{
        .{ .name = "first", .declaration = span, .ty = owner_type, .mutable = false },
        .{ .name = "second", .declaration = span, .ty = value_type, .mutable = false },
    };
    var nodes = [_]typed.Node{
        .{ .span = span, .ty = owner_type, .data = .{ .local = @fromBackingInt(0) } },
        .{ .span = span, .ty = value_type, .data = .{ .local = @fromBackingInt(1) } },
        .{ .span = span, .ty = value_type, .data = .{ .borrow_selection = .{ .kind = kind, .first = @fromBackingInt(7), .second = @fromBackingInt(8) } } },
    };
    const selection = &nodes[2].data.borrow_selection;
    switch (damage) {
        .none => {},
        .first_before => selection.first = @fromBackingInt(6),
        .second_before => selection.second = @fromBackingInt(6),
        .first_self => selection.first = @fromBackingInt(9),
        .second_self => selection.second = @fromBackingInt(9),
        .first_after => selection.first = @fromBackingInt(10),
        .second_after => selection.second = @fromBackingInt(10),
        .scalar_first => nodes[0].ty = .i64,
        .wrong_second => nodes[1].ty = .bool,
        .wrong_result => nodes[2].ty = .bool,
    }
    const statements = [_]typed.Statement{.{ .span = span, .terminates = true, .data = .{ .ret = @fromBackingInt(9) } }};
    const body: StoredBody = .{
        .meta = .{
            .identity = .{ .key = selection_test_key, .context = @splat(0), .body = span, .region = span },
            .old_function_count = 1,
            .old_record_count = 2,
            .function_refs = &.{},
            .record_refs = &.{ .{ .index = 0, .key = "str" }, .{ .index = 1, .key = "Optional[str]" } },
        },
        .function = .{
            .id = @fromBackingInt(0),
            .name = "main",
            .declaration = span,
            .signature = .{ .parameter_count = 2, .return_type = value_type },
            .scope = .{ .body = @fromBackingInt(11), .locals = &locals },
        },
        .nodes = &nodes,
        .statements = &statements,
        .range = .{ .nodes = .{ .start = 7, .end = 10 }, .statements = .{ .start = 11, .end = 12 } },
        .source_bytes = .{ .old_len = 1, .body = "x", .region = "x" },
    };
    var payload = codec.Writer.init(allocator);
    defer payload.deinit();
    try payload.write(StoredBody, body);
    try std.testing.expect(try store.publishPayload(selection_test_key, @splat(0), payload.bytes.items));
}

// spec-case: SEMANTIC-CACHE-1
test "A08 selection durable operands validate range order and structural types" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, selection_test_key);
    defer store.deinit();
    for (std.meta.tags(SelectionKind)) |kind| {
        for (std.meta.tags(SelectionDamage)[1..]) |damage| {
            try selectionImage(t.allocator, &store, kind, damage, false);
            try t.expect((try store.lookup(t.allocator, selection_test_key, @splat(0))) == null);
        }
        try selectionImage(t.allocator, &store, kind, .none, false);
        var entry = (try store.lookup(t.allocator, selection_test_key, @splat(0))).?;
        defer entry.deinit();
        try t.expect(try store.put(&entry));
        @constCast(entry.nodes)[2].data.borrow_selection.second = @fromBackingInt(9);
        try t.expect(!try store.put(&entry));
    }
    try selectionImage(t.allocator, &store, .optional_default, .none, true);
    var scalar = (try store.lookup(t.allocator, selection_test_key, @splat(0))).?;
    defer scalar.deinit();
    try t.expectEqual(typed.Type.i64, scalar.nodes[2].ty);
}

// spec-case: SEMANTIC-CACHE-1
test "A08 selection rejects prior v8 wire with valid checksum" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, selection_test_key);
    defer store.deinit();
    try selectionImage(t.allocator, &store, .min_text, .none, false);
    const path = try store.entryPath(selection_test_key, @splat(0));
    defer t.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .limited(max_entry_bytes));
    defer t.allocator.free(bytes);
    const old = "semantic-cache-v8";
    try t.expectEqual(old.len, format_version.len);
    @memcpy(bytes[12..][0..old.len], old);
    std.mem.writeInt(u64, bytes[bytes.len - 8 ..][0..8], codec.checksum(bytes[0 .. bytes.len - 8]), .little);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
    try t.expect((try store.lookup(t.allocator, selection_test_key, @splat(0))) == null);
}

// spec-case: SEMANTIC-CACHE-1
test "A08 selection specialization publication and decoded operands fail closed" {
    const t = std.testing;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var store = Store.init(t.allocator, t.io, root, cache_key.Contract.default, selection_test_key);
    defer store.deinit();
    try selectionImage(t.allocator, &store, .optional_default, .none, false);
    var entry = (try store.lookup(t.allocator, selection_test_key, @splat(0))).?;
    defer entry.deinit();
    const key = "selection-specialization";
    var specialization: owned.SpecializationEntry = .{
        .arena = std.heap.ArenaAllocator.init(t.allocator),
        .payload = .{
            .identity = .{ .key = key, .context = @splat(0), .fingerprint = "fixture", .template = "Optional", .arguments = &.{}, .lengths = &.{} },
            .source = .{ .old_len = 1, .region = entry.meta.identity.region, .body = entry.meta.identity.body, .region_bytes = "x", .body_bytes = "x" },
            .body = .{ .function = entry.function, .nodes = entry.nodes, .statements = entry.statements, .range = entry.range },
            .refs = .{ .function_refs = &.{}, .record_refs = entry.meta.record_refs },
            .counts = .{ .old_function_count = 1, .old_record_count = 2 },
        },
    };
    defer specialization.deinit();
    try t.expect(try store.putSpecialization(&specialization));
    var restored = (try store.lookupSpecialization(t.allocator, key, @splat(0))).?;
    defer restored.deinit();
    @constCast(entry.nodes)[2].data.borrow_selection.first = @fromBackingInt(9);
    try t.expect(!try store.putSpecialization(&specialization));
    try t.expectEqual(@as(usize, 7), @backingInt(restored.payload.body.nodes[2].data.borrow_selection.first));
    var encoded = codec.Writer.init(t.allocator);
    defer encoded.deinit();
    try encoded.write(owned.StoredSpecialization, specialization.payload);
    try t.expect(try store.publishPayload(key, @splat(0), encoded.bytes.items));
    try t.expect((try store.lookupSpecialization(t.allocator, key, @splat(0))) == null);
}
