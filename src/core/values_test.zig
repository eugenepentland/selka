//! S1 step 0: compound types and the value, list, box, RC and trace operations,
//! each built by hand as Core IR, verified, emitted, compiled with `zig cc` and run.
const std = @import("std");
const ir = @import("ir.zig");
const print = @import("print.zig");
const support = @import("test_support.zig");

const Hand = support.Hand;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// `record{i64, bool, i32}`: 16 bytes, the bool at 8 and the i32 at 12.
fn smallRecord(module: *ir.Module, arena: std.mem.Allocator) !ir.Type {
    return module.intern(arena, .{ .record = &.{ .i64, .bool, .i32 } });
}

// spec: NEW-CORE-IR-4
test "compound types have C layout, word counts, a union form and a managed bit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const small = try smallRecord(&m, a);
    try std.testing.expectEqual(small, try smallRecord(&m, a));
    try std.testing.expectEqual(@as(u32, 16), m.size(small));
    try std.testing.expectEqual(@as(u32, 8), m.fieldOffset(small, 1));
    try std.testing.expectEqual(@as(u32, 12), m.fieldOffset(small, 2));
    const nested = try m.intern(a, .{ .record = &.{ .i64, small } });
    try std.testing.expectEqual(@as(u32, 24), m.size(nested));
    try std.testing.expect(!m.passedInMemory(nested));
    const big = try m.intern(a, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64 } });
    try std.testing.expect(m.passedInMemory(big));
    const boxed = try m.intern(a, .{ .box = .i64 });
    const option_box = try m.option(a, boxed);
    try std.testing.expectEqual(ir.UnionForm.niche, m.unionLayout(option_box).form);
    try std.testing.expectEqual(@as(u32, 8), m.size(option_box));
    try std.testing.expectEqual(ir.UnionForm.scalar, m.unionLayout(try m.option(a, .bool)).form);
    const result = try m.intern(a, .{ .@"union" = &.{ .i64, small, .void } });
    try std.testing.expectEqual(ir.UnionForm.words, m.unionLayout(result).form);
    try std.testing.expectEqual(@as(u32, 24), m.size(result));
    const list = try m.intern(a, .{ .list = .i64 });
    try std.testing.expect(m.managed(list) and m.managed(option_box) and !m.managed(small) and !m.managed(result));
    try std.testing.expect(m.managed(try m.intern(a, .{ .record = &.{ .i64, list } })));
    // A path into a union reads its tag (step 0) or a case's payload (step k + 1).
    const path = ir.FieldPath.init(&.{ 2, 1 }).?;
    try std.testing.expectEqual(path, ir.FieldPath.unpack(path.pack()));
    const field = m.pathTarget(result, path).?;
    try std.testing.expectEqual(ir.Type.bool, field.ty);
    try std.testing.expectEqual(@as(u32, 16), field.offset);
    try std.testing.expectEqual(result, m.pathTarget(result, ir.FieldPath.init(&.{0}).?).?.tag_of);
    try std.testing.expect(m.pathTarget(result, ir.FieldPath.init(&.{3}).?) == null);
}

/// main(out): records in registers and in a list, a nested path, and a record over
/// four words through a call.
fn recordsProgram(arena: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    const small = try smallRecord(&m, arena);
    const nested = try m.intern(arena, .{ .record = &.{ .i64, small } });
    const big = try m.intern(arena, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64, .i64 } });
    const list = try m.intern(arena, .{ .list = small });
    const nested_list = try m.intern(arena, .{ .list = nested });
    // grow(p: big) -> big: field 5 becomes field 0 + field 5.
    m.entry = 1;
    var grow = try Hand.init(arena, &m, "grow", .{ .params = try arena.dupe(ir.Type, &.{big}), .ret = big });
    const p = try grow.param(0);
    const first = try grow.emit(.{ .op = .record_get, .ty = .i64, .a = p, .data = 0 });
    const last = try grow.emit(.{ .op = .record_get, .ty = .i64, .a = p, .data = 5 });
    const total = try grow.emit(.{ .op = .add, .ty = .i64, .a = first, .b = last, .check = .exact });
    const grown = try grow.emit(.{ .op = .record_set, .ty = big, .a = p, .b = total, .data = 5 });
    _ = try grow.emit(.{ .op = .ret, .ty = .void, .a = grown });
    _ = try grow.finish();

    var h = try Hand.init(arena, &m, "main", .{ .params = try arena.dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const out = try h.param(0);
    const r0 = try h.emit(.{ .op = .record_make, .ty = small, .data = try h.extra(&.{ try h.int(.i64, 7), try h.int(.bool, 1), try h.int(.i32, 5) }) });
    const a0 = try h.emit(.{ .op = .record_get, .ty = .i64, .a = r0, .data = 0 });
    const r1 = try h.emit(.{ .op = .record_set, .ty = small, .a = r0, .b = try h.int(.i32, 9), .data = 2 });
    const c1 = try h.emit(.{ .op = .record_get, .ty = .i32, .a = r1, .data = 2 });
    const l0 = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.i64, 1) });
    const l1 = try h.emit(.{ .op = .list_push, .ty = list, .a = l0, .b = r0 });
    const l2 = try h.emit(.{ .op = .list_push, .ty = list, .a = l1, .b = r1 });
    const f = try h.emit(.{ .op = .list_get_field, .ty = .i32, .a = l2, .b = try h.int(.i64, 1), .data = ir.FieldPath.init(&.{2}).?.pack(), .check = .exact });
    const g = try h.emit(.{ .op = .list_get_field, .ty = .bool, .a = l2, .b = try h.int(.i64, 0), .data = ir.FieldPath.init(&.{1}).?.pack(), .check = .exact });
    const e = try h.emit(.{ .op = .list_get, .ty = small, .a = l2, .b = try h.int(.i64, 1), .check = .exact });
    const e0 = try h.emit(.{ .op = .record_get, .ty = .i64, .a = e, .data = 0 });
    const replacement = try h.emit(.{ .op = .record_make, .ty = small, .data = try h.extra(&.{ try h.int(.i64, 11), try h.int(.bool, 0), try h.int(.i32, 3) }) });
    const l3 = try h.emit(.{ .op = .list_set, .ty = list, .a = l2, .b = try h.int(.i64, 0), .data = try h.extra(&.{replacement}), .check = .exact });
    const k = try h.emit(.{ .op = .list_get_field, .ty = .i64, .a = l3, .b = try h.int(.i64, 0), .data = ir.FieldPath.init(&.{0}).?.pack(), .check = .exact });
    const l4 = try h.emit(.{ .op = .list_pop, .ty = list, .a = l3, .check = .exact });
    const n = try h.emit(.{ .op = .list_len, .ty = .u64, .a = l4 });
    try h.printValues(out, &.{ a0, c1, f, g, e0, k, n });
    // A nested record element: field 1 is `small`, whose field 2 sits at byte 20.
    const inner = try h.emit(.{ .op = .record_make, .ty = small, .data = try h.extra(&.{ try h.int(.i64, 1), try h.int(.bool, 0), try h.int(.i32, 21) }) });
    const outer = try h.emit(.{ .op = .record_make, .ty = nested, .data = try h.extra(&.{ try h.int(.i64, 2), inner }) });
    const nl0 = try h.emit(.{ .op = .list_new, .ty = nested_list, .a = try h.int(.i64, 1) });
    const nl1 = try h.emit(.{ .op = .list_push, .ty = nested_list, .a = nl0, .b = outer });
    const deep = try h.emit(.{ .op = .list_get_field, .ty = .i32, .a = nl1, .b = try h.int(.i64, 0), .data = ir.FieldPath.init(&.{ 1, 2 }).?.pack(), .check = .exact });
    const wide = try h.emit(.{ .op = .record_make, .ty = big, .data = try h.extra(&.{ try h.int(.i64, 1), try h.int(.i64, 2), try h.int(.i64, 3), try h.int(.i64, 4), try h.int(.i64, 5), try h.int(.i64, 6) }) });
    const widened = try h.emit(.{ .op = .call, .ty = big, .a = @fromBackingInt(0), .data = try h.extra(&.{wide}) });
    const sixth = try h.emit(.{ .op = .record_get, .ty = .i64, .a = widened, .data = 5 });
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.origin) });
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.append) });
    try h.printValues(out, &.{ deep, sixth });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

const records_output = "7 9 9 True 7 11 1\n21 7\n";

// spec: NEW-CORE-RECORD-1
test "records: make, get and set in registers, inline list elements read by field path, and an sret call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try recordsProgram(arena.allocator());
    const run = try support.runModule(arena.allocator(), &module, false);
    try std.testing.expectEqualStrings(records_output, run.stdout);
    try std.testing.expectEqual(@as(u8, 0), run.status);
    // Small records are struct values; the six-word one crosses the call in memory.
    try std.testing.expect(contains(run.llvm, "insertvalue { i64, i1, i32 }"));
    try std.testing.expect(contains(run.llvm, "extractvalue { i64, i1, i32 }"));
    try std.testing.expect(contains(run.llvm, "define internal void @\"my.grow\"(ptr noalias sret([48 x i8]) align 8 %ret, ptr noalias readonly align 8 %p0)"));
    // The nested field is one GEP at its offset from the element slot, stride 24.
    try std.testing.expect(contains(run.llvm, "getelementptr inbounds [24 x i8]"));
    try std.testing.expect(contains(run.llvm, ", i64 20\n"));
    try std.testing.expect(contains(run.llvm, "call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(i32 "));
}

// spec-case: NEW-CORE-RECORD-1
test "records at -O3: the same output, with the TBAA scaffold accepted by LLVM" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try recordsProgram(arena.allocator());
    const run = try support.runModule(arena.allocator(), &module, true);
    try std.testing.expectEqualStrings(records_output, run.stdout);
    try std.testing.expect(contains(run.llvm, "!7 = !{!6, !6, i64 0}"));
}

/// main(out): the three union forms, in registers and as list elements.
fn unionsProgram(arena: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    try m.strings.append(arena, "hi");
    const pair = try m.intern(arena, .{ .record = &.{ .i64, .i64 } });
    const result = try m.intern(arena, .{ .@"union" = &.{ .i64, pair, .void } });
    const results = try m.intern(arena, .{ .list = result });
    const maybe_bool = try m.option(arena, .bool);
    const maybe_str = try m.option(arena, .str);
    const strs = try m.intern(arena, .{ .list = maybe_str });
    var h = try Hand.init(arena, &m, "main", .{ .params = try arena.dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const out = try h.param(0);
    const case0 = try h.emit(.{ .op = .union_make, .ty = result, .a = try h.int(.i64, 42), .data = 0 });
    const made = try h.emit(.{ .op = .record_make, .ty = pair, .data = try h.extra(&.{ try h.int(.i64, 3), try h.int(.i64, 4) }) });
    const case1 = try h.emit(.{ .op = .union_make, .ty = result, .a = made, .data = 1 });
    const case2 = try h.emit(.{ .op = .union_make, .ty = result, .data = 2 });
    const t1 = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = case1 });
    const p1 = try h.emit(.{ .op = .union_payload, .ty = pair, .a = case1, .data = 1 });
    const s1 = try h.emit(.{ .op = .record_get, .ty = .i64, .a = p1, .data = 1 });
    const p0 = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = case0, .data = 0 });
    var list = try h.emit(.{ .op = .list_new, .ty = results, .a = try h.int(.i64, 0) });
    list = try h.emit(.{ .op = .list_push, .ty = results, .a = list, .b = case0 });
    list = try h.emit(.{ .op = .list_push, .ty = results, .a = list, .b = case1 });
    list = try h.emit(.{ .op = .list_push, .ty = results, .a = list, .b = case2 });
    const tag = try h.emit(.{ .op = .list_get_field, .ty = .u32, .a = list, .b = try h.int(.i64, 2), .data = ir.FieldPath.init(&.{0}).?.pack(), .check = .exact });
    const field = try h.emit(.{ .op = .list_get_field, .ty = .i64, .a = list, .b = try h.int(.i64, 1), .data = ir.FieldPath.init(&.{ 2, 0 }).?.pack(), .check = .exact });
    const whole = try h.emit(.{ .op = .list_get, .ty = result, .a = list, .b = try h.int(.i64, 0), .check = .exact });
    const loaded = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = whole, .data = 0 });
    try h.printValues(out, &.{ t1, s1, p0, tag, field, loaded });
    const o = try h.emit(.{ .op = .union_make, .ty = maybe_bool, .a = try h.int(.bool, 1), .data = 1 });
    const ot = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = o });
    const op = try h.emit(.{ .op = .union_payload, .ty = .bool, .a = o, .data = 1 });
    const n0 = try h.emit(.{ .op = .union_make, .ty = maybe_str, .data = 0 });
    const n1 = try h.emit(.{ .op = .union_make, .ty = maybe_str, .a = try h.loose(.{ .op = .str_const, .ty = .str, .data = 0 }), .data = 1 });
    const nt0 = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = n0 });
    const nt1 = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = n1 });
    const np = try h.emit(.{ .op = .union_payload, .ty = .str, .a = n1, .data = 1 });
    var names = try h.emit(.{ .op = .list_new, .ty = strs, .a = try h.int(.i64, 2) });
    names = try h.emit(.{ .op = .list_push, .ty = strs, .a = names, .b = n0 });
    names = try h.emit(.{ .op = .list_push, .ty = strs, .a = names, .b = n1 });
    const absent = try h.emit(.{ .op = .list_get_field, .ty = .u32, .a = names, .b = try h.int(.i64, 0), .data = ir.FieldPath.init(&.{0}).?.pack(), .check = .exact });
    const present = try h.emit(.{ .op = .list_get_field, .ty = .str, .a = names, .b = try h.int(.i64, 1), .data = ir.FieldPath.init(&.{2}).?.pack(), .check = .exact });
    try h.printValues(out, &.{ ot, op, nt0, nt1, np, absent, present });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

// spec: NEW-CORE-UNION-1
test "unions: tag and payload words in registers, a tag word in memory, and the null niche of Option[str]" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try unionsProgram(arena.allocator());
    const run = try support.runModule(arena.allocator(), &module, false);
    try std.testing.expectEqualStrings("1 4 42 2 3 42\n1 True 0 1 hi 0 hi\n", run.stdout);
    try std.testing.expect(contains(run.llvm, "insertvalue { i8, [2 x i64] }"));
    try std.testing.expect(contains(run.llvm, "insertvalue { i8, i1 }"));
    try std.testing.expect(contains(run.llvm, "icmp ne ptr"));
}

/// main(out): box contents, counts seen through `is_unique`, and releases through
/// a list write, a record, a niche option and a words union.
fn countsProgram(arena: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    try m.strings.append(arena, "x");
    const boxed = try m.intern(arena, .{ .box = .i64 });
    const boxes = try m.intern(arena, .{ .list = boxed });
    const holder = try m.intern(arena, .{ .record = &.{ boxed, .i64 } });
    const maybe = try m.option(arena, boxed);
    const either = try m.intern(arena, .{ .@"union" = &.{ .i64, boxed } });
    var h = try Hand.init(arena, &m, "main", .{ .params = try arena.dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const out = try h.param(0);
    const b = try h.emit(.{ .op = .box_make, .ty = boxed, .a = try h.int(.i64, 5) });
    const v = try h.emit(.{ .op = .box_get, .ty = .i64, .a = b });
    const fresh = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = b });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = b });
    const shared = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = b });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = b });
    const again = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = b });
    // The list takes an owner of `b`; writing over it releases that owner.
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = b });
    var list = try h.emit(.{ .op = .list_new, .ty = boxes, .a = try h.int(.i64, 1) });
    list = try h.emit(.{ .op = .list_push, .ty = boxes, .a = list, .b = b });
    const c = try h.emit(.{ .op = .box_make, .ty = boxed, .a = try h.int(.i64, 9) });
    list = try h.emit(.{ .op = .list_set, .ty = boxes, .a = list, .b = try h.int(.i64, 0), .data = try h.extra(&.{c}), .check = .exact });
    const dropped = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = b });
    const element = try h.emit(.{ .op = .list_get, .ty = boxed, .a = list, .b = try h.int(.i64, 0), .check = .exact });
    const w = try h.emit(.{ .op = .box_get, .ty = .i64, .a = element });
    // A string constant is saturated: never unique, and counting it writes nothing.
    const s = try h.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    const immortal = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = s });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = s });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = s });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = b });
    try h.printValues(out, &.{ v, fresh, shared, again, dropped, w, immortal });
    // Counting a record, a niche option and a words union reaches `c` through each.
    const r = try h.emit(.{ .op = .record_make, .ty = holder, .data = try h.extra(&.{ c, try h.int(.i64, 1) }) });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = r });
    const by_record = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = c });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = r });
    const some = try h.emit(.{ .op = .union_make, .ty = maybe, .a = c, .data = 1 });
    const none = try h.emit(.{ .op = .union_make, .ty = maybe, .data = 0 });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = some });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = none });
    const by_option = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = c });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = some });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = none });
    // Tag 0 carries an integer in the payload word: counting it must not touch it.
    const number = try h.emit(.{ .op = .union_make, .ty = either, .a = try h.int(.i64, 77), .data = 0 });
    const pointer = try h.emit(.{ .op = .union_make, .ty = either, .a = c, .data = 1 });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = number });
    _ = try h.emit(.{ .op = .retain, .ty = .void, .a = pointer });
    const by_union = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = c });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = pointer });
    _ = try h.emit(.{ .op = .release, .ty = .void, .a = number });
    const back = try h.emit(.{ .op = .is_unique, .ty = .bool, .a = c });
    try h.printValues(out, &.{ by_record, by_option, by_union, back });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

const counts_output = "5 True False True True 9 False\nFalse False False True\n";

// spec: NEW-CORE-RC-1
test "retain, release and is_unique count inline, saturate, and reach blocks inside records and unions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try countsProgram(arena.allocator());
    const run = try support.runModule(arena.allocator(), &module, false);
    try std.testing.expectEqualStrings(counts_output, run.stdout);
    try std.testing.expect(contains(run.llvm, " = load i32, ptr %v2, align 8, !tbaa !3, !range !8"));
    try std.testing.expect(contains(run.llvm, "icmp eq i32 %rc"));
    try std.testing.expect(contains(run.llvm, "add nuw i32"));
    try std.testing.expect(contains(run.llvm, "call void @myl_core_free(ptr "));
    try std.testing.expect(contains(run.llvm, "declare void @myl_core_free_block(ptr) nounwind cold"));
    try std.testing.expect(contains(run.llvm, "call ptr @myl_core_box_new(i64 8)"));
}

// spec-case: NEW-CORE-RC-1
test "the counting program at -O3 prints the same" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try countsProgram(arena.allocator());
    const run = try support.runModule(arena.allocator(), &module, true);
    try std.testing.expectEqualStrings(counts_output, run.stdout);
}

/// main(out): one list write or pop that fails its check.
fn trapProgram(arena: std.mem.Allocator, op: ir.Op) !ir.Module {
    var m: ir.Module = .{};
    const ints = try m.intern(arena, .{ .list = .i64 });
    var h = try Hand.init(arena, &m, "main", .{ .params = try arena.dupe(ir.Type, &.{.cap}), .ret = .i64 });
    const out = try h.param(0);
    var list = try h.emit(.{ .op = .list_new, .ty = ints, .a = try h.int(.i64, 1) });
    try h.printValues(out, &.{try h.int(.i64, 1)});
    const value = try h.int(.i64, 5);
    list = try h.emit(.{ .op = op, .ty = ints, .a = list, .b = if (op == .list_set) try h.int(.i64, 3) else .none, .data = if (op == .list_set) try h.extra(&.{value}) else 0, .check = .exact, .span = 4 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

// spec: NEW-CORE-LIST-1
test "a list write out of range traps R_LIST_BOUNDS with the index and length after flushing stdout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try trapProgram(arena.allocator(), .list_set);
    const run = try support.runModule(arena.allocator(), &module, false);
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("1\n", run.stdout);
    try std.testing.expect(contains(run.stderr, "error[R_LIST_BOUNDS]: native execution failed (index 3, length 0)"));
    try std.testing.expect(contains(run.stderr, "\"operation\":\"index\",\"index\":3,\"length\":0"));
}

// spec-case: NEW-CORE-LIST-1
test "a pop of an empty list traps R_LIST_BOUNDS with the old core's pop detail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try trapProgram(arena.allocator(), .list_pop);
    const run = try support.runModule(arena.allocator(), &module, false);
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expect(contains(run.stderr, "error[R_LIST_BOUNDS]: native execution failed (length 0)"));
    try std.testing.expect(contains(run.stderr, "MYLANG-TRAP {\"version\":1,\"operation\":\"pop\",\"length\":0}"));
}

// spec-case: NEW-CORE-IR-4
test "the textual IR spells compound types and the new operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try recordsProgram(arena.allocator());
    const text = try print.module(arena.allocator(), &module);
    try std.testing.expect(contains(text, "= record_make record{i64, bool, i32} 7:i64, 1:bool, 5:i32"));
    try std.testing.expect(contains(text, "= record_set record{i64, bool, i32} %"));
    try std.testing.expect(contains(text, ", field2, 9:i32"));
    try std.testing.expect(contains(text, "= list_get_field.exact i32 %"));
    try std.testing.expect(contains(text, ", path 1.2"));
    try std.testing.expect(contains(text, "  err_trace append"));
    try std.testing.expect(contains(text, "= list_pop.exact list[record{i64, bool, i32}] %"));
}
