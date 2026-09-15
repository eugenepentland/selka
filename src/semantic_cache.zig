//! Bounded successful function-query snapshots; fresh whole-program passes stay mandatory.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const key = @import("semantic_key.zig");
const copy = @import("semantic_copy.zig");
const owned = @import("semantic_entry.zig");
/// Observations count actual checked or copied bodies, including changed-source
/// requests. `checked` increments at the `checkFunction` execution site and
/// `reused` increments only when a stored body is actually copied. The
/// `work-report-v1` receipt reads these counters rather than inferring reuse from
/// equal digests.
pub const Statistics = struct { reused: usize = 0, checked: usize = 0, stored: usize = 0, bypassed: usize = 0, retained_bytes: usize = 0 };
/// Caller-serialized cache; returned typed trees never borrow retained storage.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    max_bytes: usize,
    statistics: Statistics = .{},
    entries: []owned.Entry = &.{},
    digest: ?[32]u8 = null,
    /// Wave-3 contract fingerprint mixed into every prepared dependency digest.
    /// Empty preserves the historical behavior for callers that have not resolved
    /// a contract; a changed fingerprint forces a fresh check with no body reuse.
    contract: []const u8 = "",
    /// Zero retention bytes disables reuse without changing checking behavior.
    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) Cache {
        return .{ .allocator = allocator, .max_bytes = max_bytes };
    }
    /// Create a cache bound to an explicit Wave-3 contract fingerprint.
    pub fn initWithContract(allocator: std.mem.Allocator, max_bytes: usize, contract: []const u8) Cache {
        return .{ .allocator = allocator, .max_bytes = max_bytes, .contract = contract };
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
        self.digest = null;
        self.statistics.retained_bytes = 0;
    }
    /// Begin after fresh declaration/type collection, before checking any body.
    pub fn begin(self: *Cache, allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, records: []const typed.Record) error{ OutOfMemory, InternalError }!Session {
        const prepared = try key.prepare(allocator, src, syntax, records, self.contract);
        var reusable = false;
        if (prepared.enabled and self.max_bytes != 0) {
            if (self.digest) |digest| reusable = std.mem.eql(u8, &digest, &prepared.digest) and self.entries.len == prepared.bodies.len;
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
    relocations: std.AutoHashMapUnmanaged(*owned.Generation, []const copy.Segment) = .empty,
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
        const entry = self.cache.entries[index];
        const generation = entry.generation;
        const before = generation.bodies[index];
        const after = self.prepared.bodies[index];
        if (!std.mem.eql(u8, generation.bytes[before.start..before.end], self.src.bytes[after.start..after.end])) return null;
        const relocation = self.reuse.relocations.get(generation) orelse result: {
            const mapped = try copy.segments(allocator, generation.bytes, generation.bodies, self.src.bytes, self.prepared.bodies);
            try self.reuse.relocations.put(allocator, generation, mapped);
            break :result mapped;
        };
        const mapper: copy.Mapper = .{ .segments = relocation, .before = entry.range, .after = .{
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
        if (!self.prepared.enabled or cache.max_bytes == 0 or program.functions.len != self.ranges.len) return;
        if (self.src.bytes.len > cache.max_bytes) {
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
                if (generation == null) generation = try owned.Generation.create(cache.allocator, self.src.bytes, self.prepared.bodies);
                entry.* = try owned.Entry.create(cache.allocator, generation.?, program, i, self.ranges[i]);
            }
            completed += 1;
        }
        const retained = owned.retained(pending);
        if (retained > cache.max_bytes) {
            cache.statistics.bypassed += 1;
            return;
        }
        for (cache.entries, 0..) |*entry, i| if (!self.reuse.enabled or !self.reuse.functions[i]) entry.deinit();
        cache.allocator.free(cache.entries);
        cache.entries = pending;
        cache.digest = self.prepared.digest;
        cache.statistics.retained_bytes = retained;
        cache.statistics.stored += 1;
        published = true;
    }
};
