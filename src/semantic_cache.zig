//! Per-function successful checked-body snapshots. Global declaration, type,
//! effect and mutation validation always runs; only unchanged bodies are copied.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const key = @import("semantic_key.zig");
const copy = @import("semantic_copy.zig");
const owned = @import("semantic_entry.zig");
const interfaces = @import("interfaces.zig");
const cache_key = @import("cache_key.zig");
const semantic_store = @import("semantic_store.zig");
const generic_cache = @import("generic_cache.zig");
const generic_specializations = @import("generic_specializations.zig");

/// Re-exported so host wiring can bind the full contract without depending on
/// the compiler module's internal file layout.
pub const Contract = cache_key.Contract;
/// Durable store type and default root re-exported so host wiring shares the
/// compiler module's exact type instead of importing a duplicate file instance.
pub const Store = semantic_store.Store;
pub const default_store_directory = semantic_store.default_directory;
/// C3 symbolic-template reuse surface for host wiring and reports.
pub const symbolic = generic_cache;
/// C3 concrete-specialization reuse surface for host wiring and reports.
pub const specializations = generic_specializations;
/// Version of the M1/M2 mutation-contract encoding that semantic entries embed.
/// A change invalidates every retained body just like a changed effect contract.
pub const mutation_contract_version = "mutation-v1";

/// Observations count actual checked or copied bodies, including changed-source
/// requests. `checked` increments at the `checkFunction` execution site and
/// `reused` increments only when a stored body is actually copied. The
/// `work-report-v1` receipt reads these counters rather than inferring reuse from
/// equal digests.
pub const MissReason = enum {
    /// Reuse was never consulted because the cache holds no retention budget.
    cache_disabled,
    /// The request ordinal is not one of the prepared ordinary functions.
    not_ordinary,
    /// No retained entry has this stable declaration identity.
    no_entry,
    /// The resolved dependency digest changed.
    context_changed,
    /// The declaration region length changed.
    region_length_changed,
    /// The declaration region bytes changed.
    region_bytes_changed,
    /// A referenced function identity is absent from the fresh catalog.
    missing_function,
    /// A referenced function identity is ambiguous in the fresh catalog.
    ambiguous_function,
    /// A referenced record identity is absent from the fresh catalog.
    missing_record,
    /// A referenced record identity is ambiguous in the fresh catalog.
    ambiguous_record,
    /// Copying the retained tree failed a relocation check.
    relocation_failed,
    /// A referenced generic specialization would not exist without checking.
    generic_specialization,
    /// A referenced dynamically interned record cannot be remapped before checking.
    interned_record,
    /// A stored function value would require an interned callable contract.
    function_value,
    /// The retained tree was too large to keep.
    over_budget,
};
pub const miss_reason_count = std.meta.tags(MissReason).len;
pub const MissCounts = [miss_reason_count]usize;

/// Human-readable work-report reason tag for one conservative miss.
pub fn missReasonName(reason: MissReason) []const u8 {
    return switch (reason) {
        .cache_disabled => "cache-disabled",
        .not_ordinary => "not-ordinary-body",
        .no_entry => "no-retained-body",
        .context_changed => "dependencies-changed",
        .region_length_changed => "declaration-region-length-changed",
        .region_bytes_changed => "declaration-region-changed",
        .missing_function => "missing-function-identity",
        .ambiguous_function => "ambiguous-function-identity",
        .missing_record => "missing-record-identity",
        .ambiguous_record => "ambiguous-record-identity",
        .relocation_failed => "relocation-failed",
        .generic_specialization => "generic-specialization",
        .interned_record => "interned-record",
        .function_value => "function-value",
        .over_budget => "over-budget",
    };
}

/// Observations count actual checked or copied bodies, including changed-source
/// requests. `checked` increments at the `checkFunction` execution site and
/// `reused` increments only when a stored body is actually copied. The
/// `work-report-v1` receipt reads these counters rather than inferring reuse from
/// equal digests.
pub const Statistics = struct {
    reused: usize = 0,
    checked: usize = 0,
    stored: usize = 0,
    bypassed: usize = 0,
    /// Total owned in-memory retention bytes across ordinary bodies, symbolic
    /// templates and concrete specializations, including entry rows, arenas,
    /// keys and hash-index capacity. This is the field `check-session` reports
    /// as `functions.retained_bytes`.
    retained_bytes: usize = 0,
    /// Conservative per-reason miss counts for bodies that were not reused. These
    /// name an exact cause even when the body is checked fresh.
    misses: MissCounts = @splat(0),
    /// Per-kind breakdown and eviction count for the shared budget.
    retention: RetentionDetail = .{},
};

/// Per-kind retained storage and eviction detail exposed beside the existing
/// total so a report can attribute `retained_bytes` without guessing.
pub const RetentionDetail = struct {
    ordinary_bytes: usize = 0,
    symbolic_bytes: usize = 0,
    specialization_bytes: usize = 0,
    /// Entries released to hold the combined budget: ordinary bodies dropped
    /// from the retained prefix plus generic entries evicted oldest-first.
    evicted: usize = 0,
};

/// One host-bound semantic cache context. C2 persists this fingerprint so an
/// entry can never be admitted across an incompatible build or mutation contract.
pub const Context = struct {
    contract: []const u8 = "",
    mutation_contract: []const u8 = mutation_contract_version,
    /// Optional durable store attached to this cache session. It is part of the
    /// context so the public `Cache` shape does not grow another field solely for
    /// host wiring.
    persistent: ?*semantic_store.Store = null,
};

/// Retention budget and the symbolic-template table that shares it. Grouped
/// so the cache keeps one bounded retention policy rather than a second switch.
pub const Retention = struct {
    max_bytes: usize = 0,
    /// Process-local insertion order for generic entries. Both generic tables
    /// share it, so the combined budget evicts the globally oldest entry
    /// deterministically. Runtime-only and never persisted.
    sequence: u64 = 0,
    /// C3 symbolic-template results. It shares the same durable store and
    /// retention budget, but lives under its own entry kind and stable-key
    /// namespace so it can never collide with an ordinary checked body.
    symbolic: generic_cache.Table = .{},
    /// C3 concrete-specialization results. Same durable store and retention
    /// budget, under the `specialization-v1` kind and its own key namespace.
    specializations: generic_specializations.Table = .{},
};

/// Caller-serialized cache; returned typed trees never borrow retained storage.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    statistics: Statistics = .{},
    entries: []owned.Entry = &.{},
    /// Stable declaration identity -> retained entry ordinal.
    index: std.StringHashMapUnmanaged(usize) = .empty,
    /// Persistence-facing cache context: the Wave-3 contract fingerprint plus
    /// the M1/M2 mutation-contract version. A changed context forces a fresh
    /// check with no body reuse.
    context: Context = .{},
    /// Lexical module/import identities for the current project compilation.
    /// Single-unit callers leave this null and resolve against their one module.
    resolution: ?*interfaces.Index = null,
    /// Retention budget shared by ordinary checked bodies and C3 symbolic
    /// templates.
    reuse: Retention = .{},

    /// Zero retention bytes disables reuse without changing checking behavior.
    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) Cache {
        return .{ .allocator = allocator, .reuse = .{ .max_bytes = max_bytes } };
    }
    /// Create a cache bound to an explicit Wave-3 contract fingerprint.
    pub fn initWithContract(allocator: std.mem.Allocator, max_bytes: usize, contract: []const u8) Cache {
        return .{ .allocator = allocator, .reuse = .{ .max_bytes = max_bytes }, .context = .{ .contract = contract } };
    }
    /// Release every retained ordinary body, symbolic template and concrete
    /// specialization. Safe to call after `clear`.
    pub fn deinit(self: *Cache) void {
        self.clear();
    }
    /// Evict retained bodies of every kind; already-returned compilations remain
    /// valid because checked trees are copied out of cache-owned storage. Work
    /// counters stay cumulative, but retained-byte fields report the actual
    /// (now empty) storage rather than entries that no longer exist.
    pub fn clear(self: *Cache) void {
        for (self.entries) |*entry| entry.deinit();
        self.allocator.free(self.entries);
        self.entries = &.{};
        self.index.deinit(self.allocator);
        self.index = .empty;
        self.reuse.symbolic.clear();
        self.reuse.specializations.clear();
        self.statistics.retained_bytes = 0;
        self.statistics.retention.ordinary_bytes = 0;
        self.statistics.retention.symbolic_bytes = 0;
        self.statistics.retention.specialization_bytes = 0;
        // `retention.evicted` stays cumulative: clear is not a budget eviction.
    }
    /// Recompute the reported retained bytes from the three owned tables.
    pub fn recountRetention(self: *Cache) void {
        const ordinary = self.ordinaryRetainedBytes();
        const symbolic_bytes = self.reuse.symbolic.retainedBytes();
        const specialization_bytes = self.reuse.specializations.retainedBytes();
        self.statistics.retention.ordinary_bytes = ordinary;
        self.statistics.retention.symbolic_bytes = symbolic_bytes;
        self.statistics.retention.specialization_bytes = specialization_bytes;
        self.statistics.retained_bytes = ordinary + symbolic_bytes + specialization_bytes;
    }
    /// Owned bytes of the ordinary table: rows, arenas (metadata, dependency
    /// keys and source slices) and the stable-key hash index capacity.
    fn ordinaryRetainedBytes(self: *const Cache) usize {
        var bytes: usize = self.entries.len * @sizeOf(owned.Entry);
        for (self.entries) |entry| bytes += entry.arena.queryCapacity();
        bytes += owned.hashIndexBytes(self.index.capacity());
        return bytes;
    }
    /// Hold the combined ordinary + symbolic + specialization budget by
    /// releasing generic entries oldest-first. Ordinary bodies are already
    /// bounded by `remember` against the generic total, so this only needs to
    /// evict generic entries; it is also the universal convergence point called
    /// after every generic promotion or durable-hit promotion.
    fn enforceGenericRetention(self: *Cache) void {
        if (self.reuse.max_bytes == 0) return;
        while (self.ordinaryRetainedBytes() + self.reuse.symbolic.retainedBytes() + self.reuse.specializations.retainedBytes() > self.reuse.max_bytes) {
            const symbolic_age = self.reuse.symbolic.oldestSequence();
            const specialization_age = self.reuse.specializations.oldestSequence();
            if (symbolic_age == null and specialization_age == null) break;
            const evict_symbolic = if (symbolic_age) |symbolic_order| if (specialization_age) |specialization_order| symbolic_order <= specialization_order else true else false;
            const released = if (evict_symbolic) self.reuse.symbolic.evictOldest() else self.reuse.specializations.evictOldest();
            if (released == null) break;
            self.statistics.retention.evicted += 1;
        }
        self.recountRetention();
    }
    /// Open one symbolic-template request over the prepared declaration facts.
    /// `prepared` must outlive the returned session; `mode` distinguishes the
    /// project name-resolution mode from the single-unit lexical mode.
    pub fn symbolicSession(self: *Cache, src: source.Source, prepared: *const key.Prepared, mode: []const u8) error{OutOfMemory}!generic_cache.Session {
        return generic_cache.Session.init(self.allocator, src, prepared, .{
            .memory = &self.reuse.symbolic,
            .persistent = self.context.persistent,
            .enabled = self.reuse.max_bytes != 0,
            .mode = mode,
            .retention = .{ .owner = self, .reconcile = reconcileRetention },
            .sequence = &self.reuse.sequence,
        });
    }
    /// Open one concrete-specialization request over the prepared declaration
    /// facts. `prepared` must outlive the returned session.
    pub fn specializationSession(self: *Cache, prepared: *const key.Prepared) error{OutOfMemory}!generic_specializations.Session {
        return generic_specializations.Session.init(self.allocator, prepared, .{
            .memory = &self.reuse.specializations,
            .persistent = self.context.persistent,
            .enabled = self.reuse.max_bytes != 0,
            .build = self.context.contract,
            .retention = .{ .owner = self, .reconcile = reconcileRetention },
            .sequence = &self.reuse.sequence,
        });
    }
    /// Decode only entries whose stable key and dependency context are current.
    /// Any malformed file, missing identity or ambiguous remap is a miss; the
    /// decoder never enters this list unvalidated.
    fn loadPersistent(self: *Cache, persistent: *semantic_store.Store, prepared: key.Prepared) error{ OutOfMemory, InternalError }!void {
        if (self.reuse.max_bytes == 0) return;
        const generic_bytes = self.reuse.symbolic.retainedBytes() + self.reuse.specializations.retainedBytes();
        const ordinary_budget = self.reuse.max_bytes -| generic_bytes;
        var running: usize = 0;
        var loaded: std.ArrayList(owned.Entry) = .empty;
        var index: std.StringHashMapUnmanaged(usize) = .empty;
        // UNTESTED-ERROR: the cache's existing FailingAllocator scenario covers allocation failure at the checkWithCache boundary; this branch only releases entries already decoded by a partial load.
        errdefer {
            for (loaded.items) |*entry| entry.deinit();
            loaded.deinit(self.allocator);
            index.deinit(self.allocator);
        }
        for (prepared.ordinary_ast) |ast_index| {
            const stable_key = prepared.keys[ast_index];
            if (index.contains(stable_key)) continue;
            const entry = (try persistent.lookup(self.allocator, stable_key, prepared.contexts[ast_index])) orelse continue;
            // Durable entries are promoted into memory only while they fit the
            // ordinary share of the shared budget; the rest stay on disk and are
            // decoded on demand.
            const cost = owned.entryCost(entry);
            if (!fitsOrdinaryBudget(running, cost, loaded.items.len + 1, ordinary_budget)) {
                var dropped = entry;
                dropped.deinit();
                break;
            }
            // UNTESTED-ERROR: allocation failure while appending a completed decoded entry is covered by the cache-wide FailingAllocator scenario; this catch only releases that one entry.
            loaded.append(self.allocator, entry) catch |err| {
                var owned_entry = entry;
                owned_entry.deinit();
                return err;
            };
            // UNTESTED-ERROR: allocation failure while publishing the persistent index is covered by the cache-wide FailingAllocator scenario; this catch releases the just-appended entry.
            index.put(self.allocator, loaded.items[loaded.items.len - 1].meta.identity.key, loaded.items.len - 1) catch |err| {
                var owned_entry = loaded.items[loaded.items.len - 1];
                owned_entry.deinit();
                loaded.items.len -= 1;
                return err;
            };
            running += cost;
        }
        if (loaded.items.len == 0) return;
        self.entries = try loaded.toOwnedSlice(self.allocator);
        self.index = index;
    }

    /// Begin after fresh declaration/type collection, before checking any body.
    pub fn begin(self: *Cache, allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, records: []const typed.Record) error{ OutOfMemory, InternalError }!Session {
        const prepared = try key.prepare(allocator, src, syntax, self.context.contract, self.context.mutation_contract, self.resolution);
        if (self.context.persistent) |persistent| {
            if (self.entries.len == 0) try self.loadPersistent(persistent, prepared);
        }
        // Per-function eligibility: an unrelated generic, alias, constant or
        // callback no longer disables ordinary-body reuse. A zero-retention cache
        // still reports a bypass because reuse was never consulted.
        const enabled = self.reuse.max_bytes != 0 and self.entries.len != 0;
        if (self.reuse.max_bytes == 0) self.statistics.bypassed += 1;
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
            .remap = .{
                .functions = function_map,
                .records = record_map,
                .initial_record_count = records.len,
            },
        };
    }
};

/// Fresh-catalog remap tables for one request.
const Remap = struct {
    /// Stable function identity -> fresh ordinary instance ordinal.
    functions: std.StringHashMapUnmanaged(usize),
    /// Record name -> fresh catalog ordinal (ambiguous names are `maxInt`).
    records: std.StringHashMapUnmanaged(usize),
    /// Catalog records that existed before body checking. Records appended while
    /// checking (callable contracts, structural arrays) have no stable remap yet.
    initial_record_count: usize,
};

/// Per-function reuse state for one check request.
pub const Session = struct {
    cache: *Cache,
    src: source.Source,
    prepared: key.Prepared,
    ranges: []copy.Range,
    reuse: Reuse,
    /// Fresh-catalog remap tables for this request.
    remap: Remap,

    /// Copy one unchanged checked local tree, remapping declaration and catalog
    /// identities. Any missing or ambiguous remap is a miss.
    pub fn lookup(self: *Session, allocator: std.mem.Allocator, index: usize, nodes: *std.ArrayList(typed.Node), statements: *std.ArrayList(typed.Statement)) error{ OutOfMemory, InternalError }!?typed.Function {
        // A disabled cache or a first request with no retained snapshot is a
        // whole-cache bypass already counted by `begin`; do not manufacture a
        // per-body reason when reuse was never a candidate.
        if (!self.reuse.enabled) return null;
        if (index >= self.prepared.ordinary_ast.len) return self.reason(.not_ordinary);
        const ast_index = self.prepared.ordinary_ast[index];
        const entry_index = self.cache.index.get(self.prepared.keys[ast_index]) orelse return self.reason(.no_entry);
        const entry = &self.cache.entries[entry_index];
        if (!std.mem.eql(u8, &entry.meta.identity.context, &self.prepared.contexts[ast_index])) return self.reason(.context_changed);
        const before = entry.meta.identity.body;
        const after = self.prepared.bodies[ast_index];
        if (before.end - before.start != after.end - after.start) return self.reason(.region_length_changed);
        if (!std.mem.eql(u8, entry.source.body_bytes, self.src.bytes[after.start..after.end])) return self.reason(.region_bytes_changed);
        const old_region = entry.meta.identity.region;
        const new_region = self.prepared.regions[ast_index];
        if (old_region.end - old_region.start != new_region.end - new_region.start) return self.reason(.region_length_changed);
        if (!std.mem.eql(u8, entry.source.region_bytes, self.src.bytes[new_region.start..new_region.end])) return self.reason(.region_bytes_changed);

        // Resolve only the declarations this body actually references. A dense
        // old-ordinal-indexed array would allocate and initialize one slot per
        // program function for every reused body, which is quadratic across a
        // whole-project body set.
        const functions = try allocator.alloc(copy.FunctionRemap, entry.meta.function_refs.len);
        for (entry.meta.function_refs, functions) |reference, *out| {
            const fresh = self.remap.functions.get(reference.key) orelse return self.reason(.missing_function);
            if (fresh == std.math.maxInt(usize)) return self.reason(.ambiguous_function);
            out.* = .{ .old = @backingInt(reference.id), .fresh = @fromBackingInt(fresh) };
        }
        copy.sortFunctionRemaps(functions);
        const records = try allocator.alloc(copy.RecordRemap, entry.meta.record_refs.len);
        for (entry.meta.record_refs, records) |reference, *out| {
            const fresh = self.remap.records.get(reference.key) orelse return self.reason(.missing_record);
            if (fresh == std.math.maxInt(usize)) return self.reason(.ambiguous_record);
            out.* = .{ .old = reference.index, .fresh = @fromBackingInt(fresh + typed.Type.record_base) };
        }
        copy.sortRecordRemaps(records);
        var segment = [_]copy.Segment{.{ .before = old_region, .after = new_region.start }};
        const mapper: copy.Mapper = .{
            .segments = &segment,
            .before = entry.range,
            .after = .{
                .nodes = .{ .start = nodes.items.len, .end = nodes.items.len + entry.nodes.len },
                .statements = .{ .start = statements.items.len, .end = statements.items.len + entry.statements.len },
            },
            .function_remaps = functions,
            .record_remaps = records,
        };
        const function = mapper.copy(allocator, typed.Function, entry.function) catch |err| return self.relocationMiss(err);
        const copied_nodes = mapper.copy(allocator, []const typed.Node, entry.nodes) catch |err| return self.relocationMiss(err);
        const copied_statements = mapper.copy(allocator, []const typed.Statement, entry.statements) catch |err| return self.relocationMiss(err);
        try nodes.appendSlice(allocator, copied_nodes);
        try statements.appendSlice(allocator, copied_statements);
        self.reuse.functions[index] = true;
        self.cache.statistics.reused += 1;
        return function;
    }
    fn reason(self: *Session, why: MissReason) ?typed.Function {
        self.cache.statistics.misses[@backingInt(why)] += 1;
        return null;
    }
    fn relocationMiss(self: *Session, err: copy.Error) error{ OutOfMemory, InternalError }!?typed.Function {
        return switch (err) {
            error.InvalidRelocation => self.reason(.relocation_failed),
            error.OutOfMemory => error.OutOfMemory,
            error.InternalError => error.InternalError,
        };
    }
    /// Build one retained entry for a freshly checked body, or record the exact
    /// conservative miss and return null. Every temporary key slice is copied
    /// into the entry arena by `Entry.create`, so the temporaries can be freed
    /// before return.
    fn buildFreshEntry(self: *Session, program: typed.Program, i: usize, range: copy.Range) error{ OutOfMemory, InternalError }!?owned.Entry {
        const cache = self.cache;
        const ast_index = self.prepared.ordinary_ast[i];
        const stable_key = self.prepared.keys[ast_index];
        var refs = copy.RefSet.init(cache.allocator);
        defer refs.deinit();
        try copy.collectRefs(cache.allocator, program.functions[i], program.nodes[range.nodes.start..range.nodes.end], program.statements[range.statements.start..range.statements.end], &refs);
        // A body that references a concrete specialization cannot be reused
        // without re-instantiating it, so it stays on the fresh path with an
        // explicit reason until C3.
        const function_refs = try cache.allocator.alloc(owned.FunctionRef, refs.functions.count());
        defer cache.allocator.free(function_refs);
        var function_iterator = refs.functions.keyIterator();
        var function_count: usize = 0;
        var specialization = false;
        while (function_iterator.next()) |id| {
            if (id.* >= self.prepared.ordinary_ast.len) {
                specialization = true;
                break;
            }
            function_refs[function_count] = .{
                .id = @fromBackingInt(id.*),
                .key = self.prepared.keys[self.prepared.ordinary_ast[id.*]],
            };
            function_count += 1;
        }
        if (specialization) return self.freshMiss(.generic_specialization);
        // Every referenced aggregate must have a stable identity that exists
        // before checking. A declared callback, record or prelude type does;
        // a callable contract or structural array interned while checking does
        // not, so the body stays fresh with the exact reason.
        const record_refs = try cache.allocator.alloc(owned.RecordRef, refs.records.count());
        defer cache.allocator.free(record_refs);
        var record_iterator = refs.records.keyIterator();
        var record_count: usize = 0;
        var unstable: ?MissReason = null;
        while (record_iterator.next()) |index| {
            if (index.* >= program.records.len) {
                unstable = .missing_record;
                break;
            }
            if (index.* >= self.remap.initial_record_count) {
                const callable = declaredCallback(program.records, index.*);
                unstable = if (callable and (refs.function_values or refs.invokes)) .function_value else .interned_record;
                break;
            }
            const name = program.records[index.*].name;
            const fresh_index = self.remap.records.get(name) orelse {
                unstable = .missing_record;
                break;
            };
            if (fresh_index == std.math.maxInt(usize)) {
                unstable = .ambiguous_record;
                break;
            }
            record_refs[record_count] = .{ .index = index.*, .key = name };
            record_count += 1;
        }
        if (unstable) |why| return self.freshMiss(why);
        const spec: owned.Spec = .{
            .identity = .{
                .key = stable_key,
                .context = self.prepared.contexts[ast_index],
                .body = self.prepared.bodies[ast_index],
                .region = self.prepared.regions[ast_index],
                .checked_contract = key.contractDigest(program.functions[i]),
            },
            .function_refs = function_refs,
            .record_refs = record_refs,
        };
        const entry = try owned.Entry.create(cache.allocator, self.src.bytes, program, i, range, spec);
        return entry;
    }
    /// Count one body that cannot be retained, with the exact conservative reason.
    fn freshMiss(self: *Session, why: MissReason) ?owned.Entry {
        self.cache.statistics.misses[@backingInt(why)] += 1;
        return null;
    }

    /// Atomically retain changed bodies and transfer unchanged entries; OOM keeps the old cache.
    ///
    /// The in-memory budget is shared with the symbolic and concrete
    /// specialization tables, so this request keeps the longest leading prefix
    /// of stable ordinary bodies whose owned storage plus index overhead fits
    /// the share of the budget the generic tables leave. A body that does not
    /// fit is a fresh miss on its next request rather than a reason to disable
    /// reuse for every body.
    pub fn remember(self: *Session, program: typed.Program) error{ OutOfMemory, InternalError }!void {
        const cache = self.cache;
        if (cache.reuse.max_bytes == 0) return;
        const generic_bytes = cache.reuse.symbolic.retainedBytes() + cache.reuse.specializations.retainedBytes();
        const ordinary_budget = cache.reuse.max_bytes -| generic_bytes;
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
        var published = false;
        defer if (!published) {
            for (pending.items, 0..) |*entry, i| if (fresh.items[i]) entry.deinit();
        };
        var running: usize = 0;
        var budget_exhausted = false;
        var stopped_at: usize = ordinary_count;
        for (0..ordinary_count) |i| {
            const ast_index = self.prepared.ordinary_ast[i];
            const stable_key = self.prepared.keys[ast_index];
            if (self.reuse.functions[i]) if (cache.index.get(stable_key)) |old_index| if (!used[old_index]) {
                const cost = owned.entryCost(cache.entries[old_index]);
                if (!fitsOrdinaryBudget(running, cost, pending.items.len + 1, ordinary_budget)) {
                    budget_exhausted = true;
                    stopped_at = i;
                    break;
                }
                used[old_index] = true;
                try fresh.append(cache.allocator, false);
                var transferred = cache.entries[old_index];
                // Refresh the persisted checked contract from this request's
                // mandatory global passes so a reused body never carries an
                // obsolete inferred `mutates`/return-origin bound.
                transferred.meta.identity.checked_contract = key.contractDigest(program.functions[i]);
                pending.append(cache.allocator, transferred) catch |err| return err;
                try new_index.put(cache.allocator, pending.items[pending.items.len - 1].meta.identity.key, pending.items.len - 1);
                running += cost;
                continue;
            };
            const range = self.ranges[i];
            if (range.nodes.end > program.nodes.len or range.statements.end > program.statements.len) return error.InternalError;
            const entry = (try self.buildFreshEntry(program, i, range)) orelse continue;
            const cost = owned.entryCost(entry);
            if (!fitsOrdinaryBudget(running, cost, pending.items.len + 1, ordinary_budget)) {
                var dropped = entry;
                dropped.deinit();
                budget_exhausted = true;
                stopped_at = i;
                break;
            }
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
            running += cost;
        }
        if (budget_exhausted and pending.items.len == 0) {
            // Nothing from this request fits. Preserve the previous complete
            // snapshot only when it still fits this request's share of the
            // budget; otherwise release it so a generic promotion cannot push
            // the combined total over the advertised bound.
            const previous = owned.retained(cache.entries) + owned.hashIndexBytes(cache.index.capacity());
            if (previous <= ordinary_budget) {
                cache.statistics.bypassed += 1;
                return;
            }
            cache.statistics.retention.evicted += cache.entries.len;
        } else if (budget_exhausted) {
            // Previously retained bodies beyond the prefix are released by the
            // smaller ordinary share; count them so eviction is reported.
            for (stopped_at..ordinary_count) |i| {
                const ast_index = self.prepared.ordinary_ast[i];
                const stable_key = self.prepared.keys[ast_index];
                if (cache.index.contains(stable_key)) cache.statistics.retention.evicted += 1;
            }
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
        cache.statistics.stored += 1;
        published = true;
        cache.recountRetention();
        try persistFresh(cache, fresh.items);
    }
};

/// Publish only entries freshly created by this request. Already-retained
/// entries are either durable from an earlier process or intentionally bypassed
/// by the current in-memory budget, and re-serializing them would add work
/// without extending reuse.
///
/// All fresh bodies of one request go through one `Store` publication batch:
/// the store inventories the namespace once and then only converges on its
/// byte/entry bounds by bounded-slack reconciliation, so populating N bodies
/// costs O(N) filesystem inventory instead of O(N^2).
fn persistFresh(cache: *Cache, fresh: []const bool) error{OutOfMemory}!void {
    const persistent = cache.context.persistent orelse return;
    var any_fresh = false;
    for (fresh) |is_fresh| {
        if (is_fresh) {
            any_fresh = true;
            break;
        }
    }
    // A warm request publishes nothing; opening a batch would add a namespace
    // inventory to every read-only run without changing retention.
    if (!any_fresh) return;
    try persistent.beginBatch();
    defer {
        persistent.endBatch() catch |err| switch (err) {
            error.OutOfMemory => {},
        };
    }
    for (cache.entries, 0..) |*entry, i| {
        if (i >= fresh.len or !fresh[i]) continue;
        _ = try persistent.put(entry);
    }
    try persistent.endBatch();
}

/// Bind a generic session back to the cache that owns the shared budget. The
/// entry modules invoke this through `owned.RetentionHook`, so they never import
/// the cache module.
fn reconcileRetention(owner: ?*anyopaque) void {
    const cache: *Cache = @ptrCast(@alignCast(owner orelse return));
    cache.enforceGenericRetention();
}

/// Whether the next ordinary entry still fits `budget` once the body's own
/// storage and the index capacity the standard hash map allocates for that
/// entry count are both counted.
fn fitsOrdinaryBudget(running: usize, cost: usize, count: usize, budget: usize) bool {
    return running + cost + owned.indexBytesFor(count) <= budget;
}

const Reuse = struct {
    enabled: bool,
    functions: []bool,
};

/// Whether one referenced aggregate is a declared callable-typed slot. Declared
/// callbacks are interned before checking, so they have a stable remap; callable
/// contracts interned while checking are handled as `interned_record` misses.
fn declaredCallback(records: []const typed.Record, index: usize) bool {
    return index < records.len and records[index].contract.callback != null;
}
