//! CE-A, records in the emitter (docs/audits/values-keys-trap-search-plan-2026-10-07.md
//! §4.5): records and unions over four words share homes across phis and in-place updates,
//! are read where they lie, and cross calls in-out; none of it may be observable.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const Hand = support.Hand;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The LLVM text of the function `name` (from its `define` line to the closing brace).
fn functionText(llvm: []const u8, name: []const u8) []const u8 {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, llvm, from, "define ")) |start| : (from = start + 1) {
        const line_end = std.mem.indexOfPos(u8, llvm, start, "\n").?;
        if (std.mem.indexOf(u8, llvm[start..line_end], name) == null) continue;
        return llvm[start..std.mem.indexOfPos(u8, llvm, start, "\n}\n").?];
    }
    unreachable;
}

/// Copies of records over four words in a function's text.
fn copies(text: []const u8) usize {
    return std.mem.count(u8, text, "call void @llvm.memcpy") + std.mem.count(u8, text, "call void @llvm.memmove");
}

const cursor =
    \\record Span:
    \\    line: int
    \\    col: int
    \\    offset: int
    \\
    \\
    \\record Cursor:
    \\    pos: int
    \\    line: int
    \\    col: int
    \\    span: Span
    \\
    \\
    \\record Outer:
    \\    inner: Cursor
    \\    tag: int
    \\
    \\
    \\record Runtime:
    \\    stack: int[]
    \\    top: int
    \\    a: int
    \\    b: int
    \\    c: int
    \\
    \\
    \\record Interp:
    \\    name: str
    \\    rt: Runtime
    \\    depth: int
    \\
    \\
    \\func wander(n: int) -> int:
    \\    mut w = Cursor(pos=0, line=1, col=1, span=Span(line=0, col=0, offset=0))
    \\    mut i = 0
    \\    while i < n:
    \\        i += 1
    \\        if i % 3 == 0:
    \\            continue
    \\        if i > 50:
    \\            break
    \\        w.pos += i
    \\        if i % 2 == 0:
    \\            w.col += 1
    \\    return w.pos * 100 + w.col
    \\
    \\
    \\func write_backs(n: int) -> int:
    \\    mut it = Interp(name="i", rt=Runtime(stack=[], top=0, a=0, b=0, c=0), depth=0)
    \\    for i in range(n):
    \\        mut wb = it.rt
    \\        wb.top += i
    \\        wb.a = wb.top * 2
    \\        it.rt = wb
    \\    return it.rt.top + it.rt.a
    \\
    \\
    \\func nested(k: int) -> int:
    \\    mut it = Interp(name="n", rt=Runtime(stack=[], top=k, a=k, b=k, c=k), depth=k)
    \\    return it.rt.top + it.depth
    \\
    \\
    \\func push(mut rt: Runtime, v: int):
    \\    rt.stack.append(v)
    \\    rt.top += 1
    \\
    \\
    \\func pushes(mut it: Interp, n: int):
    \\    for i in range(n):
    \\        mut wb = it.rt
    \\        push(mut wb, i)
    \\        it.rt = wb
    \\
    \\
    \\func advance(src: bytes, mut t: Cursor):
    \\    if t.pos < len(src):
    \\        if src[t.pos] == 10:
    \\            t.line += 1
    \\            t.col = 1
    \\        else:
    \\            t.col += 1
    \\        t.pos += 1
    \\
    \\
    \\func walk(src: bytes, n: int) -> int:
    \\    mut t = Cursor(pos=0, line=1, col=1, span=Span(line=0, col=0, offset=0))
    \\    mut i = 0
    \\    while i < n:
    \\        i += 1
    \\        if i % 3 == 0:
    \\            continue
    \\        if i > 50:
    \\            break
    \\        advance(src, mut t)
    \\        if i % 2 == 0:
    \\            t.col += 1
    \\    return t.pos * 100 + t.col
    \\
    \\
    \\func weight(c: Cursor) -> int:
    \\    return c.pos + c.col
    \\
    \\
    \\func through(o: Outer) -> int:
    \\    return weight(o.inner) + o.tag
    \\
    \\
    \\func bumped(input: Cursor, k: int) -> Cursor:
    \\    mut c = input
    \\    c.pos += k
    \\    c.col *= 2
    \\    return c
    \\
    \\
    \\func kept(input: Cursor) -> int:
    \\    mut c = input
    \\    mut old = c
    \\    c.pos = 7
    \\    return old.pos + c.pos
    \\
    \\
    \\func overlap(mut t: Cursor, before: Cursor, part: Span) -> int:
    \\    t.pos = 1000
    \\    return before.pos + part.offset + t.pos
    \\
    \\
    \\func overlapping() -> int:
    \\    mut t = Cursor(pos=3, line=0, col=0, span=Span(line=0, col=0, offset=4))
    \\    mut r = overlap(mut t, t, t.span)
    \\    return r + t.pos
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(walk(b"ab\ncd", 9), through(Outer(inner=bumped(Cursor(pos=1, line=2, col=3, span=Span(line=0, col=0, offset=0)), 4), tag=5)))
    \\    out.print(kept(Cursor(pos=1, line=0, col=0, span=Span(line=0, col=0, offset=0))), overlapping())
    \\    mut it = Interp(name="i", rt=Runtime(stack=[], top=0, a=0, b=0, c=0), depth=0)
    \\    pushes(mut it, 4)
    \\    out.print(wander(9), write_backs(5), it.rt.top, len(it.rt.stack), nested(3))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-RECORDS-1
test "a record carried around a loop with break and continue lives in one home: no phi is filled by a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), cursor);
    // Every join of the updated record shares the home it was built in.
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(llvm, "@\"my.wander\"")));
    const walk = functionText(llvm, "@\"my.walk\"");
    // Built once in its home, then every join, the call's in-out update and the field store reuse it.
    try std.testing.expectEqual(@as(usize, 0), copies(walk));
    try std.testing.expect(!contains(walk, "phi ptr"));
    const release = try support.releaseLlvmText(arena.allocator(), cursor);
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(release, "@\"my.walk\"")));
}

// spec: NEW-CORE-CE-RECORDS-2
test "a record field over four words is read where it lies: a pointer into its parent, not a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), cursor);
    const through = functionText(llvm, "@\"my.through\"");
    try std.testing.expectEqual(@as(usize, 0), copies(through));
    // `o.inner` is the parameter's own bytes at offset 0, passed straight to `weight`.
    try std.testing.expect(contains(through, "= getelementptr inbounds i8, ptr %p0, i64 0\n"));
    try std.testing.expect(contains(through, "(ptr %v"));
    // `Runtime(...)` inside `Interp(...)` is stored straight into the field: no copy of it.
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(llvm, "@\"my.nested\"")));
}

// spec: NEW-CORE-CE-RECORDS-3
test "a record whose old value has no later reader is updated in place; a snapshot still read keeps a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), cursor);
    // The read-only parameter is copied once, into the caller's destination, and both stores go there.
    const bumped = functionText(llvm, "@\"my.bumped\"");
    try std.testing.expectEqual(@as(usize, 1), copies(bumped));
    try std.testing.expect(contains(bumped, "@llvm.memcpy.p0.p0.i64(ptr %v"));
    try std.testing.expect(contains(bumped, "getelementptr inbounds i8, ptr %ret, i64 0\n"));
    // `old` is read after the store, so the store writes a copy.
    const kept = functionText(llvm, "@\"my.kept\"");
    try std.testing.expectEqual(@as(usize, 1), copies(kept));
    // `wb = it.rt; ...; it.rt = wb`: the write-back's value is built in the field itself.
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(llvm, "@\"my.write_backs\"")));
}

// spec: NEW-CORE-CE-RECORDS-4
test "a mut record crosses a call in-out: one writable pointer, no sret, no copy in or out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), cursor);
    const advance = functionText(llvm, "@\"my.advance\"");
    try std.testing.expect(contains(advance, "define internal fastcc void @\"my.advance\"(ptr %p0, ptr noalias align 8 %p1)"));
    try std.testing.expectEqual(@as(usize, 0), copies(advance));
    // A read-only argument that reads the `mut` record sees it from before the call: the
    // in-out argument goes in a copy, and the caller reads the result from there.
    const overlapping = functionText(llvm, "@\"my.overlapping\"");
    try std.testing.expectEqual(@as(usize, 1), copies(overlapping));
    const overlap = functionText(llvm, "@\"my.overlap\"");
    try std.testing.expect(contains(overlap, "ptr noalias sret([56 x i8]) align 8 %ret, ptr noalias align 8 %p0, ptr noalias readonly align 8 %p1, { i64, i64, i64 } %p2)"));
    try std.testing.expectEqual(@as(usize, 0), copies(overlap));
    // A write-back through an in-out call passes the field itself.
    const pushes = functionText(llvm, "@\"my.pushes\"");
    try std.testing.expectEqual(@as(usize, 0), copies(pushes));
    try std.testing.expect(contains(pushes, "call fastcc void @\"my.push\"(ptr %v"));
}

// spec-case: NEW-CORE-CE-RECORDS-4
test "a call's result record read whole gets its in-out final values copied in after the call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try completedProgram(a);
    const debug = try support.runOwned(a, &m, .{});
    try std.testing.expectEqual(@as(u8, 0), debug.status);
    try std.testing.expectEqualStrings("8 80 16 16\n", debug.stdout);
    try std.testing.expectEqualStrings("", debug.stderr);
    const main_text = functionText(debug.llvm, "@\"my.main\"");
    try std.testing.expect(contains(main_text, "call fastcc void @\"my.bump\"(ptr sret([56 x i8]) align 8"));
    try std.testing.expect(contains(functionText(debug.llvm, "@\"my.bump\""), "ptr noalias align 8 %p0, i64 %p1"));
    var again = try completedProgram(a);
    const release = try support.runOwned(a, &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}

// spec-case: NEW-CORE-CE-RECORDS-4
test "a function of more than 64 parameters is emitted and called with no in-out parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), try wideSource(arena.allocator(), 70));
    try std.testing.expect(contains(functionText(llvm, "@\"my.wide\""), "i64 %p69)"));
}

/// `wide(a0, ..., a{n-1}) -> int` and a `main` that calls it.
fn wideSource(a: std.mem.Allocator, n: usize) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(a, "func wide(");
    for (0..n) |i| try source.print(a, "{s}a{d}: int", .{ if (i == 0) "" else ", ", i });
    try source.print(a, ") -> int:\n    return a0 + a{d}\n\n\nfunc main(out: Stream) -> int:\n    out.print(wide(", .{n - 1});
    for (0..n) |i| try source.print(a, "{s}{d}", .{ if (i == 0) "" else ", ", i });
    try source.appendSlice(a, "))\n    return 0\n");
    return source.items;
}

/// `bump(w: mut Wide, k) -> {i64, Wide}` called twice: once with its result pushed whole onto
/// a list, once with the final value read out of the result twice. Both need the result record
/// completed with the final value the callee wrote in place.
fn completedProgram(a: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    const wide = try m.intern(a, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64, .i64 } });
    const both = try m.intern(a, .{ .record = &.{ .i64, wide } });
    const list = try m.intern(a, .{ .list = both });
    var target = try Hand.init(a, &m, "bump", .{ .params = try a.dupe(ir.Type, &.{ wide, .i64 }), .ret = both, .owned = 1 });
    const first = try target.emit(.{ .op = .record_get, .ty = .i64, .a = try target.param(0), .data = 0 });
    const sum = try target.emit(.{ .op = .add, .ty = .i64, .a = first, .b = try target.param(1), .check = .exact });
    const updated = try target.emit(.{ .op = .record_set, .ty = wide, .a = try target.param(0), .b = sum, .data = 0 });
    const tens = try target.emit(.{ .op = .mul, .ty = .i64, .a = sum, .b = try target.int(.i64, 10), .check = .exact });
    const result = try target.emit(.{ .op = .record_make, .ty = both, .data = try target.extra(&.{ tens, updated }) });
    _ = try target.emit(.{ .op = .ret, .ty = .void, .a = result });
    _ = try target.finish();
    m.entry = 1;
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const one = try h.int(.i64, 1);
    const initial = try h.emit(.{ .op = .record_make, .ty = wide, .data = try h.extra(&.{ one, one, one, one, one, one }) });
    const called = try h.emit(.{ .op = .call, .ty = both, .a = @fromBackingInt(0), .data = try h.extra(&.{ initial, try h.int(.i64, 7) }) });
    const container = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    const pushed = try h.emit(.{ .op = .list_push, .ty = list, .a = container, .b = called });
    const element = try h.emit(.{ .op = .list_get, .ty = both, .a = pushed, .b = try h.int(.i64, 0), .check = .exact });
    const inner = try h.emit(.{ .op = .record_get, .ty = wide, .a = element, .data = 1 });
    const field = try h.emit(.{ .op = .record_get, .ty = .i64, .a = inner, .data = 0 });
    const declared = try h.emit(.{ .op = .record_get, .ty = .i64, .a = called, .data = 0 });
    const second = try h.emit(.{ .op = .record_make, .ty = wide, .data = try h.extra(&.{ try h.int(.i64, 1), one, one, one, one, one }) });
    const again = try h.emit(.{ .op = .call, .ty = both, .a = @fromBackingInt(0), .data = try h.extra(&.{ second, try h.int(.i64, 7) }) });
    const read_once = try h.emit(.{ .op = .record_get, .ty = wide, .a = again, .data = 1 });
    const read_twice = try h.emit(.{ .op = .record_get, .ty = wide, .a = again, .data = 1 });
    const left = try h.emit(.{ .op = .record_get, .ty = .i64, .a = read_once, .data = 0 });
    const right = try h.emit(.{ .op = .record_get, .ty = .i64, .a = read_twice, .data = 0 });
    const doubled = try h.emit(.{ .op = .add, .ty = .i64, .a = left, .b = right, .check = .exact });
    try h.printValues(try h.param(0), &.{ field, declared, doubled, doubled });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

const fixture_expected =
    \\11030375
    \\9905151
    \\6214 9126
    \\714203
    \\40050811
    \\6 8011
    \\119703
    \\42216
    \\1007077
    \\2126110
    \\117487
    \\17911032713
    \\
;

/// Build `test/core/ce_records.my` with `flags` and run it under the leak check, with `args`.
fn fixtureRun(arena: std.mem.Allocator, root: []const u8, tag: []const u8, flags: []const []const u8, args: []const []const u8) !std.process.RunResult {
    const source = try std.fmt.allocPrint(arena, "{s}/ce_records.my", .{options.fixtures});
    const output = try std.fmt.allocPrint(arena, "{s}/ce_records-{s}", .{ root, tag });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", try std.fmt.allocPrint(arena, "{s}/cache", .{root}) });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    return std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
}

// spec: NEW-CORE-CE-RECORDS-5
test "shared homes, views, in-place updates and in-out calls keep value semantics, debug, release and verify, leak-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };
    for (modes, [_][]const u8{ "debug", "release", "verify" }) |flags, tag| {
        const ran = try fixtureRun(arena.allocator(), root, tag, flags, &.{});
        try std.testing.expectEqualStrings(fixture_expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        // A trap in the middle of an in-out update: everything before it printed, then the trap.
        const trapped = try fixtureRun(arena.allocator(), root, tag, flags, &.{"x"});
        try std.testing.expectEqualStrings(fixture_expected, trapped.stdout);
        try std.testing.expect(contains(trapped.stderr, "error[R_OVERFLOW]"));
        try std.testing.expect(contains(trapped.stderr, "in overflow"));
        try std.testing.expect(trapped.term == .exited and trapped.term.exited == 1);
    }
}

// spec-case: NEW-CORE-CE-RECORDS-5
test "the CE-A shapes print what value semantics says, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), cursor, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    // walk ends at pos 5, col 5 (the newline resets the column; even steps add one); `through`
    // sees the bumped copy (5 + 6) plus the tag 5; the snapshot keeps 1 next to the store's 7;
    // the read-only arguments saw pos 3 and offset 4 next to the in-out store of 1000.
    try std.testing.expectEqualStrings("505 16\n8 2007\n2704 30 4 4 6\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), cursor, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}

const swapped_return =
    \\record Big:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\    e: int
    \\
    \\
    \\record Pair:
    \\    x: Big
    \\    y: Big
    \\
    \\
    \\func make_pair(k: int) -> Pair:
    \\    return Pair(x=Big(a=k, b=k + 1, c=k + 2, d=k + 3, e=k + 4), y=Big(a=10 * k, b=0, c=0, d=0, e=10 * k + 4))
    \\
    \\
    \\func pick(k: int, flag: bool) -> Pair:
    \\    mut w = make_pair(k)
    \\    if flag:
    \\        return w
    \\    return Pair(x=w.y, y=w.x)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut p = pick(1, False)
    \\    mut q = pick(2, True)
    \\    out.print(p.x.a, p.x.e, p.y.a, p.y.e, q.x.a, q.y.e)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-RECORDS-6
test "a ret next to a value living in %ret builds its value in a temporary: a field swap reads both halves first" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), swapped_return, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    // pick(1, False) swaps the halves of make_pair(1): x is (10 .. 14), y is (1 .. 5).
    try std.testing.expectEqualStrings("10 14 1 5 2 24\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), swapped_return, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}
