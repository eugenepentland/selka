//! Per-build raw IR handles, materialized only when optimizer work needs a body.
const std = @import("std");
pub const Digest = [32]u8;
pub const Error = std.mem.Allocator.Error || error{CacheMiss};
/// Optimizer checkpoint inspection overrides raw loading only during ordered passes.
pub const Inspection = struct { pointer: *anyopaque, ensure_fn: *const fn (*anyopaque, u32) Error!void };
/// Keys bind lowering inputs and catalog identity; loaded slots track actual bodies.
pub const Context = struct {
    keys: []const ?Digest,
    /// Each function's lowering key before the source proof of its own text was mixed into `keys`: it names the lowered body
    /// without the line and column it stands at, so a line shifted above a function leaves it unchanged (G3p-0).
    unmixed: []const ?Digest = &.{},
    force_eager: bool = false,
    loaded: []bool,
    pointer: *anyopaque,
    ensure_fn: *const fn (*anyopaque, u32) Error!void,
    inspection: ?Inspection = null,

    /// Resolve one immutable raw handle before any mutable pass visits it.
    pub fn ensure(self: *Context, index: u32) Error!void {
        if (self.inspection) |inspection| return inspection.ensure_fn(inspection.pointer, index);
        return self.ensureRaw(index);
    }

    /// Load the original body without an optimizer checkpoint override.
    pub fn ensureRaw(self: *Context, index: u32) Error!void {
        if (index >= self.loaded.len or self.loaded[index]) return;
        try self.ensure_fn(self.pointer, index);
        self.loaded[index] = true;
    }
};
