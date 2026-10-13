//! Lane U1 (docs/audits/runtime-parity-plan-2026-10-08.md §8): the runtime's growth of
//! large blocks, uniqueness tests hoisted out of loops, and loop-carried state kept out
//! of memory. Every expected output is the base compiler's (main 35df839be) for the
//! same program and arguments.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.my` with `flags` and run it with `args` under the leak check;
/// a counting build writes its counters beside the executable (`countsOf`).
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}-{d}", .{ root, name, flags.len, if (flags.len > 0) flags[flags.len - 1].len else 0 });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    try environment.put("MYLANG_COUNTERS", try std.fmt.allocPrint(arena, "{s}.json", .{output}));
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// The counters a counting run of `leakChecked` wrote for `name` built with `flags`.
fn countsOf(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8) !std.json.Value {
    const path = try std.fmt.allocPrint(arena, "{s}/{s}-{d}-{d}.json", .{ root, name, flags.len, flags[flags.len - 1].len });
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, arena, .limited(16 << 20));
    return std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{});
}

/// Counter `name` of the emitted function `function` in a counting run's document.
fn functionCounter(counts: std.json.Value, function: []const u8, name: []const u8) i64 {
    for (counts.object.get("functions").?.array.items) |row| {
        if (std.mem.eql(u8, row.object.get("name").?.string, function)) return (row.object.get(name) orelse return 0).integer;
    }
    return -1;
}

/// Whether a child exited with status 0 (its output reported when not).
fn succeeded(ran: std.process.RunResult) bool {
    const ok = ran.term == .exited and ran.term.exited == 0;
    if (!ok) report("child: {s}{s}\n", .{ ran.stdout, ran.stderr });
    return ok;
}

/// Debug, release, and release with the facts verified.
// Optimized debug (`--optimize-debug`) runs the same passes as release over module units.
const modes = [_][]const []const u8{ &.{"--unoptimized"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--verify-facts", "--optimize-debug" } };

// spec: NEW-CORE-U1-GROW-1
test "a large byte buffer grows with realloc, and every append, reserve and shared append keeps its answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "u1_growth", flags, &.{});
        try std.testing.expectEqualStrings("407375991 70000851576\n7822122 916196 1005004\n0\n1 1\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "u1_growth", flags, &.{"x"});
        try std.testing.expectEqualStrings("158614987 700003052886\n21729292 2869998 2000019\n0\n1 1\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
    // A counting build: the large buffer's doublings are reallocations, not copies into
    // fresh blocks, so only its small-block growth copies.
    const counting = [_][]const u8{ "--release", "--counters" };
    const ran = try leakChecked(a, root, "u1_growth", &counting, &.{});
    try std.testing.expectEqualStrings("407375991 70000851576\n7822122 916196 1005004\n0\n1 1\n", ran.stdout);
    const counts = try countsOf(a, root, "u1_growth", &counting);
    try std.testing.expect(functionCounter(counts, "byte_appends", "reallocs") >= 6);
    try std.testing.expect(functionCounter(counts, "byte_appends", "buffer_grow_bytes") < 1024);
    // A large list keeps growing with realloc as before.
    try std.testing.expect(functionCounter(counts, "list_growth", "reallocs") >= 4);
    try std.testing.expectEqual(@as(i64, 0), functionCounter(counts, "list_growth", "buffer_grows"));
}

/// The sum of `name` over the sites of `kind` emitted in `function`.
fn siteSum(counts: std.json.Value, kind: []const u8, function: []const u8, name: []const u8) i64 {
    var sum: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("function").?.string, function)) continue;
        sum += object.get(name).?.integer;
    }
    return sum;
}

const hoist_expected = "90230 33 2\n865079466 962860009 86651320\n458455359 976384266 554113001 8718774604\n814298128 890434128 128128\n605789002 676242 22549 41868000\n343010 32 598486 343010\n952490 3 21\n";
const hoist_expected_more = "373724 33 2\n102650968 453315009 88748160\n948059408 36681838 395256001 9223654218\n814298128 175119 128128\n58046002 676242 63229 950607000\n54592 32 317729 54592\n71883 3 61\n";

// spec: NEW-CORE-U1-HOIST-1
test "a loop's updates of a value nothing in the loop shares test its count once, on the loop's entry edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{ &.{"--counters"}, &.{ "--release", "--counters" } }) |flags| {
        const ran = try leakChecked(a, root, "u1_hoist", flags, &.{});
        try std.testing.expectEqualStrings(hoist_expected, ran.stdout);
        const counts = try countsOf(a, root, "u1_hoist", flags);
        // `nested_mut` updates the `mut` list its caller shares 2 * (1 + 2 + 3 + 4) times in
        // its inner loop: one test, which finds it shared, before the outer loop.
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "nested_mut", "count"));
        try std.testing.expectEqual(@as(i64, 0), siteSum(counts, "unique_test", "nested_mut", "extra"));
        // A list a call returned: one test, which finds it unique, for 20 appends.
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "from_call", "count"));
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "from_call", "extra"));
        // Two loops over a shared `mut` list: one test, before the first.
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "two_loops", "count"));
        // An alias held until the loop's third iteration: the entering list is still needed,
        // so each of the 20 appends keeps its test.
        try std.testing.expectEqual(@as(i64, 20), siteSum(counts, "unique_test", "dropped_alias", "count"));
    }
}

// spec-case: NEW-CORE-U1-HOIST-1
test "hoisted tests keep every answer: aliases made, kept or dropped in the loop, rows, rebinding, control flow, calls, text, dictionaries, buffers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "u1_hoist", flags, &.{});
        try std.testing.expectEqualStrings(hoist_expected, plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "u1_hoist", flags, &.{"x"});
        try std.testing.expectEqualStrings(hoist_expected_more, more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
}

const state_expected = "601814 6 132 7\n476744 90\n501100 5 6\n6000 0 10\n";

// spec: NEW-CORE-U1-STATE-1
test "a scalar field a loop carries in a record is read from SSA values, not from the record's memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const llvm = try support.releaseLlvmText(a,
        \\record Frame:
        \\    code: int[]
        \\    ip: int
        \\    base: int
        \\    name: str
        \\    hits: int
        \\
        \\
        \\func run(mut frame: Frame, n: int) -> int:
        \\    mut total = 0
        \\    while frame.ip < n:
        \\        total = total + frame.code[frame.ip % 4]
        \\        frame.ip = frame.ip + 1
        \\    return total
        \\
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    mut frame = Frame(code=[1, 2, 3, 4], ip=0, base=0, name="f", hits=0)
        \\    out.print(run(mut frame, 10 + len(args)), frame.ip)
        \\    return 0
        \\
    );
    // `frame.ip` is a phi of the loop: its memory is read once, before the loop.
    const body = llvm[std.mem.indexOf(u8, llvm, "@\"my.run\"(ptr noalias sret").?..];
    const end = std.mem.indexOf(u8, body, "\n}\n").?;
    try std.testing.expect(std.mem.indexOf(u8, body[0..end], "phi i64") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body[0..end], "load i64, ptr %fp."));
}

/// The text of function `name` in a module's textual Core IR, up to the next function.
fn functionText(text: []const u8, name: []const u8) []const u8 {
    const header = std.mem.indexOf(u8, text, name) orelse return "";
    const next = std.mem.indexOfPos(u8, text, header + name.len, "\nfn ") orelse text.len;
    return text[header..next];
}

// spec-case: NEW-CORE-U1-STATE-1
test "a field the loop only passes through stays a read; a field it writes becomes one phi" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try support.optimizedText(a,
        \\record Frame:
        \\    code: int[]
        \\    ip: int
        \\    base: int
        \\    name: str
        \\    hits: int
        \\
        \\
        \\func run(mut frame: Frame, n: int) -> int:
        \\    while frame.ip < n:
        \\        frame.ip = frame.ip + frame.base
        \\    return frame.ip
        \\
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    mut frame = Frame(code=[1], ip=0, base=1 + len(args), name="f", hits=0)
        \\    out.print(run(mut frame, 10), frame.ip)
        \\    return 0
        \\
    );
    const run = functionText(text, "fn run(");
    // `ip` is written in the loop: one phi of integers; `base` is only passed along: its
    // read stays in the loop, and `ip` is read once, where the parameter is defined.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, run, "= phi i64"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, run, "= record_get i64"));
}

// spec-case: NEW-CORE-U1-STATE-1
test "promoted record state keeps every answer: calls that read or write it, copies, break, continue, early return, traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "u1_state", flags, &.{});
        try std.testing.expectEqualStrings(state_expected, plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        // The trap reports the index the promoted stack pointer gives, after the earlier output.
        const trapped = try leakChecked(a, root, "u1_state", flags, &.{"x"});
        try std.testing.expectEqualStrings("601814 6 132 7\n476744 90\n501100 5 6\n", trapped.stdout);
        try std.testing.expectEqual(@as(u8, 1), trapped.status);
        try std.testing.expect(std.mem.indexOf(u8, trapped.stderr, "error[R_LIST_BOUNDS]: native execution failed (index 101, length 64)") != null);
    }
}

/// The sum of `name` over the sites of `kind` emitted in `function` at source line `line`.
fn lineSum(counts: std.json.Value, kind: []const u8, function: []const u8, line: i64) i64 {
    var sum: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("function").?.string, function)) continue;
        if (object.get("line").?.integer == line) sum += object.get("count").?.integer;
    }
    return sum;
}

const sink_expected = "22017 1 6 17\n5797447\n20501002 1 120600\n6011\n";

// spec: NEW-CORE-U1-SINK-1
test "a store ahead of an if-elif ladder runs only in the arms that observe it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{ &.{"--counters"}, &.{ "--release", "--counters" } }) |flags| {
        const ran = try leakChecked(a, root, "u1_sink", flags, &.{});
        try std.testing.expectEqualStrings(sink_expected, ran.stdout);
        const counts = try countsOf(a, root, "u1_sink", flags);
        // The frames store after each of the 1031 dispatches (line 52) is tested and made
        // only where an arm reads the frames: the observations, calls, returns and the exit.
        // Sunk one level (main's rule) it ran 216 times.
        try std.testing.expect(lineSum(counts, "unique_test", "run", 52) <= 16);
    }
}

// spec-case: NEW-CORE-U1-SINK-1
test "a store sunk several blocks down keeps its operands: the guest tests that sink most still pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fmt.allocPrint(a, "{s}/rc_counted_receivers.my", .{options.lang_tests});
    const cache = try std.fmt.allocPrint(a, "{s}/cache", .{root});
    var environment = try options.privateEnvironment(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    // Each sinking copies the store's operands to a new place in `extra`; a copy taken from
    // under an append that moved it read freed memory (a compiler panic, at --verify-facts).
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "test", source, "--release", "--verify-facts", "--cache-dir", cache }, .environ_map = &environment });
    try std.testing.expect(succeeded(ran));
}

// spec-case: NEW-CORE-U1-SINK-1
test "sunk frame stores keep every answer, and a trap still reports the frames as stored" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "u1_sink", flags, &.{});
        try std.testing.expectEqualStrings(sink_expected, plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const trapped = try leakChecked(a, root, "u1_sink", flags, &.{"x"});
        try std.testing.expectEqualStrings("22017 1 6 17\n5797447\n20501002 1 120600\n", trapped.stdout);
        try std.testing.expectEqual(@as(u8, 1), trapped.status);
        try std.testing.expect(std.mem.indexOf(u8, trapped.stderr, "error[R_LIST_BOUNDS]: native execution failed (index 6, length 1)") != null);
    }
}

const appends_expected = "43171 589707438 191476 1262695\n1149056 908500 830547793 461553 13377258 49083919937\n300\n";
const appends_trapped = "444939 925308766 191476 -1\n27527112 52985500 197161761 539740 111193620 21517689238\n";

// spec: NEW-CORE-U1-STATE-2
test "a list or buffer a loop appends to keeps its length and capacity in slots; a loop that reads it does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const llvm = try support.releaseLlvmText(a,
        \\func fill(n: int) -> int[]:
        \\    mut xs = [n, 1]
        \\    for i in range(n):
        \\        xs.append(i * 3)
        \\    return xs
        \\
        \\
        \\func bounded(n: int) -> int[]:
        \\    mut xs: int[] = []
        \\    while len(xs) < n:
        \\        xs.append(len(xs))
        \\    return xs
        \\
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    out.print(len(fill(10 + len(args))), len(bounded(5)))
        \\    return 0
        \\
    );
    const fill = llvm[std.mem.indexOf(u8, llvm, "define internal fastcc ptr @\"my.fill\"(").?..];
    const fill_end = std.mem.indexOf(u8, fill, "\n}\n").?;
    try std.testing.expect(std.mem.indexOf(u8, fill[0..fill_end], "%state0.len = alloca i64") != null);
    const bounded = llvm[std.mem.indexOf(u8, llvm, "define internal fastcc ptr @\"my.bounded\"(").?..];
    const bounded_end = std.mem.indexOf(u8, bounded, "\n}\n").?;
    try std.testing.expect(std.mem.indexOf(u8, bounded[0..bounded_end], "%state") == null);
}

// spec-case: NEW-CORE-U1-STATE-2
test "appends with the length in slots keep every answer: exits, nested loops, managed elements, buffers, calls, traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "u1_appends", flags, &.{});
        try std.testing.expectEqualStrings(appends_expected, plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const trapped = try leakChecked(a, root, "u1_appends", flags, &.{"x"});
        try std.testing.expectEqualStrings(appends_trapped, trapped.stdout);
        try std.testing.expectEqual(@as(u8, 1), trapped.status);
        try std.testing.expect(std.mem.indexOf(u8, trapped.stderr, "error[R_LIST_BOUNDS]: native execution failed (index 1234, length 1)") != null);
    }
}
