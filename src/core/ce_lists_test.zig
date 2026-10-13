//! Checked list optimization: in-place element stores, direct child destruction,
//! explicit independent copies, borrowing loop sources and inline buffer appends.
//! Outputs retain the historical value semantics; source-required deep copies
//! are distinct from intermediate copies introduced by lowering.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const language = @import("mylang");
const contract = @import("single_owner.zig");
const core_build = @import("build.zig");
const core_passes = @import("passes.zig");
const core_print = @import("print.zig");
const core_emit = @import("emit_llvm.zig");
const zero_rc = @import("zero_rc.zig");
const zero_rc_flag = language.zero_rc_flag;
const optimize_flag = @import("e2e_test.zig").optimize_flag;
const report = std.debug.print;
const copy_prefix = @import("emit_values.zig").copy_prefix;
const octet_copy_symbol = "myl_core_owned_octets_copy";

const Checked = struct { module: @import("ir.zig").Module, analysis: core_passes.Result };

/// Structural oracles use the checked source contract as well as the owned ABI.
/// Selecting checked ownership only on CLI execution would leave IR tests on RC.
fn checkedSource(a: std.mem.Allocator, source: []const u8, release: bool) !Checked {
    var unit = try language.Compilation.init(a, "checked-lists.my", source);
    try unit.check();
    var failure: contract.Failure = .{};
    try contract.checkMode(a, unit.program.?, &failure, true);
    var refusal: core_build.Refusal = .{};
    var module = try core_build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    const analysis = if (release) try core_passes.run(a, &module, .trusted) else try core_passes.debug(a, &module);
    try contract.verifyLowered(&module, &failure);
    try support.verified(a, &module, analysis.plans);
    return .{ .module = module, .analysis = analysis };
}

fn checkedText(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    const checked = try checkedSource(a, source, false);
    const text = try core_print.module(a, &checked.module);
    // Core `release` is also the direct destruction operation; under the checked
    // ABI it emits drop_owned. Assert the selected LLVM boundary as well as the
    // absence of sharing/uniqueness operations instead of forbidding cleanup.
    for ([_][]const u8{ "retain", "is_unique" }) |operation|
        try std.testing.expectEqual(@as(usize, 0), countOp(text, operation));
    _ = try emitChecked(a, &checked);
    return text;
}

fn locate(_: *const anyopaque, offset: u32) core_emit.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn checkedLlvm(a: std.mem.Allocator, source: []const u8, release: bool) ![]const u8 {
    const checked = try checkedSource(a, source, release);
    return emitChecked(a, &checked);
}

fn emitChecked(a: std.mem.Allocator, checked: *const Checked) ![]const u8 {
    const context: u8 = 0;
    const llvm = try core_emit.emitModule(a, &checked.module, .{
        .locator = .{ .context = &context, .locate = locate },
        .source_path = "checked-lists.my",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&checked.analysis),
    });
    try std.testing.expect(zero_rc.emittedClean(llvm));
    return llvm;
}

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
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("checked list build: {s}{s}\n", .{ built.stdout, built.stderr });
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

/// All affected checked pipelines retain the same outputs, traps and cleanup.
const modes = [_][]const []const u8{
    &.{ zero_rc_flag, "--unoptimized" },
    &.{ zero_rc_flag, optimize_flag },
    &.{ zero_rc_flag, optimize_flag, "--verify-facts" },
    &.{ zero_rc_flag, "--optimize-debug" },
    &.{ zero_rc_flag, optimize_flag, "--no-facts" },
};

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
    \\    tags: str[]
    \\
    \\
    \\func bump(mut bodies: Body[], i: int, d: float):
    \\    bodies[i].vx = bodies[i].vx + d
    \\
    \\
    \\func rename(mut xs: Named[], i: int, s: str):
    \\    xs[i].name = s.copy()
    \\    xs[i].pos.x = 3
    \\
    \\
    \\func keep(mut xs: Named[], i: int) -> int:
    \\    mut before = xs[i].copy()
    \\    xs[i].pos.y = 9
    \\    return before.pos.y
    \\
    \\
    \\func grow(mut xs: Named[], i: int):
    \\    xs[i].tags.append("t")
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut bodies = [Body(x=1.0, y=0.0, z=0.0, vx=0.0, vy=0.0, vz=0.0, mass=1.0)]
    \\    bump(mut bodies, 0, 2.0)
    \\    mut xs = [Named(name="a", pos=Vec(x=1, y=2), tags=[])]
    \\    rename(mut xs, 0, "b")
    \\    grow(mut xs, 0)
    \\    mut old_y = keep(mut xs, 0)
    \\    out.print(bodies[0].vx, xs[0].name, xs[0].pos.x, old_y, len(xs[0].tags))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-1
test "checked list field writes stay in place and independent readers keep old values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try checkedText(a, field_stores);
    // `bodies[i].vx = …` reads the element's field and stores the field: no whole-element
    // read, no record update, no whole-element write.
    const bump = functionIr(text, "bump");
    try std.testing.expectEqual(@as(usize, 1), countOp(bump, "list_set_field"));
    try std.testing.expectEqual(@as(usize, 0), countOp(bump, "list_get"));
    try std.testing.expectEqual(@as(usize, 0), countOp(bump, "record_set"));
    try std.testing.expectEqual(@as(usize, 0), countOp(bump, "list_set"));
    // A managed field and a nested one (`path 1.0`) update in place; the borrowed
    // replacement string is copied explicitly without copying the containing list.
    const rename = functionIr(text, "rename");
    try std.testing.expectEqual(@as(usize, 2), countOp(rename, "list_set_field"));
    try std.testing.expect(contains(rename, "path 1.0, 3:i64"));
    try std.testing.expectEqual(@as(usize, 0), countOp(rename, "list_copy"));
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
        // Independent copies keep their values; managed fields and unions (over four words too, each
        // store replacing another case) are released exactly once, and an element read
        // before a field store keeps the old element.
        const plain = try leakChecked(a, root, "ce_elements", flags, &.{});
        try std.testing.expectEqual(@as(u8, 0), plain.status);
        try std.testing.expectEqualStrings(expected_common, plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const stored = try leakChecked(a, root, "ce_elements", flags, &.{ "x", "y" });
        try std.testing.expectEqual(@as(u8, 0), stored.status);
        try std.testing.expectEqualStrings("", stored.stderr);
        try std.testing.expectEqualStrings(expected_common ++ "99 z\n", stored.stdout);
        // `smalls` has three elements, `names` two: at 2 the second store traps
        // where its element read would have, with its index and source position.
        const trapped = try leakChecked(a, root, "ce_elements", flags, &.{ "x", "y", "z", "w" });
        try std.testing.expectEqual(@as(u8, 1), trapped.status);
        try std.testing.expectEqualStrings(expected_common, trapped.stdout);
        const expected_trap = "ce_elements.my:217:9: error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)\n";
        if (!contains(trapped.stderr, expected_trap)) report("checked element trap: {s}\n", .{trapped.stderr});
        try std.testing.expect(contains(trapped.stderr, expected_trap));
    }
}

const whole_store =
    \\record Inner:
    \\    name: str
    \\    tags: str[]
    \\    n: int
    \\
    \\
    \\record Frame:
    \\    closure: int
    \\    inner: Inner
    \\    code: int[]
    \\    ip: int
    \\    base: int
    \\
    \\
    \\func put(mut frames: Frame[], frame: Frame):
    \\    frames[len(frames) - 1] = frame.copy()
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut f = Frame(closure=1, inner=Inner(name="n", tags=[], n=0), code=[1], ip=0, base=0)
    \\    mut frames = [f.copy()]
    \\    mut g = f
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
    const llvm = try checkedLlvm(arena.allocator(), whole_store, false);
    const start = std.mem.indexOf(u8, llvm, "define internal fastcc ptr @\"my.put\"(") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, llvm, start, "\n}\n") orelse llvm.len;
    const put = llvm[start..end];
    // The new Frame is built in the destination slot, without copying either
    // whole Frame. The old inner record and code pointer are loaded in place;
    // its name, tags and code owners are each directly destroyed after the store.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, put, "@llvm.memcpy"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, put, "\n  %old."));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, put, "call void @myl_core_drop_owned("));
}

// spec: NEW-CORE-CE-LISTS-3
test "checked write-backs add no container copies beyond explicit independent source copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/ce_cow.my", .{options.fixtures}), a, .limited(1 << 20));
    const text = try checkedText(a, source);
    // Direct mutation through it.rt preserves the owned Runtime without copying
    // its four scalar lists or its object table; the stack store stays in place.
    const instantiate = functionIr(text, "instantiate");
    try std.testing.expectEqual(@as(usize, 0), countOp(instantiate, "list_copy"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, instantiate, copy_prefix));
    try std.testing.expectEqual(@as(usize, 1), countOp(instantiate, "list_set"));
    // Sweep copies only a selected object's managed children before mutation.
    // Marking mutates a scalar list directly, without copying it or its record.
    const sweep = functionIr(text, "sweep");
    try std.testing.expectEqual(@as(usize, 1), countOp(sweep, "list_copy"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, sweep, octet_copy_symbol));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, sweep, copy_prefix));
    const mark = functionIr(text, "mark_some");
    try std.testing.expectEqual(@as(usize, 0), countOp(mark, "list_copy"));
    try std.testing.expectEqual(@as(usize, 1), countOp(mark, "list_set"));
    const kept = functionIr(text, "snapshot_then_store");
    try std.testing.expectEqual(@as(usize, 1), countOp(kept, "list_copy"));
    try std.testing.expectEqual(@as(usize, 1), countOp(kept, "list_set"));
    // The independent Comp has three managed containers (pins.net, used, seen).
    // Its key, pins.ref and the two inserted strings account for four octet copies.
    // The containing comps dictionary is updated in place, never copied.
    const builder = functionIr(text, "build");
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, builder, copy_prefix));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, builder, octet_copy_symbol));
    try std.testing.expectEqual(@as(usize, 0), countOp(builder, "dict_copy"));
    try std.testing.expectEqual(@as(usize, 0), countOp(builder, "list_copy"));
}

const big_part =
    \\record Big:
    \\    a: str
    \\    b: int[]
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
    \\func touch(mut h: Holder) -> int:
    \\    h.n = h.n + 1
    \\    return h.n
    \\
    \\
    \\func keep(mut h: Holder, i: int) -> int:
    \\    mut x = h.items[i].copy()
    \\    mut k = touch(mut h)
    \\    return k + len(x.b) + len(x.a)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut h = Holder(items=[Big(a="s", b=[1], c=0, d=0, e=0)], n=0)
    \\    out.print(keep(mut h, 0))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-4
test "checked copies keep selected managed children across mutation without copying the containing list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/ce_cow.my", .{options.fixtures}), a, .limited(1 << 20));
    const text = try checkedText(a, source);
    // The selected Klass owns independent name/methods before allocate mutates
    // rt.objects. There is no object-table deep copy or implicit count promotion.
    const call_value = functionIr(text, "call_value");
    try std.testing.expectEqual(@as(usize, 1), countOp(call_value, "list_copy"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, call_value, octet_copy_symbol));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, call_value, copy_prefix));
    try std.testing.expect(contains(call_value, "list_get_field record{str, list[i64]}"));
    // The same contract holds for a selected record larger than four words:
    // copy its two managed children, then read them after the mutating call.
    const keep = functionIr(try checkedText(a, big_part), "keep");
    try std.testing.expectEqual(@as(usize, 1), countOp(keep, "list_copy"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, keep, octet_copy_symbol));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, keep, copy_prefix));
    try std.testing.expect(contains(keep, "list_get.exact record{"));
    const keep_llvm = try definition(try checkedLlvm(a, big_part, true), "@\"my.keep\"(");
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
    \\func total(xs: int[], a: int, b: int) -> int:
    \\    mut n = 0
    \\    for x in xs[a:b]:
    \\        if x < 0:
    \\            break
    \\        n = n * 10 + x
    \\    return n
    \\
    \\
    \\func written(mut xs: int[]) -> int:
    \\    mut n = 0
    \\    for x in xs[1:]:
    \\        xs[0] = x
    \\        n = n + x
    \\    return n
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    out.print(total(xs, 1, 9), written(mut xs))
    \\    return 0
    \\
;

// spec: NEW-CORE-CE-LISTS-5
test "a slice used only as a loop source is iterated in place, and a slice still built gets its exact room" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try checkedText(a, slice_loops);
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
    \\func main(out: Stream) -> int:
    \\    mut empty: int[] = []
    \\    mut buffer = byte_buffer(empty)
    \\    mut piece = b"mylang!\n"
    \\    for i in range(1000):
    \\        _ = buffer.append_range(piece, 0, 8)
    \\    out.print(len(buffer))
    \\    return 0
    \\
;

const appends_several =
    \\func fill(mut buffer: byte_buffer, piece: bytes, text: str) -> int:
    \\    mut n = 0
    \\    if buffer.append_range(piece, 1, 3):
    \\        n += 1
    \\    if buffer.append_utf8(text):
    \\        n += 1
    \\    if buffer.append_range(piece, 0, len(piece)):
    \\        n += 1
    \\    return n
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut empty: int[] = []
    \\    mut buffer = byte_buffer(empty)
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
    const llvm = try checkedLlvm(a, appends_loop, true);
    try std.testing.expect(contains(llvm, "append.fast"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, llvm, "call ptr @myl_core_buffer_append_checked("));
    try std.testing.expect(!contains(llvm, "call i1 @myl_core_buffer_range_valid"));
    const text = try checkedText(a, appends_loop);
    try std.testing.expectEqual(@as(usize, 1), countOp(text, "buffer_append"));
    // Several appends in one function, each rewritten with its own operands (the IR is
    // verified after ownership).
    const several = try checkedText(a, appends_several);
    try std.testing.expectEqual(@as(usize, 3), countOp(functionIr(several, "fill"), "buffer_append"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Valid, empty, reversed, negative and past-the-end ranges through several growths, a
    // fill exactly to the reserved room and one octet past it, an independent snapshot,
    // and appends from another buffer.
    const expected = "2729 1026 435284\n16 17 697512\n2729 2743 2729 770813\n2747 905629 48633\n10 771938\n";
    for (modes) |flags| {
        const ran = try leakChecked(a, root, "ce_appends", flags, &.{});
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings(expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const grown = try leakChecked(a, root, "ce_appends", flags, &.{ "grow", "100000" });
        try std.testing.expectEqual(@as(u8, 0), grown.status);
        try std.testing.expectEqualStrings("", grown.stderr);
        try std.testing.expectEqualStrings(expected ++ "100000\n", grown.stdout);
    }
    // A growth past the memory budget traps inside the append, at the append.
    try expectGrowthTrap(a, root, expected, &.{zero_rc_flag});
    try expectGrowthTrap(a, root, expected, &.{ optimize_flag, zero_rc_flag });
}

/// `mylang run` of `ce_appends grow` under a 1 MiB budget traps in the append, reported there.
fn expectGrowthTrap(a: std.mem.Allocator, root: []const u8, expected: []const u8, flags: []const []const u8) !void {
    const source = try std.fmt.allocPrint(a, "{s}/ce_appends.my", .{options.fixtures});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "run", source, "--max-memory=1M", "--cache-dir", try std.fmt.allocPrint(a, "{s}/run-cache", .{root}) });
    try argv.appendSlice(a, flags);
    try argv.appendSlice(a, &.{ "--", "grow", "10000000" });
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expectEqualStrings(expected, ran.stdout);
    try std.testing.expect(contains(ran.stderr, "error[R_MEMORY_BUDGET]: memory budget exhausted"));
    const frame = try std.fmt.allocPrint(a, "in main at {s}/ce_appends.my:62:17\n", .{options.fixtures});
    try std.testing.expect(contains(ran.stderr, frame));
}
