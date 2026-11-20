//! A compact previous-build index bypasses validated prepasses while retaining
//! exact post-fusion and ordered mutation checkpoints for dirty caller inspection.
//! Changed source, callees and runtime helper inventories lose demand reuse.
const std = @import("std");
const cache_miss = @import("selka").cache_miss;
const facts = @import("facts.zig");
const cache = @import("optimization_cache.zig");
const effects = @import("effects.zig");
const demand_ir = @import("demand_ir.zig");
const origins = @import("inline_origins.zig");
const fusion = @import("fusion_checkpoint.zig");
const names = @import("optimizer_names.zig");
const chunks = @import("optimizer_chunks.zig");
const snapshot = @import("ir_snapshot.zig");
const identity = @import("canonical_ir.zig");
const ir = @import("ir.zig");
const Counts = @import("pass_statistics.zig").Counts;
const cutoff = @import("optimizer_cutoff.zig");
const rows = @import("optimizer_rows.zig");
const joins_mod = @import("optimizer_joins.zig");
/// Dependency-validated inputs and exact intermediate/final checkpoint handles (`optimizer_rows.zig`).
pub const Entry = rows.Entry;
/// Exact exploratory dependencies and compact field evidence for one round.
pub const FieldRound = rows.FieldRound;
const mapEntry = rows.mapEntry;
const cloneEntry = rows.cloneEntry;
/// Stage outputs preceding ownership/final facts; base is post-fusion raw IR.
pub const Phase = enum { base, leaf, cfg, unswitch, parameter };
const Runtime = struct {
    arena: std.mem.Allocator,
    backing: std.mem.Allocator,
    provenance: *origins.Table,
    cursor: struct { stage: cache.Stage = .inline_leaf, caller: u32 = 0 } = .{},
    loaded: []?Phase,
};

/// The raw module of this build, indexed by name, with the canons that name it: what a stored entry resolves against. Built
/// once per build, before the fusions declare their helpers.
const Loader = struct {
    index: names.Index,
    canons: names.Canons,
    source: snapshot.Context,
    raw_count: u32,

    fn build(a: std.mem.Allocator, context: *cache.Context) std.mem.Allocator.Error!?Loader {
        const structure = try a.create(identity.Canon);
        structure.* = identity.Canon.prepare(a, context.source.module, context.locator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => return null,
        };
        const named = try a.create(identity.Canon);
        named.* = try structure.named();
        const canons: names.Canons = .{ .structure = structure, .named = named };
        return .{
            .index = try names.Index.build(canons, context.source.module, context.source),
            .canons = canons,
            .source = context.source,
            .raw_count = @intCast(context.source.module.functions.items.len),
        };
    }

    fn restorer(self: *const Loader, a: std.mem.Allocator, entry_names: names.Names, same_layout: bool) std.mem.Allocator.Error!rows.Restorer {
        const plain: rows.Restorer = .{ .resolver = .{ .index = &self.index, .canons = self.canons, .source = self.source, .names = entry_names, .verify = false }, .raw_count = self.raw_count, .same_layout = same_layout };
        return plain.remembering(try a.alloc(u32, entry_names.callees.len));
    }
};

/// Read the rest of the row of function `index` into `entry`, when it is pending in `lazy`.
fn settleAt(lazy: *Lazy, entry: *Entry, index: usize) demand_ir.Error!void {
    if (index >= lazy.pending.len) return;
    const pending = lazy.pending[index] orelse return;
    const a = lazy.arena orelse return cache_miss.at(@src());
    const loader = if (lazy.loader) |*known| known else return cache_miss.at(@src());
    const pool = if (lazy.candidates) |known| known.cache orelse return cache_miss.at(@src()) else return cache_miss.at(@src());
    const bytes = (try restBytes(pool, pending.rest)) orelse return cache_miss.at(@src());
    var rest = (try rows.readRest(a, bytes)) orelse return cache_miss.at(@src());
    rows.mapRest(&rest, .{ .restore = try loader.restorer(a, pending.names, pending.same_layout) }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unmappable => return cache_miss.at(@src()),
    };
    if (!rows.fill(entry, rest)) return cache_miss.at(@src());
    lazy.pending[index] = null;
    if (lazy.statistics) |counted| counted.restores.cutoff.settled += 1;
}

/// Where a build publishes its index and what of the last publication it can keep: the manifest's key, and for each function
/// the digest of the record it was loaded from, which a function left alone by this build names again without capturing it.
const Publication = struct {
    key: [32]u8,
    /// Where the entries this build started from stand: their rows, the chunks read, the state and the groups.
    held: Held = .{},
    /// The second lookup of the entries (G3p-0).
    second: Second = .{},
    /// What this build changed against the entries it started from (`optimizer_cutoff.zig`).
    cut: cutoff.Cut = .{},
    /// The rows of the entries found and not yet read in full (`Index.settle`).
    lazy: Lazy = .{},
    /// The joins of the state this build started from and the ones it made (`optimizer_joins.zig`).
    joins: Joined = .{},
};

/// Where the entries a build started from stand in the store.
const Held = struct {
    /// Each function's row in the chunk it was loaded from.
    records: []const ?chunks.Held = &.{},
    /// The chunks the build read.
    cache: ?*chunks.Cache = null,
    /// The program state this build starts from (`chunks.stateOf`), which names the head it publishes.
    state: ?[32]u8 = null,
    /// The project the build belongs to (`chunks.ProjectId`), when the stage store has a shared half: the latest-state pointers it publishes are named by it.
    project: ?[32]u8 = null,
    /// The group each function belongs to (`chunkGroups`), copied when the build began: a chunk is the entries of one group.
    modules: []const []const u8 = &.{},
};

/// A recomputed function's contribution to a field round, to compare with what its stored row held (`Index.sameAsStored`).
pub const Fresh = struct { round: usize, record: FieldRound, targets: []const u32, references: []const u32 };

/// What a field round left: its table with the digest the next round's inputs are built from, and the return interval of each function.
pub const Left = struct { table: facts.FieldIntervals, digest: [32]u8, returns: []const ?facts.Interval };

/// The manifests a build's lookups came from and the build's cut, which says where each entry came from.
const JoinSource = struct { candidates: Candidates, cut: cutoff.Cut };
/// The entries a build found and which of them stay deferred.
const JoinEntries = struct { entries: []const Entry, green: []const bool };

/// The stored joins the field rounds of this build can take. Most deferred functions come from one manifest, the one that holds the most; that manifest
/// must have been stored under this raw layout and name a joins record for the same number of functions, every deferred function must hold the field-table
/// digest the record holds, and those from that manifest the hull it holds. A deferred function found in another manifest (an undone edit leaves the
/// states of two builds as candidates) is compared with the row of the manifest the joins belong to, as a recomputed function is. Anything else leaves
/// the build the full rounds.
fn storedJoins(a: std.mem.Allocator, context: *cache.Context, source: JoinSource, found: JoinEntries) std.mem.Allocator.Error!Joined {
    var counts: [3]usize = .{ 0, 0, 0 };
    const module = context.source.module;
    for (found.green, source.cut.slot, module.functions.items) |deferred, from, function| {
        if (!deferred or function.signature.linkage != .internal) continue;
        if (from >= counts.len) return .{};
        counts[from] += 1;
    }
    var chosen: u8 = 0;
    for (counts, 0..) |count, slot| if (count > counts[chosen]) {
        chosen = @intCast(slot);
    };
    if (counts[chosen] == 0 or !source.candidates.matching[chosen]) return .{};
    const manifest = source.candidates.manifests[chosen] orelse return .{};
    const digest = manifest.joins orelse return .{};
    const stored = (try joins_mod.load(a, context.store, digest, module.functions.items.len)) orelse return .{};
    for (found.green, found.entries, source.cut.slot, module.functions.items, stored.hulls) |deferred, entry, from, function, hull| {
        if (!deferred or function.signature.linkage != .internal) continue;
        const final = entry.demand.fields.final orelse return .{};
        if (!std.mem.eql(u8, &final, &stored.tables[1].digest)) return .{};
        if (from == chosen and !equalRanges(entry.parameters, hull)) return .{};
    }
    return .{ .stored = stored, .slot = chosen };
}

/// The rest of a row whose entry has been found and not read in full: where it stands, the names both parts share, and
/// whether the manifest was stored under the layout of this build.
const Pending = struct { rest: RestAt, names: names.Names, same_layout: bool, summary_ok: bool = false, slot: u8 = 0 };

/// Where the rest of a row stands: the digest of its chunk and its row in it.
const RestAt = struct { chunk: [32]u8, row: u32 };

/// The rows a build has found and not read in full, and what reads them: the loader that resolves their names, the candidates they
/// came from and the build's arena.
const Lazy = struct {
    pending: []?Pending = &.{},
    loader: ?Loader = null,
    candidates: ?Candidates = null,
    arena: ?std.mem.Allocator = null,
    statistics: ?*cache.Statistics = null,
};

/// What the joins of the field rounds are for this build: the record the manifest it started from names (and the slot of that manifest),
/// the tables and return intervals its rounds made, the joins it made once the hulls complete them, and what the verify mode found.
const Joined = struct {
    stored: ?joins_mod.Joins = null,
    slot: u8 = cutoff.Cut.slot_none,
    rounds: [2]?Round = .{ null, null },
    made: ?joins_mod.Joins = null,
    /// A function recomputed in the verify mode contributed something other than what its stored row held: the stored joins do not stand.
    differs: bool = false,
    /// The first deferred function the rounds recomputed because its dependencies differed.
    demoted: ?u32 = null,
};

/// The table and the return intervals one field round left.
const Round = struct { table: joins_mod.Table, returns: []const ?facts.Interval };

/// The second lookup, by the lowering key without the source proof of the text.
const Second = struct {
    /// Each function's lowering key without the source proof of its text (`demand_ir.Context.unmixed`): published beside the
    /// mixed key so that a later build can find the entry of a function whose text moved, and nothing else changed.
    unmixed: []const ?[32]u8 = &.{},
    /// The functions whose exploration rounds and effects were taken from the entry that second lookup found (G3p-0): red, but
    /// only by position, so what the passes would compute for them is what that entry holds.
    loose: []const bool = &.{},
    /// What was taken from that entry besides the rounds, the effect and the hull, by function (only where `loose` holds).
    found: []const ?Loose = &.{},
};

/// What the second lookup found of a function that is red by position only: the entry it came from, to compare what this build makes of the
/// function with what that entry held (`Index.checkpoint`, `Index.summary`, the emission effect), and the manifest it stood in.
const Loose = struct {
    /// The manifest the entry came from (`Candidates.manifests`): its callers' entries came from the same one or were not built with it.
    slot: u8,
    /// The raw body digest of the entry.
    raw: ?[32]u8,
    /// The entry's checkpoints and the summary and emission effect it held.
    history: ?rows.History,
    summary: ?cache.Summary,
    emission: ?effects.Reused,
};

/// One build's candidate mask and compact records, separate from restored IR.
pub const Index = struct {
    context: *cache.Context,
    publication: Publication,
    entries: []Entry,
    green: []bool,
    parents: []const std.ArrayList(u32),
    catalog: fusion.Catalog = .{},
    runtime: ?Runtime = null,

    /// Attach phase-aware callbacks only for the lifetime of the optimizer.
    pub fn attach(self: *Index, a: std.mem.Allocator, backing: std.mem.Allocator, provenance: *origins.Table) std.mem.Allocator.Error!void {
        const loaded = try a.alloc(?Phase, self.entries.len);
        @memset(loaded, null);
        self.runtime = .{ .arena = a, .backing = backing, .provenance = provenance, .loaded = loaded };
        self.context.lazy.checkpoints = .{ .pointer = self, .identity_fn = checkpointIdentity };
        self.context.lazy.raw.?.inspection = .{ .pointer = self, .ensure_fn = inspect };
    }

    /// A skipped physical function still advances the virtual pass cursor.
    pub fn cursor(self: *Index, stage: cache.Stage, caller: u32) void {
        if (self.runtime) |*runtime| runtime.cursor = .{ .stage = stage, .caller = caller };
    }

    fn observed(stage: cache.Stage, caller: u32, target: u32) Phase {
        return switch (stage) {
            .inline_leaf => if (target < caller) .leaf else .base,
            .inline_cfg => if (target < caller) .cfg else .leaf,
            .parameter_inline => if (target < caller) .parameter else .unswitch,
            else => .base,
        };
    }

    /// The checkpoint the entry of `index` holds after `phase`, or null when it holds none.
    pub fn record(self: *const Index, index: u32, phase: Phase) ?cache.Checkpoint {
        if (phase == .base or index >= self.entries.len) return null;
        const history = self.entries[index].demand.history orelse return null;
        return history.outputs[@backingInt(phase) - 1];
    }

    fn checkpointIdentity(pointer: *anyopaque, stage: cache.Stage, caller: u32, target: u32) ?cache.CheckpointIdentity {
        const self: *Index = @ptrCast(@alignCast(pointer));
        if (target == caller or target >= self.green.len or !self.green[target]) return null;
        if (self.context.source.module.functions.items[target].signature.linkage != .internal) return null;
        const phase = observed(stage, caller, target);
        if (phase == .base) return .{ .digest = self.entries[target].raw orelse return null, .ancestry = .{ .frames = &.{}, .blocks = &.{}, .instructions = &.{}, .present = false } };
        self.settle(target) catch return null;
        const saved_checkpoint = self.record(target, phase) orelse return null;
        return .{ .digest = saved_checkpoint.output, .ancestry = saved_checkpoint.provenance };
    }

    fn inspect(pointer: *anyopaque, target: u32) demand_ir.Error!void {
        const self: *Index = @ptrCast(@alignCast(pointer));
        const at = self.runtime.?.cursor;
        if (target >= self.green.len or !self.green[target] or self.context.source.module.functions.items[target].signature.linkage != .internal) return self.context.lazy.raw.?.ensureRaw(target);
        try self.materialize(target, observed(at.stage, at.caller, target));
    }

    /// Restore an exact checkpoint, following identity aliases to their predecessor.
    pub fn materialize(self: *Index, index: u32, phase: Phase) demand_ir.Error!void {
        const runtime = &self.runtime.?;
        if (runtime.loaded[index] == phase) return;
        if (phase == .base) {
            // A previously loaded later checkpoint cannot be replaced by ensureRaw.
            if (runtime.loaded[index] != null) return cache_miss.at(@src());
            if (self.entries[index].demand.fusion.identity) {
                try self.context.lazy.raw.?.ensureRaw(index);
            } else {
                const key = self.entries[index].demand.fusion.key orelse return cache_miss.at(@src());
                var scratch = std.heap.ArenaAllocator.init(runtime.backing);
                defer scratch.deinit();
                const wire = try self.context.store.loadValue(scratch.allocator(), key, @import("ir_snapshot.zig").Wire) orelse return cache_miss.at(@src());
                const empty: cache.Provenance = .{ .frames = &.{}, .blocks = &.{}, .instructions = &.{}, .present = false };
                const restored = try self.context.restore(runtime.arena, index, wire, empty, runtime.provenance) orelse return cache_miss.at(@src());
                const kept = self.context.source.module.functions.items[index].module;
                self.context.source.module.functions.items[index] = restored;
                self.context.source.module.functions.items[index].module = kept;
                const digest = try self.context.bodyDigest(index) orelse return cache_miss.at(@src());
                const expected = self.entries[index].raw orelse return cache_miss.at(@src());
                if (!std.mem.eql(u8, &digest, &expected)) return cache_miss.at(@src());
                self.context.statistics.restores.fusions += 1;
                if (index < self.context.lazy.raw.?.loaded.len) self.context.lazy.raw.?.loaded[index] = true;
            }
            runtime.loaded[index] = .base;
            return;
        }
        try self.settle(index);
        const saved_checkpoint = self.record(index, phase) orelse return cache_miss.at(@src());
        var scratch = std.heap.ArenaAllocator.init(runtime.backing);
        defer scratch.deinit();
        const value = try self.context.store.loadValue(scratch.allocator(), saved_checkpoint.key, cache.Transform) orelse return cache_miss.at(@src());
        self.context.statistics.restores.checkpoints += 1;
        if (value.output == null or !std.mem.eql(u8, &value.output.?, &saved_checkpoint.output)) return cache_miss.at(@src());
        const resolved = try self.context.resolvedTransform(value) orelse return cache_miss.at(@src());
        if (value.changed != saved_checkpoint.changed or !resolved.provenance.equal(saved_checkpoint.provenance)) return cache_miss.at(@src());
        if (resolved.wire) |wire| {
            const restored = try self.context.restore(runtime.arena, index, wire, resolved.provenance, runtime.provenance) orelse return cache_miss.at(@src());
            const kept = self.context.source.module.functions.items[index].module;
            self.context.source.module.functions.items[index] = restored;
            self.context.source.module.functions.items[index].module = kept;
            if (index < self.context.lazy.raw.?.loaded.len) self.context.lazy.raw.?.loaded[index] = true;
        } else {
            const previous: Phase = @fromBackingInt(@intCast(@backingInt(phase) - 1));
            try self.materialize(index, previous);
        }
        const digest = try self.context.bodyDigest(index) orelse return cache_miss.at(@src());
        if (!std.mem.eql(u8, &digest, &saved_checkpoint.output)) return cache_miss.at(@src());
        const ancestry = cache.Provenance.capture(scratch.allocator(), self.context.source, runtime.provenance, index) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return cache_miss.at(@src()),
        };
        if (!ancestry.equal(saved_checkpoint.provenance)) return cache_miss.at(@src());
        runtime.loaded[index] = phase;
    }

    /// Capture compact identities while the ordinary stage body is already live.
    pub fn checkpoint(self: *Index, a: std.mem.Allocator, index: u32, input: struct { stage: cache.Stage, key: ?[32]u8, changed: u32 }, provenance: *const origins.Table) std.mem.Allocator.Error!void {
        if (self.context.lazy.raw == null) return;
        const phase: Phase = switch (input.stage) {
            .inline_leaf => .leaf,
            .inline_cfg => .cfg,
            .unswitch => .unswitch,
            .parameter_inline => .parameter,
            else => return,
        };
        // A function recomputed after it was found has been read in full (`demoteAt`, `materialize`): `was` is what its entry held.
        std.debug.assert(index >= self.publication.lazy.pending.len or self.publication.lazy.pending[index] == null);
        if (self.entries[index].demand.history == null) self.entries[index].demand.history = .{};
        // What this checkpoint is compared with: the entry's, or for a function found by the second lookup (red by position only) the one
        // that lookup found, whose positions are those of the text before it moved.
        const was = self.entries[index].demand.history.?.outputs[@backingInt(phase) - 1] orelse self.looseCheckpoint(index, phase);
        self.entries[index].demand.history.?.outputs[@backingInt(phase) - 1] = null;
        // Moved until the new output is shown to be the one the entry held: what reads this checkpoint compares against that.
        const bit = @as(u8, 1) << @intCast(@backingInt(phase) - 1);
        self.publication.cut.mark(index, bit);
        const key = input.key orelse return;
        const output = try self.context.bodyDigest(index) orelse return;
        const plain = try self.plainOf(index, phase, .{ .output = output, .was = was }) orelse return;
        const ancestry = cache.Provenance.capture(a, self.context.source, provenance, index) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return,
        };
        self.entries[index].demand.history.?.outputs[@backingInt(phase) - 1] = .{
            .key = key,
            .output = output,
            .plain = plain,
            .provenance = ancestry,
            .changed = input.changed,
            .graph = .{ .calls = try targetsOf(a, &self.context.source.module.functions.items[index], .call), .references = try targetsOf(a, &self.context.source.module.functions.items[index], .func_ref) },
        };
        const previous = was orelse return;
        // The same body inlined the same way: what a reader that did not inline this function reads of it is unchanged, whatever moved.
        if (!std.mem.eql(u8, &previous.plain, &plain) or !previous.provenance.equalPlain(ancestry)) return;
        self.publication.cut.noteSameBody(index, bit, !std.mem.eql(u8, &previous.output, &output) or !previous.provenance.equal(ancestry));
    }

    /// The digest without positions of function `index`'s body after `phase`, whose digest with them is `shown.output`. A body that is the
    /// one the entry held (`shown.was`) or the one the checkpoint before this held has the plain digest that checkpoint recorded; only
    /// a body no checkpoint of this build or the entry has seen is walked again.
    fn plainOf(self: *Index, index: u32, phase: Phase, shown: struct { output: [32]u8, was: ?cache.Checkpoint }) std.mem.Allocator.Error!?[32]u8 {
        if (shown.was) |previous| if (std.mem.eql(u8, &previous.output, &shown.output)) return previous.plain;
        if (@backingInt(phase) >= 2) if (self.entries[index].demand.history.?.outputs[@backingInt(phase) - 2]) |before| {
            if (std.mem.eql(u8, &before.output, &shown.output)) return before.plain;
        };
        return self.context.plainDigest(index);
    }

    /// The checkpoint after `phase` that the second lookup found for function `index`, when it was taken from that entry (`isLoose`).
    fn looseCheckpoint(self: *const Index, index: u32, phase: Phase) ?cache.Checkpoint {
        const found = self.looseFound(index) orelse return null;
        const history = found.history orelse return null;
        return history.outputs[@backingInt(phase) - 1];
    }

    /// What the second lookup took from the entry it found for function `index`, when the function is taken from it.
    fn looseFound(self: *const Index, index: usize) ?Loose {
        if (!self.isLoose(index) or index >= self.publication.second.found.len) return null;
        return self.publication.second.found[index];
    }

    /// Parameter demotion resumes from the pre-parameter checkpoint, preserving events.
    pub fn resumeParameters(self: *Index, was_green: []const bool) demand_ir.Error![]?Counts {
        const resumed = try self.runtime.?.arena.alloc(?Counts, self.entries.len);
        @memset(resumed, null);
        for (was_green, self.green, 0..) |prior, green, index| {
            if (!prior or green or self.context.source.module.functions.items[index].signature.linkage != .internal) continue;
            try self.materialize(@intCast(index), .unswitch);
            const leaf = self.record(@intCast(index), .leaf) orelse return cache_miss.at(@src());
            const cfg = self.record(@intCast(index), .cfg) orelse return cache_miss.at(@src());
            const unswitch = self.record(@intCast(index), .unswitch) orelse return cache_miss.at(@src());
            resumed[index] = .{ .inlined = leaf.changed + cfg.changed, .unswitched = unswitch.changed };
        }
        return resumed;
    }

    /// The functions deferred function `index` reads at `stage`, as its entry holds them: the targets of the body that stage starts
    /// from. Null when the entry does not say.
    fn readLists(self: *const Index, stage: cache.Stage, index: u32) ?[2][]const u32 {
        const source: ?cache.Checkpoint = switch (stage) {
            .inline_leaf => return .{ self.entries[index].demand.graph.calls, &.{} },
            .inline_cfg => self.record(index, .leaf),
            .parameter_inline => self.record(index, .unswitch),
            else => return null,
        };
        const saved = source orelse return null;
        return .{ saved.graph.calls, saved.graph.references };
    }

    /// Whether what `caller` reads of `target` at `stage` differs from what the entry of `caller` was built under: the target's
    /// checkpoint at the phase `observed` names (its raw body for a phase before the first stage), the query body of a wrapper
    /// target at the CFG stage, and the entries having been built together.
    fn targetMoved(self: *Index, stage: cache.Stage, caller: u32, target: u32) demand_ir.Error!bool {
        if (target == caller or target >= self.green.len) return false;
        if (self.context.source.module.functions.items[target].signature.linkage != .internal) return false;
        const cut = &self.publication.cut;
        const phase = observed(stage, caller, target);
        if (cut.changedAt(target, @intCast(@backingInt(phase)))) return true;
        if (cut.slot[caller] != cut.slot[target]) return true;
        if (cut.shiftedAt(target, @intCast(@backingInt(phase)))) {
            if (try self.inlinedAt(stage, caller, target)) return true;
            self.context.statistics.restores.cutoff.shifted += 1;
        }
        if (stage != .inline_cfg) return false;
        // A wrapper's one call is its query: the eligibility of the wrapper reads the query's body (`readerDependency`).
        if (!@import("inline_reader.zig").mutationSignature(self.context.source.module, &self.context.source.module.functions.items[target])) return false;
        const wrapper = self.record(target, phase) orelse return true;
        if (wrapper.graph.calls.len != 1) return false;
        const query = wrapper.graph.calls[0];
        if (query == caller or query >= self.green.len or self.context.source.module.functions.items[query].signature.linkage != .internal) return false;
        const seen: u8 = @intCast(@backingInt(observed(.inline_cfg, caller, query)));
        if (cut.changedAt(query, seen)) return true;
        return cut.shiftedAt(query, seen) and try self.inlinedAt(stage, caller, query);
    }

    /// Whether the entry of deferred function `caller` inlined `target` (or inlined something that did) in `stage`: the function is among
    /// the frames of the ancestry the entry held after the stage. Source positions of `target` enter the stage's result only through the
    /// instructions it cloned, and every clone is in a frame; the stage reads no position otherwise. A function the entry does not say
    /// anything about inlined it, as far as a reader can tell.
    fn inlinedAt(self: *Index, stage: cache.Stage, caller: u32, target: u32) demand_ir.Error!bool {
        const phase: Phase = switch (stage) {
            .inline_leaf => .leaf,
            .inline_cfg => .cfg,
            .parameter_inline => .parameter,
            else => return true,
        };
        try self.settle(caller);
        const saved = self.record(caller, phase) orelse return true;
        return saved.provenance.inlines(target);
    }

    /// Whether deferred function `index` reads, at `stage`, a function that is recomputed in this build (the reads the verify mode
    /// checks: nothing else could have changed them).
    pub fn keptReadingRecomputed(self: *const Index, stage: cache.Stage, index: u32) bool {
        if (index >= self.green.len or !self.green[index]) return false;
        return self.readsRecomputed(stage, index);
    }

    /// `keptReadingRecomputed` for a function known to be deferred.
    pub fn readsRecomputed(self: *const Index, stage: cache.Stage, index: u32) bool {
        const lists: [2][]const u32 = if (stage == .final) blk: {
            const saved = self.record(index, .parameter) orelse return false;
            break :blk .{ saved.graph.calls, saved.graph.references };
        } else self.readLists(stage, index) orelse return false;
        for (lists) |list| {
            for (list) |target| {
                if (self.isRecomputed(index, target)) return true;
            }
        }
        return false;
    }

    /// Whether `target`, another function than `caller`, is internal and recomputed in this build.
    fn isRecomputed(self: *const Index, caller: u32, target: u32) bool {
        if (target == caller or target >= self.green.len or self.green[target]) return false;
        return self.context.source.module.functions.items[target].signature.linkage == .internal;
    }

    /// The key the entry of `index` holds for `stage` (the record that stage stored), and the phase it follows.
    pub fn savedKey(self: *const Index, stage: cache.Stage, index: u32) ?[32]u8 {
        const phase: Phase = switch (stage) {
            .inline_leaf => .leaf,
            .inline_cfg => .cfg,
            .parameter_inline => .parameter,
            else => return self.entries[index].final,
        };
        return (self.record(index, phase) orelse return null).key;
    }

    /// Restore deferred function `index` at the checkpoint before `stage`, to derive what that stage would have made of it.
    pub fn restoreBefore(self: *Index, stage: cache.Stage, index: u32) demand_ir.Error!void {
        const before: Phase = switch (stage) {
            .inline_leaf => .base,
            .inline_cfg => .leaf,
            .parameter_inline => .unswitch,
            else => .parameter,
        };
        try self.materialize(index, before);
    }

    /// Whether deferred function `index` reads, at `stage`, a function that moved in source positions only: a read the cutoff ignores
    /// when the function did not inline it, and which the verify mode checks by running the stage afresh.
    pub fn readsShiftedKept(self: *const Index, stage: cache.Stage, index: u32) bool {
        const lists = self.readLists(stage, index) orelse return false;
        for (lists) |list| for (list) |target| {
            if (target == index or target >= self.green.len or self.context.source.module.functions.items[target].signature.linkage != .internal) continue;
            if (self.publication.cut.shiftedAt(target, @intCast(@backingInt(observed(stage, index, target))))) return true;
        };
        return false;
    }

    /// Note that function `index`, restored at the checkpoint before `stage` and run through it afresh, now holds the result the entry
    /// has for that stage: the checkpoint is loaded.
    pub fn loadedAfter(self: *Index, stage: cache.Stage, index: u32) void {
        const phase: Phase = switch (stage) {
            .inline_leaf => .leaf,
            .inline_cfg => .cfg,
            .parameter_inline => .parameter,
            else => return,
        };
        if (self.runtime) |*runtime| runtime.loaded[index] = phase;
    }

    /// The events deferred function `index` had before `stage` ran (`eventsBefore`), for a key derived afresh.
    pub fn eventsFor(self: *const Index, stage: cache.Stage, index: u32) demand_ir.Error!Counts {
        return self.eventsBefore(stage, index);
    }

    /// Whether deferred function `index` reads, at `stage`, something a recomputed function changed.
    fn readsMoved(self: *Index, stage: cache.Stage, index: u32) demand_ir.Error!bool {
        const lists = self.readLists(stage, index) orelse return true;
        for (lists) |list| for (list) |target| if (try self.targetMoved(stage, index, target)) return true;
        return false;
    }

    /// The events deferred function `index` had before `stage` ran, from its entry's checkpoints.
    fn eventsBefore(self: *const Index, stage: cache.Stage, index: u32) demand_ir.Error!Counts {
        var events: Counts = .{};
        if (stage == .inline_leaf) return events;
        const leaf = self.record(index, .leaf) orelse return cache_miss.at(@src());
        events.inlined = leaf.changed;
        if (stage == .inline_cfg) return events;
        const cfg = self.record(index, .cfg) orelse return cache_miss.at(@src());
        const unswitch = self.record(index, .unswitch) orelse return cache_miss.at(@src());
        events.inlined += cfg.changed;
        events.unswitched = unswitch.changed;
        if (stage == .inline_cfg or stage == .parameter_inline) return events;
        const parameter = self.record(index, .parameter) orelse return cache_miss.at(@src());
        events.inlined += parameter.changed;
        return events;
    }

    /// Recompute deferred function `index` from `stage` on: its body is restored at the checkpoint before that stage, and the
    /// events its entry holds up to there are returned for the caller to count.
    pub fn demoteAt(self: *Index, index: u32, stage: cache.Stage) demand_ir.Error!Counts {
        const before: Phase = switch (stage) {
            .inline_leaf => .base,
            .inline_cfg => .leaf,
            .parameter_inline => .unswitch,
            else => .parameter,
        };
        const events = try self.eventsBefore(stage, index);
        try self.settle(index);
        self.green[index] = false;
        self.context.statistics.restores.cutoff.demoted += 1;
        try self.materialize(index, before);
        return events;
    }

    /// At the turn of deferred function `index` in the inlining of `stage`: null when it keeps its entry's result, or the events
    /// of the stages it skipped when it is recomputed from here (the body at the checkpoint before this stage is restored).
    pub fn cutoffDemote(self: *Index, stage: cache.Stage, index: u32) demand_ir.Error!?Counts {
        if (!self.publication.cut.active()) return null;
        if (!try self.readsMoved(stage, index)) return null;
        const events = try self.demoteAt(index, stage);
        return events;
    }

    /// Whether `callee` changed in `bits`, for a function that read it with the entry it holds: one that the entry was not built
    /// together with counts as changed.
    fn calleeMoved(self: *const Index, caller: u32, callee: u32, bits: u8) bool {
        if (callee == caller or callee >= self.green.len) return false;
        if (self.context.source.module.functions.items[callee].signature.linkage != .internal) return false;
        const cut = &self.publication.cut;
        if (self.green[caller] and cut.slot[caller] != cut.slot[callee]) return true;
        return cut.moved[callee] & bits != 0;
    }

    /// Whether a function whose result was reused calls a function that changed in `bits`: the calls of the body after the
    /// parameter inlining, which a deferred function's entry holds and a recomputed one has loaded.
    pub fn callsChanged(self: *const Index, index: u32, deferred: bool, bits: u8) demand_ir.Error!bool {
        if (deferred) {
            const saved = self.record(index, .parameter) orelse return cache_miss.at(@src());
            for (saved.graph.calls) |callee| if (self.calleeMoved(index, callee, bits)) return true;
            return false;
        }
        for (self.context.source.module.functions.items[index].insts.items) |inst| {
            if (inst.op == .call and self.calleeMoved(index, @intCast(inst.a.index()), bits)) return true;
        }
        return false;
    }

    /// At the final stage: deferred function `index` is recomputed when a function its final key reads changed (the return
    /// interval of a callee, the effect of a callee or of a function it takes the address of). Null when it keeps its result,
    /// else the events of the stages it skipped.
    pub fn finalDemote(self: *Index, index: u32) demand_ir.Error!?Counts {
        if (!self.publication.cut.active()) return null;
        const saved = self.record(index, .parameter) orelse return cache_miss.at(@src());
        var moved = false;
        for (saved.graph.calls) |callee| moved = moved or self.calleeMoved(index, callee, cutoff.Moved.returned | cutoff.Moved.effect);
        for (saved.graph.references) |target| moved = moved or self.calleeMoved(index, target, cutoff.Moved.effect);
        if (!moved) return null;
        const events = try self.demoteAt(index, .final);
        return events;
    }

    /// Prepare build-arena-owned records and reverse calls. Failed preparation
    /// leaves partial allocations on that arena, reclaimed with the owning build.
    pub fn prepare(a: std.mem.Allocator, context: *cache.Context, mode: u8) std.mem.Allocator.Error!?Index {
        const layout = context.layoutDigest() orelse return null;
        const key = context.store.key("optimizer-shortcut-v2", &.{ &layout, &.{mode} });
        const previous = try context.store.loadValue(a, key, []Entry);
        const module = context.source.module;
        const count = module.functions.items.len;
        const entries = try a.alloc(Entry, count);
        const green = try a.alloc(bool, count);
        @memset(green, false);
        const parents = try a.alloc(std.ArrayList(u32), count);
        @memset(parents, .empty);
        var queue: std.ArrayList(u32) = .empty;
        for (module.functions.items, entries, green, 0..) |function, *entry, *reusable, index| {
            const raw = try context.bodyDigest(@intCast(index));
            entry.* = .{ .raw = raw };
            if (previous) |prior| if (prior.len >= count) {
                const old = prior[index];
                if (old.raw != null and raw != null and std.mem.eql(u8, &old.raw.?, &raw.?)) {
                    entry.* = old;
                    reusable.* = old.stable and old.final != null and old.summary != null and old.summary.?.valid(module);
                }
            };
            // External declarations have no mutable body or exploratory summary.
            if (function.signature.linkage != .internal) reusable.* = true;
            if (!reusable.*) try queue.append(a, @intCast(index));
            for (function.insts.items) |inst| {
                const target: usize = switch (inst.op) {
                    .call => inst.a.index(),
                    .func_ref => @intCast(inst.data),
                    else => continue,
                };
                if (target >= count) continue;
                try parents[target].append(a, @intCast(index));
            }
        }
        try invalidateCycles(a, parents, green, &queue);
        try invalidateCallers(a, parents, green, &queue);
        return .{ .context = context, .publication = .{ .key = key }, .entries = entries, .green = green, .parents = parents };
    }

    /// Dependency-closed functions with complete checkpoint chains stay deferred.
    /// A body that calls a declaration marked in `eager_callees` is never deferred.
    pub fn prepareDemand(a: std.mem.Allocator, context: *cache.Context, options: DemandOptions) demand_ir.Error!Index {
        const mode = options.mode;
        const field_proof = options.field_proof;
        const demand = context.lazy.raw.?;
        const name = if (context.source.source) |source| source.path else "";
        const parts: []const []const u8 = &.{ name, &.{mode} };
        // `key` is where `save` publishes this build's manifest; its candidates are the read generation's and the last full build's.
        const key = context.store.writeKey(manifest_scope, parts);
        // The raw layout (`ir_snapshot.layout` before fusion) gates the candidates: a manifest stored under another raw layout
        // names entries this program does not reuse, and its catalog's declarations are not this program's.
        const raw_layout = try @import("ir_snapshot.zig").layout(a, context.source);
        const state = chunks.stateOf(mode, raw_layout, demand.keys);
        const project = projectOf(context.store, context.source.source, mode);
        var candidates: Candidates = if (demand.force_eager) .{} else try Candidates.load(a, context.store, parts, .{ .raw_layout = raw_layout, .state = state, .project = project });
        // What the stored names resolve against: this build's raw module, indexed once. A module the canon cannot describe
        // reuses nothing.
        var loader: ?Loader = if (candidates.any()) try Loader.build(a, context) else null;
        if (candidates.any() and loader == null) candidates = .{};
        const module = context.source.module;
        const count = module.functions.items.len;
        const entries = try a.alloc(Entry, count);
        const green = try a.alloc(bool, count);
        @memset(green, false);
        const records = try a.alloc(?chunks.Held, count);
        @memset(records, null);
        const modules = try chunkGroups(a, module.functions.items);
        const parents = try a.alloc(std.ArrayList(u32), count);
        @memset(parents, .empty);
        var cut = try cutoff.Cut.init(a, count, options.cutoff);
        // Under the early cutoff a function found is read in two parts: its rest waits until something asks for it (`settle`).
        var lazy: Lazy = .{ .pending = try a.alloc(?Pending, count), .loader = loader, .candidates = candidates, .arena = a, .statistics = &context.statistics };
        @memset(lazy.pending, null);
        const wants_lazy = cut.active();
        var queue: std.ArrayList(u32) = .empty;
        for (module.functions.items, entries, green, 0..) |function, *entry, *reusable, index| {
            const lowered = if (index < demand.keys.len) demand.keys[index] else null;
            entry.* = .{ .demand = .{ .lowered = lowered } };
            const resolving: ?*const Loader = if (loader) |*built| built else null;
            if (lowered) |digest| if (try candidates.find(a, resolving, .{ .count = count, .index = index, .lowered = digest, .module = module, .lazy = wants_lazy })) |found| {
                entry.* = found.entry;
                lazy.pending[index] = found.pending;
                records[index] = found.record;
                cut.slot[index] = found.slot;
                reusable.* = reusableEntry(found.entry, module, index, found.summary_ok) and (field_proof or found.entry.summary_input != null) and
                    !callsAny(found.entry.demand.graph.calls, options.eager_callees);
                // An entry that is not used as it stands keeps its stored result as the one the cutoff compares what it makes with.
                if (!reusable.*) try settleAt(&lazy, entry, index);
            };
            if (function.signature.linkage != .internal) reusable.* = true;
            if (!reusable.*) try queue.append(a, @intCast(index));
            if (reusable.*) {
                for (entry.demand.graph.calls) |target| {
                    if (target >= count) return cache_miss.at(@src());
                    try parents[target].append(a, @intCast(index));
                }
            } else {
                try demand.ensure(@intCast(index));
                entry.demand.graph.calls = try targets(a, &module.functions.items[index]);
                entry.demand.graph.direct_calls = try targetsOf(a, &module.functions.items[index], .call);
                entry.demand.graph.references = try targetsOf(a, &module.functions.items[index], .func_ref);
                for (entry.demand.graph.calls) |target| if (target < count) try parents[target].append(a, @intCast(index));
            }
        }
        // Exploratory receipts validate exact current DFS return inputs before
        // admitting a final body, including when recursion changes DFS entry.
        if (!cut.active()) try invalidateCallers(a, parents, green, &queue);
        const loose = try looseEntries(a, .{ .candidates = candidates, .loader = if (loader) |*built| built else null, .context = context, .options = options }, .{ .entries = entries, .green = green, .parents = parents });
        // A function taken from the second lookup was built together with the entries of its manifest: its callers compare against that.
        for (loose.loose, loose.found, 0..) |taken, maybe, index| if (taken) if (maybe) |details| {
            cut.slot[index] = details.slot;
            cut.old_emission[index] = details.emission;
        };
        for (green, 0..) |reusable, index| if (!reusable) try demand.ensure(@intCast(index));
        var catalog = candidates.catalog(count);
        catalog.raw_layout = raw_layout;
        const joined = if (cut.active()) try storedJoins(a, context, .{ .candidates = candidates, .cut = cut }, .{ .entries = entries, .green = green }) else Joined{};
        const publication: Publication = .{
            .key = key,
            .held = .{ .records = records, .cache = candidates.cache, .modules = modules, .state = state, .project = project },
            .second = .{ .unmixed = demand.unmixed, .loose = loose.loose, .found = loose.found },
            .cut = cut,
            .lazy = lazy,
            .joins = joined,
        };
        return .{ .context = context, .publication = publication, .entries = entries, .green = green, .parents = parents, .catalog = catalog };
    }

    /// Read the rest of function `index`'s row into its entry, when it was found and not read in full: the field rounds, the exploratory
    /// summary and the output and ancestry of each checkpoint. A row whose rest does not decode or resolve is a cache miss.
    pub fn settle(self: *Index, index: u32) demand_ir.Error!void {
        return settleAt(&self.publication.lazy, &self.entries[index], index);
    }

    /// The joins of the state the entries of this build came from, when the field rounds can take them for the functions left alone
    /// (`storedJoins`): null when there are none, the entries came from more than one manifest, or the verify mode asks for the full rounds.
    pub fn joinsToTake(self: *const Index) ?joins_mod.Joins {
        if (self.publication.cut.mode == .verify) return null;
        return self.publication.joins.stored;
    }

    /// Whether deferred function `index` was found in the manifest the stored joins belong to: only then does the record stand for it.
    pub fn inJoinedSlot(self: *const Index, index: usize) bool {
        const cut = &self.publication.cut;
        return index < cut.slot.len and cut.slot[index] == self.publication.joins.slot;
    }

    /// The entry the manifest the stored joins belong to holds at function `index`'s place, read in full: what a recomputed function's
    /// contribution is compared with. Null when the manifest holds none there, or its names do not resolve.
    pub fn oldEntry(self: *Index, index: u32) demand_ir.Error!?Entry {
        const lazy = &self.publication.lazy;
        const candidates = lazy.candidates orelse return null;
        const manifest = candidates.manifests[self.publication.joins.slot] orelse return null;
        if (index >= manifest.refs.len or manifest.refs[index].lowered == null) return null;
        const a = lazy.arena orelse return null;
        const loader = if (lazy.loader) |*known| known else return null;
        const located = (try storedAt(a, candidates.cache.?, manifest, manifest.refs[index])) orelse return null;
        const entry = try entryIn(a, candidates.cache.?, located, try loader.restorer(a, located.row.names, true));
        return entry;
    }

    /// Whether function `index`, recomputed in this build, contributed to field round `fresh.round` what the stored row at its place
    /// contributed: the same return interval, writes, call sites (the hull's input), exploration calls and address-taken functions.
    /// When every recomputed function does, each join over the program is the one the stored joins hold.
    pub fn sameAsStored(self: *Index, index: u32, fresh: Fresh) demand_ir.Error!bool {
        const old = (try self.oldEntry(index)) orelse return false;
        const saved = old.demand.fields.rounds[fresh.round] orelse return false;
        if (!std.meta.eql(saved.summary.returned, fresh.record.summary.returned)) return false;
        if (!joins_mod.sameContribution(saved.writes, fresh.record.writes)) return false;
        if (fresh.round == 1 and !joins_mod.sameCalls(saved.summary.calls, fresh.record.summary.calls)) return false;
        const history = old.demand.history orelse return false;
        const unswitched = history.outputs[2] orelse return false;
        if (!std.mem.eql(u32, unswitched.graph.calls, fresh.targets)) return false;
        return joins_mod.sameSet(self.publication.lazy.arena.?, unswitched.graph.references, fresh.references);
    }

    /// Keep the table and return intervals field round `round` left, for the joins this build publishes. Only the functions of the raw
    /// program are kept: a fusion helper has none.
    pub fn noteRound(self: *Index, a: std.mem.Allocator, round: usize, left: Left) std.mem.Allocator.Error!void {
        const raw = self.catalog.raw_count;
        const returns = try a.dupe(?facts.Interval, left.returns[0..@min(raw, left.returns.len)]);
        self.publication.joins.rounds[round] = .{ .table = .{ .digest = left.digest, .types = left.table.types }, .returns = returns };
    }

    /// Complete the joins of this build with the parameter hulls the rounds led to. A build that took the stored joins made those.
    pub fn finishJoins(self: *Index, hulls: []const []const ?facts.Interval) void {
        const joined = &self.publication.joins;
        if (joined.made != null) return;
        const first = joined.rounds[0] orelse return;
        const second = joined.rounds[1] orelse return;
        const raw = @min(self.catalog.raw_count, hulls.len);
        if (first.returns.len != raw or second.returns.len != raw) return;
        joined.made = .{ .tables = .{ first.table, second.table }, .returns = .{ first.returns, second.returns }, .hulls = hulls[0..raw] };
    }

    /// The verify mode's check of the stored joins: when every function recomputed in the field rounds contributed what its stored row held,
    /// no function may have been recomputed for its dependencies and the joins this build made are the stored ones. Counts a finding
    /// otherwise.
    pub fn verifyJoins(self: *Index) void {
        const joined = &self.publication.joins;
        const stored = joined.stored orelse return;
        if (joined.differs) return;
        const made = joined.made orelse return self.foundJoins(joined.demoted orelse 0);
        if (joined.demoted) |index| return self.foundJoins(index);
        const left = joins_mod.encode(self.publication.lazy.arena.?, stored) catch return;
        const right = joins_mod.encode(self.publication.lazy.arena.?, made) catch return;
        if (!std.mem.eql(u8, &left.digest, &right.digest)) self.foundJoins(0);
    }

    fn foundJoins(self: *Index, index: u32) void {
        self.context.statistics.restores.cutoff.findings += 1;
        self.publication.cut.found(index, @backingInt(cache.Stage.first_facts));
    }

    /// The verify mode's check of the rows a build left unread: each rest decodes, resolves and describes the checkpoints its core does, and its
    /// summary has the arity the core's flag says (`Scalars.summary_ok`). Counts a finding for the first that does not.
    pub fn verifyRows(self: *Index) demand_ir.Error!void {
        const lazy = &self.publication.lazy;
        const pool = (lazy.candidates orelse return).cache orelse return;
        const a = lazy.arena orelse return;
        const loader = if (lazy.loader) |*known| known else return;
        for (lazy.pending, 0..) |maybe, index| {
            const pending = maybe orelse continue;
            const bytes = (try restBytes(pool, pending.rest)) orelse return self.foundJoins(@intCast(index));
            var rest = (try rows.readRest(a, bytes)) orelse return self.foundJoins(@intCast(index));
            const mapper: rows.Mapper = .{ .restore = try loader.restorer(a, pending.names, pending.same_layout) };
            rows.mapRest(&rest, mapper) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Unmappable => return self.foundJoins(@intCast(index)),
            };
            var copy = self.entries[index];
            if (!rows.fill(&copy, rest)) return self.foundJoins(@intCast(index));
            const catalog = (lazy.candidates.?.manifests[pending.slot] orelse return).catalog;
            const ok = if (copy.summary) |saved| validDemandSummary(saved, self.context.source.module, catalog) else false;
            if (ok != pending.summary_ok) return self.foundJoins(@intCast(index));
        }
    }

    /// Whether the rows function `index` was found in can still be copied: its core chunk holds its row and its rest chunk is in the store.
    /// A function whose rest was read, or that was not found, has nothing to copy.
    fn rowsHeld(self: *Index, index: usize) std.mem.Allocator.Error!bool {
        const lazy = &self.publication.lazy;
        if (index >= lazy.pending.len or lazy.pending[index] == null) return true;
        const held = self.publication.held;
        const pool = held.cache orelse return false;
        if (index >= held.records.len) return false;
        const at = held.records[index] orelse return false;
        const chunk = (try pool.get(at.chunk)) orelse return false;
        return chunk.row(at.row) != null and try pool.has(chunk.rest);
    }

    /// The joins of this build as the bytes of their record, for `save`.
    fn encodedJoins(self: *const Index) std.mem.Allocator.Error!?EncodedJoins {
        const made = self.publication.joins.made orelse return null;
        const encoded = try joins_mod.encode(self.publication.lazy.arena.?, made);
        return .{ .bytes = encoded.bytes, .digest = encoded.digest };
    }

    /// Whether function `index` is red only because its text moved, and its exploration rounds and effects were taken from the
    /// entry of the same lowered body (`looseEntries`).
    pub fn isLoose(self: *const Index, index: usize) bool {
        return index < self.publication.second.loose.len and self.publication.second.loose[index];
    }

    /// Note, once the raw digest of function `index` is known, whether the function the second lookup found differs from that entry in
    /// source positions only (`Cut.noteShifted`): its raw body is that entry's, moved or not.
    pub fn noteLoose(self: *Index, index: usize) void {
        const found = self.looseFound(index) orelse return;
        const now = self.entries[index].raw;
        const same = found.raw != null and now != null and std.mem.eql(u8, &found.raw.?, &now.?);
        self.publication.cut.noteShifted(index, !same);
    }

    /// Optimizer fusions may append immutable runtime declarations.
    pub fn extend(self: *Index, a: std.mem.Allocator) demand_ir.Error!void {
        const module = self.context.source.module;
        const old_count = self.entries.len;
        const count = module.functions.items.len;
        if (count == old_count) return;
        if (count < old_count) return cache_miss.at(@src());
        const entries = try a.alloc(Entry, count);
        const green = try a.alloc(bool, count);
        const parents = try a.alloc(std.ArrayList(u32), count);
        @memcpy(entries[0..old_count], self.entries);
        @memcpy(green[0..old_count], self.green);
        @memcpy(parents[0..old_count], self.parents);
        for (module.functions.items[old_count..], entries[old_count..], green[old_count..], parents[old_count..]) |function, *entry, *reusable, *callers| {
            if (function.signature.linkage == .internal) return cache_miss.at(@src());
            entry.* = .{};
            reusable.* = true;
            callers.* = .empty;
        }
        const pending = try a.alloc(?Pending, count);
        @memset(pending, null);
        @memcpy(pending[0..old_count], self.publication.lazy.pending);
        self.publication.lazy.pending = pending;
        self.entries = entries;
        self.green = green;
        self.parents = parents;
    }

    /// Keep the raw call graph outside materialized instruction bodies.
    // twin-drift-ok: Preserve repeated edges in instruction order for optimizer DFS; test discovery deduplicates its set of callees.
    pub fn targets(a: std.mem.Allocator, function: *const @import("ir.zig").Function) std.mem.Allocator.Error![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        for (function.insts.items) |inst| {
            const target: u32 = switch (inst.op) {
                .call => @intCast(inst.a.index()),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            try out.append(a, target);
        }
        return out.items;
    }

    /// Retain physical targets in instruction order for a single call/reference kind.
    pub fn targetsOf(a: std.mem.Allocator, function: *const @import("ir.zig").Function, op: @import("ir.zig").Op) std.mem.Allocator.Error![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        for (function.insts.items) |inst| {
            if (inst.op != op) continue;
            try out.append(a, if (op == .call) @intCast(inst.a.index()) else @intCast(inst.data));
        }
        return out.items;
    }

    /// Incoming caller intervals must still match before the parameter-dependent round.
    pub fn parameters(self: *Index, a: std.mem.Allocator, values: []const []const ?facts.Interval) std.mem.Allocator.Error!void {
        var queue: std.ArrayList(u32) = .empty;
        for (self.green, self.entries, values, 0..) |*green, entry, current, index| {
            if (!green.* or equalRanges(entry.parameters, current)) continue;
            green.* = false;
            try queue.append(a, @intCast(index));
        }
        // New bounds may make a previously identity callee inline during the
        // parameter round. Its callers must visit that checkpoint in normal order.
        // Under the cutoff they do: a deferred caller that reads the callee's new checkpoint is recomputed at its turn.
        if (!self.publication.cut.active()) try invalidateCallers(a, self.parents, self.green, &queue);
    }

    /// Keep exploratory contributions after the per-function scratch is reclaimed.
    pub fn summary(self: *Index, a: std.mem.Allocator, function: usize, value: cache.Summary) std.mem.Allocator.Error!void {
        const calls = try a.dupe(cache.Call, value.calls);
        for (calls) |*call| call.ranges = try a.dupe(?facts.Interval, call.ranges);
        // A function taken from the second lookup is compared with the summary of the entry that lookup found.
        const was = self.entries[function].summary orelse if (self.looseFound(function)) |found| found.summary else null;
        self.entries[function].summary = .{ .returned = value.returned, .calls = calls };
        if (was == null or !std.meta.eql(was.?.returned, value.returned)) self.publication.cut.mark(function, cutoff.Moved.returned);
    }

    /// Record the final key and legacy identity-only eligibility for eager shortcuts.
    pub fn final(self: *Index, a: std.mem.Allocator, function: usize, values: []const ?facts.Interval, key: ?[32]u8, events: [2]u32) std.mem.Allocator.Error!void {
        const entry = &self.entries[function];
        const current = try self.context.bodyDigest(@intCast(function));
        entry.stable = events[0] == 0 and events[1] == 0 and entry.raw != null and current != null and std.mem.eql(u8, &entry.raw.?, &current.?);
        entry.parameters = try a.dupe(?facts.Interval, values);
        entry.final = key;
    }

    /// Publish the advisory index: each entry as a record of its own content, which an unchanged entry does not rewrite,
    /// and the manifest that names those records for this generation. Absent final artifacts still miss normally.
    pub fn save(self: *Index) demand_ir.Error!void {
        if (self.context.lazy.raw == null) return self.context.store.storeValue(self.publication.key, []Entry, self.entries);
        // A function recomputed after it was found is encoded in full, so its rest is read first.
        for (self.green, 0..) |deferred, index| {
            if (!deferred or !(try self.rowsHeld(index))) try self.settle(@intCast(index));
        }
        // A function this build left deferred was neither recomputed nor changed: its record is the one it was loaded from.
        var scratch = std.heap.ArenaAllocator.init(self.context.store.backing);
        defer scratch.deinit();
        const held = self.publication.held;
        const keep = try scratch.allocator().alloc(?chunks.Held, self.entries.len);
        for (keep, 0..) |*slot, index| slot.* = if (self.green[index] and index < held.records.len) held.records[index] else null;
        const modules = try scratch.allocator().alloc([]const u8, self.entries.len);
        for (modules, 0..) |*slot, index| slot.* = if (index < held.modules.len) held.modules[index] else "";
        const lineage: ?Lineage = if (held.state) |state| .{ .state = state, .project = held.project } else null;
        const published: DemandIndex = .{ .entries = self.entries, .catalog = self.catalog, .keep = keep, .unmixed = self.publication.second.unmixed, .modules = modules, .cache = held.cache, .lineage = lineage };
        try storeDemandIndexNamed(self.context.store, self.publication.key, published, .{ .context = self.context, .raw_count = @intCast(self.catalog.raw_count), .joins = try self.encodedJoins() });
    }
};

/// Write `index` under `key`, the key of its manifest: each entry as its record, then the manifest that names those records.
/// The entries are stored as they are, which a test of the manifest does; a build stores them by name (`storeDemandIndexNamed`).
pub fn storeDemandIndex(store: *const @import("stage_store.zig").Store, key: [32]u8, index: DemandIndex) std.mem.Allocator.Error!void {
    return storeDemandIndexWith(store, key, index, null);
}

/// What names the ordinals of the entries a build stores: its prepared context and the raw function count.
pub const Namer = struct { context: *cache.Context, raw_count: u32, joins: ?EncodedJoins = null };

/// The joins a build made, as the bytes of their record and the digest that names it.
pub const EncodedJoins = struct { bytes: []const u8, digest: [32]u8 };

/// `storeDemandIndex` for a build: every entry's functions, types and source files are stored by name, so the record of an
/// unchanged function is the same record after any edit elsewhere.
pub fn storeDemandIndexNamed(store: *const @import("stage_store.zig").Store, key: [32]u8, index: DemandIndex, namer: Namer) std.mem.Allocator.Error!void {
    return storeDemandIndexWith(store, key, index, namer);
}

fn storeDemandIndexWith(store: *const @import("stage_store.zig").Store, key: [32]u8, index: DemandIndex, namer: ?Namer) std.mem.Allocator.Error!void {
    var scratch = std.heap.ArenaAllocator.init(store.backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    const refs = try a.alloc(Ref, index.entries.len);
    @memset(refs, .{});
    var named: std.ArrayList([32]u8) = .empty;
    var groups: std.array_hash_map.String(std.ArrayList(Member)) = .empty;
    var own_pool = chunks.Cache{ .storage = store, .arena = a };
    const pool = index.cache orelse &own_pool;
    for (index.entries, 0..) |entry, position| {
        const lowered = entry.demand.lowered orelse continue;
        var member: Member = .{ .position = position, .lowered = lowered, .row = .{ .kept = null } };
        if (position < index.keep.len) if (index.keep[position]) |held| if (try pool.get(held.chunk)) |chunk| if (chunk.row(held.row) != null and try pool.has(chunk.rest)) {
            member.row = .{ .kept = held };
        };
        if (member.row.kept == null) {
            const encoded = (try storedRow(a, entry, namer, index.catalog)) orelse continue;
            member.row = .{ .fresh = encoded };
        }
        try named.appendSlice(a, try recordKeys(a, store, entry));
        const module = if (position < index.modules.len) index.modules[position] else "";
        const slot = try groups.getOrPut(a, module);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(a, member);
    }
    // One chunk per module, its rows in the order of the lowering keys, so the same functions make the same chunk in any tree.
    // The new chunks go out as one batch, the manifest after them, so the manifest never names a chunk that is missing.
    var saves: std.ArrayList(@import("stage_store.zig").Save) = .empty;
    var table: std.ArrayList([32]u8) = .empty;
    var rest_table: std.ArrayList([32]u8) = .empty;
    var each = groups.iterator();
    var order: std.ArrayList([]const u8) = .empty;
    while (each.next()) |group| try order.append(a, group.key_ptr.*);
    std.mem.sort([]const u8, order.items, {}, struct {
        fn before(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.before);
    for (order.items) |module| {
        const members = groups.getPtr(module).?.items;
        std.mem.sort(Member, members, {}, Member.before);
        const digests = try chunkOf(a, store, members, pool, &saves);
        const at: u32 = @intCast(table.items.len);
        try table.append(a, digests.core);
        try rest_table.append(a, digests.rest);
        for (members, 0..) |member, row| refs[member.position] = .{
            .lowered = member.lowered,
            .chunk = at,
            .row = @intCast(row),
            .unmixed = if (member.position < index.unmixed.len) index.unmixed[member.position] else null,
        };
    }
    // The manifest goes out with the chunks it names, in the same batch: as the head of the program's state when the build knows it, with
    // the generation's record only pointing at the head, and as the generation's record otherwise.
    var manifest: DemandManifest = .{ .refs = refs, .catalog = index.catalog, .chunks = table.items };
    if (namer) |found| if (found.joins) |encoded| {
        manifest.joins = encoded.digest;
        const joins_key = joins_mod.keyOf(store, encoded.digest);
        if (!(try store.contains(joins_key))) try saves.append(a, .{ .key = joins_key, .payload = encoded.bytes });
        store.need(&.{joins_key});
    };
    try queueManifest(a, store, .{ .key = key, .state = if (index.lineage) |lineage| lineage.state else null, .project = if (index.lineage) |lineage| lineage.project else null }, manifest, &saves);
    _ = try store.saveAll(saves.items);
    // The records the entries name besides their own (a final artifact and its facts, the checkpoints, the fusion body): a later build
    // that bypasses a function never loads them, and compaction keeps only the records a recent build needed.
    store.need(named.items);
    var keys = try a.alloc([32]u8, table.items.len * 2);
    for (table.items, rest_table.items, 0..) |digest, rest, at| {
        keys[2 * at] = chunks.keyOf(store, digest);
        keys[2 * at + 1] = chunks.keyOf(store, rest);
    }
    store.need(keys);
}

/// Where a manifest is published: the generation's key, the program state whose head holds it when the build knows its state, and the project
/// whose latest-state pointers name that state when the store has a shared half to publish them in.
const Destination = struct { key: [32]u8, state: ?[32]u8, project: ?[32]u8 = null };

/// Queue the records that publish `manifest` in `saves`. With a state, the head holds the manifest, unless the store holds one: the same
/// state is the same program, so the manifest it names is the one already there. Either way the build says it needs the head.
fn queueManifest(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, destination: Destination, manifest: DemandManifest, saves: *std.ArrayList(@import("stage_store.zig").Save)) std.mem.Allocator.Error!void {
    const codec = @import("selka").persist_codec;
    var pointer = codec.Writer.init(a);
    try pointer.write(Stored, .{ .state = destination.state, .manifest = if (destination.state == null) manifest else null });
    try saves.append(a, .{ .key = destination.key, .payload = pointer.bytes.items });
    const state = destination.state orelse return;
    const head = chunks.headKey(store, state);
    store.need(&.{head});
    if (!(try store.contains(head))) {
        var body = codec.Writer.init(a);
        try body.write(DemandManifest, manifest);
        try saves.append(a, .{ .key = head, .payload = body.bytes.items });
    }
    // The pointers go last: the batch is one write, and a reader that scans the journal while it is being written sees a prefix of the batch, so a
    // pointer it sees has the head and the chunks it names before it.
    try queueLatest(a, store, destination, manifest, saves);
}

/// Queue the latest-state pointers of `destination`'s project: the state this build published, under its raw layout and under any layout,
/// replacing the state a tree published before. They go out in the batch of the head and the chunks, so a pointer never names a head
/// this publication did not also make. Only a store that publishes to a shared half writes them: a work directory's own generations
/// already name its latest state.
fn queueLatest(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, destination: Destination, manifest: DemandManifest, saves: *std.ArrayList(@import("stage_store.zig").Save)) std.mem.Allocator.Error!void {
    const project = destination.project orelse return;
    const state = destination.state orelse return;
    if (!store.publishesShared()) return;
    const codec = @import("selka").persist_codec;
    var writer = codec.Writer.init(a);
    try writer.write(chunks.Latest, .{ .state = state });
    const layout = manifest.catalog.raw_layout orelse return;
    const keys = [2][32]u8{ chunks.latestKey(store, project), chunks.latestLayoutKey(store, project, layout) };
    for (keys) |key| {
        store.need(&.{key});
        try saves.append(a, .{ .key = key, .payload = writer.bytes.items });
    }
}

/// One function of a module being written into its chunk: its row is either an entry encoded now or a row of a chunk read earlier.
const Member = struct {
    position: usize,
    lowered: [32]u8,
    row: union(enum) { kept: ?chunks.Held, fresh: rows.Encoded },

    fn before(_: void, left: Member, right: Member) bool {
        const order = std.mem.order(u8, &left.lowered, &right.lowered);
        if (order != .eq) return order == .lt;
        return left.position < right.position;
    }
};

/// The two chunks that hold `members`' rows: the digest of the core chunk (which names the rest chunk) and of the rest chunk. A group no
/// function of which changed keeps its chunks without framing or hashing them; any other group's are framed from the rows (copied from the
/// chunks read, or encoded just now) and queued in `saves` unless the store holds them already.
fn chunkOf(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, members: []const Member, pool: *chunks.Cache, saves: *std.ArrayList(@import("stage_store.zig").Save)) std.mem.Allocator.Error!ChunkPair {
    if (try unchanged(members, pool)) |digest| return .{ .core = digest, .rest = (try pool.get(digest)).?.rest };
    const cores = try a.alloc([]const u8, members.len);
    const rests = try a.alloc([]const u8, members.len);
    for (members, cores, rests) |member, *core, *rest| switch (member.row) {
        .fresh => |encoded| {
            core.* = encoded.core;
            rest.* = encoded.rest;
        },
        .kept => |held| {
            const chunk = (try pool.get(held.?.chunk)).?;
            core.* = chunk.row(held.?.row).?;
            rest.* = (try pool.get(chunk.rest)).?.row(held.?.row).?;
        },
    };
    const rest_bytes = try chunks.frame(a, rests, @splat(0));
    const rest_digest = chunks.digestOf(rest_bytes);
    const rest_key = chunks.keyOf(store, rest_digest);
    if (!(try store.contains(rest_key))) try saves.append(a, .{ .key = rest_key, .payload = rest_bytes });
    const bytes = try chunks.frame(a, cores, rest_digest);
    const digest = chunks.digestOf(bytes);
    const stored = chunks.keyOf(store, digest);
    if (!(try store.contains(stored))) try saves.append(a, .{ .key = stored, .payload = bytes });
    return .{ .core = digest, .rest = rest_digest };
}

/// The digests of a group's core chunk and rest chunk.
const ChunkPair = struct { core: [32]u8, rest: [32]u8 };

/// The chunk every one of `members` was read from, when they are all of its rows in its order.
fn unchanged(members: []const Member, pool: *chunks.Cache) std.mem.Allocator.Error!?[32]u8 {
    if (members.len == 0) return null;
    const first = switch (members[0].row) {
        .kept => |held| held orelse return null,
        .fresh => return null,
    };
    for (members, 0..) |member, row| {
        const held = switch (member.row) {
            .kept => |known| known orelse return null,
            .fresh => return null,
        };
        if (held.row != row or !std.mem.eql(u8, &held.chunk, &first.chunk)) return null;
    }
    const chunk = (try pool.get(first.chunk)) orelse return null;
    return if (chunk.count == members.len) first.chunk else null;
}

/// `entry` as a record stores it, or null when something it refers to cannot be named (the function then has no record and
/// the next build computes it).
fn storedRow(a: std.mem.Allocator, entry: Entry, namer: ?Namer, catalog: fusion.Catalog) std.mem.Allocator.Error!?rows.Encoded {
    const found = namer orelse {
        const plain = try rows.encode(a, .{ .core = rows.coreOf(entry, true), .names = .{} }, rows.restOf(entry));
        return plain;
    };
    const module = found.context.source.module;
    const summary_ok = if (entry.summary) |summary| validDemandSummary(summary, module, catalog) else false;
    var interner: names.Interner = .{ .a = a, .canons = found.context.canons(), .source = found.context.source };
    var copy = try cloneEntry(a, entry);
    mapEntry(&copy, .{ .capture = .{ .interner = &interner, .raw_count = found.raw_count } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unmappable => return null,
    };
    const bytes = try rows.encode(a, .{ .core = rows.coreOf(copy, summary_ok), .names = interner.names() }, rows.restOf(copy));
    return bytes;
}

/// The keys of the stored records one entry names: its lowering key, its final record, its checkpoints and its fusion body.
fn recordKeys(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, entry: Entry) std.mem.Allocator.Error![]const [32]u8 {
    var keys: std.ArrayList([32]u8) = .empty;
    if (entry.demand.lowered) |key| try keys.append(a, key);
    if (entry.final) |key| try keys.append(a, key);
    if (entry.demand.fusion.key) |key| try keys.append(a, key);
    // The final body's metadata names its record and, apart from it, the fact payload it restores with (`Context.loadFacts`).
    if (entry.demand.metadata) |metadata| {
        try keys.append(a, metadata.key);
        try keys.append(a, cache.factsRecordKey(store, metadata.analysis.digest));
    }
    if (entry.demand.history) |history| for (history.outputs) |output| if (output) |checkpoint| try keys.append(a, checkpoint.key);
    return keys.items;
}

/// The scope of the manifests of one entry and flags. The entries they name are rows of chunks (`optimizer_chunks.zig`).
pub const manifest_scope = "optimizer-manifest-v10";

/// One function's name in a manifest: the lowering key it was built under, and where its entry stands, as a row of one of the
/// manifest's chunks. A function without a lowering key has no record, since no later build can reuse it.
const Ref = struct { lowered: ?[32]u8 = null, chunk: u32 = 0, row: u32 = 0, unmixed: ?[32]u8 = null };

/// One generation's demand state: a reference per function, indexed like the module, the digests of the chunks the references
/// point into, and the post-fusion declaration proof.
pub const DemandManifest = struct {
    refs: []const Ref,
    catalog: fusion.Catalog,
    chunks: []const [32]u8 = &.{},
    /// The digest of the joins record of the state (`optimizer_joins.zig`), when the build that wrote the manifest made them.
    joins: ?[32]u8 = null,
};

/// What a generation's manifest record holds: the state whose head holds the manifest (a build that knows its state publishes the
/// manifest once, as the head, and this record only points at it), or the manifest itself.
const Stored = struct { state: ?[32]u8 = null, manifest: ?DemandManifest = null };

/// The manifest the record at `key` holds or points to, or null when the record or its head is missing.
pub fn loadManifest(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, key: [32]u8) std.mem.Allocator.Error!?DemandManifest {
    const stored = try store.loadValue(a, key, Stored) orelse return null;
    if (stored.manifest) |manifest| return manifest;
    const state = stored.state orelse return null;
    return store.loadValue(a, chunks.headKey(store, state), DemandManifest);
}

/// Store `manifest` itself as the record at `key`, as a build that does not know its program state does (a test replaces a manifest with it).
pub fn storeManifest(store: *const @import("stage_store.zig").Store, key: [32]u8, manifest: DemandManifest) std.mem.Allocator.Error!void {
    try store.storeValue(key, Stored, .{ .manifest = manifest });
}

/// The whole demand index a manifest names: every entry loaded from its chunk, and the catalog. Lookups read one entry at a
/// time; tests and diagnostics read them all (`loadDemandIndex`). `keep` says where each function's entry was loaded from, so that
/// a function left alone is not encoded again, and `modules` which module each function belongs to, the unit of a chunk.
pub const DemandIndex = struct {
    entries: []Entry,
    catalog: fusion.Catalog,
    keep: []const ?chunks.Held = &.{},
    unmixed: []const ?[32]u8 = &.{},
    modules: []const []const u8 = &.{},
    cache: ?*chunks.Cache = null,
    /// Where the manifest stands among the program states (`chunks.headKey`), when the build knows its state.
    lineage: ?Lineage = null,
};

/// The program state a manifest is also published for, and the project whose latest-state pointers (`chunks.latestKey`) name that state, when
/// the store has a shared half to publish them in.
pub const Lineage = struct { state: [32]u8, project: ?[32]u8 = null };

/// A row read from its chunk: the core decoded, and where its rest stands.
const Located = struct { row: rows.View, rest: RestAt };

/// The row stored at `ref` in `manifest`, its core decoded, or null when its chunk or its row are missing or malformed.
fn storedAt(a: std.mem.Allocator, pool: *chunks.Cache, manifest: DemandManifest, ref: Ref) std.mem.Allocator.Error!?Located {
    if (ref.chunk >= manifest.chunks.len) return null;
    const chunk = (try pool.get(manifest.chunks[ref.chunk])) orelse return null;
    const bytes = chunk.row(ref.row) orelse return null;
    const row = (try rows.view(a, bytes)) orelse return null;
    return .{ .row = row, .rest = .{ .chunk = chunk.rest, .row = ref.row } };
}

/// The bytes of the rest row at `at`, or null when its chunk is missing or has no such row.
fn restBytes(pool: *chunks.Cache, at: RestAt) std.mem.Allocator.Error!?[]const u8 {
    const chunk = (try pool.get(at.chunk)) orelse return null;
    return chunk.row(at.row);
}

/// The entry of a row read in full: the core and the rest decoded and, when `restore` is given, their names resolved.
fn entryIn(a: std.mem.Allocator, pool: *chunks.Cache, located: Located, restore: ?rows.Restorer) std.mem.Allocator.Error!?Entry {
    var core = located.row.core;
    const bytes = (try restBytes(pool, located.rest)) orelse return null;
    var rest = (try rows.readRest(a, bytes)) orelse return null;
    if (restore) |resolving| {
        const mapper: rows.Mapper = .{ .restore = resolving };
        rows.mapCore(&core, mapper) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unmappable => return null,
        };
        rows.mapRest(&rest, mapper) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unmappable => return null,
        };
    }
    var entry = rows.entryOf(core);
    if (!rows.fill(&entry, rest)) return null;
    return entry;
}

/// The demand index of `parts` under the store's read generation, or null when no manifest or chunk of it is stored.
pub fn loadDemandIndex(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, parts: []const []const u8) std.mem.Allocator.Error!?DemandIndex {
    const manifest = try loadManifest(a, store, store.keyAt(manifest_scope, parts, store.generations.read)) orelse return null;
    const entries = try a.alloc(Entry, manifest.refs.len);
    const pool = try a.create(chunks.Cache);
    pool.* = .{ .storage = store, .arena = a };
    for (manifest.refs, entries) |ref, *entry| {
        if (ref.lowered == null) {
            entry.* = .{};
            continue;
        }
        const row = (try storedAt(a, pool, manifest, ref)) orelse return null;
        entry.* = (try entryIn(a, pool, row, null)) orelse return null;
    }
    return .{ .entries = entries, .catalog = manifest.catalog };
}

/// The key of the manifest of `parts` under the store's read generation.
pub fn manifestKey(store: *const @import("stage_store.zig").Store, parts: []const []const u8) [32]u8 {
    return store.keyAt(manifest_scope, parts, store.generations.read);
}

/// The chunk group of each function: its module, cut into `chunks.bucketsFor` chunks by a hash of its name when the module is large.
/// The names are copied: they outlive neither the functions nor their sources.
fn chunkGroups(a: std.mem.Allocator, functions: []const ir.Function) std.mem.Allocator.Error![]const []const u8 {
    var sizes: std.StringHashMapUnmanaged(usize) = .empty;
    for (functions) |function| {
        const slot = try sizes.getOrPut(a, chunks.moduleOf(function.name));
        slot.value_ptr.* = if (slot.found_existing) slot.value_ptr.* + 1 else 1;
    }
    const groups = try a.alloc([]const u8, functions.len);
    for (functions, groups) |function, *group| {
        const module = chunks.moduleOf(function.name);
        const buckets = chunks.bucketsFor(sizes.get(module).?);
        group.* = if (buckets == 1) try a.dupe(u8, module) else try std.fmt.allocPrint(a, "{s}#{d}", .{ module, chunks.bucketOf(function.name, buckets) });
    }
    return groups;
}

/// The program a build optimizes, as far as the manifests it looks for are concerned: its raw layout, the digest of its state and, when the
/// store has a shared half, the project it belongs to, which names the pointers to the latest state published for it.
const Program = struct { raw_layout: [32]u8, state: ?[32]u8 = null, project: ?[32]u8 = null };

/// The identity of the project a build belongs to (`chunks.ProjectId`), or null when the stage store has no shared half to read or publish
/// latest-state pointers in, or the build has no source to name it by.
fn projectOf(store: *const @import("stage_store.zig").Store, maybe: ?@import("selka").source.Source, mode: u8) ?[32]u8 {
    if (!store.readsShared()) return null;
    const source = maybe orelse return null;
    var id = chunks.ProjectId.init(mode, source.keyPath());
    for (source.origins) |origin| id.module(origin.original.keyPath());
    return id.final();
}

/// The manifests a build's lookups consult: the read generation's and the last full build's (generation 0 is absent here).
const Candidates = struct {
    /// The read generation's, the last full build's and, when neither was stored for this program, the head of its state.
    manifests: [3]?DemandManifest = .{ null, null, null },
    /// Whether each manifest was stored under this build's raw layout (`ir_snapshot.layout` before fusion).
    matching: [3]bool = .{ false, false, false },
    /// Each manifest's functions by lowering key: where the function stood in the program the manifest was stored for.
    positions: [3]std.AutoHashMapUnmanaged([32]u8, u32) = .{ .empty, .empty, .empty },
    /// The same by the lowering key without the source proof (`Ref.unmixed`); `ambiguous_position` where two functions share one.
    plain_positions: [3]std.AutoHashMapUnmanaged([32]u8, u32) = .{ .empty, .empty, .empty },
    /// The store the head's entries are checked against: a head another tree published names records this tree may not hold.
    storage: ?*const @import("stage_store.zig").Store = null,
    /// The chunks the manifests name, read as the lookups reach them.
    cache: ?*chunks.Cache = null,

    /// Load the manifests `parts` names under the read generation and, when it differs, the last full build's. When one was
    /// stored under this raw layout only those are candidates, and they are used as they always were: an entry at the position
    /// its lowering key names, with its catalog. When none was, every one is a candidate for the entries that can move: a
    /// function whose fusions requested no helper and left its body as lowering built it, found by its lowering key.
    fn load(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, parts: []const []const u8, program: Program) std.mem.Allocator.Error!Candidates {
        const generations = store.generations;
        const raw_layout = program.raw_layout;
        var result: Candidates = .{ .storage = store };
        result.cache = try a.create(chunks.Cache);
        result.cache.?.* = .{ .storage = store, .arena = a };
        result.manifests[0] = try loadManifest(a, store, store.keyAt(manifest_scope, parts, generations.read));
        if (generations.last != generations.read) result.manifests[1] = try loadManifest(a, store, store.keyAt(manifest_scope, parts, generations.last));
        var stored_here = false;
        for (result.manifests, &result.matching) |maybe, *same| {
            const manifest = maybe orelse continue;
            const stored = manifest.catalog.raw_layout orelse continue;
            same.* = std.mem.eql(u8, &stored, &raw_layout);
            stored_here = stored_here or same.*;
        }
        // Neither generation was stored for this program: the head of its state is the manifest of the same program, whichever tree
        // built it (the tree before an edit that was undone, or another worktree of the project).
        if (!stored_here) if (program.state) |state| {
            const head = try store.loadValue(a, chunks.headKey(store, state), DemandManifest);
            if (head) |found| if (found.catalog.raw_layout) |stored| if (std.mem.eql(u8, &stored, &raw_layout)) {
                result.manifests[head_slot] = found;
                result.matching[head_slot] = true;
                stored_here = true;
            };
        };
        // The state of this build is one no tree has published (an edit moved it): start from the nearest state some tree did, the one a
        // shared pointer names. First the latest state under this raw layout, then, for a tree that has no manifest at all, the latest of
        // the project under any layout. The pointer is a hint: the head it names is checked like any other, and every entry it holds is
        // served or refused by its own key, so a pointer that is stale, foreign or dangling costs the reuse and nothing else.
        if (!stored_here) if (program.project) |project| {
            if (try latestHead(a, store, chunks.latestLayoutKey(store, project, raw_layout), program.state)) |found| if (found.catalog.raw_layout) |stored| if (std.mem.eql(u8, &stored, &raw_layout)) {
                result.manifests[head_slot] = found;
                result.matching[head_slot] = true;
                stored_here = true;
            };
            if (!stored_here and result.manifests[0] == null and result.manifests[1] == null) {
                if (try latestHead(a, store, chunks.latestKey(store, project), program.state)) |found| if (found.catalog.raw_layout) |stored| {
                    result.manifests[head_slot] = found;
                    result.matching[head_slot] = std.mem.eql(u8, &stored, &raw_layout);
                    stored_here = result.matching[head_slot];
                };
            }
        };
        for (&result.manifests, result.matching, &result.positions, &result.plain_positions) |*maybe, same, *positions, *plain| {
            const manifest = maybe.* orelse continue;
            if (stored_here and !same) {
                maybe.* = null;
                continue;
            }
            for (manifest.refs, 0..) |ref, position| if (ref.lowered) |lowered| {
                try positions.put(a, lowered, @intCast(position));
                const unmixed = ref.unmixed orelse continue;
                const slot = try plain.getOrPut(a, unmixed);
                slot.value_ptr.* = if (slot.found_existing) ambiguous_position else @intCast(position);
            };
        }
        return result;
    }

    /// The head of the state the pointer at `key` names, or null when there is no pointer, it names the state `own` (whose head the caller
    /// asked for), or its head is missing, torn or not a manifest. Nothing else of the pointer is trusted.
    fn latestHead(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, key: [32]u8, own: ?[32]u8) std.mem.Allocator.Error!?DemandManifest {
        const latest = try store.loadValue(a, key, chunks.Latest) orelse return null;
        if (own) |state| if (std.mem.eql(u8, &latest.state, &state)) return null;
        return store.loadValue(a, chunks.headKey(store, latest.state), DemandManifest);
    }

    /// The entry of function `index` under `lowered`, with the catalog of the manifest it came from. The first candidate
    /// whose own key matches wins; a record that fails to load, or whose names do not resolve in this build, is a miss. Under
    /// the stored raw layout the entry must stand where the function stands now.
    fn find(self: Candidates, a: std.mem.Allocator, loader: ?*const Loader, request: FindRequest) std.mem.Allocator.Error!?Found {
        for (self.manifests, self.matching, self.positions, 0..) |maybe, same, positions, slot| {
            const manifest = maybe orelse continue;
            const position = positions.get(request.lowered) orelse continue;
            if (same and (position != request.index or manifest.refs.len < request.count)) continue;
            const located = try storedAt(a, self.cache.?, manifest, manifest.refs[position]) orelse continue;
            const row = located.row;
            const kept = row.core.scalars.lowered orelse continue;
            if (!std.mem.eql(u8, &kept, &request.lowered)) continue;
            if (!same) {
                // Another layout moves every fusion helper: only a function that neither requested one nor changed its body may be reused.
                if (position >= manifest.catalog.requests.len or manifest.catalog.requests[position].len != 0) continue;
                if (!row.core.fusion.identity) continue;
            }
            const catalog_of: fusion.Catalog = if (same) manifest.catalog else .{ .raw_count = request.count };
            var found: Found = .{ .entry = undefined, .catalog = manifest.catalog, .same_layout = same, .record = heldAt(manifest, manifest.refs[position]), .slot = @intCast(slot), .summary_ok = row.core.scalars.summary_ok };
            if (request.lazy and same and loader != null) {
                // Only the core is read and resolved now; `Index.settle` reads the rest when something asks for it.
                if (!(try self.cache.?.has(located.rest.chunk))) continue;
                var core = row.core;
                rows.mapCore(&core, .{ .restore = try loader.?.restorer(a, row.names, same) }) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Unmappable => continue,
                };
                found.entry = rows.entryOf(core);
                found.pending = .{ .rest = located.rest, .names = row.names, .same_layout = same, .summary_ok = row.core.scalars.summary_ok, .slot = @intCast(slot) };
            } else {
                found.entry = (try entryIn(a, self.cache.?, located, if (loader) |resolving| try resolving.restorer(a, row.names, same) else null)) orelse continue;
                found.summary_ok = if (found.entry.summary) |summary| validDemandSummary(summary, request.module, catalog_of) else false;
            }
            if (slot == head_slot and !(try self.recordsPresent(a, found.entry))) continue;
            return found;
        }
        return null;
    }

    /// Whether the store holds every record `entry` names that the optimizer wrote (its final, fact payload, fusion body and
    /// checkpoints): a head that another tree published says the function was optimized there, not that this tree can restore it.
    fn recordsPresent(self: Candidates, a: std.mem.Allocator, entry: Entry) std.mem.Allocator.Error!bool {
        const storage = self.storage orelse return false;
        for (try recordKeys(a, storage, entry)) |key| {
            if (entry.demand.lowered) |lowered| if (std.mem.eql(u8, &key, &lowered)) continue;
            if (!(try storage.contains(key))) return false;
        }
        return true;
    }

    /// The entry of function `index` found by its lowering key without the source proof, which a line shifted above the function
    /// leaves as it was and a change to its body does not (G3p-0). Only under the raw layout the manifest was stored under, so
    /// that the function stands where it stood and the passes visit it in the same order. The caller keeps from the entry what
    /// no position enters, never the entry itself.
    fn findLoose(self: Candidates, a: std.mem.Allocator, loader: ?*const Loader, request: struct { count: usize, index: usize, unmixed: [32]u8 }) std.mem.Allocator.Error!?Found {
        for (self.manifests, self.matching, self.plain_positions, 0..) |maybe, same, positions, slot| {
            const manifest = maybe orelse continue;
            if (!same) continue;
            const position = positions.get(request.unmixed) orelse continue;
            if (position == ambiguous_position or position != request.index or manifest.refs.len < request.count) continue;
            const located = try storedAt(a, self.cache.?, manifest, manifest.refs[position]) orelse continue;
            const entry = (try entryIn(a, self.cache.?, located, if (loader) |resolving| try resolving.restorer(a, located.row.names, true) else null)) orelse continue;
            return .{ .entry = entry, .catalog = manifest.catalog, .same_layout = true, .record = heldAt(manifest, manifest.refs[position]), .slot = @intCast(slot), .summary_ok = located.row.core.scalars.summary_ok };
        }
        return null;
    }

    /// Whether `findLoose` could find function `index` under `unmixed`: a manifest stored under this raw layout holds that key at
    /// that position. No record is read, so a function the answer rules out costs nothing.
    fn holdsLoose(self: Candidates, request: struct { count: usize, index: usize, unmixed: [32]u8 }) bool {
        for (self.manifests, self.matching, self.plain_positions) |maybe, same, positions| {
            const manifest = maybe orelse continue;
            if (!same) continue;
            const position = positions.get(request.unmixed) orelse continue;
            if (position == ambiguous_position or position != request.index or manifest.refs.len < request.count) continue;
            return true;
        }
        return false;
    }

    /// Whether any manifest is a candidate.
    fn any(self: Candidates) bool {
        return self.manifests[0] != null or self.manifests[1] != null or self.manifests[head_slot] != null;
    }

    /// The catalog of the first manifest stored under this raw layout, or the empty catalog of a build that has none (one that
    /// seeds no helper declaration).
    fn catalog(self: Candidates, count: usize) fusion.Catalog {
        for (self.manifests, self.matching) |maybe, same| if (same) if (maybe) |manifest| return manifest.catalog;
        return .{ .raw_count = count };
    }
};

/// The slot of `Candidates.manifests` the head of the program state takes.
const head_slot = 2;

/// Marks a lowering key two functions of one manifest share, which the second lookup does not resolve.
const ambiguous_position: u32 = std.math.maxInt(u32);

/// An entry a lookup found, with the catalog its manifest carries and whether that manifest was stored under this raw layout.
const Found = struct {
    entry: Entry,
    catalog: fusion.Catalog,
    same_layout: bool,
    record: chunks.Held,
    slot: u8 = cutoff.Cut.slot_none,
    /// The entry's rest, when it was not read (`Index.settle`).
    pending: ?Pending = null,
    /// Whether the entry's summary is present and has the arity of its callees (`reusableEntry`).
    summary_ok: bool = false,
};

/// What `Candidates.find` looks one function up by: the program's size, the function's place, lowering key and module, and whether a
/// row found may be read in two parts.
const FindRequest = struct { count: usize, index: usize, lowered: [32]u8, module: *const ir.Module, lazy: bool };

/// Where `ref` stands: its chunk's digest and its row.
fn heldAt(manifest: DemandManifest, ref: Ref) chunks.Held {
    return .{ .chunk = manifest.chunks[ref.chunk], .row = ref.row };
}

/// How one build's demand shortcut is prepared.
pub const DemandOptions = struct {
    mode: u8,
    /// Whether record field summaries come from the post-fusion proof.
    field_proof: bool,
    /// Declarations whose callers' raw bodies must be loaded (the split family).
    eager_callees: []const bool = &.{},
    /// How the functions a recomputed one reaches are decided (`optimizer_cutoff.zig`).
    cutoff: cutoff.Mode = .transitive,
};

fn callsAny(calls: []const u32, marks: []const bool) bool {
    for (calls) |target| if (target < marks.len and marks[target]) return true;
    return false;
}

/// What `looseEntries` looks entries up with.
const LooseLookup = struct { candidates: Candidates, loader: ?*const Loader, context: *cache.Context, options: DemandOptions };
/// The tables of the build `looseEntries` extends: entries, the green mask and the callers of each function.
const DemandTables = struct { entries: []Entry, green: []const bool, parents: []const std.ArrayList(u32) };

/// A function that is red only because the text above it moved has the lowering key it had, without the source proof of its
/// position (G3p-0). Its exploration rounds, its parameter hull and its effects are functions of its body and of what its callees
/// return, which that key and the callees' own keys fix, and no position enters them. For every red function that second lookup
/// finds, the rounds, the effect and the hull of the entry found are put in the function's entry (every build overwrites them with
/// its own, which are the same), and the function is marked. A marked function whose callee is neither deferred nor marked is
/// unmarked, and so on through its callers: the passes may use an entry's rounds and effect only when the body and everything it
/// reads are the ones the entry saw. Returns the mask.
fn looseEntries(a: std.mem.Allocator, lookup: LooseLookup, tables: DemandTables) demand_ir.Error!Second {
    const context = lookup.context;
    const module = context.source.module;
    const count = module.functions.items.len;
    const marked = try a.alloc(bool, count);
    @memset(marked, false);
    const details = try a.alloc(?Loose, count);
    @memset(details, null);
    const unmixed = context.lazy.raw.?.unmixed;
    if (unmixed.len < count or !lookup.candidates.any()) return .{ .loose = marked, .found = details };
    // Without reading a record: a red function no manifest holds under its key will be recomputed, and so will every function
    // that calls it. Only the others are looked up.
    const possible = try a.alloc(bool, count);
    @memset(possible, false);
    var doomed: std.ArrayList(u32) = .empty;
    for (module.functions.items, tables.green, possible, 0..) |function, deferred, *can, index| {
        if (deferred or function.signature.linkage != .internal) continue;
        can.* = if (unmixed[index]) |plain_key| lookup.candidates.holdsLoose(.{ .count = count, .index = index, .unmixed = plain_key }) else false;
        if (!can.*) try doomed.append(a, @intCast(index));
    }
    var reach: usize = 0;
    while (reach < doomed.items.len) : (reach += 1) {
        for (tables.parents[doomed.items[reach]].items) |caller| {
            if (!possible[caller]) continue;
            possible[caller] = false;
            try doomed.append(a, caller);
        }
    }
    var any_marked = false;
    for (module.functions.items, tables.entries, possible, marked, 0..) |function, *entry, can, *taken, index| {
        if (!can or function.signature.linkage != .internal) continue;
        const plain_key = unmixed[index] orelse continue;
        const found = (try lookup.candidates.findLoose(a, lookup.loader, .{ .count = count, .index = index, .unmixed = plain_key })) orelse continue;
        const old = found.entry;
        const summary_ok = if (old.summary) |summary| validDemandSummary(summary, module, found.catalog) else false;
        const complete = reusableEntry(old, module, index, summary_ok) and (lookup.options.field_proof or old.summary_input != null) and
            !callsAny(old.demand.graph.calls, lookup.options.eager_callees);
        if (!complete) continue;
        entry.demand.fields.rounds = old.demand.fields.rounds;
        entry.demand.effect = old.demand.effect;
        entry.parameters = old.parameters;
        details[index] = .{
            .slot = found.slot,
            .raw = old.raw,
            .history = old.demand.history,
            .summary = old.summary,
            .emission = if (old.demand.metadata) |metadata| metadata.emission_effect else null,
        };
        taken.* = true;
        any_marked = true;
    }
    if (!any_marked) return .{ .loose = marked, .found = details };
    // Close the mask: a callee that must be recomputed (red and not marked) unmarks its callers.
    var queue: std.ArrayList(u32) = .empty;
    for (tables.green, marked, 0..) |deferred, taken, index| if (!deferred and !taken) try queue.append(a, @intCast(index));
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        for (tables.parents[queue.items[cursor]].items) |caller| {
            if (!marked[caller]) continue;
            marked[caller] = false;
            tables.entries[caller].demand.fields.rounds = .{ null, null };
            tables.entries[caller].demand.effect = null;
            tables.entries[caller].parameters = &.{};
            try queue.append(a, caller);
        }
    }
    return .{ .loose = marked, .found = details };
}

/// Whether an entry found for function `index` can stay deferred: its fusion, checkpoints, final key, effect and final metadata are
/// all present, and so is its summary (`summary_ok`).
fn reusableEntry(entry: Entry, module: *const @import("ir.zig").Module, index: usize, summary_ok: bool) bool {
    if (!entry.demand.fusion.identity and entry.demand.fusion.key == null) return false;
    const history = entry.demand.history orelse return false;
    for (history.outputs) |checkpoint| if (checkpoint == null) return false;
    if (entry.raw == null or entry.final == null) return false;
    if (!summary_ok) return false;
    const effect = entry.demand.effect orelse return false;
    if (effect.params.len != module.functions.items[index].signature.params.len) return false;
    const metadata = entry.demand.metadata orelse return false;
    return metadata.emission_effect != null;
}

/// Whether two parameter hulls are the same intervals.
pub fn equalRanges(left: []const ?facts.Interval, right: []const ?facts.Interval) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn invalidateCallers(a: std.mem.Allocator, parents: []const std.ArrayList(u32), green: []bool, queue: *std.ArrayList(u32)) std.mem.Allocator.Error!void {
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        for (parents[queue.items[cursor]].items) |caller| {
            if (!green[caller]) continue;
            green[caller] = false;
            try queue.append(a, caller);
        }
    }
}

fn invalidateCycles(a: std.mem.Allocator, parents: []const std.ArrayList(u32), green: []bool, queue: *std.ArrayList(u32)) std.mem.Allocator.Error!void {
    const colors = try a.alloc(enum { new, open, done }, parents.len);
    @memset(colors, .new);
    var stack: std.ArrayList(struct { function: u32, next: usize = 0 }) = .empty;
    for (0..parents.len) |root| {
        if (colors[root] != .new) continue;
        colors[root] = .open;
        try stack.append(a, .{ .function = @intCast(root) });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const edges = parents[top.function].items;
            if (top.next == edges.len) {
                colors[top.function] = .done;
                _ = stack.pop();
                continue;
            }
            const target = edges[top.next];
            top.next += 1;
            if (colors[target] == .done) continue;
            if (colors[target] == .new) {
                colors[target] = .open;
                try stack.append(a, .{ .function = target });
                continue;
            }
            // Exploratory recursion breaks cycles at DFS entry. A changed upstream
            // caller can move that entry even while the recursive raw bodies match.
            var inside = false;
            for (stack.items) |frame| {
                if (frame.function == target) inside = true;
                if (!inside or !green[frame.function]) continue;
                green[frame.function] = false;
                try queue.append(a, frame.function);
            }
        }
    }
}

fn validDemandSummary(summary: cache.Summary, module: *const @import("ir.zig").Module, catalog: fusion.Catalog) bool {
    for (summary.calls) |call| {
        const arity = if (call.callee < module.functions.items.len)
            module.functions.items[call.callee].signature.params.len
        else blk: {
            if (catalog.raw_count != module.functions.items.len) return false;
            const helper = call.callee - catalog.raw_count;
            if (helper >= catalog.declarations.len) return false;
            break :blk catalog.declarations[helper].signature.params.len;
        };
        if (call.ranges.len != arity) return false;
    }
    return true;
}

/// A lookup of function `index` in a program of `count` functions, read in full, for a test whose entries have no summary to check.
fn probeFor(count: usize, index: usize, lowered: [32]u8) FindRequest {
    const unused: *const ir.Module = undefined;
    return .{ .count = count, .index = index, .lowered = lowered, .module = unused, .lazy = false };
}

fn testDigest(n: u8) [32]u8 {
    var digest: [32]u8 = @splat(0);
    digest[0] = n;
    return digest;
}

test "a fusion helper reference of an entry resolves to its position after the raw functions only under the layout it was stored under" {
    var calls = [_]u32{rows.helper_flag | 1};
    var entry: Entry = .{};
    entry.demand.graph.calls = &calls;
    const moved: rows.Mapper = .{ .restore = .{ .resolver = undefined, .raw_count = 10, .same_layout = false } };
    try std.testing.expectError(error.Unmappable, mapEntry(&entry, moved));
    try std.testing.expectEqual(rows.helper_flag | 1, calls[0]);
    const same: rows.Mapper = .{ .restore = .{ .resolver = undefined, .raw_count = 10, .same_layout = true } };
    try mapEntry(&entry, same);
    try std.testing.expectEqual(@as(u32, 11), calls[0]);
}

/// Entries 1 to n with a lowering key each, spread over four modules.
fn spreadOverModules(entries: []Entry, modules: [][]const u8) void {
    const module_names = [_][]const u8{ "a.selka", "b.selka", "c.selka", "d.selka" };
    for (entries, modules, 0..) |*entry, *module, index| {
        entry.* = .{ .demand = .{ .lowered = testDigest(@intCast(index + 1)) } };
        module.* = module_names[index % 4];
    }
}

/// How many of two chunk tables' digests differ.
fn differing(left: []const [32]u8, right: []const [32]u8) usize {
    var count: usize = 0;
    for (left, right) |was, is| count += @intFromBool(!std.mem.eql(u8, &was, &is));
    return count;
}

test "a demand index writes only the chunks of the modules that changed, and its manifest names them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const parts: []const []const u8 = &.{ "app", &.{0} };
    var entries: [64]Entry = undefined;
    var modules: [64][]const u8 = undefined;
    spreadOverModules(&entries, &modules);
    try storeDemandIndex(&storage, manifestKey(&storage, parts), .{ .entries = &entries, .catalog = .{}, .modules = &modules });
    // Four core chunks, their four rest chunks and the manifest.
    const written = storage.statistics().publication.records_saved;
    try std.testing.expectEqual(@as(u64, 9), written);
    const first = (try loadManifest(a, &storage, manifestKey(&storage, parts))).?;
    try std.testing.expectEqual(@as(usize, 4), first.chunks.len);
    // The same entries again write the manifest alone: a chunk is the digest of its bytes, which are the same.
    try storeDemandIndex(&storage, manifestKey(&storage, parts), .{ .entries = &entries, .catalog = .{}, .modules = &modules });
    try std.testing.expectEqual(written + 1, storage.statistics().publication.records_saved);
    entries[7].demand.graph.calls = &.{3};
    try storeDemandIndex(&storage, manifestKey(&storage, parts), .{ .entries = &entries, .catalog = .{}, .modules = &modules });
    // Only the changed entry's module has another core chunk (its rest rows are the same), and the new manifest is written.
    try std.testing.expectEqual(written + 3, storage.statistics().publication.records_saved);
    const second = (try loadManifest(a, &storage, manifestKey(&storage, parts))).?;
    try std.testing.expectEqual(@as(usize, 1), differing(first.chunks, second.chunks));
    const loaded = (try loadDemandIndex(a, &storage, parts)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 64), loaded.entries.len);
    try std.testing.expectEqualSlices(u32, &.{3}, loaded.entries[7].demand.graph.calls);
    try std.testing.expectEqual(testDigest(8), loaded.entries[7].demand.lowered.?);
}

test "an entry the index is told to keep is not captured again: its row is copied from the chunk it was loaded from" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const parts: []const []const u8 = &.{ "app", &.{0} };
    var entries: [4]Entry = undefined;
    for (&entries, 0..) |*entry, index| entry.* = .{ .demand = .{ .lowered = testDigest(@intCast(index + 1)) } };
    try storeDemandIndex(&storage, manifestKey(&storage, parts), .{ .entries = &entries, .catalog = .{} });
    const first = (try loadManifest(a, &storage, manifestKey(&storage, parts))).?;
    try std.testing.expectEqual(@as(usize, 1), first.chunks.len);
    // Entry 2 differs in memory from the row it came from; told to keep it, the index copies the old row and encodes none.
    entries[2].demand.graph.calls = &.{9};
    const held: chunks.Held = .{ .chunk = first.chunks[first.refs[2].chunk], .row = first.refs[2].row };
    const keep: [4]?chunks.Held = .{ null, null, held, null };
    const written = storage.statistics().publication.records_saved;
    try storeDemandIndex(&storage, storage.keyAt(manifest_scope, parts, 5), .{ .entries = &entries, .catalog = .{}, .keep = &keep });
    // The chunk is the one it was: the same rows in the same order, so only the manifest is written.
    try std.testing.expectEqual(written + 1, storage.statistics().publication.records_saved);
    const second = (try loadManifest(a, &storage, storage.keyAt(manifest_scope, parts, 5))).?;
    try std.testing.expectEqual(first.chunks[0], second.chunks[0]);
    try std.testing.expectEqual(first.refs[2].row, second.refs[2].row);
    entries[2].demand.graph.calls = &.{};
    // Entry 0 changes too: the chunk is another, its changed row encoded now and the kept row still the old one.
    entries[0].demand.graph.calls = &.{7};
    try storeDemandIndex(&storage, storage.keyAt(manifest_scope, parts, 6), .{ .entries = &entries, .catalog = .{}, .keep = &keep });
    const third = (try loadManifest(a, &storage, storage.keyAt(manifest_scope, parts, 6))).?;
    try std.testing.expect(!std.mem.eql(u8, &first.chunks[0], &third.chunks[0]));
    var pool = chunks.Cache{ .storage = &storage, .arena = a };
    const changed = (try storedAt(a, &pool, third, third.refs[0])).?;
    try std.testing.expectEqualSlices(u32, &.{7}, changed.row.core.graph.calls);
}

/// An entry that names a record of every kind a bypassed function needs later: its final and the metadata's key and fact payload, the
/// fusion body and a checkpoint. `n` makes its keys its own.
fn namingEntry(n: u8) Entry {
    const state: cache.FinalState = .{ .known = null, .plans = &.{}, .counts = .{}, .own = .{} };
    const empty: cache.Provenance = .{ .frames = &.{}, .blocks = &.{}, .instructions = &.{}, .present = false };
    const metadata: cache.FinalMetadata = .{ .key = testDigest(n + 40), .body = .{ .positioned = testDigest(n + 50), .plain = testDigest(n + 51) }, .analysis = .{ .digest = testDigest(n + 60), .loop_ids = &.{} }, .state = state };
    const checkpoint: cache.Checkpoint = .{ .key = testDigest(n + 100), .output = testDigest(n + 101), .provenance = empty, .changed = 0, .graph = .{ .calls = &.{}, .references = &.{} } };
    return .{ .demand = .{ .lowered = testDigest(n), .fusion = .{ .key = testDigest(n + 20) }, .metadata = metadata, .history = .{ .outputs = .{ checkpoint, null, null, null } } }, .final = testDigest(n + 80) };
}

test "compaction after a build that bypassed every function keeps each record a kept chunk names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const work = try directory.dir.realPathFileAlloc(io, ".", a);
    const Stage = @import("stage_store.zig");
    const parts: []const []const u8 = &.{ "app", &.{0} };
    var entries = [_]Entry{ namingEntry(1), namingEntry(2), namingEntry(3) };
    const modules = [_][]const u8{ "a.selka", "b.selka", "a.selka" };
    var named: std.ArrayList([32]u8) = .empty;
    {
        // The first build saves the records its entries name and the index over them.
        var first = try Stage.Store.init(std.testing.allocator, io, work);
        defer first.deinit();
        for (entries) |entry| for (try recordKeys(a, &first, entry)) |key| {
            try std.testing.expect(try first.save(key, "a record"));
            try named.append(a, key);
        };
        try storeDemandIndex(&first, manifestKey(&first, parts), .{ .entries = &entries, .catalog = .{}, .modules = &modules });
        try std.testing.expect(try first.flush());
        @import("stage_roots.zig").retain(&first, a, io, "build-one", 0);
    }
    {
        // The second build bypasses every function: it reads the manifest and the chunks, keeps each row and loads none of the records.
        var second = try Stage.Store.init(std.testing.allocator, io, work);
        defer second.deinit();
        const manifest = (try loadManifest(a, &second, manifestKey(&second, parts))).?;
        var pool = chunks.Cache{ .storage = &second, .arena = a };
        const kept = try a.alloc(?chunks.Held, entries.len);
        const loaded = try a.alloc(Entry, entries.len);
        for (manifest.refs, kept, loaded) |ref, *held, *entry| {
            held.* = heldAt(manifest, ref);
            entry.* = (try entryIn(a, &pool, (try storedAt(a, &pool, manifest, ref)).?, null)).?;
        }
        try storeDemandIndex(&second, second.keyAt(manifest_scope, parts, 2), .{ .entries = loaded, .catalog = .{}, .keep = kept, .modules = &modules, .cache = &pool });
        @import("stage_roots.zig").retain(&second, a, io, "build-two", 0);
        for (manifest.chunks) |digest| try named.append(a, chunks.keyOf(&second, digest));
    }
    // Only the second build's roots remain: the records are live while it names them, and no other build does.
    const roots = try std.fs.path.join(a, &.{ work, "stages-packed-v1", "roots", "build-one-0.roots" });
    try std.Io.Dir.cwd().deleteFile(io, roots);
    {
        var collector = try Stage.Store.init(std.testing.allocator, io, work);
        defer collector.deinit();
        const ranks = try @import("stage_roots.zig").rank(a, io, work, try std.fs.path.join(a, &.{ work, "stages-packed-v1" }));
        const measured = try collector.storage.measure(&ranks);
        const result = try @import("work_retention.zig").compactBudgeted(a, collector.storage, &ranks, measured, @import("work_retention.zig").compaction_budget);
        try std.testing.expect(result != null);
    }
    var reader = try Stage.Store.init(std.testing.allocator, io, work);
    defer reader.deinit();
    var missing: usize = 0;
    for (named.items) |key| missing += @intFromBool(try reader.load(a, key) == null);
    try std.testing.expectEqual(@as(usize, 0), missing);
    try std.testing.expect(named.items.len >= 3 * 6);
}

/// A store over a fresh directory, holding the index of `entries` for `state` under raw layout `layout`, and the records they name when `records`.
fn storeForState(a: std.mem.Allocator, backing: std.mem.Allocator, directory: *std.testing.TmpDir, entries: []Entry, state: [32]u8, records: bool) !@import("stage_store.zig").Store {
    var storage = try @import("stage_store.zig").Store.init(backing, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    errdefer storage.deinit();
    if (records) for (entries) |entry| for (try recordKeys(a, &storage, entry)) |key| {
        _ = try storage.save(key, "a record");
    };
    const catalog: fusion.Catalog = .{ .raw_layout = testDigest(7), .raw_count = @intCast(entries.len) };
    try storeDemandIndex(&storage, manifestKey(&storage, &.{ "app", &.{0} }), .{ .entries = entries, .catalog = catalog, .lineage = .{ .state = state } });
    return storage;
}

test "a head serves the entries of a program state to a build that has no manifest of its own, when the store holds the records they name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var entries = [_]Entry{ namingEntry(1), namingEntry(2) };
    var storage = try storeForState(a, std.testing.allocator, &directory, &entries, testDigest(50), true);
    defer storage.deinit();
    // Another work directory's name for the manifest: nothing is stored under it, so only the head can answer.
    const elsewhere: []const []const u8 = &.{ "elsewhere", &.{0} };
    const known = try Candidates.load(a, &storage, elsewhere, .{ .raw_layout = testDigest(7), .state = testDigest(50) });
    // The head alone makes the build look for entries: names are resolved against the build's own module only when a candidate exists.
    try std.testing.expect(known.any());
    const found = (try known.find(a, null, probeFor(2, 1, testDigest(2)))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(testDigest(2), found.entry.demand.lowered.?);
    try std.testing.expect(found.same_layout);
    // Another state, or the same state under another layout, has no head.
    const other_state = try Candidates.load(a, &storage, elsewhere, .{ .raw_layout = testDigest(7), .state = testDigest(51) });
    try std.testing.expect((try other_state.find(a, null, probeFor(2, 1, testDigest(2)))) == null);
    const other_layout = try Candidates.load(a, &storage, elsewhere, .{ .raw_layout = testDigest(8), .state = testDigest(50) });
    try std.testing.expect((try other_layout.find(a, null, probeFor(2, 1, testDigest(2)))) == null);
}

/// `namingEntry` whose records have the keys a build computes (`Store.key` of the optimizer's scopes), which the shared store routes.
fn sharedNamingEntry(storage: *const @import("stage_store.zig").Store, n: u8) Entry {
    var entry = namingEntry(n);
    const own: []const u8 = &.{n};
    const final = storage.key("final", &.{own});
    entry.final = final;
    entry.demand.metadata.?.key = final;
    entry.demand.fusion.key = storage.key("optimizer-fusion-v1", &.{own});
    entry.demand.history.?.outputs[0].?.key = storage.key("inline_leaf", &.{own});
    return entry;
}

/// Save the records `entries` name (but their lowering keys) into `storage`.
fn saveNamedRecords(a: std.mem.Allocator, storage: *const @import("stage_store.zig").Store, entries: []const Entry) !void {
    for (entries) |entry| for (try recordKeys(a, storage, entry)) |key| {
        _ = try storage.save(key, "a record");
    };
}

test "a fresh worktree is served the head, the chunks and the records another worktree published, and the entries it gets are the same" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const Stage = @import("stage_store.zig");
    var entries: [3]Entry = undefined;
    const modules = [_][]const u8{ "a.selka", "b.selka", "a.selka" };
    const catalog: fusion.Catalog = .{ .raw_layout = testDigest(7), .raw_count = 3 };
    {
        // The first worktree optimizes the program: its records, its chunks and the head of its state go to the shared store.
        var first = try Stage.Store.initWithOptions(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "first" }), .{ .shared = shared, .publish = true });
        defer first.deinit();
        for (&entries, 1..) |*entry, n| entry.* = sharedNamingEntry(&first, @intCast(n));
        entries[1].demand.graph.calls = &.{ 0, 2 };
        try saveNamedRecords(a, &first, &entries);
        try storeDemandIndex(&first, manifestKey(&first, &.{ "app", &.{0} }), .{ .entries = &entries, .catalog = catalog, .modules = &modules, .lineage = .{ .state = testDigest(50) } });
        try std.testing.expect(try first.flush());
    }
    // A fresh worktree of the same project: its own work directory is empty, so no generation names the manifest.
    var second = try Stage.Store.initWithOptions(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "second" }), .{ .shared = shared, .publish = true });
    defer second.deinit();
    const known = try Candidates.load(a, &second, &.{ "app", &.{0} }, .{ .raw_layout = testDigest(7), .state = testDigest(50) });
    try std.testing.expect(known.manifests[0] == null and known.manifests[head_slot] != null);
    const found = (try known.find(a, null, probeFor(3, 1, testDigest(2)))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u32, &.{ 0, 2 }, found.entry.demand.graph.calls);
    try std.testing.expect(known.cache.?.reads > 0);
    // Without the state of the program there is nothing to look the head up by.
    const blind = try Candidates.load(a, &second, &.{ "app", &.{0} }, .{ .raw_layout = testDigest(7) });
    try std.testing.expect(!blind.any());
}

test "an entry a head names is not served when the store lacks a record it names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var entries = [_]Entry{ namingEntry(1), namingEntry(2) };
    var storage = try storeForState(a, std.testing.allocator, &directory, &entries, testDigest(50), false);
    defer storage.deinit();
    const elsewhere: []const []const u8 = &.{ "elsewhere", &.{0} };
    const known = try Candidates.load(a, &storage, elsewhere, .{ .raw_layout = testDigest(7), .state = testDigest(50) });
    try std.testing.expect(known.manifests[head_slot] != null);
    try std.testing.expect((try known.find(a, null, probeFor(2, 0, testDigest(1)))) == null);
    // The generation manifest of the build that wrote them serves them without the check: its own work directory holds what it names.
    const own = try Candidates.load(a, &storage, &.{ "app", &.{0} }, .{ .raw_layout = testDigest(7) });
    try std.testing.expect((try own.find(a, null, probeFor(2, 0, testDigest(1)))) != null);
}

test "a lookup consults the read generation and the last full build, and uses an entry only when its own key matches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const parts: []const []const u8 = &.{ "app", &.{0} };
    // Generation 1 (the tree an undo returns to) and generation 2 (the last full build) disagree on index 0 and hold
    // index 1 under different keys.
    var read: [2]Entry = .{ .{ .demand = .{ .lowered = testDigest(1) } }, .{ .demand = .{ .lowered = testDigest(2) } } };
    read[0].demand.graph.calls = &.{5};
    var last: [2]Entry = .{ .{ .demand = .{ .lowered = testDigest(4) } }, .{ .demand = .{ .lowered = testDigest(3) } } };
    const raw = testDigest(7);
    try storeDemandIndex(&storage, storage.keyAt(manifest_scope, parts, 1), .{ .entries = &read, .catalog = .{ .raw_layout = raw } });
    try storeDemandIndex(&storage, storage.keyAt(manifest_scope, parts, 2), .{ .entries = &last, .catalog = .{ .raw_layout = raw } });
    storage.generations = .{ .read = 1, .write = 3, .last = 2 };
    const candidates = try Candidates.load(a, &storage, parts, .{ .raw_layout = raw });
    // Index 0 under its read-generation key comes from the read generation.
    const first = (try candidates.find(a, null, probeFor(2, 0, testDigest(1)))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u32, &.{5}, first.entry.demand.graph.calls);
    // Index 1 under the key only the last full build holds comes from that build.
    const second = (try candidates.find(a, null, probeFor(2, 1, testDigest(3)))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(testDigest(3), second.entry.demand.lowered.?);
    // A key neither candidate holds at that index is a miss, and so is an index the manifests do not cover.
    try std.testing.expect((try candidates.find(a, null, probeFor(2, 1, testDigest(9)))) == null);
    try std.testing.expect((try candidates.find(a, null, probeFor(3, 2, testDigest(9)))) == null);
}

test "a manifest that names a missing or damaged chunk, or a row past its end, is a miss, not an error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const parts: []const []const u8 = &.{ "app", &.{0} };
    // The manifest names three entries in two chunks the store does not hold as chunks: the first is absent, the second holds damaged
    // bytes, and the third names a row past the end of a well-formed one.
    const well_formed = try chunks.frame(a, &.{"x"}, @splat(0));
    _ = try storage.save(chunks.keyOf(&storage, testDigest(98)), "damaged");
    _ = try storage.save(chunks.keyOf(&storage, chunks.digestOf(well_formed)), well_formed);
    var refs = [_]Ref{
        .{ .lowered = testDigest(1), .chunk = 0 },
        .{ .lowered = testDigest(2), .chunk = 1 },
        .{ .lowered = testDigest(3), .chunk = 2, .row = 5 },
    };
    const table = [_][32]u8{ testDigest(99), testDigest(98), chunks.digestOf(well_formed) };
    try storage.storeValue(manifestKey(&storage, parts), Stored, .{ .manifest = .{ .refs = &refs, .catalog = .{ .raw_layout = testDigest(7) }, .chunks = &table } });
    const candidates = try Candidates.load(a, &storage, parts, .{ .raw_layout = testDigest(7) });
    try std.testing.expect((try candidates.find(a, null, probeFor(3, 0, testDigest(1)))) == null);
    try std.testing.expect((try candidates.find(a, null, probeFor(3, 1, testDigest(2)))) == null);
    try std.testing.expect((try candidates.find(a, null, probeFor(3, 2, testDigest(3)))) == null);
}

test "a manifest stored under another raw layout is not a candidate, so an edited program reuses none of its entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const parts: []const []const u8 = &.{ "app", &.{0} };
    // The previous build's entries were optimized under raw layout 7; the edited program's raw layout is 8.
    var previous: [1]Entry = .{.{ .demand = .{ .lowered = testDigest(1) } }};
    try storeDemandIndex(&storage, manifestKey(&storage, parts), .{ .entries = &previous, .catalog = .{ .raw_layout = testDigest(7), .raw_count = 1 } });
    const same = try Candidates.load(a, &storage, parts, .{ .raw_layout = testDigest(7) });
    try std.testing.expect((try same.find(a, null, probeFor(1, 0, testDigest(1)))) != null);
    try std.testing.expectEqual(testDigest(7), same.catalog(1).raw_layout.?);
    const edited = try Candidates.load(a, &storage, parts, .{ .raw_layout = testDigest(8) });
    try std.testing.expect((try edited.find(a, null, probeFor(1, 0, testDigest(1)))) == null);
    // Without a candidate the catalog is the empty one of a build that has no previous state.
    try std.testing.expectEqual(@as(?[32]u8, null), edited.catalog(1).raw_layout);
    try std.testing.expectEqual(@as(usize, 1), edited.catalog(1).raw_count);
}

test "the second lookup finds a function whose text moved by its key without the source proof, and a changed body, another layout or a shared key miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const parts: []const []const u8 = &.{ "app", &.{0} };
    // The stored program: three functions whose mixed keys (1, 2, 3) hold the position of their text; the unmixed keys of the first two are
    // 11 and 12, and the third shares 12 with the second.
    var previous: [3]Entry = .{ .{ .demand = .{ .lowered = testDigest(1) } }, .{ .demand = .{ .lowered = testDigest(2) } }, .{ .demand = .{ .lowered = testDigest(3) } } };
    previous[0].demand.graph.calls = &.{2};
    const unmixed: [3]?[32]u8 = .{ testDigest(11), testDigest(12), testDigest(12) };
    try storeDemandIndex(&storage, manifestKey(&storage, parts), .{ .entries = &previous, .catalog = .{ .raw_layout = testDigest(7), .raw_count = 3 }, .unmixed = &unmixed });
    const same = try Candidates.load(a, &storage, parts, .{ .raw_layout = testDigest(7) });
    // A line shifted above function 0 changes its mixed key (the first lookup misses) and leaves its unmixed key: the second lookup finds it.
    try std.testing.expect((try same.find(a, null, probeFor(3, 0, testDigest(21)))) == null);
    try std.testing.expect(same.holdsLoose(.{ .count = 3, .index = 0, .unmixed = testDigest(11) }));
    const found = (try same.findLoose(a, null, .{ .count = 3, .index = 0, .unmixed = testDigest(11) })) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u32, &.{2}, found.entry.demand.graph.calls);
    // A changed body has another unmixed key; the same key at another index or under a count the manifest does not cover is a miss.
    try std.testing.expect(!same.holdsLoose(.{ .count = 3, .index = 0, .unmixed = testDigest(99) }));
    try std.testing.expect((try same.findLoose(a, null, .{ .count = 3, .index = 0, .unmixed = testDigest(99) })) == null);
    try std.testing.expect(!same.holdsLoose(.{ .count = 3, .index = 2, .unmixed = testDigest(11) }));
    try std.testing.expect(!same.holdsLoose(.{ .count = 4, .index = 0, .unmixed = testDigest(11) }));
    // Two functions that share an unmixed key are never resolved by it.
    try std.testing.expect(!same.holdsLoose(.{ .count = 3, .index = 1, .unmixed = testDigest(12) }));
    try std.testing.expect(!same.holdsLoose(.{ .count = 3, .index = 2, .unmixed = testDigest(12) }));
    // Another raw layout moves the order the passes visit functions in: no loose lookup then.
    const edited = try Candidates.load(a, &storage, parts, .{ .raw_layout = testDigest(8) });
    try std.testing.expect(!edited.holdsLoose(.{ .count = 3, .index = 0, .unmixed = testDigest(11) }));
}

/// A store over `work` that reads the shared half under `shared` and publishes to it when `publish` is set, as one worktree of a user has.
fn sharedStore(backing: std.mem.Allocator, work: []const u8, shared: []const u8, publish: bool) !@import("stage_store.zig").Store {
    return @import("stage_store.zig").Store.initWithOptions(backing, std.testing.io, work, .{ .shared = shared, .publish = publish });
}

/// What `publishState` publishes the entries as: the project, the raw layout, and whether the records the entries name are saved too.
/// `sealed` says whether the publisher requires its flush to seal the journal into packs: a publisher racing others for one shared
/// namespace may find its flush refused (the sequence lock's checks, `packs.State.flush`), which leaves its records in the journal, still
/// read by every store, so a test of concurrent publishers does not require it.
const Shape = struct { project: [32]u8, layout: u8, records: bool, sealed: bool = true };

/// Publish `entries` as the program state `state` of `shape.project` under raw layout `shape.layout`.
fn publishState(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, entries: []Entry, state: u8, shape: Shape) !void {
    if (shape.records) try saveNamedRecords(a, store, entries);
    const modules = try a.alloc([]const u8, entries.len);
    @memset(modules, "a.selka");
    const catalog: fusion.Catalog = .{ .raw_layout = testDigest(shape.layout), .raw_count = @intCast(entries.len) };
    try storeDemandIndex(store, manifestKey(store, &.{ "app", &.{0} }), .{ .entries = entries, .catalog = catalog, .modules = modules, .lineage = .{ .state = testDigest(state), .project = shape.project } });
    const flushed = try store.flush();
    if (shape.sealed) try std.testing.expect(flushed);
}

/// The candidates of a tree that was never built in: its work directory is empty, so only the shared half can name a manifest.
fn freshLoad(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, program: Program) !Candidates {
    return Candidates.load(a, store, &.{ "elsewhere", &.{0} }, program);
}

test "G3p-r11 pointer: a build whose state no tree published starts from the latest state of its project under its layout, and serves what that state holds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const project = testDigest(90);
    {
        var first = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "first" }), shared, true);
        defer first.deinit();
        var entries: [3]Entry = .{ sharedNamingEntry(&first, 1), sharedNamingEntry(&first, 2), sharedNamingEntry(&first, 3) };
        try publishState(a, &first, &entries, 50, .{ .project = project, .layout = 7, .records = true });
    }
    var second = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "second" }), shared, true);
    defer second.deinit();
    // The edit moved the state (51 was never published) and not the raw layout.
    const edited = try freshLoad(a, &second, .{ .raw_layout = testDigest(7), .state = testDigest(51), .project = project });
    try std.testing.expect(edited.manifests[0] == null and edited.manifests[head_slot] != null and edited.matching[head_slot]);
    const found = (try edited.find(a, null, probeFor(3, 1, testDigest(2)))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(testDigest(2), found.entry.demand.lowered.?);
    try std.testing.expect(found.same_layout and found.slot == head_slot);
    // Without the project there is nothing to look the pointer up by, and another project's pointer names nothing of this one.
    try std.testing.expect(!(try freshLoad(a, &second, .{ .raw_layout = testDigest(7), .state = testDigest(51) })).any());
    try std.testing.expect(!(try freshLoad(a, &second, .{ .raw_layout = testDigest(7), .state = testDigest(51), .project = testDigest(91) })).any());
}

test "G3p-r11 pointer: a pointer another tree replaced, or one for another layout, is harmless: the newest state under the layout serves, and a foreign layout serves nothing it should not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const project = testDigest(90);
    var writer = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "writer" }), shared, true);
    defer writer.deinit();
    var older: [2]Entry = .{ sharedNamingEntry(&writer, 1), sharedNamingEntry(&writer, 2) };
    var newer: [2]Entry = .{ sharedNamingEntry(&writer, 1), sharedNamingEntry(&writer, 3) };
    var foreign: [2]Entry = .{ sharedNamingEntry(&writer, 1), sharedNamingEntry(&writer, 4) };
    try publishState(a, &writer, &older, 50, .{ .project = project, .layout = 7, .records = true });
    try publishState(a, &writer, &newer, 52, .{ .project = project, .layout = 7, .records = true });
    try publishState(a, &writer, &foreign, 60, .{ .project = project, .layout = 9, .records = true });
    var reader = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "reader" }), shared, false);
    defer reader.deinit();
    // The pointer under layout 7 names the later state, not the one published first, and not the one published last for another layout.
    const same = try freshLoad(a, &reader, .{ .raw_layout = testDigest(7), .state = testDigest(53), .project = project });
    try std.testing.expect((try same.find(a, null, probeFor(2, 1, testDigest(3)))) != null);
    try std.testing.expect((try same.find(a, null, probeFor(2, 1, testDigest(2)))) == null);
    try std.testing.expect((try same.find(a, null, probeFor(2, 1, testDigest(4)))) == null);
    // A layout nobody published starts from the project's latest state, which stands under another layout: a candidate, not a match.
    const other = try freshLoad(a, &reader, .{ .raw_layout = testDigest(8), .state = testDigest(53), .project = project });
    try std.testing.expect(other.manifests[head_slot] != null and !other.matching[head_slot]);
    try std.testing.expect((try other.find(a, null, probeFor(2, 1, testDigest(4)))) == null);
    // A tree with a manifest of its own for another layout keeps it and does not take the project's latest state.
    try storeManifest(&reader, manifestKey(&reader, &.{ "elsewhere", &.{0} }), .{ .refs = &.{}, .catalog = .{ .raw_layout = testDigest(5) } });
    const owner = try freshLoad(a, &reader, .{ .raw_layout = testDigest(8), .state = testDigest(53), .project = project });
    try std.testing.expect(owner.manifests[0] != null and owner.manifests[head_slot] == null);
}

test "G3p-r11 pointer: a pointer to a head that is gone, or to a head whose records were collected, misses cleanly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const project = testDigest(90);
    var writer = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "writer" }), shared, true);
    defer writer.deinit();
    // A pointer to a state no tree published: the head it names is absent.
    try writer.storeValue(chunks.latestKey(&writer, project), chunks.Latest, .{ .state = testDigest(77) });
    try writer.storeValue(chunks.latestLayoutKey(&writer, project, testDigest(7)), chunks.Latest, .{ .state = testDigest(77) });
    try std.testing.expect(try writer.flush());
    var reader = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "reader" }), shared, true);
    defer reader.deinit();
    try std.testing.expect(!(try freshLoad(a, &reader, .{ .raw_layout = testDigest(7), .state = testDigest(51), .project = project })).any());
    // A pointer that is not a pointer, and a head that is not a manifest, are misses.
    try writer.storeValue(chunks.latestKey(&writer, project), []const u8, "torn");
    try writer.storeValue(chunks.headKey(&writer, testDigest(78)), []const u8, "not a manifest");
    try writer.storeValue(chunks.latestLayoutKey(&writer, project, testDigest(7)), chunks.Latest, .{ .state = testDigest(78) });
    try std.testing.expect(try writer.flush());
    try std.testing.expect(!(try freshLoad(a, &reader, .{ .raw_layout = testDigest(7), .state = testDigest(51), .project = project })).any());
    // A head whose records are gone: the pointer and the head are there, the records the entries name are not.
    var entries: [2]Entry = .{ sharedNamingEntry(&writer, 1), sharedNamingEntry(&writer, 2) };
    try publishState(a, &writer, &entries, 50, .{ .project = project, .layout = 7, .records = false });
    const bare = try freshLoad(a, &reader, .{ .raw_layout = testDigest(7), .state = testDigest(51), .project = project });
    try std.testing.expect(bare.manifests[head_slot] != null);
    try std.testing.expect((try bare.find(a, null, probeFor(2, 0, testDigest(1)))) == null);
}

/// Three stores over one shared half, each with a publisher thread of its own that publishes six states of one project.
const Fleet = struct {
    stores: [3]@import("stage_store.zig").Store = undefined,
    publishers: [3]LatestPublisher = undefined,
    opened: usize = 0,

    /// Publishes states `first` to `first + 5` of one project from the store it is given.
    const LatestPublisher = struct {
        store: *const @import("stage_store.zig").Store,
        first: u8,
        project: [32]u8,
        gpa: std.mem.Allocator,
        failed: std.atomic.Value(bool) = .init(false),

        fn run(self: *LatestPublisher) void {
            self.publish() catch self.failed.store(true, .release);
        }

        fn publish(self: *LatestPublisher) !void {
            var arena = std.heap.ArenaAllocator.init(self.gpa);
            defer arena.deinit();
            for (0..6) |round| {
                const n: u8 = self.first + @as(u8, @intCast(round));
                var entries = [_]Entry{namingEntry(n)};
                try publishState(arena.allocator(), self.store, &entries, n, .{ .project = self.project, .layout = 7, .records = false, .sealed = false });
            }
        }

        /// Whether `state` is one this publisher published.
        fn published(self: *const LatestPublisher, state: [32]u8) bool {
            return state[0] >= self.first and state[0] < self.first + 6;
        }
    };

    fn open(self: *Fleet, gpa: std.mem.Allocator, a: std.mem.Allocator, place: struct { root: []const u8, shared: []const u8, project: [32]u8 }) !void {
        const directories = [3][]const u8{ "one", "two", "three" };
        const firsts = [3]u8{ 1, 21, 41 };
        for (&self.stores, &self.publishers, directories, firsts) |*each, *publisher, name, first| {
            each.* = try sharedStore(gpa, try std.fs.path.join(a, &.{ place.root, name }), place.shared, true);
            self.opened += 1;
            publisher.* = .{ .store = each, .first = first, .project = place.project, .gpa = gpa };
        }
    }

    fn deinit(self: *Fleet) void {
        for (self.stores[0..self.opened]) |*each| each.deinit();
    }

    /// Whether `state` is one of the states some publisher published.
    fn published(self: *const Fleet, state: [32]u8) bool {
        for (&self.publishers) |*each| if (each.published(state)) return true;
        return false;
    }

    /// Whether no publisher failed.
    fn succeeded(self: *const Fleet) bool {
        for (&self.publishers) |*each| if (each.failed.load(.acquire)) return false;
        return true;
    }

    /// Run the publishers together and read the project's pointer from `reader` meanwhile.
    fn runWhilePolling(self: *Fleet, a: std.mem.Allocator, reader: *const @import("stage_store.zig").Store, project: [32]u8) !void {
        var threads: [3]std.Thread = undefined;
        var started: usize = 0;
        defer for (threads[0..started]) |each| each.join();
        for (&threads, &self.publishers) |*thread, *publisher| {
            thread.* = try std.Thread.spawn(.{}, LatestPublisher.run, .{publisher});
            started += 1;
        }
        _ = try pollLatest(a, reader, project, .{ .rounds = 40, .fleet = self });
    }
};

/// Read the project's pointer `rounds` times; each read finds no pointer or one that names a state in `published`. Returns how many reads found a
/// pointer whose head was not there to load (a reader may scan the journal of a publisher that is still writing, so this is allowed while it runs).
fn pollLatest(a: std.mem.Allocator, store: *const @import("stage_store.zig").Store, project: [32]u8, poll: struct { rounds: usize, fleet: *const Fleet }) !usize {
    var dangling: usize = 0;
    for (0..poll.rounds) |_| {
        const latest = try store.loadValue(a, chunks.latestKey(store, project), chunks.Latest) orelse continue;
        try std.testing.expect(poll.fleet.published(latest.state));
        dangling += @intFromBool((try store.loadValue(a, chunks.headKey(store, latest.state), DemandManifest)) == null);
    }
    return dangling;
}

test "G3p-r11 pointer: trees publishing a project's latest state at once never tear it: every pointer read names a head that loads, and the last one is a published state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const project = testDigest(90);
    var fleet: Fleet = .{};
    defer fleet.deinit();
    try fleet.open(std.testing.allocator, a, .{ .root = root, .shared = shared, .project = project });
    var reader = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "reader" }), shared, false);
    defer reader.deinit();
    try fleet.runWhilePolling(a, &reader, project);
    try std.testing.expect(fleet.succeeded());
    var last = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "last" }), shared, false);
    defer last.deinit();
    const latest = (try last.loadValue(a, chunks.latestKey(&last, project), chunks.Latest)).?;
    try std.testing.expect(fleet.published(latest.state));
    try std.testing.expectEqual(@as(usize, 0), try pollLatest(a, &last, project, .{ .rounds = 1, .fleet = &fleet }));
}

test "G3p-r12 pointer: a state published without requiring its journal sealed is read, pointer and head, by a store that opens the namespace afterwards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const project = testDigest(90);
    var publisher = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "publisher" }), shared, true);
    defer publisher.deinit();
    var entries = [_]Entry{namingEntry(7)};
    try publishState(a, &publisher, &entries, 7, .{ .project = project, .layout = 7, .records = false, .sealed = false });
    var reader = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "reader" }), shared, false);
    defer reader.deinit();
    const latest = (try reader.loadValue(a, chunks.latestKey(&reader, project), chunks.Latest)).?;
    try std.testing.expectEqual(testDigest(7), latest.state);
    try std.testing.expect((try reader.loadValue(a, chunks.headKey(&reader, latest.state), DemandManifest)) != null);
}

test "G3p-r11 pointer: a store that does not publish to a shared half writes no pointer, and a store with no shared half reads none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const project = testDigest(90);
    var entries: [1]Entry = .{namingEntry(1)};
    var reading = try sharedStore(std.testing.allocator, try std.fs.path.join(a, &.{ root, "reading" }), shared, false);
    defer reading.deinit();
    try publishState(a, &reading, &entries, 50, .{ .project = project, .layout = 7, .records = false });
    try std.testing.expect(try reading.loadValue(a, chunks.latestKey(&reading, project), chunks.Latest) == null);
    var private = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "private" }));
    defer private.deinit();
    try publishState(a, &private, &entries, 50, .{ .project = project, .layout = 7, .records = false });
    try std.testing.expect(try private.loadValue(a, chunks.latestKey(&private, project), chunks.Latest) == null);
    try std.testing.expect(!private.readsShared() and !private.publishesShared() and reading.readsShared() and !reading.publishesShared());
}
