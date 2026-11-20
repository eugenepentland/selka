//! `selka run`'s budgets (NEW-CORE-S5-RUN-1) and the instrumentation the test
//! runner's budgets share: calls of runtime helpers inserted at block starts and
//! before returns. A run's `main` installs its step, frame, byte and wall-clock
//! ceilings before anything else (`myl_core_run_controls`, `runtime/core_test.c`).
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");

/// `selka run`'s budgets (NEW-CORE-S5-RUN-1). Zero leaves steps and frames
/// unbounded, the memory ceiling off and no wall-clock limit.
pub const RunBudget = struct {
    steps: u64 = 0,
    frames: u32 = 0,
    memory: u64 = 0,
    timeout_seconds: u32 = 0,
    /// Internal harness builds charge steps but read their ceiling at process startup.
    harness_steps: bool = false,
};

/// The runtime start a program's C entry calls when its `main` installs a budget (`installs`): it reads the program's options
/// but leaves the byte ceiling to that budget, so `SELKA_MEMORY_LIMIT` is not applied ahead of what the run settled (BIN-CEILING).
pub const budgeted_start = "myl_core_start_budgeted";

/// Whether `module`'s `main` installs a run's budget: the module declares `myl_core_run_controls` or its harness form.
pub fn installs(module: *const ir.Module) bool {
    for (module.functions.items) |function| {
        if (function.signature.linkage != .runtime_c) continue;
        if (std.mem.eql(u8, function.name, "myl_core_run_controls") or std.mem.eql(u8, function.name, "myl_core_harness_run_controls")) return true;
    }
    return false;
}

/// Instrument a whole program for one run: `main` installs the budget before
/// anything else, every program function charges one step per executed block when
/// steps are bounded, and counts one frame per call when frames are.
pub fn instrumentRun(a: std.mem.Allocator, module: *ir.Module, budget: RunBudget) error{OutOfMemory}!void {
    const run = try Run.declare(a, module, budget);
    for (0..module.functions.items.len) |index| try run.function(a, module, index);
}

/// One run's instrumentation, function by function: the helpers it calls, declared once on the module (`declare`), and the
/// rewrite of one function (`function`). Declaring and then rewriting every function is `instrumentRun`; a build that
/// materializes a body later rewrites it then, with the same result.
pub const Run = struct {
    budget: RunBudget,
    install: u32,
    tick: ?u32,
    enter: ?u32,
    leave: ?u32,

    /// Declare the helpers `budget` calls on `module`, in the order `instrumentRun` always declared them.
    pub fn declare(a: std.mem.Allocator, module: *ir.Module, budget: RunBudget) error{OutOfMemory}!Run {
        const install = try tools.helper(a, module, if (budget.harness_steps) "myl_core_harness_run_controls" else "myl_core_run_controls", &.{ .u64, .u32, .u64, .u32 }, .void);
        const tick = if (budget.steps != 0 or budget.harness_steps) try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void) else null;
        const enter = if (budget.frames != 0) try tools.helper(a, module, "myl_core_test_enter", &.{}, .void) else null;
        const leave = if (budget.frames != 0) try tools.helper(a, module, "myl_core_test_leave", &.{}, .void) else null;
        return .{ .budget = budget, .install = install, .tick = tick, .enter = enter, .leave = leave };
    }

    /// Whether `function` rewrites function `index`: an internal function, when steps or frames are counted, and `main`.
    pub fn touches(self: Run, module: *const ir.Module, index: usize) bool {
        if (module.functions.items[index].signature.linkage != .internal) return false;
        return self.tick != null or self.enter != null or index == module.entry;
    }

    /// Rewrite function `index`: a step charged at each block that has instructions, a frame counted from the entry block to each
    /// return, and in `main` the budget installed before anything else.
    pub fn function(self: Run, a: std.mem.Allocator, module: *ir.Module, index: usize) error{OutOfMemory}!void {
        const slot = &module.functions.items[index];
        if (slot.signature.linkage != .internal) return;
        // A `@freestanding` function charges no step and counts no frame: each is a runtime call (`freestanding.zig`).
        if (index != module.entry and module.isFreestanding(slot)) return;
        var b: tools.Builder = .{ .arena = a, .function = slot.* };
        if (self.tick) |helper| for (b.function.blocks.items, 0..) |block, block_index| {
            if (block.insts.items.len == 0) continue;
            try prepend(&b, @fromBackingInt(@intCast(block_index)), module, helper, &.{try b.constant(.u64, 1)});
        };
        if (self.enter) |entering| try frame(&b, module, entering, self.leave.?);
        if (index == module.entry) {
            const budget = self.budget;
            const args = &.{
                try b.constant(.u64, @bitCast(budget.steps)),  try b.constant(.u32, budget.frames),
                try b.constant(.u64, @bitCast(budget.memory)), try b.constant(.u32, budget.timeout_seconds),
            };
            try prepend(&b, @fromBackingInt(0), module, self.install, args);
        }
        module.functions.items[index] = b.function;
    }
};

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

/// Insert a call of `helper` at the start of `block`, after its phis and copies. The
/// call takes the source position of the instruction it precedes, so a budget's trap
/// in it is located at the block's first statement (NEW-CORE-S5-TRACE-1).
pub fn prepend(b: *tools.Builder, block: ir.BlockId, module: *const ir.Module, helper: u32, arguments: []const ir.Ref) error{OutOfMemory}!void {
    const ref = try b.call(block, module, helper, arguments);
    const list = &b.function.blocks.items[block.index()].insts;
    list.items.len -= 1;
    var first: usize = 0;
    while (first < list.items.len) : (first += 1) {
        const op = b.function.inst(list.items[first]).op;
        if (op != .phi and op != .copy) break;
    }
    b.function.insts.items[ref.index()].span = located(&b.function, block);
    try list.insert(b.arena, first, ref);
}

/// The first source position in `block`, else in the block its bare jump reaches (a
/// loop's latch holds only the jump back to its header); 0 when neither has one.
fn located(function: *const ir.Function, block: ir.BlockId) u32 {
    var at = block;
    for (0..2) |_| {
        const list = function.blocks.items[at.index()].insts.items;
        for (list) |ref| if (function.inst(ref).span != 0) return function.inst(ref).span;
        if (list.len == 0 or function.inst(list[list.len - 1]).op != .jump) return 0;
        at = @fromBackingInt(@as(u32, @intCast(function.inst(list[list.len - 1]).data)));
    }
    return 0;
}
