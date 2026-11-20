//! Process-lifetime values that the sessions of one process share by name, so each session adopts what an earlier one built
//! instead of building it again (the stage packs' catalog, `core/stage_pack.zig`). Only the process wiring owns mutable
//! global state, so the table lives here; the owner of a value says how it is made and destroyed, and this file counts who
//! holds it. Slots use the process allocator, never the caller's, so a value outlives the session that made it.
const std = @import("std");

/// Failures a slot table reports: only allocation.
pub const Error = std.mem.Allocator.Error;

/// The allocator of everything the process table holds. A value outlives the session that first asked for it, so no
/// session's allocator can own it; the testing allocator's leak check does not see it either.
pub fn allocator() std.mem.Allocator {
    // allocator-ok: a process-lifetime store, owned by no session; process wiring is where such an allocator belongs.
    return std.heap.smp_allocator;
}

/// The most idle slots the process table keeps; an idle slot over the bound is destroyed, least recently used first.
pub const idle_bound = 16;

/// How a slot's value is made when no slot of that name exists, and destroyed when the table lets it go.
pub const Maker = struct {
    context: *const anyopaque,
    make: *const fn (context: *const anyopaque) Error!*anyopaque,
    destroy: *const fn (value: *anyopaque) void,
};

const Slot = struct { key: []const u8, value: *anyopaque, destroy: *const fn (value: *anyopaque) void, holders: usize, used: u64 };

/// A set of named values with holder counts. `acquire` and `release` are safe from any thread.
pub const Table = struct {
    mutex: std.Io.Mutex = .init,
    slots: std.ArrayList(Slot) = .empty,
    tick: u64 = 0,

    /// The value named `key`, made by `maker` when no slot holds one, with the caller counted as a holder until `release`.
    pub fn acquire(self: *Table, io: std.Io, key: []const u8, maker: Maker) Error!*anyopaque {
        const a = allocator();
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.tick += 1;
        for (self.slots.items) |*slot| {
            if (!std.mem.eql(u8, slot.key, key)) continue;
            slot.holders += 1;
            slot.used = self.tick;
            return slot.value;
        }
        const owned = try a.dupe(u8, key);
        errdefer a.free(owned);
        try self.slots.ensureUnusedCapacity(a, 1);
        const value = try maker.make(maker.context);
        self.slots.appendAssumeCapacity(.{ .key = owned, .value = value, .destroy = maker.destroy, .holders = 1, .used = self.tick });
        self.evict();
        return value;
    }

    /// Stop counting the caller as a holder of `value`. An idle slot stays for the next session until the bound pushes it out.
    pub fn release(self: *Table, io: std.Io, value: *anyopaque) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        for (self.slots.items) |*slot| {
            if (slot.value != value) continue;
            slot.holders -|= 1;
            break;
        }
        self.evict();
    }

    /// Destroy every value and free the table: for a table that is not the process's own, whose holders are all gone.
    pub fn deinit(self: *Table) void {
        const a = allocator();
        for (self.slots.items) |slot| {
            slot.destroy(slot.value);
            a.free(slot.key);
        }
        self.slots.deinit(a);
    }

    /// How many slots the table holds, idle or not.
    pub fn count(self: *Table, io: std.Io) usize {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.slots.items.len;
    }

    /// Destroy the least recently used idle slots while more than `idle_bound` are idle. The caller holds the mutex.
    fn evict(self: *Table) void {
        const a = allocator();
        while (true) {
            var idle: usize = 0;
            var oldest: ?usize = null;
            for (self.slots.items, 0..) |slot, index| {
                if (slot.holders != 0) continue;
                idle += 1;
                if (oldest == null or slot.used < self.slots.items[oldest.?].used) oldest = index;
            }
            if (idle <= idle_bound) return;
            const slot = self.slots.swapRemove(oldest orelse return);
            slot.destroy(slot.value);
            a.free(slot.key);
        }
    }
};

var process: Table = .{};

/// The process table's value named `key`, made by `maker` the first time; release it with `release` when the session ends.
pub fn acquire(io: std.Io, key: []const u8, maker: Maker) Error!*anyopaque {
    return process.acquire(io, key, maker);
}

/// Return a value taken with `acquire` to the process table.
pub fn release(io: std.Io, value: *anyopaque) void {
    process.release(io, value);
}

/// A value for the tests below: it counts how many were made and how many destroyed.
const Counted = struct {
    made: usize = 0,
    destroyed: usize = 0,
    value: u64 = 0,

    fn make(context: *const anyopaque) Error!*anyopaque {
        const self: *Counted = @ptrCast(@alignCast(@constCast(context)));
        self.made += 1;
        return &self.value;
    }

    fn destroy(value: *anyopaque) void {
        const field: *u64 = @ptrCast(@alignCast(value));
        const self: *Counted = @fieldParentPtr("value", field);
        self.destroyed += 1;
    }

    fn maker(self: *Counted) Maker {
        return .{ .context = self, .make = make, .destroy = destroy };
    }
};

test "a second session acquires the value the first made, and the value outlives both holders" {
    var table: Table = .{};
    var counted: Counted = .{};
    const first = try table.acquire(std.testing.io, "store", counted.maker());
    const second = try table.acquire(std.testing.io, "store", counted.maker());
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(usize, 1), counted.made);
    table.release(std.testing.io, first);
    table.release(std.testing.io, second);
    const third = try table.acquire(std.testing.io, "store", counted.maker());
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqual(@as(usize, 1), counted.made);
    try std.testing.expectEqual(@as(usize, 0), counted.destroyed);
    try std.testing.expectEqual(@as(usize, 1), table.count(std.testing.io));
    table.release(std.testing.io, third);
    table.deinit();
    try std.testing.expectEqual(@as(usize, 1), counted.destroyed);
}

test "the table destroys the least recently used idle slot past the bound and never one in use" {
    var table: Table = .{};
    defer table.deinit();
    var held: Counted = .{};
    var idle: [idle_bound + 1]Counted = @splat(.{});
    const kept = try table.acquire(std.testing.io, "held", held.maker());
    for (&idle, 0..) |*item, index| {
        var name: [8]u8 = undefined;
        const key = std.fmt.bufPrint(&name, "idle-{d}", .{index}) catch unreachable;
        table.release(std.testing.io, try table.acquire(std.testing.io, key, item.maker()));
    }
    try std.testing.expectEqual(@as(usize, 1), idle[0].destroyed);
    try std.testing.expectEqual(@as(usize, 0), idle[1].destroyed);
    try std.testing.expectEqual(@as(usize, 0), held.destroyed);
    try std.testing.expectEqual(@as(usize, idle_bound + 1), table.count(std.testing.io));
    table.release(std.testing.io, kept);
}
