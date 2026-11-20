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

// spec: PY-SET-OPS-1
const program =
    \\func leaf(x: int) -> int:
    \\    return bit_and(x, 7)
    \\func borrowed(xs: int[]) -> int[]:
    \\    mut ys = copy(xs)
    \\    ys[0] = 4
    \\    return ys
    \\func consuming(mut xs: int[]) -> int:
    \\    xs[0] = 5
    \\    return xs[0]
    \\func fresh(n: int) -> int:
    \\    mut xs: int[] = []
    \\    append(mut xs, n)
    \\    return xs[0] + leaf(n)
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2]
    \\    mut snapshots = [copy(xs), copy(xs)]
    \\    print(out, snapshots)
    \\    mut ys = borrowed(xs)
    \\    print(out, ys, consuming(mut xs), fresh(3))
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
    try std.testing.expectEqual(result.own.drops, report.totals.ownership.drops);
    try std.testing.expectEqual(result.own.promoted, report.totals.ownership.stack_lists);
    return report;
}

fn named(report: cost.Report, name: []const u8) cost.Counts {
    for (report.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function.counts;
        // A program checked as a project names its functions by module (`main::remove`).
        if (function.name.len > name.len + 2 and std.mem.endsWith(u8, function.name, name)) {
            const at = function.name.len - name.len;
            if (std.mem.eql(u8, function.name[at - 2 .. at], "::")) return function.counts;
        }
    }
    unreachable;
}

// spec: FRONTEND-COST-1
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
    for ([_]cost.Allocation{ .never, .may, .may, .unresolved }, 0..) |expected, index| {
        try std.testing.expectEqual(expected, cost.allocation(module, function, .{ .op = .call, .ty = .void, .a = @fromBackingInt(@intCast(index)) }));
    }
}

const reduction =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37 + 5) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += ((values[j] + 3) * 17 + 23) // 7 % 1009
    \\    print(out, total)
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
        \\    mut values: int[] = []
        \\    for j in range(n):
        \\        append(mut values, (j * 37) % 1009)
        \\    mut total = 0
        \\    for j in range(n):
        \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
        \\    print(out, total)
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
        \\    mut values: int[] = []
        \\    for j in range(n):
        \\        append(mut values, j * 3)
        \\    mut total = 0
        \\    for j in range(n):
        \\        total += search(values, j)
        \\    print(out, total)
        \\    return 0
    , .trusted);
    try std.testing.expectEqual(@as(u32, 0), called.totals.loops.versioned);
    // The same sum with the search written inline, an inner loop: no clone either.
    const nested = try measured(a,
        \\func main(args: str[], out: Stream) -> int:
        \\    mut n = len(args) + 100
        \\    mut values: int[] = []
        \\    for j in range(n):
        \\        append(mut values, j * 3)
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
        \\    print(out, total)
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
        \\    mut values: int[] = []
        \\    for j in range(n):
        \\        append(mut values, (j * 37) % 1009)
        \\    mut total = 0
        \\    for j in range(n):
        \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
        \\    print(out, total)
        \\    return 0
    , .trusted);
    try std.testing.expect(guarded.totals.loops.versioned > 0);
    const unswitched = try measured(a,
        \\func origin(mut xs: int[], x: int, kind: int) -> int:
        \\    append(mut xs, 2)
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
        \\    print(out, first(False))
        \\    return 0
    , null);
    try std.testing.expect(named(debug, "deep").allocation.sites > 0);
    try std.testing.expectEqual(@as(u32, 0), named(debug, "first").allocation.sites);
    try std.testing.expectEqual(@as(u32, 0), named(debug, "second").allocation.sites);
}

// The removed instructions cannot be counted after the pass. Preserve its actual
// event in the same per-function result that a build supplies to the cost report.
// A unique dictionary still allocates its tombstone bitmap on the first deletion.
fn deletionCount(a: std.mem.Allocator) !void {
    const report = try measured(a,
        \\import dicts
        \\
        \\func remove(mut d: dict[int, int]) -> int:
        \\    _ = dicts.pop(mut d, 1)
        \\    return len(d)
        \\func main(out: Stream) -> int:
        \\    mut d = {1: 2}
        \\    print(out, remove(mut d))
        \\    return 0
    , null);
    // Owned mutation has no copy branch; the dictionary's deletion scratch remains.
    try std.testing.expectEqual(@as(u32, 1), named(report, "remove").allocation.sites);
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
test "Core allocation contracts check unused scalar library bodies" {
    const language = @import("selka");
    const contracts = @import("allocation_contract.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pure = try language.Compilation.init(a, "library.selka", "@noalloc\nfunc scalar(value: int) -> int:\n    return value + 1\n");
    const pure_program = try pure.checkLibraryProgram();
    try std.testing.expect(pure.program == null);
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, pure_program, pure.src));
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
        \\@noalloc
        \\func bounded(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
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
    var bounded = try language.Compilation.init(a, "callback.selka", "@noalloc\nfunc apply(f: func(int) -> int, x: int) -> int:\n    return f(x)\n");
    const bounded_program = try bounded.checkLibraryProgram();
    const failure = (try contracts.checkProgram(a, bounded_program, bounded.src)).?;
    try std.testing.expect(failure.unresolved);
    try std.testing.expectEqualStrings("apply", failure.function);
    var ordinary = try language.Compilation.init(a, "callback.selka", "func apply(f: func(int) -> int, x: int) -> int:\n    return f(x)\n");
    const ordinary_program = try ordinary.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, ordinary_program, ordinary.src));
    var generic = try language.Compilation.init(a, "generic.selka", "@noalloc\nfunc identity[T: integer](value: T) -> T:\n    return value\n@noalloc\nfunc scalar() -> int:\n    return identity(3)\n");
    var legacy = try language.Compilation.init(a, "legacy.selka", "func fixed(mut values: int[]) -> Unit:\n    values[0] = 42\nfunc apply(f: func(int) -> int, x: int) -> int:\n    return f(x)\n");
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
    // `bytes.parse_int(raw)` needs `import bytes` (W13-S5), so this library is checked as an embedded project.
    const parsed = try support.libraryProject(a, "import bytes\n\n@noalloc\nfunc parse(raw: bytes) -> int?:\n    return bytes.parse_int(raw)\n");
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, parsed.program, parsed.src));
    var compare = try language.Compilation.init(a, "compare.selka",
        \\@noalloc
        \\func choose(a: str, b: str) -> bool:
        \\    return min(a, b) == a
        \\
    );
    const compare_program = try compare.checkLibraryProgram();
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, compare_program, compare.src));
    // migrate-embedded: skip preserved original effect retirement witness
    var foreign = try language.Compilation.init(a, "foreign.selka", "extern func myl_core_parse_int_range(host: Host) -> int effects(host)\nfunc bounded(host: Host) -> int noalloc:\n    return myl_core_parse_int_range(host)\n");
    try std.testing.expectError(error.SourceError, foreign.checkLibraryProgram());
    try std.testing.expectEqualStrings("E_EFFECTS_REMOVED", foreign.diagnostics.items[0].code);
    var modern_foreign = try language.Compilation.init(a, "foreign.selka",
        \\extern func myl_core_parse_int_range(host: Host) -> int
        \\@noalloc
        \\func bounded(host: Host) -> int:
        \\    return myl_core_parse_int_range(host)
        \\
    );
    try std.testing.expectError(error.SourceError, modern_foreign.checkLibraryProgram());
    try std.testing.expectEqualStrings("E_EXTERN_SYMBOL", modern_foreign.diagnostics.items[0].code);
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
    const scalar_source = "import bytes\n\n@noalloc\nfunc measure(raw: bytes) -> int:\n    match bytes.scalar_count(raw):\n" ++
        "        case Ok(width):\n            return width\n        case Err(_):\n            return 0\nfunc main() -> int:\n    return 0\n";
    // `bytes.scalar_count(raw)` needs `import bytes` (W13-S5), so the program is an embedded project.
    const parsed = try support.checkSource(a, scalar_source);
    try std.testing.expect(parsed.passed);
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.checkProgram(a, parsed.program.?, parsed.src.?));
    var refusal: build.Refusal = .{};
    // Build the bounded root: main does not call this unused body.
    var owned = try build.buildRootsSource(a, parsed.program.?, &.{try entryFunction(parsed.program.?, "measure")}, parsed.src, &refusal);
    const bounded_outcome = try passes.debug(a, &owned);
    const bounded_report = try cost.measure(a, &owned, &bounded_outcome, "measure");
    try std.testing.expectEqual(@as(u32, 0), bounded_report.totals.allocation.sites);
    var restricted = try language.Compilation.init(a, "cap.selka",
        \\@noalloc
        \\func bounded(fs: Filesystem) -> int:
        \\    with fs.read_only() as reader:
        \\        _ = reader
        \\    return 0
        \\
    );
    const restricted_program = try restricted.checkLibraryProgram();
    const failure = (try contracts.checkProgram(a, restricted_program, restricted.src)).?;
    try std.testing.expectEqualStrings("bounded", failure.function);
    try std.testing.expect(failure.unsupported == null);
}

/// The id of the entry module's function `name`, which an embedded project names `main::name`.
fn entryFunction(checked: @import("selka").typed.Program, name: []const u8) !@import("selka").typed.FunctionId {
    for (checked.functions, 0..) |function, index| {
        const qualified = std.mem.startsWith(u8, function.name, "main::") and std.mem.eql(u8, function.name["main::".len..], name);
        if (qualified or std.mem.eql(u8, function.name, name)) return @fromBackingInt(@intCast(index));
    }
    return error.TestUnexpectedResult;
}

fn expectKind(module: *const ir.Module, function: *const ir.Function, op: ir.Op, expected: cost.SiteKind) !void {
    try std.testing.expectEqual(expected, cost.siteKind(module, function, .{ .op = op, .ty = .void }, .may));
}

fn expectKinds(module: *const ir.Module, function: *const ir.Function, ops: []const ir.Op, expected: cost.SiteKind) !void {
    for (ops) |op| try expectKind(module, function, op, expected);
}

// spec: FRONTEND-COST-1
test "cost sites name every allocating class one of the five kinds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.functions.appendSlice(a, &.{
        .{ .name = "myl_core_owned_octets_copy", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } },
        .{ .name = "myl_core_str_from_i64", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } },
        .{ .name = "myl_core_owned_sort_keyed", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } },
        .{ .name = "myl_core_mystery_helper", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } },
    });
    const function: ir.Function = .{ .name = "subject", .signature = .{ .params = &.{}, .ret = .void } };
    try expectKinds(&module, &function, &.{ .list_copy, .dict_copy, .buffer_copy, .str_from_view, .str_slice }, .copy);
    try expectKinds(&module, &function, &.{ .list_new, .dict_new, .buffer_new, .box_make }, .construction);
    try expectKind(&module, &function, .str_char, .conversion);
    try expectKinds(&module, &function, &.{ .list_push, .dict_insert, .dict_remove, .list_sort, .dict_find, .buffer_push, .buffer_append, .str_append, .str_append_char }, .growth);
    const copy_call: ir.Inst = .{ .op = .call, .ty = .void, .a = @fromBackingInt(0) };
    try std.testing.expectEqual(cost.SiteKind.copy, cost.siteKind(&module, &function, copy_call, .may));
    const convert_call: ir.Inst = .{ .op = .call, .ty = .void, .a = @fromBackingInt(1) };
    try std.testing.expectEqual(cost.SiteKind.conversion, cost.siteKind(&module, &function, convert_call, .may));
    const sort_call: ir.Inst = .{ .op = .call, .ty = .void, .a = @fromBackingInt(2) };
    // A keyed sort copies its source and keys before it sorts (CX2: a named new value), so it is a copy site.
    try std.testing.expectEqual(cost.SiteKind.copy, cost.siteKind(&module, &function, sort_call, .may));
    const unknown_call: ir.Inst = .{ .op = .call, .ty = .void, .a = @fromBackingInt(3) };
    try std.testing.expectEqual(cost.SiteKind.construction, cost.siteKind(&module, &function, unknown_call, .may));
    // W4: a listed copy site is a copy row whatever its callee's allocation class, so `cost --sites` names every site
    // the hidden-copy check reads.
    try std.testing.expectEqual(cost.SiteKind.copy, cost.siteKind(&module, &function, copy_call, .unresolved));
    try std.testing.expectEqual(cost.SiteKind.@"unresolved call", cost.siteKind(&module, &function, .{ .op = .call_indirect, .ty = .void, .a = @fromBackingInt(0) }, .unresolved));
}

const inlined_sites =
    \\func snapshot(xs: int[]) -> int[]:
    \\    return copy(xs)
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2]
    \\    mut total = 0
    \\    for i in range(3):
    \\        mut ys = snapshot(xs)
    \\        total += len(ys)
    \\    print(out, total)
    \\    return 0
;

fn compiledSites(a: std.mem.Allocator, source: []const u8, rows: *[]const cost.Site, totals: *cost.Counts) !void {
    var unit = try @import("selka").Compilation.init(a, "sites.selka", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    var module = try build.buildModule(a, unit.program.?, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const report = try cost.measure(a, &module, &result, null);
    totals.* = report.totals;
    rows.* = try cost.sites(a, &module, &result, @import("pipeline.zig").locator(&unit.src), "sites.selka", unit.src.bytes);
}

// spec-case: FRONTEND-COST-1
test "cost sites keep row fields, physical order and an inlined callee's origin and loop depth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rows: []const cost.Site = &.{};
    var totals: cost.Counts = .{};
    try compiledSites(a, inlined_sites, &rows, &totals);
    // The site rows are exactly the instructions the unchanged allocation count reports.
    try std.testing.expectEqual(totals.allocation.sites, @as(u32, @intCast(rows.len)));
    try std.testing.expectEqual(@as(usize, 5), rows.len);
    // Rows are in emitted-function order: main's own body first, then snapshot's body.
    try std.testing.expectEqualStrings("main", rows[0].function);
    try std.testing.expectEqualStrings("main", rows[2].function);
    try std.testing.expectEqualStrings("snapshot", rows[3].function);
    try std.testing.expectEqualStrings("sites.selka", rows[3].path);
    try std.testing.expectEqual(@as(u32, 2), rows[3].line);
    try std.testing.expectEqual(@as(u32, 12), rows[3].column);
    try std.testing.expectEqual(cost.SiteKind.copy, rows[3].kind);
    // The copy is the one `copy(xs)` wrote, so the row is written and nothing is hidden.
    try std.testing.expectEqual(@as(?bool, true), rows[3].written());
    try std.testing.expectEqual(@import("copy_sites.zig").Label.written, rows[3].reading.?.label);
    try std.testing.expectEqual(@as(?bool, null), rows[0].written());
    // The clone sits inside main's loop; snapshot's own body is outside every loop.
    try std.testing.expectEqual(@as(u32, 1), rows[3].loop_depth);
    try std.testing.expectEqual(@as(u32, 0), rows[4].loop_depth);
    try std.testing.expectEqualStrings(cost.hint(.copy), cost.hint(rows[3].kind));
    // FUNCTION selection filters sites by the row's source function.
    const filtered = try cost.selectSites(a, rows, "snapshot");
    try std.testing.expectEqual(@as(usize, 2), filtered.len);
    try std.testing.expectEqual(@as(u32, 1), filtered[0].loop_depth);
    try std.testing.expectEqual(@as(u32, 0), filtered[1].loop_depth);
}

const nested_sites =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut total = 0
    \\    for i in range(3):
    \\        for j in range(2):
    \\            print(out, str(i + j))
    \\        total += i
    \\    print(out, total, len(args))
    \\    return 0
;

// spec-case: FRONTEND-COST-1
test "cost sites report a nested loop's depth and the unresolved call kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rows: []const cost.Site = &.{};
    var totals: cost.Counts = .{};
    try compiledSites(a, nested_sites, &rows, &totals);
    try std.testing.expectEqual(totals.allocation.sites, @as(u32, @intCast(rows.len)));
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqualStrings("main", rows[0].function);
    try std.testing.expectEqual(@as(u32, 5), rows[0].line);
    try std.testing.expectEqual(cost.SiteKind.@"unresolved call", rows[0].kind);
    try std.testing.expectEqual(@as(u32, 2), rows[0].loop_depth);
    const json = try cost.renderSites(a, .{ .functions = &.{}, .totals = totals }, rows, true);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"unresolved call\"") != null);
}

// spec-case: FRONTEND-COST-1
test "cost sites JSON is one cost-sites-v1 document and empty without sites" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_]cost.Site{.{
        .function = "work",
        .path = "prog.selka",
        .line = 4,
        .column = 5,
        .kind = .growth,
        .loop_depth = 1,
    }};
    const report: cost.Report = .{ .functions = &.{}, .totals = .{} };
    const json = try cost.renderSites(a, report, &rows, true);
    const parsed = try std.json.parseFromSlice(cost.SiteReport, a, json, .{ .ignore_unknown_fields = true });
    try std.testing.expectEqualStrings("cost-sites-v1", parsed.value.version);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.sites.len);
    try std.testing.expectEqualDeep(rows[0], parsed.value.sites[0]);
    try std.testing.expect(std.mem.startsWith(u8, json, "{\"version\":\"cost-sites-v1\",\"functions\":[],\"totals\":{"));
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hidden_copies\":0,\"implicit_copies\":0}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sites\":[{\"function\":\"work\",\"path\":\"prog.selka\",\"line\":4,\"column\":5,\"kind\":\"growth\",\"loop_depth\":1,\"hint\":\"") != null);
    const empty = try cost.renderSites(a, report, &.{}, true);
    try std.testing.expect(std.mem.indexOf(u8, empty, "\"sites\":[]") != null);
}

// spec-case: FRONTEND-COST-1
test "cost sites are empty for an allocation-free program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rows: []const cost.Site = &.{};
    var totals: cost.Counts = .{};
    try compiledSites(a, "func main() -> int:\n    return 0\n", &rows, &totals);
    try std.testing.expectEqual(@as(u32, 0), totals.allocation.sites);
    try std.testing.expectEqual(@as(usize, 0), rows.len);
    const text = try cost.renderSites(a, .{ .functions = &.{}, .totals = totals }, rows, false);
    try std.testing.expect(std.mem.endsWith(u8, text, "cost-sites-v1 (static allocation and copy sites after Core passes)\nhidden copies: 0\n"));
}
