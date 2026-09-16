//! C3 concrete-specialization body reuse.
//!
//! A concrete specialization is a generic template instantiated with resolved
//! type and length arguments. Its checked body is keyed by the canonical
//! specialization fingerprint (`semantic_key.specializationFingerprint`) and
//! persisted in the shared `semantic-cache-v1` durable store under the explicit
//! `specialization-v1` payload kind. Replay requires:
//!
//! * the canonical fingerprint to be re-derived from fresh inputs;
//! * the defining template's declaration region/body bytes to be byte-identical;
//! * the template dependency context and build contract to match;
//! * every stored function/record reference to remap to a fresh identity with no
//!   missing or ambiguous binding.
//!
//! The whole-graph effect and mutation passes are deliberately *not* cached:
//! `effects.check` and `origins.check` always rerun over the combined fresh and
//! replayed trees, so a changed provider or callee body can never inherit a
//! stale transitive verdict from a replayed specialization.
const std = @import("std");
const source = @import("source.zig");
const key = @import("semantic_key.zig");
const owned = @import("semantic_entry.zig");
const store_mod = @import("semantic_store.zig");

/// Why a concrete specialization was checked fresh instead of reused.
pub const MissReason = enum {
    /// Zero retention budget: reuse was never consulted.
    cache_disabled,
    /// No retained or durable entry exists for this canonical fingerprint.
    no_entry,
    /// The template dependency context or declared contract changed.
    context_changed,
    /// The defining declaration region length changed.
    region_length_changed,
    /// The defining declaration region bytes changed.
    region_bytes_changed,
    /// The retained canonical fingerprint or template key no longer matches.
    stale_identity,
    /// A retained tree reference could not be relocated.
    relocation_failed,
    /// A referenced ordinary declaration is absent from the fresh program.
    missing_ordinary,
    /// A referenced ordinary declaration is ambiguous in the fresh program.
    ambiguous_ordinary,
    /// A referenced specialization is not instantiated in the fresh program.
    missing_specialization,
    /// A referenced specialization is ambiguous in the fresh program.
    ambiguous_specialization,
    /// A referenced aggregate type has no stable fresh identity.
    missing_record,
    /// A referenced aggregate type name is ambiguous in the fresh program.
    ambiguous_record,
    /// The tree referenced a catalog record interned while checking.
    interned_record,
    /// The tree referenced a synthesized lambda body with no stable identity.
    lambda_reference,
    /// The result could not be represented safely (never a partial entry).
    unrepresentable,
};
pub const miss_reason_count = std.meta.tags(MissReason).len;
pub const MissCounts = [miss_reason_count]usize;

/// Human-readable work-report reason tag for one conservative miss.
pub fn missReasonName(reason: MissReason) []const u8 {
    return switch (reason) {
        .cache_disabled => "specialization-cache-disabled",
        .no_entry => "specialization-no-retained-body",
        .context_changed => "specialization-dependencies-changed",
        .region_length_changed => "specialization-declaration-region-length-changed",
        .region_bytes_changed => "specialization-declaration-region-changed",
        .stale_identity => "specialization-stale-identity",
        .relocation_failed => "specialization-relocation-failed",
        .missing_ordinary => "specialization-missing-ordinary-identity",
        .ambiguous_ordinary => "specialization-ambiguous-ordinary-identity",
        .missing_specialization => "specialization-missing-instance-identity",
        .ambiguous_specialization => "specialization-ambiguous-instance-identity",
        .missing_record => "specialization-missing-record-identity",
        .ambiguous_record => "specialization-ambiguous-record-identity",
        .interned_record => "specialization-interned-record",
        .lambda_reference => "specialization-lambda-reference",
        .unrepresentable => "specialization-result-unrepresentable",
    };
}

/// Actual concrete-specialization work observed at the check/replay sites.
pub const Statistics = struct {
    checked: usize = 0,
    reused: usize = 0,
    stored: usize = 0,
    bypassed: usize = 0,
    misses: MissCounts = @splat(0),
};

/// One in-process specialization entry table. It mirrors the durable store so a
/// session can reuse a specialization without a second process, and so a
/// durable hit is promoted into memory for the rest of the process.
pub const Table = struct {
    allocator: ?std.mem.Allocator = null,
    entries: std.ArrayList(owned.SpecializationEntry) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    statistics: Statistics = .{},

    fn ensure(self: *Table, allocator: std.mem.Allocator) void {
        if (self.allocator == null) self.allocator = allocator;
    }
    /// Release the table's owned storage. Equivalent to `clear`.
    pub fn deinit(self: *Table) void {
        self.clear();
    }
    /// Release every retained specialization arena. Safe before any `ensure`.
    pub fn clear(self: *Table) void {
        const allocator = self.allocator orelse return;
        for (self.entries.items) |*entry| entry.deinit();
        self.entries.deinit(allocator);
        self.index.deinit(allocator);
        self.entries = .empty;
        self.index = .empty;
    }
    /// Owned bytes of this table: entry rows plus entry arenas (which own the
    /// copied checked tree, reference keys, fingerprints and source slices)
    /// including their per-chunk bookkeeping, plus the exact stable-key
    /// hash-index backing allocation.
    pub fn retainedBytes(self: *const Table) usize {
        var bytes: usize = self.entries.capacity * @sizeOf(owned.SpecializationEntry);
        for (self.entries.items) |entry| bytes += owned.specializationArenaBytes(entry);
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
        const cost = @sizeOf(owned.SpecializationEntry) + owned.specializationArenaBytes(removed);
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
    /// key. Deiniting the old arena and reusing its slot keeps `clear` free of
    /// double frees.
    fn rememberAssumeCapacity(self: *Table, entry: owned.SpecializationEntry, sequence: u64) void {
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

/// Immutable request facts one session looks up against.
pub const Backend = struct {
    memory: *Table,
    persistent: ?*store_mod.Store,
    enabled: bool,
    /// Build-context dimension of the canonical key (compiler/target/runtime
    /// ABI/flags fingerprint). Empty is a real, distinct value.
    build: []const u8,
    /// Shared-budget reconciliation hook installed by the owning cache. Called
    /// after any promotion so generic entries converge on the combined bound.
    retention: ?owned.RetentionHook = null,
    /// Owning cache's shared insertion clock, or null in direct unit tests.
    sequence: ?*u64 = null,
};

/// One request's view over the in-memory and durable specialization stores.
pub const Session = struct {
    allocator: std.mem.Allocator,
    prepared: *const key.Prepared,
    backend: Backend,
    /// Successfully checked entries waiting for a whole-pass publish.
    fresh: std.ArrayList(owned.SpecializationEntry) = .empty,

    /// Open one request. `prepared` and `backend` must outlive the session.
    pub fn init(allocator: std.mem.Allocator, prepared: *const key.Prepared, backend: Backend) error{OutOfMemory}!Session {
        backend.memory.ensure(allocator);
        return .{ .allocator = allocator, .prepared = prepared, .backend = backend };
    }

    pub fn deinit(self: *Session) void {
        for (self.fresh.items) |*entry| entry.deinit();
        self.fresh.deinit(self.allocator);
        self.reconcileRetention();
    }

    /// Ask the owning cache to converge the combined retention budget. A
    /// durable-hit promotion happens in `open`, but eviction is deferred to this
    /// request boundary so a copied tree can never borrow a released entry.
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

    /// Durable store key for one canonical fingerprint.
    pub fn stableKey(allocator: std.mem.Allocator, fingerprint: []const u8) error{OutOfMemory}![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ owned.specialization_key_prefix, fingerprint });
    }

    /// Resolve one retained entry for `fingerprint`, or record the exact
    /// conservative miss and return null. Never returns an unvalidated entry:
    /// the store validates the payload kind, checksum, lengths and references
    /// before it reaches this point.
    pub fn open(self: *Session, fingerprint: []const u8, context: [32]u8) error{ OutOfMemory, InternalError }!?*const owned.SpecializationEntry {
        if (!self.backend.enabled) {
            self.noteMiss(.cache_disabled);
            return null;
        }
        const stable = try stableKey(self.allocator, fingerprint);
        defer self.allocator.free(stable);
        const id: usize = blk: {
            if (self.backend.memory.index.get(stable)) |id| break :blk id;
            const persistent = self.backend.persistent orelse {
                self.noteMiss(.no_entry);
                return null;
            };
            const decoded = (try persistent.lookupSpecialization(self.allocator, stable, context)) orelse {
                self.noteMiss(.no_entry);
                return null;
            };
            try self.backend.memory.reserve(1);
            self.backend.memory.rememberAssumeCapacity(decoded, self.nextSequence());
            break :blk self.backend.memory.entries.items.len - 1;
        };
        return &self.backend.memory.entries.items[id];
    }

    /// Count one replayed specialization body.
    pub fn noteReused(self: *Session) void {
        self.backend.memory.statistics.reused += 1;
    }
    /// Count one conservative miss with its located reason.
    pub fn noteMiss(self: *Session, why: MissReason) void {
        self.backend.memory.statistics.misses[@backingInt(why)] += 1;
    }
    /// Count one specialization body that was checked fresh.
    pub fn noteChecked(self: *Session) void {
        self.backend.memory.statistics.checked += 1;
    }
    /// Queue one freshly checked entry for publication after the whole request
    /// passes every cross-function check.
    pub fn record(self: *Session, entry: owned.SpecializationEntry) error{OutOfMemory}!void {
        try self.fresh.append(self.allocator, entry);
    }

    /// Persist freshly checked entries and promote them into the in-process
    /// table. Called only after the whole request succeeded. Persistence
    /// happens before any move, so an allocation failure leaves every entry
    /// owned by this session and released by `deinit`.
    // twin-drift-ok: deliberately mirrors generic_cache.Session.publish (same
    // publish-then-promote protocol); only the typed store call differs.
    pub fn publish(self: *Session) error{OutOfMemory}!void {
        if (self.fresh.items.len == 0) return;
        if (self.backend.persistent) |persistent| {
            try persistent.beginBatch();
            for (self.fresh.items) |*entry| _ = try persistent.putSpecialization(entry);
            try persistent.endBatch();
        }
        try self.backend.memory.reserve(self.fresh.items.len);
        for (self.fresh.items) |entry| self.backend.memory.rememberAssumeCapacity(entry, self.nextSequence());
        self.backend.memory.statistics.stored += self.fresh.items.len;
        self.fresh.clearRetainingCapacity();
        self.reconcileRetention();
    }
};

const testing = std.testing;

test "specialization miss reasons are stable and counted without reuse" {
    var table: Table = .{};
    defer table.deinit();
    var session: Session = try .init(testing.allocator, undefined, .{ .memory = &table, .persistent = null, .enabled = false, .build = "" });
    defer session.deinit();
    _ = try session.open("abc", @splat(0));
    try testing.expectEqual(@as(usize, 1), table.statistics.misses[@backingInt(MissReason.cache_disabled)]);
    try testing.expectEqual(@as(usize, 0), table.statistics.reused);
}
