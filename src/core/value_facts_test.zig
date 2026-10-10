//! S1 lane V facts: field intervals through records, list element hulls through writes, list
//! lengths through push and pop, and the verify-mode assertions that check each at run time.
const std = @import("std");
const support = @import("test_support.zig");

const nested_lengths =
    \\func uniform(w: int, h: int) -> int:
    \\    mut grid: int[][] = []
    \\    for i in range(h):
    \\        grid.append([for j in range(w) yield j])
    \\    mut total = 0
    \\    for j in range(w):
    \\        total += grid[0][j]
    \\    return total
    \\
    \\func ragged(w: int) -> int:
    \\    mut grid = [[for j in range(w) yield j], [for j in range(w) yield j]]
    \\    _ = grid[1].pop()
    \\    mut total = 0
    \\    for j in range(w - 1):
    \\        total += grid[1][j]
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(uniform(3, 2), ragged(3))
    \\    return 0
;

// spec: NEW-CORE-NESTED-LENGTH-S4-1
test "uniform child lengths prove nested accesses but pop invalidates them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), nested_lengths);
    const uniform_tail = text[std.mem.indexOf(u8, text, "fn uniform").?..];
    const uniform = uniform_tail[0..(std.mem.indexOf(u8, uniform_tail, "\nfn ") orelse uniform_tail.len)];
    try std.testing.expect(contains(uniform, "list_get.proven i64"));
    const ragged_tail = text[std.mem.indexOf(u8, text, "fn ragged").?..];
    const ragged = ragged_tail[0..(std.mem.indexOf(u8, ragged_tail, "\nfn ") orelse ragged_tail.len)];
    try std.testing.expect(contains(ragged, "list_get.exact i64"));
    const verified = try support.verifyLlvmText(arena.allocator(), nested_lengths);
    try std.testing.expect(contains(verified, "uniform child list length"));
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const record_fields =
    \\record P:
    \\    x: int
    \\    y: int
    \\    z: int
    \\
    \\
    \\func fields(n: int) -> int:
    \\    mut p = P(x=n % 5, y=7, z=n % 3)
    \\    p.y = p.y + 2
    \\    return p.x * 1000000000000 + p.z * 1000000000000 + p.y * 1000000000000
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(fields(7))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-6
test "a record's field intervals flow through record_make, record_set and record_get, so field arithmetic is proven" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), record_fields);
    const body = text[std.mem.indexOf(u8, text, "fn fields").?..];
    // x < 5, z < 3 and y = 9 make every product and sum fit; only the remainders of the parameter keep their checks.
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, body, "mul.proven"));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, body, "add.proven"));
    try std.testing.expect(!contains(body, "mul.exact"));
}

const list_facts =
    \\func literal() -> int:
    \\    mut xs = [10, 20, 30]
    \\    return xs[2] + xs[0] + len(xs)
    \\
    \\
    \\func hull() -> int:
    \\    mut xs = [1, 2, 3]
    \\    xs[1] = 100
    \\    xs[0] = 5
    \\    return xs[0] * 900000000000000000 + xs[1]
    \\
    \\
    \\func pops() -> int:
    \\    mut xs = [1, 2]
    \\    mut a = xs.pop()
    \\    mut b = xs.pop()
    \\    return a + b
    \\
    \\
    \\func parameter(xs: int[], i: int) -> int:
    \\    mut ys = xs
    \\    return ys.pop() + ys[i]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(literal(), hull(), pops(), parameter([1, 2, 3], 0))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-7
test "a list's length through new, push and pop and its element hull through element writes prove reads, writes and pops" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), list_facts);
    const literal = text[std.mem.indexOf(u8, text, "fn literal").?..std.mem.indexOf(u8, text, "fn hull").?];
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, literal, "list_get.proven"));
    const hull = text[std.mem.indexOf(u8, text, "fn hull").?..std.mem.indexOf(u8, text, "fn pops").?];
    // Two writes at known indices, hull [1, 100] after the first and [1, 100] with 5 after the second:
    // the product 5 * 9e17 overflows i64 only if the first element could exceed 10.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, hull, "list_set.proven"));
    const pops = text[std.mem.indexOf(u8, text, "fn pops").?..std.mem.indexOf(u8, text, "fn parameter").?];
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, pops, "list_pop.proven"));
    // A list parameter's length is unknown: its pop and its read keep their checks.
    const parameter = text[std.mem.indexOf(u8, text, "fn parameter").?..];
    try std.testing.expect(contains(parameter, "list_pop.exact"));
    try std.testing.expect(contains(parameter, "list_get.exact"));
}

// spec: NEW-CORE-VERIFY-3
test "a verify build asserts every list length interval and record field interval it relies on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lists = try support.verifyLlvmText(arena.allocator(), list_facts);
    try std.testing.expect(contains(lists, "list length [2, 2]"));
    try std.testing.expect(contains(lists, "list length [3, 3]"));
    const records = try support.verifyLlvmText(arena.allocator(), record_fields);
    // `y` is 7 + 2 = 9 in the record `record_set` built.
    try std.testing.expect(contains(records, "record field 1 range [9, 9]"));
    try std.testing.expect(contains(records, "record field 0 range [0, 4]"));
}

const rewritten_list =
    \\func churn(size: int, rounds: int, seed: int) -> int:
    \\    if size < 2 or rounds < 1 or seed < 1 or seed > 1000000:
    \\        return -1
    \\    mut values = [for j in range(size) yield (seed + j * 13) % 1009]
    \\    mut checksum = 0
    \\    for batch in range(rounds):
    \\        mut index = (seed + batch * 17) % size
    \\        values[index] = (values[index] + batch + 1) % 1000003
    \\        checksum = (checksum + values[index]) % 1000000007
    \\    return checksum
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(churn(64, 100, 7))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-8
test "a list rewritten in a loop has the hull of its entry and its writes, and an index remainder of the list's length is in bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), rewritten_list);
    const body = text[std.mem.indexOf(u8, text, "fn churn").?..];
    // `if size < 2 or ...: return` says `size >= 2` afterwards, so `% size` is an unsigned remainder, below `size = len(values)`.
    try std.testing.expect(contains(body, "list_get.proven i64"));
    try std.testing.expect(contains(body, "list_set.proven list[i64]"));
    // The elements stay in [0, 1000002]: both remainders by constants are unsigned, and the checksum sum cannot overflow.
    try std.testing.expect(!contains(body, "floor_rem.exact"));
    try std.testing.expect(!contains(body, "list_get.exact"));
}

const either_or =
    \\func guarded(size: int, n: int) -> int:
    \\    if size < 2 or n < 1:
    \\        return 0
    \\    return 100 % size + n // size
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(guarded(5, 7))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-9
test "an or of comparisons is control flow, so what each failed test says about its operands holds after the if" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), either_or);
    const body = text[std.mem.indexOf(u8, text, "fn guarded").?..];
    try std.testing.expect(contains(body, "floor_rem.proven"));
    try std.testing.expect(contains(body, "floor_div.proven"));
    // No boolean phi joins the two comparisons.
    try std.testing.expect(!contains(body, "phi bool"));
}

const plain_condition_loop =
    \\func f(xs: int[]) -> int:
    \\    mut i = 0
    \\    while xs[i] != 0:
    \\        i += 1
    \\    return i
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(f([1, 2, 0]))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-FACTS-9
test "a plain condition is evaluated before the blocks of its branch are made: the blocks of its own index fix-up come first" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), plain_condition_loop);
    const body = text[std.mem.indexOf(u8, text, "fn f").?..];
    // The fix-up blocks b2 and b3 belong to the condition; the loop body and exit follow them.
    try std.testing.expect(contains(body, "branch %16, b4, b6"));
    try std.testing.expect(contains(body, "branch %6, b2, b3"));
}

const loop_record_fields =
    \\record Pair:
    \\    x: int
    \\    y: int
    \\func walk(n: int) -> int:
    \\    mut p = Pair(x=0, y=7)
    \\    for j in range(n):
    \\        p.x = p.x + 1
    \\    return p.x + p.y
    \\func main(out: Stream) -> int:
    \\    out.print(walk(100))
    \\    return 0
;

// spec-case: NEW-CORE-FACTS-6
test "record facts and counted loops survive reclaimed analysis scratch and cloned result storage" {
    const facts = @import("facts.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var transient = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer transient.deinit();
    var work = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer work.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var records = try support.buildSource(a, record_fields, &refusal);
    var loops = try support.buildSource(a, nested_lengths, &refusal);
    var record_loop = try support.buildSource(a, loop_record_fields, &refusal);
    var widened_record_phis: usize = 0;
    var fields_seen: usize = 0;
    var loops_seen: usize = 0;
    for ([_]*@import("ir.zig").Module{ &records, &loops, &record_loop }) |module| {
        for (module.functions.items) |*function| {
            if (function.signature.linkage != .internal) continue;
            const known = try facts.analyzeWithScratch(transient.allocator(), work.allocator(), function, .{ .mark = false });
            const expected = try known.clone(a);
            // Overwrite the entire reusable scratch region. Output must contain
            // neither dominator/worklist slices nor the record transfer buffer.
            _ = work.reset(.retain_capacity);
            @memset(try work.allocator().alloc(u8, 1024 * 1024), 0xa5);
            const retained = try known.clone(a);
            for (known.aggregates.fields, retained.aggregates.fields) |old, copy| {
                if (old) |table| {
                    fields_seen += 1;
                    try std.testing.expect(copy.?.ptr != table.ptr);
                    for (table, copy.?) |before, after| try std.testing.expect(std.meta.eql(before, after));
                }
            }
            loops_seen += retained.counted.len;
            _ = transient.reset(.retain_capacity);
            @memset(try transient.allocator().alloc(u8, 1024 * 1024), 0xa5);
            // Reads after poisoning cover every escaping fact table, including
            // nested record fields and counted-loop descriptors.
            for (function.insts.items, retained.ranges, retained.aggregates.fields, 0..) |inst, range, fields, index| {
                if (inst.op == .iconst and inst.ty.integer() != null) {
                    const point = facts.Interval.point(@as(i64, @bitCast(inst.data)));
                    // Builder constants are detached from blocks, so analysis
                    // leaves their dense table entries null. A present entry
                    // must agree; valueRange derives their exact point either way.
                    if (range) |interval| try std.testing.expect(std.meta.eql(interval, point));
                    try std.testing.expect(std.meta.eql(facts.valueRange(&retained, function, @fromBackingInt(@intCast(index))), point));
                }
                if (fields) |table| {
                    for (table) |field| {
                        if (field) |interval| try std.testing.expect(interval.lo <= interval.hi);
                    }
                    if (module == &record_loop and inst.op == .phi and table.len == 2) {
                        try std.testing.expectEqual(@as(?facts.Interval, null), table[0]);
                        try std.testing.expect(std.meta.eql(table[1], facts.Interval.point(7)));
                        widened_record_phis += 1;
                    }
                }
            }
            for (retained.counted) |counted| {
                try std.testing.expect(counted.loop.header.index() < function.blocks.items.len);
                try std.testing.expect(counted.counter.index() < function.insts.items.len);
            }
            try std.testing.expectEqualDeep(expected.ranges, retained.ranges);
            try std.testing.expectEqualDeep(expected.aggregates, retained.aggregates);
            try std.testing.expectEqualDeep(expected.floats, retained.floats);
            try std.testing.expectEqualDeep(expected.bounds, retained.bounds);
            try std.testing.expectEqualDeep(expected.reachable, retained.reachable);
            try std.testing.expectEqualDeep(expected.counted, retained.counted);
            try std.testing.expectEqual(function.insts.items.len, retained.aggregates.lists.len);
            try std.testing.expectEqual(function.insts.items.len, retained.aggregates.dicts.len);
            try std.testing.expectEqual(function.insts.items.len, retained.floats.len);
            try std.testing.expectEqual(function.insts.items.len, retained.bounds.len);
            try std.testing.expect(retained.reachable[0]);
            _ = transient.reset(.retain_capacity);
            _ = work.reset(.retain_capacity);
        }
    }
    try std.testing.expect(fields_seen > 0);
    try std.testing.expect(loops_seen > 0);
    try std.testing.expect(widened_record_phis > 0);
}
