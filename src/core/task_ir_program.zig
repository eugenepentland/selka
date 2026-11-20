//! TASK-SCHEDULER-1: construct task programs without changing the front end.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const builder = @import("test_builder.zig");
const Hand = support.Hand;
const Error = support.Error;

fn call(h: *Hand, target: u32, args: []const ir.Ref) Error!ir.Ref {
    return h.emit(.{ .op = .call, .ty = h.module.functions.items[target].signature.ret, .a = @fromBackingInt(target), .data = try h.extra(args), .span = 100 });
}
fn field(h: *Hand, value: ir.Ref, index: u64, ty: ir.Type) Error!ir.Ref {
    return h.emit(.{ .op = .record_get, .ty = ty, .a = value, .data = index });
}
fn list(h: *Hand, ty: ir.Type, items: []const ir.Ref) Error!ir.Ref {
    var result = try h.emit(.{ .op = .list_new, .ty = ty, .a = try h.int(.u64, @intCast(items.len)) });
    for (items) |item| result = try h.emit(.{ .op = .list_push, .ty = ty, .a = result, .b = item });
    return result;
}
fn get(h: *Hand, value: ir.Ref, index: i64, ty: ir.Type) Error!ir.Ref {
    return h.emit(.{ .op = .list_get, .ty = ty, .a = value, .b = try h.int(.i64, index), .check = .exact });
}
fn length(h: *Hand, value: ir.Ref) Error!ir.Ref {
    return h.emit(.{ .op = .list_len, .ty = .u64, .a = value });
}
/// A moved task environment fails in its worker, preserving the submission PC.
pub fn trapped(a: std.mem.Allocator) Error!ir.Module {
    var m: ir.Module = .{};
    const box = try m.intern(a, .{ .box = .i64 });
    const thunk = try m.intern(a, .{ .@"fn" = .{ .params = try a.dupe(ir.Type, &.{box}), .ret = box } });
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, box);
    const submit = try builder.helper(a, &m, "myl_core_owned_task_submit", &.{ box, thunk, box, .i64 }, .void);
    m.functions.items[submit].signature.passing.owned = 4;
    const end = try builder.helper(a, &m, "myl_core_owned_group_end", &.{box}, .void);
    m.functions.items[end].signature.passing.owned = 1;
    var worker = try Hand.init(a, &m, "trapped_task", m.compound(thunk).@"fn");
    const divisor = try worker.emit(.{ .op = .box_get, .ty = .i64, .a = try worker.param(0) });
    const failed = try worker.emit(.{ .op = .div, .ty = .i64, .a = try worker.int(.i64, 1), .b = divisor, .check = .exact, .span = 200 });
    const result = try worker.emit(.{ .op = .box_make, .ty = box, .a = failed });
    _ = try worker.emit(.{ .op = .ret, .ty = .void, .a = result });
    const function = try worker.finish();
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const group = try call(&h, open, &.{});
    const run = try h.loose(.{ .op = .func_ref, .ty = thunk, .data = function });
    const env = try h.emit(.{ .op = .box_make, .ty = box, .a = try h.int(.i64, 0) });
    _ = try call(&h, submit, &.{ group, run, env, try h.int(.i64, -1) });
    _ = try call(&h, end, &.{group});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

const RangeShape = struct { items: ir.Type, capture: ir.Type, env: ir.Type, result: ir.Type, handle: ir.Type, thunk: ir.Type };
fn rangeShape(a: std.mem.Allocator, m: *ir.Module) Error!RangeShape {
    const items = try m.intern(a, .{ .list = .i64 });
    const capture = try m.intern(a, .{ .record = try a.dupe(ir.Type, &.{ items, .i64, .i64, .i64 }) });
    const env = try m.intern(a, .{ .box = capture });
    const result = try m.intern(a, .{ .box = items });
    return .{ .items = items, .capture = capture, .env = env, .result = result, .handle = try m.intern(a, .{ .box = .i64 }), .thunk = try m.intern(a, .{ .@"fn" = .{ .params = try a.dupe(ir.Type, &.{env}), .ret = result } }) };
}
fn rangeBody(a: std.mem.Allocator, m: *ir.Module, s: RangeShape, fail: bool) Error!u32 {
    const mark = try builder.helper(a, m, "myl_core_task_item", &.{.i64}, .void);
    var h = try Hand.init(a, m, "map_range", m.compound(s.thunk).@"fn");
    const capture = try h.emit(.{ .op = .box_get, .ty = s.capture, .a = try h.param(0) });
    const items = try field(&h, capture, 0, s.items);
    const context = try field(&h, capture, 1, .i64);
    const start = try field(&h, capture, 2, .i64);
    const end = try field(&h, capture, 3, .i64);
    const empty = try list(&h, s.items, &.{});
    const header = try h.newBlock();
    const body = try h.newBlock();
    const done = try h.newBlock();
    try h.jump(header);
    h.block = header;
    const cursor = try h.emit(.{ .op = .phi, .ty = .i64 });
    const output = try h.emit(.{ .op = .phi, .ty = s.items });
    const more = try h.emit(.{ .op = .cmp, .ty = .bool, .a = cursor, .b = end, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(more, body, done);
    h.block = body;
    _ = try call(&h, mark, &.{cursor});
    if (fail) {
        const denominator = try h.emit(.{ .op = .sub, .ty = .i64, .a = cursor, .b = try h.int(.i64, 17), .check = .exact });
        _ = try h.emit(.{ .op = .div, .ty = .i64, .a = try h.int(.i64, 1), .b = denominator, .check = .exact, .span = 200 });
    }
    const item = try h.emit(.{ .op = .list_get, .ty = .i64, .a = items, .b = cursor, .check = .exact });
    const mapped = try h.emit(.{ .op = .add, .ty = .i64, .a = item, .b = context, .check = .exact });
    const pushed = try h.emit(.{ .op = .list_push, .ty = s.items, .a = output, .b = mapped });
    const next = try h.emit(.{ .op = .add, .ty = .i64, .a = cursor, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(header);
    h.function.insts.items[cursor.index()].data = try h.extra(&.{ start, next });
    h.function.insts.items[output.index()].data = try h.extra(&.{ empty, pushed });
    h.block = done;
    const boxed = try h.emit(.{ .op = .box_make, .ty = s.result, .a = output });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = boxed });
    return h.finish();
}
/// A generated range thunk loops over its independently owned items, borrows context,
/// returns a fresh chunk list and the parent gathers results in input order.
pub fn mapRanges(a: std.mem.Allocator) Error!ir.Module {
    return rangeProgram(a, false);
}
/// A map fails on item 17, beyond its range's first item at one/two threads.
pub fn mapTrapped(a: std.mem.Allocator) Error!ir.Module {
    return rangeProgram(a, true);
}
fn rangeProgram(a: std.mem.Allocator, fail: bool) Error!ir.Module {
    var m: ir.Module = .{};
    const s = try rangeShape(a, &m);
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, s.handle);
    const submit = try builder.helper(a, &m, "myl_core_owned_task_submit", &.{ s.handle, s.thunk, s.env, .i64 }, .void);
    m.functions.items[submit].signature.passing.owned = 4;
    const result = try builder.helper(a, &m, "myl_core_owned_group_take", &.{ s.handle, .i64 }, s.result);
    const close = try builder.helper(a, &m, "myl_core_owned_group_end", &.{s.handle}, .void);
    m.functions.items[close].signature.passing.owned = 1;
    const chunks = try builder.helper(a, &m, "myl_core_map_chunks", &.{.i64}, .i64);
    const thunk = try rangeBody(a, &m, s, fail);
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    var refs: [32]ir.Ref = undefined;
    for (&refs, 0..) |*value, i| value.* = try h.int(.i64, @intCast(i));
    const items = try list(&h, s.items, &refs);
    const group = try call(&h, open, &.{});
    const run = try h.loose(.{ .op = .func_ref, .ty = s.thunk, .data = thunk });
    const k = try call(&h, chunks, &.{try h.int(.i64, 32)});
    const header = try h.newBlock();
    const body = try h.newBlock();
    const gather = try h.newBlock();
    try h.jump(header);
    h.block = header;
    const cursor = try h.emit(.{ .op = .phi, .ty = .i64 });
    const more = try h.emit(.{ .op = .cmp, .ty = .bool, .a = cursor, .b = k, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(more, body, gather);
    h.block = body;
    const next = try h.emit(.{ .op = .add, .ty = .i64, .a = cursor, .b = try h.int(.i64, 1), .check = .exact });
    const left = try h.emit(.{ .op = .mul, .ty = .i64, .a = cursor, .b = try h.int(.i64, 32), .check = .exact });
    const right = try h.emit(.{ .op = .mul, .ty = .i64, .a = next, .b = try h.int(.i64, 32), .check = .exact });
    const start = try h.emit(.{ .op = .div, .ty = .i64, .a = left, .b = k, .check = .exact });
    const end = try h.emit(.{ .op = .div, .ty = .i64, .a = right, .b = k, .check = .exact });
    const copied = try h.emit(.{ .op = .list_copy, .ty = s.items, .a = items });
    const record = try h.emit(.{ .op = .record_make, .ty = s.capture, .data = try h.extra(&.{ copied, try h.int(.i64, 100), start, end }) });
    const env = try h.emit(.{ .op = .box_make, .ty = s.env, .a = record });
    _ = try call(&h, submit, &.{ group, run, env, start });
    try h.jump(header);
    h.function.insts.items[cursor.index()].data = try h.extra(&.{ try h.int(.i64, 0), next });
    h.block = gather;
    const outer = try h.newBlock();
    const enter = try h.newBlock();
    const inner = try h.newBlock();
    const emit = try h.newBlock();
    const advance = try h.newBlock();
    const done = try h.newBlock();
    try h.jump(outer);
    h.block = outer;
    const which = try h.emit(.{ .op = .phi, .ty = .i64 });
    const has_task = try h.emit(.{ .op = .cmp, .ty = .bool, .a = which, .b = k, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(has_task, enter, done);
    h.block = enter;
    const boxed = try call(&h, result, &.{ group, which });
    const chunk = try h.emit(.{ .op = .box_get, .ty = s.items, .a = boxed });
    const count = try h.emit(.{ .op = .convert, .ty = .i64, .a = try length(&h, chunk), .check = .exact });
    try h.jump(inner);
    h.block = inner;
    const offset = try h.emit(.{ .op = .phi, .ty = .i64 });
    const has_item = try h.emit(.{ .op = .cmp, .ty = .bool, .a = offset, .b = count, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(has_item, emit, advance);
    h.block = emit;
    const item = try h.emit(.{ .op = .list_get, .ty = .i64, .a = chunk, .b = offset, .check = .exact });
    try h.printValues(try h.param(0), &.{item});
    const following = try h.emit(.{ .op = .add, .ty = .i64, .a = offset, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(inner);
    h.function.insts.items[offset.index()].data = try h.extra(&.{ try h.int(.i64, 0), following });
    h.block = advance;
    const after = try h.emit(.{ .op = .add, .ty = .i64, .a = which, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(outer);
    h.function.insts.items[which.index()].data = try h.extra(&.{ try h.int(.i64, 0), after });
    h.block = done;
    _ = try call(&h, close, &.{group});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}
