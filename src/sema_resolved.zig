//! The checked node each syntax node of the body being checked resolved to, one slot for every node of the merged program.
//!
//! A warm check visits the few nodes of the bodies it checks, while the table covers every node of every module (1.4 million at the 99k port, a slot of
//! 16 bytes as an optional id). A slot here is one `usize` that holds zero for "none" and the node id plus one otherwise, and the table comes from the
//! system as zero pages: the pages of the bodies that stand in are never written, so they cost neither a memset nor a page fault. A node id of zero is
//! a node, and stays distinct from the empty slot.
const std = @import("std");
const typed = @import("typed.zig");

/// The table. `mapping` is an anonymous mapping of the system's memory, which is zero and is not written until a slot is: taken from the allocator
/// interface, a Debug compiler would fill what it hands out with a pattern and write every page.
pub const Resolved = struct {
    slots: []usize,
    mapping: []align(std.heap.page_size_min) u8,

    /// A table of `count` empty slots.
    pub fn init(count: usize) std.mem.Allocator.Error!Resolved {
        if (count == 0) return .{ .slots = &.{}, .mapping = &.{} };
        const mapping = std.posix.mmap(null, count * @sizeOf(usize), .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0) catch return error.OutOfMemory;
        const slots = @as([*]usize, @ptrCast(mapping.ptr))[0..count];
        std.debug.assert(std.mem.allEqual(usize, slots[0..@min(count, 512)], 0));
        return .{ .slots = slots, .mapping = mapping };
    }

    /// Give the slots back.
    pub fn deinit(self: *Resolved) void {
        if (self.mapping.len != 0) std.posix.munmap(self.mapping);
        self.* = .{ .slots = &.{}, .mapping = &.{} };
    }

    /// The node the syntax node `index` resolved to, or null.
    pub fn at(self: Resolved, index: usize) ?typed.NodeId {
        const slot = self.slots[index];
        return if (slot == 0) null else @fromBackingInt(slot - 1);
    }

    /// Resolve the syntax node `index` to `value` (null clears it).
    pub fn put(self: Resolved, index: usize, value: ?typed.NodeId) void {
        self.slots[index] = if (value) |id| @backingInt(id) + 1 else 0;
    }

    /// Make room for at least `count` nodes; the new slots are empty.
    pub fn grow(self: *Resolved, count: usize) std.mem.Allocator.Error!void {
        if (self.slots.len >= count) return;
        var larger = try init(count);
        @memcpy(larger.slots[0..self.slots.len], self.slots);
        self.deinit();
        self.* = larger;
    }
};

test "a resolved table starts empty, keeps node zero apart from an empty slot, clears, and grows empty" {
    var table = try Resolved.init(3000);
    defer table.deinit();
    try std.testing.expect(table.at(0) == null and table.at(2999) == null);
    // Node zero is a node: the slot holds its id plus one, which is not the empty slot.
    const zero: typed.NodeId = @fromBackingInt(0);
    table.put(7, zero);
    try std.testing.expect(table.at(7) != null);
    try std.testing.expectEqual(@as(usize, 0), @backingInt(table.at(7).?));
    try std.testing.expect(table.at(6) == null and table.at(8) == null);
    table.put(9, @fromBackingInt(41));
    try std.testing.expectEqual(@as(usize, 41), @backingInt(table.at(9).?));
    table.put(7, null);
    try std.testing.expect(table.at(7) == null);
    try std.testing.expectEqual(@as(usize, 41), @backingInt(table.at(9).?));
    // The slots a growth adds are empty, and the ones before it are kept.
    try table.grow(20000);
    try std.testing.expect(table.slots.len >= 20000);
    try std.testing.expectEqual(@as(usize, 41), @backingInt(table.at(9).?));
    try std.testing.expect(table.at(3000) == null and table.at(19999) == null);
}
