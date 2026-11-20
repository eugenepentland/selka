//! The incremental engine (spec `docs/design/incremental-engine.md`): queries over recorded reads, validated on
//! demand, one file per record.
//!
//! `Engine.query(kind, argument)` answers a query. It looks the key up in this revision's memo; else opens the one
//! record file the key names, walks the record's reads in order and stops at the first that changed; serves the stored
//! payload if none did; otherwise runs the kind with a fresh context, records what it read, publishes the new record by
//! rename and serves that. A dependency recomputed to the same result digest leaves its dependents valid.
//!
//! The cost of serving is the reads of the queries it touches and one record open per query, never the size of the
//! store: nothing here lists or indexes the store. The records a build adopts from the shared tier are the exception to
//! "one file per record": they are written together as one pack when the engine ends (`pack.zig`, `local_records.zig`).
const std = @import("std");
const digest_rules = @import("digest.zig");
const record_rules = @import("record.zig");
const context_rules = @import("context.zig");
const world_rules = @import("world.zig");
const shared_rules = @import("shared_tier.zig");
const store_rules = @import("store.zig");
const pack_rules = @import("pack.zig");
const local_rules = @import("local_records.zig");
const memory_rules = @import("memory.zig");
const stats_rules = @import("stats.zig");
const validate = @import("validate.zig");
const Digest = digest_rules.Digest;
const Record = record_rules.Record;
const Kind = context_rules.Kind;
const Frame = context_rules.Frame;
const Fetched = context_rules.Fetched;
const Result = context_rules.Result;
const Host = context_rules.Host;
const Context = context_rules.Context;

/// Why a query could not be answered.
pub const Error = context_rules.Error;

/// How `Engine.answer` found a result: already in this revision's memo, served from a validated record, or computed.
pub const Origin = enum { memo, served, recomputed };

/// A query's result and how it was found.
pub const Answer = struct { result: Result, origin: Origin };

/// Why a kind could not be registered.
pub const RegisterError = error{ OutOfMemory, InvalidKindName, DuplicateKind, TooManyKinds };

/// How the engine is set up for one process.
pub const Config = struct {
    /// The work directory (`--cache-dir`); the store is `<work>/engine-v1`.
    work: []const u8,
    /// Recompute one in this many served queries and compare (spec §10); 0 turns verify mode off.
    verify_every: u32 = 0,
    /// Time lookups, validations and computations (the clock is read around each).
    timing: bool = false,
    /// The deepest chain of queries; deeper is `error.DepthExceeded` (spec §6: group the members under a parent).
    depth_limit: u32 = 512,
    /// The assumptions of spec §4.
    assumptions: world_rules.Assumptions = .{},
    /// The per-user tier below the store, consulted for the kinds `share` marks.
    shared: ?shared_rules.Tier = null,
    /// The rules of the tier's sweeps and of the local records pack.
    policy: Policy = .{},
};

/// The numbers that decide how often the engine asks the tier and when it writes a pack.
pub const Policy = struct {
    /// How long after the tier was asked about a partition's served records (a sweep) it is asked again. The tier refreshes the recency of an entry
    /// it is asked about only when the entry is an hour old, so an hour is as often as asking can change anything in it.
    sweep_interval_ns: i64 = 60 * 60 * std.time.ns_per_s,
    /// The fewest adopted records that make a pack: a build that adopts fewer writes them as files of their own, so a handful of records does not leave
    /// a pack behind for every build.
    pack_min_records: u32 = 16,
};

const Setup = struct { gpa: std.mem.Allocator, io: std.Io, world: world_rules.World, config: Config };

/// A registered kind and where its records live.
pub const Entry = struct {
    kind: *const Kind,
    /// `<root>/records/<kind>/<code identity hex>`.
    directory: []const u8,
    touched: std.atomic.Value(bool) = .init(false),
    /// Whether the records of this kind go to and come from the shared tier (`Engine.share`).
    shared: bool = false,
    /// Which of this kind's queries may use the tier, when only some may.
    filter: ?shared_rules.Filter = null,
    /// Whether this process asks the tier about the records of this kind it serves from the work directory: `sweep_undecided`, `sweep_due` or
    /// `sweep_done` (`Engine.sweeping`).
    sweep: std.atomic.Value(u8) = .init(sweep_undecided),
    /// Whether this process asked the tier about a served record since the partition was last stamped.
    swept: std.atomic.Value(bool) = .init(false),
};

const sweep_undecided: u8 = 0;
const sweep_due: u8 = 1;
const sweep_done: u8 = 2;

/// The kinds an engine answers.
pub const Registry = struct {
    arena: std.heap.ArenaAllocator,
    entries: [stats_rules.max_kinds]Entry = undefined,
    count: usize = 0,

    /// The position of `kind`, matched by pointer or by name and code identity.
    pub fn indexOf(self: *const Registry, kind: *const Kind) ?usize {
        for (self.entries[0..self.count], 0..) |entry, index| {
            if (entry.kind == kind) return index;
            if (std.mem.eql(u8, entry.kind.name, kind.name) and std.mem.eql(u8, &entry.kind.identity, &kind.identity)) return index;
        }
        return null;
    }

    /// The position of the kind called `name`.
    pub fn byName(self: *const Registry, name: []const u8) ?usize {
        for (self.entries[0..self.count], 0..) |entry, index| {
            if (std.mem.eql(u8, entry.kind.name, name)) return index;
        }
        return null;
    }

    /// The registered kinds' names, in registration order, in `a`.
    pub fn names(self: *const Registry, a: std.mem.Allocator) std.mem.Allocator.Error![]const []const u8 {
        const out = try a.alloc([]const u8, self.count);
        for (self.entries[0..self.count], out) |entry, *slot| slot.* = entry.kind.name;
        return out;
    }
};

/// The last cycle and the last verify mismatch, as text for the caller to print.
const Notes = struct {
    mutex: std.Io.Mutex = .init,
    cycle: []const u8 = "",
    mismatch: []const u8 = "",
};

/// A file read of a record whose stat tuple should be replaced.
const Refresh = struct { index: usize, stat: world_rules.Stat };

/// What a lookup found: the query served, or the record was missing, torn or stale.
const Lookup = union(enum) {
    served: Fetched,
    /// Not served; the argument of the stale record when there was one.
    missed: ?[]const u8,
};

/// A record on its way to the shared tier, with the bytes of the object its payload points to when it does not hold them inline.
/// `signature` is `record_rules.readSignature` of its reads: what tells one variant of the key from another.
const Outgoing = struct { key: Digest, bytes: []const u8, result: Digest, signature: Digest, object: ?[]const u8 = null };

/// What publishing a computation left in the work directory: the encoded record, its read signature, and the payload when it is
/// stored as an object.
const Published = struct { bytes: []const u8, signature: Digest, object: ?[]const u8 };

/// Where a candidate record came from.
const Source = enum {
    /// The work directory's own file for the key.
    loose,
    /// A pack of the work directory.
    pack,
    /// The shared tier: a served record needs a local copy.
    shared,
};

/// A candidate record for a lookup: its bytes, the tier its kind is shared through, and where it was found.
/// A candidate record and where it came from. `tier` is the kind's shared tier before its filter is asked (`Engine.tierOf`):
/// a record the work directory serves needs the filter only when this process sweeps the tier (`Engine.consider`), and asking
/// it can cost what a build of the query's subject costs (the test runner's portability rule).
const Offer = struct { bytes: []const u8, tier: ?shared_rules.Tier, source: Source = .loose };

/// What looking at one candidate record found.
const Candidate = union(enum) {
    /// The record's reads hold: the query is served.
    served: Fetched,
    /// A record of this key whose reads no longer hold; its argument.
    stale: []const u8,
    /// Not a record of this query at all: damaged, foreign or of another kind.
    unusable,
};

/// What running a kind produced, ready to publish.
const Execution = struct { payload: []const u8, digest: Digest, reads: []const record_rules.Read, parts: []const record_rules.Part };

/// What a served result stored as an object keeps to read it later: the query it answers, the object its record names and
/// the result digest the record promised. It lives in the revision's arena, and the result's handle is its `base`.
const Cell = struct {
    base: context_rules.Lazy,
    engine: *Engine,
    index: usize,
    key: Digest,
    /// The record's argument, copied into the revision's arena.
    argument: []const u8,
    object: Digest,
    digest: Digest,
};

/// How many variants of one query the shared tier keeps. The tier holds one record per address, and two trees that hold two versions of a
/// module (or two projects with a module of one path) ask the same key and read different things; each version is a variant, kept under
/// its own slot (`digest_rules.variantKey`) and served to the tree whose reads hold. A fifth variant replaces one of the four.
pub const shared_variants = 4;

/// The engine of one process.
pub const Engine = struct {
    setup: Setup,
    store: store_rules.Store,
    registry: Registry,
    memory: memory_rules.Memory,
    stats: stats_rules.Stats = .{},
    notes: Notes = .{},
    /// The records this process adopted and the packs of the work directory.
    local: local_rules.Records = .{},

    /// An engine over `world` whose store is under `config.work`. It must not move once a query has run.
    pub fn init(gpa: std.mem.Allocator, io: std.Io, world: world_rules.World, config: Config) std.mem.Allocator.Error!Engine {
        var registry: Registry = .{ .arena = .init(gpa) };
        errdefer registry.arena.deinit();
        const root = try std.fs.path.join(registry.arena.allocator(), &.{ config.work, store_rules.root_leaf });
        return .{
            .setup = .{ .gpa = gpa, .io = io, .world = world, .config = config },
            .store = store_rules.Store.init(io, root),
            .registry = registry,
            .memory = memory_rules.Memory.init(gpa),
        };
    }

    /// Free everything.
    pub fn deinit(self: *Engine) void {
        self.stampSwept();
        self.flushLocal();
        self.local.deinit(self.setup.gpa);
        self.memory.deinit();
        self.registry.arena.deinit();
        self.setup.gpa.free(self.notes.cycle);
        self.setup.gpa.free(self.notes.mismatch);
    }

    /// Make `kind` answerable. Kinds register before the first query; a name is registered once.
    pub fn register(self: *Engine, kind: *const Kind) RegisterError!void {
        if (!context_rules.validKindName(kind.name)) return error.InvalidKindName;
        if (self.registry.byName(kind.name) != null) return error.DuplicateKind;
        if (self.registry.count == stats_rules.max_kinds) return error.TooManyKinds;
        const directory = try self.store.partition(self.registry.arena.allocator(), kind.name, kind.identity);
        self.registry.entries[self.registry.count] = .{ .kind = kind, .directory = directory };
        self.registry.count += 1;
    }

    /// Mark `kind` shared: its records are published to the shared tier (`Config.shared`) and a local miss consults it. A
    /// kind's records may be shared when they name no path of this tree; a record is served from the tier only while every
    /// read it holds still holds, as a local one is. With a `filter`, only the queries it allows use the tier: the others
    /// are published nowhere and looked up nowhere but in the work directory.
    pub fn share(self: *Engine, kind: *const Kind, filter: ?shared_rules.Filter) void {
        const index = self.registry.indexOf(kind) orelse return;
        self.registry.entries[index].shared = true;
        self.registry.entries[index].filter = filter;
    }

    /// Give the engine a shared tier after it was created, for a caller that learns where the tier is only once the engine
    /// exists. Call it before the first query, and `share` the kinds that use it after.
    pub fn setShared(self: *Engine, tier: ?shared_rules.Tier) void {
        self.setup.config.shared = tier;
    }

    /// Remove the record of `kind(argument)` wherever this engine keeps it: the memo, the work directory's store and, for a
    /// query the tier serves, the shared tier. A caller that found a served answer wrong (a verdict that no longer holds)
    /// uses it, so the next lookup computes instead of serving the same record again. A kind that is not registered, or an
    /// argument too long to have a record, has nothing to forget.
    pub fn forget(self: *Engine, kind: *const Kind, argument: []const u8) void {
        if (argument.len > digest_rules.max_argument) return;
        const index = self.registry.indexOf(kind) orelse return;
        const key = digest_rules.key(kind.name, kind.identity, argument);
        self.memory.forget(self.setup.io, key);
        var arena: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer arena.deinit();
        const entry = &self.registry.entries[index];
        const path = self.store.recordPath(arena.allocator(), entry.directory, key) catch return;
        self.store.remove(path);
        if (!self.local.isOpen()) self.openPacks();
        self.local.forget(self.setup.gpa, self.setup.io, key);
        if (self.tierFor(entry, argument)) |known| for (0..shared_variants) |slot| known.forget(digest_rules.variantKey(key, slot));
    }

    /// Answer the query `kind(argument)`. The payload in the result is valid until the next revision. A result stored as an
    /// object is read when its payload is first asked for (`Result.payload`), not here.
    pub fn query(self: *Engine, kind: *const Kind, argument: []const u8) Error!Result {
        const fetched = try self.fetch(kind, argument, null);
        return fetched.result;
    }

    /// `query`, saying also whether the result came from the memo, from a validated record or from running the kind.
    pub fn answer(self: *Engine, kind: *const Kind, argument: []const u8) Error!Answer {
        const fetched = try self.fetch(kind, argument, null);
        return .{ .result = fetched.result, .origin = if (fetched.memoized) .memo else if (fetched.fresh) .recomputed else .served };
    }

    /// `answer` without running the kind: the result when this revision's memo or a valid record (local, else shared) serves
    /// `kind(argument)`, and null when serving it would mean computing it. Nothing is computed and nothing is written, so a
    /// caller that decides on the result (a test run that reuses a verdict) can ask and then run the work itself.
    pub fn peek(self: *Engine, kind: *const Kind, argument: []const u8) Error!?Answer {
        if (argument.len > digest_rules.max_argument) return error.ArgumentTooLong;
        const index = self.registry.indexOf(kind) orelse return error.UnknownKind;
        const key = digest_rules.key(kind.name, kind.identity, argument);
        const fetched = (try self.resolve(index, key, argument, null, false)) orelse return null;
        return .{ .result = fetched.result, .origin = if (fetched.memoized) .memo else .served };
    }

    /// Start a new revision of the world: forget every validated result and every answer of the world. Call it when
    /// the files may have changed under a process that lives on. No query may be running.
    pub fn newRevision(self: *Engine) void {
        self.stampSwept();
        self.flushLocal();
        self.memory.reset(self.setup.io);
        for (self.registry.entries[0..self.registry.count]) |*entry| {
            entry.touched.store(false, .monotonic);
            entry.sweep.store(sweep_undecided, .monotonic);
        }
    }

    /// The numbers of `kind`.
    pub fn snapshot(self: *const Engine, kind: *const Kind) ?stats_rules.Snapshot {
        const index = self.registry.indexOf(kind) orelse return null;
        return self.stats.snapshot(index);
    }

    /// Write the report line of spec §11.
    pub fn report(self: *const Engine, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var scratch: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer scratch.deinit();
        const names = self.registry.names(scratch.allocator()) catch return error.WriteFailed;
        try stats_rules.writeReport(writer, &self.stats, names);
    }

    /// The text of the last cycle found, e.g. `a(1) -> b(2) -> a(1)`, or "".
    pub fn lastCycle(self: *Engine, a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        self.notes.mutex.lockUncancelable(self.setup.io);
        defer self.notes.mutex.unlock(self.setup.io);
        return a.dupe(u8, self.notes.cycle);
    }

    /// The text of the last verify mismatch, or "".
    pub fn lastMismatch(self: *Engine, a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        self.notes.mutex.lockUncancelable(self.setup.io);
        defer self.notes.mutex.unlock(self.setup.io);
        return a.dupe(u8, self.notes.mismatch);
    }

    /// The `Host` a context asks for dependencies.
    pub fn host(self: *Engine) Host {
        return .{ .ptr = self, .world = self.setup.world, .assumptions = self.setup.config.assumptions, .vtable = &host_vtable };
    }

    fn fetch(self: *Engine, kind: *const Kind, argument: []const u8, parent: ?*const Frame) Error!Fetched {
        if (argument.len > digest_rules.max_argument) return error.ArgumentTooLong;
        const index = self.registry.indexOf(kind) orelse return error.UnknownKind;
        const key = digest_rules.key(kind.name, kind.identity, argument);
        return (try self.resolve(index, key, argument, parent, true)).?;
    }

    fn fetchKeyed(self: *Engine, kind_name: []const u8, key: Digest, parent: ?*const Frame) Error!?Fetched {
        const index = self.registry.byName(kind_name) orelse return null;
        return self.resolve(index, key, null, parent, true);
    }

    /// Answer the query stored under `key` for the kind at `index`: from the memo, from a validated record, or by
    /// running the kind. `given` is the argument when the caller has it; a keyed fetch takes it from the record, and
    /// answers null when there is no record to take it from. With `compute` false a query that would have to run answers
    /// null instead: the caller only wants to know whether a record serves it.
    fn resolve(self: *Engine, index: usize, key: Digest, given: ?[]const u8, parent: ?*const Frame, compute: bool) Error!?Fetched {
        const io = self.setup.io;
        if (self.memory.result(io, key)) |known| {
            self.stats.add(index, .memo_hits);
            return .{ .key = key, .result = known, .memoized = true };
        }
        const kind = self.registry.entries[index].kind;
        var frame: Frame = .{ .kind = kind, .key = key, .argument = given orelse "", .parent = parent, .depth = if (parent) |up| up.depth + 1 else 0 };
        try self.guard(&frame);
        var arena: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        self.touchOnce(index, a);
        const found = try self.lookup(index, key, &frame, a);
        const stale = switch (found) {
            .served => |fetched| return fetched,
            .missed => |argument| argument,
        };
        if (!compute) return null;
        const argument = given orelse stale orelse return null;
        frame.argument = argument;
        const recomputed = try self.recompute(index, key, argument, &frame, a);
        return recomputed;
    }

    fn guard(self: *Engine, frame: *const Frame) Error!void {
        if (frame.depth > self.setup.config.depth_limit) return error.DepthExceeded;
        var up = frame.parent;
        while (up) |earlier| : (up = earlier.parent) {
            if (!std.mem.eql(u8, &earlier.key, &frame.key)) continue;
            self.noteCycle(frame, earlier);
            return error.Cycle;
        }
    }

    fn noteCycle(self: *Engine, frame: *const Frame, back_to: *const Frame) void {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.setup.gpa);
        // The frames from the query that was asked again back to its first asking, printed oldest first.
        var chain: [64]*const Frame = undefined;
        var length: usize = 0;
        var up: ?*const Frame = frame.parent;
        while (up) |walk| : (up = walk.parent) {
            if (length == chain.len) break;
            chain[length] = walk;
            length += 1;
            if (walk == back_to) break;
        }
        var at = length;
        while (at > 0) {
            at -= 1;
            const shown = chain[at].argument[0..@min(chain[at].argument.len, 40)];
            text.print(self.setup.gpa, "{s}({s}) -> ", .{ chain[at].kind.name, shown }) catch return;
        }
        text.print(self.setup.gpa, "{s}({s})", .{ frame.kind.name, frame.argument[0..@min(frame.argument.len, 40)] }) catch return;
        const owned = self.setup.gpa.dupe(u8, text.items) catch return;
        self.notes.mutex.lockUncancelable(self.setup.io);
        defer self.notes.mutex.unlock(self.setup.io);
        self.setup.gpa.free(self.notes.cycle);
        self.notes.cycle = owned;
    }

    fn touchOnce(self: *Engine, index: usize, a: std.mem.Allocator) void {
        const entry = &self.registry.entries[index];
        if (entry.touched.swap(true, .monotonic)) return;
        self.store.touch(a, entry.directory, self.setup.world.now());
    }

    fn timer(self: *const Engine) i96 {
        return if (self.setup.config.timing) stats_rules.tick(self.setup.io) else 0;
    }

    fn lap(self: *Engine, index: usize, which: stats_rules.Timer, started: i96) void {
        if (!self.setup.config.timing) return;
        self.stats.addTime(index, which, @intCast(@max(0, stats_rules.tick(self.setup.io) - started)));
    }

    /// Open the record of `key`, walk its reads, and serve it if every one is as it was seen. The work directory holds one file for a key and may
    /// hold the key in its packs; when the file is absent or its reads no longer hold, the packs are asked, newest first, and then the shared tier for
    /// its variants of the key in turn, so a tree whose files differ from the tree that published first is served what a tree with its files published.
    fn lookup(self: *Engine, index: usize, key: Digest, frame: *Frame, a: std.mem.Allocator) Error!Lookup {
        const entry = &self.registry.entries[index];
        const started = self.timer();
        const path = try self.store.recordPath(a, entry.directory, key);
        // The filter is asked only when the tier is: a local hit outside a sweep never asks it.
        const asked = frame.argument;
        const tier = self.tierOf(entry);
        const local = try self.store.load(a, path);
        self.lap(index, .lookup, started);
        var stale: ?[]const u8 = null;
        // A file of the key that does not serve is removed when a pack or the tier serves the key: it is the older, and would be read and refused by every build.
        var refused = false;
        if (local) |bytes| switch (try self.consider(index, key, frame, a, .{ .bytes = bytes, .tier = tier })) {
            .served => |fetched| return .{ .served = fetched },
            .stale => |argument| {
                stale = argument;
                refused = true;
            },
            .unusable => refused = true,
        };
        switch (try self.fromPacks(index, key, frame, a, tier)) {
            .served => |fetched| {
                if (refused) self.store.remove(path);
                return .{ .served = fetched };
            },
            .missed => |argument| if (argument) |older| {
                stale = older;
            },
        }
        const known = self.tierFor(entry, asked) orelse return .{ .missed = stale };
        for (0..shared_variants) |slot| {
            const began = self.timer();
            const fetched = known.fetch(a, digest_rules.variantKey(key, slot));
            self.lap(index, .lookup, began);
            const bytes = fetched orelse break;
            switch (try self.consider(index, key, frame, a, .{ .bytes = bytes, .tier = tier, .source = .shared })) {
                .served => |served| {
                    if (refused) self.store.remove(path);
                    return .{ .served = served };
                },
                .stale => |argument| stale = argument,
                .unusable => {},
            }
        }
        return .{ .missed = stale };
    }

    /// The packs' records of `key`, the newest pack first, until one serves. The packs are read at the first local miss of the process.
    fn fromPacks(self: *Engine, index: usize, key: Digest, frame: *Frame, a: std.mem.Allocator, tier: ?shared_rules.Tier) Error!Lookup {
        if (!self.local.isOpen()) self.openPacks();
        var stale: ?[]const u8 = null;
        for (0..self.local.count()) |at| {
            const bytes = self.local.find(self.setup.io, at, key) orelse continue;
            switch (try self.consider(index, key, frame, a, .{ .bytes = bytes, .tier = tier, .source = .pack })) {
                .served => |fetched| {
                    self.local.markUsed(at);
                    return .{ .served = fetched };
                },
                .stale => |argument| stale = argument,
                .unusable => {},
            }
        }
        return .{ .missed = stale };
    }

    /// Read the work directory's packs that hold records of a kind registered here, at the identity it has.
    fn openPacks(self: *Engine) void {
        var scratch: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer scratch.deinit();
        const groups = scratch.allocator().alloc(pack_rules.Group, self.registry.count) catch return;
        for (self.registry.entries[0..self.registry.count], groups) |entry, *group| group.* = .{ .kind = entry.kind.name, .identity = entry.kind.identity };
        self.local.open(self.setup.gpa, &self.store, groups);
    }

    /// Write the records this process adopted as a pack (or as files when there are few), and stamp the packs it served from.
    fn flushLocal(self: *Engine) void {
        if (self.local.idle()) return;
        var scratch: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer scratch.deinit();
        const kinds = scratch.allocator().alloc(local_rules.KindInfo, self.registry.count) catch return;
        for (self.registry.entries[0..self.registry.count], kinds) |entry, *info| info.* = .{ .name = entry.kind.name, .identity = entry.kind.identity, .directory = entry.directory };
        self.local.flush(self.setup.gpa, &self.store, kinds, self.setup.config.policy.pack_min_records, self.setup.world.now());
    }

    /// Decode one candidate record of `key` and serve it if every read still holds. A candidate served from the shared tier, or from a pack
    /// with its tuples refreshed, is queued for the pack this process writes when it ends, so the next process finds it locally.
    fn consider(self: *Engine, index: usize, key: Digest, frame: *Frame, a: std.mem.Allocator, offer: Offer) Error!Candidate {
        const bytes = offer.bytes;
        const entry = &self.registry.entries[index];
        const kind = entry.kind;
        const found = record_rules.decode(a, bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .unusable,
        };
        const ours = std.mem.eql(u8, found.kind, kind.name) and std.mem.eql(u8, &found.key, &key) and std.mem.eql(u8, &found.identity, &kind.identity);
        if (!ours) return .unusable;
        frame.argument = found.argument;
        const started = self.timer();
        var refreshes: std.ArrayList(Refresh) = .empty;
        const valid = try self.validateRecord(found, frame, a, &refreshes);
        self.lap(index, .validate, started);
        self.stats.add(index, .validated);
        if (!valid) return .{ .stale = found.argument };
        const refreshed = refreshes.items.len != 0 and self.refresh(index, found, refreshes.items, a, offer.source != .loose);
        self.stats.add(index, .served);
        switch (offer.source) {
            .shared => {
                // A record the refresh just queued carries this tree's stat tuples; queueing the shared bytes over it would undo that, and the next
                // build would hash the files again (G4c3).
                if (!refreshed) self.local.queue(self.setup.gpa, self.setup.io, key, @intCast(index), bytes);
                self.stats.add(index, .shared_hits);
            },
            .loose, .pack => if (offer.tier) |known| {
                if (self.sweeping(index, known, a) and self.allows(entry, found.argument)) self.backfill(index, known, found, bytes, a);
            },
        }
        if (self.sampled(key)) try self.verify(index, found, frame, a);
        const body: context_rules.Body = switch (found.payload) {
            .inline_bytes => |inline_bytes| .{ .resident = inline_bytes },
            .object => |object| .{ .lazy = try self.lazyCell(index, found, object) },
        };
        const kept = try self.memory.remember(self.setup.io, key, body, found.result, found.parts);
        return .{ .served = .{ .key = key, .result = kept } };
    }

    /// The handle on the object `object` that the served record `found` names. Nothing is read: validation trusts the
    /// record's trailer and the object's name, and the object is opened when a caller first asks for the payload.
    fn lazyCell(self: *Engine, index: usize, found: Record, object: Digest) Error!*context_rules.Lazy {
        const io = self.setup.io;
        const cell = try self.memory.create(io, Cell);
        cell.* = .{
            .base = .{ .load = loadCell, .io = io },
            .engine = self,
            .index = index,
            .key = found.key,
            .argument = try self.memory.keep(io, found.argument),
            .object = object,
            .digest = found.result,
        };
        return &cell.base;
    }

    /// Read the object of `cell` for the first use of a served payload. An object that is absent or does not hash to its
    /// name is a miss (spec §5): the query runs again, its record and object are published whole, and the new payload is
    /// answered. Nothing is an error unless the kind now fails or gives a result other than the one the record promised.
    fn readPayload(self: *Engine, cell: *Cell) Error![]const u8 {
        var arena: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        self.stats.add(cell.index, .object_reads);
        if (try self.store.loadObject(a, cell.object)) |bytes| return self.memory.keep(self.setup.io, bytes);
        if (self.sharedObject(cell, a)) |bytes| return self.memory.keep(self.setup.io, bytes);
        self.stats.add(cell.index, .object_misses);
        const started = self.timer();
        var frame: Frame = .{ .kind = self.registry.entries[cell.index].kind, .key = cell.key, .argument = cell.argument, .parent = null, .depth = 0 };
        const execution = try self.execute(cell.index, cell.argument, &frame, a);
        _ = self.publishExecution(cell.index, cell.key, cell.argument, execution, a);
        self.stats.add(cell.index, .recomputed);
        self.lap(cell.index, .compute, started);
        const promised = self.memory.result(self.setup.io, cell.key);
        const parts_agree = if (promised) |held| sameParts(execution.parts, held.parts) else true;
        if (!std.mem.eql(u8, &execution.digest, &cell.digest) or !parts_agree) {
            self.stats.add(cell.index, .verify_mismatches);
            self.noteMissedObject(cell, execution);
            return error.VerifyMismatch;
        }
        return self.memory.keep(self.setup.io, execution.payload);
    }

    /// Whether every read of `found` still holds, in order, stopping at the first that does not. A file found unchanged by
    /// its hash, whose stat tuple can now be trusted, is added to `refreshes`.
    fn validateRecord(self: *Engine, found: Record, frame: *const Frame, a: std.mem.Allocator, refreshes: *std.ArrayList(Refresh)) Error!bool {
        const host_view = self.host();
        for (found.reads, 0..) |read, at| {
            if (read != .query and read != .part) {
                switch (try validate.check(host_view, a, read)) {
                    .same => {},
                    .refreshed => |stat| try refreshes.append(a, .{ .index = at, .stat = stat }),
                    .changed => return false,
                }
                continue;
            }
            const fetched = (try self.fetchDependency(read, frame)) orelse return false;
            const holds = switch (read) {
                .query => |dependency| std.mem.eql(u8, &fetched.result.digest, &dependency.result),
                .part => |projection| partsHold(fetched.result.parts, projection.parts),
                else => unreachable,
            };
            if (!holds) return false;
            const kind_name = if (read == .query) read.query.kind else read.part.kind;
            if (fetched.fresh) if (self.registry.byName(kind_name)) |dependent| self.stats.add(dependent, .early_cutoffs);
        }
        return true;
    }

    /// The dependency a query read or a part read names, validated or recomputed. Null when it cannot be answered from its
    /// key (no such kind, no record to take the argument from), when answering it finds a recorded cycle, or when its kind now
    /// fails (a unit kind asked under the argument of a program that is not this one, G-D13): the record is then not valid,
    /// and its recomputation reads what it reads now, reporting a real cycle or failure if there is one.
    fn fetchDependency(self: *Engine, read: record_rules.Read, frame: *const Frame) Error!?Fetched {
        const kind_name = if (read == .query) read.query.kind else read.part.kind;
        const key = if (read == .query) read.query.key else read.part.key;
        return self.fetchKeyed(kind_name, key, frame) catch |err| switch (err) {
            error.Cycle, error.Failed => null,
            else => err,
        };
    }

    /// Rewrite the record `found` with the stat tuples of the files that were hashed to validate it, so the next process
    /// finds the tuples unchanged and hashes nothing. A record served from a pack or the tier is `queued` for the next pack; a loose one is
    /// written over its file. A failure leaves the old record, which is as valid as it was.
    fn refresh(self: *Engine, index: usize, found: Record, updates: []const Refresh, a: std.mem.Allocator, queued: bool) bool {
        const reads = a.dupe(record_rules.Read, found.reads) catch return false;
        for (updates) |update| reads[update.index].file.stat = update.stat;
        var rewritten = found;
        rewritten.reads = reads;
        const entry = &self.registry.entries[index];
        const bytes = record_rules.encode(a, rewritten) catch return false;
        if (queued) {
            self.local.queue(self.setup.gpa, self.setup.io, found.key, @intCast(index), bytes);
            self.stats.add(index, .refreshed);
            return true;
        }
        const path = self.store.recordPath(a, entry.directory, found.key) catch return false;
        const written = self.store.publish(a, path, bytes) catch false;
        if (written) self.stats.add(index, .refreshed);
        return written;
    }

    /// Run the kind for the key, publish the record, and answer.
    fn recompute(self: *Engine, index: usize, key: Digest, argument: []const u8, frame: *Frame, a: std.mem.Allocator) Error!Fetched {
        const kind = self.registry.entries[index].kind;
        var claimed = false;
        if (kind.expensive) switch (try store_rules.claim(&self.store, a, key)) {
            .claimed => claimed = true,
            .held => if (try self.awaitOther(index, key, frame, a)) |served| return served,
            .unavailable => {},
        };
        defer if (claimed) store_rules.release(&self.store, key);
        const started = self.timer();
        const execution = try self.execute(index, argument, frame, a);
        const published = self.publishExecution(index, key, argument, execution, a);
        if (published) |kept| if (self.tierFor(&self.registry.entries[index], argument)) |known| {
            self.publishShared(index, known, .{ .key = key, .bytes = kept.bytes, .result = execution.digest, .signature = kept.signature, .object = kept.object }, a);
        };
        const kept = try self.memory.remember(self.setup.io, key, .{ .resident = execution.payload }, execution.digest, execution.parts);
        self.stats.add(index, .recomputed);
        self.lap(index, .compute, started);
        return .{ .key = key, .result = kept, .fresh = true };
    }

    /// Wait for another process's computation of `key` to publish, for at most the kind's wait bound. Null when it
    /// did not (it died, or was slow): the caller computes.
    fn awaitOther(self: *Engine, index: usize, key: Digest, frame: *Frame, a: std.mem.Allocator) Error!?Fetched {
        const kind = self.registry.entries[index].kind;
        const io = self.setup.io;
        const begun = stats_rules.tick(io);
        const bound = @as(i96, kind.wait_ms) * std.time.ns_per_ms;
        var pause: i64 = 5;
        while (try store_rules.claimed(&self.store, a, key)) {
            if (stats_rules.tick(io) - begun > bound) return null;
            std.Io.sleep(io, .fromMilliseconds(pause), .awake) catch return null;
            pause = @min(pause * 2, 100);
            switch (try self.lookup(index, key, frame, a)) {
                .served => |fetched| return fetched,
                .missed => {},
            }
        }
        return switch (try self.lookup(index, key, frame, a)) {
            .served => |fetched| fetched,
            .missed => null,
        };
    }

    /// Run the kind with a fresh context. Nothing is stored.
    fn execute(self: *Engine, index: usize, argument: []const u8, frame: *const Frame, a: std.mem.Allocator) Error!Execution {
        const kind = self.registry.entries[index].kind;
        var ctx = Context.init(self.host(), frame.*, a);
        ctx.frame.argument = argument;
        const payload = kind.run(&ctx, argument) catch |err| {
            ctx.close();
            return err;
        };
        ctx.close();
        const digest = if (kind.result_digest) |identity| identity(payload) else digest_rules.hash(payload);
        return .{ .payload = payload, .digest = digest, .reads = ctx.reads(), .parts = ctx.exposedParts() };
    }

    /// Publish the record of a computation to the work directory's store. What the shared tier takes (the encoded record, and
    /// the payload when it is an object), or null when nothing was published.
    fn publishExecution(self: *Engine, index: usize, key: Digest, argument: []const u8, execution: Execution, a: std.mem.Allocator) ?Published {
        const entry = &self.registry.entries[index];
        var payload: record_rules.Payload = .{ .inline_bytes = execution.payload };
        if (execution.payload.len > store_rules.object_threshold) {
            const object = digest_rules.hash(execution.payload);
            const stored = self.store.publishObject(a, object, execution.payload) catch return null;
            if (!stored) return null;
            payload = .{ .object = object };
        }
        const fresh: Record = .{
            .kind = entry.kind.name,
            .identity = entry.kind.identity,
            .key = key,
            .argument = argument,
            .result = execution.digest,
            .payload = payload,
            .reads = execution.reads,
            .parts = execution.parts,
        };
        const bytes = record_rules.encode(a, fresh) catch return null;
        const path = self.store.recordPath(a, entry.directory, key) catch return null;
        _ = self.store.publish(a, path, bytes) catch return null;
        return .{ .bytes = bytes, .signature = record_rules.readSignature(execution.reads), .object = if (payload == .object) execution.payload else null };
    }

    /// The bytes of the record of `key` in the shared tier, for the kind at `index`, when that kind is shared and the tier
    /// holds one. Read-only: nothing is adopted and nothing is counted.
    pub fn sharedBytes(self: *const Engine, index: usize, key: Digest, a: std.mem.Allocator) ?[]const u8 {
        const tier = self.tierOf(&self.registry.entries[index]) orelse return null;
        return tier.fetch(a, key);
    }

    /// The encoded record under `key` in the newest pack that holds one, or null. Read-only: nothing is served, adopted or counted. `explain` asks it after the
    /// file of the key, as a lookup does.
    pub fn packedBytes(self: *Engine, key: Digest) ?[]const u8 {
        if (!self.local.isOpen()) self.openPacks();
        for (0..self.local.count()) |at| {
            if (self.local.find(self.setup.io, at, key)) |bytes| return bytes;
        }
        return null;
    }

    /// The shared tier when the kind of `entry` is shared and there is one.
    fn tierOf(self: *const Engine, entry: *const Entry) ?shared_rules.Tier {
        return if (entry.shared) self.setup.config.shared else null;
    }

    /// The shared tier for the query of `entry`'s kind with `argument`: the tier, unless the kind has a filter that does not
    /// allow the query. A query whose argument is not known (a fetch by key) is not allowed by a filter.
    fn tierFor(self: *const Engine, entry: *const Entry, argument: []const u8) ?shared_rules.Tier {
        const known = self.tierOf(entry) orelse return null;
        return if (self.allows(entry, argument)) known else null;
    }

    /// Whether the kind's filter lets the query with `argument` use the shared tier (a kind without a filter lets every one).
    fn allows(_: *const Engine, entry: *const Entry, argument: []const u8) bool {
        const filter = entry.filter orelse return true;
        if (argument.len == 0) return false;
        return filter.allows(filter.context, argument);
    }

    /// Publish a record to the shared tier and count what it did. A record whose payload is an object goes after the object, so
    /// no record names an object the tier lacks; a tier that keeps no objects takes no such record.
    fn publishShared(self: *Engine, index: usize, tier: shared_rules.Tier, outgoing: Outgoing, a: std.mem.Allocator) void {
        if (outgoing.object) |payload| {
            if (!tier.holdsObjects()) return;
            switch (tier.publishObject(a, digest_rules.hash(payload), payload)) {
                .stored, .present => {},
                .mismatch, .skipped, .failed => return,
            }
        }
        switch (tier.publish(a, digest_rules.variantKey(outgoing.key, variantSlot(tier, a, outgoing)), outgoing.bytes, outgoing.result)) {
            .stored, .present => self.stats.add(index, .shared_published),
            .mismatch => self.stats.add(index, .shared_mismatches),
            .skipped, .failed => {},
        }
    }

    /// The slot of the shared tier that `outgoing` goes to: the slot of a variant with the same read signature (the tier then compares
    /// the two results, and a difference is a determinism mismatch), else the first free slot, else, when every slot holds another
    /// variant, one chosen by the signature, which that publication replaces. Slots fill from the first, so a lookup stops at the first
    /// absent one. A damaged record is replaced where it lies.
    fn variantSlot(tier: shared_rules.Tier, a: std.mem.Allocator, outgoing: Outgoing) usize {
        for (0..shared_variants) |slot| {
            const at = digest_rules.variantKey(outgoing.key, slot);
            const held = tier.fetch(a, at) orelse return slot;
            const existing = record_rules.decode(a, held) catch {
                tier.forget(at);
                return slot;
            };
            if (std.mem.eql(u8, &record_rules.readSignature(existing.reads), &outgoing.signature)) return slot;
        }
        const victim = std.mem.readInt(u32, outgoing.signature[0..4], .little) % shared_variants;
        tier.forget(digest_rules.variantKey(outgoing.key, victim));
        return victim;
    }

    /// Whether the tier is asked about the records of the kind at `index` that the work directory serves, in this process. It is when the partition
    /// has no stamp, its stamp is older than `Policy.sweep_interval_ns`, or it was made against another tier or by a clock that is ahead of ours;
    /// and always when the tier cannot name itself. The process that asks stamps the partition when it ends (`stampSwept`), so the next builds of
    /// the hour skip the tier's header and the second hash of the record that asking costs. What asking does for the tier (fill it with a record it
    /// lacks, refresh the recency of one it has, repair one that was damaged or evicted) happens once an hour instead of every build. A record this
    /// process computes is published when it is computed, and one it takes from the tier is already there; neither waits for a sweep.
    fn sweeping(self: *Engine, index: usize, tier: shared_rules.Tier, a: std.mem.Allocator) bool {
        const entry = &self.registry.entries[index];
        switch (entry.sweep.load(.acquire)) {
            sweep_due => {
                entry.swept.store(true, .monotonic);
                return true;
            },
            sweep_done => return false,
            else => {},
        }
        const due = self.sweepDue(entry, tier, a);
        entry.sweep.store(if (due) sweep_due else sweep_done, .release);
        if (due) entry.swept.store(true, .monotonic);
        return due;
    }

    fn sweepDue(self: *Engine, entry: *const Entry, tier: shared_rules.Tier, a: std.mem.Allocator) bool {
        const named = tier.identity() orelse return true;
        const last = self.store.sweptAt(a, entry.directory, named) orelse return true;
        const now = self.setup.world.now();
        return now < last or now - last >= self.setup.config.policy.sweep_interval_ns;
    }

    /// Stamp the partitions this process asked the tier about, so that the next process finds them swept. A process that serves a kind's records
    /// has asked about all of them by the time it ends; one that dies first leaves no stamp, and the next process asks again.
    fn stampSwept(self: *Engine) void {
        const tier = self.setup.config.shared orelse return;
        const named = tier.identity() orelse return;
        var arena: std.heap.ArenaAllocator = .init(self.setup.gpa);
        defer arena.deinit();
        const now = self.setup.world.now();
        for (self.registry.entries[0..self.registry.count]) |*entry| {
            if (entry.swept.swap(false, .acq_rel)) self.store.markSwept(arena.allocator(), entry.directory, now, named);
        }
    }

    /// A record served from the work directory that the shared tier lacks goes to the tier, so a tree that ran before the
    /// tier existed fills it too. The tier lacks it when no slot of its key holds a record with the same reads: a first slot
    /// that holds another variant does not make this one shared (`variantSlot` finds the slot, or the free one). A record with an
    /// object payload goes with its object when the tier keeps objects and the work directory still has it, and stays local
    /// otherwise.
    fn backfill(self: *Engine, index: usize, tier: shared_rules.Tier, found: Record, bytes: []const u8, a: std.mem.Allocator) void {
        if (found.payload == .object and !tier.holdsObjects()) return;
        // A tier that holds these very bytes says so from the record's header, without a read of the record: the usual answer for a record
        // that this tree published, and the reason a build costs the tier one stat and one small read for each record it serves.
        if (tier.holds(found.key, bytes)) return;
        if (tier.fetch(a, found.key)) |held| if (std.mem.eql(u8, held, bytes) or sharesReads(held, found, a)) return;
        const object: ?[]const u8 = switch (found.payload) {
            .inline_bytes => null,
            .object => |digest| (self.store.loadObject(a, digest) catch null) orelse return,
        };
        self.publishShared(index, tier, .{ .key = found.key, .bytes = bytes, .result = found.result, .signature = record_rules.readSignature(found.reads), .object = object }, a);
    }

    /// Whether the tier's record `held` has the reads of `found` and its result: the same variant of the key, whatever the stat tuples of
    /// its reads say. A record that cannot be decoded is not it.
    fn sharesReads(held: []const u8, found: Record, a: std.mem.Allocator) bool {
        const other = record_rules.decode(a, held) catch return false;
        return std.mem.eql(u8, &other.result, &found.result) and std.mem.eql(u8, &record_rules.readSignature(other.reads), &record_rules.readSignature(found.reads));
    }

    /// The object `cell` names, taken from the shared tier when the work directory lacks it: the bytes must hash to the name,
    /// and the work directory keeps a copy, so the next read finds it locally. Null when the kind is not shared, the tier keeps
    /// no objects or it lacks this one.
    fn sharedObject(self: *Engine, cell: *const Cell, a: std.mem.Allocator) ?[]const u8 {
        const tier = self.tierFor(&self.registry.entries[cell.index], cell.argument) orelse return null;
        const bytes = tier.fetchObject(a, cell.object) orelse return null;
        if (!std.mem.eql(u8, &digest_rules.hash(bytes), &cell.object)) return null;
        _ = self.store.publishObject(a, cell.object, bytes) catch false;
        return bytes;
    }

    /// Whether verify mode recomputes the served query under `key`: one in `verify_every`, by the key's first bytes.
    fn sampled(self: *const Engine, key: Digest) bool {
        const every = self.setup.config.verify_every;
        return every != 0 and digest_rules.sample(key) % every == 0;
    }

    /// Recompute a served query and compare result digests (spec §10).
    fn verify(self: *Engine, index: usize, found: Record, frame: *const Frame, a: std.mem.Allocator) Error!void {
        // A kind that cannot recompute (it fails) leaves the record unverified; that is counted, not an error.
        const execution = self.execute(index, found.argument, frame, a) catch |err| switch (err) {
            error.Failed => return self.stats.add(index, .unverifiable),
            else => return err,
        };
        self.stats.add(index, .verified);
        if (std.mem.eql(u8, &execution.digest, &found.result) and sameParts(execution.parts, found.parts)) return self.verifyObject(index, found, execution, a);
        self.stats.add(index, .verify_mismatches);
        self.noteMismatch(found, execution, a);
        // Heal the record, so the next run does not fail on the same one: the error is still reported.
        _ = self.publishExecution(index, found.key, found.argument, execution, a);
        return error.VerifyMismatch;
    }

    /// A sampled query whose payload is an object: read the object as a caller would, and compare it with the recomputation.
    /// An object that is absent or damaged is healed from the recomputation, as a first use would, and is no mismatch.
    fn verifyObject(self: *Engine, index: usize, found: Record, execution: Execution, a: std.mem.Allocator) Error!void {
        const object = switch (found.payload) {
            .object => |digest| digest,
            .inline_bytes => return,
        };
        self.stats.add(index, .object_reads);
        const stored = (try self.store.loadObject(a, object)) orelse {
            self.stats.add(index, .object_misses);
            _ = self.publishExecution(index, found.key, found.argument, execution, a);
            return;
        };
        // A kind with its own result identity may differ in bytes that identity ignores; the others agree byte for byte.
        if (self.registry.entries[index].kind.result_digest != null or std.mem.eql(u8, stored, execution.payload)) return;
        self.stats.add(index, .verify_mismatches);
        self.noteMismatch(found, execution, a);
        _ = self.publishExecution(index, found.key, found.argument, execution, a);
        return error.VerifyMismatch;
    }

    fn noteMissedObject(self: *Engine, cell: *const Cell, execution: Execution) void {
        const text = std.fmt.allocPrint(self.setup.gpa, "E_ENGINE_VERIFY: {s} {s}: recorded result {s}, recomputed {s} when its stored object was missing or damaged at first use", .{
            self.registry.entries[cell.index].kind.name,
            digest_rules.hex(cell.key)[0..16],
            digest_rules.hex(cell.digest)[0..8],
            digest_rules.hex(execution.digest)[0..8],
        }) catch return;
        self.notes.mutex.lockUncancelable(self.setup.io);
        defer self.notes.mutex.unlock(self.setup.io);
        self.setup.gpa.free(self.notes.mismatch);
        self.notes.mismatch = text;
    }

    fn noteMismatch(self: *Engine, found: Record, execution: Execution, a: std.mem.Allocator) void {
        const first = firstDivergence(found.reads, execution.reads);
        const where: []const u8 = if (first) |at| (validate.describe(a, if (at < found.reads.len) found.reads[at] else execution.reads[at]) catch "a read") else "none: the same reads gave another result";
        const text = std.fmt.allocPrint(self.setup.gpa, "E_ENGINE_VERIFY: {s} {s}: recorded result {s}, recomputed {s}{s}; first read that no longer reproduces: {s}", .{
            found.kind,
            digest_rules.hex(found.key)[0..16],
            digest_rules.hex(found.result)[0..8],
            digest_rules.hex(execution.digest)[0..8],
            if (std.mem.eql(u8, &found.result, &execution.digest)) " (the parts table differs)" else "",
            where,
        }) catch return;
        self.notes.mutex.lockUncancelable(self.setup.io);
        defer self.notes.mutex.unlock(self.setup.io);
        self.setup.gpa.free(self.notes.mismatch);
        self.notes.mismatch = text;
    }
};

/// Whether every part a projection read named is as it was seen in `parts`, the table a dependency publishes now: present
/// again with the same digest, or absent again.
fn partsHold(parts: []const record_rules.Part, seen: []const record_rules.PartSight) bool {
    for (seen) |sight| {
        const now = context_rules.findPart(parts, sight.name);
        if (sight.present != (now != null)) return false;
        if (now) |digest| if (!std.mem.eql(u8, &digest, &sight.digest)) return false;
    }
    return true;
}

/// Whether two parts tables name the same parts with the same digests.
fn sameParts(left: []const record_rules.Part, right: []const record_rules.Part) bool {
    if (left.len != right.len) return false;
    for (left, right) |was, is| {
        if (!std.mem.eql(u8, was.name, is.name) or !std.mem.eql(u8, &was.digest, &is.digest)) return false;
    }
    return true;
}

/// The index of the first read at which the recorded reads and the recomputed reads differ in what they saw, or in
/// shape (one list is longer); null when they agree throughout.
pub fn firstDivergence(old: []const record_rules.Read, fresh: []const record_rules.Read) ?usize {
    const common = @min(old.len, fresh.len);
    for (old[0..common], fresh[0..common], 0..) |was, is, at| {
        if (!validate.sameSight(was, is)) return at;
    }
    return if (old.len == fresh.len) null else common;
}

fn loadCell(lazy: *context_rules.Lazy) Error![]const u8 {
    const cell: *Cell = @fieldParentPtr("base", lazy);
    return cell.engine.readPayload(cell);
}

fn hostFetch(ptr: *anyopaque, kind: *const Kind, argument: []const u8, parent: *const Frame) Error!Fetched {
    const engine: *Engine = @ptrCast(@alignCast(ptr));
    return engine.fetch(kind, argument, parent);
}

fn hostFetchKeyed(ptr: *anyopaque, kind_name: []const u8, key: Digest, parent: *const Frame) Error!?Fetched {
    const engine: *Engine = @ptrCast(@alignCast(ptr));
    return engine.fetchKeyed(kind_name, key, parent);
}

fn hostStat(ptr: *anyopaque, path: []const u8) ?world_rules.Stat {
    const engine: *Engine = @ptrCast(@alignCast(ptr));
    return engine.memory.stat(engine.setup.io, engine.setup.world, path);
}

fn hostListing(ptr: *anyopaque, path: []const u8, filter: u8) Error!?Digest {
    const engine: *Engine = @ptrCast(@alignCast(ptr));
    return engine.memory.listing(engine.setup.io, engine.setup.world, engine.setup.gpa, path, filter);
}

fn hostTool(ptr: *anyopaque, path: []const u8) Error!Digest {
    const engine: *Engine = @ptrCast(@alignCast(ptr));
    return engine.memory.tool(engine.setup.io, engine.setup.world, engine.setup.gpa, path);
}

const host_vtable: Host.VTable = .{ .fetch = hostFetch, .fetch_keyed = hostFetchKeyed, .stat = hostStat, .listing = hostListing, .tool = hostTool };
