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
const run_budget = @import("run_budget.zig");

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

const frame = run_budget.frame;
const prepend = run_budget.prepend;
