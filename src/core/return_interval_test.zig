//! Proof steps S2, step 1: a function's return interval takes the branch edges that dominate each `ret`
//! (`facts.returnRange`), so a caller knows what an `@ensures` on an integer result says. The plan's exit P4 is the probe
//! below: with `xs` of length 3, `xs[clamp(i - 3)]` has its bounds check proved. The fault-injection tests show that the
//! fact validator's return rule (F6) refuses a return interval narrower than the branches give, so a wrong narrowing
//! cannot pass a Debug compiler's validation; `f1_facts_test.zig` shows a verify build trapping on one at run time.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const export_ = @import("fact_export.zig");
const form = @import("fact_function.zig");
const validate = @import("validate_facts.zig");
const mutants = @import("fact_mutants.zig");
const passes = @import("passes.zig");
const report = @import("clause_report.zig");

/// The plan's probe (exit P4), with a second callee whose bound comes from a kept clause's passing edges, and a third whose
/// `@requires` the call sites prove: the callee's body is analysed with the arguments of both calls joined.
const probe =
    \\@ensures(result >= 0 and result < 3)
    \\func clamp(value: int) -> int:
    \\    if value < 0:
    \\        return 0
    \\    if value > 2:
    \\        return 2
    \\    return value
    \\
    \\@ensures(result >= 0 and result < 3)
    \\func wrapped(value: int) -> int:
    \\    return value % 7 - 2
    \\
    \\@requires(index >= 0 and index < 3)
    \\func third(index: int) -> int:
    \\    const xs: int[] = [10, 20, 30]
    \\    return xs[index]
    \\
    \\func pick(i: int) -> int:
    \\    const xs: int[] = [10, 20, 30]
    \\    return xs[clamp(i - 3)] + xs[wrapped(i)]
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, pick(len(args)) + third(clamp(len(args))) + third(1))
    \\    return 0
    \\
;

/// A compiled program and its pass result.
const Compiled = struct { module: ir.Module, result: passes.Result };

fn compiled(a: std.mem.Allocator, source: []const u8, mode: passes.Mode) !Compiled {
    var refusal = @import("build.zig").Refusal{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, mode);
    return .{ .module = module, .result = result };
}

fn functionNamed(module: *const ir.Module, name: []const u8) !usize {
    for (module.functions.items, 0..) |function, index| if (std.mem.eql(u8, function.name, name)) return index;
    return error.TestUnexpectedResult;
}

/// The checks of `op` in function `name` by state: how many are still `exact` and how many `proven`.
fn checksOf(module: *const ir.Module, name: []const u8, op: ir.Op) !struct { exact: usize, proven: usize } {
    const function = module.functions.items[try functionNamed(module, name)];
    var exact: usize = 0;
    var proven: usize = 0;
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = function.inst(ref);
        if (inst.op != op) continue;
        if (inst.check == .exact) exact += 1;
        if (inst.check == .proven) proven += 1;
    };
    return .{ .exact = exact, .proven = proven };
}

fn certificate(a: std.mem.Allocator, program: *const Compiled) !form.Module {
    return export_.describe(a, a, &program.module, .{ .known = program.result.known, .fields = program.result.emission.fields });
}

/// How many functions of `module` the validator accepts, and how many intervals it accepted without a rule (design §8, A6).
fn judged(a: std.mem.Allocator, backing: std.mem.Allocator, module: form.Module) !struct { accepted: usize, assumed: u32 } {
    var accepted: usize = 0;
    var assumed: u32 = 0;
    for (try validate.validate(a, backing, module, null)) |verdict| switch (verdict) {
        .accepted => |stats| {
            accepted += 1;
            assumed += stats.assumed;
        },
        .rejected => {},
    };
    return .{ .accepted = accepted, .assumed = assumed };
}

/// The narrow-return mutants of `module` (each states one function's return interval one step narrower than some `ret`'s
/// view) and how many of them the validator refuses with F6 in the function edited.
fn narrowReturns(a: std.mem.Allocator, backing: std.mem.Allocator, module: form.Module) !struct { made: usize, refused: usize } {
    const accepted = try a.alloc(bool, module.functions.len);
    @memset(accepted, true);
    var made: mutants.Mutants = .empty;
    try mutants.mutate(a, backing, module, .{ .class = .narrow_return, .accepted = accepted, .limit = 16 }, &made);
    var refused: usize = 0;
    for (made.items) |mutant| switch ((try validate.validate(a, backing, mutant.module, null))[mutant.function]) {
        .accepted => {},
        .rejected => |failure| refused += @intFromBool(failure.check == .f6),
    };
    return .{ .made = made.items.len, .refused = refused };
}

/// The stated intervals of every `call` in `function`.
fn callRanges(a: std.mem.Allocator, function: form.Function) ![]const ?form.Interval {
    var out: std.ArrayList(?form.Interval) = .empty;
    for (function.blocks) |block| for (block.insts) |inst| {
        if (inst.op == .call) try out.append(a, inst.range);
    };
    return out.items;
}

const nowhere: u8 = 0;

fn locateNothing(_: *const anyopaque, _: u32) @import("source_location.zig").Location {
    return .{ .line = 0, .column = 0 };
}

const where: report.Where = .{ .locator = .{ .context = &nowhere, .locate = locateNothing }, .fallback_path = "probe.selka" };

fn rowOf(clauses: report.Report, subject: []const u8, kind: report.Kind) !report.Clause {
    for (clauses.clauses) |row| if (row.kind == kind and std.mem.eql(u8, row.name.subject, subject)) return row;
    return error.TestUnexpectedResult;
}

test "P4: a caller's bounds check is proved by the callee's ensures, whether its if branches or its kept clause bound the result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try compiled(a, probe, .trusted);
    // Both `xs[...]` of `pick` are proved: `clamp` returns [0, 2] by its `if`s, `wrapped` by its clause's passing edges.
    const pick = try checksOf(&program.module, "pick", .list_get);
    try std.testing.expectEqual(@as(usize, 0), pick.exact);
    try std.testing.expectEqual(@as(usize, 2), pick.proven);
    const described = try certificate(a, &program);
    const clamp = described.functions[try functionNamed(&program.module, "clamp")];
    try std.testing.expectEqual(form.Interval{ .lo = 0, .hi = 2 }, clamp.boundary.returns.?);
    const wrapped = described.functions[try functionNamed(&program.module, "wrapped")];
    try std.testing.expectEqual(form.Interval{ .lo = 0, .hi = 2 }, wrapped.boundary.returns.?);
    // The clause is proved in `clamp` and kept in `wrapped`, where `value % 7 - 2` lies in [-2, 4].
    const clauses = try report.collect(a, &program.module, &program.result, where);
    try std.testing.expectEqual(report.Status.proved, (try rowOf(clauses, "clamp", .ensures)).status);
    try std.testing.expectEqual(report.Status.kept, (try rowOf(clauses, "wrapped", .ensures)).status);
    // Without the facts the checks stay.
    const off = try compiled(a, probe, .off);
    try std.testing.expectEqual(@as(usize, 2), (try checksOf(&off.module, "pick", .list_get)).exact);
}

test "the requires of third is proved at both of its call sites, and the report counts them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try compiled(a, probe, .trusted);
    const clauses = try report.collect(a, &program.module, &program.result, where);
    const requires = try rowOf(clauses, "third", .requires);
    try std.testing.expectEqual(report.Status.proved, requires.status);
    // `third(clamp(len(args)))` passes [0, 2], known only from clamp's return interval, and `third(1)` passes 1.
    try std.testing.expectEqual(report.Sites{ .proved = 2 }, requires.sites);
    try std.testing.expectEqual(report.Sites{ .proved = 2 }, clauses.totals.call_sites);
    // No other kind counts call sites.
    try std.testing.expectEqual(report.Sites{}, (try rowOf(clauses, "clamp", .ensures)).sites);
}

test "the validator accepts the narrowed return intervals and refuses any narrower one at the callee's return (F6)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try compiled(a, probe, .trusted);
    const described = try certificate(a, &program);
    try std.testing.expectEqual(described.functions.len, (try judged(a, std.testing.allocator, described)).accepted);
    // A wrong narrowing of clamp's interval, [0, 1], as a fact pass that misread its branches would claim it.
    const index = try functionNamed(&program.module, "clamp");
    var functions = try a.dupe(form.Function, described.functions);
    functions[index].boundary.returns = .{ .lo = 0, .hi = 1 };
    const verdicts = try validate.validate(a, std.testing.allocator, .{ .functions = functions }, null);
    try std.testing.expectEqual(validate.Check.f6, verdicts[index].rejected.check);
    try std.testing.expect(std.mem.indexOf(u8, verdicts[index].rejected.detail, "where its return is stated [0, 1]") != null);
    // Every narrow-return mutant of the probe (one step narrower than some `ret`'s view) is refused, in its own function.
    const swept = try narrowReturns(a, std.testing.allocator, described);
    try std.testing.expect(swept.made >= 2);
    try std.testing.expectEqual(swept.made, swept.refused);
}

test "a caller's call interval is the callee's stated return interval, so the validator derives it rather than assuming it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try compiled(a, probe, .trusted);
    const described = try certificate(a, &program);
    const pick = described.functions[try functionNamed(&program.module, "pick")];
    const ranges = try callRanges(a, pick);
    try std.testing.expectEqual(@as(usize, 2), ranges.len);
    try std.testing.expectEqual(@as(?form.Interval, .{ .lo = 0, .hi = 2 }), ranges[0]);
    try std.testing.expectEqual(@as(?form.Interval, .{ .lo = 0, .hi = 2 }), ranges[1]);
    // Every interval of the program follows from a rule: none was accepted without one (design §8, A6).
    const verdicts = try judged(a, std.testing.allocator, described);
    try std.testing.expectEqual(described.functions.len, verdicts.accepted);
    try std.testing.expectEqual(@as(u32, 0), verdicts.assumed);
}

/// Lane C: a chained clause or `if` is one branch per link, so a kept `@ensures(0 <= result <= 2)` narrows its callers and
/// a chained `if` narrows its body; a chain used as a value keeps its value lowering.
const chains =
    \\@ensures(0 <= result <= 2)
    \\func wrapped(value: int) -> int:
    \\    return value % 7 - 2
    \\
    \\func pick(i: int) -> int:
    \\    const xs: int[] = [10, 20, 30]
    \\    return xs[wrapped(i)]
    \\
    \\func inside(xs: int[], i: int) -> int:
    \\    if 0 <= i < len(xs):
    \\        return xs[i]
    \\    return -1
    \\
    \\func flag(xs: int[], i: int) -> bool:
    \\    const ok = 0 <= i < len(xs)
    \\    return ok
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const ys: int[] = [1, 2, 3]
    \\    print(out, pick(len(args)), inside(ys, len(args) - 2), flag(ys, len(args)))
    \\    return 0
    \\
;

/// How many phis of `bool` function `name` has.
fn boolPhis(module: *const ir.Module, name: []const u8) !usize {
    const function = module.functions.items[try functionNamed(module, name)];
    var count: usize = 0;
    for (function.insts.items) |inst| count += @intFromBool(inst.op == .phi and inst.ty == .bool);
    return count;
}

test "a chained ensures narrows its callers and a chained if narrows its body, while a chain value keeps its phi" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try compiled(a, chains, .trusted);
    try std.testing.expectEqual(@as(usize, 0), (try checksOf(&program.module, "pick", .list_get)).exact);
    try std.testing.expectEqual(@as(usize, 0), (try checksOf(&program.module, "inside", .list_get)).exact);
    const described = try certificate(a, &program);
    const wrapped = described.functions[try functionNamed(&program.module, "wrapped")];
    try std.testing.expectEqual(form.Interval{ .lo = 0, .hi = 2 }, wrapped.boundary.returns.?);
    try std.testing.expectEqual(described.functions.len, (try judged(a, std.testing.allocator, described)).accepted);
    // The clause and the `if` leave no phi of their links; the chain stored in `ok` is still one value.
    const off = try compiled(a, chains, .off);
    try std.testing.expectEqual(@as(usize, 0), try boolPhis(&off.module, "wrapped"));
    try std.testing.expectEqual(@as(usize, 0), try boolPhis(&off.module, "inside"));
    try std.testing.expect(try boolPhis(&off.module, "flag") >= 1);
}
