//! Per-build raw IR handles, materialized only when optimizer work needs a body.
const std = @import("std");
pub const Digest = [32]u8;
pub const Error = std.mem.Allocator.Error || error{CacheMiss};
/// Keys bind lowering inputs and catalog identity; loaded slots track actual bodies.
pub const Context = struct {
    keys: []const ?Digest,
    force_eager: bool = false,
    loaded: []bool,
    pointer: *anyopaque,
    ensure_fn: *const fn (*anyopaque, u32) Error!void,

    /// Resolve one immutable raw handle before any mutable pass visits it.
    pub fn ensure(self: *Context, index: u32) Error!void {
        if (index >= self.loaded.len or self.loaded[index]) return;
        try self.ensure_fn(self.pointer, index);
        self.loaded[index] = true;
    }
};
