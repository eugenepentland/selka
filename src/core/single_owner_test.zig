//! Executable source contracts for the opt-in single-owner experiment.
const std = @import("std");
const report = std.debug.print;
const language = @import("mylang");
const unique = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "single-owner.my", source);
    try unit.check();
    return unit.program.?;
}

fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(a, try checked(a, source), &failure));
    if (!std.mem.eql(u8, code, failure.code)) report("unexpected refusal: {s} at {d}\n", .{ failure.message, failure.span.start });
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.span.end >= failure.span.start);
    try std.testing.expect(failure.message.len != 0);
}

// spec: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects use after assignment and container insertion moves" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    const ys = xs
        \\    return len(xs) + len(ys)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    const rows = [xs]
        \\    return len(xs) + len(rows)
    , "E_SINGLE_OWNER_MOVED");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects retaining and returning borrowed parameters or fields" {
    try refuses(std.testing.allocator,
        \\func keep(xs: int[]) -> int[]:
        \\    return xs
        \\func main() -> int:
        \\    return len(keep([1]))
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func change(xs: int[]) -> int:
        \\    mut ys = xs
        \\    ys.append(2)
        \\    return len(ys)
        \\func main() -> int:
        \\    return change([1])
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record Batch:
        \\    items: int[]
        \\func field(b: Batch) -> int[]:
        \\    return b.items
        \\func main() -> int:
        \\    return len(field(Batch(items=[1])))
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects read and mut overlap in direct and nested calls" {
    try refuses(std.testing.allocator,
        \\func both(xs: int[], mut ys: int[]) -> int:
        \\    ys.append(3)
        \\    return len(xs)
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return both(xs, mut xs)
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func change(mut xs: int[]) -> int:
        \\    xs.append(3)
        \\    return 0
        \\func read(xs: int[], n: int) -> int:
        \\    return len(xs) + n
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return read(xs, change(mut xs))
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner joins branches and rejects moves across loop backedges" {
    try refuses(std.testing.allocator,
        \\func probe(flag: bool) -> int:
        \\    const xs = [1]
        \\    if flag:
        \\        const ys = xs
        \\        assert len(ys) == 1
        \\    return len(xs)
        \\func main() -> int:
        \\    return probe(True)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1]
        \\    for i in range(3):
        \\        const ys = xs
        \\        assert len(ys) == 1
        \\    return 0
    , "E_SINGLE_OWNER_LOOP");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner iteration borrows prevent mutating the iterated root" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    for x in xs:
        \\        xs.append(x)
        \\    return len(xs)
    , "E_SINGLE_OWNER_OVERLAP");
}

const sample =
    \\record Batch:
    \\    items: int[]
    \\    factor: int
    \\func fill(mut xs: int[], n: int):
    \\    for i in range(n):
    \\        xs.append(i + 1)
    \\func sum(xs: int[]) -> int:
    \\    mut total = 0
    \\    for x in xs:
    \\        total += x
    \\    return total
    \\func recursive(xs: int[], i: int) -> int:
    \\    if i == len(xs):
    \\        return 0
    \\    return xs[i] + recursive(xs, i + 1)
    \\func copied(xs: int[]) -> int[]:
    \\    return xs.copy()
    \\func make(n: int) -> Batch:
    \\    mut xs: int[] = []
    \\    fill(mut xs, n)
    \\    return Batch(items=xs, factor=n)
    \\func score(b: Batch) -> int:
    \\    return sum(b.items) * b.factor
    \\func main(out: Stream) -> int:
    \\    const batch = make(4)
    \\    mut xs = copied(batch.items)
    \\    fill(mut xs, 2)
    \\    const ys = xs
    \\    out.print(score(batch), sum(ys), recursive(ys, 0))
    \\    return 0
;

fn executes(backing: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: unique.Failure = .{};
    unique.check(a, program, &failure) catch |err| {
        report("single owner check: {s} at {d}\n", .{ failure.message, failure.span.start });
        return err;
    };
    inline for (.{ false, true }) |release| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = program, .single_owner = true }, &refusal);
        const result = if (release) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        unique.verifyLowered(&module, &failure) catch |err| {
            report("single owner lowering: {s} at {d}\n", .{ failure.message, failure.span.start });
            report("{s}\n", .{try @import("print.zig").module(a, &module)});
            return err;
        };
        try support.verified(a, &module, result.plans);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = release, .verify = release, .analysis = support.analysis(&result) });
        if (run.status != 0) report("single owner execution release={any}:\n{s}{s}\n", .{ release, run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
    }
}

// spec: NEW-CORE-SINGLE-OWNER-2
test "single owner explicit copies fresh returns mut helpers recursion and records execute" {
    try executes(std.testing.allocator, sample, "40 13 13\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested explicit copies preserve independent child lists" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    const row = [1, 2]
        \\    const rows = [row]
        \\    mut copied = rows.copy()
        \\    copied[0].append(3)
        \\    out.print(len(rows[0]), len(copied[0]))
        \\    return 0
    , "2 3\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner accepts reinitialization after a move and terminating branches" {
    try executes(std.testing.allocator,
        \\func probe(flag: bool) -> int:
        \\    mut xs = [1]
        \\    if flag:
        \\        const ys = xs
        \\        return len(ys)
        \\    const ys = xs
        \\    xs = [3, 4]
        \\    return len(xs) + len(ys)
        \\func main(out: Stream) -> int:
        \\    out.print(probe(False), probe(True))
        \\    return 0
    , "3 1\n");
}

// spec: NEW-CORE-SINGLE-OWNER-3
test "single owner CLI mode is opt in and preserves normal parsing" {
    const args = @import("cli_args.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var failure: args.Failure = .usage;
    const normal = try args.parse(arena.allocator(), .build, &.{ "app.my", "-o", "app" }, "zig", &failure);
    const unique_mode = try args.parse(arena.allocator(), .build, &.{ "app.my", "-o", "app", "--experimental-single-owner" }, "zig", &failure);
    try std.testing.expect(!normal.build.show.codegen.single_owner);
    try std.testing.expect(unique_mode.build.show.codegen.single_owner);
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects moves in repeated conditions and overlapping builtin arguments" {
    try refuses(std.testing.allocator,
        \\record Box:
        \\    values: int[]
        \\func more(box: Box) -> bool:
        \\    return len(box.values) > 0
        \\func main() -> int:
        \\    const xs = [1]
        \\    while more(Box(values=xs)):
        \\        pass
        \\    return 0
    , "E_SINGLE_OWNER_LOOP");
    try refuses(std.testing.allocator,
        \\func change(mut xs: int[]) -> int:
        \\    xs.append(4)
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    mut xs = [1]
        \\    out.print(xs, change(mut xs))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func change(mut xs: int[]) -> int:
        \\    xs.append(4)
        \\    return 0
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return xs[change(mut xs)]
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner record mutation and nested record copies execute" {
    try executes(std.testing.allocator,
        \\record Row:
        \\    values: int[]
        \\    factor: int
        \\func change(mut row: Row):
        \\    row.values.append(4)
        \\    row.factor += 1
        \\func main(out: Stream) -> int:
        \\    mut row = Row(values=[1, 2], factor=3)
        \\    change(mut row)
        \\    const rows = [row]
        \\    mut copied = rows.copy()
        \\    copied[0].values.append(7)
        \\    out.print(len(rows[0].values), len(copied[0].values), rows[0].factor)
        \\    return 0
    , "3 4 4\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner pop transfers child storage and branch cleanup remains exact" {
    try executes(std.testing.allocator,
        \\func probe(flag: bool) -> int:
        \\    mut rows = [[1, 2], [3]]
        \\    mut last = rows.pop()
        \\    last.append(4)
        \\    if flag:
        \\        return len(rows[0]) + len(last)
        \\    return len(last)
        \\func main(out: Stream) -> int:
        \\    out.print(probe(True), probe(False))
        \\    return 0
    , "4 2\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner validation errors survive rendering and unsupported forms fail closed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func main() -> int:
        \\    const xs = [1]
        \\    const ys = xs
        \\    return len(xs) + len(ys)
    ;
    const program = try checked(a, source);
    const src = try language.source.Source.init(a, "single-owner.my", source);
    var diagnostics: std.ArrayList(u8) = .empty;
    try std.testing.expect(!try unique.validate(a, program, src, .json, &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items, "E_SINGLE_OWNER_MOVED") != null);
    var empty: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&empty);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.OutOfMemory, unique.check(fixed.allocator(), program, &failure));
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values: dict[int, int] = {1: 2}
        \\    return len(values)
    , "E_SINGLE_OWNER_UNSUPPORTED");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested cleanup handles wide records and shared immutable leaves" {
    try executes(std.testing.allocator,
        \\record Row:
        \\    first: int[]
        \\    second: int[][]
        \\    name: str
        \\    a: int
        \\    b: int
        \\func probe(n: int, early: bool) -> int:
        \\    const name = str(n)
        \\    mut rows = [Row(first=[n], second=[[n + 1], []], name=name, a=1, b=2)]
        \\    const saved = rows.copy()
        \\    rows = [Row(first=[], second=[], name=name, a=3, b=4)]
        \\    if early:
        \\        return saved[0].first[0] + len(saved[0].name)
        \\    rows.clear()
        \\    return saved[0].second[0][0] + len(name)
        \\func main(out: Stream) -> int:
        \\    out.print(probe(123, True), probe(123, False))
        \\    return 0
    , "126 127\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested cleanup traverses fixed arrays containing lists" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    const pair = FixedArray[int[], 2]([[1, 2], [3]])
        \\    mut rows = [pair]
        \\    out.print(rows[0][0][1], rows[0][1][0])
        \\    rows.clear()
        \\    return 0
    , "2 3\n");
}

// spec: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshots preserve independent nested writes on both versions" {
    try executes(std.testing.allocator,
        \\func grow(mut rows: int[][]):
        \\    rows[0].append(4)
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3]]
        \\    mut saved = rows.snapshot()
        \\    grow(mut rows)
        \\    saved[1].append(5)
        \\    out.print(len(rows[0]), len(saved[0]), len(rows[1]), len(saved[1]))
        \\    return 0
    , "3 2 1 2\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshots can escape borrowed fields and callback parameters" {
    try executes(std.testing.allocator,
        \\record Packet:
        \\    values: int[]
        \\func snapshot_values(packet: Packet) -> int[]:
        \\    return packet.values.snapshot()
        \\func keep(values: int[]) -> int[]:
        \\    return values.snapshot()
        \\func invoke(f: func(int[]) -> int[], values: int[]) -> int[]:
        \\    return f(values)
        \\func main(out: Stream) -> int:
        \\    const packet = Packet(values=[1, 2])
        \\    mut extracted = snapshot_values(packet)
        \\    extracted.append(3)
        \\    mut saved = invoke(keep, extracted)
        \\    saved.append(4)
        \\    out.print(len(packet.values), len(extracted), len(saved))
        \\    return 0
    , "2 3 4\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshot pop and clear preserve the original and transfer the child" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1], [2]]
        \\    const saved = rows.snapshot()
        \\    mut popped = rows.pop()
        \\    popped.append(3)
        \\    rows.clear()
        \\    out.print(len(saved), len(saved[1]), len(popped), len(rows))
        \\    return 0
    , "2 1 2 0\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshot families include record array children but leave other types exclusive" {
    const ir = @import("ir.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .single_owner = true };
    const ints = try module.intern(a, .{ .list = .i64 });
    const floats = try module.intern(a, .{ .list = .f64 });
    const pair = try module.intern(a, .{ .array = .{ .elem = ints, .n = 2 } });
    const row = try module.intern(a, .{ .record = &.{ pair, .str } });
    const rows = try module.intern(a, .{ .list = row });
    try std.testing.expect(module.exclusiveList(ints));
    try unique.enableSnapshots(a, &module, rows);
    try unique.enableSnapshots(a, &module, rows);
    try std.testing.expectEqual(@as(usize, 2), module.shared_lists.items.len);
    try std.testing.expect(!module.exclusiveList(rows));
    try std.testing.expect(!module.exclusiveList(ints));
    try std.testing.expect(module.exclusiveList(floats));
    try std.testing.expect(!unique.containsExclusiveList(&module, row));
    const mixed = try module.intern(a, .{ .record = &.{ ints, floats } });
    try std.testing.expect(unique.containsExclusiveList(&module, mixed));
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshots keep use after move and implicit borrow escapes invalid" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1]
        \\    const saved = xs.snapshot()
        \\    const moved = xs
        \\    return len(xs) + len(saved) + len(moved)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func bad(xs: int[]) -> int[]:
        \\    const saved = xs.snapshot()
        \\    return xs
        \\func main() -> int:
        \\    return len(bad([1]))
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshots share record children while eager copies remain independent" {
    try executes(std.testing.allocator,
        \\record Row:
        \\    values: int[]
        \\    label: str
        \\func saved[T: copy + storable](values: T[]) -> T[]:
        \\    return values.snapshot()
        \\func main(out: Stream) -> int:
        \\    mut rows = [Row(values=[1, 2], label="row")]
        \\    mut shared = saved(rows)
        \\    mut copied = rows.copy()
        \\    rows[0].values.append(3)
        \\    shared[0].values.append(4)
        \\    copied[0].values.append(5)
        \\    out.print(rows[0].values[2], shared[0].values[2], copied[0].values[2], shared[0].label)
        \\    return 0
    , "3 4 5 row\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner shared child outlives its exclusive parent and empty snapshots stay empty" {
    try executes(std.testing.allocator,
        \\func detached(n: int) -> int[]:
        \\    const rows = [[n], []]
        \\    return rows[0].snapshot()
        \\func main(out: Stream) -> int:
        \\    mut kept = detached(7)
        \\    kept.append(8)
        \\    mut empty: int[] = []
        \\    const saved = empty.snapshot()
        \\    empty.append(1)
        \\    out.print(kept[0], kept[1], len(saved), len(empty))
        \\    return 0
    , "7 8 0 1\n");
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "single owner exchange consumes replacements and rejects borrowed or overlapping donors" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    const donor = [2]
        \\    _ = rows.exchange(0, donor)
        \\    return len(donor)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    _ = rows.exchange(0, rows[1])
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "single owner exchange refuses receiver relocation while evaluating arguments" {
    try rejectsExchangeRelocation(std.testing.allocator,
        \\func grow(mut xs: int[]) -> int:
        \\    xs.append(3)
        \\    return -1
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    _ = xs.exchange(grow(mut xs), 9)
        \\    return 0
    , "E_MUTATION_OVERLAP");
    try rejectsExchangeRelocation(std.testing.allocator,
        \\func replacement(mut xs: int[]) -> int:
        \\    xs.append(3)
        \\    return 9
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    _ = xs.exchange(0, replacement(mut xs))
        \\    return 0
    , "E_MUTATION_OVERLAP");
}

fn rejectsExchangeRelocation(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(allocator, "exchange-relocation.my", text);
    defer c.deinit();
    try std.testing.expectError(error.SourceError, c.check());
    try std.testing.expectEqualStrings(code, c.diagnostics.items[0].code);
}
