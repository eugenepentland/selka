//! Caller-owned allocation and copied native JSON ABI descriptors.
const std = @import("std");
/// Allocator callbacks retain allocation and cleanup authority in the caller.
pub const NativeAllocator = extern struct {
    allocate: *const fn (usize) callconv(.c) ?*anyopaque,
    reallocate: *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    release: *const fn (?*anyopaque) callconv(.c) void,
    /// Borrow a standard allocator from the stable callback table.
    pub fn allocator(self: *const NativeAllocator) std.mem.Allocator {
        return .{ .ptr = @constCast(self), .vtable = &.{ .alloc = allocateBytes, .resize = resizeBytes, .remap = remapBytes, .free = freeBytes } };
    }
    fn allocateBytes(context: *anyopaque, length: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *const NativeAllocator = @ptrCast(@alignCast(context));
        if (std.mem.Alignment.compare(alignment, .gt, .of(std.c.max_align_t))) return null;
        return @ptrCast(self.allocate(length) orelse return null);
    }
    fn resizeBytes(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remapBytes(context: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, length: usize, _: usize) ?[*]u8 {
        const self: *const NativeAllocator = @ptrCast(@alignCast(context));
        if (std.mem.Alignment.compare(alignment, .gt, .of(std.c.max_align_t))) return null;
        return @ptrCast(self.reallocate(bytes.ptr, length) orelse return null);
    }
    fn freeBytes(context: *anyopaque, bytes: []u8, _: std.mem.Alignment, _: usize) void {
        const self: *const NativeAllocator = @ptrCast(@alignCast(context));
        self.release(bytes.ptr);
    }
};
/// All pointers borrow compiler-owned descriptors or one synchronous call's bytes.
pub const Node = extern struct { name: [*:0]const u8, bits: u64, children: usize };
/// Nominal structural schema with ordered field or case names.
pub const Shape = extern struct {
    name: [*:0]const u8,
    kind: c_uint,
    count: usize,
    children: ?[*]const usize,
    names: ?[*]const [*:0]const u8,
    key: usize,
    flags: c_uint,
};
/// Compiled type identity and bounded byte budget for one conversion.
pub const Request = extern struct { shapes: [*]const Shape, count: usize, ty: usize, limit: usize };
/// Either source bytes or copied argument nodes for one conversion.
pub const Input = extern struct { bytes: ?[*]const u8, length: usize, nodes: ?[*]const Node, count: usize };
/// Transferred output allocation and charged traversal work.
pub const Output = extern struct { data: ?*anyopaque = null, count: usize = 0, work: u64 = 0 };
