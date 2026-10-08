//! Copy elimination for lists (CE-B): element-field stores in place, whole-element
//! stores that release the old element's parts without copying it, copy on write
//! narrowed to what is shared, slices used only as a loop source, and inline buffer
//! appends. Every expected output is the base compiler's (`claude/copy-elim`
//! 137d00ef) for the same program and arguments.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
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

/// The value the first `retain` in `text` retains (`%N`).
fn retainedValue(text: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, text, "retain %") orelse return null;
    const start = at + "retain ".len;
    const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
    return text[start..end];
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

/// Build `test/core/NAME.my` with `flags` and run it with `args` under the leak check.
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}", .{ root, name, flags.len });
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

const field_stores =
    \\record Body:
    \\    x: float
    \\    y: float
    \\    z: float
    \\    vx: float
    \\    vy: float
    \\    vz: float
    \\    mass: float
    \\
    \\
    \\record Vec:
    \\    x: int
    \\    y: int
    \\
    \\
    \\record Named:
    \\    name: str
    \\    pos: Vec
    \\    tags: list[str]
    \\
    \\
    \\def bump(bodies: mut list[Body], i: int, d: float):
    \\    bodies[i].vx = bodies[i].vx + d
    \\
    \\
    \\def rename(xs: mut list[Named], i: int, s: str):
    \\    xs[i].name = s
    \\    xs[i].pos.x = 3
    \\
    \\
    \\def keep(xs: mut list[Named], i: int) -> int:
    \\    before = xs[i]
    \\    xs[i].pos.y = 9
    \\    return before.pos.y
    \\
    \\
    \\def grow(xs: mut list[Named], i: int):
    \\    xs[i].tags.append("t")
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    bodies = [Body(x=1.0, y=0.0, z=0.0, vx=0.0, vy=0.0, vz=0.0, mass=1.0)]
    \\    bump(mut bodies, 0, 2.0)
    \\    xs = [Named(name="a", pos=Vec(x=1, y=2), tags=[])]
    \\    rename(mut xs, 0, "b")
    \\    grow(mut xs, 0)
    \\    out.print(bodies[0].vx, xs[0].name, xs[0].pos.x, keep(mut xs, 0), len(xs[0].tags))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-1
test "a store into a field of a list element is one in-place field store after the list's uniqueness test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try support.ownedText(a, field_stores);
    // `bodies[i].vx = …` reads the element's field and stores the field: no whole-element
    // read, no record update, no whole-element write.
    const bump = functionIr(text, "bump");
    try std.testing.expectEqual(@as(usize, 1), countOp(bump, "list_set_field"));
    try std.testing.expectEqual(@as(usize, 0), countOp(bump, "list_get"));
    try std.testing.expectEqual(@as(usize, 0), countOp(bump, "record_set"));
    try std.testing.expectEqual(@as(usize, 0), countOp(bump, "list_set"));
    // A managed field and a nested one (`path 1.0`), each in place after the list's test.
    const rename = functionIr(text, "rename");
    try std.testing.expectEqual(@as(usize, 2), countOp(rename, "list_set_field"));
    try std.testing.expect(contains(rename, "path 1.0, 3:i64"));
    try std.testing.expectEqual(countOp(rename, "is_unique"), countOp(rename, "list_copy"));
    // The element read into a local before the store is still read whole and kept.
    const keep = functionIr(text, "keep");
    try std.testing.expectEqual(@as(usize, 1), countOp(keep, "list_set_field"));
    // An append to a list field of an element takes the field and stores it back in place
    // (CE2-B, NEW-CORE-CE2-RESULTS-7): no whole-element read or write.
    try std.testing.expectEqual(@as(usize, 1), countOp(functionIr(text, "grow"), "list_set_field"));
    try std.testing.expectEqual(@as(usize, 0), countOp(functionIr(text, "grow"), "list_set"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const expected_common =
        \\4599556 78493 1.0 0.0
        \\18 13 22 18 1 6
        \\a!!!!!/a!!!!!:2:11:6:2 b!!!!!/b!!!!!:2:13:6:2  2
        \\a/-:1:1:0:0 b/q:2:3:0:1  2
        \\l1 d2 p1,2 n  d4 p2,3 lhey n  24
        \\7233 105 33 5 0
        \\120 9 4
        \\20 1000 -0.05232905378682199 77.0 a!!!!! changed 2 3
        \\
    ;
    for (modes) |flags| {
        // Shared lists keep their values, managed fields and unions (over four words too, each
        // store replacing another case) are released exactly once, and an element read
        // before a field store keeps the old element.
        const plain = try leakChecked(a, root, "ce_elements", flags, &.{});
        try std.testing.expectEqualStrings(expected_common, plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const stored = try leakChecked(a, root, "ce_elements", flags, &.{ "x", "y" });
        try std.testing.expectEqualStrings(expected_common ++ "99 z\n", stored.stdout);
        // Out of range: the store traps where the element read would have, with its index.
        const trapped = try leakChecked(a, root, "ce_elements", flags, &.{ "x", "y", "z", "w" });
        try std.testing.expectEqual(@as(u8, 1), trapped.status);
        try std.testing.expectEqualStrings(expected_common, trapped.stdout);
        try std.testing.expect(contains(trapped.stderr, "ce_elements.my:216:9: error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)\n"));
    }
}

const whole_store =
    \\record Inner:
    \\    name: str
    \\    tags: list[str]
    \\    n: int
    \\
    \\
    \\record Frame:
    \\    closure: int
    \\    inner: Inner
    \\    code: list[int]
    \\    ip: int
    \\    base: int
    \\
    \\
    \\def put(frames: mut list[Frame], frame: Frame):
    \\    frames[len(frames) - 1] = frame
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    f = Frame(closure=1, inner=Inner(name="n", tags=[], n=0), code=[1], ip=0, base=0)
    \\    frames = [f]
    \\    g = f
    \\    g.ip = 4
    \\    put(mut frames, g)
    \\    out.print(frames[0].ip)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-2
test "a whole-element store releases the old element's managed parts without copying the element out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), whole_store);
    const start = std.mem.indexOf(u8, llvm, "define internal fastcc ptr @\"my.put\"(") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, llvm, start, "\n}\n") orelse llvm.len;
    const put = llvm[start..end];
    // One copy: the stored value into the element. The old element's managed parts (the
    // three-word `inner` record as one value, the `code` list) are loaded where they are
    // and released after the store.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, put, "@llvm.memcpy"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, put, "\n  %old."));
}

// spec: NEW-CORE-CE-LISTS-3
test "a read of a record field merges with an earlier identical read in another block, so a write-back takes the field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/ce_cow.my", .{options.fixtures}), a, .limited(1 << 20));
    const text = try support.ownedText(a, source["module ce_cow\n".len..]);
    // `it.rt.stack[i] = v` after a `mut` call through a write-back temporary, and the
    // collector's `rt.marker.marks[i] = False`: the index's negative branch splits each
    // into a read that reaches the list and one that writes it back. Every copy is a
    // uniqueness test's copy arm now, never an unconditional copy of the whole list.
    for ([_][]const u8{ "instantiate", "sweep", "mark_some" }) |name| {
        const body = functionIr(text, name);
        try std.testing.expect(countOp(body, "is_unique") > 0);
        try std.testing.expectEqual(countOp(body, "is_unique"), countOp(body, "list_copy"));
    }
    // A copy of the list taken before the store still keeps the old list.
    const kept = functionIr(text, "snapshot_then_store");
    try std.testing.expectEqual(@as(usize, 1), countOp(kept, "list_copy"));
    // A record passed to a call between the read of its dictionary and the write-back keeps
    // its later read separate, so the write-back still takes the dictionary: every copy in
    // the builder is a count test's copy arm.
    const build = functionIr(text, "build");
    try std.testing.expectEqual(countOp(build, "is_unique"), countOp(build, "dict_copy") + countOp(build, "list_copy"));
}

const big_part =
    \\record Big:
    \\    a: str
    \\    b: list[int]
    \\    c: int
    \\    d: int
    \\    e: int
    \\
    \\
    \\record Holder:
    \\    items: list[Big]
    \\    n: int
    \\
    \\
    \\def touch(h: mut Holder) -> int:
    \\    h.n = h.n + 1
    \\    return h.n
    \\
    \\
    \\def keep(h: mut Holder, i: int) -> int:
    \\    x = h.items[i]
    \\    k = touch(mut h)
    \\    return k + len(x.b) + len(x.a)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    h = Holder(items=[Big(a="s", b=[1], c=0, d=0, e=0)], n=0)
    \\    out.print(keep(mut h, 0))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-4
test "an element's part read before a mut call and used after it holds its own count, not the whole list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/ce_cow.my", .{options.fixtures}), a, .limited(1 << 20));
    const text = try support.ownedText(a, source["module ce_cow\n".len..]);
    // `match rt.objects[ref]: case klass(k): allocate(mut rt, …); … k.methods`: the payload
    // read is retained, not `rt.objects`, so `allocate` finds the list unique.
    const call_value = functionIr(text, "call_value");
    try std.testing.expectEqual(@as(usize, 1), countOp(call_value, "retain"));
    const retained = retainedValue(call_value) orelse return error.TestUnexpectedResult;
    try std.testing.expect(contains(call_value, try std.fmt.allocPrint(a, "{s} = list_get_field record{{str, list[i64]}}", .{retained})));
    // A part over four words holds its own count too, counted field by field where it is:
    // the only copy is the element read itself.
    const keep = functionIr(try support.ownedText(a, big_part), "keep");
    try std.testing.expectEqual(@as(usize, 1), countOp(keep, "retain"));
    const part = retainedValue(keep) orelse return error.TestUnexpectedResult;
    try std.testing.expect(contains(keep, try std.fmt.allocPrint(a, "{s} = list_get.exact record{{", .{part})));
    const keep_llvm = try definition(try support.releaseLlvmText(a, big_part), "@\"my.keep\"(");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, keep_llvm, "@llvm.memcpy"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const ran = try leakChecked(a, root, "ce_cow", flags, &.{});
        try std.testing.expectEqualStrings("30115815 20000 1500 1000 1 4 0\n5 1009 5 9\n2 2 1 0\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}

const slice_loops =
    \\def total(xs: list[int], a: int, b: int) -> int:
    \\    n = 0
    \\    for x in xs[a:b]:
    \\        if x < 0:
    \\            break
    \\        n = n * 10 + x
    \\    return n
    \\
    \\
    \\def written(xs: mut list[int]) -> int:
    \\    n = 0
    \\    for x in xs[1:]:
    \\        xs[0] = x
    \\        n = n + x
    \\    return n
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    xs = [1, 2, 3]
    \\    out.print(total(xs, 1, 9), written(mut xs))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-5
test "a slice used only as a loop source is iterated in place, and a slice still built gets its exact room" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try support.irText(a, slice_loops);
    // `for x in xs[a:b]` counts over `xs` from the clamped start to the clamped end: no
    // list is built and nothing is pushed.
    const total = functionIr(text, "total");
    try std.testing.expectEqual(@as(usize, 0), countOp(total, "list_new"));
    try std.testing.expectEqual(@as(usize, 0), countOp(total, "list_push"));
    try std.testing.expectEqual(@as(usize, 1), countOp(total, "list_get"));
    // A loop that writes the source keeps its snapshot, built with room for exactly its elements.
    const written = functionIr(text, "written");
    try std.testing.expectEqual(@as(usize, 1), countOp(written, "list_new"));
    try std.testing.expect(!contains(written, "list_new list[i64] 0:i64"));
    try std.testing.expect(contains(written, "shift_right"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Nested slice loops with `break` and `continue`, managed elements, negative, reversed,
    // empty and out-of-range bounds, an early `return`, and loops that write, pass `mut` or
    // rebind the source, or keep the slice.
    for (modes) |flags| {
        const ran = try leakChecked(a, root, "ce_slices", flags, &.{});
        try std.testing.expectEqualStrings("788980 0 0\n806 420 0 261 0 0 3244\n9 8 -1 -1\nc,def,, ,gh, \n9010 1023 13 435 15 10 7 2\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}

const appends_loop =
    \\def main(out: Stream) -> int:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    piece = b"mylang!\n"
    \\    for i in range(1000):
    \\        _ = buffer.append_range(piece, 0, 8)
    \\    out.print(len(buffer))
    \\    return 0
    \\
;

const appends_several =
    \\def fill(buffer: mut byte_buffer, piece: bytes, text: str) -> int:
    \\    n = 0
    \\    if buffer.append_range(piece, 1, 3):
    \\        n += 1
    \\    if buffer.append_utf8(text):
    \\        n += 1
    \\    if buffer.append_range(piece, 0, len(piece)):
    \\        n += 1
    \\    return n
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    out.print(fill(mut buffer, b"abcd", "xy"), len(buffer))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-6
test "a byte-buffer append copies in place when the range fits the room and calls the runtime only to grow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The range test is comparisons and the append an inline copy: the runtime's checked
    // append is called once, on the slow path, and the range test never.
    const llvm = try support.releaseLlvmText(a, appends_loop);
    try std.testing.expect(contains(llvm, "append.fast"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, llvm, "call ptr @myl_core_buffer_append_checked("));
    try std.testing.expect(!contains(llvm, "call i1 @myl_core_buffer_range_valid"));
    const text = try support.ownedText(a, appends_loop);
    try std.testing.expectEqual(@as(usize, 1), countOp(text, "buffer_append"));
    // Several appends in one function, each rewritten with its own operands (the IR is
    // verified after ownership).
    const several = try support.ownedText(a, appends_several);
    try std.testing.expectEqual(@as(usize, 3), countOp(functionIr(several, "fill"), "buffer_append"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Valid, empty, reversed, negative and past-the-end ranges through several growths, a
    // fill exactly to the reserved room and one octet past it, a snapshot that shares the
    // buffer's storage, and appends from another buffer.
    const expected = "2729 1026 435284\n16 17 697512\n2729 2743 2729 770813\n2747 905629 48633\n10 771938\n";
    for (modes) |flags| {
        const ran = try leakChecked(a, root, "ce_appends", flags, &.{});
        try std.testing.expectEqualStrings(expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const grown = try leakChecked(a, root, "ce_appends", flags, &.{ "grow", "100000" });
        try std.testing.expectEqualStrings(expected ++ "100000\n", grown.stdout);
    }
    // A growth past the memory budget traps inside the append, at the append.
    try expectGrowthTrap(a, root, expected, &.{});
    try expectGrowthTrap(a, root, expected, &.{"--release"});
}

/// `mylang run` of `ce_appends grow` under a 1 MiB budget traps in the append, reported there.
fn expectGrowthTrap(a: std.mem.Allocator, root: []const u8, expected: []const u8, flags: []const []const u8) !void {
    const source = try std.fmt.allocPrint(a, "{s}/ce_appends.my", .{options.fixtures});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "run", source, "--max-memory=1M", "--cache-dir", try std.fmt.allocPrint(a, "{s}/run-cache", .{root}) });
    try argv.appendSlice(a, flags);
    try argv.appendSlice(a, &.{ "--", "grow", "10000000" });
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expectEqualStrings(expected, ran.stdout);
    try std.testing.expect(contains(ran.stderr, "error[R_MEMORY_BUDGET]: memory budget exhausted"));
    try std.testing.expect(contains(ran.stderr, "in ce_appends::main at ce_appends.my:61:17\n"));
}
