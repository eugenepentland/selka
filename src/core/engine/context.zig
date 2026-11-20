//! The context a query reads through (spec §4) and the types of a query (spec §2): the kind, its result, the chain of
//! queries being evaluated, and the host the context asks for dependencies.
//!
//! A query receives one handle, `*Context`, and reads only through it: every file, existence test, directory listing,
//! variable, tool and other query goes through the context, which writes down what was seen. The list is the record
//! the engine stores. A query may also publish parts of its result (`exposePart`), a table of named digests that
//! travels with the record, and a dependent may read only some of them (`part`, spec §17.3). A read is recorded once, on its first occurrence, and a second read of it returns the first
//! answer, so a query sees one version of everything and its record lists every read once, in the order it first
//! happened. The context is closed when the query returns; a read after that is `error.ContextClosed`.
const std = @import("std");
const digest_rules = @import("digest.zig");
const record = @import("record.zig");
const world_rules = @import("world.zig");
const Digest = digest_rules.Digest;
const Stat = world_rules.Stat;
const Read = record.Read;

/// One part of a result: a name and the digest of what the part holds.
pub const Part = record.Part;

/// Why a query, a read or an evaluation failed.
pub const Error = error{
    OutOfMemory,
    /// A world read failed other than by the path being absent (a directory read as a file, an unreadable file).
    ReadFailed,
    /// The kind's own failure: its query cannot be answered. Nothing is stored.
    Failed,
    /// A query depends on itself.
    Cycle,
    /// A chain of queries deeper than the engine's limit (group the members under a parent query, spec §6).
    DepthExceeded,
    /// A read through a context whose query has returned.
    ContextClosed,
    /// An argument longer than `digest.max_argument`.
    ArgumentTooLong,
    /// A query of a kind the engine does not know.
    UnknownKind,
    /// Verify mode recomputed a served query and got another result (spec §10).
    VerifyMismatch,
};

/// A payload the engine has not read yet: the handle on a result stored as an object. The first `get` reads and hashes the
/// object and keeps the bytes for the rest of the revision; an object that is missing or damaged is a miss the engine
/// answers by running the query again, never an error (spec §5, lazy payloads). The engine's own cell embeds this struct
/// and recovers itself from the pointer.
pub const Lazy = struct {
    /// Read the payload, or compute it again. Called with the cell's lock held, until it succeeds once.
    load: *const fn (lazy: *Lazy) Error![]const u8,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    bytes: ?[]const u8 = null,

    /// The payload bytes, read on the first call. Safe to call from many threads; one of them reads.
    pub fn get(self: *Lazy) Error![]const u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.bytes) |known| return known;
        const loaded = try self.load(self);
        self.bytes = loaded;
        return loaded;
    }
};

/// Where a result keeps its payload: in memory, or behind a handle that reads it when first used.
pub const Body = union(enum) { resident: []const u8, lazy: *Lazy };

/// The answer to a query: the result digest, the table of parts the query published (in byte order of their names) and the
/// payload, which `payload` hands back. Validating a query never reads a stored object, so a served result whose payload is
/// large costs nothing until a caller asks for it. The parts and the payload are valid until the engine's next revision.
pub const Result = struct {
    digest: Digest,
    parts: []const Part = &.{},
    body: Body = .{ .resident = "" },

    /// A result whose payload is already in memory.
    pub fn resident(payload_bytes: []const u8, digest: Digest, parts: []const Part) Result {
        return .{ .digest = digest, .parts = parts, .body = .{ .resident = payload_bytes } };
    }

    /// The payload bytes. For a result stored as an object the first call reads it, and a missing or damaged object is
    /// recomputed (`error.VerifyMismatch` when the recomputation gives another result, `error.Failed` when the kind now fails).
    pub fn payload(self: Result) Error![]const u8 {
        return switch (self.body) {
            .resident => |bytes| bytes,
            .lazy => |cell| cell.get(),
        };
    }
};

/// A result and the key it is stored under. `fresh` is set when answering recomputed the query (a dependent whose
/// recorded result digest still matches then stays valid: an early cutoff); `memoized` when the process had already
/// answered it in this revision.
pub const Fetched = struct { key: Digest, result: Result, fresh: bool = false, memoized: bool = false };

/// A named query implementation (spec §2).
pub const Kind = struct {
    /// The kind's name: lowercase letters, digits, `.`, `_` and `-`, so it is one safe path component.
    name: []const u8,
    /// The code identity (spec §3): the digest of the import closure of the kind's roots.
    identity: Digest,
    /// The implementation. It returns the payload, allocated in `ctx.arena`.
    run: *const fn (ctx: *Context, argument: []const u8) Error![]const u8,
    /// An expensive kind (a test execution) writes an in-flight marker, and a second process waits for its record.
    expensive: bool = false,
    /// How long, in milliseconds, a process waits for another's in-flight computation before computing itself.
    wait_ms: u32 = 30_000,
    /// Data that is part of the kind's code, never of its inputs (a fixed table, a program a test kind interprets).
    data: ?*const anyopaque = null,
    /// A smaller identity of the payload than its digest (spec §2), or null for the digest of the payload.
    result_digest: ?*const fn (payload: []const u8) Digest = null,
};

/// One query being evaluated and the one that asked for it: the chain a cycle is found along.
pub const Frame = struct {
    kind: *const Kind,
    key: Digest,
    argument: []const u8,
    parent: ?*const Frame,
    depth: u32,
};

/// What a context asks of the engine that runs it. The engine implements this; the context never sees the engine.
pub const Host = struct {
    ptr: *anyopaque,
    world: world_rules.World,
    assumptions: world_rules.Assumptions,
    vtable: *const VTable,

    /// The function table of a host.
    pub const VTable = struct {
        /// Answer the query `kind(argument)` for a query running in frame `parent`.
        fetch: *const fn (ptr: *anyopaque, kind: *const Kind, argument: []const u8, parent: *const Frame) Error!Fetched,
        /// Answer the query of the kind named `kind` stored under `key`, taking its argument from its record; null
        /// when there is no such kind or record, or the record cannot be answered again.
        fetch_keyed: *const fn (ptr: *anyopaque, kind: []const u8, key: Digest, parent: *const Frame) Error!?Fetched,
        /// The stat tuple at `path` as of this revision.
        stat: *const fn (ptr: *anyopaque, path: []const u8) ?Stat,
        /// The listing digest of the directory at `path` under `filter` as of this revision, null when it will not open.
        listing: *const fn (ptr: *anyopaque, path: []const u8, filter: u8) Error!?Digest,
        /// The identity of the tool at `path` as of this revision, zero when it cannot be found.
        tool: *const fn (ptr: *anyopaque, path: []const u8) Error!Digest,
    };

    /// Answer `kind(argument)`.
    pub fn fetch(self: Host, kind: *const Kind, argument: []const u8, parent: *const Frame) Error!Fetched {
        return self.vtable.fetch(self.ptr, kind, argument, parent);
    }

    /// Answer the stored query of `kind` under `key`.
    pub fn fetchKeyed(self: Host, kind: []const u8, key: Digest, parent: *const Frame) Error!?Fetched {
        return self.vtable.fetch_keyed(self.ptr, kind, key, parent);
    }

    /// The memoized stat tuple at `path`.
    pub fn stat(self: Host, path: []const u8) ?Stat {
        return self.vtable.stat(self.ptr, path);
    }

    /// The memoized listing digest.
    pub fn listing(self: Host, path: []const u8, filter: u8) Error!?Digest {
        return self.vtable.listing(self.ptr, path, filter);
    }

    /// The memoized tool identity.
    pub fn tool(self: Host, path: []const u8) Error!Digest {
        return self.vtable.tool(self.ptr, path);
    }
};

/// What a context remembers of a read it has answered.
const Seen = struct { index: u32, bytes: ?[]const u8 = null, names: []const []const u8 = &.{}, result: ?Result = null };

/// The reads of one query, in the order they first happened, the answers to give when one repeats, and the parts the
/// query publishes.
const Recorder = struct {
    reads: std.ArrayList(Read) = .empty,
    seen: std.StringHashMapUnmanaged(Seen) = .empty,
    exposed: std.ArrayList(Part) = .empty,
    exposed_names: std.StringHashMapUnmanaged(usize) = .empty,
};

/// A file read's outcome before it is recorded.
const Observed = struct { read: record.FileRead, bytes: ?[]const u8 };

/// The handle a query reads through.
pub const Context = struct {
    host: Host,
    frame: Frame,
    /// Everything the query allocates: the answers to its reads, its payload. Freed when the evaluation ends.
    arena: std.mem.Allocator,
    recorder: Recorder = .{},
    closed: bool = false,

    /// A context for the query in `frame`, allocating from `arena`.
    pub fn init(host: Host, frame: Frame, arena: std.mem.Allocator) Context {
        return .{ .host = host, .frame = frame, .arena = arena };
    }

    /// The reads made so far, in order.
    pub fn reads(self: *const Context) []const Read {
        return self.recorder.reads.items;
    }

    /// End the query: later reads fail.
    pub fn close(self: *Context) void {
        self.closed = true;
    }

    /// The data of the kind being evaluated, as the type the kind stored.
    pub fn kindData(self: *const Context, comptime T: type) *const T {
        return @ptrCast(@alignCast(self.frame.kind.data.?));
    }

    /// The bytes of the file at `path`, or null when it is absent. The digest of the bytes, and the stat tuple seen
    /// around the hash, are recorded; a path that was looked for and was not there is recorded as absent.
    pub fn file(self: *Context, path: []const u8) Error!?[]const u8 {
        const slot = try self.identify('f', "", path);
        if (try self.opened(slot)) |seen| return seen.bytes;
        const found = try self.observe(path);
        try self.remember(slot, .{ .file = found.read }, .{ .index = 0, .bytes = found.bytes });
        return found.bytes;
    }

    /// Whether anything is at `path`. Recorded as only that: its bytes are not part of the answer.
    pub fn exists(self: *Context, path: []const u8) Error!bool {
        const slot = try self.identify('e', "", path);
        if (try self.opened(slot)) |seen| return self.recorder.reads.items[seen.index].exists.present;
        const present = self.host.world.stat(path) != null;
        try self.remember(slot, .{ .exists = .{ .path = try self.arena.dupe(u8, path), .present = present } }, .{ .index = 0 });
        return present;
    }

    /// The names filter number `filter` keeps in the directory at `path`, in byte order; a directory that will not
    /// open lists nothing. The digest of the sorted names is recorded, so a name appearing or going is a change.
    pub fn listing(self: *Context, path: []const u8, filter: u8) Error![]const []const u8 {
        const slot = try self.identify('l', &.{filter}, path);
        if (try self.opened(slot)) |seen| return seen.names;
        const listed = try self.host.world.list(self.arena, path, filter);
        const kept: []const []const u8 = listed orelse &.{};
        const sorted = try self.arena.dupe([]const u8, kept);
        std.mem.sort([]const u8, sorted, {}, nameBefore);
        const found: Digest = if (listed != null) try digest_rules.listingDigest(self.arena, sorted) else @splat(0);
        try self.remember(slot, .{ .listing = .{ .path = try self.arena.dupe(u8, path), .filter = filter, .opened = listed != null, .digest = found } }, .{ .index = 0, .names = sorted });
        return sorted;
    }

    /// Every variable that enters identities, as `NAME=VALUE` in byte order: the keyed environment of a run. Recorded as
    /// one listing, so a variable newly set, changed or unset is a change; a query that reads a few named variables
    /// reads them with `variable` instead.
    pub fn environment(self: *Context) Error![]const []const u8 {
        return self.listing(world_rules.environment_path, 0);
    }

    /// The value of the variable `name`, or null when it is unset. A placement variable is recorded as read and is
    /// never compared on validation.
    pub fn variable(self: *Context, variable_name: []const u8) Error!?[]const u8 {
        const slot = try self.identify('v', "", variable_name);
        if (try self.opened(slot)) |seen| return seen.bytes;
        const value = self.host.world.variable(variable_name);
        const copy: ?[]const u8 = if (value) |bytes| try self.arena.dupe(u8, bytes) else null;
        const placement = self.host.world.placement(variable_name);
        try self.remember(slot, .{ .variable = .{ .name = try self.arena.dupe(u8, variable_name), .set = copy != null, .value = copy orelse "", .placement = placement } }, .{ .index = 0, .bytes = copy });
        return copy;
    }

    /// The identity of the tool at `path`, or null when it cannot be found.
    pub fn tool(self: *Context, path: []const u8) Error!?Digest {
        const slot = try self.identify('t', "", path);
        if (try self.opened(slot)) |seen| return if (seen.bytes) |identity| identity[0..32].* else null;
        const found = try self.host.world.tool(self.arena, path);
        const identity: Digest = found orelse @splat(0);
        const kept: ?[]const u8 = if (found != null) try self.arena.dupe(u8, &identity) else null;
        try self.remember(slot, .{ .tool = .{ .path = try self.arena.dupe(u8, path), .identity = identity } }, .{ .index = 0, .bytes = kept });
        return found;
    }

    /// The answer of the query `kind(argument)`, validated or recomputed first. The dependency's key and result
    /// digest are recorded: this query stays valid while the dependency's result digest does. The answer's payload is read
    /// when `payload` is called on it, so a query that only compares digests never reads a stored object.
    pub fn query(self: *Context, kind: *const Kind, argument: []const u8) Error!Result {
        try self.ensureOpen();
        if (argument.len > digest_rules.max_argument) return error.ArgumentTooLong;
        const wanted = digest_rules.key(kind.name, kind.identity, argument);
        const slot = try self.identify('q', &wanted, "");
        if (try self.opened(slot)) |seen| return seen.result.?;
        const fetched = try self.host.fetch(kind, argument, &self.frame);
        try self.remember(slot, .{ .query = .{ .kind = kind.name, .key = fetched.key, .result = fetched.result.digest } }, .{ .index = 0, .result = fetched.result });
        return fetched.result;
    }

    /// What the dependency `kind(argument)` holds under each of `names`: the digest of the part, or null when the
    /// dependency published no part of that name. The answers are in the order of `names`. Only those parts are
    /// recorded, with the dependency's key: this query stays valid while they do, and a change to any other part of
    /// the dependency, or to its payload, leaves it valid (spec §17.3). The payload is not an answer here, so a query
    /// that needs it reads the dependency whole with `query`.
    pub fn part(self: *Context, kind: *const Kind, argument: []const u8, names: []const []const u8) Error![]const ?Digest {
        try self.ensureOpen();
        if (argument.len > digest_rules.max_argument) return error.ArgumentTooLong;
        const wanted = digest_rules.key(kind.name, kind.identity, argument);
        const asked = try self.arena.dupe([]const u8, names);
        std.mem.sort([]const u8, asked, {}, nameBefore);
        const distinct = distinctNames(asked);
        const slot = try self.identify('p', try self.projectionIdentity(&wanted, distinct), "");
        if (try self.opened(slot)) |seen| return self.partAnswers(self.recorder.reads.items[seen.index].part.parts, names);
        const fetched = try self.host.fetch(kind, argument, &self.frame);
        const sights = try self.arena.alloc(record.PartSight, distinct.len);
        for (distinct, sights) |name, *sight| {
            const found = findPart(fetched.result.parts, name);
            sight.* = .{ .name = try self.arena.dupe(u8, name), .present = found != null, .digest = found orelse @splat(0) };
        }
        try self.remember(slot, .{ .part = .{ .kind = kind.name, .key = fetched.key, .parts = sights } }, .{ .index = 0 });
        return self.partAnswers(sights, names);
    }

    /// Publish the part `name` of this query's result with the digest of what it holds. A dependent that reads the part
    /// is valid while the digest is. The table is part of the record; a name published twice must give the same digest.
    pub fn exposePart(self: *Context, name: []const u8, digest: Digest) Error!void {
        try self.ensureOpen();
        const slot = try self.recorder.exposed_names.getOrPut(self.arena, name);
        if (slot.found_existing) {
            if (!std.mem.eql(u8, &self.recorder.exposed.items[slot.value_ptr.*].digest, &digest)) return error.Failed;
            return;
        }
        const owned = try self.arena.dupe(u8, name);
        slot.key_ptr.* = owned;
        slot.value_ptr.* = self.recorder.exposed.items.len;
        try self.recorder.exposed.append(self.arena, .{ .name = owned, .digest = digest });
    }

    /// The parts this query published, in byte order of their names. Called once the query has returned.
    pub fn exposedParts(self: *Context) []const Part {
        std.mem.sort(Part, self.recorder.exposed.items, {}, partBefore);
        return self.recorder.exposed.items;
    }

    fn projectionIdentity(self: *const Context, wanted: *const Digest, distinct: []const []const u8) Error![]u8 {
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(self.arena, wanted);
        for (distinct) |name| {
            var length: [4]u8 = undefined;
            std.mem.writeInt(u32, &length, @intCast(name.len), .little);
            try text.appendSlice(self.arena, &length);
            try text.appendSlice(self.arena, name);
        }
        return text.toOwnedSlice(self.arena);
    }

    /// The answers for `names`, in their order, from the sights a projection read recorded.
    fn partAnswers(self: *const Context, sights: []const record.PartSight, names: []const []const u8) Error![]const ?Digest {
        const out = try self.arena.alloc(?Digest, names.len);
        for (names, out) |name, *answer| {
            answer.* = null;
            var low: usize = 0;
            var high: usize = sights.len;
            while (low < high) {
                const middle = low + (high - low) / 2;
                switch (std.mem.order(u8, sights[middle].name, name)) {
                    .eq => {
                        if (sights[middle].present) answer.* = sights[middle].digest;
                        break;
                    },
                    .lt => low = middle + 1,
                    .gt => high = middle,
                }
            }
        }
        return out;
    }

    fn ensureOpen(self: *const Context) Error!void {
        if (self.closed) return error.ContextClosed;
    }

    /// What names a read within this query: its tag, a discriminator (a filter, a key) and its path or name.
    fn identify(self: *const Context, tag: u8, discriminator: []const u8, subject: []const u8) Error![]u8 {
        try self.ensureOpen();
        const text = try self.arena.alloc(u8, 1 + discriminator.len + subject.len);
        text[0] = tag;
        @memcpy(text[1..][0..discriminator.len], discriminator);
        @memcpy(text[1 + discriminator.len ..], subject);
        return text;
    }

    fn opened(self: *const Context, name_text: []const u8) Error!?Seen {
        return self.recorder.seen.get(name_text);
    }

    fn remember(self: *Context, name_text: []const u8, read: Read, answer: Seen) Error!void {
        var seen = answer;
        seen.index = @intCast(self.recorder.reads.items.len);
        try self.recorder.reads.append(self.arena, read);
        try self.recorder.seen.put(self.arena, name_text, seen);
    }

    /// Read the file at `path` and hash it, with its stat tuple taken before and after. A tuple that moved during the
    /// read is read again, twice at most; a tuple that is not trustworthy (a file changed within the racy window, or
    /// still moving) is recorded as none, so validation hashes it.
    fn observe(self: *Context, path: []const u8) Error!Observed {
        const world = self.host.world;
        const kept = try self.arena.dupe(u8, path);
        var attempt: u32 = 0;
        while (true) : (attempt += 1) {
            const before = world.stat(path);
            const bytes = (try world.read(self.arena, path, self.host.assumptions.file_limit)) orelse
                return .{ .read = .{ .path = kept, .present = false, .digest = @splat(0), .stat = Stat.none }, .bytes = null };
            const found = digest_rules.hash(bytes);
            const after = world.stat(path);
            const steady = before != null and after != null and before.?.eql(after.?);
            if (!steady and attempt < 2) continue;
            const trusted = steady and !self.racy(after.?);
            return .{ .read = .{ .path = kept, .present = true, .digest = found, .stat = if (trusted) after.? else Stat.none }, .bytes = bytes };
        }
    }

    /// Whether a file with this tuple changed too recently to be told apart from a later write by its tuple alone.
    fn racy(self: *const Context, stat: Stat) bool {
        return stat.changed() > self.host.world.now() - self.host.assumptions.racy_window_ns;
    }
};

fn nameBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn partBefore(_: void, left: Part, right: Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// The names of the sorted list `sorted` with each once, in place.
fn distinctNames(sorted: [][]const u8) []const []const u8 {
    if (sorted.len == 0) return sorted;
    var kept: usize = 1;
    for (sorted[1..]) |name| {
        if (std.mem.eql(u8, name, sorted[kept - 1])) continue;
        sorted[kept] = name;
        kept += 1;
    }
    return sorted[0..kept];
}

/// The digest of the part called `name` in `parts`, which are in byte order of their names.
pub fn findPart(parts: []const Part, name: []const u8) ?Digest {
    var low: usize = 0;
    var high: usize = parts.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        switch (std.mem.order(u8, parts[middle].name, name)) {
            .eq => return parts[middle].digest,
            .lt => low = middle + 1,
            .gt => high = middle,
        }
    }
    return null;
}

/// Whether `name` is a safe kind name: one non-empty path component of lowercase letters, digits, `.`, `_` and `-`
/// that does not start with a dot.
pub fn validKindName(name: []const u8) bool {
    if (name.len == 0 or name.len > 64 or name[0] == '.') return false;
    for (name) |byte| {
        const ok = (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or byte == '.' or byte == '_' or byte == '-';
        if (!ok) return false;
    }
    return true;
}

test "kind names are single safe path components" {
    try std.testing.expect(validKindName("test-exec"));
    try std.testing.expect(validKindName("engine-probe.v2"));
    try std.testing.expect(!validKindName(""));
    try std.testing.expect(!validKindName(".hidden"));
    try std.testing.expect(!validKindName("a/b"));
    try std.testing.expect(!validKindName("Upper"));
    try std.testing.expect(!validKindName("sp ace"));
}

fn stubFetch(_: *anyopaque, _: *const Kind, _: []const u8, _: *const Frame) Error!Fetched {
    return error.Failed;
}

fn stubKeyed(_: *anyopaque, _: []const u8, _: Digest, _: *const Frame) Error!?Fetched {
    return null;
}

fn stubStat(_: *anyopaque, _: []const u8) ?Stat {
    return null;
}

fn stubListing(_: *anyopaque, _: []const u8, _: u8) Error!?Digest {
    return null;
}

fn stubTool(_: *anyopaque, _: []const u8) Error!Digest {
    return @splat(0);
}

fn stubRun(_: *Context, _: []const u8) Error![]const u8 {
    return "";
}

test "a context refuses every read once its query has returned" {
    const memory_world = @import("memory_world.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var files: memory_world.MemoryWorld = .init(std.testing.allocator);
    defer files.deinit();
    var anchor: u8 = 0;
    const host: Host = .{
        .ptr = &anchor,
        .world = files.world(),
        .assumptions = .{},
        .vtable = &.{ .fetch = stubFetch, .fetch_keyed = stubKeyed, .stat = stubStat, .listing = stubListing, .tool = stubTool },
    };
    const kind: Kind = .{ .name = "closing", .identity = @splat(0), .run = stubRun };
    var ctx = Context.init(host, .{ .kind = &kind, .key = @splat(0), .argument = "", .parent = null, .depth = 0 }, arena.allocator());
    try std.testing.expectEqual(@as(?[]const u8, null), try ctx.file("/absent"));
    ctx.close();
    try std.testing.expectError(error.ContextClosed, ctx.file("/absent"));
    try std.testing.expectError(error.ContextClosed, ctx.exists("/absent"));
    try std.testing.expectError(error.ContextClosed, ctx.listing("/", 0));
    try std.testing.expectError(error.ContextClosed, ctx.variable("X"));
    try std.testing.expectError(error.ContextClosed, ctx.tool("zig"));
    try std.testing.expectError(error.ContextClosed, ctx.query(&kind, ""));
}
