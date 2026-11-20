//! The budget instrumentation function by function (`run_budget.Run`, `test_runner_budget.Test`) rewrites every function
//! exactly as the whole-module instrumentation did (lane EM, stage 5b landing 1): the same instructions, blocks and operands,
//! function by function, on a program with loops, recursion, an extern, a function whose block holds nothing, a trial and the entry. (An
//! internal function with no block at all never reaches the instrumentation: lowering gives every body an entry block, and the
//! whole-module form indexed block 0 for it.)
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const support = @import("test_support.zig");
const build = @import("build.zig");
const run_budget = @import("run_budget.zig");
const test_budget = @import("test_runner_budget.zig");
const options = @import("test_runner_options.zig");

const program =
    \\func countdown(n: int) -> int:
    \\    if n <= 0:
    \\        return 0
    \\    return countdown(n - 1) + 1
    \\
    \\func my_sum(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        if i % 2 == 0:
    \\            total = total + i
    \\    return total
    \\
    \\func main() -> int:
    \\    return my_sum(10) + countdown(3)
    \\
;

/// The program lowered, with a function of no blocks, a trial, an extern and a runtime declaration added beside it: what the
/// runner's entry adds and what lowering can leave, as the instrumentation meets them.
fn fixture(a: std.mem.Allocator) !ir.Module {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    // A function whose one block holds no instruction: no step is charged in it, and its frame still starts there.
    var empty: ir.Function = .{ .name = "empty::no_instructions", .signature = .{ .params = &.{}, .ret = .void } };
    try empty.blocks.append(a, .{});
    try module.functions.append(a, empty);
    var trial = try support.Hand.init(a, &module, "__test_trial_0", .{ .params = &.{}, .ret = .i64 });
    _ = try trial.emit(.{ .op = .ret, .ty = .void, .a = try trial.int(.i64, 1) });
    _ = try trial.finish();
    try module.functions.append(a, .{ .name = "c_side", .signature = .{ .params = &.{.i64}, .ret = .i64, .linkage = .extern_c } });
    _ = try tools.helper(a, &module, "myl_core_unrelated", &.{.u64}, .void);
    return module;
}

/// `run_budget.instrumentRun` as it was before the per-function form, kept as the oracle.
fn referenceRun(a: std.mem.Allocator, module: *ir.Module, budget: run_budget.RunBudget) !void {
    const install = try tools.helper(a, module, if (budget.harness_steps) "myl_core_harness_run_controls" else "myl_core_run_controls", &.{ .u64, .u32, .u64, .u32 }, .void);
    const tick = if (budget.steps != 0 or budget.harness_steps) try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void) else null;
    const enter = if (budget.frames != 0) try tools.helper(a, module, "myl_core_test_enter", &.{}, .void) else null;
    const leave = if (budget.frames != 0) try tools.helper(a, module, "myl_core_test_leave", &.{}, .void) else null;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        var b: tools.Builder = .{ .arena = a, .function = function.* };
        if (tick) |helper| for (b.function.blocks.items, 0..) |block, block_index| {
            if (block.insts.items.len == 0) continue;
            try run_budget.prepend(&b, @fromBackingInt(@intCast(block_index)), module, helper, &.{try b.constant(.u64, 1)});
        };
        if (enter) |entering| try run_budget.frame(&b, module, entering, leave.?);
        if (index == module.entry) {
            const args = &.{
                try b.constant(.u64, @bitCast(budget.steps)),  try b.constant(.u32, budget.frames),
                try b.constant(.u64, @bitCast(budget.memory)), try b.constant(.u32, budget.timeout_seconds),
            };
            try run_budget.prepend(&b, @fromBackingInt(0), module, install, args);
        }
        function.* = b.function;
    }
}

/// `test_runner_budget.instrument` as it was before the per-function form, kept as the oracle.
fn referenceTest(a: std.mem.Allocator, module: *ir.Module, originals: usize, controls: options.Controls) !void {
    const reset = try tools.helper(a, module, "myl_core_test_limits", &.{ .u64, .u32 }, .void);
    const tick = try tools.helper(a, module, "myl_core_test_tick", &.{.u64}, .void);
    const ceilings = try tools.helper(a, module, "myl_core_test_ceilings", &.{ .u32, .u64 }, .void);
    const enter = try tools.helper(a, module, "myl_core_test_enter", &.{}, .void);
    const leave = try tools.helper(a, module, "myl_core_test_leave", &.{}, .void);
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        var b: tools.Builder = .{ .arena = a, .function = function.* };
        if (index == module.entry) {
            const args = &.{ try b.constant(.u32, controls.ceilings.frames), try b.constant(.u64, @bitCast(controls.ceilings.memory)) };
            try run_budget.prepend(&b, @fromBackingInt(0), module, ceilings, args);
        } else if (std.mem.startsWith(u8, function.name, "__test_trial_")) {
            const args = &.{ try b.constant(.u64, @bitCast(controls.max_steps)), try b.constant(.u32, controls.timeout_ms) };
            try run_budget.prepend(&b, @fromBackingInt(0), module, reset, args);
        } else if (index < originals) {
            for (b.function.blocks.items, 0..) |block, block_index| {
                if (block.insts.items.len == 0) continue;
                const cost = try b.constant(.u64, 1);
                try run_budget.prepend(&b, @fromBackingInt(@intCast(block_index)), module, tick, &.{cost});
            }
            try run_budget.frame(&b, module, enter, leave);
        }
        function.* = b.function;
    }
}

/// Every function of the two modules is the same: name, linkage, instructions, blocks with their predecessors, and operands.
fn expectSameModules(expected: *const ir.Module, actual: *const ir.Module) !void {
    try std.testing.expectEqual(expected.functions.items.len, actual.functions.items.len);
    for (expected.functions.items, actual.functions.items) |left, right| try expectSameFunction(left, right);
}

fn expectSameFunction(left: ir.Function, right: ir.Function) !void {
    try std.testing.expectEqualStrings(left.name, right.name);
    try std.testing.expectEqual(left.signature.linkage, right.signature.linkage);
    try std.testing.expectEqualSlices(ir.Inst, left.insts.items, right.insts.items);
    try std.testing.expectEqualSlices(ir.Ref, left.extra.items, right.extra.items);
    try std.testing.expectEqual(left.blocks.items.len, right.blocks.items.len);
    for (left.blocks.items, right.blocks.items) |a, b| {
        try std.testing.expectEqualSlices(ir.Ref, a.insts.items, b.insts.items);
        try std.testing.expectEqualSlices(ir.BlockId, a.preds.items, b.preds.items);
    }
}

/// The run instrumentation of `budget` both ways, on two lowerings of the fixture.
fn expectRunAlike(a: std.mem.Allocator, budget: run_budget.RunBudget) !void {
    var old = try fixture(a);
    var new = try fixture(a);
    try referenceRun(a, &old, budget);
    try run_budget.instrumentRun(a, &new, budget);
    try expectSameModules(&old, &new);
}

/// The test instrumentation both ways, the entry and the trial counted as added after `originals`.
fn expectTestAlike(a: std.mem.Allocator, controls: options.Controls) !void {
    var old = try fixture(a);
    var new = try fixture(a);
    const originals = old.functions.items.len - 3;
    try referenceTest(a, &old, originals, controls);
    try test_budget.instrument(a, &new, originals, controls);
    try expectSameModules(&old, &new);
}

test "a run's budget instrumented function by function is the whole-module instrumentation, for every kind of budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectRunAlike(a, .{ .steps = 1000, .frames = 64, .memory = 1 << 20, .timeout_seconds = 5 });
    try expectRunAlike(a, .{ .steps = 1000 });
    try expectRunAlike(a, .{ .frames = 64 });
    try expectRunAlike(a, .{ .memory = 1 << 20 });
    try expectRunAlike(a, .{ .harness_steps = true });
    var module = try fixture(a);
    const plan = try run_budget.Run.declare(a, &module, .{ .memory = 1 << 20 });
    // With neither steps nor frames counted only `main` is rewritten.
    try std.testing.expect(plan.touches(&module, module.entry));
    try std.testing.expect(!plan.touches(&module, 0) or module.entry == 0);
}

fn firstLine(_: *const anyopaque, _: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = 1 };
}

/// A one-line program emitted whole as a built program's entry (`runtime_options`), after `budget` is instrumented when
/// there is one.
fn emittedEntry(a: std.mem.Allocator, budget: ?run_budget.RunBudget) ![]const u8 {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, "func main() -> int:\n    return 0\n", &refusal);
    if (budget) |installed| try run_budget.instrumentRun(a, &module, installed);
    try std.testing.expectEqual(budget != null, run_budget.installs(&module));
    const context: u8 = 0;
    return @import("emit_llvm.zig").emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "start.selka", .main = .{ .runtime_options = true } });
}

test "a built program's entry starts with the environment's byte ceiling, and one whose main installs a run's budget without it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = try emittedEntry(a, null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "  call void @myl_core_start()\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, run_budget.budgeted_start) == null);
    for ([_]run_budget.RunBudget{ .{ .memory = 1 << 20 }, .{}, .{ .harness_steps = true, .memory = 1 << 20 } }) |budget| {
        const run = try emittedEntry(a, budget);
        try std.testing.expect(std.mem.indexOf(u8, run, "  call void @myl_core_start_budgeted()\n") != null);
        try std.testing.expect(std.mem.indexOf(u8, run, "declare void @myl_core_start_budgeted() nounwind\n") != null);
        try std.testing.expect(std.mem.indexOf(u8, run, "call void @myl_core_start()") == null);
    }
}

test "a test program's budget instrumented function by function is the whole-module instrumentation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectTestAlike(a, .{});
    try expectTestAlike(a, .{ .max_steps = 0, .timeout_ms = 10, .ceilings = .{ .frames = 7, .memory = 4096 } });
    var module = try fixture(a);
    const originals = module.functions.items.len - 3;
    const plan = try test_budget.Test.declare(a, &module, originals, .{});
    try std.testing.expect(plan.touches(&module, module.entry));
    try std.testing.expect(plan.touches(&module, originals));
    // The extern and the runtime declarations are never rewritten.
    try std.testing.expect(!plan.touches(&module, originals + 1));
    try std.testing.expect(!plan.touches(&module, originals + 2));
}
