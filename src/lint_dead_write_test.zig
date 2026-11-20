//! `dead-write` (lane W7, step 1): a write to a local, or to a field or element of one, that no later
//! read can see. The rule is off in every profile and runs only when `--rule=dead-write` names it;
//! it then reports and never refuses. These tests pin the probe's lost update
//! (`experiments/implicit-code-audit-20261111/probes/lost_update_on_copy.my`), the shapes it reports,
//! and the shapes it must not report: a `mut` parameter, a `match mut` binding, a write read again by a
//! loop, a local returned and a local moved with `own`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const interfaces = @import("interfaces.zig");
const lint_config = @import("lint_config.zig");
const project = @import("project.zig");
const project_compile = @import("project_compile.zig");
const project_files = @import("project_files.zig");

const lint = language.lint;

/// The probe of the implicit-code audit, the shapes the rule reports, and the shapes it must not.
const fixture =
    \\import lists
    \\
    \\
    \\record Item:
    \\    name: str
    \\    count: int
    \\    log: int[]
    \\
    \\
    \\enum Node:
    \\    Leaf(value: int)
    \\    Pair(left: int, right: int)
    \\
    \\
    \\enum ParseError:
    \\    Empty
    \\
    \\
    \\func bump(mut items: Item[]):
    \\    mut first = copy(items[0])
    \\    first.count = first.count + 1
    \\
    \\
    \\func inner_block(flag: bool) -> int:
    \\    mut x = 1
    \\    const before = x
    \\    if flag:
    \\        x = 2
    \\    return before
    \\
    \\
    \\func element_and_call(items: Item[]) -> int:
    \\    mut local = copy(items[0])
    \\    append(mut local.log, 3)
    \\    local.log[0] = 4
    \\    return items[0].count
    \\
    \\
    \\func failing(text: str) -> int fails ParseError:
    \\    mut count = 0
    \\    if len(text) == 0:
    \\        count = 1
    \\        fail ParseError.Empty
    \\    return len(text) + count
    \\
    \\
    \\func generic_spare[T](values: T[]) -> int:
    \\    mut spare = copy(values[0])
    \\    spare = copy(values[0])
    \\    return len(values)
    \\
    \\
    \\func set_first(mut items: Item[]):
    \\    items[0].count = 2
    \\    append(mut items[0].log, 1)
    \\
    \\
    \\func pair_into(mut out: int[], mut scratch: int[]):
    \\    append(mut out, len(scratch))
    \\
    \\
    \\func both(mut out: int[]):
    \\    mut scratch = [1]
    \\    pair_into(mut out, mut scratch)
    \\
    \\
    \\func report_and_clear(out: Stream, mut lines: str[]):
    \\    for line in lines:
    \\        print(out, line)
    \\    lists.clear(mut lines)
    \\
    \\
    \\func printed(out: Stream):
    \\    mut lines = ["a"]
    \\    report_and_clear(out, mut lines)
    \\
    \\
    \\func reset(mut item: Item):
    \\    item = Item(name="", count=0, log=[])
    \\
    \\
    \\func arm(mut nodes: Node[]):
    \\    for i in range(len(nodes)):
    \\        match mut nodes[i]:
    \\            case Leaf(value):
    \\                value = value + 1
    \\            case Pair(left, right):
    \\                left = right
    \\
    \\
    \\func loop_read(n: int) -> int:
    \\    mut left = n
    \\    mut total = 0
    \\    mut last = 0
    \\    while left > 0:
    \\        left = left - 1
    \\        total = total + last
    \\        last = left
    \\    return total
    \\
    \\
    \\func tally_until(limit: int) -> int:
    \\    mut seen: int[] = []
    \\    mut n = 0
    \\    while True:
    \\        n += 1
    \\        if n > limit:
    \\            return len(seen)
    \\        keep_one(mut seen)
    \\
    \\
    \\func keep_one(mut values: int[]):
    \\    append(mut values, 1)
    \\
    \\
    \\func returned() -> Item:
    \\    mut item = Item(name="a", count=1, log=[])
    \\    item.count = 2
    \\    return item
    \\
    \\
    \\func keep(own item: Item) -> int:
    \\    return item.count
    \\
    \\
    \\func moved() -> int:
    \\    mut item = Item(name="a", count=1, log=[])
    \\    item.count = 3
    \\    return keep(own item)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut items: Item[] = []
    \\    append(mut items, Item(name="a", count=1, log=[0]))
    \\    bump(mut items)
    \\    set_first(mut items)
    \\    reset(mut items[0])
    \\    both(mut items[0].log)
    \\    printed(out)
    \\    mut nodes: Node[] = [Node.Leaf(value=1)]
    \\    arm(mut nodes)
    \\    const parsed = failing("ab") else Err(problem):
    \\        return 1
    \\    print(out, items[0].count, inner_block(True), element_and_call(items), parsed, len(nodes))
    \\    print(out, generic_spare([1, 2]), generic_spare(["a"]), loop_read(3), returned().count, moved(), tally_until(2))
    \\    return 0
    \\
;

/// Evaluate the whole lint pipeline over the fixture without writing to stdout, which is the test
/// runner's own protocol pipe. `rule` is the `--rule=NAME` the run names, if any.
fn evaluate(scratch: std.mem.Allocator, root: []const u8, rule: ?[]const u8, profile: ?lint_config.Profile) !lint.Outcome {
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), "main", .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = try std.fs.path.join(scratch, &.{ root, "main.selka" });
    return lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = null,
        .entry_path = entry,
        .options = .{ .gate = rule == null, .rule = rule, .profile = profile },
        .data = .{ .diagnostics = .text },
    }, scratch);
}

/// How many `L_DEAD_WRITE` findings name function `qualified` and mention `needle`.
fn deadWrites(outcome: lint.Outcome, qualified: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    for (outcome.findings) |finding| {
        if (!std.mem.eql(u8, finding.code, "L_DEAD_WRITE")) continue;
        if (qualified.len != 0 and !std.mem.eql(u8, finding.subject.qualified, qualified)) continue;
        if (std.mem.indexOf(u8, finding.message, needle) != null) count += 1;
    }
    return count;
}

fn writeRoot(temp: *std.testing.TmpDir) ![:0]u8 {
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = fixture });
    return temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
}

test "dead-write reports the probe's lost update and the writes no later read sees" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeRoot(&temp);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluate(arena.allocator(), root, "dead-write", null);
    // The probe: the copy is changed and dropped.
    try t.expectEqual(@as(usize, 1), deadWrites(outcome, "main::bump", "nothing reads `first` after this field write"));
    // A write in an inner block that the function's end reads around.
    try t.expectEqual(@as(usize, 1), deadWrites(outcome, "main::inner_block", "nothing reads `x` after this assignment"));
    // A writer call and an element write through a field of a local copy.
    try t.expectEqual(@as(usize, 1), deadWrites(outcome, "main::element_and_call", "after this call that writes it"));
    try t.expectEqual(@as(usize, 1), deadWrites(outcome, "main::element_and_call", "after this element write"));
    // A write just before `fail`, which leaves the function.
    try t.expectEqual(@as(usize, 1), deadWrites(outcome, "main::failing", "`count`"));
    // A generic body's write is one site, dead in both instances.
    try t.expectEqual(@as(usize, 1), deadWrites(outcome, "", "`spare`"));
    // The rule reports; it never refuses.
    try t.expectEqual(@as(usize, 6), deadWrites(outcome, "", ""));
    try t.expectEqual(@as(usize, 0), outcome.blocking);
}

test "dead-write leaves caller storage, match mut bindings, loops, returns and moves alone" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeRoot(&temp);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluate(arena.allocator(), root, "dead-write", null);
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::set_first", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::reset", ""));
    // A call that also writes caller storage is needed for that write.
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::both", ""));
    // A call handed a capability is needed for its effect.
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::printed", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::arm", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::loop_read", ""));
    // A call in a `while True` loop whose next round reads the local before it returns.
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::tally_until", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::returned", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::moved", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(outcome, "main::main", ""));
}

test "dead-write is off unless a run names it" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeRoot(&temp);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // `evaluate` with no rule name runs under `--gate`: still nothing.
    try t.expectEqual(@as(usize, 0), deadWrites(try evaluate(scratch, root, null, null), "", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(try evaluate(scratch, root, null, .strict), "", ""));
    try t.expectEqual(@as(usize, 0), deadWrites(try evaluate(scratch, root, null, .safety), "", ""));
    // Naming another rule turns nothing else on.
    try t.expectEqual(@as(usize, 0), deadWrites(try evaluate(scratch, root, "naming", null), "", ""));
    try t.expect(lint.knownRule("dead-write"));
    try t.expect(!lint.knownRule("dead-writes"));
}
