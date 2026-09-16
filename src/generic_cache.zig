//! C3 symbolic-template reuse.
//!
//! The abstract generic pass checks every template (and every ordinary callee
//! reached from one) without representative substitution. That result is a
//! direct per-function fact: an effect mask, a mutation footprint, body-local
//! diagnostics and the abstract call edges that feed the later whole-graph
//! effect propagation. This module persists those direct facts in the shared
//! `semantic-cache-v1` durable store under an explicit `symbolic-template-v1`
//! payload kind and replays them when the declaration region, dependency
//! context and build context are all byte-identical.
//!
//! The whole-graph `effects.checkAbstract` pass is deliberately *not* cached:
//! it is cheap, and re-deriving it every request from the combined fresh and
//! replayed masks keeps transitive effect verdicts sound when one callee body
//! changes while its callers are reused. A replayed function is only accepted
//! when every callee edge resolves to a fresh declaration; a missing or
//! ambiguous callee is a conservative miss, never a partial reuse.
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const effect_set = @import("effect_set.zig");
const effects = @import("effects.zig");
const key = @import("semantic_key.zig");
const owned = @import("semantic_entry.zig");
const store_mod = @import("semantic_store.zig");

/// Why a symbolic function was checked fresh instead of reused.
pub const MissReason = enum {
    /// The cache holds no retention budget.
    cache_disabled,
    /// No retained or durable entry exists for this declaration.
    no_entry,
    /// The declaration's dependency digest changed.
    context_changed,
    /// The declaration region length changed.
    region_length_changed,
    /// The declaration region bytes changed.
    region_bytes_changed,
    /// A recorded note span no longer fits the fresh region.
    relocation_failed,
    /// A recorded callee no longer exists.
    missing_callee,
    /// A recorded callee key is ambiguous in the fresh program.
    ambiguous_callee,
    /// A successful direct result could not be represented (for example a
    /// diagnostic anchored outside the declaration region).
    unrepresentable,
};
pub const miss_reason_count = std.meta.tags(MissReason).len;
pub const MissCounts = [miss_reason_count]usize;

/// Human-readable work-report reason tag for one conservative symbolic miss.
pub fn missReasonName(reason: MissReason) []const u8 {
    return switch (reason) {
        .cache_disabled => "symbolic-cache-disabled",
        .no_entry => "symbolic-no-retained-template",
        .context_changed => "symbolic-dependencies-changed",
        .region_length_changed => "symbolic-declaration-region-length-changed",
        .region_bytes_changed => "symbolic-declaration-region-changed",
        .relocation_failed => "symbolic-relocation-failed",
        .missing_callee => "symbolic-missing-callee-identity",
        .ambiguous_callee => "symbolic-ambiguous-callee-identity",
        .unrepresentable => "symbolic-result-unrepresentable",
    };
}

/// Actual symbolic-template work observed at the check/replay sites.
pub const Statistics = struct {
    checked: usize = 0,
    reused: usize = 0,
    stored: usize = 0,
    bypassed: usize = 0,
    misses: MissCounts = @splat(0),
};

/// One in-process symbolic entry table. It mirrors the durable store so a
/// session can reuse a template without a second process, and so a durable hit
/// is promoted into memory for the rest of the process.
pub const Table = struct {
    allocator: ?std.mem.Allocator = null,
    entries: std.ArrayList(owned.SymbolicEntry) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    statistics: Statistics = .{},

    fn ensure(self: *Table, allocator: std.mem.Allocator) void {
        if (self.allocator == null) self.allocator = allocator;
    }
    /// Release the table's owned storage. Equivalent to `clear`; present so
    /// the allocator-owning type has the conventional deinit shape.
    pub fn deinit(self: *Table) void {
        self.clear();
    }
    /// Release every retained symbolic arena. Safe before any `ensure`.
    pub fn clear(self: *Table) void {
        const allocator = self.allocator orelse return;
        for (self.entries.items) |*entry| entry.deinit();
        self.entries.deinit(allocator);
        self.index.deinit(allocator);
        self.entries = .empty;
        self.index = .empty;
    }
    /// Owned bytes of this table: entry rows, entry arenas (which own keys,
    /// notes, edges and source slices) and the stable-key hash index capacity.
    pub fn retainedBytes(self: *const Table) usize {
        var bytes: usize = self.entries.capacity * @sizeOf(owned.SymbolicEntry);
        for (self.entries.items) |entry| bytes += owned.symbolicArenaBytes(entry);
        bytes += owned.hashIndexBytes(self.index.capacity());
        return bytes;
    }
    /// Insertion order of the oldest retained entry, or null when empty.
    pub fn oldestSequence(self: *const Table) ?u64 {
        if (self.entries.items.len == 0) return null;
        var oldest = self.entries.items[0].sequence;
        for (self.entries.items[1..]) |entry| {
            if (entry.sequence < oldest) oldest = entry.sequence;
        }
        return oldest;
    }
    // twin-drift-ok: deliberately mirrors the sibling table's eviction policy;
    // only the owned entry type and its cost helper differ.
    /// Release the oldest retained entry and return the bytes it owned, or null
    /// when the table is empty. Emptying the table also releases its row buffer
    /// and index, so shared-budget accounting always converges.
    pub fn evictOldest(self: *Table) ?usize {
        const allocator = self.allocator orelse return null;
        if (self.entries.items.len == 0) return null;
        var victim: usize = 0;
        for (self.entries.items[1..], 1..) |entry, i| {
            if (entry.sequence < self.entries.items[victim].sequence) victim = i;
        }
        var removed = self.entries.swapRemove(victim);
        _ = self.index.fetchRemove(removed.payload.identity.key);
        const cost = @sizeOf(owned.SymbolicEntry) + owned.symbolicArenaBytes(removed);
        removed.deinit();
        if (self.entries.items.len == 0) {
            self.entries.deinit(allocator);
            self.entries = .empty;
            self.index.deinit(allocator);
            self.index = .empty;
        } else {
            if (victim < self.entries.items.len) {
                const moved = self.entries.items[victim].payload.identity.key;
                self.index.putAssumeCapacity(moved, victim);
            }
            self.compact(allocator);
        }
        return cost;
    }
    // twin-drift-ok: deliberately mirrors the sibling table's compaction;
    // the row type and key slice are identical, so no shared helper is needed.
    /// Rebuild the index and row buffer at the live count's capacity. Without
    /// this, a once-large table keeps its peak index/row capacity forever and a
    /// tight budget would evict every entry before the accounting converged.
    /// A failed reindex leaves the previous consistent index in place.
    fn compact(self: *Table, allocator: std.mem.Allocator) void {
        const count = self.entries.items.len;
        const size = std.math.cast(u32, count) orelse return;
        var new_index: std.StringHashMapUnmanaged(usize) = .empty;
        new_index.ensureTotalCapacity(allocator, size) catch return;
        for (self.entries.items, 0..) |entry, i| new_index.putAssumeCapacity(entry.payload.identity.key, i);
        self.index.deinit(allocator);
        self.index = new_index;
        self.entries.shrinkAndFree(allocator, count);
    }
    fn reserve(self: *Table, count: usize) error{OutOfMemory}!void {
        const allocator = self.allocator orelse return error.OutOfMemory;
        const index_size = std.math.cast(u32, count) orelse return error.OutOfMemory;
        try self.entries.ensureUnusedCapacity(allocator, count);
        try self.index.ensureUnusedCapacity(allocator, index_size);
    }
    /// Insert one entry, replacing any superseded entry under the same stable
    /// key (a body edit keeps the same declaration key). `reserve(1)` must have
    /// been called for the new row; a replacement deinits the old arena and
    /// reuses its slot so `clear` never observes one arena twice.
    fn rememberAssumeCapacity(self: *Table, entry: owned.SymbolicEntry, sequence: u64) void {
        var incoming = entry;
        incoming.sequence = sequence;
        if (self.index.fetchRemove(incoming.payload.identity.key)) |removed| {
            self.entries.items[removed.value].deinit();
            self.entries.items[removed.value] = incoming;
            self.index.putAssumeCapacity(incoming.payload.identity.key, removed.value);
            return;
        }
        const id = self.entries.items.len;
        self.entries.appendAssumeCapacity(incoming);
        self.index.putAssumeCapacity(incoming.payload.identity.key, id);
    }
};

/// A relocated direct result ready to apply to the fresh checker state.
pub const Replay = struct {
    effect_mask: effect_set.Mask,
    mutation_mask: u16,
    mutation_writes: bool,
    /// Diagnostics with fresh absolute spans. Their `code`/`message` slices
    /// borrow the retained entry, which the owning cache keeps alive.
    notes: []const diagnostic.Diagnostic,
    /// Call edges with the fresh callee index already resolved.
    edges: []const effects.AbstractCall,
};

/// One fresh direct result captured for publication.
pub const Capture = struct {
    effect_mask: effect_set.Mask,
    mutation_mask: u16,
    mutation_writes: bool,
    notes: []const diagnostic.Diagnostic,
    edges: []const effects.AbstractCall,
};

/// Immutable declaration facts one session looks up against.
pub const Request = struct { src: source.Source, prepared: *const key.Prepared };
/// In-process and durable stores a session reads and publishes through. `mode`
/// distinguishes the module-qualified name-resolution mode from the single-unit
/// lexical mode, whose call-target keys and privacy rules differ.
pub const Backend = struct {
    memory: *Table,
    persistent: ?*store_mod.Store,
    enabled: bool,
    mode: []const u8,
    /// Shared-budget reconciliation hook installed by the owning cache. Called
    /// after any promotion so generic entries converge on the combined bound.
    retention: ?owned.RetentionHook = null,
    /// Owning cache's shared insertion clock, or null in direct unit tests.
    sequence: ?*u64 = null,
};

/// One request's view over the in-memory and durable symbolic stores.
pub const Session = struct {
    allocator: std.mem.Allocator,
    request: Request,
    backend: Backend,
    /// Stable declaration key -> fresh program.functions ordinal. `maxInt`
    /// marks an ambiguous key.
    fresh_by_key: std.StringHashMapUnmanaged(usize) = .empty,
    /// Successfully checked direct results waiting for a whole-pass publish.
    fresh: std.ArrayList(owned.SymbolicEntry) = .empty,

    /// Open one request. `prepared` and `backend` must outlive the session.
    pub fn init(allocator: std.mem.Allocator, src: source.Source, prepared: *const key.Prepared, backend: Backend) error{OutOfMemory}!Session {
        backend.memory.ensure(allocator);
        var self: Session = .{
            .allocator = allocator,
            .request = .{ .src = src, .prepared = prepared },
            .backend = backend,
        };
        errdefer self.deinit();
        for (prepared.keys, 0..) |stable, index| {
            const entry = try self.fresh_by_key.getOrPut(allocator, stable);
            if (entry.found_existing) entry.value_ptr.* = std.math.maxInt(usize) else entry.value_ptr.* = index;
        }
        return self;
    }

    pub fn deinit(self: *Session) void {
        for (self.fresh.items) |*entry| entry.deinit();
        self.fresh.deinit(self.allocator);
        self.fresh_by_key.deinit(self.allocator);
        self.reconcileRetention();
    }

    /// Ask the owning cache to converge the combined retention budget. A
    /// durable-hit promotion happens in `lookup`, but eviction is deferred to
    /// this request boundary so a replay can never borrow a released entry.
    fn reconcileRetention(self: *Session) void {
        if (self.backend.retention) |hook| hook.reconcile(hook.owner);
    }

    /// Next shared insertion order for a promoted entry. Ties (a null clock in
    /// direct unit tests) still evict in array/insertion order.
    fn nextSequence(self: *Session) u64 {
        const sequence = self.backend.sequence orelse return 0;
        sequence.* +%= 1;
        return sequence.*;
    }

    fn symbolicKey(self: *Session, index: usize) error{OutOfMemory}![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}\x1f{s}", .{ owned.symbolic_key_prefix, self.backend.mode, self.request.prepared.keys[index] });
    }
    fn declRegion(self: *Session, index: usize) source.Span {
        return self.request.prepared.regions[index];
    }
    fn declBody(self: *Session, index: usize) source.Span {
        return self.request.prepared.bodies[index];
    }

    /// Relocate one retained entry into a fresh direct result, or record the
    /// exact conservative miss reason and return null.
    pub fn lookup(self: *Session, allocator: std.mem.Allocator, index: usize) error{ OutOfMemory, InternalError }!?Replay {
        if (!self.backend.enabled) return self.reason(.cache_disabled);
        if (index >= self.request.prepared.keys.len) return self.reason(.no_entry);
        const stable = try self.symbolicKey(index);
        defer self.allocator.free(stable);
        const entry_id: usize = blk: {
            if (self.backend.memory.index.get(stable)) |id| break :blk id;
            const persistent = self.backend.persistent orelse return self.reason(.no_entry);
            const decoded = (try persistent.lookupSymbolic(self.allocator, stable, self.request.prepared.contexts[index])) orelse return self.reason(.no_entry);
            try self.backend.memory.reserve(1);
            self.backend.memory.rememberAssumeCapacity(decoded, self.nextSequence());
            break :blk self.backend.memory.entries.items.len - 1;
        };
        const entry = &self.backend.memory.entries.items[entry_id];
        if (!std.mem.eql(u8, &entry.payload.identity.context, &self.request.prepared.contexts[index])) return self.reason(.context_changed);
        const fresh_region = self.declRegion(index);
        if (entry.payload.source.region.end - entry.payload.source.region.start != fresh_region.end - fresh_region.start) return self.reason(.region_length_changed);
        if (!std.mem.eql(u8, entry.payload.source.region_bytes, self.request.src.bytes[fresh_region.start..fresh_region.end])) return self.reason(.region_bytes_changed);
        const fresh_body = self.declBody(index);
        if (entry.payload.source.body.end - entry.payload.source.body.start != fresh_body.end - fresh_body.start) return self.reason(.region_length_changed);
        if (!std.mem.eql(u8, entry.payload.source.body_bytes, self.request.src.bytes[fresh_body.start..fresh_body.end])) return self.reason(.region_bytes_changed);

        const notes = try allocator.alloc(diagnostic.Diagnostic, entry.payload.notes.len);
        errdefer allocator.free(notes);
        var note_count: usize = 0;
        while (note_count < entry.payload.notes.len) : (note_count += 1) {
            const relocated = try relocateNote(entry.payload.notes[note_count], fresh_region) orelse
                return self.reasonAfterAlloc(allocator, notes, &.{}, .relocation_failed);
            notes[note_count] = relocated;
        }
        const edges = try allocator.alloc(effects.AbstractCall, entry.payload.edges.len);
        errdefer allocator.free(edges);
        for (entry.payload.edges, 0..) |edge, edge_index| {
            const callee = self.fresh_by_key.get(edge.callee) orelse return self.reasonAfterAlloc(allocator, notes, edges, .missing_callee);
            if (callee == std.math.maxInt(usize)) return self.reasonAfterAlloc(allocator, notes, edges, .ambiguous_callee);
            const span = edge.span.toAbsolute(fresh_region) orelse return self.reasonAfterAlloc(allocator, notes, edges, .relocation_failed);
            edges[edge_index] = .{ .caller = index, .callee = callee, .span = span };
        }
        self.backend.memory.statistics.reused += 1;
        return .{
            .effect_mask = entry.payload.contract.effect_mask,
            .mutation_mask = entry.payload.contract.mutation_mask,
            .mutation_writes = entry.payload.contract.mutation_writes,
            .notes = notes,
            .edges = edges,
        };
    }

    fn reasonAfterAlloc(self: *Session, allocator: std.mem.Allocator, notes: []diagnostic.Diagnostic, edges: []effects.AbstractCall, why: MissReason) ?Replay {
        allocator.free(notes);
        if (edges.len != 0) allocator.free(edges);
        return self.reason(why);
    }

    fn reason(self: *Session, why: MissReason) ?Replay {
        self.backend.memory.statistics.misses[@backingInt(why)] += 1;
        return null;
    }

    /// Count one abstract check that rejected before producing a retained
    /// result. Failed checks are always re-derived, but they are still work.
    pub fn noteFailed(self: *Session, index: usize) void {
        if (index < self.request.prepared.keys.len) self.backend.memory.statistics.checked += 1;
    }

    /// Capture one successfully checked direct result. Returns false when the
    /// result cannot be represented safely (never a partial entry).
    pub fn record(self: *Session, index: usize, capture: Capture) error{ OutOfMemory, InternalError }!bool {
        if (index >= self.request.prepared.keys.len) return false;
        // A fresh abstract check is real work even when retention is disabled;
        // count it so `--no-cache` reports performed work rather than a skip.
        self.backend.memory.statistics.checked += 1;
        if (!self.backend.enabled) return false;
        const stable = try self.symbolicKey(index);
        defer self.allocator.free(stable);
        const region = self.declRegion(index);
        const body = self.declBody(index);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        var accepted = false;
        defer if (!accepted) arena.deinit();
        const arena_allocator = arena.allocator();
        const owned_notes = try arena_allocator.alloc(owned.SymbolicNote, capture.notes.len);
        for (capture.notes, owned_notes) |note, *out| {
            out.* = captureNote(arena_allocator, region, note) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Unrepresentable => {
                    self.backend.memory.statistics.misses[@backingInt(MissReason.unrepresentable)] += 1;
                    return false;
                },
            };
        }
        const owned_edges = try arena_allocator.alloc(owned.SymbolicEdge, capture.edges.len);
        for (capture.edges, owned_edges) |edge, *out| {
            if (edge.callee >= self.request.prepared.keys.len) {
                self.backend.memory.statistics.misses[@backingInt(MissReason.unrepresentable)] += 1;
                return false;
            }
            out.* = .{
                .callee = try arena_allocator.dupe(u8, self.request.prepared.keys[edge.callee]),
                .span = owned.RelativeSpan.fromAbsolute(region, edge.span) orelse {
                    self.backend.memory.statistics.misses[@backingInt(MissReason.unrepresentable)] += 1;
                    return false;
                },
            };
        }
        // Every arena allocation must happen before the arena is copied into
        // the entry: Zig evaluates struct fields in source order, and a copy
        // taken before an allocation would not own that allocation.
        const owned_key = try arena_allocator.dupe(u8, stable);
        const owned_region = try arena_allocator.dupe(u8, self.request.src.bytes[region.start..region.end]);
        const owned_body = try arena_allocator.dupe(u8, self.request.src.bytes[body.start..body.end]);
        const payload: owned.StoredSymbolic = .{
            .identity = .{ .key = owned_key, .context = self.request.prepared.contexts[index] },
            .source = .{
                .old_len = self.request.src.bytes.len,
                .region = region,
                .body = body,
                .region_bytes = owned_region,
                .body_bytes = owned_body,
            },
            .contract = .{ .effect_mask = capture.effect_mask, .mutation_mask = capture.mutation_mask, .mutation_writes = capture.mutation_writes },
            .notes = owned_notes,
            .edges = owned_edges,
        };
        const entry: owned.SymbolicEntry = .{ .payload = payload, .arena = arena };
        try self.fresh.append(self.allocator, entry);
        accepted = true;
        return true;
    }

    /// Persist freshly checked entries and promote them into the in-process
    /// table. Called only after the whole abstract pass succeeded. Persistence
    /// happens before any move, so an allocation failure leaves every entry
    /// owned by this session and released by `deinit`.
    pub fn publish(self: *Session) error{OutOfMemory}!void {
        if (self.fresh.items.len == 0) return;
        if (self.backend.persistent) |persistent| {
            // One publication batch inventories the contract namespace once
            // instead of once per body, matching C2's bounded publication path.
            try persistent.beginBatch();
            for (self.fresh.items) |*entry| _ = try persistent.putSymbolic(entry);
            try persistent.endBatch();
        }
        try self.backend.memory.reserve(self.fresh.items.len);
        for (self.fresh.items) |entry| self.backend.memory.rememberAssumeCapacity(entry, self.nextSequence());
        self.backend.memory.statistics.stored += self.fresh.items.len;
        self.fresh.clearRetainingCapacity();
        self.reconcileRetention();
    }
};

/// Capture one diagnostic whose spans must all fit the declaration region.
/// An out-of-region related/provenance note is `Unrepresentable`, never a
/// silently dropped note: a dropped note would change the replayed diagnostic.
/// Exposed so the out-of-region rejection has a direct regression test.
pub fn captureNote(allocator: std.mem.Allocator, region: source.Span, note: diagnostic.Diagnostic) error{ OutOfMemory, Unrepresentable }!owned.SymbolicNote {
    if (note.stack.len != 0) return error.Unrepresentable;
    const span = owned.RelativeSpan.fromAbsolute(region, note.span) orelse return error.Unrepresentable;
    const code = try allocator.dupe(u8, note.code);
    errdefer allocator.free(code);
    const message = try allocator.dupe(u8, note.message);
    errdefer allocator.free(message);
    const related = try captureRelated(allocator, region, note.related);
    errdefer if (related) |value| allocator.free(value.message);
    const origin = try captureRelated(allocator, region, note.provenance.origin);
    errdefer if (origin) |value| allocator.free(value.message);
    const requirement = try captureRelated(allocator, region, note.provenance.requirement);
    errdefer if (requirement) |value| allocator.free(value.message);
    return .{
        .code = code,
        .severity = note.severity,
        .span = span,
        .message = message,
        .notes = .{ .related = related, .origin = origin, .requirement = requirement },
    };
}

fn captureRelated(allocator: std.mem.Allocator, region: source.Span, note: ?diagnostic.Related) error{ OutOfMemory, Unrepresentable }!?owned.RelativeNote {
    const value = note orelse return null;
    const span = owned.RelativeSpan.fromAbsolute(region, value.span) orelse return error.Unrepresentable;
    return .{ .span = span, .message = try allocator.dupe(u8, value.message) };
}

/// Relocate one retained note. Returns null when a span no longer fits.
fn relocateNote(note: owned.SymbolicNote, region: source.Span) error{OutOfMemory}!?diagnostic.Diagnostic {
    const span = note.span.toAbsolute(region) orelse return null;
    return .{
        .code = note.code,
        .severity = note.severity,
        .span = span,
        .message = note.message,
        .related = try relocateRelated(note.notes.related, region),
        .provenance = .{
            .origin = try relocateRelated(note.notes.origin, region),
            .requirement = try relocateRelated(note.notes.requirement, region),
        },
    };
}

fn relocateRelated(note: ?owned.RelativeNote, region: source.Span) error{OutOfMemory}!?diagnostic.Related {
    const value = note orelse return null;
    const span = value.span.toAbsolute(region) orelse return null;
    return .{ .span = span, .message = value.message };
}
