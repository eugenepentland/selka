//! Runtime-parity R: fixed-array storage, integer sorting and payload destinations.
const std = @import("std");
const support = @import("test_support.zig");

const arrays =
    \\func update(mut xs: FixedArray[int, 8], at: int) -> int:
    \\    xs[at] = xs[at] + 10
    \\    return xs[at]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = FixedArray[int, 8]([0, 1, 2, 3, 4, 5, 6, 7])
    \\    mut saved = xs
    \\    out.print(update(mut xs, 3), saved[3], xs[3])
    \\    for i in range(8):
    \\        xs[i] = xs[i] + i
    \\    out.print(xs[7], saved[-1])
    \\    mut texts = FixedArray[str, 5](["a", "b", "c", "d", "e"])
    \\    mut old = texts
    \\    texts[1] = texts[4]
    \\    out.print(texts[1], old[1])
    \\    return 0
    \\
;

const Mode = enum { debug, optimize_debug, release, verify };

fn runFixture(arena: std.mem.Allocator, source: []const u8, mode: Mode) ![]const u8 {
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena, source, &refusal);
    const release = mode == .release or mode == .verify;
    const verify = mode == .verify;
    var passed = if (mode != .debug)
        try @import("passes.zig").run(arena, &module, if (verify) .verify else .trusted)
    else
        try @import("passes.zig").debug(arena, &module);
    const ran = try support.runOwned(arena, &module, .{ .release = release, .verify = verify, .own = false, .analysis = .{ .facts = passed.known, .vectors = passed.plans, .provenance = &passed.provenance } });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    return ran.stdout;
}

// spec: NEW-CORE-R-ARRAY-1
test "R fixed-array element access preserves live snapshots and managed element owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("13 3 13\n14 7\ne b\n", try runFixture(arena.allocator(), arrays, .debug));
    try std.testing.expectEqualStrings("13 3 13\n14 7\ne b\n", try runFixture(arena.allocator(), arrays, .optimize_debug));
    try std.testing.expectEqualStrings("13 3 13\n14 7\ne b\n", try runFixture(arena.allocator(), arrays, .release));
    try std.testing.expectEqualStrings("13 3 13\n14 7\ne b\n", try runFixture(arena.allocator(), arrays, .verify));
}

const sorting =
    \\record Item:
    \\    key: int
    \\    position: int
    \\
    \\
    \\func key(item: Item) -> int:
    \\    return item.key
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [for i in range(257) yield (i * 73) % 257 - 128]
    \\    mut alias = xs
    \\    xs.sort()
    \\    mut correct = True
    \\    for i in range(257):
    \\        correct = correct and xs[i] == i - 128
    \\    mut extreme = [9223372036854775807, -9223372036854775807 - 1, 0, -1, 1]
    \\    extreme.sort()
    \\    mut items = [for i in range(200) yield Item(key=(i * 13) % 7, position=i)]
    \\    items.sort(key=key)
    \\    for i in range(1, 200):
    \\        if items[i].key == items[i - 1].key:
    \\            correct = correct and items[i].position > items[i - 1].position
    \\    out.print(correct, alias[1], extreme[0], extreme[-1])
    \\    return 0
    \\
;

// spec: NEW-CORE-R-SORT-1
test "R integer radix partitions preserve signed order, aliases and stable decorated ties" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .debug));
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .optimize_debug));
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .release));
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .verify));
}

// spec: NEW-CORE-R-SRET-1
test "R destination sharing keeps ordinary function-value signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record State:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    e: int
        \\
        \\
        \\func advance(s: State) -> State:
        \\    return State(a=s.a + 1, b=s.b, c=s.c, d=s.d, e=s.e)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut f = advance
        \\    mut s = State(a=1, b=2, c=3, d=4, e=5)
        \\    mut old = s
        \\    s = f(s)
        \\    out.print(s.a, old.a, s.e)
        \\    return 0
        \\
    ;
    try std.testing.expectEqualStrings("2 1 5\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("2 1 5\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("2 1 5\n", try runFixture(arena.allocator(), source, .verify));
}

const payloads =
    \\record Node:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\    e: int
    \\    text: str
    \\
    \\
    \\func leaf(i: int) -> Result[Node, int]:
    \\    if i % 11 == 0:
    \\        return Err(i)
    \\    return Ok(Node(a=i, b=i + 1, c=2, d=3, e=4, text=str(i)))
    \\
    \\
    \\func make(i: int) -> Result[Node, int]:
    \\    return leaf(i)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut nodes: Node[] = []
    \\    mut saved: Node[] = []
    \\    for i in range(35):
    \\        match make(i):
    \\            case Ok(node):
    \\                nodes.append(node)
    \\            case Err(_):
    \\                pass
    \\        if i == 15:
    \\            saved = nodes
    \\    mut total = 0
    \\    for node in nodes:
    \\        total += node.a
    \\    out.print(len(nodes), len(saved), total, saved[-1].text)
    \\    return 0
    \\
;

// spec: NEW-CORE-R-PUSH-1
test "R payload destinations preserve fallible construction, growth and shared list snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), payloads);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "ptr noalias %payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%payload.dst") != null);
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .debug));
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .optimize_debug));
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .release));
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .verify));
}

// spec: NEW-CORE-R-ARRAY-2
test "R fixed-array element hulls retain changed and negative values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\func main(out: Stream) -> int:
        \\    mut xs = FixedArray[int, 5]([0, 1, 2, 3, 4])
        \\    for i in range(5):
        \\        xs[i] = xs[i] - 10
        \\    out.print(xs[0], xs[-1])
        \\    return 0
        \\
    ;
    try std.testing.expectEqualStrings("-10 -6\n", try runFixture(arena.allocator(), source, .verify));
}

// spec-case: NEW-CORE-R-PUSH-1
test "R payload ABI keeps a whole union snapshot contiguous" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record Node:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    e: int
        \\
        \\
        \\func leaf(i: int) -> Node?:
        \\    return Some(Node(a=i, b=2, c=3, d=4, e=5))
        \\
        \\
        \\func make(i: int) -> Node?:
        \\    mut result = leaf(i)
        \\    if inspect(result) < 0:
        \\        return None
        \\    return result
        \\
        \\
        \\func inspect(result: Node?) -> int:
        \\    match result:
        \\        case Some(node):
        \\            return node.a
        \\        case None:
        \\            return -1
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut nodes: Node[] = []
        \\    mut total = 0
        \\    for i in range(40):
        \\        mut result = make(i)
        \\        total += inspect(result)
        \\        match result:
        \\            case Some(node):
        \\                nodes.append(node)
        \\            case None:
        \\                pass
        \\    out.print(total, nodes[37].a)
        \\    return 0
        \\
    ;
    try std.testing.expectEqualStrings("780 37\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("780 37\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("780 37\n", try runFixture(arena.allocator(), source, .release));
    try std.testing.expectEqualStrings("780 37\n", try runFixture(arena.allocator(), source, .verify));
}

// spec-case: NEW-CORE-R-PUSH-1
test "R destination selection follows intervening list updates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record Node:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    e: int
        \\
        \\
        \\func make(i: int) -> Node?:
        \\    return Some(Node(a=i, b=2, c=3, d=4, e=5))
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut nodes: Node[] = []
        \\    for i in range(40):
        \\        mut result = make(i)
        \\        nodes.append(Node(a=1000 + i, b=2, c=3, d=4, e=5))
        \\        match result:
        \\            case Some(node):
        \\                nodes.append(node)
        \\            case None:
        \\                pass
        \\    out.print(nodes[74].a, nodes[75].a, len(nodes))
        \\    return 0
        \\
    ;
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .release));
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .verify));
}
