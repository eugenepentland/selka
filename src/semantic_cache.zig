//! Bounded successful function-query snapshots; fresh whole-program passes stay mandatory.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const key = @import("semantic_key.zig");
const copy = @import("semantic_copy.zig");
const owned = @import("semantic_entry.zig");
/// Observations count actual checked or copied bodies, including changed-source requests.
pub const Statistics = struct { reused: usize = 0, checked: usize = 0, stored: usize = 0, bypassed: usize = 0, retained_bytes: usize = 0 };
/// Retention budget and the published dependency digest, bundled to keep the
/// cache object below Guardian's type-size cap.
pub const Gate = struct { max_bytes: usize, digest: ?[32]u8 = null };
/// Caller-serialized cache; returned typed trees never borrow retained storage.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    gate: Gate = .{ .max_bytes = 0 },
    statistics: Statistics = .{},
    entries: []owned.Entry = &.{},
    /// Ordered declaration identities/interfaces published with `entries`.
    keys: []?key.DeclarationKey = &.{},
    /// Resolved type catalog at publication time.
    catalog_digest: ?[32]u8 = null,
    /// Wave-3 contract fingerprint mixed into every prepared dependency digest.
    /// Empty preserves the historical behavior for callers that have not resolved
    /// a contract; a changed fingerprint forces a fresh check with no body reuse.
    contract: []const u8 = "",
    /// Zero retention bytes disables reuse without changing checking behavior.
    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) Cache {
        return .{ .allocator = allocator, .gate = .{ .max_bytes = max_bytes } };
    }
    /// Create a cache bound to an explicit Wave-3 contract fingerprint.
    pub fn initWithContract(allocator: std.mem.Allocator, max_bytes: usize, contract: []const u8) Cache {
        return .{ .allocator = allocator, .gate = .{ .max_bytes = max_bytes }, .contract = contract };
    }
    /// Release every retained tree and source generation.
    pub fn deinit(self: *Cache) void {
        self.clear();
    }
    /// Evict retained bodies; already-returned compilations remain valid.
    pub fn clear(self: *Cache) void {
        for (self.entries) |*entry| entry.deinit();
        self.allocator.free(self.entries);
        self.entries = &.{};
        self.freeKeys();
        self.gate.digest = null;
        self.catalog_digest = null;
        self.statistics.retained_bytes = 0;
    }
    /// Ordered dependency gate: contract digest, catalog digest, entry/keys
    /// lengths, then each declaration identity/interface slot.
    fn canReuse(self: *Cache, prepared: key.Prepared) bool {
        const catalog_digest = self.catalog_digest orelse return false;
        const digest = self.gate.digest orelse return false;
        if (!std.mem.eql(u8, &catalog_digest, &prepared.catalog_digest)) return false;
        if (!std.mem.eql(u8, &digest, &prepared.digest)) return false;
        if (self.entries.len != prepared.keys.len or self.keys.len != prepared.keys.len) return false;
        for (self.keys, prepared.keys) |old, wanted| {
            const old_key = old orelse return false;
            const wanted_key = wanted orelse return false;
            if (!std.mem.eql(u8, old_key.identity, wanted_key.identity)) return false;
            if (!optionalBytesEqual(old_key.interface_sha256, wanted_key.interface_sha256)) return false;
        }
        return true;
    }
    fn freeKeys(self: *Cache) void {
        for (self.keys) |slot| if (slot) |owned_key| {
            self.allocator.free(owned_key.identity);
            if (owned_key.interface_sha256) |interface| self.allocator.free(interface);
        };
        self.allocator.free(self.keys);
        self.keys = &.{};
    }
    /// Begin after fresh declaration/type collection, before checking any body.
    pub fn begin(
        self: *Cache,
        allocator: std.mem.Allocator,
        src: source.Source,
        syntax: ast.Program,
        records: []const typed.Record,
        keys: []const ?key.DeclarationKey,
    ) error{ OutOfMemory, InternalError }!Session {
        const prepared = try key.prepare(allocator, src, syntax, records, self.contract, keys);
        var reusable = false;
        if (prepared.enabled and self.gate.max_bytes != 0) {
            reusable = self.canReuse(prepared);
        } else self.statistics.bypassed += 1;
        const ranges = try allocator.alloc(copy.Range, syntax.functions.len);
        @memset(ranges, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
        const reused = try allocator.alloc(bool, syntax.functions.len);
        @memset(reused, false);
        return .{ .cache = self, .src = src, .prepared = prepared, .ranges = ranges, .reuse = .{ .enabled = reusable, .functions = reused } };
    }
};
const Reuse = struct {
    enabled: bool,
    functions: []bool,
};
/// Pending query observations publish only after complete global validation succeeds.
pub const Session = struct {
    cache: *Cache,
    src: source.Source,
    prepared: key.Prepared,
    ranges: []copy.Range,
    reuse: Reuse,
    /// Copy an unchanged checked local tree and relocate source/table identities.
    pub fn lookup(self: *Session, allocator: std.mem.Allocator, index: usize, nodes: *std.ArrayList(typed.Node), statements: *std.ArrayList(typed.Statement)) error{ OutOfMemory, InternalError }!?typed.Function {
        if (!self.reuse.enabled) return null;
        if (index >= self.prepared.keys.len or index >= self.prepared.declarations.len) return null;
        const wanted = self.prepared.keys[index] orelse return null;
        if (index >= self.cache.entries.len) return null;
        const entry = self.cache.entries[index];
        // The identity/interface gate is load-bearing even if the global gate was
        // bypassed by a test or an unusual caller.
        if (!std.mem.eql(u8, entry.identity, wanted.identity)) return null;
        if (!optionalBytesEqual(entry.interface_sha256, wanted.interface_sha256)) return null;
        const generation = entry.storage.generation;
        const before = entry.declaration;
        const after = self.prepared.declarations[index];
        if (before.start > before.end or before.end > generation.bytes.len) return null;
        if (after.start > after.end or after.end > self.src.bytes.len) return null;
        if (!std.mem.eql(u8, generation.bytes[before.start..before.end], self.src.bytes[after.start..after.end])) return null;
        const segments = [_]copy.Segment{.{ .before = before, .after = after.start }};
        const mapper: copy.Mapper = .{ .segments = &segments, .before = entry.storage.range, .after = .{
            .nodes = .{ .start = nodes.items.len, .end = 0 },
            .statements = .{ .start = statements.items.len, .end = 0 },
        } };
        const function = mapper.copy(allocator, typed.Function, entry.function) catch |err| return miss(err);
        const copied_nodes = mapper.copy(allocator, []const typed.Node, entry.nodes) catch |err| return miss(err);
        const copied_statements = mapper.copy(allocator, []const typed.Statement, entry.statements) catch |err| return miss(err);
        try nodes.appendSlice(allocator, copied_nodes);
        try statements.appendSlice(allocator, copied_statements);
        self.reuse.functions[index] = true;
        self.cache.statistics.reused += 1;
        return function;
    }
    fn miss(err: copy.Error) error{ OutOfMemory, InternalError }!?typed.Function {
        return switch (err) {
            error.InvalidRelocation => null,
            error.OutOfMemory => error.OutOfMemory,
            error.InternalError => error.InternalError,
        };
    }
    /// Atomically retain changed bodies and transfer unchanged entries; OOM keeps the old cache.
    pub fn remember(self: *Session, program: typed.Program) error{ OutOfMemory, InternalError }!void {
        const cache = self.cache;
        if (!self.prepared.enabled) return;
        if (cache.gate.max_bytes == 0) return;
        if (program.functions.len != self.ranges.len) return;
        if (self.prepared.keys.len != self.ranges.len) return;
        if (self.src.bytes.len > cache.gate.max_bytes) {
            cache.statistics.bypassed += 1;
            return;
        }
        const pending = try cache.allocator.alloc(owned.Entry, program.functions.len);
        var completed: usize = 0;
        var published = false;
        defer if (!published) {
            for (pending[0..completed], 0..) |*entry, i| if (!self.reuse.functions[i]) entry.deinit();
            cache.allocator.free(pending);
        };
        var generation: ?*owned.Generation = null;
        defer if (generation) |g| g.deinit();
        for (pending, 0..) |*entry, i| {
            if (self.reuse.functions[i]) {
                entry.* = cache.entries[i];
            } else {
                if (generation == null) generation = try owned.Generation.create(cache.allocator, self.src.bytes, self.prepared.bodies, self.prepared.declarations);
                const wanted = self.prepared.keys[i] orelse return error.InternalError;
                entry.* = try owned.Entry.create(cache.allocator, generation.?, program, i, self.ranges[i], .{ .identity = wanted.identity, .interface_sha256 = wanted.interface_sha256, .declaration = self.prepared.declarations[i] });
            }
            completed += 1;
        }
        const retained = owned.retained(pending);
        if (retained > cache.gate.max_bytes) {
            cache.statistics.bypassed += 1;
            return;
        }
        const new_keys = try cache.allocator.alloc(?key.DeclarationKey, self.prepared.keys.len);
        for (new_keys) |*slot| slot.* = null;
        var key_count: usize = 0;
        errdefer {
            for (new_keys[0..key_count]) |slot| if (slot) |owned_key| {
                cache.allocator.free(owned_key.identity);
                if (owned_key.interface_sha256) |interface| cache.allocator.free(interface);
            };
            cache.allocator.free(new_keys);
        }
        for (self.prepared.keys, 0..) |supplied, i| {
            if (supplied) |wanted| {
                const identity_copy = try cache.allocator.dupe(u8, wanted.identity);
                const interface_copy = if (wanted.interface_sha256) |interface| cache.allocator.dupe(u8, interface) catch |err| {
                    cache.allocator.free(identity_copy);
                    return err;
                } else null;
                new_keys[i] = .{ .identity = identity_copy, .interface_sha256 = interface_copy };
            }
            key_count = i + 1;
        }
        for (cache.entries, 0..) |*entry, i| if (!self.reuse.enabled or !self.reuse.functions[i]) entry.deinit();
        cache.allocator.free(cache.entries);
        cache.freeKeys();
        cache.entries = pending;
        cache.keys = new_keys;
        cache.gate.digest = self.prepared.digest;
        cache.catalog_digest = self.prepared.catalog_digest;
        cache.statistics.retained_bytes = retained;
        cache.statistics.stored += 1;
        published = true;
    }
};
fn optionalBytesEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}
