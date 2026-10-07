//! Native test step bounds use existing Core calls. Each executed block of an
//! original function charges one step, as the old core charges one per dispatch
//! (docs/tooling/runtime-budgets.md); generated adapters are not charged.
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const options = @import("test_runner_options.zig");

/// Instrument only original program functions, resetting the counter per trial.
pub fn instrument(a: std.mem.Allocator, module: *ir.Module, originals: usize, controls: options.Controls) error{OutOfMemory}!void {
    const reset = try tools.helper(a, module, "myl_core_test_limits", &.{ .u64, .u32 }, .void);
    const tick = if (controls.max_steps != 0) try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void) else null;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        var b: tools.Builder = .{ .arena = a, .function = function.* };
        if (std.mem.startsWith(u8, function.name, "__test_trial_")) {
            const args = &.{ try b.constant(.u64, @bitCast(controls.max_steps)), try b.constant(.u32, controls.timeout_ms) };
            try prepend(&b, @fromBackingInt(0), module, reset, args);
        } else if (index < originals and tick != null) {
            for (b.function.blocks.items, 0..) |block, block_index| {
                if (block.insts.items.len == 0) continue;
                const cost = try b.constant(.u64, 1);
                try prepend(&b, @fromBackingInt(@intCast(block_index)), module, tick.?, &.{cost});
            }
        }
        function.* = b.function;
    }
}

fn prepend(b: *tools.Builder, block: ir.BlockId, module: *const ir.Module, helper: u32, arguments: []const ir.Ref) error{OutOfMemory}!void {
    const ref = try b.call(block, module, helper, arguments);
    const list = &b.function.blocks.items[block.index()].insts;
    list.items.len -= 1;
    var first: usize = 0;
    while (first < list.items.len) : (first += 1) {
        const op = b.function.inst(list.items[first]).op;
        if (op != .phi and op != .copy) break;
    }
    try list.insert(b.arena, first, ref);
}
