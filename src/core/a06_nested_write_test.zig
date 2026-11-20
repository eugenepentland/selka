//! Exact nested field writebacks retain their parent ownership and direct cleanup.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const language = @import("selka");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

fn legacySymbols(symbols: []const u8) bool {
    for ([_][]const u8{ "myl_core_retain", "myl_core_release", "myl_core_share", "count_retain", "count_release", "count_is_unique" }) |legacy| {
        if (std.mem.indexOf(u8, symbols, legacy) != null) return true;
    }
    return false;
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC linked symbol audit distinguishes direct destruction from counting" {
    try std.testing.expect(!legacySymbols("0001 T myl_core_drop\n0002 T myl_core_free_owned\n"));
    for ([_][]const u8{ "myl_core_retain_slow", "myl_core_release", "myl_core_share", "count_is_unique", "count_retain", "count_release_shared" }) |symbol| {
        try std.testing.expect(legacySymbols(symbol));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC a noalloc borrowed text extremum cannot become an independent return" {
    try frontendRefuses(std.testing.allocator,
        // migrate-embedded: skip intentional original noalloc retirement diagnostic
        \\func least(words: str[]) -> str noalloc:
        \\    return min(words)
        \\func main() -> int:
        \\    return 0
    , "E_EFFECTS_REMOVED");
    // R3b: the refusal this case pinned is an accepted borrow now (see borrowed_return_test.zig).
}

const records =
    \\record Inner:
    \\    scalar: int
    \\    text: str
    \\record Outer:
    \\    left: Inner
    \\    right: Inner
    \\
;

const program = records ++
    \\func sample(early: bool) -> int:
    \\    mut owner = Outer(left=Inner(scalar=2, text="left-" + str(1)), right=Inner(scalar=4, text="right-" + str(2)))
    \\    owner.left.scalar += 3
    \\    owner.right.scalar = 9
    \\    const snapshot = copy(owner)
    \\    owner.left.scalar = 17
    \\    owner.right.text = "changed-" + str(3)
    \\    if early:
    \\        return snapshot.left.scalar + strings.char_count(snapshot.right.text)
    \\    owner = Outer(left=Inner(scalar=0, text="replacement-" + str(4)), right=Inner(scalar=0, text="replacement-" + str(5)))
    \\    return snapshot.left.scalar * 100 + snapshot.right.scalar * 10 + strings.char_count(snapshot.left.text) + strings.char_count(snapshot.right.text)
    \\func main(out: Stream) -> int:
    \\    print(out, sample(False), sample(True))
    \\    return 0
;

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    return refusesRule(parent, source, code, null);
}

fn refusesRule(parent: std.mem.Allocator, source: []const u8, code: []const u8, rule: ?language.ownership_rules.Rule) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(a, try support.checkedProgram(a, source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (rule) |expected| try std.testing.expectEqual(expected, failure.rule.?);
}

fn frontendRefuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), source);
    try std.testing.expect(!checked.passed);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC nested writeback rejects another field another base and partial moves" {
    // Matching the owner alone would accidentally admit the wrong field.
    try refusesRule(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    owner.left = replace(owner.right, scalar=7)
        \\    return owner.left.scalar
    , "E_OWN_MARKER", .B2);
    // Matching the field index alone would accidentally admit another owner.
    try refusesRule(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    mut other = Outer(left=Inner(scalar=3, text="other"), right=Inner(scalar=5, text="other-right"))
        \\    owner.left = replace(other.left, scalar=7)
        \\    return owner.left.scalar
    , "E_OWN_MARKER", .B2);
    // R3b: returning a field of a record parameter is an accepted borrow (tests/lang/borrowed_results.selka).
    try refuses(std.testing.allocator, records ++
        \\func observe(inner: Inner, mut owner: Outer) -> int:
        \\    owner.left.scalar = 7
        \\    return inner.scalar
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    return observe(owner.left, mut owner)
    , "E_SINGLE_OWNER_OVERLAP");
}

test "O4 nested writeback transfers another carrier only with own and refuses carrier reuse" {
    const transferred = records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    mut other = Outer(left=Inner(scalar=3, text="other"), right=Inner(scalar=5, text="other-right"))
        \\    owner.left = replace(own other.left, scalar=7)
        \\    return owner.left.scalar
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    _ = try support.buildSource(arena.allocator(), transferred, &refusal);
    try refusesRule(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    mut other = Outer(left=Inner(scalar=3, text="other"), right=Inner(scalar=5, text="other-right"))
        \\    owner.left = replace(own other.left, scalar=7)
        \\    return owner.left.scalar + other.right.scalar
    , "E_SINGLE_OWNER_MOVED", .B3);
    try refusesRule(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    owner.left = replace(own owner.right, scalar=7)
        \\    return owner.left.scalar
    , "E_SINGLE_OWNER_MOVED", .B3);
}

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC nested writeback keeps snapshots and directly cleans early returns" {
    try counted(std.testing.allocator, program, "603 12\n");
}

const CountedExpectation = struct { stdout: []const u8, trap: ?[]const u8 = null };

fn counted(parent: std.mem.Allocator, guest_source: []const u8, expected: []const u8) !void {
    try countedOutcome(parent, guest_source, .{ .stdout = expected });
}

fn countedOutcome(parent: std.mem.Allocator, guest_source: []const u8, expected: CountedExpectation) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(a, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "nested.selka", .data = guest_source });
    const source = try std.fs.path.join(a, &.{ root, "nested.selka" });
    const modes = [_][]const []const u8{
        &.{ "--release", "--verify-facts" },
    };
    for (modes, 0..) |flags, index| {
        try support.requireReleaseArgs(flags);
        const binary = try std.fmt.allocPrint(a, "{s}/nested-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()), "--counters", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("nested writeback build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
        var environment = std.process.Environ.Map.init(a);
        try environment.put("SELKA_COUNTERS", path);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (expected.trap) |code| {
            try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
            try std.testing.expectEqualStrings(expected.stdout, ran.stdout);
            try std.testing.expect(std.mem.indexOf(u8, ran.stderr, code) != null);
            continue;
        }
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings(expected.stdout, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20));
        const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "totals", "live_bytes_at_exit" }));
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases" }) |name| {
            try std.testing.expect(counts.object.get("totals").?.object.get(name) == null);
        }
        for ([_][]const u8{ "retain", "release", "release_unique", "unique_test" }) |name| {
            try std.testing.expect(counts.object.get("kinds").?.object.get(name) == null);
        }
        try std.testing.expect(field(counts, &.{ "totals", "allocs" }) > 0);
        try std.testing.expect(field(counts, &.{ "totals", "frees" }) > 0);
        const llvm = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm_path, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(llvm));
        const symbols = try std.process.run(a, std.testing.io, .{ .argv = &.{ "nm", binary } });
        try std.testing.expect(symbols.term == .exited and symbols.term.exited == 0);
        try std.testing.expect(!legacySymbols(symbols.stdout));
    }
}

const slot_records =
    \\record Cell:
    \\    value: int
    \\    text: str
    \\record Row:
    \\    inner: Cell
    \\    cells: FixedArray[Cell, 2]
    \\
;

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec: NEW-CORE-TAKE-READS-1
test "zero RC fixed array writeback captures a dynamic signed index once" {
    const historical = slot_records ++
        // migrate-embedded: skip intentional runtime-computed negative-index source
        \\func select_last(mut calls: int) -> int:
        \\    calls += 1
        \\    return -1
        \\func change(mut cells: FixedArray[Cell, 2], index: int):
        \\    cells[index].value = 9
        \\func main(out: Stream) -> int:
        \\    mut calls = 0
        \\    mut cells = FixedArray[Cell, 2]([Cell(value=1, text="left-" + str(1)), Cell(value=2, text="right-" + str(2))])
        \\    const saved = copy(cells)
        \\    cells[select_last(mut calls)].value = 7
        \\    change(mut cells, -2)
        \\    print(out, calls, cells[0].value, cells[1].value, saved[0].value, saved[1].value, saved[1].text)
        \\    return 0
    ;
    try countedOutcome(std.testing.allocator, historical, .{ .stdout = "", .trap = "R_LIST_BOUNDS" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const positive_last = try std.mem.replaceOwned(u8, arena.allocator(), historical, "return -1", "return 1");
    const modern = try std.mem.replaceOwned(u8, arena.allocator(), positive_last, "change(mut cells, -2)", "change(mut cells, 0)");
    // The modern witness retains the copied snapshot, one select_last call and all zero-RC counters.
    try counted(arena.allocator(), modern, "1 9 7 1 2 right-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC historical duplicated tree and overlapping captured mutation refuse" {
    try refuses(std.testing.allocator,
        \\enum Tree:
        \\    leaf(value: float)
        \\    branch(left: Tree, right: Tree)
        \\func main() -> int:
        \\    mut tree = Tree.leaf(value=0.0)
        \\    for _ in range(40):
        \\        tree = Tree.branch(left=own tree, right=own tree)
        \\    return 0
    , "E_SINGLE_OWNER_MOVED");
    try negativeIndexThenOverlap(std.testing.allocator,
        // migrate-embedded: skip intentional removal and ownership overlap source
        \\record Cursor:
        \\    rows: int[][]
        \\    ticks: int
        \\func tick(mut cursor: Cursor) -> int:
        \\    cursor.ticks += 1
        \\    return 0
        \\func add(mut row: int[], ignored: int):
        \\    append(mut row, 9)
        \\func main() -> int:
        \\    mut cursor = Cursor(rows=[[1], [2]], ticks=0)
        \\    add(mut cursor.rows[-1], tick(mut cursor))
        \\    return cursor.ticks
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC list slot nested writeback preserves exact owner and index" {
    try refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one"), Inner(scalar=2, text="two")]
        \\    rows[0] = replace(rows[1], scalar=7)
        \\    return rows[0].scalar
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one")]
        \\    mut other = [Inner(scalar=2, text="two")]
        \\    rows[0] = replace(other[0], scalar=7)
        \\    return rows[0].scalar
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator, "import lists\n\n" ++ records ++
        \\func change(mut rows: Inner[]) -> int:
        \\    lists.clear(mut rows)
        \\    return 7
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one")]
        \\    rows[0] = replace(rows[0], scalar=change(mut rows))
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
    // replace first needs an owned base, so the previous element read fails B7
    // before change runs. An augmented field write captures the exact receiver
    // and reaches R2 when the RHS clears that receiver's collection.
    try refuses(std.testing.allocator, "import lists\n\n" ++ records ++
        \\func change(mut rows: Inner[]) -> int:
        \\    lists.clear(mut rows)
        \\    return 7
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one")]
        \\    rows[0].scalar += change(mut rows)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try counted(std.testing.allocator, "import lists\n\n" ++ slot_records ++
        \\func main(out: Stream) -> int:
        \\    mut rows = [Row(inner=Cell(value=1, text="inner-" + str(1)), cells=FixedArray[Cell, 2]([Cell(value=2, text="left-" + str(2)), Cell(value=3, text="right-" + str(3))]))]
        \\    const saved = copy(rows)
        \\    rows[0].inner.value = 7
        \\    rows[0].inner.text = "changed-" + str(4)
        \\    rows[0].cells[1].value = 9
        \\    rows[0].cells[0].text = "new-" + str(5)
        \\    print(out, rows[0].inner.value, rows[0].cells[1].value, saved[0].inner.value, saved[0].cells[1].value, saved[0].cells[0].text)
        \\    lists.clear(mut rows)
        \\    print(out, saved[0].inner.text)
        \\    return 0
    , "7 9 1 3 left-2\ninner-1\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC explicit tuple copy owns every managed child" {
    try counted(std.testing.allocator,
        \\record ManagedPair:
        \\    values: int[]
        \\    text: str
        \\func clone(pair: ManagedPair) -> ManagedPair:
        \\    return copy(pair)
        \\func main(out: Stream) -> int:
        \\    mut owner = ManagedPair(values=[2, 3], text="label-" + str(4))
        \\    const copied = clone(owner)
        \\    append(mut owner.values, 9)
        \\    owner.text = "changed-" + str(5)
        \\    print(out, copied.values == [2, 3], owner.values == [2, 3, 9], copied.text, owner.text)
        \\    return 0
    , "True True label-4 changed-5\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC migrated traversal originals still reject invalidation and retained escape" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    mut total = 0
        \\    for value in items:
        \\        total += value
        \\        items[1] = 9
        \\    return total
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut values = {1: 10, 2: 20}
        \\    for key in values:
        \\        values[key] = values[key] + 1
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut items = [1]
        \\    for value in items:
        \\        append(mut items, value + 1)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try frontendRefuses(std.testing.allocator,
        // migrate-embedded: skip original retained-view spelling refusal witness
        \\func retained() -> bytes:
        \\    const source = b"prefix-data-suffix" + b"!"
        \\    return source.view(7, 11)
        \\func main() -> int:
        \\    return len(retained())
    , "E_BORROW_VIEWS_REMOVED");
}

const snapshot_window_prefix =
    \\record Machine:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    stack: int[]
    \\    top: int
    \\
    \\record Interp:
    \\    m: Machine
    \\    returned: int
    \\    depth: int
    \\
    \\func take_pop(mut m: Machine) -> int:
    \\    m.top = m.top - 1
    \\    return m.stack[m.top]
    \\
    \\func snapshot_between(mut it: Interp) -> int:
    \\    mut wb = copy(it.m)
    \\
;

const snapshot_window_suffix =
    \\    mut keep = copy(it)
    \\    it.returned = take_pop(mut wb)
    \\    it.m = own wb
    \\    return keep.m.top * 100 + keep.depth * 10 + it.m.top
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut it = Interp(m=Machine(a=0, b=0, c=0, stack=[4, 5, 6, 7, 8, 9], top=6), returned=0, depth=0)
    \\    print(out, snapshot_between(mut it), it.returned, it.m.top, it.depth)
    \\    return 0
;

// spec-case: NEW-CORE-CE2-EFFECTS-2
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC whole parent snapshot survives sibling update before child writeback" {
    // A sibling write creates a newer parent SSA value. Its projected child
    // still contains the original bytes needed by the whole-parent copy.
    try counted(std.testing.allocator, snapshot_window_prefix ++
        "    it.depth = it.depth + 1\n" ++ snapshot_window_suffix, "615 9 5 1\n");
    // The same ownership window without that SSA version transition is a
    // control: both snapshots must stay independent and clean up exactly once.
    try counted(std.testing.allocator, snapshot_window_prefix ++ snapshot_window_suffix, "605 9 5 0\n");
}

// spec-case: NEW-CORE-CE2-EFFECTS-2
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC snapshot child lifetime survives a sibling update phi" {
    try counted(std.testing.allocator,
        \\record Machine:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    stack: int[]
        \\    top: int
        \\
        \\record Interp:
        \\    m: Machine
        \\    returned: int
        \\    depth: int
        \\
        \\func take_pop(mut m: Machine) -> int:
        \\    m.top = m.top - 1
        \\    return m.stack[m.top]
        \\
        \\func snapshot_between(mut it: Interp, increase: bool) -> int:
        \\    mut wb = copy(it.m)
        \\    if increase:
        \\        it.depth = it.depth + 1
        \\    else:
        \\        it.depth = it.depth + 2
        \\    mut keep = copy(it)
        \\    it.returned = take_pop(mut wb)
        \\    it.m = own wb
        \\    return keep.m.top * 100 + keep.depth * 10 + it.m.top
        \\
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    mut left = Interp(m=Machine(a=0, b=0, c=0, stack=[4, 5, 6, 7, 8, 9], top=6), returned=0, depth=0)
        \\    mut right = copy(left)
        \\    const increase = len(args) != 0
        \\    print(out, snapshot_between(mut left, increase), snapshot_between(mut right, not increase), left.depth, right.depth)
        \\    return 0
    , "625 615 2 1\n");
}

/// Keep both historical frontend removal and modern ownership rejection executable.
fn negativeIndexThenOverlap(parent: std.mem.Allocator, original: []const u8, code: []const u8) !void {
    try frontendRefuses(parent, original, "E_NEGATIVE_INDEX_REMOVED");
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const modern = try std.mem.replaceOwned(u8, arena.allocator(), original, "cursor.rows[-1]", "cursor.rows[len(cursor.rows) - 1]");
    try refuses(arena.allocator(), modern, code);
}
