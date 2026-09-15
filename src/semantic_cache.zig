//! Per-function successful checked-body snapshots. Global declaration, type,
//! effect and mutation validation always runs; only unchanged bodies are copied.
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
    /// Stable declaration identity -> retained entry ordinal.
    index: std.StringHashMapUnmanaged(usize) = .empty,
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
        self.index.deinit(self.allocator);
        self.index = .empty;
        self.statistics.retained_bytes = 0;
    }
    /// Begin after fresh declaration/type collection, before checking any body.
    pub fn begin(self: *Cache, allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, records: []const typed.Record) error{ OutOfMemory, InternalError }!Session {
        const prepared = try key.prepare(allocator, src, syntax, records, self.contract);
        // Per-function eligibility: an unrelated generic, alias, constant or
        // callback no longer disables ordinary-body reuse. A zero-retention cache
        // still reports a bypass because reuse was never consulted.
        const enabled = self.max_bytes != 0 and self.entries.len != 0;
        if (self.max_bytes == 0) self.statistics.bypassed += 1;
        const count = prepared.ordinary_ast.len;
        const ranges = try allocator.alloc(copy.Range, count);
        @memset(ranges, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
        const reused = try allocator.alloc(bool, count);
        @memset(reused, false);
        var function_map: std.StringHashMapUnmanaged(usize) = .empty;
        for (prepared.ordinary_ast, 0..) |ast_index, instance| {
            const entry = try function_map.getOrPut(allocator, prepared.keys[ast_index]);
            if (entry.found_existing) entry.value_ptr.* = std.math.maxInt(usize) else entry.value_ptr.* = instance;
        }
        var record_map: std.StringHashMapUnmanaged(usize) = .empty;
        for (records, 0..) |record, index| {
            const entry = try record_map.getOrPut(allocator, record.name);
            if (entry.found_existing) entry.value_ptr.* = std.math.maxInt(usize) else entry.value_ptr.* = index;
        }
        return .{
            .cache = self,
            .src = src,
            .prepared = prepared,
            .ranges = ranges,
            .reuse = .{ .enabled = enabled, .functions = reused },
            .function_map = function_map,
            .record_map = record_map,
        };
    }
};

/// Per-function reuse state for one check request.
pub const Session = struct {
    cache: *Cache,
    src: source.Source,
    prepared: key.Prepared,
    ranges: []copy.Range,
    reuse: Reuse,
    /// Stable function identity -> fresh ordinary instance ordinal.
    function_map: std.StringHashMapUnmanaged(usize),
    /// Record name -> fresh catalog ordinal (ambiguous names are `maxInt`).
    record_map: std.StringHashMapUnmanaged(usize),

    /// Copy one unchanged checked local tree, remapping declaration and catalog
    /// identities. Any missing or ambiguous remap is a miss.
    pub fn lookup(self: *Session, allocator: std.mem.Allocator, index: usize, nodes: *std.ArrayList(typed.Node), statements: *std.ArrayList(typed.Statement)) error{ OutOfMemory, InternalError }!?typed.Function {
        if (!self.reuse.enabled) return null;
        if (index >= self.prepared.ordinary_ast.len) return null;
        const ast_index = self.prepared.ordinary_ast[index];
        const entry_index = self.cache.index.get(self.prepared.keys[ast_index]) orelse return null;
        const entry = &self.cache.entries[entry_index];
        if (!std.mem.eql(u8, &entry.meta.identity.context, &self.prepared.contexts[ast_index])) return null;
        const before = entry.meta.identity.body;
        const after = self.prepared.bodies[ast_index];
        if (before.end - before.start != after.end - after.start) return null;
        if (!std.mem.eql(u8, entry.generation.bytes[before.start..before.end], self.src.bytes[after.start..after.end])) return null;
        const old_region = entry.meta.identity.region;
        const new_region = self.prepared.regions[ast_index];
        if (old_region.end - old_region.start != new_region.end - new_region.start) return null;
        if (!std.mem.eql(u8, entry.generation.bytes[old_region.start..old_region.end], self.src.bytes[new_region.start..new_region.end])) return null;

        const functions = try allocator.alloc(?typed.FunctionId, entry.meta.old_function_count);
        @memset(functions, null);
        for (entry.meta.function_refs) |reference| {
            const fresh = self.function_map.get(reference.key) orelse return null;
            if (fresh == std.math.maxInt(usize)) return null;
            functions[@backingInt(reference.id)] = @fromBackingInt(fresh);
        }
        const records = try allocator.alloc(?typed.Type, entry.meta.old_record_count);
        @memset(records, null);
        for (entry.meta.record_refs) |reference| {
            const fresh = self.record_map.get(reference.key) orelse return null;
            if (fresh == std.math.maxInt(usize)) return null;
            records[reference.index] = @fromBackingInt(fresh + typed.Type.record_base);
        }
        var segment = [_]copy.Segment{.{ .before = old_region, .after = new_region.start }};
        const mapper: copy.Mapper = .{
            .segments = &segment,
            .before = entry.range,
            .after = .{
                .nodes = .{ .start = nodes.items.len, .end = nodes.items.len + entry.nodes.len },
                .statements = .{ .start = statements.items.len, .end = statements.items.len + entry.statements.len },
            },
            .functions = functions,
            .records = records,
        };
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
        if (cache.max_bytes == 0) return;
        if (self.src.bytes.len > cache.max_bytes) {
            cache.statistics.bypassed += 1;
            return;
        }
        const ordinary_count = self.prepared.ordinary_ast.len;
        if (program.functions.len < ordinary_count) return;
        var pending: std.ArrayList(owned.Entry) = .empty;
        defer pending.deinit(cache.allocator);
        var new_index: std.StringHashMapUnmanaged(usize) = .empty;
        defer new_index.deinit(cache.allocator);
        var fresh: std.ArrayList(bool) = .empty;
        defer fresh.deinit(cache.allocator);
        const used = try cache.allocator.alloc(bool, cache.entries.len);
        defer cache.allocator.free(used);
        @memset(used, false);
        var generation: ?*owned.Generation = null;
        defer if (generation) |value| value.deinit();
        var published = false;
        defer if (!published) {
            for (pending.items, 0..) |*entry, i| if (fresh.items[i]) entry.deinit();
        };
        for (0..ordinary_count) |i| {
            const ast_index = self.prepared.ordinary_ast[i];
            const stable_key = self.prepared.keys[ast_index];
            if (self.reuse.functions[i]) if (cache.index.get(stable_key)) |old_index| if (!used[old_index]) {
                used[old_index] = true;
                try fresh.append(cache.allocator, false);
                pending.append(cache.allocator, cache.entries[old_index]) catch |err| return err;
                try new_index.put(cache.allocator, pending.items[pending.items.len - 1].meta.identity.key, pending.items.len - 1);
                continue;
            };
            const range = self.ranges[i];
            if (range.nodes.end > program.nodes.len or range.statements.end > program.statements.len) return error.InternalError;
            var refs = copy.RefSet.init(cache.allocator);
            defer refs.deinit();
            try copy.collectRefs(cache.allocator, program.functions[i], program.nodes[range.nodes.start..range.nodes.end], program.statements[range.statements.start..range.statements.end], &refs);
            if (refs.callbacks or callbackTyped(program.functions[i], program.records)) continue;
            var unstable = false;
            var function_iterator = refs.functions.keyIterator();
            while (function_iterator.next()) |id| if (id.* >= ordinary_count) {
                unstable = true;
                break;
            };
            if (unstable) continue;
            const function_refs = try cache.allocator.alloc(owned.FunctionRef, refs.functions.count());
            defer cache.allocator.free(function_refs);
            var function_count: usize = 0;
            function_iterator = refs.functions.keyIterator();
            while (function_iterator.next()) |id| {
                function_refs[function_count] = .{
                    .id = @fromBackingInt(id.*),
                    .key = self.prepared.keys[self.prepared.ordinary_ast[id.*]],
                };
                function_count += 1;
            }
            const record_refs = try cache.allocator.alloc(owned.RecordRef, refs.records.count());
            defer cache.allocator.free(record_refs);
            var record_count: usize = 0;
            var record_iterator = refs.records.keyIterator();
            while (record_iterator.next()) |index| {
                if (index.* >= program.records.len) {
                    unstable = true;
                    break;
                }
                record_refs[record_count] = .{ .index = index.*, .key = program.records[index.*].name };
                record_count += 1;
            }
            if (unstable) continue;
            if (generation == null) generation = try owned.Generation.create(cache.allocator, self.src.bytes, self.prepared.bodies);
            const spec: owned.Spec = .{
                .identity = .{
                    .key = stable_key,
                    .context = self.prepared.contexts[ast_index],
                    .body = self.prepared.bodies[ast_index],
                    .region = self.prepared.regions[ast_index],
                },
                .function_refs = function_refs,
                .record_refs = record_refs,
            };
            const entry = try owned.Entry.create(cache.allocator, generation.?, program, i, range, spec);
            fresh.append(cache.allocator, true) catch |err| {
                var owned_entry = entry;
                owned_entry.deinit();
                return err;
            };
            pending.append(cache.allocator, entry) catch |err| {
                var owned_entry = entry;
                owned_entry.deinit();
                return err;
            };
            try new_index.put(cache.allocator, entry.meta.identity.key, pending.items.len - 1);
        }
        const retained = owned.retained(pending.items);
        if (retained > cache.max_bytes) {
            cache.statistics.bypassed += 1;
            return;
        }
        // Complete the one fallible publication step before touching live cache
        // state so an OOM leaves the previous complete snapshot intact.
        const new_entries = try pending.toOwnedSlice(cache.allocator);
        for (cache.entries, 0..) |*entry, i| if (!used[i]) entry.deinit();
        cache.allocator.free(cache.entries);
        cache.index.deinit(cache.allocator);
        cache.entries = new_entries;
        cache.index = new_index;
        new_index = .empty;
        cache.statistics.retained_bytes = retained;
        cache.statistics.stored += 1;
        published = true;
    }
};

const Reuse = struct {
    enabled: bool,
    functions: []bool,
};

/// C1 keeps callable values and callback-typed slots on the fresh path because
/// their inferred effect/mutation contract is not yet a stable dependency fact.
fn callbackTyped(function: typed.Function, records: []const typed.Record) bool {
    if (function.signature.return_type.isAggregate()) {
        const index = function.signature.return_type.recordIndex();
        if (index < records.len and records[index].contract.callback != null) return true;
    }
    for (function.type_arguments) |ty| if (ty.isAggregate()) {
        const index = ty.recordIndex();
        if (index < records.len and records[index].contract.callback != null) return true;
    };
    for (function.scope.locals) |local| if (local.ty.isAggregate()) {
        const index = local.ty.recordIndex();
        if (index < records.len and records[index].contract.callback != null) return true;
    };
    return false;
}
