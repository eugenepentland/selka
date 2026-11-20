//! FX7: a `match mut` on a payload binding of an enclosing `match mut` arm. The inner binding's place lies below two union
//! payloads (`o` case `boxed`, its field `inner`, case `rad`), and every use of it is projected again from the held
//! container: the read through `union_payload` and the write through `union_take`. The inner match tested the tag of an
//! earlier projection, which the IR verifier's union-tag rule (F-VL-10) cannot relate to the later ones, so a build counted
//! those reads (`--stats`: `union-tags: 2`) and the gate's `verify-ir-proof`, which refuses them, could hold no test of the
//! shape. The builder now tests the tag of a union below another payload where it reads or takes it (`caseGuard`), and these
//! tests check, with the rule refusing as the gate does, that every payload read of each shape is justified, before and after
//! the release passes, and that the programs run. FX7b adds three one-level shapes the same rule did not justify: a field
//! of a record written back in a loop, a place two fields deep and a field of a list element. The language-level tests are `tests/lang/match_mut_nested.selka`; the list
//! element is pinned here because its outer reads are of shape M, which the gate's corpus caps.
const std = @import("std");
const support = @import("test_support.zig");
const verify_ir = @import("verify_ir.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");

const unions =
    \\enum Sh:
    \\    empty
    \\    rad(value: int)
    \\
    \\
    \\enum Bag:
    \\    none
    \\    items(values: int[])
    \\
    \\
    \\enum Outer:
    \\    nothing
    \\    boxed(inner: Sh)
    \\
    \\
    \\enum OuterBag:
    \\    nothing
    \\    holding(bag: Bag)
    \\
    \\
    \\record Pot:
    \\    label: str
    \\    leaf: Sh
    \\
    \\
    \\record Shelf:
    \\    name: str
    \\    pot: Pot
    \\
    \\
;

/// One nested shape: its program (after `unions`) and what it prints.
const Shape = struct { source: []const u8, stdout: []const u8 };

const shapes = [_]Shape{
    // FX7b: one level, a field of a `mut` parameter written in a loop (the record is a `phi` at each read).
    .{ .source =
    \\func grow(mut p: Pot, by: int) -> int:
    \\    match mut p.leaf:
    \\        case rad(value=n):
    \\            for step in range(by):
    \\                n += step
    \\            return n
    \\        case empty:
    \\            return -1
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut one = Pot(label="one", leaf=Sh.rad(value=10))
    \\    print(out, grow(mut one, 4))
    \\    return 0
    \\
    , .stdout = "16\n" },
    // FX7b: a place two fields deep (`s.pot.leaf`), written in a `while` loop with `break`.
    .{ .source =
    \\func main(out: Stream) -> int:
    \\    mut s = Shelf(name="s", pot=Pot(label="p", leaf=Sh.rad(value=1)))
    \\    match mut s.pot.leaf:
    \\        case rad(value=n):
    \\            while True:
    \\                n = n * 2
    \\                if n > 20:
    \\                    break
    \\            print(out, n)
    \\        case empty:
    \\            return 1
    \\    return 0
    \\
    , .stdout = "32\n" },
    // FX7b: a field of a list element (`pots[1].leaf`), written in a loop.
    .{ .source =
    \\func main(out: Stream) -> int:
    \\    mut pots = [Pot(label="a", leaf=Sh.empty), Pot(label="b", leaf=Sh.rad(value=2))]
    \\    match mut pots[1].leaf:
    \\        case rad(value=n):
    \\            for i in range(3):
    \\                n += i
    \\            print(out, n)
    \\        case empty:
    \\            return 1
    \\    return 0
    \\
    , .stdout = "5\n" },
    // The two programs lane FX5 found: a scalar payload and an owned one, two levels down.
    .{ .source =
    \\func main(out: Stream) -> int:
    \\    mut o = Outer.boxed(inner=Sh.rad(value=1))
    \\    match mut o:
    \\        case boxed(inner=sh):
    \\            match mut sh:
    \\                case rad(value=v):
    \\                    v = v + 8
    \\                    print(out, v)
    \\                case empty:
    \\                    return 1
    \\        case nothing:
    \\            return 1
    \\    return 0
    \\
    , .stdout = "9\n" },
    .{ .source =
    \\func main(out: Stream) -> int:
    \\    mut o = OuterBag.holding(bag=Bag.items(values=[1]))
    \\    match mut o:
    \\        case holding(bag=b):
    \\            match mut b:
    \\                case items(values=v):
    \\                    append(mut v, 8)
    \\                    print(out, len(v))
    \\                case none:
    \\                    return 1
    \\        case nothing:
    \\            return 1
    \\    return 0
    \\
    , .stdout = "2\n" },
    // The outer union is a list element: its reads are of shape M, the inner ones are justified by the new test.
    .{ .source =
    \\func main(out: Stream) -> int:
    \\    mut xs = [Outer.nothing, Outer.boxed(inner=Sh.rad(value=4))]
    \\    match mut xs[1]:
    \\        case boxed(inner=sh):
    \\            match mut sh:
    \\                case rad(value=v):
    \\                    v = v * 10
    \\                    print(out, v)
    \\                case empty:
    \\                    return 1
    \\        case nothing:
    \\            return 1
    \\    return 0
    \\
    , .stdout = "40\n" },
    // The inner binding written in a loop through a `mut` parameter.
    .{ .source =
    \\func grow(mut o: Outer) -> int:
    \\    match mut o:
    \\        case boxed(inner=sh):
    \\            match mut sh:
    \\                case rad(value=v):
    \\                    for i in range(4):
    \\                        v = v + i
    \\                    return v
    \\                case empty:
    \\                    return -1
    \\        case nothing:
    \\            return -2
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut o = Outer.boxed(inner=Sh.rad(value=1))
    \\    print(out, grow(mut o))
    \\    return 0
    \\
    , .stdout = "7\n" },
};

/// The verifier's report on `module` with the union-tag rule refusing, as the gate's `selka verify-ir` does: empty when
/// every payload read is justified (or of shape M), else the reason.
fn unjustified(a: std.mem.Allocator, module: *const ir.Module, plans: []const []const @import("vector.zig").Plan) ![]const u8 {
    var report: std.ArrayList(u8) = .empty;
    verify_ir.checkPresent(a, module, .{ .plans = plans, .union_tags = .{ .mode = .refuse } }, &report) catch |err| switch (err) {
        error.InvalidIr => return if (report.items.len == 0) "refused" else report.items,
        else => return err,
    };
    return "";
}

/// "justified" when every shape's payload reads are justified as built, after the debug pipeline's passes and after the
/// release passes; else the shape, the stage and the verifier's reason.
fn everyReadJustified(a: std.mem.Allocator, chosen: []const Shape) ![]const u8 {
    for (chosen, 0..) |shape, index| {
        const source = try std.mem.concat(a, u8, &.{ unions, shape.source });
        var refusal: build.Refusal = .{};
        const built = try support.buildSource(a, source, &refusal);
        var debug = try support.buildSource(a, source, &refusal);
        const debugged = try passes.debug(a, &debug);
        var release = try support.buildSource(a, source, &refusal);
        const released = try support.runPasses(a, &release, .trusted);
        const stages = [_][]const u8{ try unjustified(a, &built, &.{}), try unjustified(a, &debug, debugged.plans), try unjustified(a, &release, released.plans) };
        for (stages, [_][]const u8{ "built", "debug", "release" }) |reason, stage| {
            if (reason.len != 0) return std.fmt.allocPrint(a, "shape {d} {s}: {s}", .{ index, stage, reason });
        }
    }
    return "justified";
}

/// "ran" when every shape, through the debug pipeline's ownership pass, prints what it should; else what it printed.
fn everyShapeRuns(a: std.mem.Allocator, chosen: []const Shape) ![]const u8 {
    for (chosen, 0..) |shape, index| {
        var refusal: build.Refusal = .{};
        var module = try support.buildSource(a, try std.mem.concat(a, u8, &.{ unions, shape.source }), &refusal);
        const ran = try support.runOwned(a, &module, .{});
        if (!std.mem.eql(u8, ran.stdout, shape.stdout) or ran.stderr.len != 0) return std.fmt.allocPrint(a, "shape {d} exited {d}: {s}{s}", .{ index, ran.status, ran.stdout, ran.stderr });
    }
    return "ran";
}

test "every union payload read of a nested match mut is justified by a tag test, as built and after the passes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("justified", try everyReadJustified(arena.allocator(), &shapes));
}

// FX7b: the three one-level shapes first in `shapes` (a field written in a loop, a place two fields deep, a field of a
// list element) had reads the rule did not justify before the builder tested their tags where it reads them.
test "a one-level match mut on a merged, nested or element field reads its payload under a justified tag test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("justified", try everyReadJustified(arena.allocator(), shapes[0..3]));
}

/// How many `union_tag` instructions function `name` of `module` holds.
fn tagReads(module: *const ir.Module, name: []const u8) usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        for (function.insts.items) |inst| count += @intFromBool(inst.op == .union_tag);
    }
    return count;
}

// FX7b: a union `phi` where two branches join is justified by shape P and gets no test of its own; a loop header's
// `phi` does (the gate's `tag-phi-operand` mutants need a read shape P justifies).
test "a union written on one branch of a match mut arm is read after the join without a tag test of its own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const joined = try support.buildSource(a, unions ++
        \\func main(out: Stream) -> int:
        \\    mut x = Sh.rad(value=1)
        \\    match mut x:
        \\        case rad(value=n):
        \\            if len(str(n)) > 0:
        \\                n = 5
        \\            n = n + 1
        \\            print(out, n)
        \\        case empty:
        \\            return 1
        \\    return 0
        \\
    , &refusal);
    try std.testing.expectEqual(@as(usize, 1), tagReads(&joined, "main"));
    try std.testing.expectEqualStrings("", try unjustified(a, &joined, &.{}));
    const looped = try support.buildSource(a, unions ++
        \\func main(out: Stream) -> int:
        \\    mut x = Sh.rad(value=1)
        \\    match mut x:
        \\        case rad(value=n):
        \\            for i in range(3):
        \\                n = n + i
        \\            print(out, n)
        \\        case empty:
        \\            return 1
        \\    return 0
        \\
    , &refusal);
    try std.testing.expect(tagReads(&looped, "main") > 1);
    try std.testing.expectEqualStrings("", try unjustified(a, &looped, &.{}));
}

/// FR77: a user call given `mut` a binding of a nested `match mut` arm. The call takes the place's path from the root
/// (`prepareMutPlace`): the outer payload, its field, then the inner payload, which the inner match's tag test of another
/// projection did not justify. The inner payload is now tested where the call takes it.
const call_shapes = [_]Shape{
    .{ .source =
    \\enum Pair:
    \\    two(u: int[], v: int[])
    \\    no_pair
    \\
    \\
    \\enum Held:
    \\    both(x: Pair, y: int[])
    \\    no_held
    \\
    \\
    \\func one(mut a: int[]):
    \\    append(mut a, 1)
    \\
    \\
    \\func fill(mut a: int[], mut b: int[]):
    \\    append(mut a, 2)
    \\    append(mut b, 3)
    \\
    \\
    \\func bump(mut n: int):
    \\    n = n + 10
    \\
    \\
    \\func through(mut t: Held):
    \\    match mut t:
    \\        case both(x, y):
    \\            match mut x:
    \\                case two(u, v):
    \\                    one(mut u)
    \\                    fill(mut u, mut v)
    \\                    fill(mut v, mut y)
    \\                    bump(mut u[0])
    \\                case no_pair:
    \\                    pass
    \\        case no_held:
    \\            pass
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut t = Held.both(x=Pair.two(u=[5], v=[]), y=[])
    \\    through(mut t)
    \\    print(out, t)
    \\    return 0
    \\
    , .stdout = "Held.both(x=Pair.two(u=[15, 1, 2], v=[3, 2]), y=[3])\n" },
};

test "a call given mut a binding of a nested match mut arm takes the inner payload under a tag test (FR77)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("justified", try everyReadJustified(arena.allocator(), &call_shapes));
    try std.testing.expectEqualStrings("ran", try everyShapeRuns(arena.allocator(), &call_shapes));
}

test "a nested match mut writes through to the outer owner when it runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("ran", try everyShapeRuns(arena.allocator(), &shapes));
}

// Since FX9 `check` refuses this program (the hold covers every payload type: `sh = Sh.empty` replaces the place the
// inner arm's binding writes into, before its last use). The IR the builder makes for it, which this test builds without
// the source ownership check, still tests the inner union's tag where it is read and traps if the case changed.
test "a nested binding used after its union changed case traps instead of reading another case's payload" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, unions ++
        \\func main(out: Stream) -> int:
        \\    mut o = Outer.boxed(inner=Sh.rad(value=1))
        \\    match mut o:
        \\        case boxed(inner=sh):
        \\            match mut sh:
        \\                case rad(value=v):
        \\                    sh = Sh.empty
        \\                    v = v + 8
        \\                case empty:
        \\                    return 1
        \\        case nothing:
        \\            return 1
        \\    print(out, 0)
        \\    return 0
        \\
    , &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expect(ran.status != 0);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_CORE_FACT") != null);
    try std.testing.expectEqualStrings("", ran.stdout);
}
