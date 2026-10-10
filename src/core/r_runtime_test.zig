//! Runtime-parity R: fixed-array storage, integer sorting and fallible payload lifetimes.
const std = @import("std");
const support = @import("test_support.zig");
const passes = @import("passes.zig");

const arrays =
    \\func update(mut xs: FixedArray[int, 8], at: int) -> int:
    \\    xs[at] = xs[at] + 10
    \\    return xs[at]
    \\
    \\
    \\func replaced(xs: FixedArray[int, 8]) -> FixedArray[int, 8]:
    \\    return replace(xs, 2, 90)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = FixedArray[int, 8]([0, 1, 2, 3, 4, 5, 6, 7])
    \\    mut saved = xs
    \\    out.print(update(mut xs, 3), saved[3], xs[3])
    \\    for i in range(8):
    \\        xs[i] = xs[i] + i
    \\    out.print(xs[7], saved[-1])
    \\    mut changed = replaced(xs)
    \\    out.print(xs[2], changed[2])
    \\    mut texts = FixedArray[str, 5](["a", "b", "c", "d", "e"])
    \\    mut old = texts
    \\    texts[1] = texts[4]
    \\    out.print(texts[1], old[1])
    \\    return 0
    \\
;

const Mode = enum { debug, optimize_debug, optimize_debug_verify, release, verify };

fn runFixture(arena: std.mem.Allocator, source: []const u8, mode: Mode) ![]const u8 {
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena, source, &refusal);
    const release = mode != .debug;
    const verify = mode == .verify or mode == .optimize_debug_verify;
    var passed = if (mode != .debug)
        try passes.run(arena, &module, if (verify) .verify else .trusted)
    else
        try passes.debug(arena, &module);
    const ran = try support.runOwned(arena, &module, .{ .release = release, .verify = verify, .own = false, .analysis = .{ .facts = passed.known, .vectors = passed.plans, .provenance = &passed.provenance } });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    return ran.stdout;
}

// spec: NEW-CORE-R-ARRAY-1
test "R fixed-array element access preserves live snapshots and managed element owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("13 3 13\n14 7\n4 90\ne b\n", try runFixture(arena.allocator(), arrays, .debug));
    try std.testing.expectEqualStrings("13 3 13\n14 7\n4 90\ne b\n", try runFixture(arena.allocator(), arrays, .optimize_debug));
    try std.testing.expectEqualStrings("13 3 13\n14 7\n4 90\ne b\n", try runFixture(arena.allocator(), arrays, .optimize_debug_verify));
    try std.testing.expectEqualStrings("13 3 13\n14 7\n4 90\ne b\n", try runFixture(arena.allocator(), arrays, .release));
    try std.testing.expectEqualStrings("13 3 13\n14 7\n4 90\ne b\n", try runFixture(arena.allocator(), arrays, .verify));
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
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .optimize_debug_verify));
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .release));
    try std.testing.expectEqualStrings("True -55 -9223372036854775808 9223372036854775807\n", try runFixture(arena.allocator(), sorting, .verify));
}

const small_sorting =
    \\record Item:
    \\    key: int
    \\    position: int
    \\
    \\
    \\func signed_value(i: int, n: int) -> int:
    \\    if i == 0:
    \\        return -9223372036854775807 - 1
    \\    if i == n - 1:
    \\        return 9223372036854775807
    \\    return i - n // 2
    \\
    \\
    \\func unsigned_value(i: int) -> u64:
    \\    if i % 2 == 0:
    \\        return u64(i // 2)
    \\    return 18446744073709551615u64 - u64(i // 2)
    \\
    \\
    \\func check_values(n: int) -> bool:
    \\    mut xs = [for i in range(n) yield signed_value((i + n // 2) % n, n)]
    \\    mut saved = xs
    \\    xs.sort()
    \\    mut descending = sorted(saved, reverse=True)
    \\    mut words = [for i in range(n) yield unsigned_value(i)]
    \\    mut saved_words = words
    \\    words.sort()
    \\    mut descending_words = sorted(saved_words, reverse=True)
    \\    if len(xs) != n or len(descending) != n or len(words) != n or len(descending_words) != n:
    \\        return False
    \\    for i in range(n):
    \\        if xs[i] != signed_value(i, n) or descending[n - 1 - i] != signed_value(i, n):
    \\            return False
    \\        if saved[i] != signed_value((i + n // 2) % n, n):
    \\            return False
    \\        mut expected = u64(i)
    \\        if i >= (n + 1) // 2:
    \\            expected = 18446744073709551615u64 - u64(n - 1 - i)
    \\        if words[i] != expected or descending_words[n - 1 - i] != expected:
    \\            return False
    \\        if saved_words[i] != unsigned_value(i):
    \\            return False
    \\    return True
    \\
    \\
    \\func item_key(item: Item) -> int:
    \\    return item.key
    \\
    \\
    \\func input_key(i: int, wide: bool) -> int:
    \\    if not wide:
    \\        return ((i * 5) % 8) * 1000003
    \\    if i % 4 == 0:
    \\        return 9223372036854775807
    \\    if i % 4 == 1:
    \\        return -9223372036854775807 - 1
    \\    if i % 4 == 2:
    \\        return 1
    \\    return -1
    \\
    \\
    \\func check_keyed(n: int, wide: bool) -> bool:
    \\    mut original = [for i in range(n) yield Item(key=input_key(i, wide), position=i)]
    \\    mut rows = original
    \\    rows.sort(key=item_key)
    \\    mut descending = sorted(original, key=item_key, reverse=True)
    \\    if len(rows) != n or len(descending) != n:
    \\        return False
    \\    for i in range(n):
    \\        if original[i].position != i or original[i].key != input_key(i, wide):
    \\            return False
    \\        mut a = rows[i]
    \\        mut d = descending[i]
    \\        if a.position < 0 or a.position >= n or d.position < 0 or d.position >= n:
    \\            return False
    \\        if a.key != input_key(a.position, wide) or d.key != input_key(d.position, wide):
    \\            return False
    \\        if i > 0:
    \\            mut before = rows[i - 1]
    \\            mut reverse_before = descending[i - 1]
    \\            if before.key > a.key or reverse_before.key < d.key:
    \\                return False
    \\            if before.key == a.key and before.position >= a.position:
    \\                return False
    \\            if reverse_before.key == d.key and reverse_before.position >= d.position:
    \\                return False
    \\    return True
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut correct = True
    \\    for n in [0, 1, 2, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257]:
    \\        mut passed = check_values(n)
    \\        correct = passed and correct
    \\    for n in [31, 32, 33, 63, 64, 65, 128, 255, 256, 257]:
    \\        mut packed = check_keyed(n, False)
    \\        mut wide = check_keyed(n, True)
    \\        correct = packed and wide and correct
    \\    out.print(correct)
    \\    return 0
;

// spec-case: NEW-CORE-R-SORT-1
test "R small integer sort boundaries preserve unsigned order snapshots and decorated ties" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("True\n", try runFixture(arena.allocator(), small_sorting, .debug));
    try std.testing.expectEqualStrings("True\n", try runFixture(arena.allocator(), small_sorting, .optimize_debug));
    try std.testing.expectEqualStrings("True\n", try runFixture(arena.allocator(), small_sorting, .optimize_debug_verify));
    try std.testing.expectEqualStrings("True\n", try runFixture(arena.allocator(), small_sorting, .release));
    try std.testing.expectEqualStrings("True\n", try runFixture(arena.allocator(), small_sorting, .verify));
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
    try std.testing.expectEqualStrings("2 1 5\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
    try std.testing.expectEqualStrings("2 1 5\n", try runFixture(arena.allocator(), source, .release));
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
test "R ordinary return storage preserves fallible construction, growth and shared list snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), payloads);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "ptr noalias %payload") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "ptr noalias sret(") != null);
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .debug));
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .optimize_debug));
    try std.testing.expectEqualStrings("31 14 529 15\n", try runFixture(arena.allocator(), payloads, .optimize_debug_verify));
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
    try std.testing.expectEqualStrings("-10 -6\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("-10 -6\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("-10 -6\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
    try std.testing.expectEqualStrings("-10 -6\n", try runFixture(arena.allocator(), source, .release));
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
    try std.testing.expectEqualStrings("780 37\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
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
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .release));
    try std.testing.expectEqualStrings("1037 37 80\n", try runFixture(arena.allocator(), source, .verify));
}

// spec-case: NEW-CORE-R-PUSH-1
test "R delayed payload reads survive a later capacity growing append" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record Node:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    e: int
        \\    name: str
        \\
        \\
        \\func make(i: int) -> Node?:
        \\    return Some(Node(a=i, b=2, c=3, d=4, e=5, name=str(i)))
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut nodes: Node[] = []
        \\    for i in range(5):
        \\        nodes.append(Node(a=-1, b=2, c=3, d=4, e=5, name="seed"))
        \\    mut result = make(42)
        \\    match result:
        \\        case Some(node):
        \\            nodes.append(node)
        \\        case None:
        \\            pass
        \\    for i in range(80):
        \\        nodes.append(Node(a=i, b=2, c=3, d=4, e=5, name=str(i)))
        \\    match result:
        \\        case Some(saved):
        \\            out.print(nodes[5].a, saved.name, len(nodes))
        \\        case None:
        \\            out.print("missing")
        \\    return 0
    ;
    try std.testing.expectEqualStrings("42 42 86\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("42 42 86\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("42 42 86\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
    try std.testing.expectEqualStrings("42 42 86\n", try runFixture(arena.allocator(), source, .release));
    try std.testing.expectEqualStrings("42 42 86\n", try runFixture(arena.allocator(), source, .verify));
}

// spec-case: NEW-CORE-R-PUSH-1
test "R wider managed error payloads preserve detached bytes and ordinary suffix fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record Node:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    name: str
        \\
        \\
        \\record Failure:
        \\    a: str
        \\    b: str
        \\    c: str
        \\    d: str
        \\    e: str
        \\    f: str
        \\    g: str
        \\
        \\
        \\func leaf(i: int) -> Result[Node, Failure]:
        \\    if i % 2 == 1:
        \\        return Err(Failure(a=str(i), b="b", c="c", d="d", e="e", f="f", g="suffix-" + str(i)))
        \\    return Ok(Node(a=i, b=2, c=3, d=4, name=str(i)))
        \\
        \\
        \\func make(i: int) -> Result[Node, Failure]:
        \\    return leaf(i)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut nodes: Node[] = []
        \\    for i in range(6):
        \\        match make(i):
        \\            case Ok(node):
        \\                nodes.append(node)
        \\            case Err(problem):
        \\                out.print(problem.a, problem.g)
        \\    out.print(len(nodes), nodes[-1].name)
        \\    return 0
    ;
    try std.testing.expectEqualStrings("1 suffix-1\n3 suffix-3\n5 suffix-5\n3 4\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("1 suffix-1\n3 suffix-3\n5 suffix-5\n3 4\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("1 suffix-1\n3 suffix-3\n5 suffix-5\n3 4\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
    try std.testing.expectEqualStrings("1 suffix-1\n3 suffix-3\n5 suffix-5\n3 4\n", try runFixture(arena.allocator(), source, .release));
    try std.testing.expectEqualStrings("1 suffix-1\n3 suffix-3\n5 suffix-5\n3 4\n", try runFixture(arena.allocator(), source, .verify));
}

/// Two callers consume differently sized variants of the same forwarded union.
/// Ordinary contiguous return storage preserves the wider variant's suffix fields.
fn differentPayloadRegions(arena: std.mem.Allocator, mode: Mode) ![]const u8 {
    const ir = @import("ir.zig");
    var module: ir.Module = .{};
    const small = try module.intern(arena, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64 } });
    const large = try module.intern(arena, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64, .i64, .i64 } });
    const result = try module.intern(arena, .{ .@"union" = &.{ small, large } });
    const smalls = try module.intern(arena, .{ .list = small });
    const larges = try module.intern(arena, .{ .list = large });
    var child = try support.Hand.init(arena, &module, "wide_child", .{ .params = &.{}, .ret = result });
    const seven = try child.int(.i64, 77);
    const made = try child.emit(.{ .op = .record_make, .ty = large, .data = try child.extra(&.{ seven, seven, seven, seven, seven, seven, seven }) });
    const wrapped = try child.emit(.{ .op = .union_make, .ty = result, .a = made, .data = 1 });
    _ = try child.emit(.{ .op = .ret, .ty = .void, .a = wrapped });
    const child_index = try child.finish();
    var parent = try support.Hand.init(arena, &module, "small_parent", .{ .params = &.{}, .ret = result });
    const forwarded = try parent.emit(.{ .op = .call, .ty = result, .a = @fromBackingInt(child_index), .data = try parent.extra(&.{}) });
    _ = try parent.emit(.{ .op = .ret, .ty = .void, .a = forwarded });
    const parent_index = try parent.finish();
    var main = try support.Hand.init(arena, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const out = try main.param(0);
    const capacity = try main.int(.i64, 4);
    const big_list = try main.emit(.{ .op = .list_new, .ty = larges, .a = capacity });
    const direct = try main.emit(.{ .op = .call, .ty = result, .a = @fromBackingInt(child_index), .data = try main.extra(&.{}) });
    const big = try main.emit(.{ .op = .union_payload, .ty = large, .a = direct, .data = 1 });
    const appended = try main.emit(.{ .op = .list_push, .ty = larges, .a = big_list, .b = big });
    const length = try main.emit(.{ .op = .list_len, .ty = .i64, .a = appended });
    try main.printValues(out, &.{length});
    const small_list = try main.emit(.{ .op = .list_new, .ty = smalls, .a = capacity });
    const indirect = try main.emit(.{ .op = .call, .ty = result, .a = @fromBackingInt(parent_index), .data = try main.extra(&.{}) });
    const tag = try main.emit(.{ .op = .union_tag, .ty = .u32, .a = indirect });
    const is_small = try main.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try main.int(.u32, 0), .data = @backingInt(ir.Predicate.eq) });
    const small_arm = try main.newBlock();
    const big_arm = try main.newBlock();
    try main.branch(is_small, small_arm, big_arm);
    main.block = small_arm;
    const little = try main.emit(.{ .op = .union_payload, .ty = small, .a = indirect, .data = 0 });
    const kept = try main.emit(.{ .op = .list_push, .ty = smalls, .a = small_list, .b = little });
    const kept_length = try main.emit(.{ .op = .list_len, .ty = .i64, .a = kept });
    try main.printValues(out, &.{kept_length});
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    main.block = big_arm;
    const bigger = try main.emit(.{ .op = .union_payload, .ty = large, .a = indirect, .data = 1 });
    const suffix = try main.emit(.{ .op = .record_get, .ty = .i64, .a = bigger, .data = 6 });
    try main.printValues(out, &.{suffix});
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    module.entry = try main.finish();
    const verify = mode == .verify or mode == .optimize_debug_verify;
    var passed = if (mode != .debug)
        try passes.run(arena, &module, if (verify) .verify else .trusted)
    else
        try passes.debug(arena, &module);
    const ran = try support.runOwned(arena, &module, .{ .release = mode != .debug, .verify = verify, .own = false, .analysis = .{ .facts = passed.known, .vectors = passed.plans, .provenance = &passed.provenance } });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    return ran.stdout;
}

// spec-case: NEW-CORE-R-PUSH-1
test "R differently sized union variants survive forwarding through fallible producers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("1\n77\n", try differentPayloadRegions(arena.allocator(), .debug));
    try std.testing.expectEqualStrings("1\n77\n", try differentPayloadRegions(arena.allocator(), .optimize_debug));
    try std.testing.expectEqualStrings("1\n77\n", try differentPayloadRegions(arena.allocator(), .optimize_debug_verify));
    try std.testing.expectEqualStrings("1\n77\n", try differentPayloadRegions(arena.allocator(), .release));
    try std.testing.expectEqualStrings("1\n77\n", try differentPayloadRegions(arena.allocator(), .verify));
}

// spec-case: NEW-CORE-R-PUSH-1
test "R recursive produced nodes keep wider errors valid after the destination list is destroyed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record Node:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    name: str
        \\    children: Node[]
        \\
        \\
        \\record Failure:
        \\    a: str
        \\    b: str
        \\    c: str
        \\    d: str
        \\    e: str
        \\    f: str
        \\    g: str
        \\
        \\
        \\func leaf(i: int) -> Result[Node, Failure]:
        \\    if i == 5:
        \\        return Err(Failure(a=str(i), b="b", c="c", d="d", e="e", f="f", g="suffix-" + str(i)))
        \\    mut child = Node(a=-i, b=2, c=3, name="child-" + str(i), children=[])
        \\    return Ok(Node(a=i, b=2, c=3, name=str(i), children=[child]))
        \\
        \\
        \\func gather(n: int) -> Result[Node[], Failure]:
        \\    mut nodes: Node[] = []
        \\    for i in range(n):
        \\        mut node = try leaf(i)
        \\        nodes.append(node)
        \\    return Ok(nodes)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    match gather(7):
        \\        case Ok(nodes):
        \\            out.print(len(nodes))
        \\        case Err(problem):
        \\            out.print(problem.a, problem.g)
        \\    match gather(4):
        \\        case Ok(nodes):
        \\            out.print(len(nodes), nodes[-1].name, nodes[-1].children[0].name)
        \\        case Err(problem):
        \\            out.print(problem.g)
        \\    return 0
    ;
    try std.testing.expectEqualStrings("5 suffix-5\n4 3 child-3\n", try runFixture(arena.allocator(), source, .debug));
    try std.testing.expectEqualStrings("5 suffix-5\n4 3 child-3\n", try runFixture(arena.allocator(), source, .optimize_debug));
    try std.testing.expectEqualStrings("5 suffix-5\n4 3 child-3\n", try runFixture(arena.allocator(), source, .optimize_debug_verify));
    try std.testing.expectEqualStrings("5 suffix-5\n4 3 child-3\n", try runFixture(arena.allocator(), source, .release));
    try std.testing.expectEqualStrings("5 suffix-5\n4 3 child-3\n", try runFixture(arena.allocator(), source, .verify));
}
