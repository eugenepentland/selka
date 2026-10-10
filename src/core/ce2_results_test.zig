//! CE2-B, results and arguments in place (docs/audits/values-keys-trap-search-plan-2026-10-07.md
//! §4.5 "CE2"): values a `ret` stores inside the returned value are built at their place in the
//! caller's `sret` destination; none of it may be observable. Every expected output is the
//! pre-CE compiler's (`65a14aeb`) for the same program and arguments.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");

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

const results =
    \\record Span:
    \\    line: int
    \\    col: int
    \\    offset: int
    \\
    \\
    \\record Token:
    \\    tag: int
    \\    text: str
    \\    span: Span
    \\
    \\
    \\record Cursor:
    \\    pos: int
    \\    line: int
    \\    col: int
    \\    error_span: Span
    \\
    \\
    \\record Tokenizer:
    \\    source: bytes
    \\    cur: Cursor
    \\
    \\
    \\enum LexError:
    \\    bad
    \\    eof
    \\
    \\
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
    \\func make_token(t: Cursor, tag: int) -> Token:
    \\    return Token(tag=tag, text=str(t.pos), span=Span(line=t.line, col=t.col, offset=t.pos))
    \\
    \\
    \\func next_in(src: bytes, mut t: Cursor) -> Result[Token, LexError]:
    \\    if t.pos >= len(src):
    \\        return Err(LexError.eof)
    \\    t.pos += 1
    \\    return Ok(make_token(t, 1))
    \\
    \\
    \\func next(mut t: Tokenizer) -> Result[Token, LexError]:
    \\    mut src = t.source
    \\    mut cur = t.cur
    \\    mut r = next_in(src, mut cur)
    \\    t.cur = cur
    \\    return r
    \\
    \\
    \\func next_token(mut tok: Tokenizer) -> Result[Token, str]:
    \\    match next(mut tok):
    \\        case Ok(token):
    \\            return Ok(token)
    \\        case Err(_):
    \\            return Err("lex")
    \\
    \\
    \\func make_pair(k: int) -> Pair:
    \\    return Pair(x=Big(a=k, b=k, c=k, d=k, e=k), y=Big(a=10 * k, b=0, c=0, d=0, e=1))
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
    \\    mut tok = Tokenizer(source=b"abc", cur=Cursor(pos=0, line=1, col=1, error_span=Span(line=0, col=0, offset=0)))
    \\    for _ in range(4):
    \\        match next_token(mut tok):
    \\            case Ok(token):
    \\                out.print(token.text, token.span.offset)
    \\            case Err(e):
    \\                out.print(e)
    \\    mut p = pick(1, False)
    \\    mut q = pick(2, True)
    \\    out.print(p.x.a, p.y.a, p.x.e, p.y.e, q.x.a, q.y.a)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-RESULTS-1
test "a value a ret stores inside the result is built at its place in %ret: no copy into %ret" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), results);
    // `return Ok(make_token(...))`: the callee's destination is the payload's place in `%ret`.
    const next_in = functionText(llvm, "@\"my.next_in\"");
    try std.testing.expectEqual(@as(usize, 0), copies(next_in));
    try std.testing.expect(contains(next_in, "= getelementptr inbounds i8, ptr %ret, i64 8\n"));
    // `r = next_in(...)` returned next to a `mut` value: the call's whole result is built in `%ret`.
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(llvm, "@\"my.next\"")));
    // The payload of a callee's result returned under another error type: no copy either.
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(llvm, "@\"my.next_token\"")));
    const release = try support.releaseLlvmText(arena.allocator(), results);
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(release, "@\"my.next\"")));
}

// spec: NEW-CORE-CE2-RESULTS-2
test "a ret that would overwrite a value in %ret before reading it builds its value in a temporary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), results, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    // The swapped halves of `w`, which lives in `%ret` for the other return: 10 1 and 1 1, not 10 10.
    try std.testing.expectEqualStrings("1 1\n2 2\n3 3\nlex\n10 1 1 1 2 20\n", debug.stdout);
    const pick = functionText(debug.llvm, "@\"my.pick\"");
    // Both halves into a temporary, then the temporary into `%ret`.
    try std.testing.expectEqual(@as(usize, 3), copies(pick));
    var again = try support.buildSource(arena.allocator(), results, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}

const lending =
    \\record Big:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\    e: int
    \\
    \\
    \\record Holder:
    \\    items: Big[]
    \\    n: int
    \\
    \\
    \\func weight(x: Big) -> int:
    \\    return x.a + 2 * x.e
    \\
    \\
    \\func grow(mut h: Holder, x: Big) -> int:
    \\    h.items[0] = Big(a=-1, b=-1, c=-1, d=-1, e=-1)
    \\    return x.a + h.items[0].a
    \\
    \\
    \\func lend(xs: Big[]) -> int:
    \\    mut total = 0
    \\    for i in range(len(xs)):
    \\        total += weight(xs[i])
    \\    return total
    \\
    \\
    \\func reach(mut h: Holder) -> int:
    \\    return grow(mut h, h.items[0])
    \\
    \\
    \\func stale(source: Big[]) -> int:
    \\    mut xs = source
    \\    mut y = xs[1]
    \\    xs[1] = Big(a=50, b=0, c=0, d=0, e=0)
    \\    return weight(y) + xs[1].a
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [for i in range(5) yield Big(a=i, b=i, c=i, d=i, e=i * 3)]
    \\    mut h = Holder(items=xs, n=0)
    \\    out.print(lend(xs), reach(mut h), stale(xs), h.items[0].a, xs[0].a)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-RESULTS-4
test "a list element passed by value to a call that cannot write it is passed where it lies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), lending);
    // `weight(xs[i])`: the element's own slot is the argument.
    const lend = functionText(llvm, "@\"my.lend\"");
    try std.testing.expectEqual(@as(usize, 0), copies(lend));
    try std.testing.expect(contains(lend, "@\"my.weight\"(ptr %v"));
    // A `mut` argument of the same call reaches the list: the element is copied first.
    try std.testing.expectEqual(@as(usize, 1), copies(functionText(llvm, "@\"my.reach\"")));
    // The slot is overwritten between the read and the call: the read is a copy.
    try std.testing.expect(copies(functionText(llvm, "@\"my.stale\"")) >= 1);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), lending, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    // weights 0+0, 1+6, 2+12, 3+18, 4+24 = 70; grow sees x.a 0 next to -1; stale sees 1+6 then 50.
    try std.testing.expectEqualStrings("70 -1 57 -1 0\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), lending, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}

const sharing =
    \\record State:
    \\    f0: int
    \\    f1: int
    \\    f2: int
    \\    f3: int
    \\    f4: int
    \\    f5: int
    \\
    \\
    \\record Pair:
    \\    x: State
    \\    y: State
    \\
    \\
    \\func advance(s: State, x: int) -> State:
    \\    mut t = (s.f0 * 31 + x) % 1009
    \\    return State(f0=s.f1, f1=s.f2, f2=s.f3, f3=s.f4, f4=s.f5, f5=t)
    \\
    \\
    \\func swap(p: Pair) -> Pair:
    \\    return Pair(x=p.y, y=p.x)
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut s = State(f0=1, f1=2, f2=3, f3=4, f4=5, f5=6)
    \\    for j in range(n):
    \\        s = advance(s, j)
    \\    return s.f0 * 1000 + s.f5
    \\
    \\
    \\func swaps(n: int) -> int:
    \\    mut p = Pair(x=State(f0=1, f1=0, f2=0, f3=0, f4=0, f5=0), y=State(f0=2, f1=0, f2=0, f3=0, f4=0, f5=0))
    \\    for _ in range(n):
    \\        p = swap(p)
    \\    return p.x.f0 * 10 + p.y.f0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(run(20), swaps(3), swaps(4))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-RESULTS-5
test "s = advance(s, x): one noalias destination carries the dead argument without copying" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), sharing);
    // The shared parameter is accessed through the sole noalias destination pointer.
    try std.testing.expect(contains(llvm, "define internal fastcc void @\"my.advance\"(ptr noalias sret([48 x i8]) align 8 %ret, i64 %p1)"));
    // The loop carries one storage home through the call.
    try std.testing.expectEqual(@as(usize, 0), copies(functionText(llvm, "@\"my.run\"")));
    // `swap` reads `p.x` after storing over it: it may not share, and its caller copies.
    try std.testing.expect(contains(llvm, "define internal fastcc void @\"my.swap\"(ptr noalias sret([96 x i8]) align 8 %ret, ptr noalias readonly align 8 %p0)"));
    try std.testing.expect(copies(functionText(llvm, "@\"my.swaps\"")) >= 1);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), sharing, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    try std.testing.expectEqualStrings("747179 21 12\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), sharing, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
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

const globals =
    \\record Entry:
    \\    key: int
    \\    value: int
    \\
    \\
    \\record Table:
    \\    entries: Entry[]
    \\    count: int
    \\
    \\
    \\record Runtime:
    \\    names: str[]
    \\    globals: Table
    \\
    \\
    \\func hash_of(rt: Runtime, k: int) -> int:
    \\    return len(rt.names[k % len(rt.names)]) + len(rt.globals.entries)
    \\
    \\
    \\func put(mut t: Table, k: int, h: int, v: int) -> bool:
    \\    mut i = (k + h) % len(t.entries)
    \\    mut fresh = t.entries[i].key == -1
    \\    t.entries[i] = Entry(key=k, value=v)
    \\    return fresh
    \\
    \\
    \\func set_global(mut rt: Runtime, k: int, v: int) -> bool:
    \\    mut wb = rt.globals
    \\    mut r = put(mut wb, k, hash_of(rt, k), v)
    \\    rt.globals = wb
    \\    return r
    \\
    \\
    \\func peek_after(mut rt: Runtime, k: int) -> int:
    \\    mut wb = rt.globals
    \\    mut r = put(mut wb, k, 0, 7)
    \\    mut seen = hash_of(rt, k) + rt.globals.entries[k % len(rt.globals.entries)].value
    \\    rt.globals = wb
    \\    return seen + (if (r) then (1) else (0))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut rt = Runtime(names=["a", "bb"], globals=Table(entries=[for _ in range(8) yield Entry(key=-1, value=0)], count=0))
    \\    mut snapshot = rt.globals
    \\    for k in range(12):
    \\        _ = set_global(mut rt, k, k * 2)
    \\    out.print(rt.globals.entries[3].value, snapshot.entries[3].value, peek_after(mut rt, 5), rt.globals.entries[5].value)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-RESULTS-6
test "a field taken for a mut call survives a call that borrows its record first: the update finds it unique" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.ownedText(arena.allocator(), globals);
    // `wb = rt.globals; put(mut wb, k, hash_of(rt, k), v)`: `hash_of` reads `rt` before `put`
    // takes the field, so the field is taken, not retained, and the write-back drops nothing.
    const set_global = functionIr(text, "set_global");
    try std.testing.expect(set_global.len != 0);
    try std.testing.expect(!contains(set_global, "retain"));
    try std.testing.expect(!contains(set_global, "release"));
    // A read of `rt.globals` after `put` must see the old table: the field is retained.
    try std.testing.expect(contains(functionIr(text, "peek_after"), "retain"));
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), globals, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    try std.testing.expectEqualStrings("20 0 32 7\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), globals, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}

const element_fields =
    \\record Bucket:
    \\    name: str
    \\    items: int[]
    \\    a: int
    \\    b: int
    \\    c: int
    \\
    \\
    \\func fill(n: int) -> int:
    \\    mut xs = [for k in range(4) yield Bucket(name="b", items=[], a=k, b=0, c=0)]
    \\    mut before = xs
    \\    mut keep = xs[1].items
    \\    for i in range(n):
    \\        xs[i % 4].items.append(i)
    \\        if i % 7 == 0:
    \\            _ = xs[i % 4].items.pop()
    \\    mut total = 0
    \\    for x in xs:
    \\        total += len(x.items) * 100 + x.items[len(x.items) - 1]
    \\    return total * 10 + len(before[0].items) + len(keep)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(fill(100))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-RESULTS-7
test "xs[i].items.append(v) updates the element's field in place: the element is never copied out or back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.ownedText(arena.allocator(), element_fields);
    const fill = functionIr(text, "fill");
    // Both updates read the field (taking the slot's owner) and store it back in place.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, fill, "= list_set_field"));
    try std.testing.expect(!contains(fill, "list_set.exact list[record"));
    // The only whole-element read left is the summing loop's `for x in xs`.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, fill, "list_get.exact record{"));
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), element_fields, &refusal);
    const debug = try support.runOwned(arena.allocator(), &module, .{});
    try std.testing.expectEqualStrings("88860\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), element_fields, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}

const fixture_expected =
    \\1:71@1.2 1:72@1.3 1:73@2.1 2:73@2.1 1:75@2.3 bad 1:77@2.5 0:@2.5 0:@2.5 1 5
    \\bad bad 1:33@1.4 0:@1.4 0:@1.4 2 1
    \\71@1 73@3 74@4 ! 76@6 @7 @7 8
    \\10 1 14 5 2 20 | 30 3 34 7 3 | 40 44 5 9 2 | 10 2 100 14 1 | 7 8 9 10 11 | 10 31 | early | 2 16
    \\617 5 -1 6 0 50 7 8
    \\747 179 179 966 | 7 3 5 | 2 2 3 | 7 8 | 1673 926 | 388
    \\16 16 99 0 16 64099 91 7
    \\27001 0 3 9 b3 299
    \\
;

/// Build `test/core/ce2_results.my` with `flags` and run it under the leak check, with `args`.
fn fixtureRun(arena: std.mem.Allocator, root: []const u8, tag: []const u8, flags: []const []const u8, args: []const []const u8) !std.process.RunResult {
    const source = try std.fmt.allocPrint(arena, "{s}/ce2_results.my", .{options.fixtures});
    const output = try std.fmt.allocPrint(arena, "{s}/ce2_results-{s}", .{ root, tag });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", try std.fmt.allocPrint(arena, "{s}/cache", .{root}) });
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

// spec: NEW-CORE-CE2-RESULTS-3
test "results, arguments and pushes in place keep value semantics, debug, release and verify, leak-free" {
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
        // A trap between building a result in `%ret` and returning it: everything before it printed.
        const trapped = try fixtureRun(arena.allocator(), root, tag, flags, &.{"x"});
        try std.testing.expectEqualStrings(fixture_expected, trapped.stdout);
        try std.testing.expect(contains(trapped.stderr, "error[R_OVERFLOW]"));
        try std.testing.expect(contains(trapped.stderr, "in trapping"));
        try std.testing.expect(trapped.term == .exited and trapped.term.exited == 1);
    }
}
