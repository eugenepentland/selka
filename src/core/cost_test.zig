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
    \\func leaf(x: int) -> int:
    \\    return x & 7
    \\func borrowed(xs: int[]) -> int[]:
    \\    mut ys = xs
    \\    ys[0] = 4
    \\    return ys
    \\func consuming(mut xs: int[]) -> int:
    \\    xs[0] = 5
    \\    return xs[0]
    \\func fresh(n: int) -> int:
    \\    mut xs: int[] = []
    \\    xs.append(n)
    \\    return xs[0] + leaf(n)
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2]
    \\    mut snapshots = [xs, xs]
    \\    out.print(snapshots)
    \\    mut ys = borrowed(xs)
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
    for ([_]ir.Op{
        .list_new,    .list_push,  .list_copy,       .dict_new,  .dict_copy,     .dict_insert, .dict_remove, .box_make,
        .str_char,    .str_append, .str_append_char, .str_slice, .str_from_view, .list_sort,   .buffer_new,  .buffer_copy,
        .buffer_push,
    }) |op| {
        try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, .{ .op = op, .ty = .void }));
    }
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .list_new, .ty = .void, .data = 3 }));
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, .{ .op = .list_new, .ty = .void, .data = flags.fill_capacity }));
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .list_push, .ty = .void, .data = @import("promote.zig").stack_push }));
    try directCalls(&module, &function);
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .call_indirect, .ty = .void, .a = @fromBackingInt(0) }));
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &function, .{ .op = .call_indirect, .ty = .void, .a = @fromBackingInt(1) }));
    try std.testing.expect(!cost.runtimeAllocationFree("myl_core_future_helper"));
    try deletionCount(a);
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
    try std.testing.expect(command.parse(&.{ "entry.selka", "f", "--json" }).?.json);
    try std.testing.expect(command.parse(&.{ "entry.selka", "--debug", "--verify-facts" }) == null);
    try std.testing.expect(command.parse(&.{ "entry.selka", "--unknown" }) == null);
    try std.testing.expect(command.parse(&.{ "entry.selka", "--llvm-remarks" }) == null);
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
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values = [for j in range(n) yield (j * 37 + 5) % 1009]
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += ((values[j] + 3) * 17 + 23) // 7 % 1009
    \\    out.print(total)
    \\    return 0
;

// spec: NEW-CORE-FSX-VERSION-1
test "a reduction loop is versioned only when its body makes no call and holds no other loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A flat body: the clone proves the sum, so the loop is versioned.
    const flat = try measured(a,
        \\func main(args: str[], out: Stream) -> int:
        \\    mut n = len(args) + 100
        \\    mut values = [for j in range(n) yield (j * 37) % 1009]
        \\    mut total = 0
        \\    for j in range(n):
        \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
        \\    out.print(total)
        \\    return 0
    , .trusted);
    try std.testing.expect(flat.totals.loops.versioned > 0);
    // The sum of a call's results (its return interval bounds each summand): no clone.
    const called = try measured(a,
        \\func search(values: int[], key: int) -> int:
        \\    mut low = 0
        \\    mut high = len(values)
        \\    while low < high:
        \\        mut middle = (low + high) // 2
        \\        if values[middle] < key:
        \\            low = middle + 1
        \\        else:
        \\            high = middle
        \\    return low
        \\func main(args: str[], out: Stream) -> int:
        \\    mut n = len(args) + 100
        \\    mut values = [for j in range(n) yield j * 3]
        \\    mut total = 0
        \\    for j in range(n):
        \\        total += search(values, j)
        \\    out.print(total)
        \\    return 0
    , .trusted);
    try std.testing.expectEqual(@as(u32, 0), called.totals.loops.versioned);
    // The same sum with the search written inline, an inner loop: no clone either.
    const nested = try measured(a,
        \\func main(args: str[], out: Stream) -> int:
        \\    mut n = len(args) + 100
        \\    mut values = [for j in range(n) yield j * 3]
        \\    mut total = 0
        \\    for j in range(n):
        \\        mut low = 0
        \\        mut high = len(values)
        \\        while low < high:
        \\            mut middle = (low + high) // 2
        \\            if values[middle] < j:
        \\                low = middle + 1
        \\            else:
        \\                high = middle
        \\        total += low
        \\    out.print(total)
        \\    return 0
    , .trusted);
    try std.testing.expectEqual(@as(u32, 0), nested.totals.loops.versioned);
}

// spec-case: FRONTEND-COST-1
test "cost includes real vector plans loop guards and unswitched cloned body events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const vectorized = try measured(a, reduction, .trusted);
    try std.testing.expect(vectorized.totals.loops.vector_plans > 0);
    const guarded = try measured(a,
        \\func main(args: str[], out: Stream) -> int:
        \\    mut n = len(args) + 100
        \\    mut values = [for j in range(n) yield (j * 37) % 1009]
        \\    mut total = 0
        \\    for j in range(n):
        \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
        \\    out.print(total)
        \\    return 0
    , .trusted);
    try std.testing.expect(guarded.totals.loops.versioned > 0);
    const unswitched = try measured(a,
        \\func origin(mut xs: int[], x: int, kind: int) -> int:
        \\    xs.append(2)
        \\    mut total = 0
        \\    for i in range(x):
        \\        if kind == 0:
        \\            total += xs[i]
        \\        else:
        \\            total += xs[i] + 1
        \\    return total
        \\func main(args: str[]) -> int:
        \\    mut xs = [1]
        \\    return origin(mut xs, 3, len(args))
    , .verify);
    try std.testing.expect(unswitched.totals.loops.unswitched > 0);
}

// spec-case: FRONTEND-COST-1
test "cost allocation sites remain in cold callees two calls down before release optimization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const debug = try measured(arena.allocator(),
        \\func deep(flag: bool) -> int:
        \\    if flag:
        \\        mut xs = [1]
        \\        return len(xs)
        \\    return 0
        \\func second(flag: bool) -> int:
        \\    return deep(flag)
        \\func first(flag: bool) -> int:
        \\    return second(flag)
        \\func main(out: Stream) -> int:
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

// A unique dictionary still allocates its tombstone bitmap on the first deletion.
fn deletionCount(a: std.mem.Allocator) !void {
    const report = try measured(a,
        \\func remove(mut d: dict[int, int]) -> int:
        \\    _ = d.pop(1)
        \\    return len(d)
        \\func main(out: Stream) -> int:
        \\    mut d = {1: 2}
        \\    out.print(remove(mut d))
        \\    return 0
    , null);
    // The ownership copy branch and the dictionary's own deletion scratch count.
    try std.testing.expectEqual(@as(u32, 2), named(report, "remove").allocation.sites);
}

// spec: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts visit internal callees cold blocks and recursive graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contracts = @import("allocation_contract.zig");
    var module: ir.Module = .{};
    for ([_][]const u8{ "bounded", "helper", "cold" }) |name| {
        var function: ir.Function = .{ .name = name, .signature = .{ .params = &.{}, .ret = .void } };
        try function.blocks.append(a, .{});
        try module.functions.append(a, function);
    }
    try module.functions.items[0].insts.append(a, .{ .op = .call, .ty = .void, .a = @fromBackingInt(1) });
    try module.functions.items[0].blocks.items[0].insts.append(a, @fromBackingInt(0));
    // The recursive edge must terminate; a disconnected block still contributes.
    try module.functions.items[1].insts.append(a, .{ .op = .call, .ty = .void, .a = @fromBackingInt(0) });
    try module.functions.items[1].blocks.items[0].insts.append(a, @fromBackingInt(0));
    try module.functions.items[1].blocks.append(a, .{});
    try module.functions.items[1].insts.append(a, .{ .op = .call, .ty = .void, .a = @fromBackingInt(2) });
    try module.functions.items[1].blocks.items[1].insts.append(a, @fromBackingInt(1));
    try module.functions.items[2].insts.append(a, .{ .op = .buffer_new, .ty = .void, .span = 91 });
    try module.functions.items[2].blocks.items[0].insts.append(a, @fromBackingInt(0));
    const failure = (try contracts.witness(a, &module, 0)).?;
    try std.testing.expectEqualStrings("cold", failure.callee);
    try std.testing.expectEqual(@as(u32, 91), failure.span);
    module.functions.items[2].insts.items[0].op = .ret;
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.witness(a, &module, 0));
    module.functions.items[2].signature.linkage = .extern_c;
    try std.testing.expect((try contracts.witness(a, &module, 0)).?.unresolved);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts check unused library bodies and expose ownership copies" {
    const language = @import("selka");
    const contracts = @import("allocation_contract.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pure = try language.Compilation.init(a, "library.selka", "func scalar(value: int) -> int noalloc:\n    return value + 1\n");
    const pure_program = try pure.checkLibraryProgram();
    try std.testing.expect(pure.program == null);
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, pure_program, pure.src));
    var copied = try language.Compilation.init(a, "library.selka", "func fixed(mut values: int[]) -> Unit noalloc:\n    values[0] = 42\n");
    const copied_program = try copied.checkLibraryProgram();
    const failure = (try contracts.checkProgram(a, copied_program, copied.src)).?;
    try std.testing.expectEqualStrings("fixed", failure.function);
    try std.testing.expect(!failure.unresolved);
    try std.testing.expect(failure.unsupported == null);
    try std.testing.expectEqual(@as(u32, 2), @import("frontend.zig").position(copied.src, .{ .start = failure.span, .end = failure.span }).line);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts reject compound dictionary scratch on cold internal paths" {
    const language = @import("selka");
    const contracts = @import("allocation_contract.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func probe(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return key in values
        \\func bounded(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool noalloc:
        \\    if False:
        \\        return probe(values, key)
        \\    return False
    ;
    var unit = try language.Compilation.init(a, "scratch.selka", source);
    const scratch_program = try unit.checkLibraryProgram();
    const failure = (try contracts.checkProgram(a, scratch_program, unit.src)).?;
    try std.testing.expectEqualStrings("bounded", failure.function);
    try std.testing.expectEqualStrings("probe", failure.callee);
    try std.testing.expect(failure.unsupported == null);
    try std.testing.expect(!failure.unresolved);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts conservatively reject typed unresolved callbacks and preserve ordinary calls" {
    const language = @import("selka");
    const contracts = @import("allocation_contract.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bounded = try language.Compilation.init(a, "callback.selka", "func apply(f: func(int) -> int effects(), x: int) -> int noalloc:\n    return f(x)\n");
    const bounded_program = try bounded.checkLibraryProgram();
    const failure = (try contracts.checkProgram(a, bounded_program, bounded.src)).?;
    try std.testing.expect(failure.unresolved);
    try std.testing.expectEqualStrings("apply", failure.function);
    var ordinary = try language.Compilation.init(a, "callback.selka", "func apply(f: func(int) -> int effects(), x: int) -> int:\n    return f(x)\n");
    const ordinary_program = try ordinary.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, ordinary_program, ordinary.src));
    var generic = try language.Compilation.init(a, "generic.selka", "func identity[T: integer](value: T) -> T noalloc:\n    return value\nfunc scalar() -> int noalloc:\n    return identity(3)\n");
    var legacy = try language.Compilation.init(a, "legacy.selka", "func fixed(mut values: int[]) -> Unit effects(mutation):\n    values[0] = 42\nfunc apply(f: func(int) -> int effects(), x: int) -> int effects():\n    return f(x)\n");
    const legacy_program = try legacy.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, legacy_program, legacy.src));
    const generic_program = try generic.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, generic_program, generic.src));
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts distinguish compiler runtime scalar helpers from source extern names" {
    const language = @import("selka");
    const contracts = @import("allocation_contract.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parsed = try language.Compilation.init(a, "parse.selka", "func parse(raw: bytes) -> int? noalloc:\n    return raw.parse_int()\n");
    const parsed_program = try parsed.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, parsed_program, parsed.src));
    var compare = try language.Compilation.init(a, "compare.selka", "func choose(a: str, b: str) -> str noalloc:\n    return min(a, b)\n");
    const compare_program = try compare.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, compare_program, compare.src));
    var foreign = try language.Compilation.init(a, "foreign.selka", "extern func myl_core_parse_int_range(host: Host) -> int effects(host)\nfunc bounded(host: Host) -> int noalloc:\n    return myl_core_parse_int_range(host)\n");
    try std.testing.expectError(error.SourceError, foreign.checkLibraryProgram());
    try std.testing.expectEqualStrings("E_EXTERN_SYMBOL", foreign.diagnostics.items[0].code);
    // The classifier also refuses a source-spanned declaration in raw Core.
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = "myl_core_parse_int_range", .span = 13, .signature = .{ .params = &.{}, .ret = .void, .linkage = .extern_c } });
    const call: ir.Inst = .{ .op = .call, .ty = .void, .a = @fromBackingInt(0) };
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &module.functions.items[0], call));
    module.functions.items[0].span = 0;
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts pool fixed UTF8 errors and reject capability block allocation" {
    const language = @import("selka");
    const contracts = @import("allocation_contract.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const scalar_source = "func measure(raw: bytes) -> int noalloc:\n    match raw.scalar_count():\n        case Ok(width):\n            return width\n        case Err(_):\n            return 0\nfunc main() -> int:\n    return 0\n";
    var parsed = try language.Compilation.init(a, "count.selka", scalar_source);
    try parsed.check();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, parsed.program.?, parsed.src));
    var refusal: build.Refusal = .{};
    // Build the bounded root: main does not call this unused body.
    var owned = try build.buildRootsSource(a, parsed.program.?, &.{@fromBackingInt(0)}, parsed.src, &refusal);
    const bounded_outcome = try passes.debug(a, &owned);
    const bounded_report = try cost.measure(a, &owned, &bounded_outcome, "measure");
    try std.testing.expectEqual(@as(u32, 0), bounded_report.totals.allocation.sites);
    var restricted = try language.Compilation.init(a, "cap.selka", "func bounded(fs: Filesystem) -> int noalloc:\n    _ = fs.read_only()\n    return 0\n");
    const restricted_program = try restricted.checkLibraryProgram();
    const failure = (try contracts.checkProgram(a, restricted_program, restricted.src)).?;
    try std.testing.expectEqualStrings("bounded", failure.function);
    try std.testing.expect(failure.unsupported == null);
}
