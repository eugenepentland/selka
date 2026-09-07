//! Live allocation budget that forwards storage to the caller's allocator.
//! Returned storage can be freed directly by the parent after this wrapper dies.
const std = @import("std");
/// Forwarding allocator accounting for live codec bytes and enforcing the operation's memory limit.
pub const Memory = struct {
    parent: std.mem.Allocator,
    limit: usize,
    live: usize = 0,
    peak: usize = 0,
    limit_failure: bool = false,
    /// Create a narrower accounting layer; keep both objects alive until all
    /// child allocations are freed through the child allocator. Every byte is
    /// charged to both limits, so nested children cannot amplify parent authority.
    pub fn child(self: *Memory, limit: usize) Memory {
        return .{ .parent = self.allocator(), .limit = @min(limit, self.limit) };
    }
    /// Borrow an allocator interface tied to this accounting object's lifetime.
    pub fn allocator(self: *Memory) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn account(self: *Memory, before: usize, after: usize) void {
        self.live = self.live - before + after;
        self.peak = @max(self.peak, self.live);
    }
    fn fits(self: *Memory, before: usize, after: usize) bool {
        return after <= self.limit - (self.live - before);
    }
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *Memory = @ptrCast(@alignCast(context));
        self.limit_failure = !self.fits(0, len);
        if (self.limit_failure) return null;
        const output = self.parent.rawAlloc(len, alignment, ret) orelse return null;
        self.account(0, len);
        return output;
    }
    fn resize(context: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *Memory = @ptrCast(@alignCast(context));
        if (!self.fits(bytes.len, len)) return false;
        if (!self.parent.rawResize(bytes, alignment, len, ret)) return false;
        self.account(bytes.len, len);
        return true;
    }
    fn remap(context: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *Memory = @ptrCast(@alignCast(context));
        if (!self.fits(bytes.len, len)) return null;
        const output = self.parent.rawRemap(bytes, alignment, len, ret) orelse return null;
        self.account(bytes.len, len);
        return output;
    }
    fn free(context: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *Memory = @ptrCast(@alignCast(context));
        self.live -= bytes.len;
        self.parent.rawFree(bytes, alignment, ret);
    }
};
