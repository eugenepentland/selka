//! Lane F1 (docs/audits/runtime-parity-plan-2026-10-08.md §8): element data tagged by
//! scalar type, no store-back of an unchanged element pointer, and overflow facts for
//! counters, loop variables and floor-mod results. Every expected output is the base
//! compiler's (main cafe7fea7) for the same program and arguments.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The LLVM definition whose `define` line names `symbol`, up to its closing brace.
fn definition(llvm: []const u8, symbol: []const u8) ![]const u8 {
    var lines = std.mem.splitScalar(u8, llvm, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "define ") or std.mem.indexOf(u8, line, symbol) == null) continue;
        const start = @intFromPtr(line.ptr) - @intFromPtr(llvm.ptr);
        const end = std.mem.indexOfPos(u8, llvm, start, "\n}\n") orelse llvm.len;
        return llvm[start..end];
    }
    return error.TestUnexpectedResult;
}

/// How many lines of `text` contain both `first` and `second`.
fn linesWith(text: []const u8, first: []const u8, second: []const u8) usize {
    var total: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (contains(line, first) and contains(line, second)) total += 1;
    }
    return total;
}

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.selka` with `flags` and run it with `args` under the leak check.
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}", .{ root, name, flags.len });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

const tagged_elements =
    \\record P:
    \\    x: float
    \\    n: int
    \\
    \\
    \\enum Num:
    \\    i(value: int)
    \\    f(value: float)
    \\
    \\
    \\func touch(mut xs: float[], mut rows: int[][], mut ps: P[], mut us: Num[], k: int) -> int:
    \\    xs[k] = xs[k] + 1.0
    \\    rows[k][k] = rows[k][k] + 1
    \\    ps[k].x = ps[k].x * 2.0
    \\    us[k] = Num.f(value=float(k))
    \\    return len(rows[k]) + ps[k].n
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1.5, 2.5]
    \\    mut rows = [[1, 2], [3, 4]]
    \\    mut ps = [P(x=1.0, n=2), P(x=3.0, n=4)]
    \\    mut us = [Num.i(value=1), Num.f(value=2.0)]
    \\    out.print(touch(mut xs, mut rows, mut ps, mut us, 1), xs[1], rows[1][1], ps[1].x)
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-TBAA-1
test "list element data is tagged by its scalar type, and union words keep the generic data tag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), tagged_elements);
    // The element tags are children of `myl.data`, so the generic tag aliases each of them.
    try std.testing.expect(contains(llvm, "!11 = !{!\"myl.data.double\", !6, i64 0}\n!12 = !{!11, !11, i64 0}\n"));
    try std.testing.expect(contains(llvm, "!13 = !{!\"myl.data.i64\", !6, i64 0}\n!14 = !{!13, !13, i64 0}\n"));
    try std.testing.expect(contains(llvm, "!21 = !{!\"myl.data.ptr\", !6, i64 0}\n!22 = !{!21, !21, i64 0}\n"));
    const touch = try definition(llvm, "@\"my.touch\"");
    // A float element, a row pointer, an int element and a record's float field each carry
    // their scalar's tag.
    try std.testing.expect(linesWith(touch, "store double", "!tbaa !12") >= 2);
    try std.testing.expect(linesWith(touch, "load double", "!tbaa !12") >= 2);
    try std.testing.expect(linesWith(touch, "load ptr", "!tbaa !22") >= 1);
    try std.testing.expect(linesWith(touch, "store i64", "!tbaa !14") >= 1);
    // The union element's tag word is stored with the generic tag, and so is its payload:
    // its cases share the payload word.
    try std.testing.expect(linesWith(touch, "store i64", "!tbaa !7") >= 1);
    try std.testing.expect(linesWith(touch, "store double", "!tbaa !7") >= 1);
}

// spec: NEW-CORE-F1-TBAA-2
test "the inline free orders every access before it: a compiler barrier precedes the free-list push" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), tagged_elements);
    const free = try definition(llvm, "@myl_core_free(");
    const barrier = std.mem.indexOf(u8, free, "call void asm sideeffect \"\", \"~{memory}\"()") orelse return error.TestUnexpectedResult;
    const push = std.mem.indexOf(u8, free, "store ptr %block, ptr %slot") orelse return error.TestUnexpectedResult;
    try std.testing.expect(barrier < push);
}

// spec-case: NEW-CORE-F1-TBAA-1
test "typed element tags keep every answer: records copied whole, unions, mixed lists, reused blocks, aliasing rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f1_tbaa", flags, &.{});
        try std.testing.expectEqualStrings("6077 67108861 671088849\n902 30518 100056\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "f1_tbaa", flags, &.{ "x", "y" });
        try std.testing.expectEqualStrings("6234 234881021 968884428\n5055 31739 100084\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
}

const store_backs =
    \\func fill(n: int) -> int:
    \\    mut c = [for i in range(n) yield [for j in range(n) yield 0.5]]
    \\    for i in range(n):
    \\        for j in range(n):
    \\            c[i][j] = c[i][j] + float(j)
    \\    return int(c[n - 1][n - 1])
    \\
    \\
    \\func scale(mut c: float[][], n: int):
    \\    for i in range(n):
    \\        for j in range(n):
    \\            c[i][j] = c[i][j] * 2.0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut rows = [[1.0, 2.0], [3.0, 4.0]]
    \\    scale(mut rows, 2)
    \\    out.print(fill(4), rows[1][1])
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-STOREBACK-1
test "a row updated in place is not stored back; a row copy on write may move is stored only when it moved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), store_backs);
    // `fill`'s rows are unique, so `c[i][j] = …` updates the row in place and its pointer
    // never changes: the only element pointer store left is the comprehension's push.
    const fill = try definition(llvm, "@\"my.fill\"");
    try std.testing.expectEqual(@as(usize, 1), linesWith(fill, "store ptr", "!tbaa !22"));
    try std.testing.expect(!contains(fill, "%moved"));
    // `scale`'s rows may be shared, so the row's update may copy it: every store-back
    // runs only when the pointer differs from the one the slot holds.
    const scale = try definition(llvm, "@\"my.scale\"");
    const moved = linesWith(scale, "%moved", "icmp ne ptr");
    try std.testing.expect(moved >= 1);
    try std.testing.expectEqual(moved, linesWith(scale, "store ptr", "!tbaa !22"));
}

// spec-case: NEW-CORE-F1-STOREBACK-1
test "store-backs keep every answer: shared rows, rows replaced in the loop, aliasing rows, break and early return, list fields and text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f1_storeback", flags, &.{});
        try std.testing.expectEqualStrings("7000070 600 457114\n-2513 -2993 -3000 8053\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "f1_storeback", flags, &.{ "x", "y" });
        try std.testing.expectEqualStrings("25970094 1750 1399118\n-10353 -11753 -11760 14003\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
}

/// The text of one function in a module's textual IR, from its header to the next function.
fn functionIr(text: []const u8, name: []const u8) []const u8 {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, text, start, "fn ")) |header| {
        const line_end = std.mem.indexOfScalarPos(u8, text, header, '\n') orelse text.len;
        const line = text[header..line_end];
        const paren = std.mem.indexOfScalar(u8, line, '(') orelse line.len;
        if (std.mem.endsWith(u8, line[0..paren], name)) {
            const next = std.mem.indexOfPos(u8, text, line_end, "\nfn ") orelse text.len;
            return text[header..next];
        }
        start = line_end;
    }
    return "";
}

const counted_growth =
    \\func scan(data: bytes) -> int:
    \\    mut count = 0
    \\    for pass_index in range(16):
    \\        count += pass_index
    \\        for i in range(len(data)):
    \\            if data[i] == 109:
    \\                count += 1
    \\    return count
    \\
    \\
    \\func tally(flags: bool[]) -> int:
    \\    mut count = 0
    \\    for flag in flags:
    \\        if flag:
    \\            count += 1
    \\    return count
    \\
    \\
    \\func total(xs: int[]) -> int:
    \\    mut t = 0
    \\    for x in xs:
    \\        t += x
    \\    return t
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(scan(b"mmx"), tally([True, False]), total([1, 2]))
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-OVERFLOW-1
test "a counter that grows by a bounded step per iteration, conditionally or through an inner counted loop, never overflows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), counted_growth);
    // `count += pass_index` and the inner `count += 1` (under a condition) are proven: at most
    // 16 passes of at most `max_list_length` bytes each.
    const scan = functionIr(text, "scan");
    try std.testing.expect(!contains(scan, "add.exact"));
    try std.testing.expect(contains(scan, "add.proven i64"));
    // A conditional `count += 1` over a list's elements.
    try std.testing.expect(!contains(functionIr(text, "tally"), "add.exact"));
    // A step the facts cannot bound keeps its check.
    try std.testing.expect(contains(functionIr(text, "total"), "add.exact"));
}

const loop_conditions =
    \\func sieve() -> int:
    \\    mut n = 20000000
    \\    mut flags = [for _ in range(n + 1) yield True]
    \\    mut i = 2
    \\    while i * i <= n:
    \\        if flags[i]:
    \\            mut j = i * i
    \\            while j <= n:
    \\                flags[j] = False
    \\                j = j + i
    \\        i = i + 1
    \\    return len(flags)
    \\
    \\
    \\func drift(n: int) -> int:
    \\    mut j = 0
    \\    mut limit = n
    \\    while j <= limit:
    \\        j = j + 3
    \\        limit = limit + 1
    \\    return j
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(sieve(), drift(10))
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-OVERFLOW-2
test "a loop variable is bounded by its loop condition, and `i * i <= n` bounds `i` by the square root of `n`" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), loop_conditions);
    const sieve = functionIr(text, "sieve");
    // `j = i * i`, `j = j + i` and `i = i + 1` are proven: `i <= 4472` in the body, `j <= 20000000`.
    // The condition's own `i * i` keeps its check, as do the index normalizations nothing reaches.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, sieve, "mul.proven i64"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, sieve, "mul.exact i64"));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, sieve, "add.proven i64"));
    // A bound that moves in the body bounds nothing: `j + 3` keeps its check.
    try std.testing.expect(contains(functionIr(text, "drift"), "add.exact"));
}

const callee_ranges =
    \\func step(a: int, b: int) -> int:
    \\    return (a + b) % 1000003
    \\
    \\
    \\func signed_step(a: int, b: int) -> int:
    \\    return (a + b) % 1000003
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut total = 0
    \\    mut other = 0
    \\    for i in range(30000000):
    \\        total = step(total, i)
    \\        other = signed_step(other, i - 5)
    \\    out.print(total, other)
    \\    return 0
    \\
;

// spec: NEW-CORE-F1-OVERFLOW-3
test "a call returns its callee's return interval, so floor modulo of non-negative arguments needs no fix-up" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), callee_ranges);
    // `total` is a result of `step`, in [0, 1000002], and `i` is non-negative: the sum cannot
    // overflow and is non-negative, so the remainder is unsigned and needs no floor fix-up.
    const step = functionIr(text, "step");
    try std.testing.expect(contains(step, "add.proven i64 param0, param1"));
    try std.testing.expect(contains(step, "floor_rem.proven i64"));
    // One argument may be negative (`i - 5`): the floor remainder keeps its fix-up.
    try std.testing.expect(contains(functionIr(text, "signed_step"), "floor_rem.exact i64"));
}

// spec: NEW-CORE-F1-OVERFLOW-4
test "a proven 64-bit division or remainder whose operands fit in 32 bits masks them to their low 32 bits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), callee_ranges);
    const step = try definition(llvm, "@\"my.step\"");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, step, " = and i64 "));
    try std.testing.expect(contains(step, ", 4294967295\n"));
    try std.testing.expect(contains(step, " = urem i64 %nl."));
    try std.testing.expect(!contains(step, "srem"));
    // A verify build never narrows: the facts are what it checks.
    const verify = try support.verifyLlvmText(arena.allocator(), callee_ranges);
    try std.testing.expect(!contains(try definition(verify, "@\"my.step\""), "4294967295"));
}

// spec-case: NEW-CORE-F1-OVERFLOW-1
test "overflow facts keep every answer and trap where they must: counters near the top, unbounded steps, moving bounds, negative modulo arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f1_overflow", flags, &.{});
        try std.testing.expectEqualStrings("101\n3\n41\n1229 25\n4\n6\n14114\n49950029970031\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const moving = try leakChecked(a, root, "f1_overflow", flags, &.{ "moving", "x", "x", "x" });
        try std.testing.expectEqualStrings("16117\n", moving.stdout);
        // A counter that starts near the top of `int` traps once it leaves it.
        const near = try leakChecked(a, root, "f1_overflow", flags, &.{ "near", "x" });
        try std.testing.expectEqual(@as(u8, 1), near.status);
        try std.testing.expect(contains(near.stderr, "f1_overflow.selka:52:19: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 1, width 64)"));
        // A step the facts cannot bound traps too.
        const huge = try leakChecked(a, root, "f1_overflow", flags, &.{"huge"});
        try std.testing.expectEqual(@as(u8, 1), huge.status);
        try std.testing.expect(contains(huge.stderr, "f1_overflow.selka:60:15: error[R_OVERFLOW]: native execution failed (add: left 4611686018427387904, right 4611686018427387904, width 64)"));
    }
}

// spec: NEW-CORE-F1-OVERFLOW-5
test "a verify build catches each overflow rule made one off on the inside: counter growth, square roots, return intervals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const sabotaged: []const []const u8 = &.{ "--release", "--sabotage-facts=overflow" };
    const counter = try leakChecked(a, root, "f1_overflow", sabotaged, &.{"counter"});
    try std.testing.expectEqual(@as(u8, 1), counter.status);
    try std.testing.expect(contains(counter.stderr, "error[R_CORE_FACT]: native execution failed (range [0, 0]: value 1"));
    try std.testing.expect(contains(counter.stderr, "in counter_probe"));
    const square = try leakChecked(a, root, "f1_overflow", sabotaged, &.{"square"});
    try std.testing.expectEqual(@as(u8, 1), square.status);
    try std.testing.expect(contains(square.stderr, "error[R_CORE_FACT]: native execution failed (range [2, 100]: value 101"));
    const returns = try leakChecked(a, root, "f1_overflow", sabotaged, &.{"modulos"});
    try std.testing.expectEqual(@as(u8, 1), returns.status);
    try std.testing.expect(contains(returns.stderr, "error[R_CORE_FACT]: native execution failed (range [0, 5]: value 6"));
}
