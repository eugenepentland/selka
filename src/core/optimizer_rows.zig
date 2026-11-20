//! The optimizer's stored entry and the row that stores it (part 2, G3p (d), D-G3p-17).
//!
//! An entry holds everything a build keeps about one function. A function left alone by an edit needs from it only a few digests,
//! its call lists and its final metadata; the field rounds, the exploratory summary and the identity of each checkpoint (its output
//! digest and its inline ancestry) are read for a function that is recomputed, for a callee a recomputed function reads, and when a
//! join over the whole program must be made again. A row therefore holds two parts, stored in two chunks (`optimizer_chunks.zig`): the
//! `Core`, decoded for every function a build finds, and the `Rest`, read and decoded when something asks for it (`Index.settle`).
//!
//! Every function and type an entry refers to by ordinal is a local index into the row's `names` table (raw functions by the digest
//! of their reference, compound types by name, source files by key path), and a fusion helper, which the build declares after the
//! raw functions, is `helper_flag` plus its position among them. Both parts share the one table.
const std = @import("std");
const cache = @import("optimization_cache.zig");
const effects = @import("effects.zig");
const facts = @import("facts.zig");
const fields = @import("fields.zig");
const fusion = @import("fusion_checkpoint.zig");
const names = @import("optimizer_names.zig");
const ir = @import("ir.zig");
const codec = @import("selka").persist_codec;

/// The checkpoints a function passed through during the inlining stages and unswitching, by phase.
pub const History = struct { outputs: [4]?cache.Checkpoint = @splat(null) };

/// A function's raw call lists: every call or reference of the lowered body, its direct calls, and its function references.
pub const Graph = struct { calls: []const u32 = &.{}, direct_calls: []const u32 = &.{}, references: []const u32 = &.{} };

/// Exact exploratory dependencies and compact field evidence for one round.
pub const FieldRound = struct {
    input: [32]u8,
    summary: cache.Summary,
    writes: fields.Contribution,
};

/// Dependency-validated inputs and exact intermediate/final checkpoint handles.
pub const Entry = struct {
    raw: ?[32]u8 = null,
    demand: struct {
        lowered: ?[32]u8 = null,
        fusion: fusion.Body = .{},
        fields: struct { rounds: [2]?FieldRound = .{ null, null }, final: ?[32]u8 = null } = .{},
        graph: Graph = .{},
        effect: ?effects.Reused = null,
        metadata: ?cache.FinalMetadata = null,
        history: ?History = null,
    } = .{},
    stable: bool = false,
    summary: ?cache.Summary = null,
    summary_input: ?[32]u8 = null,
    parameters: []const ?facts.Interval = &.{},
    final: ?[32]u8 = null,
};

/// Marks a stored function reference as the position of a fusion helper after the raw functions, not a local name.
pub const helper_flag: u32 = 0x8000_0000;
/// What rewriting an entry's ordinals can fail with: memory, or a name that does not stand for anything here.
pub const MapError = error{ OutOfMemory, Unmappable };

/// Names the ordinals of an entry being stored (`mapEntry`).
pub const Capturer = struct {
    interner: *names.Interner,
    raw_count: u32,

    fn callee(self: Capturer, ordinal: u32) MapError!u32 {
        if (ordinal >= self.raw_count) return helper_flag | (ordinal - self.raw_count);
        return self.interner.callee(ordinal) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidSnapshot => error.Unmappable,
        };
    }

    fn typeRef(self: Capturer, ty: ir.Type) MapError!ir.Type {
        return self.interner.typeRef(ty) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidSnapshot => error.Unmappable,
        };
    }

    fn provenance(self: Capturer, value: *cache.Provenance) MapError!void {
        value.* = cache.portableProvenance(self.interner, value.*) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return error.Unmappable,
        };
    }
};

/// Resolves the local names of a loaded entry to this build's ordinals (`mapEntry`). A fusion helper position is only meaningful
/// when the raw layout is the one the entry was stored under, and then it is the same position after this build's raw functions.
pub const Restorer = struct {
    resolver: names.Resolver,
    raw_count: u32,
    same_layout: bool,
    /// What each local callee index resolved to when it was first asked (`memo_unset` before, `memo_missing` for a name that does not
    /// resolve), so a name a row uses many times is looked up once. Empty when the caller keeps no memo.
    memo: []u32 = &.{},

    const memo_unset: u32 = std.math.maxInt(u32);
    const memo_missing: u32 = std.math.maxInt(u32) - 1;

    /// A restorer that remembers the callees it resolves in `memo`, which holds one slot per local callee name.
    pub fn remembering(self: Restorer, memo: []u32) Restorer {
        @memset(memo, memo_unset);
        var out = self;
        out.memo = memo;
        return out;
    }

    fn callee(self: Restorer, local: u32) MapError!u32 {
        if (local & helper_flag != 0) {
            if (!self.same_layout) return error.Unmappable;
            return self.raw_count + (local & ~helper_flag);
        }
        if (local >= self.memo.len) return self.resolver.callee(local) orelse error.Unmappable;
        const known = self.memo[local];
        if (known == memo_missing) return error.Unmappable;
        if (known != memo_unset) return known;
        const found = self.resolver.callee(local) orelse {
            self.memo[local] = memo_missing;
            return error.Unmappable;
        };
        self.memo[local] = found;
        return found;
    }

    fn typeRef(self: Restorer, ty: ir.Type) MapError!ir.Type {
        return self.resolver.typeRef(ty) orelse error.Unmappable;
    }

    fn provenance(self: Restorer, value: *cache.Provenance) MapError!void {
        value.* = cache.resolveProvenance(self.resolver, value.*) orelse return error.Unmappable;
    }
};

/// Which way `mapEntry` rewrites: to local names when an entry is stored, to this build's ordinals when it is loaded.
pub const Mapper = union(enum) {
    capture: Capturer,
    restore: Restorer,

    fn callee(self: Mapper, ordinal: u32) MapError!u32 {
        return switch (self) {
            inline else => |each| each.callee(ordinal),
        };
    }

    fn typeRef(self: Mapper, ty: ir.Type) MapError!ir.Type {
        return switch (self) {
            inline else => |each| each.typeRef(ty),
        };
    }

    fn provenance(self: Mapper, value: *cache.Provenance) MapError!void {
        return switch (self) {
            inline else => |each| each.provenance(value),
        };
    }
};

fn mapList(list: *[]const u32, mapper: Mapper) MapError!void {
    for (@constCast(list.*)) |*each| each.* = try mapper.callee(each.*);
}

fn mapSummary(summary: *cache.Summary, mapper: Mapper) MapError!void {
    for (@constCast(summary.calls)) |*call| call.callee = try mapper.callee(call.callee);
}

/// Rewrite every function and type an entry refers to by ordinal through `mapper`, in place. The slices are the caller's to
/// change: a copy made by `cloneEntry` when storing, a freshly decoded record when loading.
pub fn mapEntry(entry: *Entry, mapper: Mapper) MapError!void {
    try mapList(&entry.demand.graph.calls, mapper);
    try mapList(&entry.demand.graph.direct_calls, mapper);
    try mapList(&entry.demand.graph.references, mapper);
    for (&entry.demand.fields.rounds) |*slot| if (slot.*) |*round| try mapRound(round, mapper);
    if (entry.demand.metadata) |*metadata| {
        try mapList(&metadata.outgoing, mapper);
        if (metadata.render) |*render| try mapList(&render.scopes, mapper);
    }
    if (entry.demand.history) |*history| for (&history.outputs) |*slot| if (slot.*) |*checkpoint| {
        try mapper.provenance(&checkpoint.provenance);
        try mapList(&checkpoint.graph.calls, mapper);
        try mapList(&checkpoint.graph.references, mapper);
    };
    if (entry.summary) |*summary| try mapSummary(summary, mapper);
}

fn mapRound(round: *FieldRound, mapper: Mapper) MapError!void {
    try mapSummary(&round.summary, mapper);
    for (@constCast(round.writes.writes)) |*write| write.record = try mapper.typeRef(write.record);
    for (@constCast(round.writes.opens)) |*open| open.* = try mapper.typeRef(open.*);
    try mapList(&round.writes.references, mapper);
}

/// A copy of `entry` whose ordinal lists are the caller's to rewrite.
pub fn cloneEntry(a: std.mem.Allocator, entry: Entry) std.mem.Allocator.Error!Entry {
    var out = entry;
    out.demand.graph = .{
        .calls = try a.dupe(u32, entry.demand.graph.calls),
        .direct_calls = try a.dupe(u32, entry.demand.graph.direct_calls),
        .references = try a.dupe(u32, entry.demand.graph.references),
    };
    for (&out.demand.fields.rounds) |*slot| if (slot.*) |*round| {
        round.summary.calls = try a.dupe(cache.Call, round.summary.calls);
        round.writes.writes = try a.dupe(fields.Write, round.writes.writes);
        round.writes.opens = try a.dupe(ir.Type, round.writes.opens);
        round.writes.references = try a.dupe(u32, round.writes.references);
    };
    if (out.demand.metadata) |*metadata| {
        metadata.outgoing = try a.dupe(u32, metadata.outgoing);
        if (metadata.render) |*render| render.scopes = try a.dupe(u32, render.scopes);
    }
    if (out.demand.history) |*history| for (&history.outputs) |*slot| if (slot.*) |*checkpoint| {
        checkpoint.graph = .{ .calls = try a.dupe(u32, checkpoint.graph.calls), .references = try a.dupe(u32, checkpoint.graph.references) };
    };
    if (out.summary) |*summary| summary.calls = try a.dupe(cache.Call, summary.calls);
    return out;
}

/// The digests and flags of an entry that every build reads of every function it finds.
pub const Scalars = struct {
    raw: ?[32]u8,
    summary_input: ?[32]u8,
    final: ?[32]u8,
    lowered: ?[32]u8,
    fields_final: ?[32]u8,
    stable: bool,
    /// The entry's summary was present and its call sites had the arity of their callees when it was stored (`reusableEntry`).
    summary_ok: bool,
};

/// One checkpoint as every build reads it: the key of its record, the events it counted, and the calls it left.
pub const Link = struct { key: [32]u8, changed: u32, calls: []const u32, references: []const u32 };

/// The part of an entry decoded for every function a build finds.
pub const Core = struct {
    scalars: Scalars,
    parameters: []const ?facts.Interval,
    fusion: fusion.Body,
    graph: Graph,
    effect: ?effects.Reused,
    metadata: ?cache.FinalMetadata,
    history: ?[4]?Link,
};

/// What a checkpoint's output digest and inline ancestry were.
pub const Seen = struct { output: [32]u8, plain: [32]u8, provenance: cache.Provenance };

/// The part of an entry decoded when a recomputed function, a join over the program or a restore asks for it.
pub const Rest = struct {
    rounds: [2]?FieldRound,
    summary: ?cache.Summary,
    history: ?[4]?Seen,
};

/// A row's core as it is stored, with the names both parts use.
pub const Row = struct { core: Core, names: names.Names };

/// What an output digest holds until the rest of its entry is decoded: no checkpoint's output ever is this.
pub const unsettled_output: [32]u8 = @splat(0xdd);
const unsettled_provenance: cache.Provenance = .{ .frames = &.{}, .blocks = &.{}, .instructions = &.{}, .present = false };

/// The core of `entry`; `summary_ok` is whether its summary can be used as it stands (`Scalars.summary_ok`).
pub fn coreOf(entry: Entry, summary_ok: bool) Core {
    var history: ?[4]?Link = null;
    if (entry.demand.history) |kept| {
        var links: [4]?Link = @splat(null);
        for (kept.outputs, &links) |maybe, *link| if (maybe) |checkpoint| {
            link.* = .{ .key = checkpoint.key, .changed = checkpoint.changed, .calls = checkpoint.graph.calls, .references = checkpoint.graph.references };
        };
        history = links;
    }
    return .{
        .scalars = .{
            .raw = entry.raw,
            .summary_input = entry.summary_input,
            .final = entry.final,
            .lowered = entry.demand.lowered,
            .fields_final = entry.demand.fields.final,
            .stable = entry.stable,
            .summary_ok = summary_ok,
        },
        .parameters = entry.parameters,
        .fusion = entry.demand.fusion,
        .graph = entry.demand.graph,
        .effect = entry.demand.effect,
        .metadata = entry.demand.metadata,
        .history = history,
    };
}

/// The rest of `entry`.
pub fn restOf(entry: Entry) Rest {
    var history: ?[4]?Seen = null;
    if (entry.demand.history) |kept| {
        var seen: [4]?Seen = @splat(null);
        for (kept.outputs, &seen) |maybe, *slot| if (maybe) |checkpoint| {
            slot.* = .{ .output = checkpoint.output, .plain = checkpoint.plain, .provenance = checkpoint.provenance };
        };
        history = seen;
    }
    return .{ .rounds = entry.demand.fields.rounds, .summary = entry.summary, .history = history };
}

/// The entry a core describes, its rest not yet read: no rounds, no summary, and checkpoints whose output is `unsettled_output`.
pub fn entryOf(core: Core) Entry {
    var entry: Entry = .{
        .raw = core.scalars.raw,
        .stable = core.scalars.stable,
        .summary_input = core.scalars.summary_input,
        .parameters = core.parameters,
        .final = core.scalars.final,
    };
    entry.demand.lowered = core.scalars.lowered;
    entry.demand.fusion = core.fusion;
    entry.demand.fields.final = core.scalars.fields_final;
    entry.demand.graph = core.graph;
    entry.demand.effect = core.effect;
    entry.demand.metadata = core.metadata;
    if (core.history) |links| {
        var history: History = .{};
        for (links, &history.outputs) |maybe, *slot| if (maybe) |link| {
            slot.* = .{ .key = link.key, .output = unsettled_output, .provenance = unsettled_provenance, .changed = link.changed, .graph = .{ .calls = link.calls, .references = link.references } };
        };
        entry.demand.history = history;
    }
    return entry;
}

/// Put a decoded rest into `entry`, which `entryOf` made from the core of the same row. False when the two do not describe the same
/// checkpoints, or when the entry has been changed since (its rounds, summary or a checkpoint's output are no longer those of the core).
pub fn fill(entry: *Entry, rest: Rest) bool {
    // A rest read after the entry was changed would overwrite what the change made with what the entry held before it.
    if (entry.demand.fields.rounds[0] != null or entry.demand.fields.rounds[1] != null or entry.summary != null) return false;
    if (entry.demand.history) |history| for (history.outputs) |slot| if (slot) |checkpoint| {
        if (!std.mem.eql(u8, &checkpoint.output, &unsettled_output)) return false;
    };
    entry.demand.fields.rounds = rest.rounds;
    entry.summary = rest.summary;
    const seen = rest.history orelse return entry.demand.history == null;
    const history = if (entry.demand.history) |*kept| kept else return false;
    for (&history.outputs, seen) |*slot, maybe| {
        if ((slot.* == null) != (maybe == null)) return false;
        if (slot.*) |*checkpoint| {
            checkpoint.output = maybe.?.output;
            checkpoint.plain = maybe.?.plain;
            checkpoint.provenance = maybe.?.provenance;
        }
    }
    return true;
}

/// Rewrite the ordinals of a decoded core through `mapper`.
pub fn mapCore(core: *Core, mapper: Mapper) MapError!void {
    try mapList(&core.graph.calls, mapper);
    try mapList(&core.graph.direct_calls, mapper);
    try mapList(&core.graph.references, mapper);
    if (core.metadata) |*metadata| {
        try mapList(&metadata.outgoing, mapper);
        if (metadata.render) |*render| try mapList(&render.scopes, mapper);
    }
    if (core.history) |*links| for (links) |*slot| if (slot.*) |*link| {
        try mapList(&link.calls, mapper);
        try mapList(&link.references, mapper);
    };
}

/// Rewrite the ordinals of a decoded rest through `mapper`.
pub fn mapRest(rest: *Rest, mapper: Mapper) MapError!void {
    for (&rest.rounds) |*slot| if (slot.*) |*round| try mapRound(round, mapper);
    if (rest.summary) |*summary| try mapSummary(summary, mapper);
    if (rest.history) |*seen| for (seen) |*slot| if (slot.*) |*each| try mapper.provenance(&each.provenance);
}

/// A row's core read from its chunk: the core decoded, with the names both parts share.
pub const View = struct { core: Core, names: names.Names };

/// The two records of a row: its core with the names, and its rest.
pub const Encoded = struct { core: []const u8, rest: []const u8 };

/// The bytes of a row's two parts.
pub fn encode(a: std.mem.Allocator, row: Row, rest: Rest) std.mem.Allocator.Error!Encoded {
    var core = codec.Writer.init(a);
    try core.write(Row, row);
    var tail = codec.Writer.init(a);
    try tail.write(Rest, rest);
    return .{ .core = core.bytes.items, .rest = tail.bytes.items };
}

/// Decode the core of a row from the bytes `Encoded.core` holds, or null when they are not a well-formed core.
pub fn view(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?View {
    var reader = codec.Reader.init(a, bytes);
    const row = reader.read(Row) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (!reader.done()) return null;
    return .{ .core = row.core, .names = row.names };
}

/// Decode the rest of a row from the bytes `Encoded.rest` holds, or null when they are malformed.
pub fn readRest(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?Rest {
    var reader = codec.Reader.init(a, bytes);
    const rest = reader.read(Rest) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return if (reader.done()) rest else null;
}

test "an entry's core and rest rebuild the entry, and a core alone leaves the rest unsettled" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{ .raw = @splat(1), .final = @splat(2), .stable = true };
    entry.demand.lowered = @splat(3);
    entry.demand.fields.final = @splat(4);
    var history: History = .{};
    history.outputs[1] = .{ .key = @splat(5), .output = @splat(6), .plain = @splat(8), .provenance = unsettled_provenance, .changed = 7, .graph = .{ .calls = &.{ 1, 2 }, .references = &.{3} } };
    entry.demand.history = history;
    entry.summary = .{ .returned = facts.Interval.point(9), .calls = &.{} };
    const bytes = try encode(a, .{ .core = coreOf(entry, true), .names = .{} }, restOf(entry));
    const seen = (try view(a, bytes.core)).?;
    var back = entryOf(seen.core);
    try std.testing.expect(seen.core.scalars.summary_ok);
    try std.testing.expect(back.summary == null);
    try std.testing.expectEqual(unsettled_output, back.demand.history.?.outputs[1].?.output);
    try std.testing.expectEqual(@as(u32, 7), back.demand.history.?.outputs[1].?.changed);
    try std.testing.expect(fill(&back, (try readRest(a, bytes.rest)).?));
    try std.testing.expectEqual(@as(u8, 6), back.demand.history.?.outputs[1].?.output[0]);
    try std.testing.expectEqual(@as(u8, 8), back.demand.history.?.outputs[1].?.plain[0]);
    try std.testing.expectEqual(@as(?facts.Interval, facts.Interval.point(9)), back.summary.?.returned);
    try std.testing.expectEqual(@as(u8, 3), back.demand.lowered.?[0]);
    try std.testing.expect(back.stable);
}

test "a rest that names other checkpoints than its core is refused, and bytes cut short are no row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{};
    var history: History = .{};
    history.outputs[0] = .{ .key = @splat(1), .output = @splat(2), .provenance = unsettled_provenance, .changed = 0, .graph = .{ .calls = &.{}, .references = &.{} } };
    entry.demand.history = history;
    var rest = restOf(entry);
    rest.history.?[0] = null;
    var back = entryOf(coreOf(entry, false));
    try std.testing.expect(!fill(&back, rest));
    const bytes = try encode(a, .{ .core = coreOf(entry, false), .names = .{} }, restOf(entry));
    try std.testing.expectEqual(@as(?View, null), try view(a, bytes.core[0..3]));
    try std.testing.expectEqual(@as(?Rest, null), try readRest(a, bytes.rest[0 .. bytes.rest.len - 1]));
}

test "a rest is refused for an entry changed since its core was read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{};
    var history: History = .{};
    history.outputs[2] = .{ .key = @splat(1), .output = @splat(2), .provenance = unsettled_provenance, .changed = 0, .graph = .{ .calls = &.{}, .references = &.{} } };
    entry.demand.history = history;
    entry.summary = .{ .returned = null, .calls = &.{} };
    const bytes = try encode(a, .{ .core = coreOf(entry, true), .names = .{} }, restOf(entry));
    const rest = (try readRest(a, bytes.rest)).?;
    var untouched = entryOf((try view(a, bytes.core)).?.core);
    var replaced = untouched;
    replaced.demand.history.?.outputs[2].?.output = @splat(9);
    var summarised = untouched;
    summarised.summary = .{ .returned = facts.Interval.point(1), .calls = &.{} };
    try std.testing.expect(!fill(&replaced, rest));
    try std.testing.expect(!fill(&summarised, rest));
    try std.testing.expect(fill(&untouched, rest));
}

test "a restorer that remembers looks each local callee up once, and remembers a name that does not resolve" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var index: names.Index = .{};
    const known: [32]u8 = @splat(1);
    const unknown: [32]u8 = @splat(2);
    try index.callees.put(a, known, 7);
    const table = [_][32]u8{ known, unknown };
    const resolver: names.Resolver = .{ .index = &index, .canons = undefined, .source = undefined, .names = .{ .callees = &table }, .verify = false };
    var memo: [2]u32 = undefined;
    const restorer = (Restorer{ .resolver = resolver, .raw_count = 10, .same_layout = true }).remembering(&memo);
    try std.testing.expectEqual(@as(u32, 7), try restorer.callee(0));
    try std.testing.expectError(error.Unmappable, restorer.callee(1));
    // Both answers now come from the memo: the index no longer holds the name, and the unresolved one is not asked for again.
    index.callees.clearRetainingCapacity();
    try index.callees.put(a, unknown, 9);
    try std.testing.expectEqual(@as(u32, 7), try restorer.callee(0));
    try std.testing.expectError(error.Unmappable, restorer.callee(1));
    try std.testing.expectEqual(@as(u32, 13), try restorer.callee(helper_flag | 3));
}
