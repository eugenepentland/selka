//! Loop range facts and loop versioning (`QBE-LOOP-FACTS-1`,
//! `QBE-LOOP-VERSION-1`): the IL shape of a versioned loop's guard and
//! check-free copy, the loops left alone, and traps that must stay
//! byte-identical to the unversioned lowering.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const fixture_path = "loops.my";
const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { functions: []Unit };

/// One function's IL under the protocol a published executable uses: no step
/// or frame accounting, value guards on (or off, with `checked = false`).
fn functionIl(source: []const u8, name: []const u8, step_checks: bool) ![]u8 {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(t.allocator, .{ .step_checks = step_checks, .frame_checks = false });
    defer t.allocator.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return t.allocator.dupe(u8, unit.il);
    return error.TestUnexpectedResult;
}
fn fastIl(source: []const u8, name: []const u8) ![]u8 {
    return functionIl(source, name, false);
}

/// The versioned parts of one function's IL: everything before the first
/// check-free instruction (prologue, earlier code and the guard), the
/// check-free copy, and the original loop onward.
const Parts = struct { before: []const u8, copy: []const u8, original: []const u8 };
fn parts(il: []const u8) !Parts {
    const copy = std.mem.indexOf(u8, il, "\n@fi") orelse return error.TestUnexpectedResult;
    const original = std.mem.indexOf(u8, il, "\n@oi") orelse return error.TestUnexpectedResult;
    return .{ .before = il[0..copy], .copy = il[copy..original], .original = il[original..] };
}

const list_sum =
    \\def total(xs: list[int]) -> int:
    \\    t = 0
    \\    for i in range(len(xs)):
    \\        t += xs[i]
    \\    return t
    \\
    \\
    \\def main() -> int:
    \\    return total([1, 2, 3])
;

// spec: QBE-LOOP-FACTS-1
test "a counted loop over a list proves its index and counter and keeps the sum's check" {
    const il = try fastIl(list_sum, "total");
    defer t.allocator.free(il);
    const loop = try parts(il);
    // The copy reads `xs[i]` with no bounds test and no negative-index
    // adjustment, and advances `i` unchecked; the unbounded `t += xs[i]` keeps
    // its one overflow test.
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_qbe_fail_normalized_index_bounds"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, loop.copy, "myl_qbe_fail_overflow_op"));
    // The original keeps every check it had.
    try t.expect(std.mem.count(u8, loop.original, "myl_qbe_fail_normalized_index_bounds") >= 1);
    try t.expect(std.mem.count(u8, loop.original, "myl_qbe_fail_overflow_op") >= 2);
}

const sieve =
    \\def mark(flags: mut list[bool], i: int, n: int) -> None:
    \\    j = i * i
    \\    while j <= n:
    \\        flags[j] = False
    \\        j = j + i
    \\
    \\
    \\def main() -> int:
    \\    flags = [True for _ in range(30)]
    \\    mark(mut flags, 2, 29)
    \\    count = 0
    \\    for flag in flags:
    \\        if flag:
    \\            count += 1
    \\    return count
;

// spec-case: QBE-LOOP-FACTS-1
test "a while loop with a step held in a local proves its index and its update" {
    // RC-DEFAULT-1: reads the tracing collector's lowering, not the RC default's.
    const collector_runtime = language.runtime_mode.pinCollector();
    defer language.runtime_mode.set(collector_runtime);
    const il = try fastIl(sieve, "mark");
    defer t.allocator.free(il);
    const loop = try parts(il);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_qbe_fail_"));
    // The counter only rises while the step is not negative.
    try t.expect(std.mem.indexOf(u8, loop.before, " csgel ") != null);
}

// spec-case: QBE-LOOP-FACTS-1
test "a for loop's length checks and its counting accumulator are proven" {
    const il = try fastIl(sieve, "main");
    defer t.allocator.free(il);
    const loop = try parts(il);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_qbe_fail_"));
    try t.expect(std.mem.count(u8, loop.original, "myl_qbe_fail_iteration") >= 2);
    var c = try language.Compilation.init(t.allocator, fixture_path, sieve);
    defer c.deinit();
    try t.expectEqual(@as(i64, 17), (try native.runUnaccounted(&c, .{})).value);
}

const spectral =
    \\def a(i: int, j: int) -> float:
    \\    return 1.0 / float((i + j) * (i + j + 1) // 2 + i + 1)
    \\
    \\
    \\def row(v: list[float], i: int) -> float:
    \\    s = 0.0
    \\    for j in range(len(v)):
    \\        s = s + a(i, j) * v[j]
    \\    return s
    \\
    \\
    \\def main() -> int:
    \\    v = [1.0 + float(k) for k in range(20)]
    \\    return int(row(v, 1) * 1000.0)
;

// spec-case: QBE-LOOP-FACTS-1
test "a product of counters is proven under a narrower leaf bound" {
    const il = try fastIl(spectral, "row");
    defer t.allocator.free(il);
    const loop = try parts(il);
    // `(i + j) * (i + j + 1) // 2 + i + 1` is at most 8 * X^2 for leaves
    // bounded by X, which fits 64 bits for X = 2^29 and no wider. No add (0)
    // or multiply (2) keeps its check; the division by 2 keeps its own (5).
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_qbe_fail_overflow_op(l %ctx, l 0,"));
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_qbe_fail_overflow_op(l %ctx, l 2,"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, loop.copy, "myl_qbe_fail_overflow_op(l %ctx, l 5,"));
    // Each leaf is tested as `v + 2^29 <=u 2^30`; a 2^30 bound would test
    // against 2^31.
    try t.expect(std.mem.indexOf(u8, loop.before, ", 536870912\n") != null);
    try t.expect(std.mem.indexOf(u8, loop.before, ", 2147483648\n") == null);
    try t.expect(!(try sameOutcome(spectral)).failed);
}

const matmul =
    \\def kernel(a: list[list[float]], b: list[list[float]], c: mut list[list[float]], n: int) -> None:
    \\    for i in range(n):
    \\        for k in range(n):
    \\            aik = a[i][k]
    \\            for j in range(n):
    \\                c[i][j] = c[i][j] + aik * b[k][j]
    \\
    \\
    \\def main() -> int:
    \\    n = 20
    \\    a = [[1.0 for j in range(n)] for i in range(n)]
    \\    b = [[2.0 for j in range(n)] for i in range(n)]
    \\    c = [[0.0 for j in range(n)] for i in range(n)]
    \\    kernel(a, b, mut c, n)
    \\    return int(c[1][2])
;

// spec-case: QBE-LOOP-FACTS-1
test "invariant rows and their element storage are read once by the guard" {
    const il = try fastIl(matmul, "kernel");
    defer t.allocator.free(il);
    const loop = try parts(il);
    // No storage word (header offset 32) is loaded inside the copy: both rows
    // and both rows' element storage come from the guard.
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, ", 32\n"));
    try t.expect(std.mem.count(u8, loop.before, ", 32\n") >= 2);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_qbe_fail_normalized_index_bounds"));
    var c = try language.Compilation.init(t.allocator, fixture_path, matmul);
    defer c.deinit();
    try t.expectEqual(@as(i64, 40), (try native.runUnaccounted(&c, .{})).value);
}

const unversioned =
    \\def grow(xs: mut list[int], n: int) -> int:
    \\    total = 0
    \\    for i in range(n):
    \\        xs.append(i)
    \\        total += xs[i]
    \\    return total
    \\
    \\
    \\def text(xs: list[int]) -> int:
    \\    size = 0
    \\    for i in range(len(xs)):
    \\        size += len(str(xs[i]))
    \\    return size
    \\
    \\
    \\def main() -> int:
    \\    xs: list[int] = []
    \\    return grow(mut xs, 4) + text(xs)
;

const fills =
    \\def flags(n: int) -> list[bool]:
    \\    return [True for _ in range(n)]
    \\
    \\
    \\def squares(n: int) -> list[int]:
    \\    values = [0 for _ in range(n)]
    \\    values.clear()
    \\    for i in range(n):
    \\        values.append(i * i)
    \\    return values
    \\
    \\
    \\def grown(n: int) -> list[int]:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append(i)
    \\    return values
    \\
    \\
    \\def echoed(n: int) -> list[int]:
    \\    values = [0 for _ in range(n)]
    \\    for i in range(n):
    \\        values.append(len(values))
    \\    return values
    \\
    \\
    \\def main() -> int:
    \\    marks = flags(40)
    \\    total = 0
    \\    for square in squares(40):
    \\        total += square
    \\    for value in grown(40):
    \\        total += value
    \\    for value in echoed(20):
    \\        total += value
    \\    return total + len(marks)
;

// spec-case: QBE-LOOP-FACTS-1
test "an append the list's spare capacity holds is a store with no capacity test" {
    // RC-DEFAULT-1: reads the tracing collector's lowering, not the RC default's.
    const collector_runtime = language.runtime_mode.pinCollector();
    defer language.runtime_mode.set(collector_runtime);
    const il = try fastIl(fills, "flags");
    defer t.allocator.free(il);
    const loop = try parts(il);
    // The copy stores the element and bumps the length and generation it
    // carries; the grow helper and the capacity load are the original's.
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.copy, "myl_native_list_append"));
    try t.expect(std.mem.count(u8, loop.original, "myl_native_list_append") >= 1);
    try t.expect(std.mem.indexOf(u8, loop.before, ", 8\n") != null);
    // A loop that reads the list it appends to keeps one copy: of `echoed`'s
    // two loops only the comprehension is versioned.
    const echoed = try fastIl(fills, "echoed");
    defer t.allocator.free(echoed);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, echoed, "\n@oi"));
}

// spec-case: QBE-LOOP-VERSION-1
test "presized and growing appends build the same lists" {
    // 40 flags, squares 0..39 (20540), 0..39 (780), and 20..39 (590).
    try t.expectEqual(@as(i64, 40 + 20540 + 780 + 590), (try sameOutcome(fills)).value);
    _ = try sameOutcome(
        \\def reciprocal(n: int) -> list[int]:
        \\    return [100 // (i - 17) for i in range(n)]
        \\
        \\
        \\def main() -> int:
        \\    return len(reciprocal(20))
    );
}

/// Require that function `name` of `source` has no check-free copy.
fn expectUnversioned(source: []const u8, name: []const u8) !void {
    const il = try fastIl(source, name);
    defer t.allocator.free(il);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, il, "@fi"));
}

// spec-case: QBE-LOOP-FACTS-1
test "a loop that can resize a list or allocate is not versioned" {
    try expectUnversioned(unversioned, "grow");
    try expectUnversioned(unversioned, "text");
}

// spec-case: QBE-LOOP-FACTS-1
test "a step-accounted build keeps one copy of every loop" {
    const counted = try functionIl(list_sum, "total", true);
    defer t.allocator.free(counted);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, counted, "@fi"));
}

/// Run `source` under both lowerings — the versioned fast protocol and the
/// step-accounted one, which versions nothing — and require the same result:
/// the same value or the same trap code, position, frames, detail and text.
fn sameOutcome(source: []const u8) !native.Run {
    var fast = try language.Compilation.init(t.allocator, fixture_path, source);
    defer fast.deinit();
    const versioned = try native.runUnaccounted(&fast, .{});
    var counted = try language.Compilation.init(t.allocator, fixture_path, source);
    defer counted.deinit();
    const reference = try native.run(&counted);
    try t.expectEqual(reference.failed, versioned.failed);
    try t.expectEqual(reference.value, versioned.value);
    try t.expectEqual(reference.status, versioned.status);
    try t.expectEqualStrings(reference.stdout, versioned.stdout);
    try t.expectEqualStrings(reference.stderr, versioned.stderr);
    try t.expectEqualStrings(reference.trap.code, versioned.trap.code);
    try t.expectEqual(reference.trap.line, versioned.trap.line);
    try t.expectEqual(reference.trap.column, versioned.trap.column);
    try t.expectEqual(reference.trap.frames.len, versioned.trap.frames.len);
    try t.expect(std.meta.eql(reference.trap.detail, versioned.trap.detail));
    return versioned;
}

// Every program below runs its loops for at least `min_span` iterations, so
// the guard reaches its facts instead of stopping at the span test.

// spec: QBE-LOOP-VERSION-1
test "an index the guard cannot prove traps in the original loop at its own iteration" {
    const outcome = try sameOutcome(
        \\def shifted(xs: list[int]) -> int:
        \\    t = 0
        \\    for i in range(len(xs)):
        \\        t += xs[i + 1]
        \\    return t
        \\
        \\
        \\def main() -> int:
        \\    return shifted([i for i in range(20)])
    );
    try t.expectEqualStrings("R_LIST_BOUNDS", outcome.trap.code);
    try t.expectEqual(@as(u64, 4), outcome.trap.line);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "index 20, length 20") != null);
}

// spec-case: QBE-LOOP-VERSION-1
test "a check the guard does not prove still traps inside the check-free copy" {
    const sum = try sameOutcome(
        \\def total(xs: list[int]) -> int:
        \\    t = 0
        \\    for i in range(len(xs)):
        \\        t += xs[i]
        \\    return t
        \\
        \\
        \\def main() -> int:
        \\    xs = [0 for _ in range(20)]
        \\    xs[17] = 9223372036854775000
        \\    xs[18] = 500
        \\    xs[19] = 500
        \\    return total(xs)
    );
    try t.expectEqualStrings("R_OVERFLOW", sum.trap.code);
    try t.expect(std.mem.indexOf(u8, sum.stderr, "left 9223372036854775500, right 500") != null);
    const ratio = try sameOutcome(
        \\def ratio(xs: list[int]) -> int:
        \\    t = 0
        \\    for i in range(len(xs)):
        \\        t += xs[i] // (i - 12)
        \\    return t
        \\
        \\
        \\def main() -> int:
        \\    return ratio([i for i in range(20)])
    );
    try t.expect(ratio.failed);
    try t.expectEqual(@as(u64, 4), ratio.trap.line);
}

// spec-case: QBE-LOOP-VERSION-1
test "an accumulator whose bound the guard rejects overflows at the same increment" {
    const outcome = try sameOutcome(
        \\def count(xs: list[int], start: int) -> int:
        \\    c = start
        \\    for x in xs:
        \\        if x > 0:
        \\            c += 1
        \\    return c
        \\
        \\
        \\def main() -> int:
        \\    return count([1 for _ in range(20)], 9223372036854775805)
    );
    try t.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "left 9223372036854775807, right 1") != null);
}

// spec-case: QBE-LOOP-VERSION-1
test "a short row traps where the original loop reaches its end" {
    const outcome = try sameOutcome(
        \\def kernel(c: mut list[list[float]], n: int) -> None:
        \\    for j in range(n):
        \\        c[1][j] = c[1][j] + 1.0
        \\
        \\
        \\def main() -> int:
        \\    c = [[0.0 for _ in range(20)], [0.0 for _ in range(19)]]
        \\    kernel(mut c, 20)
        \\    return 0
    );
    try t.expectEqualStrings("R_LIST_BOUNDS", outcome.trap.code);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "index 19, length 19") != null);
}

// spec-case: QBE-LOOP-VERSION-1
test "negative indices and a negative start take the original loop with Python's meaning" {
    const outcome = try sameOutcome(
        \\def mark(flags: mut list[bool], j0: int, step: int, n: int) -> int:
        \\    j = j0
        \\    marked = 0
        \\    while j <= n:
        \\        flags[j] = False
        \\        marked += 1
        \\        j = j + step
        \\    return marked
        \\
        \\
        \\def reverse(values: mut [32]int, k: int) -> int:
        \\    for i in range(20):
        \\        values[k - i] = i
        \\    return values[0] + values[31]
        \\
        \\
        \\def main() -> int:
        \\    flags = [True for _ in range(40)]
        \\    count = mark(mut flags, -9, 1, 20) + mark(mut flags, 25, 1, 39)
        \\    values: [32]int = [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]
        \\    total = reverse(mut values, 10) + reverse(mut values, 31)
        \\    left = 0
        \\    for flag in flags:
        \\        if flag:
        \\            left += 1
        \\    return count * 10000 + left * 100 + total
    );
    // mark: 30 then 15 flags cleared, 0..20 and 25..39 in all (-9..-1 is
    // 31..39), so 4 are left; reverse(10) counts from the end below 0 and
    // returns 10 + 11, reverse(31) stays in bounds and returns 10 + 0.
    try t.expectEqual(@as(i64, 45 * 10000 + 4 * 100 + 31), outcome.value);
}

// spec-case: QBE-LOOP-VERSION-1
test "a loop shorter than the minimum span runs the original loop" {
    const il = try fastIl(list_sum, "total");
    defer t.allocator.free(il);
    // The guard opens with `bound > entry and bound - entry >=u 16`.
    const guard = (try parts(il)).before;
    try t.expect(std.mem.indexOf(u8, guard, " csgtl ") != null);
    try t.expect(std.mem.indexOf(u8, guard, " cugel ") != null);
    try t.expect(std.mem.indexOf(u8, guard, ", 16\n") != null);
    // Three elements: the original loop runs, with the same result.
    try t.expectEqual(@as(i64, 6), (try sameOutcome(list_sum)).value);
}
