//! What the engine remembers within one revision of the world (spec §5, steps 1 and 3): the validated result of
//! every key, and the stat tuple, listing digest and tool identity of every path asked about. A key validated once
//! is not validated again in the process, and a path is stat-ed once per revision, however many records read it.
//!
//! A revision is a consistent snapshot of the world. The world is assumed not to change inside one; a process that
//! lives across edits (a server, a test) starts a new revision, which forgets all of it.
const std = @import("std");
const digest_rules = @import("digest.zig");
const world_rules = @import("world.zig");
const context = @import("context.zig");
const Digest = digest_rules.Digest;
const Result = context.Result;
const Body = context.Body;
const Part = context.Part;
const Stat = world_rules.Stat;
const World = world_rules.World;

/// Hashes a key by its first eight bytes, which are already uniform.
const DigestContext = struct {
    /// The first eight bytes of the key as the hash.
    pub fn hash(_: DigestContext, key: Digest) u64 {
        return std.mem.readInt(u64, key[0..8], .little);
    }

    /// Whether two keys are the same key.
    pub fn eql(_: DigestContext, left: Digest, right: Digest) bool {
        return std.mem.eql(u8, &left, &right);
    }
};

/// The per-revision tables, guarded by one mutex. Lookups and insertions hold it; the world is never called under it.
pub const Memory = struct {
    mutex: std.Io.Mutex = .init,
    /// Owns the payloads and the path strings the tables hold.
    arena: std.heap.ArenaAllocator,
    results: std.HashMapUnmanaged(Digest, Result, DigestContext, 80) = .empty,
    stats: std.StringHashMapUnmanaged(?Stat) = .empty,
    listings: std.StringHashMapUnmanaged(?Digest) = .empty,
    tools: std.StringHashMapUnmanaged(Digest) = .empty,
    revision: u32 = 0,

    /// Empty tables allocating from `gpa`.
    pub fn init(gpa: std.mem.Allocator) Memory {
        return .{ .arena = .init(gpa) };
    }

    /// Free everything.
    pub fn deinit(self: *Memory) void {
        const gpa = self.arena.child_allocator;
        self.results.deinit(gpa);
        self.stats.deinit(gpa);
        self.listings.deinit(gpa);
        self.tools.deinit(gpa);
        self.arena.deinit();
    }

    /// Start a new revision: forget every result and every answer of the world.
    pub fn reset(self: *Memory, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.results.clearRetainingCapacity();
        self.stats.clearRetainingCapacity();
        self.listings.clearRetainingCapacity();
        self.tools.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
        self.revision += 1;
    }

    /// How many results are remembered.
    pub fn count(self: *Memory, io: std.Io) usize {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.results.count();
    }

    /// The validated result of `key` in this revision, or null.
    pub fn result(self: *Memory, io: std.Io, key: Digest) ?Result {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.results.get(key);
    }

    /// Remember `body`, `digest` and the table of `parts` as the validated result of `key`, and return the copy the memory
    /// holds, whose parts (and payload, when `body` is resident bytes) stay valid until the next revision. A lazy body is
    /// kept as given: its handle must have been made by `create`. A key remembered twice (two threads computed it) keeps
    /// the first.
    pub fn remember(self: *Memory, io: std.Io, key: Digest, body: Body, digest: Digest, parts: []const Part) std.mem.Allocator.Error!Result {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const gpa = self.arena.child_allocator;
        const slot = try self.results.getOrPut(gpa, key);
        if (slot.found_existing) return slot.value_ptr.*;
        errdefer _ = self.results.remove(key);
        const owned = self.arena.allocator();
        const kept = try owned.alloc(Part, parts.len);
        // The names are copied into one block: a record of a module holds a few hundred parts, and one allocation each was a third of the cost
        // of remembering it.
        var length: usize = 0;
        for (parts) |part| length += part.name.len;
        const names = try owned.alloc(u8, length);
        var at: usize = 0;
        for (parts, kept) |part, *copy| {
            @memcpy(names[at..][0..part.name.len], part.name);
            copy.* = .{ .name = names[at..][0..part.name.len], .digest = part.digest };
            at += part.name.len;
        }
        const stored: Body = switch (body) {
            .resident => |bytes| .{ .resident = try owned.dupe(u8, bytes) },
            .lazy => body,
        };
        slot.value_ptr.* = .{ .digest = digest, .parts = kept, .body = stored };
        return slot.value_ptr.*;
    }

    /// An uninitialized `T` in the revision's arena, which lives until the next revision. The engine's lazy payload
    /// cells are made here.
    pub fn create(self: *Memory, io: std.Io, comptime T: type) std.mem.Allocator.Error!*T {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.arena.allocator().create(T);
    }

    /// A copy of `bytes` in the revision's arena, valid until the next revision.
    pub fn keep(self: *Memory, io: std.Io, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.arena.allocator().dupe(u8, bytes);
    }

    /// Forget the validated result of `key`, so the next lookup reads the store again.
    pub fn forget(self: *Memory, io: std.Io, key: Digest) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        _ = self.results.remove(key);
    }

    /// The stat tuple at `path`, from the world the first time it is asked in this revision.
    pub fn stat(self: *Memory, io: std.Io, world: World, path: []const u8) ?Stat {
        self.mutex.lockUncancelable(io);
        if (self.stats.get(path)) |known| {
            self.mutex.unlock(io);
            return known;
        }
        self.mutex.unlock(io);
        const fresh = world.stat(path);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const owned = self.arena.allocator().dupe(u8, path) catch return fresh;
        self.stats.put(self.arena.child_allocator, owned, fresh) catch return fresh;
        return fresh;
    }

    /// The digest of the listing of `path` under `filter`, from the world the first time it is asked.
    pub fn listing(self: *Memory, io: std.Io, world: World, scratch: std.mem.Allocator, path: []const u8, filter: u8) world_rules.ReadError!?Digest {
        const key = try std.fmt.allocPrint(scratch, "{c}{s}", .{ filter, path });
        defer scratch.free(key);
        self.mutex.lockUncancelable(io);
        if (self.listings.get(key)) |known| {
            self.mutex.unlock(io);
            return known;
        }
        self.mutex.unlock(io);
        var temporary: std.heap.ArenaAllocator = .init(scratch);
        defer temporary.deinit();
        const names = try world.list(temporary.allocator(), path, filter);
        const fresh: ?Digest = if (names) |kept| try digest_rules.listingDigest(temporary.allocator(), kept) else null;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const owned = self.arena.allocator().dupe(u8, key) catch return fresh;
        self.listings.put(self.arena.child_allocator, owned, fresh) catch return fresh;
        return fresh;
    }

    /// The identity of the tool at `path` (zero when it cannot be found), from the world the first time it is asked.
    pub fn tool(self: *Memory, io: std.Io, world: World, scratch: std.mem.Allocator, path: []const u8) world_rules.ReadError!Digest {
        self.mutex.lockUncancelable(io);
        if (self.tools.get(path)) |known| {
            self.mutex.unlock(io);
            return known;
        }
        self.mutex.unlock(io);
        var temporary: std.heap.ArenaAllocator = .init(scratch);
        defer temporary.deinit();
        const fresh: Digest = (try world.tool(temporary.allocator(), path)) orelse @splat(0);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const owned = self.arena.allocator().dupe(u8, path) catch return fresh;
        self.tools.put(self.arena.child_allocator, owned, fresh) catch return fresh;
        return fresh;
    }
};

/// `names` as a table of parts whose names are slices of `scratch`, the digest of part `at` being `at` in every byte.
fn tableOver(scratch: []u8, names: []const []const u8, table: []Part) void {
    var used: usize = 0;
    for (names, table, 0..) |name, *part, at| {
        @memcpy(scratch[used..][0..name.len], name);
        part.* = .{ .name = scratch[used..][0..name.len], .digest = @splat(@intCast(at)) };
        used += name.len;
    }
}

/// Whether `table` holds `names` in order, with the digests `tableOver` gives.
fn tableHolds(names: []const []const u8, table: []const Part) bool {
    for (names, table, 0..) |name, part, at| {
        if (!std.mem.eql(u8, name, part.name) or part.digest[0] != @as(u8, @intCast(at))) return false;
    }
    return names.len == table.len;
}

test "a remembered table keeps every part name intact in its own copy, whatever became of the names it was made from" {
    var memory = Memory.init(std.testing.allocator);
    defer memory.deinit();
    const names = [_][]const u8{ "alpha", "b", "gamma:delta", "proof:fn\x1fm\x1f\x1ff@0123456789abcdef" };
    var source: [names.len]Part = undefined;
    var scratch: [128]u8 = undefined;
    tableOver(&scratch, &names, &source);
    const kept = try memory.remember(std.testing.io, @splat(5), .{ .resident = "p" }, @splat(6), &source);
    @memset(&scratch, 'x');
    try std.testing.expect(tableHolds(&names, kept.parts));
    // A table of no parts is remembered too.
    try std.testing.expectEqual(@as(usize, 0), (try memory.remember(std.testing.io, @splat(7), .{ .resident = "q" }, @splat(8), &.{})).parts.len);
}

test "a result is remembered once and survives until the revision ends" {
    var memory = Memory.init(std.testing.allocator);
    defer memory.deinit();
    const io = std.testing.io;
    const key: Digest = @splat(1);
    try std.testing.expectEqual(@as(?Result, null), memory.result(io, key));
    const parts = [_]Part{.{ .name = "decl", .digest = @splat(4) }};
    const first = try memory.remember(io, key, .{ .resident = "payload" }, @splat(2), &parts);
    try std.testing.expectEqualStrings("payload", try first.payload());
    try std.testing.expectEqualStrings("decl", first.parts[0].name);
    const second = try memory.remember(io, key, .{ .resident = "other" }, @splat(3), &.{});
    try std.testing.expectEqualStrings("payload", try second.payload());
    try std.testing.expectEqual(@as(usize, 1), second.parts.len);
    try std.testing.expectEqual(@as(usize, 1), memory.count(io));
    memory.reset(io);
    try std.testing.expectEqual(@as(?Result, null), memory.result(io, key));
    try std.testing.expectEqual(@as(u32, 1), memory.revision);
}

test "the world is asked once per path in a revision, and again after it" {
    const MemoryWorld = @import("memory_world.zig").MemoryWorld;
    var memory = Memory.init(std.testing.allocator);
    defer memory.deinit();
    var files: MemoryWorld = .init(std.testing.allocator);
    defer files.deinit();
    const io = std.testing.io;
    try files.write("/a", "x");
    try files.setTool("zig", @splat(4));
    const world = files.world();
    try std.testing.expect(memory.stat(io, world, "/a") != null);
    try std.testing.expect(memory.stat(io, world, "/a") != null);
    try std.testing.expectEqual(@as(?Stat, null), memory.stat(io, world, "/b"));
    try std.testing.expectEqual(@as(?Stat, null), memory.stat(io, world, "/b"));
    try std.testing.expectEqual(@as(u64, 2), files.count("stats"));
    const first = try memory.listing(io, world, std.testing.allocator, "/", 0);
    try std.testing.expectEqual(first, try memory.listing(io, world, std.testing.allocator, "/", 0));
    try std.testing.expectEqual(@as(u64, 1), files.count("lists"));
    try std.testing.expectEqual(@as(Digest, @splat(4)), try memory.tool(io, world, std.testing.allocator, "zig"));
    try std.testing.expectEqual(@as(Digest, @splat(4)), try memory.tool(io, world, std.testing.allocator, "zig"));
    try std.testing.expectEqual(@as(u64, 1), files.count("tools"));
    memory.reset(io);
    _ = memory.stat(io, world, "/a");
    try std.testing.expectEqual(@as(u64, 3), files.count("stats"));
}
