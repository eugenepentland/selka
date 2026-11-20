//! The validator on the programs the compiler itself makes: every function of a set of programs, after the release passes,
//! is accepted, and the two schedules the validator first showed unsafe stay fixed (a take followed only by a trap, a
//! dictionary pop with a default).
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");
const support = @import("test_support.zig");
const certificate = @import("ownership_certificate.zig");
const exporter = @import("ownership_export.zig");
const form = @import("ownership_function.zig");
const validate = @import("validate_ownership.zig");

/// What can stop a program of the corpus before the validator sees it.
pub const CorpusError = std.mem.Allocator.Error || build.Error || passes.Error || support.Error;

/// The module of `source` after the release passes, with the tables the ownership pass kept in `sink`.
fn finished(a: std.mem.Allocator, source: []const u8, sink: *certificate.Sink) !ir.Module {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var stopped: own.Refusal = .{ .certificates = sink };
    _ = try (passes.Reporting{ .arena = a, .backing = a, .module = &module, .refusal = &stopped }).runWithScratch(.trusted);
    return module;
}

/// Every function of `source` the ownership pass analysed, as the validator reads it.
pub fn functionsOf(a: std.mem.Allocator, source: []const u8) CorpusError![]form.Function {
    var sink: certificate.Sink = .{};
    const module = try finished(a, source, &sink);
    var out: std.ArrayList(form.Function) = .empty;
    for (module.functions.items, 0..) |_, i| switch (try exporter.build(a, &module, &sink, @intCast(i))) {
        .described => |function| try out.append(a, function),
        .refused => {},
    };
    return out.items;
}

/// The name of the first function of `functions` the validator does not accept, with its failure; null when all pass.
fn firstRejected(a: std.mem.Allocator, functions: []const form.Function) !?[]const u8 {
    for (functions) |function| switch (try validate.validate(a, function)) {
        .accepted, .unchecked => {},
        .rejected => |failure| {
            const text = try validate.describe(a, function.name, failure);
            return text;
        },
    };
    return null;
}

/// The programs of the corpus: each exercises a family of operations the certificate states.
pub const programs = [_][]const u8{
    // A field taken, grown and stored back; a record emptied by `own`.
    \\record Row:
    \\    items: int[]
    \\    name: str
    \\
    \\func grow(own r: Row) -> Row:
    \\    mut rows = own r
    \\    append(mut rows.items, 3)
    \\    return rows
    \\
    \\func main(out: Stream) -> int:
    \\    const r = Row(items=[1, 2], name="x")
    \\    const g = grow(own r)
    \\    print(out, len(g.items), g.name)
    \\    return 0
    ,
    // Borrowed parameters, a view returned under its `from`, owned results and calls.
    \\func part(text: str) -> str from text:
    \\    return text[1:4]
    \\
    \\func total(items: int[]) -> int:
    \\    mut sum = 0
    \\    for v in items:
    \\        sum += v
    \\    return sum
    \\
    \\func make(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(n):
    \\        append(mut xs, i)
    \\    return xs
    \\
    \\func three() -> int[]:
    \\    return [1, 2, 3]
    \\
    \\func eat(own xs: int[]) -> int:
    \\    return len(xs)
    \\
    \\func main(out: Stream) -> int:
    \\    const xs = make(4)
    \\    const t = part("abcde")
    \\    const n = eat(own three())
    \\    print(out, total(xs), len(t), n)
    \\    return 0
    ,
    // A list of lists, a loop that carries an owner, a branch that drops on one arm.
    \\func rows(n: int, wide: bool) -> int:
    \\    mut table: int[][] = []
    \\    for i in range(n):
    \\        mut row: int[] = [i]
    \\        if wide:
    \\            append(mut row, i + 1)
    \\        append(mut table, own row)
    \\    mut seen = 0
    \\    for row in table:
    \\        seen += len(row)
    \\    return seen
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, rows(3, True), rows(2, False))
    \\    return 0
    ,
    // A recursive box: options of records, copies, projections and the stores back (tests/value_semantics/recursive.selka).
    \\record Branch:
    \\    items: int[]
    \\    next: Branch?
    \\
    \\func leaf(value: int) -> Branch:
    \\    return Branch(items=[value], next=None)
    \\
    \\func copied() -> bool:
    \\    mut original = Branch(items=[0], next=Some(leaf(1)))
    \\    mut changed = copy(original)
    \\    mut child = copy(changed.next)
    \\    if child is not None:
    \\        append(mut child.items, 2)
    \\    changed.next = own child
    \\    mut old_child = copy(original.next)
    \\    mut new_child = copy(changed.next)
    \\    if old_child is None or new_child is None:
    \\        return False
    \\    return original.items == [0] and changed.items == [0] and old_child.items == [1] and new_child.items == [1, 2]
    \\
    \\func child_of(root: Branch) -> Branch:
    \\    mut child = copy(root.next)
    \\    if child is None:
    \\        return leaf(-1)
    \\    return copy(child)
    \\
    \\func projected() -> bool:
    \\    mut original = Branch(items=[0], next=Some(leaf(1)))
    \\    mut exposed = child_of(original)
    \\    mut copy_of = copy(original)
    \\    append(mut exposed.items, 2)
    \\    mut old = child_of(copy_of)
    \\    assert old.items == [1]
    \\    assert exposed.items == [1, 2]
    \\    return child_of(original).items == [1]
    \\
    \\func read_child_while_pinned(mut items: int[], root: Branch) -> Branch:
    \\    mut snapshot = child_of(root)
    \\    items[0] = 7
    \\    return snapshot
    \\
    \\func pinned() -> bool:
    \\    mut original = Branch(items=[0], next=Some(leaf(1)))
    \\    mut child = child_of(original)
    \\    const before_call = copy(child)
    \\    mut snapshot = read_child_while_pinned(mut child.items, Branch(items=[0], next=Some(own before_call)))
    \\    assert snapshot.items == [1]
    \\    assert child.items == [7]
    \\    return child_of(original).items == [1]
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, copied(), projected(), pinned())
    \\    return 0
    ,
    // A list extended with an element of itself: one list, read at one index, so the append reads the list itself.
    \\import lists
    \\
    \\func self_extend(source_index: int) -> int:
    \\    mut rows: int[][][] = [[], []]
    \\    lists.extend(mut rows[0], rows[0])
    \\    for value in range(4):
    \\        append(mut rows[0], [value])
    \\    lists.extend(mut rows[0], rows[0])
    \\    lists.extend(mut rows[0], rows[source_index])
    \\    return len(rows[0])
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, self_extend(1))
    \\    return 0
    ,
    // A dictionary entry taken and removed in one step, with and without a default.
    \\import dicts
    \\
    \\func pop_text(mut values: dict[int, str[]], key: int) -> int:
    \\    const got = dicts.pop_default(mut values, key, ["none"])
    \\    return len(got)
    \\
    \\func main(out: Stream) -> int:
    \\    mut values: dict[int, str[]] = {1: ["a" + str(1)], 2: ["b" + str(2)]}
    \\    const present = pop_text(mut values, 1)
    \\    const missing = pop_text(mut values, 9)
    \\    print(out, present, missing, len(values))
    \\    return 0
    ,
    // Task groups: a local list, a list element and a record field of a borrowed parameter lent to a task, and a parallel map.
    \\import parallel
    \\
    \\record Bag:
    \\    items: int[]
    \\    tag: int
    \\
    \\func weigh(values: int[], work: int) -> int:
    \\    mut total = work
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\func double(value: int) -> int:
    \\    return value * 2
    \\
    \\func lend_local() -> int:
    \\    with parallel.group() as g:
    \\        const xs = [1, 2, 3, 4]
    \\        const t = g.submit(weigh, xs, 2)
    \\        assert len(xs) == 4
    \\        return t.result()
    \\
    \\func lend_element() -> int:
    \\    const rows = [[1, 2], [3, 4, 5]]
    \\    mut out = 0
    \\    with parallel.group() as g:
    \\        const row = rows[1]
    \\        const t = g.submit(weigh, row, 4)
    \\        out = t.result()
    \\    return out
    \\
    \\func lend_field(bag: Bag) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(weigh, bag.items, 3)
    \\        return t.result()
    \\
    \\func main(out: Stream) -> int:
    \\    const bag = Bag(items=[1, 2], tag=0)
    \\    const doubled = parallel.map([1, 2, 3], double)
    \\    print(out, lend_local(), lend_element(), lend_field(bag), len(doubled))
    \\    return 0
    ,
    // Trap paths: a slice of a built text checks its bounds, and its trap block reads the text; an assert fails in a loop that holds a list.
    \\func part(n: int) -> int:
    \\    const text = "abcde-" + str(n)
    \\    const head = text[0:5]
    \\    return len(head)
    \\
    \\func checked(n: int) -> int:
    \\    mut rows: int[][] = []
    \\    for i in range(n):
    \\        mut row: int[] = [i]
    \\        assert len(row) == 1
    \\        append(mut rows, own row)
    \\    return len(rows)
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, part(7), checked(3))
    \\    return 0
    ,
    // A fallible borrowed result with a `mut` argument (an in-out call returns a record of the result and the written-back
    // scalar), matched, nested, bound by `try`, forwarded by `return try` (its failure is built in the declared borrowed type), and from a local owner.
    \\func withmut(data: bytes, mut position: int) -> bytes from data fails str:
    \\    if position > len(data):
    \\        fail "short-" + str(len(data))
    \\    const out = data[position:]
    \\    position = len(data)
    \\    return out
    \\
    \\func matched(data: bytes, start: int) -> int:
    \\    mut at = start
    \\    match withmut(data, mut at):
    \\        case Ok(part):
    \\            return len(part) + at
    \\        case Err(message):
    \\            return len(message)
    \\
    \\func nested(data: bytes, start: int) -> int:
    \\    mut at = start
    \\    match withmut(data, mut at):
    \\        case Ok(first):
    \\            at = start * 20
    \\            match withmut(data, mut at):
    \\                case Ok(second):
    \\                    return len(first) + len(second)
    \\                case Err(message):
    \\                    return len(first) * 100 + len(message)
    \\        case Err(message):
    \\            return len(message)
    \\
    \\func tried(data: bytes, start: int) -> int fails str:
    \\    mut at = start
    \\    const part = try withmut(data, mut at)
    \\    return len(part) * 10 + at
    \\
    \\func forward(data: bytes, mut position: int) -> bytes from data fails str:
    \\    return try withmut(data, mut position)
    \\
    \\func forwarded(data: bytes, start: int) -> int:
    \\    mut at = start
    \\    match forward(data, mut at):
    \\        case Ok(part):
    \\            return len(part) * 10 + at
    \\        case Err(message):
    \\            return len(message)
    \\
    \\func owned_source(n: int) -> int:
    \\    mut octets: int[] = []
    \\    for i in range(n):
    \\        append(mut octets, 97 + i)
    \\    const data = bytes(octets)
    \\    return matched(data, 1) + nested(data, 1) + forwarded(data, 1)
    \\
    \\func main(out: Stream) -> int:
    \\    mut failed = 0
    \\    match tried(b"abcdef", 9):
    \\        case Ok(_):
    \\            failed = 1
    \\        case Err(_):
    \\            failed = 2
    \\    print(out, matched(b"abcdef", 2), nested(b"abcdef", 1), owned_source(5), failed)
    \\    return 0
    ,
};

/// The report of the first rejection among all functions of program `i` of the corpus, or null.
fn rejectionIn(a: std.mem.Allocator, i: usize) !?[]const u8 {
    return firstRejected(a, try functionsOf(a, programs[i]));
}

test "the validator accepts every function of the ownership programs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 0));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 1));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 2));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 3));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 4));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 5));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 6));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 7));
    try std.testing.expectEqual(@as(?[]const u8, null), try rejectionIn(a, 8));
}

/// The projections of `function` that are owners (state owned) and list parents: a certificate states none.
fn ownedProjectionsWithParents(function: form.Function) usize {
    var found: usize = 0;
    for (function.blocks) |block| for (block.insts) |inst| {
        if (inst.op == .record_get and inst.result.state == .owned and inst.result.parents.len != 0) found += 1;
    };
    return found;
}

/// The owned constructors of `function` that list a parent they do not read: an owner they consume is inherited, and the
/// checker admits the parents of an owned result only among its read operands (J1, in the Zig validator and the Lean one).
fn constructorsListingConsumedParents(function: form.Function) usize {
    var found: usize = 0;
    for (function.blocks) |block| for (block.insts) |inst| {
        if (inst.class != .construct or inst.result.state != .owned) continue;
        for (inst.result.parents) |parent| switch (parent) {
            .value => |value| found += @intFromBool(std.mem.indexOfScalar(u32, inst.reads, value) == null),
            .caller => {},
        };
    };
    return found;
}

test "the record that wraps a union holding a view lists no consumed parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = try functionsOf(a, programs[8]);
    var listed: usize = 0;
    for (functions) |function| listed += constructorsListingConsumedParents(function);
    try std.testing.expectEqual(@as(usize, 0), listed);
    try std.testing.expect(functions.len >= 8);
}

test "a record a call writes a mut argument back in hands an owned projection no parents" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = try functionsOf(a, programs[8]);
    var checked: usize = 0;
    for (functions) |function| {
        const caller = std.mem.eql(u8, function.name, "matched") or std.mem.eql(u8, function.name, "nested") or std.mem.eql(u8, function.name, "tried");
        if (!caller) continue;
        checked += 1;
        try std.testing.expectEqual(@as(usize, 0), ownedProjectionsWithParents(function));
    }
    try std.testing.expectEqual(@as(usize, 3), checked);
}

/// FX15: an exchange of an element of a list of records with a managed field, the old element's field read. The old
/// element is a transferred read whose only managed part the field read takes, so the pass leaves it `emptied`.
const exchanged_record =
    \\import lists
    \\
    \\record Rec:
    \\    text: str
    \\
    \\func swapped(out: Stream) -> int:
    \\    mut xs: Rec[] = [Rec(text="a"), Rec(text="b")]
    \\    const was = lists.exchange(mut xs, 0, Rec(text="new"))
    \\    print(out, was.text, xs[0].text)
    \\    return 0
    \\
    \\func main(out: Stream) -> int:
    \\    return swapped(out)
    \\
;

/// The certificate of the function named `name` in `source` after the release passes: what the exporter refused, or the
/// number of transferred element reads it states as `emptied` and the validator's first rejection, if any.
fn exchangedRecordReport(a: std.mem.Allocator, source: []const u8, name: []const u8) ![]const u8 {
    var sink: certificate.Sink = .{};
    const module = try finished(a, source, &sink);
    for (module.functions.items, 0..) |function, i| {
        if (!std.mem.endsWith(u8, function.name, name)) continue;
        const described = switch (try exporter.build(a, &module, &sink, @intCast(i))) {
            .described => |described| described,
            .refused => |why| return std.fmt.allocPrint(a, "refused: {s}", .{why}),
        };
        var emptied: usize = 0;
        for (described.blocks) |block| for (block.insts) |inst| {
            emptied += @intFromBool(inst.op == .list_get and inst.result.state == .emptied);
        };
        const rejected = (try firstRejected(a, &.{described})) orelse "accepted";
        return std.fmt.allocPrint(a, "emptied element reads {d}, {s}", .{ emptied, rejected });
    }
    return "no such function";
}

test "an exchanged element of a list of records whose field is read is described as emptied and accepted (FX15)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("emptied element reads 1, accepted", try exchangedRecordReport(arena.allocator(), exchanged_record, "swapped"));
}

/// FR91: how many `record_take`s of the function of `source` whose name ends with `name` give an `emptied` record, and the
/// validator's verdict on it.
fn openedRecordReport(a: std.mem.Allocator, source: []const u8, name: []const u8) ![]const u8 {
    var sink: certificate.Sink = .{};
    const module = try finished(a, source, &sink);
    for (module.functions.items, 0..) |function, i| {
        if (!std.mem.endsWith(u8, function.name, name)) continue;
        const described = switch (try exporter.build(a, &module, &sink, @intCast(i))) {
            .described => |described| described,
            .refused => |why| return std.fmt.allocPrint(a, "refused: {s}", .{why}),
        };
        var emptied: usize = 0;
        for (described.blocks) |block| for (block.insts) |inst| {
            emptied += @intFromBool(inst.op == .record_take and inst.result.state == .emptied);
        };
        const rejected = (try firstRejected(a, &.{described})) orelse "accepted";
        return std.fmt.allocPrint(a, "emptied takes {d}, {s}", .{ emptied, rejected });
    }
    return "no such function";
}

/// Two fields of one record moved in one statement, out of an `own` parameter and out of a local (FR91).
const own_fields =
    \\record Piece:
    \\    order: func(int, int) -> int
    \\    items: int[]
    \\
    \\record Pair:
    \\    lo: Piece
    \\    hi: Piece
    \\    tag: str
    \\
    \\func cmp(a: int, b: int) -> int:
    \\    return a - b
    \\
    \\func total(own a: Piece, own b: Piece) -> int:
    \\    return len(a.items) * 10 + len(b.items)
    \\
    \\func make(n: int) -> Pair:
    \\    return Pair(lo=Piece(order=cmp, items=[n]), hi=Piece(order=cmp, items=[n, n]), tag="t-" + str(n))
    \\
    \\func opened_parameter(own p: Pair) -> int:
    \\    return total(own p.lo, own p.hi)
    \\
    \\func opened_local(n: int) -> int:
    \\    const p = make(n)
    \\    const before = len(p.tag)
    \\    return total(own p.hi, own p.lo) + before
    \\
    \\func main() -> int:
    \\    return opened_parameter(make(1)) + opened_local(2)
;

test "several fields moved out of one record in one statement open it once, an emptied record_take, and are accepted (FR91)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("emptied takes 1, accepted", try openedRecordReport(arena.allocator(), own_fields, "opened_parameter"));
    try std.testing.expectEqualStrings("emptied takes 1, accepted", try openedRecordReport(arena.allocator(), own_fields, "opened_local"));
}

/// How many instructions of `function` are drops in a block that only reaches a trap: the process exits at the trap and
/// runs no destruction, so a drop there is a release that never happens and a take that is never closed.
fn dropsOnTrapPaths(a: std.mem.Allocator, function: *const ir.Function) !usize {
    const trapping = try a.alloc(bool, function.blocks.items.len);
    @memset(trapping, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (function.blocks.items, 0..) |block, b| {
            if (trapping[b] or block.insts.items.len == 0) continue;
            const next = own.successors(function, @intCast(b));
            var all = next.len != 0;
            for (next.slice()) |s| all = all and trapping[s];
            const ends = function.inst(block.insts.items[block.insts.items.len - 1]).op == .@"unreachable";
            if (ends or all) {
                trapping[b] = true;
                changed = true;
            }
        }
    }
    var found: usize = 0;
    for (function.blocks.items, 0..) |block, b| {
        if (!trapping[b]) continue;
        for (block.insts.items) |ref| found += @intFromBool(function.inst(ref).op == .drop);
    }
    return found;
}

test "a block that only reaches a trap releases nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: certificate.Sink = .{};
    const module = try finished(a, programs[3], &sink);
    var found: usize = 0;
    for (module.functions.items) |*function| found += try dropsOnTrapPaths(a, function);
    try std.testing.expectEqual(@as(usize, 0), found);
}

/// Lane J4: three shapes of records and collections that hold borrows, whose drops the pass once ordered against their roots.
const lent_drop_programs = [_][]const u8{
    // RB2: a local list of borrowed dictionary keys filled in a loop; the loop's phis are a cycle of parents.
    \\import dicts
    \\
    \\func roles(key: bytes) -> int:
    \\    mut pins: dict[bytes, bytes] = {}
    \\    pins[key] = b"sw"
    \\    pins[b"p2"] = b"x"
    \\    mut nodes: bytes[] = []
    \\    for pad in dicts.keys(pins):
    \\        if pins[pad] == b"sw":
    \\            append(mut nodes, pad)
    \\    mut total = 0
    \\    for pad in nodes:
    \\        total += len(pad)
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, roles(b"p1"))
    \\    return 0
    ,
    // RB1: a borrowed record that keeps a `None` default for a managed option field, appended to a list in a loop.
    \\record Spoke:
    \\    name: bytes
    \\    pins: bytes[] = []
    \\
    \\record Body:
    \\    x: int
    \\    terminal: bytes
    \\    deferred: Spoke? = None
    \\
    \\func bodies(names: bytes[]) -> int:
    \\    mut out: Body[] = []
    \\    for n in names:
    \\        append(mut out, Body(x=1, terminal=n))
    \\    mut total = 0
    \\    for b in out:
    \\        total += b.x + len(b.terminal)
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    mut names: bytes[] = []
    \\    append(mut names, b"aa")
    \\    print(out, bodies(names))
    \\    return 0
    ,
    // A chain of 150 appends of borrows with no loop: longer than the step budget the loan search once gave up at.
    \\record Spoke:
    \\    name: bytes
    \\
    \\func chain(name: bytes) -> int:
    \\    const owner = Spoke(name=b"first-" + name)
    \\    mut nodes: bytes[] = []
    \\    append(mut nodes, owner.name)
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    append(mut nodes, b"zz")
    \\    mut total = 0
    \\    for node in nodes:
    \\        total += len(node)
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, chain(b"nm"))
    \\    return 0
    ,
};

test "lists and records that hold borrows are destroyed before what they borrow (J4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, try functionsOf(a, lent_drop_programs[0])));
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, try functionsOf(a, lent_drop_programs[1])));
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, try functionsOf(a, lent_drop_programs[2])));
}

test "a borrowed result read out of a call's record beside a mut list, and read by nothing after, keeps its root until it is taken (J4)" {
    // The ownership matrix's `ints__param_element__return_from__bare` (lane OC, stage O5): `rows` died at the call and the
    // borrow was taken from the call's result after it, because the schedule counted a loan's uses but not its definition.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func number_row(n: int) -> int[]:
        \\    return [n, n + 1]
        \\
        \\func logged_first(rows: int[][], mut log: int[]) -> int[] from rows:
        \\    append(mut log, len(rows))
        \\    return rows[0]
        \\
        \\func main(out: Stream) -> int:
        \\    const rows = [number_row(4)]
        \\    mut log: int[] = []
        \\    _ = logged_first(rows, mut log)
        \\    print(out, len(log))
        \\    return 0
    ;
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, try functionsOf(a, source)));
}

test "a view of a dictionary entry's field in a record keeps the field's later reads from taking it before the view's last use (FR54)" {
    // W5-F-4: `server.conns[id].out` read three times and then assigned. The ownership pass merged the assignment's take of
    // `server.conns` into the third read, ahead of the last use of the first read's view, because its walk of a read's
    // uses stopped at the dictionary entry (and, with the field bound to a local, at the view of it); the validator refused the
    // function (J4) and the build failed. `selka fix` turns the writer's `copy(...)` workaround into `queue_bound`;
    // `flush_queue` is the server's own loop, whose `at` (a scalar read through the entry) the walk must not follow.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import byte_builder
        \\
        \\record Conn:
        \\    out: bytes
        \\    sent: int
        \\
        \\record Server:
        \\    conns: dict[int, Conn]
        \\
        \\func queue_output(mut server: Server, id: int):
        \\    mut joined = byte_builder.create()
        \\    _ = byte_builder.append_range(mut joined, server.conns[id].out, server.conns[id].sent, len(server.conns[id].out))
        \\    server.conns[id].out = byte_builder.finish(joined)
        \\
        \\func double_output(mut server: Server, id: int):
        \\    server.conns[id].out = byte_builder.repeat(server.conns[id].out, server.conns[id].sent + 1)
        \\
        \\func queue_bound(mut server: Server, id: int):
        \\    const queued = server.conns[id].out
        \\    mut joined = byte_builder.create()
        \\    _ = byte_builder.append_range(mut joined, queued, server.conns[id].sent, len(queued))
        \\    server.conns[id].out = byte_builder.finish(joined)
        \\
        \\record Queue:
        \\    chunks: bytes[]
        \\    head: int
        \\    sent: int
        \\
        \\record Outbox:
        \\    queues: dict[int, Queue]
        \\
        \\func unsent(chunk: bytes, sent: int) -> int:
        \\    return len(chunk) - sent
        \\
        \\func flush_queue(mut box: Outbox, id: int):
        \\    while box.queues[id].head < len(box.queues[id].chunks):
        \\        const at = box.queues[id].head
        \\        const n = unsent(box.queues[id].chunks[at], box.queues[id].sent)
        \\        box.queues[id].sent += n
        \\        if box.queues[id].sent >= len(box.queues[id].chunks[at]):
        \\            box.queues[id].head += 1
        \\            box.queues[id].sent = 0
        \\
        \\func main(out: Stream) -> int:
        \\    mut server = Server(conns={})
        \\    server.conns[1] = Conn(out=b"abc", sent=1)
        \\    queue_output(mut server, 1)
        \\    double_output(mut server, 1)
        \\    queue_bound(mut server, 1)
        \\    mut box = Outbox(queues={})
        \\    box.queues[1] = Queue(chunks=[b"ab", b"cde"], head=0, sent=0)
        \\    flush_queue(mut box, 1)
        \\    print(out, box.queues[1].head)
        \\    print(out, server.conns[1].out)
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        if (std.mem.endsWith(u8, function.name, "::queue_output") or std.mem.endsWith(u8, function.name, "::double_output") or
            std.mem.endsWith(u8, function.name, "::queue_bound") or std.mem.endsWith(u8, function.name, "::flush_queue")) named += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a call that lends a scalar field and a managed field of one record mut stores both back from one record (FR62)" {
    // `split_url(o.url, mut o.port, mut o.path)`: the call's write-back stored `o.port` from the record first, then rebuilt
    // `o.path`'s path from the record read before the call, so the ownership pass refused the second store (Z3, "takes
    // ownership of a value that `split_url` still reads afterwards") and the functions were not described.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Options:
        \\    url: str
        \\    port: int
        \\    path: str
        \\
        \\record Inner:
        \\    x: int
        \\    name: str
        \\
        \\record Outer:
        \\    b: Inner
        \\    c: str
        \\    url: str
        \\
        \\func split_url(url: str, mut port_out: int, mut path_out: str) -> bool:
        \\    if len(url) < 3:
        \\        return False
        \\    port_out = 80
        \\    path_out = copy(url[2:])
        \\    return True
        \\
        \\func parse(own url: str) -> Options:
        \\    mut options = Options(url=own url, port=0, path="/")
        \\    if not split_url(options.url, mut options.port, mut options.path):
        \\        options.port = -1
        \\    return options
        \\
        \\func fill(mut options: Options):
        \\    _ = split_url(options.url, mut options.port, mut options.path)
        \\
        \\func parse_nested(own url: str) -> Outer:
        \\    mut a = Outer(b=Inner(x=0, name="n"), c="/", url=own url)
        \\    _ = split_url(a.url, mut a.b.x, mut a.c)
        \\    return a
        \\
        \\func main(out: Stream) -> int:
        \\    mut o = parse("abcdef")
        \\    fill(mut o)
        \\    const n = parse_nested("abcdef")
        \\    print(out, o.port, o.path, n.b.x, n.c)
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "parse", "fill", "parse_nested" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a try that lends a list element at a run-time index beside a managed field of one record stores the element's list first (FR94)" {
    // `try step(mut server.state, mut server.counts, mut server.conns[index], now)`: the write-back set `state` into
    // `server` before it set the element into its list, read from `server` before the call; the ownership pass then left
    // that list a borrow, and the element's take at a run-time index from it failed J8 ("a take from %15, which is borrowed").
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Reader:
        \\    buf: u8[]
        \\
        \\record Conn:
        \\    id: int
        \\    reader: Reader
        \\
        \\record State:
        \\    names: str[]
        \\
        \\record Counts:
        \\    reads: int
        \\
        \\record Server:
        \\    conns: Conn[]
        \\    state: State
        \\    counts: Counts
        \\
        \\func step(mut state: State, mut counts: Counts, mut c: Conn, now: int) -> Unit fails str:
        \\    if now > 100:
        \\        fail "late"
        \\    append(mut c.reader.buf, 1u8)
        \\    append(mut state.names, "n")
        \\    counts.reads += 1
        \\    c.id += 10
        \\    return
        \\
        \\func poll_one(mut server: Server, index: int, now: int) -> Unit fails str:
        \\    try step(mut server.state, mut server.counts, mut server.conns[index], now)
        \\
        \\func main(out: Stream) -> int:
        \\    mut server = Server(conns=[Conn(id=1, reader=Reader(buf=[]))], state=State(names=[]), counts=Counts(reads=0))
        \\    const r = poll_one(mut server, 0, 5)
        \\    if r is Err(e):
        \\        print(out, e)
        \\    print(out, server.conns[0].id, server.counts.reads, len(server.state.names))
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        if (std.mem.eql(u8, function.name, "poll_one")) named += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a field written through two dictionary entries, or by a compound assignment that reads its entry again, takes the reads its receiver was made of (FR66)" {
    // Lane FR54's two open shapes. `queue_output` rebuilt the outer entry from a second read of `server.groups` while the
    // inner write took the first read's `conns`; `drain` and `bump` left a dead second read of `pool.conns` beside the
    // right side's own read, which kept the reads from being joined. Both were refused at build (Z3, "a borrowed part of
    // `server`"), so the ownership pass described none of the three functions.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Conn:
        \\    out: bytes
        \\    sent: int
        \\
        \\record Group:
        \\    conns: dict[int, Conn]
        \\
        \\record Server:
        \\    groups: dict[int, Group]
        \\
        \\record Pool:
        \\    conns: dict[int, Conn]
        \\
        \\func queue_output(mut server: Server, g: int, id: int):
        \\    server.groups[g].conns[id].out = b"xyz"
        \\
        \\func drain(mut pool: Pool, id: int, chunks: bytes[]) -> int:
        \\    mut at = 0
        \\    while at < len(chunks):
        \\        pool.conns[id].sent += len(chunks[at]) - pool.conns[id].sent
        \\        at += 1
        \\    return pool.conns[id].sent
        \\
        \\func bump(mut pool: Pool, id: int, n: int) -> int:
        \\    pool.conns[id].sent *= n - pool.conns[id].sent
        \\    return pool.conns[id].sent
        \\
        \\func main(out: Stream) -> int:
        \\    mut server = Server(groups={})
        \\    server.groups[1] = Group(conns={})
        \\    server.groups[1].conns[2] = Conn(out=b"abc", sent=1)
        \\    queue_output(mut server, 1, 2)
        \\    mut pool = Pool(conns={})
        \\    pool.conns[7] = Conn(out=b"abcdef", sent=1)
        \\    print(out, drain(mut pool, 7, [b"ab", b"cde", b"f"]))
        \\    print(out, bump(mut pool, 7, 5))
        \\    print(out, server.groups[1].conns[2].out)
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "queue_output", "drain", "bump" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a scalar mut argument under a match mut payload binding is stored back by taking the payload, as an assignment is (FR76)" {
    // `bump1(mut vals[0])` in `case pairs(keys, vals):` stored the result back through a borrowed read of the payload
    // (`union_payload`) whose record the rebuild then took: refused at build (Z3, "a borrowed part"), and for a scrutinee
    // that is a list element (`match mut ts[0]`) the plan left a take open (J8). The ownership pass described neither.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\enum Pairs:
        \\    pairs(keys: str[], vals: int[])
        \\    nothing
        \\
        \\func bump1(mut a: int):
        \\    a = a + 1
        \\
        \\func swap2(mut a: int, mut b: int):
        \\    const t = a
        \\    a = b
        \\    b = t
        \\
        \\func local_payload() -> int:
        \\    mut t = Pairs.pairs(keys=["x"], vals=[1, 2])
        \\    match mut t:
        \\        case pairs(keys=_, vals):
        \\            bump1(mut vals[0])
        \\            swap2(mut vals[0], mut vals[1])
        \\        case nothing:
        \\            pass
        \\    return len(f"{t}")
        \\
        \\func element_scrutinee() -> int:
        \\    mut ts = [Pairs.pairs(keys=["x"], vals=[1, 2])]
        \\    match mut ts[0]:
        \\        case pairs(keys=_, vals):
        \\            bump1(mut vals[1])
        \\        case nothing:
        \\            pass
        \\    return len(f"{ts}")
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, local_payload(), element_scrutinee())
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "local_payload", "element_scrutinee" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

// A `match mut` on a list element is payload-read shape M, which the `tests/lang` proof corpus caps (verify-ir-proof's
// SHAPE_M_CEILING, D-VL-12), so this one runs here rather than in `tests/lang/payload_scalar_mut_arguments.selka`.
const fr76_list_element_scrutinee =
    \\enum Pairs:
    \\    pairs(keys: str[], vals: int[])
    \\    nothing
    \\
    \\func bump1(mut a: int):
    \\    a = a + 1
    \\
    \\func bump_value(a: int) -> int:
    \\    return a + 1
    \\
    \\func shown(ts: Pairs[]) -> int:
    \\    match ts[0]:
    \\        case pairs(keys, vals):
    \\            return len(keys) * 100 + vals[0] * 10 + vals[1]
    \\        case nothing:
    \\            return -1
    \\
    \\func main(out: Stream) -> int:
    \\    mut ts = [Pairs.pairs(keys=["x"], vals=[1, 2])]
    \\    match mut ts[0]:
    \\        case pairs(keys=_, vals):
    \\            bump1(mut vals[1])
    \\        case nothing:
    \\            pass
    \\    mut us = [Pairs.pairs(keys=["x"], vals=[1, 2])]
    \\    match mut us[0]:
    \\        case pairs(keys=_, vals):
    \\            vals[1] = bump_value(vals[1])
    \\        case nothing:
    \\            pass
    \\    print(out, shown(ts), shown(us))
    \\    return 0
;

test "a scalar mut argument under a match mut on a list element runs as the plain assignment does (FR76)" {
    // `bump1(mut vals[1])` in `match mut ts[0]:` left a take open (J8) and did not build; it now prints what
    // `vals[1] = bump_value(vals[1])` prints, through the debug pipeline with the leak check. The release half is a test
    // of its own: it is skipped unless release builds are on (`-Dtest-release`), and this one must run in the gate.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, fr76_list_element_scrutinee, &refusal);
    const result = try passes.debug(a, &module);
    const ran = try support.runOwned(a, &module, .{ .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("113 113\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

test "a scalar mut argument under a match mut on a list element runs as the plain assignment does, optimized (FR76)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try support.requireRelease();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, fr76_list_element_scrutinee, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    const ran = try support.runOwned(a, &module, .{ .own = false, .release = true, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("113 113\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

test "a compound assignment to an entry field whose right side reads other entries of the dictionary takes the reads its receiver was made of (FR70)" {
    // The right side read `dock.ports` (or `yard.docks` and the entry under it) again for each other entry, after the
    // receiver binding's read and before the write that takes it, so the write took a read that was then a borrow. It
    // was refused at build (Z3, "a borrowed part of `dock`"), so the ownership pass described neither function.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Port:
        \\    out: bytes
        \\    sent: int
        \\
        \\record Dock:
        \\    ports: dict[int, Port]
        \\
        \\record Yard:
        \\    docks: dict[int, Dock]
        \\
        \\func add_other(mut dock: Dock, id: int) -> int:
        \\    dock.ports[id].sent += dock.ports[8].sent * len(dock.ports[id].out)
        \\    return dock.ports[id].sent
        \\
        \\func add_other_two_deep(mut yard: Yard, d: int, id: int) -> int:
        \\    yard.docks[d].ports[id].sent += yard.docks[d].ports[8].sent * len(yard.docks[d].ports[id].out)
        \\    return yard.docks[d].ports[id].sent
        \\
        \\func main(out: Stream) -> int:
        \\    mut dock = Dock(ports={})
        \\    dock.ports[7] = Port(out=b"abc", sent=1)
        \\    dock.ports[8] = Port(out=b"", sent=2)
        \\    print(out, add_other(mut dock, 7))
        \\    mut yard = Yard(docks={})
        \\    yard.docks[1] = dock
        \\    print(out, add_other_two_deep(mut yard, 1, 7))
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "add_other", "add_other_two_deep" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a compound assignment to an entry field whose right side calls a function takes the reads its receiver was made of (FR71)" {
    // The call ran after the receiver binding's read and before the write that takes it, and any call there made the
    // write read `dock.ports` again; that read left the binding's a borrow the write took. It was refused at build (Z3,
    // "cannot schedule dict_set_value"), so the ownership pass described none of the functions.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Port:
        \\    out: bytes
        \\    sent: int
        \\
        \\record Dock:
        \\    ports: dict[int, Port]
        \\
        \\func twice(n: int) -> int:
        \\    return n * 2
        \\
        \\func out_len(port: Port) -> int:
        \\    return len(port.out)
        \\
        \\func add_called(mut dock: Dock, id: int) -> int:
        \\    dock.ports[id].sent += twice(dock.ports[8].sent)
        \\    return dock.ports[id].sent
        \\
        \\func add_lent(mut dock: Dock, id: int) -> int:
        \\    dock.ports[id].sent -= out_len(dock.ports[8])
        \\    return dock.ports[id].sent
        \\
        \\func main(out: Stream) -> int:
        \\    mut dock = Dock(ports={})
        \\    dock.ports[7] = Port(out=b"abc", sent=1)
        \\    dock.ports[8] = Port(out=b"zz", sent=2)
        \\    print(out, add_called(mut dock, 7))
        \\    print(out, add_lent(mut dock, 7))
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "add_called", "add_lent" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a compound assignment to an entry field whose right side lends another entry mut reads its receiver again (FR72)" {
    // The call stores `dock.ports` back into `dock`, and the checker's second read of the entry went through the receiver
    // binding's value from before the call: the write put that stale dictionary back while the store had taken it. It
    // was refused at build (Z3, "cannot schedule a store", at the `mut` argument), so the pass described none of them.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Port:
        \\    out: bytes
        \\    sent: int
        \\
        \\record Dock:
        \\    ports: dict[int, Port]
        \\
        \\record Yard:
        \\    docks: dict[int, Dock]
        \\
        \\func reset_port(mut port: Port) -> int:
        \\    port.sent = 50
        \\    return 3
        \\
        \\func add_reset(mut dock: Dock, id: int) -> int:
        \\    dock.ports[id].sent += reset_port(mut dock.ports[8])
        \\    return dock.ports[id].sent
        \\
        \\func add_reset_two_deep(mut yard: Yard, d: int, e: int, id: int) -> int:
        \\    yard.docks[d].ports[id].sent -= reset_port(mut yard.docks[e].ports[8])
        \\    return yard.docks[d].ports[id].sent
        \\
        \\func main(out: Stream) -> int:
        \\    mut dock = Dock(ports={})
        \\    dock.ports[7] = Port(out=b"abc", sent=1)
        \\    dock.ports[8] = Port(out=b"zz", sent=2)
        \\    print(out, add_reset(mut dock, 7))
        \\    mut yard = Yard(docks={})
        \\    yard.docks[1] = dock
        \\    print(out, add_reset_two_deep(mut yard, 1, 1, 7))
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "add_reset", "add_reset_two_deep" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a compound assignment to a list element field whose right side lends another element mut reads its list again (FR73)" {
    // The list form of FR72: the call stores `deck.slots` back into `deck`, and the element write went through the
    // receiver binding's list from before the call. It was refused at build (E_CORE_UNSUPPORTED, "write to a receiver's
    // place while its arguments are evaluated", at the write), so the pass described none of them.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Slot:
        \\    id: int
        \\    n: int
        \\
        \\record Lane:
        \\    slots: Slot[]
        \\
        \\record Deck:
        \\    slots: Slot[]
        \\    lanes: Lane[]
        \\
        \\func bump_slot(mut slot: Slot) -> int:
        \\    slot.n = slot.n + 50
        \\    return 3
        \\
        \\func add_bump(mut deck: Deck, i: int, j: int) -> int:
        \\    deck.slots[i].n += bump_slot(mut deck.slots[j])
        \\    return deck.slots[i].n
        \\
        \\func subtract_bump_two_deep(mut deck: Deck, g: int, h: int, i: int, j: int) -> int:
        \\    deck.lanes[g].slots[i].n -= bump_slot(mut deck.lanes[h].slots[j])
        \\    return deck.lanes[g].slots[i].n
        \\
        \\func main(out: Stream) -> int:
        \\    mut deck = Deck(slots=[Slot(id=1, n=1), Slot(id=2, n=2)], lanes=[Lane(slots=[Slot(id=3, n=9)])])
        \\    print(out, add_bump(mut deck, 0, 1))
        \\    print(out, subtract_bump_two_deep(mut deck, 0, 0, 0, 0))
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "add_bump", "subtract_bump_two_deep" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a compound assignment to an element field of a local list whose right side lends another element mut reads it again (FR74)" {
    // The local-root form of FR73: the receiver binding is the list (or dictionary) local itself, or lies under one of its
    // elements, and the call stores the element back into the local. The write went through the binding's value from
    // before the call: refused at build (E_CORE_UNSUPPORTED, "write to a receiver's place while its arguments are
    // evaluated"), so the pass described none of them.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Slot:
        \\    n: int
        \\
        \\func bump_slot(mut slot: Slot) -> int:
        \\    slot.n = slot.n + 50
        \\    return 3
        \\
        \\func add_bump_list(mut slots: Slot[], i: int, j: int) -> int:
        \\    slots[i].n += bump_slot(mut slots[j])
        \\    return slots[i].n
        \\
        \\func subtract_bump_grid(mut grid: Slot[][], i: int, j: int) -> int:
        \\    grid[i][0].n -= bump_slot(mut grid[j][0])
        \\    return grid[i][0].n
        \\
        \\func add_bump_dict(mut slots: dict[str, Slot], k: str) -> int:
        \\    slots[k].n += bump_slot(mut slots["b"])
        \\    return slots[k].n
        \\
        \\func main(out: Stream) -> int:
        \\    mut slots = [Slot(n=1), Slot(n=2)]
        \\    mut grid = [[Slot(n=1)], [Slot(n=2)]]
        \\    mut named = {"a": Slot(n=1), "b": Slot(n=2)}
        \\    print(out, add_bump_list(mut slots, 0, 1), subtract_bump_grid(mut grid, 0, 1), add_bump_dict(mut named, "a"))
        \\    return 0
    ;
    const functions = try functionsOf(a, source);
    var named: usize = 0;
    for (functions) |function| {
        for ([_][]const u8{ "add_bump_list", "subtract_bump_grid", "add_bump_dict" }) |name| {
            if (std.mem.eql(u8, function.name, name)) named += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), named);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, functions));
}

test "a byte buffer an option or a result holds reaches a read-only parameter in its owned form, as a plain one does (FR92)" {
    // A `byte_buffer?` or `Result[byte_buffer, str]` parameter took a spine of bytes views, which the caller made of the
    // buffer with a text length (`str_len`): the IR verifier refused the module, and `bytes(b)` of the payload binding had
    // no bytes-view form. A plain `byte_buffer` parameter was always passed owned.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import buffers
        \\
        \\func buffer_option(first: byte_buffer?) -> int:
        \\    match first:
        \\        case Some(b):
        \\            return 100 * len(b) + len(bytes(b))
        \\        case None:
        \\            return 1
        \\
        \\func buffer_result(r: Result[byte_buffer, str]) -> int:
        \\    const b = r else Err(e):
        \\        return len(e)
        \\    return b[0]
        \\
        \\func main(out: Stream) -> int:
        \\    mut a = buffers.empty()
        \\    _ = buffers.append_byte(mut a, 7)
        \\    const first: byte_buffer? = Some(copy(a))
        \\    const r: Result[byte_buffer, str] = Ok(own a)
        \\    print(out, buffer_option(first) + buffer_result(r))
        \\    return 0
    ;
    var sink: certificate.Sink = .{};
    const module = try finished(a, source, &sink);
    var owned: usize = 0;
    for (module.functions.items) |function| {
        const named = std.mem.endsWith(u8, function.name, "buffer_option") or std.mem.endsWith(u8, function.name, "buffer_result");
        if (!named) continue;
        const cases = module.compound(function.signature.params[0]).@"union";
        if (std.mem.indexOfScalar(ir.Type, cases, .byte_buffer) != null) owned += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), owned);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstRejected(a, try functionsOf(a, source)));
}
