//! `mylang run`'s budgets (NEW-CORE-S5-RUN-1) and the instrumentation the test
//! runner's budgets share: calls of runtime helpers inserted at block starts and
//! before returns. A run's `main` installs its step, frame, byte and wall-clock
//! ceilings before anything else (`myl_core_run_controls`, `runtime/core_test.c`).
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");

/// `mylang run`'s budgets (NEW-CORE-S5-RUN-1). Zero leaves steps and frames
/// unbounded, the memory ceiling off and no wall-clock limit.
pub const RunBudget = struct {
    steps: u64 = 0,
    frames: u32 = 0,
    memory: u64 = 0,
    timeout_seconds: u32 = 0,
};

/// Instrument a whole program for one run: `main` installs the budget before
/// anything else, every program function charges one step per executed block when
/// steps are bounded, and counts one frame per call when frames are.
pub fn instrumentRun(a: std.mem.Allocator, module: *ir.Module, budget: RunBudget) error{OutOfMemory}!void {
    const install = try tools.helper(a, module, "myl_core_run_controls", &.{ .u64, .u32, .u64, .u32 }, .void);
    const tick = if (budget.steps != 0) try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void) else null;
    const enter = if (budget.frames != 0) try tools.helper(a, module, "myl_core_test_enter", &.{}, .void) else null;
    const leave = if (budget.frames != 0) try tools.helper(a, module, "myl_core_test_leave", &.{}, .void) else null;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        var b: tools.Builder = .{ .arena = a, .function = function.* };
        if (tick) |helper| for (b.function.blocks.items, 0..) |block, block_index| {
            if (block.insts.items.len == 0) continue;
            try prepend(&b, @fromBackingInt(@intCast(block_index)), module, helper, &.{try b.constant(.u64, 1)});
        };
        if (enter) |entering| try frame(&b, module, entering, leave.?);
        if (index == module.entry) {
            const args = &.{
                try b.constant(.u64, @bitCast(budget.steps)),  try b.constant(.u32, budget.frames),
                try b.constant(.u64, @bitCast(budget.memory)), try b.constant(.u32, budget.timeout_seconds),
            };
            try prepend(&b, @fromBackingInt(0), module, install, args);
        }
        function.* = b.function;
    }
}

/// Count one frame from the entry block until each return.
pub fn frame(b: *tools.Builder, module: *const ir.Module, enter: u32, leave: u32) error{OutOfMemory}!void {
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

/// Insert a call of `helper` at the start of `block`, after its phis and copies.
pub fn prepend(b: *tools.Builder, block: ir.BlockId, module: *const ir.Module, helper: u32, arguments: []const ir.Ref) error{OutOfMemory}!void {
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
