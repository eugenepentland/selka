//! Ownership and one-count RC (`own.zig`, `runtime/core_rt.c`): copy-on-write
//! forms, counting of lists, strings, records, unions and boxes, early exits, the
//! R-2 peephole, verify-mode uniqueness asserts, saturation, iterative free and the
//! leak check over every `test/core` program.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const print = @import("print.zig");
const driver = @import("driver.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");

const Hand = support.Hand;

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

const forms =
    \\def borrowed(xs: list[int]) -> int:
    \\    ys = xs
    \\    ys.append(1)
    \\    return len(ys) + len(xs)
    \\
    \\
    \\def fresh(n: int) -> int:
    \\    out: list[int] = []
    \\    for i in range(n):
    \\        out.append(i)
    \\    return len(out)
    \\
    \\
    \\def make(n: int) -> list[int]:
    \\    out: list[int] = []
    \\    out.append(n)
    \\    return out
    \\
    \\
    \\def maybe_shared(n: int) -> int:
    \\    a = make(n)
    \\    a.append(2)
    \\    return len(a)
    \\
    \\
    \\def kept(n: int) -> int:
    \\    a = make(n)
    \\    b = a
    \\    b.append(3)
    \\    return len(a) * 10 + len(b)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(borrowed([1]), fresh(3), maybe_shared(1), kept(1))
    \\    return 0
    \\
;

// spec: NEW-CORE-RC-2
test "copy on write: a fresh list updates in place, a call result tests its count, a borrowed or still-used list is copied" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.ownedText(arena.allocator(), forms);
    // Form 3: the parameter is borrowed, so the push appends to a copy.
    try std.testing.expect(contains(functionIr(text, "borrowed"), "list_copy list[i64] param0"));
    // Form 1: built here and dead after each push; no copy, no test, no count traffic.
    const fresh_ir = functionIr(text, "fresh");
    try std.testing.expect(!contains(fresh_ir, "list_copy") and !contains(fresh_ir, "is_unique") and !contains(fresh_ir, "retain"));
    // Form 2: a call result may be shared, so its count decides.
    const maybe_ir = functionIr(text, "maybe_shared");
    try std.testing.expect(contains(maybe_ir, "is_unique") and contains(maybe_ir, "list_copy") and contains(maybe_ir, "release"));
    // Form 3 again: `a` is still read after `b`'s push, so the push copies without a test.
    const kept_ir = functionIr(text, "kept");
    try std.testing.expect(contains(kept_ir, "list_copy") and !contains(kept_ir, "is_unique"));
}

// spec-case: NEW-CORE-RC-2
test "the copy-on-write forms print the old core's values with nothing left live, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var debug_module = try support.buildSource(arena.allocator(), forms, &refusal);
    const debug = try support.runOwned(arena.allocator(), &debug_module, .{});
    try std.testing.expectEqualStrings("3 3 2 12\n", debug.stdout);
    try std.testing.expectEqualStrings("", debug.stderr);
    var release_module = try support.buildSource(arena.allocator(), forms, &refusal);
    const release = try support.runOwned(arena.allocator(), &release_module, .{ .release = true });
    try std.testing.expectEqualStrings("3 3 2 12\n", release.stdout);
    try std.testing.expectEqualStrings("", release.stderr);
}

/// main(out): a record holding a list and a string, a list of such records updated
/// by field, element write and pop, an `Option[list]` (niche), a words-form union
/// with a list case, a box of a list and a list of unions; it prints lengths.
fn valuesProgram(arena: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    const ints = try m.intern(arena, .{ .list = .i64 });
    const holder = try m.intern(arena, .{ .record = &.{ .i64, ints, .str } });
    const holders = try m.intern(arena, .{ .list = holder });
    const maybe = try m.option(arena, ints);
    const either = try m.intern(arena, .{ .@"union" = &.{ .i64, ints } });
    const eithers = try m.intern(arena, .{ .list = either });
    const boxed = try m.intern(arena, .{ .box = ints });
    try m.strings.append(arena, "tag");
    var h = try Hand.init(arena, &m, "main", .{ .params = try arena.dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const out = try h.param(0);
    const one = try h.int(.i64, 1);
    const tag = try h.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    const l2 = try pushed(&h, ints, &.{ 5, 6 });
    const r = try h.emit(.{ .op = .record_make, .ty = holder, .data = try h.extra(&.{ try h.int(.i64, 7), l2, tag }) });
    const g = try h.emit(.{ .op = .record_get, .ty = ints, .a = r, .data = 1 });
    const n1 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = g });
    const hl0 = try h.emit(.{ .op = .list_new, .ty = holders, .a = one });
    const hl1 = try h.emit(.{ .op = .list_push, .ty = holders, .a = hl0, .b = r });
    // A copy of element 0 with its first field and its list replaced, appended.
    const e = try h.emit(.{ .op = .list_get, .ty = holder, .a = hl1, .b = try h.int(.i64, 0), .check = .exact });
    const e2 = try h.emit(.{ .op = .record_set, .ty = holder, .a = e, .b = try h.int(.i64, 99), .data = 0 });
    const inner = try h.emit(.{ .op = .record_get, .ty = ints, .a = e2, .data = 1 });
    const inner2 = try h.emit(.{ .op = .list_push, .ty = ints, .a = inner, .b = try h.int(.i64, 8) });
    const e3 = try h.emit(.{ .op = .record_set, .ty = holder, .a = e2, .b = inner2, .data = 1 });
    const hl2 = try h.emit(.{ .op = .list_push, .ty = holders, .a = hl1, .b = e3 });
    const n2 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = hl2 });
    const f0 = try h.emit(.{ .op = .list_get_field, .ty = ints, .a = hl2, .b = one, .data = ir.FieldPath.init(&.{1}).?.pack(), .check = .exact });
    const n3 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = f0 });
    // Pop the last element: the read before the pop owns it.
    const last = try h.emit(.{ .op = .list_get, .ty = holder, .a = hl2, .b = one, .check = .exact });
    const hl3 = try h.emit(.{ .op = .list_pop, .ty = holders, .a = hl2, .check = .exact });
    const last_list = try h.emit(.{ .op = .record_get, .ty = ints, .a = last, .data = 1 });
    const n4 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = last_list });
    // Replace element 0: the old holder (and its list) is released.
    const fresh = try pushed(&h, ints, &.{1});
    const replacement = try h.emit(.{ .op = .record_make, .ty = holder, .data = try h.extra(&.{ one, fresh, tag }) });
    const hl4 = try h.emit(.{ .op = .list_set, .ty = holders, .a = hl3, .b = try h.int(.i64, 0), .data = try h.extra(&.{replacement}), .check = .exact });
    const f1 = try h.emit(.{ .op = .list_get_field, .ty = ints, .a = hl4, .b = try h.int(.i64, 0), .data = ir.FieldPath.init(&.{1}).?.pack(), .check = .exact });
    const n5 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = f1 });
    // Unions: a niche option and a words-form union, each holding a list.
    const opt = try h.emit(.{ .op = .union_make, .ty = maybe, .data = 1, .a = try pushed(&h, ints, &.{3}) });
    const opt_tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = opt });
    const opt_list = try h.emit(.{ .op = .union_payload, .ty = ints, .a = opt, .data = 1 });
    const n6 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = opt_list });
    const w = try h.emit(.{ .op = .union_make, .ty = either, .data = 1, .a = try pushed(&h, ints, &.{ 4, 4 }) });
    const w_list = try h.emit(.{ .op = .union_payload, .ty = ints, .a = w, .data = 1 });
    const n7 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = w_list });
    const plain = try h.emit(.{ .op = .union_make, .ty = either, .data = 0, .a = try h.int(.i64, 42) });
    // A box of a list, and a list of unions whose integer case holds no block.
    const bx = try h.emit(.{ .op = .box_make, .ty = boxed, .a = try pushed(&h, ints, &.{9}) });
    const bg = try h.emit(.{ .op = .box_get, .ty = ints, .a = bx });
    const n8 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = bg });
    const ul0 = try h.emit(.{ .op = .list_new, .ty = eithers, .a = one });
    const ul1 = try h.emit(.{ .op = .list_push, .ty = eithers, .a = ul0, .b = w });
    const ul2 = try h.emit(.{ .op = .list_push, .ty = eithers, .a = ul1, .b = plain });
    const n9 = try h.emit(.{ .op = .list_len, .ty = .u64, .a = ul2 });
    try h.printValues(out, &.{ n1, n2, n3, n4, n5, n6, n7, n8, n9, opt_tag });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

/// A fresh `list[int]` holding `values`.
fn pushed(h: *Hand, ty: ir.Type, values: []const i64) !ir.Ref {
    var list = try h.emit(.{ .op = .list_new, .ty = ty, .a = try h.int(.i64, 1) });
    for (values) |value| list = try h.emit(.{ .op = .list_push, .ty = ty, .a = list, .b = try h.int(.i64, value) });
    return list;
}

const values_output = "2 2 3 3 1 1 2 1 2 1\n";

// spec: NEW-CORE-RC-3
test "records, unions and boxes with managed parts are counted field by field and freed with their children, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var debug_module = try valuesProgram(arena.allocator());
    const debug = try support.runOwned(arena.allocator(), &debug_module, .{});
    try std.testing.expectEqualStrings(values_output, debug.stdout);
    try std.testing.expectEqualStrings("", debug.stderr);
    var release_module = try valuesProgram(arena.allocator());
    const release = try support.runOwned(arena.allocator(), &release_module, .{ .release = true });
    try std.testing.expectEqualStrings(values_output, release.stdout);
    try std.testing.expectEqualStrings("", release.stderr);
    // The list of records and the list of unions carry element layouts for the runtime.
    try std.testing.expect(contains(release.llvm, "@myl.layout.0 = private constant [7 x i32] [i32 24, i32 2, i32 0, i32 8, i32 0, i32 16, i32 0]"));
    try std.testing.expect(contains(release.llvm, "[i32 16, i32 1, i32 1, i32 8, i32 1, i32 0, i32 1, i32 0]"));
}

// spec-case: NEW-CORE-RC-3
test "without the ownership pass the leak check reports every block left live at exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try valuesProgram(arena.allocator());
    const run = try support.runOwned(arena.allocator(), &module, .{ .own = false });
    try std.testing.expectEqualStrings(values_output, run.stdout);
    try std.testing.expect(contains(run.stderr, "myl-core leakcheck: "));
    try std.testing.expect(contains(run.stderr, " blocks live at exit\n"));
}

// spec: NEW-CORE-RC-4
test "the R-2 peephole drops a retain and release of one value with only pure reads between them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var m: ir.Module = .{};
    const ints = try m.intern(arena.allocator(), .{ .list = .i64 });
    var h = try Hand.init(arena.allocator(), &m, "f", .{ .params = try arena.allocator().dupe(ir.Type, &.{ ints, ints }), .ret = .u64 });
    const p = try h.param(0);
    const q = try h.param(1);
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = p });
    const n = try h.emit(.{ .op = .list_len, .ty = .u64, .a = p });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = p });
    // A call between them keeps the second pair: the callee could drop an owner.
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = q });
    _ = try h.emit(.{ .op = .print, .ty = .void, .data = try h.extra(&.{ try h.int(.cap, 1), n }) });
    _ = try h.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(0), .data = try h.extra(&.{ q, q }) });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = q });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = n });
    _ = try h.finish();
    const dropped = try own.elidePairs(arena.allocator(), &m.functions.items[0]);
    try std.testing.expectEqual(@as(u32, 1), dropped);
    const text = try print.module(arena.allocator(), &m);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "retain"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "release"));
}

// spec: NEW-CORE-RC-5
test "a verify build traps R_CORE_FACT when an update the pass called unique finds a shared list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var m: ir.Module = .{};
    const ints = try m.intern(arena.allocator(), .{ .list = .i64 });
    var h = try Hand.init(arena.allocator(), &m, "main", .{ .params = try arena.allocator().dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const list = try h.emit(.{ .op = .list_new, .ty = ints, .a = try h.int(.i64, 1) });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = list });
    const unique = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = list });
    const ok = try h.newBlock();
    const fail = try h.newBlock();
    try h.branch(unique, ok, fail);
    h.block = fail;
    _ = try h.emit(.{ .op = .@"unreachable", .ty = .void, .data = own.unique_assert });
    h.block = ok;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    const run = try support.runOwned(arena.allocator(), &m, .{ .own = false, .verify = true, .leakcheck = false });
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expect(contains(run.stderr, "error[R_CORE_FACT]: native execution failed (count == 1 before an in-place update"));
}

// spec-case: NEW-CORE-RC-5
test "a verify build asserts each statically unique update and still runs clean" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), forms, &refusal);
    const run = try support.runOwned(arena.allocator(), &module, .{ .release = true, .verify = true });
    try std.testing.expectEqualStrings("3 3 2 12\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expect(contains(run.llvm, "count == 1 before an in-place update"));
}

/// A C program that includes the runtime and checks saturation, copying and an
/// iterative free of a list-of-lists chain a million blocks deep.
const runtime_harness =
    \\#include "core_rt.c"
    \\const myl_core_site myl_core_sites[1];
    \\const char myl_core_source_path[] = "harness";
    \\int main(void) {
    \\    myl_block *head = myl_core_list_new(1, 8);
    \\    head->reserved = (int64_t)(intptr_t)layout_blocks;
    \\    myl_block *tail = head;
    \\    for (int i = 0; i < 1000000; ++i) {
    \\        myl_block *next = myl_core_list_new(1, 8);
    \\        next->reserved = (int64_t)(intptr_t)layout_blocks;
    \\        ((myl_block **)block_data(tail))[0] = next;
    \\        tail->len = 1;
    \\        tail = next;
    \\    }
    \\    myl_block *immortal = myl_core_list_new(0, 8);
    \\    immortal->count = MYL_SATURATED - 1;
    \\    retain_block(immortal);
    \\    retain_block(immortal);
    \\    ((myl_block **)block_data(tail))[0] = immortal;
    \\    tail->len = 1;
    \\    myl_block *copy = myl_core_list_copy(tail, 8);
    \\    int64_t before = live_blocks;
    \\    myl_core_release(head);
    \\    myl_core_release(copy);
    \\    myl_core_release(immortal);
    \\    printf("%lld %lld %u\n", (long long)before, (long long)live_blocks, immortal->count == MYL_SATURATED);
    \\    return 0;
    \\}
    \\
;

// spec: NEW-CORE-RC-6
test "the runtime frees a list-of-lists chain a million deep without recursion, copies retain children, and a saturated count never changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "core_rt.c", .data = driver.runtime_source });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "harness.c", .data = runtime_harness });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    const zig = environment.get("ZIG") orelse "zig";
    const source = try std.fs.path.join(a, &.{ root, "harness.c" });
    const output = try std.fs.path.join(a, &.{ root, "harness" });
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const built = try std.process.run(a, std.testing.io, .{ .argv = &.{ zig, "cc", "-O0", "-std=c11", "-o", output, source }, .environ_map = &environment });
    try std.testing.expectEqualStrings("", built.stderr);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output} });
    // Head, a million links, the immortal block and the copy were live; only the immortal block stays.
    try std.testing.expectEqualStrings("1000003 1 1\n", ran.stdout);
}

/// Build `test/core/NAME.my` with the new core and run it with `MYL_CORE_LEAKCHECK=1`.
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, release: bool, args: []const []const u8) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}", .{ root, name, if (release) "release" else "debug" });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    if (release) try argv.append(arena, "--release");
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    return ran.stderr;
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
};

// spec: NEW-CORE-RC-7
test "every test/core program ends with no block live under MYL_CORE_LEAKCHECK=1, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    for (leak_fixtures) |fixture| {
        try std.testing.expectEqualStrings("", try leakChecked(arena.allocator(), root, fixture.name, false, fixture.args));
        try std.testing.expectEqualStrings("", try leakChecked(arena.allocator(), root, fixture.name, true, fixture.args));
    }
}
