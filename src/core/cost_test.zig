//! Regression coverage for the cost report and its allocation contract.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const command = @import("cost_command.zig");
const remarks = @import("cost_remarks.zig");
const flags = @import("flags.zig");

const program =
    \\def leaf(x: int) -> int:
    \\    return x & 7
    \\def borrowed(xs: list[int]) -> list[int]:
    \\    ys = xs
    \\    ys[0] = 4
    \\    return ys
    \\def consuming(xs: mut list[int]) -> int:
    \\    xs[0] = 5
    \\    return xs[0]
    \\def fresh(n: int) -> int:
    \\    xs: list[int] = []
    \\    xs.append(n)
    \\    return xs[0] + leaf(n)
    \\def main(out: Stream) -> int:
    \\    xs = [1, 2]
    \\    snapshots = [xs, xs]
    \\    out.print(snapshots)
    \\    ys = borrowed(xs)
    \\    out.print(ys, consuming(mut xs), fresh(3))
    \\    return 0
;

fn measured(a: std.mem.Allocator, source: []const u8, mode: ?passes.Mode) !cost.Report {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = if (mode) |release| try support.runPasses(a, &module, release) else try passes.debug(a, &module);
    const report = try cost.measure(a, &module, &result, null);
    // The report's whole-program events must be identical to the optimizer's counters.
    try std.testing.expectEqual(result.counts.inlined, report.totals.inlined_calls);
    try std.testing.expectEqual(result.counts.proven, report.totals.checks.proved);
    try std.testing.expectEqual(result.counts.unswitched, report.totals.loops.unswitched);
    try std.testing.expectEqual(result.counts.versioned, report.totals.loops.versioned);
    try std.testing.expectEqual(result.counts.vectorized, report.totals.loops.vector_plans);
    try std.testing.expectEqual(result.own.in_place, report.totals.updates.in_place);
    try std.testing.expectEqual(result.own.tested, report.totals.updates.tested);
    try std.testing.expectEqual(result.own.copied, report.totals.updates.copied);
    try std.testing.expectEqual(result.own.retains, report.totals.rc.retains);
    try std.testing.expectEqual(result.own.releases, report.totals.rc.releases);
    try std.testing.expectEqual(result.own.elided, report.totals.rc.elided_pairs);
    try std.testing.expectEqual(result.own.promoted, report.totals.rc.stack_lists);
    return report;
}

fn named(report: cost.Report, name: []const u8) cost.Counts {
    for (report.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.counts;
    unreachable;
}

// spec: FRONTEND-COST-1
test "cost attributes inlining checks and all ownership forms to emitted bodies in debug release and verify" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const debug = try measured(a, program, null);
    try std.testing.expect(named(debug, "borrowed").updates.copied > 0);
    try std.testing.expect(named(debug, "consuming").updates.tested > 0);
    try std.testing.expect(named(debug, "fresh").updates.in_place > 0);
    try std.testing.expect(debug.totals.checks.kept > 0);
    try std.testing.expect(debug.totals.allocation.sites > 0);
    try std.testing.expect(debug.totals.rc.retains > 0);
    try std.testing.expect(debug.totals.rc.releases > 0);
    try std.testing.expectEqual(@as(u32, 0), debug.totals.inlined_calls);
    const release = try measured(a, program, .trusted);
    try std.testing.expect(named(release, "fresh").inlined_calls > 0);
    try std.testing.expect(release.totals.checks.proved > 0);
    try std.testing.expect(release.totals.rc.stack_lists > 0);
    const verify = try measured(a, program, .verify);
    try std.testing.expect(verify.totals.checks.kept >= release.totals.checks.kept);
    _ = try measured(a, program, .off);
    try elidedCount(a);
}

// spec-case: FRONTEND-COST-1
test "cost allocation classification includes growth scratch and unresolved calls but excludes stack and borrow identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.functions.appendSlice(a, &.{
        .{ .name = "local", .signature = .{ .params = &.{}, .ret = .void } },
        .{ .name = "myl_core_text_encode", .signature = .{ .params = &.{.str}, .ret = .bytes, .linkage = .runtime_c } },
        .{ .name = "myl_core_str_join", .signature = .{ .params = &.{}, .ret = .str, .linkage = .runtime_c } },
        .{ .name = "foreign", .signature = .{ .params = &.{}, .ret = .void, .linkage = .extern_c } },
    });
    var function: ir.Function = .{ .name = "test", .signature = .{ .params = &.{}, .ret = .void } };
    try function.insts.appendSlice(a, &.{ .{ .op = .func_ref, .ty = .void, .data = 0 }, .{ .op = .param, .ty = .void } });
    for ([_]ir.Op{ .list_new, .list_push, .list_copy, .dict_new, .dict_copy, .dict_insert, .box_make, .str_char, .str_append, .str_append_char, .str_slice, .str_from_view, .list_sort, .buffer_new, .buffer_copy, .buffer_push }) |op| {
        try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, .{ .op = op, .ty = .void }));
    }
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .list_new, .ty = .void, .data = 3 }));
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, .{ .op = .list_new, .ty = .void, .data = flags.fill_capacity }));
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .list_push, .ty = .void, .data = @import("promote.zig").stack_push }));
    try directCalls(&module, &function);
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .call_indirect, .ty = .void, .a = @fromBackingInt(0) }));
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &function, .{ .op = .call_indirect, .ty = .void, .a = @fromBackingInt(1) }));
    try std.testing.expect(!cost.runtimeAllocationFree("myl_core_future_helper"));
}

// spec-case: FRONTEND-COST-1
test "cost LLVM remarks distinguish successful vectorization from plans misses and unavailable evidence" {
    var rows = [_]cost.Function{ .{ .name = "app::loop", .counts = .{ .loops = .{ .unknown = 2, .vector_plans = 1 } } }, .{ .name = "app::other", .counts = .{ .loops = .{ .unknown = 1 } } } };
    var report: cost.Report = .{ .functions = &rows, .totals = .{} };
    remarks.apply(&report,
        \\--- !Passed
        \\Pass:            loop-vectorize
        \\Name:            Vectorized
        \\Function:        'my.app::loop'
        \\...
        \\--- !Missed
        \\Pass:            loop-vectorize
        \\Name:            MissedDetails
        \\Function:        'app::other'
        \\...
        \\--- !Passed
        \\Pass:            inline
        \\Name:            Inlined
        \\Function:        'app::other'
        \\...
    );
    try std.testing.expectEqual(@as(?u32, 1), rows[0].counts.llvm_vectorized_loops);
    try std.testing.expect(rows[1].counts.llvm_vectorized_loops == null);
    try std.testing.expectEqual(@as(u32, 3), report.totals.loops.unknown);
    try std.testing.expectEqual(@as(u32, 1), report.totals.loops.vector_plans);
}

// spec-case: FRONTEND-COST-1
test "cost command filters names rejects unknown flags and renders stable totals as text and JSON" {
    try std.testing.expect(command.parse(&.{ "entry.my", "f", "--json" }).?.json);
    try std.testing.expect(command.parse(&.{ "entry.my", "--debug", "--verify-facts" }) == null);
    try std.testing.expect(command.parse(&.{ "entry.my", "--unknown" }) == null);
    try std.testing.expect(command.parse(&.{ "entry.my", "--llvm-remarks" }) == null);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const report = try cost.measure(a, &module, &result, "fresh");
    try std.testing.expectEqual(@as(usize, 1), report.functions.len);
    try std.testing.expectEqualDeep(report.functions[0].counts, report.totals);
    const json = try cost.render(a, report, true);
    const parsed = try std.json.parseFromSlice(cost.Report, a, json, .{});
    try std.testing.expectEqualDeep(report.totals, parsed.value.totals);
    const text = try cost.render(a, report, false);
    try std.testing.expect(std.mem.indexOf(u8, text, "TOTAL:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "LLVM vectorized unknown") != null);
    try std.testing.expectEqual(@as(usize, 0), (try cost.measure(a, &module, &result, "missing")).functions.len);
}

fn directCalls(module: *const ir.Module, function: *const ir.Function) !void {
    for ([_]cost.Allocation{ .never, .never, .may, .unresolved }, 0..) |expected, index| {
        try std.testing.expectEqual(expected, cost.allocation(module, function, .{ .op = .call, .ty = .void, .a = @fromBackingInt(@intCast(index)) }));
    }
}

const reduction =
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = len(args) + 100
    \\    values = [(j * 37 + 5) % 1009 for j in range(n)]
    \\    total = 0
    \\    for j in range(n):
    \\        total += ((values[j] + 3) * 17 + 23) // 7 % 1009
    \\    out.print(total)
    \\    return 0
;

// spec-case: FRONTEND-COST-1
test "cost includes real vector plans loop guards and unswitched cloned body events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const vectorized = try measured(a, reduction, .trusted);
    try std.testing.expect(vectorized.totals.loops.vector_plans > 0);
    const guarded = try measured(a,
        \\def main(args: list[str], out: Stream) -> int:
        \\    n = len(args) + 100
        \\    values = [(j * 37) % 1009 for j in range(n)]
        \\    total = 0
        \\    for j in range(n):
        \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
        \\    out.print(total)
        \\    return 0
    , .trusted);
    try std.testing.expect(guarded.totals.loops.versioned > 0);
    const unswitched = try measured(a,
        \\def origin(xs: mut list[int], x: int, kind: int) -> int:
        \\    xs.append(2)
        \\    total = 0
        \\    for i in range(x):
        \\        if kind == 0:
        \\            total += xs[i]
        \\        else:
        \\            total += xs[i] + 1
        \\    return total
        \\def main(args: list[str]) -> int:
        \\    xs = [1]
        \\    return origin(mut xs, 3, len(args))
    , .verify);
    try std.testing.expect(unswitched.totals.loops.unswitched > 0);
}

// spec-case: FRONTEND-COST-1
test "cost allocation sites remain in cold callees two calls down before release optimization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const debug = try measured(arena.allocator(),
        \\def deep(flag: bool) -> int:
        \\    if flag:
        \\        xs = [1]
        \\        return len(xs)
        \\    return 0
        \\def second(flag: bool) -> int:
        \\    return deep(flag)
        \\def first(flag: bool) -> int:
        \\    return second(flag)
        \\def main(out: Stream) -> int:
        \\    out.print(first(False))
        \\    return 0
    , null);
    try std.testing.expect(named(debug, "deep").allocation.sites > 0);
    try std.testing.expectEqual(@as(u32, 0), named(debug, "first").allocation.sites);
    try std.testing.expectEqual(@as(u32, 0), named(debug, "second").allocation.sites);
}

// The removed instructions cannot be counted after the pass. Preserve its actual
// event in the same per-function result that a build supplies to the cost report.
fn elidedCount(a: std.mem.Allocator) !void {
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    var h = try support.Hand.init(a, &module, "peephole", .{ .params = try a.dupe(ir.Type, &.{ints}), .ret = .u64 });
    const p = try h.param(0);
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = p });
    const n = try h.emit(.{ .op = .list_len, .ty = .u64, .a = p });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = p });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = n });
    _ = try h.finish();
    const dropped = try @import("own.zig").elidePairs(a, &module.functions.items[0]);
    try std.testing.expectEqual(@as(u32, 1), dropped);
    var local = [_]passes.FunctionStats{.{ .own = .{ .elided = dropped } }};
    const result: passes.Result = .{ .known = &.{}, .plans = &.{}, .per_function = &local, .own = local[0].own };
    const report = try cost.measure(a, &module, &result, null);
    try std.testing.expectEqual(@as(u32, 1), named(report, "peephole").rc.elided_pairs);
    try std.testing.expectEqual(result.own.elided, report.totals.rc.elided_pairs);
    try std.testing.expectEqual(@as(u32, 0), report.totals.rc.retains);
    try std.testing.expectEqual(@as(u32, 0), report.totals.rc.releases);
}
