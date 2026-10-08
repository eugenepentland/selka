//! Field effects (CE2-A): the per-parameter read and write summaries (`effects.zig`),
//! per-field interference of memory homes, dead and sunk element stores, and element
//! stores narrowed to the fields that changed.
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const effects = @import("effects.zig");
const support = @import("test_support.zig");

/// The index of the function named `name` (its Core name ends with it).
fn functionIndex(module: *const ir.Module, name: []const u8) !usize {
    for (module.functions.items, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) return i;
    }
    return error.TestUnexpectedResult;
}

/// The paths of `set` spelled `a.b,c` (`*` for the whole value, `-` for none), sorted.
fn spell(arena: std.mem.Allocator, set: *const effects.Paths) ![]const u8 {
    if (set.whole) return "*";
    if (set.items.items.len == 0) return "-";
    var parts: std.ArrayList([]const u8) = .empty;
    for (set.items.items) |path| {
        var text: std.ArrayList(u8) = .empty;
        for (path.slice(), 0..) |step, i| {
            if (i != 0) try text.append(arena, '.');
            try text.print(arena, "{d}", .{step});
        }
        try parts.append(arena, text.items);
    }
    std.mem.sort([]const u8, parts.items, {}, struct {
        fn less(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.less);
    return std.mem.join(arena, ",", parts.items);
}

const summaries_source =
    \\record Inner:
    \\    a: int
    \\    b: list[int]
    \\
    \\
    \\record State:
    \\    ip: int
    \\    inner: Inner
    \\    code: list[int]
    \\    count: int
    \\
    \\
    \\def bump(s: mut State) -> int:
    \\    s.ip = s.ip + 1
    \\    return s.ip
    \\
    \\
    \\def read_code(s: mut State) -> int:
    \\    return s.code[bump(mut s)]
    \\
    \\
    \\def deep(s: mut State):
    \\    s.inner.a = 5
    \\
    \\
    \\def grow(s: mut State, x: int):
    \\    s.inner.b.append(x)
    \\
    \\
    \\def replace(s: mut State, t: State):
    \\    s = t
    \\
    \\
    \\def countdown(s: mut State, n: int):
    \\    if n > 0:
    \\        s.count = s.count + 1
    \\        countdown(mut s, n - 1)
    \\
    \\
    \\def ping(s: mut State, n: int):
    \\    if n > 0:
    \\        pong(mut s, n - 1)
    \\
    \\
    \\def pong(s: mut State, n: int):
    \\    s.ip = s.ip + 2
    \\    ping(mut s, n)
    \\
    \\
    \\def check(s: mut State) -> bool:
    \\    if s.count > 3:
    \\        s.count = 0
    \\        return False
    \\    s.ip = s.ip + 1
    \\    return True
    \\
    \\
    \\def relay(s: mut State) -> bool:
    \\    return check(mut s)
    \\
    \\
    \\def refuse(s: mut State) -> bool:
    \\    s.count = 0
    \\    return False
    \\
    \\
    \\def length(s: State) -> int:
    \\    return len(s.code)
    \\
    \\
    \\def through(s: State, f: def(State) -> int) -> int:
    \\    return f(s)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    s = State(ip=0, inner=Inner(a=1, b=[]), code=[1, 2, 3], count=0)
    \\    t = s
    \\    out.print(read_code(mut s), length(s), through(s, length))
    \\    deep(mut s)
    \\    grow(mut s, 4)
    \\    replace(mut s, t)
    \\    countdown(mut s, 3)
    \\    ping(mut s, 4)
    \\    out.print(check(mut s), relay(mut s), refuse(mut s), s.ip)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-EFFECTS-1
test "a function's effect summary names the fields each parameter may be read and written in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, summaries_source, &refusal);
    const s = try effects.analyze(a, &module);
    const Expect = struct { name: []const u8, param: usize, reads: []const u8, writes: []const u8 };
    // `State` is ip (0), inner (1: a 1.0, b 1.1), code (2), count (3).
    const cases = [_]Expect{
        .{ .name = "bump", .param = 0, .reads = "0", .writes = "0" },
        // Through the callee: its writes and reads, plus the list read here.
        .{ .name = "read_code", .param = 0, .reads = "0,2", .writes = "0" },
        // A nested field, and a list updated inside a nested record.
        .{ .name = "deep", .param = 0, .reads = "-", .writes = "1.0" },
        .{ .name = "grow", .param = 0, .reads = "-", .writes = "1.1" },
        // A new value: everything.
        .{ .name = "replace", .param = 0, .reads = "-", .writes = "*" },
        .{ .name = "replace", .param = 1, .reads = "*", .writes = "-" },
        // Recursion, and mutual recursion: the least fixed point.
        .{ .name = "countdown", .param = 0, .reads = "3", .writes = "3" },
        .{ .name = "ping", .param = 0, .reads = "0", .writes = "0" },
        .{ .name = "pong", .param = 0, .reads = "0", .writes = "0" },
        // Reading the length reads the list's path; an indirect call reads everything.
        .{ .name = "length", .param = 0, .reads = "2", .writes = "-" },
        .{ .name = "through", .param = 0, .reads = "*", .writes = "-" },
        .{ .name = "check", .param = 0, .reads = "0,3", .writes = "0,3" },
    };
    for (cases) |case| {
        const effect = s.of(try functionIndex(&module, case.name), case.param);
        errdefer std.debug.print("{s} param {d}\n", .{ case.name, case.param });
        try std.testing.expectEqualStrings(case.reads, try spell(a, &effect.reads));
        try std.testing.expectEqualStrings(case.writes, try spell(a, &effect.writes));
    }
    // Conditional writes: `check` resets the count only when it answers False, and a
    // function returning a call's answer answers as it does.
    try expectAnswers(a, &module, &s, "check");
    try expectAnswers(a, &module, &s, "relay");
    // A function that only answers False writes nothing on a return that answers True.
    const refuse = try functionIndex(&module, "refuse");
    try std.testing.expectEqual([2]bool{ false, true }, s.may[refuse]);
    try std.testing.expectEqualStrings("-", try spell(a, s.writes(refuse, 0, true)));
    try std.testing.expectEqualStrings("3", try spell(a, s.writes(refuse, 0, false)));
}

/// `name` writes field 0 when it answers True and field 3 when it answers False.
fn expectAnswers(a: std.mem.Allocator, module: *const ir.Module, s: *const effects.Summaries, name: []const u8) !void {
    const index = try functionIndex(module, name);
    try std.testing.expectEqualStrings("0", try spell(a, s.writes(index, 0, true)));
    try std.testing.expectEqualStrings("3", try spell(a, s.writes(index, 0, false)));
    try std.testing.expectEqual([2]bool{ true, true }, s.may[index]);
}

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

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/ce2_effects.my` with `flags` and run it with `args` under the leak check.
fn fixture(arena: std.mem.Allocator, root: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/ce2_effects.my", .{options.fixtures});
    const output = try std.fmt.allocPrint(arena, "{s}/ce2_effects-{d}", .{ root, flags.len });
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

/// What the base compiler (`claude/copy-elim-2` 9f9667b1b) prints for `ce2_effects.my`, by section.
const fields_expected =
    \\20 30 2 3
    \\3103 103
    \\110153 7 new
    \\8005 5
    \\44 4
    \\43 9 4
    \\300 4 -1
    \\
;

const view_source =
    \\record Code:
    \\    consts: list[int]
    \\    lines: list[int]
    \\    name: str
    \\    n: int
    \\    m: int
    \\
    \\
    \\record Frame:
    \\    closure: int
    \\    code: Code
    \\    ops: list[int]
    \\    ip: int
    \\    base: int
    \\
    \\
    \\def next_op(frame: mut Frame) -> int:
    \\    op = frame.ops[frame.ip]
    \\    frame.ip = frame.ip + 1
    \\    return op
    \\
    \\
    \\def read_const(frame: mut Frame) -> int:
    \\    return frame.code.consts[next_op(mut frame)]
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    frame = Frame(closure=0, code=Code(consts=[5, 6], lines=[], name="x", n=0, m=0), ops=[1, 0], ip=0, base=0)
    \\    out.print(read_const(mut frame), read_const(mut frame))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-EFFECTS-2
test "an in-place update of one field goes ahead while a view of a disjoint field is live, across a call that writes only other fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `frame.code` is read where it lies and stays live across `next_op(mut frame)`, which
    // writes only `frame.ip`: the frame is passed in its own memory and nothing is copied.
    const llvm = try support.llvmText(a, view_source);
    const body = try definition(llvm, "@\"my.read_const\"(");
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "@llvm.memcpy"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        // A callee writing the very field a view holds, a view across in-place updates of
        // another field and then of its own, loops, recursion, counted fields and a union
        // payload all print what copies would, and free every block.
        const ran = try fixture(a, root, flags, &.{});
        try std.testing.expectStringStartsWith(ran.stdout, fields_expected);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expect(!contains(ran.stderr, "leak"));
    }
}

/// What the base compiler prints for the element-store section of `ce2_effects.my`.
const stores_expected =
    \\6 1 4 2 t5 6m 0m 0m 0m
    \\8 1 4 1 i6 t7 8m 0m 0m 0m
    \\3 1 4 0 t24 3m 5c 0m 0m
    \\3 1 4 1 t26 3m 7c 0m 0m
    \\-2 0 4 1 big:3 3m 0m 0m 4m
    \\5 1 6 0 t2 t4 5m 0m 0m 0m 1m 3m
    \\6 1 2 1 t2 t5 6m 1m
    \\5 1 4 1 i1 i4 5m 0m 0m 0m
    \\6 1 4 0 m!5 t3 m!!6 6m!! 0m 0m 0m
    \\3 1 4 0 3m 0m 0m 0m
    \\-2 0 4 0 deep:2666 2m 6c 6c 6c
    \\
;

const loop_source =
    \\record Frame:
    \\    closure: int
    \\    name: str
    \\    ops: list[int]
    \\    ip: int
    \\    base: int
    \\
    \\
    \\record Machine:
    \\    frames: list[Frame]
    \\    count: int
    \\    stack: list[int]
    \\
    \\
    \\def next_op(frame: mut Frame) -> int:
    \\    op = frame.ops[frame.ip]
    \\    frame.ip = frame.ip + 1
    \\    return op
    \\
    \\
    \\def fail(m: mut Machine) -> bool:
    \\    total = 0
    \\    for frame in m.frames:
    \\        total = total + frame.ip
    \\    m.stack.append(total)
    \\    m.count = 0
    \\    return False
    \\
    \\
    \\def checked(m: mut Machine, x: int) -> bool:
    \\    if x > 9:
    \\        return fail(mut m)
    \\    m.stack.append(x)
    \\    return True
    \\
    \\
    \\def run(m: mut Machine) -> int:
    \\    frame = m.frames[m.count - 1]
    \\    while True:
    \\        op = next_op(mut frame)
    \\        m.frames[m.count - 1] = frame
    \\        ok = True
    \\        if op == 0:
    \\            return len(m.stack)
    \\        elif op == 1:
    \\            m.stack.append(next_op(mut frame))
    \\        elif op == 2:
    \\            ok = checked(mut m, next_op(mut frame))
    \\        m.frames[m.count - 1] = frame
    \\        if not ok:
    \\            return -1
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    frame = Frame(closure=0, name="f", ops=[1, 4, 2, 5, 2, 12, 0], ip=0, base=0)
    \\    m = Machine(frames=[frame, frame], count=1, stack=[])
    \\    out.print(run(mut m), m.frames[0].ip, m.frames[1].ip, m.stack[0])
    \\    return 0
    \\
;

/// What the base compiler prints for `loop_source`: the error path stores the frame into the
/// last element (the count is 0, so `count - 1` is -1).
const loop_expected = "-1 5 6 4\n";

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

/// Instructions of operation `op` in IR text (`%N = op` or `op` at a line's start).
fn countOp(text: []const u8, op: []const u8) usize {
    var total: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trimStart(u8, raw, " ");
        if (std.mem.indexOf(u8, line, " = ")) |at| {
            if (line.len > 0 and line[0] == '%') line = line[at + 3 ..];
        }
        if (!std.mem.startsWith(u8, line, op)) continue;
        const rest = line[op.len..];
        if (rest.len == 0 or rest[0] == ' ' or rest[0] == '.') total += 1;
    }
    return total;
}

// spec: NEW-CORE-CE2-EFFECTS-3
test "an element store a later store of the same element overwrites before anything reads it goes, or moves to the exits that read it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The store at the end of each step is overwritten by the next step's first store, with
    // only `if not ok: return` and `next_op(mut frame)` between: it stays only on the return
    // path, where the caller sees the machine; its bounds check stays where it was.
    const run = functionIr(try support.ownedText(a, loop_source), "run");
    try std.testing.expectEqual(@as(usize, 1), countOp(run, "list_set"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        // Reads through callees (a trace, an error report that resets the count, an indirect
        // call), a list that grows or is replaced, calls that push frames, `continue`, early
        // returns, counted fields and a store whose index runs past the list all print what
        // the stores as written print, and free every block.
        const ran = try fixture(a, root, flags, &.{});
        try std.testing.expectEqualStrings(fields_expected ++ takes_expected ++ stores_expected, ran.stdout);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        const read_trap = try fixture(a, root, flags, &.{"x"});
        try std.testing.expectEqual(@as(u8, 1), read_trap.status);
        try std.testing.expectEqualStrings(fields_expected ++ takes_expected ++ stores_expected, read_trap.stdout);
        try std.testing.expect(contains(read_trap.stderr, "ce2_effects.my:239:30: error[R_LIST_BOUNDS]: native execution failed (index 7, length 1)\n"));
        const store_trap = try fixture(a, root, flags, &.{"y"});
        try std.testing.expectEqual(@as(u8, 1), store_trap.status);
        try std.testing.expect(contains(store_trap.stderr, "ce2_effects.my:247:9: error[R_LIST_BOUNDS]: native execution failed (index 10, length 4)\n"));
    }
}

// spec: NEW-CORE-CE2-EFFECTS-4
test "an element store of a record read from that element stores only the fields that changed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `next_op(mut frame)` writes only `frame.ip` (field 3): the step's first store, and the
    // store on the return path's only predecessor that keeps the count, write that field in
    // place. The error path, where `fail` reset the count, still stores the whole frame.
    const run = functionIr(try support.ownedText(a, loop_source), "run");
    try std.testing.expect(countOp(run, "list_set_field") >= 1);
    try std.testing.expect(contains(run, "path 3, "));
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, loop_source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqualStrings(loop_expected, ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

/// What the base compiler prints for the write-back section of `ce2_effects.my`.
const takes_expected =
    \\9 5 i
    \\8 4 renamed
    \\413 7 3 1
    \\23 6 2 2 1
    \\
;

const take_source =
    \\record Machine:
    \\    frames: list[int]
    \\    count: int
    \\    stack: list[int]
    \\    top: int
    \\    log: list[str]
    \\
    \\
    \\record Interp:
    \\    name: str
    \\    m: Machine
    \\    returned: int
    \\    depth: int
    \\
    \\
    \\def take_pop(m: mut Machine) -> int:
    \\    m.top = m.top - 1
    \\    return m.stack[m.top]
    \\
    \\
    \\def return_value(it: mut Interp):
    \\    wb = it.m
    \\    it.returned = take_pop(mut wb)
    \\    it.m = wb
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    it = Interp(name="i", m=Machine(frames=[], count=0, stack=[4, 5, 6], top=3, log=[]), returned=0, depth=0)
    \\    return_value(mut it)
    \\    return_value(mut it)
    \\    out.print(it.returned, it.m.top, len(it.m.stack))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-EFFECTS-5
test "a write-back takes its field from the record before updates of other fields, without counting or copying it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `wb = it.m; it.returned = take_pop(mut wb); it.m = wb`: the read of `it.m` owns the
    // field until it is written back (no retain of it, no release of the old one), so the
    // machine is updated where it lies in `it`.
    const body = functionIr(try support.ownedText(a, take_source), "return_value");
    try std.testing.expectEqual(@as(usize, 0), countOp(body, "retain"));
    try std.testing.expectEqual(@as(usize, 0), countOp(body, "release"));
    const llvm = try support.llvmText(a, take_source);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, try definition(llvm, "@\"my.return_value\"("), "@llvm.memcpy"));
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, take_source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqualStrings("5 1 3\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

const construct_source =
    \\record Frame:
    \\    closure: int
    \\    name: str
    \\    ops: list[int]
    \\    ip: int
    \\    base: int
    \\
    \\
    \\def put(frames: mut list[Frame], at: int, name: str, ops: list[int]) -> int:
    \\    frames[at] = Frame(closure=at, name=name, ops=ops, ip=0, base=len(ops))
    \\    return len(frames)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    frames = [Frame(closure=0, name="a", ops=[1], ip=3, base=0), Frame(closure=1, name="b", ops=[], ip=4, base=1)]
    \\    keep = frames
    \\    n = put(mut frames, -1, "c", [7, 8])
    \\    m = put(mut frames, 0, "d", [9])
    \\    out.print(n, m, frames[0].name, frames[1].name, frames[1].base, keep[1].name, keep[0].ip)
    \\    return 0
    \\
;

/// What the base compiler prints for `construct_source`.
const construct_expected = "2 2 d c 2 b 3\n";

// spec: NEW-CORE-CE2-EFFECTS-6
test "a record built for a whole-element store past the index's branches is built in the element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `frames[at] = Frame(...)`: the store sits after the negative-index branch and the
    // list's uniqueness test, in another block than the construction; the frame is still
    // written straight into the element, with no copy of it.
    const llvm = try support.llvmText(a, construct_source);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, try definition(llvm, "@\"my.put\"("), "@llvm.memcpy"));
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, construct_source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqualStrings(construct_expected, ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}
