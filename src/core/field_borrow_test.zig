//! C3: field-level borrows in call arguments, per-arm holds of a named `match` scrutinee, and last-use moves of a
//! field out of a local record. Two different fields of one record are disjoint storage and may be passed together. A
//! path through a list element, a record and its field, the same place twice, and a payload binding read after the
//! scrutinee changed keep the overlap refusal. Moving a field consumes its whole record and drops the other fields,
//! including when the transfer occurs conditionally or inside an assignment. R2: a `const` binding of a record place holds the
//! container it was read from, so another field of the record can be written while the binding is live and read after it.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

fn refuses(backing: std.mem.Allocator, source: []const u8) !void {
    try refusesWith(backing, source, "E_SINGLE_OWNER_OVERLAP");
}

fn refusesWith(backing: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    return refusesExpected(backing, source, code, null);
}

fn refusesRule(backing: std.mem.Allocator, source: []const u8, expected: language.ownership_rules.Refusal) !void {
    return refusesExpected(backing, source, expected.code, expected.rule);
}

fn refusesExpected(backing: std.mem.Allocator, source: []const u8, code: []const u8, rule: ?language.ownership_rules.Rule) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(a, try support.checkedProgram(a, source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
    if (rule) |expected| try std.testing.expectEqual(expected, failure.rule.?);
}

fn executes(backing: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    try executesModes(backing, source, expected, &.{ false, true });
}

/// Like `executes`, but runs only the builds `releases` lists: `false` is the debug build, `true` the verified release build.
fn executesModes(backing: std.mem.Allocator, source: []const u8, expected: []const u8, releases: []const bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a, source);
    var failure: unique.Failure = .{};
    try unique.check(a, program, &failure);
    for (releases) |release| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
        const result = if (release) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        try support.verified(a, &module, result.plans);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = release, .verify = release, .analysis = support.analysis(&result) });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
    }
}

const record_prelude =
    \\record Inner:
    \\    x: int
    \\    y: int[]
    \\
    \\
    \\record Outer:
    \\    inner: Inner
    \\    grid: int[][]
    \\    tag: int[]
    \\
    \\
    \\func grow(mut xs: int[], ys: int[]) -> int:
    \\    append(mut xs, len(ys))
    \\    return len(xs)
    \\
    \\
    \\func grow_list(mut xs: int[], gs: int[][]) -> int:
    \\    append(mut xs, len(gs))
    \\    return len(xs)
    \\
    \\
    \\func bump_both(mut xs: int[], mut ys: int[]) -> int:
    \\    append(mut xs, 1)
    \\    append(mut ys, 2)
    \\    return len(xs) + len(ys)
    \\
    \\
    \\func grow_outer(mut xs: int[], o: Outer) -> int:
    \\    append(mut xs, len(o.tag))
    \\    return len(xs)
    \\
    \\
    \\func inner_grow(mut i: Inner, ys: int[]) -> int:
    \\    append(mut i.y, len(ys))
    \\    return len(i.y)
    \\
    \\
    \\func inner_read(mut ys: int[], i: Inner) -> int:
    \\    append(mut ys, i.x)
    \\    return len(ys)
    \\
    \\
;

test "C3 disjoint field arguments execute in either order, with mutable pairs and nested fields" {
    try executes(std.testing.allocator, record_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1], [2, 2]], tag=[9])
        \\    const a = grow(mut o.inner.y, o.tag)
        \\    const b = grow(mut o.tag, o.inner.y)
        \\    const c = bump_both(mut o.inner.y, mut o.tag)
        \\    const d = grow_list(mut o.inner.y, o.grid)
        \\    print(out, a, b, c, d, len(o.inner.y), len(o.tag))
        \\    return 0
        \\
    , "2 2 6 4 4 3\n");
}

test "C3 a field next to a list element of another field executes" {
    try executes(std.testing.allocator, record_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1], [2]], tag=[9])
        \\    const b = grow(mut o.tag, o.inner.y)
        \\    print(out, b, len(o.tag))
        \\    return 0
        \\
    , "2 2\n");
}

test "C3 a field and the same field refuses" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1]], tag=[9])
        \\    return grow(mut o.tag, o.tag)
        \\
    );
}

test "C3 a field and its whole record refuse in either order" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1]], tag=[9])
        \\    return grow_outer(mut o.tag, o)
        \\
    );
}

test "C3 a record and a field of it refuse in either order" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func my_take(mut o: Outer, ys: int[]) -> int:
        \\    append(mut o.tag, len(ys))
        \\    return len(o.tag)
        \\
        \\
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1]], tag=[9])
        \\    return my_take(mut o, o.tag)
        \\
    );
}

test "C3 a field and a nested part of it refuse in either order" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1]], tag=[9])
        \\    return inner_grow(mut o.inner, o.inner.y)
        \\
    );
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1]], tag=[9])
        \\    return inner_read(mut o.inner.y, o.inner)
        \\
    );
}

test "C3 list elements: a read element at another literal index and a field next to a list are disjoint and execute (G3)" {
    try executes(std.testing.allocator, record_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut g = [[1], [2, 2]]
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1], [2]], tag=[9])
        \\    const a = grow(mut g[0], g[1])
        \\    const b = grow(mut o.grid[0], o.grid[1])
        \\    const c = grow(mut o.tag, o.grid[1])
        \\    const d = grow(mut g[1], g[0])
        \\    print(out, a, b, c, d, len(g[0]), len(g[1]), len(o.grid[0]), len(o.tag))
        \\    return 0
        \\
    , "2 2 2 3 2 3 2 2\n");
}

test "C3 list elements keep the list rule: equal literals, fields inside elements and computed indices refuse" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut g = [[1], [2, 2]]
        \\    return grow(mut g[0], g[0])
        \\
    );
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1], [2]], tag=[9])
        \\    return grow(mut o.grid[0], o.grid[0])
        \\
    );
    try refuses(std.testing.allocator, record_prelude ++
        \\record Item:
        \\    tags: int[]
        \\
        \\
        \\func main() -> int:
        \\    mut items = [Item(tags=[1]), Item(tags=[2])]
        \\    return grow(mut items[0].tags, items[1].tags)
        \\
    );
}

test "C3 an element with a computed index refuses against a sibling element and against its whole list" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut g = [[1], [2]]
        \\    const i = len(g) - 2
        \\    return grow(mut g[i], g[1])
        \\
    );
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut g = [[1], [2]]
        \\    return grow_list(mut g[0], g)
        \\
    );
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1], [2]], tag=[9])
        \\    const i = len(o.grid) - 2
        \\    return grow(mut o.grid[i], o.grid[0])
        \\
    );
}

test "C3 an element refuses against its own list field's whole value" {
    try refuses(std.testing.allocator, record_prelude ++
        \\func main() -> int:
        \\    mut o = Outer(inner=Inner(x=1, y=[3]), grid=[[1], [2]], tag=[9])
        \\    return grow_list(mut o.grid[0], o.grid)
        \\
    );
}

const runtime_prelude =
    \\record Runtime:
    \\    slots: Slot[]
    \\    top: int
    \\
    \\
    \\enum Slot:
    \\    empty
    \\    full(value: int)
    \\    pair(items: int[], count: int)
    \\
    \\
    \\func bump(mut rt: Runtime):
    \\    rt.top += 1
    \\
    \\
;

test "C3 an arm that binds nothing may change the scrutinee's owner" {
    try executes(std.testing.allocator, runtime_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut rt = Runtime(slots=[Slot.full(value=4)], top=0)
        \\    match rt.slots[0]:
        \\        case full(value=_):
        \\            bump(mut rt)
        \\            print(out, rt.top)
        \\            return 0
        \\        case empty:
        \\            return 1
        \\        case pair(items=_, count=_):
        \\            return 2
        \\
    , "1\n");
}

test "C3 a payload read before the change, and a fielded payload copied before it, execute" {
    try executes(std.testing.allocator, runtime_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut rt = Runtime(slots=[Slot.pair(items=[4, 5], count=7)], top=0)
        \\    match rt.slots[0]:
        \\        case pair(items=xs, count=k):
        \\            const n = len(xs) + k
        \\            bump(mut rt)
        \\            print(out, n, rt.top)
        \\            return 0
        \\        case empty:
        \\            return 1
        \\        case full(value=_):
        \\            return 2
        \\
    , "9 1\n");
}

test "C3 a payload of numbers read after the scrutinee changed is a copy and executes (FR93)" {
    // Refused before FR93 as a read of a binding after the change; a fielded payload of numbers is copied when bound, as
    // `case Some(v)` is, so the read keeps the value it had (4, not what `bump` could have written).
    try executes(std.testing.allocator, runtime_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut rt = Runtime(slots=[Slot.full(value=4)], top=0)
        \\    match rt.slots[0]:
        \\        case full(value=v):
        \\            bump(mut rt)
        \\            print(out, v + rt.top)
        \\            return 0
        \\        case empty:
        \\            return 1
        \\        case pair(items=_, count=_):
        \\            return 2
        \\
    , "5\n");
}

test "C3 a payload binding read after the scrutinee changed refuses" {
    // A payload that holds a list is not copied: the binding reads the place the change may free (a payload of numbers: FR93).
    try refuses(std.testing.allocator, runtime_prelude ++
        \\func main(out: Stream) -> int:
        \\    mut rt = Runtime(slots=[Slot.pair(items=[4, 5], count=7)], top=0)
        \\    match rt.slots[0]:
        \\        case pair(items=xs, count=k):
        \\            bump(mut rt)
        \\            print(out, len(xs), k)
        \\            return 0
        \\        case empty:
        \\            return 1
        \\        case full(value=_):
        \\            return 2
        \\
    );
}

test "C3 a binding's own borrow of a payload refuses a change of the scrutinee while it is live" {
    try refuses(std.testing.allocator,
        \\record Box:
        \\    items: int[]
        \\
        \\
        \\record Runtime:
        \\    slots: Slot[]
        \\    top: int
        \\
        \\
        \\enum Slot:
        \\    empty
        \\    full(box: Box)
        \\
        \\
        \\func items_of(box: Box) -> int[] from box:
        \\    return box.items
        \\
        \\
        \\func bump(mut rt: Runtime):
        \\    rt.top += 1
        \\
        \\
        \\func main() -> int:
        \\    mut rt = Runtime(slots=[Slot.full(box=Box(items=[4, 5]))], top=0)
        \\    match rt.slots[0]:
        \\        case full(box=b):
        \\            const w = items_of(b)
        \\            bump(mut rt)
        \\            return len(w)
        \\        case empty:
        \\            return 0
        \\
    );
}

const move_prelude =
    \\record Box:
    \\    items: int[]
    \\    names: int[]
    \\
    \\
    \\func my_take(own xs: int[]) -> int:
    \\    return len(xs)
    \\
    \\
;

test "C3 a field moves out of a record that is never read again, with its siblings dropped" {
    try executes(std.testing.allocator, move_prelude ++
        \\func main(out: Stream) -> int:
        \\    const first = Box(items=[1, 2], names=[5, 6, 7])
        \\    const n = my_take(own first.items)
        \\    mut box = Box(items=[4], names=[8])
        \\    const m = my_take(own box.items)
        \\    box = Box(items=[9, 9], names=[1])
        \\    print(out, n, m, len(box.items), len(box.names))
        \\    return 0
        \\
    , "2 1 2 1\n");
}

test "C3 a field moves on one branch and cleans up its carrier on both paths" {
    try executes(std.testing.allocator, move_prelude ++
        \\func select(flag: bool) -> int:
        \\    const box = Box(items=[1, 2], names=[5, 6, 7])
        \\    mut n = 0
        \\    if flag:
        \\        n = my_take(own box.items)
        \\    return n
        \\func main(out: Stream) -> int:
        \\    print(out, select(True), select(False))
        \\    return 0
        \\
    , "2 0\n");
}
test "C3 a field move refuses a later read of the record or of a sibling, on one branch or after the move" {
    try refusesRule(std.testing.allocator, move_prelude ++
        \\func main(out: Stream) -> int:
        \\    const box = Box(items=[1, 2], names=[5, 6, 7])
        \\    const n = my_take(own box.items)
        \\    print(out, n, len(box.names))
        \\    return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
    try refusesRule(std.testing.allocator, move_prelude ++
        \\func main(out: Stream) -> int:
        \\    const box = Box(items=[1, 2], names=[5, 6, 7])
        \\    const n = my_take(own box.items)
        \\    const flag = 2 > 1
        \\    if flag:
        \\        print(out, n, len(box.names))
        \\    return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
}
test "C3 a field move refuses a loop that reaches the move twice" {
    try refusesRule(std.testing.allocator, move_prelude ++
        \\func main(out: Stream) -> int:
        \\    const box = Box(items=[1, 2], names=[5, 6, 7])
        \\    mut total = 0
        \\    for i in range(2):
        \\        total += my_take(own box.items)
        \\    print(out, total)
        \\    return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_LOOP", .rule = .B6 });
}

test "C3 a field move refuses a record that is a parameter the callee does not own" {
    try refusesRule(std.testing.allocator, move_prelude ++
        \\func first(box: Box) -> int:
        \\    const n = my_take(own box.items)
        \\    return n
        \\
        \\
        \\func main() -> int:
        \\    return first(Box(items=[1], names=[2]))
        \\
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8 });
    try refusesRule(std.testing.allocator, move_prelude ++
        \\func first(mut box: Box) -> int:
        \\    const n = my_take(own box.items)
        \\    return n
        \\
        \\
        \\func main() -> int:
        \\    mut b = Box(items=[1], names=[2])
        \\    return first(mut b)
        \\
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .M1 });
}

test "C3 a field moves out of a dead record and into another owner inside an assignment" {
    try executesModes(std.testing.allocator, move_prelude ++
        \\record Pair:
        \\    left: str[]
        \\    right: str[]
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const pair = Pair(left=["a"], right=["b", "c"])
        \\    mut stolen = own pair.left
        \\    print(out, len(stolen), stolen[0])
        \\    return 0
        \\
    , "1 a\n", &.{false});
    // O4 schedules carrier consumption inside the assignment's lowered block.
    try executesModes(std.testing.allocator, move_prelude ++
        \\record Inner:
        \\    scalar: int
        \\    text: str
        \\
        \\
        \\record Outer:
        \\    left: Inner
        \\    right: Inner
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    mut other = Outer(left=Inner(scalar=3, text="other"), right=Inner(scalar=5, text="other-right"))
        \\    owner.left = replace(own other.left, scalar=7)
        \\    print(out, owner.left.scalar, owner.left.text, owner.right.scalar, owner.right.text)
        \\    return 0
        \\
    , "7 other 4 right\n", &.{false});
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "C3 a field moves out of a dead record and into another owner inside an assignment (release)" {
    try support.requireRelease();
    try executesModes(std.testing.allocator, move_prelude ++
        \\record Pair:
        \\    left: str[]
        \\    right: str[]
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const pair = Pair(left=["a"], right=["b", "c"])
        \\    mut stolen = own pair.left
        \\    print(out, len(stolen), stolen[0])
        \\    return 0
        \\
    , "1 a\n", &.{true});
    // O4 schedules carrier consumption inside the assignment's lowered block.
    try executesModes(std.testing.allocator, move_prelude ++
        \\record Inner:
        \\    scalar: int
        \\    text: str
        \\
        \\
        \\record Outer:
        \\    left: Inner
        \\    right: Inner
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    mut other = Outer(left=Inner(scalar=3, text="other"), right=Inner(scalar=5, text="other-right"))
        \\    owner.left = replace(own other.left, scalar=7)
        \\    print(out, owner.left.scalar, owner.left.text, owner.right.scalar, owner.right.text)
        \\    return 0
        \\
    , "7 other 4 right\n", &.{true});
}

// R2, disjoint fields (6 November 2026): a `const` binding of a record place holds the container it was read from, so a write to
// another field of the record may happen while the binding is live, and the binding is read after it. The lowering reads the
// place again from the record after a write (alias_places.zig), which keeps every borrow clear of the update that consumes its
// root, so the ownership pass and the certificate validator (the Debug build runs it on every function) accept the result.
const builder_prelude =
    \\record Inner:
    \\    n: int
    \\    tags: str[]
    \\    other: str[]
    \\
    \\
    \\record Inst:
    \\    name: str
    \\    pins: int[]
    \\
    \\
    \\record Builder:
    \\    items: str[]
    \\    links: str[]
    \\    count: int
    \\    inner: Inner
    \\    insts: Inst[]
    \\    table: dict[str, int]
    \\
    \\
    \\func use(s: str) -> int:
    \\    return len(s)
    \\
    \\
    \\func fresh() -> Builder:
    \\    return Builder(items=["a", "bb"], links=[], count=0, inner=Inner(n=0, tags=["t"], other=[]), insts=[Inst(name="i0", pins=[1, 2])], table={})
    \\
    \\
    \\func touch(mut b: Builder):
    \\    b.count = b.count + 1
    \\
    \\
    \\func grow(mut xs: str[], s: str) -> int:
    \\    append(mut xs, copy(s))
    \\    return len(xs)
    \\
    \\
;

test "R2 an element borrow does not block a write to another field and is read after it" {
    try executes(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    for i in range(len(self.items)):
        \\        const item = self.items[i]
        \\        append(mut self.links, copy(item))
        \\        self.count = self.count + use(item)
        \\    return len(self.links) * 10 + self.count
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut b = fresh()
        \\    print(out, f(mut b), len(b.items))
        \\    return 0
        \\
    , "23 2\n");
}

test "R2 a nested record is disjoint below a shared field, and a local record by field" {
    try executes(std.testing.allocator, builder_prelude ++
        \\func nested(mut self: Builder) -> int:
        \\    const t = self.inner.tags[0]
        \\    self.inner.other = ["q"]
        \\    self.inner.n = 5
        \\    append(mut self.inner.other, copy(t))
        \\    return use(t) + self.inner.n + len(self.inner.other)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut b = fresh()
        \\    const first = nested(mut b)
        \\    const item = b.items[0]
        \\    append(mut b.links, copy(item))
        \\    b.count = use(item) + 1
        \\    b.inner.n = 3
        \\    print(out, first, len(b.links), b.count, b.inner.n, use(item))
        \\    return 0
        \\
    , "8 1 2 3 1\n");
}

test "R2 a record element, a dictionary field and a mutable argument next to a borrow" {
    try executes(std.testing.allocator, builder_prelude ++
        \\func elements(mut self: Builder) -> int:
        \\    const inst = self.insts[0]
        \\    append(mut self.links, "w")
        \\    self.count = 1
        \\    return use(inst.name) + len(inst.pins) + inst.pins[1] + self.count
        \\
        \\
        \\func table(mut self: Builder) -> int:
        \\    const item = self.items[1]
        \\    self.table[copy(item)] = 5
        \\    return self.table[copy(item)] + use(item)
        \\
        \\
        \\func arguments(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    const n = grow(mut self.inner.other, item)
        \\    const m = grow(mut self.links, item)
        \\    return n + m + use(item)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut b = fresh()
        \\    print(out, elements(mut b), table(mut b), arguments(mut b))
        \\    return 0
        \\
    , "7 7 4\n");
}

test "R2 a borrow survives the writes of a loop it was taken before, and of a branch" {
    try executes(std.testing.allocator, builder_prelude ++
        \\func across_loop(mut self: Builder) -> int:
        \\    const first = self.items[0]
        \\    for i in range(3):
        \\        self.count = self.count + use(first)
        \\        append(mut self.links, copy(first))
        \\    return self.count * 10 + len(self.links)
        \\
        \\
        \\func after_while(mut self: Builder) -> int:
        \\    const first = self.items[1]
        \\    mut i = 0
        \\    while i < 3:
        \\        append(mut self.links, "z")
        \\        i = i + 1
        \\    return use(first) * 10 + len(self.links)
        \\
        \\
        \\func in_branch(mut self: Builder) -> int:
        \\    const item = self.items[1]
        \\    if len(self.links) == 0:
        \\        append(mut self.links, "x")
        \\        self.count = use(item)
        \\    else:
        \\        self.count = 99
        \\    return self.count + use(item)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut b = fresh()
        \\    const a = across_loop(mut b)
        \\    mut c = fresh()
        \\    const d = after_while(mut c)
        \\    mut e = fresh()
        \\    mut g = fresh()
        \\    append(mut g.links, "x")
        \\    print(out, a, d, in_branch(mut e), in_branch(mut g))
        \\    return 0
        \\
    , "33 23 4 101\n");
}

test "R2 a scalar or text copy of a field keeps the value it had when it was bound" {
    try executes(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const n = self.count
        \\    const inner = self.inner.n
        \\    self.count = n + 5
        \\    self.inner.n = 9
        \\    append(mut self.links, "t")
        \\    return n * 100 + inner * 10 + self.count
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut b = fresh()
        \\    b.count = 1
        \\    print(out, f(mut b))
        \\    return 0
        \\
    , "106\n");
}

test "R2 a write to the borrowed field, to its whole record or to an element of it overlaps" {
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    append(mut self.items, "x")
        \\    return use(item)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    self.items = []
        \\    return use(item)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    self.items[1] = "y"
        \\    return use(item)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    self = fresh()
        \\    return use(item)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    touch(mut self)
        \\    return use(item)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
}

test "R2 nested records overlap at the field both paths share, and a field of an element stays one value" {
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const t = self.inner.tags[0]
        \\    append(mut self.inner.tags, "x")
        \\    return use(t)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const t = self.inner.tags[0]
        \\    self.inner = Inner(n=1, tags=[], other=[])
        \\    return use(t)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const inst = self.insts[0]
        \\    append(mut self.insts[0].pins, 3)
        \\    return use(inst.name)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
}

test "R2 only a direct const binding of a place is read by place; an alias of it, a slice and a borrowed result hold the owner" {
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    const again = item
        \\    append(mut self.links, "x")
        \\    return use(again)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func pick(s: str) -> str from s:
        \\    return s
        \\
        \\
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    const view = pick(item)
        \\    append(mut self.links, "x")
        \\    return use(view)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
    try refuses(std.testing.allocator, builder_prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    const alias = self.links
        \\    append(mut self.links, "x")
        \\    return use(item) + len(alias)
        \\
        \\
        \\func main() -> int:
        \\    mut b = fresh()
        \\    return f(mut b)
        \\
    );
}
