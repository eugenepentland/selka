//! Function-local raw normalization, shared by eager and demand restoration.
const std = @import("std");
const ir = @import("ir.zig");

/// These passes inspect declarations, but never another function's body.
pub fn function(a: std.mem.Allocator, module: *ir.Module, index: usize) std.mem.Allocator.Error!void {
    const f = &module.functions.items[index];
    if (f.signature.linkage != .internal) return;
    _ = try @import("fuse.zig").projections(a, f, module);
    _ = try @import("slices.zig").loops(a, module, f);
    _ = try @import("fuse_text.zig").cursors(a, module, f);
    _ = try @import("build_fn.zig").specialize(a, f);
    _ = try @import("fuse_dict.zig").updateCopies(a, module, f);
    _ = try @import("fuse_dict.zig").probes(a, f);
}
