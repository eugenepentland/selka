//! U2 nested borrows, frame copies, generated destruction and dispatch facts.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const report = std.debug.print;
const main_decl = "func main";

const copied_receiver_source =
    \\record Chunk:
    \\    values: int[]
    \\    other: int[]
    \\record Function:
    \\    chunk: Chunk
    \\record Frame:
    \\    function: Function
    \\    ip: int
    \\func advance(mut f: Frame) -> int:
    \\    f.ip += 1
    \\    return f.ip
    \\func unchanged(mut f: Frame) -> int:
    \\    const receiver = copy(f.function.chunk.values)
    \\    return receiver[advance(mut f)]
    \\func change(mut f: Frame) -> int:
    \\    f.function.chunk.values = [90, 91, 92]
    \\    return 1
    \\func snapshot(mut f: Frame) -> int:
    \\    const receiver = copy(f.function.chunk.values)
    \\    return receiver[change(mut f)]
    \\func main(out: Stream) -> int:
    \\    mut f = Frame(function=Function(chunk=Chunk(values=[10, 11, 12], other=[20])), ip=0)
    \\    const alias = copy(f)
    \\    print(out, unchanged(mut f), f.ip)
    \\    print(out, snapshot(mut f), f.function.chunk.values[1])
    \\    print(out, alias.function.chunk.values[1], alias.ip)
    \\    return 0
;

fn functionText(text: []const u8, name: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, text, name) orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, text, start + name.len, "\nfn ") orelse text.len;
    return text[start..end];
}

const Fixture = struct { source: []const u8, output: []const u8, status: u8 = 0, trap: []const u8 = "" };

fn native(a: std.mem.Allocator, root: []const u8, flags: []const []const u8, fixture: Fixture) !void {
    const source = try std.fmt.allocPrint(a, "{s}/borrow.selka", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/borrow", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", try options.suiteCache(a, @src()) });
    try argv.appendSlice(a, flags);
    try support.requireReleaseArgs(flags);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != fixture.status) report("U2 flags={any} term={any}\n{s}{s}", .{ flags, ran.term, ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == fixture.status);
    try std.testing.expectEqualStrings(fixture.output, ran.stdout);
    if (fixture.trap.len == 0) try std.testing.expectEqualStrings("", ran.stderr) else try std.testing.expect(std.mem.indexOf(u8, ran.stderr, fixture.trap) != null);
}

fn nativeModes(a: std.mem.Allocator, fixture: Fixture) !void {
    var dir = stable_dir.tmpDir(a, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "borrow.selka", .data = fixture.source });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{ &.{"--optimize-debug"}, &.{ "--optimize-debug", "--verify-facts" }, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |flags| try native(a, root, flags, fixture);
}

// spec: NEW-CORE-U2-BORROW-1
test "U2 copied nested receivers preserve values across calls in every build kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = copied_receiver_source, .output = "11 1\n11 91\n11 0\n" });
}

const borrow_trap =
    \\record Chunk:
    \\    values: int[]
    \\record Frame:
    \\    chunk: Chunk
    \\    ip: int
    \\func index(mut f: Frame, out: Stream) -> int:
    \\    print(out, "before")
    \\    f.ip += 1
    \\    assert False, "index failed"
    \\    return 99
    \\func main(out: Stream) -> int:
    \\    mut f = Frame(chunk=Chunk(values=[]), ip=0)
    \\    const receiver = copy(f.chunk.values)
    \\    print(out, receiver[index(mut f, out)])
    \\    return 0
;

// spec-case: NEW-CORE-U2-BORROW-1
test "U2 borrowing keeps index evaluation output and assertion ahead of the list trap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = borrow_trap, .output = "before\n", .status = 1, .trap = "R_ASSERT" });
}

const release_source =
    \\import dicts
    \\
    \\enum Inner:
    \\    absent
    \\    lists(left: int[], right: int[])
    \\enum Outer:
    \\    number(value: int)
    \\    inner(value: Inner)
    \\func main(out: Stream) -> int:
    \\    mut ints = [7, 8, 9]
    \\    mut values = [Outer.number(value=17), Outer.inner(value=Inner.absent), Outer.inner(value=Inner.lists(left=copy(ints), right=copy(ints)))]
    \\    const snapshot = copy(values)
    \\    values[2] = Outer.number(value=999)
    \\    mut entries: dict[str, Outer] = {str(123): copy(snapshot[2]), str(456): copy(values[2])}
    \\    const saved = copy(entries)
    \\    entries[str(123)] = Outer.inner(value=Inner.absent)
    \\    _ = dicts.pop(mut entries, str(456))
    \\    print(out, len(entries), len(saved), len(snapshot), ints[1])
    \\    return 0
;

// spec: NEW-CORE-U2-RELEASE-1
test "U2 generated layout callbacks specialize guards and dictionary parts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmText(arena.allocator(), release_source);
    try std.testing.expect(std.mem.indexOf(u8, text, ".drop(ptr %element, ptr %pending)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".drop.key(ptr %element, ptr %pending)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".drop.value(ptr %element, ptr %pending)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @myl_core_drop_child_pending") != null);
}

// spec-case: NEW-CORE-U2-RELEASE-1
test "U2 generated release preserves nested union arms aliases and dictionary snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = release_source, .output = "1 2 3 8\n" });
}

const edge_source =
    \\record State:
    \\    count: int
    \\    step: int
    \\func covered(a: int, b: int, again: bool) -> int:
    \\    mut target = a
    \\    if again:
    \\        target = b
    \\    mut state = State(count=a, step=0)
    \\    mut result = state.count - 1
    \\    while state.step < 2:
    \\        result = state.count - 1
    \\        state.count = target
    \\        result = state.count - 1
    \\        state.step += 1
    \\    return result
    \\func uncovered(a: int, b: int, again: bool) -> int:
    \\    mut state = State(count=a, step=0)
    \\    mut result = state.count - 1
    \\    while state.step < 2:
    \\        result = state.count - 1
    \\        if again:
    \\            state.count = b
    \\        state.step += 1
    \\    return result
    \\func main(out: Stream) -> int:
    \\    print(out, covered(7, 0, True), covered(7, 0, False), uncovered(7, 0, True))
    \\    return 0
;

// spec: NEW-CORE-U2-LOX-1
test "U2 every incoming record edge must establish the exact signed operation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), edge_library);
    const covered = try functionText(text, "fn covered(");
    const uncovered = try functionText(text, "fn uncovered(");
    try std.testing.expect(std.mem.indexOf(u8, covered, "sub.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, uncovered, "sub.proven i64") == null);
}

// spec-case: NEW-CORE-U2-LOX-1
test "U2 all-edge overflow proof accepts zero as well as positive record fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = edge_source, .output = "-1 6 -1\n" });
}

const peek_source =
    \\record Stack:
    \\    items: int[]
    \\    top: int
    \\func peek(s: Stack, distance: int) -> int:
    \\    return s.items[s.top - 1 - distance]
    \\func read(s: Stack, distance: int) -> int:
    \\    return peek(s, distance)
    \\func main(out: Stream) -> int:
    \\    print(out, read(Stack(items=[7, 8, 9], top=3), 0), read(Stack(items=[7, 8, 9], top=0), 0))
    \\    return 0
;

// spec: NEW-CORE-U2-LOX-2
test "U2 small read-only list peeks inline their complete checked control flow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), peek_library);
    const body = try functionText(text, "fn read(");
    try std.testing.expect(std.mem.indexOf(u8, body, "peek(") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "sub.exact i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "list_get.exact") != null);
}

// spec-case: NEW-CORE-U2-LOX-2
test "U2 checked inlined peeks trap on runtime negative indexes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = peek_source, .output = "", .status = 1, .trap = "error[R_LIST_BOUNDS]: native execution failed (index -1, length 3)" });
}

const frame_source =
    \\record Chunk:
    \\    values: int[]
    \\    lines: int[]
    \\record Frame:
    \\    chunk: Chunk
    \\    code: int[]
    \\    ip: int
    \\    base: int
    \\record Runtime:
    \\    frames: Frame[]
    \\    stack: int[]
    \\func unrelated(mut rt: Runtime):
    \\    append(mut rt.stack, 99)
    \\func change(mut rt: Runtime):
    \\    rt.frames[0].chunk.values = [90, 91]
    \\    rt.frames[0].ip = 17
    \\func read(mut frame: Frame) -> int:
    \\    frame.ip += 1
    \\    return frame.chunk.values[frame.ip]
    \\func main(out: Stream) -> int:
    \\    mut rt = Runtime(frames=[Frame(chunk=Chunk(values=[10, 11], lines=[1, 2]), code=[0], ip=0, base=0)], stack=[])
    \\    const alias = copy(rt.frames)
    \\    mut frame = copy(rt.frames[0])
    \\    unrelated(mut rt)
    \\    print(out, read(mut frame), rt.frames[0].ip)
    \\    change(mut rt)
    \\    print(out, frame.chunk.values[1], frame.ip, rt.frames[0].chunk.values[1], rt.frames[0].ip, alias[0].ip)
    \\    rt.frames[0] = own frame
    \\    print(out, rt.frames[0].ip, alias[0].chunk.values[1])
    \\    return 0
;

// spec: NEW-CORE-U2-FRAME-1
test "U2 frame snapshots survive disjoint effects overlapping list writes and writeback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = frame_source, .output = "11 0\n11 1 91 17 0\n1 11\n" });
}

const edge_library = edge_source[0..std.mem.indexOf(u8, edge_source, main_decl).?] ++
    \\func main(args: str[], out: Stream) -> int:
    \\    const n = -9223372036854775808 + len(args)
    \\    print(out, covered(n, n, len(args) > 1), uncovered(n, n, len(args) > 1))
    \\    return 0
;
const peek_library = peek_source[0..std.mem.indexOf(u8, peek_source, main_decl).?] ++
    \\func main(args: str[], out: Stream) -> int:
    \\    const n = -9223372036854775808 + len(args)
    \\    print(out, read(Stack(items=[7, 8, 9], top=n), 0))
    \\    return 0
;

const edge_trap = edge_source[0..std.mem.indexOf(u8, edge_source, main_decl).?] ++
    \\func main(out: Stream) -> int:
    \\    print(out, "before")
    \\    print(out, uncovered(7, -9223372036854775808, True))
    \\    return 0
;

// spec-case: NEW-CORE-U2-LOX-1
test "U2 an unchecked changed incoming edge retains its overflow trap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = edge_trap, .output = "before\n", .status = 1, .trap = "R_OVERFLOW" });
}

const peek_trap = peek_source[0..std.mem.indexOf(u8, peek_source, main_decl).?] ++
    \\func main(out: Stream) -> int:
    \\    print(out, "before")
    \\    print(out, read(Stack(items=[7, 8, 9], top=4), 0))
    \\    return 0
;

// spec-case: NEW-CORE-U2-LOX-2
test "U2 an inlined peek retains its bounds failure after earlier output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = peek_trap, .output = "before\n", .status = 1, .trap = "R_LIST_BOUNDS" });
}

// spec-case: NEW-CORE-U2-LOX-2
test "U2 checked inlined peeks support explicit from-end arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Keep the original dynamic-negative fixture above unchanged. The modern
    // counterpart explicitly adds the collection length when counting from its end.
    const replacement = "const index = s.top - 1 - distance\n" ++
        "    if index < 0:\n        return s.items[len(s.items) + index]\n" ++
        "    return s.items[index]";
    const source = try std.mem.replaceOwned(u8, arena.allocator(), peek_source, "return s.items[s.top - 1 - distance]", replacement);
    try nativeModes(arena.allocator(), .{ .source = source, .output = "9 9\n" });
}
