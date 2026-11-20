//! Fact pass tests: what a release build proves, and what it must not.
const std = @import("std");
const support = @import("test_support.zig");

const filled_then_read =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 7) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += values[j] // 3
    \\    print(out, total)
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-1
test "a list filled by a counted loop and read under the same bound needs no bounds, overflow or floor checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), filled_then_read);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "floor_div.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "floor_rem.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "mul.proven i64") != null);
    // `n + 100`, both counter steps and the sum; what stays exact is in branches the facts showed dead.
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, text, "add.proven i64"));
    // Index removal no longer constructs a normalization arm to fold.
    try std.testing.expect(std.mem.indexOf(u8, text, "branch 0:bool") == null);
}

const unknown_sources =
    \\func total(values: int[], n: int) -> int:
    \\    mut acc = 0
    \\    for j in range(n):
    \\        acc += values[j]
    \\    return acc
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, total([1, 2, 3], len(args)))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-2
test "a list parameter or an unbounded sum keeps its checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), unknown_sources);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact i64 param0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "add.exact i64") != null);
    // The counter's own step is still proven: it stops below a bound that fits the type.
    try std.testing.expect(std.mem.indexOf(u8, text, "add.proven i64") != null);
}

const facts = @import("facts.zig");

const wide_elements =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 7) % 1000000)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += values[j]
    \\    print(out, total)
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-3
test "the 2^47 list-length rule bounds reductions: 1008 * 2^47 fits i64 and 999999 * 2^47 does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(i128, 1) << 47, facts.max_list_length);
    const narrow = try support.factsText(arena.allocator(), filled_then_read);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, narrow, "add.proven i64"));
    const wide = try support.factsText(arena.allocator(), wide_elements);
    // `n + 100` and both counter steps are proven; the sum of up to 2^47 values below 10^6 is not.
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, wide, "add.proven i64"));
    try std.testing.expect(std.mem.indexOf(u8, wide, "list_get.proven i64") != null);
}

const searching =
    \\func search(values: int[], key: int) -> int:
    \\    mut low = 0
    \\    mut high = len(values)
    \\    while low < high:
    \\        mut middle = (low + high) // 2
    \\        if values[middle] < key:
    \\            low = middle + 1
    \\        else:
    \\            high = middle
    \\    return low
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, search([1, 3, 5], 4))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-4
test "binary search over a list parameter keeps no check: widened indices, the midpoint below high, high at most the length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), searching);
    // `low + high`, `middle + 1`, the floor division and the read `values[middle]` are proven.
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.proven i64 param0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "floor_div.proven i64") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "add.proven i64"));
    // Index removal no longer constructs a normalization arm to fold.
    try std.testing.expect(std.mem.indexOf(u8, text, "branch 0:bool") == null);
}

/// The facts of the function named `name` in `source`, analysed alone.
fn factsOf(arena: std.mem.Allocator, source: []const u8, name: []const u8) !?struct { function: @import("ir.zig").Function, known: facts.Facts } {
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(arena, source, &refusal);
    for (module.functions.items) |function| {
        if (!std.mem.endsWith(u8, function.name, name)) continue;
        var copy = function;
        const known = try facts.analyze(arena, &copy, .{});
        return .{ .function = copy, .known = known };
    }
    return null;
}

/// The widest upper bound over the phis of a function's facts.
fn widestPhi(found: anytype) i128 {
    var widest: i128 = std.math.minInt(i128);
    for (found.function.insts.items, found.known.ranges) |inst, range| {
        if (inst.op == .phi) widest = @max(widest, (range orelse facts.Interval{ .lo = 0, .hi = std.math.maxInt(i128) }).hi);
    }
    return widest;
}

// spec-case: NEW-CORE-FACTS-4
test "the search loop's phis widen to the 2^47 threshold, not to the i64 range" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const found = (try factsOf(arena.allocator(), searching, "search")).?;
    // `low` and `high` settle at 2^47 (and the joins feeding them at most 2^47 + 1).
    try std.testing.expect(widestPhi(found) <= facts.max_list_length + 1);
    try std.testing.expect(widestPhi(found) >= facts.max_list_length);
}

// spec-case: NEW-CORE-FACTS-4
test "widening moves a growing bound to the nearest threshold that holds it and keeps a bound that stays" {
    const limits = facts.typeRange(.i64).?;
    const big = facts.max_list_length;
    const grown = facts.widen(.{ .lo = 0, .hi = 5 }, .{ .lo = 0, .hi = 7 }, limits, .none);
    try std.testing.expectEqual(facts.Interval{ .lo = 0, .hi = big }, grown);
    try std.testing.expectEqual(facts.Interval{ .lo = 0, .hi = big + 1 }, facts.widen(.{ .lo = 0, .hi = big }, .{ .lo = 0, .hi = big + 1 }, limits, .none));
    try std.testing.expectEqual(limits.hi, facts.widen(.{ .lo = 0, .hi = big + 1 }, .{ .lo = 0, .hi = big + 2 }, limits, .none).hi);
    // Downward: 0 is the only threshold below 2^47; past it the type's minimum.
    try std.testing.expectEqual(@as(i128, 0), facts.widen(.{ .lo = 9, .hi = 9 }, .{ .lo = 3, .hi = 9 }, limits, .none).lo);
    try std.testing.expectEqual(limits.lo, facts.widen(.{ .lo = 0, .hi = 9 }, .{ .lo = -1, .hi = 9 }, limits, .none).lo);
    // A bound that stays inside the old interval keeps the old bound.
    try std.testing.expectEqual(facts.Interval{ .lo = 0, .hi = big }, facts.widen(.{ .lo = 0, .hi = big }, .{ .lo = 2, .hi = 3 }, limits, .none));
    // Thresholds outside a narrow type do not apply.
    try std.testing.expectEqual(@as(i128, 255), facts.widen(.{ .lo = 0, .hi = 1 }, .{ .lo = 0, .hi = 2 }, facts.typeRange(.u8).?, .none).hi);
    // The sabotaged rule rounds toward the inside: the interval no longer holds the value.
    try std.testing.expectEqual(@as(i128, 0), facts.widen(.{ .lo = 0, .hi = 5 }, .{ .lo = 0, .hi = 7 }, limits, .widening).hi);
}

const almost_searching =
    \\func wide(values: int[], key: int) -> int:
    \\    mut low = 0
    \\    mut high = len(values) + 1
    \\    while low < high:
    \\        mut middle = (low + high) // 2
    \\        if values[middle] < key:
    \\            low = middle + 1
    \\        else:
    \\            high = middle
    \\    return low
    \\
    \\
    \\func inclusive(values: int[], key: int) -> int:
    \\    mut low = 0
    \\    mut high = len(values)
    \\    while low <= high:
    \\        mut middle = (low + high) // 2
    \\        if values[middle] < key:
    \\            low = middle + 1
    \\        else:
    \\            high = middle - 1
    \\    return low
    \\
    \\
    \\func other(values: int[], keys: int[], key: int) -> int:
    \\    mut low = 0
    \\    mut high = len(values)
    \\    while low < high:
    \\        mut middle = (low + high) // 2
    \\        if keys[middle] < key:
    \\            low = middle + 1
    \\        else:
    \\            high = middle
    \\    return low
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, wide([1, 3, 5], 4) + inclusive([1, 3, 5], 4) + other([1, 3, 5], [2, 4], 4))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-5
test "a search whose high may reach the length, or that reads another list, keeps its bounds check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), almost_searching);
    // `len + 1`, `low <= high` and `keys[middle]` with `high` bounded by `values`: none is provable.
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact i64 param0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact i64 param1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.proven") == null);
}

const guarded_reads =
    \\func first_or_zero(values: int[], i: int) -> int:
    \\    if i >= 0:
    \\        if i < len(values):
    \\            return values[i]
    \\    return 0
    \\
    \\
    \\func total(values: int[]) -> int:
    \\    mut acc = 0
    \\    for j in range(len(values)):
    \\        acc += values[j] % 7
    \\    return acc
    \\
    \\
    \\func off_by_one(values: int[], i: int) -> int:
    \\    if i >= 0:
    \\        if i <= len(values):
    \\            return values[i]
    \\    return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, first_or_zero([1, 2], 1) + total([3, 4]) + off_by_one([5], 0))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-FACTS-5
test "a read under index < len(list) of a list parameter needs no bounds check, under index <= len it keeps it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), guarded_reads);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "list_get.proven i64 param0"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "list_get.exact i64 param0"));
}

const huge_reduction =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args)
    \\    mut total = 0
    \\    for j in range(0 - 9223372036854775807, n):
    \\        total += 4611686018427387904
    \\    print(out, total)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-FACTS-2
test "a reduction whose bound exceeds every integer type is clamped, not overflowed, and keeps its check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), huge_reduction);
    try std.testing.expect(std.mem.indexOf(u8, text, "add.exact i64") != null);
}

// spec-case: DEBUG-OPTIMIZE-1
test "unsigned negation is provable only for zero across every integer width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "u8", "u16", "u32", "u64" }) |ty| {
        const source = try std.fmt.allocPrint(arena.allocator(), "func negate(x: {s}) -> {s}:\n    return -x\n\n" ++
            "func zero() -> {s}:\n    mut x = 0{s}\n    return -x\n\n" ++
            "func one() -> {s}:\n    mut x = 1{s}\n    return -x\n\n" ++
            "func main(args: str[], out: Stream) -> int:\n    print(out, negate({s}(len(args))), zero(), one())\n    return 0\n", .{ ty, ty, ty, ty, ty, ty, ty });
        const text = try support.factsText(arena.allocator(), source);
        const exact = try std.fmt.allocPrint(arena.allocator(), "neg.exact {s}", .{ty});
        const proven = try std.fmt.allocPrint(arena.allocator(), "neg.proven {s}", .{ty});
        try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, exact));
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, proven));
    }
}

const guarded_sums =
    \\func one_side(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        if value <= 100:
    \\            total += value
    \\    return total
    \\
    \\func skipped(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        if value > 100:
    \\            continue
    \\        total += value
    \\    return total
    \\
    \\func both_sides(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        if value <= 100:
    \\            if value >= -100:
    \\                total += value
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, one_side([1, 200]) + skipped([2, 300]) + both_sides([3, -300]))
    \\    return 0
    \\
;

/// Whether some integer phi of the function `name` in `source` is stated `[lo, hi]` by the fact pass.
fn statesPhi(a: std.mem.Allocator, source: []const u8, name: []const u8, lo: i128, hi: i128) !bool {
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    for (module.functions.items) |*function| {
        if (std.mem.indexOf(u8, function.name, name) == null) continue;
        const known = try facts.analyze(a, function, .{});
        for (function.insts.items, 0..) |inst, at| {
            const range = known.ranges[at] orelse continue;
            if (inst.op == .phi and inst.ty == .i64 and range.lo == lo and range.hi == hi) return true;
        }
    }
    return false;
}

// spec-case: NEW-CORE-FACTS-3
test "a reduction keeps its trips-times-step bound only where the bound stays inside the type, so the checker can state it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const full = facts.typeRange(.i64).?;
    const reach = facts.max_list_length * 100;
    // `-100 <= value <= 100` bounds the sum by 100 * 2^47 on both sides, inside i64: stated.
    try std.testing.expect(try statesPhi(a, guarded_sums, "both_sides", -reach, reach));
    // `value <= 100` alone bounds the sum above, but below its bound is 2^47 * i64's minimum: the sum
    // takes the plain phi rule's interval, and its top is not the clipped `100 * 2^47` that F4 cannot state.
    try std.testing.expect(try statesPhi(a, guarded_sums, "one_side", full.lo, full.hi));
    try std.testing.expect(!try statesPhi(a, guarded_sums, "one_side", full.lo, reach));
    try std.testing.expect(try statesPhi(a, guarded_sums, "skipped", full.lo, full.hi));
    try std.testing.expect(!try statesPhi(a, guarded_sums, "skipped", full.lo, reach));
}

const dead_arm_join =
    \\func make() -> bytes:
    \\    return b"x"
    \\
    \\func dead_join() -> int:
    \\    const ok = True
    \\    const got: bytes
    \\    if ok:
    \\        got = make()
    \\    else:
    \\        got = make()
    \\    return len(got)
    \\
    \\func of_parameter(data: bytes) -> int:
    \\    return len(data)
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, dead_join() + of_parameter(b"abc"))
    \\    return 0
    \\
;

/// The length bound the fact pass gives the first `list_len` of the function `name` in `source`.
fn firstLengthBound(a: std.mem.Allocator, source: []const u8, name: []const u8) !?facts.LengthBound {
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    for (module.functions.items) |*function| {
        if (std.mem.indexOf(u8, function.name, name) == null) continue;
        const known = try facts.analyze(a, function, .{});
        for (function.insts.items, 0..) |inst, at| {
            if (inst.op == .list_len) return known.bounds[at];
        }
    }
    return error.NoSuchFunction;
}

test "a length bound never names a bytes value that does not dominate the join the facts reach it through" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `if True` leaves the else arm dead for the facts, but `--verify-facts` still emits it: its edge reaches the join, so
    // the call result of the live arm is no source the join's length can be bounded by.
    const joined = try firstLengthBound(a, dead_arm_join, "dead_join");
    try std.testing.expectEqual(@as(?facts.LengthBound, .{}), joined);
    // A parameter is defined by the entry, which dominates everything: its length still bounds `len(data)`.
    const parameter = (try firstLengthBound(a, dead_arm_join, "of_parameter")).?;
    try std.testing.expect(parameter.list != .none);
    try std.testing.expectError(error.NoSuchFunction, firstLengthBound(a, dead_arm_join, "absent_function"));
}
