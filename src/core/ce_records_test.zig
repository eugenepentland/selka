//! CE-A, records in the emitter (docs/audits/values-keys-trap-search-plan-2026-10-07.md
//! §4.5): records and unions over four words share homes across phis and in-place updates,
//! are read where they lie, and cross calls in-out; none of it may be observable.
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
    \\    stack: list[int]
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
    \\def wander(n: int) -> int:
    \\    w = Cursor(pos=0, line=1, col=1, span=Span(line=0, col=0, offset=0))
    \\    i = 0
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
    \\def write_backs(n: int) -> int:
    \\    it = Interp(name="i", rt=Runtime(stack=[], top=0, a=0, b=0, c=0), depth=0)
    \\    for i in range(n):
    \\        wb = it.rt
    \\        wb.top += i
    \\        wb.a = wb.top * 2
    \\        it.rt = wb
    \\    return it.rt.top + it.rt.a
    \\
    \\
    \\def push(rt: mut Runtime, v: int):
    \\    rt.stack.append(v)
    \\    rt.top += 1
    \\
    \\
    \\def pushes(it: mut Interp, n: int):
    \\    for i in range(n):
    \\        wb = it.rt
    \\        push(mut wb, i)
    \\        it.rt = wb
    \\
    \\
    \\def advance(src: bytes, t: mut Cursor):
    \\    if t.pos < len(src):
    \\        if src[t.pos] == 10:
    \\            t.line += 1
    \\            t.col = 1
    \\        else:
    \\            t.col += 1
    \\        t.pos += 1
    \\
    \\
    \\def walk(src: bytes, n: int) -> int:
    \\    t = Cursor(pos=0, line=1, col=1, span=Span(line=0, col=0, offset=0))
    \\    i = 0
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
    \\def weight(c: Cursor) -> int:
    \\    return c.pos + c.col
    \\
    \\
    \\def through(o: Outer) -> int:
    \\    return weight(o.inner) + o.tag
    \\
    \\
    \\def bumped(c: Cursor, k: int) -> Cursor:
    \\    c.pos += k
    \\    c.col *= 2
    \\    return c
    \\
    \\
    \\def kept(c: Cursor) -> int:
    \\    old = c
    \\    c.pos = 7
    \\    return old.pos + c.pos
    \\
    \\
    \\def overlap(t: mut Cursor, before: Cursor, part: Span) -> int:
    \\    t.pos = 1000
    \\    return before.pos + part.offset + t.pos
    \\
    \\
    \\def overlapping() -> int:
    \\    t = Cursor(pos=3, line=0, col=0, span=Span(line=0, col=0, offset=4))
    \\    r = overlap(mut t, t, t.span)
    \\    return r + t.pos
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(walk(b"ab\ncd", 9), through(Outer(inner=bumped(Cursor(pos=1, line=2, col=3, span=Span(line=0, col=0, offset=0)), 4), tag=5)))
    \\    out.print(kept(Cursor(pos=1, line=0, col=0, span=Span(line=0, col=0, offset=0))), overlapping())
    \\    it = Interp(name="i", rt=Runtime(stack=[], top=0, a=0, b=0, c=0), depth=0)
    \\    pushes(mut it, 4)
    \\    out.print(wander(9), write_backs(5), it.rt.top, len(it.rt.stack))
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
        try std.testing.expect(contains(trapped.stderr, "in ce_records::overflow"));
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
    try std.testing.expectEqualStrings("505 16\n8 2007\n2704 30 4 4\n", debug.stdout);
    var again = try support.buildSource(arena.allocator(), cursor, &refusal);
    const release = try support.runOwned(arena.allocator(), &again, .{ .release = true });
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
}
