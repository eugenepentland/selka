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
    \\    bad,
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
    \\def make_token(t: Cursor, tag: int) -> Token:
    \\    return Token(tag=tag, text=str(t.pos), span=Span(line=t.line, col=t.col, offset=t.pos))
    \\
    \\
    \\def next_in(src: bytes, t: mut Cursor) -> Result[Token, LexError]:
    \\    if t.pos >= len(src):
    \\        return Err(LexError.eof)
    \\    t.pos += 1
    \\    return Ok(make_token(t, 1))
    \\
    \\
    \\def next(t: mut Tokenizer) -> Result[Token, LexError]:
    \\    src = t.source
    \\    cur = t.cur
    \\    r = next_in(src, mut cur)
    \\    t.cur = cur
    \\    return r
    \\
    \\
    \\def next_token(tok: mut Tokenizer) -> Result[Token, str]:
    \\    match next(mut tok):
    \\        case Ok(token):
    \\            return Ok(token)
    \\        case Err(_):
    \\            return Err("lex")
    \\
    \\
    \\def make_pair(k: int) -> Pair:
    \\    return Pair(x=Big(a=k, b=k, c=k, d=k, e=k), y=Big(a=10 * k, b=0, c=0, d=0, e=1))
    \\
    \\
    \\def pick(k: int, flag: bool) -> Pair:
    \\    w = make_pair(k)
    \\    if flag:
    \\        return w
    \\    return Pair(x=w.y, y=w.x)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    tok = Tokenizer(source=b"abc", cur=Cursor(pos=0, line=1, col=1, error_span=Span(line=0, col=0, offset=0)))
    \\    for _ in range(4):
    \\        match next_token(mut tok):
    \\            case Ok(token):
    \\                out.print(token.text, token.span.offset)
    \\            case Err(e):
    \\                out.print(e)
    \\    p = pick(1, False)
    \\    q = pick(2, True)
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

const fixture_expected =
    \\1:71@1.2 1:72@1.3 1:73@2.1 2:73@2.1 1:75@2.3 bad 1:77@2.5 0:@2.5 0:@2.5 1 5
    \\bad bad 1:33@1.4 0:@1.4 0:@1.4 2 1
    \\10 1 14 5 2 20 | 30 3 34 7 3 | 40 44 5 9 2 | 10 2 100 14 1 | 7 8 9 10 11 | 10 31 | early | 2 16
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
        try std.testing.expect(contains(trapped.stderr, "in ce2_results::trapping"));
        try std.testing.expect(trapped.term == .exited and trapped.term.exited == 1);
    }
}
