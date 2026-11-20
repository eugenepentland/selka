//! Function-local raw normalization, shared by eager and demand restoration.
const std = @import("std");
const ir = @import("ir.zig");

/// These passes inspect declarations, but never another function's body. Each
/// works on a private copy of the function and stores it back by index: a pass
/// may declare a runtime helper, which grows `module.functions` and moves the
/// array, so no pointer into it may outlive the call (a bound bytes view return
/// with a concatenated argument proved the hard way).
pub fn function(a: std.mem.Allocator, module: *ir.Module, index: usize) std.mem.Allocator.Error!void {
    if (module.functions.items[index].signature.linkage != .internal) return;
    var current = module.functions.items[index];
    // The views the lowering of a `mut` place argument leaves in front of its take go first, so that the passes below see
    // the take alone.
    _ = try @import("take_first.zig").run(a, &current);
    _ = try @import("fuse.zig").projections(a, &current, module);
    module.functions.items[index] = current;
    current = module.functions.items[index];
    _ = try @import("slices.zig").loops(a, module, &current);
    module.functions.items[index] = current;
    current = module.functions.items[index];
    _ = try @import("fuse_text.zig").cursors(a, module, &current);
    module.functions.items[index] = current;
    current = module.functions.items[index];
    _ = try @import("build_fn.zig").specialize(a, &current);
    module.functions.items[index] = current;
    current = module.functions.items[index];
    _ = try @import("fuse_dict.zig").updateCopies(a, module, &current);
    module.functions.items[index] = current;
    current = module.functions.items[index];
    _ = try @import("fuse_dict.zig").probes(a, &current);
    module.functions.items[index] = current;
    // The recovery runs last, after the body-repair passes have had their shape:
    // a slice only read in place borrows its source in every build mode, so a
    // debug build reads it without allocating too.
    current = module.functions.items[index];
    _ = try @import("fuse_slice_key.zig").rewriteReadOnly(a, module, &current);
    module.functions.items[index] = current;
    // A view binding is materialized after the recovery, so the verifier sees an
    // owned value wherever one is needed.
    current = module.functions.items[index];
    _ = try @import("view_materialize.zig").run(a, module, &current);
    module.functions.items[index] = current;
}

/// `function`, reporting whether it made the body call a declaration outside
/// the program (a runtime helper) that the body did not call before. Demand
/// builds restore such a deferred body in the eager order, so both paths
/// declare the same helpers at the same indices.
pub fn functionTracked(a: std.mem.Allocator, module: *ir.Module, index: usize) std.mem.Allocator.Error!bool {
    if (module.functions.items[index].signature.linkage != .internal) return false;
    var before: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer before.deinit(a);
    for (module.functions.items[index].insts.items) |inst| if (externalTarget(module, inst)) |target| try before.put(a, target, {});
    try function(a, module, index);
    for (module.functions.items[index].insts.items) |inst| if (externalTarget(module, inst)) |target| {
        if (!before.contains(target)) return true;
    };
    return false;
}

fn externalTarget(module: *const ir.Module, inst: ir.Inst) ?u32 {
    const target: usize = switch (inst.op) {
        .call => inst.a.index(),
        .func_ref => std.math.cast(usize, inst.data) orelse return null,
        else => return null,
    };
    if (target >= module.functions.items.len or module.functions.items[target].signature.linkage == .internal) return null;
    return @intCast(target);
}
