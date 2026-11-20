//! Checked owner lifetimes, stack promotion, and analysis storage lifetime.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const print = @import("print.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const effects = @import("effects.zig");
const facts = @import("facts.zig");
const promotion = @import("promote.zig");

const Hand = support.Hand;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// One emitted function's text, from its `define` to its closing brace.
fn llvmFunction(text: []const u8, name: []const u8) []const u8 {
    const header = std.mem.indexOf(u8, text, "define internal") orelse return "";
    var at = header;
    while (std.mem.indexOfPos(u8, text, at, "define internal")) |start| : (at = start + 1) {
        const line_end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse return "";
        if (std.mem.indexOf(u8, text[start..line_end], name) == null) continue;
        const end = std.mem.indexOfPos(u8, text, start, "\n}\n") orelse return "";
        return text[start..end];
    }
    return "";
}

/// A fresh `list[int]` holding `values`.
fn pushed(h: *Hand, ty: ir.Type, values: []const i64) !ir.Ref {
    var list = try h.emit(.{ .op = .list_new, .ty = ty, .a = try h.int(.i64, 1) });
    for (values) |value| list = try h.emit(.{ .op = .list_push, .ty = ty, .a = list, .b = try h.int(.i64, value) });
    return list;
}

// spec: NEW-CORE-RC-3
test "without the ownership pass the leak check reports every block left live at exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), "func main(out: Stream) -> int:\n    mut values: int[] = []\n    append(mut values, 1)\n    print(out, values)\n    return 0\n", &refusal);
    const run = try support.runOwned(arena.allocator(), &module, .{ .own = false });
    try std.testing.expectEqualStrings("[1]\n", run.stdout);
    try std.testing.expect(contains(run.stderr, "myl-core leakcheck: "));
    try std.testing.expect(contains(run.stderr, " blocks live at exit\n"));
}

/// Small-block reuse and growing lists keep the live allocation count exact.
const allocator_harness =
    \\#include "core_rt.c"
    \\/* Native-only harness: no emitted LLVM unit supplies the task bridge. */
    \\myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
    \\const myl_core_site myl_core_sites[1];
    \\const char myl_core_source_path[] = "harness";
    \\int main(void) {
    \\    myl_block *a = myl_core_list_new_slow(4, 8);
    \\    int64_t cap = a->cap;
    \\    myl_core_drop_owned(a);
    \\    myl_block *b = myl_core_list_new_slow(3, 8);
    \\    int reused = a == b;
    \\    myl_block *big = myl_core_list_new_slow(200, 8);
    \\    big->len = big->cap;
    \\    big = myl_core_list_grow(big, 8);
    \\    int64_t live = live_count(), grown = big->cap;
    \\    myl_core_drop_owned(b);
    \\    myl_core_drop_owned(big);
    \\    printf("%lld %d %lld %lld %lld\n", (long long)cap, reused, grown >= 400 ? 400LL : 0LL, (long long)live, (long long)live_count());
    \\    return 0;
    \\}
    \\
;

/// Compile `source` (a C program including the runtime) with `zig cc` and run it; returns stdout.
fn runHarness(a: std.mem.Allocator, source_text: []const u8) ![]const u8 {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const output = try @import("native_fixture.zig").buildProgram(a, root, .{ .source = source_text, .binary_name = "harness", .source_name = "harness.c", .flags = &.{ "-O0", "-std=c11" } });
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output} });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    return ran.stdout;
}

// spec: NEW-CORE-ALLOC-1
test "the allocator reuses a freed small block for its class, fills small lists to their class and keeps the live count exact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // A 4-element list of i64 is a 64-byte block: 4 elements fit, and 3 reuse it.
    try std.testing.expectEqualStrings("4 1 400 2 0\n", try runHarness(arena.allocator(), allocator_harness));
}

/// The output of one leak-checked run of a `test/core` program.
const Checked = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.selka` with the new core and `flags` (none: a debug build) and run
/// it with `SELKA_CORE_LEAKCHECK=1`.
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Checked {
    const original = try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ options.fixtures, name });
    var source = original;
    if (std.mem.eql(u8, name, "rc_field_take")) {
        const old = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, original, arena, .limited(1 << 20));
        const first = try std.mem.replaceOwned(u8, arena, old, "put(mut rt, -1,", "put(mut rt, len(rt.objects) - 1,");
        const modern = try std.mem.replaceOwned(u8, arena, first, "replace_row(mut shelf, -1,", "replace_row(mut shelf, len(shelf.rows) - 1,");
        source = try std.fmt.allocPrint(arena, "{s}/rc_field_take_wave1.selka", .{root});
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = source, .data = modern });
    }
    const ran = try leakCheckedFile(arena, root, source, flags, args);
    const expected_status: u8 = if (std.mem.eql(u8, name, "control")) 255 else 0;
    try std.testing.expectEqual(expected_status, ran.status);
    try std.testing.expect(ran.stdout.len > 0);
    return ran;
}

/// Keep the original dynamic-negative fixture executable as a retirement witness.
fn leakCheckedFile(arena: std.mem.Allocator, root: []const u8, source: []const u8, flags: []const []const u8, args: []const []const u8) !Checked {
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}", .{ root, std.fs.path.stem(source), if (flags.len == 0) "debug" else flags[flags.len - 1] });
    const cache = try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// Every `test/core` program that runs to its end, with arguments it accepts.
const leak_fixtures = [_]struct { name: []const u8, args: []const []const u8 }{
    .{ .name = "int_math", .args = &.{ "64", "3", "7" } },
    .{ .name = "float_math", .args = &.{ "64", "3", "7" } },
    .{ .name = "call_direct", .args = &.{ "64", "3", "7" } },
    .{ .name = "branch_predictable", .args = &.{ "64", "3", "7" } },
    .{ .name = "branch_mixed", .args = &.{ "64", "3", "7" } },
    .{ .name = "binary_search", .args = &.{ "64", "3", "7" } },
    .{ .name = "compute_s0", .args = &.{ "3", "64", "3", "7" } },
    .{ .name = "control", .args = &.{ "3", "x" } },
    .{ .name = "list_alias", .args = &.{} },
    .{ .name = "rc_lists", .args = &.{ "a", "b" } },
    .{ .name = "rc_stack", .args = &.{ "a", "b", "c", "d" } },
    .{ .name = "rc_mut", .args = &.{ "a", "b" } },
    .{ .name = "rc_shared_loops", .args = &.{} },
    .{ .name = "rc_alias_paths", .args = &.{"x"} },
    .{ .name = "rc_phi_fields", .args = &.{} },
    .{ .name = "rc_promote_order", .args = &.{} },
};

/// Build every `leak_fixtures` program with `flags`, run it under the leak check, and require an empty stderr.
fn leakFixtures(arena: std.mem.Allocator, root: []const u8, flags: []const []const u8) !void {
    try support.requireReleaseArgs(flags);
    for (leak_fixtures) |fixture| {
        try std.testing.expectEqualStrings("", (try leakChecked(arena, root, fixture.name, flags, fixture.args)).stderr);
    }
}

// spec: NEW-CORE-RC-7
test "every test/core program ends with no block live under SELKA_CORE_LEAKCHECK=1, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    try leakFixtures(arena.allocator(), root, &.{});
    try leakFixtures(arena.allocator(), root, &.{"--release"});
}

/// Build `test/core/rc_stack.selka` with `flags`, run it with four arguments under the leak
/// check, and return the build's report and the run.
fn stackRun(arena: std.mem.Allocator, root: []const u8, tag: []const u8, flags: []const []const u8) !struct { report: []const u8, run: std.process.RunResult } {
    try support.requireReleaseArgs(flags);
    const source = try std.fmt.allocPrint(arena, "{s}/rc_stack.selka", .{options.fixtures});
    const output = try std.fmt.allocPrint(arena, "{s}/rc_stack-{s}", .{ root, tag });
    const cache = try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", cache, "--stats" });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{ output, "a", "b", "c", "d" }, .environ_map = &environment });
    return .{ .report = built.stderr, .run = ran };
}

// spec: NEW-CORE-STACK-1
test "lists that never escape and whose length the facts bound live on the stack, with the old core's output and no leak" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const debug = try stackRun(arena.allocator(), root, "unoptimized", &.{"--unoptimized"});
    try std.testing.expect(contains(debug.report, "; 0 lists on the stack\n"));
    try std.testing.expectEqualStrings("475 16 3\n", debug.run.stdout);
    // The comprehension, the emptied list, the two-element literal and the bounded fill
    // loop go on the stack; the list `escapes` returns stays on the heap.
    const release = try stackRun(arena.allocator(), root, "release", &.{"--release"});
    try std.testing.expect(contains(release.report, "; 4 lists on the stack\n"));
    try std.testing.expectEqualStrings("475 16 3\n", release.run.stdout);
    try std.testing.expectEqualStrings("", release.run.stderr);
    const verify = try stackRun(arena.allocator(), root, "verify", &.{ "--release", "--verify-facts", "--emit-llvm", try std.fmt.allocPrint(arena.allocator(), "{s}/verify.ll", .{root}) });
    try std.testing.expectEqualStrings("475 16 3\n", verify.run.stdout);
    const llvm = try dir.dir.readFileAlloc(std.testing.io, "verify.ll", arena.allocator(), .limited(1 << 24));
    try std.testing.expect(contains(llvm, "a stack list's length below its capacity"));
    try std.testing.expect(contains(llvm, "alloca [64 x i8], align 32"));
}

// spec-case: NEW-CORE-STACK-1
test "a wrong length bound behind a stack list is caught by the verify build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    // `seed % 5` taken to lie in [0, 3]: the fill loop's capacity would be 3, not 4.
    const sabotaged = try stackRun(arena.allocator(), root, "sabotage", &.{ "--release", "--sabotage-facts" });
    try std.testing.expectEqual(@as(u8, 1), sabotaged.run.term.exited);
    try std.testing.expect(contains(sabotaged.run.stderr, "error[R_CORE_FACT]"));
}

const stack_borrowing =
    \\func total(xs: int[]) -> int:
    \\    mut answer = 0
    \\    for x in xs:
    \\        answer += x
    \\    return answer
    \\
    \\func forwarded(xs: int[]) -> int:
    \\    return total(xs)
    \\
    \\func both(xs: int[], ys: int[]) -> int:
    \\    return total(xs) + total(ys)
    \\
    \\func borrowed_caller(seed: int) -> int:
    \\    mut xs = [seed, seed + 1, seed + 2]
    \\    return forwarded(xs) + both(xs, xs)
    \\
    \\func looped(seed: int) -> int:
    \\    mut answer = 0
    \\    for i in range(4):
    \\        mut xs = [seed + i, seed]
    \\        answer += forwarded(xs)
    \\    return answer
    \\
    \\func read_then_fill(seed: int) -> int:
    \\    mut xs = [seed]
    \\    mut before = total(xs)
    \\    append(mut xs, seed + 1)
    \\    return before + total(xs)
    \\
    \\func snapshot(seed: int) -> int:
    \\    mut xs = [seed, seed + 1]
    \\    mut before = copy(xs)
    \\    append(mut xs, seed + 2)
    \\    return total(before) * 10 + total(xs)
    \\
    \\func returned(xs: int[]) -> int[]:
    \\    if total(xs) < 0:
    \\        return copy(xs)
    \\    return copy(xs)
    \\
    \\func returned_caller(seed: int) -> int:
    \\    mut xs = [seed, seed + 1]
    \\    return total(returned(xs)) + total(xs)
    \\
    \\func keep_second(read: int[], kept: int[]) -> int[][]:
    \\    return [copy(kept)]
    \\
    \\func stored_caller(seed: int) -> int:
    \\    mut xs = [seed, seed + 1]
    \\    mut nested = keep_second(xs, xs)
    \\    return total(nested[0]) + total(xs)
    \\
    \\func grow(mut xs: int[]):
    \\    append(mut xs, 9)
    \\
    \\func mutated_caller(seed: int) -> int:
    \\    mut xs = [seed]
    \\    grow(mut xs)
    \\    return total(xs)
    \\
    \\func indirect_caller(read: func(int[]) -> int, seed: int) -> int:
    \\    mut xs = [seed]
    \\    return read(xs)
    \\
    \\func joined(flag: bool) -> int:
    \\    mut xs = [1, 2]
    \\    if flag:
    \\        xs = [3, 4]
    \\    return total(xs)
    \\
    \\func strings(xs: str[]) -> int:
    \\    mut answer = 0
    \\    for x in xs:
    \\        answer += strings.char_count(x)
    \\    return answer
    \\
    \\func managed_elements() -> int:
    \\    return strings(["one", "two"])
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, borrowed_caller(3), looped(3), read_then_fill(3), snapshot(3))
    \\    print(out, returned_caller(3), stored_caller(3), mutated_caller(3), indirect_caller(total, 3))
    \\    print(out, joined(False), joined(True), managed_elements())
    \\    return 0
    \\
;

/// Run promotion directly, before inlining can erase a call boundary under test.
fn stackLists(a: std.mem.Allocator, module: *ir.Module, name: []const u8, summaries: ?*const effects.Summaries) !u32 {
    for (module.functions.items) |*function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        const known = try facts.analyze(a, function, .{ .mark = false });
        const promoted = try promotion.promote(a, module, function, &known, .{ .effects = summaries });
        return promoted.lists;
    }
    return error.TestUnexpectedResult;
}

// spec: NEW-CORE-STACK-2
test "stack borrowing promotes loop readers, forwarding and repeated ordinary arguments without inlining" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, stack_borrowing, &refusal);
    const summaries = try effects.analyze(a, &module);
    // Missing proof is conservative, even for a direct call with no mut parameter.
    try std.testing.expectEqual(@as(u32, 0), try stackLists(a, &module, "borrowed_caller", null));
    // One safe occurrence cannot hide the second argument's store. Returned aliases,
    // mut/indirect calls, managed children, general phis and old snapshots still escape.
    const cases = [_]struct { name: []const u8, expected: u32 }{
        .{ .name = "borrowed_caller", .expected = 1 },
        .{ .name = "looped", .expected = 1 },
        .{ .name = "read_then_fill", .expected = 1 },
        .{ .name = "returned_caller", .expected = 0 },
        .{ .name = "stored_caller", .expected = 0 },
        .{ .name = "mutated_caller", .expected = 0 },
        .{ .name = "indirect_caller", .expected = 0 },
        .{ .name = "managed_elements", .expected = 0 },
        .{ .name = "joined", .expected = 0 },
        .{ .name = "snapshot", .expected = 0 },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.expected, try stackLists(a, &module, case.name, &summaries));
    }
}

// spec-case: NEW-CORE-STACK-2
test "stack borrowing preserves snapshots and repeated loop instances in debug release and verify builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    const modes = [_]?@import("passes.zig").Mode{ null, .trusted, .verify };
    for (modes) |mode| {
        var module = try support.buildSource(a, stack_borrowing, &refusal);
        const run = if (mode) |selected| blk: {
            const result = try support.runPasses(a, &module, selected);
            const checked = try support.runOwned(a, &module, .{ .release = true, .verify = selected == .verify, .own = false, .analysis = support.analysis(&result) });
            const caller = llvmFunction(checked.llvm, "@\"my.borrowed_caller\"(");
            try std.testing.expect(contains(caller, "alloca [56 x i8], align 32"));
            try std.testing.expect(!contains(caller, "@myl_core_list_new("));
            break :blk checked;
        } else try support.runOwned(a, &module, .{});
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("36 30 10 82\n14 14 12 3\n3 7 6\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
    }
}

const stack_borrow_trap =
    \\func last(xs: int[], index: int) -> int:
    \\    mut answer = 0
    \\    for x in xs:
    \\        answer += x
    \\    return answer + xs[index]
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, 17)
    \\    mut xs = [1, 2]
    \\    return last(xs, 2)
    \\
;

// spec-case: NEW-CORE-STACK-2
test "stack borrowing keeps a helper bounds trap after earlier output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, stack_borrow_trap, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    const run = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .leakcheck = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("17\n", run.stdout);
    try std.testing.expect(contains(run.stderr, "error[R_LIST_BOUNDS]"));
    try std.testing.expect(contains(llvmFunction(run.llvm, "@\"my.main\"("), "alloca [48 x i8], align 32"));
}

/// Independent read-only list constructions in one frame; capacities are counts
/// of actual pushes, not untrusted `list_new` reserve requests.
fn stackBudgetFunction(a: std.mem.Allocator, module: *ir.Module, name: []const u8, element: ir.Type, capacities: []const u32) !void {
    const list = try module.intern(a, .{ .list = element });
    var h = try Hand.init(a, module, name, .{ .params = &.{}, .ret = .u64 });
    const zero = try h.int(.u64, 0);
    const one = try h.int(element, 1);
    var total = zero;
    for (capacities) |capacity| {
        var value = try h.emit(.{ .op = .list_new, .ty = list, .a = zero });
        for (0..capacity) |_| value = try h.emit(.{ .op = .list_push, .ty = list, .a = value, .b = one });
        const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = value });
        total = try h.emit(.{ .op = .add, .ty = .u64, .a = total, .b = length });
    }
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = total });
    _ = try h.finish();
}

// spec: NEW-CORE-STACK-3
test "stack budget counts headers alignment and all constructions separately in each function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // 508 i64s plus the header fill 4096 bytes: exactly two fit; even an
    // empty list's header no longer fits. A later function gets a fresh budget.
    try stackBudgetFunction(a, &module, "exact", .i64, &.{ 508, 508, 0 });
    try stackBudgetFunction(a, &module, "reset", .i64, &.{ 508, 508 });
    // The original element limit stays: 513 i64s do not qualify. One 512-list
    // does, but its header prevents another from fitting within the frame budget.
    try stackBudgetFunction(a, &module, "large", .i64, &.{ 513, 512, 512 });
    // One byte and a header round up to 64 bytes each, including padding.
    const small: [129]u32 = @splat(1);
    try stackBudgetFunction(a, &module, "aligned", .i8, &small);
    try std.testing.expectEqual(@as(u32, 2), try stackLists(a, &module, "exact", null));
    try std.testing.expectEqual(@as(u32, 2), try stackLists(a, &module, "reset", null));
    try std.testing.expectEqual(@as(u32, 1), try stackLists(a, &module, "large", null));
    try std.testing.expectEqual(@as(u32, 128), try stackLists(a, &module, "aligned", null));
}

// spec: NEW-CORE-MUT-OWN-1
test "mut appends, mut records and aliases match the old core, linear and leak-free, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    // 400,000 appends through `mut` each way: a copy per append would take minutes.
    const args = [_][]const u8{ "a", "b", "c", "d" };
    for ([_]bool{ false, true }) |release| {
        if (release) try support.requireRelease();
        const source = try std.fmt.allocPrint(arena.allocator(), "{s}/rc_mut.selka", .{options.fixtures});
        const output = try std.fmt.allocPrint(arena.allocator(), "{s}/rc_mut-{}", .{ root, release });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena.allocator(), &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", try options.suiteCache(arena.allocator(), @src()) });
        if (release) try argv.append(arena.allocator(), "--release");
        const built = try std.process.run(arena.allocator(), std.testing.io, .{ .argv = argv.items });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        var environment = try std.testing.environ.createMap(arena.allocator());
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        var run_argv: std.ArrayList([]const u8) = .empty;
        try run_argv.append(arena.allocator(), output);
        try run_argv.appendSlice(arena.allocator(), &args);
        const ran = try std.process.run(arena.allocator(), std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
        // `b = a; add(mut a, 3)` leaves `b` at two elements; `other = bag` keeps five items.
        try std.testing.expectEqualStrings("2400003 32 75\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

/// main(out): `p = phi [undef, entry], [next, latch]` of `list[int]` in a loop that runs
/// `n` times (0 here), reading `p` only after the first iteration: on the zero-trip path
/// the phi holds `undef` when it dies on the exit edge.
fn undefLoopProgram(arena: std.mem.Allocator, record_shaped: bool) !ir.Module {
    var m: ir.Module = .{};
    const ints = try m.intern(arena, .{ .list = .i64 });
    const holder = try m.intern(arena, .{ .record = &.{ .i64, ints, ints, ints, ints } });
    const ty = if (record_shaped) holder else ints;
    var h = try Hand.init(arena, &m, "main", .{ .params = try arena.dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const out = try h.param(0);
    const header = try h.newBlock();
    const body = try h.newBlock();
    const read = try h.newBlock();
    const latch = try h.newBlock();
    const exit = try h.newBlock();
    const undef = try h.loose(.{ .op = .undef, .ty = ty });
    try h.jump(header);
    // header: i = phi(0, i + 1); p = phi(undef, next); i < 0?
    h.block = header;
    const i = try h.loose(.{ .op = .phi, .ty = .i64 });
    const p = try h.loose(.{ .op = .phi, .ty = ty });
    try h.function.blocks.items[header.index()].insts.appendSlice(arena, &.{ i, p });
    const more = try h.emit(.{ .op = .cmp, .ty = .bool, .a = i, .b = try h.int(.i64, 0), .data = @backingInt(ir.Predicate.lt) });
    try h.branch(more, body, exit);
    // body: if i > 0: read len(p)
    h.block = body;
    const later = try h.emit(.{ .op = .cmp, .ty = .bool, .a = i, .b = try h.int(.i64, 0), .data = @backingInt(ir.Predicate.gt) });
    try h.branch(later, read, latch);
    h.block = read;
    const list = if (record_shaped) try h.emit(.{ .op = .record_get, .ty = ints, .a = p, .data = 1 }) else p;
    const n = try h.emit(.{ .op = .list_len, .ty = .u64, .a = list });
    try h.printValues(out, &.{n});
    try h.jump(latch);
    // latch: next = a fresh value; i + 1
    h.block = latch;
    const fresh = try pushed(&h, ints, &.{ 1, 2 });
    const next = if (record_shaped) try h.emit(.{ .op = .record_make, .ty = holder, .data = try h.extra(&.{ try h.int(.i64, 1), fresh, try pushed(&h, ints, &.{3}), try pushed(&h, ints, &.{4}), try pushed(&h, ints, &.{5}) }) }) else fresh;
    const step = try h.emit(.{ .op = .add, .ty = .i64, .a = i, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(header);
    h.function.insts.items[i.index()].data = try h.extra(&.{ try h.int(.i64, 0), step });
    h.function.insts.items[p.index()].data = try h.extra(&.{ undef, next });
    h.block = exit;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

// spec: NEW-CORE-RC-11
test "a phi that may hold undef is released only when it holds a block: a zero-trip loop does not crash, list and record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_]bool{ false, true }) |release| {
        for ([_]bool{ false, true }) |record_shaped| {
            var module = try undefLoopProgram(arena.allocator(), record_shaped);
            const run = try support.runOwned(arena.allocator(), &module, .{ .release = release });
            try std.testing.expectEqual(@as(u8, 0), run.status);
            try std.testing.expectEqualStrings("", run.stderr);
        }
    }
}

/// Swap a populated record and undef through two memory phis on one loop iteration.
/// Both incoming values must be staged before either phi's slot is overwritten.
fn swappedUndefRecords(arena: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    const ints = try module.intern(arena, .{ .list = .i64 });
    const holder = try module.intern(arena, .{ .record = &.{ .i64, ints, ints, ints, ints } });
    var h = try Hand.init(arena, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const out = try h.param(0);
    const header = try h.newBlock();
    const latch = try h.newBlock();
    const exit = try h.newBlock();
    const undef = try h.loose(.{ .op = .undef, .ty = holder });
    var fields: [5]ir.Ref = undefined;
    fields[0] = try h.int(.i64, 7);
    for (fields[1..], 1..) |*field, i| field.* = try pushed(&h, ints, &.{@intCast(i)});
    const initial = try h.emit(.{ .op = .record_make, .ty = holder, .data = try h.extra(&fields) });
    try h.jump(header);
    h.block = header;
    const i = try h.loose(.{ .op = .phi, .ty = .i64 });
    const first = try h.loose(.{ .op = .phi, .ty = holder });
    const second = try h.loose(.{ .op = .phi, .ty = holder });
    try h.function.blocks.items[header.index()].insts.appendSlice(arena, &.{ i, first, second });
    const more = try h.emit(.{ .op = .cmp, .ty = .bool, .a = i, .b = try h.int(.i64, 1), .data = @backingInt(ir.Predicate.lt) });
    try h.branch(more, latch, exit);
    h.block = latch;
    const step = try h.emit(.{ .op = .add, .ty = .i64, .a = i, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(header);
    h.function.insts.items[i.index()].data = try h.extra(&.{ try h.int(.i64, 0), step });
    h.function.insts.items[first.index()].data = try h.extra(&.{ undef, second });
    h.function.insts.items[second.index()].data = try h.extra(&.{ initial, first });
    h.block = exit;
    const value = try h.emit(.{ .op = .record_get, .ty = .i64, .a = first, .data = 0 });
    try h.printValues(out, &.{value});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return module;
}

// spec-case: NEW-CORE-RC-11
test "managed undef memory phis remain empty while parallel incoming records swap, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_]bool{ false, true }) |release| {
        var module = try swappedUndefRecords(arena.allocator());
        const run = try support.runOwned(arena.allocator(), &module, .{ .release = release });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("7\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(contains(run.llvm, "@myl.zeros = private constant [40 x i8] zeroinitializer"));
    }
}

// spec: NEW-CORE-RC-12
test "a record phi read only through its fields still takes its operands, so unswitched loop exits release nothing twice" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source = try std.fmt.allocPrint(arena, "{s}/rc_phi_fields.selka", .{options.fixtures});
    const output = try std.fmt.allocPrint(arena, "{s}/rc_phi_fields-release", .{root});
    const cache = try options.suiteCache(arena, @src());
    try support.requireRelease();
    const built = try std.process.run(arena, std.testing.io, .{ .argv = &.{ options.corePath(), "build", source, "-o", output, "--release", "--link", options.clock_path, "--cache-dir", cache } });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("48 1 1\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec: NEW-CORE-RC-2
test "ownership IR survives reclaiming and overwriting every function's analysis storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var backing = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer backing.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var expected_module = try support.buildSource(a, stack_borrowing, &refusal);
    var actual_module = try support.buildSource(a, stack_borrowing, &refusal);
    const expected_stats = try own.run(a, &expected_module, .{ .verify = true });
    const actual_stats = try own.runWithScratch(a, backing.allocator(), &actual_module, .{ .verify = true });
    // The backing arena preserves freed pages until this reset, allowing a
    // deterministic overwrite of scratch graphs, marks and destruction actions.
    _ = backing.reset(.retain_capacity);
    @memset(try backing.allocator().alloc(u8, 4 * 1024 * 1024), 0xa5);
    try std.testing.expectEqualDeep(expected_stats, actual_stats);
    var failure: @import("verify_ir.zig").Failure = .{};
    try @import("verify_ir.zig").verifyModule(a, &actual_module, &failure);
    try std.testing.expectEqualStrings(try print.module(a, &expected_module), try print.module(a, &actual_module));
}

/// FX6: a dictionary of a borrowed type (here a `from` result) reaches each of the entry pair's ordinal lookups through
/// its own `borrow` overlay. The pass must still see one entry and build a borrowed `DictItem`, or it destroys each key
/// at the end of its iteration while the dictionary still holds it; the strings allocated between the loops then reuse
/// the freed keys' blocks, and the dictionary's own destruction frees them again.
const borrowed_items_source =
    \\import dicts
    \\
    \\record Holder:
    \\    fields: dict[str, int]
    \\
    \\func get(value: Holder) -> dict[str, int] from value:
    \\    return value.fields
    \\
    \\func main(out: Stream) -> int:
    \\    mut fields: dict[str, int] = {}
    \\    fields["key-" + str(7)] = 1
    \\    fields["key-" + str(8)] = 2
    \\    const h = Holder(fields=own fields)
    \\    for entry in dicts.items(get(h)):
    \\        print(out, entry.key, entry.value)
    \\    mut junk: str[] = []
    \\    for n in range(4):
    \\        append(mut junk, "junk-" + str(n))
    \\    for entry in dicts.items(get(h)):
    \\        print(out, entry.key)
    \\    print(out, len(junk))
    \\    return 0
    \\
;

test "items of a dictionary lent through borrow overlays are one borrowed entry: no key is destroyed and none leaks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), borrowed_items_source, &refusal);
    const run = try support.runOwned(arena.allocator(), &module, .{});
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("key-7 1\nkey-8 2\nkey-7\nkey-8\n4\n", run.stdout);
    try std.testing.expect(!contains(run.stderr, "myl-core leakcheck: "));
    // The lowering reads the dictionary through two overlays, the shape the pass has to see through.
    const owned = try support.ownedText(arena.allocator(), borrowed_items_source);
    try std.testing.expect(contains(owned, "= borrow dict[str, i64] "));
}
