//! The ownership rules of lent task arguments (E1b), on hand-built IR. Rule B: a lent box (`flags.lent_box`) borrows its
//! operand, so the lender keeps and drops it. Rule A: a group join reads the values that lent boxes hold, so their drops
//! follow the join. The lowering's end-to-end tests are in `task_group_lower_test.zig`.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const flags = @import("flags.zig");
const emit_llvm = @import("emit_llvm.zig");
const support = @import("test_support.zig");
const builder = @import("test_builder.zig");

const Hand = support.Hand;

fn noLocation(_: *const anyopaque, _: u32) emit_llvm.Location {
    return .{ .line = 1, .column = 1 };
}

/// A fresh `list[int]` holding one element.
fn oneElement(h: *Hand, ty: ir.Type) !ir.Ref {
    const list = try h.emit(.{ .op = .list_new, .ty = ty, .a = try h.int(.i64, 1) });
    return h.emit(.{ .op = .list_push, .ty = ty, .a = list, .b = try h.int(.i64, 1) });
}

/// `main` makes a list, boxes it (lent or consuming), then drops the box.
fn boxProgram(a: std.mem.Allocator, lent: bool) !ir.Module {
    var m: ir.Module = .{};
    const list_type = try m.intern(a, .{ .list = .i64 });
    const box_type = try m.intern(a, .{ .box = list_type });
    const group_type = try m.intern(a, .{ .box = .i64 });
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, group_type);
    const end = try builder.helper(a, &m, "myl_core_owned_group_end", &.{group_type}, .void);
    m.functions.items[end].signature.passing.owned = 1;
    var h = try Hand.init(a, &m, "main", .{ .params = &.{}, .ret = .i64 });
    // A lent box names its group, which must join (rule A fails closed without one), so the program opens and joins one.
    const group = try h.emit(.{ .op = .call, .ty = group_type, .a = @fromBackingInt(open), .data = try h.extra(&.{}) });
    const xs = try oneElement(&h, list_type);
    const boxed = try h.emit(.{ .op = .box_make, .ty = box_type, .a = xs, .b = if (lent) group else .none, .data = if (lent) flags.lent_box else 0 });
    _ = try h.emit(.{ .op = .drop, .ty = .void, .a = boxed });
    _ = try h.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(end), .data = try h.extra(&.{group}) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

/// `main` opens a group, boxes a list as a lent box, drops the box, and joins the group. Without rule A the list dies
/// at its box, before the join; with it the list's drop follows the join.
fn joinProgram(a: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    const list_type = try m.intern(a, .{ .list = .i64 });
    const box_type = try m.intern(a, .{ .box = list_type });
    const group_type = try m.intern(a, .{ .box = .i64 });
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, group_type);
    const end = try builder.helper(a, &m, "myl_core_owned_group_end", &.{group_type}, .void);
    m.functions.items[end].signature.passing.owned = 1;
    var h = try Hand.init(a, &m, "main", .{ .params = &.{}, .ret = .i64 });
    const group = try h.emit(.{ .op = .call, .ty = group_type, .a = @fromBackingInt(open), .data = try h.extra(&.{}) });
    const xs = try oneElement(&h, list_type);
    const boxed = try h.emit(.{ .op = .box_make, .ty = box_type, .a = xs, .b = group, .data = flags.lent_box });
    _ = try h.emit(.{ .op = .drop, .ty = .void, .a = boxed });
    _ = try h.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(end), .data = try h.extra(&.{group}) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

/// Run the ownership pass on `module` and emit its LLVM text.
fn emitOwned(arena: std.mem.Allocator, module: *ir.Module) ![]const u8 {
    try support.verified(arena, module, &.{});
    _ = try own.run(arena, module, .{});
    try support.verified(arena, module, &.{});
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = noLocation }, .source_path = "task.selka", .main = .{} });
}

/// The number of calls to `callee` in `text`.
fn callsOf(text: []const u8, callee: []const u8) usize {
    var needle_buffer: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buffer, "call void @{s}(", .{callee}) catch return 0;
    return std.mem.count(u8, text, needle);
}

test "task groups: a lent box borrows its operand, so the lender drops it and the box drops only its shell" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lent = try boxProgram(a, true);
    const lent_text = try emitOwned(a, &lent);
    // The list's own drop, and the box's drop: two drops.
    try std.testing.expectEqual(@as(usize, 2), callsOf(lent_text, "myl_core_drop_inline"));
    var consuming = try boxProgram(a, false);
    const consuming_text = try emitOwned(a, &consuming);
    // A plain box takes the list over: one drop of the box, which releases the list through its layout.
    try std.testing.expectEqual(@as(usize, 1), callsOf(consuming_text, "myl_core_drop_inline"));
}

test "task groups: a group join runs before the drop of a value a lent box holds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try joinProgram(a);
    const text = try emitOwned(a, &module);
    const join = std.mem.indexOf(u8, text, "call void @myl_core_owned_group_end(") orelse return error.TestUnexpectedResult;
    // Before the join: only the lent box's own drop. After it: the list's drop, which the join keeps alive.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text[0..join], "call void @myl_core_drop_inline("));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text[join..], "call void @myl_core_drop_inline("));
}

/// `main` lends a call result that can borrow any of three owned texts. Every
/// declared source must outlive the task join, including sources beyond two.
fn borrowedPickProgram(a: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    const borrowed_text = try m.borrowedType(a, .str);
    const box_type = try m.intern(a, .{ .box = .str });
    const group_type = try m.intern(a, .{ .box = .i64 });
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, group_type);
    const end = try builder.helper(a, &m, "myl_core_owned_group_end", &.{group_type}, .void);
    m.functions.items[end].signature.passing.owned = 1;
    const make = try builder.helper(a, &m, "make_text", &.{}, .str);
    const pick = try builder.helper(a, &m, "pick", &.{ .str, .str, .str }, borrowed_text);
    m.functions.items[pick].signature.borrow = .{ .sources = &.{ .{ .argument = 0 }, .{ .argument = 1 }, .{ .argument = 2 } } };
    var h = try Hand.init(a, &m, "main", .{ .params = &.{}, .ret = .i64 });
    const group = try h.emit(.{ .op = .call, .ty = group_type, .a = @fromBackingInt(open), .data = try h.extra(&.{}) });
    const first = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(make), .data = try h.extra(&.{}) });
    const second = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(make), .data = try h.extra(&.{}) });
    const third = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(make), .data = try h.extra(&.{}) });
    const picked = try h.emit(.{ .op = .call, .ty = borrowed_text, .a = @fromBackingInt(pick), .data = try h.extra(&.{ first, second, third }) });
    const storage = try h.emit(.{ .op = .borrow, .ty = .str, .a = picked });
    const boxed = try h.emit(.{ .op = .box_make, .ty = box_type, .a = storage, .b = group, .data = flags.lent_box });
    _ = try h.emit(.{ .op = .drop, .ty = .void, .a = boxed });
    _ = try h.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(end), .data = try h.extra(&.{group}) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

test "O3 task groups: a value that borrows three owned texts keeps every source alive until the join" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try borrowedPickProgram(a);
    const text = try emitOwned(a, &module);
    const join = std.mem.indexOf(u8, text, "call void @myl_core_owned_group_end(") orelse return error.TestUnexpectedResult;
    // Before the join: only the lent box shell. After it: all three source texts.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text[0..join], "call void @myl_core_drop_inline("));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, text[join..], "call void @myl_core_drop_inline("));
}

test "task groups: a lent box whose group has no join is refused, not scheduled" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const list_type = try m.intern(a, .{ .list = .i64 });
    const box_type = try m.intern(a, .{ .box = list_type });
    const group_type = try m.intern(a, .{ .box = .i64 });
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, group_type);
    var h = try Hand.init(a, &m, "main", .{ .params = &.{}, .ret = .i64 });
    const group = try h.emit(.{ .op = .call, .ty = group_type, .a = @fromBackingInt(open), .data = try h.extra(&.{}) });
    const xs = try oneElement(&h, list_type);
    const boxed = try h.emit(.{ .op = .box_make, .ty = box_type, .a = xs, .b = group, .data = flags.lent_box });
    _ = try h.emit(.{ .op = .drop, .ty = .void, .a = boxed });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    try support.verified(a, &m, &.{});
    try std.testing.expectError(error.Unsupported, own.run(a, &m, .{}));
}
