//! Lane F2 (docs/audits/runtime-parity-plan-2026-10-08.md §8): index facts. A written index
//! is tested as written before its normalization from the end; a fill loop's length holds
//! only once the loop has exited; a dominating `i < len(other)` proves an access to a list of
//! the same length; a dominating check proves the accesses with its index and length. Every
//! expected output is the base compiler's (main 35df839be) for the same program, except
//! `fill_inside`, which the base answered wrongly in release builds.
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

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.my` with `flags` and run it with `args` under the leak check.
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}-{d}", .{ root, name, flags.len, if (flags.len > 1) flags[1].len else 0 });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

const written_index =
    \\def at(xs: list[int], i: int) -> int:
    \\    return xs[i]
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    xs = [1, 2, 3]
    \\    out.print(at(xs, 1), at(xs, -1))
    \\    return 0
    \\
;

// spec: NEW-CORE-F2-WRAP-1
test "F2 index: a written index is tested as written first: only an index outside [0, len) takes its normalization and check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), written_index);
    const at = try definition(llvm, "@\"my.at\"");
    // The written index `%p1` is compared unsigned with the length; only its failure goes to the
    // block that checks the normalized index, and the element's address takes `%p1` on the hot path.
    try std.testing.expect(contains(at, "%rawout"));
    try std.testing.expect(contains(at, " = icmp uge i64 %p1, %len"));
    try std.testing.expect(contains(at, "label %wrapped"));
    try std.testing.expect(contains(at, " = phi i64 [ %p1, "));
    // A debug build takes the same shape: the check is the same check.
    const debug = try support.llvmText(arena.allocator(), written_index);
    try std.testing.expect(contains(try definition(debug, "@\"my.at\""), "%rawout"));
}

// spec-case: NEW-CORE-F2-WRAP-1
test "F2 index: written indexes keep every answer and trap where they must: negatives that wrap, one-path negatives, too-negative indexes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f2_index", flags, &.{});
        try std.testing.expectEqualStrings("1410091606\n33 77\n135\n202 302\n405 1\n8007 5 9\n1341\n11860\n801\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "f2_index", flags, &.{ "all", "x" });
        try std.testing.expectEqualStrings("1420091706\n33 22\n165\n202 302\n405 1\n8007 5 9\n1353\n11861\n109\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
        const next = try leakChecked(a, root, "f2_index", flags, &.{"next_trap"});
        try std.testing.expectEqual(@as(u8, 1), next.status);
        try std.testing.expect(contains(next.stderr, "f2_index.my:163:9: error[R_LIST_BOUNDS]: native execution failed (index 7, length 7)"));
    }
}

const fill_loops =
    \\def inside(n: int) -> int:
    \\    zs: list[int] = []
    \\    total = 0
    \\    for i in range(n):
    \\        total = total + zs[i]
    \\        zs.append(i)
    \\    return total
    \\
    \\
    \\def after(n: int) -> int:
    \\    ys: list[int] = []
    \\    for i in range(n):
    \\        ys.append(i)
    \\    total = 0
    \\    for i in range(n):
    \\        total = total + ys[i]
    \\    return total
    \\
    \\
    \\def sieve(n: int) -> int:
    \\    flags = [True for _ in range(n + 1)]
    \\    j = 4
    \\    while j <= n:
    \\        flags[j] = False
    \\        j = j + 2
    \\    count = 0
    \\    for flag in flags:
    \\        if flag:
    \\            count += 1
    \\    return count
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    out.print(inside(len(args)), after(4), sieve(20000))
    \\    return 0
    \\
;

// spec: NEW-CORE-F2-INDEX-1
test "F2 index: a fill loop's length holds only after the loop: a read inside it keeps its check, a read after it or below the bound does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), fill_loops);
    // Inside its fill loop the list is shorter than the bound: the read is checked.
    try std.testing.expect(contains(functionIr(text, "inside"), "list_get.exact"));
    // After the loop, `i < n` with `n` the fill bound proves the read.
    try std.testing.expect(!contains(functionIr(text, "after"), "list_get.exact"));
    // `flags[j]` with `j <= n` and a list of `n + 1` flags (the bound's least value is above `j`).
    const sieve = functionIr(text, "sieve");
    try std.testing.expect(contains(sieve, "list_set.proven"));
    try std.testing.expect(!contains(sieve, "list_set.exact"));
}

// spec-case: NEW-CORE-F2-INDEX-1
test "F2 index: a list read inside its own fill loop traps in every build mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const ran = try leakChecked(a, root, "f2_index", flags, &.{"fill_inside"});
        try std.testing.expectEqual(@as(u8, 1), ran.status);
        try std.testing.expect(contains(ran.stderr, "f2_index.my:59:25: error[R_LIST_BOUNDS]: native execution failed (index 0, length 0)"));
    }
}

const same_lengths =
    \\record Stack:
    \\    items: list[int]
    \\    top: int
    \\
    \\
    \\def scale(xs: list[int]) -> int:
    \\    ys = xs
    \\    ys[0] = 7
    \\    total = 0
    \\    for i in range(len(xs)):
    \\        total = total + ys[i]
    \\    return total
    \\
    \\
    \\def tally(flags: list[bool]) -> int:
    \\    count = 0
    \\    for flag in flags:
    \\        if flag:
    \\            count += 1
    \\    return count
    \\
    \\
    \\def peek_all(s: Stack) -> int:
    \\    total = 0
    \\    for i in range(len(s.items)):
    \\        total = total + s.items[i]
    \\    return total
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(scale([1, 2]), tally([True, False]), peek_all(Stack(items=[3, 4], top=0)))
    \\    return 0
    \\
;

// spec: NEW-CORE-F2-INDEX-2
test "F2 index: a dominating `i < len(other)` proves an access to a list of the same length: a written copy, an iterated list, a record's list field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), same_lengths);
    // `ys` is `xs` with one element written: the same length, so `ys[i]` under `i < len(xs)`.
    try std.testing.expect(contains(functionIr(text, "scale"), "list_get.proven"));
    try std.testing.expect(!contains(functionIr(text, "tally"), "list_get.exact"));
    // Two reads of one field of one record are one list.
    try std.testing.expect(!contains(functionIr(text, "peek_all"), "list_get.exact"));
}

const dominating =
    \\def swap(xs: mut list[int], i: int, j: int) -> int:
    \\    a = xs[i]
    \\    b = xs[j]
    \\    xs[i] = b
    \\    xs[j] = a
    \\    return a - b
    \\
    \\
    \\def shrink(xs: mut list[int], i: int) -> int:
    \\    a = xs[i]
    \\    _ = xs.pop()
    \\    return a + xs[i]
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    xs = [1, 2, 3]
    \\    n = len(args)
    \\    out.print(swap(mut xs, n, 0 - n), shrink(mut xs, n))
    \\    return 0
    \\
;

// spec: NEW-CORE-F2-INDEX-3
test "F2 index: an access a dominating check covers is proven: the same index and length, a written index after either kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), dominating);
    // The writes reuse the reads' indexes on a list of the same length (a copy keeps it).
    const swap = functionIr(text, "swap");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, swap, "list_get.exact"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, swap, "list_set.proven"));
    // A pop between the reads changes the length: the second read keeps its check (the third
    // checked read is the pop's own read of the last element).
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, functionIr(text, "shrink"), "list_get.exact"));
}

// spec-case: NEW-CORE-F2-INDEX-3
test "F2 index: dominating checks keep every answer and trap where they must: a pop between reads, a field written between reads, a shorter list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const shrink = try leakChecked(a, root, "f2_index", flags, &.{"shrink_trap"});
        try std.testing.expectEqual(@as(u8, 1), shrink.status);
        try std.testing.expect(contains(shrink.stderr, "f2_index.my:79:9: error[R_LIST_BOUNDS]: native execution failed (index 3, length 3)"));
        const loop = try leakChecked(a, root, "f2_index", flags, &.{ "loop_shrink", "x" });
        try std.testing.expectEqual(@as(u8, 1), loop.status);
        try std.testing.expect(contains(loop.stderr, "f2_index.my:91:25: error[R_LIST_BOUNDS]: native execution failed (index 3, length 3)"));
        const bump = try leakChecked(a, root, "f2_index", flags, &.{"bump_trap"});
        try std.testing.expectEqual(@as(u8, 1), bump.status);
        try std.testing.expect(contains(bump.stderr, "f2_index.my:104:9: error[R_LIST_BOUNDS]: native execution failed (index 3, length 3)"));
        const shorter = try leakChecked(a, root, "f2_index", flags, &.{"same_length_trap"});
        try std.testing.expectEqual(@as(u8, 1), shorter.status);
        try std.testing.expect(contains(shorter.stderr, "f2_index.my:136:25: error[R_LIST_BOUNDS]: native execution failed (index 7, length 7)"));
    }
}

// spec: NEW-CORE-F2-INDEX-4
test "F2 index: a verify build catches a dominating check taken to cover the next index too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const ran = try leakChecked(a, root, "f2_index", &.{ "--release", "--sabotage-facts=index" }, &.{"next_trap"});
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(contains(ran.stderr, "f2_index.my:163:9: error[R_CORE_FACT]: native execution failed (index: value 7, other 7)"));
    // Unsabotaged, the same program traps on the index itself.
    const plain = try leakChecked(a, root, "f2_index", &.{ "--release", "--verify-facts" }, &.{"next_trap"});
    try std.testing.expect(contains(plain.stderr, "error[R_LIST_BOUNDS]"));
}

const field_writes =
    \\record Slot:
    \\    index: int
    \\
    \\
    \\record Loose:
    \\    v: int
    \\
    \\
    \\def pick(s: Slot) -> int:
    \\    table = [5, 6, 7, 8]
    \\    return table[s.index]
    \\
    \\
    \\def use(b: Loose) -> int:
    \\    table = [5, 6]
    \\    return table[b.v]
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    s = Slot(index=0)
    \\    total = 0
    \\    for k in range(len(args) + 3):
    \\        s.index = k % 4
    \\        total = total + pick(s)
    \\    reader = use
    \\    out.print(total, reader(Loose(v=1)), use(Loose(v=0)))
    \\    return 0
    \\
;

// spec: NEW-CORE-F2-FIELD-1
test "F2 index: a field read takes the hull of every value the program writes into the field: no wrap, no check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), field_writes);
    // `pick` sees only its parameter, but every `Slot.index` written is `k % 4` with `k >= 0`:
    // the normalization from the end is folded away and the read of a 4-element list is proven.
    const pick = functionIr(text, "pick");
    try std.testing.expect(contains(pick, "list_get.proven"));
    try std.testing.expect(!contains(pick, "cmp.lt bool"));
}

// spec: NEW-CORE-F2-FIELD-2
test "F2 index: a record type a value from outside the program may hold has no field interval" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), field_writes);
    // `use` is a function value, so it may be called with a `Loose` the program did not
    // make: its field keeps the type's range, and the read keeps its normalization and check.
    const use = functionIr(text, "use");
    try std.testing.expect(contains(use, "list_get.exact"));
    try std.testing.expect(contains(use, "cmp.lt bool"));
}

// spec-case: NEW-CORE-F2-FIELD-1
test "F2 index: field intervals keep every answer: fields written negative far away, element field stores, copies, recursion, function values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "f2_fields", flags, &.{});
        try std.testing.expectEqualStrings("9040 39050\n403030\n50 40\n40 20\n63\n6 6\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "f2_fields", flags, &.{ "all", "x" });
        try std.testing.expectEqualStrings("14151 44751\n201051\n40 40\n30 20\n70\n14 6\n", more.stdout);
        const deep = try leakChecked(a, root, "f2_fields", flags, &.{"deep"});
        try std.testing.expectEqual(@as(u8, 1), deep.status);
        try std.testing.expect(contains(deep.stderr, "f2_fields.my:63:16: error[R_LIST_BOUNDS]: native execution failed (index -6, length 5)"));
    }
}

// spec: NEW-CORE-F2-FIELD-3
test "F2 index: a verify build catches a field interval that lost its top" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const sabotaged: []const []const u8 = &.{ "--release", "--sabotage-facts=field" };
    const slots = try leakChecked(a, root, "f2_fields", sabotaged, &.{"slots"});
    try std.testing.expectEqual(@as(u8, 1), slots.status);
    try std.testing.expect(contains(slots.stderr, "f2_fields.my:84:18: error[R_CORE_FACT]: native execution failed (range [0, 2]: value 3"));
    const small = try leakChecked(a, root, "f2_fields", sabotaged, &.{ "small", "x" });
    try std.testing.expectEqual(@as(u8, 1), small.status);
    try std.testing.expect(contains(small.stderr, "error[R_CORE_FACT]: native execution failed (range [3, 6]: value 7"));
}
