//! Native test step bounds use existing Core calls. Each executed block of an
//! original function charges one step, as the old core charges one per dispatch
//! (docs/tooling/runtime-budgets.md); generated adapters are not charged. The same
//! call counts the block for the test's reported work (NEW-CORE-TEST-WORK-1), so it
//! is emitted even when `--max-steps 0` removed the ceiling. Each
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
    const plan = try Test.declare(a, module, originals, controls);
    for (0..module.functions.items.len) |index| try plan.function(a, module, index);
}

/// A test program's instrumentation, function by function: the helpers, declared once on the module (`declare`), and the
/// rewrite of one function (`function`). Declaring and then rewriting every function is `instrument`; a build that
/// materializes a body later rewrites it then, with the same result.
pub const Test = struct {
    controls: options.Controls,
    /// The functions before the runner's entry and trials were added: only these are charged steps and frames.
    originals: usize,
    reset: u32,
    tick: u32,
    ceilings: u32,
    enter: u32,
    leave: u32,

    /// Declare the helpers on `module`, in the order `instrument` always declared them.
    pub fn declare(a: std.mem.Allocator, module: *ir.Module, originals: usize, controls: options.Controls) error{OutOfMemory}!Test {
        const reset = try tools.helper(a, module, "myl_core_test_limits", &.{ .u64, .u32 }, .void);
        const tick = try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void);
        const ceilings = try tools.helper(a, module, "myl_core_test_ceilings", &.{ .u32, .u64 }, .void);
        const enter = try tools.helper(a, module, "myl_core_test_enter", &.{}, .void);
        const leave = try tools.helper(a, module, "myl_core_test_leave", &.{}, .void);
        return .{ .controls = controls, .originals = originals, .reset = reset, .tick = tick, .ceilings = ceilings, .enter = enter, .leave = leave };
    }

    /// Whether `function` rewrites function `index`: the entry, a trial, or an internal original function.
    pub fn touches(self: Test, module: *const ir.Module, index: usize) bool {
        const target = module.functions.items[index];
        if (target.signature.linkage != .internal) return false;
        return index == module.entry or std.mem.startsWith(u8, target.name, "__test_trial_") or index < self.originals;
    }

    /// Rewrite function `index`: the entry installs the frame and byte ceilings, a trial resets the step budget, and an original
    /// function charges a step at each block that has instructions and counts a frame from its entry block to each return.
    pub fn function(self: Test, a: std.mem.Allocator, module: *ir.Module, index: usize) error{OutOfMemory}!void {
        const target = &module.functions.items[index];
        if (target.signature.linkage != .internal) return;
        // A `@freestanding` function charges no step and counts no frame: each is a runtime call (`freestanding.zig`).
        if (index != module.entry and module.isFreestanding(target)) return;
        const controls = self.controls;
        var b: tools.Builder = .{ .arena = a, .function = target.* };
        if (index == module.entry) {
            const args = &.{ try b.constant(.u32, controls.ceilings.frames), try b.constant(.u64, @bitCast(controls.ceilings.memory)) };
            try prepend(&b, @fromBackingInt(0), module, self.ceilings, args);
        } else if (std.mem.startsWith(u8, target.name, "__test_trial_")) {
            const args = &.{ try b.constant(.u64, @bitCast(controls.max_steps)), try b.constant(.u32, controls.timeout_ms) };
            try prepend(&b, @fromBackingInt(0), module, self.reset, args);
        } else if (index < self.originals) {
            for (b.function.blocks.items, 0..) |block, block_index| {
                if (block.insts.items.len == 0) continue;
                const cost = try b.constant(.u64, 1);
                try prepend(&b, @fromBackingInt(@intCast(block_index)), module, self.tick, &.{cost});
            }
            try frame(&b, module, self.enter, self.leave);
        }
        module.functions.items[index] = b.function;
    }
};

const frame = run_budget.frame;
const prepend = run_budget.prepend;
