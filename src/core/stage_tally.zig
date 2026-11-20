//! Per-scope counts of one stage store: the records each scope loaded (hits), looked for and did not find (misses),
//! and saved. A store that observes (`stage_store.Options.observe`) keeps one tally, shared by its copies. The cache report
//! names each scope with its counts (`ScopeCount`), and the test runner's profile record names its keys' store the same way.
const std = @import("std");

/// The scope a record is counted under when no key of its store computed its digest: a record that names a digest (a
/// receipt names its artifact) is counted here, never under another scope.
pub const named_label = "(named)";

/// What one scope did: records found (`hits`), records looked for and absent (`misses`), and records saved (`saves`).
pub const Counts = struct { hits: u64 = 0, misses: u64 = 0, saves: u64 = 0 };

/// One scope's counts, as a report lists them. `scope` is borrowed from the tally it came from.
pub const ScopeCount = struct { scope: []const u8, hits: u64, misses: u64, saves: u64 };

/// What happened to one digest: a load found its record, a load did not, or a record was saved.
pub const Event = enum { hit, miss, save };

/// The scope of each digest a store computed, and each scope's counts. Every method is safe to call from concurrent
/// workers of one store; `init` and `deinit` are not.
pub const Tally = struct {
    mutex: std.Io.Mutex = .init,
    /// Scope names, owned by the tally; index 0 is `named_label`.
    names: std.ArrayList([]const u8) = .empty,
    /// The counts of each name, at the same index.
    counts: std.ArrayList(Counts) = .empty,
    /// The index in `names` of the scope that computed each digest.
    scope_of: std.AutoHashMapUnmanaged([32]u8, u16) = .empty,

    /// An empty tally, allocating from `a`: its first scope is `named_label`.
    pub fn init(a: std.mem.Allocator) std.mem.Allocator.Error!Tally {
        var tally: Tally = .{};
        errdefer tally.deinit(a);
        try tally.counts.append(a, .{});
        const name = try a.dupe(u8, named_label);
        errdefer a.free(name);
        try tally.names.append(a, name);
        return tally;
    }

    /// Release every allocation of `init` and its later calls, which all used `a`.
    pub fn deinit(self: *Tally, a: std.mem.Allocator) void {
        for (self.names.items) |name| a.free(name);
        self.names.deinit(a);
        self.counts.deinit(a);
        self.scope_of.deinit(a);
    }

    /// Remember that `scope` computed `digest`, so later events on it count under `scope`. When memory runs out the digest
    /// stays unnamed and its events count under `named_label`: a miss of attribution, never a count in the wrong scope.
    pub fn noteScope(self: *Tally, io: std.Io, a: std.mem.Allocator, digest: [32]u8, scope: []const u8) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const index = self.indexOf(a, scope) orelse return;
        self.scope_of.put(a, digest, index) catch return;
    }

    /// Count one event on `digest` under the scope that computed it (`named_label` when none did).
    pub fn count(self: *Tally, io: std.Io, digest: [32]u8, event: Event) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const index = self.scope_of.get(digest) orelse 0;
        const slot = &self.counts.items[index];
        switch (event) {
            .hit => slot.hits += 1,
            .miss => slot.misses += 1,
            .save => slot.saves += 1,
        }
    }

    /// The scopes with at least one event, sorted by name. The names are borrowed from the tally (valid until `deinit`);
    /// the slice is owned by `a`.
    pub fn snapshot(self: *Tally, io: std.Io, a: std.mem.Allocator) std.mem.Allocator.Error![]const ScopeCount {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        var out: std.ArrayList(ScopeCount) = .empty;
        for (self.names.items, self.counts.items) |name, counts| {
            if (counts.hits + counts.misses + counts.saves == 0) continue;
            try out.append(a, .{ .scope = name, .hits = counts.hits, .misses = counts.misses, .saves = counts.saves });
        }
        std.mem.sort(ScopeCount, out.items, {}, before);
        return out.toOwnedSlice(a);
    }

    /// The index of `scope` in `names`, added with zero counts when absent. Null when memory runs out (nothing is added).
    fn indexOf(self: *Tally, a: std.mem.Allocator, scope: []const u8) ?u16 {
        for (self.names.items, 0..) |name, index| if (std.mem.eql(u8, name, scope)) return @intCast(index);
        const name = a.dupe(u8, scope) catch return null;
        self.names.append(a, name) catch {
            a.free(name);
            return null;
        };
        self.counts.append(a, .{}) catch {
            _ = self.names.pop();
            a.free(name);
            return null;
        };
        return @intCast(self.names.items.len - 1);
    }
};

/// Sort order of a snapshot: by scope name.
fn before(_: void, left: ScopeCount, right: ScopeCount) bool {
    return std.mem.lessThan(u8, left.scope, right.scope);
}

test "a tally counts each event under the scope that computed its digest, and sorts the snapshot by name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tally = try Tally.init(std.testing.allocator);
    defer tally.deinit(std.testing.allocator);
    const first: [32]u8 = @splat(1);
    const second: [32]u8 = @splat(2);
    const unnamed: [32]u8 = @splat(3);
    tally.noteScope(std.testing.io, std.testing.allocator, first, "final");
    tally.noteScope(std.testing.io, std.testing.allocator, second, "llvm-unit-v1");
    tally.count(std.testing.io, first, .hit);
    tally.count(std.testing.io, first, .miss);
    tally.count(std.testing.io, second, .save);
    tally.count(std.testing.io, unnamed, .hit);
    const counts = try tally.snapshot(std.testing.io, a);
    try std.testing.expectEqual(@as(usize, 3), counts.len);
    try std.testing.expectEqualStrings(named_label, counts[0].scope);
    try std.testing.expectEqual(@as(u64, 1), counts[0].hits);
    try std.testing.expectEqualStrings("final", counts[1].scope);
    try std.testing.expectEqual(@as(u64, 1), counts[1].hits);
    try std.testing.expectEqual(@as(u64, 1), counts[1].misses);
    try std.testing.expectEqualStrings("llvm-unit-v1", counts[2].scope);
    try std.testing.expectEqual(@as(u64, 1), counts[2].saves);
}
