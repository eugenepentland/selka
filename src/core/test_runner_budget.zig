//! Native test step bounds use existing Core calls. Each executed block of an
//! original function charges one step, as the old core charges one per dispatch
//! (docs/tooling/runtime-budgets.md); generated adapters are not charged. Each
//! call of an original function is one frame of the `--max-frames` budget: it
//! enters on its first block and leaves before every return. The entry installs
//! the frame and byte ceilings before the first trial, so the runtime can map the
//! trial's stack and bound the process's address space.
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const options = @import("test_runner_options.zig");

/// Instrument only original program functions, resetting the counter per trial.
pub fn instrument(a: std.mem.Allocator, module: *ir.Module, originals: usize, controls: options.Controls) error{OutOfMemory}!void {
    const reset = try tools.helper(a, module, "myl_core_test_limits", &.{ .u64, .u32 }, .void);
    const tick = if (controls.max_steps != 0) try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void) else null;
    const ceilings = try tools.helper(a, module, "myl_core_test_ceilings", &.{ .u32, .u64 }, .void);
    const enter = try tools.helper(a, module, "myl_core_test_enter", &.{}, .void);
    const leave = try tools.helper(a, module, "myl_core_test_leave", &.{}, .void);
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        var b: tools.Builder = .{ .arena = a, .function = function.* };
        if (index == module.entry) {
            const args = &.{ try b.constant(.u32, controls.ceilings.frames), try b.constant(.u64, @bitCast(controls.ceilings.memory)) };
            try prepend(&b, @fromBackingInt(0), module, ceilings, args);
        } else if (std.mem.startsWith(u8, function.name, "__test_trial_")) {
            const args = &.{ try b.constant(.u64, @bitCast(controls.max_steps)), try b.constant(.u32, controls.timeout_ms) };
            try prepend(&b, @fromBackingInt(0), module, reset, args);
        } else if (index < originals) {
            if (tick) |helper| for (b.function.blocks.items, 0..) |block, block_index| {
                if (block.insts.items.len == 0) continue;
                const cost = try b.constant(.u64, 1);
                try prepend(&b, @fromBackingInt(@intCast(block_index)), module, helper, &.{cost});
            };
            try frame(&b, module, enter, leave);
        }
        function.* = b.function;
    }
}

/// Count one frame from the entry block until each return.
fn frame(b: *tools.Builder, module: *const ir.Module, enter: u32, leave: u32) error{OutOfMemory}!void {
    for (b.function.blocks.items, 0..) |block, block_index| {
        const list = block.insts.items;
        if (list.len == 0 or b.function.inst(list[list.len - 1]).op != .ret) continue;
        const ref = try b.call(@fromBackingInt(@intCast(block_index)), module, leave, &.{});
        const insts = &b.function.blocks.items[block_index].insts;
        insts.items.len -= 1;
        try insts.insert(b.arena, insts.items.len - 1, ref);
    }
    try prepend(b, @fromBackingInt(0), module, enter, &.{});
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
