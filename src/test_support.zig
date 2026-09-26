//! Allocators used to verify bounded live runtime storage.
const std = @import("std");
const values = @import("value_semantics.zig");

/// Explicit scope for tests of the one-release legacy sharing contract.
pub const LegacySharing = struct {
    previous: bool,
    /// Enter legacy mode for a fixture that intentionally tests shared identity.
    pub fn enter() LegacySharing {
        const scope: LegacySharing = .{ .previous = values.enabled() };
        values.setEnabled(false);
        return scope;
    }
    /// Restore the caller's mode after that fixture.
    pub fn restore(self: LegacySharing) void {
        values.setEnabled(self.previous);
    }
};

/// Test allocator enforcing a live-byte bound; resize/remap deliberately force fallback paths.
pub const LimitedLiveAllocator = struct {
    parent: std.mem.Allocator,
    limit: usize,
    live: usize = 0,
    /// Borrow an allocator interface that charges allocations and refunds frees to this object's live count.
    pub fn allocator(self: *LimitedLiveAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    /// Verify that every allocation was freed; this adapter owns no separate backing storage.
    pub fn deinit(self: *LimitedLiveAllocator) void {
        std.debug.assert(self.live == 0);
    }
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *LimitedLiveAllocator = @ptrCast(@alignCast(context));
        if (len > self.limit - self.live) return null;
        const result = self.parent.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.live += len;
        return result;
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *LimitedLiveAllocator = @ptrCast(@alignCast(context));
        self.live -= memory.len;
        self.parent.rawFree(memory, alignment, ret_addr);
    }
};
