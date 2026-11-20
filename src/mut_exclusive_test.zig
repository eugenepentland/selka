//! M5 belongs to Core: the front end accepts overlap candidates after checking
//! their markers, and Core alone refuses conflicting active place paths.
const std = @import("std");
const t = std.testing;
const transition = @import("ownership_transition_test_support.zig");
const compiler = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const File = compiler.embedded_project.File;

const helpers =
    \\record R:
    \\    rows: int[][]
    \\    n: int
    \\
    \\record S:
    \\    a: int[]
    \\    b: int[]
    \\
    \\enum Status:
    \\    ok
    \\    failed
    \\
    \\func two(mut a: int[], mut b: int[]) -> Unit:
    \\    append(mut a, 1)
    \\    append(mut b, 2)
    \\
    \\func nested(mut xs: int[][], mut ys: int[]) -> Unit:
    \\    append(mut xs, [5])
    \\    append(mut ys, 9)
    \\
    \\func same(mut xs: int[][], mut ys: int[][]) -> Unit:
    \\    append(mut xs, [5])
    \\    append(mut ys, [9])
    \\
    \\func rec(mut a: R, mut xs: int[][]) -> Unit:
    \\    a.n = a.n + 1
    \\    append(mut xs, [1])
    \\
    \\func records(mut a: S, mut b: S) -> Unit:
    \\    append(mut a.a, 1)
    \\    append(mut b.b, 2)
    \\
    \\func read_one(mut a: int[], b: int[]) -> int:
    \\    append(mut a, len(b))
    \\    return len(b)
    \\
    \\func make(mut p: int[]) -> int:
    \\    append(mut p, 3)
    \\    return len(p)
    \\
    \\func emit(mut p: int[], c: int) -> Unit:
    \\    append(mut p, c)
    \\
    \\func inner_first(mut ys: int[], mut xs: int[][]) -> Unit:
    \\    append(mut ys, 9)
    \\    append(mut xs, [5])
    \\
    \\
;

/// Check the helper program in the front end, leaving overlap decisions to Core.
fn accepts(body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(), try std.mem.concat(arena.allocator(), u8, &.{ helpers, body }));
}

/// Check a whole program without applying Core's ownership rules.
fn acceptsProgram(bytes: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(), bytes);
}

/// Require frontend acceptance and the exact Core overlap refusal.
fn refuses(comptime body: []const u8) !void {
    return refusesProgram(helpers ++ body);
}

/// `refuses` for a body that calls `lists.exchange` (W13-S5), which needs `import lists` before the helpers.
fn refusesWithLists(comptime body: []const u8) !void {
    return refusesProgram("import lists\n\n" ++ helpers ++ body);
}

fn refusesProgram(bytes: []const u8) !void {
    try acceptsProgram(bytes);
    try transition.refuses(t.allocator, bytes, "E_SINGLE_OWNER_OVERLAP");
}

fn removedNegative(body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const bytes = try std.mem.concat(arena.allocator(), u8, &.{ helpers, body });
    try fixture.rejectsWith(arena.allocator(), bytes, "E_NEGATIVE_INDEX_REMOVED");
}

fn main(comptime statements: []const u8) []const u8 {
    return "func main() -> int:\n" ++ statements ++ "    return 0\n";
}

// spec: MUT-EXCLUSIVE-1
test "Core alone rejects mut arguments naming one place or its part" {
    try refuses(main("    mut b = [[1, 2], [3]]\n    same(mut b, mut b)\n"));
    try refuses(main("    mut a = [[1, 2], [3]]\n    nested(mut a, mut a[0])\n"));
    try refuses(main("    mut r = R(rows=[[1, 2], [3]], n=0)\n    rec(mut r, mut r.rows)\n"));
    try refuses(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[0])\n"));
    try refuses(main("    mut s = S(a=[1], b=[2])\n    two(mut s.a, mut s.a)\n"));
}

// spec-case: MUT-EXCLUSIVE-1
test "frontend defers dynamic mut indices while Core rejects unresolved roots" {
    try refuses(main("    mut xs = [[1], [2], [3]]\n    mut i = 0\n    mut j = 1\n    two(mut xs[i], mut xs[j])\n"));
    try refuses(main("    mut xs = [[1], [2], [3]]\n    mut i = 0\n    two(mut xs[i], mut xs[0])\n"));
    try removedNegative(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[-1], mut xs[2])\n"));
    try refuses(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[len(xs) - 1], mut xs[2])\n"));
    try refuses(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[1 + 1], mut xs[0])\n"));
    try refuses(main("    mut d = {1: [1], 2: [2]}\n    mut k = 1\n    two(mut d[k], mut d[2])\n"));
    try refuses(main("    mut rows = [S(a=[1], b=[2]), S(a=[3], b=[4])]\n    mut i = 0\n    mut j = 1\n    two(mut rows[i].a, mut rows[j].a)\n"));
    const table = "    mut t: [Status]int[] = {Status.ok: [1], Status.failed: [2]}\n    two(mut t[Status.ok], mut t[Status.ok])\n";
    try refuses(main(table));
}

// spec-case: MUT-EXCLUSIVE-1
test "frontend accepts disjoint places and defers conservative Core refusals" {
    // Core also permits disjoint mutable fields and literal list indices.
    try accepts(main("    mut s = S(a=[1], b=[2])\n    two(mut s.a, mut s.b)\n"));
    try accepts(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[2])\n"));
    try removedNegative(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[-1], mut xs[-2])\n"));
    try refuses(main("    mut xs = [[1], [2], [3]]\n    two(mut xs[len(xs) - 1], mut xs[len(xs) - 2])\n"));
    try refuses(main("    mut d = {\"a\": [1], \"b\": [2]}\n    two(mut d[\"a\"], mut d[\"b\"])\n"));
    try refuses(main("    mut d = {-1: [1], 2: [2]}\n    two(mut d[-1], mut d[2])\n"));
    try refuses(main("    mut rows = [S(a=[1], b=[2]), S(a=[3], b=[4])]\n    mut i = 0\n    mut j = 1\n    two(mut rows[i].a, mut rows[j].b)\n"));
    try refuses(main("    mut t: [Status]int[] = {Status.ok: [1], Status.failed: [2]}\n    two(mut t[Status.ok], mut t[Status.failed])\n"));
    try accepts(main("    mut a = [1]\n    mut b = [2]\n    two(mut a, mut b)\n"));
    try accepts("const LAST: int = 2\n\n" ++ comptime main("    mut xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[LAST])\n"));
    try accepts(main("    mut s = S(a=[1], b=[2])\n    mut o = S(a=[3], b=[4])\n    records(mut s, mut o)\n"));
}

// spec: MUT-EXCLUSIVE-2
test "Core alone enforces keyword indirect and nested argument exclusivity" {
    try refuses(main("    mut xs = [[1], [2], [3]]\n    two(b=mut xs[0], a=mut xs[0])\n"));
    try accepts(main("    mut xs = [[1], [2], [3]]\n    two(b=mut xs[2], a=mut xs[0])\n"));
    try refuses(main("    mut v = [1]\n    mut action = two\n    action(mut v, mut v)\n"));
    try accepts(main("    mut v = [1]\n    mut w = [2]\n    mut action = two\n    action(mut v, mut w)\n"));
    try refuses(main("    mut a = [1, 2]\n    _ = read_one(mut a, a)\n"));
    try refuses(main("    mut p = [1]\n    emit(mut p, make(mut p))\n"));
}

test "Core rejects ancestor overlap in either argument order" {
    try refuses(main("    mut a = [[1, 2], [3]]\n    nested(mut a, mut a[0])\n"));
    try refuses(main("    mut a = [[1, 2], [3]]\n    inner_first(mut a[0], mut a)\n"));
    try refuses(main("    mut xs = [[1], [2]]\n    const i = 1\n    two(b=mut xs[i], a=mut xs[0])\n"));
}

// The aliasing calls guest tests made before MUT-EXCLUSIVE-1, each now rejected;
// the guest tests pass disjoint places instead (tests/lang/mut_argument_places.selka,
// rc_mut_aliases.selka, rc_mut_list_aliases.selka, mut_record_call_window.selka,
// rc_caller_field_reads.selka, migrated/effects_case_6.selka and
// tests/value_semantics/{calls,field_return,index_return}.selka).
// spec-case: MUT-EXCLUSIVE-1
test "the aliasing calls converted guest tests used to make are rejected" {
    const dictionaries = "func write_twice(mut first: dict[int, int], mut second: dict[int, int]) -> int:\n    first[1] = 13\n    second[1] = 17\n    return first[1]\n\n";
    try refusesProgram(dictionaries ++ "func main() -> int:\n    mut original = {0: {1: 7}}\n    return write_twice(mut original[0], mut original[0])\n");
    try refusesProgram(dictionaries ++ "func main() -> int:\n    mut original = {1: 7}\n    mut action = write_twice\n    return action(mut original, mut original)\n");
    const frames = "record Frame:\n    rows: int[][]\n    n: int\n\nfunc interval(mut frame: Frame, mut other: Frame) -> int:\n    frame.n = frame.n + 1\n    other.rows = [[7]]\n    return 0\n\n" ++
        "func contained(mut frame: Frame, mut rows: int[][]) -> int:\n    frame.n = frame.n + 1\n    append(mut rows, [1])\n    return 0\n\n";
    try refusesProgram(frames ++ "func main() -> int:\n    mut frame = Frame(rows=[[1, 2], [3]], n=0)\n    return interval(mut frame, mut frame)\n");
    try refusesProgram(frames ++ "func main() -> int:\n    mut frame = Frame(rows=[[1, 2], [3]], n=0)\n    return contained(mut frame, mut frame.rows)\n");
    const lists = "func write_both(mut x: int[], mut y: int[]) -> Unit:\n    x[0] = 1\n    y[0] = 2\n\nfunc use(mut values: int[]) -> Unit:\n    write_both(mut values, mut values)\n\n";
    try refusesProgram(lists ++ "func main() -> int:\n    mut values = [0, 0]\n    use(mut values)\n    return values[0]\n");
    const both = "func touch_both(mut first: int[], mut second: int[], source: int[]) -> int:\n    append(mut first, len(source))\n    append(mut second, len(source))\n    return len(source)\n\n";
    try refusesProgram(both ++ "func main() -> int:\n    mut items = [1, 2]\n    return touch_both(mut items, mut items, items)\n");
}

const accepted_code = "accepted";

/// An embedded two-module project: `main` plus the `library.lists` module.
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) compiler.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return compiler.embedded_project.read(allocator, self.entries, path, limit);
    }
};

const library =
    \\
    \\
    \\public func two(mut a: int[], mut b: int[]) -> Unit:
    \\    append(mut a, 1)
    \\    append(mut b, 2)
    \\
;

/// The first diagnostic code of the project whose `main` calls `call`, and the
/// source text it points at; "accepted" and "" when the project checks clean.
fn qualified(allocator: std.mem.Allocator, comptime call: []const u8) ![2][]const u8 {
    const main_source = "import library.lists as lists\n\n\nfunc main() -> int:\n    mut v = [1]\n    mut w = [2]\n    " ++ call ++ "\n    return len(v) + len(w)\n";
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main_source }, .{ .path = "library/lists.selka", .bytes = library } } };
    var project = compiler.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try compiler.interfaces.build(&project);
    var compilation = try compiler.project_compile.Compilation.init(&index);
    if (compilation.check()) |_| return .{ accepted_code, "" } else |err| if (err != error.SourceError) return err;
    const first = compilation.diagnostics.items.items[0];
    return .{ first.code, try allocator.dupe(u8, compilation.src.text(first.span)) };
}

/// Exercise the same module-qualified call through the complete ownership check.
fn qualifiedRefuses(a: std.mem.Allocator) !void {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.createDirPath(t.io, "library");
    try directory.dir.writeFile(t.io, .{ .sub_path = "library/lists.selka", .data = library });
    try directory.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "import library.lists as lists\n\nfunc main() -> int:\n    mut v = [1]\n    lists.two(mut v, mut v)\n    return 0\n" });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "main.selka" });
    const outcome = try std.process.run(a, t.io, .{ .argv = &.{ @import("test_paths").corePath(), "check", path, "--no-cache", "--diagnostics=json" } });
    try t.expect(outcome.term == .exited and outcome.term.exited == 1);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "E_SINGLE_OWNER_OVERLAP") != null);
}

// spec-case: MUT-EXCLUSIVE-2
test "frontend defers module-qualified argument overlap to Core" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const candidate = try qualified(arena.allocator(), "lists.two(mut v, mut v)");
    try t.expectEqualStrings(accepted_code, candidate[0]);
    try t.expectEqualStrings("", candidate[1]);
    try qualifiedRefuses(arena.allocator());
    const legal = try qualified(arena.allocator(), "lists.two(mut v, mut w)");
    try t.expectEqualStrings(accepted_code, legal[0]);
}

// spec: MUT-OVERLAP-RECEIVER-1
test "frontend defers receiver index and exchange overlap to Core" {
    try refuses(main("    mut p = [1]\n    p[make(mut p)] = 9\n"));
    try accepts(main("    mut p = [1]\n    p[0] = make(mut p)\n"));
    // The index is evaluated while its receiver is held; the write value is
    // staged before the receiver and is accepted (O0 receiver_rhs disagreement).
    try refusesWithLists(main("    mut p = [1]\n    _ = lists.exchange(mut p, make(mut p), 5)\n"));
    try accepts(main("    mut p = [1]\n    mut q = [2]\n    p[0] = make(mut q)\n"));
    try accepts(main("    mut p = [1]\n    mut value = make(mut p)\n    p[0] = value\n"));
    try accepts(main("    mut p = [1]\n    append(mut p, len(p))\n"));
    try accepts(main("    mut s = S(a=[1], b=[2])\n    s.a[0] = make(mut s.b)\n"));
}

// spec-case: MUT-OVERLAP-RECEIVER-1
test "Core receiver overlap covers enclosing records and nested constant paths" {
    try refusesWithLists(main("    mut r = R(rows=[[1]], n=0)\n    _ = lists.exchange(mut r.rows[0], make(mut r.rows[0]), 5)\n"));
    const points = "record Point:\n    x: int\n\nfunc save(mut points: Point[]) -> int:\n    append(mut points, Point(x=1))\n    return 0\n\n" ++
        "func main() -> int:\n    mut points = [Point(x=0)]\n    points[save(mut points)].x = 13\n    return 0\n";
    try refusesProgram(points);
    try refusesWithLists(main("    mut r = R(rows=[[1], [2]], n=0)\n    _ = lists.exchange(mut r.rows[0], make(mut r.rows[1]), 5)\n"));
}

// spec-case: MUT-OVERLAP-RECEIVER-1
test "frontend defers mapping set keyword and indirect receiver overlap" {
    const set = "import sets\n\nfunc select(mut flags: set[int]) -> int:\n    sets.add(mut flags, 2)\n    return 3\n\n";
    try refusesProgram(set ++ "func main() -> int:\n    mut flags = {1}\n    sets.add(mut flags, select(mut flags))\n    return len(flags)\n");
    try refusesProgram(set ++ "func main() -> int:\n    mut flags = {1}\n    sets.discard(mut flags, select(mut flags))\n    return len(flags)\n");
    const dict = "func select(mut values: dict[int, int]) -> int:\n    values[2] = 3\n    return 0\n\n";
    try refusesProgram(dict ++ "func main() -> int:\n    mut values = {0: 1}\n    values[select(mut values)] = 9\n    return len(values)\n");
    try accepts(main("    mut p = [1]\n    p[0] = make(p=mut p)\n"));
    try refuses(main("    mut p = [1]\n    mut action = make\n    p[action(mut p)] = 9\n"));
}

// spec-case: PY-ARRAY-MUT-1
test "whole fixed array mut parameter rebinding updates caller storage" {
    var compilation = try compiler.Compilation.init(t.allocator, "mut-fixed-rebind.selka", "func reset(mut values: FixedArray[int, 2]) -> Unit:\n    values = FixedArray[int, 2]([3, 4])\n\n" ++
        "func main() -> int:\n    mut values = FixedArray[int, 2]([1, 2])\n    reset(mut values)\n    return values[0]\n");
    defer compilation.deinit();
    const result = try @import("native_execute.zig").run(&compilation);
    try t.expectEqual(@as(i64, 3), result.value);
}

test "take refuses a place that a live borrow still holds" {
    const source =
        \\record Holder:
        \\    items: int[]
        \\
        \\
        \\func main() -> int:
        \\    mut h = Holder(items=[1])
        \\    const view = h.items
        \\    _ = take(mut h.items)
        \\    return len(view)
    ;
    try transition.refuses(t.allocator, source, "E_SINGLE_OWNER_OVERLAP");
}

test "exchange moves a named replacement in with own, and one that is the place itself is refused" {
    const holder = "record Holder:\n    items: int[]\n\n\n";
    // B2: a named managed replacement moves in, so it needs `own`, as `append(mut xs, own value)` does.
    try transition.refuses(t.allocator, holder ++ "func main() -> int:\n    mut h = Holder(items=[1])\n    const fresh = [2]\n    _ = exchange(mut h.items, fresh)\n    return len(h.items)\n", "E_OWN_MARKER");
    // B3: the replacement is built before the place is read, so moving the place's own owner leaves nothing to write.
    try transition.refuses(t.allocator, "func main() -> int:\n    mut xs = [1]\n    _ = exchange(mut xs, own xs)\n    return len(xs)\n", "E_SINGLE_OWNER_MOVED");
    try transition.refuses(t.allocator, holder ++ "func main() -> int:\n    mut h = Holder(items=[1])\n    _ = exchange(mut h.items, own h.items)\n    return len(h.items)\n", "E_SINGLE_OWNER_MOVED");
    // B1: a plain parameter is a read-only borrow, so the place it holds cannot be taken.
    try transition.refuses(t.allocator, holder ++ "func drain(h: Holder) -> int[]:\n    return take(mut h.items)\n\n\nfunc main() -> int:\n    return len(drain(Holder(items=[1])))\n", "E_IMMUTABLE");
}

test "an element, element-field or match mut take is refused while a borrow of its container or an iteration holds it" {
    const holder = "record Holder:\n    items: int[]\n\n\n";
    // R2: a live borrow of one element holds the list, so another element cannot be taken while it is used.
    try transition.refuses(t.allocator, "func main() -> int:\n    mut xs = [[1], [2]]\n    const a = xs[0]\n    const got = take(mut xs[1])\n    return len(a) + len(got)\n", "E_SINGLE_OWNER_OVERLAP");
    // R7: a loop over the list borrows it for every iteration.
    try transition.refuses(t.allocator, "func main() -> int:\n    mut xs = [[1], [2]]\n    for x in xs:\n        _ = take(mut xs[0])\n    return 0\n", "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(t.allocator, holder ++ "func main() -> int:\n    mut hs = [Holder(items=[1])]\n    const view = hs[0].items\n    _ = exchange(mut hs[0].items, [2])\n    return len(view)\n", "E_SINGLE_OWNER_OVERLAP");
    // B7: a replacement moved out of another element of the same list is a borrowed element, not an owner.
    try transition.refuses(t.allocator, holder ++ "func main() -> int:\n    mut hs = [Holder(items=[1]), Holder(items=[2])]\n    _ = exchange(mut hs[0].items, own hs[1].items)\n    return 0\n", "E_SINGLE_OWNER_BORROW");
    // B1: an element of a plain parameter is read-only.
    try transition.refuses(t.allocator, "func drain(xs: int[][]) -> int[]:\n    return take(mut xs[0])\n\n\nfunc main() -> int:\n    return len(drain([[1]]))\n", "E_IMMUTABLE");
    // X2: the scrutinee of a running `match mut` arm is held, so the arm cannot exchange it whole.
    try transition.refuses(t.allocator, holder ++ "enum Slot:\n    empty\n    full(value: Holder)\n\n\nfunc main() -> int:\n    mut s = Slot.full(value=Holder(items=[1]))\n    match mut s:\n        case full(value=payload):\n" ++
        "            _ = exchange(mut s, Slot.empty)\n            return len(payload.items)\n        case empty:\n            return 0\n", "E_SINGLE_OWNER_OVERLAP");
    // A record field borrowed by a live const cannot be exchanged whole.
    try transition.refuses(t.allocator, holder ++ "record Outer:\n    holder: Holder\n\n\nfunc main() -> int:\n    mut o = Outer(holder=Holder(items=[1]))\n" ++
        "    const view = o.holder\n    _ = exchange(mut o.holder, Holder(items=[]))\n    return len(view.items)\n", "E_SINGLE_OWNER_OVERLAP");
}

test "lists.extend_own takes its second list: a later use, a borrowed list and the receiver itself are refused" {
    const lists = "import lists\n\n\n";
    // B3: the moved list is unavailable after the call.
    try transition.refuses(t.allocator, lists ++ "func main() -> int:\n    mut xs = [[1]]\n    const ys = [[2]]\n    lists.extend_own(mut xs, own ys)\n    return len(ys)\n", "E_SINGLE_OWNER_MOVED");
    // B2: a named list moves in only with `own`.
    try transition.refuses(t.allocator, lists ++ "func main() -> int:\n    mut xs = [[1]]\n    const ys = [[2]]\n    lists.extend_own(mut xs, ys)\n    return len(xs)\n", "E_OWN_MARKER");
    // A plain parameter is borrowed, so its list cannot be given away.
    try transition.refuses(t.allocator, lists ++ "func grow(mut xs: int[][], ys: int[][]):\n    lists.extend_own(mut xs, own ys)\n\n\nfunc main() -> int:\n    return 0\n", "E_SINGLE_OWNER_BORROW");
    // The receiver cannot also be the list given away.
    try transition.refuses(t.allocator, lists ++ "func main() -> int:\n    mut xs = [[1]]\n    lists.extend_own(mut xs, own xs)\n    return len(xs)\n", "E_SINGLE_OWNER_OVERLAP");
}

test "a consuming loop takes only a list a local or an own parameter owns, and its name is moved from the loop on" {
    const entry = "func main() -> int:\n";
    // B3: the list is moved by the loop, so a use after it or inside its body is a use of a moved value.
    try transition.refuses(t.allocator, entry ++ "    const xs = [[1], [2]]\n    for x in own xs:\n        _ = len(x)\n    return len(xs)\n", "E_SINGLE_OWNER_MOVED");
    try transition.refuses(t.allocator, entry ++ "    const xs = [[1], [2]]\n    mut n = 0\n    for x in own xs:\n        n += len(xs)\n    return n\n", "E_SINGLE_OWNER_MOVED");
    try transition.refuses(t.allocator, entry ++ "    mut xs = [[1], [2]]\n    for x in own xs:\n        append(mut xs, [3])\n    return 0\n", "E_SINGLE_OWNER_MOVED");
    // B6: a list defined outside an enclosing loop is moved on its first iteration.
    try transition.refuses(t.allocator, entry ++ "    const xs = [[1], [2]]\n    mut n = 0\n    for i in range(2):\n        for x in own xs:\n            n += len(x)\n    return n\n", "E_SINGLE_OWNER_LOOP");
    // A `mut` parameter, a borrowed parameter and a field are not lists the loop may take.
    try transition.refuses(t.allocator, "func f(mut xs: int[][]) -> int:\n    mut n = 0\n    for x in own xs:\n        n += len(x)\n    return n\n\n\n" ++ entry ++ "    mut xs = [[1]]\n    return f(mut xs)\n", "E_ITERATION");
    try transition.refuses(t.allocator, "func f(xs: int[][]) -> int:\n    mut n = 0\n    for x in own xs:\n        n += len(x)\n    return n\n\n\n" ++ entry ++ "    return f([[1]])\n", "E_ITERATION");
    try transition.refuses(t.allocator, "record H:\n    items: int[][]\n\n\n" ++ entry ++ "    const h = H(items=[[1]])\n    mut n = 0\n    for x in own h.items:\n        n += len(x)\n    return n\n", "E_ITERATION");
    // F-16: a call's new list is taken as a local's would be; a call whose result is lent by its argument is not, and a
    // call that is not a list, or any other expression, is not a list the loop may take.
    try acceptsProgram("func rows() -> int[][]:\n    return [[1]]\n\n\n" ++ entry ++ "    mut n = 0\n    for x in own rows():\n        n += len(x)\n    return n\n");
    const first = "func first(xss: int[][][]) -> int[][] from xss:\n    return xss[0]\n\n\n";
    try transition.refuses(t.allocator, first ++ entry ++ "    const xss = [[[1]]]\n    mut n = 0\n    for x in own first(xss):\n        n += len(x)\n    return n\n", "E_SINGLE_OWNER_BORROW");
    try transition.refuses(t.allocator, "func count() -> int:\n    return 1\n\n\n" ++ entry ++ "    mut n = 0\n    for x in own count():\n        n += x\n    return n\n", "E_ITERATION");
    try transition.refuses(t.allocator, entry ++ "    const xs = [[1]]\n    mut n = 0\n    for x in own xs[0:1]:\n        n += len(x)\n    return n\n", "E_ITERATION");
    // A const binding of a place borrows it, so `own` cannot take it.
    try transition.refuses(t.allocator, entry ++ "    const xs = [[1], [2]]\n    const alias = xs\n    mut n = 0\n    for x in own alias:\n        n += len(x)\n    return n + len(xs)\n", "E_OWN_MARKER");
    // One name, a list, and an element that moves only with `own`.
    try transition.refuses(t.allocator, entry ++ "    const xs = [[1], [2]]\n    mut n = 0\n    for i, x in own xs:\n        n += len(x)\n    return n\n", "E_ITERATION");
    // Any other collection keeps the ordinary walk, where the marker is refused with its removal repair.
    try transition.refuses(t.allocator, entry ++ "    const d = {\"a\": 1}\n    mut n = 0\n    for k in own d:\n        n += 1\n    return n\n", "E_OWN_MARKER");
    try transition.refuses(t.allocator, entry ++ "    mut keep: int[][] = []\n    const xs = [[1], [2]]\n    for x in own xs:\n        append(mut keep, x)\n    return len(keep)\n", "E_OWN_MARKER");
}

// FX8 (friction F-39): a payload binding of `match own` owns its payload, so the consuming loop takes it as it takes an
// owned local; a binding of a plain match on a local and of `match mut` borrows, and stays refused.
test "a consuming loop takes a payload binding of match own, and not one of a borrowing match" {
    const make = "func make() -> int[][]?:\n    return Some([[1], [2]])\n\n\nenum Slot:\n    full(items: int[][])\n    empty\n\n\n";
    const loop = "        case Some(found):\n            for x in own found:\n                n += len(x)\n        case None:\n            pass\n    return n\n";
    const entry = "func main() -> int:\n    mut n = 0\n";
    try acceptsProgram(make ++ entry ++ "    const listing = make()\n    match own listing:\n" ++ loop);
    try acceptsProgram(make ++ entry ++ "    mut listing = make()\n    match own listing:\n" ++ loop);
    try acceptsProgram(make ++ "func f(own listing: int[][]?) -> int:\n    mut n = 0\n    match own listing:\n" ++ loop ++ "\n\nfunc main() -> int:\n    return f(make())\n");
    // A fielded payload of a call result owns its fields too.
    try acceptsProgram(make ++ entry ++ "    match Slot.full(items=[[1]]):\n        case full(items):\n            for x in own items:\n" ++
        "                n += len(x)\n        case empty:\n            pass\n    return n\n");
    try transition.refuses(t.allocator, make ++ entry ++ "    const listing = make()\n    match listing:\n" ++ loop, "E_ITERATION");
    try transition.refuses(t.allocator, make ++ entry ++ "    mut listing = make()\n    match mut listing:\n" ++ loop, "E_ITERATION");
    // `own` of a borrowed parameter is refused at the match, and the consumed local is moved after it.
    try transition.refuses(t.allocator, make ++ "func f(listing: int[][]?) -> int:\n    mut n = 0\n    match own listing:\n" ++ loop ++ "\n\nfunc main() -> int:\n    return f(make())\n", "E_OWN_MARKER");
    try transition.refuses(t.allocator, make ++ entry ++ "    const listing = make()\n    match own listing:\n" ++ loop[0 .. loop.len - "    return n\n".len] ++
        "    const again = listing\n    _ = again\n    return n\n", "E_SINGLE_OWNER_MOVED");
}

test "a writer's argument may write a field disjoint from the writer's receiver, never the receiver or its owner" {
    const records = "record Block:\n    items: int[] = []\n\n\nrecord E:\n    block: Block = Block()\n    stack: Block[] = []\n\n\nfunc whole(mut e: E) -> Block:\n    return Block()\n\n\n";
    // The argument passes the receiver's owner whole, takes the receiver itself, or reaches an element that may be the receiver.
    try transition.refuses(t.allocator, records ++ "func main() -> int:\n    mut e = E()\n    append(mut e.stack, whole(mut e))\n    return len(e.stack)\n", "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(t.allocator, records ++ "func main() -> int:\n    mut e = E()\n    append(mut e.stack, Block(items=[len(take(mut e.stack))]))\n    return len(e.stack)\n", "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(t.allocator, "func main() -> int:\n    mut xs = [[1], [2]]\n    append(mut xs, exchange(mut xs[0], []))\n    return len(xs)\n", "E_SINGLE_OWNER_OVERLAP");
    // Elements stay refused even at different literal indices: the receiver is read again only across record fields.
    try transition.refuses(t.allocator, "func main() -> int:\n    mut xs = [[1], [2]]\n    append(mut xs[0], len(exchange(mut xs[1], [5])))\n    return len(xs[0])\n", "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(t.allocator, "func f(mut xs: int[][], i: int, j: int) -> int:\n    append(mut xs[i], len(exchange(mut xs[j], [5])))\n    return len(xs[i])\n\n\n" ++
        "func main() -> int:\n    mut xs = [[1], [2]]\n    return f(mut xs, 0, 1)\n", "E_SINGLE_OWNER_OVERLAP");
}
