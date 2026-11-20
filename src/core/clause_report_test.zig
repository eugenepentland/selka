//! The clause report (proof steps S1, `clause_report.zig`): every contract clause is proved, refuted or kept after
//! Core's passes, with its copies counted in its own body and inlined; a clause the report calls proved is one whose
//! trap block the fact certificate states dead, which the validator and `--verify-facts` both check.
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const report = @import("clause_report.zig");
const flags = @import("flags.zig");
const text = @import("fact_text.zig");
const export_ = @import("fact_export.zig");
const validate = @import("validate_facts.zig");
const form = @import("fact_function.zig");
const command = @import("cost_command.zig");

/// The brief's probe (exit P3): `clamp`'s clause holds on every return, `wrong`'s fails on the one its caller reaches.
const probe =
    \\@ensures(result >= 0 and result < 3)
    \\func clamp(value: int) -> int:
    \\    if value < 0:
    \\        return 0
    \\    if value > 2:
    \\        return 2
    \\    return value
    \\
    \\@ensures(result >= 1)
    \\func wrong(value: int) -> int:
    \\    if value > 5:
    \\        return 0
    \\    return 0
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, clamp(7) + wrong(3))
    \\    return 0
    \\
;

/// A compiled program, its pass result and its clause report.
const Compiled = struct { module: ir.Module, result: passes.Result, report: report.Report };

fn compiled(a: std.mem.Allocator, source: []const u8, mode: ?passes.Mode) !Compiled {
    var unit = try @import("selka").Compilation.init(a, "probe.selka", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    var module = try build.buildModule(a, unit.program.?, &refusal);
    const result = if (mode) |chosen| try support.runPasses(a, &module, chosen) else try passes.debug(a, &module);
    const where: report.Where = .{ .locator = @import("pipeline.zig").locator(&unit.src), .fallback_path = "probe.selka", .text = unit.src.bytes };
    return .{ .module = module, .result = result, .report = try report.collect(a, &module, &result, where) };
}

fn row(rows: []const report.Clause, subject: []const u8, kind: report.Kind) !report.Clause {
    for (rows) |clause| if (clause.kind == kind and std.mem.eql(u8, clause.name.subject, subject)) return clause;
    return error.TestUnexpectedResult;
}

test "the probe's clamp clause is proved on all three returns and wrong's clause is refuted where main reaches it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try compiled(arena.allocator(), probe, .trusted);
    try std.testing.expectEqual(@as(usize, 2), program.report.clauses.len);
    const clamp = try row(program.report.clauses, "clamp", .ensures);
    try std.testing.expectEqual(report.Status.proved, clamp.status);
    try std.testing.expectEqual(report.Copies{ .proved = 3 }, clamp.copies.own);
    try std.testing.expectEqualStrings("result >= 0 and result < 3", clamp.name.text);
    try std.testing.expectEqual(@as(u32, 1), clamp.at.line);
    try std.testing.expectEqual(@as(u32, 10), clamp.at.column);
    const wrong = try row(program.report.clauses, "wrong", .ensures);
    try std.testing.expectEqual(report.Status.refuted, wrong.status);
    // The return under `value > 5` is dead for the one call, so its copy is proved; the other is refuted.
    try std.testing.expectEqual(report.Copies{ .proved = 1, .refuted = 1 }, wrong.copies.own);
    try std.testing.expectEqualStrings("wrong", wrong.refuted.?.function);
    try std.testing.expect(wrong.refuted.?.call == null);
    try std.testing.expectEqual(report.Copies{ .proved = 1, .refuted = 1 }, program.report.totals.clauses);
    try std.testing.expectEqual(report.Copies{ .proved = 4, .refuted = 1 }, program.report.totals.own);
}

test "a build without facts keeps every clause copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const debug = try compiled(arena.allocator(), probe, null);
    try std.testing.expectEqual(report.Copies{ .kept = 2 }, debug.report.totals.clauses);
    try std.testing.expectEqual(report.Copies{ .kept = 5 }, debug.report.totals.own);
    const off = try compiled(arena.allocator(), probe, .off);
    try std.testing.expectEqual(report.Copies{ .kept = 5 }, off.report.totals.own);
    // Verify mode states the same facts without folding, so it reports the same statuses.
    const verified = try compiled(arena.allocator(), probe, .verify);
    try std.testing.expectEqual(report.Copies{ .proved = 4, .refuted = 1 }, verified.report.totals.own);
}

/// Two compound clauses on one value the facts bound to `0..2`: an `or` whose last disjunct is decided false but whose
/// first is not, and an `and` whose first conjunct is decided true and whose last is decided false.
const chains =
    \\@ensures(result < 2 or result > 5)
    \\func spread(value: int) -> int:
    \\    return value
    \\
    \\@ensures(result >= 0 and result > 5)
    \\func narrow(value: int) -> int:
    \\    return value
    \\
    \\func main(out: Stream) -> int:
    \\    mut total = 0
    \\    for i in range(3):
    \\        total += spread(i) + narrow(i)
    \\    print(out, total)
    \\    return 0
    \\
;

test "an or chain whose last disjunct folds false is kept, and an and chain whose last conjunct folds false is refuted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try compiled(arena.allocator(), chains, .trusted);
    // The branch on `result > 5` goes only to the trap, but it is reached only when `result < 2` fails at run time.
    const spread = try row(program.report.clauses, "spread", .ensures);
    try std.testing.expectEqual(report.Status.kept, spread.status);
    try std.testing.expectEqual(report.Copies{ .kept = 1 }, spread.copies.own);
    // Every path from the clause's first branch reaches the trap: `result >= 0` holds, so `result > 5` is always tested.
    const narrow = try row(program.report.clauses, "narrow", .ensures);
    try std.testing.expectEqual(report.Status.refuted, narrow.status);
    try std.testing.expectEqual(report.Copies{ .refuted = 1 }, narrow.copies.own);
}

const inlined =
    \\@requires(len(xs) > 0)
    \\@ensures(result >= 0)
    \\func bump(mut xs: int[]) -> int:
    \\    xs[0] = xs[0] + 1
    \\    return xs[0]
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2]
    \\    mut empty: int[] = []
    \\    print(out, bump(mut xs))
    \\    print(out, bump(mut empty))
    \\    return 0
    \\
;

test "inlined copies are counted apart from the function's own body and a refuted one names its call site" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try compiled(arena.allocator(), inlined, .trusted);
    try std.testing.expect(program.result.counts.inlined >= 2);
    const requires = try row(program.report.clauses, "bump", .requires);
    try std.testing.expectEqual(report.Status.refuted, requires.status);
    try std.testing.expectEqual(@as(u32, 1), requires.copies.inlined.proved);
    try std.testing.expectEqual(@as(u32, 1), requires.copies.inlined.refuted);
    try std.testing.expectEqualStrings("main", requires.refuted.?.function);
    // The refuted copy was cloned at the second call, `bump(mut empty)` on line 11.
    try std.testing.expectEqual(@as(u32, 11), requires.refuted.?.call.?.line);
    const ensures = try row(program.report.clauses, "bump", .ensures);
    try std.testing.expectEqual(@as(u32, 2), ensures.copies.inlined.proved + ensures.copies.inlined.kept);
    try std.testing.expectEqual(@as(u32, 0), ensures.copies.inlined.refuted);
    // Both calls were inlined, so nothing calls bump's own body: its copies never run and decide no status.
    try std.testing.expectEqual(report.Copies{ .unused = 1 }, requires.copies.own);
    try std.testing.expectEqual(report.Copies{ .unused = 1 }, ensures.copies.own);
    try std.testing.expectEqual(report.Status.kept, (report.Copies{ .unused = 3 }).verdict());
}

const invariants =
    \\@invariant(self.lo <= self.hi, "a span never runs backwards")
    \\@invariant(self.lo >= 0)
    \\record Span:
    \\    lo: int
    \\    hi: int
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const fixed = Span(lo=1, hi=2)
    \\    const open = Span(lo=len(args), hi=3)
    \\    assert fixed.lo + open.hi > 0
    \\    assert len(args) < 3, "few arguments"
    \\    print(out, fixed.lo, open.hi)
    \\    return 0
    \\
;

test "an invariant is one clause with a copy per construction, placed where the source writes it, and asserts are their own kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try compiled(arena.allocator(), invariants, .trusted);
    try std.testing.expectEqual(@as(usize, 2), program.report.clauses.len);
    const first = program.report.clauses[0];
    try std.testing.expectEqual(report.Kind.invariant, first.kind);
    try std.testing.expectEqualStrings("Span", first.name.subject);
    try std.testing.expectEqualStrings("self.lo <= self.hi", first.name.text);
    try std.testing.expectEqual(@as(u32, 1), first.name.ordinal);
    try std.testing.expectEqual(@as(u32, 1), first.at.line);
    try std.testing.expectEqual(@as(u32, 12), first.at.column);
    try std.testing.expectEqual(@as(u32, 2), first.copies.own.proved + first.copies.own.kept);
    const second = program.report.clauses[1];
    try std.testing.expectEqual(@as(u32, 2), second.name.ordinal);
    try std.testing.expectEqual(@as(u32, 2), second.at.line);
    // Two `assert` statements; the compiler's own checks are not counted as asserts.
    try std.testing.expectEqual(@as(usize, 2), program.report.asserts.len);
    try std.testing.expectEqualStrings("few arguments", program.report.asserts[1].name.text);
    const asserts = program.report.totals.asserts;
    try std.testing.expectEqual(@as(u32, 2), asserts.proved + asserts.refuted + asserts.kept);
}

test "the source search finds one invariant by its folded condition and record, and refuses an ambiguous one" {
    const source =
        \\@invariant(self.a  <=
        \\    self.b, "note")
        \\record Pair:
        \\    a: int
        \\@invariant(self.a <= self.b)
        \\record Other:
        \\    a: int
        \\@invariant(self.a <= self.b)
        \\record Other:
        \\    a: int
    ;
    try std.testing.expectEqual(@as(?u32, 11), report.invariantOffset(source, .{ .subject = "Pair", .text = "self.a <= self.b" }));
    try std.testing.expectEqual(@as(?u32, null), report.invariantOffset(source, .{ .subject = "Other", .text = "self.a <= self.b" }));
    try std.testing.expectEqual(@as(?u32, null), report.invariantOffset(source, .{ .subject = "Missing", .text = "self.a <= self.b" }));
}

test "the clause section renders text and one cost-clauses-v1 document, and stats print nothing without clauses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try compiled(a, probe, .trusted);
    const costs: @import("cost.zig").Report = .{ .functions = &.{}, .totals = .{} };
    const rendered = try report.render(a, costs, program.report, .{});
    // The header says what proved means: the check cannot fail (its branch may remain in Core's output, D-S1-13).
    try std.testing.expect(std.mem.indexOf(u8, rendered, "proved: cannot fail, refuted: fails whenever reached, kept: checked at run time)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "probe.selka:1:10  ensures 1  clamp  `result >= 0 and result < 3`  proved  own 3/0/0  inlined 0/0/0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "probe.selka:9:10  ensures 1  wrong  `result >= 1`  refuted  own 1/1/0  inlined 0/0/0  fails whenever this program reaches it (in wrong)\n") != null);
    const json = try report.render(a, costs, program.report, .{ .json = true });
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    try std.testing.expectEqualStrings("cost-clauses-v1", parsed.value.object.get("version").?.string);
    const rows = parsed.value.object.get("clauses").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("refuted", rows[1].object.get("status").?.string);
    try std.testing.expectEqualStrings("wrong", rows[1].object.get("refuted_at").?.object.get("function").?.string);
    try std.testing.expect(rows[0].object.get("refuted_at") == null);
    var stats: std.ArrayList(u8) = .empty;
    try report.stats(a, &stats, program.report);
    try std.testing.expect(std.mem.indexOf(u8, stats.items, "selka-core: clauses 2: 1 proved, 1 refuted, 0 kept;") != null);
    try std.testing.expect(std.mem.indexOf(u8, stats.items, "selka-core: refuted: probe.selka:9:10 wrong ensures `result >= 1`") != null);
    const plain = try compiled(a, "func main() -> int:\n    return 0\n", .trusted);
    var none: std.ArrayList(u8) = .empty;
    try report.stats(a, &none, plain.report);
    try std.testing.expectEqualStrings("", none.items);
    // A function filter selects clauses by their subject and recounts the totals.
    const selected = try report.select(a, program.report, "clamp");
    try std.testing.expectEqual(@as(usize, 1), selected.clauses.len);
    try std.testing.expectEqual(report.Copies{ .proved = 1 }, selected.totals.clauses);
}

test "cost accepts --clauses with --asserts and refuses --asserts alone and --clauses beside --sites or counters" {
    try std.testing.expect(command.parse(&.{ "p.selka", "--clauses" }) != null);
    try std.testing.expect(command.parse(&.{ "p.selka", "--clauses", "--asserts", "--json" }) != null);
    try std.testing.expect(command.parse(&.{ "p.selka", "--asserts" }) == null);
    try std.testing.expect(command.parse(&.{ "p.selka", "--clauses", "--sites" }) == null);
    try std.testing.expect(command.parse(&.{ "p.selka", "--clauses", "--counters", "c.json" }) == null);
    try std.testing.expect(command.parse(&.{ "p.selka", "--clauses", "--clauses" }) == null);
}

const kept =
    \\@requires(x > 0)
    \\func half(x: int) -> int:
    \\    return x // 2
    \\
    \\func main(out: Stream) -> int:
    \\    mut total = 0
    \\    for i in range(3):
    \\        total += half(i)
    \\    print(out, total)
    \\    return 0
    \\
;

/// The block holding the one clause trap of the function named `name`.
fn trapBlock(module: *const ir.Module, name: []const u8) !struct { function: usize, block: usize } {
    for (module.functions.items, 0..) |function, index| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        for (function.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            if (inst.op == .@"unreachable" and inst.data & flags.assertion_trap != 0) return .{ .function = index, .block = b };
        };
    }
    return error.TestUnexpectedResult;
}

fn allAccepted(verdicts: []const validate.Verdict) bool {
    for (verdicts) |verdict| if (verdict != .accepted) return false;
    return true;
}

fn certificate(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result) !form.Module {
    const described = try export_.describe(a, a, module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try text.write(a, &out, described);
    var problem: text.Problem = .{};
    return text.parse(a, out.items, &problem);
}

test "a kept clause stated proved is refused by the fact validator, and a proved clause's certificate is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, kept, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const at = try trapBlock(&module, "half");
    try std.testing.expectEqual(report.Status.kept, report.copyStatus(&module.functions.items[at.function], result.known[at.function], at.block));
    const honest = try certificate(a, &module, &result);
    try std.testing.expect(allAccepted(try validate.validate(a, std.testing.allocator, honest, null)));
    // The fault: the clause's trap block stated dead, which is exactly what `proved` reads.
    var function = honest.functions[at.function];
    const blocks = try a.dupe(form.Block, function.blocks);
    try std.testing.expect(!blocks[at.block].dead);
    try std.testing.expect(blocks[at.block].term == .unreachable_path);
    blocks[at.block].dead = true;
    function.blocks = blocks;
    const functions = try a.dupe(form.Function, honest.functions);
    functions[at.function] = function;
    const judged = try validate.validate(a, std.testing.allocator, .{ .functions = functions }, null);
    try std.testing.expect(judged[at.function] == .rejected);
    // The probe's proved clause rests on dead trap blocks the validator accepts.
    var probe_module = try support.buildSource(a, probe, &refusal);
    const probe_result = try support.runPasses(a, &probe_module, .trusted);
    const proved = try certificate(a, &probe_module, &probe_result);
    try std.testing.expect(allAccepted(try validate.validate(a, std.testing.allocator, proved, null)));
    const clamp = try trapBlock(&probe_module, "clamp");
    try std.testing.expect(proved.functions[clamp.function].blocks[clamp.block].dead);
}

test "a clause wrongly folded to proved traps the fact assertion when --verify-facts code reaches it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, kept, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    const at = try trapBlock(&module, "half");
    const known = result.known[at.function].?;
    try std.testing.expect(known.reachable[at.block]);
    known.reachable[at.block] = false;
    // The report now reads the wrong fact as a proof...
    try std.testing.expectEqual(report.Status.proved, report.copyStatus(&module.functions.items[at.function], known, at.block));
    // ...and the verify build's assertion on the dead block catches it when the check runs.
    const ran = try support.runOwned(a, &module, .{ .verify = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "unreachable block") != null);
}
