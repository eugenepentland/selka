//! Per-function successful checked-body snapshots. Global declaration, type,
//! effect and mutation validation always runs; only unchanged bodies are copied.
const std = @import("std");
const frontend = @import("frontend_runtime.zig");
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
const timings = @import("timings.zig");
const summary = @import("semantic_summary.zig");
const sources = @import("semantic_sources.zig");

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
pub const mutation_contract_version = "mutation-v2";

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
    /// A record the retained tree touched has a different transitive shape.
    record_shape_changed,
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
        .record_shape_changed => "record-shape-changed",
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
    /// templates and concrete specializations: entry rows, arena backing
    /// allocations including per-chunk bookkeeping, keys, and the exact
    /// hash-index backing allocation including the stdlib minimum/header/
    /// alignment. This is the field `check-session` reports as
    /// `functions.retained_bytes`.
    retained_bytes: usize = 0,
    /// Lookup rejection and retention eligibility are distinct observations.
    rejections: MissDetail = .{},
    /// Per-kind breakdown and eviction count for the shared budget.
    retention: RetentionDetail = .{},
};

/// Conservative reasons split by lookup and retention, with a legacy total.
pub const MissDetail = struct {
    total: MissCounts = @splat(0),
    lookup: MissCounts = @splat(0),
    retention: MissCounts = @splat(0),
    /// First rejected identity by semantic_copy.Failure tag (none is slot zero).
    relocation: [copy.failure_count]usize = @splat(0),
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
    /// Opt-in phase recorder. Kept in the context so the public cache shape does
    /// not grow another field solely for instrumentation.
    timing: ?*timings.Profile = null,
    /// Per-function check summaries for a `check` that needs no checked trees:
    /// unchanged bodies are stood in by their stored summaries instead of being
    /// checked or copied, and the check's own summaries come back here. Such a
    /// request never hydrates retained checked trees unless the host explicitly
    /// enables complete-tree reuse for a lowering request below.
    summaries: ?*summary.Request = null,
    /// Complete typed-tree reuse alongside facts-only summaries is opt-in.
    /// Legacy native-test facts keep their existing check/retention policy.
    retain_summary_trees: bool = false,
    boundary: Boundary = .{},
};

const Boundary = struct {
    verified: frontend.Verified = .{},
    base: []const u8 = "",
    owned: ?[]const u8 = null,
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
    /// budget, under the `specialization-v2` kind and its own key namespace.
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
        if (self.context.boundary.owned) |contract_bytes| self.allocator.free(contract_bytes);
    }
    /// Partition every semantic key and evict retained bodies when the verified producer changes.
    pub fn setFrontend(self: *Cache, verified: frontend.Verified) error{OutOfMemory}!void {
        const previous = self.context.boundary;
        if (std.mem.eql(u8, &previous.verified.identity, &verified.identity) and previous.verified.reuse == verified.reuse) return;
        const base = if (previous.owned != null) previous.base else self.context.contract;
        const combined = try std.fmt.allocPrint(self.allocator, "{s}/frontend/{s}", .{ base, std.fmt.bytesToHex(verified.identity, .lower) });
        self.clear();
        if (previous.owned) |contract_bytes| self.allocator.free(contract_bytes);
        self.context.boundary = .{ .verified = verified, .base = base, .owned = combined };
        self.context.contract = combined;
        if (!verified.reuse) self.context.summaries = null;
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
    /// Owned bytes of the ordinary table: entry rows, entry arenas (metadata,
    /// dependency keys and source slices) including their chunk bookkeeping, and
    /// the exact stable-key hash-index backing allocation.
    fn ordinaryRetainedBytes(self: *const Cache) usize {
        var bytes: usize = self.entries.len * @sizeOf(owned.Entry);
        for (self.entries) |entry| bytes += owned.arenaOwnedBytes(entry.arena);
        bytes += owned.hashIndexBytes(self.index.capacity());
        return bytes;
    }
    /// Hold the combined ordinary + symbolic + specialization budget by
    /// releasing generic entries oldest-first. Ordinary bodies are already
    /// bounded by `remember` against the generic total using the same exact
    /// owned-byte model, so this only needs to evict generic entries; it is also
    /// the universal convergence point called after every generic promotion or
    /// durable-hit promotion.
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
            .persistent = if (self.context.boundary.verified.reuse) self.context.persistent else null,
            .enabled = self.reuse.max_bytes != 0 and self.context.boundary.verified.reuse,
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
            .persistent = if (self.context.boundary.verified.reuse) self.context.persistent else null,
            .enabled = self.reuse.max_bytes != 0 and self.context.boundary.verified.reuse,
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
            // Durable entries are promoted into memory only while their exact
            // owned row, arena backing and index share fit the ordinary share of
            // the shared budget; the rest stay on disk and are decoded on demand.
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
        const profile = if (self.context.timing) |p| if (p.enabled) p else null else null;
        const prepare_start = if (profile) |p| p.now() else std.Io.Timestamp.zero;
        const recall = if (self.context.summaries) |request| if (request.previous) |previous| summary.recall(previous) else null else null;
        const prepared = try key.prepare(allocator, src, syntax, .{ .build = self.context.contract, .mutation = self.context.mutation_contract }, self.resolution, recall);
        if (profile) |p| p.addSince("dependency_key_preparation", prepare_start, false);
        const needs_trees = if (self.context.summaries) |request|
            request.body_policy == .concrete and self.context.retain_summary_trees
        else
            true;
        // Demand requests decode only bodies their host cannot replace, after
        // summary planning; Session.lookup retains the ordinary lazy miss path.
        const lazy_trees = if (self.context.summaries) |request| request.policy.demand != null else false;
        if (if (self.context.boundary.verified.reuse) self.context.persistent else null) |persistent| {
            if (self.entries.len == 0 and needs_trees and !lazy_trees) {
                const io_start = if (profile) |p| p.now() else std.Io.Timestamp.zero;
                try self.loadPersistent(persistent, prepared);
                if (profile) |p| p.addSince("retention_store_io", io_start, false);
            }
        }
        // Per-function eligibility: an unrelated generic, alias, constant or
        // callback no longer disables ordinary-body reuse. A zero-retention cache
        // still reports a bypass because reuse was never consulted.
        const enabled = self.context.boundary.verified.reuse and self.reuse.max_bytes != 0 and
            (self.entries.len != 0 or (needs_trees and self.context.persistent != null));
        if (self.reuse.max_bytes == 0) self.statistics.bypassed += 1;
        const count = prepared.ordinary_ast.len;
        const ranges = try allocator.alloc(copy.Range, count);
        @memset(ranges, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
        const reused = try allocator.alloc(bool, count);
        @memset(reused, false);
        const stood_in = try allocator.alloc(bool, count);
        @memset(stood_in, false);
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
            .reuse = .{ .enabled = enabled, .functions = reused, .stood_in = stood_in },
            .remap = .{
                .functions = function_map,
                .records = record_map,
                .initial_record_count = records.len,
                .sources = try sources.Catalog.init(allocator, src),
                .shapes = .{ .allocator = allocator, .records = try allocator.dupe(typed.Record, records) },
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
    /// Transitive shape digests of the fresh catalog's records.
    shapes: key.Shapes,
    sources: sources.Catalog,
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
        // Do not manufacture per-body misses when retention is disabled or
        // neither retained entries nor an eligible durable store is available.
        if (!self.reuse.enabled) return null;
        if (index >= self.prepared.ordinary_ast.len) return self.reason(.not_ordinary);
        const ast_index = self.prepared.ordinary_ast[index];
        if (self.cache.index.get(self.prepared.keys[ast_index])) |entry_index| {
            return self.copyEntry(allocator, index, &self.cache.entries[entry_index], nodes, statements);
        }
        const persistent = self.cache.context.persistent orelse return self.reason(.no_entry);
        var entry = (try persistent.lookup(self.cache.allocator, self.prepared.keys[ast_index], self.prepared.contexts[ast_index])) orelse return self.reason(.no_entry);
        defer entry.deinit();
        // Restore only this body's independently owned tree. It need not fit
        // the retention budget, and no decoded storage survives the copy.
        return self.copyEntry(allocator, index, &entry, nodes, statements);
    }

    fn copyEntry(self: *Session, allocator: std.mem.Allocator, index: usize, entry: *const owned.Entry, nodes: *std.ArrayList(typed.Node), statements: *std.ArrayList(typed.Statement)) error{ OutOfMemory, InternalError }!?typed.Function {
        const ast_index = self.prepared.ordinary_ast[index];
        if (!owned.validTypeRecipes(entry.meta, semantic_store.max_declarations)) return self.reason(.relocation_failed);
        // Cheap rejections first. The dependency digest is a 32-byte compare that
        // also carries the mutation and effect contract, and both stored lengths
        // are integer compares; only a request that survives all three touches
        // the source bytes.
        if (!std.mem.eql(u8, &entry.meta.identity.context, &self.prepared.contexts[ast_index])) return self.reason(.context_changed);
        const before = entry.meta.identity.body;
        const after = self.prepared.bodies[ast_index];
        const old_region = entry.meta.identity.region;
        const new_region = self.prepared.regions[ast_index];
        if (before.end - before.start != after.end - after.start) return self.reason(.region_length_changed);
        if (old_region.end - old_region.start != new_region.end - new_region.start) return self.reason(.region_length_changed);
        // No stored digest covers the body bytes, so this byte comparison stays
        // the authority and a same-length body edit still misses here. It is also
        // the only source pass: the stored region encloses the stored body as its
        // trailing slice, so one comparison over the union decides both ranges
        // instead of walking the body's bytes again. An entry whose stored shape
        // does not give that guarantee keeps its own body comparison.
        const suffix = bodyIsRegionSuffix(entry.meta.identity, new_region, after);
        if (!std.mem.eql(u8, entry.source.region_bytes, self.src.bytes[new_region.start..new_region.end])) return self.reason(.region_bytes_changed);
        if (!suffix and !std.mem.eql(u8, entry.source.body_bytes, self.src.bytes[after.start..after.end])) return self.reason(.region_bytes_changed);

        // Resolve only the declarations this body actually references. A dense
        // old-ordinal-indexed array would allocate and initialize one slot per
        // program function for every reused body, which is quadratic across a
        // whole-project body set.
        const functions = try allocator.alloc(copy.FunctionRemap, entry.meta.function_refs.len);
        for (entry.meta.function_refs, functions) |reference, *out| {
            const fresh = if (reference.template != null)
                @backingInt((try self.resolveSpecialization(reference)) orelse return self.reason(.missing_function))
            else
                self.remap.functions.get(reference.key) orelse return self.reason(.missing_function);
            if (fresh == std.math.maxInt(usize)) return self.reason(.ambiguous_function);
            out.* = .{ .old = @backingInt(reference.id), .fresh = @fromBackingInt(fresh) };
        }
        copy.sortFunctionRemaps(functions);
        const records = try allocator.alloc(copy.RecordRemap, entry.meta.record_refs.len);
        for (entry.meta.record_refs, records, 0..) |reference, *out, position| {
            if (reference.recipes.len != 0) {
                const recipe = reference.recipes[0];
                const resolver = self.reuse.resolver orelse return self.reason(.interned_record);
                const resolve_type = resolver.resolve_type orelse return self.reason(.interned_record);
                const fresh_type = (try resolve_type(resolver.context, recipe, old_region, new_region, records[0..position])) orelse return self.reason(.interned_record);
                const type_shape = resolver.type_shape orelse return self.reason(.missing_record);
                const shape = (try type_shape(resolver.context, fresh_type)) orelse return self.reason(.missing_record);
                if (!std.mem.eql(u8, &shape, &reference.shape)) return self.reason(.record_shape_changed);
                out.* = .{ .old = reference.index, .fresh = fresh_type };
                continue;
            }
            var fresh = self.remap.records.get(reference.key) orelse {
                const resolver = self.reuse.resolver orelse return self.reason(.missing_record);
                const resolve_record = resolver.resolve_record orelse return self.reason(.missing_record);
                const ty = (try resolve_record(resolver.context, reference.key, reference.shape)) orelse return self.reason(.missing_record);
                out.* = .{ .old = reference.index, .fresh = ty };
                continue;
            };
            if (fresh == std.math.maxInt(usize)) fresh = (try uniqueRecordShape(&self.remap.shapes, reference.key, reference.shape)) orelse return self.reason(.ambiguous_record);
            const shape = (try self.remap.shapes.digest(fresh)) orelse return self.reason(.missing_record);
            if (!std.mem.eql(u8, &shape, &reference.shape)) return self.reason(.record_shape_changed);
            out.* = .{ .old = reference.index, .fresh = @fromBackingInt(fresh + typed.Type.record_base) };
        }
        copy.sortRecordRemaps(records);
        var proven_region = old_region;
        const trailing = entry.source.trailing_bytes;
        if (trailing.len <= self.src.bytes.len - new_region.end and std.mem.eql(u8, trailing, self.src.bytes[new_region.end..][0..trailing.len])) {
            proven_region.end += trailing.len;
        }
        const segments = try self.remap.sources.segments(allocator, entry.source.modules, .{ .before = proven_region, .after = new_region.start });
        const mapper: copy.Mapper = .{
            .segments = segments,
            .before = entry.range,
            .after = .{
                .nodes = .{ .start = nodes.items.len, .end = nodes.items.len + entry.nodes.len },
                .statements = .{ .start = statements.items.len, .end = statements.items.len + entry.statements.len },
            },
            .function_remaps = functions,
            .record_remaps = records,
        };
        var failure: copy.Failure = .none;
        try nodes.ensureUnusedCapacity(allocator, entry.nodes.len);
        try statements.ensureUnusedCapacity(allocator, entry.statements.len);
        const function = mapper.copyWithFailure(allocator, typed.Function, entry.function, &failure) catch |err| {
            return self.relocationMiss(err, failure);
        };
        mapper.copySliceInto(allocator, typed.Node, entry.nodes, nodes.unusedCapacitySlice()[0..entry.nodes.len], &failure) catch |err| {
            return self.relocationMiss(err, failure);
        };
        mapper.copySliceInto(allocator, typed.Statement, entry.statements, statements.unusedCapacitySlice()[0..entry.statements.len], &failure) catch |err| {
            return self.relocationMiss(err, failure);
        };
        nodes.items.len += entry.nodes.len;
        statements.items.len += entry.statements.len;
        self.reuse.functions[index] = true;
        self.cache.statistics.reused += 1;
        return function;
    }
    fn resolveSpecialization(self: *Session, reference: owned.FunctionRef) error{ OutOfMemory, InternalError }!?typed.FunctionId {
        const resolver = self.reuse.resolver orelse return null;
        return resolver.resolve(resolver.context, reference);
    }
    /// A summary identity names nominal records directly. Callable spellings
    /// omit return origins, so include their exact schema to distinguish them.
    pub fn recordIdentity(self: *Session, allocator: std.mem.Allocator, index: usize) error{OutOfMemory}!?[]const u8 {
        if (index >= self.remap.shapes.records.len) return null;
        const record = self.remap.shapes.records[index];
        if (record.contract.callback == null) return record.name;
        const digest = (try self.remap.shapes.digest(index)) orelse return null;
        const named = self.remap.records.get(record.name) orelse return null;
        if (named == std.math.maxInt(usize) and (try uniqueRecordShape(&self.remap.shapes, record.name, digest)) == null) return null;
        const hex = std.fmt.bytesToHex(digest, .lower);
        const identity = try std.fmt.allocPrint(allocator, "{s}\x00{s}", .{ record.name, hex });
        return identity;
    }
    /// Resolve a stored nominal name or callable name plus exact schema.
    /// Old name-only summaries remain conservative for ambiguous spellings.
    pub fn shapeOf(self: *Session, identity: []const u8) error{OutOfMemory}!?[32]u8 {
        if (std.mem.indexOfScalar(u8, identity, 0)) |separator| {
            const hex = identity[separator + 1 ..];
            if (hex.len != 64) return null;
            var expected: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&expected, hex) catch return null;
            const name = identity[0..separator];
            var index = self.remap.records.get(name) orelse return null;
            if (index == std.math.maxInt(usize)) index = (try uniqueRecordShape(&self.remap.shapes, name, expected)) orelse return null;
            if (self.remap.shapes.records[index].contract.callback == null) return null;
            const digest = (try self.remap.shapes.digest(index)) orelse return null;
            if (!std.mem.eql(u8, &digest, &expected)) return null;
            return digest;
        }
        const index = self.remap.records.get(identity) orelse return null;
        if (index == std.math.maxInt(usize)) return null;
        return self.remap.shapes.digest(index);
    }
    /// Record that a check summary stood in for ordinary instance `index`: the
    /// body was neither checked nor copied, and nothing is retained for it.
    pub fn standIn(self: *Session, index: usize) void {
        if (index < self.reuse.stood_in.len) self.reuse.stood_in[index] = true;
        self.cache.statistics.reused += 1;
    }
    fn reason(self: *Session, why: MissReason) ?typed.Function {
        self.cache.statistics.rejections.lookup[@backingInt(why)] += 1;
        self.cache.statistics.rejections.total[@backingInt(why)] += 1;
        return null;
    }
    fn relocationMiss(self: *Session, err: copy.Error, failure: copy.Failure) error{ OutOfMemory, InternalError }!?typed.Function {
        return switch (err) {
            error.InvalidRelocation => blk: {
                self.cache.statistics.rejections.relocation[@backingInt(std.meta.activeTag(failure))] += 1;
                break :blk self.reason(.relocation_failed);
            },
            error.OutOfMemory => error.OutOfMemory,
            error.InternalError => error.InternalError,
        };
    }
    /// Build one retained entry for a freshly checked body, or record the exact
    /// conservative miss and return null. Every temporary key slice is copied
    /// into the entry arena by `Entry.create`, so the temporaries can be freed
    /// before return.
    fn buildFreshEntry(self: *Session, program: typed.Program, i: usize, range: copy.Range, shapes: *key.Shapes) error{ OutOfMemory, InternalError }!?owned.Entry {
        const cache = self.cache;
        const ast_index = self.prepared.ordinary_ast[i];
        const stable_key = self.prepared.keys[ast_index];
        var refs = copy.RefSet.init(cache.allocator);
        refs.sources.enabled = true;
        refs.sources.local = self.prepared.regions[ast_index];
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
                if (self.reuse.resolver) |resolver| if (try resolver.capture(resolver.context, @fromBackingInt(id.*))) |reference| {
                    function_refs[function_count] = reference;
                    function_count += 1;
                    continue;
                };
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
        owned.sortFunctionRefs(owned.FunctionRef, function_refs[0..function_count]);
        var record_arena = std.heap.ArenaAllocator.init(cache.allocator);
        defer record_arena.deinit();
        const record_refs = (try self.buildRecordRefs(program, .{ .ast_index = ast_index, .range = range, .shapes = shapes }, &refs, record_arena.allocator())) orelse return null;
        const source_refs = try self.remap.sources.capture(cache.allocator, self.prepared.regions[ast_index], &refs.sources.items);
        defer cache.allocator.free(source_refs);
        const spec: owned.Spec = .{
            .source_refs = source_refs,
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
    fn recordMiss(self: *Session, why: MissReason) ?[]const owned.RecordRef {
        _ = self.freshMiss(why);
        return null;
    }
    fn collectRecordIndices(self: *Session, program: typed.Program, refs: *copy.RefSet, allocator: std.mem.Allocator) error{ OutOfMemory, InternalError }!?[]usize {
        var indices: std.ArrayList(usize) = .empty;

        var referenced = refs.records.keyIterator();
        while (referenced.next()) |index| try indices.append(allocator, index.*);
        var cursor: usize = 0;
        while (cursor < indices.items.len) : (cursor += 1) {
            const index = indices.items[cursor];
            if (index >= program.records.len) return null;
            if (index < self.remap.initial_record_count) continue;
            const record = program.records[index];
            const dependencies: []const typed.Type = if (record.shape.array) |array| &.{array.element} else if (record.shape.tuple) tuple: {
                // Insert fields directly: their slice cannot escape this block.
                for (record.fields) |field| try addRecordDependency(refs, &indices, allocator, field.ty);
                break :tuple &.{};
            } else &.{};
            for (dependencies) |dependency| try addRecordDependency(refs, &indices, allocator, dependency);
        }
        const result = try indices.toOwnedSlice(allocator);
        return result;
    }
    const RecordCapture = struct { ast_index: usize, range: copy.Range, shapes: *key.Shapes };
    fn addRecordDependency(refs: *copy.RefSet, indices: *std.ArrayList(usize), allocator: std.mem.Allocator, dependency: typed.Type) error{OutOfMemory}!void {
        if (!dependency.isAggregate()) return;
        const child = dependency.recordIndex();
        if (refs.records.contains(child)) return;
        try refs.records.put(refs.allocator, child, {});
        try indices.append(allocator, child);
    }
    fn buildRecordRefs(self: *Session, program: typed.Program, capture: RecordCapture, refs: *copy.RefSet, allocator: std.mem.Allocator) error{ OutOfMemory, InternalError }!?[]const owned.RecordRef {
        const indices = (try self.collectRecordIndices(program, refs, allocator)) orelse return self.recordMiss(.missing_record);
        std.mem.sort(usize, indices, {}, struct {
            fn less(_: void, a: usize, b: usize) bool {
                return a < b;
            }
        }.less);
        const record_refs = try allocator.alloc(owned.RecordRef, indices.len);
        for (indices, record_refs) |index, *reference| {
            const record = program.records[index];
            const shape = (try (if (index < self.remap.initial_record_count) &self.remap.shapes else capture.shapes).digest(index)) orelse return self.recordMiss(.missing_record);
            reference.* = .{ .index = index, .key = record.name, .shape = shape };
            if (index < self.remap.initial_record_count) continue;
            if (record.shape.array == null and !record.shape.tuple and record.contract.callback == null) continue;
            const recipes = try allocator.alloc(owned.TypeRecipe, 1);
            reference.recipes = recipes;
            if (record.shape.array) |array| {
                if (array.key != null) return self.recordMiss(.interned_record);
                const region = self.prepared.regions[capture.ast_index];
                if (record.declaration.start < region.start or record.declaration.end > region.end) return self.recordMiss(.interned_record);
                if (array.length > record.declaration.end - record.declaration.start) return self.recordMiss(.interned_record);
                recipes[0] = .{ .array = .{ .element = array.element, .length = array.length, .site = record.declaration } };
            } else if (record.shape.tuple) {
                const elements = try allocator.alloc(typed.Type, record.fields.len);
                for (record.fields, elements) |field, *element| element.* = field.ty;
                recipes[0] = .{ .tuple = elements };
            } else if (record.contract.callback != null) {
                var site: ?source.Span = null;
                for (program.nodes[capture.range.nodes.start..capture.range.nodes.end]) |node| {
                    if (node.ty != record.id or node.data != .function_value) continue;
                    site = node.span;
                    break;
                }
                recipes[0] = .{ .callable = site orelse return self.recordMiss(.function_value) };
            } else return self.recordMiss(.interned_record);
        }
        return record_refs;
    }
    /// Count one body that cannot be retained, with the exact conservative reason.
    fn freshMiss(self: *Session, why: MissReason) ?owned.Entry {
        self.cache.statistics.rejections.retention[@backingInt(why)] += 1;
        self.cache.statistics.rejections.total[@backingInt(why)] += 1;
        return null;
    }

    /// Atomically retain changed bodies and transfer unchanged entries; OOM keeps the old cache.
    ///
    /// The in-memory budget is shared with the symbolic and concrete
    /// specialization tables, so this request keeps the longest leading prefix
    /// of stable ordinary bodies whose owned storage plus the exact
    /// hash-index backing allocation fits the share of the budget the generic
    /// tables leave. Bodies outside that prefix can still be restored one at
    /// a time from the durable store without growing retained storage.
    pub fn remember(self: *Session, program: typed.Program) error{ OutOfMemory, InternalError }!void {
        const cache = self.cache;
        if (!cache.context.boundary.verified.reuse or cache.reuse.max_bytes == 0) return;
        // Validation-only summary requests have no complete trees to retain.
        // Hosts may opt lowering requests into tree reuse independently of the
        // unchanged pass facts their summaries stand in for.
        if (cache.context.summaries) |request| if (request.body_policy != .concrete or !cache.context.retain_summary_trees) return;
        var shapes: key.Shapes = .{ .allocator = cache.allocator, .records = program.records };
        defer shapes.deinit();
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
            if (self.reuse.stood_in[i]) continue;
            const ast_index = self.prepared.ordinary_ast[i];
            const stable_key = self.prepared.keys[ast_index];
            // An on-demand durable hit was already copied and released. Leave
            // its existing file alone rather than rebuilding a retained entry.
            if (self.reuse.functions[i] and !cache.index.contains(stable_key)) continue;
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
            const entry = (try self.buildFreshEntry(program, i, range, &shapes)) orelse continue;
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
                try self.persistUnretained(program, stopped_at, &shapes);
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
        try self.persistUnretained(program, stopped_at, &shapes);
    }

    /// Persist checked bodies beyond the in-memory prefix, with one temporary
    /// owned entry at a time. Successful durable hits need no publication.
    fn persistUnretained(self: *Session, program: typed.Program, start: usize, shapes: *key.Shapes) error{ OutOfMemory, InternalError }!void {
        const persistent = self.cache.context.persistent orelse return;
        var started = false;
        errdefer if (started) {
            persistent.endBatch() catch |err| switch (err) {
                // Preserve the original publication/check error during cleanup.
                error.OutOfMemory => {},
            };
        };
        for (start..self.prepared.ordinary_ast.len) |i| {
            if (self.reuse.stood_in[i] or self.reuse.functions[i]) continue;
            const range = self.ranges[i];
            if (range.nodes.end > program.nodes.len or range.statements.end > program.statements.len) return error.InternalError;
            var entry = (try self.buildFreshEntry(program, i, range, shapes)) orelse continue;
            defer entry.deinit();
            if (!started) {
                try persistent.beginBatch();
                started = true;
            }
            _ = try persistent.put(&entry);
        }
        if (started) try persistent.endBatch();
    }
};

/// Whether one entry's stored body bytes are the trailing slice of its stored
/// region bytes, which is the shape `Entry.create` always writes: a region runs
/// from the declaration's first byte to the end of its body. When it holds, and
/// the two lengths have already been proven equal, byte equality of the region
/// implies byte equality of the body, so the body needs no second pass. The
/// fresh side is always in that shape because `key.prepare` ends a region where
/// the body ends; this guards the stored side, whose shape a decoder only
/// bounds-checks.
fn bodyIsRegionSuffix(identity: owned.Identity, region: source.Span, body: source.Span) bool {
    return identity.region.end == identity.body.end and
        identity.body.start >= identity.region.start and
        region.end == body.end and
        body.start >= region.start;
}

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

/// Whether the next ordinary entry still fits `budget` once the body's actual
/// owned storage (entry row plus arena backing including chunk bookkeeping) and
/// the exact hash-index backing the standard map allocates for that entry count
/// (including its minimum capacity, header and alignment) are both counted.
fn fitsOrdinaryBudget(running: usize, cost: usize, count: usize, budget: usize) bool {
    return running + cost + owned.indexBytesFor(count) <= budget;
}

const Reuse = struct {
    enabled: bool,
    functions: []bool,
    /// Bodies a check summary stood in for: there is no checked tree to retain.
    stood_in: []bool,
    resolver: ?ReferenceResolver = null,
};

/// Whether one referenced aggregate is a declared callable-typed slot. Declared
/// callbacks are interned before checking, so they have a stable remap; callable
/// contracts interned while checking are handled as `interned_record` misses.
fn declaredCallback(records: []const typed.Record, index: usize) bool {
    return index < records.len and records[index].contract.callback != null;
}

/// A duplicate spelling can still identify one catalog record by its exact
/// transitive schema. Multiple matching records remain conservative misses.
fn uniqueRecordShape(shapes: *key.Shapes, name: []const u8, expected: [32]u8) error{OutOfMemory}!?usize {
    var found: ?usize = null;
    for (shapes.records, 0..) |record, index| {
        if (record.contract.callback == null) continue;
        if (!std.mem.eql(u8, record.name, name)) continue;
        const digest = (try shapes.digest(index)) orelse continue;
        if (!std.mem.eql(u8, &digest, &expected)) continue;
        if (found != null) return null;
        found = index;
    }
    return found;
}

test "semantic cache duplicate callable names require one exact shape" {
    const t = std.testing;
    const callback: typed.Callable = .{ .parameters = &.{}, .return_type = .i64, .effects = 0 };
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(typed.Type.record_base), .name = "func() -> i64", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{}, .shape = .{ .domain = .u64 }, .contract = .{ .callback = callback } },
        .{ .id = @fromBackingInt(typed.Type.record_base + 1), .name = "func() -> i64", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{}, .shape = .{ .domain = .u64 }, .contract = .{ .callback = callback } },
    };
    records[1].contract.callback.?.return_origin = .fresh;
    var shapes: key.Shapes = .{ .allocator = t.allocator, .records = &records };
    defer shapes.deinit();
    const first = (try shapes.digest(0)).?;
    try t.expectEqual(@as(?usize, 0), try uniqueRecordShape(&shapes, records[0].name, first));
    records[1].contract.callback.?.return_origin = .unknown;
    shapes.memo.clearRetainingCapacity();
    try t.expectEqual(@as(?usize, null), try uniqueRecordShape(&shapes, records[0].name, first));
}

/// Request-local bridge to validated specialization registration; never retained or persisted.
pub const ReferenceResolver = struct {
    context: *anyopaque,
    capture: *const fn (*anyopaque, typed.FunctionId) error{OutOfMemory}!?owned.FunctionRef,
    resolve: *const fn (*anyopaque, owned.FunctionRef) error{ OutOfMemory, InternalError }!?typed.FunctionId,
    resolve_type: ?*const fn (*anyopaque, owned.TypeRecipe, source.Span, source.Span, []const copy.RecordRemap) error{ OutOfMemory, InternalError }!?typed.Type = null,
    type_shape: ?*const fn (*anyopaque, typed.Type) error{OutOfMemory}!?[32]u8 = null,
    resolve_record: ?*const fn (*anyopaque, []const u8, [32]u8) error{OutOfMemory}!?typed.Type = null,
};
