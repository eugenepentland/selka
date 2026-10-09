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
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
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

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

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
    try std.testing.expect(functionCounter(counts, "u1_growth::byte_appends", "reallocs") >= 6);
    try std.testing.expect(functionCounter(counts, "u1_growth::byte_appends", "buffer_grow_bytes") < 1024);
    // A large list keeps growing with realloc as before.
    try std.testing.expect(functionCounter(counts, "u1_growth::list_growth", "reallocs") >= 4);
    try std.testing.expectEqual(@as(i64, 0), functionCounter(counts, "u1_growth::list_growth", "buffer_grows"));
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

const hoist_expected = "90230 33 2\n865079466 962860009 86651320\n458455359 976384266 554113001 8718774604\n814298128 890434128 128128\n605789002 676242 22549 41868000\n343010 32 598486 343010\n";
const hoist_expected_more = "373724 33 2\n102650968 453315009 88748160\n948059408 36681838 395256001 9223654218\n814298128 175119 128128\n58046002 676242 63229 950607000\n54592 32 317729 54592\n";

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
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "u1_hoist::nested_mut", "count"));
        try std.testing.expectEqual(@as(i64, 0), siteSum(counts, "unique_test", "u1_hoist::nested_mut", "extra"));
        // A list a call returned: one test, which finds it unique, for 20 appends.
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "u1_hoist::from_call", "count"));
        try std.testing.expectEqual(@as(i64, 1), siteSum(counts, "unique_test", "u1_hoist::from_call", "extra"));
        // An alias held until the loop's third iteration: the entering list is still needed,
        // so each of the 20 appends keeps its test.
        try std.testing.expectEqual(@as(i64, 20), siteSum(counts, "unique_test", "u1_hoist::dropped_alias", "count"));
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
        \\    code: list[int]
        \\    ip: int
        \\    base: int
        \\    name: str
        \\    hits: int
        \\
        \\
        \\def run(frame: mut Frame, n: int) -> int:
        \\    total = 0
        \\    while frame.ip < n:
        \\        total = total + frame.code[frame.ip % 4]
        \\        frame.ip = frame.ip + 1
        \\    return total
        \\
        \\
        \\def main(args: list[str], out: Stream) -> int:
        \\    frame = Frame(code=[1, 2, 3, 4], ip=0, base=0, name="f", hits=0)
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
